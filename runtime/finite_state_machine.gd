@tool
@icon("res://addons/state_machine/icons/finite_state_machine.svg")
class_name FiniteStateMachine
extends Node

## Owns a local graph of State children and evaluates authored transitions.
## Assign actor and initial_state before entering the tree. State names are matched
## case-insensitively within this machine. Runtime starts automatically on ready.
## Priority wins; equal priorities preserve authored transition order.
## See res://examples/basic.tscn in the development project.

const RUNTIME_SCRIPT := preload("res://addons/state_machine/runtime/transition_runtime.gd")
const PROPERTY := preload("res://addons/state_machine/runtime/property_comparison.gd")
const CONDITION_LOGIC := preload("res://addons/state_machine/runtime/condition_expression.gd")
const DEBUG_TRANSPORT := preload("res://addons/state_machine/runtime/debugger_transport.gd")
const DECISION_TRACE := preload("res://addons/state_machine/runtime/decision_trace.gd")
const INPUT_ACTIONS := preload("res://addons/state_machine/runtime/input_action_catalog.gd")
const POLICIES := preload("res://addons/state_machine/runtime/transition_policies.gd")
const EFFECTS := preload("res://addons/state_machine/runtime/transition_effects.gd")
var _decision_trace

func _begin_decision(request: String):
	if not DEBUG_TRANSPORT.tracing(self): return null
	var trace := DECISION_TRACE.new()
	trace.previous = _decision_trace
	trace.request = request
	trace.state_elapsed = get_current_state_elapsed()
	_decision_trace = trace
	return trace

func _end_decision(trace, success: bool) -> void:
	if trace == null: return
	_decision_trace = trace.previous
	DEBUG_TRANSPORT.decision(_debug_id, trace.finish(success))

func _debug_block(route, reason: String) -> bool:
	if _decision_trace != null: _decision_trace.blocked(self, route, reason)
	return false

func _debug_trigger(route, matched: bool, details: Dictionary = {}) -> bool:
	if _decision_trace != null: _decision_trace.trigger(self, route, matched, details)
	return matched

## Emitted when authored data changes; editor views schedule updates from this signal.
signal editor_data_changed

enum NestedEntryMode { RESET, RESUME }


@export_category("References")

## Gameplay Node used for condition/effect paths and inherited by nested FSMs.
@export var actor: Node:
	get:
		return _assigned_actor if Engine.is_editor_hint() else get_effective_actor()
	set(value):
		_assigned_actor = value
		if _runtime != null:
			_refresh_actor_bindings({})

		if Engine.is_editor_hint():
			update_configuration_warnings()

@export_category("State Machine")

## Direct child State entered on activation unless a valid hierarchy ENTRY wins.
@export var initial_state: State:
	set(value):
		initial_state = value
		if is_instance_valid(state_container) and state_container.get("initial_state") != value:
			state_container.set("initial_state", value)

		if Engine.is_editor_hint():
			update_configuration_warnings()
			editor_data_changed.emit()


## When true, explicit changes require an eligible authored Manual route.
@export var use_visual_transition_rules: bool = false

@export_group("Hierarchy")
@export var inherit_actor: bool = true
@export var nested_entry_mode: NestedEntryMode = NestedEntryMode.RESET

@export_group("Debug")

@export var print_transitions: bool = false


@export_storage var graph_positions: Dictionary = {}

## Authored routes in stable tie-breaking order. Replace the array to invalidate
## bindings after structural edits; individual Resource setters emit changed.
@export_storage var transitions: Array[StateTransition] = []:
	set(value):
		transitions = value
		if _runtime != null: _runtime.invalidate()
		if Engine.is_editor_hint(): editor_data_changed.emit()

# Authored debugger configuration. Runtime values are never stored here.
@export_storage var debugger_watches: Array[Resource] = []:
	set(value):
		debugger_watches = value
		if Engine.is_editor_hint():
			editor_data_changed.emit()

# Retained for scenes saved before resource-based transitions.
@export_storage var transition_rules: Array[Dictionary] = []


var current_state: State
var previous_state: State
var _state_elapsed := 0.0
var _policy_state_elapsed := 0.0
var _policy_clock := 0.0
var _cooldown_deadlines: Dictionary = {}
var _state_generation := 0
var _executing_transition := false
var _state_exit_started := false
var states: Dictionary = {}
var _runtime = RUNTIME_SCRIPT.new()
var _debug_id := ""
var owner_state: State
var parent_fsm: FiniteStateMachine
var previous_active_path := ""
var _assigned_actor: Node
var _active := false
var _initialized := false
var _resume_state: State
var state_container: Node
var _requesting_exit := false
var _boundary_warning_emitted := false
var _resolving_entry := false
var _deactivating := false
var _evaluating_conditions := false
var _registered_states: Array[State] = []
var _boundary_transition: StateTransition
var _boundary_failed := false

func _refresh_actor_bindings(visited: Dictionary) -> void:
	if visited.has(self): return
	visited[self] = true
	_runtime.invalidate()
	if Engine.is_editor_hint(): return
	for state in get_state_container().get_children():
		if state is State and is_instance_valid(state.nested_fsm) and state.nested_fsm.inherit_actor:
			state.nested_fsm._refresh_actor_bindings(visited)

func has_hierarchy_boundary() -> bool:
	return get_parent() is State and get_parent().has_method("get_nested_machine") and get_parent_fsm() != null

func has_valid_entry_route() -> bool:
	var names := {}
	for state in get_state_container().get_children():
		if state is State: names[_make_state_key(state.name)] = true
	for route in transitions:
		if route == null or not route.enabled or route.source_mode != StateTransition.SourceMode.HIERARCHY_ENTRY: continue
		if route.target_mode == StateTransition.TargetMode.DIRECT and route.destination_mode == StateTransition.DestinationMode.STATE and names.has(_make_state_key(route.to_state)): return true
		if route.target_mode != StateTransition.TargetMode.RANDOM or route.random_routing == null or not route.random_routing.configuration_error().is_empty(): continue
		var valid := true
		for branch in route.random_routing.branches:
			if not names.has(_make_state_key(branch.target_state)): valid = false; break
		if valid: return true
	return false

