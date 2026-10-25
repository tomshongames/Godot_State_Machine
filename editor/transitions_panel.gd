@tool
extends VBoxContainer

signal transition_selected(transition: StateTransition)
signal pair_selected(from: StringName, to: StringName, mode: int)
signal delete_requested(transition: StateTransition)
signal create_requested(machine: FiniteStateMachine, from: StringName, to: StringName, mode: int, trigger: int)
const LABELS := preload("res://addons/state_machine/runtime/transition_labels.gd")
const ICONS := preload("res://addons/state_machine/editor/editor_icons.gd")
const COLORS := preload("res://addons/state_machine/editor/transition_colors.gd")
var machine: FiniteStateMachine
var tree: Tree
var add_button: Button
var quick_add: MenuButton
var empty: Label
var dialog: ConfirmationDialog
var source: OptionButton
var destination: OptionButton
var trigger: OptionButton
var dialog_machine: FiniteStateMachine
var syncing := false
var selected: StateTransition
var resource_rows: Dictionary = {}
var pair_rows: Dictionary = {}
var debug_event: Dictionary = {}
var debug_accent := Color.TRANSPARENT
var fallback_entry: StateTransition
var delete_icon: Texture2D

func setup() -> void:
	var create_heading := Label.new()
	create_heading.text = "CREATE"
	add_child(create_heading)
	var create_row := HBoxContainer.new()
	add_child(create_row)
	add_button = Button.new()
	add_button.text = "+ Transition"
	add_button.tooltip_text = "Choose From, To and Trigger, then edit details in the Inspector."
	add_button.pressed.connect(open_create)
	add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(add_button)
	quick_add = MenuButton.new()
	quick_add.text = "▼"
	quick_add.tooltip_text = "Choose a trigger to start a new transition."
	for type in [0, 1, 2, 3, 4, 5, 7]:
		quick_add.get_popup().add_icon_item(ICONS.trigger_icon(self, type), String(StateTransition.TriggerType.find_key(type)).capitalize(), type)
	quick_add.get_popup().id_pressed.connect(open_create)
	create_row.add_child(quick_add)
	var browse_heading := Label.new()
	browse_heading.text = "EXISTING"
	add_child(browse_heading)
	empty = Label.new()
	empty.text = "No transitions yet.\nUse + Transition to connect States."
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(empty)
	tree = Tree.new()
	tree.hide_root = true
	var scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	tree.add_theme_constant_override("draw_guides", 1)
	tree.add_theme_constant_override("draw_relationship_lines", 1)
	tree.add_theme_constant_override("indent", roundi(20 * scale))
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 100
	tree.item_selected.connect(_selected)
	delete_icon = ICONS.get_icon(self, "GuiClose")
	if delete_icon == null:
		var icon_image := Image.new()
		icon_image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><path d="M4 4l8 8M12 4l-8 8" stroke="#c4c9d1" stroke-width="2"/></svg>')
		delete_icon = ImageTexture.create_from_image(icon_image)
	tree.button_clicked.connect(func(item: TreeItem, column: int, id: int, mouse_button: int):
		if syncing or column != 0 or id != 0 or mouse_button != MOUSE_BUTTON_LEFT: return
		var transition: StateTransition = item.get_metadata(0)
		if is_instance_valid(machine) and transition != null and (transition in machine.transitions or transition == fallback_entry):
			delete_requested.emit(transition))
	add_child(tree)
	dialog = ConfirmationDialog.new()
	dialog.title = "Create Transition"
	dialog.ok_button_text = "Create"
	dialog.confirmed.connect(_confirm_create)
	add_child(dialog)
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 300
	dialog.add_child(form)
	source = _picker(form, "FROM")
	destination = _picker(form, "TO")
	trigger = _picker(form, "TRIGGER")
	for type in [0, 1, 2, 3, 4, 5, 7]:
		trigger.add_icon_item(ICONS.trigger_icon(self, type), String(StateTransition.TriggerType.find_key(type)).capitalize(), type)
	source.item_selected.connect(func(_index): _validate_dialog())
	destination.item_selected.connect(func(_index): _validate_dialog())

func _picker(parent: Node, title: String) -> OptionButton:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var picker := OptionButton.new()
	picker.expand_icon = true
	picker.add_theme_constant_override("icon_max_width", roundi(16 * (EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0)))
	parent.add_child(picker)
	return picker

static func pair_key(from: StringName, to: StringName, mode: int) -> String:
	return "%d|%s|%s" % [mode, String(from).to_lower() if mode == StateTransition.SourceMode.STATE else "", String(to).to_lower()]

