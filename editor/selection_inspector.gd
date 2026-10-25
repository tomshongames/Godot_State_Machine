@tool
extends VBoxContainer

const SUMMARIES := preload("res://addons/state_machine/editor/transitions_panel.gd")
const SCRIPTS := preload("res://addons/state_machine/editor/state_script_utils.gd")
const CARD := preload("res://addons/state_machine/editor/transition_summary_card.gd")
const TRANSITION_COLORS := preload("res://addons/state_machine/editor/transition_colors.gd")
signal transition_requested(transition: StateTransition)
signal policy_edit_requested(state: State, property: StringName, value: Variant)
signal state_color_preview_requested(state: State, color: Color)
signal state_color_edit_requested(machine: FiniteStateMachine, state: State, had_color: bool, previous: Color, color: Color)
signal state_color_reset_requested(machine: FiniteStateMachine, state: State)
signal graph_visibility_requested(state: State, value: bool)
var graph_visibility: CheckBox
var policies: VBoxContainer
var minimum_time: SpinBox
var interruptible: CheckBox
var invalid_time: Label
var heading: Label
var info: Label
var active: Label
var cards: VBoxContainer
var routes_heading: Label
var routes: Array[StateTransition] = []
var machine: FiniteStateMachine
var state: State
var signature := ""
var state_color_row: HBoxContainer
var state_color_picker: ColorPickerButton
var state_color_reset: Button
var color_edit_machine: FiniteStateMachine
var color_edit_state: State
var color_edit_had_color := false
var color_edit_previous := Color.WHITE
var color_edit_active := false
var color_syncing := false

func setup() -> void:
	heading = Label.new()
	add_child(heading)
	graph_visibility = CheckBox.new()
	graph_visibility.text = "Visible in Graph"
	graph_visibility.tooltip_text = "Editor presentation only. Hidden States still run and are validated."
	graph_visibility.toggled.connect(func(value):
		if is_instance_valid(state): graph_visibility_requested.emit(state, value))
	add_child(graph_visibility)
	state_color_row = HBoxContainer.new()
	state_color_row.visible = false
	add_child(state_color_row)
	var color_label := Label.new()
	color_label.text = "Color"
	color_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_color_row.add_child(color_label)
	state_color_picker = ColorPickerButton.new()
	TRANSITION_COLORS.configure_inspector_color_button(state_color_picker)
	state_color_picker.tooltip_text = "State color override"
	state_color_picker.pressed.connect(_begin_state_color_edit)
	state_color_picker.color_changed.connect(_preview_state_color)
	state_color_picker.popup_closed.connect(_finish_state_color_edit)
	state_color_row.add_child(state_color_picker)
	state_color_reset = Button.new()
	state_color_reset.text = "Reset"
	state_color_reset.tooltip_text = "Use the current Appearance default color."
	state_color_reset.pressed.connect(func():
		if is_instance_valid(machine) and is_instance_valid(state): state_color_reset_requested.emit(machine, state))
	state_color_row.add_child(state_color_reset)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info)
	active = Label.new()
	add_child(active)
	policies = VBoxContainer.new()
	add_child(policies)
	var title := Label.new()
	title.text = "STATE POLICIES"
	policies.add_child(title)
	var label := Label.new()
	label.text = "Minimum State Time"
	policies.add_child(label)
	minimum_time = SpinBox.new()
	minimum_time.min_value = 0.0
	minimum_time.max_value = 86400.0
	minimum_time.allow_greater = true
	minimum_time.step = 0.01
	minimum_time.suffix = "s"
	minimum_time.tooltip_text = "Minimum time this State must remain active before normal outgoing transitions can commit."
	minimum_time.value_changed.connect(func(value):
		if is_instance_valid(state): policy_edit_requested.emit(state, &"minimum_state_time", value))
	policies.add_child(minimum_time)
	invalid_time = Label.new()
	invalid_time.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	policies.add_child(invalid_time)
	interruptible = CheckBox.new()
	interruptible.text = "Interruptible"
	interruptible.tooltip_text = "Allows transitions marked Can Interrupt to bypass Minimum State Time."
	interruptible.toggled.connect(func(value):
		if is_instance_valid(state): policy_edit_requested.emit(state, &"interruptible", value))
	policies.add_child(interruptible)
	routes_heading = Label.new()
	add_child(routes_heading)
	cards = VBoxContainer.new()
	add_child(cards)

