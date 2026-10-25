@tool
extends RefCounted

signal changed(machine: FiniteStateMachine)
signal error(message: String)
signal visual_changed(machine: FiniteStateMachine, transition: StateTransition)
signal machine_created(machine: FiniteStateMachine)
signal positions_changed(machine: FiniteStateMachine)
signal endpoints_changed(machine: FiniteStateMachine, transition: StateTransition, source_only: bool)
signal order_changed(machine: FiniteStateMachine, transition: StateTransition)
signal transition_property_changed(machine: FiniteStateMachine, transition: StateTransition, property: StringName)
signal state_color_changed(machine: FiniteStateMachine, state: State)
signal hierarchy_exit_changed(machine: FiniteStateMachine, state: HierarchyState)
signal paste_started(machine: FiniteStateMachine)
signal graph_visibility_changed(machine: FiniteStateMachine, state: State)
const HIDDEN_META := &"fsm_editor_graph_hidden"
const CLIPBOARD := preload("res://addons/state_machine/editor/fsm_clipboard.gd")
const TRANSITION_COLORS := preload("res://addons/state_machine/editor/transition_colors.gd")
var creation_color := TRANSITION_COLORS.DEFAULT

const COLOR_META := &"fsm_editor_color"
const SCRIPT_UTILS := preload("res://addons/state_machine/editor/state_script_utils.gd")
const DIALOGS_SCRIPT := preload("res://addons/state_machine/editor/state_authoring_dialogs.gd")
const CONDITION_LOGIC := preload("res://addons/state_machine/runtime/condition_expression.gd")
const SNAPSHOT := preload("res://addons/state_machine/editor/transition_snapshot.gd")
const AUTHORING_COPY := preload("res://addons/state_machine/runtime/authoring_copy.gd")
var undo_manager: EditorUndoRedoManager
var applying := false
var applied_random_positions: Dictionary = {}


func capture(machine: FiniteStateMachine) -> Dictionary:
	var data := {"nodes": [], "transitions": [], "positions": machine.graph_positions.duplicate(), "initial": machine.initial_state}
	data.initial_block_present = machine.get_state_container().has_meta(&"fsm_editor_initial_block_position")
	data.initial_block_value = machine.get_state_container().get_meta(&"fsm_editor_initial_block_position", Vector2.ZERO)
	data.entry_color_present = machine.get_state_container().has_meta(&"fsm_editor_entry_color")
	data.entry_color_value = machine.get_state_container().get_meta(&"fsm_editor_entry_color", TRANSITION_COLORS.DEFAULT)
	for child in machine.get_state_container().get_children():
		if child is State:
			data.nodes.append(_node_data(child))
	for transition in machine.transitions:
		data.transitions.append({"resource": transition, "from": transition.from_state if transition else &"", "to": transition.to_state if transition else &"", "settings": _transition_settings(transition)})
	return data


func _node_data(state: State) -> Dictionary:
	var owners: Dictionary = {}
	_capture_owners(state, owners)
	return {"node": state, "name": state.name, "index": state.get_index() if state.get_parent() else -1, "owners": owners, "has_color": state.has_meta(COLOR_META), "color": state.get_meta(COLOR_META, Color.WHITE), "exit_target": state.exit_target if state is HierarchyState else &""}

func set_hierarchy_exit_target(machine: FiniteStateMachine, state: HierarchyState, target: StringName) -> bool:
	if not is_instance_valid(machine) or not machine.owns_state(state): return false
	if not target.is_empty():
		if target == StateTransition.EXIT_TARGET:
			if not machine.has_hierarchy_boundary(): return false
		else:
			var found := false
			for child in machine.get_state_container().get_children():
				if child is State and String(child.name).nocasecmp_to(String(target)) == 0: target = child.name; found = true; break
			if not found: return false
	if state.exit_target == target: return true
	if undo_manager == null: _apply_hierarchy_exit_target(machine, state, target)
	else:
		undo_manager.create_action("Set Hierarchy Exit Destination", UndoRedo.MERGE_DISABLE, machine.get_state_container())
		undo_manager.add_do_method(self, "_apply_hierarchy_exit_target", machine, state, target)
		undo_manager.add_undo_method(self, "_apply_hierarchy_exit_target", machine, state, state.exit_target)
		undo_manager.commit_action()
	return true

func _apply_hierarchy_exit_target(machine: FiniteStateMachine, state: HierarchyState, target: StringName) -> void:
	if not is_instance_valid(machine) or not is_instance_valid(state): return
	state.exit_target = target
	state.update_configuration_warnings()
	machine.update_configuration_warnings()
	hierarchy_exit_changed.emit(machine, state)
	changed.emit(machine)


func _capture_owners(node: Node, owners: Dictionary) -> void:
	owners[node] = node.owner
	for child in node.get_children():
		_capture_owners(child, owners)


func valid_name(machine: FiniteStateMachine, requested: String, except: State = null) -> bool:
	if requested.is_empty() or requested != requested.strip_edges() or requested.validate_node_name() != requested:
		error.emit("Use a non-empty node name without leading/trailing spaces or invalid characters.")
		return false
	for child in machine.get_state_container().get_children():
		if child != except and String(child.name).to_lower() == requested.to_lower():
			error.emit("A child named '%s' already exists (names are case-insensitive)." % child.name)
			return false
	return true


func unique_name(machine: FiniteStateMachine, base: String) -> String:
	var candidate := base
	var suffix := 2
	var used: Dictionary = {}
	for child in machine.get_state_container().get_children():
		used[String(child.name).to_lower()] = true
	while used.has(candidate.to_lower()):
		candidate = base + str(suffix)
		suffix += 1
	return candidate


func create_state(machine: FiniteStateMachine, requested: String, position: Vector2, owner: Node, script: Script = null, insert_index := -1) -> State:
	if not valid_name(machine, requested) or not is_instance_valid(owner) or (owner != machine and not owner.is_ancestor_of(machine)):
		return null
	if script != null and not SCRIPT_UTILS.is_state_subclass(script):
		error.emit("The State script must extend State.")
		return null
	var state: State = script.new() as State if script != null else State.new()
	if state == null:
		error.emit("The script did not create a valid State instance.")
		return null
	state.name = requested
	# New visual States copy the toolbar's current authoring color. Existing and
	# duplicated States keep their own metadata because this runs only on create.
	state.set_meta(COLOR_META, creation_color)
	var before := capture(machine)
	var after := before.duplicate(true)
	var node_data := _node_data(state)
	node_data.owners[state] = owner
	if insert_index >= 0:
		node_data.index = clampi(insert_index, 0, machine.get_state_container().get_child_count())
		var at: int = after.nodes.size()
		for index in after.nodes.size():
			if after.nodes[index].index >= node_data.index:
				at = mini(at, index)
				after.nodes[index].index += 1
		after.nodes.insert(at, node_data)
	else: after.nodes.append(node_data)
	after.positions[requested] = position
	_commit("Create State", machine, before, after, state)
	return state


func rename_state(machine: FiniteStateMachine, state: State, requested: String, previous: String = "", record_history := true) -> bool:
	if not valid_name(machine, requested, state):
		if not previous.is_empty():
			applying = true
			state.name = previous
			applying = false
			changed.emit(machine)
		return false
	var old_name := previous if not previous.is_empty() else String(state.name)
	if old_name == requested:
		return true
	var before := capture(machine)
	for entry in before.nodes:
		if entry.node == state:
			entry.name = StringName(old_name)
	var after := before.duplicate(true)
	for entry in after.nodes:
		if entry.node == state:
			entry.name = StringName(requested)
		if entry.node is HierarchyState and String(entry.exit_target).nocasecmp_to(old_name) == 0: entry.exit_target = StringName(requested)
	if after.positions.has(old_name):
		after.positions[requested] = after.positions[old_name]
		after.positions.erase(old_name)
	for entry in after.transitions:
		if entry.resource == null: continue
		if entry.resource.source_mode == StateTransition.SourceMode.STATE and String(entry.from).to_lower() == old_name.to_lower():
			entry.from = StringName(requested)
		if String(entry.to).to_lower() == old_name.to_lower():
			entry.to = StringName(requested)
		for branch in entry.settings.get("routing_values", []):
			if String(branch.target).nocasecmp_to(old_name) == 0: branch.target = StringName(requested)
	if record_history:
		_commit("Rename State", machine, before, after)
	else:
		_apply(machine, after)
	return true


