## core/application/combine/multi_phase_targeting_controller.gd —
## MultiPhaseTargetingController (FEAT-005, Iteration O "Combine Selection
## UX"; US-005; FR-004/FR-013; NFR-002/NFR-003).
##
## Application layer (Clean Architecture, ADR-001): depends on domain
## (implicitly, via the CombineQueue/VerbQueueEntry-shaped entries it
## iterates — this file performs no domain rule evaluation of its own,
## design notes: "No phase-count branching — loop bound is
## len(queue.entries)") and its own sibling application-layer port
## (core/application/combine/verb_controller_port.gd's VerbControllerPort)
## — never an adapter/infrastructure/presentation type, and never the
## engine scene tree. Every controller in its injected registry is reached
## by name (verb_id -> VerbControllerPort-shaped collaborator), duck-typed
## exactly like core/application/combine/verb_registry_port.gd's own
## established convention — a concrete registrant need not literally
## `extends VerbControllerPort`.
##
## THIS FEATURE'S SCOPE (US-005): the GENERALIZED N-length sequential
## targeting loop — design notes' architecture section: "orchestrates the
## N-length sequential targeting loop — for each entry by order_index, call
## VerbControllerPort.enter_selection(context) ... store
## accumulated[verb_id]=value, advance. No phase-count branching — loop
## bound is len(queue.entries). On exhaustion it invokes
## CombineActionController.execute()." A confirmed queue of ANY length (2,
## 3, or more) drives the EXACT SAME code path — this file contains no
## `if entries.size() == 2` / `== 3` branch anywhere (this feature's own
## test_criteria: "verified by parameterized test over queue length 2 and 3
## with identical controller code path"). The presentation-layer callback
## wiring that lets a REAL player resolve each phase through
## SelectionOverlay (design notes: "await the resolved value via an
## injected callback ... only a thin presentation Port") is a LATER feature
## (US-006) layered on top of this same seam — this feature's own
## `enter_selection()` call is treated as already yielding the resolved
## SelectionDescriptor (exactly the shape this feature's own test suite's
## fakes return), matching this feature's description: "invoking each verb
## controller's real enter_selection(), storing results in an accumulated
## map."
##
## Failure mid-loop (design notes' error_handling: "Sub-action resolution
## failure mid-loop ... MultiPhaseTargetingController treats this as an
## abort trigger equivalent to cancellation ... no sub-action side effects
## are applied until ALL targeting is resolved") aborts the loop
## immediately — `execute()` (below) is NEVER reached on that path, so
## CombineActionController.execute() is invoked ONLY on full loop
## exhaustion (this feature's own test_criteria), never on a partial/failed
## run.
##
## FEAT-008 (US-008; FR-006) — cancellation, at ANY phase, aborts the WHOLE
## Combine: this feature's own `resolved_selections` seam (a verb_id's
## already-resolved selection input, forwarded from a real per-phase UI
## resolution, FEAT-006) is where a CANCEL_SENTINEL pick surfaces. Before
## dispatching a given phase's controller, `execute()` below checks whether
## `resolved_selections` carries
## core/application/combine/cancel_combine_use_case.gd's
## CancelCombineUseCase.CANCEL_SENTINEL_ID for that phase's own verb_id --
## if so, the loop short-circuits immediately (that phase's own
## enter_selection() is NEVER called, no side effect, mirroring the
## unregistered-verb-id abort's "abort BEFORE dispatch" discipline),
## invokes CancelCombineUseCase.execute() against the optional injected
## `combine_queue` aggregate (transitioning its status to CANCELLED so a
## later ConfirmQueueUseCase.execute() against that SAME instance is
## rejected -- this feature's own test_criteria), and returns `accumulated`
## as an EMPTY Dictionary regardless of how many phases had already resolved
## -- design notes' data_model: "cancellation ... can discard
## AccumulatedSelectionState wholesale" -- never a partial map a caller
## might mistake for a resumable in-progress state.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage:
##   var controller := MultiPhaseTargetingController.new({
##       "controller_registry": {"STRIDE": stride_controller, "STRIKE": strike_controller},
##       "combine_action_controller": combine_action_controller,
##   })
##   var result: Dictionary = controller.execute(queue.sorted_entries(), actor, CombineQueue.Context.TURN)
##   # {"ok": true, "accumulated": {"STRIDE": <SelectionDescriptor>, "STRIKE": <SelectionDescriptor>},
##   #  "execution_result": {"ok": true, "error_code": "", "actions_spent": 1, "stamina_spent": 1, "resolution_log": []}}