func show_context(mode: String, context_machine: FiniteStateMachine, selected_state: State, values: Array[StateTransition], pair: Dictionary = {}, effective_color := Color.WHITE) -> void:
	machine = context_machine
	state = selected_state
	graph_visibility.visible = is_instance_valid(state)
	if graph_visibility.visible: graph_visibility.set_pressed_no_signal(not bool(state.get_meta(&"fsm_editor_graph_hidden", false)))
	state_color_row.visible = is_instance_valid(state)
	if state_color_row.visible:
		_set_state_color_picker(effective_color)
		state_color_reset.visible = state.has_meta(&"fsm_editor_color")
	policies.visible = is_instance_valid(state)
	if policies.visible:
		invalid_time.visible = not is_finite(state.minimum_state_time) or state.minimum_state_time < 0.0
		invalid_time.text = "Invalid authored Minimum State Time: %s" % state.minimum_state_time
		minimum_time.set_value_no_signal(state.minimum_state_time if is_finite(state.minimum_state_time) else 0.0)
		interruptible.set_pressed_no_signal(state.interruptible)
	heading.text = mode
	heading.visible = not mode.is_empty()
	var text := "Select a State or Transition."
	if is_instance_valid(state):
		var scripted := SCRIPTS.has_gameplay_script(state)
		text = "Name: %s\nType: %s\nScript: %s\nInitial: %s\nOutgoing Transitions: %d" % [state.name, "HierarchyState" if state is HierarchyState else "State", "Attached · " + state.get_script().resource_path.get_file() if scripted else "No Script", "Yes" if machine != null and machine.initial_state == state else "No", values.size()]
		if state is HierarchyState:
			var nested: FiniteStateMachine = state.get_nested_machine()
			var count: int = nested.get_state_container().get_children().filter(func(child): return child is State).size()
			text += "\nEntry Mode: %s\nInitial / Entry fallback: %s\nInternal States: %d" % ["RESET" if state.entry_mode == 0 else "RESUME", String(nested.initial_state.name) if nested.owns_state(nested.initial_state) else "Missing", count]
			text += "\nExit Destination: %s" % ("EXIT" if state.exit_target == StateTransition.EXIT_TARGET else (String(state.exit_target) if not state.exit_target.is_empty() else "Unconnected"))
	elif mode == "ENTRY": text = "Source-only hierarchy boundary.\nRoutes: %d\nInitial State is the canonical fallback." % values.size()
	elif mode == "EXIT": text = "Target-only hierarchy boundary.\nIncoming Exit Transitions: %d" % values.size()
	elif mode == "ANY STATE": text = "Source only · this FSM.\nOutgoing Transitions: %d" % values.size()
	elif mode == "TRANSITIONS": text = "%s\n%d transitions\nSelect one in the Transitions tab to edit." % [pair.get("label", ""), values.size()]
	info.text = text
	active.visible = is_instance_valid(state)
	var labels: Array[String] = []
	var ids: Array[int] = []
	for route in values:
		labels.append("%s%s · %s" % ["Off · " if not route.enabled else "", "%s → EXIT" % route.source_label() if mode == "EXIT" else "→ " + route.target_label(), SUMMARIES.trigger_summary(route)])
		ids.append(route.get_instance_id())
	var icons: Array[int] = []
	for route in values:
		var icon := CARD.ICONS.transition_icon(self, machine, route)
		icons.append(icon.get_instance_id() if icon != null else 0)
	var next := str(labels) + str(ids) + str(icons)
	routes = values.duplicate()
	cards.visible = not values.is_empty()
	routes_heading.visible = cards.visible
	routes_heading.text = "ENTRY ROUTES" if mode == "ENTRY" else ("INCOMING EXIT TRANSITIONS" if mode == "EXIT" else ("TRANSITIONS" if mode == "TRANSITIONS" else "OUTGOING TRANSITIONS"))
	if signature != next:
		signature = next
		for child in cards.get_children():
			cards.remove_child(child)
			child.queue_free()
		for route in values:
			var card := CARD.new()
			cards.add_child(card)
			card.setup(machine, route, mode == "EXIT")
			card.transition_requested.connect(func(value): transition_requested.emit(value))
	else:
		for card in cards.get_children(): card.color_accent.color = CARD.COLORS.source_color(card.transition, machine)

func set_state_color(effective_color: Color, has_override: bool) -> void:
	if not is_instance_valid(state_color_picker): return
	_set_state_color_picker(effective_color)
	state_color_reset.visible = has_override

func _set_state_color_picker(color: Color) -> void:
	color_syncing = true
	state_color_picker.color = color
	color_syncing = false

func _begin_state_color_edit() -> void:
	if color_edit_active or not is_instance_valid(machine) or not is_instance_valid(state): return
	color_edit_machine = machine
	color_edit_state = state
	color_edit_had_color = state.has_meta(&"fsm_editor_color")
	color_edit_previous = state.get_meta(&"fsm_editor_color", Color.WHITE)
	color_edit_active = true

func _preview_state_color(color: Color) -> void:
	if not color_syncing and color_edit_active and is_instance_valid(color_edit_state):
		state_color_preview_requested.emit(color_edit_state, color)

func _finish_state_color_edit() -> void:
	if not color_edit_active: return
	color_edit_active = false
	if is_instance_valid(color_edit_machine) and is_instance_valid(color_edit_state):
		state_color_edit_requested.emit(color_edit_machine, color_edit_state, color_edit_had_color, color_edit_previous, state_color_picker.color)
	color_edit_machine = null
	color_edit_state = null

func update_active(record: Dictionary) -> void:
	active.text = "Active: unavailable" if record.is_empty() else "Active: " + ("Yes" if record.get("active", true) and is_instance_valid(state) and record.get("current", "") == String(state.name) else "No")
