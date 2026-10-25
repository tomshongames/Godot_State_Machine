@tool
extends EditorProperty

var state_ref: WeakRef
var actions: RefCounted
var toggle: CheckBox

func setup(state: State, editor_actions: RefCounted) -> void:
	name = "StateGraphVisibility"
	label = "Visible in Graph"
	tooltip_text = "Editor graph organization only. Hidden States still run, remain searchable and are validated."
	state_ref = weakref(state)
	actions = editor_actions
	toggle = CheckBox.new()
	toggle.tooltip_text = tooltip_text
	add_child(toggle)
	add_focusable(toggle)
	toggle.toggled.connect(_requested)
	actions.graph_visibility_changed.connect(_visibility_changed)
	_update_property()

func _update_property() -> void:
	if toggle == null: return
	var state := state_ref.get_ref() as State if state_ref != null else null
	var machine := FiniteStateMachine.machine_for_state(state) if is_instance_valid(state) else null
	toggle.disabled = read_only or actions == null or machine == null or not machine.owns_state(state)
	toggle.set_pressed_no_signal(not bool(state.get_meta(actions.HIDDEN_META, false)) if is_instance_valid(state) and actions != null else true)

func _set_read_only(value: bool) -> void:
	if toggle == null: return
	var state := state_ref.get_ref() as State if state_ref != null else null
	var machine := FiniteStateMachine.machine_for_state(state) if is_instance_valid(state) else null
	toggle.disabled = value or actions == null or machine == null or not machine.owns_state(state)

func _requested(value: bool) -> void:
	var state := state_ref.get_ref() as State if state_ref != null else null
	if actions == null or not is_instance_valid(state) or read_only: return
	var machine := FiniteStateMachine.machine_for_state(state)
	if machine == null or not machine.owns_state(state): _update_property(); return
	# The central action owns the one Undo entry. Do not emit_changed as well:
	# this is the existing metadata setting, not a second exported Node property.
	actions.set_graph_visible(machine, state, value)

func _visibility_changed(_machine: FiniteStateMachine, state: State) -> void:
	if state_ref != null and state_ref.get_ref() == state: _update_property()

func shutdown() -> void:
	if actions != null and actions.graph_visibility_changed.is_connected(_visibility_changed): actions.graph_visibility_changed.disconnect(_visibility_changed)
	actions = null
	state_ref = null
	if toggle != null: toggle.disabled = true
