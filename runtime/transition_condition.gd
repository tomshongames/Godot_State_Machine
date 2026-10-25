@tool
class_name TransitionCondition
extends Resource

## A typed comparison that gates a transition using an Actor property or node path.
## Configure property_path, comparison_operator and comparison_value. Node paths
## resolve relative to Actor. Invalid or incompatible comparisons fail closed.
## Negation inverts a valid comparison; disabled conditions are ignored.

enum TargetMode { ACTOR, NODE_PATH }
enum ComparisonOperator { EQUAL, NOT_EQUAL, GREATER, GREATER_EQUAL, LESS, LESS_EQUAL }

@export var enabled: bool = true:
	set(value):
		if enabled == value and typeof(enabled) == typeof(value):
			return
		enabled = value
		emit_changed()

@export var negated := false:
	set(value):
		if negated == value: return
		negated = value
		emit_changed()

@export var target_mode: TargetMode = TargetMode.ACTOR:
	set(value):
		if target_mode == value and typeof(target_mode) == typeof(value):
			return
		target_mode = value
		emit_changed()

@export var target_path: NodePath = NodePath():
	set(value):
		if target_path == value and typeof(target_path) == typeof(value):
			return
		target_path = value
		emit_changed()

@export var property_path: NodePath = NodePath():
	set(value):
		if property_path == value and typeof(property_path) == typeof(value):
			return
		property_path = value
		emit_changed()

@export var comparison_operator: ComparisonOperator = ComparisonOperator.EQUAL:
	set(value):
		if comparison_operator == value and typeof(comparison_operator) == typeof(value):
			return
		comparison_operator = value
		emit_changed()

@export_storage var comparison_value: Variant = false:
	set(value):
		if typeof(comparison_value) == typeof(value) and comparison_value == value:
			return
		comparison_value = value
		emit_changed()

