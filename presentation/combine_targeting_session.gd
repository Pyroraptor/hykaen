## presentation/combine_targeting_session.gd — CombineTargetingSession
## (FEAT-005; US-004; FR-004; ADR-003).
##
## Presentation layer (Clean Architecture, ADR-001): a primary/driving
## controller extracted VERBATIM (same algorithm/behavior) from
## MainScene.gd's own former `_combine_targeting_*` fields and
## `start_combine_targeting()` / `_enter_combine_targeting_phase()` /
## `_on_combine_targeting_value_chosen()` / `_advance_combine_targeting_phase()`
## / `_finish_combine_targeting()` / `_abort_combine_targeting()` /
## `_reset_combine_targeting_state()` / `_combine_verb_id_of()` /
## `_combine_order_index_of()` methods (FEAT-007's own "interactive Combine
## sub-action targeting" loop) — mirrors presentation/
## combine_queue_build_session.gd's (FEAT-004) identical extraction
## discipline one phase later in the Combine flow. MainScene.gd now `.new()`s
## this class once, hands it its dependencies via `setup(deps)`, and drives
## it purely through this file's public `start(queue_entries, actor, context,
## combine_queue)` / `abort()` / `try_advance(verb_id)` surface plus the
## `targeting_complete(result)` / `aborted()` signals below — no
## `_combine_targeting_*` field/function remains on MainScene.gd (this
## feature's own test_criteria).
##
## RISK-002 mitigation (this feature's own explicit scope): this class WRAPS
## core/application/combine/multi_phase_targeting_controller.gd's
## MultiPhaseTargetingController via composition ONLY — it is injected
## (already-constructed) through `setup(deps)`'s `"targeting_controller"` key
## and this file NEVER edits, re-implements, or forks any part of its own
## `execute()` algorithm. Every phase this session drives interactively is
## resolved through the SAME `_controller_registry` collaborators (the
## VerbControllerPort-shaped STRIDE/STRIKE/CAST_SPELL controllers) that
## MultiPhaseTargetingController itself was constructed with — never a
## second/forked verb_id -> controller lookup path (ADR-002's "verb_id
## whitelisting" security note) — and the FINAL authoritative resolution
## (order_index-authoritative replay, CANCEL_SENTINEL handling, sub-action
## dispatch via the injected `combine_action_controller`) is performed
## SOLELY by one `_targeting_controller.execute(...)` call in `_finish()`
## below; this file's own get_result() is that call's return value passed
## through completely unmodified. tests/gut/test_combine_targeting_session.gd
## additionally asserts, via a pinned SHA-256 hash of
## multi_phase_targeting_controller.gd's own source, that the wrapped file is
## byte-for-byte unchanged by this extraction (RISK-002's own explicit
## acceptance test).
##
## Why the interactive per-phase loop (`_enter_phase()` /
## `_on_combine_targeting_value_chosen()` below) still asks each phase's OWN
## controller for a descriptor directly, rather than only ever calling
## `_targeting_controller.execute()`: MultiPhaseTargetingController.execute()
## is a SYNCHRONOUS, fully-resolved replay engine — it requires every phase's
## chosen value pre-resolved (its own `resolved_selections` parameter) and
## returns immediately; it has no mechanism to pause mid-loop for a real
## asynchronous player click. This session instead drives ONE phase of that
## SAME algorithm at a time — offering the CURRENT phase's live SelectionDescriptor
## through the existing, unmodified SelectionOverlay (`_selection_overlay`
## below) and waiting for `try_advance()` to be called once the player
## resolves it — and only once EVERY phase has a real, player-chosen value
## does it hand the fully-populated map to `_targeting_controller.execute()`
## for the authoritative final resolution. No RULE (legality/reach/damage/
## economy) is ever evaluated by this file itself: every such decision is
## delegated to a `controller.enter_selection()` call (the exact same
## VerbControllerPort collaborators the wrapped controller's own registry
## holds) or to `_targeting_controller.execute()` itself — this file
## performs pure sequencing/plumbing (which phase is current, when to show
## SelectionOverlay, when to switch it back) and nothing else.
##
## Depends only on: core/application/combine/multi_phase_targeting_controller.gd
## (MultiPhaseTargetingController, application, injected UNCHANGED — see
## above), the VerbControllerPort-shaped `controller_registry` collaborators
## (also injected, application layer), and
## presentation/adapters/combine_targeting_registry_proxy.gd (the FEAT-002
## adapter this session hands to `selection_overlay.configure()` for the
## duration of a phase — completely UNCHANGED by this feature). Zero direct
## SQL/HTTP/framework concerns; the only Godot-specific surface touched is
## the duck-typed `selection_overlay`/`hex_grid_view` collaborators injected
## via `setup(deps)`, mirroring every other extracted controller in this
## steel thread (CombineQueueBuildSession, VerbDispatchController, ...).
##
## API contract (design notes' api_contracts #5; ADR-005's signal-based
## error vocabulary — GDScript has no exceptions):
##   setup(deps: Dictionary) -> void
##     Wires this session's collaborators. Must be called exactly once,
##     before start()/abort()/try_advance(). `deps` keys:
##       "controller_registry" — Dictionary of verb_id -> VerbControllerPort-
##           shaped collaborator (`_combine_controller_registry` in
##           MainScene) — the EXACT SAME registry `targeting_controller`
##           below was itself constructed with.
##       "targeting_controller" — the already-constructed, UNCHANGED
##           MultiPhaseTargetingController instance
##           (`multi_phase_targeting_controller` in MainScene) this session
##           wraps via composition (see RISK-002 doc above).
##       "selection_overlay"  — presentation/selection_overlay.gd instance.
##       "hex_grid_view"      — presentation/hex_grid_view.gd instance (or
##                               null, passed straight through to
##                               selection_overlay.configure()/activate()).
##       "verb_registry"      — the standalone `_verb_registry` selection_overlay
##                               is switched BACK to once this session's
##                               targeting loop terminates (success, abort,
##                               or an unregistered/no-legal-options phase) —
##                               mirrors `_reset_combine_targeting_state()`'s
##                               own "switches back to `_verb_registry`"
##                               guarantee.
##       "show_spell_picker_fn" — optional Callable (MainScene's own
##           `_show_spell_picker()` Layer-2a option-panel UI, UNCHANGED and
##           NOT moved by this feature) invoked exactly where the former
##           inline MainScene code invoked it. An omitted/invalid Callable is
##           simply skipped (no crash).
##
##   start(queue_entries: Array, actor, context: int, combine_queue) -> void
##     Entry point for a fresh interactive Combine sub-action targeting loop
##     (mirrors the former `start_combine_targeting(queue_entries, actor,
##     context, combine_queue)`). `queue_entries` — a CONFIRMED CombineQueue's
##     entries (VerbQueueEntry instances, or equivalent
##     {"verb_id":...,"order_index":...} Dictionaries — the SAME shapes
##     MultiPhaseTargetingController.execute() itself accepts), sorted by
##     order_index (authoritative, never insertion/array position). `combine_queue`
##     — optional CombineQueue aggregate (core/domain/combine/combine_queue.gd)
##     `queue_entries` belongs to, forwarded verbatim to
##     `targeting_controller.execute()`'s own optional `combine_queue`
##     argument once this run finishes, so a CANCEL_SENTINEL pick during any
##     phase transitions this SAME queue instance to CANCELLED (FEAT-008).
##     FAILURE CONTRACT (this feature's own test_criteria — "invalid phase
##     count"): an empty `queue_entries` never engages the loop and emits
##     `aborted()` immediately, rather than the former silent no-op.
##
##   abort() -> void
##     Public cancel entry point: tears the targeting loop down (identical
##     bookkeeping to every other terminal path below) and emits `aborted()`.
##
##   try_advance(verb_id: String) -> bool
##     Called by the caller (MainScene's `_on_selection_overlay_resolved()`)
##     once `selection_overlay.selection_resolved` fires. Returns true (and
##     advances to the next phase / finishes the loop) ONLY when this session
##     is active AND `verb_id` matches the CURRENT phase's own verb_id —
##     mirroring the former inline `_combine_targeting_active and
##     _combine_targeting_index < _combine_targeting_entries.size() and
##     _verb_id == _combine_verb_id_of(...)` guard. Returns false (a no-op)
##     for every standalone (non-Combine-targeting) verb resolution, so a
##     caller can simply `if session.try_advance(verb_id): return`.
##
## Signals:
##   targeting_complete(result: Dictionary) — emitted once every queued phase
##     has resolved (loop exhaustion) and `targeting_controller.execute()` has
##     produced its own authoritative Dictionary result
##     (`{"ok", "error_code", "accumulated", "execution_result"}` — see
##     multi_phase_targeting_controller.gd's own `execute()` doc). `result` is
##     that Dictionary passed straight through, UNMODIFIED — this session
##     never reinterprets it (this mirrors the former `_finish_combine_targeting()`,
##     which invoked `multi_phase_targeting_controller.execute()`
##     unconditionally on loop exhaustion regardless of its own `.ok`, since
##     "successful N-phase resolution" here means every phase was
##     successfully TARGETED, not that the final sub-action dispatch/economy
##     charge necessarily succeeded — callers inspect `result.ok`/
##     `result.execution_result.ok` themselves for that finer-grained
##     outcome, exactly as the pre-extraction code already required).
##   aborted() — emitted on every non-success terminal path: an empty/invalid
##     `queue_entries` at start() ("invalid phase count"), an unregistered
##     verb_id or a null/failed SelectionDescriptor ("no valid candidates
##     from the wrapped controller's own registry"), or an explicit abort()
##     call ("cancel") — ADR-005's uniform "expected failure/cancel = signal,
##     never a silent no-op" vocabulary.
##
## Query helpers (exposed so callers/GUT tests can verify state directly,
## mirroring presentation/combine_queue_build_session.gd's own "constructed
## here, exposed for verification" precedent):
##   is_active() -> bool           — true only while a targeting loop is in
##                                    progress.
##   get_result() -> Dictionary    — the most recently finished/aborted run's
##                                    result Dictionary (`{}` before any run).
##   get_resolved() -> Dictionary  — the in-progress run's verb_id -> raw
##                                    chosen-value map (mirrors the former
##                                    `_combine_targeting_resolved`).
##   get_accumulated() -> Dictionary — the in-progress run's verb_id ->
##                                    resolved SelectionDescriptor map.
##   get_actor()                   — the acting Combatant this in-progress run
##                                    started for, or null.
##   get_context() -> int          — the CombineQueue.Context this in-progress
##                                    run started under.
##   get_queue()                   — the in-progress CombineQueue aggregate
##                                    (or null).

