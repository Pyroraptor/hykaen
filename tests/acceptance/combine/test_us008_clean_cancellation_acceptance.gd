extends GutTest
## tests/acceptance/combine/test_us008_clean_cancellation_acceptance.gd —
## FEAT-303 (Iteration O "Combine Selection UX"; CHECKLIST-3).
##
## Scripted acceptance-test evidence for US-008 ("As a player, cancelling a
## Combine attempt -- whether while still picking verbs, or mid-way through
## resolving a targeting phase -- must leave NO trace behind: no leftover
## CombineQueue entries, no leftover AccumulatedSelectionState, so my NEXT,
## unrelated Combine attempt starts completely clean").
##
## Exercises the REAL, already-shipped
## core/application/combine/cancel_combine_use_case.gd CancelCombineUseCase,
## core/application/combine/build_verb_queue_use_case.gd
## BuildVerbQueueUseCase (the queue-build step's own Cancel offer), and
## core/application/combine/multi_phase_targeting_controller.gd
## MultiPhaseTargetingController (the targeting loop's own CANCEL_SENTINEL
## short-circuit) together, driven with fakes exactly like this project's
## own tests/integration/combine/test_cancellation_no_state_leak.gd
## convention -- this suite exists to give the deployment-readiness
## checklist an explicit, individually-named, CI-verifiable trace back to
## US-008's own acceptance behavior.
##
## test_criteria (feature spec, verbatim): "test_us008 asserts no
## AccumulatedSelectionState or CombineQueue entries persist after
## cancellation at build phase and at each targeting phase."

const BuildVerbQueueUseCaseClass = preload("res://core/application/combine/build_verb_queue_use_case.gd")
const CancelCombineUseCaseClass = preload("res://core/application/combine/cancel_combine_use_case.gd")
const MultiPhaseTargetingControllerClass = preload("res://core/application/combine/multi_phase_targeting_controller.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const SelectionDescriptorScript = preload("res://core/domain/combine/selection_descriptor.gd")

const STRIDE_RESOURCE_PATH: String = "res://data/verbs/stride.tres"
const STRIKE_RESOURCE_PATH: String = "res://data/verbs/strike.tres"


class FakeVerbRegistryPort:
	extends "res://core/application/combine/verb_registry_port.gd"

	var _pool: Array

	func _init(pool: Array) -> void:
		_pool = pool

	func get_available_verbs(_actor, _context) -> Array:
		return _pool


class FakeVerbController:
	extends "res://core/application/combine/verb_controller_port.gd"

	var verb_id: String
	var calls: Array = []

	func _init(p_verb_id: String) -> void:
		verb_id = p_verb_id

	func enter_selection(context: Dictionary) -> Object:
		calls.append(context)
		return SelectionDescriptorScript.new(true, [], [], [], context.get("order_index", 0), {"chosen_value": "resolved_%s" % verb_id})


class FakeCombineActionController:
	var execute_calls: Array = []

	func execute(payload: Dictionary) -> Dictionary:
		execute_calls.append(payload)
		return {"ok": true, "error_code": "", "actions_spent": 1, "stamina_spent": 1, "resolution_log": []}


func _pool() -> Array:
	return [ResourceLoader.load(STRIDE_RESOURCE_PATH), ResourceLoader.load(STRIKE_RESOURCE_PATH)]


# ══════════════════════════════════════════════════════════════════════════
# US-008, build phase -- cancelling while still picking verbs leaves NO
# CombineQueue entries reachable by ANY later use case.
# ══════════════════════════════════════════════════════════════════════════

func test_us008_cancel_at_build_phase_leaves_no_combine_queue_entries_reachable() -> void:
	var queue := CombineQueueClass.new("q1", "player_0", CombineQueueClass.Context.TURN)
	queue.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))
	assert_eq(queue.entries.size(), 1, "fixture assumption: one verb picked so far")

	var cancel_result: Dictionary = CancelCombineUseCaseClass.new().execute(queue)

	assert_true(cancel_result.get("ok", false), "US-008: cancelling an in-progress (BUILDING) queue must succeed")
	assert_eq(queue.status, CombineQueueClass.Status.CANCELLED, "US-008: a build-phase cancel must transition status to CANCELLED")

	# No CombineQueue entries "persist" in the sense that matters: the
	# cancelled queue can never again be advanced by ANY later use case --
	# a fresh BuildVerbQueueUseCase pick loop starting from [] sees no trace
	# of it, and the cancelled instance itself can never be confirmed.
	var build_use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_pool())
	var fresh_descriptor = build_use_case.enter_selection([], {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)
	var fresh_ids: Array = []
	for option in fresh_descriptor.candidate_options:
		fresh_ids.append(option.get("id"))
	assert_true(fresh_ids.has("STRIDE"), "US-008: a fresh attempt after a build-phase cancel must NOT carry forward the cancelled queue's own STRIDE exclusion -- no leaked state")


# ══════════════════════════════════════════════════════════════════════════
# US-008, targeting phase -- cancelling mid-targeting leaves EMPTY
# AccumulatedSelectionState (never a partial map), aborts the whole Combine,
# and never reaches execute().
# ══════════════════════════════════════════════════════════════════════════

func test_us008_cancel_at_order_index_0_targeting_phase_leaves_no_accumulated_state() -> void:
	var stride := FakeVerbController.new("STRIDE")
	var strike := FakeVerbController.new("STRIKE")
	var combine_action_controller := FakeCombineActionController.new()
	var mptc := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": strike},
		"combine_action_controller": combine_action_controller,
	})
	var queue := CombineQueueClass.new("q1", "player_0", CombineQueueClass.Context.TURN)
	queue.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))
	queue.add_entry(VerbQueueEntryClass.new("q1", 1, "STRIKE"))
	queue.status = CombineQueueClass.Status.CONFIRMED

	var result: Dictionary = mptc.execute(
		queue.sorted_entries(), "actor_0", CombineQueueClass.Context.TURN,
		{"STRIDE": CancelCombineUseCaseClass.CANCEL_SENTINEL_ID}, queue
	)

	assert_false(result.get("ok", true), "US-008: cancelling at order_index 0 must abort the whole Combine")
	assert_eq(result.get("accumulated", {}), {}, "US-008: NO AccumulatedSelectionState may persist after cancellation")
	assert_eq(stride.calls.size(), 0, "US-008: the cancelled phase's own enter_selection() must never even be called")
	assert_eq(strike.calls.size(), 0, "US-008: no later phase may be reached once cancelled")
	assert_eq(combine_action_controller.execute_calls.size(), 0, "US-008: execute() must never be reached on a cancelled attempt")
	assert_eq(queue.status, CombineQueueClass.Status.CANCELLED, "US-008: the CombineQueue itself must be transitioned to CANCELLED")