func resolve_entry() -> Dictionary:
	var chosen: StateTransition
	if has_hierarchy_boundary():
		for transition in transitions:
			if _decision_trace != null and transition != null and transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY:
				var item: Dictionary = _decision_trace.candidate(self, transition)
				if not item.is_empty(): item.trigger = {"status": "NOT_APPLICABLE"}; item.policies = {"status": "NOT_APPLICABLE"}
				if not transition.enabled: _decision_trace.blocked(self, transition, "DISABLED")
			if transition == null or not transition.enabled or transition.source_mode != StateTransition.SourceMode.HIERARCHY_ENTRY or transition.destination_mode != StateTransition.DestinationMode.STATE: continue
			if transition.target_mode == StateTransition.TargetMode.RANDOM:
				if not _random_targets_valid(transition, true): continue
			elif not owns_state(get_state(transition.to_state)): continue
			if not _conditions_pass(transition): continue
			if chosen == null or transition.priority > chosen.priority: chosen = transition
	if _decision_trace != null: _decision_trace.select(self, chosen)
	if chosen != null and chosen.target_mode == StateTransition.TargetMode.RANDOM:
		var choice := _choose_random_target(chosen)
		return {"state": get_state(StringName(choice.selected_target)) if not choice.is_empty() else null, "route": chosen}
	return {"state": get_state(chosen.to_state) if chosen != null else (initial_state if owns_state(initial_state) else null), "route": chosen}


func get_state_container() -> Node:
	return state_container if is_instance_valid(state_container) else self


func owns_state(state: State) -> bool:
	if not is_instance_valid(state) or state.get_parent() != get_state_container():
		return false
	# Authoring can inspect children before registration. Runtime activation must
	# use the exact registered identity, not an excluded case-insensitive duplicate.
	return Engine.is_editor_hint() or not _initialized or states.get(_make_state_key(state.name)) == state


static func machine_for_state(state: State) -> FiniteStateMachine:
	var parent := state.get_parent()
	if parent is FiniteStateMachine:
		return parent
	return parent.get_nested_machine() if parent != null and parent.has_method("get_nested_machine") else null


static func nested_machine_for_state(state: State) -> FiniteStateMachine:
	if state.has_method("get_nested_machine"):
		return state.get_nested_machine()
	var found: FiniteStateMachine
	for child in state.get_children():
		if child is FiniteStateMachine:
			if found != null:
				return null
			found = child
	return found


func _enter_tree() -> void:
	if Engine.is_editor_hint() and not ProjectSettings.settings_changed.is_connected(_editor_input_settings_changed):
		ProjectSettings.settings_changed.connect(_editor_input_settings_changed)
	if not Engine.is_editor_hint():
		var container := get_state_container()
		if not container.child_entered_tree.is_connected(_state_child_entered): container.child_entered_tree.connect(_state_child_entered)

func _state_child_entered(node: Node) -> void:
	if _initialized and node is State: _register_states()

func _editor_input_settings_changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree(): return
	update_configuration_warnings()
	var container := get_state_container()
	if container != self: container.update_configuration_warnings()

func _ready() -> void:
	if Engine.is_editor_hint():
		migrate_legacy_transitions()
		update_configuration_warnings()
		return
	owner_state = get_parent() as State
	parent_fsm = machine_for_state(owner_state) if owner_state != null else null
	if owner_state != null:
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	_initialize_hierarchy({})
	activate()


func get_parent_fsm() -> FiniteStateMachine:
	if not Engine.is_editor_hint():
		return parent_fsm
	var state := get_parent() as State
	return machine_for_state(state) if state != null else null


## Returns the assigned gameplay Actor or the inherited parent Actor for a nested FSM.
func get_effective_actor() -> Node:
	var cursor: FiniteStateMachine = self
	var visited := {}
	while is_instance_valid(cursor) and not visited.has(cursor):
		visited[cursor] = true
		var parent := cursor.get_parent_fsm()
		if not cursor.inherit_actor or parent == null:
			return cursor._assigned_actor
		cursor = parent
	return null


func _initialize_hierarchy(visited: Dictionary) -> void:
	if visited.has(self):
		return
	visited[self] = true
	owner_state = get_parent() as State
	parent_fsm = machine_for_state(owner_state) if owner_state != null else null
	migrate_legacy_transitions()
	_register_states()
	_initialized = true
	_debug_id = DEBUG_TRANSPORT.register_fsm(self)
	for state: State in states.values():
		if state.nested_fsm != null:
			state.nested_fsm._initialize_hierarchy(visited)


## Returns the current activation flag; does not perform a new hierarchy validation.
func is_active() -> bool:
	return _active


func _valid_hierarchy() -> bool:
	var cursor: FiniteStateMachine = self
	var visited := {}
	while is_instance_valid(cursor):
		if visited.has(cursor):
			return false
		visited[cursor] = true
		if cursor.owner_state != null:
			if cursor.get_parent() != cursor.owner_state or cursor.parent_fsm == null or not cursor.parent_fsm.owns_state(cursor.owner_state) or cursor.owner_state.nested_fsm != cursor:
				return false
		elif cursor.parent_fsm != null:
			return false
		cursor = cursor.parent_fsm
	return true


## Activates a valid machine inside the SceneTree. Root FSMs call this on ready;
## nested FSMs are activated by their owning State. Requires Actor and valid entry.
func activate() -> void:
	var trace = _begin_decision("Activation / ENTRY")
	_activate_evaluated()
	if is_instance_valid(self): _end_decision(trace, trace.outcome if trace != null else false)

func _activate_evaluated() -> void:
	if Engine.is_editor_hint() or _active or _resolving_entry or _deactivating or _executing_transition or not _initialized or not _valid_hierarchy():
		return
	if owner_state != null and (parent_fsm == null or not parent_fsm.is_active() or parent_fsm.current_state != owner_state):
		return

	current_state = null
	migrate_legacy_transitions()
	if not is_instance_valid(actor):
		push_error("FiniteStateMachine '%s': No Actor assigned." % name)
		return

	var has_state_child := false
	for child in get_state_container().get_children():
		if child is State:
			has_state_child = true
			break
	if not has_state_child:
		push_error("FiniteStateMachine '%s': No State children." % name)
		return
	_register_states()
	var resumed := owner_state != null and nested_entry_mode == NestedEntryMode.RESUME and owns_state(_resume_state)
	_resolving_entry = true
	var entry: Dictionary = {"state": _resume_state, "route": null} if resumed else resolve_entry()
	_resolving_entry = false
	if not is_inside_tree() or not _valid_hierarchy() or owner_state != null and (not parent_fsm.is_active() or parent_fsm.current_state != owner_state): return
	if not resumed and entry.state == null and not is_instance_valid(initial_state):
		push_error("FiniteStateMachine '%s': No Initial State assigned." % name)
		return
	if not resumed and entry.state == null and not owns_state(initial_state):
		push_error("FiniteStateMachine '%s': Initial State must be a direct State child." % name)
		return

	_register_states()
	current_state = _resume_state if resumed else entry.state
	if _decision_trace != null: _decision_trace.outcome = true
	_state_exit_started = false
	_active = true
	_state_elapsed = 0.0
	if not resumed:
		_policy_state_elapsed = 0.0
		_policy_clock = 0.0
		_cooldown_deadlines.clear()
	_state_generation += 1
	_runtime.setup(self)
	_boundary_warning_emitted = false
	if not resumed and entry.route != null: DEBUG_TRANSPORT.transitioned(_debug_id, "ENTRY", entry.route)
	_enter_current()
	DEBUG_TRANSPORT.hierarchy_changed(self)


