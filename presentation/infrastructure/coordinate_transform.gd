## presentation/infrastructure/coordinate_transform.gd — CoordinateTransform
## (FEAT-001 / US-001 / FR-011 / ADR-003)
##
## Infrastructure layer (Clean Architecture): the ONE shared, engine-light,
## pure-function module for translating between a domain
## core/geometry/hex_coord.gd HexCoord (axial q, r) and screen-space pixel
## coordinates. This is Infrastructure rather than Domain because pixel/
## screen space is a rendering concern (ADR-001 keeps core/geometry/
## hex_math.gd free of any Vector2/pixel concept) — but it holds no Node/
## Control state of its own and is independently unit-testable without a
## scene tree.
##
## Iteration-D context (the bug this module exists to prevent by
## construction): token drawing, click-to-hex mapping, and highlight
## rendering each independently recomputed the axial<->pixel formula, so
## they could (and did) drift out of sync — a click on a visibly highlighted
## hex could resolve to the WRONG axial coordinate. Every consumer of the
## axial<->pixel transform (presentation/hex_grid_view.gd's grid/highlight
## drawing and click handling, presentation/combatant_token_view.gd's token
## positioning) now calls THIS module's axial_to_pixel()/pixel_to_axial()
## exclusively — there is no other place in Presentation the flat-top
## axial<->pixel formula is implemented. Passing the SAME `offset` value to
## every call site (e.g. a future viewport-centering offset, per ADR-003) is
## what keeps drawing/clicking/highlighting mathematically guaranteed to
## agree, rather than merely conventionally agreeing.
##
## axial_to_pixel(hex_coord, hex_size, offset) → Vector2 — ADR-004 flat-top
## axial-to-pixel translation, translated by `offset`:
##   x = offset.x + hex_size * (3/2 * q)
##   y = offset.y + hex_size * (sqrt(3)/2 * q + sqrt(3) * r)
##
## pixel_to_axial(pixel, hex_size, offset) → HexCoord — the exact algebraic
## inverse of axial_to_pixel() (accounting for `offset`), rounded to the
## nearest whole hex via cube rounding so any click position inside a hex
## cell resolves to that cell's HexCoord. Lossless round-trip with
## axial_to_pixel() for every (hex_coord, hex_size, offset) combination —
## see tests/gut/test_coordinate_transform.gd.
##
## Both functions are duck-typed on `hex_coord`/the returned HexCoord: any
## object exposing integer q/r fields (i.e. a core/geometry/hex_coord.gd
## HexCoord instance), matching the convention already established by
## core/geometry/hex_math.gd.
##
## compute_centering_offset(hex_coords, viewport_size, hex_size) → Vector2
## (FEAT-002 / US-002 / FR-012, ADR-003): derives the ONE shared centering
## offset a composition root (presentation/main_scene, i.e. MainScene.gd)
## hands to HexGridView.set_origin_offset() so the grid/token battlefield
## renders fully within the viewport at boot -- computed from the SAME
## axial_to_pixel() this module already exposes (zero-offset pass) rather
## than a second, independent pixel-space formula, so the resulting offset
## is guaranteed consistent with every other axial<->pixel call site
## (drawing, click mapping, highlighting, token positioning) once applied.
## `hex_coords` is the caller-supplied set of HexCoords whose combined pixel
## extents must fit the viewport -- normally the union of the rendered
## grid's extent hexes and every occupied (combatant) hex, per this
## feature's design notes ("compute grid/occupied-hex extents"). Returns
## Vector2(viewport_size.x, viewport_size.y) / 2.0 (the plain viewport
## center) when `hex_coords` is empty, so an empty board still centers on
## something sane rather than producing a NaN/garbage offset.

class_name CoordinateTransform

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## Default pixel radius of one hex cell (center to corner), flat-top
## orientation — mirrors presentation/hex_grid_view.gd's HEX_SIZE constant so
## callers that omit `hex_size` get identical behavior to the rest of the
## presentation stack.
const DEFAULT_HEX_SIZE: float = 48.0


