@tool
extends VBoxContainer

const LABELS := preload("res://addons/state_machine/runtime/transition_labels.gd")
const FOLLOW_SETTING := "editors/state_machine/debugger/follow_active_state"
const WATCH_ENTRY := preload("res://addons/state_machine/runtime/watch_entry.gd")
const WATCH_CONFIG := preload("res://addons/state_machine/editor/watch_configuration.gd")
const NODE_PATH_FIELD := preload("res://addons/state_machine/editor/node_path_field.gd")
const WATCH_RATE_SETTING := "editors/state_machine/debugger/watch_refresh_hz"
signal snapshot_changed(record: Dictionary)
signal flash_requested(event: Dictionary)
signal history_navigation_requested(event: Dictionary)
var debugger
var machine: FiniteStateMachine
var interface: EditorInterface
var instance_picker: OptionButton
var status: Button
var contents: VBoxContainer
var info: Label
var history: ItemList
var follow: CheckBox
var selected_session := -1
var selected_id := ""
var loading := false
var was_active := false
var refresh_pending := false
var pending_flash: Dictionary = {}
var watch_rows: VBoxContainer
var watch_dialog: AcceptDialog
var watch_name: LineEdit
var watch_target: OptionButton
var watch_node_path
var watch_property: LineEdit
var watch_suggestions: OptionButton
var watch_enabled: CheckBox
var watch_validation: Label
var watch_edit_index := -1
var undo_manager: EditorUndoRedoManager
var watch_signature := ""
var watch_rate_picker: OptionButton
var watch_render_signature := ""
var watch_value_labels: Array[Label] = []
var decisions
signal decision_navigation_requested(record: Dictionary, candidate: Dictionary)