func duplicate_state(machine: FiniteStateMachine, state: State, position: Vector2) -> State:
	var copy_name := unique_name(machine, String(state.name))
	var independent_script: Script
	if SCRIPT_UTILS.has_gameplay_script(state):
		var writer = DIALOGS_SCRIPT.new()
		independent_script = writer.copy_state_script(state.get_script(), copy_name, state.owner)
		writer.free()
		if independent_script == null:
			error.emit("Could not create an independent State script; no duplicate was created.")
			return null
	var copy := state.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION) as State
	if copy == null:
		error.emit("This State could not be duplicated.")
		return null
	if independent_script != null:
		var values := _script_storage_values(copy)
		copy.set_script(independent_script)
		for property in values:
			copy.set(property, values[property])
	copy.name = copy_name
	if not _independent_nested_copy(state, copy):
		copy.free()
		error.emit("Could not safely duplicate the nested State scripts; no duplicate was created.")
		return null
	copy.remove_meta(&"_fsm_editor_removed_data")
	var before := capture(machine)
	var after := before.duplicate(true)
	var entry := _node_data(copy)
	entry.copy_source = state
	entry.owners[copy] = state.owner
	# Scene-owned descendants must keep ownership after duplication.
	for node in entry.owners:
		if node != copy and entry.owners[node] == null:
			entry.owners[node] = state.owner
	after.nodes.append(entry)
	after.positions[String(copy.name)] = position + Vector2(40, 40)
	_commit("Duplicate State", machine, before, after, copy)
	return copy


func paste_clipboard(machine: FiniteStateMachine, clipboard: RefCounted, owner: Node, destination_source: State = null, destination_position: Variant = null) -> Object:
	var reason: String = clipboard.refusal(machine, destination_source)
	if not reason.is_empty(): error.emit(reason); return null
	var cross_scope: bool = not clipboard.same_scope(machine)
	var before := capture(machine)
	var after := before.duplicate(true)
	var added: State
	var pasted_route: StateTransition
	if clipboard.kind == "TRANSITION":
		pasted_route = CLIPBOARD.clone_transition(clipboard.transitions[0])
		if cross_scope:
			pasted_route.source_mode = StateTransition.SourceMode.STATE
			pasted_route.from_state = destination_source.name
			_remap_cross_target(pasted_route, machine, &"", &"")
			var blocked := {}
			for prefix: String in clipboard.scope_paths: blocked[prefix] = null
			CLIPBOARD.remap_paths(pasted_route, blocked, {}, {}, null, true)
		else:
			if pasted_route.source_mode == StateTransition.SourceMode.STATE: pasted_route.from_state = clipboard.source.get_ref().name
			if pasted_route.target_mode == StateTransition.TargetMode.DIRECT and pasted_route.destination_mode == StateTransition.DestinationMode.STATE: pasted_route.to_state = clipboard.resolved_name(pasted_route.to_state)
		var anchor: StateTransition = clipboard.last_pasted.get_ref() if clipboard.last_pasted != null else null
		if anchor == null or not anchor in machine.transitions: anchor = clipboard.anchor.get_ref()
		var at: int = machine.transitions.find(anchor) + 1 if anchor != null and anchor in machine.transitions and anchor.source_mode == pasted_route.source_mode and anchor.from_state == pasted_route.from_state else after.transitions.size()
		after.transitions.insert(at, _copied_route_data(pasted_route))
	else:
		added = CLIPBOARD.clone_state(clipboard.state)
		if added == null: error.emit("Could not duplicate the copied State."); return null
		var old_name: String = clipboard.state.name
		added.name = unique_name(machine, old_name)
		# Visibility is organization of the source graph, not a State template.
		if added.has_meta(HIDDEN_META): added.remove_meta(HIDDEN_META)
		var replacements := {}
		var actor := machine.get_effective_actor() as Node
		for prefix: String in clipboard.paths:
			replacements[prefix] = String(machine.get_state_container().get_path()) + "/" + String(added.name) if prefix.begins_with("/") else (String(actor.get_path_to(machine.get_state_container())) + "/" + String(added.name) if actor != null else prefix)
		if cross_scope:
			for prefix: String in clipboard.scope_paths:
				if not replacements.has(prefix): replacements[prefix] = null
		CLIPBOARD.remap_paths(added, replacements, {}, {}, added, cross_scope)
		if added is HierarchyState:
			if cross_scope:
				added.exit_target = added.name if String(added.exit_target).nocasecmp_to(old_name) == 0 else (StateTransition.EXIT_TARGET if added.exit_target == StateTransition.EXIT_TARGET and machine.has_hierarchy_boundary() else &"")
			else: added.exit_target = added.name if String(added.exit_target).nocasecmp_to(old_name) == 0 else clipboard.resolved_name(added.exit_target)
		var entry := _node_data(added)
		for node in entry.owners:
			var previous_owner: Node = entry.owners[node]
			# Keep ownership within duplicated subscenes; external scene ownership
			# moves to the current edited scene when the pasted root is attached.
			if not is_instance_valid(previous_owner) or previous_owner != added and not added.is_ancestor_of(previous_owner): entry.owners[node] = owner
		after.nodes.append(entry)
		after.positions[String(added.name)] = destination_position if destination_position is Vector2 else (Vector2(40, 40) if cross_scope else clipboard.position + Vector2(40, 40) * (clipboard.paste_count + 1))
		var nodes := {}
		CLIPBOARD._collect_nodes(clipboard.state, added, nodes)
		for route: StateTransition in clipboard.transitions:
			var duplicate := CLIPBOARD.clone_transition(route, nodes)
			duplicate.from_state = added.name
			if cross_scope: _remap_cross_target(duplicate, machine, StringName(old_name), added.name)
			elif duplicate.target_mode == StateTransition.TargetMode.DIRECT and duplicate.destination_mode == StateTransition.DestinationMode.STATE:
				duplicate.to_state = added.name if String(duplicate.to_state).nocasecmp_to(old_name) == 0 else clipboard.resolved_name(duplicate.to_state)
			var external := {}
			if duplicate.random_routing != null: external[duplicate.random_routing] = true
			CLIPBOARD.remap_paths(duplicate, replacements, {}, external, added, cross_scope)
			after.transitions.append(_copied_route_data(duplicate))
	if undo_manager == null: _apply_paste(machine, after)
	else:
		undo_manager.create_action("Paste Transition" if added == null else "Paste State", UndoRedo.MERGE_DISABLE, machine.get_state_container())
		undo_manager.add_do_method(self, "_apply_paste", machine, after)
		undo_manager.add_undo_method(self, "_apply_paste", machine, before)
		if added != null: undo_manager.add_do_reference(added)
		undo_manager.commit_action()
	clipboard.paste_count += 1
	if pasted_route != null: clipboard.last_pasted = weakref(pasted_route)
	return added if added != null else pasted_route

func _remap_cross_target(route: StateTransition, machine: FiniteStateMachine, old_self: StringName, new_self: StringName) -> void:
	# Inactive routing fields may survive a previous Random -> Direct edit too.
	# No router reference, active or dormant, may travel to another FSM.
	route.random_routing = null
	if route.target_mode == StateTransition.TargetMode.RANDOM:
		route.target_mode = StateTransition.TargetMode.DIRECT
		route.destination_mode = StateTransition.DestinationMode.STATE
		route.to_state = &""
	elif route.destination_mode == StateTransition.DestinationMode.EXIT:
		if not machine.has_hierarchy_boundary():
			route.destination_mode = StateTransition.DestinationMode.STATE
			route.to_state = &""
	else:
		route.to_state = new_self if not old_self.is_empty() and String(route.to_state).nocasecmp_to(String(old_self)) == 0 else &""

func set_graph_visible(machine: FiniteStateMachine, state: State, value: bool) -> void:
	if not machine.owns_state(state): return
	var previous := not bool(state.get_meta(HIDDEN_META, false))
	if previous == value: return
	if undo_manager == null: _apply_graph_visible(machine, state, value)
	else:
		undo_manager.create_action("Show State in Graph" if value else "Hide State in Graph", UndoRedo.MERGE_DISABLE, machine.get_state_container())
		undo_manager.add_do_method(self, "_apply_graph_visible", machine, state, value)
		undo_manager.add_undo_method(self, "_apply_graph_visible", machine, state, previous)
		undo_manager.commit_action()

func _apply_graph_visible(machine: FiniteStateMachine, state: State, value: bool) -> void:
	if value:
		if state.has_meta(HIDDEN_META): state.remove_meta(HIDDEN_META)
	else: state.set_meta(HIDDEN_META, true)
	graph_visibility_changed.emit(machine, state)

func _copied_route_data(route: StateTransition) -> Dictionary:
	return {"resource": route, "from": route.from_state, "to": route.to_state, "settings": _transition_settings(route)}

func _apply_paste(machine: FiniteStateMachine, data: Dictionary) -> void:
	paste_started.emit(machine)
	_apply(machine, data)


func nested_machine(state: State) -> FiniteStateMachine:
	return FiniteStateMachine.nested_machine_for_state(state)


func copy_machine_resources(source: FiniteStateMachine, target: FiniteStateMachine) -> void:
	var copies := {}
	target.transitions = AUTHORING_COPY.clone(source.transitions, copies)
	target.debugger_watches = AUTHORING_COPY.clone(source.debugger_watches, copies)
	target.graph_positions = AUTHORING_COPY.clone(source.graph_positions, copies)
	target.transition_rules = AUTHORING_COPY.clone(source.transition_rules, copies)
	target.initial_state = target.get_state_container().get_node_or_null(source.get_state_container().get_path_to(source.initial_state)) if source.owns_state(source.initial_state) else null
	target.editor_data_changed.emit()


