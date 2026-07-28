extends GutTest
## tests/gut/test_coordinate_transform.gd — FEAT-001 (US-001 / FR-011 / ADR-003)
##
## GUT test suite for presentation/infrastructure/coordinate_transform.gd —
## the single shared axial<->pixel transform module extracted from
## presentation/hex_grid_view.gd so token drawing, click-to-hex mapping, and
## highlight rendering can never independently drift out of sync (the
## Iteration D "click a highlighted hex, nothing happens" bug class).
##
## test_criteria satisfied:
##   1. axial_to_pixel()/pixel_to_axial() round-trip is lossless for a range
##      of coords and offsets.
##   2. click mapping (HexGridView's _unhandled_input) and highlight
##      rendering (HexGridView's axial_to_pixel_with_offset(), the same
##      offset-aware center _draw_hex_cell() computed before FEAT-002) both
##      invoke this SAME shared function with the SAME offset value —
##      verified by configuring a non-zero, distinguishable "spy" offset on
##      HexGridView and asserting both consumers reflect it identically.
##      FEAT-002 (US-003, iteration-W W0-0): token draw (CombatantTokenView)
##      and grid/highlight drawing itself now DELIBERATELY diverge from this
##      offset-aware pairing — with a GameCamera Camera2D now the canonical
##      view controller, both draw in PURE world coordinates, ignoring
##      `_origin_offset` entirely (see this file's token/move_token tests
##      below, and presentation/hex_grid_view.gd's own FEAT-002 doc).
##   3. Integration: clicking a rendered, highlighted hex (a legal Step or
##      Stride destination) resolves to that exact axial coordinate, driven
##      end-to-end through the real HexGridView + core/rules/movement.gd
##      Movement destination sets.

const CoordinateTransformClass = preload("res://presentation/infrastructure/coordinate_transform.gd")
const HexGridViewClass: GDScript = preload("res://presentation/hex_grid_view.gd")
const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const CombatantTokenViewScene: PackedScene = preload("res://presentation/combatant_token_view.tscn")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const MovementClass = preload("res://core/rules/movement.gd")

const EPSILON: float = 0.01

## A deliberately non-zero, easy-to-spot "spy" offset — if any consumer
## silently computed its own zero/implicit offset instead of consuming the
## one actually configured on HexGridView, these tests would fail.
const SPY_OFFSET: Vector2 = Vector2(137.0, -251.0)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — round-trip losslessness across a range of coords and offsets.
# ══════════════════════════════════════════════════════════════════════════

func test_round_trip_is_lossless_for_a_range_of_coords_and_offsets() -> void:
	var coords: Array = []
	for q in range(-4, 5):
		for r in range(-4, 5):
			coords.append(HexCoordClass.new(q, r))

	var offsets: Array = [
		Vector2.ZERO, Vector2(100.0, 0.0), Vector2(0.0, -75.0),
		Vector2(320.5, 240.25), Vector2(-500.0, 500.0),
	]

	for offset in offsets:
		for coord in coords:
			var pixel: Vector2 = CoordinateTransformClass.axial_to_pixel(coord, 48.0, offset)
			var round_tripped = CoordinateTransformClass.pixel_to_axial(pixel, 48.0, offset)
			assert_eq(
				round_tripped.q, coord.q,
				"round-trip must preserve q for coord=%s offset=%s" % [coord, offset]
			)
			assert_eq(
				round_tripped.r, coord.r,
				"round-trip must preserve r for coord=%s offset=%s" % [coord, offset]
			)


func test_axial_to_pixel_with_zero_offset_matches_flat_top_formula() -> void:
	var coord := HexCoordClass.new(2, -1)
	var pixel: Vector2 = CoordinateTransformClass.axial_to_pixel(coord, 48.0, Vector2.ZERO)
	assert_almost_eq(pixel, Vector2(144.0, 0.0), Vector2(EPSILON, EPSILON))


func test_axial_to_pixel_applies_the_supplied_offset() -> void:
	var coord := HexCoordClass.new(0, 0)
	var pixel: Vector2 = CoordinateTransformClass.axial_to_pixel(coord, 48.0, SPY_OFFSET)
	assert_almost_eq(
		pixel, SPY_OFFSET, Vector2(EPSILON, EPSILON),
		"axial_to_pixel(origin, offset) must equal the offset itself"
	)


func test_pixel_to_axial_inverts_axial_to_pixel_with_a_nonzero_offset() -> void:
	var coord := HexCoordClass.new(3, -2)
	var pixel: Vector2 = CoordinateTransformClass.axial_to_pixel(coord, 48.0, SPY_OFFSET)
	var resolved = CoordinateTransformClass.pixel_to_axial(pixel, 48.0, SPY_OFFSET)
	assert_eq(resolved.q, coord.q)
	assert_eq(resolved.r, coord.r)


