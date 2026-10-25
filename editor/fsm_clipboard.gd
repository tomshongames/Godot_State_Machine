@tool
extends RefCounted

# Editor-local authored snapshots. Nodes in the buffer never enter the SceneTree.
# Scripts/assets and external Random destinations are references; owned data is copied.
const OWNED := preload("res://addons/state_machine/runtime/authoring_copy.gd")
var kind := ""
var scope: WeakRef
var source: WeakRef
var anchor: WeakRef
var last_pasted: WeakRef
var state: State
var transitions: Array[StateTransition] = []
var targets: Dictionary = {}
var paths: PackedStringArray = []
var scope_paths: PackedStringArray = []
var position := Vector2.ZERO
var paste_count := 0

func clear() -> void:
	if is_instance_valid(state): state.free()
	state = null
	transitions.clear()
	targets.clear()
	paths.clear()
	scope_paths.clear()
	scope = null
	source = null
	anchor = null
	last_pasted = null
	kind = ""
	paste_count = 0

func copy_state(machine: FiniteStateMachine, original: State) -> bool:
	if not machine.owns_state(original): return false
	clear()
	state = clone_state(original)
	if state == null: return false
	kind = "HIERARCHY_STATE" if original is HierarchyState else "STATE"
	scope = weakref(machine)
	_capture_scope_paths(machine)
	source = weakref(original)
	position = machine.graph_positions.get(String(original.name), Vector2.ZERO)
	var actor := machine.get_effective_actor() as Node
	if actor != null and actor.is_inside_tree() and original.is_inside_tree(): paths.append(String(actor.get_path_to(original)))
	if original.is_inside_tree(): paths.append(String(original.get_path()))
	var nodes := {}
	_collect_nodes(original, state, nodes)
	for route in machine.transitions:
		if route != null and route.source_mode == StateTransition.SourceMode.STATE and String(route.from_state).nocasecmp_to(String(original.name)) == 0:
			transitions.append(clone_transition(route, nodes))
			_remember_target(machine, route, original)
	if original is HierarchyState: _remember_name(machine, original.exit_target, original)
	return true

func copy_transition(machine: FiniteStateMachine, route: StateTransition) -> bool:
	if route == null or not route in machine.transitions: return false
	clear()
	kind = "TRANSITION"
	scope = weakref(machine)
	_capture_scope_paths(machine)
	anchor = weakref(route)
	transitions.append(clone_transition(route))
	if route.source_mode == StateTransition.SourceMode.STATE:
		for child in machine.get_state_container().get_children():
			if child is State and String(child.name).nocasecmp_to(String(route.from_state)) == 0: source = weakref(child); break
	_remember_target(machine, route, null)
	return true

func same_scope(machine: FiniteStateMachine) -> bool:
	return scope != null and scope.get_ref() == machine

func refusal(machine: FiniteStateMachine, destination_source: State = null) -> String:
	if kind.is_empty(): return "Copy a State or persistent Transition Block first."
	if not is_instance_valid(machine): return "Open a State Machine to paste."
	if not same_scope(machine):
		if kind == "TRANSITION" and not machine.owns_state(destination_source): return "Select a State to paste this transition."
		return ""
	if kind == "TRANSITION":
		if transitions[0].source_mode == StateTransition.SourceMode.STATE and (source == null or not machine.owns_state(source.get_ref())): return "Cannot paste: the copied transition's source State no longer exists."
		if transitions[0].source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY and not machine.has_hierarchy_boundary(): return "Cannot paste ENTRY outside its hierarchy."
	for reference in targets.values():
		if not machine.owns_state(reference.get_ref()): return "Cannot paste: an original destination State no longer exists."
	return ""

func resolved_name(value: StringName) -> StringName:
	var reference: WeakRef = targets.get(String(value).to_lower())
	return reference.get_ref().name if reference != null and is_instance_valid(reference.get_ref()) else value

func _remember_target(machine: FiniteStateMachine, route: StateTransition, self_state: State) -> void:
	# The router itself owns its output destinations; it is not part of this copy.
	if route.target_mode == StateTransition.TargetMode.DIRECT and route.destination_mode == StateTransition.DestinationMode.STATE: _remember_name(machine, route.to_state, self_state)

func _remember_name(machine: FiniteStateMachine, value: StringName, self_state: State) -> void:
	for child in machine.get_state_container().get_children():
		if child is State and child != self_state and String(child.name).nocasecmp_to(String(value)) == 0: targets[String(value).to_lower()] = weakref(child); break

