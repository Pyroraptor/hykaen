extends GutTest
## tests/unit/presentation/test_game_camera_zoom.gd
##
## GUT test suite for FEAT-009 (US-007, ADR-004/ADR-005 camera zoom steel
## thread): presentation/game_camera.gd's GameCamera._unhandled_input()
## mouse-wheel zoom handling. GameCamera is the infrastructure adapter that
## delegates the actual clamp math to the already-shipped DOMAIN
## core/domain/zoom_clamp.gd ZoomClamp.apply_delta pure function (this
## feature), rather than re-deriving the clamp math itself.
##
## Following this codebase's established "call the handler directly"
## convention (see tests/hex_grid/test_hex_grid_view_pan.gd's own
## file-level docs): a real mouse-wheel dispatch through the engine's
## actual input pipeline is NOT exercised here — _unhandled_input() is
## called directly with a hand-built InputEventMouseButton, and
## get_viewport().set_input_as_handled() consumption is asserted via a
## freshly-created, isolated SubViewport (Viewport.is_input_handled()
## defaults to false on a brand-new Viewport, and there is no public
## "reset" hook once something has marked it handled).
##
## Verifies (test_criteria):
##   1. Synthesized MOUSE_BUTTON_WHEEL_UP InputEventMouseButton increases
##      GameCamera zoom by the configured step and calls
##      set_input_as_handled().
##   2. Synthesized wheel events at the zoom extremes do not exceed clamp
##      bounds.
##   3. Non-wheel InputEventMouseButton events pass through unhandled (no
##      zoom change, no set_input_as_handled call).

const GameCameraScript = preload("res://presentation/game_camera.gd")


func _make_camera() -> Camera2D:
	var cam: Camera2D = GameCameraScript.new()
	add_child_autofree(cam)
	return cam


## _instantiate_camera_in_isolated_subviewport() → Dictionary — builds a
## GameCamera inside a FRESH SubViewport (added to this test's own tree),
## so `cam.get_viewport()` resolves to a Viewport instance that has NEVER
## had set_input_as_handled() called on it yet. Mirrors
## tests/hex_grid/test_hex_grid_view_pan.gd's identical pattern.
func _instantiate_camera_in_isolated_subviewport() -> Dictionary:
	var sub_viewport := SubViewport.new()
	var cam: Camera2D = GameCameraScript.new()
	sub_viewport.add_child(cam)
	add_child_autofree(sub_viewport)
	return {"cam": cam, "viewport": sub_viewport}


func _wheel_event(button_index: int, pressed: bool = true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	return event


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: MOUSE_BUTTON_WHEEL_UP increases zoom by the configured step
# and calls set_input_as_handled().
# ══════════════════════════════════════════════════════════════════════════

func test_wheel_up_increases_zoom_by_configured_step() -> void:
	var cam := _make_camera()
	cam.zoom = Vector2(1.0, 1.0)

	cam._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))

	assert_almost_eq(cam.zoom, Vector2(1.1, 1.1), Vector2(0.0001, 0.0001),
		"wheel up must increase zoom by the exported +0.1 step")


func test_wheel_down_decreases_zoom_by_configured_step() -> void:
	var cam := _make_camera()
	cam.zoom = Vector2(1.0, 1.0)

	cam._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_DOWN))

	assert_almost_eq(cam.zoom, Vector2(0.9, 0.9), Vector2(0.0001, 0.0001),
		"wheel down must decrease zoom by the exported -0.1 step")


func test_zoom_step_is_exported_and_overridable() -> void:
	var cam := _make_camera()
	assert_eq(cam.zoom_step, 0.1, "zoom_step must default to 0.1")

	cam.zoom_step = 0.25
	cam.zoom = Vector2(1.0, 1.0)
	cam._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))

	assert_almost_eq(cam.zoom, Vector2(1.25, 1.25), Vector2(0.0001, 0.0001),
		"an overridden zoom_step must be used instead of the default")


