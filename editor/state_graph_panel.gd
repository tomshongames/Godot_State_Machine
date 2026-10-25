@tool
extends VBoxContainer
const BLOCK := preload("res://addons/state_machine/editor/transition_graph_block.gd")
const PALETTE := preload("res://addons/state_machine/editor/fsm_palette.gd")
var palette: VBoxContainer
var palette_scroll: ScrollContainer
var palette_toggle: Button
var transition_blocks: Dictionary = {}
var drafts: Dictionary = {}
var dock_drag: Dictionary = {}
var block_move: Dictionary = {}
var palette_move: Dictionary = {}
var docking := false
var dock_refresh_queued := false
var dock_cancelled := false
var source_dock_updated := false
var curve_drag: Dictionary = {}
var native_connection_layer: CanvasItem
var debug_outline_amount := 0.0
var connection_redraw_pending := false
var structure_topology := ""
# Opt-in diagnostic trace; no polling and no per-frame recording in normal use.
var trace_connection_sync := false
var connection_sync_trace: Array[Dictionary] = []
var connection_draw_records: Dictionary = {}
var random_controller := preload("res://addons/state_machine/editor/graph_random_controller.gd").new()
const RANDOM_BLOCK := preload("res://addons/state_machine/editor/random_graph_block.gd")
var random_blocks: Dictionary:
	get: return random_controller.random_blocks
	set(value): random_controller.random_blocks = value
# Session records survive parent ownership changes, including committed routers
# that must return to a visible draft when their input is disconnected.
var random_drafts: Dictionary:
	get: return random_controller.random_drafts
	set(value): random_controller.random_drafts = value
var random_branch_connections: Dictionary:
	get: return random_controller.random_branch_connections
	set(value): random_controller.random_branch_connections = value
var random_visual_update: bool:
	get: return random_controller.random_visual_update
	set(value): random_controller.random_visual_update = value
var random_visual_synced: bool:
	get: return random_controller.random_visual_synced
	set(value): random_controller.random_visual_synced = value
var selected_random: StateRandomRouting:
	get: return random_controller.selected_random
	set(value): random_controller.selected_random = value
var routing_inspector: VBoxContainer:
	get: return random_controller.routing_inspector
	set(value): random_controller.routing_inspector = value
var random_color_edit: Dictionary:
	get: return random_controller.random_color_edit
	set(value): random_controller.random_color_edit = value
var random_router_color_edit: Dictionary:
	get: return random_controller.random_router_color_edit
	set(value): random_controller.random_router_color_edit = value
var selected_random_branch: StateRandomTarget:
	get: return random_controller.selected_random_branch
	set(value): random_controller.selected_random_branch = value
var draft_serial := 0
var block_menu: PopupMenu
var color_target: Object
var color_boundary := ""
var topology := ""
const VALIDATION_SEARCH := preload("res://addons/state_machine/editor/validation_search_controller.gd")
const CONNECTION_DRAG := preload("res://addons/state_machine/editor/connection_drag.gd")
var validation_search
signal navigation_selection_changed(node: Node)

const ACTIONS_SCRIPT := preload("res://addons/state_machine/editor/state_editor_actions.gd")
const NODE_SCRIPT := preload("res://addons/state_machine/editor/state_graph_node.gd")
const ANY_NODE := preload("res://addons/state_machine/editor/any_state_graph_node.gd")
const DIALOGS_SCRIPT := preload("res://addons/state_machine/editor/state_authoring_dialogs.gd")
const TRANSITION_EDITOR_SCRIPT := preload("res://addons/state_machine/editor/transition_editor.gd")
const SCRIPT_UTILS := preload("res://addons/state_machine/editor/state_script_utils.gd")
var appearance_controller := preload("res://addons/state_machine/editor/graph_appearance_controller.gd").new()
const APPEARANCE := preload("res://addons/state_machine/editor/appearance_preferences.gd")
const LIVE_PANEL := preload("res://addons/state_machine/editor/live_debug_panel.gd")
const EVENT_AUTHORING := preload("res://addons/state_machine/editor/event_script_authoring.gd")
const SELECTION_INSPECTOR := preload("res://addons/state_machine/editor/selection_inspector.gd")
const GRAPH_INDEX := preload("res://addons/state_machine/editor/graph_index.gd")
var graph_index := GRAPH_INDEX.new()
const TRANSITION_COLORS := preload("res://addons/state_machine/editor/transition_colors.gd")
var creation_color_picker: ColorPickerButton
enum SelectionMode { NONE, STATE, TRANSITION, TRANSITION_PAIR, ENTRY, EXIT, ANY_STATE, RANDOM, RANDOM_CONNECTION }
var selection_mode := SelectionMode.NONE
var selected_state: State
var selected_transition: StateTransition
var selected_pair: Dictionary = {}
var selected_boundary: StringName
var selection_inspector
const BOUNDARY := preload("res://addons/state_machine/editor/boundary_graph_node.gd")
var entry_node: GraphNode
var exit_node: GraphNode
var fallback_entry: StateTransition
var entry_fallback_cache := {}
const UI_PREFIX := "editors/state_machine/layout/"
const TRANSITIONS_PANEL := preload("res://addons/state_machine/editor/transitions_panel.gd")
var transitions_panel
var right_tabs: TabContainer
var live_scroll: ScrollContainer
var preferred_right_tab := 0
var restoring_right_tab := true
var inspector_scroll: ScrollContainer
var dock_content: VBoxContainer
var toolbar: HFlowContainer
var show_hidden_button: CheckButton
var show_hidden_states := false
var visibility_connections_active := false
var workspace_active := true
var pending_debug_event: Dictionary = {}
signal authoring_dock_requested
var warning_summary: Label
var connection_menu: PopupMenu
var connection_context: StateTransition
var connection_context_edge := {}
var selected_connection_edge := {}
var hovered_connection_edge := {}
var entry_connection := {}

var editor_interface: EditorInterface
var state_machine: FiniteStateMachine
var graph: GraphEdit
var empty_label: Label
var is_loading := false
var graph_revision := 0
var actions = ACTIONS_SCRIPT.new()
var dialogs
var graph_menu: PopupMenu
var state_menu: PopupMenu
var context_state: State
var context_machine: FiniteStateMachine
var create_position := Vector2.ZERO
var create_insert_index := -1
var graph_views: Dictionary = {}
var observed_states: Dictionary = {}
const CLIPBOARD := preload("res://addons/state_machine/editor/fsm_clipboard.gd")
var clipboard := CLIPBOARD.new()
var paste_topology_pending := false
var refresh_pending := false
var syncing_selection := false
var move_before: Dictionary = {}
var moving_machine: FiniteStateMachine
var pending_script_state: State
var pending_script_machine: FiniteStateMachine
var script_scan_pending := false
var transition_editor
var orphan_button: Button
var appearance_popup: PopupPanel:
	get: return appearance_controller.appearance_popup
	set(value): appearance_controller.appearance_popup = value
var appearance_rows: VBoxContainer:
	get: return appearance_controller.appearance_rows
	set(value): appearance_controller.appearance_rows = value
var exit_appearance_picker: ColorPickerButton:
	get: return appearance_controller.exit_appearance_picker
	set(value): appearance_controller.exit_appearance_picker = value
var appearance_pickers: Dictionary:
	get: return appearance_controller.appearance_pickers
	set(value): appearance_controller.appearance_pickers = value
var appearance_button: Button
var live_debug
var debug_record: Dictionary = {}
var debug_edge: Dictionary = {}
var connection_transitions: Dictionary = {}
var transition_connections: Dictionary = {}
var hierarchy_exit_connections: Dictionary = {}
var hierarchy_exit_menu: PopupMenu
var hierarchy_exit_context: HierarchyState
var connection_drag := CONNECTION_DRAG.new()
var reconnect: Dictionary:
	get: return connection_drag.pending
var connection_drag_active: bool:
	get: return connection_drag.active
var connection_drag_token: int:
	get: return connection_drag.token
var debug_tween: Tween
var debug_follow_token := ""
var breadcrumbs: HFlowContainer
var nested_delete_dialog: ConfirmationDialog
var event_script_dialog: ConfirmationDialog
var event_target: FiniteStateMachine
var event_transition: StateTransition
var event_state: State
var event_name_pending: StringName
var event_script_pending := false
var any_state_node: GraphNode
var any_source_requested := false


func setup(value: EditorInterface, undo_manager: EditorUndoRedoManager = null) -> void:
	actions.transition_property_changed.connect(_transition_property_changed)
	actions.endpoints_changed.connect(_source_endpoint_changed)
	actions.order_changed.connect(_transition_order_changed)
	actions.endpoints_changed.connect(_target_endpoint_changed)
	actions.endpoints_changed.connect(_random_endpoint_changed)
	editor_interface = value
	actions.undo_manager = undo_manager
	actions.changed.connect(_on_action_changed)
	actions.state_color_changed.connect(_state_color_changed)
	actions.hierarchy_exit_changed.connect(_hierarchy_exit_changed)
	actions.paste_started.connect(func(machine): paste_topology_pending = machine == state_machine)
	actions.machine_created.connect(_navigate_machine)
	actions.positions_changed.connect(_graph_positions_changed)
	actions.visual_changed.connect(_transition_visual_changed)
	_build_ui()
	_build_authoring_ui()
	APPEARANCE.initialize(_editor_settings() if is_instance_valid(editor_interface) else null)
	transition_editor.set_editor_context(editor_interface)
	_build_appearance_popup()
	_apply_appearance()
	_render_selection()


func _editor_settings() -> EditorSettings:
	return editor_interface.get_editor_settings() if is_instance_valid(editor_interface) else null


func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	toolbar = HFlowContainer.new()
	toolbar.custom_minimum_size.y = 34.0
	add_child(toolbar)
	breadcrumbs = HFlowContainer.new()
	add_child(breadcrumbs)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh Graph"
	refresh_button.tooltip_text = "Refresh State Machine Graph"
	refresh_button.pressed.connect(refresh)
	toolbar.add_child(refresh_button)

	var arrange_button := Button.new()
	arrange_button.text = "Auto Layout"
	arrange_button.tooltip_text = "Automatically arrange all states."
	arrange_button.pressed.connect(_on_arrange_pressed)
	toolbar.add_child(arrange_button)

	var frame_button := Button.new()
	frame_button.text = "Frame All"
	frame_button.pressed.connect(_frame.bind(false))
	toolbar.add_child(frame_button)
	show_hidden_button = CheckButton.new()
	show_hidden_button.text = "Show Hidden (0)"
	show_hidden_button.tooltip_text = "Preview graph-hidden States at half opacity. Runtime is unaffected."
	show_hidden_button.toggled.connect(func(value):
		show_hidden_states = value
		_apply_graph_visibility())
	toolbar.add_child(show_hidden_button)
	actions.graph_visibility_changed.connect(func(machine, _state):
		if machine == state_machine:
			_apply_graph_visibility()
			_render_selection()
		if is_instance_valid(editor_interface): editor_interface.mark_scene_as_unsaved())
	appearance_button = Button.new()
	appearance_button.text = "Appearance"
	appearance_button.tooltip_text = "State Machine appearance preferences"
	if has_theme_icon("GuiTabMenuHl", "EditorIcons"):
		appearance_button.icon = get_theme_icon("GuiTabMenuHl", "EditorIcons")
		appearance_button.text = ""
	appearance_button.pressed.connect(_show_appearance_popup)
	toolbar.add_child(appearance_button)
	creation_color_picker = ColorPickerButton.new()
	creation_color_picker.custom_minimum_size = Vector2(28, 28) * (EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0)
	creation_color_picker.tooltip_text = "Creation color for new States, HierarchyStates, Transitions, and Random routers."
	creation_color_picker.color = TRANSITION_COLORS.creation(_editor_settings() if is_instance_valid(editor_interface) else null)
	actions.creation_color = creation_color_picker.color
	creation_color_picker.color_changed.connect(func(color):
		if creation_color_picker.color != color: creation_color_picker.color = color
		actions.creation_color = color
		APPEARANCE.set_color(_editor_settings(), "default_transition", color)
		_apply_appearance("default_transition")
		if is_instance_valid(editor_interface): _editor_settings().set_setting(TRANSITION_COLORS.SETTING, color))
	toolbar.add_child(creation_color_picker)
	orphan_button = Button.new()
	orphan_button.hide()
	orphan_button.pressed.connect(_cleanup_orphan_transitions)
	toolbar.add_child(orphan_button)

	var workspace := HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(workspace)
	palette = PALETTE.new()
	palette_scroll = ScrollContainer.new()
	palette_scroll.name = "PaletteScroll"
	palette_scroll.custom_minimum_size.x = 205
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	workspace.add_child(palette_scroll)
	palette_scroll.add_child(palette)
	palette.setup()
	palette.activated.connect(_palette_activate)
	palette.drag_started.connect(_begin_palette_move)
	palette.visible = _ui_setting("palette_visible", true)
	palette_scroll.visible = palette.visible
	palette_toggle = Button.new()
	palette_toggle.text = "Events"
	palette_toggle.tooltip_text = "Add States, transitions and routing elements."
	palette_toggle.toggle_mode = true
	palette_toggle.button_pressed = palette.visible
	palette_toggle.toggled.connect(func(open):
		palette.visible = open
		palette_scroll.visible = open
		_save_ui_setting("palette_visible", open))
	toolbar.add_child(palette_toggle)
	graph = GraphEdit.new()
	# Keep native connections for topology, hit testing and the minimap, but use
	# one foreground renderer. GraphEdit's child Line2Ds otherwise cover our draw
	# commands, and native activity=1 collapses both endpoints to a solid tint.
	# Godot does not expose its connection shader override to GDScript. Isolate
	# its committed-wire layer instead; modulation keeps its cache/hit tests live.
	# The native drag preview is a separate layer and remains unchanged.
	native_connection_layer = graph.get_node(^"_connection_layer") as CanvasItem
	native_connection_layer.modulate = Color.TRANSPARENT
	graph.name = "Graph"
	graph.child_entered_tree.connect(_watch_connection_geometry)
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.show_grid = true
	graph.snapping_enabled = true
	graph.snapping_distance = 20
	graph.minimap_enabled = true
	graph.resized.connect(_resize_minimap)
	graph.show_arrange_button = false
	graph.focus_mode = Control.FOCUS_ALL
	# A shared target socket cannot identify one incoming Resource. Start new
	# drags from exact chip/branch outputs; never let GraphEdit pick its first edge.
	graph.right_disconnects = false
	graph.connection_drag_started.connect(_connection_drag_started)
	graph.connection_drag_ended.connect(_connection_drag_ended)
	graph.connection_to_empty.connect(_connection_to_empty)
	graph.connection_from_empty.connect(_connection_from_empty)
	graph.visibility_changed.connect(func():
		if not graph.is_visible_in_tree(): _cancel_connection_drag())

	graph.connection_request.connect(
		_on_connection_request
	)

	graph.disconnection_request.connect(
		_on_disconnection_request
	)

	workspace.add_child(graph)
	graph.set_drag_forwarding(Callable(), _palette_can_drop, _palette_drop)
	dock_content = VBoxContainer.new()
	dock_content.name = "StateMachineDockContent"
	dock_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(dock_content)
	# Single instance, attached directly to the right tabs after Inspector.
	transitions_panel = TRANSITIONS_PANEL.new()
	transitions_panel.transition_selected.connect(func(route): _select_transition(route, false))
	transitions_panel.pair_selected.connect(_select_pair)
	transitions_panel.delete_requested.connect(_delete_transition)
	transitions_panel.create_requested.connect(_create_transition)
	right_tabs = TabContainer.new()
	right_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock_content.add_child(right_tabs)
	inspector_scroll = ScrollContainer.new()
	inspector_scroll.name = "Inspector"
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_tabs.add_child(inspector_scroll)
	transition_editor = TRANSITION_EDITOR_SCRIPT.new()
	transition_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transition_editor.name = "InspectorEditor"
	inspector_scroll.add_child(transition_editor)
	transition_editor.setup()
	selection_inspector = SELECTION_INSPECTOR.new()
	transition_editor.add_child(selection_inspector)
	transition_editor.move_child(selection_inspector, 0)
	selection_inspector.setup()
	selection_inspector.policy_edit_requested.connect(func(state, property, value): actions.edit_state_policy(selection_inspector.machine, state, property, value))
	selection_inspector.state_color_preview_requested.connect(_preview_state_color)
	selection_inspector.graph_visibility_requested.connect(func(state, value): actions.set_graph_visible(state_machine, state, value))
	selection_inspector.state_color_edit_requested.connect(_commit_state_color_edit)
	selection_inspector.state_color_reset_requested.connect(_reset_state_color)
	selection_inspector.transition_requested.connect(func(transition):
		if selection_inspector.machine != state_machine: _navigate_machine(selection_inspector.machine)
		_select_transition(transition))
	transition_editor.edit_requested.connect(_edit_transition)
	transition_editor.delete_requested.connect(_delete_transition)
	transition_editor.comparison_edit_requested.connect(_edit_comparison)
	transition_editor.resource_edits_requested.connect(func(transition, resource, values):
		if is_instance_valid(state_machine): actions.edit_typed_row(state_machine, transition, resource, values))
	transition_editor.condition_add_requested.connect(_add_condition)
	transition_editor.condition_remove_requested.connect(_remove_condition)
	transition_editor.condition_node_edit_requested.connect(func(transition, node, property, value):
		if is_instance_valid(state_machine): actions.edit_condition_node(state_machine, transition, node, property, value))
	transition_editor.condition_tree_action_requested.connect(func(transition, parent, action, node):
		if is_instance_valid(state_machine): actions.condition_tree_action(state_machine, transition, parent, action, node))
	transition_editor.action_add_requested.connect(func(transition, action_type):
		if is_instance_valid(state_machine): actions.add_action(state_machine, transition, action_type))
	transition_editor.action_remove_requested.connect(func(transition, action):
		if is_instance_valid(state_machine): actions.remove_action(state_machine, transition, action))
	transition_editor.action_edit_requested.connect(func(transition, action, property, value):
		if is_instance_valid(state_machine): actions.edit_action(state_machine, transition, action, property, value))
	transition_editor.action_move_requested.connect(func(transition, action, direction):
		if is_instance_valid(state_machine): actions.move_action(state_machine, transition, action, direction))
	transition_editor.event_script_requested.connect(_event_script_requested)
	event_script_dialog = ConfirmationDialog.new()
	event_script_dialog.title = "Create Event Method"
	event_script_dialog.dialog_text = "This State does not have a script.\nCreate a script and add the Event method?"
	event_script_dialog.ok_button_text = "Create Script & Method"
	event_script_dialog.confirmed.connect(_confirm_event_script)
	add_child(event_script_dialog)
	live_debug = LIVE_PANEL.new()
	transitions_panel.name = "Transitions"
	transitions_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transitions_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_tabs.add_child(transitions_panel)
	transitions_panel.setup()
	live_scroll = ScrollContainer.new()
	live_scroll.name = "Live"
	live_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_tabs.add_child(live_scroll)
	live_debug.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live_scroll.add_child(live_debug)
	live_debug.setup(editor_interface, actions.undo_manager)
	live_debug.snapshot_changed.connect(_debug_snapshot)
	live_debug.flash_requested.connect(_debug_flash)
	live_debug.history_navigation_requested.connect(_history_transition_selected)
	validation_search = VALIDATION_SEARCH.new()
	live_debug.decision_navigation_requested.connect(func(record, candidate): validation_search.navigate_decision(record, candidate))
	validation_search.setup(self)
	# The old authoring_tab belonged to the removed left tab container.
	if is_instance_valid(editor_interface):
		var settings := _editor_settings()
		for old_key in ["navigation_tab", "authoring_tab", "left_visible", "right_visible", "left_width", "right_offset"]:
			if settings.has_setting(UI_PREFIX + old_key): settings.erase(UI_PREFIX + old_key)
	preferred_right_tab = clampi(int(_ui_setting("right_tab", 0)), 0, 3)
	if not bool(_ui_setting("validation_tab_migrated", false)):
		if preferred_right_tab == 2: preferred_right_tab = 3
		_save_ui_setting("right_tab", preferred_right_tab)
		_save_ui_setting("validation_tab_migrated", true)
	right_tabs.current_tab = preferred_right_tab
	right_tabs.tab_changed.connect(func(index):
		if not restoring_right_tab: _save_ui_setting("right_tab", index))
	if is_inside_tree(): _restore_right_tab.call_deferred()
	graph.gui_input.connect(_graph_connection_input)
	graph.draw.connect(_draw_curve_drag)
	graph.draw.connect(_draw_block_move)
	graph.draw.connect(_draw_connection_gradients)

	empty_label = Label.new()
	empty_label.text = (
		"No State Machine selected.\nSelect a FiniteStateMachine in the SceneTree or add one to start editing."
	)
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_label.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	graph.add_child(empty_label)
	warning_summary = Label.new()
	warning_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(warning_summary)


