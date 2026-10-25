@tool
extends EditorPlugin

const PANEL_SCRIPT := preload(
	"res://addons/state_machine/editor/state_graph_panel.gd"
)
const MAINTENANCE_SCRIPT := preload("res://addons/state_machine/editor/state_scene_maintenance.gd")
const DEBUGGER_SCRIPT := preload("res://addons/state_machine/editor/live_debugger_plugin.gd")
const SCENE_CONTEXT_SCRIPT := preload("res://addons/state_machine/editor/state_scene_context_menu.gd")
const STATE_INSPECTOR_SCRIPT := preload("res://addons/state_machine/editor/state_inspector_plugin.gd")

var scene_tree_visibility
var panel
var dock: EditorDock
var last_selected_node: Node
var workspace_icon: Texture2D
var editor_selection: EditorSelection
var maintenance
var live_debugger
var scene_context_menu: EditorContextMenuPlugin
var state_inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	panel = PANEL_SCRIPT.new()
	panel.name = "StateMachineVisualEditor"
	panel.setup(get_editor_interface(), get_undo_redo())
	state_inspector = STATE_INSPECTOR_SCRIPT.new()
	state_inspector.setup(panel.actions)
	add_inspector_plugin(state_inspector)
	scene_context_menu = SCENE_CONTEXT_SCRIPT.new()
	scene_context_menu.setup(get_editor_interface(), panel.actions)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCENE_TREE, scene_context_menu)
	get_editor_interface().get_editor_main_screen().add_child(panel)
	panel.set_workspace_visible(false)
	dock = EditorDock.new()
	dock.name = "StateMachineDock"
	dock.title = "State Machine"
	dock.layout_key = "state_machine"
	dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	dock.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	dock.dock_icon = _get_plugin_icon()
	panel.dock_content.reparent(dock)
	add_dock(dock)
	panel.authoring_dock_requested.connect(dock.make_visible)
	panel.navigation_selection_changed.connect(func(node): last_selected_node = node)
	maintenance = MAINTENANCE_SCRIPT.new()
	maintenance.setup(get_editor_interface(), panel.actions, get_tree())

	live_debugger = DEBUGGER_SCRIPT.new()
	add_debugger_plugin(live_debugger)
	panel.live_debug.set_debugger(live_debugger)

	editor_selection = get_editor_interface().get_selection()

	if not editor_selection.selection_changed.is_connected(
		_on_selection_changed
	):
		editor_selection.selection_changed.connect(
			_on_selection_changed
		)

	scene_changed.connect(_on_scene_changed)
	scene_closed.connect(_on_scene_closed)
	_on_selection_changed()
	scene_tree_visibility = preload("res://addons/state_machine/editor/scene_tree_visibility_bridge.gd").new()
	scene_tree_visibility.setup(self, panel.actions)


func _exit_tree() -> void:
	if scene_tree_visibility != null:
		scene_tree_visibility.shutdown()
		scene_tree_visibility = null
	if state_inspector != null:
		remove_inspector_plugin(state_inspector)
		state_inspector.shutdown()
		state_inspector = null
	if scene_context_menu != null:
		remove_context_menu_plugin(scene_context_menu)
		scene_context_menu.shutdown()
		scene_context_menu = null
	if live_debugger != null:
		if is_instance_valid(panel): panel.live_debug.set_debugger(null)
		live_debugger.shutdown()
		remove_debugger_plugin(live_debugger)
		live_debugger = null
	if maintenance != null:
		maintenance.stop()
		maintenance = null
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	if scene_closed.is_connected(_on_scene_closed):
		scene_closed.disconnect(_on_scene_closed)
	if is_instance_valid(editor_selection):
		if editor_selection.selection_changed.is_connected(
			_on_selection_changed
		):
			editor_selection.selection_changed.disconnect(
				_on_selection_changed
			)

	if is_instance_valid(panel):
		panel.set_state_machine(null)
		panel.free()
	if is_instance_valid(dock):
		remove_dock(dock)
		dock.free()

	panel = null
	dock = null
	last_selected_node = null
	editor_selection = null


func _on_selection_changed() -> void:
	if not is_instance_valid(panel) or not is_instance_valid(editor_selection):
		return
	if panel.syncing_selection or panel.actions.applying:
		return

	var selected := editor_selection.get_selected_nodes()
	# Native debugger/SceneTree focus can temporarily clear the authored selection.
	if selected.is_empty() and get_editor_interface().is_playing_scene() and is_instance_valid(panel.state_machine):
		return

	if selected.size() != 1:
		panel.set_state_machine(null)
		return

	var node := selected[0]
	if not is_instance_valid(node):
		panel.set_state_machine(null)
		return
	var machine: FiniteStateMachine = null

	if node is FiniteStateMachine:
		machine = node

	elif node is State:
		machine = FiniteStateMachine.machine_for_state(node)
		if node.has_method("get_nested_machine") and panel.state_machine == node.get_nested_machine():
			machine = panel.state_machine

	var unchanged: bool = panel.state_machine == machine and last_selected_node == node
	panel.set_state_machine(machine)
	if not unchanged: panel.select_graph_state(node if node is State and machine != null else null)
	last_selected_node = node


func _on_scene_changed(_scene: Node) -> void:
	if maintenance != null:
		maintenance.watch_scene(_scene)
	if is_instance_valid(panel):
		panel.set_state_machine(null)
	_on_selection_changed()


func _on_scene_closed(_path: String) -> void:
	if is_instance_valid(panel):
		panel.set_state_machine(null)


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "State Machine"


func _get_plugin_icon() -> Texture2D:
	if workspace_icon == null:
		var pixels := preload("res://addons/state_machine/icons/finite_state_machine.svg").get_image()
		var side := roundi(16 * EditorInterface.get_editor_scale())
		pixels.resize(side, side, Image.INTERPOLATE_LANCZOS)
		workspace_icon = ImageTexture.create_from_image(pixels)
	return workspace_icon


func _make_visible(active: bool) -> void:
	if is_instance_valid(panel): panel.set_workspace_visible(active)
	if active and is_instance_valid(dock): dock.make_visible()
