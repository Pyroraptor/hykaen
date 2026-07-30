extends GutTest
## tests/unit/presentation/test_hex_grid_view_bounds.gd — FEAT-004 (US-002):
## "HexGridView.get_world_bounds() adapter".
##
## Maps to the feature plan's files_to_create entry
## "res://test/unit/presentation/test_hex_grid_view_bounds.gd" — this
## project's actual, established file layout keeps every HexGridView test
## under tests/unit/presentation/ (see tests/unit/presentation/
## test_hex_grid_view_selection.gd, test_hex_grid_view_mapping.gd, etc.), so
## this suite lives here rather than at the literal res://test/... path the
## plan names, matching every prior HexGridView feature's own documented
## precedent.
##
## get_world_bounds() (design notes / API contract #4) is the Node-level
## adapter for US-002: it gathers pixel-space points for every entry in
## `_tokens` AND every currently-selectable hex (`_selectable_hexes`), each
## converted via axial_to_pixel_with_offset() (the offset-aware conversion —
## this establishes the canonical axial_to_pixel_with_offset() call path
## RISK-002 references), then delegates the AABB + margin math entirely to
## core/domain/map_bounds_calculator.gd's MapBoundsCalculator.compute_bounds()
## (already implemented/tested by FEAT-003's
## tests/unit/core/domain/test_map_bounds_calculator.gd) with
## margin = HEX_SIZE * 1.5.
##
## Verifies (test_criteria):
##   1. get_world_bounds() with 3 known tokens returns the expected bounds
##      using axial_to_pixel_with_offset() conversions — proven with a
##      non-zero configured origin offset, so a test that accidentally used
##      the offset-LESS axial_to_pixel() instead would fail (the expected
##      value would not match).
##   2. get_world_bounds() with zero tokens/selectable hexes returns an
##      empty Rect2() (MapBoundsCalculator's documented "no bounds" contract
##      for an empty points array).
##   3. get_world_bounds() includes BOTH _tokens and selectable-hex
##      positions in the AABB input set — proven by placing a token and a
##      selectable hex at two very different hexes and asserting the result
##      matches the AABB over BOTH points (a bounds computed from only one
##      of the two sets would not match).

const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexGridViewClass: GDScript = preload("res://presentation/hex_grid_view.gd")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")
const CombatantClass: GDScript = preload("res://core/domain/combatant.gd")
const MapBoundsCalculatorClass: GDScript = preload("res://core/domain/map_bounds_calculator.gd")

## Tolerance for floating-point Rect2 comparisons.
const EPSILON: float = 0.01

var _hex_grid_view = null


func before_each() -> void:
	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — 3 known tokens -> expected bounds via
# axial_to_pixel_with_offset() conversions.
# ══════════════════════════════════════════════════════════════════════════

func test_get_world_bounds_with_three_tokens_matches_axial_to_pixel_with_offset_aabb() -> void:
	# A non-zero origin offset is configured deliberately: if the production
	# implementation used the offset-LESS axial_to_pixel() instead of
	# axial_to_pixel_with_offset(), the actual result would drift from this
	# expected value (computed via the SAME offset-aware conversion), and
	# this assertion would fail.
	_hex_grid_view.set_origin_offset(Vector2(50.0, -20.0))

	var hex_a = HexCoordClass.new(0, 0)
	var hex_b = HexCoordClass.new(2, 1)
	var hex_c = HexCoordClass.new(-1, 3)

	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", hex_a),
		CombatantClass.new("defender-2", "Rufus", "Player", hex_b),
		CombatantClass.new("defender-3", "Marcus", "Enemy", hex_c),
	])

	var expected_points: Array = [
		_hex_grid_view.axial_to_pixel_with_offset(hex_a),
		_hex_grid_view.axial_to_pixel_with_offset(hex_b),
		_hex_grid_view.axial_to_pixel_with_offset(hex_c),
	]
	var expected: Rect2 = MapBoundsCalculatorClass.compute_bounds(
		expected_points, HexGridViewClass.HEX_SIZE * 1.5
	)

	var actual: Rect2 = _hex_grid_view.get_world_bounds()

	assert_almost_eq(actual.position, expected.position, Vector2(EPSILON, EPSILON),
		"get_world_bounds() position must match the AABB (+ margin) over the tokens' " +
		"axial_to_pixel_with_offset() pixel positions")
	assert_almost_eq(actual.size, expected.size, Vector2(EPSILON, EPSILON),
		"get_world_bounds() size must match the AABB (+ margin) over the tokens' " +
		"axial_to_pixel_with_offset() pixel positions")


func test_get_world_bounds_uses_hex_size_one_point_five_margin() -> void:
	var hex_a = HexCoordClass.new(0, 0)
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", hex_a),
	])

	var actual: Rect2 = _hex_grid_view.get_world_bounds()

	# A single token/point expands symmetrically by margin on every side
	# (MapBoundsCalculator's documented single-point contract) -- so the
	# resulting square's half-width/half-height directly reveals the margin
	# actually used.
	var expected_margin: float = HexGridViewClass.HEX_SIZE * 1.5
	assert_almost_eq(actual.size, Vector2(expected_margin * 2.0, expected_margin * 2.0),
		Vector2(EPSILON, EPSILON),
		"get_world_bounds() must expand a single token's point by HEX_SIZE * 1.5 on every side")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — zero tokens/selectable hexes -> empty Rect2().
# ══════════════════════════════════════════════════════════════════════════

func test_get_world_bounds_with_no_tokens_or_selectable_hexes_returns_empty_rect() -> void:
	var actual: Rect2 = _hex_grid_view.get_world_bounds()

	assert_eq(actual, Rect2(),
		"get_world_bounds() must return an empty Rect2() (MapBoundsCalculator's " +
		"documented no-bounds contract) when there are no tokens and no selectable hexes")
	assert_false(actual.has_area(),
		"an empty Rect2() must have no area")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — includes BOTH _tokens and selectable-hex positions in the
# AABB input set.
# ══════════════════════════════════════════════════════════════════════════

func test_get_world_bounds_includes_both_tokens_and_selectable_hexes() -> void:
	var token_hex = HexCoordClass.new(0, 0)
	var selectable_hex = HexCoordClass.new(6, 6)

	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", token_hex),
	])
	_hex_grid_view.set_selectable_hexes([selectable_hex])

	var expected_points: Array = [
		_hex_grid_view.axial_to_pixel_with_offset(token_hex),
		_hex_grid_view.axial_to_pixel_with_offset(selectable_hex),
	]
	var expected: Rect2 = MapBoundsCalculatorClass.compute_bounds(
		expected_points, HexGridViewClass.HEX_SIZE * 1.5
	)

	var actual: Rect2 = _hex_grid_view.get_world_bounds()

	assert_almost_eq(actual.position, expected.position, Vector2(EPSILON, EPSILON),
		"get_world_bounds() must include both the token's and the selectable hex's " +
		"positions in its AABB input set")
	assert_almost_eq(actual.size, expected.size, Vector2(EPSILON, EPSILON),
		"get_world_bounds() must include both the token's and the selectable hex's " +
		"positions in its AABB input set")


func test_get_world_bounds_with_only_selectable_hexes_and_no_tokens_is_not_empty() -> void:
	_hex_grid_view.set_selectable_hexes([HexCoordClass.new(3, -2)])

	var actual: Rect2 = _hex_grid_view.get_world_bounds()

	assert_true(actual.has_area(),
		"get_world_bounds() must include selectable-hex positions even when there " +
		"are zero tokens -- the AABB input set is not tokens-only")
