@tool
extends RefCounted

# Internal Undo codec. Keep resource identities and copy only settings/arrays.
const LOGIC := preload("res://addons/state_machine/runtime/condition_expression.gd")
const FIELDS := [&"source_mode", &"destination_mode", &"enabled", &"priority", &"cooldown", &"can_interrupt", &"trigger_type", &"event_name", &"duration", &"input_action", &"input_mode", &"reenter_state", &"animation_player_path", &"animation_name", &"signal_source_mode", &"signal_source_path", &"signal_name", &"watch", &"actions"]
const COMPARISON_FIELDS := [&"enabled", &"negated", &"target_mode", &"target_path", &"property_path", &"comparison_operator", &"comparison_value"]
const ACTION_FIELDS := [&"enabled", &"timing", &"action_type", &"target_mode", &"target_path", &"property_path", &"value", &"method_name", &"signal_name"]

static func comparison(condition: TransitionCondition) -> Dictionary:
	var settings := {}
	if condition != null:
		for property in COMPARISON_FIELDS: settings[property] = condition.get(property)
	return settings

static func capture(transition: StateTransition) -> Dictionary:
	if transition == null: return {}
	var settings := {}
	for property in FIELDS: settings[property] = transition.get(property)
	settings.target_mode = transition.target_mode
	settings.random_routing = transition.random_routing
	settings.routing_values = []
	if transition.random_routing != null:
		settings.routing_mode = transition.random_routing.mode
		settings.routing_branches = transition.random_routing.branches.duplicate()
		settings.router_color_present = transition.random_routing.has_meta(&"fsm_editor_random_color")
		settings.router_color_value = transition.random_routing.get_meta(&"fsm_editor_random_color", Color("514765"))
		for branch in transition.random_routing.branches:
			settings.routing_values.append({"resource": branch, "target": branch.target_state if branch != null else &"", "percentage": branch.percentage if branch != null else 0.0, "start_present": branch.has_meta(&"fsm_editor_transition_color") if branch != null else false, "start_value": branch.get_meta(&"fsm_editor_transition_color", Color("aab7c8")) if branch != null else Color("aab7c8"), "end_present": branch.has_meta(&"fsm_editor_transition_end_color") if branch != null else false, "end_value": branch.get_meta(&"fsm_editor_transition_end_color", Color.WHITE) if branch != null else Color.WHITE})
	settings.conditions = transition.conditions.duplicate()
	settings.condition_group = transition.condition_group
	settings.block_position_present = transition.has_meta(&"fsm_editor_block_position")
	settings.block_position_value = transition.get_meta(&"fsm_editor_block_position", Vector2.ZERO)
	settings.editor_color_present = transition.has_meta(&"fsm_editor_transition_color")
	settings.editor_color_value = transition.get_meta(&"fsm_editor_transition_color", Color("aab7c8"))
	settings.editor_end_color_present = transition.has_meta(&"fsm_editor_transition_end_color")
	settings.editor_end_color_value = transition.get_meta(&"fsm_editor_transition_end_color", Color.WHITE)
	var nodes: Array[Resource] = []
	LOGIC.nodes(transition.condition_group, nodes)
	var groups: Array[Dictionary] = []
	var comparisons: Array[Dictionary] = []
	var leaves: Array[Resource] = []
	if transition.watch != null: leaves.append(transition.watch)
	leaves.append_array(transition.conditions)
	for node in nodes:
		if node is TransitionConditionGroup:
			groups.append({"resource":node, "enabled":node.enabled, "operator":node.operator, "negated":node.negated, "children":node.children.duplicate()})
		elif node is TransitionCondition: leaves.append(node)
	var seen := {}
	for leaf in leaves:
		if leaf != null and not seen.has(leaf):
			seen[leaf] = true
			comparisons.append({"resource":leaf, "settings":comparison(leaf)})
	settings.group_values = groups
	settings.condition_values = comparisons
	var action_values: Array[Dictionary] = []
	for action in transition.actions:
		if action == null:
			continue
		var action_settings := {}
		for property in ACTION_FIELDS:
			action_settings[property] = action.get(property)
		action_values.append({"resource": action, "settings": action_settings})
	settings.action_values = action_values
	return settings

static func apply(transition: StateTransition, settings: Dictionary) -> void:
	for property in settings:
		if property not in ["routing_values", "routing_mode", "routing_branches", "router_color_present", "router_color_value", "condition_values", "group_values", "action_values", "editor_color_present", "editor_color_value", "editor_end_color_present", "editor_end_color_value", "block_position_present", "block_position_value"]:
			transition.set(property, settings[property])
	if transition.random_routing != null:
		transition.random_routing.mode = settings.get("routing_mode", 0)
		transition.random_routing.branches = settings.get("routing_branches", [])
		if settings.get("router_color_present", false): transition.random_routing.set_meta(&"fsm_editor_random_color", settings.router_color_value)
		else: transition.random_routing.remove_meta(&"fsm_editor_random_color")
		for item in settings.get("routing_values", []):
			if item.resource == null: continue
			item.resource.target_state = item.target
			item.resource.percentage = item.percentage
			if item.get("start_present", false): item.resource.set_meta(&"fsm_editor_transition_color", item.start_value)
			else: item.resource.remove_meta(&"fsm_editor_transition_color")
			if item.get("end_present", false): item.resource.set_meta(&"fsm_editor_transition_end_color", item.end_value)
			else: item.resource.remove_meta(&"fsm_editor_transition_end_color")
	if settings.get("block_position_present", false): transition.set_meta(&"fsm_editor_block_position", settings.block_position_value)
	else: transition.remove_meta(&"fsm_editor_block_position")
	if settings.get("editor_color_present", false): transition.set_meta(&"fsm_editor_transition_color", settings.editor_color_value)
	else: transition.remove_meta(&"fsm_editor_transition_color")
	if settings.get("editor_end_color_present", false): transition.set_meta(&"fsm_editor_transition_end_color", settings.editor_end_color_value)
	else: transition.remove_meta(&"fsm_editor_transition_end_color")
	for value: Dictionary in settings.get("condition_values", []):
		if value.resource == null: continue
		for property in value.settings: value.resource.set(property, value.settings[property])
	for value: Dictionary in settings.get("group_values", []):
		if value.resource == null: continue
		value.resource.enabled = value.enabled
		value.resource.operator = value.operator
		value.resource.negated = value.negated
		value.resource.children = value.children
	for value: Dictionary in settings.get("action_values", []):
		if value.resource == null: continue
		for property in value.settings: value.resource.set(property, value.settings[property])