## axial_to_pixel(hex_coord, hex_size, offset) → Vector2 — see file-level doc.
static func axial_to_pixel(hex_coord, hex_size: float = DEFAULT_HEX_SIZE, offset: Vector2 = Vector2.ZERO) -> Vector2:
	var x: float = hex_size * (1.5 * hex_coord.q)
	var y: float = hex_size * (sqrt(3.0) / 2.0 * hex_coord.q + sqrt(3.0) * hex_coord.r)
	return Vector2(x, y) + offset


## pixel_to_axial(pixel, hex_size, offset) → HexCoord — see file-level doc.
static func pixel_to_axial(pixel: Vector2, hex_size: float = DEFAULT_HEX_SIZE, offset: Vector2 = Vector2.ZERO):
	var local: Vector2 = pixel - offset
	var q_frac: float = (2.0 / 3.0 * local.x) / hex_size
	var r_frac: float = (-1.0 / 3.0 * local.x + sqrt(3.0) / 3.0 * local.y) / hex_size
	return _round_to_hex_coord(q_frac, r_frac)


## _round_to_hex_coord(q_frac, r_frac) → HexCoord — standard cube-coordinate
## rounding: rounds q/r/s independently, then discards whichever of the three
## had the largest rounding error and re-derives it from the other two, so
## the cube invariant q + r + s == 0 always holds for the result.
static func _round_to_hex_coord(q_frac: float, r_frac: float):
	var s_frac: float = -q_frac - r_frac

	var q: int = roundi(q_frac)
	var r: int = roundi(r_frac)
	var s: int = roundi(s_frac)

	var q_diff: float = absf(q - q_frac)
	var r_diff: float = absf(r - r_frac)
	var s_diff: float = absf(s - s_frac)

	if q_diff > r_diff and q_diff > s_diff:
		q = -r - s
	elif r_diff > s_diff:
		r = -q - s

	return HexCoordClass.new(q, r)


## compute_centering_from_combatants(hex_combatants, viewport_size, grid_radius, hex_size) → Vector2
## Convenience wrapper used by the composition root at boot: builds the six
## corner hexes of the axial grid (radius = grid_radius), appends every
## non-null combatant hex_coord, then delegates to compute_centering_offset().
## Accepts grid_radius and hex_size as explicit parameters to avoid a circular
## preload dependency with presentation/hex_grid_view.gd.
static func compute_centering_from_combatants(hex_combatants: Array, viewport_size: Vector2, grid_radius: int, hex_size: float = DEFAULT_HEX_SIZE) -> Vector2:
	var r: int = grid_radius
	var extent_hexes: Array = [
		HexCoordClass.new(r, 0), HexCoordClass.new(r, -r), HexCoordClass.new(0, -r),
		HexCoordClass.new(-r, 0), HexCoordClass.new(-r, r), HexCoordClass.new(0, r),
	]
	for combatant in hex_combatants:
		if combatant.hex_coord != null:
			extent_hexes.append(combatant.hex_coord)
	return compute_centering_offset(extent_hexes, viewport_size, hex_size)


## compute_centering_offset(hex_coords, viewport_size, hex_size) → Vector2 —
## see file-level doc. Derives the offset such that the pixel-space bounding
## box of `hex_coords` (each hex padded by `hex_size` on every side, so a
## hex's full drawn extent — not just its center point — is accounted for)
## is centered within a `viewport_size`-sized rectangle. Uses the SAME
## axial_to_pixel() above (with an implicit zero offset) to compute each raw
## hex center, so this can never drift out of sync with how those hexes are
## actually drawn once the returned offset is applied.
static func compute_centering_offset(hex_coords: Array, viewport_size: Vector2, hex_size: float = DEFAULT_HEX_SIZE) -> Vector2:
	var viewport_center: Vector2 = viewport_size / 2.0
	if hex_coords.is_empty():
		return viewport_center

	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF

	for hex_coord in hex_coords:
		var raw_pixel: Vector2 = axial_to_pixel(hex_coord, hex_size, Vector2.ZERO)
		min_x = minf(min_x, raw_pixel.x - hex_size)
		max_x = maxf(max_x, raw_pixel.x + hex_size)
		min_y = minf(min_y, raw_pixel.y - hex_size)
		max_y = maxf(max_y, raw_pixel.y + hex_size)

	var content_center: Vector2 = Vector2((min_x + max_x) / 2.0, (min_y + max_y) / 2.0)
	return viewport_center - content_center
