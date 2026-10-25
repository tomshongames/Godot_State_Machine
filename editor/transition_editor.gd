@tool
extends VBoxContainer
var navigation_read_only := false

const COMPARISON_EDITOR := preload("res://addons/state_machine/editor/property_comparison_editor.gd")
const NODE_PATH_FIELD := preload("res://addons/state_machine/editor/node_path_field.gd")
const APPEARANCE := preload("res://addons/state_machine/editor/appearance_preferences.gd")
const LABELS := preload("res://addons/state_machine/runtime/transition_labels.gd")
const EVENT_AUTHORING := preload("res://addons/state_machine/editor/event_script_authoring.gd")
const LOGIC := preload("res://addons/state_machine/runtime/condition_expression.gd")
const ICONS := preload("res://addons/state_machine/editor/editor_icons.gd")
const COLORS := preload("res://addons/state_machine/editor/transition_colors.gd")
const INPUT_ACTIONS := preload("res://addons/state_machine/runtime/input_action_catalog.gd")
const SIGNAL_EDITOR := preload("res://addons/state_machine/editor/signal_trigger_editor.gd")
var color_picker: ColorPickerButton
var start_color_reset: Button
var start_color_row: HBoxContainer
var end_color_picker: ColorPickerButton
var end_color_auto: Button
var end_color_row: HBoxContainer
var automatic_end_color := Color.WHITE

signal edit_requested(transition: StateTransition, property: StringName, value: Variant)
signal delete_requested(transition: StateTransition)
signal comparison_edit_requested(transition: StateTransition, condition: TransitionCondition, property: StringName, value: Variant)
signal condition_add_requested(transition: StateTransition)
signal condition_remove_requested(transition: StateTransition, condition: TransitionCondition)
signal event_script_requested(transition: StateTransition, emitter: State, create: bool)
signal condition_node_edit_requested(transition: StateTransition, node: Resource, property: StringName, value: Variant)
signal condition_tree_action_requested(transition: StateTransition, parent: TransitionConditionGroup, action: String, node: Resource)
signal action_add_requested(transition: StateTransition, action_type: int)
signal action_remove_requested(transition: StateTransition, action: TransitionAction)
signal action_edit_requested(transition: StateTransition, action: TransitionAction, property: StringName, value: Variant)
signal action_move_requested(transition: StateTransition, action: TransitionAction, direction: int)
signal resource_edits_requested(transition: StateTransition, resource: Resource, values: Dictionary)

var machine: FiniteStateMachine
var selected: StateTransition
var draft_selection: StateTransition
var source_filter: StringName
var target_filter: StringName
var source_mode_filter := -1
var loading := false
var rows: Array[StateTransition] = []
var heading: Label
var endpoints: Label
var source_state: OptionButton
var destination_state: OptionButton
var enabled: CheckBox
var trigger: OptionButton
var priority: SpinBox
var policy_controls: VBoxContainer
var cooldown: SpinBox
var can_interrupt: CheckBox
var invalid_cooldown: Label
var signal_row
var signal_source_mode: OptionButton
var signal_source_path
var signal_picker: OptionButton
var signal_name: LineEdit
var signal_status: Label
var event_row: VBoxContainer
var event_name: LineEdit
var timer_row: VBoxContainer
var duration: SpinBox
var details: VBoxContainer
var hint: Label
var input_row: VBoxContainer
var input_action: OptionButton
var input_mode: OptionButton
var animation_row: VBoxContainer
var animation_path: Control
var animation_name: LineEdit
var watch_row: VBoxContainer
var watch_editor
var condition_list: ItemList
var condition_editor
var condition_remove: Button
var selected_condition: TransitionCondition
var editor_interface: EditorInterface
var animation_picker: OptionButton
var animation_missing: Label
var observed_animation_player: AnimationPlayer
var debug_event: Dictionary = {}
var debug_accent := Color.TRANSPARENT
var event_suggestions: OptionButton
var event_emitter: OptionButton
var event_method_status: Label
var condition_tree: Tree
var selected_tree_resource: Resource
var condition_tree_rows := 0
var fallback_entry: StateTransition
var group_controls: HFlowContainer
var group_match: OptionButton
var group_enabled: CheckBox
var group_not: CheckBox
var condition_explanation: Label
var add_menu: MenuButton
var reenter_box: CheckBox
var actions_list: VBoxContainer
var action_menu: MenuButton
var conditions_builder: VBoxContainer
var inline_condition_rows: Array[Control] = []
var inline_action_rows: Array[Control] = []
var builder_rebuilds := 0
var conditions_shape := ""
var actions_shape := ""
var inline_groups: Array[Dictionary] = []
var action_enabled_controls: Dictionary = {}


