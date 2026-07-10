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
##
##     FEAT-003 (US-003, ADR-005 guard-clause discipline, NFR-003 "no
##     stall/deadlock"): this is the dedicated "successful Dodge, zero legal
##     adjacent hexes" edge case — a defender who is boxed in (every
##     adjacent hex occupied/out-of-bounds) can still roll a successful
##     Dodge. Guarding on `legal_hexes.is_empty()` BEFORE ever touching
##     `hex_choice_resolver_fn` is what makes this safe: the Step-selection
##     prompt (the real `_UIHexChoiceResolver`, which genuinely blocks on a
##     live hex click) is NEVER invoked with nothing to offer, so this
##     branch can never await/stall the turn coroutine — it returns on the
##     same frame it was called, exactly like the `defender_stepped == false`
##     guard above. final_damage/damage_final is still correctly negated
##     (0) for this branch — again, entirely via Resolution.resolve_to_hit()
##     already recording the successful Dodge as a miss, never via any logic
##     this use case adds. See tests/gut/test_dodge_step_no_legal_hex.gd for
##     the boot-real-MainScene proof of both halves of this contract
##     (damage negated AND no prompt AND no stall) together.
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
##
## FEAT-005 (US-005, Iteration K — "Synchronous AI hex chooser for enemy
## Dodge-Step", ADR-004): this SAME class is now ALSO consumed by
## MainScene.gd's `_resolve_enemy_dodge_step()` for the player-strikes-ENEMY
## path (the Skeleton's OWN Dodge-Step), never a second/duplicated use case
## (ADR-001/ADR-002 "no duplicate seam" — this feature's code-inspection
## test_criterion). The ONLY thing that differs between the player path
## (round_session.gd's `_resolve_dodge_step_prompt()`) and the enemy path
## (MainScene.gd's `_resolve_enemy_dodge_step()`) is WHICH
## `hex_choice_resolver_fn` is handed in — the real, blocking
## `_UIHexChoiceResolver` for the player; infrastructure/
## ai_hex_choice_resolver.gd's synchronous, no-pop-up AIHexChoiceResolver for
## the enemy — this use case's own resolve() method is identical, unmodified,
## and reused verbatim by both call sites.
##
## FEAT-004 (US-004, Dodge-Step steel thread — "Relocate defender to
## player-chosen hex via shared token-reposition seam"): once a hex has
## actually been chosen (`chosen_hex != null`), this use case now ALSO
## relocates the defender through the SAME two-step sequence
## core/application/round_session.gd's `_reposition_token_after_ai_stride()`
## already establishes for an AI-issued Stride (ADR-002 "no duplicate seam" —
## never a second, parallel reposition implementation):
##   1. `token_reposition_fn.call(defender_id, chosen_hex)` — the injected
##      ITokenRepositionPort Callable (the SAME `_token_reposition_fn` seam
##      round_session.gd already threads through for AI-Stride, bound at the
##      REAL MainScene.gd composition root to
##      `Callable(hex_grid_view, "move_token")` — never a second reposition
##      function), so the on-screen token visibly moves to `chosen_hex`.
##   2. `target["hex_coord"] = chosen_hex` — updates the defender's own
##      Combatant.hex_coord Dictionary field directly (the same mutation
##      shape core/rules/movement.gd's `_set_hex()` already applies for a
##      Dictionary-shaped combatant), so subsequent reach/adjacency
##      computations observe the defender's NEW position immediately.
## Both `token_reposition_fn` and `target` are OPTIONAL, defaulting to an
## invalid Callable / an empty Dictionary respectively — every pre-existing
## 4-argument call site (this use case's own pre-FEAT-004 contract, still
## exercised directly by tests/gut/test_dodge_step_prompt.gd's and
## tests/gut/test_dodge_step_no_legal_hex.gd's own isolation coverage) keeps
## behaving byte-for-byte identically: an invalid `token_reposition_fn` is
## never invoked (mirrors `_reposition_token_after_ai_stride()`'s own no-op
## guard), and an empty `target` is never mutated.
class_name ResolveDodgeStepUseCase
extends RefCounted


## resolve(defender_id, defender_stepped, legal_hexes, hex_choice_resolver_fn,
##         token_reposition_fn, target) -> Dictionary
##
## defender_id             — the defending combatant's stable id (String),
##                            carried through on the returned Dictionary
##                            purely for the caller's/a test's observability;
##                            never consulted by this use case's own logic
##                            (mirrors HexChoiceResolverPort.choose_step_hex()'s
##                            own documented `defender_id` contract), but also
##                            the `token_id` handed to `token_reposition_fn`
##                            below (the SAME identity convention
##                            `_reposition_token_after_ai_stride()` uses).
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
## token_reposition_fn      — OPTIONAL (FEAT-004). Callable satisfying
##                            `func(token_id: String, new_hex_coord) -> void`
##                            — the SAME ITokenRepositionPort seam
##                            round_session.gd's `_token_reposition_fn`
##                            already documents/consumes for AI-Stride.
##                            Invoked with `(defender_id, chosen_hex)` ONLY
##                            when a hex was actually chosen AND this Callable
##                            is valid — never on the "no prompt"/"no hex
##                            chosen" guard-clause paths above. Defaults to an
##                            invalid Callable, matching every pre-FEAT-004
##                            caller's behavior (no reposition call at all).
## target                   — OPTIONAL (FEAT-004). The defender's own
##                            combatant Dictionary (the SAME Dictionary
##                            round_session.gd's `_entries` holds a live
##                            reference to). When non-empty AND a hex was
##                            actually chosen, this use case sets
##                            `target["hex_coord"] = chosen_hex` directly —
##                            the sole Combatant.hex_coord mutation this
##                            feature introduces. Defaults to an empty
##                            Dictionary, matching every pre-FEAT-004 caller's
##                            behavior (no mutation at all).
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
	hex_choice_resolver_fn: Callable,
	token_reposition_fn: Callable = Callable(),
	target: Dictionary = {}
) -> Dictionary:
	if not defender_stepped:
		return {"prompted": false, "defender_id": defender_id, "chosen_hex": null}

	if legal_hexes.is_empty():
		return {"prompted": false, "defender_id": defender_id, "chosen_hex": null}

	if not hex_choice_resolver_fn.is_valid():
		return {"prompted": false, "defender_id": defender_id, "chosen_hex": null}

	var chosen_hex = await hex_choice_resolver_fn.call(legal_hexes)

	if chosen_hex != null:
		# FEAT-004: mirrors _reposition_token_after_ai_stride()'s own
		# "reposition the on-screen token, via the shared seam" step — same
		# call shape (token_id, new_hex_coord), only the seam's origin
		# (Dodge-Step vs AI-Stride) differs.
		if token_reposition_fn.is_valid():
			token_reposition_fn.call(defender_id, chosen_hex)
		# FEAT-004: the sole Combatant.hex_coord mutation this feature
		# introduces — mirrors core/rules/movement.gd's own `_set_hex()`
		# Dictionary-branch mutation shape.
		if not target.is_empty():
			target["hex_coord"] = chosen_hex

	return {"prompted": true, "defender_id": defender_id, "chosen_hex": chosen_hex}