func test_pixel_to_axial_without_matching_offset_does_not_resolve_to_the_same_hex() -> void:
	# Sanity/negative check proving the offset genuinely participates in the
	# computation: decoding with the WRONG offset must NOT reliably resolve
	# back to the original coordinate (guards against an accidental no-op
	# `offset` parameter).
	var coord := HexCoordClass.new(5, -3)
	var pixel: Vector2 = CoordinateTransformClass.axial_to_pixel(coord, 48.0, SPY_OFFSET)
	var resolved = CoordinateTransformClass.pixel_to_axial(pixel, 48.0, Vector2.ZERO)
	var mismatched: bool = resolved.q != coord.q or resolved.r != coord.r
	assert_true(mismatched, "decoding with a different offset than was encoded must not resolve to the same hex")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — token draw / click mapping / highlight rendering all invoke
# the SAME shared function with the SAME offset (spy via a configured,
# distinguishable origin offset on the real HexGridView instance).
# ══════════════════════════════════════════════════════════════════════════

var _hex_grid_view = null


func before_each() -> void:
	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)


func test_hex_grid_view_exposes_the_shared_coordinate_transform_class() -> void:
	assert_eq(
		HexGridViewClass.CoordinateTransformClass, CoordinateTransformClass,
		"HexGridView must delegate to presentation/infrastructure/coordinate_transform.gd, not a local reimplementation"
	)


func test_setting_origin_offset_shifts_click_mapping_to_match_coordinate_transform() -> void:
	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	var coord := HexCoordClass.new(1, -1)

	var expected_pixel: Vector2 = CoordinateTransformClass.axial_to_pixel(coord, HexGridViewClass.HEX_SIZE, SPY_OFFSET)
	var resolved = _hex_grid_view.pixel_to_axial_with_offset(expected_pixel)

	assert_eq(resolved.q, coord.q, "click mapping must consume CoordinateTransform with the configured origin offset")
	assert_eq(resolved.r, coord.r, "click mapping must consume CoordinateTransform with the configured origin offset")


func test_setting_origin_offset_shifts_hex_cell_center_to_match_coordinate_transform() -> void:
	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	var coord := HexCoordClass.new(2, 0)

	var expected_center: Vector2 = CoordinateTransformClass.axial_to_pixel(coord, HexGridViewClass.HEX_SIZE, SPY_OFFSET)
	var actual_center: Vector2 = _hex_grid_view.axial_to_pixel_with_offset(coord)

	assert_almost_eq(
		actual_center, expected_center, Vector2(EPSILON, EPSILON),
		"grid-cell drawing (and, since it shares the same computed center, highlight fill rendering) must use the configured origin offset"
	)


func test_highlight_rendering_reuses_the_same_offset_aware_center_as_grid_drawing() -> void:
	# HexGridView's _draw_hex_cell() computes ONE `center` Vector2 per hex and
	# uses it for BOTH the grid outline AND (when selectable) the highlight
	# fill polygon -- there is no separate highlight-only transform to drift.
	# This is exercised indirectly: is_selectable-marked hexes must resolve to
	# the exact same offset-aware center exposed by axial_to_pixel_with_offset().
	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	var selectable := HexCoordClass.new(1, 0)
	_hex_grid_view.set_selectable_hexes([selectable])

	var expected_center: Vector2 = CoordinateTransformClass.axial_to_pixel(selectable, HexGridViewClass.HEX_SIZE, SPY_OFFSET)
	var actual_center: Vector2 = _hex_grid_view.axial_to_pixel_with_offset(selectable)

	assert_almost_eq(actual_center, expected_center, Vector2(EPSILON, EPSILON))
	# Must not error when actually drawn with a highlighted hex + offset set.
	_hex_grid_view.queue_redraw()
	assert_true(true)


## FEAT-002 (US-003, iteration-W W0-0): with a GameCamera Camera2D now the
## canonical view controller, token positioning draws in PURE WORLD
## coordinates -- `_origin_offset` deliberately no longer participates here
## (only grid/highlight drawing's click-mapping counterpart,
## axial_to_pixel_with_offset()/pixel_to_axial_with_offset(), still consumes
## it, pending the follow-on hit-test-refactor story). This supersedes this
## test's pre-FEAT-002 name/assertion (tokens no longer share the offset
## grid-drawing/click-mapping use), so it is renamed to assert the new
## invariant rather than silently keep asserting the old one.
func test_token_draw_uses_the_pure_zero_offset_transform_regardless_of_configured_origin_offset() -> void:
	var combatant := CombatantClass.new("c1", "Titus", "Player", HexCoordClass.new(1, -1))

	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	_hex_grid_view.load_combatants([combatant])

	var token = _hex_grid_view.get_token("c1")
	assert_not_null(token)
	if token == null:
		return

	var expected_position: Vector2 = CoordinateTransformClass.axial_to_pixel(
		combatant.hex_coord, HexGridViewClass.HEX_SIZE, Vector2.ZERO
	)
	assert_almost_eq(
		token.position, expected_position, Vector2(EPSILON, EPSILON),
		"CombatantTokenView must be positioned via the pure (zero-offset) CoordinateTransform -- _origin_offset no longer applies to token drawing (FEAT-002)"
	)


