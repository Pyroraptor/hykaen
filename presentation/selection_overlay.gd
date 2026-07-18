## presentation/selection_overlay.gd — SelectionOverlay (FEAT-008 / US-008 /
## FR-003; ADR-002, ADR-004)
##
## Presentation layer (Clean Architecture): the generic Layer 2 (target /
## destination selection) surface a Layer 1 verb (VerbBarView, FEAT-004)
## enters once its SelectionDescriptor is available. Mirrors core/
## application/verb_registry.py's SelectionDescriptor shape exactly, as
## realized by this Godot runtime's own registry adapter (MainScene.gd's
## _VerbBarRegistryAdapter, which — like the Python VerbRegistry — hands
## back a Dictionary carrying "candidate_hexes"/"candidate_targets").
##
## THIS FEATURE'S SCOPE (US-008): Strike's Layer 2 — highlighting only the
## in-reach enemy targets a Strike SelectionDescriptor names, and resolving
## a click on one of them straight through the SAME, REUSED
## VerbRegistry.execute() -> ActionResolverPort.select_target() ->
## ResolveActionUseCase path (ADR-002: no new port, no forked/duplicated
## resolution logic). This component is written GENERICALLY over
## candidate_hexes/candidate_targets precisely so a later feature (Step/
## Stride Layer 2) needs no fork of its own here — it is driven purely by
## whichever candidate collection the active verb's descriptor populates.
## This file contains NO "if verb_id == ..." branching of its own (mirrors
## presentation/verb_bar_view.gd's / core/application/verb_registry.py's
## established generic-dispatch discipline).
##
## Highlighting a TARGET (as opposed to a bare hex): candidate_targets
## carries combatant ids, not hexes — this overlay resolves each id's
## current board position via the injected hex_grid_view's OWN
## already-tracked token (HexGridView.get_token(id).hex_coord), the SAME
## positional data CombatantTokenView already renders from (ADR-001: no
## independent position bookkeeping of its own here). The resulting hex set
## is unioned with any direct candidate_hexes and handed to
## hex_grid_view.set_selectable_hexes() — the SAME visual highlight
## affordance FEAT-013/US-013 already established for Step/Stride, reused
## here rather than inventing a second highlight mechanism (ADR-002 /
## CR-001 guardrail).
##
## Layer-2a option presentation (FEAT-010 / US-010): a descriptor whose
## candidate_options is a non-empty Array (core/application/
## selection_descriptor.gd's `candidate_options` field, FEAT-007) causes
## activate() to enter an interstitial Layer-2a "awaiting option" state
## INSTEAD of immediately highlighting Layer-2b targeting -- no hex/target
## highlight is pushed to hex_grid_view until an option has been chosen.
## choose_option(option) is the sole way out of that state: it stores the
## chosen option and THEN highlights Layer-2b targeting via the SAME
## _refresh_highlight()/hex_grid_view.set_selectable_hexes() path every
## other verb already uses (no parallel/forked highlight mechanism is
## introduced here -- ADR-002). A subsequent hex click resolves exactly as
## before, except _resolve() now calls
## registry.execute(verb_id, {"option": chosen_option, "target": value}) --
## the SAME OPTION_TARGET Dictionary shape presentation/action_controller.gd
## already dispatches on (FEAT-009) -- rather than the bare scalar `value`.
## A descriptor with no candidate_options (null or empty, every verb
## registered before this feature) is completely unaffected: activate()
## highlights Layer-2b targeting immediately, exactly as it always has.
##
## Post-resolution lock (FEAT-177 / US-013, extending the EXISTING
## presentation/result_screen_view.gd lock mechanism -- not a new one):
## lock() immediately discards any in-progress Layer 2 selection (clearing
## the HexGridView highlight, exactly like clear()) and permanently rejects
## both activate() (a stray verb_selection_entered re-fire can never
## re-enter Layer 2) and any further hex_clicked dispatch (a click already
## queued/dispatched at the moment of resolution can never reach
## registry.execute()) from that point on. Sticky, mirroring presentation/
## movement_input_controller.gd's/presentation/verb_bar_view.gd's lock()
## contract exactly.
##
## Resolving a click: subscribes to the injected hex_grid_view's existing
## hex_clicked(hex_coord) signal (presentation/hex_grid_view.gd) — left
## unconnected by the composition root since FEAT-007 removed the legacy
## auto-move handler specifically so "a future Layer 2 SelectionOverlay may
## subscribe to it" (see that file's own doc); this is that subscriber. A
## click landing on a highlighted TARGET's hex resolves
## registry.execute(verb_id, target_id); a click landing on a highlighted
## HEX resolves registry.execute(verb_id, hex_coord); a click landing
## anywhere else (an out-of-reach / non-highlighted location) triggers
## NEITHER — no registry.execute() call is made at all, so a stale or
## wayward click can never mutate game state (error_handling design note:
## re-validation additionally happens *inside* execute() itself — this
## overlay's own pre-filter is defense in depth, mirroring
## movement_input_controller.gd's step_to()/stride_to()
## ERR_..._NOT_SELECTABLE pattern).
##
## A plain RefCounted adapter (no companion .tscn), instantiated directly by
## the composition root (MainScene.gd) exactly like
## presentation/movement_input_controller.gd — see that file's file-level
## doc for the established precedent.

