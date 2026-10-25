@tool
extends RefCounted

const NAMES := {
	"Manual": "GuiArrowRight", "Event": "Signal", "Timer": "Timer",
	"Input Action": "InputEventKey", "Animation Finished": "AnimationPlayer",
	"Property Watch": "Search", "Condition": "MemberProperty",
	"Signal": "Signal",
	"ALL": "GuiTreeArrowDown", "ANY": "GuiTreeArrowRight", "NOT": "GuiUnchecked",
	"Active": "Play", "Initial": "ArrowRight", "Warning": "NodeWarning",
	"Error": "StatusError", "Script": "Script", "Transition": "Curve2D",
}

static func get_icon(control: Control, kind: String) -> Texture2D:
	var name: String = NAMES.get(kind, kind)
	return control.get_theme_icon(name, "EditorIcons") if control.has_theme_icon(name, "EditorIcons") else null

static func trigger_icon(control: Control, trigger: int) -> Texture2D:
	if trigger == 7: return get_icon(control, "Signal")
	return get_icon(control, ["Manual", "Event", "Timer", "Input Action", "Animation Finished", "Property Watch"][clampi(trigger, 0, 5)])

static func transition_icon(control: Control, machine: FiniteStateMachine, transition: StateTransition) -> Texture2D:
	if transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY:
		return get_icon(control, "Initial")
	if transition.destination_mode == StateTransition.DestinationMode.EXIT:
		return get_icon(control, "Initial")
	if is_instance_valid(machine):
		var target := machine.get_state_container().get_node_or_null(NodePath(String(transition.to_state)))
		if target is HierarchyState: return preload("res://addons/state_machine/icons/hierarchy_state.svg")
	return preload("res://addons/state_machine/icons/state.svg")