class_name MultiPhaseTargetingController
extends RefCounted

const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const CancelCombineUseCaseClass = preload("res://core/application/combine/cancel_combine_use_case.gd")


## verb_id -> VerbControllerPort-shaped collaborator (duck-typed — see
## file-level doc). Looked up strictly by the entry's OWN verb_id — an
## unregistered verb_id aborts the loop (see execute()'s own doc) rather
## than dispatching to an arbitrary/guessed controller (design notes'
## security section: "verb_id whitelisting").
var _controller_registry: Dictionary

## The CombineActionController (or an equivalent duck-typed collaborator
## exposing `execute(payload) -> Dictionary`) invoked EXACTLY ONCE, and
## ONLY on full loop exhaustion (see execute()'s own doc).
var _combine_action_controller


func _init(deps: Dictionary = {}) -> void:
	_controller_registry = deps.get("controller_registry", {})
	_combine_action_controller = deps.get("combine_action_controller")


## execute(queue_entries, actor, context, resolved_selections) -> Dictionary{ok,
## error_code, accumulated, execution_result}
##
## queue_entries — Array of VerbQueueEntry (or equivalent
##                 {"verb_id":..., "order_index":...} Dictionaries — see
##                 core/application/combine/validate_combine_queue_use_case.gd's
##                 own `queue_entries` contract for the accepted shapes)
##                 belonging to a CONFIRMED CombineQueue. Walked in
##                 order_index order (authoritative — NEVER insertion
##                 order, mirrors core/domain/combine/combine_queue.gd's
##                 CombineQueue.sorted_entries() convention), regardless of
##                 how many entries it holds (NO phase-count branching).
## actor         — the combatant driving this Combine; forwarded verbatim
##                 to every phase's `enter_selection()` context Dictionary
##                 and to the final `execute()` payload.
## context       — one of core/domain/combine/combine_queue.gd's
##                 CombineQueue.Context enum members (TURN|REACTION);
##                 defaults to TURN when omitted, forwarded verbatim.
## resolved_selections — FEAT-006 (US-006; FR-005; ADR-006): optional
##                 Dictionary of verb_id -> already-resolved selection input
##                 (e.g. {"STRIDE": chosen_hex}), forwarded onto that phase's
##                 own `enter_selection()` context Dictionary as
##                 `"selected_hex"` when present for that verb_id. This is
##                 the seam a future SelectionOverlay-driven UI wiring will
##                 populate from real player input (see this file's own
##                 file-level doc's "await the resolved value via an
##                 injected callback" note); for now it lets a caller (or a
##                 test) drive this loop to a genuinely resolved multi-phase
##                 outcome without a live UI. Defaults to {} — every
##                 pre-existing caller is completely unaffected. FEAT-008
##                 (US-008; FR-006): a verb_id mapped to
##                 CancelCombineUseCase.CANCEL_SENTINEL_ID signals that
##                 phase's own resolution came back as a Cancel pick,
##                 short-circuiting the WHOLE loop (see `combine_queue`
##                 below and file-level doc).
## combine_queue — FEAT-008 (US-008; FR-006): optional CombineQueue
##                 aggregate (core/domain/combine/combine_queue.gd) this
##                 confirmed `queue_entries` belongs to. Forwarded to
##                 CancelCombineUseCase.execute() ONLY when a
##                 CANCEL_SENTINEL_ID short-circuit fires, so its `.status`
##                 is transitioned to CANCELLED and a later
##                 ConfirmQueueUseCase.execute() call against the SAME
##                 instance is rejected. Defaults to null — every
##                 pre-existing caller (none of which ever cancels) is
##                 completely unaffected.
##
## Returns:
##   {"ok": true, "error_code": "", "accumulated": {<verb_id>: <SelectionDescriptor>, ...},
##    "execution_result": <CombineActionController.execute()'s own return Dictionary>}
##       — every phase resolved (`ok:true`) and CombineActionController.execute()
##       ran exactly once (its own `ok` is NOT re-interpreted here — callers
##       inspect `execution_result.ok` for the DEF-001/economy outcome).
##   {"ok": false, "error_code": "UNREGISTERED_VERB", "accumulated": {...so far...},
##    "execution_result": {}}
##       — `queue_entries` referenced a verb_id absent from
##       `_controller_registry`; the loop aborts BEFORE calling that (missing)
##       controller, and CombineActionController.execute() is NEVER reached.
##   {"ok": false, "error_code": <the failing phase's own error_code, default
##    "NO_LEGAL_OPTIONS">, "accumulated": {...so far...}, "execution_result": {}}
##       — a phase's own `enter_selection()` returned `ok:false` (or null);
##       the loop aborts at that phase and CombineActionController.execute()
##       is NEVER reached (error_handling: "no sub-action side effects are
##       applied until ALL targeting is resolved").
##   {"ok": false, "error_code": "CANCELLED", "accumulated": {}, "execution_result": {}}
##       — FEAT-008: `resolved_selections` carried CANCEL_SENTINEL_ID for the
##       CURRENT phase's own verb_id; the loop aborts BEFORE that phase's own
##       enter_selection() is ever called, `combine_queue` (if given) is
##       transitioned to CANCELLED via CancelCombineUseCase, and
##       `accumulated` is WHOLESALE-DISCARDED (always {}, regardless of how
##       many earlier phases had already resolved) — never a partial map, per
##       this feature's own "no partial-state leak" guarantee.
func execute(queue_entries: Array, actor, context: int = CombineQueueClass.Context.TURN, resolved_selections: Dictionary = {}, combine_queue = null) -> Dictionary:
	var accumulated: Dictionary = {}

	for entry in _sorted_by_order_index(queue_entries):
		var verb_id: String = _verb_id_of(entry)
		if _is_cancel_sentinel(resolved_selections.get(verb_id)):
			return _cancelled_result(combine_queue)

		var controller = _controller_registry.get(verb_id)
		if controller == null:
			return _abort_result("UNREGISTERED_VERB", accumulated)

		var selection_context: Dictionary = {
			"actor_id": actor,
			"mode": "TARGET_PHASE",
			"combine_context": context,
			"order_index": _order_index_of(entry),
			"verb_id": verb_id,
			"accumulated": accumulated,
		}
		if resolved_selections.has(verb_id):
			selection_context["selected_hex"] = resolved_selections[verb_id]
		var descriptor = controller.enter_selection(selection_context)
		if descriptor == null or not descriptor.ok:
			return _abort_result(_error_code_of(descriptor), accumulated)

		accumulated[verb_id] = descriptor

	var execution_result: Dictionary = {}
	if _combine_action_controller != null:
		execution_result = _combine_action_controller.execute({
			"queue": queue_entries,
			"actor": actor,
			"context": context,
			"accumulated": accumulated,
		})

	return {
		"ok": true,
		"error_code": "",
		"accumulated": accumulated,
		"execution_result": execution_result,
	}


