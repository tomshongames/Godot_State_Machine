@tool
extends RefCounted
var appearance_popup: PopupPanel
var appearance_rows: VBoxContainer
var appearance_pickers: Dictionary = {}
var exit_appearance_picker: ColorPickerButton
const TRANSITION_COLORS := preload("res://addons/state_machine/editor/transition_colors.gd")
const APPEARANCE := preload("res://addons/state_machine/editor/appearance_preferences.gd")
## Appearance policy and controls. Owns popup controls; caller retains scene Undo history.
## Context is passed per call, never retained; no signal or RefCounted ownership cycle.

func _build_appearance_popup(panel) -> void:
	appearance_popup = PopupPanel.new()
	panel.add_child(appearance_popup)
	var outer := VBoxContainer.new()
	outer.custom_minimum_size = Vector2(300, 420)
	appearance_popup.add_child(outer)
	var title := Label.new()
	title.text = "State Machine Appearance"
	outer.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	appearance_rows = VBoxContainer.new()
	scroll.add_child(appearance_rows)
	var reset := Button.new()
	reset.text = "Reset to Defaults"
	reset.pressed.connect(func():
		APPEARANCE.reset(panel._editor_settings())
		panel._refresh_appearance_controls()
		panel._apply_appearance())
	outer.add_child(reset)
	panel._refresh_appearance_controls()


func _refresh_appearance_controls(panel) -> void:
	if not is_instance_valid(appearance_rows):
		return
	appearance_pickers.clear()
	for child in appearance_rows.get_children():
		child.queue_free()
	var settings: EditorSettings = panel._editor_settings() if is_instance_valid(panel.editor_interface) else null
	for key in APPEARANCE.keys():
		if key in ["graph_background", "transition_manual", "active_state_accent"]:
			var group_label := Label.new()
			group_label.text = "GRAPH" if key == "graph_background" else ("TRANSITIONS" if key == "transition_manual" else "DEBUG")
			appearance_rows.add_child(group_label)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = APPEARANCE.label(key)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var picker := ColorPickerButton.new()
		TRANSITION_COLORS.configure_inspector_color_button(picker)
		picker.color = APPEARANCE.get_color(settings, key)
		var changed := func(color: Color, setting_key: String):
			APPEARANCE.set_color(panel._editor_settings(), setting_key, color)
			panel._apply_appearance(setting_key)
		picker.color_changed.connect(changed.bind(key))
		appearance_pickers[key] = picker
		if key == "exit": exit_appearance_picker = picker
		picker.pressed.connect(func(): picker.set_meta("appearance_color_before", APPEARANCE.get_color(panel._editor_settings(), key)))
		picker.popup_closed.connect(panel._commit_appearance_color.bind(picker, key))
		row.add_child(picker)
		appearance_rows.add_child(row)


func _commit_appearance_color(panel, picker: ColorPickerButton, key: String) -> void:
	var before: Color = picker.get_meta("appearance_color_before", picker.color)
	picker.remove_meta("appearance_color_before")
	if before == picker.color or panel.actions.undo_manager == null: return
	panel.actions.undo_manager.create_action("Change Appearance " + APPEARANCE.label(key), UndoRedo.MERGE_DISABLE, panel)
	panel.actions.undo_manager.add_do_method(panel, "_apply_appearance_color", key, picker.color)
	panel.actions.undo_manager.add_undo_method(panel, "_apply_appearance_color", key, before)
	panel.actions.undo_manager.commit_action()


func _apply_appearance_color(panel, key: String, color: Color) -> void:
	APPEARANCE.set_color(panel._editor_settings(), key, color)
	var picker: ColorPickerButton = appearance_pickers.get(key)
	if is_instance_valid(picker): picker.color = color
	panel._apply_appearance(key)


func _show_appearance_popup(panel) -> void:
	if is_instance_valid(appearance_popup):
		appearance_popup.popup(Rect2i(Vector2i(panel.appearance_button.get_global_rect().position), Vector2i(320, 440)))