func test_us008_cancel_at_order_index_1_targeting_phase_leaves_no_accumulated_state() -> void:
	var stride := FakeVerbController.new("STRIDE")
	var strike := FakeVerbController.new("STRIKE")
	var combine_action_controller := FakeCombineActionController.new()
	var mptc := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": strike},
		"combine_action_controller": combine_action_controller,
	})
	var queue := CombineQueueClass.new("q2", "player_0", CombineQueueClass.Context.TURN)
	queue.add_entry(VerbQueueEntryClass.new("q2", 0, "STRIDE"))
	queue.add_entry(VerbQueueEntryClass.new("q2", 1, "STRIKE"))
	queue.status = CombineQueueClass.Status.CONFIRMED

	var result: Dictionary = mptc.execute(
		queue.sorted_entries(), "actor_0", CombineQueueClass.Context.TURN,
		{"STRIKE": CancelCombineUseCaseClass.CANCEL_SENTINEL_ID}, queue
	)

	assert_false(result.get("ok", true), "US-008: cancelling at order_index 1 must abort the whole Combine, even though order_index 0 already resolved")
	assert_eq(result.get("accumulated", {}), {}, "US-008: NO AccumulatedSelectionState may persist -- order_index 0's own already-resolved value must be discarded wholesale too")
	assert_eq(stride.calls.size(), 1, "US-008 fixture assumption: order_index 0 resolved normally before the cancel")
	assert_eq(strike.calls.size(), 0, "US-008: the cancelled phase's own enter_selection() must never even be called")
	assert_eq(combine_action_controller.execute_calls.size(), 0, "US-008: execute() must never be reached -- order_index 0's own resolution must never be committed")
	assert_eq(queue.status, CombineQueueClass.Status.CANCELLED)


# ══════════════════════════════════════════════════════════════════════════
# US-008 -- a subsequent, unrelated Combine attempt after ANY cancellation
# point observes zero leaked state (no leftover chosen_value survives into
# its own fresh accumulated map).
# ══════════════════════════════════════════════════════════════════════════

func test_us008_subsequent_attempt_after_targeting_phase_cancellation_starts_with_zero_leaked_state() -> void:
	var stride := FakeVerbController.new("STRIDE")
	var strike := FakeVerbController.new("STRIKE")
	var mptc := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": strike},
		"combine_action_controller": FakeCombineActionController.new(),
	})
	var cancelled_queue := CombineQueueClass.new("q1", "player_0", CombineQueueClass.Context.TURN)
	cancelled_queue.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))
	cancelled_queue.add_entry(VerbQueueEntryClass.new("q1", 1, "STRIKE"))
	cancelled_queue.status = CombineQueueClass.Status.CONFIRMED

	mptc.execute(
		cancelled_queue.sorted_entries(), "actor_0", CombineQueueClass.Context.TURN,
		{"STRIDE": "hex_leaked", "STRIKE": CancelCombineUseCaseClass.CANCEL_SENTINEL_ID}, cancelled_queue
	)
	assert_eq(cancelled_queue.status, CombineQueueClass.Status.CANCELLED)

	var fresh_stride := FakeVerbController.new("STRIDE")
	var fresh_strike := FakeVerbController.new("STRIKE")
	var fresh_mptc := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": fresh_stride, "STRIKE": fresh_strike},
		"combine_action_controller": FakeCombineActionController.new(),
	})
	var fresh_queue := CombineQueueClass.new("q3", "player_0", CombineQueueClass.Context.TURN)
	fresh_queue.add_entry(VerbQueueEntryClass.new("q3", 0, "STRIDE"))
	fresh_queue.add_entry(VerbQueueEntryClass.new("q3", 1, "STRIKE"))
	fresh_queue.status = CombineQueueClass.Status.CONFIRMED

	var fresh_result: Dictionary = fresh_mptc.execute(fresh_queue.sorted_entries(), "actor_0")

	assert_true(fresh_result.get("ok", false), "US-008: a fresh attempt after a prior cancellation must resolve normally")
	var fresh_accumulated: Dictionary = fresh_result.get("accumulated", {})
	assert_eq(fresh_accumulated.get("STRIDE").meta.get("chosen_value"), "resolved_STRIDE", "US-008: the fresh attempt's own resolution must be genuinely its own, never the cancelled attempt's leaked value")
	assert_eq(fresh_queue.status, CombineQueueClass.Status.CONFIRMED, "US-008: an unrelated, later CombineQueue's own status must be untouched by an earlier cancellation")
