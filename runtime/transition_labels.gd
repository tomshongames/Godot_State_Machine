@tool
extends RefCounted


static func condition_description(condition: TransitionCondition, show_enabled := true) -> String:
	if condition == null:
		return "Missing comparison"
	var operators := ["==", "!=", ">", ">=", "<", "<="]
	var target := String(condition.property_path)
	if show_enabled and condition.target_mode == TransitionCondition.TargetMode.ACTOR:
		target = "Actor." + target
	if condition.target_mode == TransitionCondition.TargetMode.NODE_PATH and not condition.target_path.is_empty():
		target = String(condition.target_path) + "." + target
	return "%s%s%s %s %s" % ["[Off] " if show_enabled and not condition.enabled else "", "NOT " if condition.negated else "", target, operators[clampi(condition.comparison_operator, 0, 5)], str(condition.comparison_value)]


static func trigger_description(transition: StateTransition) -> String:
	var label := _trigger_description(transition)
	return "Any State / " + label if transition != null and transition.source_mode == StateTransition.SourceMode.ANY_STATE else label


static func _trigger_description(transition: StateTransition) -> String:
	if transition == null:
		return "Manual"
	if transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY: return "Entry Route"
	match transition.trigger_type:
		StateTransition.TriggerType.EVENT: return "Event: %s" % transition.event_name
		StateTransition.TriggerType.TIMER: return "Timer: %.2f s" % transition.duration
		StateTransition.TriggerType.INPUT_ACTION: return "Input: %s [%s]" % [transition.input_action, ["Pressed", "Released", "Held"][clampi(transition.input_mode, 0, 2)]]
		StateTransition.TriggerType.ANIMATION_FINISHED: return "Animation: %s" % transition.animation_name
		StateTransition.TriggerType.PROPERTY_WATCH: return "Watch: %s" % condition_description(transition.watch, false)
		StateTransition.TriggerType.SIGNAL: return "Signal: %s.%s" % ["Actor" if transition.signal_source_mode == StateTransition.SignalSourceMode.ACTOR else String(transition.signal_source_path), transition.signal_name]
	return "Manual"


static func source_identity(machine: Node) -> Dictionary:
	var ancestor := machine
	while is_instance_valid(ancestor):
		if not ancestor.scene_file_path.is_empty():
			return {"scene": ancestor.scene_file_path, "local_path": String(ancestor.get_path_to(machine))}
		ancestor = ancestor.get_parent()
	return {"scene": "", "local_path": ""}
