extends RefCounted

static func advance(machine: FiniteStateMachine, delta: float) -> void:
	if not machine._active or Engine.is_editor_hint() or not machine.is_inside_tree() or not is_instance_valid(machine.current_state):
		return
	var step := maxf(delta, 0.0) if is_finite(delta) else 0.0
	machine._policy_state_elapsed += step
	machine._policy_clock += step

static func remaining(machine: FiniteStateMachine, transition: StateTransition) -> float:
	return maxf(float(machine._cooldown_deadlines.get(transition, machine._policy_clock)) - machine._policy_clock, 0.0)

static func allows(machine: FiniteStateMachine, transition: StateTransition = null) -> bool:
	var item: Dictionary = machine._decision_trace.candidate(machine, transition) if machine._decision_trace != null else {}
	if transition != null and transition.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY:
		if not item.is_empty(): item.policies = {"status": "NOT_APPLICABLE"}
		return true
	if not is_instance_valid(machine.current_state): return machine._debug_block(transition, "FSM_INACTIVE")
	var minimum := machine.current_state.minimum_state_time
	var remaining := machine.get_transition_cooldown_remaining(transition) if transition != null else 0.0
	if not item.is_empty():
		item.policies = {"status": "FAILED", "minimum": minimum if is_finite(minimum) else -1.0,
			"elapsed": machine._policy_state_elapsed, "minimum_remaining": maxf(minimum - machine._policy_state_elapsed, 0.0) if is_finite(minimum) else 0.0,
			"interruptible": machine.current_state.interruptible, "can_interrupt": transition != null and transition.can_interrupt,
			"cooldown_remaining": remaining}
	if not is_finite(minimum) or minimum < 0.0: return machine._debug_block(transition, "INVALID_POLICY")
	if machine._policy_state_elapsed < minimum and not (transition != null and transition.can_interrupt and machine.current_state.interruptible):
		return machine._debug_block(transition, "STATE_NOT_INTERRUPTIBLE" if transition != null and transition.can_interrupt else "MINIMUM_STATE_TIME")
	if transition != null and (not is_finite(transition.cooldown) or transition.cooldown < 0.0): return machine._debug_block(transition, "INVALID_POLICY")
	if remaining > 0.0: return machine._debug_block(transition, "COOLDOWN")
	if not item.is_empty(): item.policies.status = "PASSED"
	return true

static func commit(machine: FiniteStateMachine, transition: StateTransition) -> void:
	if machine._decision_trace != null:
		var item: Dictionary = machine._decision_trace.candidate(machine, transition)
		if not item.is_empty(): item.assignment_committed = true; item.order.append("STATE_ASSIGNED")
	if transition != null and transition.source_mode != StateTransition.SourceMode.HIERARCHY_ENTRY and transition.cooldown > 0.0 and is_finite(transition.cooldown):
		machine._cooldown_deadlines[transition] = machine._policy_clock + transition.cooldown