func _enter_current() -> void:
	var entered := current_state
	var generation := _state_generation
	if not _transition_context_valid(generation, entered): return
	entered.enter()
	if is_instance_valid(self) and _transition_context_valid(generation, entered) and is_instance_valid(entered.nested_fsm):
		entered.nested_fsm.activate()


## Leaves the active State and releases runtime Resource/signal bindings.
## Nested RESUME mode retains the resumable State; this does not free authored Nodes.
func deactivate() -> void:
	if not _active:
		return
	_deactivating = true
	_boundary_failed = false
	var outgoing := current_state
	var completed := _execute_boundary_actions(TransitionAction.Timing.BEFORE_EXIT, outgoing)
	_active = false
	_state_generation += 1
	_resume_state = outgoing
	if is_instance_valid(outgoing):
		if completed and is_instance_valid(outgoing.nested_fsm):
			outgoing.nested_fsm.deactivate()
			completed = not outgoing.nested_fsm._boundary_failed if is_instance_valid(outgoing.nested_fsm) else false
		if completed and is_instance_valid(self) and is_instance_valid(outgoing) and not outgoing.is_queued_for_deletion() and not _state_exit_started:
			_state_exit_started = true
			outgoing.exit()
		if completed and is_instance_valid(self): completed = _execute_boundary_actions(TransitionAction.Timing.AFTER_EXIT, outgoing)
	if not is_instance_valid(self): return
	_boundary_failed = not completed
	_runtime.stop()
	_state_elapsed = 0.0
	if owner_state == null or nested_entry_mode != NestedEntryMode.RESUME:
		_policy_state_elapsed = 0.0
		_policy_clock = 0.0
		_cooldown_deadlines.clear()
	current_state = null
	_deactivating = false
	DEBUG_TRANSPORT.hierarchy_changed(self)

func _execute_boundary_actions(timing: int, source: State) -> bool:
	if _boundary_transition == null: return true
	var context := parent_fsm
	while is_instance_valid(context) and not context.is_active(): context = context.parent_fsm
	if not is_instance_valid(context): return false
	var was_executing := _executing_transition
	_executing_transition = true
	var completed := _execute_actions(_boundary_transition, timing, source, source, context)
	if is_instance_valid(self): _executing_transition = was_executing
	return completed

## Sends an event to the active parent FSM, returning whether it committed.
func bubble_event(event_name: StringName) -> bool:
	return parent_fsm.send_event(event_name) if _active and is_instance_valid(parent_fsm) and parent_fsm.is_active() else false


## Returns the active hierarchy path, such as Movement/Walk; empty if inactive.
func get_active_state_path() -> String:
	var cursor: FiniteStateMachine = self
	var visited := {}
	var names := PackedStringArray()
	while is_instance_valid(cursor) and cursor._active and is_instance_valid(cursor.current_state) and not visited.has(cursor):
		visited[cursor] = true
		names.append(String(cursor.current_state.name))
		cursor = cursor.current_state.nested_fsm
	return "/".join(names)


func _remember_active_paths() -> void:
	var cursor: FiniteStateMachine = self
	var visited := {}
	while is_instance_valid(cursor) and not visited.has(cursor):
		visited[cursor] = true
		cursor.previous_active_path = cursor.get_active_state_path()
		cursor = cursor.parent_fsm


func _unhandled_input(event: InputEvent) -> void:
	if parent_fsm == null:
		_route_input(event)


func _route_input(event: InputEvent) -> void:
	if not _active or not is_instance_valid(current_state):
		return
	var generation := _state_generation
	current_state.handle_input(event)
	var nested := _active_nested()
	if generation == _state_generation and nested != null:
		nested._route_input(event)


func _active_nested() -> FiniteStateMachine:
	if not _active or not is_instance_valid(current_state):
		return null
	var nested := current_state.nested_fsm
	if not is_instance_valid(nested) or nested == self or nested.parent_fsm != self or nested.owner_state != current_state:
		return null
	return nested if nested._active else null


func _process(delta: float) -> void:
	if parent_fsm == null:
		_tick(delta)


func _tick(delta: float) -> void:
	if not _active or not is_instance_valid(current_state):
		return
	if not _debug_id.is_empty():
		DEBUG_TRANSPORT.sample_watches(_debug_id, delta)
		DEBUG_TRANSPORT.sample_state(_debug_id, delta)

	var generation := _state_generation
	_advance_policy_clocks(delta)
	_runtime.advance_any_timers(delta)
	current_state.update(delta)
	if generation == _state_generation and is_instance_valid(current_state):
		_advance_timers(delta, false)
	var nested := _active_nested()
	if generation == _state_generation and nested != null:
		nested._tick(delta)


func _physics_process(delta: float) -> void:
	if parent_fsm == null:
		_tick_physics(delta)


func _tick_physics(delta: float) -> void:
	if not _active or not is_instance_valid(current_state):
		return

	var generation := _state_generation
	current_state.physics_update(delta)
	var nested := _active_nested()
	if generation == _state_generation and nested != null:
		nested._tick_physics(delta)


## Requests an explicit transition by local State name. Policies and authored
## Manual rules still apply; inspect get_current_state_name() for the result.
func change_state(new_state_name: StringName) -> void:
	if not is_instance_valid(current_state):
		return

	_transition_to(
		current_state,
		new_state_name
	)


## Returns the current local State name, or an empty StringName if inactive.
func get_current_state_name() -> StringName:
	if not is_instance_valid(current_state):
		return &""

	return StringName(current_state.name)


## Looks up a direct State by case-insensitive name. Returns null if missing.
func get_state(state_name: StringName) -> State:
	var key := _make_state_key(state_name)
	var state = states.get(key)
	if not is_instance_valid(state):
		return null
	return state as State if state is State and state.get_parent() == get_state_container() and _make_state_key(state.name) == key else null


func has_state(state_name: StringName) -> bool:
	return get_state(state_name) != null


func is_transition_allowed(
	from_state: StringName,
	to_state: StringName
) -> bool:
	return _resolve_manual_transition(from_state, to_state) != null


