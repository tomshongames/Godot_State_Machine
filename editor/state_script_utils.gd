@tool
extends RefCounted

const BASE_STATE_SCRIPT := preload("res://addons/state_machine/runtime/state.gd")
const HIERARCHY_SCRIPT := preload("res://addons/state_machine/runtime/hierarchy_state.gd")


static func has_gameplay_script(state: State) -> bool:
	if not is_instance_valid(state):
		return false
	var script: Script = state.get_script()
	return script != null and script != BASE_STATE_SCRIPT and script != HIERARCHY_SCRIPT


static func is_state_subclass(script: Script) -> bool:
	if script == null or script == BASE_STATE_SCRIPT:
		return false
	var base := script.get_base_script()
	while base != null:
		if base == BASE_STATE_SCRIPT:
			return true
		base = base.get_base_script()
	return false