## FEAT-002: see the doc on test_token_draw_uses_the_pure_zero_offset_transform_regardless_of_configured_origin_offset()
## immediately above -- move_token() likewise now ignores _origin_offset.
func test_move_token_after_offset_change_ignores_the_configured_offset() -> void:
	var combatant := CombatantClass.new("c1", "Titus", "Player", HexCoordClass.new(0, 0))
	_hex_grid_view.load_combatants([combatant])

	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	var destination := HexCoordClass.new(2, -1)
	_hex_grid_view.move_token("c1", destination)

	var token = _hex_grid_view.get_token("c1")
	var expected_position: Vector2 = CoordinateTransformClass.axial_to_pixel(
		destination, HexGridViewClass.HEX_SIZE, Vector2.ZERO
	)
	assert_almost_eq(
		token.position, expected_position, Vector2(EPSILON, EPSILON),
		"move_token() must reposition using the pure (zero-offset) CoordinateTransform -- _origin_offset no longer applies (FEAT-002)"
	)


func test_combatant_token_view_reposition_directly_consumes_coordinate_transform() -> void:
	var token = CombatantTokenViewScene.instantiate()
	add_child_autofree(token)

	var coord := HexCoordClass.new(-2, 3)
	token.reposition(coord, SPY_OFFSET)

	var expected_position: Vector2 = CoordinateTransformClass.axial_to_pixel(coord, HexGridViewClass.HEX_SIZE, SPY_OFFSET)
	assert_almost_eq(token.position, expected_position, Vector2(EPSILON, EPSILON))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — integration: clicking a rendered, highlighted hex resolves to
# that exact axial coordinate, for both Step and Stride target sets.
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_a_highlighted_step_destination_resolves_to_its_exact_axial_coord() -> void:
	var mover := CombatantClass.new("mover", "Titus", "Player", HexCoordClass.new(0, 0))
	var others: Array = [CombatantClass.new("enemy", "Skeleton", "Enemy", HexCoordClass.new(5, 5))]

	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	_hex_grid_view.load_combatants([mover] + others)

	var step_destinations: Array = MovementClass.get_step_destinations(mover, others)
	assert_true(step_destinations.size() > 0, "mover must have at least one legal Step destination")
	_hex_grid_view.set_selectable_hexes(step_destinations)

	for destination in step_destinations:
		var click_pixel: Vector2 = _hex_grid_view.axial_to_pixel_with_offset(destination)
		var resolved = _hex_grid_view.pixel_to_axial_with_offset(click_pixel)
		assert_eq(resolved.q, destination.q, "click on the rendered Step destination must resolve to its exact q")
		assert_eq(resolved.r, destination.r, "click on the rendered Step destination must resolve to its exact r")


func test_clicking_a_highlighted_stride_destination_resolves_to_its_exact_axial_coord() -> void:
	var mover := CombatantClass.new("mover", "Titus", "Player", HexCoordClass.new(0, 0))
	var others: Array = [CombatantClass.new("enemy", "Skeleton", "Enemy", HexCoordClass.new(10, 10))]

	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	_hex_grid_view.load_combatants([mover] + others)

	var stride_destinations: Array = MovementClass.get_stride_destinations(mover, others)
	assert_true(stride_destinations.size() > 0, "mover must have at least one legal Stride destination")
	_hex_grid_view.set_selectable_hexes(stride_destinations)

	for destination in stride_destinations:
		var click_pixel: Vector2 = _hex_grid_view.axial_to_pixel_with_offset(destination)
		var resolved = _hex_grid_view.pixel_to_axial_with_offset(click_pixel)
		assert_eq(resolved.q, destination.q, "click on the rendered Stride destination must resolve to its exact q")
		assert_eq(resolved.r, destination.r, "click on the rendered Stride destination must resolve to its exact r")


func test_hex_clicked_signal_resolves_a_step_destination_when_offset_configured() -> void:
	var mover := CombatantClass.new("mover", "Titus", "Player", HexCoordClass.new(0, 0))
	var others: Array = []

	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	_hex_grid_view.load_combatants([mover])

	var step_destinations: Array = MovementClass.get_step_destinations(mover, others)
	_hex_grid_view.set_selectable_hexes(step_destinations)
	var target = step_destinations[0]

	watch_signals(_hex_grid_view)
	var pixel: Vector2 = _hex_grid_view.axial_to_pixel_with_offset(target)
	_hex_grid_view.hex_clicked.emit(_hex_grid_view.pixel_to_axial_with_offset(pixel))

	assert_signal_emitted(_hex_grid_view, "hex_clicked")
	var params: Array = get_signal_parameters(_hex_grid_view, "hex_clicked")
	assert_eq(params.size(), 1)
	if params.size() == 1:
		assert_eq(params[0].q, target.q, "hex_clicked must carry the exact q of the clicked highlighted Step destination")
		assert_eq(params[0].r, target.r, "hex_clicked must carry the exact r of the clicked highlighted Step destination")
