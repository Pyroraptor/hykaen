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
## FEAT-005 (US-005 / FR-009, ADR-004): immediately after the Stride executed
## above, decide_action() re-checks reach in the SAME decision cycle — the
## IDENTICAL _is_in_reach() check FEAT-003 already performs at the top of
## decide_action(), now re-evaluated against the combatant's POST-Stride
## position (Movement.stride() already repositioned it in place). When the
## target is now in reach AND `action_economy` still reports at least one
## action remaining (action_economy.get_remaining() > 0 — the Stride's own
## spend_action() call already accounted for the action it consumed), the
## returned AIDecision reports will_strike: true alongside the Stride's own
## action_type/destination — a single composite "Stride-then-Strike" decision
## for RoundSession/ResolveActionUseCase to execute sequentially (the Strike
## itself is never resolved here — ai.gd is domain-layer and has no RNG/event
## collaborators; only resolve_action_use_case.resolve() actually applies
## damage). will_strike remains false when the target is still out of reach
## after the Stride, or when no action remains to spend on a Strike.
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

class_name AI

const HexMathClass = preload("res://core/geometry/hex_math.gd")
const MovementClass = preload("res://core/rules/movement.gd")


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
##   will_strike: bool — true iff the chosen target is in reach (melee-
##                          adjacent, or within a ranged weapon's
##                          range_hexes) and a Strike should be issued this
##                          decision. True with zero Stride issued when the
##                          target was ALREADY in reach. FEAT-005: also true
##                          when a Stride WAS issued this decision, the
##                          target is in reach from the combatant's new
##                          (post-Stride) position, AND `action_economy`
##                          reports an action remains after the Stride's own
##                          spend — a composite Stride-then-Strike decision.
##                          False when a Stride was issued but the target
##                          remains out of reach afterward, or no action
##                          remains to spend on a Strike.
##
## v0 behaviour (unchanged): the target pool is searched in order and the
## first living target found is chosen when no positional (hex_coord) data
## is available. Future iterations may weight by hp or conditions.
func decide_action(combatant: Dictionary, targets: Array, action_economy = null, other_combatants: Array = []) -> Dictionary:
	var chosen_target: Dictionary = _select_target(combatant, targets)

	# No living target — return a null-action sentinel
	if chosen_target.is_empty():
		return {"action_type": "", "target": {}, "destination": null, "will_strike": false}

	var in_reach: bool = _is_in_reach(combatant, chosen_target)
	if in_reach:
		# Already in reach: Strike immediately, zero Stride issued.
		return {"action_type": "Strike", "target": chosen_target, "destination": null, "will_strike": true}

	# Out of reach. Without an ActionEconomy collaborator, FEAT-004's
	# Stride-closing logic cannot run — preserve the exact FEAT-003 no-op
	# contract for every legacy (2-argument) caller.
	if action_economy == null:
		return {"action_type": "", "target": {}, "destination": null, "will_strike": false}

	return _stride_toward_target(combatant, chosen_target, targets, action_economy, other_combatants)


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
## FEAT-005 (US-005 / FR-009, ADR-004): on a SUCCESSFUL Stride, re-checks
## reach (_is_in_reach()) against the combatant's new (post-Stride) position
## and reports will_strike: true iff the target is now in reach AND
## `action_economy` still has an action remaining (get_remaining() > 0) after
## the Stride's own spend — the single composite Stride-then-Strike decision.
func _stride_toward_target(
	combatant: Dictionary,
	chosen_target: Dictionary,
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
		return {"action_type": "", "target": {}, "destination": null, "will_strike": false}

	var origin = combatant.get("hex_coord", null)
	var target_hex = chosen_target.get("hex_coord", null)
	var occupancy: Array = targets + other_combatants

	var destinations: Array = MovementClass.get_stride_destinations(combatant, occupancy)
	if destinations.is_empty():
		return {"action_type": "", "target": {}, "destination": null, "will_strike": false}

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
		return {"action_type": "", "target": {}, "destination": null, "will_strike": false}

	var stride_result: Dictionary = MovementClass.stride(combatant, best_destination, action_economy, occupancy)
	if not stride_result.get("ok", false):
		return {"action_type": "", "target": {}, "destination": null, "will_strike": false}

	# FEAT-005: re-check reach from the combatant's NEW (post-Stride)
	# position, in the SAME decision cycle. An action must also remain
	# (the Stride above already spent one) before reporting will_strike.
	var will_strike: bool = action_economy.get_remaining() > 0 and _is_in_reach(combatant, chosen_target)

	return {"action_type": "Stride", "target": chosen_target, "destination": best_destination, "will_strike": will_strike}


## _select_target(combatant, targets) -> Dictionary — chooses the target this
## combatant will act against. When `combatant` carries "hex_coord" data,
## selects the NEAREST living target by HexMath.hex_distance() (targets
## lacking "hex_coord" are skipped from distance comparison), breaking ties
## by the stable lowest-(q,r) rule (deterministic — no RNG). Falls back to
## the pre-existing "first living target in array order" behavior when the
## acting combatant has no "hex_coord" (legacy callers) or none of the
## living targets carry positional data.
func _select_target(combatant: Dictionary, targets: Array) -> Dictionary:
	var living: Array = []
	for t in targets:
		if t.get("hp_current", 0) > 0:
			living.append(t)

	if living.is_empty():
		return {}

	var combatant_hex = combatant.get("hex_coord", null)
	if combatant_hex == null:
		return living[0]

	var nearest: Dictionary = {}
	var nearest_distance: int = -1
	for t in living:
		var t_hex = t.get("hex_coord", null)
		if t_hex == null:
			continue
		var distance: int = HexMathClass.hex_distance(combatant_hex, t_hex)
		if nearest.is_empty() or distance < nearest_distance or (distance == nearest_distance and _is_lower_coord(t_hex, nearest.get("hex_coord"))):
			nearest = t
			nearest_distance = distance

	return nearest if not nearest.is_empty() else living[0]


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
func _is_in_reach(combatant: Dictionary, target: Dictionary) -> bool:
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
func _requires_reach_check(combatant: Dictionary, target: Dictionary) -> bool:
	return combatant.get("hex_coord", null) != null and target.get("hex_coord", null) != null


## _is_adjacent(combatant, target) -> bool — true iff target.hex_coord is one
## of the 6 flat-top axial neighbors of combatant.hex_coord
## (core/geometry/hex_math.gd HexMath.hex_neighbors()).
func _is_adjacent(combatant: Dictionary, target: Dictionary) -> bool:
	var neighbors: Array = HexMathClass.hex_neighbors(combatant["hex_coord"])
	for neighbor in neighbors:
		if neighbor.equals(target["hex_coord"]):
			return true
	return false


## _is_ranged_weapon(combatant) -> bool — true iff the acting combatant's
## "weapon" Dictionary carries a "range_hexes" key (mirrors
## core/application/resolve_action_use_case.gd's identically-named helper).
func _is_ranged_weapon(combatant: Dictionary) -> bool:
	var weapon: Dictionary = combatant.get("weapon", {})
	return weapon.has("range_hexes")


## _is_in_range(combatant, target) -> bool — true iff the target's
## HexMath.hex_distance() from the combatant is within the acting weapon's
## range_hexes (inclusive) — mirrors
## core/application/resolve_action_use_case.gd's identically-named helper.
func _is_in_range(combatant: Dictionary, target: Dictionary) -> bool:
	var weapon: Dictionary = combatant.get("weapon", {})
	var range_hexes: int = weapon.get("range_hexes", 1)
	var distance: int = HexMathClass.hex_distance(combatant["hex_coord"], target["hex_coord"])
	return distance <= range_hexes