class_name SelectionOverlay
extends RefCounted

## selection_resolved(verb_id, result) — emitted after a highlighted
## target/hex click successfully dispatches through registry.execute().
## `result` is that call's return value verbatim (this overlay never
## inspects its shape).
signal selection_resolved(verb_id: String, result)

## selection_rejected(verb_id, hex_coord) — emitted whenever a click lands
## on a location that names neither a currently highlighted target nor a
## currently highlighted hex — observability only; NO registry.execute()
## call is ever made for this case (see file-level doc).
signal selection_rejected(verb_id: String, hex_coord)

## selection_cancelled(verb_id) — FEAT-176 (US-012 / FR-007, ADR-005):
## emitted by cancel() whenever a Layer 2 selection WAS active and has now
## been discarded via the cancel/back affordance (Esc/right-click/Cancel
## button — see presentation/cancel_controller.gd, the sole caller of
## cancel()). Distinguishes an explicit cancel from a normal
## selection_resolved-triggered clear() — NEVER emitted by clear() itself,
## only by cancel().
signal selection_cancelled(verb_id: String)

## The injected registry (duck-typed: any object exposing execute(verb_id,
## selection) — mirrors presentation/verb_bar_view.gd's identical
## convention). SelectionOverlay never constructs one itself and never
## calls enter_selection() itself — activate() is always handed an
## already-computed descriptor (normally forwarded verbatim from
## VerbBarView's verb_selection_entered signal), so a Layer 1 press only
## ever queries the registry once.
var _registry = null

## The injected presentation/hex_grid_view.gd collaborator this overlay
## highlights candidates on and reads hex_clicked from.
var _hex_grid_view = null

## The verb_id currently in Layer 2 selection, or "" when inactive (Layer 1).
var _active_verb_id: String = ""

## The active SelectionDescriptor's candidate_hexes, verbatim.
var _candidate_hexes: Array = []

## target_id (String) -> HexCoord — resolved once per activate() call from
## the active SelectionDescriptor's candidate_targets, via
## hex_grid_view.get_token(target_id).hex_coord.
var _target_hex_by_id: Dictionary = {}

## True once lock() has been called (FEAT-177 / US-013) — permanently
## rejects activate() and any further hex_clicked dispatch from that point
## on.
var _locked: bool = false

## FEAT-010 (US-010): the active SelectionDescriptor's candidate_options,
## verbatim -- empty Array when the descriptor named none (every verb
## registered before this feature).
var _candidate_options: Array = []

## FEAT-010 (US-010): true while Layer-2a's option pick is pending (i.e.
## _candidate_options was non-empty at activate() and choose_option() has
## not yet been called) -- false for every SCALAR-shaped descriptor (the
## legacy, unaffected default) and false again once an option has been
## chosen and Layer-2b targeting has begun.
var _awaiting_option: bool = false

## FEAT-010 (US-010): the Layer-2a option chosen via choose_option(), or
## null when no option has been (or ever needs to be) chosen. Carried
## forward into _resolve() so a Layer-2b click resolves through
## registry.execute(verb_id, {"option": ..., "target": ...}) instead of the
## legacy bare-scalar call.
var _chosen_option = null


## configure(registry, hex_grid_view) -> void — injects both collaborators
## and subscribes to hex_grid_view.hex_clicked exactly once (idempotent —
## safe to call configure() again, e.g. a future encounter reload, without
## leaking duplicate connections).
func configure(registry, hex_grid_view) -> void:
	_registry = registry
	_hex_grid_view = hex_grid_view
	if _hex_grid_view != null and not _hex_grid_view.hex_clicked.is_connected(_on_hex_clicked):
		_hex_grid_view.hex_clicked.connect(_on_hex_clicked)


## is_active() -> bool — true while a Layer 2 selection is in progress.
func is_active() -> bool:
	return _active_verb_id != ""


## is_locked() -> bool — true once lock() has been called (FEAT-177 /
## US-013).
func is_locked() -> bool:
	return _locked


