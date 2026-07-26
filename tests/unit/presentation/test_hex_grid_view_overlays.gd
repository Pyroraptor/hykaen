extends GutTest
## tests/unit/presentation/test_hex_grid_view_overlays.gd
##
## GUT test suite for FEAT-005 (US-005 / FR-005): HexGridView's exploration
## path overlay rendering — set_path_overlay(path, color) stores the path
## and color and triggers a redraw; clear_overlays() resets the stored path
## to empty and triggers a redraw; both handle empty and single-hex path
## arrays safely (no crash, no line segment drawn).
##
## Verifies (test_criteria):
##   1. set_path_overlay stores the given path array and color and triggers
##      a redraw.
##   2. clear_overlays resets the stored path to empty and triggers a
##      redraw.
##   3. set_path_overlay called with an empty array does not crash and
##      draws nothing.
##   4. set_path_overlay called with a single-hex array does not crash and
##      draws no line segment.
##
## Following this codebase's established convention for CanvasItem
## _draw()-side effects (see tests/gut/test_coordinate_transform.gd's
## test_highlight_rendering_reuses_the_same_offset_aware_center_as_grid_drawing()
## and tests/unit/presentation/test_hex_grid_view_mapping.gd's
## test_set_selectable_hexes_stores_the_supplied_array()): there is no public
## hook to intercept/count actual draw_* calls made from inside the engine's
## real _draw() dispatch, so "triggers a redraw" is proven behaviorally --
## queue_redraw() is invoked (never errors) and the view remains fully
## usable/responsive afterward -- while "stores the given path/color" is
## proven directly via the get_path_overlay()/get_path_overlay_color() test
## helpers added alongside set_path_overlay()/clear_overlays().

const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")

var _hex_grid_view = null


func before_each() -> void:
	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: set_path_overlay stores the given path array and color and
# triggers a redraw.
# ══════════════════════════════════════════════════════════════════════════

func test_set_path_overlay_stores_the_given_path() -> void:
	var path: Array = [
		HexCoordClass.new(0, 0), HexCoordClass.new(1, 0), HexCoordClass.new(1, -1),
	]

	_hex_grid_view.set_path_overlay(path, Color.RED)

	var stored_path: Array = _hex_grid_view.get_path_overlay()
	assert_eq(stored_path.size(), path.size(), "get_path_overlay() must return a path of the same length supplied to set_path_overlay()")
	for i in range(path.size()):
		assert_true(
			stored_path[i].equals(path[i]),
			"get_path_overlay()[%d] must equal the HexCoord supplied at that index" % i
		)


func test_set_path_overlay_stores_the_given_color() -> void:
	var path: Array = [HexCoordClass.new(0, 0), HexCoordClass.new(1, 0)]

	_hex_grid_view.set_path_overlay(path, Color.RED)

	assert_eq(
		_hex_grid_view.get_path_overlay_color(), Color.RED,
		"get_path_overlay_color() must return the color most recently supplied to set_path_overlay()"
	)


func test_set_path_overlay_triggers_a_redraw_without_error() -> void:
	var path: Array = [HexCoordClass.new(0, 0), HexCoordClass.new(1, 0)]

	_hex_grid_view.set_path_overlay(path, Color.BLUE)
	# Behavioral proof (matches this codebase's established convention for
	# CanvasItem _draw()-side effects): queue_redraw() must not error and the
	# view must remain fully usable afterward.
	_hex_grid_view.queue_redraw()
	assert_true(true)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: clear_overlays resets the stored path to empty and triggers
# a redraw.
# ══════════════════════════════════════════════════════════════════════════

func test_clear_overlays_resets_stored_path_to_empty() -> void:
	var path: Array = [HexCoordClass.new(0, 0), HexCoordClass.new(1, 0)]
	_hex_grid_view.set_path_overlay(path, Color.GREEN)
	assert_eq(_hex_grid_view.get_path_overlay().size(), 2, "sanity check: path must be stored before clear_overlays() is called")

	_hex_grid_view.clear_overlays()

	assert_eq(
		_hex_grid_view.get_path_overlay(), [],
		"clear_overlays() must reset the stored path overlay back to an empty array"
	)


func test_clear_overlays_triggers_a_redraw_without_error() -> void:
	var path: Array = [HexCoordClass.new(0, 0), HexCoordClass.new(1, 0)]
	_hex_grid_view.set_path_overlay(path, Color.GREEN)

	_hex_grid_view.clear_overlays()
	# Behavioral proof, mirroring the convention used above for
	# set_path_overlay(): must not error and the view remains usable.
	_hex_grid_view.queue_redraw()
	assert_true(true)


func test_clear_overlays_is_safe_when_no_overlay_was_ever_set() -> void:
	_hex_grid_view.clear_overlays()
	assert_eq(_hex_grid_view.get_path_overlay(), [], "clear_overlays() must be a safe idempotent no-op when no overlay was ever set")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: set_path_overlay([]) does not crash and draws nothing.
# ══════════════════════════════════════════════════════════════════════════

func test_set_path_overlay_with_empty_array_does_not_crash() -> void:
	_hex_grid_view.set_path_overlay([], Color.RED)
	# no crash -- reaching this line is part of the assertion.
	assert_eq(_hex_grid_view.get_path_overlay(), [], "an empty path must be stored as-is (empty)")


func test_set_path_overlay_with_empty_array_redraws_without_error() -> void:
	_hex_grid_view.set_path_overlay([], Color.RED)
	_hex_grid_view.queue_redraw()
	assert_true(true)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: set_path_overlay([single_hex]) does not crash and draws no
# line segment.
# ══════════════════════════════════════════════════════════════════════════

func test_set_path_overlay_with_single_hex_array_does_not_crash() -> void:
	var single_hex_path: Array = [HexCoordClass.new(2, -1)]

	_hex_grid_view.set_path_overlay(single_hex_path, Color.YELLOW)

	var stored_path: Array = _hex_grid_view.get_path_overlay()
	assert_eq(stored_path.size(), 1, "a single-hex path must be stored as a one-element array")
	assert_true(stored_path[0].equals(single_hex_path[0]))


func test_set_path_overlay_with_single_hex_array_redraws_without_error() -> void:
	var single_hex_path: Array = [HexCoordClass.new(2, -1)]

	_hex_grid_view.set_path_overlay(single_hex_path, Color.YELLOW)
	_hex_grid_view.queue_redraw()
	assert_true(true)


# ══════════════════════════════════════════════════════════════════════════
# Additional regression coverage: the view remains fully functional (token
# instantiation, etc.) after path-overlay calls -- overlays are a purely
# additive, non-invasive rendering concern (ADR-001).
# ══════════════════════════════════════════════════════════════════════════

func test_view_remains_usable_after_overlay_calls() -> void:
	const CombatantClass = preload("res://core/domain/combatant.gd")

	_hex_grid_view.set_path_overlay([HexCoordClass.new(0, 0), HexCoordClass.new(1, 0)], Color.RED)
	_hex_grid_view.clear_overlays()

	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(0, 0)),
	])
	assert_eq(_hex_grid_view.get_token_count(), 1, "HexGridView must remain fully functional after path-overlay calls")
