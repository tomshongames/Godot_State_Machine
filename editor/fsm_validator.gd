@tool
extends RefCounted

const INDEX := preload("res://addons/state_machine/editor/fsm_graph_index.gd")
const PROPERTY := preload("res://addons/state_machine/runtime/property_comparison.gd")
const CATALOG := preload("res://addons/state_machine/editor/property_catalog.gd")
const LOGIC := preload("res://addons/state_machine/runtime/condition_expression.gd")
const SNAPSHOT := preload("res://addons/state_machine/editor/transition_snapshot.gd")
const AUTHORING_COPY := preload("res://addons/state_machine/runtime/authoring_copy.gd")
enum Severity { ERROR, WARNING }
var issues: Array[Dictionary] = []
var seen := {}
var index
var runs := 0

func validate(machine: FiniteStateMachine, graph_index = null) -> Array[Dictionary]:
	index = graph_index if graph_index != null else INDEX.new()
	if graph_index == null: index.rebuild(machine)
	issues.clear()
	seen.clear()
	runs += 1
	for context in index.contexts: _context(context)
	_shared_resources()
	return issues.duplicate()

func _shared_resources() -> void:
	var owners := {}
	for context in index.contexts:
		var resources := {}
		AUTHORING_COPY.resources(context.fsm.transitions, resources)
		AUTHORING_COPY.resources(context.fsm.debugger_watches, resources)
		for resource in resources:
			if owners.has(resource):
				var previous: Dictionary = owners[resource]
				_issue(context, "SHARED_MUTABLE_FSM_RESOURCE", "%s and %s share mutable FSM data (%s)." % [previous.hierarchy_path, context.hierarchy_path, resource.get_script().resource_path.get_file()], Severity.ERROR, null, resource if resource is StateTransition else null, resource)
			else: owners[resource] = context

func _issue(context: Dictionary, code: String, message: String, severity := Severity.ERROR, state = null, route = null, resource = null, fix := "") -> void:
	var key := "%s/%s/%s/%s/%s" % [context.fsm.get_instance_id(), code, state.get_instance_id() if is_instance_valid(state) else 0, route.get_instance_id() if route != null else 0, resource.get_instance_id() if resource != null else 0]
	if seen.has(key): return
	seen[key] = true
	issues.append({"severity": severity, "code": code, "message": message, "fsm": context.fsm, "state": state, "transition": route, "resource": resource, "hierarchy_path": context.hierarchy_path, "optional_fix_id": fix})

