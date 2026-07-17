## core/combat/ai.gd — Enemy AI Module (FEAT-089 / FR-012)
##
## Domain layer (ADR-001): pure GDScript class — no Node/Control inheritance.
## Encapsulates enemy action selection logic, decoupled from encounter.gd's
## run_round() method to satisfy the data-driven encounter architecture (FR-012).
##
## decide_action() is the single entry point: given a combatant dict and
## an array of potential targets, it returns a structured action dict describing
## what the combatant should do and against whom.
##
## Satisfies: FR-012, US-009, ADR-001
##
## FEAT-003 (US-003 / FR-007): decide_action() is extended (not replaced) with
## a reach check at the TOP of its target-selection logic — mirroring the
## SAME melee-adjacency (core/geometry/hex_math.gd HexMath.hex_neighbors())
## and ranged-range (HexMath.hex_distance() <= weapon.range_hexes) rules
## core/application/resolve_action_use_case.gd already enforces when
## resolving a Strike, so an enemy's decision and the use case that later
## executes it always agree on what counts as "in reach". When the chosen
## target is already in reach, decide_action() reports
## {destination: null, will_strike: true} and issues ZERO Stride — this is
## the baseline AI decision path FEAT-004's movement/closing-distance logic
## is layered on top of. Exactly like the reach precondition in
## resolve_action_use_case.gd, this check is a no-op (always "in reach")
## when either the acting combatant or the chosen target lacks "hex_coord"
## data — preserving the pre-FEAT-003 "always Strike the first/nearest
## living target" contract for every legacy caller.
##
## FEAT-004 (US-004 / FR-008, ADR-005 groundwork): when the nearest living
## target is OUT of reach, decide_action() optionally closes distance by
## Striding toward it. This is opt-in via two NEW optional parameters
## (`action_economy`, `other_combatants`) appended AFTER the pre-existing
## (combatant, targets) signature — every legacy 2-argument call site
## (tests/unit/test_ai.gd, tests/unit/core/combat/test_ai_reach_strike.gd,
## core/application/round_session.gd, etc.) is completely unaffected and
## keeps the exact FEAT-003 "no Stride issued" contract, since the new
## movement logic below is gated entirely behind `action_economy != null`.
##
## When an `action_economy` IS supplied and the chosen target is out of
## reach, decide_action():
##   1. Sources the legal candidate destinations from the SAME
##      core/rules/movement.gd Movement.get_stride_destinations() the
##      player's own Stride affordance uses (ADR-001 — one shared domain
##      rule, never re-derived).
##   2. Selects the destination that MINIMISES HexMath.hex_distance() to the
##      chosen (nearest living) target, breaking ties by the SAME stable
##      lowest-(q,r) rule _select_target() already uses (deterministic — no
##      RNG, US-007).
##   3. Only Strides if the best candidate STRICTLY reduces the distance to
##      the target versus the actor's current position — an enemy already as
##      close as any legal Stride can get it never moves pointlessly.
##   4. Executes the chosen Stride via Movement.stride(), which spends
##      exactly one action from `action_economy` and marks its Movement
##      trait (the SAME per-turn gate FEAT-001's Step hook trips) — the
##      identical ActionEconomy gate a player-driven Stride goes through.
##
## FEAT-005 (US-005 / FR-009, ADR-004) — SUPERSEDED/REMOVED by FEAT-007
## below: this feature originally made decide_action() re-check reach
## immediately after the Stride executed above, in the SAME decision cycle,
## and report a composite "Stride-then-Strike" AIDecision (will_strike: true
## alongside the Stride's own action_type/destination) when the Stride
## closed the target into reach with an action still remaining. FEAT-007
## removes this composite path entirely — see its doc block below for the
## current (single-action-per-call) contract.
##
## FEAT-006 (US-006 / FR-010, ADR-002): before EVER attempting to Stride,
## _stride_toward_target() now explicitly checks
## action_economy.can_take_movement_action() (the SAME per-turn
## Movement-trait gate core/rules/movement.gd's stride()/step() already
## share, ADR-003's single source of truth) and
## action_economy.get_remaining() > 0 (the SAME per-round budget stride()'s
## own spend_action() call already enforces). Movement.stride() already
## rejects a locked-out/over-budget Stride internally (ERR_ACTION_UNAVAILABLE
## / MOVEMENT_ALREADY_USED / ALREADY_SPENT) — this is a fail-fast, no-side-
## effect MIRROR of that same rule at the decision layer itself (never a
## second/parallel gate), so an enemy already out of movement or actions this
## turn never even computes/considers a Stride destination, guaranteeing it
## can never issue two Strides (no move-then-move) or exceed its per-turn
## action budget across any number of decide_action() calls/simulated turns.
##
## FEAT-007a (US-007 / FR-011, ADR-005): formalizes, as its own feature, the
## determinism guarantee _select_target() and _stride_toward_target() were
## already built on as FEAT-004 groundwork: BOTH nearest-target selection and
## Stride-destination selection break ties by the SAME stable lowest-(q,r)
## lexicographic rule (_is_lower_coord() below) whenever more than one
## candidate is equidistant. Every comparison in that tie-break path is a
## pure integer comparison over (q, r) — there is NO RNG call site, NO
## randomness-generating/randomness-port collaborator, and NO seed parameter
## anywhere in ai.gd (verified statically by
## tests/unit/core/combat/test_ai_determinism.gd's
## test_ai_gd_contains_no_rng_call_sites()). Consequently, decide_action()'s
## resulting AIDecision (target/destination/will_strike) is guaranteed
## byte-identical across any number of repeated invocations against an
## identical battlefield_state, completely independent of whichever seed is
## active via HYKAEN_SEED/seed_override (infrastructure/seed_policy.gd) —
## the tie-break path simply never consults it.
##
## FEAT-007 (US-007 / FR-005, ADR-105): REMOVES the FEAT-005 composite
## "Stride-then-Strike" path. decide_action() now returns EXACTLY ONE action
## per call, mirroring the SAME one-action-per-turn gate the player is bound
## to (core/rules/action_economy.gd's can_take_action()/_action_used):
##   - Strike immediately when the chosen target is already in reach (this
##     part is unchanged from FEAT-003).
##   - Otherwise, Stride toward the chosen target via the SAME
##     _stride_toward_target() distance-minimizing logic FEAT-004 built,
##     using the SAME core/rules/movement.gd Movement.get_stride_destinations()
##     source of legal candidates and the SAME stable lowest-(q,r) tie-break
##     (FEAT-007a above) — but decide_action() no longer re-checks reach
##     against the combatant's post-Stride position, and _stride_toward_target()
##     now ALWAYS reports will_strike: false. The Strike half (if the Stride
##     happened to land the actor in reach) is deferred entirely to the
##     enemy's NEXT decision cycle (its next turn), exactly the way a
##     player's Stride-then-Strike spans two separate verb-bar actions.
## This closes the gap where core/application/round_session.gd's
## advance_ai_turn() had to special-case a composite decision it could
## resolve only one half of (the Strike half of a same-decision composite was
## always rejected downstream by ActionEconomy's ACTION_ALREADY_USED gate,
## since Movement.stride() had already spent the turn's one action) — that
## dead-on-arrival second resolve_action_use_case.resolve() call, and the
## will_strike branch that triggered it, are both removed from
## round_session.gd's advance_ai_turn() as part of this same feature.

