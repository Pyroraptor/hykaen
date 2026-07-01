## core/geometry/hex_math.gd — hex_distance / hex_neighbors utilities
## (FEAT-002 / US-002 / ADR-004)
##
## Domain layer (ADR-001): pure GDScript — no Node/Control/CanvasItem
## inheritance, no engine lifecycle callbacks, no engine I/O. This is a
## stateless namespace of `static func`s (no instance state, matching the
## existing pure-value-object/pure-function convention established by
## core/geometry/hex_coord.gd and core/rules/resolution.gd) operating on
## flat-top axial HexCoord (q, r) values (core/geometry/hex_coord.gd).
##
## hex_distance(a, b) → int — the hex-grid (cube) distance between two
## HexCoords, per the standard axial/cube distance formula:
##   distance = (|a.q-b.q| + |a.r-b.r| + |a.s-b.s|) / 2
## where s is each coordinate's derived cube coordinate (s = -q - r).
##
## hex_neighbors(coord) → Array[HexCoord] — the 6 hexes directly adjacent to
## `coord` on a flat-top axial grid. There is no diagonal-cost concept in a
## hex grid (unlike a square grid) — all 6 neighbors are equally
## distance 1 from `coord`. The domain hex math is unbounded: it does not
## know about any board/map size, so the same 6 neighbors are returned
## uniformly for an interior coordinate or one representing a
## battlefield-edge position.
##
## Usage:
##   var d := HexMath.hex_distance(HexCoord.new(0, 0), HexCoord.new(2, -1))
##   var ns := HexMath.hex_neighbors(HexCoord.new(0, 0))   # 6 HexCoords

class_name HexMath

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## The 6 flat-top axial direction vectors, in a fixed clockwise order.
## Identical for flat-top and pointy-top orientations — axial-coordinate
## adjacency is orientation-independent; only the screen-space projection
## (owned by the Presentation layer, not this domain utility) differs.
const _DIRECTIONS: Array = [
	[1, 0],
	[1, -1],
	[0, -1],
	[-1, 0],
	[-1, 1],
	[0, 1],
]


## hex_distance(a, b) → int — cube-coordinate distance between two HexCoords.
## Returns 0 when a and b represent identical coordinates, 1 when they are
## adjacent, and the correct multi-hex distance otherwise. `a` and `b` are
## duck-typed: any object exposing integer `q`/`r` fields and a `get_s()`
## method (i.e. HexCoord instances).
static func hex_distance(a, b) -> int:
	var dq: int = absi(a.q - b.q)
	var dr: int = absi(a.r - b.r)
	var ds: int = absi(a.get_s() - b.get_s())
	return int((dq + dr + ds) / 2.0)


## hex_neighbors(coord) → Array[HexCoord] — the 6 HexCoords directly
## adjacent to `coord` (no diagonal cost — every returned neighbor is
## exactly hex_distance 1 from `coord`).
static func hex_neighbors(coord) -> Array:
	var neighbors: Array = []
	for dir in _DIRECTIONS:
		neighbors.append(HexCoordClass.new(coord.q + dir[0], coord.r + dir[1]))
	return neighbors
