@tool
extends EditorDebuggerPlugin

const MODEL := preload("res://addons/state_machine/editor/debugger_model.gd")
const VERSION := 1
var model = MODEL.new()
var bindings: Array[Dictionary] = []
var message_counts: Dictionary = {}
var watch_target: Dictionary = {}
var watch_definitions: Array[Dictionary] = []
var watch_rate := 10
var shutting_down := false
var trace_target: Dictionary = {}

func update_trace_subscription(session_id: int, instance_id: String) -> void:
	if shutting_down: return
	var next := {"session": session_id, "id": instance_id} if session_id >= 0 and not instance_id.is_empty() else {}
	if next == trace_target: return
	if not trace_target.is_empty() and model.sessions.has(trace_target.session):
		get_session(trace_target.session).send_message("state_machine_live:trace_subscribe", [VERSION, ""])
	trace_target = next
	_send_trace_subscription()

func _send_trace_subscription() -> void:
	if not trace_target.is_empty() and model.sessions.has(trace_target.session):
		get_session(trace_target.session).send_message("state_machine_live:trace_subscribe", [VERSION, trace_target.id])


func _has_capture(capture: String) -> bool:
	return capture == "state_machine_live"


func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	_bind(session.started, _started.bind(session_id))
	_bind(session.stopped, _stopped.bind(session_id))
	_bind(session.breaked, _breaked.bind(session_id))
	_bind(session.continued, _continued.bind(session_id))
	if session.is_active():
		_started(session_id)


func _bind(event: Signal, callback: Callable) -> void:
	event.connect(callback)
	bindings.append({"event": event, "callback": callback})


func _started(id: int) -> void:
	if shutting_down: return
	message_counts[id] = 0
	model.start_session(id)
	model.set_paused(id, get_session(id).is_breaked())
	get_session(id).send_message("state_machine_live:subscribe", [VERSION])
	if not watch_target.is_empty() and watch_target.session == id:
		_send_watch_subscription()
	_send_trace_subscription()


func _stopped(id: int) -> void:
	if not trace_target.is_empty() and trace_target.session == id: trace_target.clear()
	message_counts.erase(id)
	model.stop_session(id)
	if not watch_target.is_empty() and watch_target.session == id:
		watch_target.clear()


func _breaked(_can_debug: bool, id: int) -> void:
	model.set_paused(id, true)


func _continued(id: int) -> void:
	model.set_paused(id, false)


func _capture(message: String, data: Array, session_id: int) -> bool:
	if shutting_down: return false
	if message == "state_machine_live:hello":
		if data.size() == 1 and typeof(data[0]) == TYPE_INT and data[0] == VERSION and get_session(session_id).is_active():
			get_session(session_id).send_message("state_machine_live:subscribe", [VERSION])
		return true
	if message != "state_machine_live:records":
		return false
	if data.size() != 2 or typeof(data[0]) != TYPE_INT or data[0] != VERSION or not data[1] is Array or data[1].size() > 64:
		return true
	if model.sessions.has(session_id):
		message_counts[session_id] = message_counts.get(session_id, 0) + 1
	for record in data[1]:
		if record is Dictionary:
			if record.get("kind", "") == "watch_values" and (watch_target.is_empty() or watch_target.session != session_id or watch_target.id != record.get("id", "")):
				continue
			model.receive(session_id, record)
	return true


func request_snapshots() -> void:
	if shutting_down: return
	for session in get_sessions():
		if session.is_active():
			session.send_message("state_machine_live:snapshot", [VERSION])
	if not watch_target.is_empty():
		_send_watch_subscription()
	_send_trace_subscription()


func update_watch_subscription(session_id: int, instance_id: String, definitions: Array[Dictionary], hz: int) -> void:
	if shutting_down: return
	var next := {"session": session_id, "id": instance_id} if session_id >= 0 and not instance_id.is_empty() else {}
	var same_target := not watch_target.is_empty() and watch_target == next
	if not same_target and not watch_target.is_empty():
		var old_session: int = watch_target.session
		model.clear_watch_values(old_session, watch_target.id)
		if model.sessions.has(old_session):
			get_session(old_session).send_message("state_machine_live:watch_unsubscribe", [VERSION, watch_target.id])
	watch_target = next
	watch_definitions = definitions.duplicate(true)
	watch_rate = clampi(hz, 5, 20)
	if watch_target.is_empty():
		return
	model.clear_watch_values(watch_target.session, watch_target.id)
	_send_watch_subscription()


func _send_watch_subscription() -> void:
	if watch_target.is_empty() or not model.sessions.has(watch_target.session):
		return
	get_session(watch_target.session).send_message("state_machine_live:watch_subscribe", [VERSION, watch_target.id, watch_definitions, watch_rate])


func shutdown() -> void:
	if shutting_down: return
	shutting_down = true
	trace_target.clear()
	if not watch_target.is_empty() and model.sessions.has(watch_target.session):
		get_session(watch_target.session).send_message("state_machine_live:watch_unsubscribe", [VERSION, watch_target.id])
	watch_target.clear()
	for id in model.sessions.keys():
		var session := get_session(id)
		if session.is_active():
			session.send_message("state_machine_live:unsubscribe", [VERSION])
	for pair in bindings:
		if pair.event.is_connected(pair.callback):
			pair.event.disconnect(pair.callback)
	bindings.clear()
	for id in model.sessions.keys():
		_stopped(id)