func rebuild(value: FiniteStateMachine) -> void:
	if machine != value:
		selected = null
		if is_instance_valid(dialog): dialog.hide()
	machine = value
	syncing = true
	var collapsed := {}
	for key in pair_rows: collapsed[key] = pair_rows[key].collapsed
	tree.clear()
	resource_rows.clear()
	pair_rows.clear()
	var root := tree.create_item()
	add_button.disabled = not is_instance_valid(machine)
	quick_add.disabled = add_button.disabled
	empty.text = "No State Machine selected." if not is_instance_valid(machine) else "No transitions."
	if is_instance_valid(machine):
		var visible: Array[StateTransition] = machine.transitions.duplicate()
		if fallback_entry != null: visible.append(fallback_entry)
		for transition in visible:
			if transition == null: continue
			var key := pair_key(transition.from_state, transition.target_key(), transition.source_mode)
			if not pair_rows.has(key):
				var pair := tree.create_item(root)
				pair.set_metadata(0, transition)
				pair.set_text(0, "%s → %s" % [transition.source_label(), transition.target_label()])
				pair.set_icon(0, ICONS.get_icon(self, "Transition"))
				pair.set_icon_max_width(0, roundi(16 * (EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0)))
				pair.collapsed = collapsed.get(key, false)
				pair_rows[key] = pair
			var row := tree.create_item(pair_rows[key])
			_update_transition_row(row, transition)
			row.set_metadata(0, transition)
			row.add_button(0, delete_icon, 0, false, "Delete this transition (Undo available)")
			row.add_button(0, COLORS.swatch(COLORS.source_color(transition, machine)), 1, true, "Transition color")
			resource_rows[transition] = row
	for pair in pair_rows.values():
		pair.set_text(0, pair.get_text(0) + " [%d]" % pair.get_child_count())
	empty.visible = resource_rows.is_empty()
	syncing = false
	if selected != null and resource_rows.has(selected): select_transition(selected)
	else: selected = null
	set_debug_transition(debug_event, debug_accent)

func _update_transition_row(row: TreeItem, transition: StateTransition) -> void:
	row.set_text(0, ("Off · " if not transition.enabled else "") + trigger_summary(transition))
	row.set_icon(0, ICONS.transition_icon(self, machine, transition))
	row.set_icon_max_width(0, roundi(16 * (EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0)))
	row.set_tooltip_text(0, "Priority %d · Select to edit this logical transition." % transition.priority)

func update_transition(transition: StateTransition) -> void:
	if resource_rows.has(transition): _update_transition_row(resource_rows[transition], transition)

func update_colors(changed: StateTransition = null) -> void:
	for route in resource_rows:
		if changed != null and route != changed: continue
		resource_rows[route].set_button(0, 1, COLORS.swatch(COLORS.source_color(route, machine)))

func set_debug_transition(event: Dictionary, accent: Color) -> void:
	debug_event = event
	debug_accent = accent
	for transition in resource_rows:
		var matches: bool = not event.is_empty() and is_instance_valid(machine) and machine.transitions.find(transition) == event.get("transition_index", -1)
		resource_rows[transition].set_custom_bg_color(0, Color(accent.r, accent.g, accent.b, 0.25) if matches else Color.TRANSPARENT)

func _selected() -> void:
	if syncing: return
	var item := tree.get_selected()
	if item != null and item.get_parent() == tree.get_root():
		var route: StateTransition = item.get_metadata(0)
		selected = null
		pair_selected.emit(route.from_state, route.target_key(), route.source_mode)
		return
	if item != null and item.get_metadata(0) is StateTransition:
		selected = item.get_metadata(0)
		transition_selected.emit(selected)

func select_transition(transition: StateTransition) -> void:
	if not resource_rows.has(transition): return
	syncing = true
	selected = transition
	var row: TreeItem = resource_rows[transition]
	row.get_parent().collapsed = false
	row.select(0)
	tree.scroll_to_item(row)
	syncing = false

func select_pair(from: StringName, to: StringName, mode: int) -> void:
	var key := pair_key(from, to, mode)
	if not pair_rows.has(key): return
	var pair: TreeItem = pair_rows[key]
	if pair.get_child_count() == 1:
		select_transition(pair.get_metadata(0))
		transition_selected.emit(selected)
	else:
		focus_pair(from, to, mode)
		pair_selected.emit(from, to, mode)

func focus_pair(from: StringName, to: StringName, mode: int) -> void:
	clear_selection()
	var key := pair_key(from, to, mode)
	if not pair_rows.has(key): return
	syncing = true
	var pair: TreeItem = pair_rows[key]
	pair.collapsed = false
	pair.select(0)
	tree.scroll_to_item(pair)
	syncing = false

func clear_selection() -> void:
	syncing = true
	selected = null
	tree.deselect_all()
	syncing = false

