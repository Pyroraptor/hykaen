## core/rules/flanking.gd — Flanking -> Off-Guard positional condition
## (FEAT-015 / US-015 / FR-016)
##
## Domain layer (ADR-001): pure GDScript — no Node/Control/CanvasItem
## inheritance, no engine lifecycle callbacks, no engine I/O. A stateless
## namespace of `static func`s (matching the existing pure-function
## convention established by core/geometry/hex_math.gd and
## core/rules/movement.gd), operating on flat-top axial HexCoord (q, r)
## values (core/geometry/hex_coord.gd) via the existing hex adjacency
## utility (core/geometry/hex_math.gd HexMath.hex_neighbors()) — no new
## geometry is invented here.
##
## Rule (FR-016, US-015): when TWO combatants ("an attacker and an ally")
## occupy hexes that are BOTH:
##   1. directly adjacent to a target (one of the target's 6 flat-top axial
##      neighbors, HexMath.hex_neighbors()), AND
##   2. directly OPPOSITE each other around that target (the two neighbor
##      hexes sit on exactly opposite sides of the target -- e.g. neighbor
##      index 0 and neighbor index 3 of HexMath's fixed 6-direction
##      ordering, which are each other's negated direction vector)
## ...the target is Off-Guard: a BLANKET +2 bonus applies to ALL attacks
## resolved against it while so positioned (core/rules/resolution.gd
## integrates OFF_GUARD_BONUS whenever OFF_GUARD_CONDITION is present in a
## target's "conditions" list) -- NOT only to attacks made by the specific
## flanking pair. This file is a PURE POSITIONAL DETECTOR: it has no
## knowledge of teams/attackers/allies as such -- it is handed the
## candidate set of "other combatants" to check for opposite-adjacency by
## its caller (an Application/Infrastructure concern -- see MainScene.gd,
## which supplies each target's OPPOSING team as the candidate set). This
## keeps the hex-geometry rule itself team-agnostic and reusable, exactly
## like core/rules/movement.gd's occupancy check.
##
## v0 is explicitly BLANKET, NOT flankers-only: this file only ever answers
## "is this target Off-Guard right now" (a single bool) -- it never reports
## WHICH pair of combatants is flanking, and core/rules/resolution.gd never
## checks attacker identity against a flanking pair before applying the
## bonus. A flankers-only tightening (bonus applies only when the specific
## attacker was part of the flanking pair) is a documented future balance
## lever and is explicitly OUT OF SCOPE for this feature.
##
## `target`/entries of `other_combatants` are duck-typed to accept either
## shape already used across this codebase for a combatant's positional
## data (identical convention to core/rules/movement.gd):
##   - a core/domain/combatant.gd Combatant instance (hex_coord field), or
##   - a Dictionary carrying a "hex_coord" key (the shape
##     core/application/resolve_action_use_case.gd's `combatant`/`target`
##     parameters already use).
##
## Usage:
##   var off_guard: bool = Flanking.is_off_guard(target, [attacker, ally, bystander])
##   target["conditions"] = Flanking.off_guard_conditions(target, other_combatants)
##   # -> ["Off-Guard"] or [] -- append/merge into a richer conditions list
##   #    at the call site as needed.

class_name Flanking

const HexMathClass = preload("res://core/geometry/hex_math.gd")

## The condition label surfaced in a combatant's "conditions" list
## (presentation/status_panel_view.gd's readout, core/rules/resolution.gd's
## bonus check) whenever a target is flanked per this file's rule. The
## single source of truth for the string -- callers must read this constant
## rather than re-deriving/hardcoding "Off-Guard" themselves (ADR-001).
const OFF_GUARD_CONDITION: String = "Off-Guard"

## The blanket attack bonus (US-015 / FR-016: "+2 to ALL attacks against
## it") core/rules/resolution.gd applies whenever OFF_GUARD_CONDITION is
## present in a target's "conditions" list. Kept alongside the condition
## constant itself so the bonus value has exactly one source of truth.
const OFF_GUARD_BONUS: int = 2

