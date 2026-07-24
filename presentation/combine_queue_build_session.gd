## presentation/combine_queue_build_session.gd — CombineQueueBuildSession
## (FEAT-004; US-003; FR-003; ADR-005).
##
## Presentation layer (Clean Architecture, ADR-001): a primary/driving
## controller extracted VERBATIM (same algorithm/behavior) from
## MainScene.gd's own former `_combine_build_*` fields and
## `_start_combine_queue_build()` / `_enter_combine_build_pick()` /
## `_on_combine_build_option_chosen()` / `_advance_combine_build()` /
## `_abort_combine_build()` / `_reset_combine_build_state()` methods
## (FEAT-296/DEF-NEW-001's own "interactive Combine QUEUE-BUILD pick loop").
## MainScene.gd now `.new()`s this class once, hands it its dependencies via
## `setup(deps)`, and drives it purely through this file's public
## `start(actor)` / `abort()` surface plus the `queue_built(queue)` /
## `aborted()` signals below — no `_combine_build_*` field/function remains
## on MainScene.gd (this feature's own test_criteria).
##
## Depends only on: core/domain/combine/combine_queue.gd (CombineQueue,
## domain), core/domain/combine/verb_queue_entry.gd (VerbQueueEntry,
## domain), core/application/combine/{build_verb_queue_use_case,
## confirm_queue_use_case, cancel_combine_use_case}.gd (application use
## cases), and presentation/adapters/combine_build_registry_proxy.gd (the
## FEAT-002 adapter this session hands to `selection_overlay.configure()`
## for the duration of a pick — completely UNCHANGED by this feature; see
## that file's own doc). Zero direct SQL/HTTP/framework concerns; the only
## Godot-specific surface touched is the duck-typed
## `selection_overlay`/`hex_grid_view` collaborators injected via
## `setup(deps)`, mirroring every other extracted controller in this steel
## thread (CombineTargetingSession, VerbDispatchController, ...).
##
## API contract (design notes' api_contracts #4; ADR-005's signal-based
## error vocabulary — GDScript has no exceptions):
##   setup(deps: Dictionary) -> void
##     Wires this session's collaborators. Must be called exactly once,
##     before start()/abort(). `deps` keys:
##       "combine_action_controller" — the BuildVerbQueueUseCase-backed
##           controller (`_core_combine_action_controller` in MainScene),
##           duck-typed `enter_selection(payload) -> SelectionDescriptor`.
##       "selection_overlay"  — presentation/selection_overlay.gd instance.
##       "hex_grid_view"      — presentation/hex_grid_view.gd instance (or
##                               null, passed straight through to
##                               selection_overlay.configure()/activate()).
##       "verb_registry"      — the standalone `_verb_registry` selection_overlay
##                               is switched BACK to once this session's
##                               build loop terminates (success, abort, or
##                               cancel) — mirrors
##                               `_reset_combine_build_state()`'s own
##                               "switches back to `_verb_registry`" guarantee.
##       "show_spell_picker_fn" / "hide_spell_picker_fn" — optional
##           Callables (MainScene's own `_show_spell_picker()` /
##           `_hide_spell_picker()` Layer-2a option-panel UI, UNCHANGED and
##           NOT moved by this feature) invoked exactly where the former
##           inline MainScene code invoked them. Omitted/invalid Callables
##           are simply skipped (no crash) — for GUT tests that inject a
##           fake selection_overlay with no real spell-picker UI at all.
##
##   start(actor) -> void
##     Entry point for a fresh interactive queue-build pick loop (mirrors
##     the former `_start_combine_queue_build(actor)`). A null `actor`
##     degrades safely (no crash) — the first `_enter_pick()` descriptor
##     query fails and the build aborts immediately, exactly as before.
##     FAILURE CONTRACT (this feature's own test_criteria): calling
##     start() while a build is ALREADY in progress (`is_active()` true)
##     does NOT overwrite the in-flight queue/state — it emits `aborted()`
##     immediately instead, per ADR-005's "expected failure path is a
##     signal, never a silent overwrite" discipline.
##
##   abort() -> void
##     Public cancel entry point: tears the build loop down (identical
##     bookkeeping to every other terminal path below) and emits
##     `aborted()`. A no-op-safe call when no build is in progress (still
##     emits `aborted()` — callers that only ever call abort() after
##     confirming `is_active()` are unaffected either way).
##
## Signals:
##   queue_built(queue: CombineQueue) — emitted once the player's Confirm
##     pick succeeds (ConfirmQueueUseCase reports ok:true). `queue` is the
##     now-CONFIRMED CombineQueue instance (`queue.sorted_entries()` /
##     `queue.actor_id` / `queue.context` carry everything a caller needs
##     to hand off into the targeting phase — mirrors the former
##     `_advance_combine_build()`'s own confirm branch, which read those
##     same three facts off `_combine_build_queue` before tearing it down).
##   aborted() — emitted on every non-success terminal path: a null/failed
##     SelectionDescriptor, a rejected add_entry()/ConfirmQueueUseCase call,
##     the player's own Cancel pick, an explicit abort() call, OR an
##     illegal start()-while-building re-entry (see start()'s own doc
##     above) — ADR-005's uniform "expected failure/cancel = signal, never
##     a silent no-op" vocabulary.
##
## Query helpers (exposed so callers/GUT tests can verify state directly,
## mirroring this codebase's established "constructed here, exposed for
## verification" precedent — see e.g. MainScene.gd's own
## `multi_phase_targeting_controller`/`_core_combine_action_controller`
## field doc):
##   is_active() -> bool         — true only while a build is in progress.
##   get_queue()                 — the in-progress CombineQueue, or null.
##   get_actor()                 — the acting Combatant this build started
##                                  for, or null.
##   get_context() -> int        — the CombineQueue.Context this build
##                                  started under.
##   get_pending_option() -> Dictionary — the most recently recorded (not
##                                  yet dispatched) option Dictionary.

