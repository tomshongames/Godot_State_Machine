@tool
extends RefCounted
## Compatibility boundary: native Scene dock Tree access, tested on Godot 4.7.2.
## All visibility data/actions remain supported addon APIs outside this bridge.
const BUTTON_ID := 0x46534D56 # "FSMV", positive signed 32-bit; native IDs are small enums.
const OWNER_META := &"_fsm_scene_eye_owner"
var editor: EditorInterface
var actions: RefCounted
var host: EditorPlugin
var scene_tree: SceneTree
var tree: Tree
var pending := false
var stopped := true
var warned := false
var retries := 0
var generation := 0
var native_parent: Node

func setup(plugin: EditorPlugin, service: RefCounted) -> void:
	# Reusing the bridge must be as safe as creating a new one on plugin enable.
	shutdown()
	warned = false
	retries = 0
	if not is_instance_valid(plugin) or not plugin.is_inside_tree() or not is_instance_valid(service): return
	var version := Engine.get_version_info()
	if version.major != 4 or version.minor != 7:
		_warn()
		return
	host = plugin
	editor = plugin.get_editor_interface()
	actions = service
	scene_tree = plugin.get_tree()
	stopped = false
	scene_tree.tree_changed.connect(request_refresh)
	scene_tree.node_renamed.connect(_node_renamed)
	editor.get_selection().selection_changed.connect(request_refresh)
	host.scene_changed.connect(_scene_changed)
	actions.graph_visibility_changed.connect(_visibility_changed)
	request_refresh()

func _warn() -> void:
	if warned: return
	warned = true
	push_warning("FSM SceneTree eye integration is unavailable on this Godot editor version/layout.")

func request_refresh() -> void:
	if stopped or pending: return
	pending = true
	_refresh.call_deferred(generation)

func _node_renamed(_node: Node) -> void:
	request_refresh()

func _scene_changed(_root: Node) -> void:
	retries = 0
	request_refresh()

func _visibility_changed(_machine: FiniteStateMachine, _state: State) -> void:
	# Actions and Undo update the icon in the same turn as the graph/inspectors.
	if not stopped and is_instance_valid(tree): _decorate()
	request_refresh()

func _items(candidate: Tree) -> Array[TreeItem]:
	var result: Array[TreeItem] = []
	var root := candidate.get_root()
	if root == null: return result
	result.append(root)
	var cursor := 0
	while cursor < result.size():
		result.append_array(result[cursor].get_children())
		cursor += 1
	return result

func node_for_item(item: TreeItem) -> Node:
	if not is_instance_valid(editor) or not is_instance_valid(item): return null
	var root := editor.get_edited_scene_root()
	if not is_instance_valid(root): return null
	var path = item.get_metadata(0)
	# Observed native format is an absolute NodePath, including the editor viewport.
	if not path is NodePath or not path.is_absolute() or path.get_subname_count() != 0: return null
	var node := root.get_node_or_null(path)
	if node == null or (node != root and not root.is_ancestor_of(node)): return null
	if node.get_path() != path: return null
	return node

func accepts(candidate: Tree) -> bool:
	if not is_instance_valid(editor) or not is_instance_valid(candidate) or not candidate.is_inside_tree(): return false
	if not editor.get_base_control().is_ancestor_of(candidate): return false
	var root := editor.get_edited_scene_root()
	if not is_instance_valid(root): return false
	# A native class hint alone is insufficient: dialogs also contain SceneTreeEditors.
	var parent := candidate.get_parent()
	if parent == null or parent.get_class() != "SceneTreeEditor": return false
	if not parent.has_signal("node_changed"): return false
	var dock := parent.get_parent()
	while dock != null and not dock is EditorDock: dock = dock.get_parent()
	if dock == null: return false
	var mapped := {}
	var has_root := false
	for item in _items(candidate):
		var node := node_for_item(item)
		if node == null or mapped.has(node.get_instance_id()): return false
		mapped[node.get_instance_id()] = true
		has_root = has_root or node == root
	# Require multiple real identities whenever the scene has children. A filtered
	# tree without its root is intentionally left alone until its filter is cleared.
	return has_root and mapped.size() >= mini(3, 1 + root.find_children("*", "", true, false).size())

