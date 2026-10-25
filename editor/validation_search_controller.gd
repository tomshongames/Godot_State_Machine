@tool
extends RefCounted

const INDEX := preload("res://addons/state_machine/editor/fsm_graph_index.gd")
const VALIDATOR := preload("res://addons/state_machine/editor/fsm_validator.gd")
const ICONS := preload("res://addons/state_machine/editor/editor_icons.gd")
const LOGIC := preload("res://addons/state_machine/runtime/condition_expression.gd")
var panel
var index := INDEX.new()
var validator := VALIDATOR.new()
var validation_tab: VBoxContainer
var issues_tree: Tree
var counters: Label
var filter: OptionButton
var fix: Button
var search: LineEdit
var results: Tree
var issues: Array[Dictionary] = []
var bindings: Array[Dictionary] = []
var pending := false
var stopped := false
var rendering := false

func setup(owner) -> void:
	panel = owner
	validation_tab = VBoxContainer.new()
	validation_tab.name = "Validation"
	panel.right_tabs.add_child(validation_tab)
	panel.right_tabs.move_child(validation_tab, 2)
	var heading := Label.new()
	heading.text = "VALIDATION"
	validation_tab.add_child(heading)
	var controls := HFlowContainer.new()
	validation_tab.add_child(controls)
	var refresh := Button.new()
	refresh.text = "Validate"
	refresh.icon = ICONS.get_icon(validation_tab, "Reload")
	refresh.pressed.connect(rebuild)
	controls.add_child(refresh)
	filter = OptionButton.new()
	for label in ["All", "Errors", "Warnings"]: filter.add_item(label)
	filter.item_selected.connect(func(_value): render_issues())
	controls.add_child(filter)
	counters = Label.new()
	validation_tab.add_child(counters)
	issues_tree = _tree()
	issues_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	validation_tab.add_child(issues_tree)
	issues_tree.item_selected.connect(_issue_selected)
	fix = Button.new()
	fix.text = "Remove Orphan Transition"
	fix.icon = ICONS.get_icon(validation_tab, "Remove")
	fix.hide()
	fix.pressed.connect(_quick_fix)
	validation_tab.add_child(fix)
	search = LineEdit.new()
	search.name = "FSMSearch"
	search.placeholder_text = "Search..."
	search.clear_button_enabled = true
	search.custom_minimum_size.x = 220
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.toolbar.add_child(search)
	search.text_changed.connect(_query)
	search.gui_input.connect(_search_key)
	results = _tree()
	results.name = "FSMSearchResults"
	results.custom_minimum_size.y = 180
	results.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	results.hide()
	panel.add_child(results)
	panel.move_child(results, 1)
	results.item_mouse_selected.connect(func(_position, _button): _open_search())
	results.item_activated.connect(_open_search)
	panel.actions.changed.connect(queue_rebuild)
	ProjectSettings.settings_changed.connect(queue_rebuild)
	if is_instance_valid(panel.editor_interface):
		panel.editor_interface.get_inspector().property_edited.connect(_policy_property_edited)
	render_issues()

func _policy_property_edited(property: String) -> void:
	if stopped or not is_instance_valid(panel): return
	if property not in ["minimum_state_time", "interruptible", "cooldown", "can_interrupt"]: return
	queue_rebuild()
	panel._render_selection()

func _tree() -> Tree:
	var tree := Tree.new()
	tree.hide_root = true
	tree.columns = 2
	tree.set_column_expand_ratio(0, 2)
	tree.set_column_expand_ratio(1, 1)
	return tree

func set_machine(machine: FiniteStateMachine) -> void:
	var root := INDEX.root_for(machine)
	if index.root == root and is_instance_valid(root): return
	search.text = ""
	rebuild()

func queue_rebuild(_machine = null) -> void:
	if pending or stopped or not is_instance_valid(panel) or not panel.is_inside_tree(): return
	pending = true
	panel.get_tree().create_timer(0.1).timeout.connect(_deferred_rebuild)

func _deferred_rebuild() -> void:
	pending = false
	if not stopped and is_instance_valid(panel) and panel.is_inside_tree(): rebuild()

func rebuild() -> void:
	if stopped: return
	_disconnect()
	index.rebuild(panel.state_machine)
	issues = validator.validate(index.root, index)
	panel._refresh_warning_summary()
	for c in index.contexts:
		var actor := index.actor(c)
		for signal_name in [&"script_changed", &"property_list_changed", &"child_order_changed"]: _bind(actor, signal_name)
		if actor != null: _bind(actor.get_script(), &"changed")
		for signal_name in [&"editor_data_changed", &"tree_exiting"]: _bind(c.fsm, signal_name)
		_bind(c.fsm.get_state_container(), &"child_order_changed")
		for state in c.states:
			_bind(state, &"renamed")
			_bind(state, &"child_order_changed")
			_bind(state, &"script_changed")
			_bind(state.get_script(), &"changed")
		for route in c.fsm.transitions:
			if route == null: continue
			_bind(route, &"changed")
			_bind(route.random_routing, &"changed")
			if route.random_routing != null:
				for branch in route.random_routing.branches: _bind(branch, &"changed")
			_bind(route.watch, &"changed")
			for resource in LOGIC.compile(route).resources: _bind(resource, &"changed")
			for effect in route.actions: _bind(effect, &"changed")
	render_issues()
	_query(search.text)

