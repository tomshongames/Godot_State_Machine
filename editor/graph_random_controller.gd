@tool
extends RefCounted
var random_blocks := {}
var random_drafts := {}
var random_branch_connections := {}
var random_visual_update := false
var random_visual_synced := false
var selected_random: StateRandomRouting
var selected_random_branch: StateRandomTarget
var routing_inspector: VBoxContainer
var random_color_edit: Dictionary = {}
var random_router_color_edit: Dictionary = {}
## Random visual authoring: drafts, branches, router inspector and color transactions.
## Owns Random maps, draft session state, selection and inspector controls.
## Per-call panel context supplies graph/index/actions; actions own Resource edits.
## No retained panel reference, deferred work or independent lifecycle.

const BLOCK := preload("res://addons/state_machine/editor/transition_graph_block.gd")
const RANDOM_BLOCK := preload("res://addons/state_machine/editor/random_graph_block.gd")
const NODE_SCRIPT := preload("res://addons/state_machine/editor/state_graph_node.gd")
const APPEARANCE := preload("res://addons/state_machine/editor/appearance_preferences.gd")
const TRANSITION_COLORS := preload("res://addons/state_machine/editor/transition_colors.gd")

func _make_random_block(panel, routing: StateRandomRouting, route: StateTransition, position: Vector2) -> GraphNode:
	var block := RANDOM_BLOCK.new()
	block.name = "__FSM_RANDOM_%s" % routing.get_instance_id()
	panel.graph.add_child(block)
	block.setup(routing, route)
	block.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: panel.selected_connection_edge.clear())
	block.position_offset = routing.get_meta(RANDOM_BLOCK.POSITION_META, position)
	block.edited.connect(panel._random_edited)
	block.position_offset_changed.connect(panel._on_node_position_changed.bind(block, panel.graph_revision))
	random_blocks[routing] = block
	block.set_meta("routing_signature", str([routing.mode, panel._routing_signature(routing)]))
	if not random_drafts.has(routing): random_drafts[routing] = {"machine": weakref(panel.state_machine), "position": block.position_offset}
	return block

func _random_block_gui_input(panel, event: InputEvent, block: GraphNode) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	panel._random_block_body_click(block, panel.graph.get_global_mouse_position())

func _random_block_body_click(panel, block: GraphNode, global_position: Vector2) -> void:
	if not is_instance_valid(block) or not block is RANDOM_BLOCK: return
	panel.selected_connection_edge.clear()
	var graph_position: Vector2 = global_position - panel.graph.global_position
	for port in block.get_input_port_count():
		if graph_position.distance_to(block.position + block.get_input_port_position(port) * panel.graph.zoom) <= 18.0: return
	for port in block.get_output_port_count():
		if graph_position.distance_to(block.position + block.get_output_port_position(port) * panel.graph.zoom) <= 18.0: return
	for control in block.find_children("*", "Control", true, false):
		if not control.get_global_rect().has_point(global_position): continue
		if control is BaseButton or control is Range or control is LineEdit: return
	panel._select_random(block.routing)

func _restore_random_blocks(panel) -> void:
	for route in panel.state_machine.transitions:
		if route == null or route.target_mode != StateTransition.TargetMode.RANDOM or route.random_routing == null: continue
		if not random_blocks.has(route.random_routing): panel._make_random_block(route.random_routing, route, Vector2(450, 100))
	for routing in random_drafts.keys():
		var data: Dictionary = random_drafts[routing]
		if not is_instance_valid(data.machine.get_ref()): random_drafts.erase(routing); continue
		if data.machine.get_ref() == panel.state_machine and not random_blocks.has(routing): panel._make_random_block(routing, null, data.position)
	for block in random_blocks.values(): panel._sync_random_branches(block)


