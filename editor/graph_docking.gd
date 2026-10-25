@tool
extends RefCounted

# A docking pass owns only local lookup tables; the panel retains graph/history.
const BLOCK := preload("res://addons/state_machine/editor/transition_graph_block.gd")
const RANDOM_BLOCK := preload("res://addons/state_machine/editor/random_graph_block.gd")

static func arrange(panel) -> void:
	if panel.docking or not is_instance_valid(panel.graph) or not is_instance_valid(panel.state_machine): return
	panel.docking = true
	var offsets := {}
	var widths := {}
	var sources := {}
	var authored := {}
	for route in panel.state_machine.transitions: authored[route] = true
	for block in panel.transition_blocks.values():
		var source_name: StringName = block.draft_source if block.draft else panel._route_source(block.transition)
		if source_name.is_empty(): continue
		var source: GraphNode = sources.get(source_name)
		if source == null: source = panel.graph.get_node_or_null(NodePath(source_name)) as GraphNode
		if source == null: continue
		if not sources.has(source_name):
			sources[source_name] = source
			if not source.has_meta(&"fsm_dock_resize_watched"):
				source.set_meta(&"fsm_dock_resize_watched", true)
				source.resized.connect(panel._queue_dock_blocks)
			widths[source_name] = maxf(source.custom_minimum_size.x, source.get_combined_minimum_size().x)
		# The GraphNode's current width is authoritative, including a width we
		# applied on the previous docking pass. Do not mistake that stable value
		# for stale layout and shrink the source/stack on the next deferred pass.
		widths[source_name] = maxf(maxf(widths[source_name], source.size.x), block.required_dock_width())
	for block in panel._ordered_blocks():
		var route: StateTransition = block.transition
		var source_name: StringName = block.draft_source if block.draft else panel._route_source(route)
		block.source_movable = not block.draft and route != panel.fallback_entry and authored.has(route)
		block.draggable = not block.source_movable
		var source: GraphNode = sources.get(source_name)
		if source == null: continue
		if block.dock_source != source_name:
			block.dock_source = source_name
			block.update_color()
		var offset: float = offsets.get(source_name, 0.0)
		var width: float = widths[source_name]
		if not is_equal_approx(source.size.x, width): source.size.x = width
		block.set_dock_width(source.size.x)
		if panel.block_move.get("route") != route:
			block.position_offset = source.position_offset + Vector2(0, maxf(source.size.y, source.get_combined_minimum_size().y) + offset)
		offsets[source_name] = offset + maxf(block.size.y, block.get_combined_minimum_size().y)
	var preview: Dictionary = panel._insertion_preview()
	if not preview.is_empty() and preview.has("block") and is_instance_valid(preview.get("block")):
		var preview_block: GraphNode = preview.block
		var preview_source: GraphNode = preview.get("hover")
		if preview_source != null:
			preview_block.set_dock_width(widths.get(preview_source.name, preview_source.size.x))
	if not preview.is_empty() and preview.active and preview.hover != null:
		var groups := {}
		for block in panel._ordered_blocks():
			var source_name: StringName = block.draft_source if block.draft else panel._route_source(block.transition)
			if source_name.is_empty(): continue
			if not groups.has(source_name): groups[source_name] = []
			if block != preview.get("block"): groups[source_name].append(block)
		for source_name in groups:
			var source := panel.graph.get_node_or_null(NodePath(source_name)) as GraphNode
			if source == null: continue
			var offset := 0.0
			var index := 0
			for block in groups[source_name]:
				if source == preview.hover and index == preview.index:
					preview.gap = source.position_offset + Vector2(0, source.size.y + offset)
					offset += panel._insertion_height(preview)
				block.position_offset = source.position_offset + Vector2(0, source.size.y + offset)
				offset += maxf(block.size.y, block.get_combined_minimum_size().y)
				index += 1
			if source == preview.hover and index == preview.index:
				preview.gap = source.position_offset + Vector2(0, source.size.y + offset)
				offset += panel._insertion_height(preview)
			offsets[source_name] = offset
		if not groups.has(preview.hover.name):
			preview.gap = preview.hover.position_offset + Vector2(0, preview.hover.size.y)
			offsets[preview.hover.name] = panel._insertion_height(preview)
	for source in panel.graph.get_children():
		if not source is GraphNode or source is BLOCK or source is RANDOM_BLOCK or source == panel.exit_node: continue
		var height: float = offsets.get(source.name, 0.0)
		source.set_meta("dock_width", widths.get(source.name, source.size.x))
		if source.get_meta("dock_height", -1.0) != height:
			source.set_meta("dock_height", height)
			source.queue_redraw()
		if height > 0 and source.is_slot_enabled_right(0): source.set_slot_color_right(0, Color.TRANSPARENT)
	panel.docking = false
	panel._apply_graph_visibility()
	panel._queue_connection_redraw()

