@tool
extends RefCounted

static var _property_names: Dictionary = {}


static func _has_property(object: Object, name: StringName) -> bool:
	var id := object.get_instance_id()
	if not _property_names.has(id):
		if _property_names.size() >= 512:
			_property_names.clear()
		var names: Dictionary = {}
		for property in object.get_property_list():
			names[StringName(property.name)] = true
		var script: Script = object.get_script()
		while script != null:
			for property in script.get_script_property_list():
				names[StringName(property.name)] = true
			script = script.get_base_script()
		_property_names[id] = {"object": weakref(object), "names": names}
		var callback := _invalidate.bind(id)
		for signal_name in [&"property_list_changed", &"script_changed"]:
			if object.has_signal(signal_name) and not object.is_connected(signal_name, callback):
				object.connect(signal_name, callback)
	return _property_names[id].names.has(name)


static func _invalidate(id: int) -> void:
	_property_names.erase(id)


static func target(actor: Node, mode: int, path: NodePath) -> Node:
	if not is_instance_valid(actor):
		return null
	if mode == TransitionCondition.TargetMode.ACTOR:
		return actor
	if mode != TransitionCondition.TargetMode.NODE_PATH or path.is_empty() or path.is_absolute():
		return null
	return actor.get_node_or_null(path)


static func action_target(machine: FiniteStateMachine, source: State, destination: State, action: TransitionAction) -> Object:
	if action == null or not is_instance_valid(machine):
		return null
	match action.target_mode:
		TransitionAction.TargetMode.ACTOR:
			return machine.actor
		TransitionAction.TargetMode.FSM:
			return machine
		TransitionAction.TargetMode.SOURCE_STATE:
			return source
		TransitionAction.TargetMode.DESTINATION_STATE:
			return destination
		TransitionAction.TargetMode.NODE_PATH:
			if not is_instance_valid(machine.actor) or action.target_path.is_empty() or action.target_path.is_absolute():
				return null
			return machine.actor.get_node_or_null(action.target_path)
	return null


static func vector_component_type(type: int, component: StringName) -> int:
	var count := 0
	match type:
		TYPE_VECTOR2, TYPE_VECTOR2I: count = 2
		TYPE_VECTOR3, TYPE_VECTOR3I: count = 3
		TYPE_VECTOR4, TYPE_VECTOR4I: count = 4
	var index := ["x", "y", "z", "w"].find(String(component))
	if index < 0 or index >= count: return TYPE_NIL
	return TYPE_INT if type in [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I] else TYPE_FLOAT


static func declared_type(node: Object, path: NodePath) -> int:
	if not is_instance_valid(node) or path.is_absolute() or path.get_name_count() != 1 or path.get_subname_count() > 1: return TYPE_NIL
	var properties := node.get_property_list()
	var script: Script = node.get_script()
	while script != null:
		properties = script.get_script_property_list() + properties
		script = script.get_base_script()
	for entry in properties:
		if String(entry.name) != String(path.get_name(0)): continue
		return vector_component_type(entry.type, path.get_subname(0)) if path.get_subname_count() == 1 else int(entry.type)
	return TYPE_NIL


static func read(node: Object, path: NodePath) -> Dictionary:
	if not is_instance_valid(node):
		return {"valid": false, "reason": "Property target is missing."}
	if path.is_empty() or path.is_absolute() or path.get_name_count() != 1:
		return {"valid": false, "reason": "Use a property name with optional colon subpaths, such as velocity:x."}
	var parts: Array[StringName] = [path.get_name(0)]
	for index in path.get_subname_count():
		parts.append(path.get_subname(index))
	var value: Variant = node
	for part in parts:
		if value is Object:
			if not is_instance_valid(value):
				return {"valid": false, "reason": "Property object was freed."}
			if not _has_property(value, part):
				return {"valid": false, "reason": "Property '%s' is unavailable (non-exported script properties may need runtime validation)." % part}
			value = value.get_indexed(NodePath(String(part)))
		elif value is Dictionary:
			if not value.has(part) and not value.has(String(part)):
				return {"valid": false, "reason": "Dictionary property '%s' is missing." % part}
			value = value.get(part, value.get(String(part)))
		elif value is Vector2 or value is Vector3 or value is Vector4 or value is Vector2i or value is Vector3i or value is Vector4i:
			var index := ["x", "y", "z", "w"].find(String(part))
			if vector_component_type(typeof(value), part) == TYPE_NIL:
				return {"valid": false, "reason": "Invalid vector component '%s'." % part}
			value = value[index]
		else:
			return {"valid": false, "reason": "This value has no supported subproperty '%s'." % part}
	return {"valid": true, "value": value}


