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
## AREA_SET origin-hex pick and preview (FEAT-242 / US-011): a descriptor
## whose resolution_mode is SelectionDescriptor.ResolutionMode.AREA_SET
## (core/application/selection_descriptor.gd) additively changes what a
## Layer-2 hex click on one of the descriptor's candidate_hexes (here,
## candidate ORIGIN hexes) does: instead of resolving immediately (the
## legacy SCALAR behavior every other hex-destination verb still gets),
## the FIRST such click computes the affected-hex set via
## core/application/selection_resolution_use_case.gd's
## SelectionResolutionUseCase.affected_set(origin, geometry_rule) -- a pure
## CONSUMER of core/geometry's HexMath, per that method's own doc calling
## out this exact future consumer -- and PREVIEWS it by pushing the
## computed set to hex_grid_view.set_selectable_hexes(), the SAME highlight
## affordance every other Layer-2 highlight (candidate hexes/targets,
## Layer-2a/2b) already reuses (ADR-002: no forked/parallel highlight
## mechanism). No registry.execute() call happens on this first click --
## is_awaiting_area_confirm() reports true and the overlay waits for
## confirmation. A SECOND click landing on any hex WITHIN the previewed set
## (the origin itself, or any other hex the preview highlighted) confirms
## the selection: it resolves the FULL computed target_set -- not just the
## clicked hex -- into registry.execute(verb_id, target_set), mirroring
## presentation/action_controller.gd's TARGET_SET SelectionShape (FEAT-009)
## contract. A descriptor whose resolution_mode is anything other than
## AREA_SET (every verb registered before this feature, including every
## SCALAR/OPTION_THEN_TARGET verb) is completely unaffected: candidate
## hexes still resolve on the very first click, exactly as before.
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

## FEAT-242 (US-011): the AREA_SET resolution-mode enum (duck-typed access
## only -- SelectionDescriptor.ResolutionMode.AREA_SET) and the use case
## this overlay calls directly to compute an AREA_SET preview, exactly the
## "future consumer" that class's own affected_set() doc anticipates. A
## presentation-layer file instantiating an application-layer use case
## directly (no port) mirrors the existing convention established by e.g.
## presentation/reaction_controller.gd/stride_action_controller.gd's own
## `UseCaseClass.new()` call sites -- this is a pure computation with no
## I/O, so no port is warranted (design notes: "no new ports beyond the
## applier seam").
const SelectionDescriptorClass = preload("res://core/application/selection_descriptor.gd")
const SelectionResolutionUseCaseClass = preload("res://core/application/selection_resolution_use_case.gd")

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

## FEAT-242 (US-011): the active SelectionDescriptor's resolution_mode,
## verbatim -- SelectionDescriptor.ResolutionMode.SCALAR (the legacy,
## unaffected default) for every verb registered before this feature.
var _resolution_mode: int = SelectionDescriptorClass.ResolutionMode.SCALAR

## FEAT-242 (US-011): the active SelectionDescriptor's geometry_rule,
## verbatim -- opaque to this class (mirrors _candidate_options' "opaque,
## stored verbatim" convention), only meaningful when _resolution_mode ==
## AREA_SET. null otherwise.
var _geometry_rule = null

## FEAT-242 (US-011): true once a candidate origin hex has been picked for
## an AREA_SET verb and its computed affected-hex set is being PREVIEWED --
## i.e. highlighted via hex_grid_view.set_selectable_hexes() -- but not yet
## confirmed/resolved. Always false for a non-AREA_SET descriptor.
var _awaiting_area_confirm: bool = false

## FEAT-242 (US-011): the full computed affected-hex set (Array of
## core/geometry/hex_coord.gd HexCoord instances) currently being previewed
## while _awaiting_area_confirm is true -- the SAME set a confirming click
## resolves into registry.execute() verbatim. Empty when not previewing.
var _area_target_set: Array = []


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
	if _awaiting_area_confirm:
		# FEAT-242 (US-011): while previewing an AREA_SET pick, the
		# highlighted set is the FULL computed affected set, not the raw
		# origin candidates -- mirrors what was actually pushed to
		# hex_grid_view.set_selectable_hexes() in _enter_area_preview()
		# below.
		return _area_target_set.duplicate()
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
	_resolution_mode = _extract_resolution_mode(selection)
	_geometry_rule = _extract_geometry_rule(selection)
	_awaiting_area_confirm = false
	_area_target_set = []

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


## is_awaiting_area_confirm() -> bool — FEAT-242 (US-011): true while an
## AREA_SET verb's computed affected-hex set is being previewed (a
## candidate origin hex has been picked, its affected set highlighted via
## hex_grid_view, but no confirming click has landed yet). Always false for
## every non-AREA_SET descriptor.
func is_awaiting_area_confirm() -> bool:
	return _awaiting_area_confirm