func setup(editor: EditorInterface, undo: EditorUndoRedoManager = null) -> void:
	interface = editor
	undo_manager = undo
	status = Button.new()
	status.text = "Debugger inactive"
	status.alignment = HORIZONTAL_ALIGNMENT_LEFT
	status.pressed.connect(func(): contents.visible = not contents.visible)
	add_child(status)
	contents = VBoxContainer.new()
	add_child(contents)
	instance_picker = OptionButton.new()
	instance_picker.item_selected.connect(_picked)
	contents.add_child(instance_picker)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contents.add_child(info)
	decisions = preload("res://addons/state_machine/editor/decision_panel.gd").new()
	contents.add_child(decisions)
	decisions.setup()
	decisions.filter.item_selected.connect(func(_index): refresh())
	decisions.navigate_requested.connect(func(record, candidate): decision_navigation_requested.emit(record, candidate))
	var watch_header := HBoxContainer.new()
	contents.add_child(watch_header)
	var watch_title := Label.new()
	watch_title.text = "WATCH"
	watch_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	watch_header.add_child(watch_title)
	var refresh_label := Label.new()
	refresh_label.text = "Update Rate:"
	refresh_label.tooltip_text = "Live Watch update rate."
	watch_header.add_child(refresh_label)
	watch_rate_picker = OptionButton.new()
	watch_rate_picker.tooltip_text = "How often Live Watch values are sampled and displayed while debugging.\n5 Hz ≈ 5 updates/sec\n10 Hz ≈ 10 updates/sec\n20 Hz ≈ 20 updates/sec"
	for hz in [5, 10, 20]:
		watch_rate_picker.add_item("%d Hz" % hz)
		watch_rate_picker.set_item_metadata(watch_rate_picker.item_count - 1, hz)
	watch_rate_picker.item_selected.connect(func(_index):
		watch_signature = ""
		_sync_watch_subscription())
	watch_header.add_child(watch_rate_picker)
	var settings := interface.get_editor_settings() if is_instance_valid(interface) else null
	var watch_rate := 10
	if settings != null:
		if settings.get_setting(WATCH_RATE_SETTING) == null:
			settings.set_setting(WATCH_RATE_SETTING, 10)
		settings.add_property_info({"name": WATCH_RATE_SETTING, "type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": "5 Hz,10 Hz,20 Hz"})
		watch_rate = clampi(int(settings.get_setting(WATCH_RATE_SETTING)), 5, 20)
		if watch_rate not in [5, 10, 20]:
			watch_rate = 10
		settings.set_setting(WATCH_RATE_SETTING, watch_rate)
		watch_rate_picker.item_selected.connect(func(index): settings.set_setting(WATCH_RATE_SETTING, watch_rate_picker.get_item_metadata(index)))
	for index in watch_rate_picker.item_count:
		if watch_rate_picker.get_item_metadata(index) == watch_rate:
			watch_rate_picker.select(index)
	watch_rows = VBoxContainer.new()
	contents.add_child(watch_rows)
	var add_watch := Button.new()
	add_watch.text = "+ Watch"
	add_watch.pressed.connect(func(): _open_watch_dialog())
	contents.add_child(add_watch)
	_build_watch_dialog()
	follow = CheckBox.new()
	follow.text = "Follow Active State"
	follow.tooltip_text = "Focus the active State in the selected runtime FSM."
	if settings != null:
		if settings.get_setting(FOLLOW_SETTING) == null:
			settings.set_setting(FOLLOW_SETTING, false)
		settings.add_property_info({"name": FOLLOW_SETTING, "type": TYPE_BOOL})
		follow.button_pressed = bool(settings.get_setting(FOLLOW_SETTING))
		follow.toggled.connect(func(value): settings.set_setting(FOLLOW_SETTING, value))
	contents.add_child(follow)
	history = ItemList.new()
	history.custom_minimum_size.y = 90
	history.tooltip_text = "Latest 20 transitions; timestamps are seconds since runtime startup."
	history.item_selected.connect(func(index):
		var event: Variant = history.get_item_metadata(index)
		if event is Dictionary:
			history_navigation_requested.emit(event)
			flash_requested.emit(event))
	contents.add_child(history)
	var clear := Button.new()
	clear.text = "Clear History"
	clear.pressed.connect(func():
		if debugger != null:
			debugger.model.clear_history(selected_session, selected_id))
	var buttons := HBoxContainer.new()
	contents.add_child(buttons)
	buttons.add_child(clear)
	var resync := Button.new()
	resync.text = "Resync"
	resync.tooltip_text = "Request fresh snapshots from live FSM instances."
	resync.pressed.connect(func():
		if debugger != null:
			debugger.request_snapshots())
	buttons.add_child(resync)
	contents.hide()
	visibility_changed.connect(_sync_trace_subscription)

func _sync_trace_subscription() -> void:
	if debugger != null and debugger.has_method("update_trace_subscription"):
		debugger.update_trace_subscription(selected_session if is_visible_in_tree() else -1, selected_id if is_visible_in_tree() else "")


func set_debugger(value) -> void:
	pending_flash.clear()
	watch_signature = ""
	if debugger != null and debugger != value and debugger.has_method("update_trace_subscription"):
		debugger.update_trace_subscription(-1, "")
	if debugger != null and debugger.model.changed.is_connected(_changed):
		debugger.model.changed.disconnect(_changed)
	debugger = value
	if debugger != null:
		debugger.model.changed.connect(_changed)
	refresh()


func set_machine(value: FiniteStateMachine) -> void:
	if machine != value:
		if is_instance_valid(machine) and machine.editor_data_changed.is_connected(_watch_config_changed):
			machine.editor_data_changed.disconnect(_watch_config_changed)
		pending_flash.clear()
		watch_signature = ""
		selected_session = -1
		selected_id = ""
	machine = value
	if is_instance_valid(machine) and not machine.editor_data_changed.is_connected(_watch_config_changed):
		machine.editor_data_changed.connect(_watch_config_changed)
	refresh()
	if debugger != null:
		debugger.request_snapshots()


func _watch_config_changed() -> void:
	watch_signature = ""
	refresh()


