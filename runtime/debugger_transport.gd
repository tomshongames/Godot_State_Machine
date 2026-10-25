extends RefCounted

const LABELS := preload("res://addons/state_machine/runtime/transition_labels.gd")
const PROPERTY := preload("res://addons/state_machine/runtime/property_comparison.gd")
const DECISIONS := preload("res://addons/state_machine/runtime/decision_data.gd")
const PREFIX := &"state_machine_live"
const VERSION := 1
const BATCH_SIZE := 64
const MAX_WATCHES := 32
const MAX_WATCH_TEXT := 256
static var instances: Dictionary = {}
static var activation := 0
static var listening := false
static var waiting_for_listener := true
static var listener_deadline_usec := 0
static var pending: Array[Dictionary] = []
static var scheduled := false
static var watch_subscriptions: Dictionary = {}
static var trace_target := ""
static var run_identity := ""

static func tracing(machine: Node) -> bool:
	if trace_target.is_empty() or not listening or not available(): return false
	var cursor = machine
	for depth in 32:
		if not is_instance_valid(cursor): return false
		if cursor._debug_id == trace_target: return true
		cursor = cursor.parent_fsm
	return false

static func decision(id: String, data: Dictionary) -> void:
	if id.is_empty() or not available() or not listening or not instances.has(id) or data.candidates.is_empty(): return
	var entry: Dictionary = instances[id]
	var record := snapshot(id)
	if record.is_empty(): return
	if not prepare_decision(entry, data, Time.get_ticks_usec()): return
	record.kind = "decision"
	record.decision = data
	_enqueue(record)

static func prepare_decision(entry: Dictionary, data: Dictionary, now_usec: int) -> bool:
	var key := decision_signature(data)
	var last: Dictionary = entry.get("decision_last", {})
	var committed: bool = data.candidates.any(func(candidate): return candidate.committed)
	var repeated: bool = data.request == "Frame" and not committed and not last.is_empty() and last.signature == key
	if repeated:
		data.decision_sequence = last.sequence
		data.repeat_count = last.count + 1
		last.count = data.repeat_count
		if now_usec - last.sent < 250000: return false
	else:
		entry.decision_sequence = int(entry.get("decision_sequence", 0)) + 1
		data.decision_sequence = entry.decision_sequence
		data.repeat_count = 1
	entry.decision_last = {"signature": key, "sequence": data.decision_sequence, "count": data.repeat_count, "sent": now_usec}
	return true

static func decision_signature(data: Dictionary) -> String:
	var items := [data.request]
	for candidate in data.candidates:
		items.append([candidate.route_key, candidate.actual_state, candidate.reason, candidate.result,
			candidate.selected, candidate.trigger.get("status"), candidate.trigger.get("actual", {}), candidate.conditions])
	return str(items).sha256_text()


static func available() -> bool:
	return not Engine.is_editor_hint() and OS.is_debug_build() and EngineDebugger.is_active()


static func register_fsm(machine: Node) -> String:
	if not available():
		return ""
	var first := not EngineDebugger.has_capture(PREFIX)
	if first:
		run_identity = "%s-%s-%s" % [OS.get_process_id(), int(Time.get_unix_time_from_system() * 1000000.0), Time.get_ticks_usec()]
		EngineDebugger.register_message_capture(PREFIX, _capture)
		listener_deadline_usec = Time.get_ticks_usec() + 2000000
	activation += 1
	var id := "%s:%s:%s" % [run_identity, machine.get_instance_id(), activation]
	instances[id] = {"node": weakref(machine), "sequence": 0, "last": {}}
	if first:
		EngineDebugger.send_message("state_machine_live:hello", [VERSION])
	if _wants_records():
		_enqueue(snapshot(id))
	return id


static func transitioned(id: String, from: String, transition: StateTransition, boundary_to := "", description_override := "") -> void:
	if id.is_empty() or not available() or not instances.has(id):
		return
	var entry: Dictionary = instances[id]
	entry.sequence += 1
	if not _wants_records():
		entry.last = {}
		return
	var machine: Node = entry.node.get_ref()
	if not is_instance_valid(machine):
		return
	entry.last = {
		"from": from, "to": boundary_to if not boundary_to.is_empty() else String(machine.get_current_state_name()),
		"trigger": int(transition.trigger_type) if transition != null else 0,
		"description": (description_override if not description_override.is_empty() else LABELS.trigger_description(transition)).left(512),
		"transition_index": machine.transitions.find(transition) if transition != null else -1,
		"any_state": transition != null and transition.source_mode == StateTransition.SourceMode.ANY_STATE,
		"sequence": entry.sequence, "time_usec": Time.get_ticks_usec(),
	}
	var record := snapshot(id)
	record.kind = "transition"
	_enqueue(record)