## _abort_result(error_code, accumulated) -> Dictionary — the SOLE
## mid-loop-abort shape constructor this file uses (see execute()'s own
## doc), so an unregistered verb_id and a failed phase report the SAME
## {ok:false, execution_result:{}} shape — CombineActionController.execute()
## is provably unreached on either path (it is never even referenced in
## this method's body).
func _abort_result(error_code: String, accumulated: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"error_code": error_code,
		"accumulated": accumulated,
		"execution_result": {},
	}


## _cancelled_result(combine_queue) -> Dictionary — FEAT-008 (US-008;
## FR-006): the sole CANCEL_SENTINEL_ID short-circuit result constructor.
## Routes `combine_queue` (when given) through
## core/application/combine/cancel_combine_use_case.gd's
## CancelCombineUseCase.execute() so its `.status` is authoritatively
## transitioned to CANCELLED (this use case's own return value is
## intentionally not surfaced here -- a defensive double-cancel rejection
## from CancelCombineUseCase does not change THIS method's own CANCELLED
## outcome, since the loop itself is unconditionally aborting either way).
## `accumulated` is ALWAYS returned empty ({}), never `_abort_result()`'s own
## "accumulated so far" -- design notes' data_model: cancellation discards
## AccumulatedSelectionState WHOLESALE, so no earlier phase's resolved value
## survives into the returned Dictionary a caller might otherwise mistake
## for a resumable partial state.
## _is_cancel_sentinel(value) -> bool — true iff `value` (a
## `resolved_selections[verb_id]` entry, which may legitimately be a hex
## coordinate Object/String/int or any other verb-specific chosen-value
## shape — see this file's own `resolved_selections` doc) IS
## CancelCombineUseCase.CANCEL_SENTINEL_ID. Guards with a `typeof()` check
## BEFORE the `==` comparison because GDScript 4 raises a runtime script
## error ("Invalid operands 'Object' and 'String' in operator '=='") when a
## real resolved value is a non-primitive Object (e.g. a HexCoord) compared
## directly against a String literal — this file must never crash on an
## ordinary, non-cancelling resolved selection of ANY shape.
func _is_cancel_sentinel(value) -> bool:
	return typeof(value) == TYPE_STRING and value == CancelCombineUseCaseClass.CANCEL_SENTINEL_ID