func _bind(object: Object, signal_name: StringName) -> void:
	if not is_instance_valid(object) or not object.has_signal(signal_name) or object.is_connected(signal_name, queue_rebuild): return
	object.connect(signal_name, queue_rebuild)
	bindings.append({"object": weakref(object), "signal": signal_name})

func _disconnect() -> void:
	for binding in bindings:
		var object: Object = binding.object.get_ref()
		if object != null and object.is_connected(binding.signal, queue_rebuild): object.disconnect(binding.signal, queue_rebuild)
	bindings.clear()

func shutdown() -> void:
	if ProjectSettings.settings_changed.is_connected(queue_rebuild): ProjectSettings.settings_changed.disconnect(queue_rebuild)
	stopped = true
	_disconnect()
	if panel.actions.changed.is_connected(queue_rebuild): panel.actions.changed.disconnect(queue_rebuild)
	if is_instance_valid(panel.editor_interface):
		var inspector: EditorInspector = panel.editor_interface.get_inspector()
		if inspector.property_edited.is_connected(_policy_property_edited): inspector.property_edited.disconnect(_policy_property_edited)
	index.contexts.clear()
	index.items.clear()
	index.by_machine.clear()
	issues.clear()

func render_issues() -> void:
	rendering = true
	issues_tree.clear()
	fix.hide()
	var root := issues_tree.create_item()
	var errors := 0
	var warnings := 0
	for issue in issues:
		if issue.severity == 0: errors += 1
		else: warnings += 1
		if filter.selected == 1 and issue.severity != 0 or filter.selected == 2 and issue.severity != 1: continue
		var row := issues_tree.create_item(root)
		row.set_text(0, ("ERROR \u00b7 " if issue.severity == 0 else "WARNING \u00b7 ") + issue.message)
		row.set_text(1, issue.hierarchy_path)
		row.set_tooltip_text(0, issue.code + "\n" + issue.message + "\n" + issue.hierarchy_path)
		row.set_icon(0, ICONS.get_icon(issues_tree, "Error" if issue.severity == 0 else "Warning"))
		row.set_metadata(0, issue)
	counters.text = "No State Machine selected" if not is_instance_valid(index.root) else ("No problems" if issues.is_empty() else "Errors: %d \u00b7 Warnings: %d" % [errors, warnings])
	rendering = false

func _issue_selected() -> void:
	if rendering: return
	var selected := issues_tree.get_selected()
	if selected == null: return
	var issue: Dictionary = selected.get_metadata(0)
	navigate(issue)
	fix.visible = issue.optional_fix_id == "remove_orphan" and issue.transition != null

func _quick_fix() -> void:
	var selected := issues_tree.get_selected()
	if selected == null: return
	var issue: Dictionary = selected.get_metadata(0)
	if issue.optional_fix_id != "remove_orphan" or not is_instance_valid(issue.fsm) or not issue.transition in issue.fsm.transitions: return
	var latest := VALIDATOR.new().validate(issue.fsm)
	if latest.any(func(value): return value.transition == issue.transition and value.optional_fix_id == "remove_orphan"):
		panel.actions.delete_transition(issue.fsm, issue.transition)
		queue_rebuild()

func _query(text: String) -> void:
	results.clear()
	results.visible = not text.strip_edges().is_empty()
	var root := results.create_item()
	for item in index.query(text):
		var row := results.create_item(root)
		row.set_text(0, item.label)
		row.set_text(1, item.hierarchy_path)
		row.set_tooltip_text(0, item.label + "\n" + item.hierarchy_path)
		row.set_metadata(0, item)
		row.set_icon(0, preload("res://addons/state_machine/icons/hierarchy_state.svg") if item.state is HierarchyState else (preload("res://addons/state_machine/icons/state.svg") if item.state != null else ICONS.get_icon(results, "Transition")))
	if root.get_first_child() != null: root.get_first_child().select(0)

func _open_search() -> void:
	var selected := results.get_selected()
	if selected != null: navigate(selected.get_metadata(0))