func setup() -> void:
	custom_minimum_size.x = 260
	heading = Label.new()
	add_child(heading)
	details = VBoxContainer.new()
	add_child(details)
	endpoints = Label.new()
	details.add_child(endpoints)
	endpoints.hide()
	var color_row := HBoxContainer.new()
	start_color_row = color_row
	details.add_child(color_row)
	_label(color_row, "Start Color")
	color_picker = ColorPickerButton.new()
	COLORS.configure_inspector_color_button(color_picker)
	color_picker.tooltip_text = "Color of this exact logical transition (Undo available)."
	color_picker.color_changed.connect(func(value): _commit(&"editor_color", value))
	color_row.add_child(color_picker)
	start_color_reset = Button.new()
	start_color_reset.text = "Reset"
	start_color_reset.tooltip_text = "Use the current Default Transition Color."
	start_color_reset.pressed.connect(func(): _commit(&"editor_color", null))
	color_row.add_child(start_color_reset)
	end_color_row = HBoxContainer.new()
	details.add_child(end_color_row)
	_label(end_color_row, "End Color")
	end_color_picker = ColorPickerButton.new()
	COLORS.configure_inspector_color_button(end_color_picker)
	end_color_picker.color_changed.connect(func(value): _commit(&"editor_end_color", value))
	end_color_row.add_child(end_color_picker)
	end_color_auto = Button.new()
	end_color_auto.text = "Auto"
	end_color_auto.tooltip_text = "Use the destination input's current color."
	end_color_auto.pressed.connect(func(): _commit(&"editor_end_color", null))
	end_color_row.add_child(end_color_auto)
	enabled = CheckBox.new()
	enabled.text = "Enabled"
	enabled.toggled.connect(func(value): _commit(&"enabled", value))
	details.add_child(enabled)
	var priority_row := HBoxContainer.new()
	details.add_child(priority_row)
	_label(priority_row, "Priority")
	priority = SpinBox.new()
	priority.min_value = -2147483648
	priority.max_value = 2147483647
	priority.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	priority.value_changed.connect(func(value): _commit(&"priority", int(value)))
	priority.tooltip_text = "Higher values are evaluated first among eligible transitions. Equal values keep authored order."
	priority_row.add_child(priority)
	_label(details, "FROM")
	source_state = OptionButton.new()
	source_state.item_selected.connect(func(index):
		if selected != null and selected.source_mode == StateTransition.SourceMode.STATE and not source_state.disabled:
			_commit(&"from_state", source_state.get_item_metadata(index)))
	details.add_child(source_state)
	_label(details, "TO")
	destination_state = OptionButton.new()
	destination_state.item_selected.connect(func(index):
		if selected != null and selected.target_mode == StateTransition.TargetMode.RANDOM and index == 0: return
		_commit(&"to_state", destination_state.get_item_metadata(index)))
	details.add_child(destination_state)
	trigger = OptionButton.new()
	for type in StateTransition.TriggerType.values():
		var caption := String(StateTransition.TriggerType.find_key(type)).capitalize()
		trigger.add_icon_item(ICONS.get_icon(self, caption), caption, type)
	trigger.item_selected.connect(func(index): _commit(&"trigger_type", trigger.get_item_id(index)))
	details.add_child(trigger)
	policy_controls = VBoxContainer.new()
	details.add_child(policy_controls)
	_label(policy_controls, "Cooldown")
	cooldown = SpinBox.new()
	cooldown.min_value = 0.0
	cooldown.max_value = 86400.0
	cooldown.allow_greater = true
	cooldown.step = 0.01
	cooldown.suffix = "s"
	cooldown.tooltip_text = "Minimum time before this transition can successfully commit again."
	cooldown.value_changed.connect(func(value): _commit(&"cooldown", value))
	policy_controls.add_child(cooldown)
	invalid_cooldown = Label.new()
	invalid_cooldown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	policy_controls.add_child(invalid_cooldown)
	can_interrupt = CheckBox.new()
	can_interrupt.text = "Can Interrupt"
	can_interrupt.tooltip_text = "May bypass the source State's Minimum State Time when that State is Interruptible."
	can_interrupt.toggled.connect(func(value): _commit(&"can_interrupt", value))
	policy_controls.add_child(can_interrupt)
	reenter_box = CheckBox.new()
	reenter_box.text = "Re-enter State"
	reenter_box.tooltip_text = "On a self-transition, run the State's exit() and enter() lifecycle again."
	reenter_box.toggled.connect(func(value): _commit(&"reenter_state", value))
	details.add_child(reenter_box)
	event_row = VBoxContainer.new()
	details.add_child(event_row)
	_label(event_row, "Event Name")
	event_name = LineEdit.new()
	event_name.text_submitted.connect(func(_value): _commit_event())
	event_name.focus_exited.connect(_commit_event)
	event_row.add_child(event_name)
	event_suggestions = OptionButton.new()
	event_suggestions.item_selected.connect(func(index):
		if not loading and index > 0:
			event_name.text = event_suggestions.get_item_text(index)
			_commit_event())
	event_row.add_child(event_suggestions)
	_label(event_row, "Emitter State")
	event_emitter = OptionButton.new()
	event_emitter.item_selected.connect(func(_index): _event_method_status())
	event_row.add_child(event_emitter)
	event_method_status = Label.new()
	event_method_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_row.add_child(event_method_status)
	var event_buttons := HFlowContainer.new()
	for create in [false, true]:
		var button := Button.new()
		button.text = "Create / Go to Method" if create else "Open Script"
		button.tooltip_text = "Navigate to an existing method, or create it once." if create else "Open the emitter State's script."
		button.pressed.connect(func():
			var emitter := _event_emitter_state()
			if selected != null and emitter != null:
				event_script_requested.emit(selected, emitter, create))
		event_buttons.add_child(button)
	event_row.add_child(event_buttons)
	timer_row = VBoxContainer.new()
	details.add_child(timer_row)
	_label(timer_row, "Duration (seconds)")
	duration = SpinBox.new()
	duration.min_value = 0
	duration.max_value = 86400
	duration.allow_greater = true
	duration.step = 0.01
	duration.value_changed.connect(func(value): _commit(&"duration", value))
	timer_row.add_child(duration)
	_build_phase4_controls()
	_build_signal_controls()
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(hint)
	var remove := Button.new()
	remove.text = "Delete Transition"
	remove.pressed.connect(func():
		if selected != null:
			delete_requested.emit(selected))
	details.add_child(remove)
	_organize_sections()
	refresh()


func _organize_sections() -> void:
	var buckets := {"Transition": [], "Trigger": [], "Conditions": [policy_controls], "Actions": [], "Self Transition": []}
	var section := "Transition"
	for child in details.get_children():
		if child == policy_controls:
			continue
		if child == trigger: section = "Trigger"
		if child is Label and child.text == "Conditions":
			section = "Conditions"
			child.hide()
		if child is Label and child.text == "Actions":
			section = "Actions"
			child.hide()
		if child == reenter_box:
			buckets["Self Transition"].append(child)
			continue
		buckets[section].append(child)
	for name in buckets:
		var header := Button.new()
		header.text = {"Trigger": "TRANSITION TRIGGER", "Conditions": "TRANSITION CONDITIONS", "Actions": "EFFECTS"}.get(name, name.to_upper())
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.toggle_mode = true
		header.button_pressed = true
		header.tooltip_text = "Expand or collapse %s settings." % header.text.to_lower()
		details.add_child(header)
		var body := VBoxContainer.new()
		body.set_meta("section", name)
		details.add_child(body)
		for child in buckets[name]: child.reparent(body)
		header.toggled.connect(func(expanded):
			body.visible = expanded
			if is_instance_valid(editor_interface):
				editor_interface.get_editor_settings().set_setting("editors/state_machine/sections/" + name.to_lower(), expanded))
		header.set_meta("section", name)
		if name == "Self Transition": body.set_meta("self_transition", true)


func _label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)

func _build_signal_controls() -> void:
	signal_row = SIGNAL_EDITOR.new()
	details.add_child(signal_row)
	signal_row.setup(editor_interface)
	signal_row.edited.connect(_commit)
	signal_source_mode = signal_row.source_mode
	signal_source_path = signal_row.source_path
	signal_picker = signal_row.picker
	signal_name = signal_row.name_edit
	signal_status = signal_row.status

func _fill_signal_controls() -> void:
	signal_row.configure(machine, selected, editor_interface)


func focus_created_trigger(transition: StateTransition) -> void:
	if selected != transition or not is_inside_tree(): return
	if transition.trigger_type not in [StateTransition.TriggerType.EVENT, StateTransition.TriggerType.TIMER]: return
	for child in details.get_children():
		if child is Button and child.get_meta("section", "") == "Trigger": child.button_pressed = true
	if transition.trigger_type == StateTransition.TriggerType.TIMER: duration.get_line_edit().grab_focus()
	else: event_name.grab_focus()


func set_machine(value: FiniteStateMachine) -> void:
	if machine != value:
		selected = null
		source_filter = &""
		target_filter = &""
		source_mode_filter = -1
	machine = value
	if is_instance_valid(watch_editor):
		watch_editor.set_editor_context(editor_interface, machine)
	if is_instance_valid(condition_editor):
		condition_editor.set_editor_context(editor_interface, machine)
	refresh()


func set_editor_context(interface: EditorInterface) -> void:
	editor_interface = interface
	if is_instance_valid(interface):
		var settings := interface.get_editor_settings()
		for child in details.get_children():
			if child is Button and child.has_meta("section"):
				var key: String = "editors/state_machine/sections/" + String(child.get_meta("section")).to_lower()
				if not settings.has_setting(key): settings.set_setting(key, true)
				child.button_pressed = bool(settings.get_setting(key))
	if is_instance_valid(watch_editor):
		watch_editor.set_editor_context(editor_interface, machine)
	if is_instance_valid(condition_editor):
		condition_editor.set_editor_context(editor_interface, machine)


func show_source(source: StringName) -> void:
	source_mode_filter = StateTransition.SourceMode.STATE if not source.is_empty() else -1
	source_filter = source
	target_filter = &""
	selected = null
	refresh()


func show_pair(source: StringName, target: StringName) -> void:
	source_mode_filter = StateTransition.SourceMode.STATE
	source_filter = source
	target_filter = target
	selected = null
	refresh()