class_name AI

const HexMathClass = preload("res://core/geometry/hex_math.gd")
const MovementClass = preload("res://core/rules/movement.gd")


## _stride_reaction_resolver_fn — OPTIONAL (iteration K FEAT-006 / US-006,
## ADR-002): an injected, duck-typed
## Callable(mover: Dictionary, mover_start_hex, candidate_reactors: Array) ->
## Variant, AWAITED (see below) inside _stride_toward_target() immediately
## BEFORE it commits a Stride via core/rules/movement.gd's Movement.stride()
## — the seam MainScene.gd's composition root binds to a real
## core/application/use_cases/resolve_stride_use_case.gd ResolveStrideUseCase
## invocation, opening an OpportunisticStrike reaction window for every
## hostile reactor eligible per core/domain/opportunistic_strike_eligibility.gd
## BEFORE `combatant`'s hex_coord ever changes — this feature's "second
## demoable slice: a Stride opens a resolved reaction window before position
## changes".
##
## Mirrors this project's established Callable Dependency-Inversion seam
## convention (e.g. core/application/round_session.gd's
## _reaction_resolver_fn/_token_reposition_fn): this file never imports/
## references core/application/use_cases/resolve_stride_use_case.gd,
## presentation/turn_controller.gd, infrastructure/ai_reaction_policy.gd, or
## any other concrete adapter/use-case type (ADR-001/ADR-002) — it only calls
## whichever Callable MainScene.gd injects via
## set_stride_reaction_resolver_fn().
##
## Left as an invalid (unbound) Callable — the default — for every
## pre-existing caller/test double (every test in tests/unit/test_ai*.gd,
## tests/unit/core/combat/, and every headless/sim caller), which never sets
## one: _stride_toward_target()'s own guard (`if
## _stride_reaction_resolver_fn.is_valid(): ...`) makes this call an
## unconditional no-op for them, so decide_action()'s pre-existing
## byte-for-byte contract (a Stride is committed synchronously, with zero new
## await-driven suspension) is completely unaffected (NFR-004).
##
## iteration K FEAT-008 (US-008): the Variant this Callable resolves to is
## now READ by _stride_toward_target() (previously discarded) — when it is a
## Dictionary carrying `"mover_downed": true` (core/application/use_cases/
## resolve_stride_use_case.gd's own return contract), the Stride below is
## CANCELLED — `combatant` is never repositioned. Any other answer (a bare
## `{}`, a non-Dictionary/void return, or a Dictionary with `"mover_downed"`
## false/absent) is treated as "the Stride may proceed", matching this
## field's pre-existing default-safe convention.
var _stride_reaction_resolver_fn: Callable = Callable()