func _sync_random_branches(panel, block: GraphNode) -> void:
	var desired := {}
	for i in block.routing.branches.size():
		var branch: StateRandomTarget = block.routing.branches[i]
		if branch == null: continue
		var target: StringName = panel._graph_target(branch.target_state)
		if target.is_empty(): continue
		var key: String = panel._connection_key(block.name, i, target, 0)
		desired[key] = {"routing": block.routing, "branch": branch, "from_node": block.name, "from_port": i, "to_node": target, "to_port": 0}
	for key in random_branch_connections.keys():
		var edge: Dictionary = random_branch_connections[key]
		if edge.routing != block.routing or desired.has(key): continue
		panel.graph.disconnect_node(edge.from_node, edge.from_port, edge.to_node, edge.to_port)
		random_branch_connections.erase(key)
		panel.connection_transitions.erase(key)
	for key in desired:
		var edge: Dictionary = desired[key]
		if not panel.graph.is_node_connected(edge.from_node, edge.from_port, edge.to_node, edge.to_port): panel.graph.connect_node(edge.from_node, edge.from_port, edge.to_node, edge.to_port)
		random_branch_connections[key] = edge
		if block.transition == null: panel.connection_transitions.erase(key)
		else: panel.connection_transitions[key] = block.transition
	panel.graph.queue_redraw()


func _random_endpoint_changed(panel, machine: FiniteStateMachine, route: StateTransition, source_only: bool) -> void:
	if machine != panel.state_machine or source_only or not panel.transition_blocks.has(route): return
	var old: Dictionary = panel.transition_connections.get(route, {})
	var target: Node = panel.graph.get_node_or_null(NodePath(old.get("to_node", "")))
	if route.target_mode == StateTransition.TargetMode.RANDOM or target is RANDOM_BLOCK:
		random_visual_synced = true


func _sync_random_visuals(panel) -> void:
	panel.graph_index.rebuild(panel.state_machine)
	for node in panel.graph.get_children():
		if node is NODE_SCRIPT:
			panel.graph_index.register_node(node.state, node)
			node.set_outgoing_transitions(panel.graph_index.routes_for(node.state), panel.editor_interface)
	for route in panel.state_machine.transitions:
		if route != null and route.target_mode == StateTransition.TargetMode.RANDOM and route.random_routing != null and not random_blocks.has(route.random_routing):
			panel._make_random_block(route.random_routing, route, Vector2(450, 100))
	for routing in random_blocks:
		var block: GraphNode = random_blocks[routing]
		var owner_route: StateTransition
		for route in panel.state_machine.transitions:
			if route != null and route.target_mode == StateTransition.TargetMode.RANDOM and route.random_routing == routing: owner_route = route; break
		block.transition = owner_route
		block.draft = owner_route == null
		block.title = "RANDOM · Draft" if block.draft else "RANDOM"
		var signature: String = str([routing.mode, panel._routing_signature(routing)])
		if block.get_meta("routing_signature", "") != signature:
			block.setup(routing, owner_route)
			block.set_meta("routing_signature", signature)
		panel._sync_random_branches(block)
	for route in panel.state_machine.transitions:
		if route == null or not panel.transition_blocks.has(route): continue
		var block: GraphNode = panel.transition_blocks[route]
		block.draft = false
		var target: StringName = panel._route_target(route)
		var old: Dictionary = panel.transition_connections.get(route, {})
		if not old.is_empty() and old.to_node != target:
			panel.graph.disconnect_node(old.from_node, old.from_port, old.to_node, old.to_port)
			panel.connection_transitions.erase(panel._connection_key(old.from_node, old.from_port, old.to_node, old.to_port))
			panel.transition_connections.erase(route)
		if not target.is_empty() and not panel.transition_connections.has(route):
			var edge: Dictionary = panel._connect_block_segment(block.name, target, route)
			edge.source_edge = {}
			edge.source_node = panel._route_source(route)
			panel.transition_connections[route] = edge
		block.refresh_summary()
	panel._dock_blocks()
	panel.transitions_panel.rebuild(panel.state_machine)
	panel.transition_editor.refresh()