func create_hierarchy(machine: FiniteStateMachine, requested: String, position: Vector2, owner: Node, insert_index := -1) -> State:
	return create_state(machine, requested, position, owner, load("res://addons/state_machine/runtime/hierarchy_state.gd"), insert_index)


func isolate_native_subtree(source: Node, target: Node, signal_origins: Dictionary = {}) -> void:
	var machine: FiniteStateMachine = source if source is FiniteStateMachine else (source.get_nested_machine() if source is HierarchyState else null)
	var prefixes := []
	if machine != null:
		for route in machine.transitions: prefixes.append(signal_origins.get(route.get_instance_id(), "") if route != null else "")
	if source is FiniteStateMachine and target is FiniteStateMachine:
		copy_machine_resources(source, target)
	elif source is HierarchyState and target is HierarchyState:
		copy_machine_resources(source.get_nested_machine(), target.get_nested_machine())
	var copied: FiniteStateMachine = target if target is FiniteStateMachine else (target.get_nested_machine() if target is HierarchyState else null)
	if copied != null:
		var actor := copied.get_effective_actor()
		if is_instance_valid(actor):
			for i in copied.transitions.size():
				var route := copied.transitions[i]
				var prefix: String = prefixes[i]
				if route == null or route.signal_source_mode != StateTransition.SignalSourceMode.NODE_PATH or prefix.is_empty(): continue
				var path := String(route.signal_source_path)
				if path != prefix and not path.begins_with(prefix + "/"): continue
				var relative := path.trim_prefix(prefix).trim_prefix("/")
				var node := copied.get_state_container() if relative.is_empty() else copied.get_state_container().get_node_or_null(NodePath(relative))
				if node != null: route.signal_source_path = actor.get_path_to(node)
	for child in source.get_children():
		var copy := target.get_node_or_null(NodePath(String(child.name)))
		if copy != null: isolate_native_subtree(child, copy, signal_origins)


func remap_signal_subtree(source: Node, copy: Node) -> void:
	var original: FiniteStateMachine = source if source is FiniteStateMachine else (source.get_nested_machine() if source is HierarchyState else null)
	var duplicate: FiniteStateMachine = copy if copy is FiniteStateMachine else (copy.get_nested_machine() if copy is HierarchyState else null)
	if original != null and duplicate != null:
		var actor := original.get_effective_actor()
		var copied_actor := duplicate.get_effective_actor()
		if is_instance_valid(actor) and is_instance_valid(copied_actor):
			var source_container := original.get_state_container()
			for i in mini(original.transitions.size(), duplicate.transitions.size()):
				var route := original.transitions[i]
				if route == null or route.signal_source_mode != StateTransition.SignalSourceMode.NODE_PATH: continue
				var node := actor.get_node_or_null(route.signal_source_path)
				if node == null or not (node == source_container or source_container.is_ancestor_of(node)): continue
				var copied_node := duplicate.get_state_container().get_node_or_null(source_container.get_path_to(node))
				if copied_node != null: duplicate.transitions[i].signal_source_path = copied_actor.get_path_to(copied_node)
	for child in source.get_children():
		var copied_node := copy.get_node_or_null(NodePath(String(child.name)))
		if copied_node != null: remap_signal_subtree(child, copied_node)


func make_composite(machine: FiniteStateMachine, state: State) -> FiniteStateMachine:
	if not machine.owns_state(state) or state.has_method("get_nested_machine"):
		return null
	for child in state.get_children():
		if child is FiniteStateMachine:
			return null
	var nested := FiniteStateMachine.new()
	nested.name = "FiniteStateMachine"
	nested.inherit_actor = true
	nested.nested_entry_mode = FiniteStateMachine.NestedEntryMode.RESET
	_change_nested(machine, state, nested, true)
	return nested


func remove_nested(machine: FiniteStateMachine, state: State) -> void:
	var nested := nested_machine(state)
	if nested != null and machine.owns_state(state) and not state.has_method("get_nested_machine"):
		_change_nested(machine, state, nested, false)


