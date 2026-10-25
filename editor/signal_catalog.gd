@tool
extends RefCounted

static func names(source: Node) -> Array[StringName]:
	var result: Array[StringName] = []
	if not is_instance_valid(source): return result
	for entry in source.get_signal_list():
		var name := StringName(entry.name)
		if not name in result: result.append(name)
	var script: Script = source.get_script()
	while script != null:
		for entry in script.get_script_signal_list():
			var name := StringName(entry.name)
			if not name in result: result.append(name)
		script = script.get_base_script()
	result.sort()
	return result

static func declared_names(script: Script) -> Array[StringName]:
	var result: Array[StringName] = []
	while script != null:
		for entry in script.get_script_signal_list():
			var name := StringName(entry.name)
			if not name in result: result.append(name)
		script = script.get_base_script()
	return result
