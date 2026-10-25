@tool
extends RefCounted

var pending: Dictionary = {}
var active := false
var token := 0

func begin(machine: FiniteStateMachine, route: StateTransition, edge: Dictionary) -> void:
	pending = {"route": route, "machine": machine, "edge": edge.duplicate(), "target": true}

func started(is_output: bool) -> void:
	active = true
	token += 1
	if not pending.is_empty(): pending.target = is_output

func ended() -> void:
	active = false
	pending.clear()
	token += 1

func cancel(graph: GraphEdit) -> void:
	var was_active := active
	ended()
	if was_active and is_instance_valid(graph): graph.force_connection_drag_end()

func commit(panel, from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	var request := pending.duplicate()
	cancel(panel.graph)
	if not is_instance_valid(panel.state_machine) or request.machine != panel.state_machine: return
	var route: StateTransition = request.route
	if route != panel.fallback_entry and not route in panel.state_machine.transitions: return
	var source := panel.graph.get_node_or_null(NodePath(from)) as GraphNode
	var target := panel.graph.get_node_or_null(NodePath(to)) as GraphNode
	if source == null or target == null: return
	if from_port < 0 or from_port >= source.get_output_port_count() or to_port < 0 or to_port >= target.get_input_port_count(): return
	var edge: Dictionary = request.edge
	if request.target:
		if from != edge.from_node or from_port != edge.from_port: return
	else:
		if to != edge.to_node or to_port != edge.to_port: return
	var mode := StateTransition.SourceMode.HIERARCHY_ENTRY if source == panel.entry_node else (StateTransition.SourceMode.ANY_STATE if source == panel.any_state_node else StateTransition.SourceMode.STATE)
	var source_name: StringName = source.state.name if mode == StateTransition.SourceMode.STATE and is_instance_valid(source.state) else &""
	var target_name: StringName = StateTransition.EXIT_TARGET if target == panel.exit_node else (target.state.name if is_instance_valid(target.state) else &"")
	if route == panel.fallback_entry:
		if request.target and source == panel.entry_node and is_instance_valid(target.state): panel.actions.set_initial(panel.state_machine, target.state)
		return
	if request.target:
		mode = route.source_mode
		source_name = route.from_state
	else: target_name = route.target_key()
	if panel.actions.reconnect_transition(panel.state_machine, route, mode, source_name, target_name, &"to" if request.target else &"from"):
		panel._select_transition(route, false)
