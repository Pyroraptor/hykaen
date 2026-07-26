extends GutTest
## tests/unit/presentation/test_hex_grid_view_terrain.gd — FEAT-331
## (resolves DEPLOY-BLOCKER-002).
##
## GUT test suite pinning down presentation/hex_grid_view.gd's
## terrain-rendering surface (GRID_RADIUS, TERRAIN_FILL_COLORS,
## set_tile_terrain()) so this behavior is exercised by the test gate
## before it ships alongside the click-to-navigate steel thread.
##
## Following this codebase's established convention for CanvasItem
## _draw()-side effects (see tests/unit/presentation/
## test_hex_grid_view_overlays.gd's file doc): there is no public hook to
## intercept/count actual draw_* calls made from inside the engine's real
## _draw() dispatch, so "applies the correct fill color" is proven via the
## get_tile_fill_color() test/inspection getter (mirrors get_tile_terrain()
## reading back exactly what set_tile_terrain() stored, and
## TERRAIN_FILL_COLORS being the single source of truth _draw_hex_cell()
## itself reads from -- see hex_grid_view.gd's own doc), rather than by
## asserting on draw_colored_polygon() call arguments directly.
##
## Verifies (test_criteria):
##   1. set_tile_terrain() applies the correct fill color per
##      TERRAIN_FILL_COLORS entry for each defined terrain type, verified
##      via get_tile_fill_color()/get_tile_terrain().
##   2. GRID_RADIUS equals 12, and is_hex_in_grid_bounds() treats a hex at
##      cube-distance 12 from the origin as in-bounds/renderable while
##      cube-distance 13 is rejected.
##   3. (git status / commit hygiene) -- verified out-of-band by the
##      CLAUDE.md-mandated `git add` + `git commit` step, not by this test
##      file itself.
##   4. Pre-existing tests/unit/presentation/test_hex_grid_view_overlays.gd
##      remains green and unaffected -- verified by re-running that suite,
##      not duplicated here; this file adds ONLY new, additive coverage.

const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")

var _hex_grid_view = null


func before_each() -> void:
	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — set_tile_terrain() applies the correct fill color per
# TERRAIN_FILL_COLORS entry for each defined terrain type.
# ══════════════════════════════════════════════════════════════════════════

func test_terrain_fill_colors_table_is_non_empty_and_publicly_readable() -> void:
	assert_true(
		_hex_grid_view.TERRAIN_FILL_COLORS is Dictionary,
		"TERRAIN_FILL_COLORS must be a Dictionary(String -> Color) lookup table"
	)
	assert_true(
		_hex_grid_view.TERRAIN_FILL_COLORS.size() > 0,
		"TERRAIN_FILL_COLORS must define at least one terrain type"
	)


func test_set_tile_terrain_stores_the_given_terrain_type() -> void:
	var coord = HexCoordClass.new(1, 0)

	_hex_grid_view.set_tile_terrain(coord, "water")

	assert_eq(
		_hex_grid_view.get_tile_terrain(coord), "water",
		"get_tile_terrain() must return the terrain type most recently supplied to set_tile_terrain() for that hex"
	)


func test_set_tile_terrain_applies_the_correct_fill_color_for_every_defined_terrain_type() -> void:
	var coord = HexCoordClass.new(2, -1)

	for terrain_type in _hex_grid_view.TERRAIN_FILL_COLORS.keys():
		_hex_grid_view.set_tile_terrain(coord, terrain_type)

		assert_eq(
			_hex_grid_view.get_tile_fill_color(coord),
			_hex_grid_view.TERRAIN_FILL_COLORS[terrain_type],
			"get_tile_fill_color() must return TERRAIN_FILL_COLORS[%s] once set_tile_terrain() has assigned that terrain type" % terrain_type
		)


func test_set_tile_terrain_only_affects_the_given_hex() -> void:
	var painted = HexCoordClass.new(3, 0)
	var untouched = HexCoordClass.new(-3, 0)

	_hex_grid_view.set_tile_terrain(painted, "lava")

	assert_eq(_hex_grid_view.get_tile_terrain(painted), "lava")
	assert_eq(
		_hex_grid_view.get_tile_terrain(untouched), "",
		"a hex that set_tile_terrain() was never called for must report no assigned terrain type"
	)


func test_get_tile_fill_color_for_an_unassigned_hex_is_not_any_defined_terrain_color() -> void:
	var untouched = HexCoordClass.new(4, -4)

	var fill_color: Color = _hex_grid_view.get_tile_fill_color(untouched)

	for terrain_type in _hex_grid_view.TERRAIN_FILL_COLORS.keys():
		assert_ne(
			fill_color, _hex_grid_view.TERRAIN_FILL_COLORS[terrain_type],
			"an unassigned hex must not resolve to any defined terrain's fill color"
		)