func show_any_source(target: StringName = &"") -> void:
	source_mode_filter = StateTransition.SourceMode.ANY_STATE
	source_filter = &""
	target_filter = target
	selected = null
	refresh()


func refresh() -> void:
	if heading == null:
		return
	loading = true
	rows.clear()
	heading.text = "From Any State" if source_mode_filter == StateTransition.SourceMode.ANY_STATE else ("All transitions" if source_filter.is_empty() else "From %s%s" % [source_filter, " → " + String(target_filter) if not target_filter.is_empty() else ""])
	if is_instance_valid(machine):
		var visible: Array[StateTransition] = machine.transitions.duplicate()
		if fallback_entry != null: visible.append(fallback_entry)
		if draft_selection != null and selected == draft_selection and not draft_selection in visible: visible.append(draft_selection)
		for transition in visible:
			if transition == null:
				continue
			if source_mode_filter >= 0 and transition.source_mode != source_mode_filter: continue
			if not source_filter.is_empty() and String(transition.from_state).to_lower() != String(source_filter).to_lower():
				continue
			if not target_filter.is_empty() and String(transition.to_state).to_lower() != String(target_filter).to_lower():
				continue
			rows.append(transition)
	if selected == null or not selected in rows:
		selected = null
	heading.text += " [%d]" % rows.size()
	if not target_filter.is_empty() and source_mode_filter == StateTransition.SourceMode.ANY_STATE:
		heading.text = "Any State → %s [%d]" % [target_filter, rows.size()]
	heading.tooltip_text = "Each row is an independent logical transition resource. One graph edge can contain several triggers."
	heading.text = "Select a transition in Transitions or click a graph edge." if selected == null else "%s → %s" % [selected.source_label(), selected.target_label()]
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fill_details()
	loading = false
	_apply_debug_transition()


func _description(transition: StateTransition) -> String:
	var label := LABELS.trigger_description(transition)
	var source := ("Any State" if transition.source_mode == StateTransition.SourceMode.ANY_STATE else String(transition.from_state)) + " · " if source_filter.is_empty() else ""
	return "%s%s%s%s" % ["[Off] " if not transition.enabled else "", source, label, " → " + String(transition.to_state) if target_filter.is_empty() else ""]


func _fill_details() -> void:
	watch_editor.auto_normalize = not navigation_read_only
	condition_editor.auto_normalize = not navigation_read_only
	for row in inline_condition_rows + inline_action_rows: row.auto_normalize = not navigation_read_only
	details.visible = selected != null
	if selected == null:
		return
	endpoints.text = "From: %s\nTo: %s" % [selected.source_label(), selected.target_label()]
	color_picker.color = COLORS.color(selected)
	start_color_row.visible = not COLORS.uses_entry_color(selected)
	color_picker.disabled = false
	start_color_reset.disabled = not COLORS.has_override(selected)
	end_color_row.visible = not COLORS.uses_exit_color(selected)
	end_color_picker.color = COLORS.end_color(selected, automatic_end_color)
	end_color_auto.disabled = not COLORS.has_end_override(selected)
	source_state.show()
	source_state.disabled = selected.source_mode != StateTransition.SourceMode.STATE
	if selected.source_mode == StateTransition.SourceMode.STATE:
		_fill_endpoint(source_state, selected.from_state)
	else:
		source_state.clear()
		source_state.add_item("Any State" if selected.source_mode == StateTransition.SourceMode.ANY_STATE else "ENTRY")
		source_state.set_item_metadata(0, selected.from_state)
		source_state.select(0)
	_fill_endpoint(destination_state, selected.target_key())
	if selected.target_mode == StateTransition.TargetMode.RANDOM:
		destination_state.set_item_text(0, "Random routing")
		destination_state.select(0)
	if machine.has_hierarchy_boundary() and selected.source_mode != StateTransition.SourceMode.HIERARCHY_ENTRY:
		destination_state.add_item("EXIT")
		destination_state.set_item_metadata(destination_state.item_count - 1, StateTransition.EXIT_TARGET)
		if selected.target_mode == StateTransition.TargetMode.DIRECT and selected.destination_mode == StateTransition.DestinationMode.EXIT:
			# EXIT resolves to the boundary, not a child State named by its sentinel.
			if destination_state.get_item_text(0).begins_with("[Missing] ") and destination_state.get_item_metadata(0) == StateTransition.EXIT_TARGET:
				destination_state.remove_item(0)
			destination_state.select(destination_state.item_count - 1)
	var entry_route := selected.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY
	var virtual_route := selected.get_meta("initial_fallback", false)
	destination_state.disabled = virtual_route
	enabled.disabled = virtual_route
	priority.editable = not virtual_route
	trigger.disabled = entry_route
	var owner_source: Node = machine.get_state_container().get_node_or_null(NodePath(String(selected.from_state))) if selected.source_mode == StateTransition.SourceMode.STATE and not selected.from_state.is_empty() else null
	enabled.button_pressed = selected.enabled
	trigger.select(maxi(trigger.get_item_index(selected.trigger_type), 0))
	trigger.add_theme_color_override("font_color", APPEARANCE.get_transition_color(editor_interface, selected.trigger_type))
	priority.value = selected.priority
	cooldown.set_value_no_signal(selected.cooldown if is_finite(selected.cooldown) else 0.0)
	invalid_cooldown.visible = not is_finite(selected.cooldown) or selected.cooldown < 0.0
	invalid_cooldown.text = "Invalid authored Cooldown: %s" % selected.cooldown
	can_interrupt.set_pressed_no_signal(selected.can_interrupt)
	policy_controls.visible = not entry_route
	var self_transition := selected.source_mode == StateTransition.SourceMode.STATE and selected.destination_mode == StateTransition.DestinationMode.STATE and String(selected.from_state).to_lower() == String(selected.to_state).to_lower()
	if selected.target_mode == StateTransition.TargetMode.RANDOM and selected.random_routing != null:
		self_transition = selected.random_routing.branches.any(func(branch): return branch != null and selected.source_mode == StateTransition.SourceMode.STATE and String(branch.target_state).nocasecmp_to(String(selected.from_state)) == 0)
	reenter_box.visible = self_transition
	reenter_box.button_pressed = selected.reenter_state
	for control in details.get_children():
		if control.get_meta("section", "") == "Self Transition": control.visible = self_transition
		if control.get_meta("section", "") == "Actions": control.visible = not entry_route
	event_name.text = selected.event_name
	duration.value = selected.duration
	event_row.visible = selected.trigger_type == StateTransition.TriggerType.EVENT
	if event_row.visible:
		_fill_event_authoring()
	timer_row.visible = selected.trigger_type == StateTransition.TriggerType.TIMER
	_fill_phase4_controls()
	_fill_signal_controls()
	_fill_actions()
	_fill_inline_conditions()
	add_menu.disabled = virtual_route
	action_menu.disabled = virtual_route
	group_match.disabled = virtual_route
	group_enabled.disabled = virtual_route
	group_not.disabled = virtual_route
	if virtual_route:
		var root := condition_tree.get_root()
		if root != null:
			for column in 3: root.set_editable(column, false)
	hint.text = ""
	if entry_route:
		event_row.hide()
		timer_row.hide()
		input_row.hide()
		animation_row.hide()
		watch_row.hide()
		hint.text = "Initial State is the canonical fallback. Drag its ENTRY curve to change it; add routes for conditional priority-based entry." if virtual_route else "Entry is evaluated on RESET activation (or RESUME fallback). Initial State remains the fallback."
	if event_row.visible and selected.event_name.is_empty():
		hint.text = "Enter an Event Name."
	elif timer_row.visible and selected.duration < 0:
		hint.text = "Duration must be non-negative."
	if is_instance_valid(machine):
		var warnings := machine.transition_warnings(selected)
		if not warnings.is_empty():
			hint.text = "\n".join(warnings)
	if selected.trigger_type == StateTransition.TriggerType.ANIMATION_FINISHED:
		var note := "Conditions are checked when the animation finishes; if they fail, the transition is not retried automatically."
		hint.text = note if hint.text.is_empty() else hint.text + "\n" + note


