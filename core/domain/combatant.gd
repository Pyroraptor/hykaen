## core/domain/combatant.gd — Combatant domain entity (FEAT-001 / US-001)
##
## Domain layer (ADR-001): pure GDScript — no Node/Control/CanvasItem
## inheritance, no engine lifecycle callbacks, no engine I/O. Extends
## RefCounted only, matching the existing value-object convention
## established by core/rules/round_events.gd / core/application/*_port.gd.
##
## Represents one combatant's identity and battlefield position within an
## Encounter. FEAT-001 introduces this entity specifically to carry
## `hex_coord` (a core/geometry/hex_coord.gd HexCoord value object) so the
## battlefield can expose every combatant's positional data on the flat-top
## axial hex grid (v0-release-2 spec, Amendment log — movement) — satisfying
## the acceptance criterion "battlefield shows all combatants' positional
## data" as the foundational data layer for iteration B.
##
## Fields (see the iteration-B 3NF data model — Combatant entity):
##   combatant_id — String, unique identifier within its Encounter
##   name         — String, display name (e.g. "Titus", "Skeleton")
##   team         — String, "Player" or "Enemy"
##   hex_coord    — HexCoord, this combatant's current position on the
##                  flat-top axial hex grid (core/geometry/hex_coord.gd)
##
## HP/Stamina/action-budget/condition fields from the full data model are
## deliberately NOT added here — FEAT-001 establishes only the positional
## data layer; later iteration-B features extend this entity as needed.
##
## Usage:
##   var c := Combatant.new("player_0", "Titus", "Player", HexCoord.new(0, 0))
##   c.hex_coord.q   # 0

class_name Combatant
extends RefCounted

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## Unique identifier for this combatant within its Encounter.
var combatant_id: String

## Display name (e.g. "Titus", "Skeleton").
var name: String

## "Player" or "Enemy".
var team: String

## This combatant's current position — a HexCoord instance
## (core/geometry/hex_coord.gd). Defaults to HexCoord(0, 0) when not
## supplied at construction time.
##
## NOTE: typed against the preloaded HexCoordClass constant (not the bare
## global `HexCoord` class_name) — relying on the bare global class_name as
## a static type annotation requires Godot's global script class cache to
## already know about a brand-new script, which is not guaranteed outside
## the editor (headless/CI script execution can hit "Could not find type"
## parse errors). Preload-based typing has no such dependency.
var hex_coord: HexCoordClass


func _init(
	p_combatant_id: String = "",
	p_name: String = "",
	p_team: String = "",
	p_hex_coord: HexCoordClass = null
) -> void:
	combatant_id = p_combatant_id
	name = p_name
	team = p_team
	hex_coord = p_hex_coord if p_hex_coord != null else HexCoordClass.new(0, 0)


## move_to(new_hex_coord) → void — FEAT-013 (US-013): updates this
## combatant's current position to `new_hex_coord` (a
## core/geometry/hex_coord.gd HexCoord instance). The sole mutator of
## hex_coord — core/rules/movement.gd (domain layer, ADR-001) is the only
## caller, after it has validated the move (adjacency/occupancy for Step).
## This method performs NO validation itself: Combatant is a plain data
## entity, not the rule-enforcing layer (that responsibility belongs to
## core/rules/movement.gd, keeping the "where can I legally move" rule in
## exactly one place).
func move_to(new_hex_coord: HexCoordClass) -> void:
	hex_coord = new_hex_coord
