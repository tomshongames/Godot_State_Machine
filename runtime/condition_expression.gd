@tool
extends RefCounted

const PROPERTY := preload("res://addons/state_machine/runtime/property_comparison.gd")
const MAX_DEPTH := 128
const MAX_NODES := 4096

static func compile(transition: StateTransition) -> Dictionary:
	var resources: Array[Resource] = []
	var context := {"resources": resources, "path": {}, "error": "", "visits": 0}
	var children: Array[Dictionary] = []
	for condition in transition.conditions:
		var plan := _compile_node(condition, context, 0)
		if not plan.is_empty(): children.append(plan)
		if not context.error.is_empty(): break
	if transition.condition_group != null:
		var plan := _compile_node(transition.condition_group, context, 0)
		if not plan.is_empty(): children.append(plan)
	return {"valid": context.error.is_empty(), "error": context.error, "resources": resources, "root": {"kind": 1, "negated": false, "children": children}}

static func _compile_node(node: Resource, context: Dictionary, depth: int) -> Dictionary:
	context.visits += 1
	if context.visits > MAX_NODES:
		context.error = "Condition expression exceeds %d expanded nodes." % MAX_NODES
		return {}
	if depth > MAX_DEPTH:
		context.error = "Condition tree exceeds %d nested levels." % MAX_DEPTH
		return {}
	if node == null or not (node is TransitionCondition or node is TransitionConditionGroup):
		context.error = "Condition tree contains a null or invalid child resource."
		return {}
	if not node in context.resources: context.resources.append(node)
	if not node.enabled: return {}
	if node is TransitionCondition:
		return {"kind": 0, "spec": node}
	if context.path.has(node):
		context.error = "Cyclic condition group reference."
		return {}
	if node.operator not in [TransitionConditionGroup.Operator.AND, TransitionConditionGroup.Operator.OR]:
		context.error = "Condition group has an invalid operator."
		return {}
	context.path[node] = true
	var children: Array[Dictionary] = []
	for child in node.children:
		var plan := _compile_node(child, context, depth + 1)
		if not plan.is_empty(): children.append(plan)
		if not context.error.is_empty(): break
	context.path.erase(node)
	return {"kind": 1 if node.operator == TransitionConditionGroup.Operator.AND else 2, "negated": node.negated, "children": children}

static func evaluate(actor: Node, plan: Dictionary, observation: Dictionary = {}, capture_budget: Array = []) -> bool:
	if not plan.valid:
		if not observation.is_empty(): observation.status = "ERROR"; observation.error = plan.error
		return false
	var budget: Array = capture_budget if not capture_budget.is_empty() else ([128] if not observation.is_empty() else [])
	return _evaluate_node(actor, plan.root, observation, budget, 0) == 1

static func _evaluate_node(actor: Node, node: Dictionary, observation: Dictionary = {}, budget: Array = [], depth := 0) -> int:
	if not observation.is_empty():
		if budget[0] <= 0 or depth >= 16:
			var result := _evaluate_node(actor, node)
			observation.status = "ERROR" if result < 0 else ("PASSED" if result == 1 else "FAILED")
			observation.truncated = true
			return result
		budget[0] -= 1
	if node.kind == 0:
		return PROPERTY.evaluate_validated(actor, node.spec, observation)
	if not observation.is_empty():
		observation.kind = "AND" if node.kind == 1 else "OR"
		observation.negated = node.negated
		observation.children = []
	var value: bool = node.kind == 1
	var stopped := false
	for child: Dictionary in node.children:
		var child_observation: Dictionary = {"status": "SKIPPED"} if not observation.is_empty() and budget[0] > 0 else {}
		if not observation.is_empty() and child_observation.is_empty(): observation.truncated = true
		if not observation.is_empty() and not child_observation.is_empty(): observation.children.append(child_observation)
		if stopped:
			if not child_observation.is_empty(): _skipped(child, child_observation, 0, budget)
			continue
		var result := _evaluate_node(actor, child, child_observation, budget, depth + 1)
		if result < 0:
			if observation.is_empty(): return -1
			observation.status = "ERROR"
			stopped = true
			value = false
		if node.kind == 1 and result == 0:
			value = false
			if observation.is_empty(): break
			stopped = true
		if node.kind == 2 and result == 1:
			value = true
			if observation.is_empty(): break
			stopped = true
	if observation.get("status", "") == "ERROR": return -1
	var passed := not value if node.negated else value
	if not observation.is_empty(): observation.status = "PASSED" if passed else "FAILED"
	return int(passed)

static func _skipped(node: Dictionary, observation: Dictionary, depth := 0, budget: Array = [128]) -> void:
	if depth > 16 or budget[0] <= 0: observation.truncated = true; return
	budget[0] -= 1
	if node.kind == 0:
		observation.property = String(node.spec.property_path)
		return
	observation.kind = "AND" if node.kind == 1 else "OR"
	observation.children = []
	for child in node.children.slice(0, 128):
		if budget[0] <= 0: observation.truncated = true; break
		var item := {"status": "SKIPPED"}
		observation.children.append(item)
		_skipped(child, item, depth + 1, budget)

static func warnings(actor: Node, transition: StateTransition) -> PackedStringArray:
	var result := PackedStringArray()
	var plan := compile(transition)
	if not plan.valid: result.append(plan.error)
	for node in plan.resources:
		if node is TransitionCondition and node.enabled:
			var message: String = PROPERTY.warning(actor, node)
			if not message.is_empty(): result.append("Condition: " + message)
	return result

static func nodes(root: Resource, result: Array[Resource]) -> void:
	_nodes(root, result, {}, 0)

static func _nodes(root: Resource, result: Array[Resource], visited: Dictionary, depth: int) -> void:
	if root == null or visited.has(root) or depth > MAX_DEPTH: return
	visited[root] = true
	result.append(root)
	if root is TransitionConditionGroup:
		for child in root.children: _nodes(child, result, visited, depth + 1)

static func contains(transition: StateTransition, node: Resource) -> bool:
	if node in transition.conditions: return true
	var resources: Array[Resource] = []
	nodes(transition.condition_group, resources)
	return node in resources

static func clone(root: Resource) -> Resource:
	if not root is TransitionCondition and not root is TransitionConditionGroup: return null
	return preload("res://addons/state_machine/runtime/authoring_copy.gd").clone(root) as Resource

static func duplicate_transition(source: StateTransition) -> StateTransition:
	return preload("res://addons/state_machine/runtime/authoring_copy.gd").clone(source) as StateTransition

