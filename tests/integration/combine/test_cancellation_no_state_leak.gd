extends GutTest
## tests/integration/combine/test_cancellation_no_state_leak.gd — FEAT-008
## (Iteration O "Combine Selection UX"; US-008; FR-006): "Clean cancellation
## with no partial-state leak".
##
## Integration proof that core/application/combine/cancel_combine_use_case.gd's
## CancelCombineUseCase, wired into BOTH
## core/application/combine/build_verb_queue_use_case.gd's
## BuildVerbQueueUseCase (the queue-build pick loop's own Cancel-sentinel
## OFFER) and core/application/combine/multi_phase_targeting_controller.gd's
## MultiPhaseTargetingController (the targeting loop's own CANCEL_SENTINEL_ID
## short-circuit), drives a genuinely CLEAN cancellation at every phase a
## Combine attempt can be in -- never leaking a partial CombineQueue or
## AccumulatedSelectionState into a SUBSEQUENT, unrelated Combine attempt.
## Runs entirely against injected fakes (mirrors
## tests/unit/application/combine/test_multi_phase_targeting_controller.gd's
## own "no MainScene/SelectionOverlay" convention) -- these three use cases
## are exercised together, but never through the engine scene tree.
##
## test_criteria covered:
##   1. CANCEL_SENTINEL during the queue-build step discards the
##      in-progress queue and a subsequent fresh enter_selection() call
##      returns candidate_options equivalent to the Layer 1 verb bar's own
##      very-first-pick state (STRIDE/STRIKE both legal again -- no leaked
##      same-verb exclusion from the discarded queue).
##   2. CANCEL_SENTINEL during each targeting phase (order_index 0 and
##      order_index 1) aborts the ENTIRE Combine, not just the current
##      phase.
##   3. After cancellation at ANY point (queue-build step, order_index 0,
##      order_index 1), a subsequent Combine attempt starts with an EMPTY
##      AccumulatedSelectionState and a FRESH CombineQueue -- no leaked
##      prior chosen_value entries.
##   4. CombineQueue.status is set to CANCELLED and is never reused by a
##      later ConfirmQueueUseCase call.

const BuildVerbQueueUseCaseClass = preload("res://core/application/combine/build_verb_queue_use_case.gd")
const CancelCombineUseCaseClass = preload("res://core/application/combine/cancel_combine_use_case.gd")
const ConfirmQueueUseCaseClass = preload("res://core/application/combine/confirm_queue_use_case.gd")
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
	var chosen_value
	var calls: Array = []

	func _init(p_verb_id: String, p_chosen_value = null) -> void:
		verb_id = p_verb_id
		chosen_value = p_chosen_value

	func enter_selection(context: Dictionary) -> Object:
		calls.append(context)
		return SelectionDescriptorScript.new(true, [], [], [], context.get("order_index", 0), {"chosen_value": chosen_value})

	func execute(_payload: Dictionary) -> Dictionary:
		return {"ok": true, "error_code": "", "actions_spent": 0, "stamina_spent": 0, "resolution_log": []}


class FakeCombineActionController:
	var execute_calls: Array = []

	func execute(payload: Dictionary) -> Dictionary:
		execute_calls.append(payload)
		return {"ok": true, "error_code": "", "actions_spent": 1, "stamina_spent": 1, "resolution_log": []}


func _stride_and_strike_pool() -> Array:
	return [ResourceLoader.load(STRIDE_RESOURCE_PATH), ResourceLoader.load(STRIKE_RESOURCE_PATH)]


func _option_ids(candidate_options: Array) -> Array:
	var ids: Array = []
	for option in candidate_options:
		ids.append(option.get("id"))
	return ids


func _entries(verb_ids: Array) -> Array:
	var entries: Array = []
	for i in range(verb_ids.size()):
		entries.append(VerbQueueEntryClass.new("q1", i, verb_ids[i]))
	return entries


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — cancelling during the queue-build step discards the
# in-progress queue; a subsequent fresh attempt sees the Layer-1-equivalent
# candidate set.
# ══════════════════════════════════════════════════════════════════════════