func _disconnect_random_input(panel, block: GraphNode) -> void:
	if block.transition != null: panel.actions.set_random_routing(panel.state_machine, block.transition, null)

func _connect_random(panel, source: GraphNode, from_port: int, target: GraphNode, to_port: int) -> void:
	var request: Dictionary = panel.reconnect.duplicate()
	panel._cancel_connection_drag()
	if not request.is_empty():
		if not request.target or source == null or request.edge.from_node != source.name or request.edge.from_port != from_port: return
		if source.transition != request.route: return
	if source is BLOCK and target is RANDOM_BLOCK:
		if from_port != 0 or to_port != 0 or target.transition != null and target.transition != source.transition: return
		var route: StateTransition = source.transition
		target.routing.set_meta(RANDOM_BLOCK.POSITION_META, target.position_offset)
		if source.draft:
			if source.draft_source.is_empty(): return
			var origin: GraphNode = panel.graph.get_node(NodePath(source.draft_source))
			route.source_mode = panel._source_mode(origin)
			route.from_state = origin.state.name if origin.state != null else &""
			route.target_mode = StateTransition.TargetMode.RANDOM
			route.random_routing = target.routing
			panel.drafts.erase(route)
			random_visual_update = true
			if not panel.actions.commit_draft(panel.state_machine, route): panel.refresh()
			random_visual_update = false
		else:
			random_visual_update = true
			panel.actions.set_random_routing(panel.state_machine, route, target.routing)
			random_visual_update = false
	elif source is RANDOM_BLOCK and target != null and (target.state != null or target == panel.exit_node):
		if from_port < 0 or from_port >= source.routing.branches.size() or to_port != 0: return
		if target == panel.exit_node and source.transition != null and source.transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: return
		panel._random_edited(source, "target", from_port, panel._target_name(target))

func _random_edited(panel, block: GraphNode, command: String, index: int, value: Variant) -> void:
	var routing: StateRandomRouting = block.routing
	if block.transition == null:
		var before: Dictionary = panel.actions._routing_values(routing)
		panel._apply_draft_routing(routing, command, index, value)
		var after: Dictionary = panel.actions._routing_values(routing)
		if panel.actions.undo_manager == null: panel._sync_random_visuals()
		else:
			panel.actions.undo_manager.create_action("Edit Random Draft", UndoRedo.MERGE_DISABLE, panel.state_machine.get_state_container())
			panel.actions.undo_manager.add_do_method(panel, "_apply_draft_routing_values", routing, after)
			panel.actions.undo_manager.add_undo_method(panel, "_apply_draft_routing_values", routing, before)
			panel.actions.undo_manager.commit_action()
	else:
		random_visual_update = true
		panel.actions.edit_random_routing(panel.state_machine, block.transition, command, index, value)
		random_visual_update = false
	if selected_random == routing:
		if selected_random_branch != null and routing.branches.has(selected_random_branch):
			for edge in random_branch_connections.values():
				if edge.branch == selected_random_branch:
					panel._select_random_branch(routing, selected_random_branch, edge)
					return
		panel._select_random(routing)

func _begin_random_branch_color_edit(panel, branch: StateRandomTarget, picker: ColorPickerButton, meta_key: StringName = TRANSITION_COLORS.META) -> void:
	if branch == null: return
	random_color_edit = {
		"branch": branch,
		"meta_key": meta_key,
		"had_color": branch.has_meta(meta_key),
		"previous": branch.get_meta(meta_key) if branch.has_meta(meta_key) else null,
		"picker": picker
	}

func _begin_random_router_color_edit(panel, routing: StateRandomRouting, picker: ColorPickerButton) -> void:
	if routing == null: return
	random_router_color_edit = {
		"routing": routing,
		"had_color": routing.has_meta(&"fsm_editor_random_color"),
		"previous": routing.get_meta(&"fsm_editor_random_color") if routing.has_meta(&"fsm_editor_random_color") else null,
		"picker": picker
	}