func _ready() -> void:
	if is_instance_valid(right_tabs): _restore_right_tab.call_deferred()

func _restore_right_tab() -> void:
	if not is_inside_tree() or not is_instance_valid(right_tabs): return
	right_tabs.current_tab = preferred_right_tab
	restoring_right_tab = false

func _build_authoring_ui() -> void:
	dialogs = DIALOGS_SCRIPT.new()
	add_child(dialogs)
	dialogs.setup()
	dialogs.create_requested.connect(_create_state)
	dialogs.delete_confirmed.connect(_delete_confirmed)
	dialogs.color_confirmed.connect(_color_confirmed)
	dialogs.script_ready.connect(_attach_created_script)
	actions.error.connect(dialogs.show_error)
	graph_menu = PopupMenu.new()
	add_child(graph_menu)
	graph_menu.add_item("Create State", 0)
	graph_menu.add_separator()
	graph_menu.add_item("Auto Layout", 1)
	graph_menu.add_item("Frame All", 2)
	graph_menu.add_separator()
	graph_menu.add_item("Refresh", 3)
	graph_menu.add_item("Create HierarchyState", 4)
	graph_menu.add_item("Show Any State", 5)
	graph_menu.add_separator()
	graph_menu.add_item("Paste", 6)
	graph_menu.id_pressed.connect(_graph_menu_action)
	state_menu = PopupMenu.new()
	add_child(state_menu)
	for entry in ["Rename", "Set as Initial State", "Open Script", "Change Color", "Reset Color"]:
		state_menu.add_item(entry)
	state_menu.add_separator()
	state_menu.add_item("Duplicate State", 5)
	state_menu.add_item("Delete State", 6)
	state_menu.add_item("Copy", 12)
	state_menu.add_item("Paste", 13)
	state_menu.add_item("Hide State", 14)
	state_menu.add_separator()
	state_menu.add_item("Make Composite State", 7)
	state_menu.add_item("Open Nested State Machine", 8)
	state_menu.add_item("Remove Nested State Machine", 9)
	state_menu.add_separator()
	state_menu.add_radio_check_item("Entry Mode: RESET", 10)
	state_menu.set_item_tooltip(state_menu.get_item_index(10), "Enter the nested FSM's Initial State each time this hierarchy activates.")
	state_menu.add_radio_check_item("Entry Mode: RESUME", 11)
	state_menu.set_item_tooltip(state_menu.get_item_index(11), "Re-enter the last nested State when this hierarchy activates.")
	nested_delete_dialog = ConfirmationDialog.new()
	nested_delete_dialog.title = "Remove Nested State Machine"
	nested_delete_dialog.dialog_text = "Remove this nested FSM and all its States, transitions and Watch definitions?"
	nested_delete_dialog.confirmed.connect(func():
		if _valid_context(true):
			actions.remove_nested(state_machine, context_state))
	add_child(nested_delete_dialog)
	state_menu.id_pressed.connect(_state_menu_action)
	connection_menu = PopupMenu.new()
	connection_menu.add_item("Select Transition", 0)
	connection_menu.add_item("Create Transition…", 1)
	connection_menu.add_item("Delete Connection", 2)
	connection_menu.id_pressed.connect(_connection_menu_action)
	add_child(connection_menu)
	hierarchy_exit_menu = PopupMenu.new()
	hierarchy_exit_menu.add_item("Select HierarchyState", 0)
	hierarchy_exit_menu.add_item("Delete Exit Connection", 1)
	hierarchy_exit_menu.id_pressed.connect(func(id):
		if not is_instance_valid(hierarchy_exit_context): return
		if id == 0: select_graph_state(hierarchy_exit_context)
		else: actions.set_hierarchy_exit_target(state_machine, hierarchy_exit_context, &""))
	add_child(hierarchy_exit_menu)

	block_menu = PopupMenu.new()
	add_child(block_menu)
	for caption in ["Inspect / Edit", "Change Color…", "Reset Color", "Enable / Disable", "Delete"]: block_menu.add_item(caption)
	block_menu.add_item("New Entry Route…", 5)
	block_menu.add_item("Copy", 6)
	block_menu.add_item("Paste", 7)
	block_menu.id_pressed.connect(_block_menu_action)
	graph.popup_request.connect(_graph_popup)
	graph.node_selected.connect(_graph_selected)
	graph.delete_nodes_request.connect(_delete_requested)
	graph.duplicate_nodes_request.connect(_duplicate_requested)
	graph.copy_nodes_request.connect(func():
		if _graph_has_focus(): _copy_selection())
	graph.paste_nodes_request.connect(func():
		if _graph_has_focus(): _paste_clipboard())
	graph.begin_node_move.connect(_begin_move)
	graph.end_node_move.connect(_end_move)


func _ui_setting(key: String, fallback: Variant) -> Variant:
	if not is_instance_valid(editor_interface): return fallback
	var settings := _editor_settings()
	if not settings.has_setting(UI_PREFIX + key): settings.set_setting(UI_PREFIX + key, fallback)
	return settings.get_setting(UI_PREFIX + key)


func _save_ui_setting(key: String, value: Variant) -> void:
	if is_instance_valid(editor_interface):
		_editor_settings().set_setting(UI_PREFIX + key, value)


func begin_state_creation(hierarchy := false) -> void:
	if _prepare_creation(): _graph_menu_action(4 if hierarchy else 0)


func show_authoring_dock() -> void:
	authoring_dock_requested.emit()


func set_workspace_visible(active: bool) -> void:
	workspace_active = active
	visible = active
	if active:
		var record := debug_record
		if is_instance_valid(live_debug) and live_debug.debugger != null:
			var latest: Dictionary = live_debug.debugger.model.get_instance(live_debug.selected_session, live_debug.selected_id)
			if not latest.is_empty(): record = latest
		_debug_snapshot(record)
		if not pending_debug_event.is_empty():
			var event := pending_debug_event
			pending_debug_event = {}
			_debug_flash(event)
	else:
		_clear_debug_flash()




func _select_transition(transition: StateTransition, show_inspector := true) -> void:
	selected_connection_edge.clear()
	selected_random = null
	selected_random_branch = null
	if not is_instance_valid(state_machine) or transition == null or (not transition in state_machine.transitions and transition != fallback_entry and not drafts.has(transition)): return
	for candidate in observed_states:
		if is_instance_valid(candidate) and String(candidate.name).to_lower() in [String(transition.from_state).to_lower(), String(transition.to_state).to_lower()]: _reveal_hidden_state(candidate)
	_clear_debug_flash()
	selection_mode = SelectionMode.TRANSITION
	selected_state = null
	selected_boundary = &""
	selected_pair.clear()
	selected_transition = transition
	_sync_graph_selection(null, transition)
	if transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY:
		transition_editor.source_mode_filter = StateTransition.SourceMode.HIERARCHY_ENTRY
		transition_editor.source_filter = &""
		transition_editor.target_filter = &""
		transition_editor.fallback_entry = fallback_entry
	elif transition.source_mode == StateTransition.SourceMode.ANY_STATE:
		transition_editor.show_any_source(transition.to_state)
	else: transition_editor.show_pair(transition.from_state, transition.to_state)
	transition_editor.selected = transition
	transition_editor.draft_selection = transition if drafts.has(transition) else null
	transition_editor.refresh()
	transitions_panel.select_transition(transition)
	show_authoring_dock()
	if show_inspector: right_tabs.current_tab = 0
	_highlight_transition(transition)
	_render_selection()

func _clear_transition_selection() -> void:
	selected_connection_edge.clear()
	selected_transition = null
	selected_random = null
	selected_random_branch = null
	selected_pair.clear()
	transition_editor.selected = null
	transitions_panel.clear_selection()
	_clear_debug_flash()
	graph.queue_redraw()

func _select_pair(from: StringName, to: StringName, mode: int) -> void:
	_clear_transition_selection()
	selection_mode = SelectionMode.TRANSITION_PAIR
	selected_state = null
	selected_boundary = &""
	selected_pair = {"from": from, "to": to, "mode": mode}
	_sync_graph_selection(null)
	right_tabs.current_tab = 1
	transitions_panel.focus_pair(from, to, mode)
	_render_selection()

func _select_boundary(mode: int) -> void:
	_clear_transition_selection()
	selection_mode = mode
	selected_state = null
	selected_boundary = &"ENTRY" if mode == SelectionMode.ENTRY else (&"EXIT" if mode == SelectionMode.EXIT else &"Any State")
	_sync_graph_selection(null)
	var node: GraphNode = entry_node if mode == SelectionMode.ENTRY else (exit_node if mode == SelectionMode.EXIT else any_state_node)
	if is_instance_valid(node):
		syncing_selection = true
		node.selected = true
		syncing_selection = false
	_render_selection()

func _render_selection() -> void:
	if not is_instance_valid(selection_inspector): return
	if is_instance_valid(routing_inspector): routing_inspector.visible = selected_random != null
	if selected_random != null:
		selection_inspector.hide()
		transition_editor.heading.hide()
		transition_editor.details.hide()
		return
	var exact := selection_mode == SelectionMode.TRANSITION and selected_transition != null
	selection_inspector.visible = not exact
	transition_editor.heading.visible = exact
	transition_editor.details.visible = exact
	if exact:
		transition_editor.automatic_end_color = _automatic_end_color(transition_connections.get(selected_transition, {}))
		transition_editor.color_picker.color = TRANSITION_COLORS.color(selected_transition)
		transition_editor.start_color_reset.disabled = not TRANSITION_COLORS.has_override(selected_transition)
		transition_editor.end_color_picker.color = TRANSITION_COLORS.end_color(selected_transition, transition_editor.automatic_end_color)
		transition_editor.end_color_auto.disabled = not TRANSITION_COLORS.has_end_override(selected_transition)
		return
	var values: Array[StateTransition] = []
	var context := state_machine
	var label := ""
	var pair: Dictionary = {}
	if selection_mode == SelectionMode.STATE and is_instance_valid(selected_state):
		context = FiniteStateMachine.machine_for_state(selected_state)
		label = "HIERARCHY STATE" if selected_state is HierarchyState else "STATE"
	elif selection_mode == SelectionMode.ENTRY: label = "ENTRY"
	elif selection_mode == SelectionMode.EXIT: label = "EXIT"
	elif selection_mode == SelectionMode.ANY_STATE: label = "ANY STATE"
	elif selection_mode == SelectionMode.TRANSITION_PAIR: label = "TRANSITIONS"
	if is_instance_valid(context):
		var visible: Array[StateTransition] = context.transitions.duplicate()
		if context == state_machine and fallback_entry != null:
			var has_explicit_entry := false
			for route in context.transitions:
				if route != null and route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY:
					has_explicit_entry = true
					break
			if not has_explicit_entry: visible.append(fallback_entry)
		for route in visible:
			if route == null: continue
			if selection_mode == SelectionMode.STATE and route.source_mode == StateTransition.SourceMode.STATE and String(route.from_state).to_lower() == String(selected_state.name).to_lower(): values.append(route)
			elif selection_mode == SelectionMode.ENTRY and route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: values.append(route)
			elif selection_mode == SelectionMode.EXIT and route.destination_mode == StateTransition.DestinationMode.EXIT: values.append(route)
			elif selection_mode == SelectionMode.ANY_STATE and route.source_mode == StateTransition.SourceMode.ANY_STATE: values.append(route)
			elif selection_mode == SelectionMode.TRANSITION_PAIR and route.source_mode == selected_pair.get("mode") and route.from_state == selected_pair.get("from") and route.target_key() == selected_pair.get("to"):
				values.append(route)
		if not values.is_empty() and selection_mode == SelectionMode.TRANSITION_PAIR: pair.label = "%s → %s" % [values[0].source_label(), values[0].target_label()]
	var effective_color := Color.WHITE
	if is_instance_valid(selected_state) and is_instance_valid(editor_interface):
		effective_color = APPEARANCE.get_color(_editor_settings(), "hierarchy_state" if selected_state is HierarchyState else "default_state")
	if is_instance_valid(selected_state):
		effective_color = selected_state.get_meta(&"fsm_editor_color", effective_color)
	selection_inspector.show_context(label, context, selected_state, values, pair, effective_color)
	selection_inspector.update_active(debug_record)

func _restore_selection() -> void:
	if selection_mode == SelectionMode.RANDOM_CONNECTION:
		if selected_random != null and selected_random_branch != null and selected_random.branches.has(selected_random_branch):
			for edge in random_branch_connections.values():
				if edge.branch == selected_random_branch:
					_select_random_branch(selected_random, selected_random_branch, edge)
					return
		if selected_random != null:
			_select_random(selected_random)
			return
	if selection_mode == SelectionMode.RANDOM:
		_select_random(selected_random)
		return
	if selection_mode == SelectionMode.TRANSITION:
		if selected_transition != null and selected_transition.get_meta("initial_fallback", false) and fallback_entry != null:
			selected_transition = fallback_entry
		if selected_transition != null and (selected_transition in state_machine.transitions or selected_transition == fallback_entry or drafts.has(selected_transition)):
			transition_editor.selected = selected_transition
			transition_editor.draft_selection = selected_transition if drafts.has(selected_transition) else null
			transition_editor.refresh()
			transitions_panel.select_transition(selected_transition)
			_highlight_transition(selected_transition)
		else:
			var old := selected_transition
			_clear_transition_selection()
			if old != null and old.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: _select_boundary(SelectionMode.ENTRY)
			elif old != null and old.source_mode == StateTransition.SourceMode.ANY_STATE: _select_boundary(SelectionMode.ANY_STATE)
			else:
				var node := graph.get_node_or_null(NodePath(_graph_name(old.from_state))) if old != null else null
				select_graph_state(node.state if node != null else null)
	elif selection_mode == SelectionMode.STATE:
		if not is_instance_valid(selected_state) or (not state_machine.owns_state(selected_state) and selected_state != state_machine.get_state_container()):
			selected_state = null
			selection_mode = SelectionMode.NONE
		_sync_graph_selection(selected_state)
	elif selection_mode == SelectionMode.TRANSITION_PAIR:
		transitions_panel.focus_pair(selected_pair.from, selected_pair.to, selected_pair.mode)
	else:
		_sync_graph_selection(null)
		if selection_mode in [SelectionMode.ENTRY, SelectionMode.EXIT, SelectionMode.ANY_STATE]: _select_boundary(selection_mode)
	_render_selection()


func _highlight_transition(transition: StateTransition) -> void:
	graph.queue_redraw()
	if transition_blocks.has(transition):
		syncing_selection = true
		transition_blocks[transition].selected = true
		syncing_selection = false


func _connection_key(from: StringName, from_port: int, to: StringName, to_port: int) -> String:
	return var_to_str([from, from_port, to, to_port])

func _is_entry_edge(edge: Dictionary) -> bool:
	return not entry_connection.is_empty() and _connection_key(edge.get("from_node", &""), edge.get("from_port", -1), edge.get("to_node", &""), edge.get("to_port", -1)) == _connection_key(entry_connection.from_node, entry_connection.from_port, entry_connection.to_node, entry_connection.to_port)


func transition_for_connection(edge: Dictionary) -> StateTransition:
	return connection_transitions.get(_connection_key(edge.from_node, edge.from_port, edge.to_node, edge.to_port))


func select_connection(edge: Dictionary) -> void:
	var hierarchy := _hierarchy_for_edge(edge)
	if hierarchy != null:
		select_graph_state(hierarchy)
		selected_connection_edge = edge.duplicate()
		graph.queue_redraw()
		return
	if not edge.has("from_port") or not edge.has("to_port"):
		var source: GraphNode = graph.get_node_or_null(NodePath(edge.from_node))
		if source == null: return
		var mode := StateTransition.SourceMode.HIERARCHY_ENTRY if source == entry_node else (StateTransition.SourceMode.ANY_STATE if source == any_state_node else StateTransition.SourceMode.STATE)
		var target: StringName = StateTransition.EXIT_TARGET if is_instance_valid(exit_node) and edge.to_node == exit_node.name else StringName(edge.to_node)
		transitions_panel.select_pair(&"" if source.state == null else StringName(source.state.name), target, mode)
		return
	var branch: Dictionary = random_branch_connections.get(_connection_key(edge.from_node, edge.from_port, edge.to_node, edge.to_port), {})
	if not branch.is_empty():
		_select_random_branch(branch.routing, branch.branch, edge)
		return
	if _is_entry_edge(edge):
		_select_boundary(SelectionMode.ENTRY)
		selected_connection_edge = edge.duplicate()
		graph.queue_redraw()
		return
	var transition := transition_for_connection(edge)
	if transition != null:
		right_tabs.current_tab = 1
		_select_transition(transition)
		selected_connection_edge = edge.duplicate()


func _create_transition(machine: FiniteStateMachine, from: StringName, to: StringName, mode: int, trigger: int) -> void:
	if not is_instance_valid(machine) or machine != state_machine: return
	if _graph_target(to).is_empty() or (mode == StateTransition.SourceMode.STATE and _graph_name(from).is_empty()): return
	var transition: StateTransition = actions.connect_states(machine, from, to, true, mode, trigger)
	if transition != null:
		# Preserve the dialog's existing create-then-edit workflow. Browsing an
		# existing Tree leaf uses show_inspector=false and never jumps tabs.
		_select_transition(transition)
		transition_editor.focus_created_trigger.call_deferred(transition)


func _native_selected_node() -> Node:
	if not is_instance_valid(editor_interface): return null
	var nodes := editor_interface.get_selection().get_selected_nodes()
	return nodes[0] if nodes.size() == 1 else null


func _prepare_creation() -> bool:
	var selected := _native_selected_node()
	var target := state_machine
	var anchor: State
	if selected is HierarchyState:
		target = selected.get_nested_machine()
	elif selected is FiniteStateMachine: target = selected
	elif selected is State:
		target = FiniteStateMachine.machine_for_state(selected)
		anchor = selected
	else: anchor = _selected_state()
	if not is_instance_valid(target):
		dialogs.show_error("Select a FiniteStateMachine, HierarchyState or State before creating States.")
		return false
	if state_machine != target: _navigate_machine(target)
	context_machine = target
	create_insert_index = _insertion_index(target, anchor)
	create_position = _new_state_position(anchor)
	return true


func _insertion_index(machine: FiniteStateMachine, anchor: State) -> int:
	if is_instance_valid(anchor) and machine.owns_state(anchor): return anchor.get_index() + 1
	var index := 0
	for child in machine.get_state_container().get_children():
		if child is State: index = child.get_index() + 1
	return index


func _new_state_position(anchor: State) -> Vector2:
	var position := (graph.scroll_offset + graph.size * 0.5) / graph.zoom
	var children := graph.get_children()
	if is_instance_valid(anchor) and state_machine.owns_state(anchor):
		for node in children:
			if node is GraphNode and node.state == anchor:
				position = node.position_offset + Vector2(60, maxf(node.size.y, 78) + 40)
	var candidate := Rect2(position, Vector2(210, 100))
	var occupied := false
	for node in children:
		if node is GraphNode and Rect2(node.position_offset - Vector2(20, 20), node.size.max(Vector2(190, 78)) + Vector2(40, 40)).intersects(candidate):
			occupied = true
			break
	if not occupied: return position.snapped(Vector2(20, 20))
	# Allocate a bounds snapshot only after a collision. Bounds cannot change
	# during this synchronous search; hidden nodes still occupy space.
	var occupied_bounds: Array[Rect2] = []
	for node in children:
		if node is GraphNode:
			occupied_bounds.append(Rect2(node.position_offset - Vector2(20, 20), node.size.max(Vector2(190, 78)) + Vector2(40, 40)))
	for attempt in range(1, 1024):
		position.y += 120
		candidate.position = position
		occupied = false
		for bounds in occupied_bounds:
			if bounds.intersects(candidate):
				occupied = true
				break
		if not occupied: return position.snapped(Vector2(20, 20))
	# All 1024 candidates collided: keep the original one-step-past fallback.
	return (position + Vector2(0, 120)).snapped(Vector2(20, 20))


