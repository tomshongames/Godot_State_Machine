@tool
extends RefCounted

# Only FSM-owned authoring Resources are copied. External assets retain identity.
static func is_mutable(value: Resource) -> bool:
	if value is StateRandomRouting or value is StateRandomTarget: return true
	return value is StateTransition or value is TransitionCondition or value is TransitionConditionGroup or value is TransitionAction or (value.get_script() != null and value.get_script().resource_path == "res://addons/state_machine/runtime/watch_entry.gd")

static func clone(value: Variant, copies: Dictionary = {}) -> Variant:
	if value is Resource:
		if not is_mutable(value): return value
		if copies.has(value): return copies[value]
		var copy: Resource = value.get_script().new()
		copies[value] = copy
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.name not in ["script", "resource_path"]:
				copy.set(property.name, clone(value.get(property.name), copies))
		for key in value.get_meta_list(): copy.set_meta(key, clone(value.get_meta(key), copies))
		return copy
	if value is Array:
		var copy: Array = value.duplicate()
		for i in value.size(): copy[i] = clone(value[i], copies)
		return copy
	if value is Dictionary:
		var copy: Dictionary = {}
		for key in value: copy[key] = clone(value[key], copies)
		return copy
	return value

static func resources(value: Variant, result: Dictionary) -> void:
	if value is Resource and is_mutable(value):
		if result.has(value): return
		result[value] = true
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.name != "script": resources(value.get(property.name), result)
		for key in value.get_meta_list(): resources(value.get_meta(key), result)
	elif value is Array or value is Dictionary:
		for item in (value.values() if value is Dictionary else value): resources(item, result)