func _refresh(epoch: int = -1) -> void:
	if epoch != -1 and epoch != generation: return
	pending = false
	if stopped or not is_instance_valid(editor): return
	if editor.get_edited_scene_root() == null:
		_release_tree()
		return
	if is_instance_valid(tree) and not editor.get_base_control().is_ancestor_of(tree):
		_release_tree()
	if not is_instance_valid(tree):
		var matches: Array[Tree] = []
		for candidate in editor.get_base_control().find_children("*", "Tree", true, false):
			if accepts(candidate): matches.append(candidate)
		if matches.size() == 1:
			tree = matches[0]
			tree.button_clicked.connect(_clicked)
			# Draw is a redraw EVENT, not a process loop. Native updates can replace
			# buttons without changing scene Nodes (warnings, scripts, filters).
			tree.draw.connect(request_refresh)
			tree.visibility_changed.connect(request_refresh)
			tree.theme_changed.connect(request_refresh)
			native_parent = tree.get_parent()
			if not native_parent.is_connected("node_changed", request_refresh):
				native_parent.connect("node_changed", request_refresh)
		else:
			if retries < 3:
				retries += 1
				_retry_after_frame()
			else: _warn()
			return
	if accepts(tree):
		retries = 0
		_decorate()

func _retry_after_frame() -> void:
	var epoch := generation
	if not is_instance_valid(scene_tree): return
	await scene_tree.process_frame
	if epoch == generation and not stopped: request_refresh()

func _supported(node: Node) -> bool:
	if not node is State: return false
	var machine := FiniteStateMachine.machine_for_state(node)
	return machine != null and machine.owns_state(node)

func _owned(item: TreeItem) -> bool:
	return item.get_meta(OWNER_META, 0) == get_instance_id()

func _decorate() -> void:
	if not accepts(tree): return
	var theme := editor.get_editor_theme()
	if not theme.has_icon("GuiVisibilityVisible", "EditorIcons") or not theme.has_icon("GuiVisibilityHidden", "EditorIcons"):
		_warn()
		return
	for item in _items(tree):
		var index := item.get_button_by_id(0, BUTTON_ID)
		if not _supported(node_for_item(item)):
			if _owned(item):
				if index >= 0: item.erase_button(0, index)
				item.remove_meta(OWNER_META)
			continue
		# Another extension using this ID is left untouched, even on our States.
		if index >= 0 and not _owned(item): continue
		var node := node_for_item(item)
		var hidden := bool(node.get_meta(actions.HIDDEN_META, false))
		var icon := theme.get_icon("GuiVisibilityHidden" if hidden else "GuiVisibilityVisible", "EditorIcons")
		var tip := "Show in State Machine" if hidden else "Hide in State Machine"
		if index < 0:
			item.add_button(0, icon, BUTTON_ID, false, tip)
			item.set_meta(OWNER_META, get_instance_id())
		else:
			if item.get_button(0, index) != icon: item.set_button(0, index, icon)
			if item.get_button_tooltip_text(0, index) != tip: item.set_button_tooltip_text(0, index, tip)

func _clicked(item: TreeItem, column: int, id: int, mouse: int) -> void:
	if stopped or id != BUTTON_ID or column != 0 or mouse != MOUSE_BUTTON_LEFT: return
	if not is_instance_valid(tree) or not is_instance_valid(item) or item.get_tree() != tree or not _owned(item): return
	if not accepts(tree): return
	var node := node_for_item(item)
	if not _supported(node): return
	actions.set_graph_visible(FiniteStateMachine.machine_for_state(node), node, bool(node.get_meta(actions.HIDDEN_META, false)))

func shutdown() -> void:
	stopped = true
	generation += 1
	pending = false
	if is_instance_valid(scene_tree):
		if scene_tree.tree_changed.is_connected(request_refresh): scene_tree.tree_changed.disconnect(request_refresh)
		if scene_tree.node_renamed.is_connected(_node_renamed): scene_tree.node_renamed.disconnect(_node_renamed)
	if is_instance_valid(editor) and editor.get_selection().selection_changed.is_connected(request_refresh): editor.get_selection().selection_changed.disconnect(request_refresh)
	if is_instance_valid(host) and host.scene_changed.is_connected(_scene_changed): host.scene_changed.disconnect(_scene_changed)
	if is_instance_valid(actions) and actions.graph_visibility_changed.is_connected(_visibility_changed): actions.graph_visibility_changed.disconnect(_visibility_changed)
	_release_tree()
	editor = null
	actions = null
	host = null
	scene_tree = null

func _release_tree() -> void:
	if is_instance_valid(native_parent) and native_parent.has_signal("node_changed") and native_parent.is_connected("node_changed", request_refresh):
		native_parent.disconnect("node_changed", request_refresh)
	native_parent = null
	if is_instance_valid(tree):
		for pair in [[tree, "button_clicked", _clicked], [tree, "draw", request_refresh], [tree, "visibility_changed", request_refresh], [tree, "theme_changed", request_refresh]]:
			if is_instance_valid(pair[0]) and pair[0].is_connected(pair[1], pair[2]): pair[0].disconnect(pair[1], pair[2])
		for item in _items(tree):
			if not _owned(item): continue
			var index := item.get_button_by_id(0, BUTTON_ID)
			if index >= 0: item.erase_button(0, index)
			item.remove_meta(OWNER_META)
	tree = null
