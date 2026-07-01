extends GutTest
## tests/unit/core/geometry/test_hex_math.gd
##
## GUT test suite for FEAT-002 / US-002 — hex_distance and hex_neighbors
## pure domain utilities (core/geometry/hex_math.gd), per flat-top
## axial/cube math (ADR-004).
##
## Verifies:
##   1. hex_distance(a, b) returns 0 for identical coords, 1 for adjacent
##      coords, and correct multi-hex distances across >= 5 distinct pairs.
##   2. hex_neighbors(coord) returns exactly the 6 correct neighbor HexCoords
##      for an interior origin and for a grid-edge coordinate (no diagonal
##      cost — every neighbor is exactly distance 1 from the origin coord).
##   3. Static source-inspection check (ADR-001): hex_math.gd contains no
##      Node/Control/CanvasItem inheritance and no engine lifecycle
##      callbacks (_ready/_process/_physics_process).

const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")
const HexMathClass: GDScript = preload("res://core/geometry/hex_math.gd")
const HEX_MATH_PATH: String = "res://core/geometry/hex_math.gd"


# ── Criterion 1: hex_distance ────────────────────────────────────────────────

func test_distance_zero_for_identical_coords() -> void:
	var a = HexCoordClass.new(3, -2)
	var b = HexCoordClass.new(3, -2)
	assert_eq(HexMathClass.hex_distance(a, b), 0, "Distance between identical coords must be 0")


func test_distance_one_for_adjacent_coords() -> void:
	var origin = HexCoordClass.new(0, 0)
	var adjacent = HexCoordClass.new(1, 0)
	assert_eq(HexMathClass.hex_distance(origin, adjacent), 1, "Distance between adjacent coords must be 1")


func test_distance_across_multiple_distinct_pairs() -> void:
	# Each entry: [a.q, a.r, b.q, b.r, expected_distance]
	var cases = [
		[0, 0, 3, 0, 3],
		[0, 0, 0, 3, 3],
		[0, 0, -2, 2, 2],
		[1, 1, -1, -1, 4],
		[2, -3, -2, 1, 4],
	]
	for c in cases:
		var a = HexCoordClass.new(c[0], c[1])
		var b = HexCoordClass.new(c[2], c[3])
		assert_eq(
			HexMathClass.hex_distance(a, b), c[4],
			"Distance from (%d,%d) to (%d,%d) must be %d" % [c[0], c[1], c[2], c[3], c[4]]
		)


func test_distance_is_symmetric() -> void:
	var a = HexCoordClass.new(4, -5)
	var b = HexCoordClass.new(-1, 2)
	assert_eq(
		HexMathClass.hex_distance(a, b), HexMathClass.hex_distance(b, a),
		"hex_distance must be symmetric"
	)


# ── Criterion 2: hex_neighbors ───────────────────────────────────────────────

func test_neighbors_returns_exactly_six_for_interior_origin() -> void:
	var origin = HexCoordClass.new(0, 0)
	var neighbors: Array = HexMathClass.hex_neighbors(origin)
	assert_eq(neighbors.size(), 6, "hex_neighbors must return exactly 6 neighbors")


func test_neighbors_are_correct_for_interior_origin() -> void:
	var origin = HexCoordClass.new(0, 0)
	var neighbors: Array = HexMathClass.hex_neighbors(origin)
	var expected_pairs = [
		[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]
	]
	var actual_pairs = []
	for n in neighbors:
		actual_pairs.append([n.q, n.r])
	for expected in expected_pairs:
		assert_true(
			actual_pairs.has(expected),
			"Expected neighbor (%d,%d) missing from hex_neighbors(origin)" % [expected[0], expected[1]]
		)


func test_neighbors_are_all_exactly_distance_one_no_diagonal_cost() -> void:
	var origin = HexCoordClass.new(2, -3)
	var neighbors: Array = HexMathClass.hex_neighbors(origin)
	for n in neighbors:
		assert_eq(
			HexMathClass.hex_distance(origin, n), 1,
			"Every hex_neighbor must be exactly distance 1 (no diagonal cost)"
		)


func test_neighbors_returns_exactly_six_for_grid_edge_origin() -> void:
	# A coordinate representative of a battlefield-edge position on a bounded
	# map. The domain hex math itself is unbounded (no clipping/board-size
	# concept lives in core/geometry), so the same 6-neighbor rule applies
	# uniformly regardless of position.
	var edge = HexCoordClass.new(50, -50)
	var neighbors: Array = HexMathClass.hex_neighbors(edge)
	assert_eq(neighbors.size(), 6, "hex_neighbors must return exactly 6 neighbors even at a grid edge")


func test_neighbors_are_correct_for_grid_edge_origin() -> void:
	var edge = HexCoordClass.new(50, -50)
	var neighbors: Array = HexMathClass.hex_neighbors(edge)
	var expected_pairs = [
		[51, -50], [51, -51], [50, -51], [49, -50], [49, -49], [50, -49]
	]
	var actual_pairs = []
	for n in neighbors:
		actual_pairs.append([n.q, n.r])
	for expected in expected_pairs:
		assert_true(
			actual_pairs.has(expected),
			"Expected neighbor (%d,%d) missing from hex_neighbors(edge)" % [expected[0], expected[1]]
		)


func test_neighbors_returns_hexcoord_instances() -> void:
	var origin = HexCoordClass.new(0, 0)
	var neighbors: Array = HexMathClass.hex_neighbors(origin)
	for n in neighbors:
		assert_true(n is HexCoordClass, "Each neighbor must be a HexCoord instance")


# ── Criterion 3: static check — no Node/Control/engine-lifecycle (ADR-001) ───

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable to run the ADR-001 static check" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_has_no_node_control_inheritance() -> void:
	var content: String = _read_source(HEX_MATH_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("extends Node"), "hex_math.gd must not extend Node (ADR-001)")
	assert_false(content.contains("extends Control"), "hex_math.gd must not extend Control (ADR-001)")
	assert_false(content.contains("extends CanvasItem"), "hex_math.gd must not extend CanvasItem (ADR-001)")


func test_source_has_no_engine_lifecycle_callbacks() -> void:
	var content: String = _read_source(HEX_MATH_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("func _ready("), "hex_math.gd must not define _ready() (ADR-001)")
	assert_false(content.contains("func _process("), "hex_math.gd must not define _process() (ADR-001)")
	assert_false(
		content.contains("func _physics_process("),
		"hex_math.gd must not define _physics_process() (ADR-001)"
	)
