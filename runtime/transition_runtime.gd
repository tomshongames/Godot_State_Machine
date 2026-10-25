extends RefCounted

const PROPERTY := preload("res://addons/state_machine/runtime/property_comparison.gd")
const LOGIC := preload("res://addons/state_machine/runtime/condition_expression.gd")
const SIGNAL_TREE_EVENTS := [&"child_order_changed", &"tree_exiting"]
var machine: FiniteStateMachine
var active: Array[StateTransition] = []
var bound_transitions: Array[StateTransition] = []
var bound_resources: Array[Resource] = []
var resource_callbacks: Dictionary = {}
var condition_lists: Dictionary = {}
var players: Dictionary = {}
var state_key: StringName
var generation := -1
var dirty := true
var last_input_frame := -1
var condition_plans: Dictionary = {}
var group_lists: Dictionary = {}
var condition_build_count := 0
var any_timers: Dictionary = {}
var any_timer_signatures: Dictionary = {}
var signal_bindings: Dictionary = {}
var binding_actor: Node
var signal_connect_count := 0
var refreshing := false
var signal_watchers: Dictionary = {}
var signal_refresh_pending := false
var player_binding_revision := 0
var evaluating_signal := false

func _signal_tree_changed() -> void:
	if signal_refresh_pending: return
	signal_refresh_pending = true
	_refresh_signal_tree.call_deferred()

func _refresh_signal_tree() -> void:
	signal_refresh_pending = false
	if is_instance_valid(machine) and machine.is_active(): invalidate()

func _sync_signal_watchers() -> void:
	var wanted := {}
	for route in active:
		if route.trigger_type != StateTransition.TriggerType.SIGNAL or not route.enabled: continue
		var actor: Node = machine.actor
		if not is_instance_valid(actor): continue
		wanted[actor.get_instance_id()] = actor
		var path := ""
		for i in route.signal_source_path.get_name_count():
			path += ("/" if i > 0 else "") + String(route.signal_source_path.get_name(i))
			var node := actor.get_node_or_null(NodePath(path))
			if node != null: wanted[node.get_instance_id()] = node
	for id in signal_watchers.keys():
		if wanted.has(id): continue
		_disconnect_signal_watcher(signal_watchers[id])
		signal_watchers.erase(id)
	for id in wanted:
		if signal_watchers.has(id): continue
		var node: Node = wanted[id]
		signal_watchers[id] = weakref(node)
		for event in SIGNAL_TREE_EVENTS:
			if not node.is_connected(event, _signal_tree_changed): node.connect(event, _signal_tree_changed)

func _disconnect_signal_watcher(reference: WeakRef) -> void:
	var node: Node = reference.get_ref()
	if not is_instance_valid(node): return
	for event in SIGNAL_TREE_EVENTS:
		if node.is_connected(event, _signal_tree_changed): node.disconnect(event, _signal_tree_changed)

func signal_source(transition: StateTransition) -> Node:
	if transition.signal_source_mode == StateTransition.SignalSourceMode.NODE_PATH and transition.signal_source_path.get_subname_count() > 0: return null
	return PROPERTY.target(machine.actor, transition.signal_source_mode, transition.signal_source_path) if is_instance_valid(machine) else null

func _disconnect_signals() -> void:
	for entry in signal_bindings.values():
		var source = entry.source.get_ref()
		if is_instance_valid(source) and entry.owned and source.is_connected(entry.name, entry.callback): source.disconnect(entry.name, entry.callback)
	signal_bindings.clear()
	for reference in signal_watchers.values():
		_disconnect_signal_watcher(reference)
	signal_watchers.clear()

func _sync_signals() -> void:
	_sync_signal_watchers()
	var wanted := {}
	for route in active:
		if route.trigger_type != StateTransition.TriggerType.SIGNAL or not route.enabled or route.signal_name.is_empty(): continue
		var source := signal_source(route)
		if not is_instance_valid(source) or not source.is_inside_tree() or not source.has_signal(route.signal_name): continue
		var key := "%s:%s" % [source.get_instance_id(), route.signal_name]
		if wanted.has(key): continue
		var count := 0
		for spec in source.get_signal_list():
			if spec.name == route.signal_name: count = spec.args.size(); break
		var shared: bool = source is AnimationPlayer and route.signal_name == &"animation_finished" and players.has(source)
		wanted[key] = {"source": weakref(source), "name": route.signal_name, "owned": not shared, "count": count}
	for key in signal_bindings.keys():
		var entry: Dictionary = signal_bindings[key]
		if wanted.has(key) and entry.generation == generation and entry.owned == wanted[key].owned: continue
		var source = entry.source.get_ref()
		if is_instance_valid(source) and entry.owned and source.is_connected(entry.name, entry.callback): source.disconnect(entry.name, entry.callback)
		signal_bindings.erase(key)
	for key in wanted:
		if signal_bindings.has(key): continue
		var entry: Dictionary = wanted[key]
		entry.generation = generation
		entry.callback = _signal_emitted.bind(key, generation)
		if entry.count > 0: entry.callback = entry.callback.unbind(entry.count)
		signal_bindings[key] = entry
		var source = entry.source.get_ref()
		if entry.owned and not source.is_connected(entry.name, entry.callback):
			source.connect(entry.name, entry.callback)
			signal_connect_count += 1

