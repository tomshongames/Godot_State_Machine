@tool
extends VBoxContainer

const CATALOG := preload("res://addons/state_machine/editor/property_catalog.gd")
const NODE_PATH_FIELD := preload("res://addons/state_machine/editor/node_path_field.gd")
const COMPARISON := preload("res://addons/state_machine/runtime/property_comparison.gd")
enum Mode { COMPARISON, ASSIGN, ADD, TOGGLE }
signal edited(property: StringName, value: Variant)
signal edits_requested(values: Dictionary)
var spec: TransitionCondition
var action: TransitionAction
var transition: StateTransition
var machine: FiniteStateMachine
var editor_interface: EditorInterface
var mode := Mode.COMPARISON
var loading := false
var inferred_type := TYPE_NIL
var enabled: CheckBox
var negated: CheckBox
var target_mode: OptionButton
var target_row: VBoxContainer
var target_path
var property_path: LineEdit
var property_picker: Button
var property_menu: PopupMenu
var operator: OptionButton
var value_type: OptionButton
var value_bool: OptionButton
var value_number: SpinBox
var value_text: LineEdit
var expression: HFlowContainer
var value_field: StringName = &"comparison_value"
var normalized_bindings := {}
var auto_normalize := true
var advanced: VBoxContainer
var advanced_button: Button
var property_tools: HFlowContainer
var property_field: HBoxContainer


func setup(with_enabled := true) -> void:
	advanced = VBoxContainer.new()
	var flags := HFlowContainer.new()
	advanced.add_child(flags)
	enabled = CheckBox.new()
	enabled.text = "Enabled"
	enabled.tooltip_text = "Enabled (unchecked means disabled)"
	enabled.visible = with_enabled
	enabled.toggled.connect(func(value): _commit(&"enabled", value))
	flags.add_child(enabled)
	negated = CheckBox.new()
	negated.text = "NOT"
	negated.visible = with_enabled
	negated.toggled.connect(func(value): _commit(&"negated", value))
	flags.add_child(negated)
	expression = HFlowContainer.new()
	expression.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(expression)
	target_mode = OptionButton.new()
	target_mode.tooltip_text = "Target"
	target_mode.item_selected.connect(func(index): _request({&"target_mode": target_mode.get_item_id(index)}))
	advanced.add_child(target_mode)
	value_type = OptionButton.new()
	for entry in [["bool", TYPE_BOOL], ["int", TYPE_INT], ["float", TYPE_FLOAT], ["String", TYPE_STRING]]:
		value_type.add_item(entry[0], entry[1])
	value_type.tooltip_text = "Inferred type; choose manually for an unknown property"
	value_type.item_selected.connect(_change_type)
	expression.add_child(value_type)
	property_path = LineEdit.new()
	property_path.placeholder_text = "Property..."
	property_path.custom_minimum_size.x = 90
	property_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	property_path.text_submitted.connect(func(_text): _request({&"property_path": NodePath(property_path.text.strip_edges())}))
	property_path.focus_exited.connect(func(): _request({&"property_path": NodePath(property_path.text.strip_edges())}))
	property_field = HBoxContainer.new()
	property_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	property_field.add_child(property_path)
	expression.add_child(property_field)
	property_picker = Button.new()
	property_picker.text = "Pick..."
	property_picker.tooltip_text = "Choose a property on the target"
	property_picker.pressed.connect(_pick_property)
	expression.add_child(property_picker)
	expression.move_child(property_picker, 0)
	property_tools = HFlowContainer.new()
	add_child(property_tools)
	property_tools.hide()
	property_menu = PopupMenu.new()
	add_child(property_menu)
	property_menu.id_pressed.connect(_property_menu_selected)
	operator = OptionButton.new()
	operator.item_selected.connect(func(index): _commit(&"comparison_operator", operator.get_item_id(index)))
	expression.add_child(operator)
	value_bool = OptionButton.new()
	value_bool.add_item("False", 0)
	value_bool.add_item("True", 1)
	value_bool.item_selected.connect(func(index): _commit(value_field, index == 1))
	expression.add_child(value_bool)
	value_number = SpinBox.new()
	value_number.min_value = -1e12
	value_number.max_value = 1e12
	value_number.allow_greater = true
	value_number.allow_lesser = true
	value_number.custom_minimum_size.x = 85
	value_number.value_changed.connect(func(value): _commit(value_field, int(value) if _display_type() == TYPE_INT else value))
	expression.add_child(value_number)
	value_text = LineEdit.new()
	value_text.custom_minimum_size.x = 85
	value_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_text.text_submitted.connect(func(_text): _commit_text())
	value_text.focus_exited.connect(_commit_text)
	expression.add_child(value_text)
	target_row = VBoxContainer.new()
	advanced.add_child(target_row)
	target_path = NODE_PATH_FIELD.new()
	target_row.add_child(target_path)
	target_path.setup("Target Node", editor_interface, &"Node")
	target_path.path_changed.connect(func(value): _request({&"target_path": value}))
	advanced_button = Button.new()
	advanced_button.text = ">"
	advanced_button.tooltip_text = "Advanced: target, Enabled and NOT"
	advanced_button.toggle_mode = true
	advanced_button.toggled.connect(func(open): advanced.visible = open)
	expression.add_child(advanced_button)
	add_child(advanced)
	advanced.hide()


