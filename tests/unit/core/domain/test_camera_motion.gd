extends GutTest
## tests/unit/core/domain/test_camera_motion.gd
##
## GUT test suite for FEAT-001 (US-001): core/domain/camera_motion.gd's
## CameraMotion pure functions — lerp_step (proportional, non-overshooting
## motion toward a target) and has_arrived (epsilon-based arrival check).
## Both are exercised entirely with plain Vector2 values and zero SceneTree
## (no Node/Camera2D instantiated), matching this feature's "unit-testable
## without a SceneTree" mandate.
##
## Verifies (test_criteria):
##   1. lerp_step moves current toward target proportionally to speed*delta
##      and never overshoots target.
##   2. has_arrived returns false when distance_to(target) >= epsilon.
##   3. has_arrived returns true when distance_to(target) < epsilon.
##   4. lerp_step with delta=0 returns current unchanged (no NaN/division
##      errors).
##   5. Static/code-inspection: the file is domain-pure (no engine imports,
##      extends RefCounted only) per ADR-001.

const CameraMotionClass = preload("res://core/domain/camera_motion.gd")
const CAMERA_MOTION_PATH: String = "res://core/domain/camera_motion.gd"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: lerp_step moves current toward target proportionally to
# speed*delta, and never overshoots target.
# ══════════════════════════════════════════════════════════════════════════

func test_lerp_step_moves_proportionally_toward_target() -> void:
	var current := Vector2(0, 0)
	var target := Vector2(100, 0)
	# speed * delta = 0.25 -> should move 25% of the remaining distance.
	var result: Vector2 = CameraMotionClass.lerp_step(current, target, 0.5, 0.5)
	assert_almost_eq(result, Vector2(25, 0), Vector2(0.001, 0.001),
		"lerp_step should move 25% of the distance toward target when speed*delta=0.25")


func test_lerp_step_moves_further_with_larger_speed_delta_product() -> void:
	var current := Vector2(0, 0)
	var target := Vector2(100, 0)
	var small_step: Vector2 = CameraMotionClass.lerp_step(current, target, 0.1, 1.0)
	var large_step: Vector2 = CameraMotionClass.lerp_step(current, target, 0.5, 1.0)
	assert_true(current.distance_to(large_step) > current.distance_to(small_step),
		"a larger speed*delta product should move current further toward target")


func test_lerp_step_never_overshoots_target() -> void:
	var current := Vector2(0, 0)
	var target := Vector2(10, 0)
	# speed*delta is deliberately huge (a hitched-frame scenario) — must
	# clamp to exactly target, never past it.
	var result: Vector2 = CameraMotionClass.lerp_step(current, target, 1000.0, 1.0)
	assert_almost_eq(result, target, Vector2(0.001, 0.001),
		"lerp_step must clamp to target, never overshoot it, when speed*delta is large")


func test_lerp_step_result_never_farther_from_target_than_current() -> void:
	var current := Vector2(0, 0)
	var target := Vector2(50, -30)
	var result: Vector2 = CameraMotionClass.lerp_step(current, target, 2.5, 0.3)
	assert_true(result.distance_to(target) <= current.distance_to(target),
		"lerp_step result must never be farther from target than current was")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: lerp_step with delta=0 returns current unchanged (no
# NaN/division errors).
# ══════════════════════════════════════════════════════════════════════════

func test_lerp_step_with_zero_delta_returns_current_unchanged() -> void:
	var current := Vector2(12, 34)
	var target := Vector2(999, -999)
	var result: Vector2 = CameraMotionClass.lerp_step(current, target, 5.0, 0.0)
	assert_eq(result, current, "delta=0 must return current unchanged")
	assert_false(is_nan(result.x) or is_nan(result.y), "result must never be NaN")


func test_lerp_step_with_negative_delta_returns_current_unchanged() -> void:
	# Defensive: a negative delta should never move current or produce NaN.
	var current := Vector2(1, 2)
	var target := Vector2(50, 50)
	var result: Vector2 = CameraMotionClass.lerp_step(current, target, 5.0, -1.0)
	assert_eq(result, current, "delta<0 must be a defensive no-op returning current unchanged")
	assert_false(is_nan(result.x) or is_nan(result.y), "result must never be NaN")


func test_lerp_step_with_zero_speed_returns_current_unchanged() -> void:
	var current := Vector2(5, 5)
	var target := Vector2(500, 500)
	var result: Vector2 = CameraMotionClass.lerp_step(current, target, 0.0, 1.0)
	assert_eq(result, current, "speed=0 means no motion this step")


# ══════════════════════════════════════════════════════════════════════════
# Criteria 2 & 3: has_arrived epsilon boundary behavior.
# ══════════════════════════════════════════════════════════════════════════

func test_has_arrived_false_when_distance_greater_than_epsilon() -> void:
	var current := Vector2(0, 0)
	var target := Vector2(10, 0)
	assert_false(CameraMotionClass.has_arrived(current, target, 1.0),
		"distance(10) > epsilon(1.0) -> not arrived")


func test_has_arrived_false_when_distance_exactly_equals_epsilon() -> void:
	var current := Vector2(0, 0)
	var target := Vector2(2.0, 0)
	# distance is exactly 2.0, epsilon is exactly 2.0 -> distance >= epsilon -> false.
	assert_false(CameraMotionClass.has_arrived(current, target, 2.0),
		"distance == epsilon must NOT count as arrived (strict less-than contract)")


func test_has_arrived_true_when_distance_less_than_epsilon() -> void:
	var current := Vector2(0, 0)
	var target := Vector2(0.5, 0)
	assert_true(CameraMotionClass.has_arrived(current, target, 1.0),
		"distance(0.5) < epsilon(1.0) -> arrived")


func test_has_arrived_true_when_current_equals_target() -> void:
	var pos := Vector2(42, 42)
	assert_true(CameraMotionClass.has_arrived(pos, pos, 1.0),
		"zero distance is always arrived for any positive epsilon")


func test_has_arrived_uses_default_epsilon_of_one() -> void:
	var current := Vector2(0, 0)
	assert_true(CameraMotionClass.has_arrived(current, Vector2(0.9, 0)),
		"default epsilon should be 1.0 -> distance 0.9 counts as arrived")
	assert_false(CameraMotionClass.has_arrived(current, Vector2(1.1, 0)),
		"default epsilon should be 1.0 -> distance 1.1 does not count as arrived")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: domain purity — no engine imports, RefCounted only (ADR-001).
# ══════════════════════════════════════════════════════════════════════════

func test_source_is_domain_pure() -> void:
	var f := FileAccess.open(CAMERA_MOTION_PATH, FileAccess.READ)
	assert_not_null(f, "camera_motion.gd must be readable")
	if f == null:
		return
	var content: String = f.get_as_text()
	f.close()

	assert_true(content.contains("extends RefCounted"),
		"CameraMotion must extend RefCounted (domain purity, ADR-001)")
	assert_false(content.contains("extends Node"), "must not extend Node (ADR-001)")
	assert_false(content.contains("extends Control"), "must not extend Control (ADR-001)")
	assert_false(content.contains("extends Camera2D"), "must not extend Camera2D (ADR-001)")
