@tool
extends GraphNode

const TRANSITION_COLORS := preload("res://addons/state_machine/editor/transition_colors.gd")

signal edited(block: GraphNode, command: String, index: int, value: Variant)
var state: State
var transition: StateTransition
var routing: StateRandomRouting
var draft := true
var inspector: VBoxContainer
const POSITION_META := &"fsm_editor_random_position"
var branch_color_indicators: Dictionary = {}
var router_color := Color("514765")

func setup(value: StateRandomRouting, route: StateTransition = null) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	clear_all_slots()
	routing = value
	transition = route
	branch_color_indicators.clear()
	draft = route == null
	title = "RANDOM · Draft" if draft else "RANDOM"
	custom_minimum_size.x = 220
	var mode := OptionButton.new()
	mode.add_item("Equal")
	mode.add_item("Percentages")
	mode.selected = routing.mode
	mode.item_selected.connect(func(choice): edited.emit(self, "mode", -1, choice))
	add_child(mode)
	set_slot(0, true, 0, Color("aab7c8"), false, 0, Color.WHITE)
	for i in routing.branches.size():
		var row := HBoxContainer.new()
		var branch := routing.branches[i]
		var label := Label.new()
		label.text = String(branch.target_state) if branch != null and not branch.target_state.is_empty() else "Connect target"
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = 90
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_text = label.text
		row.add_child(label)
		var color_indicator := ColorRect.new()
		color_indicator.custom_minimum_size = Vector2(10, 10)
		color_indicator.color = TRANSITION_COLORS.color(branch)
		color_indicator.tooltip_text = "Random branch color"
		row.add_child(color_indicator)
		if branch != null: branch_color_indicators[branch] = color_indicator
		var percent := SpinBox.new()
		percent.min_value = 0
		percent.max_value = 100
		percent.step = 0.1
		percent.suffix = "%"
		percent.value = 100.0 / routing.branches.size() if routing.mode == 0 else (branch.percentage if branch != null else 0.0)
		percent.editable = routing.mode == 1
		percent.value_changed.connect(func(number): edited.emit(self, "percentage", i, number))
		row.add_child(percent)
		var remove := Button.new()
		remove.text = "−"
		remove.tooltip_text = "Remove output"
		remove.pressed.connect(func(): edited.emit(self, "remove", i, null))
		row.add_child(remove)
		add_child(row)
		set_slot(i + 1, false, 0, Color.WHITE, true, 0, TRANSITION_COLORS.color(branch))
	var add := Button.new()
	add.text = "+ Output"
	add.pressed.connect(func(): edited.emit(self, "add", -1, null))
	add_child(add)
	tooltip_text = routing.configuration_error()

func set_branch_color(branch: StateRandomTarget, color: Color) -> void:
	var indicator: ColorRect = branch_color_indicators.get(branch)
	if is_instance_valid(indicator): indicator.color = color
	if routing == null or branch == null: return
	var index := routing.branches.find(branch)
	if index >= 0: set_slot_color_right(index + 1, color)

func apply_router_appearance(default_color: Color, selected_accent: Color, is_selected: bool, preview_color: Variant = null) -> void:
	router_color = preview_color if preview_color is Color else (routing.get_meta(&"fsm_editor_random_color", default_color) if routing != null else default_color)
	var title_style := get_theme_stylebox("titlebar").duplicate() as StyleBoxFlat
	if title_style == null: title_style = StyleBoxFlat.new()
	title_style.bg_color = router_color
	add_theme_stylebox_override("titlebar", title_style)
	var selected_style := get_theme_stylebox("titlebar_selected").duplicate() as StyleBoxFlat
	if selected_style == null: selected_style = title_style.duplicate() as StyleBoxFlat
	selected_style.bg_color = router_color
	selected_style.border_width_bottom = 3 if is_selected else 0
	selected_style.border_color = selected_accent
	add_theme_stylebox_override("titlebar_selected", selected_style)
	for child in get_titlebar_hbox().get_children():
		if child is Label: child.add_theme_color_override("font_color", Color("eeeeee") if router_color.get_luminance() < 0.45 else Color("20242a"))

