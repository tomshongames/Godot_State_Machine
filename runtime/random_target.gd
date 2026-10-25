@tool
class_name StateRandomTarget
extends Resource

## One Random destination with a local State name and authored percentage.
## percentage is used only in PERCENTAGES mode. EXIT uses
## StateTransition.EXIT_TARGET and is valid only in an eligible nested machine.

@export var target_state: StringName = &"":
	set(value):
		target_state = value
		emit_changed()
@export_range(0, 100, 0.1) var percentage := 0.0:
	set(value):
		percentage = value
		emit_changed()