## Number of flat-top axial neighbor directions (HexMath.hex_neighbors()
## always returns exactly 6, in a fixed order) -- and therefore the modulus
## for "opposite direction index" below.
const _NEIGHBOR_COUNT: int = 6

## Two neighbor-direction indices are directly opposite each other (their
## direction vectors are negations of one another, per
## core/geometry/hex_math.gd's fixed _DIRECTIONS ordering) exactly when they
## differ by half the neighbor count.
const _OPPOSITE_OFFSET: int = _NEIGHBOR_COUNT / 2


## is_off_guard(target, other_combatants) -> bool
##
## target            — the potential flanking victim; a Combatant instance
##                      or a Dictionary carrying "hex_coord" (see file-level
##                      doc). Combatants with no positional data (missing
##                      hex_coord) are never Off-Guard (returns false).
## other_combatants   — Array of candidate flankers (Combatant instances
##                      and/or "hex_coord"-carrying Dictionaries, may be
##                      mixed) to check for opposite-adjacency around
##                      `target`. The target itself must NOT be included
##                      (mirrors core/rules/movement.gd's `other_combatants`
##                      convention). Entries with no positional data are
##                      silently skipped (never counted as flanking).
##
## Returns true iff at least two DISTINCT neighbor positions of `target` are
## occupied by entries of `other_combatants` that sit on directly opposite
## sides of `target` (see file-level doc rule). A single flanker adjacent to
## `target` -- with no second flanker directly opposite it -- is NOT enough
## (returns false): exactly the "Non-opposite / non-adjacent positions do
## NOT flag Off-Guard" negative case.
static func is_off_guard(target, other_combatants: Array) -> bool:
	var target_hex = _hex_of(target)
	if target_hex == null:
		return false

	var neighbors: Array = HexMathClass.hex_neighbors(target_hex)
	var occupied_indices: Array = _occupied_neighbor_indices(neighbors, other_combatants)

	for i in range(_OPPOSITE_OFFSET):
		if occupied_indices.has(i) and occupied_indices.has(i + _OPPOSITE_OFFSET):
			return true
	return false


## off_guard_conditions(target, other_combatants) -> Array[String]
##
## Convenience wrapper: returns [OFF_GUARD_CONDITION] when is_off_guard()
## is true for the given target/other_combatants, else an empty Array — the
## exact shape a caller can assign directly to a combatant Dictionary's
## "conditions" key (or merge into a richer conditions list already
## carrying other condition strings such as "Dazed"/"Immobilized").
static func off_guard_conditions(target, other_combatants: Array) -> Array:
	if is_off_guard(target, other_combatants):
		return [OFF_GUARD_CONDITION]
	return []


# ── Internal helpers ─────────────────────────────────────────────────────

## _occupied_neighbor_indices(neighbors, other_combatants) -> Array[int] —
## the set of DISTINCT indices into `neighbors` (target's 6 flat-top axial
## neighbor hexes, in HexMath.hex_neighbors()'s fixed direction order) that
## are occupied by at least one entry of `other_combatants`.
static func _occupied_neighbor_indices(neighbors: Array, other_combatants: Array) -> Array:
	var occupied_indices: Array = []
	for other in other_combatants:
		var other_hex = _hex_of(other)
		if other_hex == null:
			continue
		for i in range(neighbors.size()):
			if neighbors[i].equals(other_hex):
				if not occupied_indices.has(i):
					occupied_indices.append(i)
				break
	return occupied_indices


## _hex_of(entity) -> HexCoord or null — reads positional data from either a
## Combatant instance (hex_coord field) or a Dictionary ("hex_coord" key).
## Identical duck-typing convention to core/rules/movement.gd's own
## _hex_of() helper (kept file-local rather than shared, matching this
## codebase's existing per-file convention for this tiny helper).
static func _hex_of(entity):
	if entity == null:
		return null
	if entity is Dictionary:
		return entity.get("hex_coord", null)
	return entity.hex_coord
