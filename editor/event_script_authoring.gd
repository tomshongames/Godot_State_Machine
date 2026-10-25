@tool
extends RefCounted

static func root_machine(machine: FiniteStateMachine) -> FiniteStateMachine:
	var visited := {}
	while is_instance_valid(machine) and not visited.has(machine):
		visited[machine] = true
		var parent := _parent(machine)
		if parent == null:
			return machine
		machine = parent
	return null


static func _parent(machine: FiniteStateMachine) -> FiniteStateMachine:
	var owner := machine.get_parent() as State
	return FiniteStateMachine.machine_for_state(owner) if owner != null else null


static func emitters(machine: FiniteStateMachine) -> Array[State]:
	var result: Array[State] = []
	_collect(machine, result, {})
	return result


static func _collect(machine: FiniteStateMachine, result: Array[State], visited: Dictionary) -> void:
	if not is_instance_valid(machine) or visited.has(machine):
		return
	visited[machine] = true
	for child in machine.get_state_container().get_children():
		if child is State:
			result.append(child)
			_collect(FiniteStateMachine.nested_machine_for_state(child), result, visited)


static func catalog(machine: FiniteStateMachine) -> PackedStringArray:
	var events := PackedStringArray()
	var root := root_machine(machine)
	var machines: Array[FiniteStateMachine] = []
	if root != null:
		machines.append(root)
	for state in emitters(root):
		var nested := FiniteStateMachine.nested_machine_for_state(state)
		if nested != null:
			machines.append(nested)
	for fsm in machines:
		for transition in fsm.transitions:
			if transition != null and transition.trigger_type == StateTransition.TriggerType.EVENT and not transition.event_name.is_empty() and String(transition.event_name) not in events:
				events.append(String(transition.event_name))
	events.sort()
	return events


static func method_name(event: StringName) -> String:
	var invalid := RegEx.new()
	invalid.compile("[^a-zA-Z0-9_]+")
	var name := invalid.sub(String(event).to_snake_case(), "_", true).strip_edges()
	return "trigger_" + (name if not name.is_empty() else "event")


static func distance(state: State, target: FiniteStateMachine) -> int:
	var fsm := FiniteStateMachine.machine_for_state(state)
	var visited := {}
	var depth := 0
	while is_instance_valid(fsm) and not visited.has(fsm):
		if fsm == target:
			return depth
		visited[fsm] = true
		fsm = _parent(fsm)
		depth += 1
	return -1


static func location(script: Script, method: String) -> Dictionary:
	var visited := {}
	var declaration := RegEx.new()
	declaration.compile("^(?:static[ \\t]+)?func[ \\t]+" + method + "[ \\t]*\\(")
	while script != null and not visited.has(script):
		visited[script] = true
		var declared := false
		for info in script.get_script_method_list():
			if info.name == method:
				declared = true
		if script is GDScript and declared:
			var lines: PackedStringArray = script.source_code.split("\n")
			for index in lines.size():
				if declaration.search(lines[index]) != null:
					return {"script": script, "line": index}
		script = script.get_base_script()
	return {}


static func append_method(state: State, target: FiniteStateMachine, event: StringName, editor: EditorInterface = null) -> Dictionary:
	if event.is_empty() or not is_instance_valid(state):
		return {"ok": false, "message": "Choose a State and a non-empty Event Name."}
	var depth := distance(state, target)
	if depth < 0:
		return {"ok": false, "message": "The emitter must belong to this FSM or one of its nested FSMs."}
	var script: Script = state.get_script()
	if not script is GDScript or not script.resource_path.begins_with("res://") or script.resource_path.to_lower().begins_with("res://addons/") or script.resource_path.get_extension() != "gd":
		return {"ok": false, "message": "Create a project-owned GDScript outside addons before adding an Event method."}
	var method := method_name(event)
	var existing := location(script, method)
	if not existing.is_empty():
		return {"ok": true, "created": false, "script": existing.script, "line": existing.line, "method": method}
	var path := script.resource_path
	var original := FileAccess.get_file_as_string(path)
	var buffer: CodeEdit
	if original.is_empty() or original.replace("\r\n", "\n") != script.source_code.replace("\r\n", "\n"):
		return {"ok": false, "message": "Save/reload this script before adding the method; its resource and file differ."}
	var static_initialization := RegEx.new()
	static_initialization.compile("(?m)^[ \\t]*static[ \\t]+var[ \\t]|^[ \\t]*func[ \\t]+_static_init[ \\t]*\\(")
	if static_initialization.search(original) != null:
		return {"ok": false, "message": "Add this Event method manually: compiler validation could execute this script's static initialization."}
	if is_instance_valid(editor):
		var script_editor := editor.get_script_editor()
		if script in script_editor.get_open_scripts() and script_editor.get_current_script() != script:
			return {"ok": false, "message": "Open this State's script before inserting its Event method."}
		var current := script_editor.get_current_editor()
		if current != null and script_editor.get_current_script() == script:
			buffer = current.get_base_editor() as CodeEdit
			if buffer != null and buffer.text.replace("\r\n", "\n") != original.replace("\r\n", "\n"):
				return {"ok": false, "message": "Save the script's unsaved editor changes before creating an Event method."}
	var literal := "&" + JSON.stringify(String(event))
	var body := "\tsend_event(%s)\n" % literal if depth == 0 else "\tbubble_event(%s)\n" % literal
	if depth > 1:
		body = "\tif not is_instance_valid(machine) or machine.current_state != self:\n\t\treturn\n\tvar ancestor: FiniteStateMachine = machine\n"
		for level in depth - 1:
			body += "\tancestor = ancestor.parent_fsm\n"
		body += "\tif is_instance_valid(ancestor):\n\t\tancestor.bubble_event(%s)\n" % literal
	var suffix := "\n\nfunc %s() -> void:\n%s" % [method, body]
	if original.contains("\r\n"):
		suffix = suffix.replace("\n", "\r\n")
	var proposed := original + suffix
	var candidate := GDScript.new()
	candidate.set_path_cache(path)
	candidate.source_code = proposed
	if candidate.reload() != OK:
		return {"ok": false, "message": "The appended method did not compile. The original file was not changed."}
	if FileAccess.get_file_as_string(path) != original:
		return {"ok": false, "message": "The script changed during generation. Retry after saving it."}
	var temporary := path + ".fsm-event." + str(Time.get_ticks_usec()) + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Cannot write beside this script."}
	file.store_string(proposed)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if FileAccess.get_file_as_string(path) != original:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "message": "The script changed while writing. The newer file was retained."}
	if write_error != OK or DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "message": "Could not replace the script safely. The original file was retained."}
	script.source_code = proposed
	script.reload(true)
	if is_instance_valid(buffer):
		buffer.text = proposed
		buffer.tag_saved_version()
	var created := location(script, method)
	return {"ok": true, "created": true, "script": script, "line": created.get("line", -1), "method": method}