func _cancelled_result(combine_queue) -> Dictionary:
	if combine_queue != null:
		CancelCombineUseCaseClass.new().execute(combine_queue)
	return {
		"ok": false,
		"error_code": "CANCELLED",
		"accumulated": {},
		"execution_result": {},
	}


## _error_code_of(descriptor) -> String — reads a failed phase's own
## error_code off its SelectionDescriptor.meta (build_verb_queue_use_case.gd's
## own established convention: `{"error_code": "NO_LEGAL_OPTIONS"}` on a
## failed descriptor's `meta`), defaulting to "NO_LEGAL_OPTIONS" when the
## descriptor is null or carries none (design notes' error_handling: a
## failed sub-action phase is NO_LEGAL_OPTIONS unless the controller says
## otherwise).
func _error_code_of(descriptor) -> String:
	if descriptor == null:
		return "NO_LEGAL_OPTIONS"
	return descriptor.meta.get("error_code", "NO_LEGAL_OPTIONS")


## _verb_id_of(entry) -> String — duck-typed verb_id accessor mirroring
## core/application/combine/validate_combine_queue_use_case.gd's own
## `_verb_id_of()` convention, so this controller accepts the SAME entry
## shapes (VerbQueueEntry or an equivalent {"verb_id": ...} Dictionary)
## that use case does.
func _verb_id_of(entry) -> String:
	if entry is Dictionary:
		return entry.get("verb_id", "")
	return entry.verb_id


## _order_index_of(entry) -> int — duck-typed order_index accessor, mirrors
## `_verb_id_of()` above.
func _order_index_of(entry) -> int:
	if entry is Dictionary:
		return entry.get("order_index", 0)
	return entry.order_index


## _sorted_by_order_index(entries) -> Array — a NEW Array of `entries`
## ordered by order_index ascending, mirroring
## core/domain/combine/combine_queue.gd's CombineQueue.sorted_entries() /
## core/application/combine/validate_combine_queue_use_case.gd's own
## `_sorted_by_order_index()` convention: order_index, never
## insertion/array position, is authoritative for resolution order.
func _sorted_by_order_index(entries: Array) -> Array:
	var ordered: Array = entries.duplicate()
	ordered.sort_custom(func(a, b): return _order_index_of(a) < _order_index_of(b))
	return ordered