static func removed(id: String) -> void:
	if id.is_empty() or not instances.has(id):
		return
	if available() and _wants_records():
		_enqueue({"kind": "removed", "id": id, "alive": false})
	instances.erase(id)
	watch_subscriptions.erase(id)
	if trace_target == id: trace_target = ""


static func hierarchy_changed(machine: Node) -> void:
	if not available() or not _wants_records():
		return
	var visited := {}
	while is_instance_valid(machine) and not visited.has(machine):
		visited[machine] = true
		if not machine.is_active() and watch_subscriptions.has(machine._debug_id):
			watch_subscriptions[machine._debug_id].last = {}
			watch_subscriptions[machine._debug_id].elapsed = 0.0
		_enqueue(snapshot(machine._debug_id))
		machine = machine.parent_fsm


static func _wants_records() -> bool:
	if listening:
		return true
	if waiting_for_listener and Time.get_ticks_usec() <= listener_deadline_usec:
		return true
	waiting_for_listener = false
	pending.clear()
	return false


static func snapshot(id: String) -> Dictionary:
	if not instances.has(id):
		return {}
	var entry: Dictionary = instances[id]
	var machine: Node = entry.node.get_ref()
	if not is_instance_valid(machine) or not machine.is_inside_tree():
		return {}
	var source := LABELS.source_identity(machine)
	return {
		"kind": "snapshot", "id": id, "path": String(machine.get_path()),
		"actor_path": String(machine.actor.get_path()) if is_instance_valid(machine.actor) and machine.actor.is_inside_tree() else "",
		"scene": source.scene, "local_path": source.local_path,
		"current": String(machine.get_current_state_name()),
		"previous": String(machine.previous_state.name) if is_instance_valid(machine.previous_state) else "",
		"active": machine.is_active(), "active_path": machine.get_active_state_path(),
		"previous_path": machine.previous_active_path,
		"parent_id": machine.parent_fsm._debug_id if is_instance_valid(machine.parent_fsm) else "",
		"owner_state": String(machine.owner_state.name) if is_instance_valid(machine.owner_state) else "",
		"sequence": entry.sequence, "time_usec": Time.get_ticks_usec(), "alive": true,
		"state_elapsed": machine.get_current_state_elapsed(),
		"last": entry.last.duplicate(),
	}


static func _capture(message: String, data: Array) -> bool:
	if message not in ["subscribe", "snapshot", "unsubscribe", "watch_subscribe", "watch_unsubscribe", "trace_subscribe"]:
		return false
	if message == "trace_subscribe":
		if data.size() == 2 and data[0] is int and data[0] == VERSION and data[1] is String and data[1].length() <= 128 and listening and (data[1].is_empty() or instances.has(data[1])):
			trace_target = data[1]
		return true
	if message == "watch_subscribe":
		if data.size() != 4 or typeof(data[0]) != TYPE_INT or data[0] != VERSION or not data[1] is String or not data[2] is Array or typeof(data[3]) != TYPE_INT:
			return true
		if not listening or not instances.has(data[1]):
			return true
		var definitions: Array[Dictionary] = []
		for entry in data[2].slice(0, MAX_WATCHES):
			if not entry is Dictionary or not entry.get("name", "") is String or not entry.get("mode", -1) is int or not entry.get("target", "") is String or not entry.get("property", "") is String or not entry.get("enabled", false) is bool:
				continue
			if entry.name.length() > MAX_WATCH_TEXT or entry.target.length() > 4096 or entry.property.length() > MAX_WATCH_TEXT:
				continue
			if entry.mode not in [0, 1, 2]:
				continue
			definitions.append({"name": entry.name, "mode": entry.mode, "target": entry.target, "property": entry.property, "enabled": entry.enabled})
		var hz := clampi(data[3], 5, 20)
		watch_subscriptions[data[1]] = {"watches": definitions, "interval": 1.0 / float(hz), "elapsed": 0.0, "last": {}}
		return true
	if message == "watch_unsubscribe":
		if data.size() == 2 and typeof(data[0]) == TYPE_INT and data[0] == VERSION and data[1] is String:
			watch_subscriptions.erase(data[1])
		return true
	if data.size() != 1 or typeof(data[0]) != TYPE_INT or data[0] != VERSION:
		return true
	if message == "unsubscribe":
		listening = false
		waiting_for_listener = false
		pending.clear()
		watch_subscriptions.clear()
		trace_target = ""
		return true
	listening = true
	waiting_for_listener = false
	for id in instances.keys():
		var record := snapshot(id)
		if record.is_empty():
			instances.erase(id)
		else:
			_enqueue(record)
	return true