func _context(c: Dictionary) -> void:
	var machine: FiniteStateMachine = c.fsm
	if machine.get_state_container().has_meta(&"fsm_legacy_hierarchy_exit_data"):
		_issue(c, "HIERARCHY_LEGACY_AMBIGUOUS", "Ambiguous legacy hierarchy-exit data preserved; manual migration is required.", Severity.WARNING)
	if c.states.is_empty(): _issue(c, "FSM_EMPTY", "FSM has no States.")
	if index.actor(c) == null: _issue(c, "FSM_ACTOR_MISSING", "Actor cannot be resolved.")
	if machine.get_parent() is State and c.parent == null: _issue(c, "HIERARCHY_INVALID_OWNER", "Nested FSM owner must belong to an FSM.")
	if c.parent != null and (c.owner_state.get_parent() != c.parent.get_state_container() or machine.get_parent() != c.owner_state): _issue(c, "HIERARCHY_INVALID_OWNER", "Nested FSM ownership is invalid.")
	var named := {}
	for state: State in c.states:
		if not is_finite(state.minimum_state_time) or state.minimum_state_time < 0.0:
			_issue(c, "STATE_POLICY_INVALID_MINIMUM_TIME", "Minimum State Time must be finite and non-negative.", Severity.ERROR, state)
		var key := String(state.name).to_lower()
		if named.has(key): _issue(c, "STATE_DUPLICATE_NAME", "State names must be unique ignoring case.", Severity.ERROR, state)
		named[key] = true
		var nested := 0
		for child in state.get_children(true):
			if child is FiniteStateMachine: nested += 1
		if nested > 1: _issue(c, "HIERARCHY_MULTIPLE_FSMS", "State owns multiple nested FSMs.", Severity.ERROR, state)
		if state is HierarchyState and nested == 0: _issue(c, "HIERARCHY_MISSING_FSM", "HierarchyState has no nested FSM.", Severity.ERROR, state)
	var starts := []
	if is_instance_valid(machine.initial_state):
		if machine.initial_state in c.states: starts.append(machine.initial_state)
		else: _issue(c, "FSM_INVALID_INITIAL_STATE", "Initial State does not belong to this FSM.")
	var adjacency := {}
	for state in c.states:
		if state is HierarchyState and c.names.has(String(state.exit_target).to_lower()): _edge(adjacency, state, c.names[String(state.exit_target).to_lower()])
	var duplicates := {}
	var priorities := {}
	for route in machine.transitions:
		if route == null: _issue(c, "TRANSITION_MISSING_RESOURCE", "Transition resource is missing."); continue
		if not is_finite(route.cooldown) or route.cooldown < 0.0:
			_issue(c, "TRANSITION_POLICY_INVALID_COOLDOWN", "Cooldown must be finite and non-negative.", Severity.ERROR, null, route)
		var source = c.names.get(String(route.from_state).to_lower())
		var target = c.names.get(String(route.to_state).to_lower())
		var valid := true
		if route.target_mode not in [StateTransition.TargetMode.DIRECT, StateTransition.TargetMode.RANDOM]: _issue(c, "TRANSITION_TARGET_MODE", "Invalid target mode.", Severity.ERROR, null, route); valid = false
		if route.source_mode not in [StateTransition.SourceMode.STATE, StateTransition.SourceMode.ANY_STATE, StateTransition.SourceMode.HIERARCHY_ENTRY]: _issue(c, "TRANSITION_SOURCE_MODE", "Invalid source mode.", Severity.ERROR, null, route); valid = false
		elif route.source_mode == StateTransition.SourceMode.STATE and source == null: _issue(c, "TRANSITION_MISSING_FROM", "Missing From State: %s." % route.from_state, Severity.ERROR, null, route, route, "remove_orphan"); valid = false
		elif route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY and c.parent == null: _issue(c, "ENTRY_INVALID_CONTEXT", "ENTRY requires a nested FSM.", Severity.ERROR, null, route); valid = false
		if route.target_mode == StateTransition.TargetMode.RANDOM:
			if route.random_routing == null:
				_issue(c, "RANDOM_MISSING", "Random routing is missing.", Severity.ERROR, null, route); valid = false
			else:
				var routing_error := route.random_routing.configuration_error()
				if not routing_error.is_empty(): _issue(c, "RANDOM_INVALID", routing_error, Severity.ERROR, null, route); valid = false
				var targets := {}
				for branch in route.random_routing.branches:
					if branch == null: continue
					var key := String(branch.target_state).to_lower()
					if targets.has(key): _issue(c, "RANDOM_DUPLICATE_TARGET", "Random has duplicate target branches: %s." % branch.target_state, Severity.WARNING, null, route, branch)
					targets[key] = true
					var branch_target: State = c.names.get(key)
					if branch.target_state == StateTransition.EXIT_TARGET:
						if c.parent == null or route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: _issue(c, "RANDOM_INVALID_TARGET", "Random EXIT requires a nested FSM and cannot originate at ENTRY.", Severity.ERROR, null, route, branch); valid = false
					elif branch_target == null:
						_issue(c, "RANDOM_INVALID_TARGET", "Random references missing or illegal target: %s." % branch.target_state, Severity.ERROR, null, route, branch); valid = false
					elif route.enabled:
						if route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: starts.append(branch_target)
						elif route.source_mode == StateTransition.SourceMode.ANY_STATE:
							for state in c.states: _edge(adjacency, state, branch_target)
						else: _edge(adjacency, source, branch_target)
		elif route.destination_mode == StateTransition.DestinationMode.STATE:
			if route.to_state.is_empty(): _issue(c, "TRANSITION_UNCONNECTED", "Transition has no target State.", Severity.WARNING, null, route); valid = false
			elif target == null: _issue(c, "TRANSITION_MISSING_TO", "Missing To State: %s." % route.to_state, Severity.ERROR, null, route, route, "remove_orphan"); valid = false
		elif route.destination_mode == StateTransition.DestinationMode.EXIT:
			if c.parent == null or route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: _issue(c, "EXIT_INVALID_CONTEXT", "EXIT requires a nested FSM and cannot originate at ENTRY.", Severity.ERROR, null, route); valid = false
		else: _issue(c, "TRANSITION_DESTINATION_MODE", "Invalid destination mode.", Severity.ERROR, null, route); valid = false
		if route.enabled:
			var first_issue := issues.size()
			_trigger(c, route, source)
			_conditions(c, route)
			for issue in issues.slice(first_issue):
				if issue.severity == Severity.ERROR: valid = false
			if route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY:
				if not route.actions.is_empty(): _issue(c, "ENTRY_EFFECTS_IGNORED", "ENTRY routes do not execute Effects.", Severity.WARNING, null, route)
			else:
				for effect in route.actions: _effect(c, route, effect, source, target)
			if valid and target != null:
				if route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: starts.append(target)
				elif route.source_mode == StateTransition.SourceMode.ANY_STATE:
					for state in c.states: _edge(adjacency, state, target)
				else: _edge(adjacency, source, target)
			var identity := _signature(route)
			if duplicates.has(identity): _issue(c, "TRANSITION_DUPLICATE", "Exact duplicate transition; resource order decides.", Severity.WARNING, null, route)
			duplicates[identity] = true
			var trigger_key := _signature(route, true)
			var target_key := route.target_label().to_lower()
			if priorities.has(trigger_key) and priorities[trigger_key] != target_key: _issue(c, "TRANSITION_PRIORITY_TIE", "Equivalent triggers have equal priority; resource order decides.", Severity.WARNING, null, route)
			priorities[trigger_key] = target_key
	if starts.is_empty() and not is_instance_valid(machine.initial_state): _issue(c, "FSM_NO_INITIAL_STATE", "Assign an Initial State or a valid nested ENTRY route.")
	var reachable := {}
	var cursor := 0
	while cursor < starts.size():
		var state = starts[cursor]
		cursor += 1
		if reachable.has(state): continue
		reachable[state] = true
		for target in adjacency.get(state, []):
			if not reachable.has(target): starts.append(target)
	for state in c.states:
		if state is HierarchyState:
			var exit_warning: String = state.exit_destination_warning()
			if not exit_warning.is_empty(): _issue(c, "HIERARCHY_EXIT_DESTINATION", exit_warning, Severity.WARNING, state)
		if not reachable.has(state): _issue(c, "STATE_UNREACHABLE", "State is unreachable through enabled transitions.", Severity.WARNING, state)

