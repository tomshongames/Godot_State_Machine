@tool
extends RefCounted

signal changed(session_id: int, instance_id: String, kind: String)
const HISTORY_LIMIT := 20
const DECISIONS := preload("res://addons/state_machine/runtime/decision_data.gd")
var sessions: Dictionary = {}


func start_session(id: int) -> void:
	sessions[id] = {"active": true, "paused": false, "instances": {}, "history": {}, "decisions": {}, "decision_sequences": {}}
	changed.emit(id, "", "started")


func stop_session(id: int) -> void:
	sessions.erase(id)
	changed.emit(id, "", "stopped")


func set_paused(id: int, paused: bool) -> void:
	if sessions.has(id):
		sessions[id].paused = paused
		changed.emit(id, "", "paused")


func receive(id: int, record: Dictionary) -> void:
	if not sessions.has(id) or not record.get("id") is String:
		return
	var key: String = record.id
	if key.is_empty() or key.length() > 128:
		return
	var session: Dictionary = sessions[id]
	var kind: String = str(record.get("kind", ""))
	if kind == "decision":
		if not record.get("decision") is Dictionary or not DECISIONS.valid(record.decision) or not session.instances.has(key): return
		if record.has("sequence") and (not record.sequence is int or record.sequence < session.instances[key].sequence): return
		if record.has("current"):
			var snapshot := record.duplicate()
			snapshot.kind = "snapshot"
			snapshot.erase("decision")
			receive(id, snapshot)
		var data: Dictionary = record.decision
		var sequence: int = session.decision_sequences.get(key, 0)
		if data.decision_sequence < sequence: return
		if not session.decisions.has(key): session.decisions[key] = []
		var history: Array = session.decisions[key]
		var safe: Dictionary = data.duplicate(true)
		safe.id = key
		safe.session_id = id
		safe.scene = session.instances[key].scene
		safe.local_path = session.instances[key].local_path
		safe.path = session.instances[key].path
		if data.decision_sequence == sequence:
			if history.is_empty() or history.back().decision_sequence != sequence or data.repeat_count <= history.back().repeat_count: return
			history[history.size() - 1] = safe
		else:
			history.append(safe)
			if history.size() > DECISIONS.HISTORY_LIMIT: history.pop_front()
		session.decision_sequences[key] = data.decision_sequence
		changed.emit(id, key, kind)
		return
	if kind == "watch_values":
		if not session.instances.has(key) or not record.get("time_usec") is int or not record.get("values") is Array or record.values.size() > 32:
			return
		# Reject a malformed batch without partially mutating the last good snapshot.
		var watched: Dictionary = session.instances[key].get("watch_values", {}).duplicate()
		for value in record.values:
			if not value is Dictionary or not value.get("index", -1) is int or value.index < 0 or value.index >= 32 or not value.get("name", "") is String or value.name.length() > 256 or not value.get("value", "") is String or value.value.length() > 256:
				return
			watched[value.index] = {"name": value.name, "value": value.value}
		session.instances[key].watch_values = watched
		changed.emit(id, key, kind)
		return
	if kind == "removed":
		session.instances.erase(key)
		session.history.erase(key)
		session.decisions.erase(key)
		session.decision_sequences.erase(key)
		changed.emit(id, key, kind)
		return
	if kind not in ["snapshot", "transition"]:
		return
	for field in ["path", "actor_path", "scene", "local_path", "current", "previous"]:
		if not record.get(field) is String or record[field].length() > 4096:
			return
	if not record.get("sequence") is int or record.sequence < 0 or not record.get("time_usec") is int or not record.get("last") is Dictionary:
		return
	var old: Dictionary = session.instances.get(key, {})
	if not old.is_empty() and record.sequence < old.sequence:
		return
	var safe := {"id": key, "session_id": id, "kind": kind, "alive": true, "sequence": record.sequence, "time_usec": record.time_usec, "last": {}, "watch_values": old.get("watch_values", {}).duplicate()}
	for field in ["path", "actor_path", "scene", "local_path", "current", "previous"]:
		safe[field] = record[field]
	for field in ["active_path", "previous_path", "parent_id", "owner_state"]:
		if not record.get(field, "") is String or record.get(field, "").length() > 4096:
			return
		safe[field] = record.get(field, "")
	if not record.get("active", true) is bool:
		return
	safe.active = record.get("active", true)
	if not record.get("state_elapsed", 0.0) is float and not record.get("state_elapsed", 0.0) is int: return
	safe.state_elapsed = float(record.get("state_elapsed", 0.0))
	if not is_finite(safe.state_elapsed) or safe.state_elapsed < 0.0: return
	if not safe.active:
		safe.watch_values = {}
	var last: Dictionary = record.last
	if not last.is_empty():
		for field in ["from", "to", "description"]:
			if not last.get(field) is String or last[field].length() > 512:
				return
		for field in ["trigger", "transition_index", "sequence", "time_usec"]:
			if not last.get(field) is int:
				return
		safe.last = {"from": last.from, "to": last.to, "description": last.description, "trigger": last.trigger, "transition_index": last.transition_index, "sequence": last.sequence, "time_usec": last.time_usec}
		if not last.get("any_state", false) is bool: return
		safe.last.any_state = last.get("any_state", false)
	session.instances[key] = safe
	if not session.history.has(key):
		session.history[key] = []
	if kind == "transition" and not safe.last.is_empty():
		var history: Array = session.history[key]
		# Snapshots/duplicates never recreate cleared history or repeat a transition.
		if old.is_empty() or record.sequence > old.sequence:
			history.append(safe.last.duplicate())
			if history.size() > HISTORY_LIMIT:
				history.pop_front()
	changed.emit(id, key, "snapshot" if kind == "transition" and not old.is_empty() and record.sequence == old.sequence else kind)


func get_instance(session_id: int, id: String) -> Dictionary:
	return sessions.get(session_id, {}).get("instances", {}).get(id, {})


func get_history(session_id: int, id: String) -> Array:
	return sessions.get(session_id, {}).get("history", {}).get(id, [])


func clear_history(session_id: int, id: String) -> void:
	if sessions.has(session_id):
		sessions[session_id].history.erase(id)
		sessions[session_id].decisions.erase(id)
		changed.emit(session_id, id, "history_cleared")

func get_decisions(session_id: int, id: String) -> Array:
	return sessions.get(session_id, {}).get("decisions", {}).get(id, [])


func clear_watch_values(session_id: int, id: String) -> void:
	if sessions.has(session_id) and sessions[session_id].instances.has(id):
		sessions[session_id].instances[id].watch_values = {}
		changed.emit(session_id, id, "watch_values")