func _fill_endpoint(picker: OptionButton, current: StringName) -> void:
	picker.clear()
	picker.add_item("Choose State" if current.is_empty() else "[Missing] " + String(current))
	picker.set_item_metadata(0, current)
	if not is_instance_valid(machine): return
	var match_index := -1
	for child in machine.get_state_container().get_children():
		if child is State:
			picker.add_item(String(child.name))
			picker.set_item_metadata(picker.item_count - 1, StringName(child.name))
			if child.name == current or (match_index < 0 and String(child.name).nocasecmp_to(String(current)) == 0):
				match_index = picker.item_count - 1
	if match_index >= 0:
		# Retain authored unresolved names, but do not label a resolved State Missing.
		picker.remove_item(0)
		picker.select(match_index - 1)


func _commit_event() -> void:
	_commit(&"event_name", StringName(event_name.text.strip_edges()))


func _event_emitter_state() -> State:
	return event_emitter.get_selected_metadata() as State if event_emitter.selected >= 0 else null


func _fill_event_authoring() -> void:
	var previous := _event_emitter_state()
	event_suggestions.clear()
	event_suggestions.add_item("Known Events")
	for event in EVENT_AUTHORING.catalog(machine):
		event_suggestions.add_item(event)
	event_emitter.clear()
	for state in EVENT_AUTHORING.emitters(machine):
		var label := String(machine.get_state_container().get_path_to(state))
		event_emitter.add_item(label)
		event_emitter.set_item_metadata(event_emitter.item_count - 1, state)
		if state == previous or (previous == null and String(state.name) == String(selected.from_state)):
			event_emitter.select(event_emitter.item_count - 1)
	_event_method_status()


func _event_method_status() -> void:
	var state := _event_emitter_state()
	if not is_instance_valid(state):
		event_method_status.text = "Choose an emitter State."
		return
	var script: Script = state.get_script()
	var method := EVENT_AUTHORING.method_name(selected.event_name) if selected != null else ""
	var base := script.get_global_name() if script != null else &""
	if script == null or base in [&"State", &"HierarchyState"]:
		event_method_status.text = "State has no gameplay script"
	else:
		var exists := not EVENT_AUTHORING.location(script, method).is_empty()
		event_method_status.text = "Event method exists: %s" % method if exists else "Event method missing: %s" % method
		event_method_status.tooltip_text = script.resource_path


func _commit(property: StringName, value: Variant) -> void:
	if property == &"editor_color" and COLORS.uses_entry_color(selected): return
	if property == &"editor_end_color" and COLORS.uses_exit_color(selected): return
	if not loading and is_instance_valid(machine) and selected != null and (selected in machine.transitions or property in [&"editor_color", &"editor_end_color"] and selected.get_meta("initial_fallback", false)):
		edit_requested.emit(selected, property, value)


func _build_phase4_controls() -> void:
	input_row = VBoxContainer.new()
	details.add_child(input_row)
	_label(input_row, "Input Action")
	input_action = OptionButton.new()
	input_action.get_popup().about_to_popup.connect(_refresh_input_actions)
	input_action.focus_entered.connect(_refresh_input_actions)
	input_action.item_selected.connect(func(index): _commit(&"input_action", input_action.get_item_metadata(index)))
	input_row.add_child(input_action)
	input_mode = OptionButton.new()
	for name in ["Pressed", "Released", "Held"]:
		input_mode.add_item(name)
	input_mode.item_selected.connect(func(index): _commit(&"input_mode", index))
	input_row.add_child(input_mode)
	animation_row = VBoxContainer.new()
	details.add_child(animation_row)
	animation_path = _trigger_line(animation_row, "AnimationPlayer", &"animation_player_path", true)
	animation_name = _trigger_line(animation_row, "Animation Name", &"animation_name", false)
	watch_row = VBoxContainer.new()
	details.add_child(watch_row)
	watch_editor = COMPARISON_EDITOR.new()
	watch_row.add_child(watch_editor)
	watch_editor.setup(false)
	watch_editor.edits_requested.connect(func(values):
		if selected != null: resource_edits_requested.emit(selected, selected.watch, values))
	var condition_heading := Label.new()
	condition_heading.text = "Conditions"
	details.add_child(condition_heading)
	condition_explanation = Label.new()
	condition_explanation.text = ""
	condition_explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(condition_explanation)
	condition_tree = Tree.new()
	condition_tree.columns = 3
	condition_tree.set_column_title(0, "Expression")
	condition_tree.set_column_title(1, "On")
	condition_tree.set_column_title(2, "NOT")
	condition_tree.column_titles_visible = false
	condition_tree.set_column_expand(1, false)
	condition_tree.set_column_expand(2, false)
	condition_tree.set_column_custom_minimum_width(1, 35)
	condition_tree.set_column_custom_minimum_width(2, 40)
	condition_tree.custom_minimum_size.y = 150
	condition_tree.item_selected.connect(_select_condition_tree)
	condition_tree.item_edited.connect(_condition_tree_edited)
	details.add_child(condition_tree)
	group_controls = HFlowContainer.new()
	details.add_child(group_controls)
	group_match = OptionButton.new()
	group_match.add_item("ALL · all conditions")
	group_match.add_item("ANY · any condition")
	group_match.tooltip_text = "ALL is AND. ANY is OR. Groups can contain conditions and nested groups."
	group_match.item_selected.connect(func(index):
		if not loading and selected != null: condition_node_edit_requested.emit(selected, selected_tree_resource, &"operator", index))
	group_controls.add_child(group_match)
	group_enabled = CheckBox.new()
	group_enabled.text = "Enabled"
	group_enabled.toggled.connect(func(value):
		if not loading and selected != null: condition_node_edit_requested.emit(selected, selected_tree_resource, &"enabled", value))
	group_controls.add_child(group_enabled)
	group_not = CheckBox.new()
	group_not.text = "NOT"
	group_not.tooltip_text = "Negate this entire group. Invalid comparisons still fail."
	group_not.toggled.connect(func(value):
		if not loading and selected != null: condition_node_edit_requested.emit(selected, selected_tree_resource, &"negated", value))
	group_controls.add_child(group_not)
	condition_list = ItemList.new()
	condition_list.custom_minimum_size.y = 70
	condition_list.item_selected.connect(_select_condition)
	details.add_child(condition_list)
	var buttons := HFlowContainer.new()
	details.add_child(buttons)
	add_menu = _create_add_button("+ Condition", true) as MenuButton
	add_menu.tooltip_text = "Add a property comparison condition."
	add_menu.get_popup().add_item("Condition", 0)
	add_menu.get_popup().add_item("Group: ALL", 1)
	add_menu.get_popup().add_item("Group: ANY", 2)
	add_menu.get_popup().id_pressed.connect(func(id): _condition_tree_command(["add_condition", "add_group", "add_any_group"][id]))
	buttons.add_child(add_menu)
	var group_button := _create_add_button("+ Group", true) as MenuButton
	group_button.tooltip_text = "Add an ALL or ANY group."
	group_button.get_popup().add_item("ALL", 1)
	group_button.get_popup().add_item("ANY", 2)
	group_button.get_popup().id_pressed.connect(func(id): _condition_tree_command("add_group" if id == 1 else "add_any_group"))
	buttons.add_child(group_button)
	condition_remove = Button.new()
	condition_remove.text = "Remove"
	condition_remove.pressed.connect(func():
		_condition_tree_command("delete"))
	buttons.add_child(condition_remove)
	for action in ["up", "down"]:
		var move := Button.new()
		move.text = "Move Up" if action == "up" else "Move Down"
		move.pressed.connect(_condition_tree_command.bind(action))
		buttons.add_child(move)
	condition_editor = COMPARISON_EDITOR.new()
	details.add_child(condition_editor)
	condition_editor.setup()
	condition_editor.edited.connect(func(property, value): _edit_comparison(selected_condition, property, value))
	condition_editor.edits_requested.connect(func(values):
		if selected != null and selected_condition != null: resource_edits_requested.emit(selected, selected_condition, values))
	# Retain the legacy selection adapter for older editor integrations.
	condition_tree.hide()
	condition_explanation.hide()
	group_controls.hide()
	condition_list.hide()
	buttons.hide()
	condition_editor.hide()
	conditions_builder = VBoxContainer.new()
	conditions_builder.tooltip_text = "Every condition at this level must be true. Add a Group for nested AND/OR logic."
	details.add_child(conditions_builder)
	var actions_heading := Label.new()
	actions_heading.text = "Actions"
	details.add_child(actions_heading)
	var actions_help := Label.new()
	actions_help.text = ""
	actions_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(actions_help)
	actions_help.hide()
	actions_list = VBoxContainer.new()
	actions_list.tooltip_text = "Effects run only after this transition has been accepted."
	details.add_child(actions_list)
	action_menu = _create_add_button("+ Effect", true) as MenuButton
	action_menu.tooltip_text = "Add a transition Effect"
	for entry in [["Set Property", TransitionAction.ActionType.SET_PROPERTY], ["Toggle Bool", TransitionAction.ActionType.TOGGLE_BOOL], ["Add Value", TransitionAction.ActionType.ADD_VALUE], ["Call Method", TransitionAction.ActionType.CALL_METHOD], ["Emit Signal", TransitionAction.ActionType.EMIT_SIGNAL]]:
		action_menu.get_popup().add_item(entry[0], entry[1])
	action_menu.get_popup().id_pressed.connect(func(id):
		if selected != null: action_add_requested.emit(selected, id))
	var action_footer := _branch(details)
	var action_buttons := HFlowContainer.new()
	action_footer.add_child(action_buttons)
	action_buttons.add_child(action_menu)


