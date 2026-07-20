## core/application/combine/cancel_combine_use_case.gd — CancelCombineUseCase
## (FEAT-008, Iteration O "Combine Selection UX"; US-008; FR-006).
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (core/domain/combine/combine_queue.gd's CombineQueue -- specifically its
## Status enum) — never an adapter/infrastructure/presentation type, and
## never the engine scene tree.
##
## Drives US-008's "clean cancellation with no partial-state leak" guarantee
## (design notes' error_handling: "Cancellation is NOT modelled as an error;
## CANCEL_SENTINEL on selection_resolved routes to CancelCombineUseCase which
## resets CombineQueue.status to CANCELLED and clears
## AccumulatedSelectionState, then hands control back to MainScene's Layer 1
## verb bar"). This is the ONE command-time gate every CANCEL_SENTINEL pick
## routes through, whether it fires during the queue-build pick loop
## (core/application/combine/build_verb_queue_use_case.gd, which now OFFERS
## this use case's own CANCEL_SENTINEL_ID in candidate_options once a queue
## has at least one entry in progress) or during any targeting phase
## (core/application/combine/multi_phase_targeting_controller.gd, which now
## short-circuits its own N-length loop the instant a phase's resolved
## selection equals CANCEL_SENTINEL_ID, aborting the WHOLE Combine rather
## than just that one phase) -- mirrors this project's established "one pure
## rule, referenced from every seam that needs it" convention
## (core/domain/combine/combine_actions.gd's own same-verb/Repeat rule,
## core/domain/combine/combine_queue.gd's own meets_confirm_minimum()).
##
## CANCEL_SENTINEL_ID lives HERE (rather than duplicated as a private
## constant on each of the two calling use cases, the way
## build_verb_queue_use_case.gd's own CONFIRM_SENTINEL_ID is a single-seam
## local constant) precisely BECAUSE this sentinel is shared across two
## distinct call sites (the queue-build loop AND the targeting loop) --
## a single source of truth for the sentinel string prevents those two
## seams from ever silently drifting onto different literal values.
##
## THIS FEATURE'S SCOPE (US-008): the queue-lifecycle transition ANY
## BUILDING/CONFIRMED/EXECUTING CombineQueue to CANCELLED, unconditionally
## discarding whatever entries/params it carries (no partial rollback logic
## -- the WHOLE queue is dead the instant this runs) so a later
## ConfirmQueueUseCase.execute() call against the SAME queue instance is
## rejected (INVALID_QUEUE_STATE) rather than silently resuming a
## conceptually-abandoned Combine. Discarding AccumulatedSelectionState
## itself is the CALLER's responsibility (this use case owns no reference to
## it -- design notes' data_model: "kept as a separate map rather than
## mutating VerbQueueEntry.params in place, so cancellation (US-008) can
## discard AccumulatedSelectionState wholesale without needing to also roll
## back CombineQueue"); multi_phase_targeting_controller.gd's own abort path
## is what actually drops its `accumulated` map to {} on a CANCEL_SENTINEL
## short-circuit (see that file's own doc).
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name CancelCombineUseCase
extends RefCounted

const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")

## CANCEL_SENTINEL_ID — the candidate_options "id" (build_verb_queue_use_case.gd)
## / resolved-selection value (multi_phase_targeting_controller.gd) that
## signals "abort the whole Combine", mirroring build_verb_queue_use_case.gd's
## own CONFIRM_SENTINEL_ID convention. Selecting this at ANY phase --
## queue-build or any targeting order_index -- routes to this use case's
## execute(), never treated as a domain error (design notes' error_handling).
const CANCEL_SENTINEL_ID: String = "CANCEL"


## execute(combine_queue) -> Dictionary{ok, error_code} — see file-level doc
## for the full contract.
##
## combine_queue — the CombineQueue instance being cancelled. A null queue
##                 degrades safely (ok=false, error_code="INVALID_QUEUE_STATE")
##                 rather than crashing.
##
## Returns:
##   {"ok": true, "error_code": ""} — combine_queue.status transitioned to
##                                     CANCELLED (the SOLE mutation this use
##                                     case ever performs). Valid from
##                                     BUILDING, CONFIRMED, or EXECUTING (any
##                                     status still "in progress" -- design
##                                     notes: "at ANY phase").
##   {"ok": false, "error_code": "INVALID_QUEUE_STATE"} — combine_queue is
##                                     null, or its status is already
##                                     CANCELLED or EXECUTED (defensive check
##                                     against double-cancelling an already
##                                     terminal queue -- no mutation, and no
##                                     re-emission of a second cancellation).
func execute(combine_queue) -> Dictionary:
	if combine_queue == null:
		return {"ok": false, "error_code": "INVALID_QUEUE_STATE"}

	if combine_queue.status == CombineQueueClass.Status.CANCELLED \
			or combine_queue.status == CombineQueueClass.Status.EXECUTED:
		return {"ok": false, "error_code": "INVALID_QUEUE_STATE"}

	combine_queue.status = CombineQueueClass.Status.CANCELLED
	return {"ok": true, "error_code": ""}