static func write(node: Object, path: NodePath, next_value: Variant) -> Dictionary:
	if not is_instance_valid(node):
		return {"valid": false, "reason": "Property target is missing."}
	if path.is_empty() or path.is_absolute() or path.get_name_count() != 1:
		return {"valid": false, "reason": "Use a property name with optional colon subpaths, such as velocity:x."}
	var parts: Array[StringName] = [path.get_name(0)]
	for index in path.get_subname_count():
		parts.append(path.get_subname(index))
	if parts.size() == 1:
		if not _has_property(node, parts[0]):
			return {"valid": false, "reason": "Property '%s' is unavailable." % parts[0]}
		node.set_indexed(NodePath(String(parts[0])), next_value)
		return {"valid": true}
	var owner: Variant = node
	# Vector components are value types. Retain their immediate owning property,
	# rather than writing the modified vector into the root path's first segment.
	var property_owner: Object = node
	var property_name: StringName = parts[0]
	for index in parts.size() - 1:
		var part := parts[index]
		if owner is Object:
			if not is_instance_valid(owner) or not _has_property(owner, part):
				return {"valid": false, "reason": "Property '%s' is unavailable." % part}
			property_owner = owner
			property_name = part
			owner = owner.get_indexed(NodePath(String(part)))
		else:
			return {"valid": false, "reason": "Nested property writes are only supported on Object properties."}
	var leaf := parts[parts.size() - 1]
	if owner is Object and is_instance_valid(owner) and _has_property(owner, leaf):
		owner.set_indexed(NodePath(String(leaf)), next_value)
		return {"valid": true}
	if owner is Dictionary:
		owner[leaf] = next_value
		return {"valid": true}
	if owner is Vector2 or owner is Vector3 or owner is Vector4 or owner is Vector2i or owner is Vector3i or owner is Vector4i:
		var component := ["x", "y", "z", "w"].find(String(leaf))
		if vector_component_type(typeof(owner), leaf) == TYPE_NIL:
			return {"valid": false, "reason": "Invalid vector component '%s'." % leaf}
		owner[component] = next_value
		property_owner.set_indexed(NodePath(String(property_name)), owner)
		return {"valid": true}
	return {"valid": false, "reason": "This value has no supported subproperty '%s'." % leaf}


static func compatible(left: Variant, right: Variant, operator: int) -> bool:
	var numeric := typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT]
	if numeric:
		return is_finite(float(left)) and is_finite(float(right)) and operator in range(6)
	if operator not in [TransitionCondition.ComparisonOperator.EQUAL, TransitionCondition.ComparisonOperator.NOT_EQUAL]:
		return false
	return (left is bool and right is bool) or (typeof(left) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(right) in [TYPE_STRING, TYPE_STRING_NAME])


static func compare(left: Variant, right: Variant, operator: int) -> bool:
	if not compatible(left, right, operator):
		return false
	match operator:
		TransitionCondition.ComparisonOperator.EQUAL: return left == right
		TransitionCondition.ComparisonOperator.NOT_EQUAL: return left != right
		TransitionCondition.ComparisonOperator.GREATER: return left > right
		TransitionCondition.ComparisonOperator.GREATER_EQUAL: return left >= right
		TransitionCondition.ComparisonOperator.LESS: return left < right
		TransitionCondition.ComparisonOperator.LESS_EQUAL: return left <= right
	return false


static func evaluate(actor: Node, spec: TransitionCondition, observation: Dictionary = {}) -> bool:
	return evaluate_validated(actor, spec, observation) == 1


static func evaluate_validated(actor: Node, spec: TransitionCondition, observation: Dictionary = {}) -> int:
	if spec == null:
		return -1
	var result := read(target(actor, spec.target_mode, spec.target_path), spec.property_path)
	if not observation.is_empty():
		var data := preload("res://addons/state_machine/runtime/decision_data.gd")
		observation.property = String(spec.property_path)
		observation.target = String(spec.target_path) if spec.target_mode == 1 else "Actor"
		observation.operator = int(spec.comparison_operator)
		observation.negated = spec.negated
		observation.expected = data.value(spec.comparison_value)
		observation.actual = data.value(result.value) if result.valid else {"type": TYPE_NIL, "text": "<unavailable>"}
		observation.status = "ERROR"
	if not result.valid or not compatible(result.value, spec.comparison_value, spec.comparison_operator):
		return -1
	var value := compare(result.value, spec.comparison_value, spec.comparison_operator)
	var passed := not value if spec.negated else value
	if not observation.is_empty(): observation.status = "PASSED" if passed else "FAILED"
	return int(passed)


static func warning(actor: Node, spec: TransitionCondition) -> String:
	if spec == null:
		return "Missing property comparison resource."
	var node := target(actor, spec.target_mode, spec.target_path)
	var result := read(node, spec.property_path)
	# Non-tool placeholders cannot read non-exported variables or their vector
	# components; use declarations for warnings only, never for evaluation.
	if Engine.is_editor_hint() and is_instance_valid(node) and node.get_script() != null and not node.get_script().is_tool() and (not result.valid or result.get("value") == null):
		var type := declared_type(node, spec.property_path)
		match type:
			TYPE_BOOL: result = {"valid": true, "value": false}
			TYPE_INT: result = {"valid": true, "value": 0}
			TYPE_FLOAT: result = {"valid": true, "value": 0.0}
			TYPE_STRING: result = {"valid": true, "value": ""}
			TYPE_STRING_NAME: result = {"valid": true, "value": &""}
	if not result.valid: return result.reason
	if not compatible(result.value, spec.comparison_value, spec.comparison_operator):
		return "Property and comparison value/operator have incompatible types."
	return ""
