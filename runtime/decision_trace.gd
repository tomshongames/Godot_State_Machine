extends RefCounted

const DATA := preload("res://addons/state_machine/runtime/decision_data.gd")
var previous
var candidates: Array[Dictionary] = []
var by_route := {}
var request := ""
var frame := Engine.get_process_frames()
var time_usec := Time.get_ticks_usec()
var state_elapsed := 0.0
var truncated := false
var outcome := false
var condition_budget := [128]

func candidate(machine, route: StateTransition) -> Dictionary:
	var key := route.get_instance_id() if route != null else 0
	if by_route.has(key): return by_route[key]
	if candidates.size() >= DATA.MAX_CANDIDATES:
		truncated = true
		return {}
	var item := {"route_index": machine.transitions.find(route), "route_path": route.resource_path if route != null else "",
		"route_key": DATA.route_key(route), "route_id": str(key), "from": route.source_label() if route != null else String(machine.get_current_state_name()),
		"to": route.target_label().left(512) if route != null else "", "actual_state": String(machine.get_current_state_name()),
		"source_mode": int(route.source_mode) if route != null else 0, "destination_mode": int(route.destination_mode) if route != null else 0,
		"trigger_type": int(route.trigger_type) if route != null else 0, "priority": route.priority if route != null else 0,
		"reenter": route.reenter_state if route != null else true, "eligible": false, "selected": false,
		"committed": false, "assignment_committed": false, "reason": "", "result": "BLOCKED",
		"trigger": {"status": "SKIPPED"}, "conditions": {"status": "SKIPPED"}, "policies": {"status": "SKIPPED"},
		"effects": [], "order": []}
	by_route[key] = item
	candidates.append(item)
	return item

func blocked(machine, route, reason: String) -> void:
	var item := candidate(machine, route)
	if not item.is_empty(): item.reason = reason

func trigger(machine, route, matched: bool, details: Dictionary = {}) -> void:
	var item := candidate(machine, route)
	if item.is_empty(): return
	item.trigger = details.duplicate(true)
	item.trigger.status = "PASSED" if matched else "FAILED"
	if not matched: item.reason = "TRIGGER_NOT_MET"

func select(machine, chosen: StateTransition) -> void:
	if chosen != null and not by_route.has(chosen.get_instance_id()) and candidates.size() >= DATA.MAX_CANDIDATES:
		var removed: Dictionary = candidates.pop_back()
		by_route.erase(int(removed.route_id))
	var winner := candidate(machine, chosen) if chosen != null else {}
	for item in candidates:
		if item.reason.is_empty():
			item.eligible = true
			item.result = "ELIGIBLE"
			item.selected = item == winner
			if not item.selected and not winner.is_empty():
				item.reason = "LOWER_PRIORITY" if item.priority < winner.priority else "AUTHORED_ORDER"
				item.winner = {"from": winner.from, "to": winner.to, "priority": winner.priority, "route_index": winner.route_index}

func finish(success: bool) -> Dictionary:
	for item in candidates:
		if item.selected:
			item.committed = success
			item.result = "COMMITTED" if success else ("COMMIT_INTERRUPTED" if item.assignment_committed or not item.effects.is_empty() or item.reason.is_empty() or item.reason == "COMMIT_INTERRUPTED" else "BLOCKED")
			if not success and item.reason.is_empty(): item.reason = "COMMIT_INTERRUPTED"
	return {"schema": 1, "request": request, "frame": frame, "time_usec": time_usec,
		"state_elapsed": state_elapsed, "candidates": candidates, "truncated": truncated}
