extends GutTest
## tests/hex_grid/test_hex_grid_view_pan.gd — FEAT-005 (US-006 / FR-006):
## "Implement middle-mouse drag-to-pan with click suppression".
##
## Maps to the feature plan's files_to_create entry
## "tests/hex_grid/test_hex_grid_view_pan.gd" verbatim. HexGridView's own
## production script continues to live at presentation/hex_grid_view.gd
## (this project's actual, established file layout from every prior
## FEAT-001..004 commit — see tests/unit/presentation/test_hex_grid_view_hit_test.gd's
## own file-level doc for the same note), so this suite preloads that path
## even though it is filed under tests/hex_grid/ per the feature spec.
##
## Verifies (test_criteria):
##   1. Middle-mouse motion while _drag_panning is true decrements
##      _camera.position by event.relative.
##   2. hex_clicked is not emitted for a left-click event received while
##      _drag_panning is true.
##   3. hex_hovered is not emitted for a mouse-move event received while
##      _drag_panning is true.
##   4. Left-click still emits hex_clicked with the correct HexCoord when
##      _drag_panning is false.
##   5. Drag panning never mutates the legacy _origin_offset field.
##   6. get_viewport().set_input_as_handled() is called for consumed
##      middle-mouse press/drag events.
##
## Following this codebase's established "call the handler directly"
## convention (see test_hex_grid_view_hit_test.gd's/test_hex_grid_view_hover.gd's
## own file-level docs): a real middle-mouse-button/drag dispatch through
## _unhandled_input() via the engine's actual input pipeline
## (Input.parse_input_event()) is the headless-unreliable part this project's
## tests avoid depending on -- this suite instead calls
## HexGridView._unhandled_input() directly with hand-built InputEvent
## instances, which is the SAME method the real engine would call and is
## fully deterministic in a headless CI run.

const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")

## Tolerance for floating-point pixel/position comparisons.
const EPSILON: float = 0.5


## _instantiate_hex_grid_view_with_game_camera_sibling() → HexGridView —
## copied verbatim (same shape) from
## tests/unit/presentation/test_hex_grid_view_hit_test.gd's own helper of the
## same name: builds a minimal "world layer" Node2D with a Camera2D named
## "GameCamera" and a fresh HexGridView instance as SIBLING children
## (mirroring MainScene.tscn's real wiring), adds that world layer to the
## test's own tree so the returned HexGridView's `@onready var _camera`
## resolves `../GameCamera` to a real, CURRENT Camera2D.
func _instantiate_hex_grid_view_with_game_camera_sibling():
	var world_layer := Node2D.new()
	var game_camera := Camera2D.new()
	game_camera.name = "GameCamera"
	game_camera.position_smoothing_enabled = false
	world_layer.add_child(game_camera)
	var hex_grid_view = HexGridViewScene.instantiate()
	world_layer.add_child(hex_grid_view)
	add_child_autofree(world_layer)
	game_camera.make_current()
	return hex_grid_view


## _instantiate_hex_grid_view_in_isolated_subviewport() → Dictionary —
## builds a HexGridView inside a FRESH SubViewport (added to this test's own
## tree), so `hex_grid_view.get_viewport()` resolves to a Viewport instance
## that has NEVER had set_input_as_handled() called on it yet
## (Viewport.is_input_handled() defaults to false on a brand-new Viewport).
## Isolating each set_input_as_handled() assertion behind its own fresh
## SubViewport avoids any cross-test contamination of that boolean flag
## (the shared, single running test-scene Viewport otherwise has no public
## "reset" hook once something has marked it handled).
func _instantiate_hex_grid_view_in_isolated_subviewport() -> Dictionary:
	var sub_viewport := SubViewport.new()
	var hex_grid_view = HexGridViewScene.instantiate()
	sub_viewport.add_child(hex_grid_view)
	add_child_autofree(sub_viewport)
	return {"view": hex_grid_view, "viewport": sub_viewport}