func _changed(session_id: int, id: String, kind: String) -> void:
	if kind == "transition" and session_id == selected_session and id == selected_id:
		var record: Dictionary = debugger.model.get_instance(session_id, id)
		if not record.is_empty() and not record.last.is_empty():
			pending_flash = record.last.duplicate()
	elif (kind == "stopped" and session_id == selected_session) or (kind == "removed" and session_id == selected_session and id == selected_id):
		pending_flash.clear()
		if kind == "stopped":
			selected_session = -1
			selected_id = ""
	if not refresh_pending:
		refresh_pending = true
		_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	refresh_pending = false
	if not is_inside_tree():
		return
	refresh()
	if not pending_flash.is_empty():
		flash_requested.emit(pending_flash)
		pending_flash.clear()


func refresh() -> void:
	if not is_instance_valid(instance_picker):
		return
	loading = true
	instance_picker.clear()
	history.clear()
	var candidates: Array[Dictionary] = []
	var matches: Array[Dictionary] = []
	var source := LABELS.source_identity(machine) if is_instance_valid(machine) else {}
	if debugger != null:
		for session_id in debugger.model.sessions:
			for record in debugger.model.sessions[session_id].instances.values():
				candidates.append(record)
				if not source.get("scene", "").is_empty() and record.scene == source.scene and record.local_path == source.local_path:
					matches.append(record)
	var exact := not matches.is_empty()
	if exact:
		candidates = matches
	instance_picker.add_item("Runtime Instance" if exact else "Choose instance (all live FSMs)")
	instance_picker.set_item_metadata(0, [])
	if selected_id.is_empty() and exact:
		selected_session = candidates[0].session_id
		selected_id = candidates[0].id
	for record in candidates:
		instance_picker.add_item("Session %d · %s" % [record.session_id + 1, record.path])
		instance_picker.set_item_metadata(instance_picker.item_count - 1, [record.session_id, record.id])
		if record.session_id == selected_session and record.id == selected_id:
			instance_picker.select(instance_picker.item_count - 1)
	var active: bool = debugger != null and not debugger.model.sessions.is_empty()
	var current: Dictionary = debugger.model.get_instance(selected_session, selected_id) if debugger != null else {}
	status.text = "LIVE DEBUG" if active else "Debugger inactive"
	if active and debugger.model.sessions.get(selected_session, {}).get("paused", false):
		status.text += " — Paused"
	if not active:
		selected_id = ""
		selected_session = -1
		if is_instance_valid(machine):
			contents.show()
		else:
			contents.hide()
	elif not was_active:
		contents.show()
	was_active = active
	info.text = "Choose a runtime instance." if active else ""
	if active and not selected_id.is_empty() and current.is_empty():
		info.text = "Runtime instance ended."
	if not current.is_empty():
		instance_picker.tooltip_text = "Session %d · %s\nRuntime ID: %s" % [selected_session + 1, current.path, current.id]
		var last: Dictionary = current.last
		var current_path: String = current.get("active_path", current.current)
		var previous_path: String = current.get("previous_path", current.previous)
		info.text = "Current: %s\nPrevious: %s\nLast: %s\nTrigger: %s" % [current_path if not current_path.is_empty() else current.current, previous_path if not previous_path.is_empty() else (current.previous if not current.previous.is_empty() else "none"), "%s → %s" % [last.from, last.to] if not last.is_empty() else "none", last.description if not last.is_empty() else "none"]
		info.tooltip_text = "Actor: %s\nRuntime ID: %s" % [current.actor_path, current.id]
		for event in debugger.model.get_history(selected_session, selected_id):
			history.add_item("#%d %.3fs · %s → %s · %s" % [event.sequence, event.time_usec / 1000000.0, event.from, event.to, event.description])
			history.set_item_metadata(history.item_count - 1, event)
	_refresh_watch_rows(current)
	decisions.render(debugger.model.get_decisions(selected_session, selected_id) if debugger != null and not current.is_empty() else [], "%s:%s" % [selected_session, selected_id])
	if not current.is_empty(): info.text += "\nState Time: %.3f s" % current.get("state_elapsed", 0.0)
	elif not active: info.text = "No active FSM runtime instance."
	loading = false
	_sync_watch_subscription()
	_sync_trace_subscription()
	snapshot_changed.emit(current if is_instance_valid(machine) else {})