func set_editor_context(interface: EditorInterface, owner: FiniteStateMachine) -> void:
	editor_interface = interface
	machine = owner
	if target_path != null:
		target_path.set_context(interface, machine, _resource().target_path if _resource() != null else NodePath())
	if property_picker != null:
		property_picker.disabled = _property_target() == null


func set_spec(value: TransitionCondition) -> void:
	spec = value
	action = null
	mode = Mode.COMPARISON
	value_field = &"comparison_value"
	_fill()


func set_action(value: TransitionAction, route: StateTransition) -> void:
	action = value
	spec = null
	transition = route
	value_field = &"value"
	mode = Mode.TOGGLE if action.action_type == TransitionAction.ActionType.TOGGLE_BOOL else (Mode.ADD if action.action_type == TransitionAction.ActionType.ADD_VALUE else Mode.ASSIGN)
	negated.hide()
	enabled.show()
	enabled.text = "Effect Enabled"
	_fill()


func _resource() -> Resource:
	return action if action != null else spec


func _property_target(changes: Dictionary = {}) -> Object:
	if not is_instance_valid(machine): return null
	var resource := _resource()
	if resource == null: return machine.get_effective_actor()
	var target: int = changes.get(&"target_mode", resource.target_mode)
	var path: NodePath = changes.get(&"target_path", resource.target_path)
	if action != null:
		var probe := TransitionAction.new()
		probe.target_mode = target
		probe.target_path = path
		var source: State = machine.get_state_container().get_node_or_null(NodePath(String(transition.from_state))) if transition != null and not transition.from_state.is_empty() else null
		var destination: State = machine.get_state_container().get_node_or_null(NodePath(String(transition.to_state))) if transition != null and not transition.to_state.is_empty() else null
		return COMPARISON.action_target(machine, source, destination, probe)
	var actor := machine.get_effective_actor()
	return actor if target == 0 else (actor.get_node_or_null(path) if is_instance_valid(actor) and not path.is_empty() else null)


func _metadata(changes: Dictionary = {}) -> Dictionary:
	return CATALOG.find(_property_target(changes), changes.get(&"property_path", _resource().property_path)) if _resource() != null else {}


func _display_type() -> int:
	return value_type.get_selected_id()


func _normalized(value: Variant, type: int) -> Variant:
	if typeof(value) == type: return value
	if type in [TYPE_INT, TYPE_FLOAT] and typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return int(value) if type == TYPE_INT else float(value)
	return CATALOG.default_value(type)


func _fill() -> void:
	visible = _resource() != null
	if not visible: return
	loading = true
	var resource := _resource()
	enabled.button_pressed = resource.enabled
	enabled.tooltip_text = "Enabled" if resource.enabled else "Disabled"
	negated.button_pressed = spec.negated if spec != null else false
	advanced_button.text = "NOT" if spec != null and spec.negated else ("Off" if not resource.enabled else ">")
	advanced_button.tooltip_text = ("Advanced: target and Effect Enabled" if action != null else "Advanced: target, Enabled and NOT") if resource.enabled else "Disabled; open Advanced to enable"
	target_mode.clear()
	for label in (["Actor", "Node Path"] if spec != null else ["Actor", "FSM", "Source State", "Destination State", "Node Path"]):
		target_mode.add_item(label)
	target_mode.select(resource.target_mode)
	target_row.visible = resource.target_mode == (1 if spec != null else 4)
	target_path.set_context(editor_interface, machine, resource.target_path)
	property_path.text = resource.property_path
	var metadata := _metadata()
	inferred_type = int(metadata.get("type", TYPE_NIL))
	var value: Variant = resource.get(value_field)
	var type := inferred_type if inferred_type in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME] else typeof(value)
	if mode == Mode.TOGGLE: type = TYPE_BOOL
	if mode == Mode.ADD and type not in [TYPE_INT, TYPE_FLOAT]: type = TYPE_INT
	value = _normalized(value, type)
	value_type.select(maxi(0, value_type.get_item_index(TYPE_STRING if type == TYPE_STRING_NAME else type)))
	value_type.disabled = inferred_type != TYPE_NIL or mode == Mode.TOGGLE
	for index in value_type.item_count:
		value_type.set_item_disabled(index, mode == Mode.ADD and value_type.get_item_id(index) not in [TYPE_INT, TYPE_FLOAT])
	operator.clear()
	if mode == Mode.COMPARISON:
		var labels := ["==", "!=", ">", ">=", "<", "<="]
		for id in CATALOG.operator_ids(type): operator.add_item(labels[id], id)
		operator.select(maxi(0, operator.get_item_index(spec.comparison_operator)))
	else:
		operator.add_item("=" if mode == Mode.ASSIGN else ("+=" if mode == Mode.ADD else "Toggle"))
	operator.disabled = mode != Mode.COMPARISON
	value_bool.visible = type == TYPE_BOOL and mode != Mode.TOGGLE
	value_number.visible = type in [TYPE_INT, TYPE_FLOAT] and mode != Mode.TOGGLE
	value_text.visible = type in [TYPE_STRING, TYPE_STRING_NAME] and mode != Mode.TOGGLE
	if value_bool.visible: value_bool.select(1 if value else 0)
	if value_number.visible:
		value_number.step = 1.0 if type == TYPE_INT else 0.01
		value_number.value = value
	if value_text.visible: value_text.text = str(value)
	property_picker.disabled = _property_target() == null
	loading = false
	_queue_normalization()