func _middle_mouse_button_event(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = pressed
	return event


func _left_mouse_button_event() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func _mouse_motion_event(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — middle-mouse motion while dragging decrements
# _camera.position by event.relative.
# ══════════════════════════════════════════════════════════════════════════

func test_middle_mouse_press_then_drag_motion_decrements_camera_position_by_relative() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	var camera: Camera2D = hex_grid_view.get_node("../GameCamera")
	var initial_position: Vector2 = camera.position

	hex_grid_view._unhandled_input(_middle_mouse_button_event(true))
	assert_true(hex_grid_view._drag_panning, "a middle-mouse press must set _drag_panning to true")

	var relative := Vector2(37.0, -19.0)
	hex_grid_view._unhandled_input(_mouse_motion_event(relative))

	assert_almost_eq(
		camera.position, initial_position - relative, Vector2(EPSILON, EPSILON),
		"drag-pan motion must decrement _camera.position by event.relative"
	)


func test_middle_mouse_release_clears_drag_panning() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	hex_grid_view._unhandled_input(_middle_mouse_button_event(true))
	assert_true(hex_grid_view._drag_panning, "a middle-mouse press must set _drag_panning to true")

	hex_grid_view._unhandled_input(_middle_mouse_button_event(false))
	assert_false(hex_grid_view._drag_panning, "a middle-mouse release must clear _drag_panning back to false")


func test_multiple_drag_motions_accumulate_on_camera_position() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	var camera: Camera2D = hex_grid_view.get_node("../GameCamera")
	var initial_position: Vector2 = camera.position

	hex_grid_view._unhandled_input(_middle_mouse_button_event(true))
	hex_grid_view._unhandled_input(_mouse_motion_event(Vector2(10.0, 5.0)))
	hex_grid_view._unhandled_input(_mouse_motion_event(Vector2(-4.0, 12.0)))

	var expected_position: Vector2 = initial_position - Vector2(10.0, 5.0) - Vector2(-4.0, 12.0)
	assert_almost_eq(
		camera.position, expected_position, Vector2(EPSILON, EPSILON),
		"successive drag motions must each independently decrement _camera.position by their own event.relative"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — hex_clicked is not emitted for a left-click received while
# _drag_panning is true.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_clicked_is_not_emitted_for_left_click_while_drag_panning() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	hex_grid_view._unhandled_input(_middle_mouse_button_event(true))
	assert_true(hex_grid_view._drag_panning, "sanity: _drag_panning must be true after the middle-mouse press")

	watch_signals(hex_grid_view)
	hex_grid_view._unhandled_input(_left_mouse_button_event())

	assert_signal_not_emitted(
		hex_grid_view, "hex_clicked",
		"hex_clicked must be suppressed for a left-click received while _drag_panning is true"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — hex_hovered is not emitted for mouse-move events while
# _drag_panning is true.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_hovered_is_not_emitted_for_mouse_motion_while_drag_panning() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	hex_grid_view._unhandled_input(_middle_mouse_button_event(true))
	assert_true(hex_grid_view._drag_panning, "sanity: _drag_panning must be true after the middle-mouse press")

	watch_signals(hex_grid_view)
	hex_grid_view._unhandled_input(_mouse_motion_event(Vector2(5.0, 5.0)))

	assert_signal_not_emitted(
		hex_grid_view, "hex_hovered",
		"hex_hovered must be suppressed for mouse motion received while _drag_panning is true"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — left-click still emits hex_clicked with the correct HexCoord
# when _drag_panning is false.
# ══════════════════════════════════════════════════════════════════════════

func test_left_click_still_emits_hex_clicked_when_not_drag_panning() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	assert_false(hex_grid_view._drag_panning, "sanity: _drag_panning must default to false")

	watch_signals(hex_grid_view)
	hex_grid_view._unhandled_input(_left_mouse_button_event())

	# With the GameCamera at its default (0, 0) position and no OS-level
	# cursor state in this headless CI, get_global_mouse_position() resolves
	# to world (0, 0) -- the same default-camera sanity pin
	# test_hex_grid_view_hit_test.gd's own criterion 1 establishes -- so a
	# left-click here must resolve to hex (0, 0).
	assert_signal_emitted_with_parameters(
		hex_grid_view, "hex_clicked", [HexCoordClass.new(0, 0)],
		"a left-click while _drag_panning is false must still emit hex_clicked with the correct HexCoord"
	)


func test_hex_clicked_resumes_after_drag_panning_ends() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	hex_grid_view._unhandled_input(_middle_mouse_button_event(true))
	hex_grid_view._unhandled_input(_middle_mouse_button_event(false))
	assert_false(hex_grid_view._drag_panning, "sanity: _drag_panning must be false again after release")

	watch_signals(hex_grid_view)
	hex_grid_view._unhandled_input(_left_mouse_button_event())

	assert_signal_emitted(
		hex_grid_view, "hex_clicked",
		"hex_clicked must resume firing on left-click once a drag-pan gesture has ended"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — drag panning never mutates the legacy _origin_offset field.
# ══════════════════════════════════════════════════════════════════════════

func test_drag_panning_never_mutates_origin_offset() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	var initial_offset: Vector2 = hex_grid_view.get_origin_offset()

	hex_grid_view._unhandled_input(_middle_mouse_button_event(true))
	hex_grid_view._unhandled_input(_mouse_motion_event(Vector2(50.0, 25.0)))
	hex_grid_view._unhandled_input(_mouse_motion_event(Vector2(-8.0, 4.0)))
	hex_grid_view._unhandled_input(_middle_mouse_button_event(false))

	assert_eq(
		hex_grid_view.get_origin_offset(), initial_offset,
		"drag-to-pan motion must never mutate the legacy _origin_offset field, only _camera.position"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 — get_viewport().set_input_as_handled() is called for consumed
# middle-mouse press/drag events.
# ══════════════════════════════════════════════════════════════════════════

func test_middle_mouse_press_calls_set_input_as_handled() -> void:
	var ctx: Dictionary = _instantiate_hex_grid_view_in_isolated_subviewport()
	assert_false(
		ctx["viewport"].is_input_handled(),
		"sanity: a freshly created SubViewport must start with no input marked handled"
	)

	ctx["view"]._unhandled_input(_middle_mouse_button_event(true))

	assert_true(
		ctx["viewport"].is_input_handled(),
		"a consumed middle-mouse press event must call get_viewport().set_input_as_handled()"
	)


func test_drag_motion_calls_set_input_as_handled() -> void:
	var ctx: Dictionary = _instantiate_hex_grid_view_in_isolated_subviewport()
	ctx["view"]._drag_panning = true
	assert_false(
		ctx["viewport"].is_input_handled(),
		"sanity: a freshly created SubViewport must start with no input marked handled"
	)

	ctx["view"]._unhandled_input(_mouse_motion_event(Vector2(12.0, 8.0)))

	assert_true(
		ctx["viewport"].is_input_handled(),
		"a consumed drag-pan motion event must call get_viewport().set_input_as_handled()"
	)


# ══════════════════════════════════════════════════════════════════════════
# Regression: the view remains fully usable after drag-pan input handling.
# ══════════════════════════════════════════════════════════════════════════

func test_view_remains_usable_after_drag_pan_calls() -> void:
	const CombatantClass = preload("res://core/domain/combatant.gd")

	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	hex_grid_view._unhandled_input(_middle_mouse_button_event(true))
	hex_grid_view._unhandled_input(_mouse_motion_event(Vector2(20.0, -10.0)))
	hex_grid_view._unhandled_input(_middle_mouse_button_event(false))

	hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(0, 0)),
	])
	assert_eq(hex_grid_view.get_token_count(), 1, "HexGridView must remain fully functional after drag-pan calls")


# ══════════════════════════════════════════════════════════════════════════
# FEAT-006 (US-007 / FR-007): "Implement keyboard pan via WASD / arrow keys
# with UI-focus passthrough" -- per-frame _process() keyboard pan.
#
# Unlike the middle-mouse drag-pan suite above (which calls
# HexGridView._unhandled_input() directly with hand-built InputEvent
# instances), HexGridView._process() polls GLOBAL engine Input singleton
# state (Input.is_action_pressed()/Input.is_key_pressed()) rather than
# reacting to a passed-in event object -- there is no event parameter to
# hand-build here. This suite therefore drives the REAL Input singleton via
# GutInputSender (this project's addons/gut/input_sender.gd, exposed as the
# `InputSender` class reference on every GutTest, per addons/gut/test.gd)
# with `Input` itself as the sole receiver and auto-flush enabled
# (Input.flush_buffered_events() after every event, required for
# Input.is_key_pressed()/is_action_pressed() to observe the just-sent event
# headlessly -- verified empirically against this project's actual Godot
# 4.3 binary), then calls HexGridView._process(delta) directly with an
# explicit delta (the SAME "call the handler directly" convention this
# file's own drag-pan suite above already documents, just applied to
# _process() instead of _unhandled_input()). Every test releases all
# simulated input in an `after_each()` so no pressed key/action state leaks
# across tests (Input singleton state is process-global, not per-test).
# ══════════════════════════════════════════════════════════════════════════

var _key_sender = null


func before_each() -> void:
	_key_sender = InputSender.new(Input)
	_key_sender.set_auto_flush_input(true)


func after_each() -> void:
	if _key_sender != null:
		_key_sender.release_all()
		_key_sender = null


## Criterion — a no-input frame leaves _camera.position unchanged.
func test_no_input_frame_leaves_camera_position_unchanged() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	var camera: Camera2D = hex_grid_view.get_node("../GameCamera")
	var initial_position: Vector2 = camera.position

	hex_grid_view._process(0.1)

	assert_eq(
		camera.position, initial_position,
		"a _process() frame with no key/action held must leave _camera.position completely unchanged"
	)


## Criterion — single-direction input moves _camera.position by exactly
## PAN_SPEED * delta in that direction (WASD variant: KEY_D -> +x).
func test_single_direction_wasd_input_moves_camera_by_pan_speed_times_delta() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	var camera: Camera2D = hex_grid_view.get_node("../GameCamera")
	var initial_position: Vector2 = camera.position

	_key_sender.key_down(KEY_D)
	hex_grid_view._process(0.1)

	var expected_position: Vector2 = initial_position + Vector2(hex_grid_view.PAN_SPEED * 0.1, 0.0)
	assert_almost_eq(
		camera.position, expected_position, Vector2(EPSILON, EPSILON),
		"KEY_D held must move _camera.position.x by exactly PAN_SPEED * delta"
	)


## Criterion — single-direction input via the built-in arrow-key actions
## (ui_up) also moves _camera.position by exactly PAN_SPEED * delta.
func test_single_direction_arrow_action_input_moves_camera_by_pan_speed_times_delta() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	var camera: Camera2D = hex_grid_view.get_node("../GameCamera")
	var initial_position: Vector2 = camera.position

	_key_sender.action_down("ui_up")
	hex_grid_view._process(0.1)

	var expected_position: Vector2 = initial_position + Vector2(0.0, -hex_grid_view.PAN_SPEED * 0.1)
	assert_almost_eq(
		camera.position, expected_position, Vector2(EPSILON, EPSILON),
		"the ui_up action held must move _camera.position.y by exactly -(PAN_SPEED * delta)"
	)


## Criterion — diagonal input (W+D) is normalized before being scaled by
## PAN_SPEED * delta, i.e. the resulting displacement's magnitude is
## PAN_SPEED * delta, not PAN_SPEED * delta * sqrt(2).
func test_diagonal_input_is_normalized_before_scaling() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	var camera: Camera2D = hex_grid_view.get_node("../GameCamera")
	var initial_position: Vector2 = camera.position

	_key_sender.key_down(KEY_W)
	_key_sender.key_down(KEY_D)
	hex_grid_view._process(0.1)

	var delta_position: Vector2 = camera.position - initial_position
	var expected_delta: Vector2 = Vector2(1.0, -1.0).normalized() * hex_grid_view.PAN_SPEED * 0.1
	assert_almost_eq(
		delta_position, expected_delta, Vector2(EPSILON, EPSILON),
		"W+D held simultaneously must normalize the diagonal direction before scaling by PAN_SPEED * delta"
	)
	assert_almost_eq(
		delta_position.length(), hex_grid_view.PAN_SPEED * 0.1, EPSILON,
		"a normalized diagonal pan must move at exactly PAN_SPEED * delta, never PAN_SPEED * delta * sqrt(2)"
	)


## Criterion — when get_viewport().gui_get_focus_owner() != null, arrow-key
## input is not consumed and does not move the camera.
func test_arrow_key_input_does_not_move_camera_when_control_has_focus() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	var focus_target := LineEdit.new()
	focus_target.focus_mode = Control.FOCUS_ALL
	add_child_autofree(focus_target)
	focus_target.grab_focus()
	assert_eq(
		hex_grid_view.get_viewport().gui_get_focus_owner(), focus_target,
		"sanity: the LineEdit must actually hold keyboard focus on this view's viewport"
	)

	var camera: Camera2D = hex_grid_view.get_node("../GameCamera")
	var initial_position: Vector2 = camera.position

	_key_sender.action_down("ui_right")
	hex_grid_view._process(0.1)

	assert_eq(
		camera.position, initial_position,
		"arrow-key (ui_right) input must NOT move the camera while a Control holds keyboard focus"
	)


## Regression companion to the above: with no Control focused, the SAME
## ui_right action still pans the camera as normal (proves the guard is
## focus-conditional, not a blanket regression that disables arrow-key pan
## entirely).
func test_arrow_key_input_still_moves_camera_when_nothing_has_focus() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	assert_null(
		hex_grid_view.get_viewport().gui_get_focus_owner(),
		"sanity: nothing should hold keyboard focus on this view's viewport by default"
	)

	var camera: Camera2D = hex_grid_view.get_node("../GameCamera")
	var initial_position: Vector2 = camera.position

	_key_sender.action_down("ui_right")
	hex_grid_view._process(0.1)

	var expected_position: Vector2 = initial_position + Vector2(hex_grid_view.PAN_SPEED * 0.1, 0.0)
	assert_almost_eq(
		camera.position, expected_position, Vector2(EPSILON, EPSILON),
		"ui_right action held must move the camera normally when no Control holds keyboard focus"
	)


## Criterion — zero-vector input never triggers a normalize-of-zero-vector
## call: with no input held, _camera.position must remain EXACTLY equal
## (bit-for-bit, no float epsilon drift from a stray Vector2.ZERO.normalized()
## NaN/undefined result) to its pre-frame value across several consecutive
## no-input frames.
func test_zero_vector_input_never_normalizes_and_position_stays_exact() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	var camera: Camera2D = hex_grid_view.get_node("../GameCamera")
	var initial_position: Vector2 = camera.position

	hex_grid_view._process(0.1)
	hex_grid_view._process(0.016)
	hex_grid_view._process(1.0)

	assert_eq(
		camera.position, initial_position,
		"repeated no-input _process() frames must never move the camera or produce NaN from normalizing a zero vector"
	)
	assert_false(is_nan(camera.position.x) or is_nan(camera.position.y), "camera position must never become NaN")


## Regression: HexGridView instantiated standalone (no GameCamera sibling,
## `_camera == null`, e.g. this view's own .tscn in isolation) must not
## crash when _process() runs with keys held -- mirrors this view's
## established graceful-degradation precedent (set_origin_offset(),
## _handle_drag_pan_motion()).
func test_process_does_not_crash_when_camera_is_null() -> void:
	var hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(hex_grid_view)
	await get_tree().process_frame

	assert_null(hex_grid_view._camera, "sanity: a standalone HexGridView must have no resolved _camera")

	_key_sender.key_down(KEY_D)
	hex_grid_view._process(0.1)

	pass_test("HexGridView._process() must not crash when _camera is null")
