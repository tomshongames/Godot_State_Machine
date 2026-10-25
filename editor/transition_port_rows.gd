@tool
extends RefCounted

const SUMMARIES := preload("res://addons/state_machine/editor/transitions_panel.gd")
const COLORS := preload("res://addons/state_machine/editor/transition_colors.gd")
const SEPARATOR := preload("res://addons/state_machine/editor/footer_separator.gd")
signal creation_requested
signal transition_selected(transition: StateTransition)
var rows: Array[MarginContainer] = []
var incoming_rows: Array[MarginContainer] = []
var separators: Array[Control] = []
var creation_row: MarginContainer
var creation_button: Button
var footer_controls: Array[Control] = []
var transitions: Array[StateTransition] = []
var incoming: Array[StateTransition] = []
var signature := ""
var fit_pending := false

func _queue_fit(node: GraphNode) -> void:
    if fit_pending: return
    fit_pending = true
    var owner := weakref(node)
    (func():
        fit_pending = false
        var card := owner.get_ref() as GraphNode
        if card != null and card.is_inside_tree(): card.reset_size()
    ).call_deferred()

func rebuild(node: GraphNode, values: Array[StateTransition], _interface: EditorInterface, input_enabled: bool, input_color: Color, incoming_values: Array[StateTransition] = [], allow_creation := true) -> void:
    if not node.minimum_size_changed.is_connected(_queue_fit.bind(node)):
        node.minimum_size_changed.connect(_queue_fit.bind(node))
    node.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    transitions = values.duplicate()
    incoming = incoming_values.duplicate()
    var identities: Array[int] = []
    var labels: Array[String] = []
    for route in incoming + transitions:
        identities.append(route.get_instance_id())
        labels.append(row_text(route, route in incoming))
    var next := str(identities) + str(labels) + str(incoming.size()) + str(allow_creation)
    node.set_slot(0, input_enabled, 0, input_color, false, 0, Color.WHITE)
    if next == signature:
        update_colors(node)
        return
    signature = next
    node.clear_all_slots()
    # Generic input 0 is reserved for creating connections, never used by curves.
    node.set_slot(0, input_enabled, 0, input_color, false, 0, Color.WHITE)
    for control in footer_controls:
        node.remove_child(control)
        control.queue_free()
    footer_controls.clear()
    rows.clear()
    incoming_rows.clear()
    separators.clear()
    creation_row = null
    creation_button = null
    for route in incoming:
        if not incoming_rows.is_empty(): _separator(node)
        var row := _row(node, route, true)
        incoming_rows.append(row)
        node.set_slot(row.get_index(), true, 0, COLORS.color(route), false, 0, Color.WHITE)
    if not incoming_rows.is_empty() and (not transitions.is_empty() or allow_creation):
        _separator(node, not transitions.is_empty())
    for route in transitions:
        if not rows.is_empty(): _separator(node)
        var row := _row(node, route, false)
        rows.append(row)
        node.set_slot(row.get_index(), false, 0, Color.WHITE, true, 0, COLORS.color(route))
    if allow_creation:
        if not rows.is_empty(): _separator(node)
        creation_row = MarginContainer.new()
        creation_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
        creation_row.set_meta("creation_row", true)
        creation_row.add_theme_constant_override("margin_left", 16)
        creation_row.add_theme_constant_override("margin_right", 16)
        var contents := HBoxContainer.new()
        creation_row.add_child(contents)
        creation_button = Button.new()
        creation_button.text = "+"
        creation_button.flat = true
        creation_button.tooltip_text = "Create an outgoing transition; or drag this row's output bubble."
        creation_button.pressed.connect(func(): creation_requested.emit())
        contents.add_child(creation_button)
        var caption := Label.new()
        caption.text = "New Transition"
        contents.add_child(caption)
        node.add_child(creation_row)
        footer_controls.append(creation_row)
        creation_row.gui_input.connect(func(event: InputEvent):
            if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.position.x < creation_row.size.x - 16:
                creation_row.accept_event()
                creation_requested.emit())
        node.set_slot(creation_row.get_index(), false, 0, Color.WHITE, true, 0, node.get_theme_color("font_color", "Label"))
    _queue_fit(node)

static func row_text(route: StateTransition, is_incoming: bool) -> String:
    var body := "→ %s · %s" % [route.source_label(), SUMMARIES.trigger_summary(route)] if is_incoming else "%s · %s →" % [SUMMARIES.trigger_summary(route), route.target_label()]
    return body + " · Disabled" if not route.enabled and is_incoming else (("Disabled · " if not route.enabled else "") + body)

func _row(node: GraphNode, route: StateTransition, is_incoming: bool) -> MarginContainer:
    var row := MarginContainer.new()
    node.add_child(row)
    row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    row.set_meta("transition", route)
    row.set_meta("incoming", is_incoming)
    row.add_theme_constant_override("margin_left", 16)
    row.add_theme_constant_override("margin_right", 16)
    var contents := HBoxContainer.new()
    contents.mouse_filter = Control.MOUSE_FILTER_PASS
    row.add_child(contents)
    var label := Label.new()
    label.text = row_text(route, is_incoming)
    label.tooltip_text = label.text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    contents.add_child(label)
    # Wrapping labels otherwise contribute almost no width while their initial
    # narrow allocation contributes a very tall minimum height to GraphNode.
    _measure_label(label)
    label.theme_changed.connect(_measure_inherited_label.bind(weakref(label)), CONNECT_DEFERRED)
    label.mouse_filter = Control.MOUSE_FILTER_PASS
    var accent := ColorRect.new()
    accent.custom_minimum_size = Vector2(8, 8)
    accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    accent.color = COLORS.color(route)
    accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
    contents.add_child(accent)
    footer_controls.append(row)
    row.gui_input.connect(func(event: InputEvent):
        if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.position.x > 16 and event.position.x < row.size.x - 16:
            row.accept_event()
            transition_selected.emit(route))
    return row

func _measure_label(label: Label) -> void:
    var font := label.get_theme_font("font")
    var font_size := label.get_theme_font_size("font_size")
    var scale := float(font_size) / 16.0
    label.custom_minimum_size = Vector2(clampf(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, 190.0 * scale, 320.0 * scale), ceilf(font.get_height(font_size)))

func _measure_inherited_label(reference: WeakRef) -> void:
    var label := reference.get_ref() as Label
    if label != null and label.is_inside_tree(): _measure_label(label)

func update_colors(node: GraphNode, changed: StateTransition = null) -> void:
    for row in incoming_rows + rows:
        var route: StateTransition = row.get_meta("transition")
        if changed != null and route != changed: continue
        row.get_child(0).get_child(1).color = COLORS.color(route)
        var is_incoming: bool = row.get_meta("incoming")
        node.set_slot(row.get_index(), is_incoming, 0, COLORS.color(route), not is_incoming, 0, COLORS.color(route))

func _separator(node: GraphNode, section := false) -> void:
    var separator := SEPARATOR.new()
    separator.section_boundary = section
    node.add_child(separator)
    footer_controls.append(separator)
    separators.append(separator)

func creation_port() -> int: return transitions.size()
func port_for(transition: StateTransition) -> int: return transitions.find(transition)
func input_port_for(transition: StateTransition) -> int:
    var index := incoming.find(transition)
    return index + 1 if index >= 0 else -1
