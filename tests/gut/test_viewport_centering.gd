extends GutTest
## tests/gut/test_viewport_centering.gd — FEAT-002 (US-002 / FR-012, ADR-003)
##
## GUT test suite for viewport centering via the FEAT-001 shared transform:
## presentation/infrastructure/coordinate_transform.gd's
## CoordinateTransform.compute_centering_offset(), and its wiring into the
## REAL res://MainScene.tscn composition root (presentation/main_scene, i.e.
## MainScene.gd), so the grid/token battlefield renders fully within the
## viewport at boot — via the SAME shared axial_to_pixel()/pixel_to_axial()
## transform every other consumer (token draw, click mapping, highlight
## rendering) already uses, never a second/independent offset computation
## (FEAT-001 / ADR-003).
##
## test_criteria satisfied:
##   1. Unit test: compute_centering_offset() returns an offset that places
##      computed extents within given viewport bounds, for multiple distinct
##      board sizes/shapes.
##   2. Boot-time automated test: after the REAL MainScene.tscn's _ready()
##      completes, every rendered token position falls within viewport
##      bounds.

const CoordinateTransformClass = preload("res://presentation/infrastructure/coordinate_transform.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const HEX_SIZE: float = 48.0
const VIEWPORT_SIZE: Vector2 = Vector2(1152.0, 648.0)

## A larger viewport for the larger-board scenario below -- a GRID_RADIUS=5
## ring at HEX_SIZE=48 spans roughly 816x927 raw pixels (see
## test_compute_centering_offset_centers_a_larger_ring_shaped_board()),
## which does not fit this project's default 1152x648 window; a bigger
## board legitimately needs a bigger viewport to be translation-centered
## without overflow -- compute_centering_offset() centers, it does not
## scale/zoom to fit.
const VIEWPORT_SIZE_LARGE: Vector2 = Vector2(1920.0, 1080.0)

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — compute_centering_offset() places computed extents within
# given viewport bounds, for multiple distinct board sizes/shapes.
# ══════════════════════════════════════════════════════════════════════════

## _assert_all_within_viewport(hex_coords, offset, viewport_size, hex_size,
## context) — asserts that applying `offset` (via the SAME
## CoordinateTransform.axial_to_pixel() every other consumer uses) to every
## coord in `hex_coords` yields a pixel position whose full drawn hex extent
## (padded by `hex_size` on every side, matching compute_centering_offset()'s
## own padding convention) falls entirely within
## [0, viewport_size.x] x [0, viewport_size.y].
func _assert_all_within_viewport(hex_coords: Array, offset: Vector2, viewport_size: Vector2, hex_size: float, context: String) -> void:
	for hex_coord in hex_coords:
		var pixel: Vector2 = CoordinateTransformClass.axial_to_pixel(hex_coord, hex_size, offset)
		assert_true(
			pixel.x - hex_size >= -0.01 and pixel.x + hex_size <= viewport_size.x + 0.01,
			"%s: hex %s pixel.x=%s (padded [%s, %s]) must fall within viewport width [0, %s]"
			% [context, hex_coord, pixel.x, pixel.x - hex_size, pixel.x + hex_size, viewport_size.x]
		)
		assert_true(
			pixel.y - hex_size >= -0.01 and pixel.y + hex_size <= viewport_size.y + 0.01,
			"%s: hex %s pixel.y=%s (padded [%s, %s]) must fall within viewport height [0, %s]"
			% [context, hex_coord, pixel.y, pixel.y - hex_size, pixel.y + hex_size, viewport_size.y]
		)


func test_compute_centering_offset_centers_a_single_occupied_hex() -> void:
	var hexes: Array = [HexCoordClass.new(0, 0)]
	var offset: Vector2 = CoordinateTransformClass.compute_centering_offset(hexes, VIEWPORT_SIZE, HEX_SIZE)
	_assert_all_within_viewport(hexes, offset, VIEWPORT_SIZE, HEX_SIZE, "single-hex board")

	# A lone hex at the origin must resolve to the exact viewport center.
	var pixel: Vector2 = CoordinateTransformClass.axial_to_pixel(hexes[0], HEX_SIZE, offset)
	assert_almost_eq(pixel, VIEWPORT_SIZE / 2.0, Vector2(0.01, 0.01))


func test_compute_centering_offset_centers_a_small_two_hex_board() -> void:
	# Mirrors the prologue encounter's fixture board (party at (0,0), enemy at (1,0)).
	var hexes: Array = [HexCoordClass.new(0, 0), HexCoordClass.new(1, 0)]
	var offset: Vector2 = CoordinateTransformClass.compute_centering_offset(hexes, VIEWPORT_SIZE, HEX_SIZE)
	_assert_all_within_viewport(hexes, offset, VIEWPORT_SIZE, HEX_SIZE, "two-hex prologue-shaped board")


func test_compute_centering_offset_centers_a_larger_ring_shaped_board() -> void:
	# A full GRID_RADIUS=5-ring hexagonal grid, mirroring presentation/
	# hex_grid_view.gd's rendered background grid extent.
	var hexes: Array = []
	var radius: int = 5
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			var s: int = -q - r
			if absi(s) <= radius:
				hexes.append(HexCoordClass.new(q, r))
	var offset: Vector2 = CoordinateTransformClass.compute_centering_offset(hexes, VIEWPORT_SIZE_LARGE, HEX_SIZE)
	_assert_all_within_viewport(hexes, offset, VIEWPORT_SIZE_LARGE, HEX_SIZE, "GRID_RADIUS=5 ring board")


func test_compute_centering_offset_centers_an_asymmetric_offboard_cluster() -> void:
	# A board whose occupied hexes are NOT centered around the axial origin
	# at all (e.g. a cluster far in the +q/+r quadrant) -- proving centering
	# is derived from the actual extents, not merely Vector2.ZERO.
	var hexes: Array = [
		HexCoordClass.new(8, 8), HexCoordClass.new(9, 8), HexCoordClass.new(8, 9), HexCoordClass.new(10, 9),
	]
	var offset: Vector2 = CoordinateTransformClass.compute_centering_offset(hexes, VIEWPORT_SIZE, HEX_SIZE)
	_assert_all_within_viewport(hexes, offset, VIEWPORT_SIZE, HEX_SIZE, "asymmetric off-origin cluster")
	assert_ne(offset, Vector2.ZERO, "a non-origin-centered board must not resolve to a zero (no-op) offset")


func test_compute_centering_offset_returns_viewport_center_for_an_empty_board() -> void:
	var offset: Vector2 = CoordinateTransformClass.compute_centering_offset([], VIEWPORT_SIZE, HEX_SIZE)
	assert_eq(offset, VIEWPORT_SIZE / 2.0, "an empty hex set must center on the plain viewport center")


func test_compute_centering_offset_is_consistent_with_shared_axial_to_pixel() -> void:
	# The offset this function derives must be usable through the EXACT SAME
	# axial_to_pixel()/pixel_to_axial() round trip every other consumer uses
	# -- i.e. it participates in, rather than bypasses, the FEAT-001 shared
	# transform (ADR-003).
	var hexes: Array = [HexCoordClass.new(-1, 0), HexCoordClass.new(0, 0), HexCoordClass.new(1, -1)]
	var offset: Vector2 = CoordinateTransformClass.compute_centering_offset(hexes, VIEWPORT_SIZE, HEX_SIZE)

	for hex_coord in hexes:
		var pixel: Vector2 = CoordinateTransformClass.axial_to_pixel(hex_coord, HEX_SIZE, offset)
		var resolved = CoordinateTransformClass.pixel_to_axial(pixel, HEX_SIZE, offset)
		assert_eq(resolved.q, hex_coord.q)
		assert_eq(resolved.r, hex_coord.r)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — boot-time: after the REAL MainScene.tscn's _ready() completes,
# every rendered token renders at its pure world-space pixel position.
#
# FEAT-002 (US-003, iteration-W "Camera Panning & Collapsible Panels", W0-0):
# HexGridView's token positioning (load_combatants()/move_token()) now draws
# in PURE WORLD coordinates -- MainScene.gd's boot-time centering offset
# (still configured via set_origin_offset(), see
# test_mainscene_boot_configures_a_non_zero_origin_offset_on_hex_grid_view()
# below) no longer shifts where tokens actually render; a GameCamera Camera2D
# is now the canonical view controller responsible for centering the
# viewport on the map (a follow-on story re-implements set_origin_offset()
# to position that camera instead of a per-token draw offset -- see
## presentation/hex_grid_view.gd's own FEAT-002 doc). This test's original
# "every token within viewport bounds" assertion assumed the pre-FEAT-002
# draw-offset centering approach and is superseded here by the new
# invariant: every rendered token's screen position IS its unshifted
# axial_to_pixel(hex_coord) world pixel.
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_boot_renders_every_token_at_its_pure_world_pixel_position() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return

	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return

	# FEAT-006 (US-005/FR-005, ADR-002): pin the prologue fixture's own
	# established "Titus (player) acts first" seed before add_child()
	# triggers _ready() -- otherwise an unpinned random initiative draw
	# could seat the Skeleton first, and MainScene.gd's rewire_session()
	# now wires RoundSession's enemy-strikes-player reaction window to the
	# REAL, blocking TurnController.resolve_reaction() -> PlayerReactionChooser
	# chain (no auto-timeout by design), which would suspend this boot
	# indefinitely with no player present to answer it. This test only
	# checks token render positions, not turn advancement, so pinning the
	# seed changes nothing it asserts.
	instance.seed_override = 42
	add_child_autofree(instance)
	await get_tree().process_frame

	var hex_grid_view = instance.hex_grid_view
	assert_not_null(hex_grid_view, "MainScene must expose a non-null hex_grid_view")
	if hex_grid_view == null:
		return

	var combatants: Array = instance._party + instance._enemies
	assert_true(combatants.size() > 0, "the prologue fixture must supply at least one combatant to check")

	for combatant in combatants:
		var token = hex_grid_view.get_token(combatant.combatant_id)
		assert_not_null(token, "hex_grid_view must render a token for combatant_id=%s" % combatant.combatant_id)
		if token == null:
			continue
		var expected_position: Vector2 = hex_grid_view.axial_to_pixel(combatant.hex_coord)
		assert_almost_eq(
			token.position, expected_position, Vector2(0.01, 0.01),
			"token %s must render at its pure world-space pixel position axial_to_pixel(hex_coord), unshifted by the boot-time centering offset (FEAT-002 / US-003)"
			% combatant.combatant_id
		)


func test_mainscene_boot_configures_a_non_zero_origin_offset_on_hex_grid_view() -> void:
	# The prologue fixture's board sits near the axial origin (party at
	# (0,0), enemy at (1,0)) -- with no centering applied, HexGridView's
	# default Vector2.ZERO offset would draw it in the viewport's top-left
	# corner rather than centered. A real boot must configure a non-zero
	# offset via the SAME set_origin_offset() every other HexGridView
	# consumer (drawing/click mapping/highlighting) reads from.
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return

	var instance = packed.instantiate()
	# FEAT-006 (US-005/FR-005, ADR-002): see the FEAT-006 doc on
	# test_mainscene_boot_renders_every_token_within_viewport_bounds()
	# above -- pinning this seed avoids a possible enemy-led-initiative
	# boot-time hang on the real, blocking reaction-resolver chain.
	instance.seed_override = 42
	add_child_autofree(instance)
	await get_tree().process_frame

	var hex_grid_view = instance.hex_grid_view
	assert_not_null(hex_grid_view, "MainScene must expose a non-null hex_grid_view")
	if hex_grid_view == null:
		return

	assert_ne(
		hex_grid_view.get_origin_offset(), Vector2.ZERO,
		"MainScene must configure a non-zero centering offset on hex_grid_view at boot (FEAT-002 / US-002)"
	)