func _edge(edges: Dictionary, source, target) -> void:
	if not edges.has(source): edges[source] = []
	edges[source].append(target)

func _trigger(c: Dictionary, route: StateTransition, source) -> void:
	if route.trigger_type not in StateTransition.TriggerType.values(): _issue(c, "TRIGGER_INVALID", "Unknown trigger type.", Severity.ERROR, null, route); return
	if route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: return
	match route.trigger_type:
		1:
			if route.event_name.is_empty(): _issue(c, "TRIGGER_EVENT_EMPTY", "Event Name is empty.", Severity.ERROR, null, route)
		2:
			if not is_finite(route.duration) or route.duration < 0: _issue(c, "TRIGGER_TIMER_INVALID", "Timer duration must be finite and non-negative.", Severity.ERROR, null, route)
		3:
			if not preload("res://addons/state_machine/runtime/input_action_catalog.gd").has_action(route.input_action): _issue(c, "TRIGGER_INPUT_MISSING_ACTION", "Input Action '%s' does not exist." % route.input_action, Severity.WARNING, null, route)
			if route.input_mode not in range(3): _issue(c, "TRIGGER_INPUT_MODE", "Invalid Input mode.", Severity.ERROR, null, route)
		4:
			var actor: Node = index.actor(c)
			var player = actor.get_node_or_null(route.animation_player_path) if actor != null and not route.animation_player_path.is_empty() and not route.animation_player_path.is_absolute() else null
			if not player is AnimationPlayer: _issue(c, "TRIGGER_ANIMATION_PLAYER", "AnimationPlayer could not be verified.", Severity.WARNING, null, route)
			elif not player.has_animation(route.animation_name): _issue(c, "TRIGGER_ANIMATION_MISSING", "Animation '%s' does not exist." % route.animation_name, Severity.ERROR, null, route)
		5: _comparison(c, route, route.watch)
		7:
			if route.signal_name.is_empty(): _issue(c, "TRIGGER_SIGNAL_MISSING_NAME", "Signal name is empty.", Severity.ERROR, null, route)
			if route.signal_source_mode not in [StateTransition.SignalSourceMode.ACTOR, StateTransition.SignalSourceMode.NODE_PATH] or route.signal_source_mode == StateTransition.SignalSourceMode.NODE_PATH and (route.signal_source_path.is_empty() or route.signal_source_path.is_absolute() or route.signal_source_path.get_subname_count() > 0):
				_issue(c, "TRIGGER_SIGNAL_MISSING_SOURCE", "Select Actor or an Actor-relative Node path.", Severity.ERROR, null, route)
				return
			var actor: Node = index.actor(c)
			var target := PROPERTY.target(actor, route.signal_source_mode, route.signal_source_path)
			if target == null: _issue(c, "TRIGGER_SIGNAL_SOURCE_NOT_FOUND", "Signal source could not be verified; runtime-created nodes may resolve later.", Severity.WARNING, null, route)
			elif not route.signal_name.is_empty() and not route.signal_name in preload("res://addons/state_machine/editor/signal_catalog.gd").names(target):
				var script: Script = target.get_script()
				var dynamic := script != null and not script.is_tool() and preload("res://addons/state_machine/editor/signal_catalog.gd").declared_names(script).is_empty()
				_issue(c, "TRIGGER_SIGNAL_UNVERIFIED" if dynamic else "TRIGGER_SIGNAL_NOT_FOUND", "Signal '%s' is not declared on the source; runtime-added signals cannot be verified." % route.signal_name, Severity.WARNING if dynamic else Severity.ERROR, null, route)

