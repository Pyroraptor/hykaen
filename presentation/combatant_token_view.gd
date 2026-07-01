## presentation/combatant_token_view.gd — CombatantTokenView (FEAT-007 / US-005)
##
## Presentation layer (Clean Architecture): the visual representation of a
## single combatant on the hex battlefield (presentation/hex_grid_view.gd).
## Reads a combatant's hex_coord (a core/geometry/hex_coord.gd HexCoord value
## object) and maps it to a screen position via HexGridView.axial_to_pixel()
## (ADR-004 flat-top axial-to-pixel translation, kept in Presentation per
## ADR-001 — screen projection is a rendering concern, not a combat rule).
## CombatantTokenView is READ-ONLY with respect to domain state: it never
## mutates a combatant, never reaches into Infrastructure, and never calls a
## use case directly.
##
## One CombatantTokenView is instantiated per combatant by
## HexGridView.load_combatants() when the battlefield first loads (US-005's
## "sees the hex battlefield with all combatants" criterion).
##
## Repositioning hook (ADR-003): reposition(hex_coord) updates this token's
## screen position when a combatant's hex_coord changes. This feature
## introduces only the read-only rendering/positioning path; wiring
## reposition() to a live position-changing round event (broadcast through a
## future SignalEventSinkAdapter once a movement round-event type exists) is
## left for the iteration-B movement feature that introduces that
## event/adapter — no new port or event type is invented here (ADR-002 /
## CR-001 guardrail). reposition() is public today specifically so that
## future subscriber can call it without re-deriving the ADR-004 mapping.

class_name CombatantTokenView
extends Node2D

const HexGridViewClass = preload("res://presentation/hex_grid_view.gd")

const TEAM_COLORS: Dictionary = {
	"Player": Color(0.25, 0.55, 0.95, 1.0),
	"Enemy":  Color(0.85, 0.25, 0.25, 1.0),
}
const DEFAULT_TEAM_COLOR: Color = Color(0.6, 0.6, 0.6, 1.0)
const TOKEN_RADIUS: float = 18.0

## This combatant's stable identifier (core/domain/combatant.gd Combatant.combatant_id).
var combatant_id: String = ""

## Display name shown on the token's label.
var display_name: String = ""

## "Player" or "Enemy" — selects the token's fill color.
var team: String = ""

## This token's current position — a core/geometry/hex_coord.gd HexCoord
## instance, or null before set_combatant()/reposition() is first called.
var hex_coord = null

@onready var _name_label: Label = $NameLabel


## set_combatant(combatant) → void — reads combatant_id/name/team/hex_coord
## from `combatant` (duck-typed: any object exposing those fields, i.e. a
## core/domain/combatant.gd Combatant instance) and positions this token at
## the mapped screen position (ADR-004, via reposition()).
func set_combatant(combatant) -> void:
	combatant_id = combatant.combatant_id
	display_name = combatant.name
	team = combatant.team
	reposition(combatant.hex_coord)
	if _name_label != null:
		_name_label.text = display_name
	queue_redraw()


## reposition(new_hex_coord) → void — updates hex_coord and this token's
## screen position via the shared ADR-004 axial-to-pixel formula
## (HexGridView.axial_to_pixel()).
func reposition(new_hex_coord) -> void:
	hex_coord = new_hex_coord
	position = HexGridViewClass.axial_to_pixel(hex_coord)


func _draw() -> void:
	var color: Color = TEAM_COLORS.get(team, DEFAULT_TEAM_COLOR)
	draw_circle(Vector2.ZERO, TOKEN_RADIUS, color)
