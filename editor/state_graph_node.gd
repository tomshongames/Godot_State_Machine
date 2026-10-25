@tool
extends GraphNode

const APPEARANCE := preload("res://addons/state_machine/editor/appearance_preferences.gd")
const SCRIPT_UTILS := preload("res://addons/state_machine/editor/state_script_utils.gd")
const PORT_ROWS := preload("res://addons/state_machine/editor/transition_port_rows.gd")

signal rename_requested(state: State, new_name: String)
signal context_requested(state: State)
signal script_requested(state: State)
signal nested_requested(state: State)
signal transition_creation_requested
signal transition_selected(transition: StateTransition)
signal graph_visibility_requested(state: State)
var visibility_button: Button

var state: State
var name_label: Label
var rename_edit: LineEdit
var initial_marker: Label
var base_state_color := Color("3a424d")
var initial_color := Color("78b887")
var selected_color := Color("79a9e5")
var preview_color: Variant = null
var hierarchy_summary: Label
var port_rows = PORT_ROWS.new()
var transition_rows: Array[MarginContainer]:
	get: return port_rows.rows
var outgoing: Array[StateTransition] = []
var incoming: Array[StateTransition] = []
var debug_active := false
var debug_marker: Label

func update_graph_visibility(hidden: bool) -> void:
	if visibility_button == null: return
	var icon_name := "GuiVisibilityHidden" if hidden else "GuiVisibilityVisible"
	visibility_button.icon = get_theme_icon(icon_name, "EditorIcons") if has_theme_icon(icon_name, "EditorIcons") else null
	visibility_button.text = "Hidden" if hidden else ("" if visibility_button.icon != null else "Hide")
	visibility_button.tooltip_text = "Show State in Graph" if hidden else "Hide State in Graph (editor only)"


func setup(value: State, initial: bool, warning: String) -> void:
	state = value
	port_rows.creation_requested.connect(func(): transition_creation_requested.emit())
	port_rows.transition_selected.connect(func(transition): transition_selected.emit(transition))
	name = state.name
	title = ""
	custom_minimum_size = Vector2(190, 78)
	focus_mode = Control.FOCUS_NONE
	var bar := get_titlebar_hbox()
	for child in bar.get_children():
		if child is Label:
			child.hide()
	var type_icon := TextureRect.new()
	type_icon.texture = preload("res://addons/state_machine/icons/hierarchy_state.svg") if state is HierarchyState else preload("res://addons/state_machine/icons/state.svg")
	type_icon.custom_minimum_size = Vector2(16, 16)
	type_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	type_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	type_icon.tooltip_text = "Hierarchy State" if state is HierarchyState else "State"
	bar.add_child(type_icon)
	if initial:
		initial_marker = Label.new()
		initial_marker.text = "▶"
		initial_marker.tooltip_text = "Initial State"
		bar.add_child(initial_marker)
	name_label = Label.new()
	name_label.text = state.name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_label.gui_input.connect(_name_input)
	bar.add_child(name_label)
	visibility_button = Button.new()
	visibility_button.flat = true
	visibility_button.focus_mode = Control.FOCUS_NONE
	visibility_button.pressed.connect(func(): graph_visibility_requested.emit(state))
	bar.add_child(visibility_button)
	# Keep the eye beside the type icon, leaving the center/name region draggable.
	bar.move_child(visibility_button, name_label.get_index())
	update_graph_visibility(false)
	for child in [FiniteStateMachine.nested_machine_for_state(state)]:
		if child != null:
			var nested := Button.new()
			nested.flat = true
			nested.text = ""
			if has_theme_icon("GuiForward", "EditorIcons"): nested.icon = get_theme_icon("GuiForward", "EditorIcons")
			else: nested.text = "Open"
			nested.tooltip_text = "HierarchyState: Open Nested State Machine" if state.has_method("get_nested_machine") else "Open Nested State Machine"
			nested.pressed.connect(func(): nested_requested.emit(state))
			bar.add_child(nested)
			break
	debug_marker = Label.new()
	debug_marker.text = "Active"
	debug_marker.tooltip_text = "Active State in the selected runtime instance"
	debug_marker.hide()
	bar.add_child(debug_marker)
	rename_edit = LineEdit.new()
	rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_edit.custom_minimum_size.x = 100
	rename_edit.hide()
	rename_edit.text_submitted.connect(_submit_rename)
	rename_edit.focus_exited.connect(_cancel_rename)
	rename_edit.gui_input.connect(_rename_input)
	bar.add_child(rename_edit)
	var script_button := Button.new()
	script_button.flat = true
	script_button.focus_mode = Control.FOCUS_NONE
	var has_script := SCRIPT_UTILS.has_gameplay_script(state)
	script_button.tooltip_text = "Open this State's script" if has_script else "Create a unique State script"
	if has_theme_icon("Script", "EditorIcons"):
		script_button.icon = get_theme_icon("Script", "EditorIcons")
	else:
		script_button.text = "Script" if has_script else "+ Script"
	script_button.pressed.connect(func(): script_requested.emit(state))
	bar.add_child(script_button)
	port_rows.creation_button = Button.new()
	port_rows.creation_button.text = "+"
	port_rows.creation_button.flat = true
	port_rows.creation_button.tooltip_text = "New Transition"
	port_rows.creation_button.pressed.connect(func(): transition_creation_requested.emit())
	bar.add_child(port_rows.creation_button)
	if not warning.is_empty():
		var badge := TextureRect.new()
		badge.texture = get_theme_icon("NodeWarning", "EditorIcons") if has_theme_icon("NodeWarning", "EditorIcons") else null
		badge.custom_minimum_size = Vector2(16, 16)
		badge.tooltip_text = warning
		bar.add_child(badge)
	var ports := MarginContainer.new()
	ports.custom_minimum_size.y = 16
	ports.add_theme_constant_override("margin_left", 16)
	ports.add_theme_constant_override("margin_right", 16)
	add_child(ports)
	hierarchy_summary = Label.new()
	ports.add_child(hierarchy_summary)
	if state is HierarchyState:
		var exit_row := Label.new()
		exit_row.text = "Exit destination"
		exit_row.tooltip_text = "When the internal FSM reaches EXIT, continue to this one destination."
		add_child(exit_row)
	var input_color := base_state_color
	set_slot(0, true, 0, input_color, false, 0, input_color)
	gui_input.connect(_node_input)
	apply_appearance(base_state_color, initial_color, selected_color, initial, false)


