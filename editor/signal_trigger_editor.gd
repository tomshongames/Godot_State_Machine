@tool
extends VBoxContainer

const PATH_FIELD := preload("res://addons/state_machine/editor/node_path_field.gd")
const PROPERTY := preload("res://addons/state_machine/runtime/property_comparison.gd")
const CATALOG := preload("res://addons/state_machine/editor/signal_catalog.gd")
signal edited(property: StringName, value: Variant)
var source_mode: OptionButton
var source_path
var picker: OptionButton
var name_edit: LineEdit
var status: Label
var loading := false

func setup(interface: EditorInterface) -> void:
	_label("Source")
	source_mode = OptionButton.new()
	for text in ["Actor", "Node Path"]: source_mode.add_item(text)
	source_mode.item_selected.connect(func(index): _edit(&"signal_source_mode", index))
	add_child(source_mode)
	source_path = PATH_FIELD.new()
	source_path.setup("Node", interface, &"Node")
	source_path.path_changed.connect(func(value): _edit(&"signal_source_path", value))
	add_child(source_path)
	_label("Signal")
	picker = OptionButton.new()
	picker.item_selected.connect(func(index): _edit(&"signal_name", picker.get_item_metadata(index)))
	add_child(picker)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Signal name"
	name_edit.text_submitted.connect(func(_text): _commit_name())
	name_edit.focus_exited.connect(_commit_name)
	add_child(name_edit)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)

func configure(machine: FiniteStateMachine, route: StateTransition, interface: EditorInterface) -> void:
	visible = route.trigger_type == StateTransition.TriggerType.SIGNAL and route.source_mode != StateTransition.SourceMode.HIERARCHY_ENTRY
	if not visible: return
	loading = true
	source_mode.select(clampi(route.signal_source_mode, 0, 1))
	source_path.visible = route.signal_source_mode == StateTransition.SignalSourceMode.NODE_PATH
	source_path.set_context(interface, machine, route.signal_source_path)
	var source := PROPERTY.target(machine.get_effective_actor(), route.signal_source_mode, route.signal_source_path)
	var names := CATALOG.names(source)
	picker.clear()
	var at := 0
	if not route.signal_name in names:
		picker.add_item("[Unverified] " + String(route.signal_name) if not route.signal_name.is_empty() else "Select signal")
		picker.set_item_metadata(0, route.signal_name)
	for name in names:
		picker.add_item(String(name))
		picker.set_item_metadata(picker.item_count - 1, name)
		if name == route.signal_name: at = picker.item_count - 1
	picker.select(at)
	name_edit.text = String(route.signal_name)
	status.text = "Source not found; configuration is retained." if source == null else ("Signal not declared on source." if not route.signal_name.is_empty() and not route.signal_name in names else "")
	loading = false

func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	add_child(label)

func _commit_name() -> void:
	_edit(&"signal_name", StringName(name_edit.text.strip_edges()))

func _edit(property: StringName, value: Variant) -> void:
	if not loading: edited.emit(property, value)
