## core/application/resolve_dodge_step_use_case.gd — ResolveDodgeStepUseCase
## (FEAT-002 / US-002, Dodge-Step steel thread)
##
## Application layer (Clean Architecture): the use case that answers "given
## this Strike's already-resolved to-hit outcome, does the player need to be
## prompted for a Dodge-Step destination hex — and if so, which hex did they
## pick?" It depends ONLY on plain data (a bool + an Array of
## core/geometry/hex_coord.gd HexCoord-shaped values) and a duck-typed
## Callable seam — never on domain internals, never on any
## Presentation/Infrastructure type (ADR-001/ADR-002). Extends RefCounted
## only — zero Godot Node/Control/SceneTree imports.
##
## This use case introduces NO new hex-choice resolution algorithm of its
## own (ADR-001/ADR-002 "no duplicate seam"): the actual prompting/awaiting
## is entirely delegated to the injected `hex_choice_resolver_fn` Callable —
## the EXACT SAME seam core/application/round_session.gd's
## `_hex_choice_resolver_fn` / `_resolve_step_hex_choice()` already
## establishes (FEAT-001), itself ultimately bound at the MainScene.gd
## composition root to the real, production `hex_choice_resolver` field
## (the `_UIHexChoiceResolver` that blocks on a live hex click) — see
## MainScene.gd's `resolve_hex_choice()`.
##
## Guard-clause / anti-punt discipline (G3/G4, this steel thread's
## error_handling design note):
##   - `defender_stepped == false` (no successful Dodge occurred) — no
##     prompt, no await, returns immediately. This is the overwhelmingly
##     common case (a miss without Dodge, a hit, a failed Dodge, ...).
##   - `defender_stepped == true` but `legal_hexes` is empty (the defender
##     has no legal adjacent Step destination) — no prompt, no await,
##     returns immediately. Damage negation for this case is the caller's
##     concern (Resolution.resolve_to_hit()'s own math already reflects a
##     successful Dodge as a miss regardless of legal_hexes) — this use
##     case's sole job is deciding whether/how to prompt, never re-deriving
##     hit/damage math.
##   - `hex_choice_resolver_fn` not injected/invalid — no prompt, no await,
##     returns immediately (default-safety fallback mirroring every other
##     Callable seam in this codebase, e.g. round_session.gd's
##     `_resolve_step_hex_choice()`).
##   - Otherwise: awaits `hex_choice_resolver_fn.call(legal_hexes)` — the
##     SAME `func(legal_hexes: Array) -> HexCoord | null` contract
##     `_hex_choice_resolver_fn` already documents — and returns its result
##     verbatim. A non-empty `legal_hexes` handed to a conforming resolver
##     must never resolve to null (see
##     core/application/ports/hex_choice_resolver_port.gd's own contract);
##     this use case does not re-validate that invariant itself — it is the
##     injected resolver's job, exactly as it already is for every other
##     caller of that seam.
class_name ResolveDodgeStepUseCase
extends RefCounted


## resolve(defender_id, defender_stepped, legal_hexes, hex_choice_resolver_fn)
## -> Dictionary
##
## defender_id             — the defending combatant's stable id (String),
##                            carried through on the returned Dictionary
##                            purely for the caller's/a test's observability;
##                            never consulted by this use case's own logic
##                            (mirrors HexChoiceResolverPort.choose_step_hex()'s
##                            own documented `defender_id` contract).
## defender_stepped         — bool, the Resolution.resolve_to_hit() result's
##                            "defender_stepped" flag for THIS Strike (true
##                            only after a genuinely successful Dodge).
## legal_hexes              — Array of HexCoord-shaped values, e.g.
##                            presentation/movement_input_controller.gd's
##                            get_selectable_step_hexes() output for the
##                            defender's CURRENT position — this use case
##                            never computes/re-derives this set itself
##                            (ADR-001: no new adjacency rule).
## hex_choice_resolver_fn   — Callable satisfying `func(legal_hexes: Array)
##                            -> HexCoord | null` (the SAME contract
##                            round_session.gd's `_hex_choice_resolver_fn`
##                            already documents/consumes).
##
## Returns Dictionary:
##   "prompted"    — bool, true iff the Step-selection prompt was actually
##                   invoked (i.e. `hex_choice_resolver_fn` was awaited).
##   "defender_id" — the `defender_id` argument, verbatim.
##   "chosen_hex"  — the resolver's answer (a HexCoord, or null when no
##                   prompt was ever invoked, per the guard clauses above).
func resolve(
	defender_id: String,
	defender_stepped: bool,
	legal_hexes: Array,
	hex_choice_resolver_fn: Callable
) -> Dictionary:
	if not defender_stepped:
		return {"prompted": false, "defender_id": defender_id, "chosen_hex": null}

	if legal_hexes.is_empty():
		return {"prompted": false, "defender_id": defender_id, "chosen_hex": null}

	if not hex_choice_resolver_fn.is_valid():
		return {"prompted": false, "defender_id": defender_id, "chosen_hex": null}

	var chosen_hex = await hex_choice_resolver_fn.call(legal_hexes)
	return {"prompted": true, "defender_id": defender_id, "chosen_hex": chosen_hex}