func _preview_random_router_color(panel, color: Color, routing: StateRandomRouting) -> void:
	if random_router_color_edit.get("routing") != routing: return
	var block: GraphNode = random_blocks.get(routing)
	if is_instance_valid(block):
		block.apply_router_appearance(
			APPEARANCE.get_color(panel._editor_settings(), "default_random"),
			APPEARANCE.get_color(panel._editor_settings(), "selected_accent"),
			block.selected,
			color
		)

func _finish_random_router_color_edit(panel, routing: StateRandomRouting, picker: ColorPickerButton) -> void:
	if random_router_color_edit.get("routing") != routing: return
	var edit: Dictionary = random_router_color_edit
	random_router_color_edit = {}
	var color: Color = picker.color
	if (edit.had_color and color == edit.previous) or (not edit.had_color and color == APPEARANCE.get_color(panel._editor_settings(), "default_random")):
		panel._apply_random_router_appearance(routing)
		return
	if panel.actions.undo_manager == null: panel._apply_random_router_color(routing, color)
	else:
		panel.actions.undo_manager.create_action("Change Random Color", UndoRedo.MERGE_DISABLE, panel.state_machine.get_state_container())
		panel.actions.undo_manager.add_do_method(panel, "_apply_random_router_color", routing, color)
		panel.actions.undo_manager.add_undo_method(panel, "_apply_random_router_color", routing, edit.previous if edit.had_color else null)
		panel.actions.undo_manager.commit_action()

func _set_random_router_color(panel, routing: StateRandomRouting, color: Variant) -> void:
	if routing == null or not is_instance_valid(panel.state_machine): return
	var had := routing.has_meta(&"fsm_editor_random_color")
	var previous: Variant = routing.get_meta(&"fsm_editor_random_color") if had else null
	if color == null and not had or color is Color and had and color == previous: return
	if panel.actions.undo_manager == null: panel._apply_random_router_color(routing, color)
	else:
		panel.actions.undo_manager.create_action("Reset Random Color" if color == null else "Change Random Color", UndoRedo.MERGE_DISABLE, panel.state_machine.get_state_container())
		panel.actions.undo_manager.add_do_method(panel, "_apply_random_router_color", routing, color)
		panel.actions.undo_manager.add_undo_method(panel, "_apply_random_router_color", routing, previous)
		panel.actions.undo_manager.commit_action()

func _apply_random_router_color(panel, routing: StateRandomRouting, color: Variant) -> void:
	if routing == null: return
	if color == null: routing.remove_meta(&"fsm_editor_random_color")
	else: routing.set_meta(&"fsm_editor_random_color", color)
	panel._apply_random_router_appearance(routing)
	if is_instance_valid(panel.editor_interface): panel.editor_interface.mark_scene_as_unsaved()

func _apply_random_router_appearance(panel, routing: StateRandomRouting) -> void:
	var block: GraphNode = random_blocks.get(routing)
	if not is_instance_valid(block) or not is_instance_valid(panel.editor_interface): return
	var color: Color = routing.get_meta(&"fsm_editor_random_color", APPEARANCE.get_color(panel._editor_settings(), "default_random"))
	block.apply_router_appearance(
		APPEARANCE.get_color(panel._editor_settings(), "default_random"),
		APPEARANCE.get_color(panel._editor_settings(), "selected_accent"),
		block.selected,
		color
	)
	panel.graph.queue_redraw()
	if selected_random == routing and is_instance_valid(routing_inspector):
		for row in routing_inspector.get_children():
			panel._sync_random_router_inspector(routing, color)