class_name CombineTargetingSession
extends RefCounted

signal targeting_complete(result)
signal aborted()

const CombineTargetingRegistryProxyClass = preload("res://presentation/adapters/combine_targeting_registry_proxy.gd")

## _WeakTargetingTarget — RefCounted-cycle guard, mirrors
## presentation/combine_queue_build_session.gd's own `_WeakOptionTarget`
## doc verbatim: CombineTargetingRegistryProxy
## (presentation/adapters/combine_targeting_registry_proxy.gd, UNCHANGED by
## this feature) always calls
## `_main_scene._on_combine_targeting_value_chosen(...)` on whatever object
## it is constructed with. This session is itself a RefCounted (unlike
## MainScene, which is a Node — Godot's refcounting never collects reference
## cycles, only Node's manual scene-tree lifetime sidesteps the problem).
## Constructing the proxy with `self` directly would make the proxy hold a
## STRONG reference back to this session while this session's own
## `_registry_proxy` field holds a STRONG reference to the proxy — a
## permanent two-object reference cycle. This tiny indirection breaks the
## cycle: the proxy holds a STRONG reference to a `_WeakTargetingTarget`
## instance, which itself holds only a WEAKREF back to this session.
class _WeakTargetingTarget:
	extends RefCounted

	var _session_ref: WeakRef

	func _init(session) -> void:
		_session_ref = weakref(session)

	func _on_combine_targeting_value_chosen(verb_id: String, value) -> Dictionary:
		var session = _session_ref.get_ref()
		if session == null:
			return {"ok": false}
		return session._on_combine_targeting_value_chosen(verb_id, value)


