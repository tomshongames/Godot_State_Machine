@tool
class_name StateTransition
extends Resource

## An authored route: source, destination, trigger, conditions, effects and policies.
## Store routes in FiniteStateMachine.transitions. Source and target names are
## local State names. EXIT is legal only inside a hierarchy; Random needs routing.
## Resource setters emit changed so runtime/editor bindings can be refreshed.

enum TriggerType { MANUAL = 0, EVENT = 1, TIMER = 2, INPUT_ACTION = 3, ANIMATION_FINISHED = 4, PROPERTY_WATCH = 5, SIGNAL = 7 }
enum SignalSourceMode { ACTOR, NODE_PATH }
enum InputMode { PRESSED, RELEASED, HELD }
enum SourceMode { STATE, ANY_STATE, HIERARCHY_ENTRY }
enum DestinationMode { STATE, EXIT }
enum TargetMode { DIRECT, RANDOM }
@export var target_mode: TargetMode = TargetMode.DIRECT:
	set(value):
		target_mode = value
		emit_changed()
@export var random_routing: StateRandomRouting:
	set(value):
		random_routing = value
		emit_changed()
const EXIT_TARGET := &"@hierarchy_exit"

func target_key() -> StringName:
	if target_mode == TargetMode.RANDOM: return &"@random"
	return EXIT_TARGET if destination_mode == DestinationMode.EXIT else to_state

func target_label() -> String:
	if target_mode == TargetMode.RANDOM:
		var targets := PackedStringArray()
		if random_routing != null:
			for branch in random_routing.branches:
				if branch != null: targets.append(String(branch.target_state))
		return "Random (%s)" % ", ".join(targets)
	if destination_mode == DestinationMode.EXIT: return "EXIT"
	return "Unconnected" if to_state.is_empty() else String(to_state)

func source_label() -> String:
	return "ENTRY" if source_mode == SourceMode.HIERARCHY_ENTRY else ("Any State" if source_mode == SourceMode.ANY_STATE else String(from_state))

@export var destination_mode: DestinationMode = DestinationMode.STATE:
	set(value):
		if destination_mode == value: return
		destination_mode = value
		emit_changed()

@export var source_mode: SourceMode = SourceMode.STATE:
	set(value):
		if source_mode == value: return
		source_mode = value
		emit_changed()

func matches_source(state_name: StringName) -> bool:
	return source_mode == SourceMode.ANY_STATE or (source_mode == SourceMode.STATE and String(from_state).to_lower() == String(state_name).to_lower())

@export var from_state: StringName = &"":
	set(value):
		if from_state == value:
			return
		from_state = value
		emit_changed()

@export var to_state: StringName = &"":
	set(value):
		if to_state == value:
			return
		to_state = value
		emit_changed()

@export var enabled: bool = true:
	set(value):
		if enabled == value:
			return
		enabled = value
		emit_changed()

@export var priority: int = 0:
	set(value):
		if priority == value:
			return
		priority = value
		emit_changed()

@export var trigger_type: TriggerType = TriggerType.MANUAL:
	set(value):
		if trigger_type == value:
			return
		trigger_type = value
		emit_changed()

@export_range(0.0, 86400.0, 0.01, "or_greater", "suffix:s") var cooldown := 0.0:
	set(value):
		if cooldown == value: return
		cooldown = value
		emit_changed()

@export var can_interrupt := false:
	set(value):
		if can_interrupt == value: return
		can_interrupt = value
		emit_changed()

@export var event_name: StringName = &"":
	set(value):
		if event_name == value:
			return
		event_name = value
		emit_changed()

@export var signal_source_mode: SignalSourceMode = SignalSourceMode.ACTOR:
	set(value):
		if signal_source_mode == value: return
		signal_source_mode = value
		emit_changed()

@export var signal_source_path: NodePath = NodePath():
	set(value):
		if signal_source_path == value: return
		signal_source_path = value
		emit_changed()

@export var signal_name: StringName = &"":
	set(value):
		if signal_name == value: return
		signal_name = value
		emit_changed()

@export var duration: float = 1.0:
	set(value):
		if duration == value:
			return
		duration = value
		emit_changed()

@export var input_action: StringName = &"":
	set(value):
		if input_action == value:
			return
		input_action = value
		emit_changed()

@export var input_mode: InputMode = InputMode.PRESSED:
	set(value):
		if input_mode == value:
			return
		input_mode = value
		emit_changed()

@export var reenter_state: bool = true:
	set(value):
		if reenter_state == value:
			return
		reenter_state = value
		emit_changed()

@export var actions: Array[Resource] = []:
	set(value):
		if actions == value:
			return
		actions = value
		emit_changed()

@export var animation_player_path: NodePath = NodePath():
	set(value):
		if animation_player_path == value:
			return
		animation_player_path = value
		emit_changed()

@export var animation_name: StringName = &"":
	set(value):
		if animation_name == value:
			return
		animation_name = value
		emit_changed()

@export var watch: TransitionCondition = TransitionCondition.new():
	set(value):
		if watch == value:
			return
		watch = value
		emit_changed()

@export var conditions: Array[TransitionCondition] = []:
	set(value):
		if conditions == value:
			return
		conditions = value
		emit_changed()

# Legacy conditions remain an implicit AND, also when an explicit group is set.
@export var condition_group: TransitionConditionGroup:
	set(value):
		if condition_group == value: return
		condition_group = value
		emit_changed()