func _sync_random_router_inspector(panel, routing: StateRandomRouting, color: Color) -> void:
	if not is_instance_valid(routing_inspector): return
	for row in routing_inspector.get_children():
		if not row.has_meta(&"random_router_color_picker") or row.get_meta(&"random_router_color_picker") != routing: continue
		var picker: ColorPickerButton = row.get_meta(&"picker")
		picker.color = color
		for control in row.get_children():
			if control is Button and control.text == "Reset": control.disabled = not routing.has_meta(&"fsm_editor_random_color")

func _preview_random_branch_color(panel, color: Color, branch: StateRandomTarget, meta_key: StringName = TRANSITION_COLORS.META) -> void:
	if random_color_edit.get("branch") != branch or random_color_edit.get("meta_key", TRANSITION_COLORS.META) != meta_key: return
	panel._apply_random_branch_color(branch, color, meta_key)

func _finish_random_branch_color_edit(panel, branch: StateRandomTarget, picker: ColorPickerButton, meta_key: StringName = TRANSITION_COLORS.META) -> void:
	if random_color_edit.get("branch") != branch or random_color_edit.get("meta_key", TRANSITION_COLORS.META) != meta_key: return
	var edit: Dictionary = random_color_edit
	random_color_edit = {}
	if not is_instance_valid(panel.state_machine): return
	var current: Color = picker.color
	if edit.had_color: branch.set_meta(meta_key, edit.previous)
	else: branch.remove_meta(meta_key)
	panel._apply_random_branch_color(branch, edit.previous if edit.had_color else null, meta_key)
	var default_color: Color = TRANSITION_COLORS.default_color if meta_key == TRANSITION_COLORS.META else panel._automatic_end_color(panel._edge_for_random_branch(branch))
	if (edit.had_color and current == edit.previous) or (not edit.had_color and current == default_color): return
	if panel.actions.undo_manager == null:
		panel._apply_random_branch_color(branch, current, meta_key)
	else:
		panel.actions.undo_manager.create_action("Change Random Branch End Color" if meta_key == TRANSITION_COLORS.END_META else "Change Random Branch Start Color", UndoRedo.MERGE_DISABLE, panel.state_machine.get_state_container())
		panel.actions.undo_manager.add_do_method(panel, "_apply_random_branch_color", branch, current, meta_key)
		panel.actions.undo_manager.add_undo_method(panel, "_apply_random_branch_color", branch, edit.previous if edit.had_color else null, meta_key)
		panel.actions.undo_manager.commit_action()

func _set_random_branch_color(panel, branch: StateRandomTarget, color: Variant, meta_key: StringName = TRANSITION_COLORS.META) -> void:
	if branch == null or not is_instance_valid(panel.state_machine): return
	var had_color := branch.has_meta(meta_key)
	var previous: Variant = branch.get_meta(meta_key) if had_color else null
	if (color == null and not had_color) or (color is Color and had_color and color == previous): return
	if panel.actions.undo_manager == null:
		panel._apply_random_branch_color(branch, color, meta_key)
	else:
		var label := ("Reset Random Branch End Color" if meta_key == TRANSITION_COLORS.END_META else "Reset Random Branch Start Color") if color == null else "Change Random Branch Color"
		panel.actions.undo_manager.create_action(label, UndoRedo.MERGE_DISABLE, panel.state_machine.get_state_container())
		panel.actions.undo_manager.add_do_method(panel, "_apply_random_branch_color", branch, color, meta_key)
		panel.actions.undo_manager.add_undo_method(panel, "_apply_random_branch_color", branch, previous, meta_key)
		panel.actions.undo_manager.commit_action()

