extends RefCounted

const PROPERTY := preload("res://addons/state_machine/runtime/property_comparison.gd")

static func execute(machine: FiniteStateMachine, action: TransitionAction, source: State, destination: State) -> Dictionary:
	var target: Object = PROPERTY.action_target(machine, source, destination, action)
	if not is_instance_valid(target):
		return {"ok": false, "message": "target is missing"}
	match action.action_type:
		TransitionAction.ActionType.SET_PROPERTY:
			var set_result := PROPERTY.write(target, action.property_path, action.value)
			return {"ok": bool(set_result.valid), "message": set_result.get("reason", "")}
		TransitionAction.ActionType.TOGGLE_BOOL:
			var read_result := PROPERTY.read(target, action.property_path)
			if not read_result.valid or typeof(read_result.value) != TYPE_BOOL:
				return {"ok": false, "message": read_result.get("reason", "Toggle Bool requires a bool property.")}
			var toggle_result := PROPERTY.write(target, action.property_path, not read_result.value)
			return {"ok": bool(toggle_result.valid), "message": toggle_result.get("reason", "")}
		TransitionAction.ActionType.ADD_VALUE:
			var read_numeric := PROPERTY.read(target, action.property_path)
			if not read_numeric.valid or typeof(read_numeric.value) not in [TYPE_INT, TYPE_FLOAT] or typeof(action.value) not in [TYPE_INT, TYPE_FLOAT]:
				return {"ok": false, "message": read_numeric.get("reason", "Add Value requires a numeric property and amount.")}
			var added: Variant = read_numeric.value + action.value
			var add_result := PROPERTY.write(target, action.property_path, int(added) if typeof(read_numeric.value) == TYPE_INT else float(added))
			return {"ok": bool(add_result.valid), "message": add_result.get("reason", "")}
		TransitionAction.ActionType.CALL_METHOD:
			if action.method_name.is_empty() or not target.has_method(action.method_name):
				return {"ok": false, "message": "method '%s' is unavailable" % action.method_name}
			for method in target.get_method_list():
				if method.name == action.method_name and method.args.size() > method.default_args.size():
					return {"ok": false, "message": "method '%s' requires arguments; Effects supply none" % action.method_name}
			target.call(action.method_name)
			return {"ok": true, "message": ""}
		TransitionAction.ActionType.EMIT_SIGNAL:
			if action.signal_name.is_empty() or not target.has_signal(action.signal_name):
				return {"ok": false, "message": "signal '%s' is unavailable" % action.signal_name}
			for declaration in target.get_signal_list():
				if declaration.name == action.signal_name and not declaration.args.is_empty():
					return {"ok": false, "message": "signal '%s' requires arguments; Effects supply none" % action.signal_name}
			target.emit_signal(action.signal_name)
			return {"ok": true, "message": ""}
	return {"ok": false, "message": "unknown action type"}
