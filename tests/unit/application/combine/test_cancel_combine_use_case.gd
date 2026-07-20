extends GutTest
## tests/unit/application/combine/test_cancel_combine_use_case.gd
##
## GUT suite for FEAT-008 (Iteration O "Combine Selection UX"; US-008;
## FR-006): core/application/combine/cancel_combine_use_case.gd's
## CancelCombineUseCase.
##
## Verifies:
##   1. execute() transitions a BUILDING CombineQueue to CANCELLED and
##      reports {ok: true}.
##   2. execute() transitions a CONFIRMED CombineQueue to CANCELLED (a
##      targeting-phase cancel arrives against an already-CONFIRMED queue).
##   3. execute() transitions an EXECUTING CombineQueue to CANCELLED too
##      (any in-progress status is cancellable, per FR-006 "at any phase").
##   4. execute() degrades safely (ok=false, no crash) against a null queue.
##   5. execute() rejects (no re-mutation) an already-CANCELLED queue, and
##      an already-EXECUTED queue -- a terminal queue cannot be cancelled a
##      second time.
##   6. A cancelled queue is never reusable by a later ConfirmQueueUseCase
##      call -- the cross-use-case guarantee test_criteria calls for.

const CancelCombineUseCaseClass = preload("res://core/application/combine/cancel_combine_use_case.gd")
const ConfirmQueueUseCaseClass = preload("res://core/application/combine/confirm_queue_use_case.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")


func _queue_with_entries(entry_count: int, context: int = CombineQueueClass.Context.TURN) -> CombineQueueClass:
	var queue := CombineQueueClass.new("q1", "player_0", context)
	for i in range(entry_count):
		queue.add_entry(VerbQueueEntryClass.new("q1", i, "VERB_%d" % i))
	return queue


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1-3 — cancellation succeeds from every in-progress status.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_cancels_a_building_queue() -> void:
	var use_case := CancelCombineUseCaseClass.new()
	var queue := _queue_with_entries(1)

	var result: Dictionary = use_case.execute(queue)

	assert_true(result.get("ok", false), "cancelling a BUILDING queue must succeed")
	assert_eq(queue.status, CombineQueueClass.Status.CANCELLED, "a successful cancel must transition status to CANCELLED")


func test_execute_cancels_a_confirmed_queue() -> void:
	var use_case := CancelCombineUseCaseClass.new()
	var queue := _queue_with_entries(2)
	queue.status = CombineQueueClass.Status.CONFIRMED

	var result: Dictionary = use_case.execute(queue)

	assert_true(result.get("ok", false), "cancelling a CONFIRMED queue (mid targeting) must succeed")
	assert_eq(queue.status, CombineQueueClass.Status.CANCELLED)


func test_execute_cancels_an_executing_queue() -> void:
	var use_case := CancelCombineUseCaseClass.new()
	var queue := _queue_with_entries(2)
	queue.status = CombineQueueClass.Status.EXECUTING

	var result: Dictionary = use_case.execute(queue)

	assert_true(result.get("ok", false), "cancelling an EXECUTING queue must succeed -- any in-progress status is cancellable")
	assert_eq(queue.status, CombineQueueClass.Status.CANCELLED)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — safe degradation against a null queue.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_degrades_safely_with_null_queue() -> void:
	var use_case := CancelCombineUseCaseClass.new()

	var result: Dictionary = use_case.execute(null)

	assert_false(result.get("ok", true), "a null queue must degrade safely to ok=false, never crash")
	assert_eq(result.get("error_code", ""), "INVALID_QUEUE_STATE")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — a terminal (already CANCELLED/EXECUTED) queue is rejected,
# not re-cancelled.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_rejects_an_already_cancelled_queue() -> void:
	var use_case := CancelCombineUseCaseClass.new()
	var queue := _queue_with_entries(1)
	queue.status = CombineQueueClass.Status.CANCELLED

	var result: Dictionary = use_case.execute(queue)

	assert_false(result.get("ok", true), "cancelling an already-CANCELLED queue must be rejected, not re-cancelled")
	assert_eq(result.get("error_code", ""), "INVALID_QUEUE_STATE")


func test_execute_rejects_an_already_executed_queue() -> void:
	var use_case := CancelCombineUseCaseClass.new()
	var queue := _queue_with_entries(2)
	queue.status = CombineQueueClass.Status.EXECUTED

	var result: Dictionary = use_case.execute(queue)

	assert_false(result.get("ok", true), "cancelling an already-EXECUTED queue must be rejected")
	assert_eq(queue.status, CombineQueueClass.Status.EXECUTED, "an EXECUTED queue's status must never be overwritten by a late cancel attempt")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 — a cancelled queue is never reusable by ConfirmQueueUseCase.
# ══════════════════════════════════════════════════════════════════════════

func test_cancelled_queue_is_rejected_by_a_later_confirm_attempt() -> void:
	var cancel_use_case := CancelCombineUseCaseClass.new()
	var confirm_use_case := ConfirmQueueUseCaseClass.new()
	var queue := _queue_with_entries(2)

	var cancel_result: Dictionary = cancel_use_case.execute(queue)
	assert_true(cancel_result.get("ok", false))

	var confirm_result: Dictionary = confirm_use_case.execute(queue)

	assert_false(confirm_result.get("ok", true), "ConfirmQueueUseCase must reject a queue that has already been CANCELLED")
	assert_eq(confirm_result.get("error_code", ""), "INVALID_QUEUE_STATE")
	assert_eq(queue.status, CombineQueueClass.Status.CANCELLED, "a rejected confirm attempt must not resurrect the queue out of CANCELLED")
