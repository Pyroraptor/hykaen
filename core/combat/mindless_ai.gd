## core/combat/mindless_ai.gd — MindlessAI (FEAT-003 / US-003 / FR-010)
##
## Domain layer (Clean Architecture): the baseline-tier AIPlannerPort
## implementation. A clean-room domain SERVICE — given (combatant,
## world_context) it returns a pure Array of ActionPlanItem Dictionaries,
## with no orchestration, no persistence, no I/O, and no calls back into
## RoundSession. It depends outward only on the AIPlannerPort contract it
## implements (core/application/ai_planner_port.gd) and on the shared
## domain movement rules (core/rules/movement.gd, core/geometry/hex_math.gd)
## — never on core/combat/ai.gd, the frozen legacy AI module this class
## formalizes but deliberately does not wrap, import, or reference.
##
## Algorithm (per design notes / test_criteria):
##   1. Select the nearest LIVING target (hp_current > 0) from
##      world_context["party"] by HexMath.hex_distance() from the
##      combatant's current hex_coord, breaking ties by the SAME stable
##      lowest-(q, r) lexicographic rule the legacy core/combat/ai.gd
##      module already established (deterministic — no RNG).
##   2. No living target -> return [] (a first-class WAIT, not an error).
##   3. Target already adjacent (hex_distance == 1) -> return a single
##      {"action_type": "Strike", "target": target} plan item.
##   4. Target out of reach -> return an ordered two-item plan:
##      [{"action_type": "Stride", "destination": <hex>, "target": target},
##       {"action_type": "Strike", "target": target}]
##      where <hex> is the legal Movement.get_stride_destinations()
##      candidate that minimises hex_distance to the target (same
##      lowest-(q, r) tie-break on distance ties).
##
## Occupancy for the Stride destination search is world_context["party"] +
## world_context["enemies"] (every other combatant currently on the board),
## mirroring core/combat/ai.gd's own `targets + other_combatants` occupancy
## set.

class_name MindlessAI
extends "res://core/application/ai_planner_port.gd"

const MovementClass = preload("res://core/rules/movement.gd")
const HexMathClass  = preload("res://core/geometry/hex_math.gd")


## plan_turn(combatant, world_context) -> Array — see file-level doc for the
## full algorithm. Overrides AIPlannerPort's abstract base.
func plan_turn(combatant, world_context: Dictionary) -> Array:
	var party: Array = world_context.get("party", [])
	var target = _select_nearest_living_target(combatant, party)

	if target == null:
		return []

	if _is_adjacent(combatant, target):
		return [{"action_type": "Strike", "target": target}]

	var enemies: Array = world_context.get("enemies", [])
	var occupancy: Array = party + enemies
	var destination = _choose_stride_destination(combatant, target, occupancy)

	if destination == null:
		# No legal Stride destination exists (e.g. fully boxed in) — nothing
		# useful this planner can do this turn; degrade to WAIT rather than
		# emitting an unreachable/illegal Strike.
		return []

	return [
		{"action_type": "Stride", "destination": destination, "target": target},
		{"action_type": "Strike", "target": target},
	]


# ── Internal helpers ─────────────────────────────────────────────────────

## _select_nearest_living_target(combatant, party) -> Dictionary or null —
## nearest living (hp_current > 0) target by HexMath.hex_distance() from
## `combatant`'s hex_coord, breaking exact-distance ties by the stable
## lowest-(q, r) rule below. Returns null when no living target exists.
func _select_nearest_living_target(combatant, party: Array):
	var living: Array = []
	for candidate in party:
		if _hp_of(candidate) > 0:
			living.append(candidate)

	if living.is_empty():
		return null

	var origin = _hex_of(combatant)
	var nearest = null
	var nearest_distance: int = -1
	for candidate in living:
		var candidate_hex = _hex_of(candidate)
		if origin == null or candidate_hex == null:
			if nearest == null:
				nearest = candidate
			continue

		var distance: int = HexMathClass.hex_distance(origin, candidate_hex)
		if (
			nearest == null
			or distance < nearest_distance
			or (distance == nearest_distance and _is_lower_coord(candidate_hex, _hex_of(nearest)))
		):
			nearest = candidate
			nearest_distance = distance

	return nearest


## _choose_stride_destination(combatant, target, occupancy) -> HexCoord or
## null — the legal Movement.get_stride_destinations() candidate that
## minimises hex_distance to `target`, breaking exact ties by the SAME
## stable lowest-(q, r) rule. Returns null when no legal destination exists.
func _choose_stride_destination(combatant, target, occupancy: Array):
	var destinations: Array = MovementClass.get_stride_destinations(combatant, occupancy)
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


## _is_adjacent(combatant, target) -> bool — true iff target's hex_coord is
## one of the 6 flat-top axial neighbors of combatant's hex_coord
## (HexMath.hex_neighbors()). Both sides must carry positional data.
func _is_adjacent(combatant, target) -> bool:
	var origin = _hex_of(combatant)
	var target_hex = _hex_of(target)
	if origin == null or target_hex == null:
		return false

	for neighbor in HexMathClass.hex_neighbors(origin):
		if neighbor.equals(target_hex):
			return true
	return false


## _is_lower_coord(a, b) -> bool — stable tie-break rule (matches
## core/combat/ai.gd's identically-behaving helper): true iff `a` sorts
## before `b` under (q, r) lexicographic order.
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