func _apply_random_branch_color(panel, branch: StateRandomTarget, color: Variant, meta_key: StringName = TRANSITION_COLORS.META) -> void:
	if branch == null: return
	if color == null: branch.remove_meta(meta_key)
	else: branch.set_meta(meta_key, color)
	for routing in random_blocks:
		if routing.branches.has(branch):
			if meta_key == TRANSITION_COLORS.META: random_blocks[routing].set_branch_color(branch, TRANSITION_COLORS.color(branch))
			break
	if selected_random != null and selected_random.branches.has(branch) and is_instance_valid(routing_inspector):
		for child in routing_inspector.get_children():
			if child.has_meta(&"random_branch_color_picker") and child.get_meta(&"random_branch_color_picker") == branch:
				var picker: ColorPickerButton = child.get_meta("start_picker") if meta_key == TRANSITION_COLORS.META else child.get_meta("end_picker")
				picker.color = TRANSITION_COLORS.color(branch) if meta_key == TRANSITION_COLORS.META else TRANSITION_COLORS.end_color(branch, panel._automatic_end_color(panel._edge_for_random_branch(branch)))
				for control in child.get_children():
					if control is Button and control.text == "Reset" and meta_key == TRANSITION_COLORS.META: control.disabled = not TRANSITION_COLORS.has_override(branch)
					if control is Button and control.text == "Auto" and meta_key == TRANSITION_COLORS.END_META: control.disabled = not TRANSITION_COLORS.has_end_override(branch)
	panel.graph.queue_redraw()
	if is_instance_valid(panel.editor_interface): panel.editor_interface.mark_scene_as_unsaved()

func _edge_for_random_branch(panel, branch: StateRandomTarget) -> Dictionary:
	for edge in random_branch_connections.values():
		if edge.branch == branch: return edge
	return {}

func _apply_draft_routing_values(panel, routing: StateRandomRouting, values: Dictionary) -> void:
	var branches: Array[StateRandomTarget] = []
	for item in values.branches:
		if item.resource != null:
			item.resource.target_state = item.target
			item.resource.percentage = item.percentage
			if item.get("start_present", false): item.resource.set_meta(TRANSITION_COLORS.META, item.start_value)
			else: item.resource.remove_meta(TRANSITION_COLORS.META)
			if item.get("end_present", false): item.resource.set_meta(TRANSITION_COLORS.END_META, item.end_value)
			else: item.resource.remove_meta(TRANSITION_COLORS.END_META)
		branches.append(item.resource)
	routing.mode = values.mode
	routing.branches = branches
	if random_blocks.has(routing):
		panel._sync_random_visuals()

func _apply_draft_routing(panel, routing: StateRandomRouting, command: String, index: int, value: Variant) -> void:
	match command:
		"mode": routing.mode = value
		"add": routing.branches.append(StateRandomTarget.new())
		"remove": routing.branches.remove_at(index)
		"percentage": routing.branches[index].percentage = value
		"target": routing.branches[index].target_state = value

func _select_random(panel, routing: StateRandomRouting) -> void:
	panel._show_random_inspector(routing, null, {})

func _select_random_branch(panel, routing: StateRandomRouting, branch: StateRandomTarget, edge: Dictionary) -> void:
	if routing == null or branch == null or not routing.branches.has(branch): return
	panel._show_random_inspector(routing, branch, edge)