## lock() -> void — FEAT-177 (US-013 / FR-013): the post-resolution guard
## extending the EXISTING presentation/result_screen_view.gd lock mechanism
## to any open Layer 2 SelectionOverlay. Immediately discards any
## in-progress selection via clear() (so no stale highlight/candidate set
## survives) and permanently rejects activate()/hex_clicked dispatch from
## this point on — no registry.execute() call is reachable through this
## overlay once locked. Idempotent and sticky: safe to call more than once,
## and no later activate() call may ever re-enter Layer 2.
func lock() -> void:
	_locked = true
	clear()


## get_active_verb_id() -> String — the verb currently in Layer 2, or "".
func get_active_verb_id() -> String:
	return _active_verb_id


## get_highlighted_target_ids() -> Array[String] — every candidate target
## id this overlay currently believes is in reach (test/inspection helper;
## mirrors the exact set handed to hex_grid_view.set_selectable_hexes()).
## FEAT-010 (US-010): always empty while is_awaiting_option() is true --
## candidate_targets are resolved and held internally ahead of time (so
## choose_option() need not re-extract them), but nothing is actually
## highlighted until Layer-2b targeting begins.
func get_highlighted_target_ids() -> Array:
	if _awaiting_option:
		return []
	return _target_hex_by_id.keys()


## get_highlighted_hexes() -> Array[HexCoord] — the exact union this
## overlay most recently pushed to hex_grid_view.set_selectable_hexes()
## (test/inspection helper). FEAT-010 (US-010): always empty while
## is_awaiting_option() is true, mirroring get_highlighted_target_ids().
func get_highlighted_hexes() -> Array:
	if _awaiting_option:
		return []
	var union_hexes: Array = _candidate_hexes.duplicate()
	for hex_coord in _target_hex_by_id.values():
		union_hexes.append(hex_coord)
	return union_hexes


## activate(verb_id, selection) -> void — enters Layer 2 for `verb_id` with
## the descriptor already returned by registry.enter_selection(verb_id).
##
## FEAT-010 (US-010): when `selection` names a non-empty candidate_options
## list, this additively inserts a Layer-2a "awaiting option" step ahead of
## Layer-2b targeting — candidate_hexes/candidate_targets are resolved and
## stored immediately (so choose_option() can hand them straight to
## _refresh_highlight() with no re-extraction), but NO highlight reaches
## hex_grid_view until choose_option() picks one. A descriptor with no
## candidate_options (null or empty — every verb registered before this
## feature) is unaffected: it highlights the union of any direct
## candidate_hexes and every resolvable candidate_target's current hex
## immediately, exactly as before.
func activate(verb_id: String, selection) -> void:
	if _locked:
		return
	_active_verb_id = verb_id
	_candidate_hexes = _extract(selection, "candidate_hexes")
	_target_hex_by_id = _resolve_target_hexes(_extract(selection, "candidate_targets"))
	_candidate_options = _extract_options(selection)
	_chosen_option = null

	if _candidate_options.size() > 0:
		_awaiting_option = true
		if _hex_grid_view != null:
			_hex_grid_view.set_selectable_hexes([])
	else:
		_awaiting_option = false
		_refresh_highlight()


## is_awaiting_option() -> bool — FEAT-010 (US-010): true while Layer-2a's
## option pick is pending (candidate_options was non-empty at activate() and
## choose_option() has not yet resolved it). Always false for a SCALAR-shaped
## descriptor (every verb registered before this feature).
func is_awaiting_option() -> bool:
	return _awaiting_option


## get_candidate_options() -> Array — the active descriptor's
## candidate_options, verbatim (test/inspection helper; empty Array when the
## descriptor named none).
func get_candidate_options() -> Array:
	return _candidate_options


## choose_option(option) -> void — FEAT-010 (US-010): Layer-2a's sole exit
## point. Stores `option` (carried forward into _resolve()'s
## registry.execute(verb_id, {"option": ..., "target": ...}) call) and THEN
## begins Layer-2b targeting via the SAME _refresh_highlight()/
## hex_grid_view.set_selectable_hexes() path every other verb already uses —
## no separate/parallel highlight rendering is introduced. A no-op when
## Layer 2 is locked, inactive, or not currently awaiting an option (e.g. a
## stray second call after an option was already chosen).
func choose_option(option) -> void:
	if _locked or not is_active() or not _awaiting_option:
		return
	_chosen_option = option
	_awaiting_option = false
	_refresh_highlight()


## clear() -> void — leaves Layer 2 (returns to Layer 1) and clears any
## highlight this overlay pushed to hex_grid_view. Called internally once a
## selection resolves; also safe to call externally (e.g. cancel() below).
## Never emits selection_cancelled and never touches `_registry` — this is
## the pure state-reset primitive both a normal resolution and an explicit
## cancel share.
func clear() -> void:
	_active_verb_id = ""
	_candidate_hexes = []
	_target_hex_by_id = {}
	_candidate_options = []
	_awaiting_option = false
	_chosen_option = null
	if _hex_grid_view != null:
		_hex_grid_view.set_selectable_hexes([])


