@tool
extends RefCounted

# One index per graph rebuild: case-insensitive identity and outgoing resources.
# No scene changes or selection ownership; this is reusable renderer input.
var names: Dictionary[StringName, StringName] = {}
var counts: Dictionary[StringName, int] = {}
var outgoing: Dictionary = {}
var incoming: Dictionary = {}

func rebuild(machine: FiniteStateMachine) -> void:
	names.clear()
	counts.clear()
	outgoing.clear()
	incoming.clear()
	if not is_instance_valid(machine): return
	# Membership is local to this rebuild: no retained Resource cache to invalidate.
	# Create sets only for Random destinations; direct-only graphs keep their arrays.
	var random_members: Dictionary = {}
	for child in machine.get_state_container().get_children():
		if child is State:
			var key := StringName(String(child.name).to_lower())
			counts[key] = counts.get(key, 0) + 1
	for route in machine.transitions:
		if route == null: continue
		var target := StringName(String(route.target_key()).to_lower())
		if not incoming.has(target):
			var routes: Array[StateTransition] = []
			incoming[target] = routes
		incoming[target].append(route)
		if random_members.has(target): random_members[target][route] = true
		if route.target_mode == StateTransition.TargetMode.RANDOM and route.random_routing != null:
			for branch in route.random_routing.branches:
				if branch == null: continue
				var branch_target := StringName(String(branch.target_state).to_lower())
				if not incoming.has(branch_target): incoming[branch_target] = [] as Array[StateTransition]
				if not random_members.has(branch_target):
					var members := {}
					for existing in incoming[branch_target]: members[existing] = true
					random_members[branch_target] = members
				if not random_members[branch_target].has(route):
					incoming[branch_target].append(route)
					random_members[branch_target][route] = true
		if route.source_mode != StateTransition.SourceMode.STATE: continue
		var key := StringName(String(route.from_state).to_lower())
		if not outgoing.has(key):
			var routes: Array[StateTransition] = []
			outgoing[key] = routes
		outgoing[key].append(route)

func register_node(state: State, node: GraphNode) -> void:
	var key := StringName(String(state.name).to_lower())
	if not names.has(key): names[key] = node.name

func graph_name(requested: StringName) -> StringName:
	return names.get(StringName(String(requested).to_lower()), &"")

func routes_for(state: State) -> Array[StateTransition]:
	return outgoing.get(StringName(String(state.name).to_lower()), [] as Array[StateTransition])

func duplicate_name(state: State) -> bool:
	return counts.get(StringName(String(state.name).to_lower()), 0) > 1

func incoming_for(target: StringName) -> Array[StateTransition]:
	return incoming.get(StringName(String(target).to_lower()), [] as Array[StateTransition])