func _trigger_line(parent: Node, title: String, property: StringName, node_path: bool) -> Control:
	if node_path:
		var field = NODE_PATH_FIELD.new()
		parent.add_child(field)
		field.setup(title, editor_interface, &"AnimationPlayer")
		field.path_changed.connect(func(value): _commit(property, value))
		return field
	_label(parent, title)
	var picker_row := HBoxContainer.new()
	parent.add_child(picker_row)
	var dropdown := OptionButton.new()
	dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dropdown.item_selected.connect(func(index):
		if dropdown.get_item_metadata(index) is StringName:
			_commit(property, dropdown.get_item_metadata(index)))
	picker_row.add_child(dropdown)
	animation_picker = dropdown
	var manual := LineEdit.new()
	manual.placeholder_text = "Or enter an animation name"
	manual.text_submitted.connect(func(_text): _commit(property, StringName(manual.text.strip_edges())))
	manual.focus_exited.connect(func(): _commit(property, StringName(manual.text.strip_edges())))
	parent.add_child(manual)
	animation_name = manual
	animation_missing = Label.new()
	animation_missing.add_theme_color_override("font_color", Color("e0a040"))
	parent.add_child(animation_missing)
	return manual


func _refresh_input_actions() -> void:
	if selected == null: return
	var names := INPUT_ACTIONS.names()
	var missing := not selected.input_action in names
	if missing: names.push_front(selected.input_action)
	input_action.clear()
	for action in names:
		input_action.add_item("[Missing] " + String(action) if missing and action == selected.input_action else String(action))
		input_action.set_item_metadata(input_action.item_count - 1, action)
		if action == selected.input_action: input_action.select(input_action.item_count - 1)

func _fill_phase4_controls() -> void:
	input_row.visible = selected.trigger_type == StateTransition.TriggerType.INPUT_ACTION
	animation_row.visible = selected.trigger_type == StateTransition.TriggerType.ANIMATION_FINISHED
	watch_row.visible = selected.trigger_type == StateTransition.TriggerType.PROPERTY_WATCH
	if watch_row.visible and selected.watch == null:
		_commit(&"watch", TransitionCondition.new())
	_refresh_input_actions()
	input_mode.select(selected.input_mode)
	if animation_path is LineEdit:
		animation_path.text = selected.animation_player_path
	elif is_instance_valid(animation_path):
		animation_path.set_context(editor_interface, machine, selected.animation_player_path)
	animation_name.text = selected.animation_name
	_refresh_animation_options()
	watch_editor.set_spec(selected.watch)
	condition_list.clear()
	for condition in selected.conditions:
		condition_list.add_item(_condition_description(condition))
	if selected_condition == null or not selected_condition in selected.conditions:
		selected_condition = selected.conditions[0] if not selected.conditions.is_empty() else null
	if selected_condition != null:
		condition_list.select(selected.conditions.find(selected_condition))
	condition_editor.set_spec(selected_condition)
	condition_remove.disabled = selected_condition == null
	condition_editor.set_editor_context(editor_interface, machine)
	_fill_condition_tree()
	condition_list.hide()
	condition_editor.hide()
	group_controls.hide()
	if selected.trigger_type == StateTransition.TriggerType.ANIMATION_FINISHED and animation_path is Control:
		animation_path.set_context(editor_interface, machine, selected.animation_player_path)
		_refresh_animation_options()


func _refresh_animation_options() -> void:
	if not is_instance_valid(animation_picker) or not is_instance_valid(selected):
		return
	var stored := selected.animation_name
	var animations: Array[StringName] = []
	var player: AnimationPlayer
	if is_instance_valid(machine) and is_instance_valid(machine.get_effective_actor()) and not selected.animation_player_path.is_empty():
		var candidate := machine.get_effective_actor().get_node_or_null(selected.animation_player_path)
		if candidate is AnimationPlayer:
			player = candidate
	if is_instance_valid(player):
		if observed_animation_player != player:
			if is_instance_valid(observed_animation_player) and observed_animation_player.animation_list_changed.is_connected(_on_animation_list_changed):
				observed_animation_player.animation_list_changed.disconnect(_on_animation_list_changed)
			observed_animation_player = player
			if not player.animation_list_changed.is_connected(_on_animation_list_changed):
				player.animation_list_changed.connect(_on_animation_list_changed)
		for name in player.get_animation_library_list():
			var library := player.get_animation_library(name)
			if library == null:
				continue
			for animation in library.get_animation_list():
				var full_name := StringName(animation) if name == &"" else StringName("%s/%s" % [name, animation])
				animations.append(full_name)
	animations.sort()
	if not is_instance_valid(player) and is_instance_valid(observed_animation_player):
		if observed_animation_player.animation_list_changed.is_connected(_on_animation_list_changed):
			observed_animation_player.animation_list_changed.disconnect(_on_animation_list_changed)
		observed_animation_player = null
	loading = true
	animation_picker.clear()
	if not stored.is_empty() and not stored in animations:
		animation_picker.add_item("[Missing] " + String(stored))
		animation_picker.set_item_metadata(0, stored)
	for animation in animations:
		animation_picker.add_item(String(animation))
		animation_picker.set_item_metadata(animation_picker.item_count - 1, animation)
		if animation == stored:
			animation_picker.select(animation_picker.item_count - 1)
	if animation_picker.item_count > 0 and animation_picker.selected < 0:
		animation_picker.select(0)
	animation_missing.text = "Stored animation is missing from this AnimationPlayer." if not stored.is_empty() and not stored in animations else ""
	loading = false


