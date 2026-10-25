@tool
@icon("res://addons/state_machine/icons/hierarchy_state.svg")
class_name HierarchyState
extends State

## A State that owns a nested FSM and direct child States.
## Configure initial_state for nested entry and exit_target for parent continuation.
## The internal FSM is managed by get_nested_machine(); do not add another one.
## RESET enters the initial State; RESUME restores the previous nested State.

# The only authored parent-level continuation. Empty is a valid draft value.
# Kept out of the native property editor: author it through the graph output.
@export_storage var exit_target: StringName = &"":
	set(value):
		if exit_target == value: return
		exit_target = value
		if Engine.is_editor_hint():
			update_configuration_warnings()
			var parent_machine := FiniteStateMachine.machine_for_state(self)
			if is_instance_valid(parent_machine): parent_machine.editor_data_changed.emit()

func exit_destination_warning() -> String:
	if exit_target.is_empty(): return "%s has no exit destination." % name
	var parent_machine := FiniteStateMachine.machine_for_state(self)
	if not is_instance_valid(parent_machine): return ""
	if exit_target == StateTransition.EXIT_TARGET:
		return "" if parent_machine.has_hierarchy_boundary() else "%s cannot target EXIT outside a hierarchy." % name
	for child in parent_machine.get_state_container().get_children():
		if child is State and String(child.name).nocasecmp_to(String(exit_target)) == 0: return ""
	return "%s references missing exit destination: %s." % [name, exit_target]

@export var initial_state: State:
	get:
		return nested_fsm.initial_state if is_instance_valid(nested_fsm) else _initial_state
	set(value):
		_initial_state = value
		if is_instance_valid(nested_fsm) and nested_fsm.initial_state != value:
			nested_fsm.initial_state = value
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var entry_mode: FiniteStateMachine.NestedEntryMode = FiniteStateMachine.NestedEntryMode.RESET:
	set(value):
		entry_mode = value
		if is_instance_valid(nested_fsm):
			nested_fsm.nested_entry_mode = value

@export var inherit_actor := true:
	set(value):
		inherit_actor = value
		if is_instance_valid(nested_fsm):
			nested_fsm.inherit_actor = value

@export var actor_override: Node:
	set(value):
		actor_override = value
		if is_instance_valid(nested_fsm):
			nested_fsm.actor = value

@export var use_visual_transition_rules := false:
	set(value):
		use_visual_transition_rules = value
		if is_instance_valid(nested_fsm):
			nested_fsm.use_visual_transition_rules = value

@export_storage var transitions: Array[StateTransition] = []:
	get:
		return nested_fsm.transitions if is_instance_valid(nested_fsm) else transitions
	set(value):
		transitions = value
		if is_instance_valid(nested_fsm):
			nested_fsm.transitions = value

@export_storage var graph_positions: Dictionary = {}:
	get:
		return nested_fsm.graph_positions if is_instance_valid(nested_fsm) else graph_positions
	set(value):
		graph_positions = value
		if is_instance_valid(nested_fsm):
			nested_fsm.graph_positions = value

@export_storage var debugger_watches: Array[Resource] = []:
	get:
		return nested_fsm.debugger_watches if is_instance_valid(nested_fsm) else debugger_watches
	set(value):
		debugger_watches = value
		if is_instance_valid(nested_fsm):
			nested_fsm.debugger_watches = value

var _initial_state: State


func _enter_tree() -> void:
	get_nested_machine()


## Returns the managed internal FSM, creating it lazily if needed.
func get_nested_machine() -> FiniteStateMachine:
	if is_instance_valid(nested_fsm):
		return nested_fsm
	var fsm: FiniteStateMachine
	for child in get_children(true):
		if child is FiniteStateMachine and child.state_container == self:
			fsm = child
			break
	var created := fsm == null
	if created:
		fsm = FiniteStateMachine.new()
	fsm.name = "_HierarchyFSM"
	fsm.state_container = self
	fsm.initial_state = _initial_state
	fsm.nested_entry_mode = entry_mode
	fsm.inherit_actor = inherit_actor
	fsm.actor = actor_override
	fsm.use_visual_transition_rules = use_visual_transition_rules
	fsm.transitions = transitions
	fsm.graph_positions = graph_positions
	fsm.debugger_watches = debugger_watches
	nested_fsm = fsm
	if created:
		add_child(fsm, false, Node.INTERNAL_MODE_BACK)
	return fsm


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := get_nested_machine()._get_configuration_warnings()
	var exit_warning := exit_destination_warning()
	if not exit_warning.is_empty() and not warnings.has(exit_warning): warnings.append(exit_warning)
	return warnings


func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED and Engine.is_editor_hint() and is_instance_valid(nested_fsm):
		update_configuration_warnings()
		nested_fsm.editor_data_changed.emit()
