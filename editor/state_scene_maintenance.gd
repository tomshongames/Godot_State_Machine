@tool
extends RefCounted

# The native SceneTree action retains the removed Node. Its backup travels with
# that same Node, so native Undo can restore metadata without another history step.
const REMOVED_DATA := &"_fsm_editor_removed_data"
const COLOR_META := &"fsm_editor_color"
var editor_interface: EditorInterface
var actions
var machines: Dictionary = {}
var tree: SceneTree
var running := false
var signal_provenance: Dictionary = {}


func setup(interface: EditorInterface, editor_actions, scene_tree: SceneTree) -> void:
	running = true
	editor_interface = interface
	actions = editor_actions
	tree = scene_tree
	tree.node_added.connect(_node_added)
	actions.changed.connect(_remember_signals)
	watch_scene(editor_interface.get_edited_scene_root())


func stop() -> void:
	running = false
	if actions.changed.is_connected(_remember_signals): actions.changed.disconnect(_remember_signals)
	if is_instance_valid(tree) and tree.node_added.is_connected(_node_added):
		tree.node_added.disconnect(_node_added)
	for machine in machines.keys():
		if is_instance_valid(machine):
			_disconnect_machine(machine)
	machines.clear()
	signal_provenance.clear()


func watch_scene(root: Node) -> void:
	if not is_instance_valid(root):
		return
	if root is FiniteStateMachine and not machines.has(root):
		machines[root] = true
		root.get_state_container().child_exiting_tree.connect(_child_exiting.bind(root))
		root.get_state_container().child_entered_tree.connect(_child_entered.bind(root))
		root.editor_data_changed.connect(_remember_signals.bind(root))
		for child in root.get_state_container().get_children():
			if child is State and child.has_meta(REMOVED_DATA):
				_restore_deferred.call_deferred(weakref(root), weakref(child))
	if root is FiniteStateMachine: _remember_signals(root)
	for child in root.get_children(true):
		watch_scene(child)

func _remember_signals(machine) -> void:
	if not running or not is_instance_valid(machine): return
	var actor := machine.get_effective_actor() as Node
	if is_instance_valid(actor) and actor.is_inside_tree() and machine.get_state_container().is_inside_tree():
		for route in machine.transitions:
			if route != null: signal_provenance[route.get_instance_id()] = String(actor.get_path_to(machine.get_state_container()))


func _node_added(node: Node) -> void:
	if node is FiniteStateMachine:
		_watch_added.call_deferred(weakref(node), not actions.applying)


func _watch_added(reference: WeakRef, isolate := true) -> void:
	var node := reference.get_ref() as FiniteStateMachine
	if not running or not is_instance_valid(node) or not is_instance_valid(editor_interface):
		return
	var root := editor_interface.get_edited_scene_root()
	if is_instance_valid(root) and (root == node or root.is_ancestor_of(node)):
		if isolate and not machines.has(node) and not actions.applying:
			# Loaded scene contexts are registered synchronously by watch_scene.
			# A freshly inserted subtree owns its data even if its clipboard source
			# is no longer alive. Node.duplicate already remaps exported Node refs.
			var container := node.get_state_container()
			actions.isolate_native_subtree(container, container, signal_provenance)
			editor_interface.mark_scene_as_unsaved()
		watch_scene(node)


func _disconnect_machine(machine: FiniteStateMachine) -> void:
	if machine.editor_data_changed.is_connected(_remember_signals.bind(machine)): machine.editor_data_changed.disconnect(_remember_signals.bind(machine))
	if machine.get_state_container().child_exiting_tree.is_connected(_child_exiting.bind(machine)):
		machine.get_state_container().child_exiting_tree.disconnect(_child_exiting.bind(machine))
	if machine.get_state_container().child_entered_tree.is_connected(_child_entered.bind(machine)):
		machine.get_state_container().child_entered_tree.disconnect(_child_entered.bind(machine))


func _child_exiting(state: Node, machine: FiniteStateMachine) -> void:
	if not Engine.is_editor_hint() or not state is State or actions.applying:
		return
	var key := machine._make_state_key(state.name)
	var linked: Array[StateTransition] = []
	for transition in machine.transitions:
		if transition != null and ((transition.source_mode == StateTransition.SourceMode.STATE and machine._make_state_key(transition.from_state) == key) or machine._make_state_key(transition.to_state) == key):
			linked.append(transition)
	var positions: Dictionary = {}
	for position_key in machine.graph_positions:
		if machine._make_state_key(StringName(position_key)) == key:
			positions[position_key] = machine.graph_positions[position_key]
	var data := {"machine": machine.get_instance_id(), "name": state.name, "transitions": linked, "order": machine.transitions.duplicate(), "positions": positions, "initial": machine.initial_state == state, "has_color": state.has_meta(COLOR_META), "color": state.get_meta(COLOR_META, Color.WHITE)}
	data.exit_links = []
	for sibling in machine.get_state_container().get_children():
		if sibling is HierarchyState and String(sibling.exit_target).nocasecmp_to(String(state.name)) == 0: data.exit_links.append({"state": sibling, "target": sibling.exit_target})
	_finalize_removal.call_deferred(machine, state, data)


