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
## the baseline AI decision path movement/closing-distance logic (a later
## feature) will be layered on top of. Exactly like the reach precondition
## in resolve_action_use_case.gd, this check is a no-op (always "in reach")
## when either the acting combatant or the chosen target lacks "hex_coord"
## data — preserving the pre-FEAT-003 "always Strike the first/nearest
## living target" contract for every legacy caller.

class_name AI

const HexMathClass = preload("res://core/geometry/hex_math.gd")


## decide_action(combatant: Dictionary, targets: Array) → Dictionary
##
## Selects the best action for the given combatant from the available target pool.
##
## Parameters:
##   combatant — A combatant Dictionary (name, hp_current, weapon, …). MAY
##               carry a "hex_coord" key (a core/geometry/hex_coord.gd
##               HexCoord instance) — see the reach check below. Must have
##               hp_current > 0 for a valid action to be returned.
##   targets   — Array of combatant Dictionaries on the opposing side. Each
##               MAY also carry a "hex_coord" key.
##
## Returns a Dictionary with at minimum:
##   action_type: String — the action to perform ('Strike'), or '' if no
##                          action is available this decision (no living
##                          target, or the nearest living target is not yet
##                          in reach — FEAT-003 issues no Stride itself).
##   target:      Dictionary — the chosen target combatant dict, or {} if
##                          none is available.
##   destination: HexCoord or null — FEAT-003: always null (no movement
##                          logic exists yet in this decision path).
##   will_strike: bool — FEAT-003: true iff the chosen target is already in
##                          reach (melee-adjacent, or within a ranged
##                          weapon's range_hexes) and a Strike should be
##                          issued immediately, with zero Stride.
##
## v0 behaviour (unchanged): the target pool is searched in order and the
## first living target found is chosen when no positional (hex_coord) data
## is available. Future iterations may weight by hp or conditions.
func decide_action(combatant: Dictionary, targets: Array) -> Dictionary:
	var chosen_target: Dictionary = _select_target(combatant, targets)

	# No living target — return a null-action sentinel
	if chosen_target.is_empty():
		return {"action_type": "", "target": {}, "destination": null, "will_strike": false}

	var in_reach: bool = _is_in_reach(combatant, chosen_target)
	if not in_reach:
		# FEAT-003 establishes only the "already in reach" baseline path —
		# closing distance via Stride is layered on by a later feature.
		return {"action_type": "", "target": {}, "destination": null, "will_strike": false}

	# Already in reach: Strike immediately, zero Stride issued.
	return {"action_type": "Strike", "target": chosen_target, "destination": null, "will_strike": true}


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
