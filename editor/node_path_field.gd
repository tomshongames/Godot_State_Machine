@tool
extends HBoxContainer

signal path_changed(value: NodePath)

var editor_interface: EditorInterface
var machine: FiniteStateMachine
var accepted_type: StringName = &"Node"
var field: LineEdit
var picker: Button
var loading := false


func setup(title: String, interface: EditorInterface, node_type: StringName) -> void:
	editor_interface = interface
	accepted_type = node_type
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 95
	add_child(label)
	field = LineEdit.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.placeholder_text = "Actor-relative NodePath"
	field.tooltip_text = "Choose a descendant of the FSM Actor. The saved value is Actor-relative."
	field.text_submitted.connect(func(_text): _commit_text())
	field.focus_exited.connect(_commit_text)
	add_child(field)
	picker = Button.new()
	picker.text = "…"
	picker.tooltip_text = "Choose a node from the edited scene"
	picker.pressed.connect(_open_picker)
	add_child(picker)


func set_context(interface: EditorInterface, owner: FiniteStateMachine, value: NodePath) -> void:
	editor_interface = interface
	machine = owner
	if is_instance_valid(field):
		loading = true
		field.text = String(value)
		loading = false


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return _resolve_dragged_node(data) != null and _relative_to_actor(_resolve_dragged_node(data)) != NodePath()


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var node := _resolve_dragged_node(data)
	if node != null:
		_commit_path(_relative_to_actor(node))


func _resolve_dragged_node(data: Variant) -> Node:
	if not data is Dictionary or data.get("type", "") != "nodes":
		return null
	var nodes: Array = data.get("nodes", [])
	if nodes.is_empty() or not is_instance_valid(editor_interface):
		return null
	var scene := editor_interface.get_edited_scene_root()
	if not is_instance_valid(scene):
		return null
	var candidate: Node
	if nodes[0] is Node:
		candidate = nodes[0]
	elif nodes[0] is NodePath or nodes[0] is String:
		var path := NodePath(nodes[0])
		candidate = scene.get_node_or_null(path)
	if not is_instance_valid(candidate) or not candidate.is_class(accepted_type):
		return null
	return candidate


func _relative_to_actor(node: Node) -> NodePath:
	if not is_instance_valid(machine) or not is_instance_valid(machine.get_effective_actor()) or not is_instance_valid(node):
		return NodePath()
	if node == machine.get_effective_actor() or not machine.get_effective_actor().is_ancestor_of(node):
		return NodePath()
	return machine.get_effective_actor().get_path_to(node)


func _open_picker() -> void:
	if not is_instance_valid(editor_interface):
		return
	var current: Node
	if is_instance_valid(machine) and is_instance_valid(machine.get_effective_actor()) and not field.text.is_empty():
		current = machine.get_effective_actor().get_node_or_null(NodePath(field.text))
	var types: Array[StringName] = [accepted_type]
	editor_interface.popup_node_selector(_on_node_picked, types, current)


func _on_node_picked(scene_path: NodePath) -> void:
	if scene_path.is_empty() or not is_instance_valid(editor_interface):
		return
	var scene := editor_interface.get_edited_scene_root()
	var node := scene.get_node_or_null(scene_path) if is_instance_valid(scene) else null
	if not is_instance_valid(node) or not node.is_class(accepted_type):
		return
	var relative := _relative_to_actor(node)
	if relative.is_empty():
		return
	_commit_path(relative)


func _commit_text() -> void:
	if loading:
		return
	var path := NodePath(field.text.strip_edges())
	if path.is_empty():
		path_changed.emit(path)
		return
	if not is_instance_valid(machine) or not is_instance_valid(machine.get_effective_actor()):
		return
	var node := machine.get_effective_actor().get_node_or_null(path)
	if not is_instance_valid(node) or not node.is_class(accepted_type):
		field.tooltip_text = "Path must resolve to a %s below the FSM Actor." % accepted_type
		return
	field.tooltip_text = ""
	_commit_path(path)


func _commit_path(value: NodePath) -> void:
	loading = true
	field.text = String(value)
	field.tooltip_text = ""
	loading = false
	path_changed.emit(value)