var _controller_registry: Dictionary = {}
var _targeting_controller = null
var _selection_overlay = null
var _hex_grid_view = null
var _verb_registry = null
var _show_spell_picker_fn: Callable = Callable()

## The thin FEAT-002 adapter (CombineTargetingRegistryProxy) this session
## hands to `selection_overlay.configure()` for the duration of a phase — it
## duck-type-delegates `execute(verb_id, value)` straight back to THIS
## session's own `_on_combine_targeting_value_chosen()` below, via the
## `_WeakTargetingTarget` indirection above (constructed once, in setup() —
## no per-phase reallocation, no reference cycle). Never dispatches to a real
## ActionController mid-queue — it only captures the resolved value for this
## session's own loop to consume.
var _registry_proxy = null

var _active: bool = false
var _entries: Array = []
var _index: int = 0
var _actor = null
var _context: int = 0
var _accumulated: Dictionary = {}
var _resolved: Dictionary = {}
var _result: Dictionary = {}
var _queue = null


## setup(deps) -> void — wires this session's collaborators. See the
## file-level doc above for `deps`'s full key set. Must be called exactly
## once, before start()/abort()/try_advance().
func setup(deps: Dictionary) -> void:
	_controller_registry = deps.get("controller_registry", {})
	_targeting_controller = deps.get("targeting_controller")
	_selection_overlay = deps.get("selection_overlay")
	_hex_grid_view = deps.get("hex_grid_view")
	_verb_registry = deps.get("verb_registry")
	_show_spell_picker_fn = deps.get("show_spell_picker_fn", Callable())
	_registry_proxy = CombineTargetingRegistryProxyClass.new(_WeakTargetingTarget.new(self))