func _finalize_removal(machine, state, data: Dictionary) -> void:
	if not running or not is_instance_valid(machine) or not machine.is_inside_tree():
		return
	# Whole-scene changes and temporary moves are not State deletion.
	if is_instance_valid(state) and state.get_parent() != null:
		return
	var root := editor_interface.get_edited_scene_root()
	if not is_instance_valid(root) or (root != machine and not root.is_ancestor_of(machine)):
		return
	var names := _state_names(machine)
	var key: StringName = machine._make_state_key(data.name)
	if names.has(key):
		return
	var removed: Array[StateTransition] = []
	for transition in data.transitions:
		if transition in machine.transitions:
			machine.transitions.erase(transition)
			removed.append(transition)
	data.transitions = removed
	for position_key in data.positions:
		machine.graph_positions.erase(position_key)
	if data.initial:
		machine.initial_state = null
	for link in data.get("exit_links", []):
		if is_instance_valid(link.state) and link.state.exit_target == link.target: link.state.exit_target = &""
	if is_instance_valid(state):
		state.remove_meta(COLOR_META)
		state.set_meta(REMOVED_DATA, data)
	_changed(machine)


func _child_entered(state: Node, machine: FiniteStateMachine) -> void:
	if not Engine.is_editor_hint() or not state is State:
		return
	_restore_all.call_deferred(weakref(machine))


func _restore_all(reference: WeakRef) -> void:
	var machine := reference.get_ref() as FiniteStateMachine
	if running and is_instance_valid(machine):
		for state in machine.get_state_container().get_children():
			if state is State and state.has_meta(REMOVED_DATA):
				_restore(machine, state)


func _restore_deferred(machine_reference: WeakRef, state_reference: WeakRef) -> void:
	var machine := machine_reference.get_ref() as FiniteStateMachine
	var state := state_reference.get_ref() as State
	if running and machine != null and state != null: _restore(machine, state)


func _restore(machine: FiniteStateMachine, state: State) -> void:
	if not is_instance_valid(machine) or not machine.owns_state(state) or not state.has_meta(REMOVED_DATA):
		return
	var data: Dictionary = state.get_meta(REMOVED_DATA)
	if data.machine != machine.get_instance_id():
		return
	var names := _state_names(machine)
	var pending: Array[StateTransition] = []
	for transition in data.transitions:
		if transition == null: continue
		var source_exists: bool = transition.source_mode in [StateTransition.SourceMode.ANY_STATE, StateTransition.SourceMode.HIERARCHY_ENTRY] or names.has(machine._make_state_key(transition.from_state))
		var target_exists: bool = transition.destination_mode == StateTransition.DestinationMode.EXIT and machine.has_hierarchy_boundary() or names.has(machine._make_state_key(transition.to_state))
		if source_exists and target_exists:
			if not transition in machine.transitions:
				machine.transitions.append(transition)
		else:
			pending.append(transition)
	for key in data.positions:
		machine.graph_positions[key] = data.positions[key]
	var ordered: Array[StateTransition] = []
	for transition in data.order:
		if transition in machine.transitions and not transition in ordered:
			ordered.append(transition)
	for transition in machine.transitions:
		if not transition in ordered:
			ordered.append(transition)
	machine.transitions = ordered
	if data.has_color:
		state.set_meta(COLOR_META, data.color)
	if data.initial and machine.initial_state == null:
		machine.initial_state = state
	for link in data.get("exit_links", []):
		if is_instance_valid(link.state) and link.state.exit_target.is_empty(): link.state.exit_target = link.target
	if pending.is_empty():
		state.remove_meta(REMOVED_DATA)
	else:
		data.transitions = pending
		state.set_meta(REMOVED_DATA, data)
	_changed(machine)


func _state_names(machine: FiniteStateMachine) -> Dictionary:
	var names: Dictionary = {}
	for child in machine.get_state_container().get_children():
		if child is State:
			names[machine._make_state_key(child.name)] = true
	return names


func _changed(machine: FiniteStateMachine) -> void:
	machine.update_configuration_warnings()
	machine.editor_data_changed.emit()
	editor_interface.mark_scene_as_unsaved()