func _on_animation_list_changed() -> void:
	_refresh_animation_options()


func _condition_description(condition: TransitionCondition, show_enabled := true) -> String:
	return LABELS.condition_description(condition, show_enabled)


func set_debug_transition(event: Dictionary, accent: Color) -> void:
	debug_event = event
	debug_accent = accent
	_apply_debug_transition()


func _apply_debug_transition() -> void:
	if heading == null: return
	heading.remove_theme_color_override("font_color")
	if selected != null and is_instance_valid(machine) and not debug_event.is_empty() and machine.transitions.find(selected) == debug_event.get("transition_index", -1):
		heading.add_theme_color_override("font_color", debug_accent)


func _select_condition(index: int) -> void:
	if loading or selected == null or index < 0 or index >= selected.conditions.size():
		return
	selected_condition = selected.conditions[index]
	selected_tree_resource = selected_condition
	condition_editor.set_spec(selected_condition)
	condition_remove.disabled = selected_condition == null


func _edit_comparison(condition: TransitionCondition, property: StringName, value: Variant) -> void:
	if not loading and selected != null and condition != null:
		comparison_edit_requested.emit(selected, condition, property, value)


func _fill_condition_tree() -> void:
	condition_tree.clear()
	condition_tree_rows = 0
	condition_list.visible = selected.condition_group != null and not selected.conditions.is_empty()
	if selected.condition_group == null:
		if selected_tree_resource == null and selected_condition != null: selected_tree_resource = selected_condition
		var root := _condition_tree_row(null, null, null, -1, true)
		for index in selected.conditions.size():
			_condition_tree_row(root, selected.conditions[index], null, index, false)
	else:
		_draw_condition_group(null, selected.condition_group, null, -1, true, {}, 0)
	if condition_tree.get_selected() == null:
		condition_tree.get_root().select(0)
	var chosen := condition_tree.get_selected()
	var data: Dictionary = chosen.get_metadata(0)
	selected_tree_resource = data.node
	selected_condition = data.node as TransitionCondition
	condition_editor.set_spec(selected_condition)
	condition_remove.disabled = data.root
	_fill_group_controls()


func _condition_tree_row(parent: TreeItem, node: Resource, group: TransitionConditionGroup, index: int, root: bool) -> TreeItem:
	condition_tree_rows += 1
	var item := condition_tree.create_item(parent)
	item.set_metadata(0, {"node": node, "parent": group, "index": index, "root": root})
	if node == null and root or node is TransitionConditionGroup:
		item.set_cell_mode(0, TreeItem.CELL_MODE_STRING)
		var all: bool = node == null or node.operator == 0
		item.set_text(0, "%s%s%s · %d" % ["Off · " if node != null and not node.enabled else "", "NOT " if node != null and node.negated else "", "ALL" if all else "ANY", node.children.size() if node != null else selected.conditions.size()])
		item.set_tooltip_text(0, "All children must match (AND)." if all else "At least one child must match (OR).")
		item.set_icon(0, ICONS.get_icon(self, "ALL" if all else "ANY"))
		item.set_range_config(0, 0, 1, 1)
		item.set_range(0, node.operator if node != null else 0)
		item.set_editable(0, false)
	elif node is TransitionCondition:
		item.set_icon(0, ICONS.get_icon(self, "Condition"))
		item.set_text(0, _condition_description(node))
		item.set_tooltip_text(0, _condition_description(node))
		var problem := preload("res://addons/state_machine/runtime/property_comparison.gd").warning(machine.get_effective_actor(), node) if is_instance_valid(machine) else ""
		if not problem.is_empty():
			item.set_text(0, item.get_text(0) + " · " + problem)
			item.set_tooltip_text(0, _condition_description(node) + "\n" + problem)
			if has_theme_icon("NodeWarning", "EditorIcons"): item.set_icon(0, get_theme_icon("NodeWarning", "EditorIcons"))
	else:
		item.set_text(0, "Invalid condition resource")
	for column in [1, 2]:
		item.set_cell_mode(column, TreeItem.CELL_MODE_CHECK)
		item.set_checked(column, (node.enabled if column == 1 else node.negated) if node is TransitionCondition or node is TransitionConditionGroup else column == 1)
		item.set_editable(column, node is TransitionCondition or node is TransitionConditionGroup or root)
		item.set_tooltip_text(column, "Include this row in evaluation." if column == 1 else "NOT: reverse this valid condition or entire group.")
	if node == selected_tree_resource: item.select(0)
	return item


func _draw_condition_group(parent: TreeItem, node: Resource, group: TransitionConditionGroup, index: int, root: bool, path: Dictionary, depth: int) -> void:
	if condition_tree_rows >= LOGIC.MAX_NODES: return
	var item := _condition_tree_row(parent, node, group, index, root)
	if not node is TransitionConditionGroup: return
	if path.has(node) or depth > LOGIC.MAX_DEPTH:
		item.set_cell_mode(0, TreeItem.CELL_MODE_STRING)
		item.set_text(0, "Invalid cycle/depth")
		item.set_editable(0, false)
		return
	path[node] = true
	for child_index in node.children.size():
		_draw_condition_group(item, node.children[child_index], node, child_index, false, path, depth + 1)
		if condition_tree_rows >= LOGIC.MAX_NODES: break
	path.erase(node)


func _select_condition_tree() -> void:
	if loading or selected == null: return
	var item := condition_tree.get_selected()
	if item == null: return
	var data: Dictionary = item.get_metadata(0)
	selected_tree_resource = data.node
	selected_condition = data.node as TransitionCondition
	condition_editor.set_spec(selected_condition)
	condition_remove.disabled = data.root
	_fill_group_controls()
	condition_editor.hide()
	group_controls.hide()


func _fill_group_controls() -> void:
	var was_loading := loading
	loading = true
	group_controls.visible = selected_tree_resource == null or selected_tree_resource is TransitionConditionGroup
	if group_controls.visible:
		group_match.select(selected_tree_resource.operator if selected_tree_resource != null else 0)
		group_enabled.button_pressed = selected_tree_resource.enabled if selected_tree_resource != null else true
		group_not.button_pressed = selected_tree_resource.negated if selected_tree_resource != null else false
	loading = was_loading


func _condition_tree_edited() -> void:
	if loading or selected == null: return
	var item := condition_tree.get_edited()
	if item == null: return
	var data: Dictionary = item.get_metadata(0)
	var column := condition_tree.get_edited_column()
	var property: StringName = &"operator" if column == 0 else (&"enabled" if column == 1 else &"negated")
	var value: Variant = int(item.get_range(0)) if column == 0 else item.is_checked(column)
	condition_node_edit_requested.emit(selected, data.node, property, value)


