@tool
extends VBoxContainer

signal activated(payload: Dictionary)
signal drag_started(payload: Dictionary)
const PAYLOAD_TYPE := "state_machine_palette"
const ICON_PATHS := {
	"Manual": "res://addons/state_machine/icons/godot_fsm_icons/manual.svg",
	"Event": "res://addons/state_machine/icons/godot_fsm_icons/event.svg",
	"Timer": "res://addons/state_machine/icons/godot_fsm_icons/timer.svg",
	"Input Action": "res://addons/state_machine/icons/godot_fsm_icons/input_action.svg",
	"Animation Finished": "res://addons/state_machine/icons/godot_fsm_icons/animation_finished.svg",
	"Property Watch": "res://addons/state_machine/icons/godot_fsm_icons/property_watch.svg",
	"Signal": "res://addons/state_machine/icons/godot_fsm_icons/signal.svg",
	"Random": "res://addons/state_machine/icons/godot_fsm_icons/random.svg",
	"State": "res://addons/state_machine/icons/state.svg",
	"Hierarchy State": "res://addons/state_machine/icons/hierarchy_state.svg",
}
const PALETTE_ICON_SIZE := 16
var items: Array[Dictionary] = []

func setup() -> void:
	name = "Palette"
	custom_minimum_size.x = 195
	_group("STRUCTURE")
	for kind in ["State", "Hierarchy State"]:
		_item(kind, {"type": PAYLOAD_TYPE, "structure": kind})
	_group("TRANSITIONS")
	# Runtime enum is the source of truth.
	for key in StateTransition.TriggerType:
		var label := String(key).capitalize()
		_item(label, {"type": PAYLOAD_TYPE, "trigger": StateTransition.TriggerType[key]})
	# Listed with transitions for authoring, but remains a destination router.
	_item("Random", {"type": PAYLOAD_TYPE, "routing": "Random"})

func _group(caption: String) -> void:
	var label := Label.new()
	label.text = caption
	add_child(label)

func _item(caption: String, payload: Dictionary) -> void:
	items.append(payload)
	var button := Button.new()
	button.name = "PaletteItem_%s" % caption.replace(" ", "_")
	button.set_meta("palette_caption", caption)
	button.custom_minimum_size.y = 24
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = "Drag into the graph, or click to create near its center."
	if payload.has("routing"):
		button.tooltip_text = "Routes a committed transition to one of multiple destinations.\n" + button.tooltip_text
	button.pressed.connect(func(): activated.emit(payload))
	button.set_drag_forwarding(func(_position):
		var preview := Label.new()
		preview.text = caption
		button.set_drag_preview(preview)
		drag_started.emit(payload)
		return payload, Callable(), Callable())
	_add_row_contents(button, caption)
	add_child(button)


func _add_row_contents(button: Button, caption: String) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 7
	row.offset_top = 0
	row.offset_right = -7
	row.offset_bottom = 0
	button.add_child(row)

	var handle := Label.new()
	handle.text = "⠿"
	handle.custom_minimum_size.x = 16
	handle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	handle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(handle)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(PALETTE_ICON_SIZE, PALETTE_ICON_SIZE)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.tooltip_text = caption
	icon.texture = _load_icon(caption)
	if icon.texture != null and caption in ["Manual", "Event", "Timer", "Input Action", "Animation Finished", "Property Watch", "Signal", "Random"]:
		icon.modulate = button.get_theme_color("font_color", "Button")
	row.add_child(icon)

	var title := Label.new()
	title.text = caption
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)


func _load_icon(caption: String) -> Texture2D:
	var path: String = ICON_PATHS.get(caption, "")
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		push_warning("FSM Palette icon is missing: %s" % path)
		return null
	var texture := ResourceLoader.load(path) as Texture2D
	if texture == null:
		push_warning("FSM Palette icon could not be loaded as a Texture2D: %s" % path)
	return texture
