extends GutTest
## tests/unit/core/domain/test_map_bounds_calculator.gd
##
## GUT test suite for FEAT-003 (US-002): core/domain/map_bounds_calculator.gd's
## MapBoundsCalculator.compute_bounds pure function — AABB-over-points math
## expanded by a margin on every side. Exercised entirely with plain
## Vector2 arrays and zero SceneTree (no Node/HexGridView instantiated),
## matching this feature's "unit-testable without a SceneTree" mandate.
##
## Verifies (test_criteria):
##   1. compute_bounds with 3 known Vector2 points returns the expected AABB
##      expanded by margin on all sides.
##   2. compute_bounds with an empty points array returns Rect2() (equal to
##      a freshly-constructed empty rect; Godot 4.3's built-in Rect2 has no
##      is_empty() method, so equality with Rect2() plus has_area()==false
##      is this suite's operational definition of "empty").
##   3. compute_bounds with a single point returns a zero-size rect expanded
##      symmetrically by margin.
##   4. Static/code-inspection: the file is domain-pure (no engine imports,
##      extends RefCounted only) per ADR-001.

const MapBoundsCalculatorClass = preload("res://core/domain/map_bounds_calculator.gd")
const MAP_BOUNDS_CALCULATOR_PATH: String = "res://core/domain/map_bounds_calculator.gd"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: 3 known points -> expected AABB expanded by margin on all
# sides.
# ══════════════════════════════════════════════════════════════════════════

func test_compute_bounds_with_three_points_returns_expected_aabb_plus_margin() -> void:
	var points: Array = [Vector2(0, 0), Vector2(100, 50), Vector2(-20, 30)]
	var margin := 10.0
	var result: Rect2 = MapBoundsCalculatorClass.compute_bounds(points, margin)

	# Raw AABB over the 3 points: x in [-20, 100], y in [0, 50].
	# Expanded by margin=10 on every side:
	#   position = (-20 - 10, 0 - 10) = (-30, -10)
	#   size     = (120 + 20, 50 + 20) = (140, 70)
	var expected := Rect2(-30, -10, 140, 70)
	assert_eq(result.position, expected.position,
		"compute_bounds position must be the AABB min corner minus margin on each side")
	assert_eq(result.size, expected.size,
		"compute_bounds size must be the AABB span plus margin*2 on each axis")


func test_compute_bounds_with_zero_margin_matches_raw_aabb() -> void:
	var points: Array = [Vector2(5, 5), Vector2(15, -5), Vector2(-5, 20)]
	var result: Rect2 = MapBoundsCalculatorClass.compute_bounds(points, 0.0)

	assert_eq(result.position, Vector2(-5, -5), "zero margin -> position is the raw AABB min corner")
	assert_eq(result.size, Vector2(20, 25), "zero margin -> size is the raw AABB span")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: empty points array -> Rect2() (an empty rect: equal to a
# freshly-constructed Rect2() and has_area() == false; Godot 4.3's Rect2
# built-in has no is_empty() method).
# ══════════════════════════════════════════════════════════════════════════

func test_compute_bounds_with_empty_points_returns_empty_rect() -> void:
	var result: Rect2 = MapBoundsCalculatorClass.compute_bounds([], 10.0)
	assert_eq(result, Rect2(), "empty points array must return an empty Rect2() (no-bounds contract)")
	assert_false(result.has_area(), "an empty Rect2() must have no area")


func test_compute_bounds_with_empty_points_and_zero_margin_returns_empty_rect() -> void:
	var result: Rect2 = MapBoundsCalculatorClass.compute_bounds([], 0.0)
	assert_eq(result, Rect2(), "empty points array must return empty Rect2() regardless of margin")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: single point -> zero-size rect expanded symmetrically by
# margin.
# ══════════════════════════════════════════════════════════════════════════

func test_compute_bounds_with_single_point_expands_symmetrically() -> void:
	var points: Array = [Vector2(10, 20)]
	var margin := 5.0
	var result: Rect2 = MapBoundsCalculatorClass.compute_bounds(points, margin)

	# Zero-size rect at the point, grown by margin on every side ->
	# position = point - margin, size = margin*2 on both axes.
	assert_eq(result.position, Vector2(5, 15), "single point must expand from position - margin")
	assert_eq(result.size, Vector2(10, 10), "single point must produce a margin*2 x margin*2 square")
	assert_true(result.has_area(), "a positive margin around a single point must have area (not empty)")

	# The original point must be exactly centered in the resulting square.
	var center := result.position + result.size / 2.0
	assert_almost_eq(center, points[0], Vector2(0.001, 0.001),
		"the single input point must be dead-center of the expanded square")


func test_compute_bounds_with_single_point_and_zero_margin_is_zero_size() -> void:
	var points: Array = [Vector2(3, 4)]
	var result: Rect2 = MapBoundsCalculatorClass.compute_bounds(points, 0.0)
	assert_eq(result.position, Vector2(3, 4), "zero margin -> position is the point itself")
	assert_eq(result.size, Vector2.ZERO, "zero margin -> size is zero for a single point")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: domain purity — no engine imports, RefCounted only (ADR-001).
# ══════════════════════════════════════════════════════════════════════════

func test_source_is_domain_pure() -> void:
	var f := FileAccess.open(MAP_BOUNDS_CALCULATOR_PATH, FileAccess.READ)
	assert_not_null(f, "map_bounds_calculator.gd must be readable")
	if f == null:
		return
	var content: String = f.get_as_text()
	f.close()

	assert_true(content.contains("extends RefCounted"),
		"MapBoundsCalculator must extend RefCounted (domain purity, ADR-001)")
	assert_false(content.contains("extends Node"), "must not extend Node (ADR-001)")
	assert_false(content.contains("extends Control"), "must not extend Control (ADR-001)")
	assert_false(content.contains("extends Camera2D"), "must not extend Camera2D (ADR-001)")