func open_create(initial_trigger := StateTransition.TriggerType.MANUAL) -> void:
	if not is_instance_valid(machine): return
	dialog_machine = machine
	source.clear()
	destination.clear()
	source.add_icon_item(preload("res://addons/state_machine/icons/any_state.svg"), "Any State")
	source.set_item_metadata(0, {"name": &"", "mode": StateTransition.SourceMode.ANY_STATE})
	if machine.has_hierarchy_boundary():
		source.add_item("ENTRY")
		source.set_item_metadata(source.item_count - 1, {"name": &"", "mode": StateTransition.SourceMode.HIERARCHY_ENTRY})
	for state in machine.get_state_container().get_children():
		if not state is State: continue
		var icon := preload("res://addons/state_machine/icons/hierarchy_state.svg") if state is HierarchyState else preload("res://addons/state_machine/icons/state.svg")
		source.add_icon_item(icon, String(state.name))
		source.set_item_metadata(source.item_count - 1, {"name": state.name, "mode": StateTransition.SourceMode.STATE})
		destination.add_icon_item(icon, String(state.name))
		destination.set_item_metadata(destination.item_count - 1, state.name)
	if machine.has_hierarchy_boundary():
		destination.add_item("EXIT")
		destination.set_item_metadata(destination.item_count - 1, StateTransition.EXIT_TARGET)
	for picker in [source, destination]:
		for index in picker.item_count:
			picker.get_popup().set_item_icon_max_width(index, roundi(16 * (EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0)))
	if selected != null and selected in machine.transitions:
		for index in source.item_count:
			var data: Dictionary = source.get_item_metadata(index)
			if data.mode == selected.source_mode and (data.mode == StateTransition.SourceMode.ANY_STATE or data.name == selected.from_state): source.select(index)
		for index in destination.item_count:
			if destination.get_item_metadata(index) == selected.target_key(): destination.select(index)
	elif source.item_count > 1:
		source.select(1)
		if destination.item_count > 1: destination.select(1)
	trigger.select(maxi(trigger.get_item_index(initial_trigger), 0))
	_validate_dialog()
	dialog.popup_centered()

func _validate_dialog() -> void:
	if is_instance_valid(machine) and source.item_count > 0:
		var data: Dictionary = source.get_selected_metadata()
		trigger.disabled = data.mode == StateTransition.SourceMode.HIERARCHY_ENTRY
	var valid := is_instance_valid(dialog_machine) and dialog_machine == machine and destination.item_count > 0
	if valid:
		var data: Dictionary = source.get_selected_metadata()
		var names := {}
		for state in dialog_machine.get_state_container().get_children():
			if state is State: names[state.name] = true
		var to: Variant = destination.get_selected_metadata()
		valid = (names.has(to) or to == StateTransition.EXIT_TARGET and machine.has_hierarchy_boundary() and data.mode != StateTransition.SourceMode.HIERARCHY_ENTRY) and (data.mode in [StateTransition.SourceMode.ANY_STATE, StateTransition.SourceMode.HIERARCHY_ENTRY] or names.has(data.name))
	dialog.get_ok_button().disabled = not valid

func open_create_for_source(from: StringName, mode: int, to: StringName = &"") -> void:
	open_create()
	if not is_instance_valid(machine): return
	for index in source.item_count:
		var data: Dictionary = source.get_item_metadata(index)
		if data.mode == mode and (mode == StateTransition.SourceMode.ANY_STATE or data.name == from):
			source.select(index)
			break
	if to.is_empty():
		destination.add_item("Choose destination")
		destination.set_item_metadata(destination.item_count - 1, &"")
		destination.select(destination.item_count - 1)
	else:
		for index in destination.item_count:
			if destination.get_item_metadata(index) == to: destination.select(index)
	_validate_dialog()

func _confirm_create() -> void:
	_validate_dialog()
	if dialog.get_ok_button().disabled: return
	var data: Dictionary = source.get_selected_metadata()
	create_requested.emit(dialog_machine, data.name, destination.get_selected_metadata(), data.mode, trigger.get_selected_id())

static func trigger_summary(transition: StateTransition) -> String:
	if transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: return "Entry Route · priority %d%s" % [transition.priority, " · Initial State fallback" if transition.get_meta("initial_fallback", false) else ""]
	match transition.trigger_type:
		StateTransition.TriggerType.EVENT: return "Event · %s" % (String(transition.event_name) if not transition.event_name.is_empty() else "Choose event")
		StateTransition.TriggerType.TIMER: return "Timer · %.2f s" % transition.duration
		StateTransition.TriggerType.INPUT_ACTION: return "Input · %s · %s" % [transition.input_action if not transition.input_action.is_empty() else "Choose action", ["Pressed", "Released", "Held"][clampi(transition.input_mode, 0, 2)]]
		StateTransition.TriggerType.ANIMATION_FINISHED: return "Animation · %s" % (String(transition.animation_name) if not transition.animation_name.is_empty() else "Choose animation")
		StateTransition.TriggerType.PROPERTY_WATCH: return "Watch · %s" % LABELS.condition_description(transition.watch)
		StateTransition.TriggerType.SIGNAL: return "Signal · %s.%s" % ["Actor" if transition.signal_source_mode == StateTransition.SignalSourceMode.ACTOR else String(transition.signal_source_path).get_file(), transition.signal_name if not transition.signal_name.is_empty() else "Choose signal"]
	return "Manual"