func test_cancel_during_queue_build_discards_in_progress_queue_and_next_attempt_matches_layer1_state() -> void:
	var build_use_case := BuildVerbQueueUseCaseClass.new()
	var cancel_use_case := CancelCombineUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var actor := {"combatant_id": "player_0"}

	# The Layer 1 verb bar's own very-first-pick state (nothing built yet).
	var layer1_descriptor = build_use_case.enter_selection([], actor, CombineQueueClass.Context.TURN, port)

	# Start a real Combine attempt: pick STRIDE, confirming Cancel is now offered.
	var in_progress_queue := CombineQueueClass.new("q1", "player_0", CombineQueueClass.Context.TURN)
	in_progress_queue.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))
	var mid_build_descriptor = build_use_case.enter_selection(in_progress_queue.sorted_entries(), actor, CombineQueueClass.Context.TURN, port)
	var mid_build_ids: Array = _option_ids(mid_build_descriptor.candidate_options)
	assert_true(mid_build_ids.has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "an in-progress queue-build must offer the Cancel sentinel")
	assert_false(mid_build_ids.has("STRIDE"), "STRIDE must be excluded from the in-progress descriptor (already queued, no Repeat)")

	# The player picks Cancel: CancelCombineUseCase discards the in-progress queue.
	var cancel_result: Dictionary = cancel_use_case.execute(in_progress_queue)
	assert_true(cancel_result.get("ok", false))
	assert_eq(in_progress_queue.status, CombineQueueClass.Status.CANCELLED)

	# A SUBSEQUENT, fresh Combine attempt starts from an empty queue -- no
	# leaked STRIDE exclusion from the discarded attempt.
	var fresh_descriptor = build_use_case.enter_selection([], actor, CombineQueueClass.Context.TURN, port)
	assert_eq(_option_ids(fresh_descriptor.candidate_options), _option_ids(layer1_descriptor.candidate_options), "post-cancel, a fresh attempt's candidate_options must equal the Layer 1 verb bar's own very-first-pick state")
	assert_true(_option_ids(fresh_descriptor.candidate_options).has("STRIDE"), "STRIDE must be legal again in a fresh attempt -- the cancelled queue's own exclusion must not leak forward")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — cancelling during EITHER targeting phase (order_index 0 or
# 1) aborts the entire Combine, not just the current phase.
# ══════════════════════════════════════════════════════════════════════════

func test_cancel_during_order_index_0_targeting_phase_aborts_entire_combine() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var strike := FakeVerbController.new("STRIKE", "target_1")
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

	assert_false(result.get("ok", true))
	assert_eq(result.get("error_code", ""), "CANCELLED")
	assert_eq(stride.calls.size(), 0, "order_index 0's own enter_selection() must never be called once cancelled")
	assert_eq(strike.calls.size(), 0, "order_index 1 must never be reached -- the WHOLE Combine is aborted")
	assert_eq(combine_action_controller.execute_calls.size(), 0)
	assert_eq(queue.status, CombineQueueClass.Status.CANCELLED)


func test_cancel_during_order_index_1_targeting_phase_aborts_entire_combine() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var strike := FakeVerbController.new("STRIKE", "target_1")
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

	assert_false(result.get("ok", true))
	assert_eq(result.get("error_code", ""), "CANCELLED")
	assert_eq(stride.calls.size(), 1, "order_index 0 must still resolve normally before the cancelled phase is reached")
	assert_eq(strike.calls.size(), 0, "order_index 1's own enter_selection() must never be called once cancelled")
	assert_eq(combine_action_controller.execute_calls.size(), 0, "cancellation must abort BEFORE CombineActionController.execute() -- STRIDE's resolution must never be committed")
	assert_eq(queue.status, CombineQueueClass.Status.CANCELLED)


# ══════════════════════════════════════════════════════════════════════════
# Criteria 3-4 — after cancellation at ANY point, a subsequent Combine
# attempt starts with a fresh CombineQueue and empty AccumulatedSelectionState
# (no leaked prior chosen_value entries), and the cancelled queue is never
# reusable by ConfirmQueueUseCase.
# ══════════════════════════════════════════════════════════════════════════

func test_after_targeting_phase_cancellation_a_subsequent_attempt_starts_fresh_with_no_leaked_accumulated_state() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var strike := FakeVerbController.new("STRIKE", "target_1")
	var mptc := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": strike},
		"combine_action_controller": FakeCombineActionController.new(),
	})
	var cancelled_queue := CombineQueueClass.new("q1", "player_0", CombineQueueClass.Context.TURN)
	cancelled_queue.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))
	cancelled_queue.add_entry(VerbQueueEntryClass.new("q1", 1, "STRIKE"))
	cancelled_queue.status = CombineQueueClass.Status.CONFIRMED

	# order_index 1 cancels AFTER STRIDE (order_index 0) already resolved.
	var cancelled_result: Dictionary = mptc.execute(
		cancelled_queue.sorted_entries(), "actor_0", CombineQueueClass.Context.TURN,
		{"STRIDE": "hex_leaked", "STRIKE": CancelCombineUseCaseClass.CANCEL_SENTINEL_ID}, cancelled_queue
	)
	assert_eq(cancelled_result.get("accumulated", {}), {}, "the aborted attempt's own returned accumulated map must already be wholesale-empty")
	assert_eq(cancelled_queue.status, CombineQueueClass.Status.CANCELLED)

	# A SUBSEQUENT, unrelated Combine attempt: a brand-new CombineQueue and a
	# brand-new MultiPhaseTargetingController run against the SAME
	# controller_registry (controllers are reusable collaborators, not
	# per-attempt state) but must observe NO trace of the cancelled attempt.
	var fresh_stride := FakeVerbController.new("STRIDE", "hex_2")
	var fresh_strike := FakeVerbController.new("STRIKE", "target_2")
	var fresh_combine_action_controller := FakeCombineActionController.new()
	var fresh_mptc := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": fresh_stride, "STRIKE": fresh_strike},
		"combine_action_controller": fresh_combine_action_controller,
	})
	var fresh_queue := CombineQueueClass.new("q3", "player_0", CombineQueueClass.Context.TURN)
	fresh_queue.add_entry(VerbQueueEntryClass.new("q3", 0, "STRIDE"))
	fresh_queue.add_entry(VerbQueueEntryClass.new("q3", 1, "STRIKE"))
	fresh_queue.status = CombineQueueClass.Status.CONFIRMED

	var fresh_result: Dictionary = fresh_mptc.execute(fresh_queue.sorted_entries(), "actor_0")

	assert_true(fresh_result.get("ok", false), "a fresh attempt after a prior cancellation must resolve normally")
	var fresh_accumulated: Dictionary = fresh_result.get("accumulated", {})
	assert_eq(fresh_accumulated.get("STRIDE").meta.get("chosen_value"), "hex_2", "the fresh attempt's own accumulated value must be its OWN resolution, never the cancelled attempt's leaked 'hex_leaked'")
	assert_eq(fresh_accumulated.get("STRIKE").meta.get("chosen_value"), "target_2")
	assert_eq(fresh_combine_action_controller.execute_calls.size(), 1, "the fresh attempt must reach CombineActionController.execute() exactly once, fully independent of the cancelled attempt")
	assert_eq(fresh_queue.status, CombineQueueClass.Status.CONFIRMED, "a fresh CombineQueue's own status is untouched by an EARLIER, unrelated attempt's cancellation")


func test_cancelled_queue_from_targeting_phase_is_never_reusable_by_confirm_queue_use_case() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var mptc := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride},
		"combine_action_controller": FakeCombineActionController.new(),
	})
	var queue := CombineQueueClass.new("q1", "player_0", CombineQueueClass.Context.TURN)
	queue.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))
	queue.status = CombineQueueClass.Status.CONFIRMED

	mptc.execute(
		queue.sorted_entries(), "actor_0", CombineQueueClass.Context.TURN,
		{"STRIDE": CancelCombineUseCaseClass.CANCEL_SENTINEL_ID}, queue
	)
	assert_eq(queue.status, CombineQueueClass.Status.CANCELLED)

	var confirm_result: Dictionary = ConfirmQueueUseCaseClass.new().execute(queue)
	assert_false(confirm_result.get("ok", true), "a CANCELLED queue must never be resurrected by a later ConfirmQueueUseCase call")
	assert_eq(confirm_result.get("error_code", ""), "INVALID_QUEUE_STATE")
	assert_eq(queue.status, CombineQueueClass.Status.CANCELLED, "the rejected confirm attempt must not mutate status away from CANCELLED")