func _conditions(c: Dictionary, route: StateTransition) -> void:
	var plan := LOGIC.compile(route)
	if not plan.valid: _issue(c, "CONDITION_TREE_INVALID", plan.error, Severity.ERROR, null, route, route.condition_group)
	for resource in plan.resources:
		if resource is TransitionCondition and resource.enabled: _comparison(c, route, resource)

func _comparison(c: Dictionary, route: StateTransition, spec: TransitionCondition) -> void:
	if spec == null: _issue(c, "PROPERTY_MISSING_COMPARISON", "Missing property comparison.", Severity.ERROR, null, route); return
	if spec.comparison_operator not in range(6): _issue(c, "PROPERTY_OPERATOR_INVALID", "Invalid comparison operator.", Severity.ERROR, null, route, spec)
	elif typeof(spec.comparison_value) not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME] or not PROPERTY.compatible(CATALOG.default_value(typeof(spec.comparison_value)), spec.comparison_value, spec.comparison_operator):
		_issue(c, "PROPERTY_TYPE_MISMATCH", "Comparison value type does not support this operator.", Severity.ERROR, null, route, spec)
	var actor: Node = index.actor(c)
	var target := PROPERTY.target(actor, spec.target_mode, spec.target_path)
	if target == null:
		var unknown := spec.target_mode == 1 and not spec.target_path.is_empty() and not spec.target_path.is_absolute()
		_issue(c, "PROPERTY_TARGET_UNVERIFIED" if unknown else "PROPERTY_TARGET_INVALID", "Property target could not be verified in the editor.", Severity.WARNING if unknown else Severity.ERROR, null, route, spec)
		return
	var type := _property_type(c, route, spec, target, spec.property_path)
	if type != TYPE_NIL and type not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]: _issue(c, "PROPERTY_TYPE_UNSUPPORTED", "Property type is not supported for comparisons.", Severity.ERROR, null, route, spec); return
	if type != TYPE_NIL and not PROPERTY.compatible(CATALOG.default_value(type), spec.comparison_value, spec.comparison_operator): _issue(c, "PROPERTY_TYPE_MISMATCH", "Property and value/operator have incompatible types.", Severity.ERROR, null, route, spec)

func _property_type(c: Dictionary, route: StateTransition, resource: Resource, target: Object, path: NodePath) -> int:
	if path.is_empty() or path.is_absolute() or path.get_name_count() != 1:
		_issue(c, "PROPERTY_PATH_INVALID", "Use a property name with optional colon subpath.", Severity.ERROR, null, route, resource)
		return TYPE_NIL
	var type := PROPERTY.declared_type(target, path)
	if type == TYPE_NIL:
		var root_type := PROPERTY.declared_type(target, NodePath(String(path.get_name(0))))
		if root_type != TYPE_NIL and root_type not in [TYPE_DICTIONARY, TYPE_OBJECT] and path.get_subname_count() > 0: _issue(c, "PROPERTY_SUBPATH_INVALID", "Invalid property subpath.", Severity.ERROR, null, route, resource)
		else: _issue(c, "PROPERTY_UNVERIFIED", "Property '%s' could not be verified in the editor." % path, Severity.WARNING, null, route, resource)
	return type

