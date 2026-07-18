## presentation/hex_grid_view.gd — HexGridView (FEAT-007 / US-005 / ADR-004;
## coordinate-transform extraction: FEAT-001 / US-001 / FR-011 / ADR-003)
##
## Presentation layer (Clean Architecture): renders the flat-top hex
## battlefield. The ADR-004 axial<->pixel translation formula itself lives in
## presentation/infrastructure/coordinate_transform.gd (Infrastructure) — NOT
## here and NOT in Domain (ADR-001: mapping a domain HexCoord to a
## screen-space Vector2 is a rendering concern, not a combat rule, so
## core/geometry/hex_math.gd stays free of any pixel/Vector2 concept).
## HexGridView depends only on the read-only domain HexCoord value object
## (core/geometry/hex_coord.gd) and never mutates domain state.
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
## FEAT-001 (US-001 / FR-011 / ADR-003): token drawing (delegated to
## CombatantTokenView.reposition(), which itself now consumes
## CoordinateTransform directly), click-to-hex mapping (_unhandled_input()),
## and highlight rendering (_draw_hex_cell(), which computes ONE `center` per
## hex and reuses it for both the grid outline and the highlight fill) all
## resolve through the SAME presentation/infrastructure/coordinate_transform.gd
## CoordinateTransform.axial_to_pixel()/pixel_to_axial() calls, with the SAME
## `_origin_offset` value (see set_origin_offset()/get_origin_offset()) —
## eliminating the Iteration D class of bug where each consumer independently
## recomputed the transform and could drift out of sync (a click on a
## visibly highlighted hex resolving to the wrong axial coordinate).
## axial_to_pixel()/pixel_to_axial() remain as `static func`s (with an
## implicit zero offset) purely for backward-compatible callers that predate
## the offset concept (e.g. tests/unit/presentation/test_hex_grid_view_mapping.gd);
## they too delegate to CoordinateTransform rather than reimplementing the
## formula, so there is exactly ONE place the flat-top axial<->pixel formula
## is implemented anywhere in Presentation.

class_name HexGridView
extends Node2D

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const CombatantTokenViewScene: PackedScene = preload("res://presentation/combatant_token_view.tscn")
const CoordinateTransformClass = preload("res://presentation/infrastructure/coordinate_transform.gd")

## Pixel radius of one hex cell (center to corner), flat-top orientation.
const HEX_SIZE: float = 48.0

## Number of concentric rings of hex cells drawn around the origin for the
## background battlefield grid — a fixed, generous bound; the prologue
## encounter's authored positions all fall well within it.
const GRID_RADIUS: int = 5

const GRID_LINE_COLOR: Color = Color(0.35, 0.35, 0.4, 1.0)

## FEAT-013 / US-013: fill color for hexes currently reported as selectable
## Step destinations (via set_selectable_hexes()) -- a purely visual
## affordance, never a source of movement-rule truth (core/rules/movement.gd
## remains that source; this view only reads/derives from it, ADR-001).
const SELECTABLE_HEX_FILL_COLOR: Color = Color(0.35, 0.75, 0.35, 0.35)

## combatant_id (String) -> CombatantTokenView, populated by load_combatants().
var _tokens: Dictionary = {}

## FEAT-001 (US-001 / FR-011 / ADR-003): the shared screen-space origin
## offset applied to EVERY axial<->pixel translation this view performs (grid
## drawing, highlight rendering, click mapping) and hands to each
## CombatantTokenView it positions (token drawing) — see set_origin_offset().
## Defaults to Vector2.ZERO, matching this feature's pre-existing behavior
## exactly (a future viewport-centering feature configures this via
## set_origin_offset() rather than reintroducing a second/independent offset
## computation).
var _origin_offset: Vector2 = Vector2.ZERO

## FEAT-013 / US-013: the hexes currently highlighted as legal Step
## destinations (an Array of core/geometry/hex_coord.gd HexCoord instances),
## set via set_selectable_hexes() -- normally handed in verbatim from
## presentation/movement_input_controller.gd's
## Movement.get_step_destinations()-derived selectable set.
var _selectable_hexes: Array = []

## hex_clicked(hex_coord) -- FEAT-013 / US-013: emitted whenever the player
## left-clicks anywhere on this view, carrying the HexCoord the click maps
## to (pixel_to_axial()). This view performs NO movement-rule validation of
## its own -- it is the caller's (e.g. MainScene.gd's, forwarding to a
## configured presentation/movement_input_controller.gd) responsibility to
## decide whether the clicked hex is actually a legal Step destination.
signal hex_clicked(hex_coord)

