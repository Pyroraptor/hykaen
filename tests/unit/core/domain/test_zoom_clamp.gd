extends GutTest
## tests/unit/core/domain/test_zoom_clamp.gd
##
## GUT test suite for FEAT-009 (US-007, ADR-004/ADR-005 camera zoom steel
## thread): core/domain/zoom_clamp.gd's ZoomClamp.apply_delta pure function.
## Exercised entirely with plain Vector2 values and zero SceneTree (no
## Node/Camera2D instantiated), matching this feature's "unit-testable
## without a SceneTree" mandate (mirrors tests/unit/core/domain/test_camera_motion.gd's
## and tests/unit/core/domain/test_map_bounds_calculator.gd's conventions).
##
## Verifies (test_criteria):
##   1. ZoomClamp.apply_delta increases/decreases zoom correctly for a given
##      delta within range.
##   2. ZoomClamp.apply_delta clamps result to
##      [Vector2(0.5,0.5), Vector2(2.0,2.0)].
##   3. Static/code-inspection: the file is domain-pure (no engine imports,
##      extends RefCounted only) per ADR-001/ADR-004.

const ZoomClampClass = preload("res://core/domain/zoom_clamp.gd")
const ZOOM_CLAMP_PATH: String = "res://core/domain/zoom_clamp.gd"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: apply_delta increases/decreases zoom correctly for a given
# delta within range.
# ══════════════════════════════════════════════════════════════════════════

func test_apply_delta_increases_zoom_within_range() -> void:
	var current := Vector2(1.0, 1.0)
	var delta := Vector2(0.1, 0.1)
	var result: Vector2 = ZoomClampClass.apply_delta(
		current, delta, Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	assert_almost_eq(result, Vector2(1.1, 1.1), Vector2(0.0001, 0.0001),
		"apply_delta should add delta to current when the result stays within range")


func test_apply_delta_decreases_zoom_within_range() -> void:
	var current := Vector2(1.0, 1.0)
	var delta := Vector2(-0.1, -0.1)
	var result: Vector2 = ZoomClampClass.apply_delta(
		current, delta, Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	assert_almost_eq(result, Vector2(0.9, 0.9), Vector2(0.0001, 0.0001),
		"apply_delta should subtract from current when delta is negative and result stays within range")


func test_apply_delta_accumulates_across_multiple_calls() -> void:
	var current := Vector2(1.0, 1.0)
	current = ZoomClampClass.apply_delta(current, Vector2(0.1, 0.1), Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	current = ZoomClampClass.apply_delta(current, Vector2(0.1, 0.1), Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	assert_almost_eq(current, Vector2(1.2, 1.2), Vector2(0.0001, 0.0001),
		"successive apply_delta calls should compound, like repeated wheel ticks")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: apply_delta clamps result to
# [Vector2(0.5,0.5), Vector2(2.0,2.0)].
# ══════════════════════════════════════════════════════════════════════════

func test_apply_delta_clamps_to_max_bound() -> void:
	var current := Vector2(1.95, 1.95)
	var delta := Vector2(0.1, 0.1)
	var result: Vector2 = ZoomClampClass.apply_delta(
		current, delta, Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	assert_eq(result, Vector2(2.0, 2.0),
		"apply_delta must clamp the result to the max bound, never exceeding it")


func test_apply_delta_clamps_to_min_bound() -> void:
	var current := Vector2(0.55, 0.55)
	var delta := Vector2(-0.1, -0.1)
	var result: Vector2 = ZoomClampClass.apply_delta(
		current, delta, Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	assert_eq(result, Vector2(0.5, 0.5),
		"apply_delta must clamp the result to the min bound, never going below it")


func test_apply_delta_stays_clamped_at_max_when_already_at_extreme() -> void:
	var current := Vector2(2.0, 2.0)
	var result: Vector2 = ZoomClampClass.apply_delta(
		current, Vector2(0.1, 0.1), Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	assert_eq(result, Vector2(2.0, 2.0),
		"repeated positive deltas at the max extreme must never exceed the clamp bound")


func test_apply_delta_stays_clamped_at_min_when_already_at_extreme() -> void:
	var current := Vector2(0.5, 0.5)
	var result: Vector2 = ZoomClampClass.apply_delta(
		current, Vector2(-0.1, -0.1), Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	assert_eq(result, Vector2(0.5, 0.5),
		"repeated negative deltas at the min extreme must never go below the clamp bound")


func test_apply_delta_with_zero_delta_returns_current_unchanged() -> void:
	var current := Vector2(1.3, 1.3)
	var result: Vector2 = ZoomClampClass.apply_delta(
		current, Vector2.ZERO, Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	assert_almost_eq(result, current, Vector2(0.0001, 0.0001),
		"a zero delta must leave current unchanged (already within range)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: domain purity — no engine imports, RefCounted only (ADR-001).
# ══════════════════════════════════════════════════════════════════════════

func test_source_is_domain_pure() -> void:
	var f := FileAccess.open(ZOOM_CLAMP_PATH, FileAccess.READ)
	assert_not_null(f, "zoom_clamp.gd must be readable")
	if f == null:
		return
	var content: String = f.get_as_text()
	f.close()

	assert_true(content.contains("extends RefCounted"),
		"ZoomClamp must extend RefCounted (domain purity, ADR-001)")
	assert_false(content.contains("extends Node"), "must not extend Node (ADR-001)")
	assert_false(content.contains("extends Control"), "must not extend Control (ADR-001)")
	assert_false(content.contains("extends Camera2D"), "must not extend Camera2D (ADR-001)")