## cancel() -> bool — FEAT-176 (US-012 / FR-007, ADR-005): the cancel/back
## affordance's sole entry point into this overlay (called exclusively by
## presentation/cancel_controller.gd's CancelController, never by
## VerbBarView/HexGridView directly). Discards the pending Layer 2 selection
## via clear() — which, per that method's own doc, NEVER calls `_registry`
## (no ActionResolverPort/MovementPort/TurnPort method is reachable from this
## call) — and returns to Layer 1 with zero state mutation beyond this
## overlay's own transient Layer 2 bookkeeping (candidate hexes/targets) and
## the purely-visual hex_grid_view highlight.
##
## Returns true and emits selection_cancelled(verb_id) iff a Layer 2
## selection was actually active (is_active() was true before this call);
## returns false (a true no-op — no signal emitted, `clear()` not even
## called) when Layer 1 was already active, so cancelling with nothing to
## cancel is guaranteed inert.
func cancel() -> bool:
	if not is_active():
		return false
	var verb_id: String = _active_verb_id
	clear()
	selection_cancelled.emit(verb_id)
	return true


# ── Internal helpers ─────────────────────────────────────────────────────

## _extract(selection, key) -> Array — duck-typed read of `key` off
## `selection`: a Dictionary (this codebase's actual registry-adapter
## shape) via .get(), or any other Object exposing that member via
## Object.get() (kept for parity with core/application/verb_registry.py's
## dataclass SelectionDescriptor, which this Godot runtime never
## instantiates directly but which this file's contract otherwise mirrors).
func _extract(selection, key: String) -> Array:
	if selection == null:
		return []
	if selection is Dictionary:
		return selection.get(key, [])
	var value = selection.get(key)
	return value if value != null else []


## _extract_options(selection) -> Array — FEAT-010 (US-010): duck-typed read
## of `selection`'s candidate_options (mirrors _extract() above), returning
## an empty Array whenever candidate_options is absent, null, or not itself
## an Array — the same "opaque, stored verbatim" convention core/
## application/selection_descriptor.gd's own field doc establishes.
func _extract_options(selection) -> Array:
	if selection == null:
		return []
	var value
	if selection is Dictionary:
		value = selection.get("candidate_options", null)
	else:
		value = selection.get("candidate_options")
	return value if value is Array else []


## _resolve_target_hexes(target_ids) -> Dictionary — target_id (String) ->
## HexCoord, read from hex_grid_view's own already-tracked tokens. A
## target_id with no rendered token (unknown/stale) is simply omitted —
## never highlighted, never selectable.
func _resolve_target_hexes(target_ids: Array) -> Dictionary:
	var by_id: Dictionary = {}
	if _hex_grid_view == null:
		return by_id
	for target_id in target_ids:
		var id_string: String = str(target_id)
		var token = _hex_grid_view.get_token(id_string)
		if token != null and token.hex_coord != null:
			by_id[id_string] = token.hex_coord
	return by_id


func _refresh_highlight() -> void:
	if _hex_grid_view != null:
		_hex_grid_view.set_selectable_hexes(get_highlighted_hexes())


func _on_hex_clicked(hex_coord) -> void:
	if _locked:
		return
	if not is_active():
		return
	if _awaiting_option:
		# FEAT-010 (US-010): Layer-2a's option pick is still pending -- no
		# highlight has been pushed to hex_grid_view yet (activate() pushed
		# an empty selectable set), so a click here can never land on
		# anything this overlay considers selectable. Ignored rather than
		# rejected: this is not a wayward/out-of-reach click, it is simply
		# too early in the Layer-2a/2b sequence to mean anything.
		return

	for target_id in _target_hex_by_id.keys():
		if _target_hex_by_id[target_id].equals(hex_coord):
			_resolve(target_id)
			return

	for candidate_hex in _candidate_hexes:
		if candidate_hex.equals(hex_coord):
			_resolve(candidate_hex)
			return

	selection_rejected.emit(_active_verb_id, hex_coord)


func _resolve(selection_value) -> void:
	var verb_id: String = _active_verb_id
	var chosen_option = _chosen_option
	var result
	if chosen_option != null:
		# FEAT-010 (US-010): the Layer-2a pick is carried forward into the
		# SAME OPTION_TARGET Dictionary shape presentation/
		# action_controller.gd already dispatches on (FEAT-009) — execute()
		# is invoked with the chosen option AND the Layer-2b target, never
		# just the bare scalar.
		result = _registry.execute(verb_id, {"option": chosen_option, "target": selection_value})
	else:
		result = _registry.execute(verb_id, selection_value)
	clear()
	selection_resolved.emit(verb_id, result)
