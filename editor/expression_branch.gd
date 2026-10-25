@tool
extends MarginContainer


func _init() -> void:
	add_theme_constant_override("margin_left", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)
	theme_changed.connect(queue_redraw)


func _draw() -> void:
	var color := get_theme_color("font_color", "Label")
	color.a = 0.45
	draw_line(Vector2(5, 0), Vector2(5, size.y), color)
	draw_line(Vector2(5, 16), Vector2(13, 16), color)