func _resolve_manual_transition(from_state: StringName, to_state: StringName, check_policy := true) -> StateTransition:
	if _runtime.machine == self and _active: _runtime.ensure()
	migrate_legacy_transitions()
	var chosen: StateTransition
	for transition in transitions:
		if transition != null and transition.target_mode == StateTransition.TargetMode.RANDOM and to_state == &"@random":
			if _eligible_transition(transition, StateTransition.TriggerType.MANUAL) and (chosen == null or transition.priority > chosen.priority): chosen = transition
			continue
		if _decision_trace != null and transition != null and transition.trigger_type == StateTransition.TriggerType.MANUAL and transition.matches_source(from_state) and transition.to_state == to_state:
			_decision_trace.candidate(self, transition)
			if not transition.enabled: _decision_trace.blocked(self, transition, "DISABLED")
			else: _debug_trigger(transition, true, {"request": String(to_state)})
		if transition == null or transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY or transition.destination_mode != StateTransition.DestinationMode.STATE or not transition.enabled or transition.trigger_type != StateTransition.TriggerType.MANUAL:
			continue
		if transition.source_mode == StateTransition.SourceMode.ANY_STATE and (not owns_state(get_state(from_state)) or _make_state_key(from_state) == _make_state_key(to_state)):
			continue
		if (
			transition.matches_source(from_state)
			and _make_state_key(transition.to_state) == _make_state_key(to_state)
		) and _conditions_pass(transition) and (not check_policy or not _active or _policy_allows(transition)):
			if chosen == null or transition.priority > chosen.priority: chosen = transition
	return chosen


func migrate_legacy_transitions() -> bool:
	var migrated := _migrate_development_hierarchy_exits()
	for index in range(transition_rules.size() - 1, -1, -1):
		var rule := transition_rules[index]
		# Unknown data stays serialized for explicit conversion later.
		if not _can_migrate_legacy_rule(rule):
			continue
		var transition := StateTransition.new()
		transition.from_state = StringName(rule["from"])
		transition.to_state = StringName(rule["to"])
		transitions.push_front(transition)
		transition_rules.remove_at(index)
		migrated = true
	return migrated

func _migrate_development_hierarchy_exits() -> bool:
	# Serialized provisional trigger ID 6 is retired, never a runtime trigger.
	# Ambiguous Resources are archived on the serializable State container.
	var groups := {}
	for route in transitions:
		if route == null or int(route.trigger_type) != 6: continue
		var key := String(route.from_state).to_lower()
		if not groups.has(key): groups[key] = []
		groups[key].append(route)
	if groups.is_empty(): return false
	var container := get_state_container()
	var archived: Array = container.get_meta(&"fsm_legacy_hierarchy_exit_data", []).duplicate()
	for key in groups:
		var owner: HierarchyState
		for child in container.get_children():
			if child is HierarchyState and String(child.name).to_lower() == key: owner = child
		var routes: Array = groups[key]
		var route: StateTransition = routes[0]
		var simple := routes.size() == 1 and owner != null and route.source_mode == StateTransition.SourceMode.STATE and route.enabled and route.priority == 0 and route.conditions.is_empty() and route.condition_group == null and route.actions.is_empty() and route.cooldown == 0.0 and not route.can_interrupt and route.target_mode == StateTransition.TargetMode.DIRECT and not route.target_key().is_empty()
		var valid_target := route.target_key() == StateTransition.EXIT_TARGET and has_hierarchy_boundary()
		for child in container.get_children():
			if child is State and String(child.name).nocasecmp_to(String(route.target_key())) == 0: valid_target = true
		# A self-route may carry old no-reentry semantics; never guess its intent.
		simple = simple and valid_target and route.destination_mode in StateTransition.DestinationMode.values() and (String(route.target_key()).nocasecmp_to(String(route.from_state)) != 0 or route.reenter_state)
		if simple and (owner.exit_target.is_empty() or owner.exit_target == route.target_key()):
			owner.exit_target = route.target_key()
		else:
			for legacy in routes:
				if not legacy in archived: archived.append(legacy)
	var retained: Array[StateTransition] = []
	for route in transitions:
		if route == null or int(route.trigger_type) != 6: retained.append(route)
	if not archived.is_empty(): container.set_meta(&"fsm_legacy_hierarchy_exit_data", archived)
	transitions = retained
	return true


func _can_migrate_legacy_rule(rule: Dictionary) -> bool:
	if rule.size() != 2 or not rule.has("from") or not rule.has("to"):
		return false
	return (
		(rule["from"] is String or rule["from"] is StringName)
		and (rule["to"] is String or rule["to"] is StringName)
	)


func _register_states() -> void:
	for state in _registered_states.duplicate():
		if not is_instance_valid(state) or state.get_parent() != get_state_container(): _unregister_state(state)
	states.clear()

	for child in get_state_container().get_children():
		if not child is State:
			continue

		var state := child as State
		if state.is_queued_for_deletion(): continue
		var key := _make_state_key(state.name)
		if states.has(key):
			push_warning(
				"FiniteStateMachine '%s': Duplicate State '%s'."
				% [name, state.name]
			)
			continue

		state.actor = actor
		state.machine = self
		state.nested_fsm = nested_machine_for_state(state)
		states[key] = state
		if not state in _registered_states:
			_registered_states.append(state)
			state.tree_exiting.connect(_unregister_state.bind(state))
			state.renamed.connect(_register_states)

		if not state.transitioned.is_connected(
			_on_state_transitioned
		):
			state.transitioned.connect(
				_on_state_transitioned
			)
	for state in _registered_states.duplicate():
		if not state in states.values(): _unregister_state(state)
	_runtime.invalidate()

func _unregister_state(state) -> void:
	_registered_states.erase(state)
	if not is_instance_valid(state): return
	if state.transitioned.is_connected(_on_state_transitioned): state.transitioned.disconnect(_on_state_transitioned)
	if state.tree_exiting.is_connected(_unregister_state.bind(state)): state.tree_exiting.disconnect(_unregister_state.bind(state))
	if state.renamed.is_connected(_register_states): state.renamed.disconnect(_register_states)
	for key in states.keys():
		if states[key] == state: states.erase(key)
	if current_state == state:
		deactivate()
		current_state = null
	if previous_state == state: previous_state = null
	if _resume_state == state: _resume_state = null
	if state.machine == self:
		state.machine = null
		state.actor = null
	_runtime.invalidate()

func _on_state_transitioned(
	state: State,
	new_state_name: StringName
) -> void:
	_transition_to(
		state,
		new_state_name
	)


func _transition_to(state: State, new_state_name: StringName) -> void:
	var trace = _begin_decision("Manual: " + String(new_state_name))
	var success := _transition_to_evaluated(state, new_state_name)
	if is_instance_valid(self): _end_decision(trace, success)