## is_active() -> bool — true only while an interactive Combine targeting
## loop is currently in progress.
func is_active() -> bool:
	return _active


## get_result() -> Dictionary — the most recently finished/aborted run's
## result Dictionary; `{}` before any run has ever completed.
func get_result() -> Dictionary:
	return _result


## get_resolved() -> Dictionary — the in-progress (or just-finished, before
## the NEXT run starts) verb_id -> raw chosen-value map.
func get_resolved() -> Dictionary:
	return _resolved


## get_accumulated() -> Dictionary — the in-progress verb_id -> resolved
## SelectionDescriptor map.
func get_accumulated() -> Dictionary:
	return _accumulated


## get_actor() — the acting Combatant the in-progress run started for, or
## null when no run is active.
func get_actor():
	return _actor


## get_context() -> int — the CombineQueue.Context the in-progress run
## started under.
func get_context() -> int:
	return _context


## get_queue() — the in-progress CombineQueue aggregate (or null).
func get_queue():
	return _queue


## start(queue_entries, actor, context, combine_queue) -> void — entry point
## for a fresh interactive Combine sub-action targeting loop (see file-level
## doc's full contract). An empty `queue_entries` ("invalid phase count")
## never engages the loop and emits `aborted()` immediately.
func start(queue_entries: Array, actor, context: int = 0, combine_queue = null) -> void:
	if queue_entries.is_empty():
		aborted.emit()
		return

	_entries = queue_entries.duplicate()
	_entries.sort_custom(func(a, b): return _order_index_of(a) < _order_index_of(b))
	_index = 0
	_actor = actor
	_context = context
	_accumulated = {}
	_resolved = {}
	_result = {}
	_queue = combine_queue
	_active = true
	_enter_phase()


## abort() -> void — public cancel entry point. Tears the targeting loop
## down (identical bookkeeping to every other terminal path) and emits
## `aborted()`.
func abort() -> void:
	_reset_state()
	aborted.emit()


## try_advance(verb_id) -> bool — see file-level doc's full contract. The
## sole entry point MainScene's `_on_selection_overlay_resolved()` calls once
## `selection_overlay.selection_resolved` fires.
func try_advance(verb_id: String) -> bool:
	if not _active or _index >= _entries.size():
		return false
	if verb_id != _verb_id_of(_entries[_index]):
		return false
	_advance()
	return true


## _enter_phase() -> void — offers the CURRENT phase's (`_index`) candidates
## via that verb's REAL enter_selection() (looked up through
## `_controller_registry`, the SAME registry `_targeting_controller` was
## constructed with — ADR-002 "verb_id whitelisting", no second/forked
## controller-resolution path), then activates selection_overlay with the
## resulting descriptor. selection_overlay is switched to `_registry_proxy`
## for the duration. An unregistered verb_id, a null descriptor, or an
## `ok:false` descriptor (no legal options for this phase) aborts the whole
## targeting sequence immediately via `_abort()`.
func _enter_phase() -> void:
	var entry = _entries[_index]
	var verb_id: String = _verb_id_of(entry)
	var order_index: int = _order_index_of(entry)
	var controller = _controller_registry.get(verb_id)

	if controller == null:
		_abort("UNREGISTERED_VERB")
		return

	var descriptor = controller.enter_selection({
		"actor_id": _actor,
		"mode": "TARGET_PHASE",
		"combine_context": _context,
		"order_index": order_index,
		"verb_id": verb_id,
		"accumulated": _accumulated,
	})

	if descriptor == null or not descriptor.ok:
		var error_code: String = descriptor.meta.get("error_code", "NO_LEGAL_OPTIONS") if descriptor != null else "NO_LEGAL_OPTIONS"
		_abort(error_code)
		return

	if _selection_overlay != null:
		_selection_overlay.configure(_registry_proxy, _hex_grid_view)
		_selection_overlay.activate(verb_id, descriptor)
		if _selection_overlay.is_awaiting_option() and _show_spell_picker_fn.is_valid():
			_show_spell_picker_fn.call(_selection_overlay.get_candidate_options())


