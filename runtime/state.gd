@icon("res://addons/state_machine/icons/state.svg")
class_name State
extends Node

## A gameplay state with optional enter, exit, update, physics_update and input hooks.
## Add as a direct child of a FiniteStateMachine or HierarchyState. The owning
## machine supplies actor on activation; do not create a second runtime in a hook.

@export_group("State Policies")
@export_range(0.0, 86400.0, 0.01, "or_greater", "suffix:s") var minimum_state_time := 0.0
@export var interruptible := true


## Explicit transition request, normally emitted by transition_to().
signal transitioned(
	current_state: State,
	new_state_name: StringName
)

## Effective gameplay Actor supplied by the owning FSM.
var actor:
	get:
		return machine.get_effective_actor() if is_instance_valid(machine) else _actor
	set(value): _actor = value
var _actor
var machine: FiniteStateMachine
var nested_fsm: FiniteStateMachine


## Dispatches locally only while this State is current; returns commitment.
func send_event(event_name: StringName) -> bool:
	return machine.send_event(event_name) if is_instance_valid(machine) and machine.current_state == self else false


func bubble_event(event_name: StringName) -> bool:
	return machine.bubble_event(event_name) if is_instance_valid(machine) else false

func request_hierarchy_exit() -> bool:
	return machine.request_exit() if is_instance_valid(machine) and machine.current_state == self else false


## Called on activation, after this State becomes current.
func enter() -> void:
	pass


## Called when leaving this State; avoid recursively forcing transitions.
func exit() -> void:
	pass


## Receives input forwarded by the active machine.
func handle_input(_event: InputEvent) -> void:
	pass


## Called during active frame processing with elapsed frame time.
func update(_delta: float) -> void:
	pass


## Called during active physics processing with fixed-step delta.
func physics_update(_delta: float) -> void:
	pass


## Requests an explicit local transition through the owning FSM.
func transition_to(
	new_state_name: StringName
) -> void:
	transitioned.emit(
		self,
		new_state_name
	)
