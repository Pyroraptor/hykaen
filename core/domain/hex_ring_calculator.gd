## core/domain/hex_ring_calculator.gd — HexRingCalculator domain service
## (FEAT-002 / US-003 / US-004, iteration Q)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/CanvasItem inheritance, no engine lifecycle callbacks, no
## engine I/O. Extends RefCounted only, matching the existing value-object/
## domain-service convention (core/geometry/hex_coord.gd,
## core/domain/opportunistic_strike_eligibility.gd).
##
## A single static, side-effect-free algorithm computing the set of hexes at
## EXACTLY a given cube-coordinate distance ("ring") from a center hex —
## per design notes' "one algorithm, two call sites, no duplication"
## requirement:
##   - US-003 (authoring-time): computes ProximityTriggerResource's
##     trigger_hexes once, from prologue_encounter.tres's enemy start hex,
##     at scenario-authoring time.
##   - US-004 (runtime): reusable by ExplorationController._evaluate_triggers
##     for membership checks (has the party member's target hex entered the
##     trigger ring?) without re-deriving the ring algorithm.
##
## Reuses the pre-existing core/geometry/hex_coord.gd HexCoord value object
## and core/geometry/hex_math.gd HexMath.hex_distance() (the SAME distance
## formula core/domain/opportunistic_strike_eligibility.gd's adjacency check
## already depends on transitively) rather than re-deriving cube-distance
## math here — this file's only new contribution is the "collect every hex
## at exactly `radius`" enumeration, not the distance formula itself.
##
## ring(center, radius) → Array[HexCoord] — every HexCoord at cube distance
## EXACTLY `radius` from `center`. `radius <= 0` returns an empty array (a
## distance-0 "ring" is degenerate — just the center hex itself — which is
## never a useful trigger boundary, so this is treated as the edge case it
## is rather than returning [center]). For `radius >= 1` the result always
## has exactly `6 * radius` elements (the standard hex-ring cardinality).
##
## Usage:
##   var trigger_hexes := HexRingCalculator.ring(HexCoord.new(0, 0), 2)
##   trigger_hexes.size()   # 12

class_name HexRingCalculator
extends RefCounted

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const HexMathClass = preload("res://core/geometry/hex_math.gd")


## ring(center, radius) → Array[HexCoord] — see class-level doc. Iterates
## the (2*radius+1)^2 bounding box of axial offsets around `center` and
## keeps only the candidates whose HexMath.hex_distance() from `center` is
## EXACTLY `radius` — filtering out both interior hexes (distance < radius)
## and the corners of the bounding box (distance > radius). `center` is
## duck-typed: any object exposing integer `q`/`r` fields and a `get_s()`
## method (i.e. a HexCoord instance).
static func ring(center, radius: int) -> Array:
	var results: Array = []
	if radius <= 0:
		return results
	for dq in range(-radius, radius + 1):
		for dr in range(-radius, radius + 1):
			var candidate = HexCoordClass.new(center.q + dq, center.r + dr)
			if HexMathClass.hex_distance(candidate, center) == radius:
				results.append(candidate)
	return results
