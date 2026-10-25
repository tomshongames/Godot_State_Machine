@tool
extends RefCounted
const PROPERTY := preload("res://addons/state_machine/runtime/property_comparison.gd")

enum Category { SCRIPT, BUILT_IN, INHERITED }

const TYPE_NAMES := {
	TYPE_BOOL: "Bool",
	TYPE_INT: "Int",
	TYPE_FLOAT: "Float",
	TYPE_STRING: "String",
	TYPE_STRING_NAME: "StringName",
	TYPE_VECTOR2: "Vector2",
	TYPE_VECTOR2I: "Vector2i",
	TYPE_VECTOR3: "Vector3",
	TYPE_VECTOR3I: "Vector3i",
	TYPE_VECTOR4: "Vector4",
	TYPE_VECTOR4I: "Vector4i",
}

static func properties(target: Object) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(target):
		return result
	var script_names := _script_property_names(target.get_script())
	var seen := {}
	for entry in _script_properties(target.get_script(), false):
		_add_property(result, seen, entry.name, int(entry.get("type", TYPE_NIL)), Category.SCRIPT, true)
	for property in target.get_property_list():
		var name := StringName(property.name)
		if String(name).begins_with("_"):
			continue
		var category := Category.SCRIPT if script_names.has(name) else Category.BUILT_IN
		_add_property(result, seen, name, int(property.get("type", TYPE_NIL)), category, true)
	for entry in _script_properties(target.get_script(), true):
		_add_property(result, seen, entry.name, int(entry.get("type", TYPE_NIL)), Category.INHERITED, true)
	result.sort_custom(func(a, b):
		if a.category != b.category:
			return a.category < b.category
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return result


static func find(target: Object, path: NodePath) -> Dictionary:
	if not is_instance_valid(target) or path.is_empty() or path.is_absolute() or path.get_name_count() != 1:
		return {}
	var root := StringName(path.get_name(0))
	for entry in properties(target):
		if entry.name == root:
			if path.get_subname_count() > 1: return {}
			if path.get_subname_count() == 1:
				return _subproperty(entry, path.get_subname(0))
			return entry
	return {}


static func operator_ids(type: int) -> PackedInt32Array:
	if type == TYPE_BOOL or type in [TYPE_STRING, TYPE_STRING_NAME]:
		return PackedInt32Array([TransitionCondition.ComparisonOperator.EQUAL, TransitionCondition.ComparisonOperator.NOT_EQUAL])
	if type in [TYPE_INT, TYPE_FLOAT]:
		return PackedInt32Array([
			TransitionCondition.ComparisonOperator.EQUAL,
			TransitionCondition.ComparisonOperator.NOT_EQUAL,
			TransitionCondition.ComparisonOperator.GREATER,
			TransitionCondition.ComparisonOperator.GREATER_EQUAL,
			TransitionCondition.ComparisonOperator.LESS,
			TransitionCondition.ComparisonOperator.LESS_EQUAL,
		])
	return PackedInt32Array([TransitionCondition.ComparisonOperator.EQUAL, TransitionCondition.ComparisonOperator.NOT_EQUAL])


static func default_value(type: int) -> Variant:
	match type:
		TYPE_BOOL: return false
		TYPE_INT: return 0
		TYPE_FLOAT: return 0.0
		TYPE_STRING: return ""
		TYPE_STRING_NAME: return &""
	return false


static func type_name(type: int) -> String:
	return TYPE_NAMES.get(type, "Variant")


static func _script_property_names(script: Script) -> Dictionary:
	var names := {}
	while script != null:
		for property in script.get_script_property_list():
			names[StringName(property.name)] = true
		script = script.get_base_script()
	return names


static func _script_properties(script: Script, inherited_only: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var first := true
	while script != null:
		for property in script.get_script_property_list():
			if inherited_only == (not first):
				result.append(property)
		first = false
		script = script.get_base_script()
	return result


static func _add_property(result: Array[Dictionary], seen: Dictionary, name: StringName, type: int, category: int, expandable: bool) -> void:
	if name.is_empty() or seen.has(name):
		return
	seen[name] = true
	result.append({"name": name, "type": type, "category": category, "expandable": expandable})
	for sub in _subproperties(name, type):
		result.append(sub)


static func _subproperties(name: StringName, type: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part in ["x", "y", "z", "w"]:
		var component_type := PROPERTY.vector_component_type(type, part)
		if component_type == TYPE_NIL: continue
		result.append({"name": StringName("%s:%s" % [name, part]), "type": component_type, "category": Category.SCRIPT, "expandable": false})
	return result


static func _subproperty(entry: Dictionary, subname: StringName) -> Dictionary:
	for candidate in _subproperties(entry.name, int(entry.type)):
		if String(candidate.name).get_slice(":", 1) == String(subname):
			return candidate
	return {}