func apply_appearance(default_color: Color, initial_accent: Color, selected_accent: Color, initial: bool, is_selected: bool, preview_color: Variant = null) -> void:
	base_state_color = default_color
	initial_color = initial_accent
	selected_color = selected_accent
	self.preview_color = preview_color
	var fill := APPEARANCE.resolve_state_color(state, default_color, preview_color)
	name_label.add_theme_color_override("font_color", Color("eeeeee") if fill.get_luminance() < 0.45 else Color("20242a"))
	var base := get_theme_stylebox("titlebar").duplicate() as StyleBoxFlat
	if base == null:
		base = StyleBoxFlat.new()
	base.bg_color = fill
	base.border_width_left = 4 if initial else 0
	base.border_color = initial_accent
	add_theme_stylebox_override("titlebar", base)
	var selected_style := get_theme_stylebox("titlebar_selected").duplicate() as StyleBoxFlat
	if selected_style == null:
		selected_style = base.duplicate() as StyleBoxFlat
	selected_style.bg_color = fill
	selected_style.border_width_left = 4 if initial else 0
	selected_style.border_width_bottom = 3 if is_selected else 0
	selected_style.border_color = selected_accent if is_selected else initial_accent
	add_theme_stylebox_override("titlebar_selected", selected_style)
	if is_instance_valid(initial_marker):
		initial_marker.visible = initial
		initial_marker.add_theme_color_override("font_color", initial_accent)
	# Keep the real input port bound to the State's resolved/preview color,
	# regardless of selection, initial-state emphasis, or outgoing triggers.
	_refresh_transition_rows(fill)


func set_outgoing_transitions(values: Array[StateTransition], _interface: EditorInterface) -> void:
	outgoing = values.duplicate()
	var fsm := FiniteStateMachine.machine_for_state(state) if is_instance_valid(state) else null
	apply_appearance(base_state_color, initial_color, selected_color, fsm != null and fsm.initial_state == state, selected)


func _refresh_transition_rows(input_color: Color) -> void:
	var nested := FiniteStateMachine.nested_machine_for_state(state) if is_instance_valid(state) else null
	hierarchy_summary.text = ""
	if nested != null:
		var count := 0
		for child in nested.get_state_container().get_children():
			if child is State: count += 1
		hierarchy_summary.text = "%d States" % count
	if state is HierarchyState:
		set_slot(0, true, 0, input_color, false, 0, input_color)
		set_slot(1, false, 0, input_color, true, 0, input_color)
	else: set_slot(0, true, 0, input_color, true, 0, input_color if outgoing.is_empty() else Color.TRANSPARENT)

func set_incoming_transitions(values: Array[StateTransition]) -> void:
	incoming = values.duplicate()

func input_port_for_transition(route: StateTransition) -> int:
	return 0


func output_port_for_transition(transition: StateTransition) -> int:
	return 0

func creation_output_port() -> int:
	return 0

func _draw_port(_slot_index: int, position: Vector2i, left: bool, color: Color) -> void:
	if not left and not state is HierarchyState and get_meta("dock_height", 0.0) > 0: return
	var icon := get_theme_icon("port")
	draw_texture(icon, Vector2(position) - icon.get_size() * 0.5, color)


func begin_rename() -> void:
	if not is_instance_valid(state):
		return
	name_label.hide()
	rename_edit.text = state.name
	rename_edit.show()
	rename_edit.grab_focus()
	rename_edit.select_all()


func set_debug_active(value: bool, accent: Color) -> void:
	debug_active = value
	debug_marker.visible = value
	debug_marker.add_theme_color_override("font_color", accent)
	for style_name in ["panel", "panel_selected"]:
		remove_theme_stylebox_override(style_name)
		if value:
			var style := get_theme_stylebox(style_name).duplicate() as StyleBoxFlat
			if style != null:
				style.border_width_right = 4
				style.border_color = accent
				add_theme_stylebox_override(style_name, style)


func clear_debug_state() -> void:
	set_debug_active(false, Color.TRANSPARENT)


func _submit_rename(value: String) -> void:
	_cancel_rename()
	if is_instance_valid(state):
		rename_requested.emit(state, value)


func _cancel_rename() -> void:
	rename_edit.hide()
	name_label.show()


func _rename_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_rename()
		accept_event()


func _name_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
			if state.has_method("get_nested_machine"):
				nested_requested.emit(state)
			else:
				begin_rename()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			context_requested.emit(state)
			accept_event()


func _node_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click and state.has_method("get_nested_machine"):
		nested_requested.emit(state)
		accept_event()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		context_requested.emit(state)
		accept_event()