class_name CombineQueueBuildSession
extends RefCounted

signal queue_built(queue)
signal aborted()

const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const BuildVerbQueueUseCaseClass = preload("res://core/application/combine/build_verb_queue_use_case.gd")
const ConfirmQueueUseCaseClass = preload("res://core/application/combine/confirm_queue_use_case.gd")
const CancelCombineUseCaseClass = preload("res://core/application/combine/cancel_combine_use_case.gd")
const CombineBuildRegistryProxyClass = preload("res://presentation/adapters/combine_build_registry_proxy.gd")

## _WeakOptionTarget — RefCounted-cycle guard: CombineBuildRegistryProxy
## (presentation/adapters/combine_build_registry_proxy.gd, UNCHANGED by this
## feature) always calls `_main_scene._on_combine_build_option_chosen(...)`
## on whatever object it is constructed with. This session is itself a
## RefCounted (unlike MainScene, which is a Node — Godot's refcounting
## never collects reference cycles, only Node's manual scene-tree lifetime
## sidesteps the problem). Constructing the proxy with `self` directly
## (`CombineBuildRegistryProxyClass.new(self)`) would make the proxy hold a
## STRONG reference back to this session while this session's own
## `_registry_proxy` field holds a STRONG reference to the proxy — a
## permanent two-object reference cycle formed the instant setup() runs,
## regardless of whether a build ever starts (this is exactly what
## tests/integration/test_headless_boot_smoke.py's zero-leaked-resources
## assertion catches: "N resources still in use at exit"). This tiny
## indirection breaks the cycle: the proxy holds a STRONG reference to a
## `_WeakOptionTarget` instance, which itself holds only a WEAKREF back to
## this session — no strong edge points back into this session's own
## reference graph, so the whole graph is collected normally once nothing
## external (MainScene) references this session anymore.
class _WeakOptionTarget:
	extends RefCounted

	var _session_ref: WeakRef

	func _init(session) -> void:
		_session_ref = weakref(session)

	func _on_combine_build_option_chosen(verb_id: String, value) -> Dictionary:
		var session = _session_ref.get_ref()
		if session == null:
			return {"ok": false}
		return session._on_combine_build_option_chosen(verb_id, value)