## token_move_failed(combatant_id) -- FEAT-226 / US-005 (resolves FIND-222):
## emitted by move_token() whenever `combatant_id` has no on-screen token on
## record (e.g. load_combatants() was never called, or the id is unknown/
## stale). A purely observational signal for callers/tests that watch signals
## rather than (or in addition to) checking move_token()'s own bool return
## value -- see move_token()'s own doc for the full TOKEN_NOT_FOUND contract.
signal token_move_failed(combatant_id)


func _draw() -> void:
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s: int = -q - r
			if absi(s) <= GRID_RADIUS:
				_draw_hex_cell(HexCoordClass.new(q, r))


func _draw_hex_cell(coord) -> void:
	# FEAT-001: ONE offset-aware center Vector2, reused for BOTH the grid
	# outline AND (when selectable) the highlight fill below -- highlight
	# rendering has no separate transform of its own to drift out of sync.
	var center: Vector2 = axial_to_pixel_with_offset(coord)
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(7):
		points.append(center + _hex_corner_offset(HEX_SIZE, i % 6))
	if _is_selectable_hex(coord):
		draw_colored_polygon(points, SELECTABLE_HEX_FILL_COLOR)
	draw_polyline(points, GRID_LINE_COLOR, 1.0)


func _is_selectable_hex(coord) -> bool:
	for hex_coord in _selectable_hexes:
		if hex_coord.equals(coord):
			return true
	return false


## _unhandled_input(event) -> void -- FEAT-013 / US-013: translates a
## left-click anywhere on this view into hex_clicked(hex_coord), via
## pixel_to_axial(). Purely an input-translation concern (ADR-001: no
## movement rule is evaluated here).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hex_clicked.emit(pixel_to_axial_with_offset(get_local_mouse_position()))


## _hex_corner_offset(size, corner_index) → Vector2 — the offset of one of
## the 6 corners of a flat-top hexagon of the given size, relative to its
## center. Flat-top corners sit at 0°, 60°, 120°, ... (no angular offset,
## unlike pointy-top's -30° offset).
static func _hex_corner_offset(size: float, corner_index: int) -> Vector2:
	var angle_rad: float = deg_to_rad(60.0 * corner_index)
	return Vector2(size * cos(angle_rad), size * sin(angle_rad))


## axial_to_pixel(hex_coord, hex_size) → Vector2 — ADR-004 flat-top axial
## coordinate to screen-pixel translation, delegated to
## presentation/infrastructure/coordinate_transform.gd (FEAT-001) with an
## implicit zero origin offset. Kept as a `static func` for
## backward-compatible callers that predate the offset concept (e.g.
## CombatantTokenView's default-offset path, existing tests); instance
## callers that must honor this view's configured `_origin_offset` (drawing,
## click mapping, highlight rendering) use axial_to_pixel_with_offset()
## instead. `hex_coord` is duck-typed: any object exposing integer q/r
## fields (i.e. a core/geometry/hex_coord.gd HexCoord instance).
static func axial_to_pixel(hex_coord, hex_size: float = HEX_SIZE) -> Vector2:
	return CoordinateTransformClass.axial_to_pixel(hex_coord, hex_size, Vector2.ZERO)


## pixel_to_axial(pixel, hex_size) → HexCoord — FEAT-013 / US-013: the
## inverse of axial_to_pixel(), delegated to CoordinateTransform (FEAT-001)
## with an implicit zero origin offset. See axial_to_pixel()'s doc for why
## this remains a `static func` alongside the offset-aware
## pixel_to_axial_with_offset() instance method.
static func pixel_to_axial(pixel: Vector2, hex_size: float = HEX_SIZE):
	return CoordinateTransformClass.pixel_to_axial(pixel, hex_size, Vector2.ZERO)


## set_origin_offset(offset) → void — FEAT-001 (US-001 / FR-011 / ADR-003):
## configures the shared screen-space origin offset applied to EVERY
## axial<->pixel translation this view performs from now on (grid/highlight
## drawing via axial_to_pixel_with_offset(), click mapping via
## pixel_to_axial_with_offset()) AND handed to every CombatantTokenView this
## view positions (load_combatants()/move_token()), so token drawing never
## drifts out of sync with click mapping/highlight rendering. Defaults to
## Vector2.ZERO (this feature's pre-existing behavior). Triggers a redraw so
## an already-rendered grid/highlight immediately reflects the new offset.
func set_origin_offset(offset: Vector2) -> void:
	_origin_offset = offset
	queue_redraw()