## set_stride_reaction_resolver_fn(fn) -> void — iteration K FEAT-006:
## injects the Callable described above. Intended to be called once by the
## composition root (MainScene.gd), the SAME way core/application/
## round_session.gd's set_reaction_resolver_fn() already is, e.g.:
##   ai_decision_port.set_stride_reaction_resolver_fn(Callable(main_scene, "_resolve_enemy_stride_opportunistic_window"))
func set_stride_reaction_resolver_fn(fn: Callable) -> void:
	_stride_reaction_resolver_fn = fn


## decide_action(combatant: Dictionary, targets: Array, action_economy = null, other_combatants: Array = []) → Dictionary
##
## Selects the best action for the given combatant from the available target pool.
##
## Parameters:
##   combatant        — A combatant Dictionary (name, hp_current, weapon, …).
##                       MAY carry a "hex_coord" key (a
##                       core/geometry/hex_coord.gd HexCoord instance) — see
##                       the reach check below. Must have hp_current > 0 for
##                       a valid action to be returned.
##   targets          — Array of combatant Dictionaries on the opposing
##                       side. Each MAY also carry a "hex_coord" key. Also
##                       used (FEAT-004) as part of the Stride-destination
##                       occupancy check — a living OR dead target's hex is
##                       never a legal Stride destination.
##   action_economy   — OPTIONAL (FEAT-004 / US-004 / FR-008). The acting
##                       combatant's core/rules/action_economy.gd instance
##                       for this round. Omitted (null, the default): the
##                       exact FEAT-003 no-Stride contract is preserved for
##                       every legacy caller. Supplied: an out-of-reach
##                       nearest living target triggers the Stride-closing
##                       logic documented at file level.
##   other_combatants — OPTIONAL (FEAT-004). Every OTHER combatant on the
##                       battlefield (e.g. allies) besides `combatant` and
##                       `targets`, folded into the SAME occupancy check
##                       core/rules/movement.gd already performs. Defaults
##                       to an empty Array (no additional occupants beyond
##                       `targets`).
##
## Returns a Dictionary with at minimum:
##   action_type: String — the action to perform ('Strike' or, FEAT-004,
##                          'Stride'), or '' if no action is available this
##                          decision (no living target; the nearest living
##                          target is out of reach and either no
##                          `action_economy` was supplied, no legal Stride
##                          destination exists, no candidate destination
##                          improves distance, or the Stride's ActionEconomy
##                          spend was rejected).
##   target:      Dictionary — the chosen target combatant dict, or {} if
##                          none is available/no action was taken.
##   destination: HexCoord or null — null unless a Stride was actually
##                          issued (FEAT-004), in which case it is the hex
##                          `combatant` just moved into.
##   will_strike: bool — true iff action_type == "Strike" (the chosen target
##                          was ALREADY in reach — melee-adjacent, or within a
##                          ranged weapon's range_hexes — this decision, with
##                          zero Stride issued). FEAT-007 (US-007 / FR-005,
##                          ADR-105): ALWAYS false when action_type ==
##                          "Stride" — decide_action() returns exactly ONE
##                          action per call, never a composite
##                          Stride-then-Strike. Even when a Stride happens to
##                          land the combatant in reach of its target, the
##                          Strike is deferred to the combatant's NEXT
##                          decision cycle (its next turn) — the SAME
##                          one-action-per-turn gate the player is bound to
##                          (core/rules/action_economy.gd's can_take_action()).
##
## v0 behaviour (unchanged): the target pool is searched in order and the
## first living target found is chosen when no positional (hex_coord) data
## is available. Future iterations may weight by hp or conditions.
func decide_action(combatant, targets: Array, action_economy = null, other_combatants: Array = []) -> Dictionary:
	# Phase C.3: `combatant`/`targets` are now Combatant instances; the chosen
	# target is a live instance (or null when none), so round_session's Strike
	# lands on the same reference the container holds. The "no target" sentinel
	# is null (was an empty Dictionary).
	var chosen_target = _select_target(combatant, targets)

	# No living target — return a null-action sentinel
	if chosen_target == null:
		return {"action_type": "", "target": null, "destination": null, "will_strike": false}

	var in_reach: bool = _is_in_reach(combatant, chosen_target)
	if in_reach:
		# Already in reach: Strike immediately, zero Stride issued.
		return {"action_type": "Strike", "target": chosen_target, "destination": null, "will_strike": true}

	# Out of reach. Without an ActionEconomy collaborator, FEAT-004's
	# Stride-closing logic cannot run — preserve the exact FEAT-003 no-op
	# contract for every legacy (2-argument) caller.
	if action_economy == null:
		return {"action_type": "", "target": null, "destination": null, "will_strike": false}

	# iteration K FEAT-006 (US-006): `await`ed so a genuinely suspending
	# _stride_reaction_resolver_fn (the real player-facing pop-up, routed via
	# MainScene.gd) is fully resolved before this method returns — see that
	# field's own doc. For every pre-existing caller (no resolver injected),
	# this `await` never actually suspends and decide_action() resolves
	# synchronously within the same call, byte-for-byte identical to before
	# this feature (NFR-004).
	return await _stride_toward_target(combatant, chosen_target, targets, action_economy, other_combatants)