func _apply_appearance(panel, changed_key: String = "") -> void:
	if not is_instance_valid(panel.graph) or not is_instance_valid(panel.editor_interface): return
	var settings: EditorSettings = panel._editor_settings()
	for category in APPEARANCE.affected_categories(changed_key):
		match category:
			"states": panel._apply_state_appearance(changed_key if changed_key in ["default_state", "hierarchy_state", "initial_accent", "selected_accent"] else "")
			"any_state": panel._apply_any_state_appearance()
			"entry": panel._apply_boundary_appearance(true)
			"exit": panel._apply_boundary_appearance(false)
			"transitions": panel._apply_transition_default_appearance()
			"random": panel._apply_random_default_appearance()
			"background":
				var background := StyleBoxFlat.new()
				background.bg_color = APPEARANCE.get_color(settings, "graph_background")
				if panel.get_theme_color("font_color", "Editor").get_luminance() < 0.5 and background.bg_color == APPEARANCE.COLORS.graph_background:
					background.bg_color = panel.get_theme_color("base_color", "Editor")
				panel.graph.add_theme_stylebox_override("panel", background)
			"grid":
				var grid: Color = APPEARANCE.get_color(settings, "grid")
				panel.graph.add_theme_color_override("grid_major", grid)
				panel.graph.add_theme_color_override("grid_minor", Color(grid.r, grid.g, grid.b, grid.a * 0.38))
			"debug": panel._apply_debug_appearance()
			"inspector":
				if is_instance_valid(panel.transition_editor): panel.transition_editor.refresh()
				panel._render_selection()
	panel._queue_connection_redraw()


func _apply_any_state_appearance(panel) -> void:
	if not is_instance_valid(panel.any_state_node): return
	var color: Color = APPEARANCE.get_color(panel._editor_settings(), "any_state")
	for key in ["titlebar", "titlebar_selected"]:
		var style: StyleBoxFlat = panel.any_state_node.get_theme_stylebox(key).duplicate() as StyleBoxFlat
		if style == null: continue
		style.bg_color = color
		if key == "titlebar_selected": style.border_color = APPEARANCE.get_color(panel._editor_settings(), "selected_accent")
		panel.any_state_node.add_theme_stylebox_override(key, style)
	panel.any_state_node.set_slot_color_right(0, color)


func _apply_debug_appearance(panel) -> void:
	var settings: EditorSettings = panel._editor_settings()
	for node in panel.graph.get_children():
		if node.has_method("set_debug_active"):
			node.set_debug_active(node.debug_active, APPEARANCE.get_color(settings, "active_state_accent"))
	var accent: Color = APPEARANCE.get_color(settings, "last_transition_accent")
	panel.graph.add_theme_color_override("activity", accent)
	panel.transition_editor.set_debug_transition(panel.transition_editor.debug_event, accent)
	panel.transitions_panel.set_debug_transition(panel.transitions_panel.debug_event, accent)


func _apply_state_appearance(panel, changed_key: String = "") -> void:
	if not is_instance_valid(panel.graph) or not is_instance_valid(panel.editor_interface):
		return
	var settings: EditorSettings = panel._editor_settings()
	for child in panel.graph.get_children():
		if child is GraphNode and child.has_method("apply_appearance"):
			var state_key := "hierarchy_state" if child.state is HierarchyState else "default_state"
			if changed_key in ["default_state", "hierarchy_state"] and (state_key != changed_key or child.state.has_meta(&"fsm_editor_color")): continue
			if changed_key == "initial_accent" and child.state != panel.state_machine.initial_state: continue
			child.apply_appearance(
				APPEARANCE.get_color(settings, state_key),
				APPEARANCE.get_color(settings, "initial_accent"),
				APPEARANCE.get_color(settings, "selected_accent"),
				child.state == panel.state_machine.initial_state,
				child.selected
			)
	if changed_key == "": panel._apply_any_state_appearance()
	if is_instance_valid(panel.selection_inspector) and is_instance_valid(panel.selection_inspector.state):
		var selected: State = panel.selection_inspector.state
		var selected_key := "hierarchy_state" if selected is HierarchyState else "default_state"
		if changed_key == "" or selected_key == changed_key:
			var default_color: Color = APPEARANCE.get_color(settings, selected_key)
			panel.selection_inspector.set_state_color(APPEARANCE.resolve_state_color(selected, default_color), selected.has_meta(&"fsm_editor_color"))

func _state_graph_node(panel, state: State) -> GraphNode:
	if not is_instance_valid(state) or not is_instance_valid(panel.graph): return null
	for child in panel.graph.get_children():
		if child is GraphNode and child.get("state") == state: return child
	return null


func _resolved_state_color(panel, state: State, preview_color: Variant = null) -> Color:
	var key := "hierarchy_state" if state is HierarchyState else "default_state"
	var settings: EditorSettings = panel._editor_settings() if is_instance_valid(panel.editor_interface) else null
	return APPEARANCE.resolve_state_color(state, APPEARANCE.get_color(settings, key), preview_color)