## get_origin_offset() → Vector2 — the origin offset most recently configured
## via set_origin_offset() (Vector2.ZERO if never called).
func get_origin_offset() -> Vector2:
	return _origin_offset


## axial_to_pixel_with_offset(hex_coord) → Vector2 — axial_to_pixel(), using
## THIS view's currently configured `_origin_offset` (FEAT-001). The single
## call site both _draw_hex_cell() (grid + highlight rendering) and
## CombatantTokenView (token drawing, via the offset this view passes it)
## are ultimately derived from.
func axial_to_pixel_with_offset(hex_coord) -> Vector2:
	return CoordinateTransformClass.axial_to_pixel(hex_coord, HEX_SIZE, _origin_offset)


## pixel_to_axial_with_offset(pixel) → HexCoord — pixel_to_axial(), using
## THIS view's currently configured `_origin_offset` (FEAT-001). Used by
## _unhandled_input() so a click is always decoded with the SAME offset the
## grid/highlights/tokens were drawn with.
func pixel_to_axial_with_offset(pixel: Vector2):
	return CoordinateTransformClass.pixel_to_axial(pixel, HEX_SIZE, _origin_offset)


## set_selectable_hexes(hexes) → void — FEAT-013 / US-013: highlights the
## given Array of HexCoords (normally handed in verbatim from
## presentation/movement_input_controller.gd's currently-legal Step
## destinations) on the next _draw(). A purely visual affordance — this view
## never decides which hexes ARE legal Step destinations, it only renders
## whichever set it is told about (ADR-001).
##
## FEAT-242 / US-011: this SAME entry point is also the sole highlight path
## presentation/selection_overlay.gd reuses for an AREA_SET verb's
## origin-hex candidates AND its computed affected-hex-set preview (via
## core/application/selection_resolution_use_case.gd's affected_set(),
## itself a pure consumer of core/geometry) — no separate/forked
## AREA-highlight rendering exists here or anywhere else. Whether `hexes`
## is a handful of Step destinations or a whole AREA_SET-computed blast
## radius, this view treats it identically: it only renders whichever set
## it is told about.
func set_selectable_hexes(hexes: Array) -> void:
	_selectable_hexes = hexes
	queue_redraw()


## move_token(combatant_id, new_hex_coord) → bool — FEAT-013 / US-013:
## repositions the already-instantiated CombatantTokenView for
## `combatant_id` (via its existing reposition() hook — see
## combatant_token_view.gd's file-level doc, which was built specifically
## for this purpose) to `new_hex_coord`. Still never crashes on a stale/
## unknown id — this view never raises/throws.
##
## FEAT-226 / US-005 (resolves FIND-222): previously a SILENT no-op on an
## unknown `combatant_id`, which let callers (e.g. core/application/
## resolve_dodge_step_use_case.gd) mutate Combatant.hex_coord even though the
## on-screen token never actually moved, desyncing the two with no signal at
## all. Now returns `true` when the token was found and repositioned, `false`
## (TOKEN_NOT_FOUND) when no token is on record for `combatant_id` — and
## additionally emits `token_move_failed(combatant_id)` on that same `false`
## path, so a caller wired only via signal (rather than checking the return
## value) can still observe the failure. ResolveDodgeStepUseCase.resolve()
## checks this return value (see its own FEAT-226 doc) and skips the
## Combatant.hex_coord mutation whenever it is `false`, closing the desync.
func move_token(combatant_id: String, new_hex_coord) -> bool:
	var token = _tokens.get(combatant_id, null)
	if token != null:
		token.reposition(new_hex_coord, _origin_offset)
		return true
	token_move_failed.emit(combatant_id)
	return false


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
		token.set_combatant(combatant, _origin_offset)
		_tokens[combatant.combatant_id] = token


## get_token(combatant_id) → CombatantTokenView or null — test/inspection helper.
func get_token(combatant_id: String):
	return _tokens.get(combatant_id, null)


## get_token_count() → int — number of currently instantiated tokens.
func get_token_count() -> int:
	return _tokens.size()