func _show_random_inspector(panel, routing: StateRandomRouting, branch: StateRandomTarget, edge: Dictionary) -> void:
	panel.selected_connection_edge = edge.duplicate() if not edge.is_empty() else {}
	selected_random = routing
	selected_random_branch = branch
	panel.selection_mode = panel.SelectionMode.RANDOM_CONNECTION if branch != null else panel.SelectionMode.RANDOM
	panel.selected_transition = null
	panel.selected_state = null
	panel._clear_debug_flash()
	panel.syncing_selection = true
	for node in panel.graph.get_children():
		if node is GraphNode:
			node.selected = branch == null and node is RANDOM_BLOCK and node.routing == routing
			if node is RANDOM_BLOCK:
				node.apply_router_appearance(
					APPEARANCE.get_color(panel._editor_settings(), "default_random"),
					APPEARANCE.get_color(panel._editor_settings(), "selected_accent"),
					node.selected
				)
	panel.syncing_selection = false
	panel._apply_state_appearance()
	if is_instance_valid(routing_inspector): routing_inspector.queue_free()
	routing_inspector = VBoxContainer.new()
	panel.inspector_scroll.get_child(0).add_child(routing_inspector)
	var title := Label.new()
	title.text = "RANDOM CONNECTION" if branch != null else "RANDOM ROUTING"
	routing_inspector.add_child(title)
	var block: GraphNode = random_blocks.get(routing)
	if not is_instance_valid(block):
		selected_random = null
		selected_random_branch = null
		panel.selection_mode = panel.SelectionMode.NONE
		panel._render_selection()
		return
	if branch == null:
		var color_row := HBoxContainer.new()
		var color_label := Label.new()
		color_label.text = "Color"
		color_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		color_row.add_child(color_label)
		var color_picker := ColorPickerButton.new()
		TRANSITION_COLORS.configure_inspector_color_button(color_picker)
		color_picker.tooltip_text = "Random router color override"
		color_picker.color = routing.get_meta(&"fsm_editor_random_color", APPEARANCE.get_color(panel._editor_settings(), "default_random"))
		color_picker.pressed.connect(panel._begin_random_router_color_edit.bind(routing, color_picker))
		color_picker.color_changed.connect(panel._preview_random_router_color.bind(routing))
		color_picker.popup_closed.connect(panel._finish_random_router_color_edit.bind(routing, color_picker))
		color_row.add_child(color_picker)
		var reset_router := Button.new()
		reset_router.text = "Reset"
		reset_router.tooltip_text = "Use the Default Random Color."
		reset_router.disabled = not routing.has_meta(&"fsm_editor_random_color")
		reset_router.pressed.connect(panel._set_random_router_color.bind(routing, null))
		color_row.add_child(reset_router)
		color_row.set_meta(&"random_router_color_picker", routing)
		color_row.set_meta(&"picker", color_picker)
		routing_inspector.add_child(color_row)
		var mode_label := Label.new()
		mode_label.text = "Mode"
		routing_inspector.add_child(mode_label)
		var mode := OptionButton.new()
		mode.add_item("Equal")
		mode.add_item("Percentages")
		mode.selected = routing.mode
		mode.item_selected.connect(func(value): panel._random_edited(block, "mode", -1, value))
		routing_inspector.add_child(mode)
		var branches_label := Label.new()
		branches_label.text = "Branches"
		routing_inspector.add_child(branches_label)
		for i in routing.branches.size():
			var item: StateRandomTarget = routing.branches[i]
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = String(item.target_state) if item != null and not item.target_state.is_empty() else "Connect target"
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var percent := SpinBox.new()
			percent.max_value = 100
			percent.step = 0.1
			percent.value = 100.0 / routing.branches.size() if routing.mode == 0 else (item.percentage if item != null else 0.0)
			percent.editable = routing.mode == 1
			percent.suffix = "%"
			percent.value_changed.connect(func(value): panel._random_edited(block, "percentage", i, value))
			row.add_child(percent)
			routing_inspector.add_child(row)
		var add := Button.new()
		add.text = "+ Output"
		add.pressed.connect(func(): panel._random_edited(block, "add", -1, null))
		routing_inspector.add_child(add)
	else:
		var color_rows: VBoxContainer = panel._random_color_row(branch)
		routing_inspector.add_child(color_rows)
		for text in ["FROM  %s" % String(routing.resource_name) if not routing.resource_name.is_empty() else "FROM  Random", "TO  %s" % String(branch.target_state), "Weight  %s%%" % str(100.0 / routing.branches.size() if routing.mode == 0 else branch.percentage), "Mode  %s" % ("Equal" if routing.mode == 0 else "Percentages")]:
			var detail := Label.new()
			detail.text = text
			routing_inspector.add_child(detail)
	var remove := Button.new()
	remove.text = "Disconnect input" if block.transition != null else "Remove Random draft"
	remove.pressed.connect(func():
		selected_random = null
		selected_random_branch = null
		if block.transition != null: panel._disconnect_random_input(block)
		else: panel._session_draft(routing, null, true))
	routing_inspector.add_child(remove)
	panel.right_tabs.current_tab = 0
	panel.show_authoring_dock()
	panel._render_selection()

