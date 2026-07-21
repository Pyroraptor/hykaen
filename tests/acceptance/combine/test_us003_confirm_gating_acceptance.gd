extends GutTest
## tests/acceptance/combine/test_us003_confirm_gating_acceptance.gd —
## FEAT-303 (Iteration O "Combine Selection UX"; CHECKLIST-3).
##
## Scripted acceptance-test evidence for US-003 ("As a player, I must be
## offered a Confirm sentinel only once my Combine queue is long enough to
## be worth confirming (>=2 entries for a TURN-context queue), never
## before").
##
## Exercises the REAL, already-shipped
## core/domain/combine/combine_queue.gd CombineQueue.meets_confirm_minimum()
## domain rule AND the REAL
## core/application/combine/build_verb_queue_use_case.gd
## BuildVerbQueueUseCase's own query-time Confirm-sentinel offer (the seam a
## player's own pick loop actually drives) AND the REAL
## core/application/combine/confirm_queue_use_case.gd ConfirmQueueUseCase's
## own command-time gate (the seam a player's own Confirm press actually
## drives) -- proving query-time and command-time agree, never two
## independently-drifting copies of the same rule. Deeper coverage already
## lives in tests/unit/domain/combine/test_combine_queue.gd,
## tests/unit/application/combine/test_build_verb_queue_use_case.gd, and
## tests/unit/application/combine/test_confirm_queue_use_case.gd -- this
## suite exists to give the deployment-readiness checklist an explicit,
## individually-named, CI-verifiable trace back to US-003's own acceptance
## behavior.
##
## test_criteria (feature spec, verbatim): "test_us003 asserts Confirm
## sentinel absent at queue length 1 and present at length 2."

const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const BuildVerbQueueUseCaseClass = preload("res://core/application/combine/build_verb_queue_use_case.gd")
const ConfirmQueueUseCaseClass = preload("res://core/application/combine/confirm_queue_use_case.gd")

const STRIDE_RESOURCE_PATH: String = "res://data/verbs/stride.tres"
const STRIKE_RESOURCE_PATH: String = "res://data/verbs/strike.tres"
const CONFIRM_SENTINEL_ID: String = "CONFIRM"


class FakeVerbRegistryPort:
	extends "res://core/application/combine/verb_registry_port.gd"

	var _pool: Array

	func _init(pool: Array) -> void:
		_pool = pool

	func get_available_verbs(_actor, _context) -> Array:
		return _pool


func _option_ids(candidate_options: Array) -> Array:
	var ids: Array = []
	for option in candidate_options:
		ids.append(option.get("id"))
	return ids


func _pool() -> Array:
	return [ResourceLoader.load(STRIDE_RESOURCE_PATH), ResourceLoader.load(STRIKE_RESOURCE_PATH)]


# ══════════════════════════════════════════════════════════════════════════
# US-003 -- domain rule: meets_confirm_minimum() directly at length 1 vs 2.
# ══════════════════════════════════════════════════════════════════════════

func test_us003_meets_confirm_minimum_is_false_at_queue_length_1() -> void:
	assert_false(
		CombineQueueClass.meets_confirm_minimum(CombineQueueClass.Context.TURN, 1),
		"US-003: the TURN-context Confirm minimum must NOT be met at queue length 1"
	)


func test_us003_meets_confirm_minimum_is_true_at_queue_length_2() -> void:
	assert_true(
		CombineQueueClass.meets_confirm_minimum(CombineQueueClass.Context.TURN, 2),
		"US-003: the TURN-context Confirm minimum must be met at queue length 2"
	)


# ══════════════════════════════════════════════════════════════════════════
# US-003 -- query-time seam: BuildVerbQueueUseCase's own candidate_options
# offer at queue length 1 vs 2 (the REAL seam a player's pick loop drives).
# ══════════════════════════════════════════════════════════════════════════

func test_us003_confirm_sentinel_absent_from_candidate_options_at_queue_length_1() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_pool())
	var queue: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var descriptor = use_case.enter_selection(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	assert_eq(queue.size(), 1)
	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_false(ids.has(CONFIRM_SENTINEL_ID), "US-003: Confirm must be ABSENT at queue length 1")


func test_us003_confirm_sentinel_present_in_candidate_options_at_queue_length_2() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_pool())
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]

	var descriptor = use_case.enter_selection(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	assert_eq(queue.size(), 2)
	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_true(ids.has(CONFIRM_SENTINEL_ID), "US-003: Confirm must be PRESENT at queue length 2")


# ══════════════════════════════════════════════════════════════════════════
# US-003 -- command-time seam: ConfirmQueueUseCase agrees with the SAME
# minimum at length 1 (rejects) vs length 2 (accepts).
# ══════════════════════════════════════════════════════════════════════════

func test_us003_confirm_queue_use_case_rejects_at_queue_length_1() -> void:
	var queue := CombineQueueClass.new("q1", "player_0", CombineQueueClass.Context.TURN)
	queue.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))

	var result: Dictionary = ConfirmQueueUseCaseClass.new().execute(queue)

	assert_false(result.get("ok", true), "US-003: a queue of length 1 must be rejected by the command-time Confirm gate")
	assert_eq(result.get("error_code", ""), "VALIDATION_FAILED")
	assert_eq(queue.status, CombineQueueClass.Status.BUILDING, "US-003: a rejected confirm must not mutate status")


func test_us003_confirm_queue_use_case_accepts_at_queue_length_2() -> void:
	var queue := CombineQueueClass.new("q1", "player_0", CombineQueueClass.Context.TURN)
	queue.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))
	queue.add_entry(VerbQueueEntryClass.new("q1", 1, "STRIKE"))

	var result: Dictionary = ConfirmQueueUseCaseClass.new().execute(queue)

	assert_true(result.get("ok", false), "US-003: a queue of length 2 must be accepted by the command-time Confirm gate")
	assert_eq(queue.status, CombineQueueClass.Status.CONFIRMED, "US-003: an accepted confirm must transition status to CONFIRMED")