## _on_combine_targeting_value_chosen(verb_id, value) -> Dictionary —
## `_registry_proxy`'s sole `execute()` delegate, called synchronously from
## INSIDE selection_overlay's OWN, UNCHANGED `_resolve()` the instant a
## highlighted hex/target click resolves the current phase. Re-invokes the
## SAME controller's enter_selection() ONE more time, now WITH the chosen
## value threaded onto the context as `selected_hex` — the EXACT generic seam
## MultiPhaseTargetingController.execute()'s own `resolved_selections`
## parameter already establishes — so the resulting resolved
## SelectionDescriptor is threaded into `_accumulated`, keyed by THIS phase's
## own `verb_id`, for the NEXT phase's own enter_selection() call to read
## (e.g. STRIKE computing post-move reach from STRIDE's chosen hex).
## `_resolved[verb_id] = value` additionally records the RAW chosen value for
## the final authoritative replay in `_finish()` below.
func _on_combine_targeting_value_chosen(verb_id: String, value) -> Dictionary:
	var entry = _entries[_index]
	var order_index: int = _order_index_of(entry)
	var controller = _controller_registry.get(verb_id)

	_resolved[verb_id] = value

	if controller != null:
		var resolved_descriptor = controller.enter_selection({
			"actor_id": _actor,
			"mode": "TARGET_PHASE",
			"combine_context": _context,
			"order_index": order_index,
			"verb_id": verb_id,
			"accumulated": _accumulated,
			"selected_hex": value,
		})
		if resolved_descriptor != null:
			_accumulated[verb_id] = resolved_descriptor

	return {"ok": true, "chosen_value": value}


## _advance() -> void — moves to the next queued entry, or -- on exhaustion
## -- hands the FULL, now fully-populated `_resolved` map to `_finish()` for
## the authoritative final resolution + sub-action dispatch (delegated
## entirely to `_targeting_controller.execute()`, UNCHANGED).
func _advance() -> void:
	_index += 1
	if _index >= _entries.size():
		_finish()
	else:
		_enter_phase()


## _finish() -> void — the interactive loop's success terminal: delegates the
## whole confirmed queue to `_targeting_controller.execute()` (UNCHANGED,
## RISK-002) with the now fully-populated `_resolved` map, stores its
## Dictionary result verbatim (see `targeting_complete`'s own doc for why
## this fires regardless of the result's own `.ok`), resets loop state, then
## emits `targeting_complete(result)`.
func _finish() -> void:
	_result = _targeting_controller.execute(_entries, _actor, _context, _resolved, _queue)
	var final_result: Dictionary = _result
	_reset_state()
	targeting_complete.emit(final_result)


## _abort(error_code) -> void — mirrors MultiPhaseTargetingController's own
## `_abort_result()` shape (`{ok:false, error_code, accumulated,
## execution_result:{}}`) for a phase that could never even reach the real
## UI (an unregistered verb_id, or an `ok:false`/no-legal-options
## descriptor). Never invokes `_targeting_controller`.
func _abort(error_code: String) -> void:
	_result = {
		"ok": false,
		"error_code": error_code,
		"accumulated": _accumulated,
		"execution_result": {},
	}
	_reset_state()
	aborted.emit()


## _reset_state() -> void — the SOLE terminal state-reset code path shared by
## `_finish()`/`_abort()`/`abort()`, so every terminal outcome leaves
## IDENTICAL bookkeeping behind: `_active` false, every loop-local field
## cleared, and selection_overlay switched back to `_verb_registry` — the
## SAME registry every standalone verb press already uses. `_result` is
## deliberately NEVER cleared here — it stays readable (get_result()) after
## the loop ends, mirroring the pre-extraction `_combine_targeting_result`
## field's own "exposed for verification" convention. Also clears any
## still-active Layer 2 selection on `_selection_overlay` — mirrors
## presentation/combine_queue_build_session.gd's own `_reset_state()` doc:
## every pre-extraction terminal path already reached here AFTER
## selection_overlay's own `_resolve()` had already cleared itself (a no-op
## re-clear), but the public `abort()` entry point (this session's OWN
## addition, absent from the pre-extraction inline code) may be called
## directly while a phase is still on screen, and must leave
## selection_overlay visibly back at Layer 1 too, not just reconfigured.
func _reset_state() -> void:
	_active = false
	_entries = []
	_index = 0
	_actor = null
	_accumulated = {}
	_resolved = {}
	_queue = null
	if _selection_overlay != null:
		_selection_overlay.clear()
		if _verb_registry != null:
			_selection_overlay.configure(_verb_registry, _hex_grid_view)


## _verb_id_of(entry) -> String — duck-typed verb_id accessor mirroring
## multi_phase_targeting_controller.gd's own `_verb_id_of()` convention, so
## this session accepts the SAME entry shapes (VerbQueueEntry or an
## equivalent {"verb_id": ...} Dictionary) that controller does.
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