func _condition_tree_command(action: String) -> void:
	if selected == null: return
	var item := condition_tree.get_selected()
	var node: Resource
	var parent: TransitionConditionGroup
	if item != null:
		var data: Dictionary = item.get_metadata(0)
		node = data.node
		parent = data.parent
		if action in ["delete", "up", "down"] and data.root: return
	if action in ["add_condition", "add_group", "add_any_group"] and node is TransitionConditionGroup: parent = node
	condition_tree_action_requested.emit(selected, parent, action, node)


func _clear_builder(parent: Control) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _branch(parent: Control) -> VBoxContainer:
	var guide := preload("res://addons/state_machine/editor/expression_branch.gd").new()
	parent.add_child(guide)
	var content := VBoxContainer.new()
	guide.add_child(content)
	return content


func _small_button(parent: Control, text: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _create_add_button(text: String, menu := false) -> Button:
	var button: Button = MenuButton.new() if menu else Button.new()
	button.text = text
	button.flat = false
	button.theme_type_variation = &"Button"
	button.custom_minimum_size.y = 28
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.size_flags_vertical = Control.SIZE_FILL
	return button


func _fill_inline_conditions() -> void:
	var shape := str(selected.get_instance_id()) + ":" + _condition_shape(selected.condition_group, {}, 0)
	for condition in selected.conditions: shape += ":" + str(condition.get_instance_id() if condition != null else 0)
	if shape == conditions_shape:
		for row in inline_condition_rows: row.set_spec(row.spec)
		for entry in inline_groups:
			var group: TransitionConditionGroup = entry.resource
			if entry.get("picker") != null: entry.picker.select(group.operator)
			if entry.get("enabled") != null:
				entry.enabled.set_pressed_no_signal(group.enabled)
				entry.negated.set_pressed_no_signal(group.negated)
				entry.disclosure.text = "NOT" if group.negated else ("Off" if not group.enabled else ">")
		return
	conditions_shape = shape
	_clear_builder(conditions_builder)
	inline_condition_rows.clear()
	inline_groups.clear()
	builder_rebuilds += 1
	if selected == null: return
	var root := selected.condition_group
	# Legacy arrays and an expression tree are evaluated together as ALL.
	if root != null and (root.operator != TransitionConditionGroup.Operator.AND or root.negated or not root.enabled):
		_inline_group(conditions_builder, null, null, true)
	elif not selected.conditions.is_empty() and root != null:
		_inline_group(conditions_builder, null, null, true)
	else:
		_inline_group(conditions_builder, root, null, true)


func _condition_shape(node: Resource, path: Dictionary, depth: int) -> String:
	if node == null: return "legacy"
	if path.has(node.get_instance_id()) or depth > LOGIC.MAX_DEPTH: return "cycle"
	var shape := str(node.get_instance_id())
	if node is TransitionConditionGroup:
		shape += "/%s/%s/%s" % [node.operator, node.negated, node.enabled]
		var next := path.duplicate()
		next[node.get_instance_id()] = true
		for child in node.children: shape += "/" + _condition_shape(child, next, depth + 1)
	return shape


func _inline_group(parent_control: Control, group: TransitionConditionGroup, parent_group: TransitionConditionGroup, root: bool, path: Dictionary = {}, depth := 0) -> void:
	if depth > LOGIC.MAX_DEPTH or inline_condition_rows.size() >= LOGIC.MAX_NODES: return
	if group != null and path.has(group.get_instance_id()):
		_label(parent_control, "Cyclic group")
		return
	var next_path := path.duplicate()
	if group != null: next_path[group.get_instance_id()] = true
	var header := HFlowContainer.new()
	if not root: parent_control.add_child(header)
	var match_mode := OptionButton.new()
	match_mode.add_item("AND GROUP", 0)
	match_mode.add_item("OR GROUP", 1)
	match_mode.select(group.operator if group != null else 0)
	match_mode.tooltip_text = "All conditions inside this group must be true." if group == null or group.operator == 0 else "At least one condition inside this group must be true."
	match_mode.item_selected.connect(func(index): condition_node_edit_requested.emit(selected, group, &"operator", index))
	var advanced := HFlowContainer.new()
	var disclosure := Button.new()
	disclosure.text = "NOT" if group != null and group.negated else ("Off" if group != null and not group.enabled else ">")
	disclosure.toggle_mode = true
	disclosure.tooltip_text = "Advanced group settings"
	disclosure.toggled.connect(func(open): advanced.visible = open)
	if not root:
		header.add_child(match_mode)
		header.add_child(disclosure)
		parent_control.add_child(advanced)
		advanced.hide()
	else:
		match_mode.free()
		disclosure.free()
		advanced.free()
		header.free()
	var controls := {"resource": group, "picker": match_mode if not root else null, "disclosure": disclosure if not root else null}
	for property in ([] if root else [&"enabled", &"negated"]):
		var box := CheckBox.new()
		box.text = "NOT" if property == &"negated" else "Enabled"
		box.tooltip_text = "NOT" if property == &"negated" else "Enabled (unchecked means disabled)"
		box.button_pressed = group.get(property) if group != null else property == &"enabled"
		box.toggled.connect(func(value): condition_node_edit_requested.emit(selected, group, property, value))
		advanced.add_child(box)
		controls["negated" if property == &"negated" else "enabled"] = box
	inline_groups.append(controls)
	if not root:
		_small_button(header, "x", "Remove group", func(): condition_tree_action_requested.emit(selected, parent_group, "delete", group))
		if group == selected.condition_group and (group.operator != 0 or group.negated or not group.enabled):
			match_mode.tooltip_text = "Existing root group: its OR/NOT/Disabled settings are preserved."
	var children: Array[Resource] = []
	children.assign(group.children if group != null else selected.conditions)
	if group == null and selected.condition_group != null: children.append(selected.condition_group)
	if children.is_empty(): _label(parent_control, "No additional conditions.")
	for child in children:
		if inline_condition_rows.size() >= LOGIC.MAX_NODES: break
		var branch := _branch(parent_control)
		if child is TransitionCondition:
			_inline_condition(branch, child, group)
		elif child is TransitionConditionGroup:
			_inline_group(branch, child, group, false, next_path, depth + 1)
		else:
			_label(branch, "Invalid condition")
	var footer := HFlowContainer.new()
	_branch(parent_control).add_child(footer)
	_add_controls(footer, group)


func _inline_condition(parent: Control, condition: TransitionCondition, group: TransitionConditionGroup) -> void:
	var row = COMPARISON_EDITOR.new()
	row.auto_normalize = not navigation_read_only
	parent.add_child(row)
	row.setup()
	row.set_editor_context(editor_interface, machine)
	row.set_spec(condition)
	inline_condition_rows.append(row)
	row.edits_requested.connect(func(values): resource_edits_requested.emit(selected, condition, values))
	_small_button(row.expression, "x", "Remove condition", func():
		if condition in selected.conditions: condition_remove_requested.emit(selected, condition)
		else: condition_tree_action_requested.emit(selected, group, "delete", condition))


func _add_controls(footer: Control, group: TransitionConditionGroup) -> void:
	var add := _create_add_button("+ Condition")
	add.tooltip_text = "Add a Condition at this level"
	add.pressed.connect(func():
		condition_tree_action_requested.emit(selected, group, "add_condition", null))
	footer.add_child(add)
	add.disabled = selected.get_meta("initial_fallback", false)
	var add_group := _create_add_button("+ Group", true) as MenuButton
	add_group.tooltip_text = "Add a nested AND/OR Group"
	add_group.get_popup().add_item("AND", 0)
	add_group.get_popup().add_item("OR", 1)
	add_group.get_popup().id_pressed.connect(func(id):
		condition_tree_action_requested.emit(selected, group, "add_group" if id == 0 else "add_any_group", null))
	add_group.disabled = add.disabled
	footer.add_child(add_group)


func _fill_actions() -> void:
	if actions_list == null: return
	var shape := "%s/%s" % [selected.get_instance_id(), selected.source_mode]
	for action in selected.actions:
		if action is TransitionAction:
			shape += ":%s/%s/%s" % [action.get_instance_id(), action.action_type, action.timing]
			if action.action_type in [TransitionAction.ActionType.CALL_METHOD, TransitionAction.ActionType.EMIT_SIGNAL]:
				shape += "/%s/%s/%s/%s" % [action.target_mode, action.target_path, action.method_name, action.signal_name]
	if shape == actions_shape:
		for row in inline_action_rows: row.set_action(row.action, selected)
		for action in action_enabled_controls: action_enabled_controls[action].set_pressed_no_signal(action.enabled)
		return
	actions_shape = shape
	_clear_builder(actions_list)
	inline_action_rows.clear()
	action_enabled_controls.clear()
	if selected == null: return
	action_menu.visible = selected.source_mode != StateTransition.SourceMode.HIERARCHY_ENTRY
	if not action_menu.visible: return
	if selected.actions.is_empty(): _label(actions_list, "No effects.")
	for phase in 3:
		var phase_actions: Array[TransitionAction] = []
		for resource in selected.actions:
			if resource is TransitionAction and resource.timing == phase: phase_actions.append(resource)
		if phase_actions.is_empty(): continue
		_label(actions_list, ["BEFORE EXIT", "AFTER EXIT", "AFTER ENTER"][phase])
		for index in phase_actions.size():
			_branch(actions_list).add_child(_action_row(phase_actions[index], index, phase_actions.size()))


func _action_row(action: TransitionAction, index: int, count: int) -> Control:
	var panel := VBoxContainer.new()
	var top := HFlowContainer.new()
	panel.add_child(top)
	top.hide()
	var enabled_box := CheckBox.new()
	enabled_box.text = "Effect Enabled"
	enabled_box.button_pressed = action.enabled
	enabled_box.tooltip_text = "Enabled" if action.enabled else "Disabled"
	enabled_box.toggled.connect(func(value): action_edit_requested.emit(selected, action, &"enabled", value))
	action_enabled_controls[action] = enabled_box
	top.add_child(enabled_box)
	var timing := OptionButton.new()
	timing.tooltip_text = "Effect Timing"
	for label in ["BEFORE EXIT", "AFTER EXIT", "AFTER ENTER"]: timing.add_item(label)
	timing.select(action.timing)
	timing.item_selected.connect(func(value): action_edit_requested.emit(selected, action, &"timing", value))
	top.add_child(timing)
	var type_picker := OptionButton.new()
	type_picker.tooltip_text = "Effect Type"
	for label in ["Set Property", "Toggle Bool", "Add Value", "Call Method", "Emit Signal"]: type_picker.add_item(label)
	type_picker.select(action.action_type)
	type_picker.item_selected.connect(func(value): _change_action_type(action, value))
	top.add_child(type_picker)
	for direction in [-1, 1]:
		var button := _small_button(top, "^" if direction < 0 else "v", "Move Up" if direction < 0 else "Move Down", func(): action_move_requested.emit(selected, action, direction))
		button.disabled = index == 0 if direction < 0 else index == count - 1
	_small_button(top, "x", "Remove Effect", func(): action_remove_requested.emit(selected, action))
	if action.action_type in [TransitionAction.ActionType.SET_PROPERTY, TransitionAction.ActionType.TOGGLE_BOOL, TransitionAction.ActionType.ADD_VALUE]:
		var row = COMPARISON_EDITOR.new()
		row.auto_normalize = not navigation_read_only
		panel.add_child(row)
		row.setup(false)
		row.set_editor_context(editor_interface, machine)
		row.set_action(action, selected)
		for control in top.get_children():
			if control is Button and not control is OptionButton and not control is CheckBox:
				control.reparent(row.expression)
		action_enabled_controls[action] = row.enabled
		enabled_box.free()
		top.reparent(row.advanced)
		top.show()
		row.edits_requested.connect(func(values): resource_edits_requested.emit(selected, action, values))
		inline_action_rows.append(row)
	else:
		var expression := HFlowContainer.new()
		panel.add_child(expression)
		var verb := Label.new()
		verb.text = "Call" if action.action_type == TransitionAction.ActionType.CALL_METHOD else "Emit"
		expression.add_child(verb)
		var target := OptionButton.new()
		for label in ["Actor", "FSM", "Source State", "Destination State", "Node Path"]: target.add_item(label)
		target.select(action.target_mode)
		target.item_selected.connect(func(value): action_edit_requested.emit(selected, action, &"target_mode", value))
		expression.add_child(target)
		var field: StringName = &"method_name" if action.action_type == TransitionAction.ActionType.CALL_METHOD else &"signal_name"
		var member := LineEdit.new()
		member.text = String(action.get(field)) + ("()" if field == &"method_name" and not String(action.get(field)).is_empty() else "")
		member.placeholder_text = "method()" if field == &"method_name" else "signal"
		member.custom_minimum_size.x = 110
		member.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		member.text_submitted.connect(func(_text): action_edit_requested.emit(selected, action, field, StringName(member.text.trim_suffix("()").strip_edges())))
		member.focus_exited.connect(func(): action_edit_requested.emit(selected, action, field, StringName(member.text.trim_suffix("()").strip_edges())))
		expression.add_child(member)
		var disclosure := Button.new()
		disclosure.text = "Off" if not action.enabled else ">"
		disclosure.toggle_mode = true
		disclosure.tooltip_text = "Advanced: Effect type, timing and Enabled"
		disclosure.toggled.connect(func(open): top.visible = open)
		expression.add_child(disclosure)
		for control in top.get_children():
			if control is Button and not control is OptionButton and not control is CheckBox:
				control.reparent(expression)
		panel.move_child(top, panel.get_child_count() - 1)
		if action.target_mode == TransitionAction.TargetMode.NODE_PATH:
			var path_field = NODE_PATH_FIELD.new()
			panel.add_child(path_field)
			path_field.setup("Target Node", editor_interface, &"Node")
			path_field.set_context(editor_interface, machine, action.target_path)
			path_field.path_changed.connect(func(value): action_edit_requested.emit(selected, action, &"target_path", value))
	return panel


func _change_action_type(action: TransitionAction, kind: int) -> void:
	if action.action_type == kind: return
	var changes := {&"action_type": kind}
	if kind in [TransitionAction.ActionType.SET_PROPERTY, TransitionAction.ActionType.ADD_VALUE, TransitionAction.ActionType.TOGGLE_BOOL]:
		var probe = COMPARISON_EDITOR.new()
		probe.machine = machine
		probe.action = action
		probe.transition = selected
		var metadata: Dictionary = probe._metadata()
		probe.free()
		var type: int = metadata.get("type", TYPE_NIL)
		if kind == TransitionAction.ActionType.ADD_VALUE and type not in [TYPE_INT, TYPE_FLOAT] or kind == TransitionAction.ActionType.TOGGLE_BOOL and type != TYPE_BOOL:
			changes[&"property_path"] = NodePath()
			changes[&"value"] = 0 if kind == TransitionAction.ActionType.ADD_VALUE else false
		elif type in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME] and typeof(action.value) != type:
			changes[&"value"] = preload("res://addons/state_machine/editor/property_catalog.gd").default_value(type)
	resource_edits_requested.emit(selected, action, changes)