func _picked(index: int) -> void:
	if loading:
		return
	pending_flash.clear()
	var key: Array = instance_picker.get_item_metadata(index)
	selected_session = key[0] if key.size() == 2 else -1
	selected_id = key[1] if key.size() == 2 else ""
	watch_signature = ""
	refresh()


func _build_watch_dialog() -> void:
	watch_dialog = AcceptDialog.new()
	watch_dialog.title = "Configure Watch"
	watch_dialog.ok_button_text = "Save"
	watch_dialog.dialog_hide_on_ok = false
	add_child(watch_dialog)
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 360
	watch_dialog.add_child(form)
	watch_name = LineEdit.new()
	watch_name.placeholder_text = "Display name"
	form.add_child(watch_name)
	watch_target = OptionButton.new()
	for mode_index in range(3):
		var mode: String = ["Actor", "Node Path", "FSM"][mode_index]
		watch_target.add_item(mode, mode_index)
		watch_target.set_item_metadata(watch_target.item_count - 1, mode_index)
	watch_target.item_selected.connect(_watch_target_changed)
	form.add_child(watch_target)
	watch_node_path = NODE_PATH_FIELD.new()
	watch_node_path.setup("Node", interface, &"Node")
	form.add_child(watch_node_path)
	var property_row := HBoxContainer.new()
	form.add_child(property_row)
	watch_property = LineEdit.new()
	watch_property.placeholder_text = "Property or nested path (e.g. velocity:x)"
	watch_property.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	property_row.add_child(watch_property)
	watch_suggestions = OptionButton.new()
	watch_suggestions.add_item("Suggestions")
	watch_suggestions.item_selected.connect(func(index):
		if index > 0:
			watch_property.text = watch_suggestions.get_item_text(index))
	property_row.add_child(watch_suggestions)
	watch_enabled = CheckBox.new()
	watch_enabled.text = "Enabled"
	watch_enabled.button_pressed = true
	form.add_child(watch_enabled)
	watch_validation = Label.new()
	watch_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(watch_validation)
	watch_node_path.path_changed.connect(func(path): _refresh_watch_suggestions(path))
	watch_dialog.confirmed.connect(_save_watch_dialog)


func _watch_target_changed(_index: int) -> void:
	var mode := _selected_watch_target_mode()
	watch_node_path.visible = mode == 1
	_refresh_watch_suggestions(NodePath(watch_node_path.field.text) if mode == 1 else NodePath())


func _refresh_watch_suggestions(path: NodePath = NodePath()) -> void:
	watch_suggestions.clear()
	watch_suggestions.add_item("Suggestions")
	var mode := _selected_watch_target_mode()
	if mode == 2:
		for property in ["current_state", "previous_state"]:
			watch_suggestions.add_item(property)
		return
	if not is_instance_valid(machine) or not is_instance_valid(machine.get_effective_actor()):
		return
	var target: Node = machine.get_effective_actor()
	if mode == 1:
		var selected_path := path if not path.is_empty() else NodePath(watch_node_path.field.text)
		target = machine.get_effective_actor().get_node_or_null(selected_path)
	if not is_instance_valid(target):
		return
	var added := {}
	for property in target.get_property_list():
		var name := String(property.name)
		if name.begins_with("_") or name in ["script", "owner", "multiplayer"] or added.has(name):
			continue
		added[name] = true
		watch_suggestions.add_item(name)


