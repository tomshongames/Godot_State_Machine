@tool
extends RefCounted

const LABELS := preload("res://addons/state_machine/runtime/transition_labels.gd")
var root: FiniteStateMachine
var contexts: Array[Dictionary] = []
var by_machine := {}
var items: Array[Dictionary] = []
var builds := 0

static func owner_machine(state: State) -> FiniteStateMachine:
	var parent := state.get_parent()
	if parent is FiniteStateMachine: return parent
	if parent != null and parent.has_method("get_nested_machine"):
		for child in parent.get_children(true):
			if child is FiniteStateMachine and child.state_container == parent: return child
	return null

static func root_for(machine: FiniteStateMachine) -> FiniteStateMachine:
	var visited := {}
	while is_instance_valid(machine) and not visited.has(machine):
		visited[machine] = true
		var parent := owner_machine(machine.get_parent()) if machine.get_parent() is State else null
		if parent == null or machine.get_parent().get_parent() != parent.get_state_container(): return machine
		machine = parent
	return machine

func rebuild(machine: FiniteStateMachine) -> void:
	contexts.clear()
	by_machine.clear()
	items.clear()
	root = root_for(machine)
	builds += 1
	if is_instance_valid(root): _collect(root, null, null, String(root.get_state_container().name))

func _collect(machine: FiniteStateMachine, parent, owner, path: String) -> void:
	if by_machine.has(machine): return
	machine.migrate_legacy_transitions()
	var context := {"fsm": machine, "parent": parent, "owner_state": owner, "hierarchy_path": path, "states": [], "names": {}}
	contexts.append(context)
	by_machine[machine] = context
	for child in machine.get_state_container().get_children():
		if not child is State: continue
		context.states.append(child)
		var key := String(child.name).to_lower()
		if not context.names.has(key): context.names[key] = child
		var label := ("Hierarchy" if child is HierarchyState else "State") + " \u00b7 " + String(child.name)
		if child is HierarchyState: label += " → Exit Destination: " + ("EXIT" if child.exit_target == StateTransition.EXIT_TARGET else (String(child.exit_target) if not child.exit_target.is_empty() else "Unconnected"))
		items.append(_item(context, child, null, label, path + "/" + String(child.name) + " " + label))
	for route in machine.transitions:
		if route == null: continue
		var label := "%s \u2192 %s \u00b7 %s" % [route.source_label(), route.target_label(), LABELS.trigger_description(route)]
		items.append(_item(context, null, route, label, path + " " + label))
	for state: State in context.states:
		for child in state.get_children(true):
			if child is FiniteStateMachine: _collect(child, machine, state, path + "/" + String(state.name))

func _item(context: Dictionary, state, route, label: String, text: String) -> Dictionary:
	return {"fsm": context.fsm, "state": state, "transition": route, "hierarchy_path": context.hierarchy_path, "label": label, "text": text.to_lower()}

func query(text: String, kind := 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var terms := text.strip_edges().to_lower().split(" ", false)
	if terms.is_empty(): return result
	for item in items:
		if kind == 1 and item.state == null or kind == 2 and item.transition == null: continue
		var matched := true
		for term in terms:
			if not item.text.contains(term): matched = false; break
		if matched: result.append(item)
	return result

func actor(context: Dictionary) -> Node:
	var visited := {}
	while context.fsm.inherit_actor and context.parent != null and not visited.has(context.fsm):
		visited[context.fsm] = true
		context = by_machine[context.parent]
	var value: Variant = context.fsm.get("_assigned_actor")
	return value as Node if is_instance_valid(value) else null