## _stride_toward_target(combatant, chosen_target, targets, action_economy,
## other_combatants) -> Dictionary — FEAT-004 (US-004 / FR-008): selects the
## legal Stride destination (Movement.get_stride_destinations()) that
## minimises hex_distance to `chosen_target`, breaking ties by the SAME
## stable lowest-(q,r) rule _select_target() uses, then executes it via
## Movement.stride() (spending one action + marking the Movement trait
## through `action_economy` — the SAME gate a player-driven Stride uses).
## Never Strides if no legal destination improves distance versus the
## actor's CURRENT position, or if Movement.stride() itself rejects the
## spend (e.g. ERR_MOVEMENT_LOCKED, ERR_ACTION_UNAVAILABLE) — either case
## falls back to the same null-action sentinel decide_action() already
## returns for "no action available".
##
## FEAT-007 (US-007 / FR-005, ADR-105): a SUCCESSFUL Stride ALWAYS reports
## will_strike: false — the composite Stride-then-Strike decision FEAT-005
## introduced is removed. decide_action() returns exactly ONE action per
## call; whether the Stride happened to land the target in reach is
## irrelevant here — that Strike, if any, is decided on the combatant's NEXT
## decide_action() call (its next turn).
## iteration K FEAT-006 (US-006, ADR-004): this method is now `await`-capable
## (a coroutine) — see `_stride_reaction_resolver_fn`'s own doc. Every
## pre-existing call site/return path below is otherwise byte-for-byte
## unchanged.
func _stride_toward_target(
	combatant,
	chosen_target,
	targets: Array,
	action_economy,
	other_combatants: Array
) -> Dictionary:
	# FEAT-006 (US-006 / FR-010, ADR-002): explicit, fail-fast guard —
	# checked BEFORE any Stride destination is even computed — mirroring the
	# SAME action-economy budget/Movement-trait rules Movement.stride()
	# itself enforces (single source of truth, ADR-003). Guarantees the AI
	# never attempts a second Movement-trait action within the same turn
	# (no move-then-move) and never attempts to spend an action it does not
	# have, across any number of decide_action() calls in a turn/round.
	if action_economy.get_remaining() <= 0 or not action_economy.can_take_movement_action():
		return {"action_type": "", "target": null, "destination": null, "will_strike": false}

	var origin = combatant.hex_coord
	var target_hex = chosen_target.hex_coord
	var occupancy: Array = targets + other_combatants

	var destinations: Array = MovementClass.get_stride_destinations(combatant, occupancy)
	if destinations.is_empty():
		return {"action_type": "", "target": null, "destination": null, "will_strike": false}

	var current_distance: int = HexMathClass.hex_distance(origin, target_hex)
	var best_destination = null
	var best_distance: int = -1
	for candidate in destinations:
		var distance: int = HexMathClass.hex_distance(candidate, target_hex)
		if best_destination == null or distance < best_distance or (distance == best_distance and _is_lower_coord(candidate, best_destination)):
			best_destination = candidate
			best_distance = distance

	if best_distance >= current_distance:
		# No legal Stride destination gets any closer — do not move
		# pointlessly (and never spend the action for a no-op move).
		return {"action_type": "", "target": null, "destination": null, "will_strike": false}

	# iteration K FEAT-006 (US-006): open an OpportunisticStrike reaction
	# window for every eligible hostile reactor in `occupancy` BEFORE this
	# Stride commits — Movement.stride() below is the sole hex_coord mutation
	# point for this decision, so this call site is guaranteed to run before
	# `combatant`'s position changes. A no-op for every pre-existing caller
	# (see `_stride_reaction_resolver_fn`'s own doc).
	#
	# iteration K FEAT-008 (US-008): the resolver's own return value is now
	# read (previously discarded — see core/application/use_cases/
	# resolve_stride_use_case.gd's own FEAT-008 doc for the full "caller
	# never consulted the result" gap this closes). Any non-Dictionary
	# answer (every pre-FEAT-008 caller/test double, whose resolver returns
	# nothing / void) is treated exactly like `{}` -- "mover_downed" reads
	# false via the same default-safe `.get()` below, so this change is a
	# pure no-op for every existing caller (NFR-004).
	var opportunistic_window_result = {}
	if _stride_reaction_resolver_fn.is_valid():
		opportunistic_window_result = await _stride_reaction_resolver_fn.call(combatant, origin, occupancy)

	if opportunistic_window_result is Dictionary and opportunistic_window_result.get("mover_downed", false):
		# A lethal Opportunistic Strike defeated `combatant` before its
		# Stride could ever commit -- cancel the Stride entirely.
		# Movement.stride() below is never called, so `combatant.hex_coord`
		# is never mutated; `combatant` remains at `origin`, exactly like
		# the "no legal Stride destination" no-op decide_action() already
		# returns above.
		return {"action_type": "", "target": null, "destination": null, "will_strike": false}

	var stride_result: Dictionary = MovementClass.stride(combatant, best_destination, action_economy, occupancy)
	if not stride_result.get("ok", false):
		return {"action_type": "", "target": null, "destination": null, "will_strike": false}

	# FEAT-007 (US-007 / FR-005, ADR-105): decide_action() issues exactly ONE
	# action per call — a Stride NEVER also reports will_strike: true, even
	# when it happens to land the combatant in reach of the target. Any
	# Strike is deferred to the combatant's next decision cycle.
	return {"action_type": "Stride", "target": chosen_target, "destination": best_destination, "will_strike": false}


