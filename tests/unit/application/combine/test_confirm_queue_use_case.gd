extends GutTest
## tests/unit/application/combine/test_confirm_queue_use_case.gd
##
## GUT suite for FEAT-003 (Iteration O "Combine Selection UX"; US-003;
## FR-002): core/application/combine/confirm_queue_use_case.gd's
## ConfirmQueueUseCase.
##
## Verifies:
##   1. execute() transitions a BUILDING CombineQueue with entries.size() at
##      or above the context-specific minimum (>=2 for TURN) to CONFIRMED
##      and reports {ok: true}.
##   2. execute() REJECTS confirmation when entries.size() is below the
##      minimum legal length -- {ok: false, error_code: "VALIDATION_FAILED"}
##      -- and leaves CombineQueue.status untouched (still BUILDING).
##   3. execute() degrades safely (ok=false, no crash, no mutation) against
##      a null queue and against a queue that is not currently BUILDING.

const ConfirmQueueUseCaseClass = preload("res://core/application/combine/confirm_queue_use_case.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")


func _queue_with_entries(entry_count: int, context: int = CombineQueueClass.Context.TURN) -> CombineQueueClass:
	var queue := CombineQueueClass.new("q1", "player_0", context)
	for i in range(entry_count):
		queue.add_entry(VerbQueueEntryClass.new("q1", i, "VERB_%d" % i))
	return queue


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — confirmation at/above the minimum length transitions status.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_transitions_building_to_confirmed_at_minimum_length() -> void:
	var use_case := ConfirmQueueUseCaseClass.new()
	var queue := _queue_with_entries(2)

	var result: Dictionary = use_case.execute(queue)

	assert_true(result.get("ok", false), "confirmation at the TURN minimum (2 entries) must succeed")
	assert_eq(queue.status, CombineQueueClass.Status.CONFIRMED, "a successful confirm must transition status to CONFIRMED")


func test_execute_transitions_building_to_confirmed_above_minimum_length() -> void:
	var use_case := ConfirmQueueUseCaseClass.new()
	var queue := _queue_with_entries(3)

	var result: Dictionary = use_case.execute(queue)

	assert_true(result.get("ok", false), "confirmation above the TURN minimum must succeed")
	assert_eq(queue.status, CombineQueueClass.Status.CONFIRMED)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — confirmation below the minimum length is rejected.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_rejects_confirmation_below_minimum_length() -> void:
	var use_case := ConfirmQueueUseCaseClass.new()
	var queue := _queue_with_entries(1)

	var result: Dictionary = use_case.execute(queue)

	assert_false(result.get("ok", true), "confirmation below the TURN minimum (1 entry) must be rejected")
	assert_eq(result.get("error_code", ""), "VALIDATION_FAILED")
	assert_eq(queue.status, CombineQueueClass.Status.BUILDING, "a rejected confirm must NOT mutate queue.status")


func test_execute_rejects_confirmation_at_empty_queue() -> void:
	var use_case := ConfirmQueueUseCaseClass.new()
	var queue := _queue_with_entries(0)

	var result: Dictionary = use_case.execute(queue)

	assert_false(result.get("ok", true), "confirmation at an empty queue must be rejected")
	assert_eq(queue.status, CombineQueueClass.Status.BUILDING)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — safe degradation against a null/non-BUILDING queue.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_degrades_safely_with_null_queue() -> void:
	var use_case := ConfirmQueueUseCaseClass.new()

	var result: Dictionary = use_case.execute(null)

	assert_false(result.get("ok", true), "a null queue must degrade safely to ok=false, never crash")


func test_execute_rejects_a_queue_that_is_not_building() -> void:
	var use_case := ConfirmQueueUseCaseClass.new()
	var queue := _queue_with_entries(2)
	queue.status = CombineQueueClass.Status.CONFIRMED

	var result: Dictionary = use_case.execute(queue)

	assert_false(result.get("ok", true), "confirming an already-CONFIRMED queue must be rejected, not re-confirmed")
	assert_eq(result.get("error_code", ""), "INVALID_QUEUE_STATE")