func _random_color_row(panel, branch: StateRandomTarget) -> VBoxContainer:
	var rows := VBoxContainer.new()
	var start_row := HBoxContainer.new()
	var start_label := Label.new()
	start_label.text = "Start Color"
	start_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_row.add_child(start_label)
	var start_picker := ColorPickerButton.new()
	TRANSITION_COLORS.configure_inspector_color_button(start_picker)
	start_picker.tooltip_text = "Random connection start color"
	start_picker.color = TRANSITION_COLORS.color(branch)
	start_picker.pressed.connect(panel._begin_random_branch_color_edit.bind(branch, start_picker, TRANSITION_COLORS.META))
	start_picker.color_changed.connect(panel._preview_random_branch_color.bind(branch, TRANSITION_COLORS.META))
	start_picker.popup_closed.connect(panel._finish_random_branch_color_edit.bind(branch, start_picker, TRANSITION_COLORS.META))
	start_row.add_child(start_picker)
	var reset_start := Button.new()
	reset_start.text = "Reset"
	reset_start.tooltip_text = "Use the Default Transition Color."
	reset_start.disabled = not TRANSITION_COLORS.has_override(branch)
	reset_start.pressed.connect(panel._set_random_branch_color.bind(branch, null, TRANSITION_COLORS.META))
	start_row.add_child(reset_start)
	rows.add_child(start_row)
	var end_row := HBoxContainer.new()
	var end_label := Label.new()
	end_label.text = "End Color"
	end_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_row.add_child(end_label)
	var end_picker := ColorPickerButton.new()
	TRANSITION_COLORS.configure_inspector_color_button(end_picker)
	end_picker.tooltip_text = "Random connection end color"
	end_picker.color = TRANSITION_COLORS.end_color(branch, panel._automatic_end_color(panel._edge_for_random_branch(branch)))
	end_picker.pressed.connect(panel._begin_random_branch_color_edit.bind(branch, end_picker, TRANSITION_COLORS.END_META))
	end_picker.color_changed.connect(panel._preview_random_branch_color.bind(branch, TRANSITION_COLORS.END_META))
	end_picker.popup_closed.connect(panel._finish_random_branch_color_edit.bind(branch, end_picker, TRANSITION_COLORS.END_META))
	end_row.add_child(end_picker)
	var auto_end := Button.new()
	auto_end.text = "Auto"
	auto_end.tooltip_text = "Use the target input's current color."
	auto_end.disabled = not TRANSITION_COLORS.has_end_override(branch)
	auto_end.pressed.connect(panel._set_random_branch_color.bind(branch, null, TRANSITION_COLORS.END_META))
	end_row.add_child(auto_end)
	rows.add_child(end_row)
	rows.set_meta(&"random_branch_color_picker", branch)
	rows.set_meta(&"start_picker", start_picker)
	rows.set_meta(&"end_picker", end_picker)
	return rows


func _routing_signature(panel, routing: StateRandomRouting) -> String:
	if routing == null: return ""
	var values := []
	for branch in routing.branches: values.append([branch.target_state, branch.percentage, branch.get_meta(TRANSITION_COLORS.META) if branch.has_meta(TRANSITION_COLORS.META) else null, branch.get_meta(TRANSITION_COLORS.END_META) if branch.has_meta(TRANSITION_COLORS.END_META) else null] if branch != null else null)
	return str([routing.mode, routing.get_meta(&"fsm_editor_random_color") if routing.has_meta(&"fsm_editor_random_color") else null, values])