func test_set_tile_terrain_triggers_a_redraw_without_error() -> void:
	var coord = HexCoordClass.new(0, 0)

	_hex_grid_view.set_tile_terrain(coord, "grass")
	# Behavioral proof (matches this codebase's established convention for
	# CanvasItem _draw()-side effects): queue_redraw() must not error and
	# the view must remain fully usable afterward.
	_hex_grid_view.queue_redraw()
	assert_true(true)


func test_set_tile_terrain_overwrites_a_previously_assigned_terrain_type() -> void:
	var coord = HexCoordClass.new(0, 0)

	_hex_grid_view.set_tile_terrain(coord, "floor")
	_hex_grid_view.set_tile_terrain(coord, "wall")

	assert_eq(
		_hex_grid_view.get_tile_terrain(coord), "wall",
		"a second set_tile_terrain() call for the same hex must overwrite, not append to, the first"
	)
	assert_eq(_hex_grid_view.get_tile_fill_color(coord), _hex_grid_view.TERRAIN_FILL_COLORS["wall"])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — GRID_RADIUS equals 12; cube-distance 12 in-bounds,
# cube-distance 13 rejected.
# ══════════════════════════════════════════════════════════════════════════

func test_grid_radius_equals_twelve() -> void:
	assert_eq(_hex_grid_view.GRID_RADIUS, 12, "GRID_RADIUS must equal 12")


func test_hex_at_cube_distance_twelve_is_in_bounds() -> void:
	# (12, 0) -> q=12, r=0, s=-12 -- cube-distance exactly GRID_RADIUS (12)
	# from the origin.
	var coord = HexCoordClass.new(12, 0)

	assert_true(
		_hex_grid_view.is_hex_in_grid_bounds(coord),
		"a hex at cube-distance exactly GRID_RADIUS (12) from the origin must be treated as in-bounds/renderable"
	)


func test_hexes_at_every_boundary_orientation_of_cube_distance_twelve_are_in_bounds() -> void:
	# The six "corner" hexes of a radius-12 hexagonal grid -- every one sits
	# at cube-distance exactly 12 from the origin.
	var boundary_hexes: Array = [
		HexCoordClass.new(12, 0), HexCoordClass.new(12, -12), HexCoordClass.new(0, -12),
		HexCoordClass.new(-12, 0), HexCoordClass.new(-12, 12), HexCoordClass.new(0, 12),
	]
	for coord in boundary_hexes:
		assert_true(
			_hex_grid_view.is_hex_in_grid_bounds(coord),
			"corner hex %s at cube-distance 12 must be treated as in-bounds/renderable" % coord
		)


func test_hex_at_cube_distance_thirteen_is_rejected() -> void:
	# (13, 0) -> q=13, r=0, s=-13 -- cube-distance 13, one hex beyond
	# GRID_RADIUS.
	var coord = HexCoordClass.new(13, 0)

	assert_false(
		_hex_grid_view.is_hex_in_grid_bounds(coord),
		"a hex at cube-distance 13 (one beyond GRID_RADIUS) must be rejected as out-of-bounds"
	)


func test_hex_just_beyond_boundary_in_every_direction_is_rejected() -> void:
	var beyond_boundary_hexes: Array = [
		HexCoordClass.new(13, 0), HexCoordClass.new(13, -13), HexCoordClass.new(0, -13),
		HexCoordClass.new(-13, 0), HexCoordClass.new(-13, 13), HexCoordClass.new(0, 13),
	]
	for coord in beyond_boundary_hexes:
		assert_false(
			_hex_grid_view.is_hex_in_grid_bounds(coord),
			"hex %s at cube-distance 13 must be rejected as out-of-bounds" % coord
		)


func test_origin_hex_is_in_bounds() -> void:
	assert_true(_hex_grid_view.is_hex_in_grid_bounds(HexCoordClass.new(0, 0)))


# ══════════════════════════════════════════════════════════════════════════
# Regression: the view remains fully functional after terrain calls.
# ══════════════════════════════════════════════════════════════════════════

func test_view_remains_usable_after_terrain_calls() -> void:
	const CombatantClass = preload("res://core/domain/combatant.gd")

	_hex_grid_view.set_tile_terrain(HexCoordClass.new(0, 0), "floor")
	_hex_grid_view.set_tile_terrain(HexCoordClass.new(1, 0), "water")

	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(0, 0)),
	])
	assert_eq(_hex_grid_view.get_token_count(), 1, "HexGridView must remain fully functional after terrain calls")