func _select_created_state(state: State) -> void:
	select_graph_state(state)
	if is_instance_valid(state) and is_instance_valid(editor_interface):
		syncing_selection = true
		var selection := editor_interface.get_selection()
		selection.clear()
		selection.add_node(state)
		editor_interface.inspect_object(state)
		syncing_selection = false


func _build_appearance_popup() -> void:
	appearance_controller._build_appearance_popup(self)

func _refresh_appearance_controls() -> void:
	appearance_controller._refresh_appearance_controls(self)

func _commit_appearance_color(picker: ColorPickerButton, key: String) -> void:
	appearance_controller._commit_appearance_color(self, picker, key)

func _apply_appearance_color(key: String, color: Color) -> void:
	appearance_controller._apply_appearance_color(self, key, color)

func _show_appearance_popup() -> void:
	appearance_controller._show_appearance_popup(self)

func _apply_appearance(changed_key: String = "") -> void:
	appearance_controller._apply_appearance(self, changed_key)

func _apply_any_state_appearance() -> void:
	appearance_controller._apply_any_state_appearance(self)

func _apply_debug_appearance() -> void:
	appearance_controller._apply_debug_appearance(self)

func _apply_state_appearance(changed_key: String = "") -> void:
	appearance_controller._apply_state_appearance(self, changed_key)

func _state_graph_node(state: State) -> GraphNode:
	return appearance_controller._state_graph_node(self, state)

func _resolved_state_color(state: State, preview_color: Variant = null) -> Color:
	return appearance_controller._resolved_state_color(self, state, preview_color)

func _apply_boundary_appearance(is_entry: bool) -> void:
	appearance_controller._apply_boundary_appearance(self, is_entry)

func _apply_transition_default_appearance() -> void:
	appearance_controller._apply_transition_default_appearance(self)

func _apply_random_default_appearance() -> void:
	appearance_controller._apply_random_default_appearance(self)

func _apply_state_graph_color(node: GraphNode, state: State, preview_color: Variant = null) -> void:
	appearance_controller._apply_state_graph_color(self, node, state, preview_color)

func _preview_state_color(state: State, color: Color) -> void:
	appearance_controller._preview_state_color(self, state, color)

func _commit_state_color_edit(machine: FiniteStateMachine, state: State, had_color: bool, previous: Color, color: Color) -> void:
	appearance_controller._commit_state_color_edit(self, machine, state, had_color, previous, color)

func _reset_state_color(machine: FiniteStateMachine, state: State) -> void:
	appearance_controller._reset_state_color(self, machine, state)

func _state_color_changed(machine: FiniteStateMachine, state: State) -> void:
	appearance_controller._state_color_changed(self, machine, state)

func set_state_machine(value: FiniteStateMachine) -> void:
	selected_connection_edge.clear()
	if is_instance_valid(value) and state_machine == value:
		return
	selection_mode = SelectionMode.NONE
	pending_debug_event.clear()
	selected_state = null
	selected_transition = null
	selected_random = null
	selected_pair.clear()
	selected_boundary = &""
	_disconnect_observers()
	if is_instance_valid(state_machine): graph_views[state_machine.get_instance_id()] = {"scroll": graph.scroll_offset, "zoom": graph.zoom}
	state_machine = value if is_instance_valid(value) else null
	var view: Dictionary = graph_views.get(state_machine.get_instance_id(), {}) if is_instance_valid(state_machine) else {}
	graph.zoom = view.get("zoom", 1.0)
	graph.scroll_offset = view.get("scroll", Vector2.ZERO)
	any_source_requested = false
	transition_editor.set_machine(state_machine)
	move_before.clear()
	if is_instance_valid(state_machine):
		state_machine.tree_exiting.connect(_on_machine_tree_exiting)
		state_machine.get_state_container().child_order_changed.connect(_queue_refresh)
		state_machine.editor_data_changed.connect(_queue_refresh)
	refresh()
	live_debug.set_machine(state_machine)
	if validation_search != null: validation_search.set_machine(state_machine)


func _disconnect_observers() -> void:
	if is_instance_valid(state_machine):
		for pair in [[state_machine.tree_exiting, _on_machine_tree_exiting], [state_machine.get_state_container().child_order_changed, _queue_refresh], [state_machine.editor_data_changed, _queue_refresh]]:
			if pair[0].is_connected(pair[1]):
				pair[0].disconnect(pair[1])
	_disconnect_states()


func _disconnect_states() -> void:
	for state in observed_states:
		if is_instance_valid(state) and state.renamed.is_connected(_state_renamed.bind(state)):
			state.renamed.disconnect(_state_renamed.bind(state))
	observed_states.clear()


func _on_machine_tree_exiting() -> void:
	set_state_machine(null)


func _exit_tree() -> void:
	clipboard.clear()
	_cancel_connection_drag()
	if validation_search != null: validation_search.shutdown()
	_disconnect_observers()
	state_machine = null
	if is_instance_valid(transition_editor): transition_editor.set_machine(null)
	move_before.clear()


func _queue_refresh() -> void:
	if not refresh_pending and is_inside_tree():
		refresh_pending = true
		_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	if not refresh_pending: return
	refresh_pending = false
	if not move_before.is_empty():
		await get_tree().process_frame
		if is_inside_tree(): _queue_refresh()
		return
	if is_inside_tree():
		if is_instance_valid(state_machine) and topology == _topology(): _refresh_block_values()
		else: refresh()


func _on_action_changed(machine: FiniteStateMachine) -> void:
	if machine == state_machine:
		if random_visual_update or random_visual_synced:
			random_visual_synced = false
			_sync_random_visuals()
			topology = _topology()
			source_dock_updated = true
		var native := _native_selected_node()
		if native == null or native is State and not native.is_inside_tree():
			# Undoing creation can detach the selected node. Keep authoring in its FSM.
			if is_instance_valid(editor_interface):
				syncing_selection = true
				var selection := editor_interface.get_selection()
				selection.clear()
				selection.add_node(machine.get_state_container())
				syncing_selection = false
		var transition: StateTransition = transition_editor.selected
		if transition != null and transition in machine.transitions:
			if transition_editor.source_mode_filter >= 0: transition_editor.source_mode_filter = transition.source_mode
			if transition.source_mode == StateTransition.SourceMode.ANY_STATE:
				transition_editor.source_filter = &""
			elif not transition_editor.source_filter.is_empty():
				transition_editor.source_filter = transition.from_state
			if not transition_editor.target_filter.is_empty():
				transition_editor.target_filter = transition.to_state
		if paste_topology_pending:
			paste_topology_pending = false
			if not _sync_paste_topology(): refresh()
			_restore_selection()
			validation_search.rebuild()
		elif source_dock_updated:
			source_dock_updated = false
			_restore_selection()
			_refresh_warning_summary()
		elif topology == _topology():
			_refresh_block_values()
		elif structure_topology == _structure_topology() and _sync_transition_topology():
			_restore_selection()
			_refresh_warning_summary()
		else: refresh()
		_apply_graph_visibility()

func _structure_topology() -> String:
	if not is_instance_valid(state_machine): return ""
	var signature := [state_machine.initial_state]
	for child in state_machine.get_state_container().get_children():
		if child is State: signature.append([child.get_instance_id(), child.name, child.get_script()])
	return str(signature)

func _sync_paste_topology() -> bool:
	# Paste histories only add/remove copied States and their outgoing Resources.
	# Reuse unrelated cards/curves, including in a 300-transition graph.
	for state in observed_states.keys():
		if is_instance_valid(state) and state_machine.owns_state(state): continue
		if is_instance_valid(state) and state.renamed.is_connected(_state_renamed.bind(state)): state.renamed.disconnect(_state_renamed.bind(state))
		observed_states.erase(state)
	for node in graph.get_children():
		if node is NODE_SCRIPT and not state_machine.owns_state(node.state): graph.remove_child(node); node.queue_free()
	graph_index.rebuild(state_machine)
	for node in graph.get_children():
		if node is NODE_SCRIPT: graph_index.register_node(node.state, node)
	for state in state_machine.get_state_container().get_children():
		if not state is State or observed_states.has(state): continue
		observed_states[state] = String(state.name)
		state.renamed.connect(_state_renamed.bind(state))
		_create_graph_node(state, observed_states.size() - 1)
	if not _sync_transition_topology(): return false
	_sync_hierarchy_exit_connections()
	structure_topology = _structure_topology()
	empty_label.visible = observed_states.is_empty()
	_refresh_warning_summary()
	return true

func _sync_transition_topology() -> bool:
	# Only structural changes (States/boundaries) need a graph reconstruction.
	for route in state_machine.transitions:
		if route == null: continue
		if _route_source(route).is_empty(): return false
		if route.target_mode == StateTransition.TargetMode.RANDOM and not random_blocks.has(route.random_routing): return false
	_trace_connection_sync("commit")
	var random_ownership_changed := false
	for route in transition_blocks.keys():
		if route == fallback_entry or drafts.has(route) or route in state_machine.transitions: continue
		if route.random_routing != null: random_ownership_changed = true
		var old: Dictionary = transition_connections.get(route, {})
		if not old.is_empty():
			graph.disconnect_node(old.from_node, old.from_port, old.to_node, old.to_port)
			connection_transitions.erase(_connection_key(old.from_node, old.from_port, old.to_node, old.to_port))
			transition_connections.erase(route)
		var block: GraphNode = transition_blocks[route]
		transition_blocks.erase(route)
		graph.remove_child(block)
		block.queue_free()
	graph_index.rebuild(state_machine)
	for node in graph.get_children():
		if node is NODE_SCRIPT: graph_index.register_node(node.state, node)
	for node in graph.get_children():
		if node is NODE_SCRIPT:
			node.set_outgoing_transitions(graph_index.routes_for(node.state), editor_interface)
			node.set_incoming_transitions(graph_index.incoming_for(node.state.name))
	if is_instance_valid(any_state_node):
		var any_routes: Array[StateTransition] = []
		for route in state_machine.transitions:
			if route != null and route.source_mode == StateTransition.SourceMode.ANY_STATE: any_routes.append(route)
		any_state_node.set_outgoing_transitions(any_routes, editor_interface)
	for route in state_machine.transitions:
		if route == null: continue
		var block: GraphNode = transition_blocks.get(route)
		if block == null or block.draft:
			if block == null: block = _make_block(route, false)
			block.draft = false
			block.dock_source = _route_source(route)
			block.refresh_summary()
		if transition_connections.has(route): continue
		var target: StringName = _route_target(route)
		if not target.is_empty():
			var edge := _connect_block_segment(block.name, target, route)
			edge.source_edge = {}
			edge.source_node = block.dock_source
			transition_connections[route] = edge
	if random_ownership_changed: _sync_random_visuals()
	_dock_blocks()
	topology = _topology()
	transitions_panel.rebuild(state_machine)
	transition_editor.refresh()
	var orphans: Array[StateTransition] = actions.orphan_transitions(state_machine)
	orphan_button.visible = not orphans.is_empty()
	orphan_button.text = "Remove Orphan Transitions (%d)" % orphans.size()
	_queue_connection_redraw()
	return true

func _trace_connection_sync(event: String) -> void:
	if not trace_connection_sync or not is_instance_valid(graph): return
	connection_sync_trace.append({"event": event, "usec": Time.get_ticks_usec(), "frame": Engine.get_process_frames(), "edges": graph.get_connection_list().size(), "rendered": connection_draw_records.size()})
	if connection_sync_trace.size() > 256: connection_sync_trace.pop_front()

func _watch_connection_geometry(node: Node) -> void:
	if not node is GraphNode: return
	node.item_rect_changed.connect(_queue_connection_redraw)
	node.slot_updated.connect(func(_slot): _queue_connection_redraw())
	_queue_connection_redraw()

func is_graph_state_hidden(state: State) -> bool:
	return is_instance_valid(state) and bool(state.get_meta(actions.HIDDEN_META, false))

func _reveal_hidden_state(state: State) -> void:
	if not is_graph_state_hidden(state) or show_hidden_states: return
	show_hidden_states = true
	show_hidden_button.set_pressed_no_signal(true)
	_apply_graph_visibility()

func _apply_graph_visibility() -> void:
	if not is_instance_valid(graph): return
	var count := 0
	for node in graph.get_children():
		if not node is NODE_SCRIPT: continue
		var hidden := is_graph_state_hidden(node.state)
		if hidden: count += 1
		node.visible = not hidden or show_hidden_states
		node.modulate = Color(1, 1, 1, 0.5 if hidden else 1.0)
		node.update_graph_visibility(hidden)
	for block in transition_blocks.values():
		if not is_instance_valid(block): continue
		var source := graph.get_node_or_null(NodePath(block.dock_source))
		var hidden: bool = source is NODE_SCRIPT and is_graph_state_hidden(source.state)
		block.visible = not hidden or show_hidden_states
		block.modulate = Color(1, 1, 1, 0.5 if hidden else 1.0)
	if is_instance_valid(show_hidden_button): show_hidden_button.text = "Show Hidden (%d)" % count
	if not is_loading and (count > 0 or visibility_connections_active):
		visibility_connections_active = _sync_graph_visibility_connections() or count > 0
	graph.queue_redraw()

func _edge_has_visible_ports(edge: Dictionary) -> bool:
	var source := graph.get_node_or_null(NodePath(edge.from_node)) as GraphNode
	var target := graph.get_node_or_null(NodePath(edge.to_node)) as GraphNode
	return source != null and target != null and source.visible and target.visible and int(edge.from_port) >= 0 and int(edge.to_port) >= 0 and int(edge.from_port) < source.get_output_port_count() and int(edge.to_port) < target.get_input_port_count()

func _sync_graph_visibility_connections() -> bool:
	# Hidden GraphNodes can have empty native port caches. Keep their logical edge
	# records, but never leave native GraphEdit wires accessing those hidden ports.
	var desired := {}
	var pending := false
	var edges: Array = transition_connections.values() + hierarchy_exit_connections.values() + random_branch_connections.values()
	if not entry_connection.is_empty(): edges.append(entry_connection)
	for edge: Dictionary in edges:
		if edge.is_empty(): continue
		if _edge_has_visible_ports(edge):
			desired[_connection_key(edge.from_node, edge.from_port, edge.to_node, edge.to_port)] = edge
		else:
			var source := graph.get_node_or_null(NodePath(edge.from_node)) as GraphNode
			var target := graph.get_node_or_null(NodePath(edge.to_node)) as GraphNode
			if source != null and target != null and source.visible and target.visible: pending = true
	for edge in graph.get_connection_list():
		if not desired.has(_connection_key(edge.from_node, edge.from_port, edge.to_node, edge.to_port)):
			graph.disconnect_node(edge.from_node, edge.from_port, edge.to_node, edge.to_port)
	for edge: Dictionary in desired.values():
		if not graph.is_node_connected(edge.from_node, edge.from_port, edge.to_node, edge.to_port): graph.connect_node(edge.from_node, edge.from_port, edge.to_node, edge.to_port)
	return pending

func _queue_connection_redraw() -> void:
	if not is_instance_valid(graph): return
	graph.queue_redraw()
	if connection_redraw_pending or not is_inside_tree(): return
	connection_redraw_pending = true
	_flush_connection_redraw.call_deferred()

func _flush_connection_redraw() -> void:
	connection_redraw_pending = false
	if not is_inside_tree() or not is_instance_valid(graph): return
	if visibility_connections_active: _apply_graph_visibility()
	_trace_connection_sync("geometry_ready")
	graph.queue_redraw()


func _state_renamed(state: State) -> void:
	if actions.applying or not is_instance_valid(state_machine) or not is_instance_valid(state):
		return
	var previous: String = observed_states.get(state, String(state.name))
	if not state_machine.graph_positions.has(previous):
		state_machine.graph_positions[previous] = _positions_from_graph().get(previous, Vector2.ZERO)
	_sync_external_rename.call_deferred(state_machine, state, previous, String(state.name))


func _sync_external_rename(machine: FiniteStateMachine, state: State, previous: String, current: String) -> void:
	if not is_instance_valid(machine) or not machine.owns_state(state) or String(state.name) != current:
		return
	# SceneTree owns its rename action; follow its do/undo without nesting history.
	actions.rename_state(machine, state, current, previous, false)


func refresh() -> void:
	if not is_instance_valid(graph):
		return
	_cancel_connection_drag()
	is_loading = true
	_clear_debug_flash()
	graph_revision += 1
	graph_index.rebuild(null)
	warning_summary.text = ""
	_refresh_breadcrumbs()
	_disconnect_states()
	graph.clear_connections()
	entry_connection.clear()
	connection_transitions.clear()
	transition_connections.clear()
	hierarchy_exit_connections.clear()
	transition_blocks.clear()
	random_blocks.clear()
	random_branch_connections.clear()
	any_state_node = null
	entry_node = null
	exit_node = null
	fallback_entry = null
	for child in graph.get_children():
		if child is GraphElement:
			graph.remove_child(child)
			child.queue_free()
	if not is_instance_valid(state_machine):
		transitions_panel.rebuild(null)
		orphan_button.hide()
		state_machine = null
		empty_label.text = "No State Machine selected\nSelect a FiniteStateMachine in the SceneTree\nor add one to start editing."
		empty_label.show()
		is_loading = false
		_debug_snapshot({})
		_render_selection()
		return
	if state_machine.migrate_legacy_transitions() and is_instance_valid(editor_interface):
		editor_interface.mark_scene_as_unsaved()
	graph_index.rebuild(state_machine)
	var orphans: Array[StateTransition] = actions.orphan_transitions(state_machine)
	orphan_button.visible = not orphans.is_empty()
	orphan_button.text = "Remove Orphan Transitions (%d)" % orphans.size()
	var index := 0
	for child in state_machine.get_state_container().get_children():
		if child is State:
			observed_states[child] = String(child.name)
			child.renamed.connect(_state_renamed.bind(child))
			_create_graph_node(child, index)
			index += 1
	empty_label.visible = index == 0
	empty_label.text = "No States yet\nDrag a State from the Palette or right-click to create one."
	_refresh_warning_summary()
	var has_any := any_source_requested
	if state_machine.has_hierarchy_boundary():
		var entry_routes: Array[StateTransition] = []
		for route in state_machine.transitions:
			if route != null and route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: entry_routes.append(route)
		if state_machine.owns_state(state_machine.initial_state):
			for key in entry_fallback_cache.keys():
				if not is_instance_valid(entry_fallback_cache[key].machine.get_ref()): entry_fallback_cache.erase(key)
			var cached: Dictionary = entry_fallback_cache.get(state_machine.get_instance_id(), {})
			fallback_entry = cached.route if not cached.is_empty() else StateTransition.new()
			entry_fallback_cache[state_machine.get_instance_id()] = {"machine": weakref(state_machine), "route": fallback_entry}
			fallback_entry.source_mode = StateTransition.SourceMode.HIERARCHY_ENTRY
			fallback_entry.to_state = state_machine.initial_state.name
			fallback_entry.set_meta("initial_fallback", true)
			if state_machine.get_state_container().has_meta(&"fsm_editor_entry_color"): fallback_entry.set_meta(TRANSITION_COLORS.META, state_machine.get_state_container().get_meta(&"fsm_editor_entry_color"))
			else: fallback_entry.remove_meta(TRANSITION_COLORS.META)
			if state_machine.get_state_container().has_meta(&"fsm_editor_initial_block_position"): fallback_entry.set_meta(BLOCK.POSITION_META, state_machine.get_state_container().get_meta(&"fsm_editor_initial_block_position"))
			else: fallback_entry.remove_meta(BLOCK.POSITION_META)
		entry_node = BOUNDARY.new()
		entry_node.name = "__FSM_ENTRY__"
		graph.add_child(entry_node, true)
		entry_node.setup(true)
		entry_node.set_routes(entry_routes, editor_interface)
		entry_node.position_offset = state_machine.graph_positions.get(BOUNDARY.ENTRY_POSITION, Vector2(-230, 30))
		entry_node.position_offset_changed.connect(_on_node_position_changed.bind(entry_node, graph_revision))
		entry_node.transition_selected.connect(_select_transition)
		entry_node.transition_creation_requested.connect(func(): _open_graph_creation(entry_node.name))
		exit_node = BOUNDARY.new()
		exit_node.name = "__FSM_EXIT__"
		graph.add_child(exit_node, true)
		exit_node.setup(false)
		exit_node.set_routes(graph_index.incoming_for(StateTransition.EXIT_TARGET), editor_interface)
		exit_node.position_offset = state_machine.graph_positions.get(BOUNDARY.EXIT_POSITION, Vector2(900, 30))
		exit_node.position_offset_changed.connect(_on_node_position_changed.bind(exit_node, graph_revision))
	transitions_panel.fallback_entry = fallback_entry
	transitions_panel.rebuild(state_machine)
	transition_editor.fallback_entry = fallback_entry
	for transition in state_machine.transitions:
		if transition != null and transition.source_mode == StateTransition.SourceMode.ANY_STATE: has_any = true
	if has_any:
		any_state_node = ANY_NODE.new()
		any_state_node.name = "__FSM_ANY_STATE__"
		graph.add_child(any_state_node, true)
		any_state_node.setup()
		any_state_node.transition_creation_requested.connect(func(): _open_graph_creation(any_state_node.name))
		any_state_node.transition_selected.connect(_select_transition)
		var outgoing_any: Array[StateTransition] = []
		for transition in state_machine.transitions:
			if transition != null and transition.source_mode == StateTransition.SourceMode.ANY_STATE: outgoing_any.append(transition)
		any_state_node.set_outgoing_transitions(outgoing_any, editor_interface)
		any_state_node.position_offset = state_machine.graph_positions.get(ANY_NODE.POSITION_KEY, Vector2(-220, 30))
		any_state_node.position_offset_changed.connect(_on_node_position_changed.bind(any_state_node, graph_revision))
	_restore_random_blocks()
	_load_connections()
	_sync_hierarchy_exit_connections()
	_restore_drafts()
	_dock_blocks()
	_dock_blocks.call_deferred()
	topology = _topology()
	structure_topology = _structure_topology()
	_apply_block_appearance()
	transition_editor.refresh()
	is_loading = false
	_restore_selection()
	_apply_graph_visibility()
	_debug_snapshot(debug_record)