func _transition_to_evaluated(state: State, new_state_name: StringName) -> bool:
	if _evaluating_conditions: return _debug_block(null, "EVALUATION_REENTRANCY")
	if not _active or not is_instance_valid(current_state) or state != current_state:
		return false
	if new_state_name == &"@hierarchy_exit" and has_hierarchy_boundary():
		return request_exit()
	var manual: StateTransition
	if use_visual_transition_rules:
		manual = _resolve_manual_transition(current_state.name, new_state_name)
		if manual == null:
			if _resolve_manual_transition(current_state.name, new_state_name, false) != null: return false
			push_warning("No enabled Manual transition: %s -> %s" % [current_state.name, new_state_name])
			return false
		if manual.target_mode == StateTransition.TargetMode.RANDOM:
			if _decision_trace != null: _decision_trace.select(self, manual)
			return _execute_transition(manual)
	var destination := get_state(new_state_name)
	if not is_instance_valid(destination):
		push_warning("FiniteStateMachine '%s': State not found: %s" % [name, new_state_name])
		return false
	return _execute_state_change(destination, manual)


## Evaluates eligible Event routes for the active local State. Returns true only
## when a transition commits; an unmatched or blocked event returns false.
func send_event(event_name: StringName) -> bool:
	var trace = _begin_decision("Event: " + String(event_name))
	var success := _send_event_evaluated(event_name)
	if is_instance_valid(self): _end_decision(trace, success)
	return success

func _send_event_evaluated(event_name: StringName) -> bool:
	if _evaluating_conditions: return _debug_block(null, "EVALUATION_REENTRANCY")
	if not _active or Engine.is_editor_hint() or not is_inside_tree() or not is_instance_valid(current_state) or event_name.is_empty():
		return false
	_runtime.ensure()
	var chosen: StateTransition
	for transition in _runtime.active:
		if not _eligible_transition(transition, StateTransition.TriggerType.EVENT, false):
			continue
		if not _debug_trigger(transition, transition.event_name == event_name, {"event": String(event_name), "expected_event": String(transition.event_name)} if _decision_trace != null else {}) or not _conditions_pass(transition):
			continue
		if chosen == null or transition.priority > chosen.priority:
			chosen = transition
	if _decision_trace != null: _decision_trace.select(self, chosen)
	return _execute_transition(chosen) if chosen != null else false


func _advance_policy_clocks(delta: float) -> void:
	POLICIES.advance(self, delta)


func _advance_timers(delta: float, advance_policy := true) -> void:
	if not _active or Engine.is_editor_hint() or not is_inside_tree() or not is_instance_valid(current_state): return
	if advance_policy: _advance_policy_clocks(delta)
	_state_elapsed += maxf(delta, 0.0) if is_finite(delta) else 0.0
	_runtime.evaluate_frame(_state_elapsed)


func get_current_state_elapsed() -> float:
	return _policy_state_elapsed


func get_transition_cooldown_remaining(transition: StateTransition) -> float:
	return POLICIES.remaining(self, transition)


func _policy_allows(transition: StateTransition = null) -> bool:
	return POLICIES.allows(self, transition)


func _commit_policy(transition: StateTransition) -> void:
	POLICIES.commit(self, transition)


func _eligible_transition(transition: StateTransition, trigger: StateTransition.TriggerType, check_conditions := true) -> bool:
	if _decision_trace != null and transition != null and transition.trigger_type == trigger: _decision_trace.candidate(self, transition)
	if not _active or not owns_state(current_state):
		return _debug_block(transition, "FSM_INACTIVE")
	if transition == null or transition.trigger_type != trigger: return false
	if not transition.enabled: return _debug_block(transition, "DISABLED")
	if transition.target_mode == StateTransition.TargetMode.DIRECT and transition.destination_mode == StateTransition.DestinationMode.STATE and transition.to_state.is_empty(): return _debug_block(transition, "INVALID_TARGET")
	if transition.target_mode not in [StateTransition.TargetMode.DIRECT, StateTransition.TargetMode.RANDOM]: return _debug_block(transition, "INVALID_TARGET")
	if not _policy_allows(transition): return false
	if transition.destination_mode not in [StateTransition.DestinationMode.STATE, StateTransition.DestinationMode.EXIT]: return _debug_block(transition, "INVALID_TARGET")
	if not transition.matches_source(current_state.name):
		return _debug_block(transition, "INVALID_SOURCE")
	if trigger not in StateTransition.TriggerType.values(): return _debug_block(transition, "INVALID_TRIGGER")
	if transition.target_mode == StateTransition.TargetMode.RANDOM:
		if not _random_targets_valid(transition): return _debug_block(transition, "INVALID_TARGET")
		return not check_conditions or _conditions_pass(transition)
	if transition.destination_mode == StateTransition.DestinationMode.EXIT:
		if not has_hierarchy_boundary(): return _debug_block(transition, "INVALID_TARGET")
		return not check_conditions or _conditions_pass(transition)
	var destination := get_state(transition.to_state)
	if transition.source_mode == StateTransition.SourceMode.ANY_STATE and destination == current_state:
		return _debug_block(transition, "INVALID_TARGET")
	if not owns_state(destination): return _debug_block(transition, "INVALID_TARGET")
	return not check_conditions or _conditions_pass(transition)


func _execute_transition(transition: StateTransition) -> bool:
	if transition == null or not transition in transitions or not is_instance_valid(current_state):
		return false
	if not _eligible_transition(transition, transition.trigger_type):
		return false
	if transition.target_mode == StateTransition.TargetMode.RANDOM:
		if _executing_transition or _requesting_exit: return _debug_block(transition, "TRANSITION_EXECUTING")
		var choice := _choose_random_target(transition)
		if choice.is_empty(): return _debug_block(transition, "INVALID_TARGET")
		var target := StringName(choice.selected_target)
		return _request_hierarchy_exit(transition) if target == StateTransition.EXIT_TARGET else _execute_state_change(get_state(target), transition)
	if transition.destination_mode == StateTransition.DestinationMode.EXIT: return _request_hierarchy_exit(transition)
	return _execute_state_change(get_state(transition.to_state), transition)

var routing_rng := RandomNumberGenerator.new()
var _routing_rng_initialized := false

func _random_targets_valid(transition: StateTransition, entry := false) -> bool:
	var routing := transition.random_routing
	if routing == null or not routing.configuration_error().is_empty(): return false
	for branch in routing.branches:
		if branch.target_state == StateTransition.EXIT_TARGET:
			if entry or not has_hierarchy_boundary(): return false
			continue
		var target := get_state(branch.target_state)
		if not owns_state(target): return false
		if transition.source_mode == StateTransition.SourceMode.ANY_STATE and target == current_state: return false
	return true

