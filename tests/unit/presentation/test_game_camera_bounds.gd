extends GutTest
## tests/unit/presentation/test_game_camera_bounds.gd
##
## GUT test suite for FEAT-005 (US-003, ADR-001 camera/panning steel
## thread): presentation/game_camera.gd's GameCamera.set_bounds(rect)
## contract — populated Rect2 sets limit_left/right/top/bottom from the
## rect's edges, an empty Rect2() resets limits back to Godot's
## +/-10,000,000 "no bounds" sentinel defaults, and set_bounds()
## immediately clamps any out-of-range _target_pos/position into the new
## rect.
##
## Also covers this feature's RISK-001 mitigation: _target_pos is
## re-clamped on EVERY _process() tick (not only at set_bounds() call
## time), so a bounds change mid-lerp — or a move_to() called with an
## unclamped destination while bounds are already active — never produces
## a single-frame position snap/discontinuity larger than one ordinary
## CameraMotion.lerp_step, and the camera converges smoothly inside the
## (possibly just-narrowed) bounds instead of oscillating.
##
## Frame ticks are simulated via GUT's built-in simulate(obj, times, delta)
## helper (addons/gut/gut_to_move.gd), matching
## tests/unit/presentation/test_game_camera_move_to.gd's convention.
##
## Verifies (test_criteria):
##   1. set_bounds(populated Rect2) sets limit_left/right/top/bottom to the
##      rect edges.
##   2. set_bounds(Rect2()) resets limits to +/-10,000,000 defaults.
##   3. set_bounds() immediately clamps out-of-range _target_pos and
##      position into the new rect.
##   4. RISK-001 regression: move_to(far_target) then
##      set_bounds(narrow_rect) while is_moving() == true -> no
##      single-frame position discontinuity greater than one lerp step,
##      and the camera converges smoothly within the new bounds.

const GameCameraScript = preload("res://presentation/game_camera.gd")
const CameraMotion = preload("res://core/domain/camera_motion.gd")

## Camera2D.limit_left/right/top/bottom are `int`-typed engine properties
## (not float), so expected values here are ints to avoid GUT's
## float/int-comparison warnings and match the real property type exactly.
const DEFAULT_LIMIT: int = 10000000


func _make_camera() -> Camera2D:
	var cam: Camera2D = GameCameraScript.new()
	add_child_autofree(cam)
	return cam


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: set_bounds(populated Rect2) sets
# limit_left/right/top/bottom to the rect edges.
# ══════════════════════════════════════════════════════════════════════════

func test_set_bounds_populated_rect_sets_limits_from_edges() -> void:
	var cam := _make_camera()

	cam.set_bounds(Rect2(Vector2(-200, -100), Vector2(500, 300)))

	assert_eq(cam.limit_left, -200, "limit_left must equal the rect's left edge")
	assert_eq(cam.limit_right, 300, "limit_right must equal rect.position.x + rect.size.x")
	assert_eq(cam.limit_top, -100, "limit_top must equal the rect's top edge")
	assert_eq(cam.limit_bottom, 200, "limit_bottom must equal rect.position.y + rect.size.y")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: set_bounds(Rect2()) resets limits to +/-10,000,000
# defaults.
# ══════════════════════════════════════════════════════════════════════════

func test_set_bounds_empty_rect_resets_to_default_limits() -> void:
	var cam := _make_camera()
	cam.set_bounds(Rect2(Vector2(-200, -100), Vector2(500, 300)))

	cam.set_bounds(Rect2())

	assert_eq(cam.limit_left, -DEFAULT_LIMIT, "limit_left must reset to -10,000,000")
	assert_eq(cam.limit_right, DEFAULT_LIMIT, "limit_right must reset to +10,000,000")
	assert_eq(cam.limit_top, -DEFAULT_LIMIT, "limit_top must reset to -10,000,000")
	assert_eq(cam.limit_bottom, DEFAULT_LIMIT, "limit_bottom must reset to +10,000,000")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: set_bounds() immediately clamps out-of-range _target_pos
# and position into the new rect.
# ══════════════════════════════════════════════════════════════════════════

func test_set_bounds_immediately_clamps_current_position() -> void:
	var cam := _make_camera()
	cam.position = Vector2(1000, 1000)

	cam.set_bounds(Rect2(Vector2(-50, -50), Vector2(100, 100)))

	assert_eq(cam.position, Vector2(50, 50),
		"an out-of-range position must be clamped into the new rect immediately")


