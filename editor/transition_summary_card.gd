@tool
extends Button

const ICONS := preload("res://addons/state_machine/editor/editor_icons.gd")
const SUMMARIES := preload("res://addons/state_machine/editor/transitions_panel.gd")
signal transition_requested(transition: StateTransition)
var transition: StateTransition
var destination: Label
var summary: Label
var type_icon: TextureRect
var content: HBoxContainer
const COLORS := preload("res://addons/state_machine/editor/transition_colors.gd")
var color_accent: ColorRect

func setup(machine: FiniteStateMachine, route: StateTransition, incoming: bool) -> void:
	transition = route
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	content = HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 8 * scale
	content.offset_right = -8 * scale
	content.offset_top = 6 * scale
	content.offset_bottom = -6 * scale
	type_icon = TextureRect.new()
	type_icon.texture = ICONS.transition_icon(self, machine, route)
	type_icon.custom_minimum_size = Vector2(16, 16) * scale
	type_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	type_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	type_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(type_icon)
	color_accent = ColorRect.new()
	color_accent.custom_minimum_size = Vector2(4, 16) * scale
	color_accent.color = COLORS.source_color(route, machine)
	color_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(color_accent)
	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(lines)
	destination = Label.new()
	destination.text = "%s → EXIT" % route.source_label() if incoming else "→ " + route.target_label()
	summary = Label.new()
	summary.text = ("Disabled · " if not route.enabled else "") + SUMMARIES.trigger_summary(route)
	for label in [destination, summary]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_child(label)
	tooltip_text = destination.text + "\n" + summary.text + ("\nSource: Any State" if route.source_mode == StateTransition.SourceMode.ANY_STATE else "")
	content.minimum_size_changed.connect(func(): custom_minimum_size.y = content.get_combined_minimum_size().y + 12 * scale)
	custom_minimum_size.y = content.get_combined_minimum_size().y + 12 * scale
	pressed.connect(func(): transition_requested.emit(transition))