func _change_nested(machine: FiniteStateMachine, state: State, nested: FiniteStateMachine, attach: bool) -> void:
	var owners := {}
	_capture_owners(nested, owners)
	if attach:
		owners[nested] = state.owner
	if undo_manager == null:
		_apply_nested(machine, state, nested, attach, owners)
		return
	undo_manager.create_action("Make Composite State" if attach else "Remove Nested State Machine", UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply_nested", machine, state, nested, attach, owners)
	undo_manager.add_undo_method(self, "_apply_nested", machine, state, nested, not attach, owners)
	if attach:
		undo_manager.add_do_reference(nested)
	else:
		undo_manager.add_undo_reference(nested)
	undo_manager.commit_action()


func _apply_nested(machine: FiniteStateMachine, state: State, nested: FiniteStateMachine, attach: bool, owners: Dictionary) -> void:
	if not is_instance_valid(machine) or not is_instance_valid(state):
		return
	applying = true
	if attach and nested.get_parent() == null:
		state.add_child(nested)
		for node in owners:
			if is_instance_valid(node):
				node.owner = owners[node] if is_instance_valid(owners[node]) else null
	elif not attach and nested.get_parent() == state:
		state.remove_child(nested)
	applying = false
	state.update_configuration_warnings()
	machine.update_configuration_warnings()
	machine.editor_data_changed.emit()
	changed.emit(machine)


func _independent_nested_copy(source: Node, copy: Node) -> bool:
	if source.has_method("get_nested_machine"):
		var original: FiniteStateMachine = source.get_nested_machine()
		var duplicate: FiniteStateMachine = copy.get_nested_machine()
		copy_machine_resources(original, duplicate)
	for child in source.get_children():
		var duplicate := copy.get_node_or_null(NodePath(String(child.name)))
		if duplicate == null:
			return false
		if child is State and SCRIPT_UTILS.has_gameplay_script(child):
			var writer = DIALOGS_SCRIPT.new()
			var script: Script = writer.copy_state_script(child.get_script(), String(child.name), child.owner)
			writer.free()
			if script == null:
				return false
			var values := _script_storage_values(duplicate)
			duplicate.set_script(script)
			for property in values:
				duplicate.set(property, values[property])
		if child is FiniteStateMachine:
			copy_machine_resources(child, duplicate)
		if not _independent_nested_copy(child, duplicate):
			return false
	return true


func connected_count(machine: FiniteStateMachine, state: State) -> int:
	var count := 0
	for transition in machine.transitions:
		if transition and ((transition.source_mode == StateTransition.SourceMode.STATE and String(transition.from_state).to_lower() == String(state.name).to_lower()) or String(transition.to_state).to_lower() == String(state.name).to_lower()):
			count += 1
		elif transition != null and transition.target_mode == StateTransition.TargetMode.RANDOM and transition.random_routing != null:
			if transition.random_routing.branches.any(func(branch): return branch != null and String(branch.target_state).nocasecmp_to(String(state.name)) == 0): count += 1
	return count


func delete_state(machine: FiniteStateMachine, state: State) -> void:
	var before := capture(machine)
	var after := before.duplicate(true)
	for entry in after.nodes:
		if entry.node is HierarchyState and String(entry.exit_target).nocasecmp_to(String(state.name)) == 0: entry.exit_target = &""
	for index in range(after.nodes.size() - 1, -1, -1):
		if after.nodes[index].node == state:
			after.nodes.remove_at(index)
	for index in range(after.transitions.size() - 1, -1, -1):
		var entry: Dictionary = after.transitions[index]
		if entry.resource == null: continue
		if (entry.resource.source_mode == StateTransition.SourceMode.STATE and String(entry.from).to_lower() == String(state.name).to_lower()) or String(entry.to).to_lower() == String(state.name).to_lower():
			after.transitions.remove_at(index)
		elif entry.settings.get("target_mode", StateTransition.TargetMode.DIRECT) == StateTransition.TargetMode.RANDOM:
			for branch_index in range(entry.settings.routing_values.size() - 1, -1, -1):
				if String(entry.settings.routing_values[branch_index].target).nocasecmp_to(String(state.name)) == 0:
					entry.settings.routing_values.remove_at(branch_index)
					entry.settings.routing_branches.remove_at(branch_index)
	for key in after.positions.keys():
		if machine._make_state_key(StringName(key)) == machine._make_state_key(state.name):
			after.positions.erase(key)
	if after.initial == state:
		after.initial = null
	_commit("Delete State", machine, before, after, null, state)


func set_initial(machine: FiniteStateMachine, state: State, color: Variant = null) -> void:
	if not is_instance_valid(machine) or machine.initial_state == state: return
	var before := capture(machine)
	var after := before.duplicate(true)
	after.initial = state
	if color is Color:
		after.entry_color_present = true
		after.entry_color_value = color
	_commit("Set Initial State", machine, before, after)


func attach_script(machine: FiniteStateMachine, state: State, script: Script) -> void:
	if not machine.owns_state(state) or not SCRIPT_UTILS.is_state_subclass(script):
		error.emit("Attach a script extending State to a direct State child.")
		return
	var previous: Script = state.get_script()
	if undo_manager == null:
		_apply_script(machine, state, script)
		return
	undo_manager.create_action("Create State Script", UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply_script", machine, state, script)
	undo_manager.add_undo_method(self, "_apply_script", machine, state, previous)
	undo_manager.commit_action()


func _apply_script(machine: FiniteStateMachine, state: State, script: Script) -> void:
	if not is_instance_valid(machine) or not is_instance_valid(state):
		return
	var previous_actor
	if not Engine.is_editor_hint():
		previous_actor = state.actor
	var values := _script_storage_values(state)
	state.set_script(script)
	for property in script.get_script_property_list():
		if values.has(property.name) and property.usage & PROPERTY_USAGE_STORAGE:
			state.set(property.name, values[property.name])
	if not Engine.is_editor_hint():
		state.actor = previous_actor
	changed.emit(machine)


func _script_storage_values(state: State) -> Dictionary:
	var values: Dictionary = {}
	var script: Script = state.get_script()
	if script != null:
		for property in script.get_script_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE:
				values[property.name] = state.get(property.name)
	return values


func set_color(machine: FiniteStateMachine, state: State, color: Color, reset := false) -> void:
	if not is_instance_valid(machine) or not machine.owns_state(state): return
	var had_color := state.has_meta(COLOR_META)
	var old_color: Color = state.get_meta(COLOR_META, Color.WHITE)
	if reset and not had_color: return
	if not reset and had_color and old_color == color: return
	if undo_manager == null:
		_apply_state_color(machine, state, not reset, color)
		return
	undo_manager.create_action("Reset State Color" if reset else "Change State Color", UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply_state_color", machine, state, not reset, color)
	undo_manager.add_undo_method(self, "_apply_state_color", machine, state, had_color, old_color)
	undo_manager.commit_action()


func _apply_state_color(machine: FiniteStateMachine, state: State, has_color: bool, color: Color) -> void:
	if not is_instance_valid(machine) or not is_instance_valid(state) or not machine.owns_state(state): return
	if has_color: state.set_meta(COLOR_META, color)
	else: state.remove_meta(COLOR_META)
	state_color_changed.emit(machine, state)


func connect_states(machine: FiniteStateMachine, from: StringName, to: StringName, parallel := false, source_mode: StateTransition.SourceMode = StateTransition.SourceMode.STATE, trigger_type: StateTransition.TriggerType = StateTransition.TriggerType.MANUAL) -> StateTransition:
	if trigger_type not in StateTransition.TriggerType.values(): return null
	if (source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY or to == StateTransition.EXIT_TARGET) and not machine.has_hierarchy_boundary(): return null
	if source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY and to == StateTransition.EXIT_TARGET: return null
	if to.is_empty():
		return null
	for transition in machine.transitions:
		if not parallel and transition and transition.source_mode == source_mode and (source_mode != StateTransition.SourceMode.STATE or String(transition.from_state).to_lower() == String(from).to_lower()) and String(transition.target_key()).to_lower() == String(to).to_lower():
			return transition
	var before := capture(machine)
	var after := before.duplicate(true)
	var transition := new_transition()
	transition.source_mode = source_mode
	transition.from_state = from
	transition.to_state = to
	if to == StateTransition.EXIT_TARGET:
		transition.destination_mode = StateTransition.DestinationMode.EXIT
		transition.to_state = &""
	transition.trigger_type = trigger_type
	after.transitions.append({"resource": transition, "from": from, "to": to, "settings": _transition_settings(transition)})
	_commit("Connect States", machine, before, after)
	return transition


func new_transition() -> StateTransition:
	var transition := StateTransition.new()
	transition.set_meta(TRANSITION_COLORS.META, creation_color)
	return transition


func disconnect_states(machine: FiniteStateMachine, from: StringName, to: StringName, source_mode: StateTransition.SourceMode = StateTransition.SourceMode.STATE) -> void:
	var before := capture(machine)
	var after := before.duplicate(true)
	for index in range(after.transitions.size() - 1, -1, -1):
		var route: StateTransition = after.transitions[index].resource
		if route != null and route.source_mode == source_mode and (source_mode != StateTransition.SourceMode.STATE or String(route.from_state).to_lower() == String(from).to_lower()) and String(route.target_key()).to_lower() == String(to).to_lower():
			after.transitions.remove_at(index)
	_commit("Disconnect States", machine, before, after)


func clear_connections(machine: FiniteStateMachine) -> void:
	var before := capture(machine)
	var after := before.duplicate(true)
	after.transitions.clear()
	for data in after.nodes:
		if data.node is HierarchyState: data.exit_target = &""
	_commit("Clear Connections", machine, before, after)


func capture_positions(machine: FiniteStateMachine) -> Dictionary:
	var data := {"positions": machine.graph_positions.duplicate(), "blocks": {}}
	data.random_positions = {}
	for route in machine.transitions:
		if route == null: continue
		if route.random_routing != null:
			data.random_positions[route.random_routing] = {"present": route.random_routing.has_meta(&"fsm_editor_random_position"), "value": route.random_routing.get_meta(&"fsm_editor_random_position", Vector2.ZERO)}
		data.blocks[route] = {"present": route.has_meta(&"fsm_editor_block_position"), "value": route.get_meta(&"fsm_editor_block_position", Vector2.ZERO)}
	var container := machine.get_state_container()
	data.initial_block_present = container.has_meta(&"fsm_editor_initial_block_position")
	data.initial_block_value = container.get_meta(&"fsm_editor_initial_block_position", Vector2.ZERO)
	return data

func save_positions(machine: FiniteStateMachine, before: Dictionary, positions: Dictionary, title: String) -> void:
	var after := capture_positions(machine)
	after.positions = positions.duplicate()
	var comparison := before.duplicate(true)
	for routing in comparison.get("random_positions", {}):
		if after.random_positions.has(routing) and not comparison.random_positions[routing].present and not after.random_positions[routing].present:
			comparison.random_positions[routing].value = after.random_positions[routing].value
	if comparison == after: return
	if undo_manager == null: _apply_positions(machine, after)
	else:
		undo_manager.create_action(title, UndoRedo.MERGE_DISABLE, machine.get_state_container())
		undo_manager.add_do_method(self, "_apply_positions", machine, after)
		undo_manager.add_undo_method(self, "_apply_positions", machine, before)
		undo_manager.commit_action()

func _apply_positions(machine: FiniteStateMachine, data: Dictionary) -> void:
	if not is_instance_valid(machine): return
	machine.graph_positions = data.positions.duplicate()
	for routing in data.get("random_positions", {}):
		var position: Dictionary = data.random_positions[routing]
		if position.present: routing.set_meta(&"fsm_editor_random_position", position.value)
		else: routing.remove_meta(&"fsm_editor_random_position")
	for route: StateTransition in data.blocks:
		if not route in machine.transitions: continue
		var position: Dictionary = data.blocks[route]
		if position.present: route.set_meta(&"fsm_editor_block_position", position.value)
		else: route.remove_meta(&"fsm_editor_block_position")
	var container := machine.get_state_container()
	if data.initial_block_present: container.set_meta(&"fsm_editor_initial_block_position", data.initial_block_value)
	else: container.remove_meta(&"fsm_editor_initial_block_position")
	applied_random_positions = data.get("random_positions", {})
	positions_changed.emit(machine)
	applied_random_positions = {}


func _commit(title: String, machine: FiniteStateMachine, before: Dictionary, after: Dictionary, added: Node = null, removed: Node = null) -> void:
	if undo_manager == null:
		_apply(machine, after)
		return
	undo_manager.create_action(title, UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply", machine, after)
	undo_manager.add_undo_method(self, "_apply", machine, before)
	if added:
		undo_manager.add_do_reference(added)
	if removed:
		undo_manager.add_undo_reference(removed)
	undo_manager.commit_action()


func _apply(machine: FiniteStateMachine, data: Dictionary) -> void:
	if not is_instance_valid(machine):
		return
	applying = true
	var wanted: Array = []
	for entry in data.nodes:
		wanted.append(entry.node)
	for child in machine.get_state_container().get_children():
		if child is State and not child in wanted:
			child.remove_meta(COLOR_META)
			machine.get_state_container().remove_child(child)
	for entry in data.nodes:
		var state: State = entry.node
		if not is_instance_valid(state):
			continue
		state.name = entry.name
		if state is HierarchyState: state.exit_target = entry.get("exit_target", state.exit_target)
		if state.get_parent() == null:
			machine.get_state_container().add_child(state)
		if entry.index >= 0:
			machine.get_state_container().move_child(state, mini(entry.index, machine.get_state_container().get_child_count() - 1))
		for node in entry.owners:
			if is_instance_valid(node):
				node.owner = entry.owners[node] if is_instance_valid(entry.owners[node]) else null
		if entry.has_color:
			state.set_meta(COLOR_META, entry.color)
		else:
			state.remove_meta(COLOR_META)
		if is_instance_valid(entry.get("copy_source")):
			remap_signal_subtree(entry.copy_source, state)
	var transitions: Array[StateTransition] = []
	for entry in data.transitions:
		var transition: StateTransition = entry.resource
		if transition:
			transition.from_state = entry.from
			transition.to_state = entry.to
			SNAPSHOT.apply(transition, entry.settings)
		transitions.append(transition)
	machine.transitions = transitions
	machine.graph_positions = data.positions.duplicate()
	machine.initial_state = data.initial if is_instance_valid(data.initial) else null
	if data.get("entry_color_present", false): machine.get_state_container().set_meta(&"fsm_editor_entry_color", data.entry_color_value)
	else: machine.get_state_container().remove_meta(&"fsm_editor_entry_color")
	if data.get("initial_block_present", false): machine.get_state_container().set_meta(&"fsm_editor_initial_block_position", data.initial_block_value)
	else: machine.get_state_container().remove_meta(&"fsm_editor_initial_block_position")
	machine.update_configuration_warnings()
	applying = false
	changed.emit(machine)


func _transition_settings(transition: StateTransition) -> Dictionary:
	return SNAPSHOT.capture(transition)

func reconnect_transition(machine: FiniteStateMachine, transition: StateTransition, mode: int, from: StringName, to: StringName, endpoint: StringName = &"", action_name := "Reconnect Transition") -> bool:
	if not is_instance_valid(machine) or transition == null or not transition in machine.transitions: return false
	var moving_unconnected := endpoint == &"from" and transition.target_mode == StateTransition.TargetMode.DIRECT and transition.destination_mode == StateTransition.DestinationMode.STATE and transition.to_state.is_empty() and to.is_empty()
	if moving_unconnected:
		if not valid_transition_source(machine, transition, mode, from): return false
	elif not valid_transition_endpoints(machine, transition, mode, from, to): return false
	var before := _transition_endpoints(transition)
	var after := before.duplicate()
	if endpoint != &"to":
		after.source_mode = mode
		after.from_state = from if mode == StateTransition.SourceMode.STATE else &""
	if endpoint != &"from":
		after.target_mode = StateTransition.TargetMode.DIRECT
		after.random_routing = null
		after.destination_mode = StateTransition.DestinationMode.EXIT if to == StateTransition.EXIT_TARGET else StateTransition.DestinationMode.STATE
		after.to_state = &"" if to == StateTransition.EXIT_TARGET else to
	if before == after: return true
	if undo_manager == null:
		_apply_transition_endpoints(machine, transition, after)
	else:
		undo_manager.create_action(action_name, UndoRedo.MERGE_DISABLE, machine.get_state_container())
		undo_manager.add_do_method(self, "_apply_transition_endpoints", machine, transition, after)
		undo_manager.add_undo_method(self, "_apply_transition_endpoints", machine, transition, before)
		undo_manager.commit_action()
	return true

func _transition_endpoints(transition: StateTransition) -> Dictionary:
	return {"source_mode": transition.source_mode, "from_state": transition.from_state, "destination_mode": transition.destination_mode, "to_state": transition.to_state, "target_mode": transition.target_mode, "random_routing": transition.random_routing}


func valid_transition_source(machine: FiniteStateMachine, route: StateTransition, mode: int, from: StringName) -> bool:
	if route == null or route.trigger_type not in StateTransition.TriggerType.values(): return false
	if not is_instance_valid(machine) or mode not in [StateTransition.SourceMode.STATE, StateTransition.SourceMode.ANY_STATE, StateTransition.SourceMode.HIERARCHY_ENTRY]: return false
	var entry_source := mode == StateTransition.SourceMode.HIERARCHY_ENTRY
	if entry_source != (route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY): return false
	if entry_source and not machine.has_hierarchy_boundary(): return false
	if mode != StateTransition.SourceMode.STATE: return true
	for child in machine.get_state_container().get_children():
		if child is State and String(child.name).nocasecmp_to(String(from)) == 0: return true
	return false


func reorder_transition(machine: FiniteStateMachine, route: StateTransition, mode: int, from: StringName, index: int) -> bool:
	if not is_instance_valid(machine) or route == null or not route in machine.transitions or not valid_transition_source(machine, route, mode, from): return false
	var before: Array[StateTransition] = machine.transitions.duplicate()
	var after: Array[StateTransition] = before.duplicate()
	after.erase(route)
	var siblings: Array[StateTransition] = []
	for other in after:
		if other != null and other.source_mode == mode and (mode != StateTransition.SourceMode.STATE or String(other.from_state).nocasecmp_to(String(from)) == 0): siblings.append(other)
	var slot := clampi(index, 0, siblings.size())
	var destination := after.find(siblings[slot]) if slot < siblings.size() else (after.find(siblings[-1]) + 1 if not siblings.is_empty() else mini(before.find(route), after.size()))
	after.insert(destination, route)
	var old_source := {"source_mode": route.source_mode, "from_state": route.from_state}
	var new_source := {"source_mode": mode, "from_state": from if mode == StateTransition.SourceMode.STATE else &""}
	if before == after and old_source == new_source: return true
	var label := "Reorder Transition" if old_source == new_source else "Move Transition"
	if undo_manager == null: _apply_transition_order(machine, route, after, new_source)
	else:
		undo_manager.create_action(label, UndoRedo.MERGE_DISABLE, machine.get_state_container())
		undo_manager.add_do_method(self, "_apply_transition_order", machine, route, after, new_source)
		undo_manager.add_undo_method(self, "_apply_transition_order", machine, route, before, old_source)
		undo_manager.commit_action()
	return true


func _apply_transition_order(machine: FiniteStateMachine, route: StateTransition, order: Array[StateTransition], source: Dictionary) -> void:
	if not is_instance_valid(machine) or not route in machine.transitions: return
	route.set_block_signals(true)
	route.source_mode = source.source_mode
	route.from_state = source.from_state
	route.set_block_signals(false)
	machine.transitions = order.duplicate()
	route.emit_changed()
	machine.update_configuration_warnings()
	order_changed.emit(machine, route)
	changed.emit(machine)


func disconnect_transition_target(machine: FiniteStateMachine, transition: StateTransition, implicit_entry := false) -> void:
	if not is_instance_valid(machine) or transition == null: return
	if not transition in machine.transitions and not implicit_entry: return
	var before := _transition_endpoints(transition)
	var after := before.duplicate()
	after.to_state = &""
	after.destination_mode = StateTransition.DestinationMode.STATE
	after.target_mode = StateTransition.TargetMode.DIRECT
	after.random_routing = null
	if before == after: return
	var method := "_apply_materialized_entry_target" if implicit_entry else "_apply_transition_endpoints"
	if undo_manager == null:
		if implicit_entry: _apply_materialized_entry_target(machine, transition, after, true, machine.initial_state)
		else: _apply_transition_endpoints(machine, transition, after)
	else:
		undo_manager.create_action("Disconnect Transition Target", UndoRedo.MERGE_DISABLE, machine.get_state_container())
		if implicit_entry:
			undo_manager.add_do_method(self, method, machine, transition, after, true, machine.initial_state)
			undo_manager.add_undo_method(self, method, machine, transition, before, false, machine.initial_state)
		else:
			undo_manager.add_do_method(self, method, machine, transition, after)
			undo_manager.add_undo_method(self, method, machine, transition, before)
		undo_manager.commit_action()


func _apply_materialized_entry_target(machine: FiniteStateMachine, transition: StateTransition, values: Dictionary, authored: bool, initial: State) -> void:
	if not is_instance_valid(machine): return
	var routes: Array[StateTransition] = machine.transitions.duplicate()
	if authored:
		if not transition in routes: routes.append(transition)
		transition.remove_meta("initial_fallback")
	else:
		routes.erase(transition)
		transition.set_meta("initial_fallback", true)
	transition.set_block_signals(true)
	for property in values: transition.set(property, values[property])
	transition.set_block_signals(false)
	transition.emit_changed()
	# The virtual wire represents Initial State itself. Clear that endpoint too,
	# so an invisible fallback cannot keep executing the disconnected target.
	machine.initial_state = null if authored else initial
	machine.transitions = routes
	machine.update_configuration_warnings()
	changed.emit(machine)

func _apply_transition_endpoints(machine, transition: StateTransition, values: Dictionary) -> void:
	if not is_instance_valid(machine) or not transition in machine.transitions: return
	var source_only: bool = values.get("to_state", transition.to_state) == transition.to_state and values.get("destination_mode", transition.destination_mode) == transition.destination_mode and values.get("target_mode", transition.target_mode) == transition.target_mode and values.get("random_routing", transition.random_routing) == transition.random_routing
	transition.set_block_signals(true)
	for property in values: transition.set(property, values[property])
	transition.set_block_signals(false)
	transition.emit_changed()
	machine.update_configuration_warnings()
	endpoints_changed.emit(machine, transition, source_only)
	changed.emit(machine)


func edit_transition(machine: FiniteStateMachine, transition: StateTransition, property: StringName, value: Variant) -> void:
	if property == &"editor_end_color" and TRANSITION_COLORS.uses_exit_color(transition): return
	if property in [&"editor_color", &"editor_end_color"]:
		if transition == null or not (transition in machine.transitions or transition.get_meta("initial_fallback", false)) or (value != null and not value is Color): return
		var storage: Object = machine.get_state_container() if transition.get_meta("initial_fallback", false) else transition
		var key: StringName = &"fsm_editor_entry_color" if storage != transition and property == &"editor_color" else (TRANSITION_COLORS.END_META if property == &"editor_end_color" else TRANSITION_COLORS.META)
		var had := storage.has_meta(key)
		var previous: Variant = storage.get_meta(key, TRANSITION_COLORS.DEFAULT)
		if had and typeof(previous) == typeof(value) and previous == value: return
		if undo_manager == null:
			_apply_transition_color(machine, transition, value != null, value, key)
		else:
			undo_manager.create_action("Edit Transition End Color" if property == &"editor_end_color" else "Edit Transition Color", UndoRedo.MERGE_DISABLE, machine.get_state_container())
			undo_manager.add_do_method(self, "_apply_transition_color", machine, transition, value != null, value, key)
			undo_manager.add_undo_method(self, "_apply_transition_color", machine, transition, had, previous, key)
			undo_manager.commit_action()
		return
	if property == &"to_state":
		if not is_instance_valid(machine) or not transition in machine.transitions: return
		var before := _transition_endpoints(transition)
		var after := before.duplicate()
		after.to_state = &"" if value == StateTransition.EXIT_TARGET else StringName(value)
		after.target_mode = StateTransition.TargetMode.DIRECT
		after.random_routing = null
		after.destination_mode = StateTransition.DestinationMode.EXIT if value == StateTransition.EXIT_TARGET else StateTransition.DestinationMode.STATE
		if before == after: return
		# Match graph reconnection: notify the exact endpoint renderer on do/undo.
		# A whole-machine snapshot only emits changed, leaving existing curves stale.
		if undo_manager == null:
			_apply_transition_endpoints(machine, transition, after)
		else:
			undo_manager.create_action("Edit Transition Destination", UndoRedo.MERGE_DISABLE, machine.get_state_container())
			undo_manager.add_do_method(self, "_apply_transition_endpoints", machine, transition, after)
			undo_manager.add_undo_method(self, "_apply_transition_endpoints", machine, transition, before)
			undo_manager.commit_action()
		return
	if not transition in machine.transitions or not property in [&"source_mode", &"from_state", &"to_state", &"enabled", &"priority", &"cooldown", &"can_interrupt", &"trigger_type", &"event_name", &"duration", &"input_action", &"input_mode", &"reenter_state", &"animation_player_path", &"animation_name", &"signal_source_mode", &"signal_source_path", &"signal_name", &"watch", &"actions"]:
		return
	if property == &"cooldown" and (not is_finite(float(value)) or float(value) < 0.0): return
	var previous = transition.get(property)
	if previous == value:
		return
	if undo_manager == null:
		_apply_transition_property(machine, transition, property, value)
		return
	undo_manager.create_action("Edit Transition %s" % property, UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply_transition_property", machine, transition, property, value)
	undo_manager.add_undo_method(self, "_apply_transition_property", machine, transition, property, previous)
	undo_manager.commit_action()


func _apply_transition_color(machine: FiniteStateMachine, transition: StateTransition, had: bool, value: Variant, key: StringName = TRANSITION_COLORS.META) -> void:
	if not is_instance_valid(machine) or not (transition in machine.transitions or transition.get_meta("initial_fallback", false)): return
	var storage: Object = machine.get_state_container() if transition.get_meta("initial_fallback", false) else transition
	if storage != transition and key == TRANSITION_COLORS.META: key = &"fsm_editor_entry_color"
	if had: storage.set_meta(key, value)
	else: storage.remove_meta(key)
	if storage != transition:
		if had: transition.set_meta(TRANSITION_COLORS.META, value)
		else: transition.remove_meta(TRANSITION_COLORS.META)
	visual_changed.emit(machine, transition)


func edit_state_policy(machine: FiniteStateMachine, state: State, property: StringName, value: Variant) -> void:
	if not is_instance_valid(machine) or not machine.owns_state(state) or property not in [&"minimum_state_time", &"interruptible"]: return
	if property == &"minimum_state_time" and (not is_finite(float(value)) or float(value) < 0.0): return
	var previous: Variant = state.get(property)
	if previous == value: return
	if undo_manager == null:
		_apply_state_policy(machine, state, property, value)
		return
	undo_manager.create_action("Edit State %s" % property, UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply_state_policy", machine, state, property, value)
	undo_manager.add_undo_method(self, "_apply_state_policy", machine, state, property, previous)
	undo_manager.commit_action()


func _apply_state_policy(machine, state, property: StringName, value: Variant) -> void:
	if not is_instance_valid(machine) or not is_instance_valid(state) or not machine.owns_state(state): return
	state.set(property, value)
	machine.editor_data_changed.emit()
	changed.emit(machine)

func _apply_transition_property(machine: FiniteStateMachine, transition: StateTransition, property: StringName, value: Variant) -> void:
	if not is_instance_valid(machine) or not transition in machine.transitions:
		return
	transition.set(property, value)
	transition.emit_changed()
	machine.update_configuration_warnings()
	transition_property_changed.emit(machine, transition, property)
	changed.emit(machine)


func delete_transition(machine: FiniteStateMachine, transition: StateTransition) -> void:
	var before := capture(machine)
	var after := before.duplicate(true)
	for index in range(after.transitions.size() - 1, -1, -1):
		if after.transitions[index].resource == transition:
			after.transitions.remove_at(index)
	_commit("Delete Transition", machine, before, after)


func orphan_transitions(machine: FiniteStateMachine) -> Array[StateTransition]:
	var names: Dictionary = {}
	for child in machine.get_state_container().get_children():
		if child is State:
			names[machine._make_state_key(child.name)] = true
	var orphans: Array[StateTransition] = []
	for transition in machine.transitions:
		if transition == null or (transition.source_mode == StateTransition.SourceMode.STATE and transition.from_state.is_empty()) or (transition.destination_mode == StateTransition.DestinationMode.STATE and transition.to_state.is_empty()):
			continue
		if (transition.source_mode == StateTransition.SourceMode.STATE and not names.has(machine._make_state_key(transition.from_state))) or (transition.destination_mode == StateTransition.DestinationMode.STATE and not names.has(machine._make_state_key(transition.to_state))):
			orphans.append(transition)
	return orphans


func cleanup_orphan_transitions(machine: FiniteStateMachine) -> void:
	var orphans := orphan_transitions(machine)
	if orphans.is_empty():
		return
	var before := capture(machine)
	var after := before.duplicate(true)
	for index in range(after.transitions.size() - 1, -1, -1):
		if after.transitions[index].resource in orphans:
			after.transitions.remove_at(index)
	var names: Dictionary = {}
	for entry in after.nodes:
		names[machine._make_state_key(entry.name)] = true
	for key in after.positions.keys():
		if not names.has(machine._make_state_key(StringName(key))):
			after.positions.erase(key)
	if not machine.owns_state(after.initial):
		after.initial = null
	_commit("Remove Orphan Transitions", machine, before, after)


func _comparison_settings(condition: TransitionCondition) -> Dictionary:
	return SNAPSHOT.comparison(condition)


func edit_comparison(machine: FiniteStateMachine, transition: StateTransition, condition: TransitionCondition, property: StringName, value: Variant) -> void:
	if not transition in machine.transitions or (condition != transition.watch and not CONDITION_LOGIC.contains(transition, condition)) or not property in _comparison_settings(condition):
		return
	var previous = condition.get(property)
	if typeof(previous) == typeof(value) and previous == value:
		return
	if undo_manager == null:
		_apply_comparison(machine, condition, property, value)
		return
	undo_manager.create_action("Edit Condition %s" % property, UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply_comparison", machine, condition, property, value)
	undo_manager.add_undo_method(self, "_apply_comparison", machine, condition, property, previous)
	undo_manager.commit_action()


func _apply_comparison(machine: FiniteStateMachine, condition: TransitionCondition, property: StringName, value: Variant) -> void:
	if is_instance_valid(machine):
		condition.set(property, value)
		machine.update_configuration_warnings()
		changed.emit(machine)


func add_condition(machine: FiniteStateMachine, transition: StateTransition) -> void:
	if transition.condition_group != null:
		condition_tree_action(machine, transition, transition.condition_group, "add_condition")
		return
	var after: Array[TransitionCondition] = transition.conditions.duplicate()
	after.append(TransitionCondition.new())
	_change_conditions(machine, transition, after, "Add Condition")


func remove_condition(machine: FiniteStateMachine, transition: StateTransition, condition: TransitionCondition) -> void:
	var after: Array[TransitionCondition] = transition.conditions.duplicate()
	after.erase(condition)
	_change_conditions(machine, transition, after, "Remove Condition")


func _change_conditions(machine: FiniteStateMachine, transition: StateTransition, after: Array[TransitionCondition], title: String) -> void:
	if not transition in machine.transitions:
		return
	var before := transition.conditions.duplicate()
	if undo_manager == null:
		_apply_transition_property(machine, transition, &"conditions", after)
		return
	undo_manager.create_action(title, UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply_transition_property", machine, transition, &"conditions", after)
	undo_manager.add_undo_method(self, "_apply_transition_property", machine, transition, &"conditions", before)
	undo_manager.commit_action()


func _root_group(transition: StateTransition) -> TransitionConditionGroup:
	var root := TransitionConditionGroup.new()
	var children: Array[Resource] = []
	children.assign(transition.conditions)
	if transition.condition_group != null: children.append(transition.condition_group)
	root.children = children
	return root


func edit_condition_node(machine: FiniteStateMachine, transition: StateTransition, node: Resource, property: StringName, value: Variant) -> void:
	if not transition in machine.transitions or property not in [&"enabled", &"negated", &"operator"]: return
	if node == null:
		var root := _root_group(transition)
		root.set(property, value)
		_commit_expression("Edit Root Condition Group", machine, transition, root, [])
		return
	if not CONDITION_LOGIC.contains(transition, node): return
	if node is TransitionCondition and property == &"operator": return
	var before: Variant = node.get(property)
	if before == value: return
	if undo_manager == null:
		_apply_condition_node(machine, transition, node, property, value)
		return
	undo_manager.create_action("Edit Condition " + String(property), UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply_condition_node", machine, transition, node, property, value)
	undo_manager.add_undo_method(self, "_apply_condition_node", machine, transition, node, property, before)
	undo_manager.commit_action()


func _apply_condition_node(machine: FiniteStateMachine, transition: StateTransition, node: Resource, property: StringName, value: Variant) -> void:
	node.set(property, value)
	transition.emit_changed()
	machine.update_configuration_warnings()
	changed.emit(machine)


func condition_tree_action(machine: FiniteStateMachine, transition: StateTransition, parent: TransitionConditionGroup, action: String, node: Resource = null) -> void:
	if not transition in machine.transitions: return
	if parent == null and node == transition.condition_group and node != null and action == "delete":
		_commit_expression("Remove Condition Group", machine, transition, null, transition.conditions.duplicate())
		return
	if parent == null and transition.condition_group == null and action not in ["add_group", "add_any_group"]:
		if action == "add_condition":
			add_condition(machine, transition)
		elif node is TransitionCondition:
			var after: Array[TransitionCondition] = transition.conditions.duplicate()
			var index := after.find(node)
			if index < 0: return
			if action == "delete": after.remove_at(index)
			elif action in ["up", "down"]:
				var next := index + (-1 if action == "up" else 1)
				if next < 0 or next >= after.size(): return
				after.remove_at(index)
				after.insert(next, node)
			_change_conditions(machine, transition, after, "Edit Conditions")
		return
	var root := transition.condition_group
	var created := root == null or (parent == null and (not transition.conditions.is_empty() or root.operator != TransitionConditionGroup.Operator.AND or root.negated or not root.enabled))
	if created: root = _root_group(transition)
	if parent == null: parent = root
	if not created and not CONDITION_LOGIC.contains(transition, parent): return
	var children: Array[Resource] = parent.children.duplicate()
	match action:
		"add_condition": children.append(TransitionCondition.new())
		"add_group": children.append(TransitionConditionGroup.new())
		"add_any_group":
			var group := TransitionConditionGroup.new()
			group.operator = TransitionConditionGroup.Operator.OR
			children.append(group)
		"delete":
			children.erase(node)
		"up", "down":
			var index := children.find(node)
			var next := index + (-1 if action == "up" else 1)
			if index < 0 or next < 0 or next >= children.size(): return
			children.remove_at(index)
			children.insert(next, node)
		_: return
	if created:
		parent.children = children
		_commit_expression("Create Condition Group", machine, transition, root, [])
	elif undo_manager == null:
		_apply_condition_node(machine, transition, parent, &"children", children)
	else:
		undo_manager.create_action("Edit Condition Tree", UndoRedo.MERGE_DISABLE, machine.get_state_container())
		undo_manager.add_do_method(self, "_apply_condition_node", machine, transition, parent, &"children", children)
		undo_manager.add_undo_method(self, "_apply_condition_node", machine, transition, parent, &"children", parent.children.duplicate())
		undo_manager.commit_action()


func _commit_expression(title: String, machine: FiniteStateMachine, transition: StateTransition, root: TransitionConditionGroup, legacy: Array[TransitionCondition]) -> void:
	if undo_manager == null:
		_apply_expression(machine, transition, root, legacy)
		return
	undo_manager.create_action(title, UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply_expression", machine, transition, root, legacy)
	undo_manager.add_undo_method(self, "_apply_expression", machine, transition, transition.condition_group, transition.conditions.duplicate())
	undo_manager.commit_action()


func _apply_expression(machine: FiniteStateMachine, transition: StateTransition, root: TransitionConditionGroup, legacy: Array[TransitionCondition]) -> void:
	transition.condition_group = root
	transition.conditions = legacy
	machine.update_configuration_warnings()
	changed.emit(machine)


func add_action(machine: FiniteStateMachine, transition: StateTransition, action_type: int) -> TransitionAction:
	if not transition in machine.transitions:
		return null
	var action := TransitionAction.new()
	action.timing = TransitionAction.Timing.AFTER_EXIT
	action.action_type = action_type
	action.value = 0 if action_type == TransitionAction.ActionType.ADD_VALUE else false
	var after: Array[Resource] = transition.actions.duplicate()
	after.append(action)
	_change_actions(machine, transition, after, "Add Transition Effect")
	return action


func remove_action(machine: FiniteStateMachine, transition: StateTransition, action: TransitionAction) -> void:
	var after: Array[Resource] = transition.actions.duplicate()
	after.erase(action)
	_change_actions(machine, transition, after, "Remove Transition Effect")


func move_action(machine: FiniteStateMachine, transition: StateTransition, action: TransitionAction, direction: int) -> void:
	var after: Array[Resource] = transition.actions.duplicate()
	var index := after.find(action)
	var next := index + direction
	while next >= 0 and next < after.size() and (not after[next] is TransitionAction or after[next].timing != action.timing):
		next += direction
	if index < 0 or next < 0 or next >= after.size():
		return
	after.remove_at(index)
	after.insert(next, action)
	_change_actions(machine, transition, after, "Move Transition Effect")


func edit_action(machine: FiniteStateMachine, transition: StateTransition, action: TransitionAction, property: StringName, value: Variant) -> void:
	if not transition in machine.transitions or not action in transition.actions or property not in [&"enabled", &"timing", &"action_type", &"target_mode", &"target_path", &"property_path", &"value", &"method_name", &"signal_name"]:
		return
	var previous = action.get(property)
	if typeof(previous) == typeof(value) and previous == value:
		return
	if undo_manager == null:
		_apply_action_property(machine, action, property, value)
		return
	undo_manager.create_action("Edit Transition Effect", UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply_action_property", machine, action, property, value)
	undo_manager.add_undo_method(self, "_apply_action_property", machine, action, property, previous)
	undo_manager.commit_action()


func _change_actions(machine: FiniteStateMachine, transition: StateTransition, after: Array[Resource], title: String) -> void:
	if not transition in machine.transitions:
		return
	var before := transition.actions.duplicate()
	if undo_manager == null:
		_apply_transition_property(machine, transition, &"actions", after)
		return
	undo_manager.create_action(title, UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply_transition_property", machine, transition, &"actions", after)
	undo_manager.add_undo_method(self, "_apply_transition_property", machine, transition, &"actions", before)
	undo_manager.commit_action()


func _apply_action_property(machine: FiniteStateMachine, action: TransitionAction, property: StringName, value: Variant) -> void:
	if not is_instance_valid(machine):
		return
	action.set(property, value)
	machine.update_configuration_warnings()
	changed.emit(machine)


func edit_typed_row(machine: FiniteStateMachine, transition: StateTransition, resource: Resource, values: Dictionary) -> void:
	if not transition in machine.transitions: return
	var fields: Dictionary
	if resource is TransitionCondition:
		if resource != transition.watch and not CONDITION_LOGIC.contains(transition, resource): return
		fields = SNAPSHOT.comparison(resource)
	elif resource is TransitionAction and resource in transition.actions:
		for field in [&"enabled", &"timing", &"action_type", &"target_mode", &"target_path", &"property_path", &"value", &"method_name", &"signal_name"]:
			fields[field] = resource.get(field)
	else: return
	var before := {}
	var after := {}
	for field in values:
		if not fields.has(field): return
		var previous: Variant = resource.get(field)
		if typeof(previous) != typeof(values[field]) or previous != values[field]:
			before[field] = previous
			after[field] = values[field]
	if after.is_empty(): return
	if undo_manager == null:
		_apply_typed_row(machine, resource, after)
		return
	undo_manager.create_action("Edit Property Expression", UndoRedo.MERGE_DISABLE, machine.get_state_container())
	undo_manager.add_do_method(self, "_apply_typed_row", machine, resource, after)
	undo_manager.add_undo_method(self, "_apply_typed_row", machine, resource, before)
	undo_manager.commit_action()


func _apply_typed_row(machine: FiniteStateMachine, resource: Resource, values: Dictionary) -> void:
	if not is_instance_valid(machine) or not is_instance_valid(resource): return
	# Resource setters emit changed individually; observers must see only the
	# completed target/property/operator/value tuple, including during Undo/Redo.
	var blocked := resource.is_blocking_signals()
	resource.set_block_signals(true)
	for field in values: resource.set(field, values[field])
	resource.set_block_signals(blocked)
	if not blocked: resource.emit_changed()
	machine.update_configuration_warnings()
	changed.emit(machine)

func commit_draft(machine: FiniteStateMachine, route: StateTransition, before_route: StateTransition = null) -> bool:
	if not is_instance_valid(machine) or route == null or route in machine.transitions: return false
	if route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY and route.trigger_type != StateTransition.TriggerType.MANUAL: return false
	if not valid_transition_endpoints(machine, route, route.source_mode, route.from_state, route.target_key()): return false
	var before := capture(machine)
	var after := before.duplicate(true)
	var index: int = after.transitions.size()
	for i in after.transitions.size():
		if after.transitions[i].resource == before_route: index = i; break
	after.transitions.insert(index, {"resource": route, "from": route.from_state, "to": route.to_state, "settings": _transition_settings(route)})
	_commit("Create Transition Block", machine, before, after)
	return true


func author_incomplete_transition(machine: FiniteStateMachine, route: StateTransition, before_route: StateTransition = null) -> bool:
	if not is_instance_valid(machine) or route == null or route in machine.transitions: return false
	if route.target_mode != StateTransition.TargetMode.DIRECT or route.destination_mode != StateTransition.DestinationMode.STATE or not route.to_state.is_empty(): return false
	if not valid_transition_source(machine, route, route.source_mode, route.from_state): return false
	if route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY and route.trigger_type != StateTransition.TriggerType.MANUAL: return false
	var before := capture(machine)
	var after := before.duplicate(true)
	var index: int = after.transitions.size()
	for i in after.transitions.size():
		if after.transitions[i].resource == before_route: index = i; break
	after.transitions.insert(index, {"resource": route, "from": route.from_state, "to": &"", "settings": _transition_settings(route)})
	_commit("Create Incomplete Transition", machine, before, after)
	return route in machine.transitions

func set_random_routing(machine: FiniteStateMachine, route: StateTransition, routing: StateRandomRouting) -> void:
	var before := {"target_mode": route.target_mode, "random_routing": route.random_routing, "to_state": route.to_state, "destination_mode": route.destination_mode}
	var after := {"target_mode": StateTransition.TargetMode.RANDOM if routing != null else StateTransition.TargetMode.DIRECT, "random_routing": routing, "to_state": &"", "destination_mode": StateTransition.DestinationMode.STATE}
	if undo_manager == null: _apply_transition_endpoints(machine, route, after)
	else:
		undo_manager.create_action("Set Random Routing", UndoRedo.MERGE_DISABLE, machine.get_state_container())
		undo_manager.add_do_method(self, "_apply_transition_endpoints", machine, route, after)
		undo_manager.add_undo_method(self, "_apply_transition_endpoints", machine, route, before)
		undo_manager.commit_action()

func edit_random_routing(machine: FiniteStateMachine, route: StateTransition, command: String, index: int, value: Variant) -> void:
	if route.random_routing == null: return
	var before := _routing_values(route.random_routing)
	var after := before.duplicate(true)
	match command:
		"mode": after.mode = value
		"add": after.branches.append({"resource": StateRandomTarget.new(), "target": &"", "percentage": 0.0})
		"remove": after.branches.remove_at(index)
		"percentage": after.branches[index].percentage = value
		"target": after.branches[index].target = value
	if undo_manager == null: _apply_routing_values(machine, route, after)
	else:
		undo_manager.create_action("Edit Random %s" % command, UndoRedo.MERGE_DISABLE, machine.get_state_container())
		undo_manager.add_do_method(self, "_apply_routing_values", machine, route, after)
		undo_manager.add_undo_method(self, "_apply_routing_values", machine, route, before)
		undo_manager.commit_action()

func _routing_values(routing: StateRandomRouting) -> Dictionary:
	var values := {"mode": routing.mode, "branches": []}
	for branch in routing.branches:
		values.branches.append({"resource": branch, "target": branch.target_state if branch != null else &"", "percentage": branch.percentage if branch != null else 0.0, "start_present": branch.has_meta(TRANSITION_COLORS.META) if branch != null else false, "start_value": branch.get_meta(TRANSITION_COLORS.META, TRANSITION_COLORS.DEFAULT) if branch != null else TRANSITION_COLORS.DEFAULT, "end_present": branch.has_meta(TRANSITION_COLORS.END_META) if branch != null else false, "end_value": branch.get_meta(TRANSITION_COLORS.END_META, Color.WHITE) if branch != null else Color.WHITE})
	return values

func _apply_routing_values(machine: FiniteStateMachine, route: StateTransition, values: Dictionary) -> void:
	if not route in machine.transitions or route.random_routing == null: return
	var branches: Array[StateRandomTarget] = []
	for item in values.branches:
		if item.resource == null: continue
		item.resource.target_state = item.target
		item.resource.percentage = item.percentage
		if item.get("start_present", false): item.resource.set_meta(TRANSITION_COLORS.META, item.start_value)
		else: item.resource.remove_meta(TRANSITION_COLORS.META)
		if item.get("end_present", false): item.resource.set_meta(TRANSITION_COLORS.END_META, item.end_value)
		else: item.resource.remove_meta(TRANSITION_COLORS.END_META)
		branches.append(item.resource)
	route.random_routing.mode = values.mode
	route.random_routing.branches = branches
	route.emit_changed()
	machine.update_configuration_warnings()
	changed.emit(machine)

func create_machine(parent: Node, owner: Node) -> FiniteStateMachine:
	if not is_instance_valid(parent) or not is_instance_valid(owner) or not parent.is_inside_tree(): return null
	if parent is State or parent is FiniteStateMachine or (owner != parent and not owner.is_ancestor_of(parent)): return null
	var ancestor := parent.get_parent()
	while ancestor != null:
		if ancestor is State or ancestor is FiniteStateMachine: return null
		ancestor = ancestor.get_parent()
	var machine := FiniteStateMachine.new()
	machine.name = "FiniteStateMachine"
	machine.actor = parent
	if undo_manager == null:
		_apply_machine(parent, machine, owner, true)
	else:
		undo_manager.create_action("Create Finite State Machine", UndoRedo.MERGE_DISABLE, parent)
		undo_manager.add_do_method(self, "_apply_machine", parent, machine, owner, true)
		undo_manager.add_undo_method(self, "_apply_machine", parent, machine, owner, false)
		undo_manager.add_do_reference(machine)
		undo_manager.commit_action()
	return machine

func _apply_machine(parent: Node, machine: FiniteStateMachine, owner: Node, attach: bool) -> void:
	if not is_instance_valid(parent) or not is_instance_valid(machine): return
	if attach:
		parent.add_child(machine, true)
		machine.owner = owner
	else:
		parent.remove_child(machine)
	changed.emit(machine)
	if attach: machine_created.emit(machine)

func set_boundary_color(machine: FiniteStateMachine, entry: bool, value: Variant) -> void:
	var storage := machine.get_state_container()
	var key := &"fsm_editor_boundary_entry_color" if entry else &"fsm_editor_exit_color"
	var before: Variant = storage.get_meta(key) if storage.has_meta(key) else null
	if undo_manager == null: _apply_boundary_color(machine, key, value)
	else:
		undo_manager.create_action("Change Boundary Color", UndoRedo.MERGE_DISABLE, storage)
		undo_manager.add_do_method(self, "_apply_boundary_color", machine, key, value)
		undo_manager.add_undo_method(self, "_apply_boundary_color", machine, key, before)
		undo_manager.commit_action()

func _apply_boundary_color(machine: FiniteStateMachine, key: StringName, value: Variant) -> void:
	if not is_instance_valid(machine): return
	if value == null: machine.get_state_container().remove_meta(key)
	else: machine.get_state_container().set_meta(key, value)
	visual_changed.emit(machine, null)

func valid_transition_endpoints(machine: FiniteStateMachine, transition: StateTransition, mode: int, from: StringName, to: StringName) -> bool:
	if transition == null or transition.trigger_type not in StateTransition.TriggerType.values(): return false
	if not is_instance_valid(machine): return false
	if mode not in [StateTransition.SourceMode.STATE, StateTransition.SourceMode.ANY_STATE, StateTransition.SourceMode.HIERARCHY_ENTRY]: return false
	var entry_source := mode == StateTransition.SourceMode.HIERARCHY_ENTRY
	if entry_source and not machine.has_hierarchy_boundary(): return false
	var source: State
	var target: State
	for state in machine.get_state_container().get_children():
		if not state is State: continue
		if String(state.name).nocasecmp_to(String(from)) == 0: source = state
		if String(state.name).nocasecmp_to(String(to)) == 0: target = state
	if mode == StateTransition.SourceMode.STATE and source == null: return false
	if to == StateTransition.EXIT_TARGET:
		if entry_source or not machine.has_hierarchy_boundary(): return false
	elif target == null and not (transition.target_mode == StateTransition.TargetMode.RANDOM and to == &"@random"): return false
	# Moving across ENTRY would change trigger/effect semantics, not just an endpoint.
	if entry_source != (transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY): return false
	return true