func _refresh_warning_summary() -> void:
	if not is_instance_valid(warning_summary): return
	warning_summary.text = ""
	warning_summary.tooltip_text = ""
	if not is_instance_valid(state_machine): return
	var warnings := state_machine._get_configuration_warnings()
	if not warnings.is_empty():
		warning_summary.text = "%d warning%s · %s" % [warnings.size(), "s" if warnings.size() != 1 else "", warnings[0]]
		warning_summary.tooltip_text = "\n".join(warnings)

func _debug_snapshot(record: Dictionary) -> void:
	if debug_record.get("id", "") != record.get("id", "") or debug_record.get("session_id", -1) != record.get("session_id", -1):
		pending_debug_event.clear()
		_clear_debug_flash()
	debug_record = record
	if is_instance_valid(selection_inspector): selection_inspector.update_active(record)
	if not workspace_active: return
	var current: String = str(record.get("current", ""))
	for candidate in observed_states:
		if is_instance_valid(candidate) and String(candidate.name).nocasecmp_to(current) == 0: _reveal_hidden_state(candidate)
	var active_color := APPEARANCE.get_color(_editor_settings(), "active_state_accent") if is_instance_valid(editor_interface) else Color("68bd87")
	for node in graph.get_children():
		if node is GraphNode and node.has_method("set_debug_active"):
			node.set_debug_active(not record.is_empty() and record.get("active", true) and String(node.name).to_lower() == current.to_lower(), active_color)
	var token := "%s:%s:%s" % [record.get("session_id", -1), record.get("id", ""), current]
	if token != debug_follow_token:
		debug_follow_token = token
		if not record.is_empty() and live_debug.follow.button_pressed:
			_follow_debug_state(current)
	if record.is_empty():
		_clear_debug_flash()


func _follow_debug_state(current: String) -> void:
	var name := _graph_name(StringName(current))
	var node := graph.get_node_or_null(NodePath(name)) as GraphNode if not name.is_empty() else null
	if node == null:
		return
	if graph.size.x <= 50 or graph.size.y <= 50:
		return
	var visible_rect := Rect2(graph.scroll_offset, graph.size).grow(-25)
	var bounds := Rect2(node.position_offset * graph.zoom, node.size * graph.zoom)
	if not visible_rect.encloses(bounds):
		graph.scroll_offset = bounds.get_center() - graph.size / 2


func _debug_flash(event: Dictionary) -> void:
	if event.has("id") and event.id != live_debug.selected_id or event.has("session_id") and event.session_id != live_debug.selected_session: return
	if not workspace_active:
		pending_debug_event = event.duplicate()
		pending_debug_event["id"] = live_debug.selected_id
		pending_debug_event["session_id"] = live_debug.selected_session
		return
	_clear_debug_flash()
	if event.is_empty() or not is_instance_valid(state_machine):
		return
	# Runtime feedback decorates the background; it never tints the foreground.
	var from: StringName = any_state_node.name if event.get("any_state", false) and is_instance_valid(any_state_node) else _graph_name(StringName(event.get("from", "")))
	var to := _graph_name(StringName(event.get("to", "")))
	var accent := APPEARANCE.get_color(_editor_settings(), "last_transition_accent")
	transition_editor.set_debug_transition(event, accent)
	transitions_panel.set_debug_transition(event, accent)
	var index := int(event.get("transition_index", -1))
	if index >= 0 and index < state_machine.transitions.size():
		var transition: StateTransition = state_machine.transitions[index]
		if transition == null: return
		if transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY and is_instance_valid(entry_node): from = entry_node.name
		if transition.destination_mode == StateTransition.DestinationMode.EXIT and is_instance_valid(exit_node): to = exit_node.name
		var edge: Dictionary = transition_connections.get(transition, {})
		var description: String = preload("res://addons/state_machine/runtime/transition_labels.gd").trigger_description(transition)
		if not edge.is_empty() and edge.get("source_node", &"") == from and (edge.to_node == to or transition.target_mode == StateTransition.TargetMode.RANDOM) and description == event.get("description", ""):
			debug_edge = edge.duplicate()
			debug_edge.from = from
			debug_edge.to = to
			_debug_flash_amount(1.0)
	debug_tween = create_tween()
	debug_tween.tween_method(_debug_flash_amount, 1.0, 0.0, 0.75)
	debug_tween.tween_callback(_clear_debug_flash)


func _debug_flash_amount(amount: float) -> void:
	debug_outline_amount = amount if not debug_edge.is_empty() else 0.0
	if is_instance_valid(graph): graph.queue_redraw()

func _history_transition_selected(event: Dictionary) -> void:
	if not is_instance_valid(state_machine): return
	var index := int(event.get("transition_index", -1))
	if index < 0 or index >= state_machine.transitions.size(): return
	var route: StateTransition = state_machine.transitions[index]
	if route == null or not transition_blocks.has(route): return
	# Refuse stale history if authoring has changed since this runtime event.
	if route.trigger_type != event.get("trigger", -1): return
	if preload("res://addons/state_machine/runtime/transition_labels.gd").trigger_description(route) != event.get("description", ""): return
	if route.source_mode == StateTransition.SourceMode.STATE and String(route.from_state).nocasecmp_to(event.get("from", "")) != 0: return
	if route.target_mode == StateTransition.TargetMode.DIRECT and route.destination_mode == StateTransition.DestinationMode.STATE and String(route.to_state).nocasecmp_to(event.get("to", "")) != 0: return
	_select_transition(route, false)
	_frame(true)


func _clear_debug_flash() -> void:
	if is_instance_valid(debug_tween):
		debug_tween.kill()
	debug_tween = null
	_debug_flash_amount(0)
	debug_edge.clear()
	if is_instance_valid(transition_editor):
		transition_editor.set_debug_transition({}, Color.TRANSPARENT)
	if is_instance_valid(transitions_panel): transitions_panel.set_debug_transition({}, Color.TRANSPARENT)
	if selected_transition != null and is_instance_valid(graph): _highlight_transition(selected_transition)


func _create_graph_node(state: State, index: int) -> void:
	var node = NODE_SCRIPT.new()
	graph.add_child(node)
	var warning := ""
	if graph_index.duplicate_name(state):
		warning = "Duplicate State name (case-insensitive)."
	if state.get_script() == null:
		warning += " State has no script."
	node.setup(state, state == state_machine.initial_state, warning)
	graph_index.register_node(state, node)
	node.position_offset = state_machine.graph_positions.get(String(state.name), Vector2((index % 4) * 220, floori(index / 4.0) * 135))
	var outgoing: Array[StateTransition] = graph_index.routes_for(state)
	node.set_incoming_transitions(graph_index.incoming_for(state.name))
	node.set_outgoing_transitions(outgoing, editor_interface)
	node.rename_requested.connect(_rename_requested)
	node.context_requested.connect(_state_popup)
	node.graph_visibility_requested.connect(func(value): actions.set_graph_visible(state_machine, value, is_graph_state_hidden(value)))
	node.script_requested.connect(_open_script)
	node.nested_requested.connect(_open_nested)
	node.transition_creation_requested.connect(func(): _open_graph_creation(node.name))
	node.transition_selected.connect(_select_transition)
	node.position_offset_changed.connect(_on_node_position_changed.bind(node, graph_revision))


func _load_connections() -> void:
	var visible: Array[StateTransition] = state_machine.transitions.duplicate()
	var pairs := {}
	for route in visible:
		if route == null: continue
		var from := _route_source(route)
		var to: StringName = _route_target(route)
		var pair := str([from, to])
		var offset: int = pairs.get(pair, 0)
		pairs[pair] = offset + 1
		var block := _make_block(route, false)
		if not (route.target_mode == StateTransition.TargetMode.DIRECT and route.destination_mode == StateTransition.DestinationMode.STATE and route.to_state.is_empty()):
			block.position_offset = _block_default_position(from, to, offset)
		var source_edge := {}
		block.dock_source = from
		block.update_color()
		var target_edge := {}
		if not to.is_empty(): target_edge = _connect_block_segment(block.name, to, route)
		if not target_edge.is_empty():
			target_edge.source_edge = source_edge
			target_edge.source_node = from
			transition_connections[route] = target_edge
	_sync_entry_connection()

func _sync_entry_connection() -> void:
	if not is_instance_valid(entry_node) or not is_instance_valid(state_machine): return
	var target: State = state_machine.initial_state if state_machine.owns_state(state_machine.initial_state) else null
	if target == null: return
	var destination := _graph_name(target.name)
	if destination.is_empty() or graph.get_node_or_null(NodePath(destination)) == null: return
	entry_connection = {"from_node": entry_node.name, "from_port": entry_node.creation_output_port(), "to_node": destination, "to_port": 0}
	graph.connect_node(entry_connection.from_node, entry_connection.from_port, entry_connection.to_node, entry_connection.to_port)
	if fallback_entry != null: transition_connections[fallback_entry] = entry_connection.duplicate()

func _hierarchy_for_edge(edge: Dictionary) -> HierarchyState:
	if edge.is_empty(): return null
	for hierarchy in hierarchy_exit_connections:
		var current: Dictionary = hierarchy_exit_connections[hierarchy]
		if _connection_key(edge.from_node, edge.from_port, edge.to_node, edge.to_port) == _connection_key(current.from_node, current.from_port, current.to_node, current.to_port): return hierarchy
	return null

func _hierarchy_exit_changed(machine: FiniteStateMachine, hierarchy: HierarchyState) -> void:
	if machine != state_machine: return
	_sync_hierarchy_exit_connections()
	if selected_state == hierarchy: _render_selection()
	source_dock_updated = true
	if is_instance_valid(editor_interface): editor_interface.mark_scene_as_unsaved()

func _sync_hierarchy_exit_connections() -> void:
	if not is_instance_valid(state_machine): return
	for hierarchy in hierarchy_exit_connections.keys():
		var edge: Dictionary = hierarchy_exit_connections[hierarchy]
		var target: StringName = _graph_target(hierarchy.exit_target) if is_instance_valid(hierarchy) and state_machine.owns_state(hierarchy) else &""
		if target != edge.to_node:
			graph.disconnect_node(edge.from_node, edge.from_port, edge.to_node, edge.to_port)
			hierarchy_exit_connections.erase(hierarchy)
	for node in graph.get_children():
		if not node is NODE_SCRIPT or not node.state is HierarchyState: continue
		var hierarchy: HierarchyState = node.state
		if hierarchy_exit_connections.has(hierarchy): continue
		var target := _graph_target(hierarchy.exit_target)
		if target.is_empty(): continue
		var edge := {"from_node": node.name, "from_port": 0, "to_node": target, "to_port": 0}
		graph.connect_node(node.name, 0, target, 0)
		hierarchy_exit_connections[hierarchy] = edge
	_queue_connection_redraw()

func _route_source(route: StateTransition) -> StringName:
	if route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: return entry_node.name if is_instance_valid(entry_node) else &""
	if route.source_mode == StateTransition.SourceMode.ANY_STATE: return any_state_node.name if is_instance_valid(any_state_node) else &""
	return _graph_name(route.from_state)

func _route_target(route: StateTransition) -> StringName:
	if route.target_mode == StateTransition.TargetMode.RANDOM and random_blocks.has(route.random_routing):
		return random_blocks[route.random_routing].name
	return _graph_target(route.target_key())

func _connect_block_segment(from: StringName, to: StringName, route: StateTransition) -> Dictionary:
	var edge := {"from_node": from, "from_port": 0, "to_node": to, "to_port": 0}
	graph.connect_node(from, 0, to, 0)
	connection_transitions[_connection_key(from, 0, to, 0)] = route
	transition_connections[route] = edge
	_trace_connection_sync("connect_node")
	_queue_connection_redraw()
	return edge

func _make_block(route: StateTransition, draft: bool) -> GraphNode:
	var block := BLOCK.new()
	block.name = "__FSM_TRANSITION_%s" % route.get_instance_id()
	graph.add_child(block)
	block.machine = state_machine
	block.setup(route, draft)
	block.docking_size_changed.connect(func(_changed_block): _queue_dock_blocks())
	block.context_requested.connect(_block_popup)
	block.gui_input.connect(_random_block_gui_input.bind(block))
	block.source_drag_started.connect(_begin_block_move)
	block.position_offset_changed.connect(_on_node_position_changed.bind(block, graph_revision))
	transition_blocks[route] = block
	return block

func _block_default_position(from: StringName, to: StringName, offset: int) -> Vector2:
	var source := graph.get_node_or_null(NodePath(from)) as GraphNode if not from.is_empty() else null
	var target := graph.get_node_or_null(NodePath(to)) as GraphNode if not to.is_empty() else null
	if source == null or target == null: return Vector2(250, 180 + offset * 100)
	if source == target: return source.position_offset + Vector2(230, 110 + offset * 100)
	return (source.position_offset + target.position_offset) * 0.5 + Vector2(0, 110 + offset * 100)


func _graph_name(requested: StringName) -> StringName:
	return graph_index.graph_name(requested)

func _graph_target(requested: StringName) -> StringName:
	return exit_node.name if requested == StateTransition.EXIT_TARGET and is_instance_valid(exit_node) else _graph_name(requested)

func _position_key(node: GraphNode) -> String:
	if node == entry_node: return BOUNDARY.ENTRY_POSITION
	if node == exit_node: return BOUNDARY.EXIT_POSITION
	return ANY_NODE.POSITION_KEY if node == any_state_node else String(node.name)


func _open_graph_creation(from: StringName, to: StringName = &"") -> void:
	if not is_instance_valid(state_machine): return
	var is_any := is_instance_valid(any_state_node) and from == any_state_node.name
	var is_entry := is_instance_valid(entry_node) and from == entry_node.name
	if not is_any and not is_entry and _graph_name(from).is_empty(): return
	if not to.is_empty() and _graph_target(to).is_empty(): return
	right_tabs.current_tab = 1
	show_authoring_dock()
	transitions_panel.open_create_for_source(&"" if is_any or is_entry else StringName(graph.get_node(NodePath(from)).state.name), StateTransition.SourceMode.HIERARCHY_ENTRY if is_entry else (StateTransition.SourceMode.ANY_STATE if is_any else StateTransition.SourceMode.STATE), to)

