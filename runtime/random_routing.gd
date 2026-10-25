@tool
class_name StateRandomRouting
extends Resource

## Weighted destination selection used by a StateTransition with target_mode RANDOM.
## EQUAL ignores stored percentages. PERCENTAGES requires finite values in [0,100]
## whose total is 100. Branch order and Resource identity are preserved.

enum Mode { EQUAL, PERCENTAGES }
@export var mode: Mode = Mode.EQUAL:
	set(value):
		mode = value
		emit_changed()
@export var branches: Array[StateRandomTarget] = []:
	set(value):
		branches = value
		emit_changed()

## Returns an actionable validation message, or an empty String if valid.
func configuration_error() -> String:
	if branches.is_empty(): return "Random routing has no destinations."
	if mode not in [Mode.EQUAL, Mode.PERCENTAGES]: return "Random routing mode is invalid."
	var total := 0.0
	for branch in branches:
		if branch == null or branch.target_state.is_empty(): return "Random routing has an unconnected destination."
		if mode == Mode.PERCENTAGES:
			if not is_finite(branch.percentage) or branch.percentage < 0 or branch.percentage > 100: return "Random percentages must be finite and between 0 and 100."
			total += branch.percentage
	if mode == Mode.PERCENTAGES and absf(total - 100.0) > 0.0001:
		return "Random transition percentages total %s%%; expected 100%%." % str(total)
	return ""

# Pure deterministic selection; production supplies an instance-owned RNG roll.
## Selects from a finite roll in [0,1). Returns a diagnostic result Dictionary,
## or an empty Dictionary for invalid routing/roll; does not mutate branches.
func select(roll: float) -> Dictionary:
	if not configuration_error().is_empty() or not is_finite(roll) or roll < 0 or roll >= 1: return {}
	var cumulative := 0.0
	var values: Array[Dictionary] = []
	var selected := -1
	for i in branches.size():
		var chance := 100.0 / branches.size() if mode == Mode.EQUAL else branches[i].percentage
		values.append({"target": String(branches[i].target_state), "percentage": chance})
		cumulative += chance / 100.0
		if selected < 0 and chance > 0 and roll < cumulative: selected = i
	if selected < 0:
		for i in range(branches.size() - 1, -1, -1):
			if mode == Mode.EQUAL or branches[i].percentage > 0: selected = i; break
	return {"mode": "Equal" if mode == Mode.EQUAL else "Percentages", "roll": roll, "branches": values, "selected_index": selected, "selected_target": String(branches[selected].target_state)}
