@tool
extends EditorContextMenuPlugin

# Only editor metadata is changed, through the same action as the graph/inspector.
var actions: RefCounted
var editor: EditorInterface

func setup(interface: EditorInterface, editor_actions: RefCounted) -> void:
	editor = interface
	actions = editor_actions

func shutdown() -> void:
	actions = null
	editor = null

func supported_state(nodes: Array) -> State:
	# The editor's authored selection is single-object. Avoid ambiguous mixed/bulk
	# operations or Undo actions spanning different scene histories.
	if actions == null or not is_instance_valid(editor) or nodes.size() != 1: return null
	var node = nodes[0]
	if not is_instance_valid(node) or not node is State or not node.is_inside_tree(): return null
	var scene := editor.get_edited_scene_root()
	if scene == null or node != scene and not scene.is_ancestor_of(node): return null
	var machine := FiniteStateMachine.machine_for_state(node)
	return node if machine != null and machine.owns_state(node) else null

func menu_action(nodes: Array) -> Dictionary:
	var state := supported_state(nodes)
	if state == null: return {}
	var hidden := bool(state.get_meta(actions.HIDDEN_META, false))
	return {"label": "Show in State Machine" if hidden else "Hide in State Machine", "visible": hidden}

func nodes_for_paths(paths: PackedStringArray) -> Array:
	if not is_instance_valid(editor): return []
	var scene := editor.get_edited_scene_root()
	if scene == null: return []
	var nodes: Array = []
	for path in paths: nodes.append(scene.get_node_or_null(NodePath(path)))
	return nodes

func _popup_menu(paths: PackedStringArray) -> void:
	var action := menu_action(nodes_for_paths(paths))
	if not action.is_empty(): add_context_menu_item(action.label, apply_visibility.bind(action.visible))

func apply_visibility(nodes: Array, value: bool) -> void:
	var state := supported_state(nodes)
	if state == null: return
	var machine := FiniteStateMachine.machine_for_state(state)
	actions.set_graph_visible(machine, state, value)
