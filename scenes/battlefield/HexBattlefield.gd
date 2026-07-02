## scenes/battlefield/HexBattlefield.gd — HexBattlefield (FEAT-005 / US-005)
##
## Presentation layer (Clean Architecture): renders the flat-top hex
## battlefield using the EXISTING domain hex/position data
## (core/geometry/hex_coord.gd, core/domain/combatant.gd) and instantiates
## one CombatantReadout (scenes/battlefield/CombatantReadout.gd) per
## combatant, satisfying US-005's "sees the hex battlefield with all
## combatants, and each combatant's name/HP/Stamina/action budget/Spent/
## conditions" criterion in a single composed widget.
##
## The ADR-004 flat-top axial-to-pixel translation lives here (Presentation,
## NOT Domain, per ADR-001) — mapping a domain HexCoord to a screen-space
## Vector2 is a rendering concern, not a combat rule, so
## core/geometry/hex_math.gd stays free of any pixel/Vector2 concept. This
## mirrors the precedent already established by
## presentation/hex_grid_view.gd for the earlier hex-rendering feature.
##
## HexBattlefield is READ-ONLY / read-and-render only with respect to domain
## state (ADR-001):
##   - load_combatants(combatants, view_models) reads each combatant's
##     hex_coord (positional data) and, when supplied, a matching
##     name/HP/Stamina/action-budget/Spent/conditions view model -- it never
##     mutates either.
##   - on_round_event(event) is the ONE integration point this widget offers
##     for EventSinkPort round-event broadcasts (ADR-003): it forwards the
##     event, unmodified, to every instantiated CombatantReadout, each of
##     which independently decides (by name match) whether the event applies
##     to it. HexBattlefield itself never inspects an event's roll/damage/
##     hit fields -- it does no combat computation of any kind (verified by
##     tests/gut/test_hex_battlefield.gd's source-inspection guardrail and by
##     code review).

class_name HexBattlefield
extends Node2D

const CombatantReadoutClass = preload("res://scenes/battlefield/CombatantReadout.gd")

## Pixel radius of one hex cell (center to corner), flat-top orientation.
const HEX_SIZE: float = 48.0

## Number of concentric rings of hex cells drawn around the origin for the
## background battlefield grid -- a fixed, generous bound; the prologue
## encounter's authored positions all fall well within it.
const GRID_RADIUS: int = 5

const GRID_LINE_COLOR: Color = Color(0.35, 0.35, 0.4, 1.0)

## combatant_id (String) -> {"q": int, "r": int}, populated by
## load_combatants() -- the rendered hex position for each combatant,
## exposed for test/inspection assertions (US-005 test_criteria: "rendered
## hex coordinate matches its domain HexPosition").
var _hex_by_id: Dictionary = {}

## combatant_id (String) -> CombatantReadout, populated by load_combatants().
var _readouts: Dictionary = {}


func _draw() -> void:
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s: int = -q - r
			if absi(s) <= GRID_RADIUS:
				_draw_hex_cell(q, r)


func _draw_hex_cell(q: int, r: int) -> void:
	var center: Vector2 = axial_to_pixel_qr(q, r, HEX_SIZE)
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
	return axial_to_pixel_qr(hex_coord.q, hex_coord.r, hex_size)


## axial_to_pixel_qr(q, r, hex_size) → Vector2 — the same ADR-004 formula as
## axial_to_pixel(), taking raw q/r ints directly (used internally by
## _draw_hex_cell() for grid-cell centers, which have no HexCoord instance).
static func axial_to_pixel_qr(q: int, r: int, hex_size: float = HEX_SIZE) -> Vector2:
	var x: float = hex_size * (1.5 * q)
	var y: float = hex_size * (sqrt(3.0) / 2.0 * q + sqrt(3.0) * r)
	return Vector2(x, y)


## load_combatants(combatants, view_models) → void — instantiates one
## CombatantReadout per entry in `combatants`, positioned at that
## combatant's mapped screen position (axial_to_pixel(hex_coord)). Clears
## any previously-instantiated readouts first, so a repeated call (e.g. a
## future encounter reload) never leaks duplicate children.
##
## `combatants` is an Array of duck-typed objects exposing combatant_id/
## name/hex_coord (i.e. core/domain/combatant.gd Combatant instances, as
## returned by infrastructure/resource_encounter_repository.gd).
##
## `view_models` (optional) is an Array of Dictionaries carrying the fuller
## name/HP/Stamina/action-budget/Spent/conditions snapshot for each
## combatant (the same shape presentation/status_panel_view.gd's
## load_combatants() accepts) -- matched to `combatants` by combatant_id.
## A combatant with no matching view model still gets a readout, seeded with
## just its combatant_id/name (HP/Stamina/etc. default to 0/empty) so this
## widget behaves correctly even before HP/Stamina view models exist for a
## given caller.
func load_combatants(combatants: Array, view_models: Array = []) -> void:
	for existing_readout in _readouts.values():
		existing_readout.queue_free()
	_readouts.clear()
	_hex_by_id.clear()

	var view_model_by_id: Dictionary = {}
	for view_model in view_models:
		view_model_by_id[view_model.get("combatant_id", "")] = view_model

	for combatant in combatants:
		_hex_by_id[combatant.combatant_id] = {"q": combatant.hex_coord.q, "r": combatant.hex_coord.r}

		var readout := CombatantReadoutClass.new()
		add_child(readout)
		readout.position = axial_to_pixel(combatant.hex_coord)
		readout.initialize(view_model_by_id.get(combatant.combatant_id, {
			"combatant_id": combatant.combatant_id,
			"name": combatant.name,
		}))
		_readouts[combatant.combatant_id] = readout

	queue_redraw()


## get_hex_position(combatant_id) → Dictionary — the rendered {"q", "r"} for
## the given combatant, or an empty Dictionary if combatant_id is unknown.
func get_hex_position(combatant_id: String) -> Dictionary:
	return _hex_by_id.get(combatant_id, {})


## get_readout(combatant_id) → CombatantReadout or null — test/inspection helper.
func get_readout(combatant_id: String):
	return _readouts.get(combatant_id, null)


## get_combatant_count() → int — number of currently instantiated readouts.
func get_combatant_count() -> int:
	return _readouts.size()


## on_round_event(event) → void — forwards `event`, unmodified, to every
## instantiated CombatantReadout (ADR-003). Each readout independently
## decides whether the event names it; HexBattlefield performs no
## event-field inspection or combat computation of its own.
func on_round_event(event) -> void:
	for readout in _readouts.values():
		readout.on_round_event(event)