## get_area_target_set() -> Array — the full computed affected-hex set
## currently being previewed (test/inspection helper; empty Array when not
## previewing). The exact same Array a confirming click resolves into
## registry.execute() verbatim.
func get_area_target_set() -> Array:
	return _area_target_set.duplicate()


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
	# Per-option candidate_targets override (future verbs may embed a
	# target list in the option dict to switch Layer-2b at pick time).
	if option is Dictionary and "candidate_targets" in option:
		_target_hex_by_id = _resolve_target_hexes(option.get("candidate_targets", []))
		_candidate_hexes = []
	_refresh_highlight()
	# Auto-resolve when no targets or hexes remain (e.g. Channel, self-cast).
	if _candidate_hexes.is_empty() and _target_hex_by_id.is_empty():
		_resolve(null)


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
	_resolution_mode = SelectionDescriptorClass.ResolutionMode.SCALAR
	_geometry_rule = null
	_awaiting_area_confirm = false
	_area_target_set = []
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


## _extract_resolution_mode(selection) -> int — FEAT-242 (US-011):
## duck-typed read of `selection`'s resolution_mode (mirrors
## _extract_options() above), defaulting to
## SelectionDescriptor.ResolutionMode.SCALAR whenever resolution_mode is
## absent or null -- the same backward-compatible default
## core/application/selection_descriptor.gd itself establishes, so every
## verb registered before this feature (which never populates this key at
## all) is completely unaffected.
func _extract_resolution_mode(selection) -> int:
	if selection == null:
		return SelectionDescriptorClass.ResolutionMode.SCALAR
	var value
	if selection is Dictionary:
		value = selection.get("resolution_mode", null)
	else:
		value = selection.get("resolution_mode")
	return value if value != null else SelectionDescriptorClass.ResolutionMode.SCALAR


## _extract_geometry_rule(selection) -> Dictionary or null — FEAT-242
## (US-011): duck-typed read of `selection`'s geometry_rule, opaque to this
## class (mirrors _extract_options()' "opaque, stored verbatim"
## convention). null whenever geometry_rule is absent -- meaningful only
## when resolution_mode is AREA_SET.
func _extract_geometry_rule(selection):
	if selection == null:
		return null
	if selection is Dictionary:
		return selection.get("geometry_rule", null)
	return selection.get("geometry_rule")


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

	if _resolution_mode == SelectionDescriptorClass.ResolutionMode.AREA_SET:
		# FEAT-242 (US-011): AREA_SET's origin-pick/preview/confirm flow is
		# entirely distinct from the generic candidate-hex/target matching
		# below (a click here never resolves to the bare clicked hex).
		_on_hex_clicked_area_set(hex_coord)
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


## _on_hex_clicked_area_set(hex_coord) -> void — FEAT-242 (US-011): the
## AREA_SET click-resolution state machine. While NOT yet previewing, a
## click matching one of the descriptor's candidate origin hexes computes
## the affected-hex set (_enter_area_preview()) and highlights it -- no
## resolution yet. While ALREADY previewing, a click landing on any hex
## WITHIN the previewed set confirms and resolves the FULL computed set
## into execute(); any other click (before or during preview) is rejected,
## exactly like the generic SCALAR click-matching path's own out-of-reach
## handling.
func _on_hex_clicked_area_set(hex_coord) -> void:
	if _awaiting_area_confirm:
		for previewed_hex in _area_target_set:
			if previewed_hex.equals(hex_coord):
				_resolve(_area_target_set.duplicate())
				return
		selection_rejected.emit(_active_verb_id, hex_coord)
		return

	for candidate_hex in _candidate_hexes:
		if candidate_hex.equals(hex_coord):
			_enter_area_preview(candidate_hex)
			return

	selection_rejected.emit(_active_verb_id, hex_coord)


## _enter_area_preview(origin) -> void — FEAT-242 (US-011): computes the
## affected-hex set for `origin` via
## core/application/selection_resolution_use_case.gd's
## SelectionResolutionUseCase.affected_set() -- a pure CONSUMER of
## core/geometry's HexMath, never a re-derived/forked notion of adjacency
## here -- and previews it through the SAME hex_grid_view.set_selectable_hexes()
## highlight path every other Layer-2 highlight already reuses (ADR-002).
## A descriptor with no bound geometry_rule (malformed AREA_SET) can never
## reach here in practice (core/application/selection_resolution_use_case.gd
## rejects such a descriptor at its own resolve()-time validation before any
## UI would ever be driven with one) but is handled defensively: it rejects
## the click rather than crashing on a null Dictionary.
func _enter_area_preview(origin) -> void:
	if _geometry_rule == null:
		selection_rejected.emit(_active_verb_id, origin)
		return
	var use_case := SelectionResolutionUseCaseClass.new()
	_area_target_set = use_case.affected_set(origin, _geometry_rule)
	_awaiting_area_confirm = true
	if _hex_grid_view != null:
		_hex_grid_view.set_selectable_hexes(_area_target_set.duplicate())


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