func _queue_normalization() -> void:
	if not auto_normalize: return
	if inferred_type not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME] or mode == Mode.TOGGLE: return
	if mode == Mode.ADD and inferred_type not in [TYPE_INT, TYPE_FLOAT]: return
	var resource := _resource()
	var key := "%s/%s/%s/%s" % [resource.get_instance_id(), resource.target_mode, resource.target_path, resource.property_path]
	if normalized_bindings.has(key): return
	normalized_bindings[key] = true
	var previous: Variant = resource.get(value_field)
	var next: Variant = _normalized(previous, inferred_type)
	var changes := {}
	if typeof(previous) != typeof(next) or previous != next: changes[value_field] = next
	if spec != null and not spec.comparison_operator in Array(CATALOG.operator_ids(inferred_type)):
		changes[&"comparison_operator"] = 0
	if changes.is_empty(): return
	# Defer until the owning builder has connected its Undo/Redo handler.
	var path: NodePath = resource.property_path
	var target: int = resource.target_mode
	var node_path: NodePath = resource.target_path
	(func():
		if not is_inside_tree() or _resource() != resource: return
		if resource.property_path != path or resource.target_mode != target or resource.target_path != node_path: return
		if typeof(resource.get(value_field)) != typeof(previous) or resource.get(value_field) != previous: return
		_request(changes)
	).call_deferred()


func _change_type(index: int) -> void:
	if value_type.disabled: return
	var type := value_type.get_item_id(index)
	if mode == Mode.ADD and type not in [TYPE_INT, TYPE_FLOAT]: return
	_request({value_field: _normalized(_resource().get(value_field), type)})


func _commit_text() -> void:
	_commit(value_field, StringName(value_text.text) if inferred_type == TYPE_STRING_NAME else value_text.text)


func _commit(property: StringName, value: Variant) -> void:
	_request({property: value})


func _request(changes: Dictionary) -> void:
	if loading or _resource() == null: return
	var metadata := _metadata(changes)
	var type: int = metadata.get("type", TYPE_NIL)
	if type == TYPE_NIL: type = typeof(changes.get(value_field, _resource().get(value_field)))
	if type in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]:
		if mode == Mode.ADD and type not in [TYPE_INT, TYPE_FLOAT] or mode == Mode.TOGGLE and type != TYPE_BOOL:
			_fill()
			return
		if mode != Mode.TOGGLE:
			changes[value_field] = _normalized(changes.get(value_field, _resource().get(value_field)), type)
		if spec != null:
			var op: int = changes.get(&"comparison_operator", spec.comparison_operator)
			if not op in Array(CATALOG.operator_ids(type)): changes[&"comparison_operator"] = 0
	# Property, inferred value and operator form one reversible authoring operation.
	if edits_requested.get_connections().is_empty():
		for property in changes: edited.emit(property, changes[property])
	else:
		edits_requested.emit(changes)


func _pick_property() -> void:
	var target := _property_target()
	if target == null: return
	property_menu.clear()
	var category := -1
	var labels := ["SCRIPT VARIABLES", "BUILT-IN PROPERTIES", "INHERITED SCRIPT VARIABLES"]
	var id := 1
	for entry in CATALOG.properties(target):
		if not int(entry.type) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]: continue
		if mode == Mode.ADD and int(entry.type) not in [TYPE_INT, TYPE_FLOAT]: continue
		if mode == Mode.TOGGLE and int(entry.type) != TYPE_BOOL: continue
		if category != int(entry.category):
			category = int(entry.category)
			property_menu.add_separator(labels[category])
		property_menu.add_item("%s  (%s)" % [entry.name, CATALOG.type_name(int(entry.type))], id)
		property_menu.set_item_metadata(property_menu.item_count - 1, entry)
		id += 1
	if property_menu.item_count == 0: property_menu.add_disabled_item("No compatible properties")
	property_menu.position = Vector2i(property_picker.get_screen_position())
	property_menu.popup()


func _property_menu_selected(id: int) -> void:
	var index := property_menu.get_item_index(id)
	if index < 0: return
	var entry: Dictionary = property_menu.get_item_metadata(index)
	_request({&"property_path": NodePath(String(entry.name))})


func _on_property_picked(path: NodePath) -> void:
	if not path.is_empty(): _request({&"property_path": path})