var _combine_action_controller = null
var _selection_overlay = null
var _hex_grid_view = null
var _verb_registry = null
var _show_spell_picker_fn: Callable = Callable()
var _hide_spell_picker_fn: Callable = Callable()

## The thin FEAT-002 adapter (CombineBuildRegistryProxy) this session hands
## to `selection_overlay.configure()` for the duration of a pick — it
## duck-type-delegates `execute(verb_id, value)` straight back to THIS
## session's own `_on_combine_build_option_chosen()` below, via the
## `_WeakOptionTarget` indirection above (constructed once, in setup() — no
## per-pick reallocation, no reference cycle).
var _registry_proxy = null

var _active: bool = false
var _queue = null
var _actor = null
var _context: int = CombineQueueClass.Context.TURN
var _pending_option: Dictionary = {}


## setup(deps) -> void — wires this session's collaborators. See the
## file-level doc above for `deps`'s full key set. Must be called exactly
## once, before start()/abort().
func setup(deps: Dictionary) -> void:
	_combine_action_controller = deps.get("combine_action_controller")
	_selection_overlay = deps.get("selection_overlay")
	_hex_grid_view = deps.get("hex_grid_view")
	_verb_registry = deps.get("verb_registry")
	_show_spell_picker_fn = deps.get("show_spell_picker_fn", Callable())
	_hide_spell_picker_fn = deps.get("hide_spell_picker_fn", Callable())
	_registry_proxy = CombineBuildRegistryProxyClass.new(_WeakOptionTarget.new(self))


## is_active() -> bool — true only while an interactive queue-build pick
## loop is currently in progress.
func is_active() -> bool:
	return _active


## get_queue() — the in-progress CombineQueue, or null when no build is
## active.
func get_queue():
	return _queue


## get_actor() — the acting Combatant this in-progress build started for,
## or null when no build is active.
func get_actor():
	return _actor


## get_context() -> int — the CombineQueue.Context this in-progress build
## started under (CombineQueue.Context.TURN by default).
func get_context() -> int:
	return _context


## get_pending_option() -> Dictionary — the most recently recorded (not yet
## dispatched) option Dictionary; `{}` when nothing has been picked yet /
## no build is active.
func get_pending_option() -> Dictionary:
	return _pending_option


## start(actor) -> void — entry point for a fresh interactive queue-build
## pick loop (see file-level doc's full contract). Calling start() while a
## build is ALREADY in progress emits `aborted()` immediately rather than
## overwriting the in-flight queue/state (this feature's own
## test_criteria) — mirrors ADR-005's "illegal state transition = signal,
## never a silent overwrite" discipline.
func start(actor) -> void:
	if _active:
		aborted.emit()
		return
	var actor_id: String = actor.display_id() if actor != null else ""
	_queue = CombineQueueClass.new("combine_build", actor_id, CombineQueueClass.Context.TURN)
	_actor = actor
	_context = CombineQueueClass.Context.TURN
	_pending_option = {}
	_active = true
	_enter_pick()


## abort() -> void — public cancel entry point. Tears the build loop down
## (identical bookkeeping to every other terminal path) and emits
## `aborted()`.
func abort() -> void:
	_reset_state()
	aborted.emit()


