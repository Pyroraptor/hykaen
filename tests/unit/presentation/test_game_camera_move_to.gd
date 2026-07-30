extends GutTest
## tests/unit/presentation/test_game_camera_move_to.gd
##
## GUT test suite for FEAT-002 (US-001, ADR-001 camera/panning steel thread):
## presentation/game_camera.gd's GameCamera adapter — move_to(world_pos,
## instant), the _process()-driven lerp toward a stored _target_pos, and the
## is_moving() accessor. GameCamera is the infrastructure adapter that calls
## the already-shipped DOMAIN core/domain/camera_motion.gd pure functions
## (CameraMotion.lerp_step / CameraMotion.has_arrived, FEAT-001) from inside
## its own _process(), rather than re-deriving the lerp/arrival math itself.
##
## Frame ticks are simulated via GUT's built-in simulate(obj, times, delta)
## helper (addons/gut/gut_to_move.gd) rather than awaiting real engine
## frames, so this suite runs deterministically and fast.
##
## Verifies (test_criteria):
##   1. move_to(pos, instant=true) sets position synchronously and
##      is_moving() becomes false.
##   2. move_to(pos, instant=false) stores _target_pos, is_moving() becomes
##      true, and position advances toward target across simulated _process
##      ticks.
##   3. is_moving() becomes false once distance_to(_target_pos) < 1.0.
##   4. Exported lerp speed/stop-threshold properties default to 12.0/1.0
##      but are overridable.

const GameCameraScript = preload("res://presentation/game_camera.gd")


func _make_camera() -> Camera2D:
	var cam: Camera2D = GameCameraScript.new()
	add_child_autofree(cam)
	return cam


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: move_to(pos, instant=true) sets position synchronously and
# is_moving() becomes false.
# ══════════════════════════════════════════════════════════════════════════

func test_move_to_instant_sets_position_synchronously() -> void:
	var cam := _make_camera()
	cam.position = Vector2(0, 0)

	cam.move_to(Vector2(500, -250), true)

	assert_eq(cam.position, Vector2(500, -250),
		"instant move_to must set position synchronously")
	assert_false(cam.is_moving(),
		"is_moving() must be false immediately after an instant move_to")


func test_move_to_instant_stops_any_in_progress_lerp() -> void:
	var cam := _make_camera()
	cam.position = Vector2(0, 0)

	cam.move_to(Vector2(1000, 1000), false)
	assert_true(cam.is_moving(), "non-instant move_to should start a lerp")

	cam.move_to(Vector2(10, 10), true)
	assert_eq(cam.position, Vector2(10, 10),
		"a later instant move_to must override any in-progress lerp target")
	assert_false(cam.is_moving(),
		"an instant move_to must stop any previously in-progress lerp")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: move_to(pos, instant=false) stores _target_pos, is_moving()
# becomes true, and position advances toward target across simulated
# _process ticks.
# ══════════════════════════════════════════════════════════════════════════

func test_move_to_non_instant_starts_moving_toward_target() -> void:
	var cam := _make_camera()
	cam.position = Vector2(0, 0)

	cam.move_to(Vector2(100, 0), false)

	assert_true(cam.is_moving(),
		"move_to(pos, instant=false) must start moving (is_moving() == true)")
	assert_eq(cam._target_pos, Vector2(100, 0),
		"move_to(pos, instant=false) must store _target_pos")


func test_position_advances_toward_target_across_process_ticks() -> void:
	var cam := _make_camera()
	cam.position = Vector2(0, 0)
	cam.move_to(Vector2(100, 0), false)

	var distance_before: float = cam.position.distance_to(cam._target_pos)
	simulate(cam, 5, 0.1)
	var distance_after: float = cam.position.distance_to(cam._target_pos)

	assert_true(distance_after < distance_before,
		"position must move closer to _target_pos across simulated _process ticks")
	assert_true(cam.position.x > 0.0,
		"position.x must have advanced toward the target (100, 0)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: is_moving() becomes false once
# distance_to(_target_pos) < 1.0.
# ══════════════════════════════════════════════════════════════════════════

func test_is_moving_becomes_false_once_within_stop_threshold() -> void:
	var cam := _make_camera()
	cam.position = Vector2(0, 0)
	cam.move_to(Vector2(50, 0), false)

	assert_true(cam.is_moving(), "must be moving right after move_to")

	# Enough ticks at the default 12.0 units/s lerp weight to converge well
	# within the default 1.0 stop threshold.
	simulate(cam, 200, 0.1)

	assert_true(cam.position.distance_to(cam._target_pos) < 1.0,
		"position should have converged to within the stop threshold of target")
	assert_false(cam.is_moving(),
		"is_moving() must become false once within the stop threshold of _target_pos")


func test_is_moving_false_before_any_move_to_call() -> void:
	var cam := _make_camera()
	assert_false(cam.is_moving(),
		"a freshly constructed GameCamera must not report is_moving() before any move_to() call")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: exported lerp speed/stop-threshold properties default to
# 12.0/1.0 but are overridable.
# ══════════════════════════════════════════════════════════════════════════

func test_lerp_speed_and_stop_threshold_default_values() -> void:
	var cam := _make_camera()
	assert_eq(cam.lerp_speed, 12.0, "lerp_speed must default to 12.0 units/s")
	assert_eq(cam.stop_threshold, 1.0, "stop_threshold must default to 1.0")


func test_lerp_speed_is_overridable() -> void:
	var cam := _make_camera()
	cam.lerp_speed = 40.0

	cam.position = Vector2(0, 0)
	cam.move_to(Vector2(100, 0), false)

	# A single tick at the overridden faster speed should close much more of
	# the distance than the default speed would in the same tick.
	simulate(cam, 1, 0.1)
	assert_true(cam.position.x > 40.0,
		"overridden higher lerp_speed must move the camera faster per tick")


func test_overridden_stop_threshold_reports_arrival_at_larger_distance() -> void:
	var cam := _make_camera()
	cam.stop_threshold = 5.0
	cam.position = Vector2(0, 0)
	cam.move_to(Vector2(4, 0), false)

	# distance(4) < overridden stop_threshold(5.0) -> should already report
	# arrived without needing any _process tick, since move_to() re-evaluates
	# the moving state against the (possibly just-overridden) stop_threshold.
	simulate(cam, 1, 0.0001)
	assert_false(cam.is_moving(),
		"an overridden larger stop_threshold must cause is_moving() to be false sooner")
