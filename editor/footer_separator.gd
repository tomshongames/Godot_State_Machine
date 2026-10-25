@tool
extends Control
var section_boundary := false

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size.y = 4
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	resized.connect(queue_redraw)

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED: queue_redraw()

func _draw() -> void:
	var color := get_theme_color("font_color", "Label")
	color.a = 0.60 if section_boundary else 0.35
	var span := line_span()
	draw_line(Vector2(span.x, size.y * 0.5), Vector2(span.y, size.y * 0.5), color, 2.0 if section_boundary else 1.0, true)

func line_span() -> Vector2:
	var card := get_parent() as GraphNode
	if card == null: return Vector2(0, size.x)
	var frame := card.get_theme_stylebox("panel_selected" if card.selected else "panel") as StyleBoxFlat
	var left := float(frame.border_width_left) if frame != null else 0.0
	var right := float(frame.border_width_right) if frame != null else 0.0
	# GraphNode insets child Controls by content margins. Draw past that allocation
	# to the frame's INNER border, independently of label and content padding.
	return Vector2(left - position.x, card.size.x - right - position.x)
