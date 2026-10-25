@tool
class_name TransitionAction
extends Resource

## An Effect executed at a transition boundary against a resolved target.
## Supports property writes, numeric addition, Boolean toggle and zero-argument
## method/signal calls. Configure timing, target_mode and the matching path/name.
## Failures are diagnosed and do not supply arguments to methods or signals.

enum Timing { BEFORE_EXIT, AFTER_EXIT, AFTER_ENTER }
enum ActionType { SET_PROPERTY, TOGGLE_BOOL, ADD_VALUE, CALL_METHOD, EMIT_SIGNAL }
enum TargetMode { ACTOR, FSM, SOURCE_STATE, DESTINATION_STATE, NODE_PATH }

@export var enabled := true:
	set(value):
		if enabled == value: return
		enabled = value
		emit_changed()

@export var timing: Timing = Timing.AFTER_EXIT:
	set(value):
		if timing == value: return
		timing = value
		emit_changed()

@export var action_type: ActionType = ActionType.SET_PROPERTY:
	set(value):
		if action_type == value: return
		action_type = value
		emit_changed()

@export var target_mode: TargetMode = TargetMode.ACTOR:
	set(value):
		if target_mode == value: return
		target_mode = value
		emit_changed()

@export var target_path: NodePath = NodePath():
	set(value):
		if target_path == value: return
		target_path = value
		emit_changed()

@export var property_path: NodePath = NodePath():
	set(value):
		if property_path == value: return
		property_path = value
		emit_changed()

@export_storage var value: Variant = false:
	set(next):
		if typeof(value) == typeof(next) and value == next: return
		value = next
		emit_changed()

@export var method_name: StringName = &"":
	set(value):
		if method_name == value: return
		method_name = value
		emit_changed()

@export var signal_name: StringName = &"":
	set(value):
		if signal_name == value: return
		signal_name = value
		emit_changed()