static func sample_watches(id: String, delta: float) -> void:
	if id.is_empty() or not available() or not listening or not watch_subscriptions.has(id) or not instances.has(id):
		return
	var subscription: Dictionary = watch_subscriptions[id]
	subscription.elapsed += maxf(delta, 0.0)
	if subscription.elapsed < subscription.interval:
		return
	subscription.elapsed = fmod(subscription.elapsed, subscription.interval)
	var entry: Dictionary = instances[id]
	var machine: Node = entry.node.get_ref()
	if not is_instance_valid(machine):
		return
	var updates: Array[Dictionary] = []
	for index in subscription.watches.size():
		var watch: Dictionary = subscription.watches[index]
		if not watch.enabled:
			continue
		var value_text := _sample_watch(machine, watch)
		var cache_key := str(index)
		if subscription.last.get(cache_key, null) == value_text:
			continue
		subscription.last[cache_key] = value_text
		updates.append({"index": index, "name": watch.name, "value": value_text})
	if not updates.is_empty():
		_enqueue({"kind": "watch_values", "id": id, "values": updates, "time_usec": Time.get_ticks_usec()})

static func sample_state(id: String, delta: float) -> void:
	if id.is_empty() or not instances.has(id) or trace_target.is_empty(): return
	var entry: Dictionary = instances[id]
	var machine = entry.node.get_ref()
	if not tracing(machine): return
	entry.state_sample_elapsed = float(entry.get("state_sample_elapsed", 0.0)) + maxf(delta, 0.0)
	if entry.state_sample_elapsed >= 0.1:
		entry.state_sample_elapsed = 0.0
		_enqueue(snapshot(id))


static func _sample_watch(machine: Node, watch: Dictionary) -> String:
	if watch.mode == 2:
		match watch.property:
			"current_state", "current_state_name":
				return String(machine.get_current_state_name()) if is_instance_valid(machine.current_state) else "<missing>"
			"previous_state", "previous_state_name":
				return String(machine.previous_state.name) if is_instance_valid(machine.previous_state) else "<null>"
		return "<invalid FSM property>"
	if not is_instance_valid(machine.actor):
		return "<missing actor>"
	var target := PROPERTY.target(machine.actor, watch.mode, NodePath(watch.target))
	if not is_instance_valid(target):
		return "<missing node>"
	var result := PROPERTY.read(target, NodePath(watch.property))
	if not result.valid:
		if result.reason.contains("unavailable") or result.reason.contains("missing") or result.reason.contains("Invalid"):
			return "<missing property>"
		return "<invalid>"
	return format_watch_value(result.value)


static func format_watch_value(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool or typeof(value) == TYPE_INT:
		return str(value)
	if typeof(value) == TYPE_FLOAT:
		return str(snappedf(value, 0.0001)) if is_finite(value) else "<non-finite>"
	if value is String or value is StringName:
		return '"%s"' % String(value).left(96)
	if value is Vector2 or value is Vector2i or value is Vector3 or value is Vector3i or value is Vector4 or value is Vector4i or value is Color:
		return str(value).left(128)
	if value is Array:
		return "<Array: %d>" % value.size()
	if value is Dictionary:
		return "<Dictionary: %d>" % value.size()
	if value is Node:
		return "<Node: %s>" % value.name
	if value is Resource:
		return "<Resource: %s>" % value.get_class()
	if value is Object:
		return "<Object: %s>" % value.get_class()
	return "<%s>" % type_string(typeof(value))


static func _enqueue(record: Dictionary) -> void:
	if record.is_empty():
		return
	pending.append(record)
	# Bounded startup/delivery queue, never gameplay history. Resync is current state.
	if pending.size() > 2048:
		pending.pop_front()
	if not scheduled:
		scheduled = true
		_flush.call_deferred()


static func _flush() -> void:
	scheduled = false
	if not available():
		pending.clear()
		return
	if not listening:
		return
	while not pending.is_empty():
		var batch: Array = pending.slice(0, BATCH_SIZE)
		pending = pending.slice(batch.size())
		EngineDebugger.send_message("state_machine_live:records", [VERSION, batch])