func navigate(item: Dictionary) -> void:
	var machine = item.get("fsm")
	if not is_instance_valid(machine) or not machine.is_inside_tree() or not index.by_machine.has(machine): return
	var state = item.get("state")
	if typeof(state) == TYPE_OBJECT and not is_instance_valid(state): return
	var route = item.get("transition")
	if route != null and not route in machine.transitions: return
	if state != null and (not is_instance_valid(state) or not state in index.by_machine[machine].states): return
	panel.editor_interface.set_main_screen_editor("State Machine")
	panel.transition_editor.navigation_read_only = true
	var runtime: Dictionary = {}
	if panel.live_debug.debugger != null: runtime = panel.live_debug.debugger.model.get_instance(panel.live_debug.selected_session, panel.live_debug.selected_id)
	panel._navigate_machine(machine)
	_restore_runtime(runtime, machine)
	var name := ""
	if route != null:
		panel._select_transition(route)
		panel.transitions_panel.select_transition(route)
		name = "__FSM_ENTRY__" if route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY else String(route.from_state)
		if route.source_mode == StateTransition.SourceMode.ANY_STATE:
			panel.any_source_requested = true
			panel.refresh()
			panel._select_transition(route)
			name = "__FSM_ANY_STATE__"
	elif is_instance_valid(state):
		panel.select_graph_state(state)
		panel.syncing_selection = true
		var selection: EditorSelection = panel.editor_interface.get_selection()
		selection.clear()
		selection.add_node(state)
		panel.editor_interface.inspect_object(state)
		panel.syncing_selection = false
		panel.navigation_selection_changed.emit(state)
		name = String(state.name)
	panel.transition_editor.navigation_read_only = false
	if route != null and route.source_mode == StateTransition.SourceMode.STATE:
		name = String(panel._graph_name(route.from_state))
		if name.is_empty(): name = "__FSM_EXIT__" if route.destination_mode == StateTransition.DestinationMode.EXIT else String(panel._graph_name(route.to_state))
	if route != null and panel.transition_blocks.has(route): name = String(panel.transition_blocks[route].name)
	_frame.call_deferred(weakref(machine), name)
	panel.show_authoring_dock()

func navigate_decision(record: Dictionary, candidate: Dictionary) -> bool:
	var labels := preload("res://addons/state_machine/runtime/transition_labels.gd")
	var data := preload("res://addons/state_machine/runtime/decision_data.gd")
	for context in index.contexts:
		var source: Dictionary = labels.source_identity(context.fsm)
		if source.scene != record.get("scene", "") or source.local_path != record.get("local_path", ""): continue
		var matches := []
		for route in context.fsm.transitions:
			if route == null: continue
			if not candidate.route_path.is_empty():
				if route.resource_path == candidate.route_path: matches.append(route)
			elif data.route_key(route) == candidate.route_key: matches.append(route)
		if matches.size() != 1: return false
		panel.live_debug.selected_session = record.session_id
		panel.live_debug.selected_id = record.id
		navigate({"fsm": context.fsm, "state": null, "transition": matches[0]})
		panel.right_tabs.current_tab = 3
		return true
	return false

func _runtime_root(record: Dictionary) -> String:
	var seen := {}
	while not record.get("parent_id", "").is_empty() and not seen.has(record.id):
		seen[record.id] = true
		var parent: Dictionary = panel.live_debug.debugger.model.get_instance(record.session_id, record.parent_id)
		if parent.is_empty(): break
		record = parent
	return record.get("id", "")

func _restore_runtime(previous: Dictionary, machine: FiniteStateMachine) -> void:
	if previous.is_empty() or panel.live_debug.debugger == null: return
	var source := preload("res://addons/state_machine/runtime/transition_labels.gd").source_identity(machine)
	var family := _runtime_root(previous)
	var session: Dictionary = panel.live_debug.debugger.model.sessions.get(previous.session_id, {})
	for record in session.get("instances", {}).values():
		if record.get("scene", "") == source.scene and record.get("local_path", "") == source.local_path and _runtime_root(record) == family:
			panel.live_debug.selected_session = previous.session_id
			panel.live_debug.selected_id = record.id
			panel.live_debug.refresh()
			return

func _frame(reference: WeakRef, name: String) -> void:
	if stopped or not is_instance_valid(panel) or panel.state_machine != reference.get_ref(): return
	var node := panel.graph.get_node_or_null(NodePath(name)) as GraphNode
	if node != null: panel.graph.scroll_offset = (node.position_offset + node.size * 0.5) * panel.graph.zoom - panel.graph.size * 0.5

func handle_key(event: InputEvent) -> bool:
	if not panel.workspace_active or not event is InputEventKey or not event.pressed: return false
	var focused: Control = panel.get_viewport().gui_get_focus_owner()
	if focused == null or not (focused == panel or panel.is_ancestor_of(focused) or panel.dock_content.is_ancestor_of(focused)): return false
	if event.keycode == KEY_F and (event.ctrl_pressed or event.meta_pressed): search.grab_focus(); return true
	return false

func _search_key(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	if event.keycode == KEY_ESCAPE:
		search.text = ""
		results.hide()
		search.accept_event()
	elif event.keycode == KEY_ENTER:
		_open_search()
		search.accept_event()
	elif event.keycode in [KEY_UP, KEY_DOWN]:
		var selected := results.get_selected()
		var next := selected.get_next() if selected != null and event.keycode == KEY_DOWN else (selected.get_prev() if selected != null else null)
		if next != null: next.select(0); results.scroll_to_item(next)
		search.accept_event()