func _signal_emitted(key: String, source_generation: int) -> void:
	if not is_instance_valid(machine) or not machine.is_active() or not machine.is_inside_tree() or source_generation != machine._state_generation or not signal_bindings.has(key): return
	var entry: Dictionary = signal_bindings[key]
	var source = entry.source.get_ref()
	if not is_instance_valid(source) or not source.is_inside_tree(): return
	var owner := machine
	ensure()
	if not signal_bindings.has(key) or source_generation != owner._state_generation: return
	var trace = owner._begin_decision("Signal: " + String(entry.name))
	if evaluating_signal:
		for route in active:
			if route.trigger_type == StateTransition.TriggerType.SIGNAL and route.signal_name == entry.name and signal_source(route) == source:
				owner._debug_trigger(route, true, {"signal": String(entry.name), "emitted": true} if trace != null else {})
				owner._debug_block(route, "EVALUATION_REENTRANCY")
		owner._end_decision(trace, false)
		return
	evaluating_signal = true
	var chosen: StateTransition
	for route in active.duplicate():
		if not is_instance_valid(owner) or not owner.is_active() or source_generation != owner._state_generation or not is_instance_valid(source) or not source.is_inside_tree(): break
		if route.trigger_type != StateTransition.TriggerType.SIGNAL or route.signal_name != entry.name or signal_source(route) != source: continue
		owner._debug_trigger(route, true, {"signal": String(entry.name), "source": String(source.get_path()), "emitted": true} if trace != null else {})
		if not owner._eligible_transition(route, StateTransition.TriggerType.SIGNAL, false) or not owner._conditions_pass(route): continue
		if not is_instance_valid(owner) or source_generation != owner._state_generation: break
		if route.trigger_type != StateTransition.TriggerType.SIGNAL or route.signal_name != entry.name or signal_source(route) != source:
			owner._debug_block(route, "INVALID_SOURCE")
			continue
		if chosen == null or route.priority > chosen.priority: chosen = route
	if is_instance_valid(owner):
		if trace != null: trace.select(owner, chosen)
		var success: bool = owner._execute_transition(chosen) if chosen != null and source_generation == owner._state_generation else false
		if is_instance_valid(owner): owner._end_decision(trace, success)
	evaluating_signal = false


func setup(value: FiniteStateMachine) -> void:
	machine = value
	ensure()


func invalidate() -> void:
	dirty = true
	if not refreshing and is_instance_valid(machine) and machine.is_active() and not Engine.is_editor_hint(): ensure()


func ensure() -> void:
	if not is_instance_valid(machine) or not machine.is_active() or Engine.is_editor_hint():
		return
	if refreshing: return
	refreshing = true
	if binding_actor != machine.actor:
		binding_actor = machine.actor
		dirty = true
	var key := machine._make_state_key(machine.current_state.name) if is_instance_valid(machine.current_state) else &""
	if bound_transitions != machine.transitions or key != state_key or generation != machine._state_generation:
		dirty = true
	for transition in active:
		if transition != null and condition_lists.get(transition) != transition.conditions:
			dirty = true
	for group in group_lists:
		if group.children != group_lists[group]: dirty = true
	var changed := dirty
	if dirty:
		_rebuild_active_resources(key)
	var player_revision := player_binding_revision
	_sync_players()
	if changed or player_revision != player_binding_revision: _sync_signals()
	refreshing = false


