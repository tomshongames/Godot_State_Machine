@tool
extends RefCounted

static func names() -> Array[StringName]:
	var result: Array[StringName] = []
	if Engine.is_editor_hint():
		# Editor InputMap holds editor shortcuts; project action edits live in
		# ProjectSettings until the game loads its own InputMap.
		for property in ProjectSettings.get_property_list():
			var key := String(property.name)
			if key.begins_with("input/") and ProjectSettings.get_setting(key) is Dictionary:
				result.append(StringName(key.trim_prefix("input/")))
	else:
		result.assign(InputMap.get_actions())
	result.sort_custom(func(a, b):
		var left := String(a).to_lower()
		var right := String(b).to_lower()
		return String(a) < String(b) if left == right else left < right)
	return result

static func has_action(action: StringName) -> bool:
	if action.is_empty(): return false
	if not Engine.is_editor_hint(): return InputMap.has_action(action)
	var key := "input/" + String(action)
	return ProjectSettings.has_setting(key) and ProjectSettings.get_setting(key) is Dictionary
