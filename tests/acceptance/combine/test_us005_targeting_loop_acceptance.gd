extends GutTest
## tests/acceptance/combine/test_us005_targeting_loop_acceptance.gd —
## FEAT-303 (Iteration O "Combine Selection UX"; CHECKLIST-3).
##
## Scripted acceptance-test evidence for US-005 ("As the system, once a
## Combine queue is confirmed, I must sequentially resolve EVERY sub-action's
## own targeting phase, in order_index order, regardless of how many entries
## the queue holds -- no hardcoded 2-phase/3-phase branching -- and invoke
## CombineActionController.execute() exactly once, only on full
## exhaustion").
##
## Exercises the REAL, already-shipped
## core/application/combine/multi_phase_targeting_controller.gd
## MultiPhaseTargetingController directly (the same class this feature's own
## design notes name as "the GENERALIZED N-length sequential targeting
## loop"), driven with fakes exactly like this project's own
## tests/unit/application/combine/test_multi_phase_targeting_controller.gd
## convention -- this suite exists to give the deployment-readiness
## checklist an explicit, individually-named, CI-verifiable trace back to
## US-005's own acceptance behavior, not to re-derive that unit coverage.
##
## Acceptance behavior verified:
##   1. A queue of length 2 resolves BOTH phases, in order_index order, and
##      invokes CombineActionController.execute() exactly once.
##   2. A queue of length 3 resolves ALL THREE phases, in order_index order,
##      via the EXACT SAME code path (no branch on entry count), and STILL
##      invokes CombineActionController.execute() exactly once.
##   3. execute() is NEVER reached when a mid-loop phase fails -- the loop
##      aborts immediately, later phases are never dispatched.

const MultiPhaseTargetingControllerClass = preload("res://core/application/combine/multi_phase_targeting_controller.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const SelectionDescriptorScript = preload("res://core/domain/combine/selection_descriptor.gd")


class FakeVerbController:
	extends "res://core/application/combine/verb_controller_port.gd"

	var verb_id: String
	var ok: bool
	var calls: Array = []

	func _init(p_verb_id: String, p_ok: bool = true) -> void:
		verb_id = p_verb_id
		ok = p_ok

	func enter_selection(context: Dictionary) -> Object:
		calls.append(context.get("order_index", 0))
		if not ok:
			return SelectionDescriptorScript.new(false, [], [], [], context.get("order_index", 0), {"error_code": "NO_LEGAL_OPTIONS"})
		return SelectionDescriptorScript.new(true, [], [], [], context.get("order_index", 0), {"chosen_value": verb_id})


class FakeCombineActionController:
	var execute_calls: Array = []

	func execute(payload: Dictionary) -> Dictionary:
		execute_calls.append(payload)
		return {"ok": true, "error_code": "", "actions_spent": 1, "stamina_spent": 1, "resolution_log": []}


func _entries(verb_ids: Array) -> Array:
	var entries: Array = []
	for i in range(verb_ids.size()):
		entries.append(VerbQueueEntryClass.new("q1", i, verb_ids[i]))
	return entries


# ══════════════════════════════════════════════════════════════════════════
# US-005, criterion 1 -- a length-2 queue resolves both phases in order and
# invokes execute() exactly once.
# ══════════════════════════════════════════════════════════════════════════

func test_us005_queue_length_2_resolves_both_phases_in_order_and_executes_once() -> void:
	var a := FakeVerbController.new("A")
	var b := FakeVerbController.new("B")
	var combine_action_controller := FakeCombineActionController.new()
	var mptc := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"A": a, "B": b},
		"combine_action_controller": combine_action_controller,
	})

	var result: Dictionary = mptc.execute(_entries(["A", "B"]), "actor_0", CombineQueueClass.Context.TURN)

	assert_true(result.get("ok", false), "US-005: a fully-resolved length-2 queue must return ok=true")
	assert_eq(a.calls, [0], "US-005: phase A (order_index 0) must be called exactly once, at its own order_index")
	assert_eq(b.calls, [1], "US-005: phase B (order_index 1) must be called exactly once, at its own order_index")
	assert_true(result.get("accumulated", {}).has("A"))
	assert_true(result.get("accumulated", {}).has("B"))
	assert_eq(combine_action_controller.execute_calls.size(), 1, "US-005: CombineActionController.execute() must be invoked EXACTLY ONCE, on full exhaustion")


# ══════════════════════════════════════════════════════════════════════════
# US-005, criterion 2 -- a length-3 queue resolves ALL THREE phases via the
# SAME code path (no hardcoded phase-count branch) and still executes once.
# ══════════════════════════════════════════════════════════════════════════

func test_us005_queue_length_3_resolves_all_phases_via_the_same_code_path_and_executes_once() -> void:
	var a := FakeVerbController.new("A")
	var b := FakeVerbController.new("B")
	var c := FakeVerbController.new("C")
	var combine_action_controller := FakeCombineActionController.new()
	var mptc := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"A": a, "B": b, "C": c},
		"combine_action_controller": combine_action_controller,
	})

	var result: Dictionary = mptc.execute(_entries(["A", "B", "C"]), "actor_0", CombineQueueClass.Context.TURN)

	assert_true(result.get("ok", false), "US-005: a fully-resolved length-3 queue must return ok=true -- the SAME MultiPhaseTargetingController code path, no phase-count branch")
	assert_eq(a.calls, [0])
	assert_eq(b.calls, [1])
	assert_eq(c.calls, [2], "US-005: a THIRD phase (order_index 2) must resolve identically to phases 0/1 -- no hardcoded 2-phase assumption")
	var accumulated: Dictionary = result.get("accumulated", {})
	assert_eq(accumulated.size(), 3, "US-005: all three phases' resolved selections must be present in accumulated")
	assert_eq(combine_action_controller.execute_calls.size(), 1, "US-005: CombineActionController.execute() must STILL be invoked EXACTLY ONCE for a length-3 queue")


# ══════════════════════════════════════════════════════════════════════════
# US-005, criterion 3 -- a mid-loop failure aborts before execute() is ever
# reached; later phases never dispatch.
# ══════════════════════════════════════════════════════════════════════════

func test_us005_mid_loop_failure_aborts_before_execute_and_before_later_phases() -> void:
	var a := FakeVerbController.new("A", true)
	var b := FakeVerbController.new("B", false)  # fails
	var c := FakeVerbController.new("C", true)
	var combine_action_controller := FakeCombineActionController.new()
	var mptc := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"A": a, "B": b, "C": c},
		"combine_action_controller": combine_action_controller,
	})

	var result: Dictionary = mptc.execute(_entries(["A", "B", "C"]), "actor_0", CombineQueueClass.Context.TURN)

	assert_false(result.get("ok", true), "US-005: a mid-loop phase failure must abort the whole targeting sequence")
	assert_eq(a.calls, [0], "US-005: phase A must have resolved before the failing phase B was reached")
	assert_eq(b.calls, [1], "US-005: phase B (the failing phase) must have been attempted")
	assert_eq(c.calls, [], "US-005: phase C must NEVER be reached once an earlier phase fails")
	assert_eq(combine_action_controller.execute_calls.size(), 0, "US-005: CombineActionController.execute() must NEVER be invoked on a partial/failed run")