## advance() -> void — called by the caller (MainScene's
## `_on_selection_overlay_resolved()`) once `_on_combine_build_option_chosen()`
## below has already recorded the just-picked option, mirroring the former
## `_advance_combine_build()`. Dispatches on the pending option's `id`:
##   - the Cancel sentinel routes through the REAL CancelCombineUseCase,
##     tears the build loop down, and emits `aborted()`.
##   - the Confirm sentinel routes through the REAL ConfirmQueueUseCase; on
##     success the build loop tears itself down and emits
##     `queue_built(queue)` with the now-CONFIRMED queue. A confirm
##     rejection (defensive — should not occur) aborts the build instead.
##   - any other option (a VERB pick) appends a new VerbQueueEntry to the
##     in-progress CombineQueue and re-enters the NEXT pick.
func advance() -> void:
	if _hide_spell_picker_fn.is_valid():
		_hide_spell_picker_fn.call()

	var option: Dictionary = _pending_option
	var option_id: String = option.get("id", "")

	if option_id == CancelCombineUseCaseClass.CANCEL_SENTINEL_ID:
		CancelCombineUseCaseClass.new().execute(_queue)
		_reset_state()
		aborted.emit()
		return

	if option_id == BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID:
		var confirm_result: Dictionary = ConfirmQueueUseCaseClass.new().execute(_queue)
		if not confirm_result.get("ok", false):
			_reset_state()
			aborted.emit()
			return
		var confirmed_queue = _queue
		_reset_state()
		queue_built.emit(confirmed_queue)
		return

	if option_id == "":
		_reset_state()
		aborted.emit()
		return

	var order_index: int = _queue.entries.size()
	var add_result: Dictionary = _queue.add_entry(
		VerbQueueEntryClass.new(_queue.queue_id, order_index, option_id)
	)
	if not add_result.get("ok", false):
		_reset_state()
		aborted.emit()
		return

	_enter_pick()


## _on_combine_build_option_chosen(verb_id, value) -> Dictionary —
## `_registry_proxy`'s sole `execute()` delegate (duck-typed, mirrors
## presentation/adapters/combine_build_registry_proxy.gd's own doc), called
## synchronously from INSIDE selection_overlay's own `_resolve()` the
## instant a Layer-2a option button press resolves the current pick.
## Records the chosen option Dictionary into `_pending_option` for
## advance() (invoked immediately afterward by the caller) to dispatch on.
## Performs NO queue mutation and NEVER re-enters Layer 2 itself.
func _on_combine_build_option_chosen(_verb_id: String, value) -> Dictionary:
	var option: Dictionary = {}
	if value is Dictionary:
		option = value.get("option", {})
	_pending_option = option
	return {"ok": true}


## _enter_pick() -> void — offers the CURRENT in-progress CombineQueue's
## next legal pick via `_combine_action_controller.enter_selection()`, then
## activates selection_overlay with the resulting descriptor. A null/failed
## descriptor (no legal pick remains) aborts the whole queue-build
## immediately.
func _enter_pick() -> void:
	if _combine_action_controller == null:
		_reset_state()
		aborted.emit()
		return

	var descriptor = _combine_action_controller.enter_selection({
		"actor_id": _actor,
		"queue": _queue.sorted_entries(),
		"combine_context": _context,
	})

	if descriptor == null or not descriptor.ok:
		_reset_state()
		aborted.emit()
		return

	if _selection_overlay != null:
		_selection_overlay.configure(_registry_proxy, _hex_grid_view)
		_selection_overlay.activate("COMBINE", descriptor)
		if _selection_overlay.is_awaiting_option() and _show_spell_picker_fn.is_valid():
			_show_spell_picker_fn.call(_selection_overlay.get_candidate_options())


## _reset_state() -> void — the SOLE terminal state-reset code path shared
## by every advance() exit and abort(), so every terminal outcome leaves
## IDENTICAL bookkeeping behind: `_active` false, every loop-local field
## cleared, and selection_overlay switched back to `_verb_registry`. Also
## clears any still-active Layer 2a selection on `_selection_overlay` —
## every pre-existing terminal path (Cancel/Confirm-reject) already reaches
## here AFTER selection_overlay's own `_resolve()` has already cleared
## itself (a no-op re-clear), but the public `abort()` entry point (NEW in
## this feature's own API contract) may be called directly while a pick is
## still on screen, and must leave selection_overlay visibly back at Layer
## 1 too, not just reconfigured.
func _reset_state() -> void:
	_active = false
	_queue = null
	_actor = null
	_pending_option = {}
	if _selection_overlay != null:
		_selection_overlay.clear()
		if _verb_registry != null:
			_selection_overlay.configure(_verb_registry, _hex_grid_view)