func _choose_random_target(transition: StateTransition) -> Dictionary:
	if not _routing_rng_initialized:
		routing_rng.randomize()
		_routing_rng_initialized = true
	var choice := transition.random_routing.select(minf(routing_rng.randf(), 0.999999999999))
	if _decision_trace != null and not choice.is_empty():
		var item: Dictionary = _decision_trace.candidate(self, transition)
		if not item.is_empty():
			var observation := choice.duplicate()
			observation.branch_count = choice.branches.size()
			observation.truncated = choice.branches.size() > 128
			observation.branches = choice.branches.slice(0, 128)
			item.routing = observation
			item.order.append("RANDOM_SELECTED")
			item.to = "EXIT" if choice.selected_target == String(StateTransition.EXIT_TARGET) else choice.selected_target
	return choice

# Instance-scoped deterministic hook; production randomizes on its first roll.
func set_routing_seed(value: int) -> void:
	routing_rng.seed = value
	_routing_rng_initialized = true

## Requests the current hierarchy boundary exit. Returns false for a root FSM
## or a blocked/invalid continuation; the active State is then preserved.
func request_exit() -> bool:
	var trace = _begin_decision("Manual EXIT")
	var success := _request_exit_evaluated()
	if is_instance_valid(self): _end_decision(trace, success)
	return success

func _request_exit_evaluated() -> bool:
	if _evaluating_conditions: return _debug_block(null, "EVALUATION_REENTRANCY")
	if not _active or not owns_state(current_state): return false
	var chosen: StateTransition
	for transition in transitions:
		if transition == null or transition.destination_mode != StateTransition.DestinationMode.EXIT or not _eligible_transition(transition, StateTransition.TriggerType.MANUAL): continue
		if chosen == null or transition.priority > chosen.priority: chosen = transition
	if _decision_trace != null: _decision_trace.select(self, chosen)
	return _execute_transition(chosen) if chosen != null else false

func _request_hierarchy_exit(transition: StateTransition) -> bool:
	if _requesting_exit or _executing_transition: return _debug_block(transition, "TRANSITION_EXECUTING")
	if not _active: return _debug_block(transition, "FSM_INACTIVE")
	if not has_hierarchy_boundary() or not _valid_hierarchy(): return _debug_block(transition, "INVALID_TARGET")
	var parent := parent_fsm
	if not is_instance_valid(parent) or not parent.is_active() or parent.current_state != owner_state or parent._executing_transition: return false
	var hierarchy := owner_state as HierarchyState
	if hierarchy == null: return false
	var target := hierarchy.exit_target
	var destination: State = parent.get_state(target) if target != StateTransition.EXIT_TARGET else null
	if target.is_empty() or target != StateTransition.EXIT_TARGET and not parent.owns_state(destination) or target == StateTransition.EXIT_TARGET and not parent.has_hierarchy_boundary():
		_debug_block(transition, "NO_EXIT_DESTINATION")
		if not _boundary_warning_emitted and OS.is_debug_build():
			push_warning("%s has no valid exit destination; internal State remains active." % hierarchy.name)
			_boundary_warning_emitted = true
		return false
	_requesting_exit = true
	_boundary_transition = transition
	_boundary_failed = false
	var source := current_state
	var from := String(current_state.name)
	# No parent trigger, condition, priority, cooldown or policy evaluation.
	var success := parent._request_hierarchy_exit(null) if target == StateTransition.EXIT_TARGET else parent._execute_state_change(destination, null, true)
	if not is_instance_valid(self): return false
	_boundary_transition = null
	if success: _commit_policy(transition)
	if not is_instance_valid(source) or source.is_queued_for_deletion():
		_requesting_exit = false
		return false
	if success:
		# EXIT actions belong to the now-inactive child, but their surviving
		# execution context is the active ancestor that accepted the boundary.
		var context := parent
		while is_instance_valid(context) and not context.is_active(): context = context.parent_fsm
		if not is_instance_valid(context):
			_requesting_exit = false
			return false
		_executing_transition = true
		context._executing_transition = true
		success = _execute_actions(transition, TransitionAction.Timing.AFTER_ENTER, source, source, context)
		if is_instance_valid(context): context._executing_transition = false
		if not is_instance_valid(self): return false
		_executing_transition = false
		DEBUG_TRANSPORT.transitioned(_debug_id, from, transition, "EXIT")
	_requesting_exit = false
	return success


func _transition_context_valid(generation: int, expected, destination = null) -> bool:
	var cursor: Node = self
	while is_instance_valid(cursor):
		if cursor.is_queued_for_deletion(): return false
		cursor = cursor.get_parent()
	var effective_actor := get_effective_actor()
	if is_instance_valid(effective_actor) and effective_actor.is_queued_for_deletion(): return false
	if not _active or not is_inside_tree() or generation != _state_generation or current_state != expected: return false
	if not is_instance_valid(expected) or expected.is_queued_for_deletion() or not expected.is_inside_tree() or not owns_state(expected): return false
	if typeof(destination) != TYPE_NIL and (not is_instance_valid(destination) or destination.is_queued_for_deletion() or not destination.is_inside_tree() or not owns_state(destination)): return false
	return true


