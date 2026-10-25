@tool
extends RefCounted

const MAX_CANDIDATES := 128
const MAX_NODES := 128
const HISTORY_LIMIT := 100
const REASONS := ["", "DISABLED", "INVALID_SOURCE", "INVALID_TARGET", "TRIGGER_NOT_MET", "CONDITION_FAILED", "MINIMUM_STATE_TIME", "COOLDOWN", "STATE_NOT_INTERRUPTIBLE", "CANNOT_INTERRUPT", "LOWER_PRIORITY", "AUTHORED_ORDER", "TRANSITION_EXECUTING", "FSM_INACTIVE", "INVALID_POLICY", "COMMIT_INTERRUPTED", "NO_PARENT_ROUTE", "EVALUATION_REENTRANCY"]

static func value(raw: Variant) -> Dictionary:
	var type := typeof(raw)
	var text := ""
	if type == TYPE_OBJECT:
		text = "<freed Object>" if not is_instance_valid(raw) else "<%s #%s>" % [raw.get_class(), raw.get_instance_id()]
	elif raw is Array or raw is Dictionary: text = "<%s: %d>" % [type_string(type), raw.size()]
	else: text = str(raw).left(256)
	return {"type": type, "text": text}

static func route_key(route: StateTransition) -> String:
	if route == null: return ""
	var conditions := []
	for condition in route.conditions: conditions.append(_condition_key(condition, {}))
	conditions.append(_condition_key(route.condition_group, {}))
	return str([route.source_mode, route.destination_mode, route.from_state, route.to_state,
		route.trigger_type, route.event_name, route.duration, route.input_action, route.input_mode,
		route.animation_player_path, route.animation_name, route.priority, route.reenter_state,
		route.cooldown, route.can_interrupt, route.signal_source_mode, route.signal_source_path,
		route.signal_name, route.target_mode, route.target_label(), route.random_routing.mode if route.random_routing != null else -1, _routing_key(route), conditions, _condition_key(route.watch, {})]).sha256_text()

static func _condition_key(node, visited: Dictionary, depth := 0) -> Variant:
	if node == null: return null
	if visited.has(node) or depth > 16: return "<cycle or depth limit>"
	visited[node] = true
	if node is TransitionCondition:
		return [node.enabled, node.negated, node.target_mode, node.target_path, node.property_path, node.comparison_operator, value(node.comparison_value)]
	if node is TransitionConditionGroup:
		var children := []
		for child in node.children.slice(0, 128): children.append(_condition_key(child, visited, depth + 1))
		visited.erase(node)
		return [node.enabled, node.operator, node.negated, children]
	return "<invalid condition>"

# Reject objects, oversized/deep payloads and malformed schemas before storing.
static func wire_safe(raw: Variant, depth := 0, budget: Array = [30000]) -> bool:
	budget[0] -= 1
	if budget[0] < 0 or depth > 64: return false
	if raw is String: return raw.length() <= 4096
	if raw is Array:
		if raw.size() > 512: return false
		for child in raw:
			if not wire_safe(child, depth + 1, budget): return false
		return true
	if raw is Dictionary:
		if raw.size() > 128: return false
		for key in raw:
			if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not wire_safe(raw[key], depth + 1, budget): return false
		return true
	return typeof(raw) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT] and (not raw is float or is_finite(raw))

static func valid(record: Dictionary) -> bool:
	if not wire_safe(record) or record.get("schema") != 1: return false
	for field in ["decision_sequence", "time_usec", "frame", "repeat_count"]:
		if not record.get(field) is int or record[field] < 0: return false
	if not record.get("candidates") is Array or record.candidates.size() > MAX_CANDIDATES: return false
	for candidate in record.candidates:
		if not candidate is Dictionary: return false
		for field in ["route_index", "priority", "source_mode", "destination_mode", "trigger_type"]:
			if not candidate.get(field) is int: return false
		for field in ["from", "to", "actual_state", "route_path", "route_key", "reason", "result"]:
			if not candidate.get(field) is String: return false
		if candidate.reason not in REASONS or candidate.result not in ["BLOCKED", "ELIGIBLE", "COMMITTED", "COMMIT_INTERRUPTED"]: return false
		for field in ["eligible", "selected", "committed", "assignment_committed", "reenter"]:
			if not candidate.get(field) is bool: return false
		for field in ["trigger", "conditions", "policies"]:
			if not candidate.get(field) is Dictionary: return false
			if candidate[field].get("status", "") not in ["SKIPPED", "PASSED", "FAILED", "ERROR", "NOT_APPLICABLE"]: return false
		if not _valid_condition(candidate.conditions): return false
		if candidate.has("routing"):
			var routing: Variant = candidate.routing
			if not routing is Dictionary or routing.get("mode") not in ["Equal", "Percentages"]: return false
			if not routing.get("selected_target") is String or not routing.get("selected_index") is int: return false
			if not routing.get("roll") is float or routing.roll < 0 or routing.roll >= 1: return false
			if not routing.get("branches") is Array or routing.branches.size() > MAX_NODES: return false
			for branch in routing.branches:
				if not branch is Dictionary or not branch.get("target") is String or typeof(branch.get("percentage")) not in [TYPE_FLOAT, TYPE_INT]: return false
				if branch.percentage < 0 or branch.percentage > 100: return false
		if not candidate.get("effects") is Array or candidate.effects.size() > MAX_NODES: return false
		for effect in candidate.effects:
			if not effect is Dictionary or not effect.get("type") is int or not effect.get("timing") is int or not effect.get("executed") is bool: return false
	return true

static func _valid_condition(node: Dictionary, depth := 0) -> bool:
	if depth > 20 or node.get("status", "") not in ["SKIPPED", "PASSED", "FAILED", "ERROR", "NOT_APPLICABLE"]: return false
	for field in ["kind", "property", "target"]:
		if node.has(field) and not node[field] is String: return false
	if node.has("negated") and not node.negated is bool: return false
	if node.has("operator") and not node.operator is int: return false
	if node.has("actual"):
		for field in ["actual", "expected"]:
			if not node.get(field) is Dictionary or not node[field].get("text") is String or not node[field].get("type") is int: return false
	if node.has("children"):
		if not node.children is Array or node.children.size() > MAX_NODES: return false
		for child in node.children:
			if not child is Dictionary or not _valid_condition(child, depth + 1): return false
	return true

static func _routing_key(route: StateTransition) -> Array:
	var values := []
	if route.random_routing != null:
		for branch in route.random_routing.branches: values.append([branch.target_state, branch.percentage] if branch != null else null)
	return values
