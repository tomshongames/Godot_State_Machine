@tool
class_name TransitionConditionGroup
extends Resource

## An AND/OR expression containing condition leaves or nested groups.
## Use TransitionCondition or TransitionConditionGroup children. Cycles and
## unsupported Resource types are invalid; negated inverts the group result.

enum Operator { AND, OR }

@export var enabled := true:
	set(value):
		if enabled == value: return
		enabled = value
		emit_changed()

@export var operator: Operator = Operator.AND:
	set(value):
		if operator == value: return
		operator = value
		emit_changed()

@export var negated := false:
	set(value):
		if negated == value: return
		negated = value
		emit_changed()

@export var children: Array[Resource] = []:
	set(value):
		if children == value: return
		children = value
		emit_changed()
