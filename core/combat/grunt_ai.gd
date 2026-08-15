## core/combat/grunt_ai.gd — GruntAI (FEAT-005 / US-005 / FR-012)
##
## Domain layer (Clean Architecture): the "Step-before-Strike" tier
## AIPlannerPort implementation. A domain SERVICE — given (combatant,
## world_context) it returns a pure Array of ActionPlanItem Dictionaries,
## with no orchestration, no persistence, no I/O, and no calls back into
## RoundSession. It depends outward only on the AIPlannerPort contract it
## implements (core/application/ai_planner_port.gd) and on the shared
## domain movement/scoring rules (core/rules/movement.gd,
## core/combat/hex_scorer.gd, core/geometry/hex_math.gd).
##
## Algorithm (per design notes / test_criteria):
##   1. Target selection: the living (hp_current > 0) target in
##      world_context["party"] with the LOWEST hp_current, breaking ties by
##      NEAREST hex_distance() from the combatant, and any further exact tie
##      by the same stable lowest-(q, r) rule core/combat/ai.gd and
##      core/combat/mindless_ai.gd already established (deterministic — no
##      RNG). Unlike MindlessAI, lowest HP is the PRIMARY key and distance is
##      only the tie-break — a lower-HP target is always preferred even when
##      a higher-HP target is nearer.
##   2. No living target -> return [] (a first-class WAIT, not an error).
##   3. Target already adjacent (hex_distance == 1) -> return a single
##      {"action_type": "Strike", "target": target} plan item.
##   4. Target is a 1-hex gap away (hex_distance == 2, i.e. exactly one empty
##      hex between combatant and target) -> return an ordered two-item plan
##      using a FREE Step to close the gap:
##      [{"action_type": "Step", "destination": <hex>, "target": target},
##       {"action_type": "Strike", "target": target}]
##      where <hex> is the Movement.get_step_destinations() candidate that
##      minimises hex_distance to the target (lowest-(q, r) tie-break).
##   5. Target is a 2+ hex gap away (hex_distance >= 3) -> return an ordered
##      two-item plan using a Stride, with the destination chosen by ranking
##      Movement.get_stride_destinations() through HexScorer.score_hex()
##      (highest score wins; ties broken by minimising hex_distance to the
##      target, then by the stable lowest-(q, r) rule):
##      [{"action_type": "Stride", "destination": <hex>, "target": target},
##       {"action_type": "Strike", "target": target}]
##
## Occupancy for the Step/Stride destination search is world_context["party"]
## + world_context["enemies"] (every other combatant currently on the
## board), mirroring core/combat/mindless_ai.gd's identical occupancy set.

class_name GruntAI
extends "res://core/application/ai_planner_port.gd"

const MovementClass  = preload("res://core/rules/movement.gd")
const HexMathClass   = preload("res://core/geometry/hex_math.gd")
const HexScorerClass = preload("res://core/combat/hex_scorer.gd")


## plan_turn(combatant, world_context) -> Array — see file-level doc for the
## full algorithm. Overrides AIPlannerPort's abstract base.
func plan_turn(combatant, world_context: Dictionary) -> Array:
	var party: Array = world_context.get("party", [])
	var target = _select_target(combatant, party)

	if target == null:
		return []

	var origin = _hex_of(combatant)
	var target_hex = _hex_of(target)
	var distance: int = -1
	if origin != null and target_hex != null:
		distance = HexMathClass.hex_distance(origin, target_hex)

	if distance == 1:
		return [{"action_type": "Strike", "target": target}]

	var enemies: Array = world_context.get("enemies", [])
	var occupancy: Array = party + enemies

	if distance == 2:
		var step_destination = _choose_step_destination(combatant, target, occupancy)
		if step_destination == null:
			# No legal Step destination exists (e.g. fully boxed in) —
			# nothing useful this planner can do this turn; degrade to WAIT
			# rather than emitting an unreachable/illegal Strike.
			return []
		return [
			{"action_type": "Step", "destination": step_destination, "target": target},
			{"action_type": "Strike", "target": target},
		]

	# distance >= 3 (or unknown positional data) — close the 2+ hex gap with
	# a HexScorer-ranked Stride.
	var stride_destination = _choose_stride_destination(combatant, target, occupancy, world_context)
	if stride_destination == null:
		return []

	return [
		{"action_type": "Stride", "destination": stride_destination, "target": target},
		{"action_type": "Strike", "target": target},
	]


