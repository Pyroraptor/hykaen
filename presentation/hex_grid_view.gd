## presentation/hex_grid_view.gd — HexGridView (FEAT-007 / US-005 / ADR-004)
##
## Presentation layer (Clean Architecture): renders the flat-top hex
## battlefield and owns the ADR-004 axial-to-pixel translation. This
## translation is kept in Presentation, NOT Domain (ADR-001) — mapping a
## domain HexCoord to a screen-space Vector2 is a rendering concern, not a
## combat rule, so core/geometry/hex_math.gd stays free of any pixel/Vector2
## concept. HexGridView depends only on the read-only domain HexCoord value
## object (core/geometry/hex_coord.gd) and never mutates domain state.
##
## Responsibilities:
##   1. Render the flat-top hex-cell grid (_draw()), covering GRID_RADIUS
##      concentric rings around the origin.
##   2. load_combatants(combatants) instantiates one CombatantTokenView
##      (presentation/combatant_token_view.gd) per combatant supplied,
##      satisfying US-005's "sees the hex battlefield with all combatants"
##      criterion. Each `combatant` is duck-typed: any object exposing
##      combatant_id/name/team/hex_coord fields (i.e. a
##      core/domain/combatant.gd Combatant instance, as returned by
##      infrastructure/resource_encounter_repository.gd).
##
## axial_to_pixel() is a `static func` — the single source of truth for the
## ADR-004 flat-top axial-to-pixel formula, exercised directly by
## tests/unit/presentation/test_hex_grid_view_mapping.gd without needing a
## scene tree, and reused by CombatantTokenView (which preloads this script)
## so the formula is never duplicated.

class_name HexGridView
extends Node2D

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const CombatantTokenViewScene: PackedScene = preload("res://presentation/combatant_token_view.tscn")

## Pixel radius of one hex cell (center to corner), flat-top orientation.
const HEX_SIZE: float = 48.0

## Number of concentric rings of hex cells drawn around the origin for the
## background battlefield grid — a fixed, generous bound; the prologue
## encounter's authored positions all fall well within it.
const GRID_RADIUS: int = 5

const GRID_LINE_COLOR: Color = Color(0.35, 0.35, 0.4, 1.0)

## combatant_id (String) -> CombatantTokenView, populated by load_combatants().
var _tokens: Dictionary = {}


func _draw() -> void:
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s: int = -q - r
			if absi(s) <= GRID_RADIUS:
				_draw_hex_cell(HexCoordClass.new(q, r))


func _draw_hex_cell(coord) -> void:
	var center: Vector2 = axial_to_pixel(coord, HEX_SIZE)
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(7):
		points.append(center + _hex_corner_offset(HEX_SIZE, i % 6))
	draw_polyline(points, GRID_LINE_COLOR, 1.0)


## _hex_corner_offset(size, corner_index) → Vector2 — the offset of one of
## the 6 corners of a flat-top hexagon of the given size, relative to its
## center. Flat-top corners sit at 0°, 60°, 120°, ... (no angular offset,
## unlike pointy-top's -30° offset).
static func _hex_corner_offset(size: float, corner_index: int) -> Vector2:
	var angle_rad: float = deg_to_rad(60.0 * corner_index)
	return Vector2(size * cos(angle_rad), size * sin(angle_rad))


## axial_to_pixel(hex_coord, hex_size) → Vector2 — ADR-004 flat-top axial
## coordinate to screen-pixel translation:
##   x = hex_size * (3/2 * q)
##   y = hex_size * (sqrt(3)/2 * q + sqrt(3) * r)
## `hex_coord` is duck-typed: any object exposing integer q/r fields (i.e. a
## core/geometry/hex_coord.gd HexCoord instance).
static func axial_to_pixel(hex_coord, hex_size: float = HEX_SIZE) -> Vector2:
	var x: float = hex_size * (1.5 * hex_coord.q)
	var y: float = hex_size * (sqrt(3.0) / 2.0 * hex_coord.q + sqrt(3.0) * hex_coord.r)
	return Vector2(x, y)


## load_combatants(combatants) → void — instantiates one CombatantTokenView
## per entry in `combatants`, positioned at that combatant's hex_coord (via
## CombatantTokenView.set_combatant(), which applies axial_to_pixel()).
## Clears any previously-instantiated tokens first, so a repeated call (e.g.
## a future encounter reload) never leaks duplicate children.
func load_combatants(combatants: Array) -> void:
	for existing_token in _tokens.values():
		existing_token.queue_free()
	_tokens.clear()

	for combatant in combatants:
		var token = CombatantTokenViewScene.instantiate()
		add_child(token)
		token.set_combatant(combatant)
		_tokens[combatant.combatant_id] = token


## get_token(combatant_id) → CombatantTokenView or null — test/inspection helper.
func get_token(combatant_id: String):
	return _tokens.get(combatant_id, null)


## get_token_count() → int — number of currently instantiated tokens.
func get_token_count() -> int:
	return _tokens.size()