func _rebuild_active_resources(key: StringName) -> void:
	_unbind_resources()
	active.clear()
	condition_lists.clear()
	condition_plans.clear()
	group_lists.clear()
	bound_transitions = machine.transitions.duplicate()
	_sync_any_timers()
	state_key = key
	generation = machine._state_generation
	for transition in bound_transitions:
		if transition == null: continue
		_bind_resource(transition)
		_bind_resource(transition.random_routing)
		if transition.random_routing != null:
			for branch in transition.random_routing.branches: _bind_resource(branch)
		if not transition.matches_source(key): continue
		active.append(transition)
		condition_lists[transition] = transition.conditions.duplicate()
		_bind_resource(transition.watch)
		for action in transition.actions:
			_bind_resource(action)
		for condition in transition.conditions:
			_bind_resource(condition)
		var plan: Dictionary = LOGIC.compile(transition)
		condition_build_count += 1
		condition_plans[transition] = plan
		if not plan.valid:
			push_warning("FSM condition tree: " + plan.error)
		for resource in plan.resources:
			_bind_resource(resource)
			if resource is TransitionConditionGroup:
				group_lists[resource] = resource.children.duplicate()
	dirty = false


func _sync_any_timers() -> void:
	var wanted := {}
	for transition in bound_transitions:
		if transition == null or not transition.enabled or transition.source_mode != StateTransition.SourceMode.ANY_STATE or transition.trigger_type != StateTransition.TriggerType.TIMER:
			continue
		wanted[transition] = true
		_refresh_any_timer(transition)
	for transition in any_timers.keys():
		if not wanted.has(transition):
			any_timers.erase(transition)
			any_timer_signatures.erase(transition)


func _refresh_any_timer(transition: StateTransition) -> void:
	# Keep one definition of the authored fields that reset an Any State timer.
	var signature := [transition.source_mode, transition.trigger_type, transition.duration, transition.to_state, transition.enabled, transition.destination_mode]
	if not any_timer_signatures.has(transition) or any_timer_signatures[transition] != signature:
		any_timers[transition] = 0.0
		any_timer_signatures[transition] = signature


func advance_any_timers(delta: float) -> void:
	if any_timers.is_empty() and not dirty: return
	ensure()
	for transition in any_timers:
		any_timers[transition] += maxf(delta, 0.0)


func transition_fired(transition: StateTransition) -> void:
	if transition != null and any_timers.has(transition): any_timers[transition] = 0.0


func _resource_changed(reference: WeakRef) -> void:
	dirty = true
	if (not signal_bindings.is_empty() or reference.get_ref() is StateTransition and reference.get_ref().trigger_type == StateTransition.TriggerType.SIGNAL) and is_instance_valid(machine) and machine.is_active(): ensure()
	var resource: Resource = reference.get_ref()
	if not resource is StateTransition or not any_timer_signatures.has(resource): return
	if not resource.enabled or resource.source_mode != StateTransition.SourceMode.ANY_STATE or resource.trigger_type != StateTransition.TriggerType.TIMER:
		any_timers.erase(resource)
		any_timer_signatures.erase(resource)
		return
	_refresh_any_timer(resource)


func conditions_pass(transition: StateTransition, observation: Dictionary = {}, capture_budget: Array = []) -> bool:
	if dirty: ensure()
	var plan: Dictionary = condition_plans[transition] if condition_plans.has(transition) else LOGIC.compile(transition)
	return LOGIC.evaluate(machine.actor, plan, observation, capture_budget) if is_instance_valid(machine) else false


func _bind_resource(resource: Resource) -> void:
	if resource != null and not resource in bound_resources:
		bound_resources.append(resource)
		var callback := _resource_changed.bind(weakref(resource))
		resource_callbacks[resource] = callback
		resource.changed.connect(callback)


func _unbind_resources() -> void:
	for resource in bound_resources:
		var callback: Callable = resource_callbacks[resource]
		if resource.changed.is_connected(callback):
			resource.changed.disconnect(callback)
	bound_resources.clear()
	resource_callbacks.clear()


func evaluate_frame(elapsed: float) -> void:
	var owner := machine
	var trace = owner._begin_decision("Frame") if is_instance_valid(owner) else null
	var success := _evaluate_frame(elapsed)
	if is_instance_valid(owner): owner._end_decision(trace, success)