## _select_target(combatant, targets) -> Dictionary — chooses the target this
## combatant will act against. When `combatant` carries "hex_coord" data,
## selects the NEAREST living target by HexMath.hex_distance() (targets
## lacking "hex_coord" are skipped from distance comparison), breaking ties
## by the stable lowest-(q,r) rule (deterministic — no RNG). Falls back to
## the pre-existing "first living target in array order" behavior when the
## acting combatant has no "hex_coord" (legacy callers) or none of the
## living targets carry positional data.
func _select_target(combatant, targets: Array):
	var living: Array = []
	for t in targets:
		if t.hp_current > 0:
			living.append(t)

	if living.is_empty():
		return null

	var combatant_hex = combatant.hex_coord
	if combatant_hex == null:
		return living[0]

	var nearest = null
	var nearest_distance: int = -1
	for t in living:
		var t_hex = t.hex_coord
		if t_hex == null:
			continue
		var distance: int = HexMathClass.hex_distance(combatant_hex, t_hex)
		if nearest == null or distance < nearest_distance or (distance == nearest_distance and _is_lower_coord(t_hex, nearest.hex_coord)):
			nearest = t
			nearest_distance = distance

	return nearest if nearest != null else living[0]


## _is_lower_coord(a, b) -> bool — stable tie-break rule (US-007 determinism):
## true iff `a` sorts before `b` under (q, r) lexicographic order.
func _is_lower_coord(a, b) -> bool:
	if a.q != b.q:
		return a.q < b.q
	return a.r < b.r