func _effect(c: Dictionary, route: StateTransition, effect, source, destination) -> void:
	if not effect is TransitionAction: _issue(c, "EFFECT_INVALID_RESOURCE", "Invalid Effect resource.", Severity.ERROR, null, route); return
	if not effect.enabled: return
	if effect.action_type not in range(5) or effect.timing not in range(3) or effect.target_mode not in range(5): _issue(c, "EFFECT_INVALID_MODE", "Invalid Effect type, timing or target.", Severity.ERROR, null, route, effect); return
	var actor: Node = index.actor(c)
	var target: Object
	match effect.target_mode:
		0: target = actor
		1: target = c.fsm
		2: target = source
		3: target = source if route.destination_mode == StateTransition.DestinationMode.EXIT else destination
		4: target = actor.get_node_or_null(effect.target_path) if actor != null and not effect.target_path.is_empty() and not effect.target_path.is_absolute() else null
	if target == null: _issue(c, "EFFECT_TARGET_UNVERIFIED", "Effect target could not be verified in the editor.", Severity.WARNING, null, route, effect); return
	if effect.action_type in [3, 4]:
		var name: StringName = effect.method_name if effect.action_type == 3 else effect.signal_name
		if name.is_empty(): _issue(c, "EFFECT_MEMBER_EMPTY", "Method/signal name is empty.", Severity.ERROR, null, route, effect); return
		var verified := target.has_method(name) if effect.action_type == 3 else target.has_signal(name)
		var member_info := {}
		for member in (target.get_method_list() if effect.action_type == 3 else target.get_signal_list()):
			if StringName(member.name) == name: member_info = member; break
		var script: Script = target.get_script()
		while script != null:
			for member in (script.get_script_method_list() if effect.action_type == 3 else script.get_script_signal_list()):
				if StringName(member.name) == name: verified = true; member_info = member; break
			if not member_info.is_empty(): break
			script = script.get_base_script()
		if not verified: _issue(c, "EFFECT_MEMBER_UNVERIFIED", "Method/signal '%s' could not be verified in the editor." % name, Severity.WARNING, null, route, effect)
		elif member_info.get("args", []).size() > member_info.get("default_args", []).size(): _issue(c, "EFFECT_ARGUMENTS_REQUIRED", "Effect method/signal requires arguments; these Effects pass none.", Severity.ERROR, null, route, effect)
		return
	var type := _property_type(c, route, effect, target, effect.property_path)
	if type == TYPE_NIL: return
	var compatible := typeof(effect.value) == type or type in [TYPE_INT, TYPE_FLOAT] and typeof(effect.value) in [TYPE_INT, TYPE_FLOAT] or type in [TYPE_STRING, TYPE_STRING_NAME] and typeof(effect.value) in [TYPE_STRING, TYPE_STRING_NAME]
	if effect.action_type == 1: compatible = type == TYPE_BOOL
	if effect.action_type == 2: compatible = type in [TYPE_INT, TYPE_FLOAT] and typeof(effect.value) in [TYPE_INT, TYPE_FLOAT]
	if effect.action_type != 1 and typeof(effect.value) in [TYPE_INT, TYPE_FLOAT] and not is_finite(float(effect.value)): compatible = false
	if not compatible: _issue(c, "EFFECT_TYPE_MISMATCH", "Effect property/value types are incompatible.", Severity.ERROR, null, route, effect)

func _signature(route: StateTransition, ambiguity := false) -> String:
	var fields := [route.source_mode, String(route.from_state).to_lower() if route.source_mode == StateTransition.SourceMode.STATE else "", route.priority]
	if route.source_mode != StateTransition.SourceMode.HIERARCHY_ENTRY:
		fields.append(route.trigger_type)
		match route.trigger_type:
			1: fields.append(route.event_name)
			2: fields.append(route.duration)
			3: fields.append([route.input_action, route.input_mode])
			4: fields.append([route.animation_player_path, route.animation_name])
			7: fields.append([route.signal_source_mode, route.signal_source_path, route.signal_name])
	var comparisons := []
	var plan := LOGIC.compile(route)
	for resource in plan.resources:
		if resource is TransitionCondition: comparisons.append(SNAPSHOT.comparison(resource))
		elif resource is TransitionConditionGroup: comparisons.append([resource.enabled, resource.operator, resource.negated, resource.children.size()])
	if route.trigger_type == 5: comparisons.append(SNAPSHOT.comparison(route.watch))
	fields.append(comparisons)
	if not ambiguity:
		if route.target_mode == StateTransition.TargetMode.RANDOM:
			fields.append([route.target_mode, route.random_routing.mode if route.random_routing != null else -1])
			if route.random_routing != null:
				for branch in route.random_routing.branches: fields.append([branch.target_state, branch.percentage] if branch != null else null)
		if route.source_mode != StateTransition.SourceMode.HIERARCHY_ENTRY: fields.append([route.cooldown, route.can_interrupt])
		fields.append([route.destination_mode, String(route.target_key()).to_lower()])
		fields.append(route.reenter_state)
		for effect in route.actions:
			var values := []
			if effect is TransitionAction:
				for field in SNAPSHOT.ACTION_FIELDS: values.append(effect.get(field))
			fields.append(values)
	return var_to_str(fields)