func _open_watch_dialog(index := -1) -> void:
	if not is_instance_valid(machine):
		return
	watch_edit_index = index
	var entry = machine.debugger_watches[index] if index >= 0 and index < machine.debugger_watches.size() else WATCH_ENTRY.new()
	if not WATCH_CONFIG.valid(entry): return
	watch_validation.text = ""
	watch_dialog.title = "Edit Watch" if index >= 0 else "Add Watch"
	watch_name.text = entry.display_name
	watch_target.select(int(entry.target_mode))
	watch_node_path.machine = machine
	watch_node_path.set_context(interface, machine, entry.target_path)
	watch_property.text = String(entry.property_path)
	watch_enabled.button_pressed = entry.enabled
	_watch_target_changed(int(entry.target_mode))
	watch_dialog.popup_centered(Vector2i(430, 260))


func _save_watch_dialog() -> void:
	if not is_instance_valid(machine):
		return
	var name := watch_name.text.strip_edges()
	var property := watch_property.text.strip_edges()
	if name.is_empty() or property.is_empty():
		watch_validation.text = "Enter a display name and a property path before saving."
		return
	var mode: int = _selected_watch_target_mode()
	if mode == -1:
		watch_validation.text = "Choose Actor, Node Path or FSM as the Watch target."
		return
	if watch_edit_index < 0 and machine.debugger_watches.size() >= WATCH_CONFIG.MAX_WATCHES:
		watch_validation.text = "Live Debug supports 32 Watches per FSM. Remove a Watch before adding another."
		return
	var after: Array[Resource] = machine.debugger_watches.duplicate()
	var entry = WATCH_ENTRY.new()
	if watch_edit_index >= 0 and watch_edit_index < after.size():
		if not WATCH_CONFIG.valid(after[watch_edit_index]):
			watch_validation.text = "This Watch resource changed. Close the dialog and select it again."
			return
		entry = after[watch_edit_index].duplicate(true)
	entry.display_name = name.left(256)
	entry.target_mode = mode
	entry.target_path = NodePath(watch_node_path.field.text) if entry.target_mode == 1 else NodePath()
	entry.property_path = NodePath(property)
	entry.enabled = watch_enabled.button_pressed
	if watch_edit_index >= 0 and watch_edit_index < after.size():
		after[watch_edit_index] = entry
	else:
		after.append(entry)
	_commit_watch_configuration("Edit Watch" if watch_edit_index >= 0 else "Add Watch", after)
	watch_dialog.hide()


func _commit_watch_configuration(title: String, after: Array[Resource]) -> void:
	var before: Array[Resource] = machine.debugger_watches.duplicate()
	if undo_manager != null:
		undo_manager.create_action(title, UndoRedo.MERGE_DISABLE, machine.get_state_container())
		undo_manager.add_do_property(machine, &"debugger_watches", after)
		undo_manager.add_undo_property(machine, &"debugger_watches", before)
		undo_manager.commit_action()
	else:
		machine.debugger_watches = after
		if is_instance_valid(interface):
			interface.mark_scene_as_unsaved()
	watch_signature = ""
	refresh()


func _selected_watch_target_mode() -> int:
	if watch_target.selected < 0:
		return -1
	var mode: int = watch_target.get_selected_id()
	if mode not in [WATCH_ENTRY.TargetMode.ACTOR, WATCH_ENTRY.TargetMode.NODE_PATH, WATCH_ENTRY.TargetMode.FSM]:
		return -1
	var metadata: Variant = watch_target.get_selected_metadata()
	if metadata == null:
		return mode
	return mode if metadata is int and metadata == mode else -1


