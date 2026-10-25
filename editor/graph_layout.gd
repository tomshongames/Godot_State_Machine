@tool
extends RefCounted
const RANDOM_BLOCK := preload("res://addons/state_machine/editor/random_graph_block.gd")
const BLOCK := preload("res://addons/state_machine/editor/transition_graph_block.gd")

# Stable breadth-first placement. Back edges and cycles retain their logical
# connections, while blocks are placed separately in deterministic lanes.
static func arrange(panel) -> void:
	var nodes: Array[GraphNode] = []
	var adjacency := {}
	for child in panel.graph.get_children():
		if child is GraphNode and not child is BLOCK and not child is RANDOM_BLOCK:
			if child.get("state") is State and panel.is_graph_state_hidden(child.state): continue
			nodes.append(child)
			adjacency[child.name] = []
	for route in panel.state_machine.transitions:
		if route == null: continue
		var from: StringName = panel._route_source(route)
		var targets: Array[StringName] = []
		if route.target_mode == StateTransition.TargetMode.RANDOM and route.random_routing != null:
			for branch in route.random_routing.branches:
				if branch != null: targets.append(panel._graph_target(branch.target_state))
		else: targets.append(panel._graph_target(route.target_key()))
		for to in targets:
			if adjacency.has(from) and adjacency.has(to) and from != to: adjacency[from].append(to)
	var depths := {}
	for hierarchy in panel.hierarchy_exit_connections:
		var edge: Dictionary = panel.hierarchy_exit_connections[hierarchy]
		if adjacency.has(edge.from_node) and adjacency.has(edge.to_node) and edge.from_node != edge.to_node: adjacency[edge.from_node].append(edge.to_node)
	var roots: Array[StringName] = []
	if is_instance_valid(panel.entry_node): roots.append(panel.entry_node.name)
	if is_instance_valid(panel.any_state_node): roots.append(panel.any_state_node.name)
	if panel.state_machine.owns_state(panel.state_machine.initial_state): roots.append(panel._graph_name(panel.state_machine.initial_state.name))
	for node in nodes: roots.append(node.name)
	for root in roots:
		if depths.has(root) or not adjacency.has(root): continue
		depths[root] = 0
		var queue: Array[StringName] = [root]
		var index := 0
		while index < queue.size():
			var from: StringName = queue[index]
			index += 1
			for to: StringName in adjacency[from]:
				if depths.has(to): continue
				depths[to] = depths[from] + 1
				queue.append(to)
	var source_widths := {}
	var router_widths := {}
	for node in nodes:
		var column: int = depths[node.name]
		source_widths[column] = maxf(source_widths.get(column, 0.0), maxf(node.size.x, node.get_combined_minimum_size().x))
	for router in panel.random_blocks.values():
		if router.transition == null: continue
		var from: StringName = panel._route_source(router.transition)
		if depths.has(from):
			var column: int = depths[from]
			router_widths[column] = maxf(router_widths.get(column, 0.0), maxf(router.size.x, router.get_combined_minimum_size().x))
	var columns := source_widths.keys()
	columns.sort()
	var column_x := {}
	var x := 0.0
	for column in columns:
		column_x[column] = x
		x += maxf(520, source_widths[column] + router_widths.get(column, 0.0) + 210)
	# Accumulate docked heights once, preserving each source's addition order.
	# Previously every State scanned all transition blocks (States x transitions).
	var heights := {}
	for node in nodes: heights[node.name] = node.size.y
	for block in panel.transition_blocks.values():
		if heights.has(block.dock_source):
			heights[block.dock_source] += maxf(block.size.y, block.get_combined_minimum_size().y)
	var rows := {}
	for node in nodes:
		var column: int = depths[node.name]
		var row: float = rows.get(column, 0.0)
		var height: float = heights[node.name]
		rows[column] = row + maxf(260, height + 70)
		node.position_offset = Vector2(column_x[column], row)
	panel._dock_blocks()
	var router_rows := {}
	for routing in panel.random_blocks:
		var block: GraphNode = panel.random_blocks[routing]
		if block.transition == null: continue
		var source: GraphNode = panel.graph.get_node_or_null(NodePath(panel._route_source(block.transition)))
		if source != null and depths.has(source.name):
			var column: int = depths[source.name]
			var chip: GraphNode = panel.transition_blocks[block.transition]
			var y := maxf(chip.position_offset.y, router_rows.get(column, 0.0))
			block.position_offset = Vector2(column_x[column] + source_widths[column] + 120, y)
			router_rows[column] = y + maxf(block.size.y, block.get_combined_minimum_size().y) + 50
