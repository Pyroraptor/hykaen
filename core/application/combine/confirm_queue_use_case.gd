## core/application/combine/confirm_queue_use_case.gd — ConfirmQueueUseCase
## (FEAT-003, Iteration O "Combine Selection UX"; US-003; FR-002).
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (core/domain/combine/combine_queue.gd's CombineQueue -- specifically its
## Status enum and its meets_confirm_minimum() static domain rule, the SAME
## seam core/application/combine/build_verb_queue_use_case.gd's
## enter_selection() already routes the Confirm-sentinel query-time gate
## through) — never an adapter/infrastructure/presentation type, and never
## the engine scene tree.
##
## Drives the SECOND half of US-003 (design notes' architecture section,
## "ConfirmQueueUseCase (US-003): finalizes CombineQueue and hands off to
## targeting"): the command-time counterpart to BuildVerbQueueUseCase's
## query-time Confirm-sentinel offer. Both seams route through
## CombineQueue.meets_confirm_minimum() -- ONE domain rule evaluated twice,
## never two independently-maintained copies of the same minimum-length
## check (mirrors core/domain/combine/combine_actions.gd's own
## query-time/command-time "one pure function called twice" convention for
## the same-verb/Repeat rule).
##
## THIS FEATURE'S SCOPE (US-003): finalizing CombineQueue.status from
## BUILDING to CONFIRMED once the context-specific minimum queue length is
## met, and REJECTING (no mutation) a confirmation attempted below that
## minimum or against a queue not currently BUILDING. The actual hand-off to
## targeting (design notes' MultiPhaseTargetingController) is a later
## feature (US-005/US-006) layered on top of this same CONFIRMED status
## transition, without changing this use case's shape.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name ConfirmQueueUseCase
extends RefCounted

const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")


## execute(combine_queue) -> Dictionary{ok, error_code} — see file-level doc
## for the full contract.
##
## combine_queue — the CombineQueue instance being confirmed. A null queue
##                 degrades safely (ok=false, error_code="INVALID_QUEUE_STATE")
##                 rather than crashing.
##
## Returns:
##   {"ok": true, "error_code": ""} — combine_queue.status transitioned
##                                     BUILDING -> CONFIRMED (the SOLE
##                                     mutation this use case ever performs).
##   {"ok": false, "error_code": "INVALID_QUEUE_STATE"} — combine_queue is
##                                     null, or its status is not currently
##                                     BUILDING (defensive check against a
##                                     stale/already-finalized queue; no
##                                     mutation).
##   {"ok": false, "error_code": "VALIDATION_FAILED"} — combine_queue.status
##                                     is BUILDING but entries.size() is
##                                     below CombineQueue.meets_confirm_minimum()'s
##                                     context-specific minimum; no mutation.
func execute(combine_queue) -> Dictionary:
	if combine_queue == null:
		return {"ok": false, "error_code": "INVALID_QUEUE_STATE"}

	if combine_queue.status != CombineQueueClass.Status.BUILDING:
		return {"ok": false, "error_code": "INVALID_QUEUE_STATE"}

	var entry_count: int = combine_queue.entries.size()
	if not CombineQueueClass.meets_confirm_minimum(combine_queue.context, entry_count):
		return {"ok": false, "error_code": "VALIDATION_FAILED"}

	combine_queue.status = CombineQueueClass.Status.CONFIRMED
	return {"ok": true, "error_code": ""}