func _refresh_watch_rows(current: Dictionary) -> void:
	var signature := ""
	if is_instance_valid(machine):
		signature = str(machine.get_instance_id())
		for entry in machine.debugger_watches:
			signature += "|" + str(WATCH_CONFIG.definition(entry)) + str(entry.get_instance_id() if entry != null else 0)
	var values: Dictionary = current.get("watch_values", {})
	if signature == watch_render_signature:
		for index in watch_value_labels.size():
			var text: String = "—" if not WATCH_CONFIG.definition(machine.debugger_watches[index]).enabled or not values.has(index) else str(values[index].value)
			if watch_value_labels[index].text != text:
				watch_value_labels[index].text = text
				watch_value_labels[index].tooltip_text = text
		return
	watch_render_signature = signature
	watch_value_labels.clear()
	for child in watch_rows.get_children():
		watch_rows.remove_child(child)
		child.queue_free()
	if not is_instance_valid(machine):
		return
	for index in machine.debugger_watches.size():
		var entry = machine.debugger_watches[index]
		var definition := WATCH_CONFIG.definition(entry)
		var row := HBoxContainer.new()
		watch_rows.add_child(row)
		var label := Label.new()
		label.text = definition.name
		label.custom_minimum_size.x = 70
		label.tooltip_text = definition.target + "/" + definition.property if definition.mode == 1 else definition.property
		row.add_child(label)
		var value := Label.new()
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.text = "—" if not definition.enabled or values.is_empty() or not values.has(index) else values[index].value
		value.tooltip_text = value.text
		row.add_child(value)
		watch_value_labels.append(value)
		if not WATCH_CONFIG.valid(entry):
			label.tooltip_text = "Missing or unsupported Watch resource. Delete this row and add a Watch to repair it."
			var repair := Button.new()
			repair.text = "×"
			repair.tooltip_text = "Delete invalid Watch (Undo available)"
			repair.pressed.connect(func():
				if not is_instance_valid(machine) or index >= machine.debugger_watches.size(): return
				var updated: Array[Resource] = machine.debugger_watches.duplicate()
				updated.remove_at(index)
				_commit_watch_configuration("Delete Invalid Watch", updated))
			row.add_child(repair)
			continue
		var toggle := CheckButton.new()
		toggle.button_pressed = entry.enabled
		toggle.tooltip_text = "Enable or disable this Watch"
		toggle.toggled.connect(func(enabled):
			var updated: Array[Resource] = machine.debugger_watches.duplicate()
			updated[index] = updated[index].duplicate(true)
			updated[index].enabled = enabled
			_commit_watch_configuration("Enable Watch" if enabled else "Disable Watch", updated))
		row.add_child(toggle)
		var edit := Button.new()
		edit.text = "Edit"
		edit.pressed.connect(_open_watch_dialog.bind(index))
		row.add_child(edit)
		var remove := Button.new()
		remove.text = "×"
		remove.tooltip_text = "Delete Watch"
		remove.pressed.connect(func():
			var updated: Array[Resource] = machine.debugger_watches.duplicate()
			updated.remove_at(index)
			_commit_watch_configuration("Delete Watch", updated))
		row.add_child(remove)
		# Keep the existing action signals as the single authoring path.
		toggle.hide()
		edit.hide()
		remove.hide()
		var menu := MenuButton.new()
		menu.text = "…"
		menu.tooltip_text = "Watch actions"
		menu.get_popup().add_item("Edit", 0)
		menu.get_popup().add_item("Disable" if entry.enabled else "Enable", 1)
		menu.get_popup().add_item("Delete", 2)
		menu.get_popup().id_pressed.connect(func(id):
			if id == 0: edit.pressed.emit()
			elif id == 1: toggle.button_pressed = not toggle.button_pressed
			elif id == 2: remove.pressed.emit())
		row.add_child(menu)


func _sync_watch_subscription() -> void:
	if debugger == null:
		return
	var definitions: Array[Dictionary] = []
	if is_instance_valid(machine):
		definitions = WATCH_CONFIG.definitions(machine.debugger_watches)
	var hz := int(watch_rate_picker.get_selected_metadata()) if is_instance_valid(watch_rate_picker) else 10
	var signature := "%s|%s|%s|%s" % [selected_session, selected_id, str(definitions), hz]
	if signature == watch_signature:
		return
	watch_signature = signature
	debugger.update_watch_subscription(selected_session, selected_id, definitions, hz)
