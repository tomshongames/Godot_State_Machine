@tool
extends GraphNode

# Editor graph endpoint only; never attached to an authored FSM/scene.
const POSITION_KEY := "@any_state"
var state: State
signal transition_creation_requested
signal transition_selected(transition: StateTransition)
const PORT_ROWS := preload("res://addons/state_machine/editor/transition_port_rows.gd")
var port_rows = PORT_ROWS.new()
var transition_rows: Array[MarginContainer]:
	get: return port_rows.rows

func setup() -> void:
	port_rows.creation_requested.connect(func(): transition_creation_requested.emit())
	port_rows.transition_selected.connect(func(transition): transition_selected.emit(transition))
	title = "Any State"
	var icon := TextureRect.new()
	icon.texture = preload("res://addons/state_machine/icons/any_state.svg")
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	get_titlebar_hbox().add_child(icon)
	custom_minimum_size = Vector2(170, 65)
	port_rows.creation_button = Button.new()
	port_rows.creation_button.text = "+"
	port_rows.creation_button.flat = true
	port_rows.creation_button.tooltip_text = "New Transition"
	port_rows.creation_button.pressed.connect(func(): transition_creation_requested.emit())
	get_titlebar_hbox().add_child(port_rows.creation_button)
	tooltip_text = "Source only - this FSM's active State"
	var port := Label.new()
	port.text = "Source only · this FSM"
	add_child(port)
	set_slot(0, false, 0, Color.WHITE, false, 0, Color.WHITE)

func set_outgoing_transitions(values: Array[StateTransition], interface: EditorInterface) -> void:
	set_slot(0, false, 0, Color.WHITE, true, 0, Color.WHITE if values.is_empty() else Color.TRANSPARENT)

func output_port_for_transition(transition: StateTransition) -> int:
	return 0

func creation_output_port() -> int:
	return 0

func _draw_port(_slot_index: int, position: Vector2i, left: bool, color: Color) -> void:
	if not left and get_meta("dock_height", 0.0) > 0: return
	var icon := get_theme_icon("port")
	draw_texture(icon, Vector2(position) - icon.get_size() * 0.5, color)
