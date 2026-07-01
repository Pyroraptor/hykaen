## core/geometry/hex_coord.gd — HexCoord value object (FEAT-001 / US-001 / ADR-004)
##
## Domain layer (ADR-001): pure GDScript — no Node/Control/CanvasItem
## inheritance, no engine lifecycle callbacks, no engine I/O. Extends
## RefCounted only, matching the existing value-object convention
## established by core/rules/round_events.gd.
##
## Flat-top axial hex coordinate (q, r), per the v0-release-2 spec Amendment
## log — movement: "Coordinate convention: flat-top hexes, axial/cube
## coordinates." The cube coordinate `s` is ALWAYS DERIVED as s = -q - r and
## is never stored — storing it alongside q/r would create an update anomaly
## (the three values could go out of sync), which the 3NF data model for
## this iteration explicitly calls out avoiding.
##
## Usage:
##   var h := HexCoord.new(2, -1)
##   h.q          # 2
##   h.r          # -1
##   h.get_s()    # -1   (-2 - -1 = -1)
##   h.q + h.r + h.get_s() == 0   # always true — cube coordinate invariant

class_name HexCoord
extends RefCounted

## Axial column coordinate.
var q: int

## Axial row coordinate.
var r: int


func _init(p_q: int = 0, p_r: int = 0) -> void:
	q = p_q
	r = p_r


## get_s() → int — the derived cube coordinate, s = -q - r. Never stored;
## always recomputed from the current q/r so it can never drift out of sync.
func get_s() -> int:
	return -q - r


## equals(other) → bool — value equality by (q, r). `other` is expected to be
## another HexCoord (duck-typed: any object exposing integer q/r fields).
## Returns false for null.
func equals(other) -> bool:
	if other == null:
		return false
	return q == other.q and r == other.r


## to_dict() → Dictionary — snapshot of q, r, and the derived s, for
## assertions/logging.
func to_dict() -> Dictionary:
	return {"q": q, "r": r, "s": get_s()}


func _to_string() -> String:
	return "HexCoord(q=%d, r=%d, s=%d)" % [q, r, get_s()]