func test_wheel_up_calls_set_input_as_handled() -> void:
	var ctx: Dictionary = _instantiate_camera_in_isolated_subviewport()
	assert_false(ctx["viewport"].is_input_handled(),
		"sanity: a freshly created SubViewport must start with no input marked handled")

	ctx["cam"]._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))

	assert_true(ctx["viewport"].is_input_handled(),
		"a consumed wheel-up event must call get_viewport().set_input_as_handled() (so HexGridView does not also react)")


func test_wheel_down_calls_set_input_as_handled() -> void:
	var ctx: Dictionary = _instantiate_camera_in_isolated_subviewport()
	assert_false(ctx["viewport"].is_input_handled(),
		"sanity: a freshly created SubViewport must start with no input marked handled")

	ctx["cam"]._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_DOWN))

	assert_true(ctx["viewport"].is_input_handled(),
		"a consumed wheel-down event must call get_viewport().set_input_as_handled()")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: wheel events at the zoom extremes do not exceed clamp
# bounds.
# ══════════════════════════════════════════════════════════════════════════

func test_wheel_up_repeated_never_exceeds_max_zoom() -> void:
	var cam := _make_camera()
	cam.zoom = Vector2(1.95, 1.95)

	for i in range(10):
		cam._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))

	assert_eq(cam.zoom, Vector2(2.0, 2.0),
		"repeated wheel-up ticks must never exceed the max zoom clamp bound")


func test_wheel_down_repeated_never_exceeds_min_zoom() -> void:
	var cam := _make_camera()
	cam.zoom = Vector2(0.55, 0.55)

	for i in range(10):
		cam._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_DOWN))

	assert_eq(cam.zoom, Vector2(0.5, 0.5),
		"repeated wheel-down ticks must never go below the min zoom clamp bound")


func test_min_and_max_zoom_are_exported_with_documented_defaults() -> void:
	var cam := _make_camera()
	assert_eq(cam.min_zoom, Vector2(0.5, 0.5), "min_zoom must default to Vector2(0.5, 0.5)")
	assert_eq(cam.max_zoom, Vector2(2.0, 2.0), "max_zoom must default to Vector2(2.0, 2.0)")


func test_overridden_min_max_zoom_are_respected() -> void:
	var cam := _make_camera()
	cam.min_zoom = Vector2(1.0, 1.0)
	cam.max_zoom = Vector2(1.0, 1.0)
	cam.zoom = Vector2(1.0, 1.0)

	cam._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))

	assert_eq(cam.zoom, Vector2(1.0, 1.0),
		"an overridden min_zoom == max_zoom == 1.0 must clamp zoom to exactly 1.0 regardless of wheel input")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: non-wheel InputEventMouseButton events pass through
# unhandled (no zoom change, no set_input_as_handled call).
# ══════════════════════════════════════════════════════════════════════════

func test_left_click_does_not_change_zoom_or_mark_handled() -> void:
	var ctx: Dictionary = _instantiate_camera_in_isolated_subviewport()
	var cam: Camera2D = ctx["cam"]
	cam.zoom = Vector2(1.0, 1.0)

	cam._unhandled_input(_wheel_event(MOUSE_BUTTON_LEFT))

	assert_eq(cam.zoom, Vector2(1.0, 1.0), "a non-wheel mouse button must not change zoom")
	assert_false(ctx["viewport"].is_input_handled(),
		"a non-wheel mouse button event must not call set_input_as_handled()")


func test_middle_click_does_not_change_zoom_or_mark_handled() -> void:
	var ctx: Dictionary = _instantiate_camera_in_isolated_subviewport()
	var cam: Camera2D = ctx["cam"]
	cam.zoom = Vector2(1.0, 1.0)

	cam._unhandled_input(_wheel_event(MOUSE_BUTTON_MIDDLE))

	assert_eq(cam.zoom, Vector2(1.0, 1.0), "a non-wheel mouse button must not change zoom")
	assert_false(ctx["viewport"].is_input_handled(),
		"a non-wheel mouse button event must not call set_input_as_handled()")


func test_mouse_motion_event_does_not_change_zoom() -> void:
	var cam := _make_camera()
	cam.zoom = Vector2(1.0, 1.0)

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 10)
	cam._unhandled_input(motion)

	assert_eq(cam.zoom, Vector2(1.0, 1.0), "a mouse-motion event must never affect zoom")