func _on_connection_request(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	var a := graph.get_node_or_null(NodePath(from)) as GraphNode
	var b := graph.get_node_or_null(NodePath(to)) as GraphNode
	if a is NODE_SCRIPT and a.state is HierarchyState:
		_cancel_connection_drag()
		if from_port == 0 and to_port == 0 and (b == exit_node or b is NODE_SCRIPT): actions.set_hierarchy_exit_target(state_machine, a.state, _target_name(b))
		return
	if a is RANDOM_BLOCK or b is RANDOM_BLOCK:
		_connect_random(a, from_port, b, to_port)
		return
	if a is BLOCK or b is BLOCK:
		_connect_transition_block(a, from_port, b, to_port)
		return
	if not reconnect.is_empty():
		if reconnect.route == fallback_entry:
			var request := reconnect.duplicate()
			_cancel_connection_drag()
			var target_node := graph.get_node_or_null(NodePath(to)) as GraphNode
			if request.machine == state_machine and request.target and from == entry_node.name and from_port == entry_node.creation_output_port() and target_node != null and target_node.state != null and state_machine.owns_state(target_node.state):
				actions.set_initial(state_machine, target_node.state)
			return
		_commit_reconnect(from, from_port, to, to_port)
		return
	_cancel_connection_drag()
	if is_instance_valid(state_machine):
		if is_instance_valid(entry_node) and to == entry_node.name or is_instance_valid(exit_node) and from == exit_node.name: return
		if is_instance_valid(exit_node) and to == exit_node.name: to = StateTransition.EXIT_TARGET
		if is_instance_valid(any_state_node) and to == any_state_node.name: return
		if _graph_target(to).is_empty(): return
		var source := graph.get_node_or_null(NodePath(from)) as GraphNode
		if source == null: return
		var destination: GraphNode = graph.get_node(NodePath(_graph_target(to)))
		if from_port < 0 or from_port >= source.get_output_port_count() or to_port < 0 or to_port >= destination.get_input_port_count(): return
		if source == entry_node:
			if from_port != entry_node.creation_output_port() or destination.state == null or not state_machine.owns_state(destination.state): return
			actions.set_initial(state_machine, destination.state)
			return
		if is_instance_valid(any_state_node) and from == any_state_node.name:
			var transition: StateTransition = actions.connect_states(state_machine, &"", to, true, StateTransition.SourceMode.ANY_STATE)
			if transition != null:
				_select_transition(transition, false)
		else:
			var kind := StateTransition.TriggerType.MANUAL
			var transition: StateTransition = actions.connect_states(state_machine, from, to, true, StateTransition.SourceMode.STATE, kind)
			if transition != null:
				_select_transition(transition, false)


func _on_disconnection_request(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	var edge := {"from_node": from, "from_port": from_port, "to_node": to, "to_port": to_port}
	if _hierarchy_for_edge(edge) != null: return # Retain the old target until a valid replacement is dropped.
	if _is_entry_edge(edge):
		if is_instance_valid(state_machine) and fallback_entry != null: connection_drag.begin(state_machine, fallback_entry, edge)
		return
	var route := transition_for_connection(edge)
	if route == null or not is_instance_valid(state_machine): return
	connection_drag.begin(state_machine, route, edge)


func _connection_drag_started(_node: StringName, _port: int, is_output: bool) -> void:
	connection_drag.started(is_output)

func _connection_drag_ended() -> void:
	connection_drag.ended()

func _cancel_connection_drag() -> void:
	_clear_palette_move()
	_finish_block_move(Vector2.ZERO, false)
	connection_drag.cancel(graph)
	curve_drag.clear()
	if is_instance_valid(graph): graph.queue_redraw()

func _connection_to_empty(_node: StringName, _port: int, _position: Vector2) -> void:
	_cancel_connection_drag()

func _connection_from_empty(_node: StringName, _port: int, _position: Vector2) -> void:
	_cancel_connection_drag()

func _input(event: InputEvent) -> void:
	if not palette_move.is_empty() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_clear_palette_move()
	if not block_move.is_empty():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_finish_block_move(Vector2.ZERO, false)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var point: Vector2 = graph.get_global_transform_with_canvas().affine_inverse() * event.position
			if block_move.active or point.distance_to(block_move.origin) > 6:
				block_move.active = true
				block_move.block.modulate.a = 0.8
				_update_block_insertion(point)
				graph.queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_finish_block_move(event.position, true)
			get_viewport().set_input_as_handled()
			return
	if not curve_drag.is_empty():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_connection_drag()
		elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			curve_drag.mouse = graph.get_global_transform_with_canvas().affine_inverse() * event.position
			curve_drag.active = curve_drag.origin.distance_to(curve_drag.mouse) > 8
			graph.queue_redraw()
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var request := curve_drag.duplicate()
			curve_drag.clear()
			graph.queue_redraw()
			if request.active and request.machine == state_machine:
				var local: Vector2 = graph.get_global_transform_with_canvas().affine_inverse() * event.position
				var target := _curve_drop_target(local)
				if not target.is_empty(): _on_connection_request(request.edge.from_node, request.edge.from_port, target.node, target.port)
				get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not dock_drag.is_empty():
		dock_cancelled = true
		_end_move()
	if not connection_drag_active: return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT or event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Let GraphEdit process a valid release first; also cover release outside it.
		_end_unhandled_connection_drag.call_deferred(connection_drag_token)

func _end_unhandled_connection_drag(token: int) -> void:
	if token == connection_drag_token: _cancel_connection_drag()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END: _clear_palette_move()
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_connection_drag()
		if not dock_drag.is_empty(): dock_cancelled = true; _end_move()

func _commit_reconnect(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	# Valid reconnects retain the exact block endpoint and are handled above.
	# Replacing the block end with a State must not reinterpret two visual wires
	# as a direct runtime transition or silently change the opposite endpoint.
	_cancel_connection_drag()


func _on_clear_connections_pressed() -> void:
	if is_instance_valid(state_machine):
		actions.clear_connections(state_machine)


func _positions_from_graph() -> Dictionary:
	var positions := state_machine.graph_positions.duplicate() if is_instance_valid(state_machine) else {}
	for child in graph.get_children():
		if child is GraphNode and not child is BLOCK and not child is RANDOM_BLOCK:
			positions[_position_key(child)] = child.position_offset
	return positions


func _begin_block_move(block: GraphNode, position: Vector2) -> void:
	if not block.source_movable or not is_instance_valid(state_machine): return
	_finish_block_move(Vector2.ZERO, false)
	_select_transition(block.transition)
	var viewport_point := block.get_global_transform_with_canvas() * position
	block_move = {"block": block, "route": block.transition, "machine": state_machine,
		"origin": graph.get_global_transform_with_canvas().affine_inverse() * viewport_point,
		"position": block.position_offset, "modulate": block.modulate, "z_index": block.z_index, "active": false,
		"hover": null, "index": -1, "mouse": graph.get_global_transform_with_canvas().affine_inverse() * viewport_point}
	block_move.grab = (block_move.origin + graph.scroll_offset) / graph.zoom - block.position_offset
	block.z_index = 1
	set_process(true)


func _block_move_valid_source(route: StateTransition, source: GraphNode) -> bool:
	if source == null or not source.visible or source.get_parent() != graph or source == exit_node: return false
	if source != any_state_node and source != entry_node:
		if not source is NODE_SCRIPT: return false
		if source.state == null or not state_machine.owns_state(source.state): return false
	return actions.valid_transition_source(state_machine, route, _source_mode(source), source.state.name if source.state != null else &"")


func _ordered_blocks() -> Array[GraphNode]:
	var result: Array[GraphNode] = []
	var seen := {}
	for route in state_machine.transitions:
		if transition_blocks.has(route):
			result.append(transition_blocks[route])
			seen[transition_blocks[route]] = true
	for block in transition_blocks.values():
		if seen.has(block): continue
		var data: Dictionary = drafts.get(block.transition, {})
		var anchor: StateTransition = data.get("before")
		if anchor != null and transition_blocks.has(anchor) and result.has(transition_blocks[anchor]):
			result.insert(result.find(transition_blocks[anchor]), block)
		else: result.append(block)
	return result


func _block_insertion(point: Vector2, route: StateTransition) -> Dictionary:
	var source := _dock_at(point)
	if not _block_move_valid_source(route, source): return {}
	var y := source.position_offset.y + maxf(source.size.y, source.get_combined_minimum_size().y)
	var index := 0
	for block in _ordered_blocks():
		var source_name: StringName = block.draft_source if block.draft else _route_source(block.transition)
		if block.transition == route or source_name != source.name: continue
		var height := maxf(block.size.y, block.get_combined_minimum_size().y)
		if point.y < y + height * 0.5: return {"source": source, "index": index}
		y += height
		index += 1
	return {"source": source, "index": index}


func _update_block_insertion(point: Vector2) -> void:
	block_move.mouse = point
	block_move.block.position_offset = (point + graph.scroll_offset) / graph.zoom - block_move.grab
	var insertion := _block_insertion((point + graph.scroll_offset) / graph.zoom, block_move.route) if Rect2(Vector2.ZERO, graph.size).has_point(point) else {}
	block_move.hover = insertion.get("source")
	block_move.index = insertion.get("index", -1)
	_dock_blocks()
	graph.queue_redraw()


func _process(delta: float) -> void:
	if not palette_move.is_empty():
		if not get_viewport().gui_is_dragging(): _clear_palette_move(); return
		var point := graph.get_local_mouse_position()
		if Rect2(Vector2.ZERO, graph.size).has_point(point):
			palette_move.entered = true
			palette_move.active = true
			var speed := -420.0 if point.y < 32 else (420.0 if point.y > graph.size.y - 32 else 0.0)
			graph.scroll_offset += Vector2(0, speed * delta)
			_update_palette_insertion(point)
		elif palette_move.entered and palette_move.active:
			palette_move.active = false
			palette_move.hover = null
			_dock_blocks()
			graph.queue_redraw()
		return
	if block_move.is_empty(): set_process(false); return
	if not block_move.active or not Rect2(Vector2.ZERO, graph.size).has_point(block_move.mouse): return
	var speed := -420.0 if block_move.mouse.y < 32 else (420.0 if block_move.mouse.y > graph.size.y - 32 else 0.0)
	if speed != 0:
		graph.scroll_offset += Vector2(0, speed * delta)
		_update_block_insertion(block_move.mouse)


func _finish_block_move(viewport_point: Vector2, commit: bool) -> void:
	if block_move.is_empty(): return
	var request := block_move
	block_move = {}
	set_process(false)
	var block: GraphNode = request.block
	if is_instance_valid(block):
		block.modulate = request.modulate
		block.z_index = request.z_index
		block.position_offset = request.position
	var moved := false
	if commit and request.active and request.machine == state_machine and is_instance_valid(state_machine) and request.route in state_machine.transitions and graph.get_global_rect().has_point(viewport_point):
		var point: Vector2 = graph.get_global_transform_with_canvas().affine_inverse() * viewport_point
		var insertion := _block_insertion((point + graph.scroll_offset) / graph.zoom, request.route)
		if not insertion.is_empty():
			var source: GraphNode = insertion.source
			var runtime_index := 0
			var visual_index := 0
			for sibling in _ordered_blocks():
				var source_name: StringName = sibling.draft_source if sibling.draft else _route_source(sibling.transition)
				if sibling.transition == request.route or source_name != source.name: continue
				if visual_index >= insertion.index: break
				if sibling.transition in state_machine.transitions: runtime_index += 1
				visual_index += 1
			moved = actions.reorder_transition(state_machine, request.route, _source_mode(source), source.state.name if source.state != null else &"", runtime_index)
	_dock_blocks()
	if is_instance_valid(graph): graph.queue_redraw()
	if moved: _select_transition(request.route, false)


func _draw_block_move() -> void:
	var preview := _insertion_preview()
	if preview.is_empty() or not preview.active: return
	var color := get_theme_color("accent_color", "Editor") if has_theme_color("accent_color", "Editor") else Color(0.3, 0.65, 1.0)
	if not block_move.is_empty() and block_move.hover == null:
		var original := Rect2(block_move.position * graph.zoom - graph.scroll_offset, block_move.block.size * graph.zoom)
		graph.draw_rect(original, Color(color, 0.3), false, 2)
	if preview.hover != null and preview.has("gap"):
		var gap := Rect2(preview.gap * graph.zoom - graph.scroll_offset, Vector2(preview.hover.size.x, _insertion_height(preview)) * graph.zoom)
		graph.draw_rect(gap, Color(color, 0.2), true)
		graph.draw_rect(gap, color, false, 2)
	for node in graph.get_children():
		if not node is GraphNode or node is BLOCK or node is RANDOM_BLOCK or not _block_move_valid_source(preview.route, node): continue
		var dock := Rect2((node.position_offset + Vector2(0, node.size.y)) * graph.zoom - graph.scroll_offset, Vector2(node.size.x, node.get_meta("dock_height", 0.0) + 80) * graph.zoom)
		graph.draw_rect(dock, Color(color, 0.12), true)
		graph.draw_rect(dock, Color(color, 0.65), false, 2)


func _insertion_preview() -> Dictionary:
	return palette_move if not palette_move.is_empty() else block_move


func _insertion_height(preview: Dictionary) -> float:
	return preview.block.size.y if preview.has("block") else 68.0


func _begin_palette_move(payload: Dictionary) -> void:
	_clear_palette_move()
	if not is_instance_valid(state_machine) or not payload.has("trigger"): return
	var route := actions.new_transition()
	route.trigger_type = payload.trigger
	palette_move = {"route": route, "payload": payload, "active": true, "entered": false, "hover": null, "index": -1}
	set_process(true)
	graph.queue_redraw()


func _update_palette_insertion(point: Vector2) -> void:
	if palette_move.is_empty(): return
	var insertion := _block_insertion((point + graph.scroll_offset) / graph.zoom, palette_move.route)
	palette_move.hover = insertion.get("source")
	palette_move.index = insertion.get("index", -1)
	_dock_blocks()
	graph.queue_redraw()


func _clear_palette_move() -> void:
	if palette_move.is_empty(): return
	palette_move = {}
	if block_move.is_empty(): set_process(false)
	_dock_blocks()
	if is_instance_valid(graph): graph.queue_redraw()


func _begin_move() -> void:
	dock_cancelled = false
	if is_instance_valid(state_machine):
		moving_machine = state_machine
		move_before = actions.capture_positions(state_machine)
		move_before.positions = _positions_from_graph()
		for routing in move_before.random_positions:
			if random_blocks.has(routing):
				move_before.random_positions[routing].value = random_blocks[routing].position_offset
		dock_drag.clear()
		for block in transition_blocks.values():
			if block.selected: dock_drag[block.transition] = block.position_offset


func _end_move() -> void:
	var moved := dock_drag.duplicate()
	dock_drag.clear()
	for route in moved:
		var block: GraphNode = transition_blocks.get(route)
		if not is_instance_valid(block) or block.position_offset == moved[route]: continue
		var source := _dock_at(block.position_offset)
		if source == null: source = _dock_at(block.position_offset + Vector2(block.size.x * 0.5, 0))
		if source != null and not dock_cancelled:
			if block.draft: _attach_draft(block, source)
			elif route != fallback_entry: actions.reconnect_transition(state_machine, route, _source_mode(source), source.state.name if source.state != null else &"", route.target_key(), &"from")
	_dock_blocks()
	if moved.is_empty() and not move_before.is_empty() and is_instance_valid(moving_machine) and moving_machine == state_machine:
		actions.save_positions(state_machine, move_before, _positions_from_graph(), "Move States")
	move_before = {}


func _on_node_position_changed(node: GraphNode, revision: int) -> void:
	if is_loading or revision != graph_revision or not is_instance_valid(node) or not is_instance_valid(state_machine):
		return
	if docking: return
	if node is RANDOM_BLOCK:
		node.routing.set_meta(RANDOM_BLOCK.POSITION_META, node.position_offset)
		if random_drafts.has(node.routing): random_drafts[node.routing].position = node.position_offset
		return
	if node is BLOCK:
		if node.draft and node.dock_source.is_empty() and drafts.has(node.transition): drafts[node.transition].position = node.position_offset
		return
	_dock_blocks()

	if move_before.is_empty():
		state_machine.graph_positions[_position_key(node)] = node.position_offset
		if is_instance_valid(editor_interface):
			editor_interface.mark_scene_as_unsaved()


func _on_arrange_pressed() -> void:
	if not is_instance_valid(state_machine):
		return
	if refresh_pending: _deferred_refresh()
	var machine := state_machine
	var revision := graph_revision
	var before: Dictionary = actions.capture_positions(machine)
	before.positions = _positions_from_graph()
	for routing in before.random_positions:
		if random_blocks.has(routing): before.random_positions[routing].value = random_blocks[routing].position_offset
	move_before = before
	is_loading = true
	preload("res://addons/state_machine/editor/graph_layout.gd").arrange(self)
	is_loading = false
	for routing in random_blocks: routing.set_meta(RANDOM_BLOCK.POSITION_META, random_blocks[routing].position_offset)
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(machine) or machine != state_machine or revision != graph_revision:
		move_before = {}
		return
	var pairs := {}
	for route in transition_blocks:
		var block: GraphNode = transition_blocks[route]
		if block.draft: continue
		var from := _route_source(route)
		var to: StringName = _route_target(route)
		var key := str([from, to])
		var offset: int = pairs.get(key, 0)
		pairs[key] = offset + 1
		block.position_offset = _block_default_position(from, to, offset)
	_dock_blocks()
	var positions := _positions_from_graph()
	move_before = {}
	actions.save_positions(machine, before, positions, "Auto Layout States")


func _selected_state() -> State:
	if not is_instance_valid(graph):
		return null
	var selected: State
	for child in graph.get_children():
		if child is GraphNode and child.selected:
			if selected:
				return null
			selected = child.state
	return selected if is_instance_valid(selected) else null


func _sync_graph_selection(state: State, route: StateTransition = null) -> void:
	selected_connection_edge.clear()
	syncing_selection = true
	for child in graph.get_children():
		if child is GraphNode:
			child.selected = (is_instance_valid(state) and child.state == state) or (child is BLOCK and child.transition == route)
	syncing_selection = false
	_apply_state_appearance()

func select_graph_state(state: State) -> void:
	_reveal_hidden_state(state)
	selected_random = null
	_clear_transition_selection()
	selected_state = state if is_instance_valid(state) else null
	selected_boundary = &""
	selection_mode = SelectionMode.STATE if selected_state != null else SelectionMode.NONE
	_sync_graph_selection(selected_state)
	_render_selection()
	if workspace_active: show_authoring_dock()


func _graph_selected(node: Node) -> void:
	if syncing_selection or is_loading or not is_instance_valid(editor_interface) or not node is GraphNode:
		return
	if node is RANDOM_BLOCK:
		_select_random(node.routing)
		return
	if node is BLOCK:
		_select_transition(node.transition)
		return
	if node == any_state_node:
		_select_boundary(SelectionMode.ANY_STATE)
		return
	if node == entry_node:
		_select_boundary(SelectionMode.ENTRY)
		return
	if node == exit_node:
		_select_boundary(SelectionMode.EXIT)
		return
	var selection := editor_interface.get_selection()
	syncing_selection = true
	selection.clear()
	selection.add_node(node.state)
	editor_interface.inspect_object(node.state)
	syncing_selection = false
	select_graph_state(node.state)
	graph.grab_focus()


func _graph_popup(at_position: Vector2) -> void:
	if not is_instance_valid(state_machine):
		return
	color_target = null
	for node in [entry_node, exit_node]:
		if is_instance_valid(node) and Rect2(node.position, node.size * graph.zoom).has_point(graph.get_local_mouse_position()):
			_boundary_popup(node)
			return
	context_machine = state_machine
	create_position = (at_position + graph.scroll_offset) / graph.zoom
	create_insert_index = _insertion_index(state_machine, _selected_state())
	# GraphEdit can also request a popup over a node.
	for child in graph.get_children():
		if child is GraphNode and child.get_global_rect().has_point(graph.get_global_mouse_position()):
			if child == any_state_node:
				_select_boundary(SelectionMode.ANY_STATE)
				return
			if child == entry_node or child == exit_node:
				_select_boundary(SelectionMode.ENTRY if child == entry_node else SelectionMode.EXIT)
				return
			_state_popup(child.state)
			return
	graph_menu.position = Vector2i(graph.get_global_mouse_position())
	graph_menu.set_item_disabled(graph_menu.get_item_index(6), not clipboard.refusal(state_machine, selected_state).is_empty())
	graph_menu.popup()


func _graph_menu_action(id: int) -> void:
	if not _valid_context():
		return
	match id:
		0: dialogs.show_create(actions.unique_name(state_machine, "NewState"))
		1: _on_arrange_pressed()
		2: _frame(false)
		3: refresh()
		4:
			var owner: Node = editor_interface.get_edited_scene_root()
			_select_created_state(actions.create_hierarchy(state_machine, actions.unique_name(state_machine, "HierarchyState"), create_position, owner, create_insert_index))
		5:
			any_source_requested = true
			refresh()
		6: _paste_clipboard()


func _state_popup(state: State) -> void:
	color_target = null
	color_boundary = ""
	if not is_instance_valid(state) or not is_instance_valid(state_machine):
		return
	context_state = state
	context_machine = state_machine
	select_graph_state(state)
	graph.grab_focus()
	state_menu.set_item_disabled(state_menu.get_item_index(1), state_machine.initial_state == state)
	state_menu.set_item_text(state_menu.get_item_index(14), "Show State" if is_graph_state_hidden(state) else "Hide State")
	state_menu.set_item_text(state_menu.get_item_index(2), "Open Script" if SCRIPT_UTILS.has_gameplay_script(state) else "Create Script")
	state_menu.set_item_disabled(state_menu.get_item_index(4), not state.has_meta(&"fsm_editor_color"))
	var nested: FiniteStateMachine = actions.nested_machine(state)
	state_menu.set_item_disabled(state_menu.get_item_index(7), nested != null or state.has_method("get_nested_machine"))
	state_menu.set_item_disabled(state_menu.get_item_index(8), nested == null)
	state_menu.set_item_disabled(state_menu.get_item_index(9), nested == null or state.has_method("get_nested_machine"))
	for id in [10, 11]:
		state_menu.set_item_disabled(state_menu.get_item_index(id), not state is HierarchyState)
		state_menu.set_item_checked(state_menu.get_item_index(id), state is HierarchyState and state.entry_mode == id - 10)
	state_menu.position = Vector2i(graph.get_global_mouse_position())
	state_menu.set_item_disabled(state_menu.get_item_index(13), not clipboard.refusal(state_machine, selected_state).is_empty())
	state_menu.popup()


func _valid_context(needs_state := false) -> bool:
	return is_instance_valid(state_machine) and context_machine == state_machine and (not needs_state or state_machine.owns_state(context_state))


func _state_menu_action(id: int) -> void:
	if not _valid_context(true):
		return
	match id:
		0: _begin_rename(context_state)
		1: actions.set_initial(state_machine, context_state)
		2: _open_script(context_state)
		3: dialogs.show_color(context_state.get_meta(&"fsm_editor_color", get_theme_color("font_color", "Label")))
		4: actions.set_color(state_machine, context_state, Color.WHITE, true)
		5: _duplicate(context_state)
		6: _request_delete(context_state)
		12: clipboard.copy_state(state_machine, context_state)
		13: _paste_clipboard()
		14: actions.set_graph_visible(state_machine, context_state, is_graph_state_hidden(context_state))
		7: actions.make_composite(state_machine, context_state)
		8: _open_nested(context_state)
		9:
			var nested: FiniteStateMachine = actions.nested_machine(context_state)
			if nested != null:
				if nested.get_child_count() > 0 or not nested.transitions.is_empty():
					nested_delete_dialog.popup_centered()
				else:
					actions.remove_nested(state_machine, context_state)
		10, 11:
			if not context_state is HierarchyState: return
			var undo: EditorUndoRedoManager = actions.undo_manager
			if undo != null:
				undo.create_action("Set Hierarchy Entry Mode", UndoRedo.MERGE_DISABLE, context_state)
				undo.add_do_property(context_state, "entry_mode", id - 10)
				undo.add_undo_property(context_state, "entry_mode", context_state.entry_mode)
				undo.commit_action()
			else: context_state.entry_mode = id - 10


func _open_nested(state: State) -> void:
	var nested: FiniteStateMachine = actions.nested_machine(state)
	if nested != null:
		_navigate_machine(nested)


func _navigate_machine(machine: FiniteStateMachine) -> void:
	if not is_instance_valid(machine) or not machine.is_inside_tree():
		return
	if is_instance_valid(editor_interface):
		syncing_selection = true
		var selection := editor_interface.get_selection()
		selection.clear()
		selection.add_node(machine.get_state_container())
		syncing_selection = false
		editor_interface.inspect_object(machine.get_state_container())
		navigation_selection_changed.emit(machine.get_state_container())
	set_state_machine(machine)
	select_graph_state(machine.get_state_container() as State)


func _refresh_breadcrumbs() -> void:
	for child in breadcrumbs.get_children():
		breadcrumbs.remove_child(child)
		child.queue_free()
	var chain: Array[FiniteStateMachine] = []
	var cursor := state_machine
	var visited := {}
	while is_instance_valid(cursor) and not visited.has(cursor):
		visited[cursor] = true
		chain.push_front(cursor)
		cursor = cursor.get_parent_fsm()
	breadcrumbs.visible = chain.size() > 1
	if chain.size() <= 1: return
	for index in chain.size():
		if index > 0:
			var separator := Label.new()
			separator.text = ">"
			breadcrumbs.add_child(separator)
		var button := Button.new()
		button.flat = true
		var state := chain[index].get_parent() as State
		button.text = String(state.name) if state != null else String(chain[index].name)
		button.tooltip_text = String(chain[index].get_path())
		button.custom_minimum_size.x = clampf(button.get_minimum_size().x, 60.0, 220.0)
		button.clip_text = true
		button.disabled = chain[index] == state_machine
		button.pressed.connect(_navigate_machine.bind(chain[index]))
		breadcrumbs.add_child(button)


func _create_state(requested: String, with_script: bool) -> void:
	if not _valid_context() or not actions.valid_name(state_machine, requested):
		return
	var owner: Node = state_machine.get_state_container().owner
	if is_instance_valid(editor_interface):
		owner = editor_interface.get_edited_scene_root()
	if owner == null and state_machine.scene_file_path != "":
		owner = state_machine
	if not is_instance_valid(owner):
		dialogs.show_error("Save or open an edited scene before creating States.")
		return
	var script: Script
	var choose_location: bool = with_script and dialogs.script_directory(owner, state_machine).is_empty()
	if with_script and not choose_location:
		script = dialogs.create_script(requested, owner, state_machine)
		if not script:
			return
		if is_instance_valid(editor_interface):
			_queue_script_scan()
	var state: State = actions.create_state(state_machine, requested, create_position, owner, script, create_insert_index)
	_select_created_state(state)
	if choose_location and is_instance_valid(state):
		_request_unique_script(state)


func _rename_requested(state: State, requested: String) -> void:
	if is_instance_valid(state_machine) and state_machine.owns_state(state):
		var position: Vector2 = _positions_from_graph().get(String(state.name), Vector2.ZERO)
		if not state_machine.graph_positions.has(String(state.name)):
			state_machine.graph_positions[String(state.name)] = position
		actions.rename_state(state_machine, state, requested)


func _begin_rename(state: State) -> void:
	for child in graph.get_children():
		if child is GraphNode and child.state == state:
			child.begin_rename()
			return


func _open_script(state: State) -> void:
	if not is_instance_valid(state):
		return
	if not SCRIPT_UTILS.has_gameplay_script(state):
		_request_unique_script(state)
		return
	if _script_users(state.get_script()) > 1:
		var scene: Node = state.owner
		if is_instance_valid(editor_interface):
			scene = editor_interface.get_edited_scene_root()
		var script: Script = dialogs.copy_state_script(state.get_script(), String(state.name), scene)
		if script == null:
			return
		actions.attach_script(state_machine, state, script)
		_queue_script_scan()
	if is_instance_valid(editor_interface):
		var script: Script = state.get_script()
		if script:
			editor_interface.edit_script(script)
			editor_interface.set_main_screen_editor("Script")


func _script_users(script: Script) -> int:
	var root: Node = state_machine
	if is_instance_valid(editor_interface):
		root = editor_interface.get_edited_scene_root()
	return _count_script_users(root, script)


func _count_script_users(node: Node, script: Script) -> int:
	if not is_instance_valid(node):
		return 0
	var count := 0
	if node is State:
		var attached: Script = node.get_script()
		if attached == script or (attached != null and not script.resource_path.is_empty() and attached.resource_path == script.resource_path):
			count += 1
	for child in node.get_children():
		count += _count_script_users(child, script)
	return count


func _request_unique_script(state: State) -> void:
	event_script_pending = false
	if not is_instance_valid(state_machine) or not state_machine.owns_state(state):
		return
	pending_script_state = state
	pending_script_machine = state_machine
	var scene: Node = state_machine.get_state_container().owner
	if is_instance_valid(editor_interface):
		scene = editor_interface.get_edited_scene_root()
	elif scene == null and not state_machine.scene_file_path.is_empty():
		scene = state_machine
	dialogs.request_script(String(state.name), scene, state_machine, "HierarchyState" if state.has_method("get_nested_machine") else "State")


func _attach_created_script(script: Script) -> void:
	if not is_instance_valid(pending_script_machine) or not pending_script_machine.owns_state(pending_script_state):
		return
	if event_script_pending and not _event_context_valid():
		event_script_pending = false
		dialogs.show_error("The scene or Event changed. The new script was not attached.")
		return
	actions.attach_script(pending_script_machine, pending_script_state, script)
	if event_script_pending and pending_script_state == event_state:
		event_script_pending = false
		_create_event_method()
	if is_instance_valid(editor_interface):
		_queue_script_scan()
	pending_script_state = null
	pending_script_machine = null


func _event_script_requested(transition: StateTransition, emitter: State, create: bool) -> void:
	if not is_instance_valid(emitter) or not is_instance_valid(state_machine) or not transition in state_machine.transitions or transition.event_name.is_empty():
		dialogs.show_error("Choose an Event transition with a non-empty Event Name.")
		return
	event_target = state_machine
	event_transition = transition
	event_state = emitter
	event_name_pending = transition.event_name
	if not SCRIPT_UTILS.has_gameplay_script(emitter):
		if create:
			event_script_dialog.popup_centered()
		else:
			dialogs.show_error("This State has no gameplay script. Choose Create Event Method to create one.")
		return
	if create:
		_create_event_method()
	else:
		var location: Dictionary = EVENT_AUTHORING.location(emitter.get_script(), EVENT_AUTHORING.method_name(transition.event_name))
		editor_interface.edit_script(location.get("script", emitter.get_script()), location.get("line", -1))
		editor_interface.set_main_screen_editor("Script")


func _event_context_valid() -> bool:
	var root := editor_interface.get_edited_scene_root() if is_instance_valid(editor_interface) else null
	return is_instance_valid(root) and is_instance_valid(event_target) and is_instance_valid(event_state) and root.is_ancestor_of(event_state) and event_transition != null and event_transition in event_target.transitions and event_transition.event_name == event_name_pending and EVENT_AUTHORING.distance(event_state, event_target) >= 0


func _confirm_event_script() -> void:
	if not _event_context_valid():
		dialogs.show_error("The Event or emitter changed. Select it again before creating the method.")
		return
	if SCRIPT_UTILS.has_gameplay_script(event_state):
		_create_event_method()
		return
	pending_script_state = event_state
	pending_script_machine = FiniteStateMachine.machine_for_state(event_state)
	event_script_pending = true
	dialogs.request_script(String(event_state.name), editor_interface.get_edited_scene_root(), pending_script_machine, "HierarchyState" if event_state.has_method("get_nested_machine") else "State")


func _create_event_method() -> void:
	if not _event_context_valid():
		dialogs.show_error("The Event or emitter changed. Select it again.")
		return
	if _script_users(event_state.get_script()) > 1:
		dialogs.show_error("This gameplay script is shared. Open the State's script from its graph first to create an independent copy.")
		return
	var emitter := event_state
	var target := event_target
	var event := event_name_pending
	editor_interface.edit_script(emitter.get_script())
	editor_interface.set_main_screen_editor("Script")
	await get_tree().process_frame
	await get_tree().process_frame
	if not _event_context_valid() or event_state != emitter or event_target != target or event_name_pending != event:
		return
	var result: Dictionary = EVENT_AUTHORING.append_method(event_state, event_target, event_name_pending, editor_interface)
	if not result.ok:
		dialogs.show_error(result.message)
		return
	editor_interface.edit_script(result.script, result.line)
	editor_interface.set_main_screen_editor("Script")
	transition_editor.refresh()
	_queue_script_scan()


func _queue_script_scan() -> void:
	if not script_scan_pending:
		script_scan_pending = true
		_scan_scripts.call_deferred()


func _scan_scripts() -> void:
	script_scan_pending = false
	if is_inside_tree() and is_instance_valid(editor_interface):
		editor_interface.get_resource_filesystem().scan()


func _duplicate(state: State) -> void:
	if is_instance_valid(state_machine) and is_instance_valid(state):
		var position: Vector2 = _positions_from_graph().get(String(state.name), Vector2.ZERO)
		select_graph_state(actions.duplicate_state(state_machine, state, position))
		_queue_script_scan()


func _cleanup_orphan_transitions() -> void:
	if is_instance_valid(state_machine):
		actions.cleanup_orphan_transitions(state_machine)


func _request_delete(state: State) -> void:
	if not is_instance_valid(state) or not is_instance_valid(state_machine):
		return
	context_state = state
	context_machine = state_machine
	var count: int = actions.connected_count(state_machine, state)
	if count > 0:
		dialogs.show_delete(String(state.name), count)
	elif state.has_method("get_nested_machine") and state.get_child_count() > 0:
		dialogs.delete_dialog.dialog_text = "Deleting HierarchyState '%s' also removes its nested States, transitions and Watches." % state.name
		dialogs.delete_dialog.popup_centered()
	else:
		_delete_confirmed()


func _delete_confirmed() -> void:
	if _valid_context(true):
		actions.delete_state(state_machine, context_state)
		if is_instance_valid(editor_interface):
			syncing_selection = true
			var selection := editor_interface.get_selection()
			selection.clear()
			selection.add_node(state_machine)
			editor_interface.inspect_object(state_machine)
			syncing_selection = false


func _color_confirmed(color: Color, reset: bool) -> void:
	if color_target != null:
		if is_instance_valid(state_machine):
			if color_boundary != "": actions.set_boundary_color(state_machine, color_boundary == "entry", null if reset else color)
			elif color_target is StateTransition: _edit_transition(color_target, &"editor_color", null if reset else color)
		color_target = null
		color_boundary = ""
		return
	if _valid_context(true):
		actions.set_color(state_machine, context_state, color, reset)


func _delete_requested(_names: Array[StringName]) -> void:
	var hierarchy := _hierarchy_for_edge(selected_connection_edge)
	if hierarchy != null:
		selected_connection_edge.clear()
		actions.set_hierarchy_exit_target(state_machine, hierarchy, &"")
		return
	if _names.is_empty():
		if _is_entry_edge(selected_connection_edge) and is_instance_valid(state_machine):
			actions.set_initial(state_machine, null)
			return
		selected_connection_edge.clear()
		return
	if _graph_has_focus():
		if not selected_connection_edge.is_empty():
			var edge := selected_connection_edge.duplicate()
			selected_connection_edge.clear()
			if graph.is_node_connected(edge.from_node, edge.from_port, edge.to_node, edge.to_port):
				if not entry_connection.is_empty() and _connection_key(edge.from_node, edge.from_port, edge.to_node, edge.to_port) == _connection_key(entry_connection.from_node, entry_connection.from_port, entry_connection.to_node, entry_connection.to_port):
					actions.set_initial(state_machine, null)
					return
				var branch: Dictionary = random_branch_connections.get(_connection_key(edge.from_node, edge.from_port, edge.to_node, edge.to_port), {})
				if not branch.is_empty(): _random_edited(random_blocks[branch.routing], "target", edge.from_port, &"")
				else: _disconnect_transition_target(transition_for_connection(edge))
			return
		for name in _names:
			var node := graph.get_node_or_null(NodePath(name))
			if node is RANDOM_BLOCK:
				selected_random = null
				if node.transition != null:
					var routing: StateRandomRouting = node.routing
					actions.set_random_routing(state_machine, node.transition, null)
					random_drafts.erase(routing)
					refresh()
				else: _session_draft(node.routing, null, true)
				return
			if node is BLOCK:
				if node.draft: _session_draft(node.transition, null, false)
				else: _delete_transition(node.transition)
				return
		var state := _selected_state()
		if state:
			_request_delete(state)


func _duplicate_requested() -> void:
	if _graph_has_focus():
		var state := _selected_state()
		if state:
			_duplicate(state)


func _graph_has_focus() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus == graph

func _copy_selection() -> bool:
	if not is_instance_valid(state_machine): return false
	if selected_transition != null and selected_transition in state_machine.transitions: return clipboard.copy_transition(state_machine, selected_transition)
	if is_instance_valid(selected_state) and state_machine.owns_state(selected_state): return clipboard.copy_state(state_machine, selected_state)
	warning_summary.text = "Select a State or persistent Transition Block to copy."
	return false

func _paste_clipboard() -> Object:
	var reason := clipboard.refusal(state_machine, selected_state)
	if not reason.is_empty(): warning_summary.text = reason; return null
	var destination_position: Variant = null
	if not clipboard.same_scope(state_machine):
		var point := graph.get_local_mouse_position()
		if not Rect2(Vector2.ZERO, graph.size).has_point(point): point = graph.size / 2
		destination_position = (graph.scroll_offset + point) / graph.zoom
	var result := actions.paste_clipboard(state_machine, clipboard, editor_interface.get_edited_scene_root(), selected_state, destination_position)
	if result is State: _select_created_state(result)
	elif result is StateTransition: _select_transition(result)
	if result != null:
		graph.grab_focus()
		editor_interface.mark_scene_as_unsaved()
	return result


func _shortcut_input(event: InputEvent) -> void:
	if _graph_has_focus() and event is InputEventKey and event.pressed and not event.echo and event.is_command_or_control_pressed() and not event.alt_pressed and not event.shift_pressed:
		if event.keycode == KEY_C: _copy_selection(); get_viewport().set_input_as_handled(); return
		if event.keycode == KEY_V: _paste_clipboard(); get_viewport().set_input_as_handled(); return
	if validation_search != null and validation_search.handle_key(event):
		get_viewport().set_input_as_handled()
		return
	if not _graph_has_focus() or not event is InputEventKey or not event.pressed or event.echo or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	var state := _selected_state()
	if event.keycode == KEY_F2 and state:
		_begin_rename(state)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F:
		_frame(true)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER and state != null and FiniteStateMachine.nested_machine_for_state(state) != null:
		_open_nested(state)
		get_viewport().set_input_as_handled()


func _frame(selected_only: bool) -> void:
	var bounds := Rect2()
	var found := false
	for child in graph.get_children():
		if child is GraphNode and child.visible and (not selected_only or child.selected):
			var rect := Rect2(child.position_offset, child.size)
			bounds = bounds.merge(rect) if found else rect
			found = true
	if found and not selected_only:
		for edge in graph.get_connection_list():
			for point in _edge_line(edge): bounds = bounds.expand((point + graph.scroll_offset) / graph.zoom)
	if found:
		if not selected_only:
			var available := graph.size - Vector2(80, 80)
			var fit := maxf(0.01, minf(available.x / maxf(bounds.size.x, 1), available.y / maxf(bounds.size.y, 1)))
			graph.zoom_min = minf(graph.zoom_min, fit)
			graph.zoom = minf(fit, graph.zoom_max)
		graph.scroll_offset = bounds.get_center() * graph.zoom - graph.size / 2


func _graph_connection_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered := _unique_connection_at(event.position)
		if hovered != hovered_connection_edge:
			hovered_connection_edge = hovered
			graph.queue_redraw()
		return
	if not event is InputEventMouseButton or not event.pressed or event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	if not is_instance_valid(state_machine) or not graph.has_method("get_closest_connection_at_point"):
		return
	# A curve can pass behind a card in dense graphs. Card interaction takes
	# precedence so clicking its title never consumes the native move gesture.
	for node in graph.get_children():
		if not node is GraphNode or not node.visible: continue
		if Rect2(node.position, node.size * graph.zoom).has_point(event.position): return
		# Curves converge here. A shared socket is never an exact curve selector.
		for port in node.get_input_port_count():
			if event.position.distance_to(node.position + node.get_input_port_position(port) * graph.zoom) <= 18: return
		for port in node.get_output_port_count():
			if event.position.distance_to(node.position + node.get_output_port_position(port) * graph.zoom) <= 18: return
	var connection := _unique_connection_at(event.position)
	if not connection.is_empty():
		show_authoring_dock()
		select_connection(connection)
		if event.button_index == MOUSE_BUTTON_LEFT:
			curve_drag = {"edge": connection.duplicate(), "route": transition_for_connection(connection), "origin": event.position, "mouse": event.position, "active": false, "machine": state_machine}
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var hierarchy := _hierarchy_for_edge(connection)
			if hierarchy != null:
				hierarchy_exit_context = hierarchy
				hierarchy_exit_menu.position = Vector2i(graph.get_global_mouse_position())
				hierarchy_exit_menu.popup()
				graph.accept_event()
				return
			var branch: Dictionary = random_branch_connections.get(_connection_key(connection.from_node, connection.from_port, connection.to_node, connection.to_port), {})
			if not branch.is_empty():
				graph.accept_event()
				return
			if transition_for_connection(connection) == null:
				graph.accept_event()
				return
			connection_context = transition_editor.selected
			connection_context_edge = connection.duplicate()
			connection_menu.position = Vector2i(graph.get_global_mouse_position())
			connection_menu.popup()
		graph.accept_event()

func _edge_line(edge: Dictionary) -> PackedVector2Array:
	if not _edge_has_visible_ports(edge): return PackedVector2Array()
	var source := graph.get_node_or_null(NodePath(edge.from_node)) as GraphNode
	var target := graph.get_node_or_null(NodePath(edge.to_node)) as GraphNode
	if source == null or target == null or not source.visible or not target.visible: return PackedVector2Array()
	return graph.get_connection_line(source.position + source.get_output_port_position(edge.from_port) * graph.zoom, target.position + target.get_input_port_position(edge.to_port) * graph.zoom)

func _automatic_end_color(edge: Dictionary) -> Color:
	var target := graph.get_node_or_null(NodePath(edge.get("to_node", ""))) as GraphNode
	var port := int(edge.get("to_port", 0))
	if target == null or port < 0: return Color.WHITE
	if target == exit_node:
		return APPEARANCE.resolve_boundary_color(state_machine, false, _editor_settings() if is_instance_valid(editor_interface) else null)
	if target == entry_node:
		return APPEARANCE.resolve_boundary_color(state_machine, true, _editor_settings() if is_instance_valid(editor_interface) else null)
	var target_state := target.get("state") as State
	if is_instance_valid(target_state):
		var preview: Variant = target.get("preview_color")
		return _resolved_state_color(target_state, preview)
	if port >= target.get_input_port_count(): return Color.WHITE
	return target.get_slot_color_left(port)

func _edge_selected(edge: Dictionary) -> bool:
	var key := _connection_key(edge.from_node, edge.from_port, edge.to_node, edge.to_port)
	if not selected_connection_edge.is_empty() and key == _connection_key(selected_connection_edge.from_node, selected_connection_edge.from_port, selected_connection_edge.to_node, selected_connection_edge.to_port): return true
	if transition_for_connection(edge) == selected_transition and selected_transition != null: return true
	var branch: Dictionary = random_branch_connections.get(key, {})
	return branch.get("branch") == selected_random_branch and selected_random_branch != null

func _edge_hovered(edge: Dictionary) -> bool:
	if hovered_connection_edge.is_empty(): return false
	return _connection_key(edge.from_node, edge.from_port, edge.to_node, edge.to_port) == _connection_key(hovered_connection_edge.from_node, hovered_connection_edge.from_port, hovered_connection_edge.to_node, hovered_connection_edge.to_port)

func _draw_connection_gradient(edge: Dictionary, start: Color, finish: Color) -> void:
	var layers := _connection_draw_layers(edge, start, finish)
	if trace_connection_sync and not layers.is_empty():
		connection_draw_records[_connection_key(edge.from_node, edge.from_port, edge.to_node, edge.to_port)] = layers[-1]
	for layer in layers:
		graph.draw_polyline_colors(layer.points, layer.colors, layer.width, true)

func _connection_draw_layers(edge: Dictionary, start: Color, finish: Color) -> Array[Dictionary]:
	var layers: Array[Dictionary] = []
	var line := _edge_line(edge)
	if line.size() < 2: return layers
	if not debug_edge.is_empty() and debug_outline_amount > 0 and _connection_key(edge.from_node, edge.from_port, edge.to_node, edge.to_port) == _connection_key(debug_edge.from_node, debug_edge.from_port, debug_edge.to_node, debug_edge.to_port):
		var flash := APPEARANCE.get_color(_editor_settings(), "last_transition_accent") if is_instance_valid(editor_interface) else Color("79a9e5")
		flash.a = 0.5 * debug_outline_amount
		layers.append({"points": line, "colors": _connection_gradient_point_colors(line, flash, flash), "width": 10.0})
	if _edge_selected(edge) or _edge_hovered(edge):
		var selected_glow := APPEARANCE.get_color(_editor_settings(), "selected_accent") if is_instance_valid(editor_interface) else Color("79a9e5")
		var glow := selected_glow if _edge_selected(edge) else start.lightened(0.25)
		glow.a = 0.35 if _edge_selected(edge) else 0.2
		layers.append({"points": line, "colors": _connection_gradient_point_colors(line, glow, glow), "width": 8.0 if _edge_selected(edge) else 6.0})
	var total := 0.0
	for index in range(line.size() - 1): total += line[index].distance_to(line[index + 1])
	if total <= 0.001: return []
	var width := 3.0 if _edge_selected(edge) else (2.75 if _edge_hovered(edge) else 2.4)
	# Always last: selection, hover and runtime pulses only decorate its outline.
	layers.append({"points": line, "colors": _connection_gradient_point_colors(line, start, finish), "width": width})
	return layers

func _connection_gradient_point_colors(line: PackedVector2Array, start: Color, finish: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	if line.is_empty(): return colors
	var distances := PackedFloat32Array()
	distances.resize(line.size())
	var total := 0.0
	for index in range(1, line.size()):
		total += line[index - 1].distance_to(line[index])
		distances[index] = total
	for index in line.size():
		var t := distances[index] / total if total > 0.001 else (float(index) / float(line.size() - 1) if line.size() > 1 else 0.0)
		colors.append(start.lerp(finish, t))
	if not colors.is_empty():
		colors[0] = start
		if colors.size() > 1: colors[colors.size() - 1] = finish
	return colors

func _connection_gradient_endpoints(resource: Resource, edge: Dictionary) -> PackedColorArray:
	if resource == null: return PackedColorArray()
	var automatic := _automatic_end_color(edge)
	return PackedColorArray([TRANSITION_COLORS.source_color(resource, state_machine, _editor_settings() if is_instance_valid(editor_interface) else null), TRANSITION_COLORS.end_color(resource, automatic)])

func _draw_connection_gradients() -> void:
	if not is_instance_valid(graph): return
	if trace_connection_sync: connection_draw_records.clear()
	for hierarchy in hierarchy_exit_connections:
		var edge: Dictionary = hierarchy_exit_connections[hierarchy]
		if not _edge_has_visible_ports(edge): continue
		var source := graph.get_node_or_null(NodePath(edge.from_node)) as GraphNode
		if source != null: _draw_connection_gradient(edge, source.get_output_port_color(0), _automatic_end_color(edge))
	for route in transition_connections:
		if route == fallback_entry: continue
		var edge: Dictionary = transition_connections[route]
		if edge.is_empty() or not _edge_has_visible_ports(edge): continue
		var colors := _connection_gradient_endpoints(route, edge)
		if colors.size() == 2: _draw_connection_gradient(edge, colors[0], colors[1])
	for edge in random_branch_connections.values():
		if edge.is_empty() or not _edge_has_visible_ports(edge): continue
		var colors := _connection_gradient_endpoints(edge.branch, edge)
		if colors.size() == 2: _draw_connection_gradient(edge, colors[0], colors[1])
	if not entry_connection.is_empty():
		var colors := _connection_gradient_endpoints(fallback_entry, entry_connection)
		if colors.size() == 2: _draw_connection_gradient(entry_connection, colors[0], colors[1])
	_trace_connection_sync("draw")

func _unique_connection_at(point: Vector2) -> Dictionary:
	var chosen := {}
	for edge in graph.get_connections_intersecting_with_rect(Rect2(point - Vector2(6, 6), Vector2(12, 12))):
		var line := _edge_line(edge)
		for i in range(line.size() - 1):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, line[i], line[i + 1])) <= 6:
				if not chosen.is_empty(): return {} # Crossing/converged curves are ambiguous.
				chosen = edge
				break
	return chosen

func _curve_drop_target(point: Vector2) -> Dictionary:
	var chosen := {}
	for node in graph.get_children():
		if not node is GraphNode or not node.visible: continue
		for port in node.get_input_port_count():
			if point.distance_to(node.position + node.get_input_port_position(port) * graph.zoom) <= 22:
				if not chosen.is_empty(): return {}
				chosen = {"node": node.name, "port": port}
	return chosen

func _draw_curve_drag() -> void:
	if curve_drag.is_empty() or not curve_drag.active: return
	var source := graph.get_node_or_null(NodePath(curve_drag.edge.from_node)) as GraphNode
	if source == null: return
	var start := source.position + source.get_output_port_position(curve_drag.edge.from_port) * graph.zoom
	var line := graph.get_connection_line(start, curve_drag.mouse)
	if source is NODE_SCRIPT and source.state is HierarchyState:
		var target := _curve_drop_target(curve_drag.mouse)
		var color := source.get_output_port_color(0)
		var finish := _automatic_end_color({"to_node": target.node, "to_port": target.port}) if not target.is_empty() else color
		graph.draw_polyline_colors(line, _connection_gradient_point_colors(line, color, finish), 3, true)
		return
	var route: Resource = curve_drag.route
	var branch_info: Dictionary = random_branch_connections.get(_connection_key(curve_drag.edge.from_node, curve_drag.edge.from_port, curve_drag.edge.to_node, curve_drag.edge.to_port), {})
	if not branch_info.is_empty(): route = branch_info.get("branch")
	if route == null: return
	var preview_edge: Dictionary = curve_drag.edge
	var drop := _curve_drop_target(curve_drag.mouse)
	if not drop.is_empty():
		preview_edge = {"from_node": curve_drag.edge.from_node, "from_port": curve_drag.edge.from_port, "to_node": drop.node, "to_port": drop.port}
	var endpoints := _connection_gradient_endpoints(route, preview_edge)
	if endpoints.size() != 2: return
	graph.draw_polyline_colors(line, _connection_gradient_point_colors(line, endpoints[0], endpoints[1]), 3, true)


func _edit_transition(transition: StateTransition, property: StringName, value: Variant) -> void:
	if property == &"editor_end_color" and TRANSITION_COLORS.uses_exit_color(transition): return
	if drafts.has(transition):
		if property == &"to_state":
			var target := graph.get_node_or_null(NodePath(_graph_name(value))) as GraphNode
			if target != null: _connect_transition_block(transition_blocks[transition], 0, target, 0)
			return
		if property == &"from_state":
			var source := graph.get_node_or_null(NodePath(_graph_name(value))) as GraphNode
			if _block_move_valid_source(transition, source): _attach_draft(transition_blocks[transition], source)
			return
		if property == &"cooldown" and (not is_finite(float(value)) or float(value) < 0): return
		var before: Variant = TRANSITION_COLORS.color(transition) if property == &"editor_color" else (TRANSITION_COLORS.end_color(transition, _automatic_end_color(transition_connections.get(transition, {}))) if property == &"editor_end_color" else transition.get(property))
		if actions.undo_manager == null: _apply_draft_property(transition, property, value)
		else:
			actions.undo_manager.create_action("Edit Transition Draft", UndoRedo.MERGE_DISABLE, state_machine.get_state_container())
			actions.undo_manager.add_do_method(self, "_apply_draft_property", transition, property, value)
			actions.undo_manager.add_undo_method(self, "_apply_draft_property", transition, property, before)
			actions.undo_manager.commit_action()
		return
	if transition == fallback_entry:
		if property == &"editor_color": actions.edit_transition(state_machine, transition, property, value)
		if property == &"to_state": actions.set_initial(state_machine, graph.get_node(NodePath(_graph_name(value))).state)
		return
	if is_instance_valid(state_machine):
		actions.edit_transition(state_machine, transition, property, value)


func _apply_draft_property(route: StateTransition, property: StringName, value: Variant) -> void:
	if property == &"editor_color":
		if value == null: route.remove_meta(TRANSITION_COLORS.META)
		else: route.set_meta(TRANSITION_COLORS.META, value)
	elif property == &"editor_end_color":
		if value == null: route.remove_meta(TRANSITION_COLORS.END_META)
		else: route.set_meta(TRANSITION_COLORS.END_META, value)
	else: route.set(property, value)
	if transition_blocks.has(route): transition_blocks[route].refresh_summary()
	transition_editor.refresh()
	graph.queue_redraw()

func _transition_visual_changed(machine: FiniteStateMachine, route: StateTransition) -> void:
	if machine != state_machine: return
	_apply_block_appearance(route)
	if route != null:
		transitions_panel.update_colors(route)
	if transition_editor.selected != null:
		transition_editor.color_picker.color = TRANSITION_COLORS.color(transition_editor.selected)
		transition_editor.start_color_reset.disabled = not TRANSITION_COLORS.has_override(transition_editor.selected)
		transition_editor.automatic_end_color = _automatic_end_color(transition_connections.get(transition_editor.selected, {}))
		transition_editor.end_color_picker.color = TRANSITION_COLORS.end_color(transition_editor.selected, transition_editor.automatic_end_color)
		transition_editor.end_color_auto.disabled = not TRANSITION_COLORS.has_end_override(transition_editor.selected)
	_render_selection()
	if selected_transition != null: _highlight_transition(selected_transition)
	if is_instance_valid(graph): graph.queue_redraw()
	if is_instance_valid(editor_interface): editor_interface.mark_scene_as_unsaved()


func _transition_property_changed(machine: FiniteStateMachine, route: StateTransition, property: StringName) -> void:
	if machine != state_machine or not transition_blocks.has(route): return
	# Endpoint mutations still use topology/connection handling. Other scalar
	# edits update their existing presentation, without recreating unrelated rows.
	if property in [&"source_mode", &"from_state", &"to_state"]: return
	transition_blocks[route].refresh_summary()
	transitions_panel.update_transition(route)
	# Existing action-completion flag: scoped visuals are already synchronized.
	# The generic changed signal still restores selection/Inspector and warnings.
	source_dock_updated = true


func _delete_transition(transition: StateTransition) -> void:
	if drafts.has(transition):
		_session_draft(transition, null, false)
		return
	if transition == fallback_entry:
		actions.set_initial(state_machine, null)
		return
	if is_instance_valid(state_machine):
		actions.delete_transition(state_machine, transition)


func _connection_menu_action(id: int) -> void:
	if not is_instance_valid(state_machine) or connection_context == null: return
	if not connection_context in state_machine.transitions and connection_context != fallback_entry: return
	match id:
		0: _select_transition(connection_context)
		1:
			right_tabs.current_tab = 1
			transitions_panel.open_create()
		2:
			var key := _connection_key(connection_context_edge.from_node, connection_context_edge.from_port, connection_context_edge.to_node, connection_context_edge.to_port) if not connection_context_edge.is_empty() else ""
			var branch: Dictionary = random_branch_connections.get(key, {})
			if not branch.is_empty() and transition_for_connection(connection_context_edge) == connection_context:
				_random_edited(random_blocks[branch.routing], "target", connection_context_edge.from_port, &"")
			else: _disconnect_transition_target(connection_context)
	connection_context_edge.clear()


func _disconnect_transition_target(route: StateTransition) -> void:
	if not is_instance_valid(state_machine): return
	_cancel_connection_drag()
	actions.disconnect_transition_target(state_machine, route, route == fallback_entry)
	_select_transition(route, false)


func _target_endpoint_changed(machine: FiniteStateMachine, route: StateTransition, source_only: bool) -> void:
	if machine != state_machine or source_only or not transition_blocks.has(route): return
	_trace_connection_sync("target_assigned")
	var old: Dictionary = transition_connections.get(route, {})
	var old_target := graph.get_node_or_null(NodePath(old.get("to_node", "")))
	if route.target_mode == StateTransition.TargetMode.RANDOM or old_target is RANDOM_BLOCK:
		# Random synchronization refreshes the Inspector before the generic changed
		# callback. Keep its filter on the newly assigned endpoint during do/undo.
		if selected_transition == route:
			transition_editor.target_filter = route.to_state
			transition_editor.selected = route
		return
	graph_index.rebuild(machine)
	for node in graph.get_children():
		if node is NODE_SCRIPT: graph_index.register_node(node.state, node)
	for node in graph.get_children():
		if not node is NODE_SCRIPT: continue
		node.set_outgoing_transitions(graph_index.routes_for(node.state), editor_interface)
		node.set_incoming_transitions(graph_index.incoming_for(StringName(String(node.state.name).to_lower())))
	if not old.is_empty():
		graph.disconnect_node(old.from_node, old.from_port, old.to_node, old.to_port)
		connection_transitions.erase(_connection_key(old.from_node, old.from_port, old.to_node, old.to_port))
		transition_connections.erase(route)
	var block: GraphNode = transition_blocks[route]
	var target := _graph_target(route.target_key())
	if not target.is_empty():
		var edge := _connect_block_segment(block.name, target, route)
		edge.source_edge = {}
		edge.source_node = _route_source(route)
		transition_connections[route] = edge
		# The gradient is drawn by GraphEdit.draw, separately from its native wire.
		# Reconnection updates the resource-to-edge mapping in place, so explicitly
		# invalidate that canvas after the exact edge and target port are current.
		graph.queue_redraw()
	block.refresh_summary()
	_dock_blocks()
	topology = _topology()
	transitions_panel.rebuild(machine)
	if selected_transition == route:
		# A target edit must keep the exact Inspector context on this Resource,
		# including when EXIT's empty to_state becomes a normal State name.
		transition_editor.source_mode_filter = route.source_mode
		transition_editor.source_filter = route.from_state if route.source_mode == StateTransition.SourceMode.STATE else &""
		transition_editor.target_filter = route.to_state
		transition_editor.selected = route
		if not selected_connection_edge.is_empty(): selected_connection_edge = transition_connections.get(route, {}).duplicate()
	transition_editor.refresh()
	_render_selection()
	source_dock_updated = true


func _add_parallel_transition(from: StringName, to: StringName, source_mode: int = StateTransition.SourceMode.STATE) -> void:
	if is_instance_valid(state_machine):
		var transition: StateTransition = actions.connect_states(state_machine, from, to, true, source_mode)
		if transition != null: _select_transition(transition)


func _edit_comparison(transition: StateTransition, condition: TransitionCondition, property: StringName, value: Variant) -> void:
	if is_instance_valid(state_machine):
		actions.edit_comparison(state_machine, transition, condition, property, value)


func _add_condition(transition: StateTransition) -> void:
	if is_instance_valid(state_machine):
		actions.add_condition(state_machine, transition)


func _remove_condition(transition: StateTransition, condition: TransitionCondition) -> void:
	if is_instance_valid(state_machine):
		actions.remove_condition(state_machine, transition, condition)

func _topology() -> String:
	if not is_instance_valid(state_machine): return ""
	var signature := []
	for node in state_machine.get_state_container().get_children():
		if node is State: signature.append([node.get_instance_id(), node.name, node.get_script()])
	signature.append(state_machine.initial_state)
	for route in state_machine.transitions:
		if route != null: signature.append([route.get_instance_id(), route.source_mode, route.from_state, route.target_key(), route.random_routing, route.random_routing.mode if route.random_routing != null else -1, _routing_signature(route.random_routing)])
	return str(signature)

func _refresh_block_values() -> void:
	is_loading = true
	var pairs := {}
	for route in transition_blocks:
		var block: GraphNode = transition_blocks[route]
		if route == fallback_entry:
			if state_machine.get_state_container().has_meta(&"fsm_editor_initial_block_position"): route.set_meta(BLOCK.POSITION_META, state_machine.get_state_container().get_meta(&"fsm_editor_initial_block_position"))
			else: route.remove_meta(BLOCK.POSITION_META)
		var from := _route_source(route)
		var to: StringName = _route_target(route)
		var pair := str([from, to])
		var offset: int = pairs.get(pair, 0)
		pairs[pair] = offset + 1
		block.refresh_summary()
		if not block.draft: block.position_offset = _block_default_position(from, to, offset)
	for node in graph.get_children():
		if node is GraphNode and not node is BLOCK and not node is RANDOM_BLOCK:
			node.position_offset = state_machine.graph_positions.get(_position_key(node), node.position_offset)
	_dock_blocks()
	is_loading = false
	transitions_panel.rebuild(state_machine)
	transition_editor.refresh()
	_restore_selection()
	_apply_state_appearance()
	_refresh_warning_summary()
	_sync_hierarchy_exit_connections()

func _palette_can_drop(_position: Vector2, payload: Variant) -> bool:
	if not payload is Dictionary or payload.get("type") != PALETTE.PAYLOAD_TYPE: return false
	if payload.has("trigger") and not palette_move.is_empty():
		_update_palette_insertion(_position)
		return palette_move.hover != null
	return is_instance_valid(state_machine) and (payload.get("structure") in ["State", "Hierarchy State"] or payload.get("trigger", -1) in StateTransition.TriggerType.values() or payload.get("routing") == "Random")

func _palette_activate(payload: Dictionary) -> void:
	# Reuse the existing creation placement helper for keyboard/click activation
	# so repeated activation does not stack all items at the same graph center.
	var position := _new_state_position(_selected_state())
	_palette_drop(position * graph.zoom - graph.scroll_offset, payload)

func _resize_minimap() -> void:
	# Keep the supported native minimap from covering short/narrow workspaces.
	graph.minimap_size = Vector2(minf(240, maxf(80, graph.size.x * 0.28)), minf(160, maxf(45, graph.size.y * 0.28)))

func _palette_drop(position: Vector2, payload: Variant) -> void:
	if not _palette_can_drop(position, payload):
		if not palette_move.is_empty(): _clear_palette_move(); return
		warning_summary.text = "Select a FiniteStateMachine to create graph items."
		return
	var graph_position := (position + graph.scroll_offset) / graph.zoom
	var owner := editor_interface.get_edited_scene_root() if is_instance_valid(editor_interface) else null
	if payload.get("routing") == "Random":
		var routing := StateRandomRouting.new()
		routing.set_meta(&"fsm_editor_random_color", actions.creation_color)
		_session_draft(routing, {"machine": weakref(state_machine), "position": graph_position}, true)
	elif payload.has("structure"):
		var hierarchy: bool = payload.structure == "Hierarchy State"
		var requested: String = actions.unique_name(state_machine, "HierarchyState" if hierarchy else "State")
		var state: State = actions.create_hierarchy(state_machine, requested, graph_position, owner) if hierarchy else actions.create_state(state_machine, requested, graph_position, owner)
		_select_created_state(state)
	else:
		var route := actions.new_transition()
		route.trigger_type = payload.trigger
		var insertion := _block_insertion(graph_position, route)
		# Native palette gestures require a compatible slot; click activation
		# retains the accessible free draft placement shortcut.
		if not palette_move.is_empty() and insertion.is_empty(): _clear_palette_move(); return
		var source: StringName = insertion.source.name if not insertion.is_empty() else &""
		var anchor: StateTransition
		if not insertion.is_empty():
			var siblings: Array[GraphNode] = []
			for block in _ordered_blocks():
				if (block.draft_source if block.draft else _route_source(block.transition)) == source: siblings.append(block)
			if insertion.index < siblings.size(): anchor = siblings[insertion.index].transition
		_clear_palette_move()
		if not source.is_empty():
			var source_node := graph.get_node_or_null(NodePath(source)) as GraphNode
			route.source_mode = _source_mode(source_node)
			route.from_state = source_node.state.name if source_node.state != null else &""
			if actions.author_incomplete_transition(state_machine, route, anchor): _select_transition(route)
		else:
			_session_draft(route, {"machine": weakref(state_machine), "position": graph_position, "source": &"", "target": &""}, false)
			_select_transition(route)
		empty_label.hide()

func _restore_drafts() -> void:
	for route in drafts.keys():
		var data: Dictionary = drafts[route]
		if not is_instance_valid(data.machine.get_ref()): drafts.erase(route); continue
		if data.machine.get_ref() != state_machine or route in state_machine.transitions: continue
		var block := _make_block(route, true)
		block.position_offset = data.position
		block.draft_source = data.source if graph.get_node_or_null(NodePath(data.source)) != null else &""
		block.draft_target = data.target if graph.get_node_or_null(NodePath(data.target)) != null else &""
		block.dock_source = block.draft_source
		if not block.draft_source.is_empty():
			var source: GraphNode = graph.get_node(NodePath(block.draft_source))
			route.source_mode = _source_mode(source)
			route.from_state = source.state.name if source.state != null else &""
		else:
			route.source_mode = StateTransition.SourceMode.STATE
			route.from_state = &""
		block.update_color()
		if not block.draft_target.is_empty(): _connect_block_segment(block.name, block.draft_target, route)
		empty_label.hide()

func _connect_transition_block(source: GraphNode, from_port: int, target: GraphNode, to_port: int) -> void:
	if source == null or target == null or source is BLOCK and target is BLOCK: _cancel_connection_drag(); return
	if from_port != 0 or to_port != 0 or source.get_output_port_count() == 0 or target.get_input_port_count() == 0: _cancel_connection_drag(); return
	var block: GraphNode = source if source is BLOCK else target
	var route: StateTransition = block.transition
	var changing_target := source == block
	var request := reconnect.duplicate()
	_cancel_connection_drag()
	if not block.draft:
		# The unchanged end must stay attached to this exact block, never a pair lookup.
		if not request.is_empty():
			if request.route != route or request.machine != state_machine: return
			if request.target:
				if source.name != request.edge.from_node: return
			else:
				if target.name != request.edge.to_node: return
		var mode: int = route.source_mode if changing_target else _source_mode(source)
		var from: StringName = route.from_state if changing_target else (source.state.name if source.state != null else &"")
		var to: StringName = _target_name(target) if changing_target else route.target_key()
		if route == fallback_entry:
			if changing_target and target.state != null: actions.set_initial(state_machine, target.state)
			return
		if actions.reconnect_transition(state_machine, route, mode, from, to, &"to" if changing_target else &"from"): _select_transition(route, false)
		return
	if changing_target: block.draft_target = target.name
	else: block.draft_source = source.name
	block.dock_source = block.draft_source
	var data: Dictionary = drafts[route]
	data.source = block.draft_source
	data.target = block.draft_target
	if not block.draft_source.is_empty():
		var a := graph.get_node(NodePath(block.draft_source)) as GraphNode
		route.source_mode = _source_mode(a)
		route.from_state = a.state.name if a.state != null else &""
		if not block.draft_target.is_empty():
			var b := graph.get_node(NodePath(block.draft_target)) as GraphNode
			route.destination_mode = StateTransition.DestinationMode.EXIT if b == exit_node else StateTransition.DestinationMode.STATE
			route.to_state = b.state.name if b.state != null else &""
		if route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY and route.trigger_type != StateTransition.TriggerType.MANUAL:
			warning_summary.text = "ENTRY routes use Manual; other triggers need a State or Any State source."
			refresh()
			return
		route.set_meta(BLOCK.POSITION_META, data.position)
		# Attachments become durable authored Resources immediately, even if TO is
		# still empty; retain this exact Resource and its slot as it is completed.
		var before_route: StateTransition
		var found := false
		for sibling in _ordered_blocks():
			if sibling == block: found = true; continue
			if found and not sibling.draft and _route_source(sibling.transition) == block.draft_source:
				before_route = sibling.transition
				break
		drafts.erase(route)
		var authored := actions.commit_draft(state_machine, route, before_route) if not block.draft_target.is_empty() else actions.author_incomplete_transition(state_machine, route, before_route)
		if authored: _select_transition(route)
		else:
			drafts[route] = data
			warning_summary.text = "Could not author transition: invalid source or destination."
			refresh()
	else:
		var old: Dictionary = transition_connections.get(route, {})
		if not old.is_empty():
			graph.disconnect_node(old.from_node, old.from_port, old.to_node, old.to_port)
			connection_transitions.erase(_connection_key(old.from_node, old.from_port, old.to_node, old.to_port))
		if not block.draft_target.is_empty(): _connect_block_segment(block.name, block.draft_target, route)
		_queue_connection_redraw()

func _source_mode(node: GraphNode) -> int:
	if node == entry_node: return StateTransition.SourceMode.HIERARCHY_ENTRY
	if node == any_state_node: return StateTransition.SourceMode.ANY_STATE
	return StateTransition.SourceMode.STATE

func _target_name(node: GraphNode) -> StringName:
	return StateTransition.EXIT_TARGET if node == exit_node else (node.state.name if node.state != null else &"")

func _apply_block_appearance(changed_route: StateTransition = null) -> void:
	if not is_instance_valid(editor_interface):
		if changed_route != null and transition_blocks.has(changed_route): transition_blocks[changed_route].update_color()
		return
	var settings := _editor_settings()
	TRANSITION_COLORS.default_color = APPEARANCE.get_color(settings, "default_transition")
	if is_instance_valid(creation_color_picker): creation_color_picker.color = TRANSITION_COLORS.default_color
	actions.creation_color = TRANSITION_COLORS.default_color
	if settings.get_setting(TRANSITION_COLORS.SETTING) != TRANSITION_COLORS.default_color:
		settings.set_setting(TRANSITION_COLORS.SETTING, TRANSITION_COLORS.default_color)
	if fallback_entry != null and (changed_route == null or changed_route == fallback_entry):
		if state_machine.get_state_container().has_meta(&"fsm_editor_entry_color"): fallback_entry.set_meta(TRANSITION_COLORS.META, state_machine.get_state_container().get_meta(&"fsm_editor_entry_color"))
		else: fallback_entry.remove_meta(TRANSITION_COLORS.META)
	for route in transition_blocks:
		if changed_route == null or changed_route == route: transition_blocks[route].update_color()
	if changed_route != null: return
	for routing in random_blocks:
		var random_block = random_blocks[routing]
		var router_color: Color = routing.get_meta(&"fsm_editor_random_color", APPEARANCE.get_color(settings, "default_random"))
		random_block.apply_router_appearance(
			APPEARANCE.get_color(settings, "default_random"),
			APPEARANCE.get_color(settings, "selected_accent"),
			random_block.selected
		)
		if selected_random == routing: _sync_random_router_inspector(routing, router_color)
		for branch in routing.branches:
			if branch != null: random_block.set_branch_color(branch, TRANSITION_COLORS.color(branch))
	graph.queue_redraw()
	for node in [entry_node, exit_node]:
		if not is_instance_valid(node) or not is_instance_valid(state_machine): continue
		var entry: bool = node == entry_node
		_apply_boundary_appearance(entry)

func _block_popup(block: GraphNode) -> void:
	connection_context_edge.clear()
	selected_connection_edge.clear()
	connection_context = block.transition
	color_target = null
	color_boundary = ""
	block_menu.set_item_disabled(0, block.draft)
	block_menu.set_item_disabled(1, block.draft or TRANSITION_COLORS.uses_entry_color(block.transition))
	block_menu.set_item_disabled(2, block.draft or TRANSITION_COLORS.uses_entry_color(block.transition))
	block_menu.set_item_disabled(3, block.draft or block.transition == fallback_entry)
	block_menu.set_item_disabled(5, true)
	block_menu.set_item_disabled(6, block.draft or block.transition == fallback_entry)
	block_menu.set_item_disabled(7, not clipboard.refusal(state_machine, selected_state).is_empty())
	block_menu.position = Vector2i(graph.get_global_mouse_position())
	block_menu.popup()

func _boundary_popup(node: GraphNode) -> void:
	color_target = state_machine.get_state_container()
	color_boundary = "entry" if node == entry_node else "exit"
	for index in 5: block_menu.set_item_disabled(index, index not in [1, 2])
	block_menu.set_item_disabled(0, false)
	block_menu.set_item_disabled(5, node != entry_node)
	block_menu.set_item_disabled(6, true)
	block_menu.set_item_disabled(7, not clipboard.refusal(state_machine, selected_state).is_empty())
	block_menu.position = Vector2i(graph.get_global_mouse_position())
	block_menu.popup()

func _block_menu_action(id: int) -> void:
	if not is_instance_valid(state_machine): return
	if id == 7: _paste_clipboard(); return
	if id == 6:
		if connection_context != null: clipboard.copy_transition(state_machine, connection_context)
		return
	if color_boundary != "":
		if id == 0: _select_boundary(SelectionMode.ENTRY if color_boundary == "entry" else SelectionMode.EXIT)
		elif id == 5 and color_boundary == "entry": _open_graph_creation(entry_node.name)
		elif id == 2: actions.set_boundary_color(state_machine, color_boundary == "entry", null); color_target = null; color_boundary = ""
		elif id == 1:
			var key := &"fsm_editor_boundary_entry_color" if color_boundary == "entry" else &"fsm_editor_exit_color"
			dialogs.show_color(state_machine.get_state_container().get_meta(key, APPEARANCE.get_color(_editor_settings(), color_boundary)))
		return
	var route := connection_context
	if route == null: return
	match id:
		0: _select_transition(route)
		1:
			color_target = route
			dialogs.show_color(TRANSITION_COLORS.color(route))
		2: _edit_transition(route, &"editor_color", null)
		3: _edit_transition(route, &"enabled", not route.enabled)
		4:
			if drafts.has(route): _session_draft(route, null, false)
			else: _delete_transition(route)

func _graph_positions_changed(machine: FiniteStateMachine) -> void:
	if machine != state_machine: return
	is_loading = true
	for routing in random_blocks:
		var fallback: Vector2 = actions.applied_random_positions.get(routing, {}).get("value", random_blocks[routing].position_offset)
		random_blocks[routing].position_offset = routing.get_meta(RANDOM_BLOCK.POSITION_META, fallback)
	for node in graph.get_children():
		if node is GraphNode and not node is BLOCK and not node is RANDOM_BLOCK:
			node.position_offset = machine.graph_positions.get(_position_key(node), node.position_offset)
	var pairs := {}
	for route in transition_blocks:
		var block: GraphNode = transition_blocks[route]
		if block.draft: continue
		if route == fallback_entry:
			if machine.get_state_container().has_meta(&"fsm_editor_initial_block_position"): route.set_meta(BLOCK.POSITION_META, machine.get_state_container().get_meta(&"fsm_editor_initial_block_position"))
			else: route.remove_meta(BLOCK.POSITION_META)
		var from := _route_source(route)
		var to: StringName = _route_target(route)
		var pair := str([from, to])
		var offset: int = pairs.get(pair, 0)
		pairs[pair] = offset + 1
		block.position_offset = _block_default_position(from, to, offset)
	_dock_blocks()
	is_loading = false
	if is_instance_valid(editor_interface): editor_interface.mark_scene_as_unsaved()

func _dock_at(point: Vector2) -> GraphNode:
	# Body drops are an accessible shortcut to the same bottom-only attachment.
	for node in graph.get_children():
		if not node is GraphNode or not node.visible or node is BLOCK or node is RANDOM_BLOCK or node == exit_node: continue
		if Rect2(node.position_offset, node.size).has_point(point): return node
	for node in graph.get_children():
		if not node is GraphNode or not node.visible or node is BLOCK or node is RANDOM_BLOCK or node == exit_node: continue
		var width := maxf(node.size.x, node.get_meta("dock_width", 0.0))
		var height: float = node.size.y + node.get_meta("dock_height", 0.0)
		if Rect2(node.position_offset + Vector2(0, node.size.y), Vector2(width, height - node.size.y + 80)).has_point(point): return node
	return null

func _attach_draft(block: GraphNode, source: GraphNode) -> void:
	if source == exit_node: return
	if source == entry_node and block.transition.trigger_type != StateTransition.TriggerType.MANUAL: return
	if not block.draft: return
	var route: StateTransition = block.transition
	route.source_mode = _source_mode(source)
	route.from_state = source.state.name if source.state != null else &""
	if not _block_move_valid_source(route, source): return
	block.draft_source = source.name
	block.dock_source = source.name
	var data: Dictionary = drafts[route]
	data.source = source.name
	if not block.draft_target.is_empty():
		var target := graph.get_node_or_null(NodePath(block.draft_target)) as GraphNode
		if target == null: return
		route.destination_mode = StateTransition.DestinationMode.EXIT if target == exit_node else StateTransition.DestinationMode.STATE
		route.to_state = target.state.name if target.state != null else &""
	if route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY and route.trigger_type != StateTransition.TriggerType.MANUAL:
		warning_summary.text = "ENTRY routes use Manual; other triggers need a State or Any State source."
		refresh()
		return
	route.set_meta(BLOCK.POSITION_META, data.position)
	block.update_color()
	_dock_blocks()
	var before_route: StateTransition
	var found := false
	for sibling in _ordered_blocks():
		if sibling == block: found = true; continue
		if found and not sibling.draft and _route_source(sibling.transition) == block.draft_source:
			before_route = sibling.transition
			break
	drafts.erase(route)
	var authored := actions.commit_draft(state_machine, route, before_route) if not block.draft_target.is_empty() else actions.author_incomplete_transition(state_machine, route, before_route)
	if authored: _select_transition(route)
	else:
		drafts[route] = data
		warning_summary.text = "Could not author transition: invalid source or destination."
		refresh()

func _dock_blocks() -> void:
	preload("res://addons/state_machine/editor/graph_docking.gd").arrange(self)

func _queue_dock_blocks() -> void:
	if dock_refresh_queued or not is_inside_tree(): return
	dock_refresh_queued = true
	_deferred_dock_blocks.call_deferred()

func _deferred_dock_blocks() -> void:
	dock_refresh_queued = false
	if is_inside_tree() and is_instance_valid(state_machine): _dock_blocks()

func _transition_order_changed(machine: FiniteStateMachine, route: StateTransition) -> void:
	_source_endpoint_changed(machine, route, true)


func _source_endpoint_changed(machine: FiniteStateMachine, route: StateTransition, source_only: bool) -> void:
	if machine != state_machine or not source_only or not transition_blocks.has(route): return
	var block: GraphNode = transition_blocks[route]
	var source := _route_source(route)
	if source.is_empty(): return # A new Any State boundary still needs a structural rebuild.
	var previous: StringName = block.dock_source
	graph_index.rebuild(machine)
	for node in graph.get_children():
		if node is GraphNode and node.state != null: graph_index.register_node(node.state, node)
	for name in [previous, source]:
		var node := graph.get_node_or_null(NodePath(name)) as GraphNode
		if node == null: continue
		if node.state != null: node.set_outgoing_transitions(graph_index.routes_for(node.state), editor_interface)
		elif node == any_state_node:
			var routes: Array[StateTransition] = []
			for value in machine.transitions:
				if value != null and value.source_mode == StateTransition.SourceMode.ANY_STATE: routes.append(value)
			node.set_outgoing_transitions(routes, editor_interface)
		elif node == entry_node:
			var routes: Array[StateTransition] = []
			for value in machine.transitions:
				if value != null and value.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: routes.append(value)
			node.set_routes(routes, editor_interface)
	if transition_connections.has(route): transition_connections[route].source_node = source
	_dock_blocks()
	topology = _topology()
	transitions_panel.rebuild(machine)
	source_dock_updated = true

func _make_random_block(routing: StateRandomRouting, route: StateTransition, position: Vector2) -> GraphNode:
	return random_controller._make_random_block(self, routing, route, position)

func _random_block_gui_input(event: InputEvent, block: GraphNode) -> void:
	random_controller._random_block_gui_input(self, event, block)

func _random_block_body_click(block: GraphNode, global_position: Vector2) -> void:
	random_controller._random_block_body_click(self, block, global_position)

func _restore_random_blocks() -> void:
	random_controller._restore_random_blocks(self)

func _sync_random_branches(block: GraphNode) -> void:
	random_controller._sync_random_branches(self, block)

func _random_endpoint_changed(machine: FiniteStateMachine, route: StateTransition, source_only: bool) -> void:
	random_controller._random_endpoint_changed(self, machine, route, source_only)

func _sync_random_visuals() -> void:
	random_controller._sync_random_visuals(self)

func _disconnect_random_input(block: GraphNode) -> void:
	random_controller._disconnect_random_input(self, block)

func _connect_random(source: GraphNode, from_port: int, target: GraphNode, to_port: int) -> void:
	random_controller._connect_random(self, source, from_port, target, to_port)

func _random_edited(block: GraphNode, command: String, index: int, value: Variant) -> void:
	random_controller._random_edited(self, block, command, index, value)

func _begin_random_branch_color_edit(branch: StateRandomTarget, picker: ColorPickerButton, meta_key: StringName = TRANSITION_COLORS.META) -> void:
	random_controller._begin_random_branch_color_edit(self, branch, picker, meta_key)

func _begin_random_router_color_edit(routing: StateRandomRouting, picker: ColorPickerButton) -> void:
	random_controller._begin_random_router_color_edit(self, routing, picker)

func _preview_random_router_color(color: Color, routing: StateRandomRouting) -> void:
	random_controller._preview_random_router_color(self, color, routing)

func _finish_random_router_color_edit(routing: StateRandomRouting, picker: ColorPickerButton) -> void:
	random_controller._finish_random_router_color_edit(self, routing, picker)

func _set_random_router_color(routing: StateRandomRouting, color: Variant) -> void:
	random_controller._set_random_router_color(self, routing, color)

func _apply_random_router_color(routing: StateRandomRouting, color: Variant) -> void:
	random_controller._apply_random_router_color(self, routing, color)

func _apply_random_router_appearance(routing: StateRandomRouting) -> void:
	random_controller._apply_random_router_appearance(self, routing)

func _sync_random_router_inspector(routing: StateRandomRouting, color: Color) -> void:
	random_controller._sync_random_router_inspector(self, routing, color)

func _preview_random_branch_color(color: Color, branch: StateRandomTarget, meta_key: StringName = TRANSITION_COLORS.META) -> void:
	random_controller._preview_random_branch_color(self, color, branch, meta_key)

func _finish_random_branch_color_edit(branch: StateRandomTarget, picker: ColorPickerButton, meta_key: StringName = TRANSITION_COLORS.META) -> void:
	random_controller._finish_random_branch_color_edit(self, branch, picker, meta_key)

func _set_random_branch_color(branch: StateRandomTarget, color: Variant, meta_key: StringName = TRANSITION_COLORS.META) -> void:
	random_controller._set_random_branch_color(self, branch, color, meta_key)

func _apply_random_branch_color(branch: StateRandomTarget, color: Variant, meta_key: StringName = TRANSITION_COLORS.META) -> void:
	random_controller._apply_random_branch_color(self, branch, color, meta_key)

func _edge_for_random_branch(branch: StateRandomTarget) -> Dictionary:
	return random_controller._edge_for_random_branch(self, branch)

func _apply_draft_routing_values(routing: StateRandomRouting, values: Dictionary) -> void:
	random_controller._apply_draft_routing_values(self, routing, values)

func _apply_draft_routing(routing: StateRandomRouting, command: String, index: int, value: Variant) -> void:
	random_controller._apply_draft_routing(self, routing, command, index, value)

func _select_random(routing: StateRandomRouting) -> void:
	random_controller._select_random(self, routing)

func _select_random_branch(routing: StateRandomRouting, branch: StateRandomTarget, edge: Dictionary) -> void:
	random_controller._select_random_branch(self, routing, branch, edge)

func _show_random_inspector(routing: StateRandomRouting, branch: StateRandomTarget, edge: Dictionary) -> void:
	random_controller._show_random_inspector(self, routing, branch, edge)

func _random_color_row(branch: StateRandomTarget) -> VBoxContainer:
	return random_controller._random_color_row(self, branch)

func _routing_signature(routing: StateRandomRouting) -> String:
	return random_controller._routing_signature(self, routing)

func _session_draft(resource: Resource, data: Variant, random: bool) -> void:
	var collection: Dictionary = random_drafts if random else drafts
	var previous: Variant = collection.get(resource)
	previous = previous.duplicate() if previous is Dictionary else null
	if actions.undo_manager == null: _apply_session_draft(resource, data, random)
	else:
		actions.undo_manager.create_action("Create Random Draft" if random else "Create Transition Draft", UndoRedo.MERGE_DISABLE, state_machine.get_state_container())
		actions.undo_manager.add_do_method(self, "_apply_session_draft", resource, data, random)
		actions.undo_manager.add_undo_method(self, "_apply_session_draft", resource, previous, random)
		actions.undo_manager.commit_action()

func _apply_session_draft(resource: Resource, data: Variant, random: bool) -> void:
	var collection: Dictionary = random_drafts if random else drafts
	if data == null: collection.erase(resource)
	else: collection[resource] = data.duplicate()
	refresh()