func test_set_bounds_immediately_clamps_target_pos() -> void:
	var cam := _make_camera()
	cam.position = Vector2(0, 0)
	cam.move_to(Vector2(1000, 1000), false)

	cam.set_bounds(Rect2(Vector2(-50, -50), Vector2(100, 100)))

	assert_eq(cam._target_pos, Vector2(50, 50),
		"an out-of-range _target_pos must be clamped into the new rect immediately")


func test_set_bounds_leaves_in_range_position_and_target_unchanged() -> void:
	var cam := _make_camera()
	cam.position = Vector2(10, -5)
	cam.move_to(Vector2(20, 5), false)

	cam.set_bounds(Rect2(Vector2(-50, -50), Vector2(100, 100)))

	assert_eq(cam.position, Vector2(10, -5),
		"a position already within the new rect must not be moved")
	assert_eq(cam._target_pos, Vector2(20, 5),
		"a _target_pos already within the new rect must not be moved")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: RISK-001 regression — move_to(far_target) then
# set_bounds(narrow_rect) while is_moving() == true: no single-frame
# position discontinuity greater than one lerp step, and the camera
# converges smoothly within the new bounds.
# ══════════════════════════════════════════════════════════════════════════

func test_set_bounds_mid_lerp_does_not_snap_position() -> void:
	var cam := _make_camera()
	cam.position = Vector2(0, 0)

	cam.move_to(Vector2(100000, 100000), false)
	assert_true(cam.is_moving(), "camera must be moving before set_bounds() is called")

	var position_before_bounds: Vector2 = cam.position

	cam.set_bounds(Rect2(Vector2(-50, -50), Vector2(100, 100)))

	# position (0,0) was already inside the new rect, so set_bounds() must
	# not itself relocate it -- only the far-away _target_pos should have
	# been clamped (criterion 3). This is the guard against a naive
	# implementation that snaps `position` to some other value on every
	# set_bounds() call even when it was already in-range.
	assert_eq(cam.position, position_before_bounds,
		"set_bounds() must not move a position that is already within the new rect")
	assert_eq(cam._target_pos, Vector2(50, 50),
		"_target_pos must have been clamped to the new rect's corner")

	# One simulated _process tick must move `position` by exactly what
	# CameraMotion.lerp_step would produce toward the *clamped* target --
	# i.e. a single ordinary lerp step, not a hard snap straight to the
	# rect edge.
	var delta := 0.05
	var expected_next_position: Vector2 = CameraMotion.lerp_step(
		cam.position, Vector2(50, 50), cam.lerp_speed, delta
	)
	simulate(cam, 1, delta)

	assert_almost_eq(cam.position.x, expected_next_position.x, 0.001,
		"a single tick after set_bounds() must move position by exactly one ordinary lerp step")
	assert_almost_eq(cam.position.y, expected_next_position.y, 0.001,
		"a single tick after set_bounds() must move position by exactly one ordinary lerp step")

	# Continue simulating: the camera must converge smoothly and end up
	# strictly within the new bounds (never overshoot past the clamped
	# corner).
	simulate(cam, 200, 0.1)

	assert_false(cam.is_moving(),
		"camera must eventually stop moving once converged on the clamped target")
	assert_true(cam.position.x <= 50.0 + 0.001, "position.x must never exceed the new limit_right")
	assert_true(cam.position.y <= 50.0 + 0.001, "position.y must never exceed the new limit_bottom")


func test_process_reclamps_target_pos_every_tick_not_only_at_set_bounds_time() -> void:
	# RISK-001: bounds must be enforced continuously, not only at the
	# moment set_bounds() is called. Here bounds are set FIRST, and only
	# afterwards is move_to() called with an out-of-range destination --
	# proving _process() itself re-clamps _target_pos each frame rather
	# than relying solely on set_bounds()'s one-time clamp.
	var cam := _make_camera()
	cam.position = Vector2(0, 0)
	cam.set_bounds(Rect2(Vector2(-50, -50), Vector2(100, 100)))

	cam.move_to(Vector2(100000, 100000), false)
	assert_true(cam.is_moving(), "camera must be moving after move_to() with a far target")

	simulate(cam, 300, 0.1)

	assert_false(cam.is_moving(), "camera must converge and stop, not oscillate forever")
	assert_true(cam.position.x <= 50.0 + 0.001,
		"position.x must stay within bounds even though move_to()'s target was out of range")
	assert_true(cam.position.y <= 50.0 + 0.001,
		"position.y must stay within bounds even though move_to()'s target was out of range")
	assert_almost_eq(cam._target_pos.x, 50.0, 0.001,
		"_target_pos must have been re-clamped by _process(), not left at the raw far value")
	assert_almost_eq(cam._target_pos.y, 50.0, 0.001,
		"_target_pos must have been re-clamped by _process(), not left at the raw far value")