func _evaluate_frame(elapsed: float) -> bool:
	ensure()
	var input_frame := Engine.get_process_frames()
	var check_input := input_frame != last_input_frame
	last_input_frame = input_frame
	var chosen: StateTransition
	for transition in active:
		if transition.trigger_type not in [StateTransition.TriggerType.TIMER, StateTransition.TriggerType.INPUT_ACTION, StateTransition.TriggerType.PROPERTY_WATCH]:
			continue
		if not machine._eligible_transition(transition, transition.trigger_type, false):
			continue
		var eligible := false
		var details := {} 
		match transition.trigger_type:
			StateTransition.TriggerType.TIMER:
				var timer_elapsed: float = any_timers.get(transition, 0.0) if transition.source_mode == StateTransition.SourceMode.ANY_STATE else elapsed
				eligible = is_finite(transition.duration) and transition.duration >= 0 and timer_elapsed >= transition.duration
				if machine._decision_trace != null: details = {"required": transition.duration if is_finite(transition.duration) else -1.0, "elapsed": timer_elapsed}
			StateTransition.TriggerType.INPUT_ACTION:
				if check_input and InputMap.has_action(transition.input_action):
					match transition.input_mode:
						StateTransition.InputMode.PRESSED: eligible = Input.is_action_just_pressed(transition.input_action)
						StateTransition.InputMode.RELEASED: eligible = Input.is_action_just_released(transition.input_action)
						StateTransition.InputMode.HELD: eligible = Input.is_action_pressed(transition.input_action)
				if machine._decision_trace != null: details = {"action": String(transition.input_action), "mode": int(transition.input_mode), "sampled_this_frame": check_input}
			StateTransition.TriggerType.PROPERTY_WATCH:
				if machine._decision_trace != null: details = {"status": "SKIPPED"}
				eligible = PROPERTY.evaluate(machine.actor, transition.watch, details)
		machine._debug_trigger(transition, eligible, details)
		if eligible and machine._conditions_pass(transition) and (chosen == null or transition.priority > chosen.priority):
			chosen = transition
	if machine._decision_trace != null: machine._decision_trace.select(machine, chosen)
	return machine._execute_transition(chosen) if chosen != null else false


func animation_player(transition: StateTransition) -> AnimationPlayer:
	if not is_instance_valid(machine.actor) or transition.animation_player_path.is_empty() or transition.animation_player_path.is_absolute():
		return null
	return machine.actor.get_node_or_null(transition.animation_player_path) as AnimationPlayer


func _sync_players() -> void:
	var wanted: Dictionary = {}
	for transition in active:
		if transition.enabled and transition.trigger_type == StateTransition.TriggerType.ANIMATION_FINISHED:
			var player := animation_player(transition)
			if is_instance_valid(player) and player.has_animation(transition.animation_name):
				wanted[player] = true
	for player in players.keys():
		var data: Dictionary = players[player]
		if not is_instance_valid(player) or not wanted.has(player) or data.generation != generation:
			if is_instance_valid(player) and player.animation_finished.is_connected(data.callback):
				player.animation_finished.disconnect(data.callback)
			players.erase(player)
			player_binding_revision += 1
	for player in wanted:
		if not players.has(player):
			var callback := _animation_finished.bind(player, generation)
			players[player] = {"callback": callback, "generation": generation}
			player.animation_finished.connect(callback)
			player_binding_revision += 1


func _animation_finished(animation: StringName, player: AnimationPlayer, source_generation: int) -> void:
	if not is_instance_valid(machine) or not machine.is_active() or not machine.is_inside_tree() or source_generation != machine._state_generation:
		return
	ensure()
	var owner := machine
	var trace = owner._begin_decision("Animation: " + String(animation))
	var chosen: StateTransition
	for transition in active:
		var signal_route: bool = transition.trigger_type == StateTransition.TriggerType.SIGNAL and transition.signal_name == &"animation_finished" and signal_source(transition) == player
		if not signal_route and transition.trigger_type != StateTransition.TriggerType.ANIMATION_FINISHED: continue
		if not machine._eligible_transition(transition, transition.trigger_type, false):
			continue
		var details: Dictionary = {"signal": "animation_finished", "source": String(player.get_path()), "emitted": true} if signal_route else {"animation": String(animation)}
		if machine._debug_trigger(transition, signal_route or transition.animation_name == animation and animation_player(transition) == player, details if trace != null else {}) and machine._conditions_pass(transition) and (chosen == null or transition.priority > chosen.priority):
			chosen = transition
	if trace != null: trace.select(machine, chosen)
	var success: bool = machine._execute_transition(chosen) if chosen != null else false
	if is_instance_valid(owner): owner._end_decision(trace, success)


func stop() -> void:
	evaluating_signal = false
	_disconnect_signals()
	binding_actor = null
	for player in players:
		if is_instance_valid(player) and player.animation_finished.is_connected(players[player].callback):
			player.animation_finished.disconnect(players[player].callback)
	players.clear()
	_unbind_resources()
	active.clear()
	bound_transitions.clear()
	condition_lists.clear()
	condition_plans.clear()
	group_lists.clear()
	any_timers.clear()
	any_timer_signatures.clear()
	machine = null
