@tool
extends GraphNode

const ROWS := preload("res://addons/state_machine/editor/transition_port_rows.gd")
const ENTRY_POSITION := "@hierarchy_entry"
const EXIT_POSITION := "@hierarchy_exit"
signal transition_creation_requested
signal transition_selected(transition: StateTransition)
var state: State
var is_entry := true
var port_rows = ROWS.new()
var transition_rows: Array[MarginContainer]:
	get: return port_rows.rows

func setup(entry: bool) -> void:
	is_entry = entry
	title = "ENTRY" if entry else "EXIT"
	custom_minimum_size = Vector2(170, 65)
	port_rows.creation_button = Button.new()
	port_rows.creation_button.text = "+"
	port_rows.creation_button.flat = true
	port_rows.creation_button.tooltip_text = "New Transition"
	port_rows.creation_button.visible = entry
	port_rows.creation_button.pressed.connect(func(): transition_creation_requested.emit())
	get_titlebar_hbox().add_child(port_rows.creation_button)
	tooltip_text = "Hierarchy entry: Initial State is the fallback; explicit routes use conditions and priority." if entry else "Target only: finish this internal FSM and follow its HierarchyState exit destination."
	var caption := Label.new()
	caption.text = "Source only" if entry else "Target only"
	add_child(caption)
	set_slot(0, not entry, 0, get_theme_color("font_color", "Label"), false, 0, Color.WHITE)
	port_rows.creation_requested.connect(func(): transition_creation_requested.emit())
	port_rows.transition_selected.connect(func(route): transition_selected.emit(route))

func set_routes(_routes: Array[StateTransition], _interface: EditorInterface) -> void:
	var port_color := Color("78b887") if is_entry else Color("d09078")
	set_slot(0, not is_entry, 0, port_color, is_entry, 0, port_color)


func input_port_for_transition(route: StateTransition) -> int:
	return 0

func output_port_for_transition(route: StateTransition) -> int:
	return 0

func creation_output_port() -> int:
	return 0 if is_entry else -1

func _draw_port(_slot_index: int, position: Vector2i, left: bool, color: Color) -> void:
	var icon := get_theme_icon("port")
	draw_texture(icon, Vector2(position) - icon.get_size() * 0.5, color)