static func clone_transition(route: StateTransition, nodes: Dictionary = {}) -> StateTransition:
	var copies := {}
	# A parent transition references a logical target router, just as it references a State.
	if route.random_routing != null: copies[route.random_routing] = route.random_routing
	return clone_value(route, copies, nodes)

static func clone_state(original: State) -> State:
	var copy := original.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION) as State
	if copy == null: return null
	var nodes := {}
	_collect_nodes(original, copy, nodes)
	var resources := {}
	for node: Node in nodes:
		var duplicate: Node = nodes[node]
		for property in node.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name != "script":
				duplicate.set(property.name, clone_value(node.get(property.name), resources, nodes))
		for key in node.get_meta_list():
			if key != &"_fsm_editor_removed_data": duplicate.set_meta(key, clone_value(node.get_meta(key), resources, nodes))
	return copy

static func _collect_nodes(original: Node, copy: Node, nodes: Dictionary) -> void:
	nodes[original] = copy
	for child in original.get_children():
		var duplicate := copy.get_node_or_null(NodePath(String(child.name)))
		if duplicate != null: _collect_nodes(child, duplicate, nodes)

static func clone_value(value: Variant, copies: Dictionary, nodes: Dictionary = {}) -> Variant:
	if value is Node: return nodes.get(value, value) if is_instance_valid(value) else null
	if value is Resource:
		if copies.has(value): return copies[value]
		# Native external assets are intentionally shared. Script-backed data and
		# inline data Resources (including custom State settings) are independent.
		if _is_asset(value): return value
		if not OWNED.is_mutable(value) and value.get_script() == null and not value.resource_path.is_empty(): return value
		# Start script-backed data from a fresh instance. Several FSM setters skip
		# equal assignments; a shallow duplicate would retain equal Array/Dictionary
		# aliases even when given an independently cloned replacement value.
		var duplicate: Resource = value.get_script().new() if value.get_script() != null else value.duplicate(false)
		copies[value] = duplicate
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.name not in ["script", "resource_path"]: duplicate.set(property.name, clone_value(value.get(property.name), copies, nodes))
		for key in value.get_meta_list(): duplicate.set_meta(key, clone_value(value.get_meta(key), copies, nodes))
		return duplicate
	if value is Array:
		var duplicate: Array = value.duplicate()
		for index in value.size(): duplicate[index] = clone_value(value[index], copies, nodes)
		return duplicate
	if value is Dictionary:
		var duplicate := {}
		for key in value: duplicate[clone_value(key, copies, nodes)] = clone_value(value[key], copies, nodes)
		return duplicate
	return value

static func _is_asset(value: Resource) -> bool:
	return value is Script or value is Texture2D or value is Texture3D or value is Material or value is Mesh or value is AudioStream or value is PackedScene or value is Font or value is Theme

func _capture_scope_paths(machine: FiniteStateMachine) -> void:
	var container := machine.get_state_container()
	var actor := machine.get_effective_actor() as Node
	if container.is_inside_tree(): scope_paths.append(String(container.get_path()))
	if actor != null and actor.is_inside_tree() and container.is_inside_tree(): scope_paths.append(String(actor.get_path_to(container)))

static func remap_paths(value: Variant, replacements: Dictionary, seen: Dictionary = {}, external: Dictionary = {}, root: Node = null, clear_external := false) -> Variant:
	if value is NodePath:
		var path := String(value)
		for prefix: String in replacements:
			if path == prefix or path.begins_with(prefix + "/") or path.begins_with(prefix + ":"): return NodePath("") if replacements[prefix] == null else NodePath(String(replacements[prefix]) + path.substr(prefix.length()))
		return value
	if value is Node or value is Resource:
		if value is Node and (root == null or value != root and not root.is_ancestor_of(value)): return null if clear_external else value
		if seen.has(value) or external.has(value): return value
		seen[value] = true
		if value is Resource and _is_asset(value): return value
		if value is Resource and not OWNED.is_mutable(value) and value.get_script() == null: return value
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.name not in ["script", "resource_path", "property_path"] and (value is Resource or property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE): value.set(property.name, remap_paths(value.get(property.name), replacements, seen, external, root, clear_external))
		for key in value.get_meta_list(): value.set_meta(key, remap_paths(value.get_meta(key), replacements, seen, external, root, clear_external))
		if value is Node:
			for child in value.get_children(): remap_paths(child, replacements, seen, external, root, clear_external)
	elif value is Array:
		for index in value.size(): value[index] = remap_paths(value[index], replacements, seen, external, root, clear_external)
	elif value is Dictionary:
		for key in value: value[key] = remap_paths(value[key], replacements, seen, external, root, clear_external)
	return value
