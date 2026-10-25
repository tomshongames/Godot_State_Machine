@tool
extends VBoxContainer

const DATA := preload("res://addons/state_machine/runtime/decision_data.gd")
signal navigate_requested(record: Dictionary, candidate: Dictionary)
var summary: Label
var filter: OptionButton
var history: Tree
var details: Tree
var inspected: Dictionary = {}
var inspected_candidate: Dictionary = {}
var scope := ""
var rendering := false
var following := true
var follow_latest: CheckBox

func setup() -> void:
	var title := Label.new()
	title.text = "LAST DECISION"
	add_child(title)
	summary = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(summary)
	follow_latest = CheckBox.new()
	follow_latest.text = "Follow Latest"
	follow_latest.button_pressed = true
	follow_latest.toggled.connect(func(value): following = value)
	add_child(follow_latest)
	var disclosure := Button.new()
	disclosure.text = "Details"
	disclosure.toggle_mode = true
	disclosure.toggled.connect(func(value): details.visible = value)
	add_child(disclosure)
	details = Tree.new()
	details.hide_root = true
	details.custom_minimum_size.y = 180
	details.hide()
	add_child(details)
	filter = OptionButton.new()
	for label in ["All", "Committed", "Blocked", "Lost Priority"]: filter.add_item(label)
	add_child(filter)
	history = Tree.new()
	history.hide_root = true
	history.custom_minimum_size.y = 140
	history.item_selected.connect(_selected)
	add_child(history)

func render(records: Array, next_scope: String) -> void:
	if next_scope != scope:
		inspected.clear()
		inspected_candidate.clear()
		scope = next_scope
		following = true
		follow_latest.set_pressed_no_signal(true)
	rendering = true
	history.clear()
	var root := history.create_item()
	for record in records:
		var group := history.create_item(root)
		group.set_text(0, "#%d %.3fs %s%s" % [record.decision_sequence, record.time_usec / 1000000.0, record.request, " x%d" % record.repeat_count if record.repeat_count > 1 else ""])
		group.collapsed = true
		var count := 0
		for candidate in record.candidates:
			if filter.selected == 1 and not candidate.committed: continue
			if filter.selected == 2 and candidate.result not in ["BLOCKED", "COMMIT_INTERRUPTED"]: continue
			if filter.selected == 3 and candidate.reason not in ["LOWER_PRIORITY", "AUTHORED_ORDER"]: continue
			var row := history.create_item(group)
			row.set_text(0, "%s -> %s | %s" % [candidate.from, candidate.to, candidate.result])
			row.set_tooltip_text(0, candidate.reason)
			row.set_metadata(0, {"record": record, "candidate": candidate})
			count += 1
		if count == 0: group.free()
	if not records.is_empty() and (inspected.is_empty() or following):
		var record: Dictionary = records.back()
		var preferred: Array = record.candidates.filter(func(candidate): return candidate.selected)
		if preferred.is_empty(): preferred = record.candidates.filter(func(candidate): return candidate.reason != "TRIGGER_NOT_MET")
		if preferred.is_empty(): preferred = record.candidates
		if not preferred.is_empty(): inspect(record, preferred[0])
	elif records.is_empty():
		inspected.clear()
		inspected_candidate.clear()
		summary.text = "No transition decision captured."
		details.clear()
	rendering = false

func inspect(record: Dictionary, candidate: Dictionary) -> void:
	inspected = record.duplicate(true)
	inspected_candidate = candidate.duplicate(true)
	summary.text = "%s -> %s\n%s%s\n%s\nEvaluated in: %s / %s" % [candidate.from, candidate.to, candidate.result,
		" | " + candidate.reason.replace("_", " ") if not candidate.reason.is_empty() else "", record.get("path", ""), candidate.actual_state, record.get("state_elapsed", 0.0)]
	details.clear()
	var root := details.create_item()
	_section(root, "TRIGGER", candidate.trigger)
	var conditions := details.create_item(root)
	conditions.set_text(0, "CONDITIONS")
	conditions.collapsed = true
	_condition(conditions, candidate.conditions)
	_section(root, "POLICIES", candidate.policies)
	_section(root, "PRIORITY", {"priority": candidate.priority, "eligible": candidate.eligible, "selected": candidate.selected, "winner": candidate.get("winner", {})})
	if candidate.has("routing"): _section(root, "RANDOM ROUTING", candidate.routing)
	var effects := details.create_item(root)
	effects.set_text(0, "EFFECTS | %d executed" % candidate.effects.filter(func(effect): return effect.executed).size())
	effects.collapsed = true
	for effect in candidate.effects:
		_section(effects, ["BEFORE EXIT", "AFTER EXIT", "AFTER ENTER"][clampi(effect.timing, 0, 2)], effect)
	_section(root, "LIFECYCLE", {"reenter": candidate.reenter, "assignment_committed": candidate.assignment_committed, "complete": candidate.committed, "order": candidate.get("order", [])})

func _section(parent: TreeItem, name: String, fields: Dictionary) -> void:
	var section := details.create_item(parent)
	section.set_text(0, name)
	section.collapsed = true
	for key in fields:
		var row := details.create_item(section)
		row.set_text(0, "%s: %s" % [String(key).replace("_", " "), str(fields[key])])
		row.set_tooltip_text(0, row.get_text(0))

func _condition(parent: TreeItem, node: Dictionary) -> void:
	var row := details.create_item(parent)
	var label: String = node.get("kind", node.get("property", "Conditions"))
	row.set_text(0, "%s | %s%s" % [node.get("status", "SKIPPED"), label, " | NOT" if node.get("negated", false) else ""])
	if node.has("actual"):
		row.set_text(0, "%s | %s %s %s | Actual: %s" % [node.status, label, {0: "==", 1: "!=", 2: ">", 3: ">=", 4: "<", 5: "<="}.get(node.get("operator"), "?"), node.expected.text, node.actual.text])
	row.set_tooltip_text(0, row.get_text(0))
	for child in node.get("children", []): _condition(row, child)

func _selected() -> void:
	if rendering: return
	var row := history.get_selected()
	if row == null: return
	var data: Variant = row.get_metadata(0)
	if data is Dictionary:
		following = false
		follow_latest.set_pressed_no_signal(false)
		inspect(data.record, data.candidate)
		navigate_requested.emit(data.record, data.candidate)
