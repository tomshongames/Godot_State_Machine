@tool
extends Resource

enum TargetMode { ACTOR, NODE_PATH, FSM }

@export var display_name := "Watch"
@export var target_mode: TargetMode = TargetMode.ACTOR
@export var target_path: NodePath
@export var property_path: NodePath
@export var enabled := true