func _execute_state_change(destination: State, transition: StateTransition = null, direct_hierarchy_exit := false) -> bool:
	if _decision_trace != null:
		var item: Dictionary = _decision_trace.candidate(self, transition)
		if not item.is_empty():
			if transition == null and is_instance_valid(destination): item.to = String(destination.name)
			_decision_trace.select(self, transition)
			if transition == null: item.selected = true; item.trigger = {"status": "PASSED", "request": item.to}
	var generation := _state_generation
	if _executing_transition: return _debug_block(transition, "TRANSITION_EXECUTING")
	if not _transition_context_valid(generation, current_state, destination): return _debug_block(transition, "COMMIT_INTERRUPTED")
	if not direct_hierarchy_exit and not _policy_allows(transition): return false
	var outgoing := current_state
	_runtime.evaluating_signal = false
	var debug_from := String(outgoing.name) if not _debug_id.is_empty() else ""
	var self_transition := destination == current_state
	_executing_transition = true
	if self_transition and transition != null and not transition.reenter_state:
		for timing in [TransitionAction.Timing.BEFORE_EXIT, TransitionAction.Timing.AFTER_EXIT, TransitionAction.Timing.AFTER_ENTER]:
			if not _execute_actions(transition, timing, outgoing, destination):
				if is_instance_valid(self): _executing_transition = false
				return false
		_executing_transition = false
		_commit_policy(transition)
		_runtime.transition_fired(transition)
		_runtime.invalidate()
		DEBUG_TRANSPORT.transitioned(_debug_id, String(current_state.name), transition)
		DEBUG_TRANSPORT.hierarchy_changed(self)
		return true
	if print_transitions:
		print("[FSM] ", current_state.name, " -> ", destination.name)
	_remember_active_paths()
	if not _execute_actions(transition, TransitionAction.Timing.BEFORE_EXIT, outgoing, destination):
		if is_instance_valid(self): _executing_transition = false
		return false
	if is_instance_valid(outgoing.nested_fsm):
		outgoing.nested_fsm.deactivate()
		if not is_instance_valid(self): return false
		if not is_instance_valid(outgoing.nested_fsm) or outgoing.nested_fsm._boundary_failed:
			_executing_transition = false
			return _debug_block(transition, "COMMIT_INTERRUPTED")
	if not is_instance_valid(self): return false
	if not _transition_context_valid(generation, outgoing, destination):
		_executing_transition = false
		return false
	_state_exit_started = true
	if _decision_trace != null:
		var item: Dictionary = _decision_trace.candidate(self, transition)
		if not item.is_empty(): item.order.append("EXIT")
	outgoing.exit()
	if not is_instance_valid(self): return false
	if not _transition_context_valid(generation, outgoing, destination):
		_executing_transition = false
		return false
	if not _execute_actions(transition, TransitionAction.Timing.AFTER_EXIT, outgoing, destination):
		if is_instance_valid(self): _executing_transition = false
		return false
	previous_state = outgoing if is_instance_valid(outgoing) else null
	current_state = destination
	_state_exit_started = false
	_state_elapsed = 0.0
	_policy_state_elapsed = 0.0
	_state_generation += 1
	generation = _state_generation
	_commit_policy(transition)
	_runtime.transition_fired(transition)
	_runtime.invalidate()
	_runtime.ensure()
	_executing_transition = false
	DEBUG_TRANSPORT.transitioned(_debug_id, debug_from, transition, "", "Exit destination" if direct_hierarchy_exit else "")
	if _decision_trace != null:
		var item: Dictionary = _decision_trace.candidate(self, transition)
		if not item.is_empty(): item.order.append("ENTER")
	_enter_current()
	if not is_instance_valid(self): return false
	if not _transition_context_valid(generation, destination): return false
	if not is_instance_valid(outgoing) or outgoing.is_queued_for_deletion() or not owns_state(outgoing): return false
	# enter() deliberately permits another transition; only the surviving context
	# may run its AFTER_ENTER actions. Actions themselves remain non-reentrant.
	_executing_transition = true
	var completed := _execute_actions(transition, TransitionAction.Timing.AFTER_ENTER, outgoing, destination)
	if not is_instance_valid(self): return false
	_executing_transition = false
	DEBUG_TRANSPORT.hierarchy_changed(self)
	return completed


func _execute_actions(transition: StateTransition, timing: int, source: State, destination: State, context = null) -> bool:
	var machine: FiniteStateMachine = self if context == null else context
	var generation := machine._state_generation
	var expected := machine.current_state
	var checked_destination = destination if machine == self else null
	if not machine._transition_context_valid(generation, expected, checked_destination): return false
	if transition == null:
		return true
	for action in transition.actions.duplicate():
		var typed_action := action as TransitionAction
		if typed_action == null or not typed_action.enabled or typed_action.timing != timing:
			continue
		var trace = _decision_trace
		var item: Dictionary = trace.candidate(self, transition) if trace != null else {}
		var detail := {"type": int(typed_action.action_type), "timing": timing, "property": String(typed_action.property_path),
			"method": String(typed_action.method_name), "signal": String(typed_action.signal_name), "value": preload("res://addons/state_machine/runtime/decision_data.gd").value(typed_action.value)} if trace != null else {}
		var result := _execute_action(typed_action, source, destination)
		if not item.is_empty() and item.effects.size() < 128:
			detail.executed = bool(result.ok)
			detail.message = String(result.message).left(256)
			item.effects.append(detail)
			item.order.append(["BEFORE_EXIT", "AFTER_EXIT", "AFTER_ENTER"][timing])
		if not result.ok and OS.is_debug_build():
			push_warning("Transition Action skipped: " + result.message)
		if not is_instance_valid(self): return false
		if not is_instance_valid(source) or source.is_queued_for_deletion() or not owns_state(source): return false
		if not is_instance_valid(destination) or destination.is_queued_for_deletion(): return false
		if not is_instance_valid(machine) or not machine._transition_context_valid(generation, expected, checked_destination): return false
	return true


func _execute_action(action: TransitionAction, source: State, destination: State) -> Dictionary:
	return EFFECTS.execute(self, action, source, destination)


func _exit_tree() -> void:
	var container := get_state_container()
	if container.child_entered_tree.is_connected(_state_child_entered): container.child_entered_tree.disconnect(_state_child_entered)
	for state in _registered_states.duplicate(): _unregister_state(state)
	if ProjectSettings.settings_changed.is_connected(_editor_input_settings_changed):
		ProjectSettings.settings_changed.disconnect(_editor_input_settings_changed)
	_active = false
	DEBUG_TRANSPORT.removed(_debug_id)
	_debug_id = ""
	_runtime.stop()
	_state_elapsed = 0.0
	_state_generation += 1
	current_state = null


func _conditions_pass(transition: StateTransition) -> bool:
	if _evaluating_conditions: return _debug_block(transition, "EVALUATION_REENTRANCY")
	_evaluating_conditions = true
	var observation := {"status": "SKIPPED"} if _decision_trace != null else {}
	var budget: Array = _decision_trace.condition_budget if _decision_trace != null else []
	var passed: bool
	if _runtime.machine == self and _active:
		passed = _runtime.conditions_pass(transition, observation, budget)
	else: passed = CONDITION_LOGIC.evaluate(actor, CONDITION_LOGIC.compile(transition), observation, budget)
	if not is_instance_valid(self): return false
	_evaluating_conditions = false
	if _decision_trace != null:
		var item: Dictionary = _decision_trace.candidate(self, transition)
		if not item.is_empty(): item.conditions = observation
		if not passed: _decision_trace.blocked(self, transition, "CONDITION_FAILED")
	return passed