## _is_in_reach(combatant, target) -> bool — FEAT-003 reach check: mirrors
## core/application/resolve_action_use_case.gd's melee-adjacency/ranged-range
## precondition exactly. A no-op (always true) when either side lacks
## "hex_coord" data — see _requires_reach_check().
func _is_in_reach(combatant, target) -> bool:
	if not _requires_reach_check(combatant, target):
		return true
	if _is_ranged_weapon(combatant):
		return _is_in_range(combatant, target)
	return _is_adjacent(combatant, target)


## _requires_reach_check(combatant, target) -> bool — the reach check only
## applies when BOTH Dictionaries carry positional "hex_coord" data,
## mirroring core/application/resolve_action_use_case.gd's identically-named
## helper so the AI's notion of "in reach" and the use case that later
## executes a Strike never disagree.
func _requires_reach_check(combatant, target) -> bool:
	return combatant.hex_coord != null and target.hex_coord != null


## _is_adjacent(combatant, target) -> bool — true iff target.hex_coord is one
## of the 6 flat-top axial neighbors of combatant.hex_coord
## (core/geometry/hex_math.gd HexMath.hex_neighbors()).
func _is_adjacent(combatant, target) -> bool:
	var neighbors: Array = HexMathClass.hex_neighbors(combatant.hex_coord)
	for neighbor in neighbors:
		if neighbor.equals(target.hex_coord):
			return true
	return false


## _is_ranged_weapon(combatant) -> bool — true iff the acting combatant's
## "weapon" Dictionary carries a "range_hexes" key (mirrors
## core/application/resolve_action_use_case.gd's identically-named helper).
func _is_ranged_weapon(combatant) -> bool:
	var weapon: Dictionary = combatant.weapon
	return weapon.has("range_hexes")


## _is_in_range(combatant, target) -> bool — true iff the target's
## HexMath.hex_distance() from the combatant is within the acting weapon's
## range_hexes (inclusive) — mirrors
## core/application/resolve_action_use_case.gd's identically-named helper.
func _is_in_range(combatant, target) -> bool:
	var weapon: Dictionary = combatant.weapon
	var range_hexes: int = weapon.get("range_hexes", 1)
	var distance: int = HexMathClass.hex_distance(combatant.hex_coord, target.hex_coord)
	return distance <= range_hexes
