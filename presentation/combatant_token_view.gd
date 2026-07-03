## presentation/combatant_token_view.gd — CombatantTokenView (FEAT-007 / US-005;
## coordinate-transform extraction: FEAT-001 / US-001 / FR-011 / ADR-003)
##
## Presentation layer (Clean Architecture): the visual representation of a
## single combatant on the hex battlefield (presentation/hex_grid_view.gd).
## Reads a combatant's hex_coord (a core/geometry/hex_coord.gd HexCoord value
## object) and maps it to a screen position via
## presentation/infrastructure/coordinate_transform.gd
## CoordinateTransform.axial_to_pixel() (ADR-004 flat-top axial-to-pixel
## translation; Infrastructure per ADR-001 — screen projection is a
## rendering concern, not a combat rule). CombatantTokenView is READ-ONLY
## with respect to domain state: it never mutates a combatant, never reaches
## into any other Infrastructure adapter, and never calls a use case
## directly.
##
## FEAT-001 (US-001 / FR-011 / ADR-003): reposition()/set_combatant() accept
## an OPTIONAL `offset` parameter (defaulting to Vector2.ZERO, preserving
## this feature's pre-existing behavior) so the caller -- normally
## HexGridView, forwarding its own `_origin_offset` -- can guarantee token
## drawing uses the EXACT SAME CoordinateTransform call and offset value as
## HexGridView's own click mapping and highlight rendering, eliminating the
## Iteration D class of bug where each consumer independently recomputed the
## axial<->pixel transform and could drift out of sync.
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
const CoordinateTransformClass = preload("res://presentation/infrastructure/coordinate_transform.gd")

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


## set_combatant(combatant, offset) → void — reads
## combatant_id/name/team/hex_coord from `combatant` (duck-typed: any object
## exposing those fields, i.e. a core/domain/combatant.gd Combatant instance)
## and positions this token at the mapped screen position (ADR-004, via
## reposition()). `offset` (FEAT-001) defaults to Vector2.ZERO and is
## normally forwarded verbatim from the owning HexGridView's
## `_origin_offset` — see file-level doc.
func set_combatant(combatant, offset: Vector2 = Vector2.ZERO) -> void:
	combatant_id = combatant.combatant_id
	display_name = combatant.name
	team = combatant.team
	reposition(combatant.hex_coord, offset)
	if _name_label != null:
		_name_label.text = display_name
	queue_redraw()


## reposition(new_hex_coord, offset) → void — updates hex_coord and this
## token's screen position via the shared ADR-004 axial-to-pixel formula,
## consumed directly from presentation/infrastructure/coordinate_transform.gd
## CoordinateTransform.axial_to_pixel() (FEAT-001) rather than a
## HexGridView-owned copy of the formula. `offset` (FEAT-001) defaults to
## Vector2.ZERO -- see file-level doc.
func reposition(new_hex_coord, offset: Vector2 = Vector2.ZERO) -> void:
	hex_coord = new_hex_coord
	position = CoordinateTransformClass.axial_to_pixel(hex_coord, HexGridViewClass.HEX_SIZE, offset)


func _draw() -> void:
	var color: Color = TEAM_COLORS.get(team, DEFAULT_TEAM_COLOR)
	draw_circle(Vector2.ZERO, TOKEN_RADIUS, color)