func _apply_boundary_appearance(panel, is_entry: bool) -> void:
	var node: GraphNode = panel.entry_node if is_entry else panel.exit_node
	if not is_instance_valid(node) or not is_instance_valid(panel.state_machine): return
	var color: Color = APPEARANCE.resolve_boundary_color(panel.state_machine, is_entry, panel._editor_settings())
	for style_key in ["titlebar", "titlebar_selected"]:
		var style := node.get_theme_stylebox(style_key).duplicate() as StyleBoxFlat
		if style != null:
			style.bg_color = color
			if style_key == "titlebar_selected": style.border_color = APPEARANCE.get_color(panel._editor_settings(), "selected_accent")
			node.add_theme_stylebox_override(style_key, style)
	node.set_slot(0, not is_entry, 0, color, is_entry, 0, color)
	if is_entry:
		for route in panel.transition_blocks:
			if TRANSITION_COLORS.uses_entry_color(route): panel.transition_blocks[route].update_color()
		if is_instance_valid(panel.transitions_panel): panel.transitions_panel.update_colors()



func _apply_transition_default_appearance(panel) -> void:
	TRANSITION_COLORS.default_color = APPEARANCE.get_color(panel._editor_settings(), "default_transition")
	if is_instance_valid(panel.creation_color_picker): panel.creation_color_picker.color = TRANSITION_COLORS.default_color
	panel.actions.creation_color = TRANSITION_COLORS.default_color
	panel._editor_settings().set_setting(TRANSITION_COLORS.SETTING, TRANSITION_COLORS.default_color)
	for route in panel.transition_blocks:
		if not TRANSITION_COLORS.has_override(route): panel.transition_blocks[route].update_color()
	for routing in panel.random_blocks:
		var block: GraphNode = panel.random_blocks[routing]
		for branch in routing.branches:
			if branch != null and not TRANSITION_COLORS.has_override(branch): block.set_branch_color(branch, TRANSITION_COLORS.color(branch))
	if is_instance_valid(panel.transitions_panel): panel.transitions_panel.update_colors()
	if is_instance_valid(panel.transition_editor): panel.transition_editor.refresh()


func _apply_random_default_appearance(panel) -> void:
	var settings: EditorSettings = panel._editor_settings()
	for routing in panel.random_blocks:
		var block: GraphNode = panel.random_blocks[routing]
		var color: Color = routing.get_meta(&"fsm_editor_random_color", APPEARANCE.get_color(settings, "default_random"))
		block.apply_router_appearance(APPEARANCE.get_color(settings, "default_random"), APPEARANCE.get_color(settings, "selected_accent"), block.selected)
		if panel.selected_random == routing: panel._sync_random_router_inspector(routing, color)

func _apply_state_graph_color(panel, node: GraphNode, state: State, preview_color: Variant = null) -> void:
	if not is_instance_valid(node) or not is_instance_valid(state) or not is_instance_valid(panel.editor_interface): return
	var settings: EditorSettings = panel._editor_settings()
	node.apply_appearance(
		APPEARANCE.get_color(settings, "hierarchy_state" if state is HierarchyState else "default_state"),
		APPEARANCE.get_color(settings, "initial_accent"),
		APPEARANCE.get_color(settings, "selected_accent"),
		state == panel.state_machine.initial_state,
		node.selected,
		preview_color
	)
	# The State node owns the port; GraphEdit owns the overlaid Auto-end curves.
	# Refresh that paint immediately without reconstructing graph nodes/connections.
	panel.graph.queue_redraw()

func _preview_state_color(panel, state: State, color: Color) -> void:
	if state == null or not is_instance_valid(panel.state_machine) or not panel.state_machine.owns_state(state): return
	panel._apply_state_graph_color(panel._state_graph_node(state), state, color)

func _commit_state_color_edit(panel, machine: FiniteStateMachine, state: State, had_color: bool, previous: Color, color: Color) -> void:
	if not is_instance_valid(machine) or not is_instance_valid(state) or not machine.owns_state(state): return
	if state.has_meta(&"fsm_editor_color") != had_color: return
	if had_color and state.get_meta(&"fsm_editor_color") != previous: return
	panel.actions.set_color(machine, state, color)

func _reset_state_color(panel, machine: FiniteStateMachine, state: State) -> void:
	if not is_instance_valid(machine) or not is_instance_valid(state) or not machine.owns_state(state): return
	var key := "hierarchy_state" if state is HierarchyState else "default_state"
	panel.actions.set_color(machine, state, APPEARANCE.get_color(panel._editor_settings(), key), true)

func _state_color_changed(panel, machine: FiniteStateMachine, state: State) -> void:
	if not is_instance_valid(machine) or not is_instance_valid(state): return
	if is_instance_valid(panel.editor_interface): panel.editor_interface.mark_scene_as_unsaved()
	if machine != panel.state_machine: return
	panel._apply_state_graph_color(panel._state_graph_node(state), state)
	if panel.selection_inspector.state == state:
		var default_color: Color = APPEARANCE.get_color(panel._editor_settings(), "hierarchy_state" if state is HierarchyState else "default_state")
		panel.selection_inspector.set_state_color(state.get_meta(&"fsm_editor_color", default_color), state.has_meta(&"fsm_editor_color"))