## Returns authoring diagnostics without executing the transition.
func transition_warnings(transition: StateTransition) -> PackedStringArray:
	var warnings := PackedStringArray()
	var effective_actor := get_effective_actor()
	if transition == null:
		return warnings
	if transition.target_mode == StateTransition.TargetMode.DIRECT and transition.destination_mode == StateTransition.DestinationMode.STATE and transition.to_state.is_empty():
		warnings.append("Transition has no target State.")
	if not transition.enabled: return warnings
	if transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY:
		warnings.append_array(CONDITION_LOGIC.warnings(effective_actor, transition))
		return warnings
	match transition.trigger_type:
		StateTransition.TriggerType.INPUT_ACTION:
			if not INPUT_ACTIONS.has_action(transition.input_action):
				warnings.append("Input action '%s' is not defined in InputMap." % transition.input_action)
		StateTransition.TriggerType.ANIMATION_FINISHED:
			var player := effective_actor.get_node_or_null(transition.animation_player_path) as AnimationPlayer if is_instance_valid(effective_actor) and not transition.animation_player_path.is_empty() and not transition.animation_player_path.is_absolute() else null
			if player == null:
				warnings.append("AnimationPlayer path must identify an AnimationPlayer relative to Actor.")
			elif not player.has_animation(transition.animation_name):
				warnings.append("Animation '%s' is missing from the AnimationPlayer." % transition.animation_name)
		StateTransition.TriggerType.PROPERTY_WATCH:
			var message: String = PROPERTY.warning(effective_actor, transition.watch)
			if not message.is_empty():
				warnings.append("Property Watch: " + message)
	warnings.append_array(CONDITION_LOGIC.warnings(effective_actor, transition))
	return warnings


func _make_state_key(
	state_name: StringName
) -> StringName:
	return StringName(
		String(state_name).to_lower()
	)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if get_state_container().has_meta(&"fsm_legacy_hierarchy_exit_data"):
		warnings.append("Ambiguous legacy hierarchy-exit data preserved; manual migration is required.")
	var parent := get_parent_fsm()
	if not Engine.is_editor_hint() and _initialized and not _valid_hierarchy():
		warnings.append("Invalid hierarchy ownership or cycle detected.")
	if get_parent() is State and parent == null:
		warnings.append("Nested FSM owner State must be a direct child of a FiniteStateMachine.")
	if parent != null and inherit_actor and get_effective_actor() == null:
		warnings.append("Actor inheritance cannot resolve the parent Actor.")

	if get_effective_actor() == null:
		warnings.append(
			"FSM '%s': Actor is missing. Assign the gameplay Node to Actor in the Inspector." % name
		)

	var state_names: Dictionary = {}
	for child in get_state_container().get_children():
		if child is State:
			if child is HierarchyState:
				var exit_warning: String = child.exit_destination_warning()
				if not exit_warning.is_empty(): warnings.append(exit_warning)
			var nested_count := 0
			for node in child.get_children():
				if node is FiniteStateMachine:
					nested_count += 1
					var has_nested_state := false
					for nested_child in node.get_children():
						if nested_child is State:
							has_nested_state = true
					if not has_nested_state:
						warnings.append("Composite State '%s': nested FSM is empty." % child.name)
					if not is_instance_valid(node.initial_state) and not node.has_valid_entry_route():
						warnings.append("Composite State '%s': nested FSM needs an Initial State." % child.name)
			if nested_count > 1:
				warnings.append("Composite State '%s' may own exactly one nested FSM." % child.name)
			var key := _make_state_key(child.name)
			if state_names.has(key):
				warnings.append("Duplicate State name (case-insensitive): %s." % child.name)
			state_names[key] = true
	if state_names.is_empty():
		warnings.append("Add at least one child node with a script that extends State.")

	for transition in transitions:
		if transition == null:
			warnings.append("FSM '%s': A transition resource is missing. Replace or remove the empty entry in Transitions." % name)
			continue
		if transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY:
			if not has_hierarchy_boundary(): warnings.append("ENTRY routes require an owning HierarchyState.")
		elif transition.source_mode == StateTransition.SourceMode.STATE and not state_names.has(_make_state_key(transition.from_state)):
			warnings.append("Transition references missing From State: %s." % transition.from_state)
		if transition.target_mode == StateTransition.TargetMode.RANDOM:
			if transition.random_routing == null: warnings.append("Random routing is missing.")
			else:
				var routing_error := transition.random_routing.configuration_error()
				if not routing_error.is_empty(): warnings.append(routing_error)
				for branch in transition.random_routing.branches:
					if branch != null and not state_names.has(_make_state_key(branch.target_state)) and not (branch.target_state == StateTransition.EXIT_TARGET and has_hierarchy_boundary() and transition.source_mode != StateTransition.SourceMode.HIERARCHY_ENTRY): warnings.append("Random references missing or illegal target: %s." % branch.target_state)
		elif transition.destination_mode == StateTransition.DestinationMode.EXIT:
			if not has_hierarchy_boundary() or transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: warnings.append("EXIT destination requires a nested HierarchyState and cannot be used by ENTRY.")
		elif transition.to_state.is_empty(): warnings.append("Transition has no target State.")
		elif not state_names.has(_make_state_key(transition.to_state)): warnings.append("Transition references missing To State: %s." % transition.to_state)
		if transition.source_mode not in [StateTransition.SourceMode.STATE, StateTransition.SourceMode.ANY_STATE, StateTransition.SourceMode.HIERARCHY_ENTRY]:
			warnings.append("Transition has an invalid Source Mode.")
		for transition_warning in transition_warnings(transition):
			if not warnings.has(transition_warning): warnings.append(transition_warning)
		if transition.enabled:
			if transition.trigger_type == StateTransition.TriggerType.EVENT and transition.event_name.is_empty():
				warnings.append("Event transition requires a non-empty Event Name.")
			if transition.trigger_type == StateTransition.TriggerType.TIMER and (not is_finite(transition.duration) or transition.duration < 0.0):
				warnings.append("Timer transition requires a finite, non-negative Duration.")
	for rule in transition_rules:
		if _can_migrate_legacy_rule(rule):
			_append_endpoint_warnings(warnings, state_names, StringName(rule["from"]), StringName(rule["to"]))
		else:
			warnings.append("Unrecognized legacy transition data retained; explicit conversion is required.")

	var has_entry := has_valid_entry_route()
	if not is_instance_valid(initial_state) and not (has_hierarchy_boundary() and has_entry):
		warnings.append(
			"Assign one of the child States as Initial State."
		)
	elif is_instance_valid(initial_state) and not owns_state(initial_state):
		warnings.append(
			"Initial State must be a direct child of this FiniteStateMachine."
		)

	return warnings


func _append_endpoint_warnings(
	warnings: PackedStringArray,
	state_names: Dictionary,
	from_name: StringName,
	to_name: StringName,
	any_source := false
) -> void:
	if not any_source and not state_names.has(_make_state_key(from_name)):
		warnings.append("Transition references missing From State: %s." % from_name)
	if not state_names.has(_make_state_key(to_name)):
		warnings.append("Transition references missing To State: %s." % to_name)


func _notification(what: int) -> void:
	if (
		Engine.is_editor_hint()
		and
		what == NOTIFICATION_CHILD_ORDER_CHANGED
	):
		update_configuration_warnings()