# ── Internal helpers ─────────────────────────────────────────────────────

## _select_target(combatant, party) -> Dictionary or null — the living
## (hp_current > 0) target with the LOWEST hp_current, breaking ties by
## NEAREST hex_distance() from `combatant`, and any further exact tie by the
## stable lowest-(q, r) rule. Returns null when no living target exists.
func _select_target(combatant, party: Array):
	var living: Array = []
	for candidate in party:
		if _hp_of(candidate) > 0:
			living.append(candidate)

	if living.is_empty():
		return null

	var origin = _hex_of(combatant)
	var best = null
	var best_hp: int = 0
	var best_distance: int = -1
	for candidate in living:
		var hp: int = _hp_of(candidate)
		var candidate_hex = _hex_of(candidate)
		var distance: int = -1
		if origin != null and candidate_hex != null:
			distance = HexMathClass.hex_distance(origin, candidate_hex)

		if best == null:
			best = candidate
			best_hp = hp
			best_distance = distance
			continue

		if hp < best_hp:
			best = candidate
			best_hp = hp
			best_distance = distance
		elif hp == best_hp:
			var best_hex = _hex_of(best)
			if (
				distance != -1
				and (best_distance == -1 or distance < best_distance)
			) or (
				distance == best_distance
				and candidate_hex != null
				and best_hex != null
				and _is_lower_coord(candidate_hex, best_hex)
			):
				best = candidate
				best_hp = hp
				best_distance = distance

	return best


## _choose_step_destination(combatant, target, occupancy) -> HexCoord or
## null — the legal Movement.get_step_destinations() candidate that
## minimises hex_distance to `target`, breaking exact ties by the stable
## lowest-(q, r) rule. Returns null when no legal destination exists.
func _choose_step_destination(combatant, target, occupancy: Array):
	var destinations: Array = MovementClass.get_step_destinations(combatant, occupancy)
	if destinations.is_empty():
		return null

	var target_hex = _hex_of(target)
	var best = null
	var best_distance: int = -1
	for candidate in destinations:
		var distance: int = HexMathClass.hex_distance(candidate, target_hex)
		if best == null or distance < best_distance or (distance == best_distance and _is_lower_coord(candidate, best)):
			best = candidate
			best_distance = distance

	return best


## _choose_stride_destination(combatant, target, occupancy, world_context) ->
## HexCoord or null — the legal Movement.get_stride_destinations() candidate
## ranked HIGHEST by HexScorer.score_hex(candidate, combatant, world_context),
## breaking ties by minimising hex_distance to `target`, and any further
## exact tie by the stable lowest-(q, r) rule. Returns null when no legal
## destination exists.
func _choose_stride_destination(combatant, target, occupancy: Array, world_context: Dictionary):
	var destinations: Array = MovementClass.get_stride_destinations(combatant, occupancy)
	if destinations.is_empty():
		return null

	var target_hex = _hex_of(target)
	var best = null
	var best_score: float = 0.0
	var best_distance: int = -1
	for candidate in destinations:
		var score: float = HexScorerClass.score_hex(candidate, combatant, world_context)
		var distance: int = HexMathClass.hex_distance(candidate, target_hex)

		if (
			best == null
			or score > best_score
			or (score == best_score and distance < best_distance)
			or (score == best_score and distance == best_distance and _is_lower_coord(candidate, best))
		):
			best = candidate
			best_score = score
			best_distance = distance

	return best


## _is_lower_coord(a, b) -> bool — stable tie-break rule (matches
## core/combat/ai.gd's and core/combat/mindless_ai.gd's identically-behaving
## helper): true iff `a` sorts before `b` under (q, r) lexicographic order.
func _is_lower_coord(a, b) -> bool:
	if a.q != b.q:
		return a.q < b.q
	return a.r < b.r


## _hex_of(entity) -> HexCoord or null — reads positional data from either a
## Combatant instance (hex_coord field) or a Dictionary ("hex_coord" key).
func _hex_of(entity):
	if entity is Dictionary:
		return entity.get("hex_coord", null)
	return entity.hex_coord


## _hp_of(entity) -> int — reads hp_current from either a Combatant instance
## or a Dictionary.
func _hp_of(entity) -> int:
	if entity is Dictionary:
		return entity.get("hp_current", 0)
	return entity.hp_current
