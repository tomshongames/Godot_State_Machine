@tool
extends GraphNode

# Editor Control only. The Resource remains the sole transition configuration.
const COLORS := preload("res://addons/state_machine/editor/transition_colors.gd")
const LABELS := preload("res://addons/state_machine/runtime/transition_labels.gd")
const POSITION_META := &"fsm_editor_block_position"
signal context_requested(block: GraphNode)
signal source_drag_started(block: GraphNode, position: Vector2)
signal docking_size_changed(block: GraphNode)
var source_movable := false
var state: State
var machine: FiniteStateMachine
var transition: StateTransition
var draft := false
var dock_source: StringName = &""
var summary: Label
var draft_source: StringName = &""
var draft_target: StringName = &""
var intrinsic_dock_width := 0.0

func setup(route: StateTransition, is_draft := false) -> void:
	transition = route
	draft = is_draft
	custom_minimum_size = Vector2(205, 68)
	summary = Label.new()
	summary.custom_minimum_size.x = 185
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(summary)
	refresh_summary()
	intrinsic_dock_width = maxf(custom_minimum_size.x, get_combined_minimum_size().x)
	minimum_size_changed.connect(_queue_size_reset)
	gui_input.connect(func(event):
		if source_movable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Ports belong to GraphEdit's destination gesture. The remaining body,
			# including the title/handle, belongs to the source move gesture.
			if event.position.distance_to(get_output_port_position(0)) > 18:
				source_drag_started.emit(self, event.position)
				accept_event()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			context_requested.emit(self)
			accept_event())

func required_dock_width() -> float:
	return intrinsic_dock_width

func set_dock_width(value: float) -> void:
	var width := maxf(intrinsic_dock_width, value)
	if not is_equal_approx(custom_minimum_size.x, width):
		custom_minimum_size.x = width
	if not is_equal_approx(size.x, width):
		size.x = width

func _queue_size_reset() -> void:
	_resize_to_minimum.call_deferred()

func _resize_to_minimum() -> void:
	if not is_instance_valid(self): return
	reset_size()
	docking_size_changed.emit(self)

func refresh_summary() -> void:
	title = "ENTRY ROUTE" if transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY else String(StateTransition.TriggerType.find_key(transition.trigger_type)).replace("_", " ")
	if draft: title += " · Draft"
	summary.text = preload("res://addons/state_machine/editor/transitions_panel.gd").trigger_summary(transition)
	if not draft and transition.target_mode == StateTransition.TargetMode.DIRECT and transition.destination_mode == StateTransition.DestinationMode.STATE and transition.to_state.is_empty():
		summary.text += " · Unconnected"
	tooltip_text = summary.text + (("\nDrag onto a State, then connect its output to a target." if dock_source.is_empty() else "\nConnect its output to a target. Drag this chip onto another State to change FROM.") if draft else "\n%s → %s\nDrag this chip onto another State to change FROM." % [transition.source_label(), transition.target_label()])
	if not transition.enabled: summary.text = "Disabled · " + summary.text
	update_color()
	reset_size()

func update_color() -> void:
	var color := COLORS.source_color(transition, machine)
	if is_slot_enabled_left(0) != dock_source.is_empty() or not is_slot_enabled_right(0) or get_slot_color_left(0) != color or get_slot_color_right(0) != color:
		set_slot(0, dock_source.is_empty(), 0, color, true, 0, color)
	for key in ["titlebar", "titlebar_selected"]:
		var style := get_theme_stylebox(key) as StyleBoxFlat
		if style != null:
			# Each local override is owned by this block. Reuse it; theme/default
			# styles are duplicated once so no neighbouring Control is mutated.
			if not has_theme_stylebox_override(key):
				style = style.duplicate() as StyleBoxFlat
				style.border_width_left = 4
				style.border_color = color
				add_theme_stylebox_override(key, style)
			elif style.border_width_left != 4 or style.border_color != color:
				style.border_width_left = 4
				style.border_color = color

func input_port_for_transition(_route: StateTransition) -> int: return 0
func output_port_for_transition(_route: StateTransition) -> int: return 0
func creation_output_port() -> int: return 0
