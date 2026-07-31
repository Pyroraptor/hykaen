## presentation/game_camera.gd — GameCamera (FEAT-002 / US-001, ADR-001
## camera/panning steel thread).
##
## Infrastructure adapter (Clean Architecture): a real Camera2D node — the
## outermost ring, per this iteration's design notes — that implements this
## slice's ICameraPort contract (move_to / is_moving; set_bounds lands in a
## later feature). GameCamera owns the only impure, per-frame state in this
## steel thread (_target_pos, whether a lerp is in progress) and calls the
## DOMAIN core/domain/camera_motion.gd pure functions (CameraMotion.lerp_step,
## CameraMotion.has_arrived — FEAT-001) from _process() rather than
## re-deriving the lerp/arrival math itself. GameCamera performs no SQL, no
## HTTP, and holds no combat-rule logic — it only reads/writes its own Node
## transform.
##
## move_to(world_pos, instant = false):
##   - instant == true: `position` is set synchronously to world_pos and any
##     in-progress lerp is cancelled (_moving cleared) — satisfies
##     "move_to(pos, instant=true) sets position synchronously and
##     is_moving() becomes false".
##   - instant == false: `_target_pos` is stored and _process() begins
##     lerping `position` toward it every frame at `lerp_speed` units/s,
##     stopping once CameraMotion.has_arrived(position, _target_pos,
##     stop_threshold) is true.
##
## `lerp_speed` (default 12.0) and `stop_threshold` (default 1.0) are
## @export-ed per RISK-005 (designer/tunability requirement) so a level or
## camera-feel pass can retune motion from the Inspector without touching
## this script.
##
## is_moving() -> bool: true while a non-instant move_to()'s lerp has not yet
## reached _target_pos (within stop_threshold); false otherwise, including
## before any move_to() call has ever been made.
##
## set_bounds(rect) — FEAT-005 (US-003, mitigates RISK-001):
##   - Populated Rect2: `limit_left`/`limit_right`/`limit_top`/
##     `limit_bottom` are set from the rect's edges
##     (position.x/position.x+size.x/position.y/position.y+size.y), and
##     `_target_pos`/`position` are immediately clamped into the new rect
##     if either was outside it.
##   - Empty Rect2() (`rect == Rect2()`): limits reset to Godot's own
##     Camera2D default sentinel values (+/-10,000,000), the documented
##     "no bounds" contract state — not a failure/error path.
##   - RISK-001: bounds must not only be enforced at the instant
##     set_bounds() is called — a subsequent move_to() can store a new,
##     unclamped `_target_pos` at any time, and set_bounds() itself may be
##     called again mid-lerp. `_process()` therefore re-clamps
##     `_target_pos` into the CURRENT limits on every tick (not only
##     inside set_bounds()), so position always lerps toward an in-bounds
##     target and never snaps/oscillates when bounds change mid-motion.
##
## _unhandled_input(event) — FEAT-009 (US-007, ADR-004/ADR-005 zoom): reacts
## to InputEventMouseButton MOUSE_BUTTON_WHEEL_UP/DOWN, adjusting `zoom` by
## +/- `zoom_step` per axis and delegating clamping to DOMAIN's
## core/domain/zoom_clamp.gd ZoomClamp.apply_delta(current, delta, min_zoom,
## max_zoom) — see that function's doc header for the full contract. All
## other events (including other mouse buttons/motion) pass through
## unhandled; a consumed wheel event calls
## get_viewport().set_input_as_handled() so HexGridView does not also react
## to the same scroll.

class_name GameCamera
extends Camera2D

const CameraMotion = preload("res://core/domain/camera_motion.gd")
const ZoomClamp = preload("res://core/domain/zoom_clamp.gd")

## Godot's own Camera2D default limit_left/right/top/bottom sentinel
## values, restored by set_bounds(Rect2()) as the documented "no bounds"
## contract state (FEAT-005 / US-003).
const _DEFAULT_LIMIT: float = 10000000.0

## Lerp speed used by CameraMotion.lerp_step, in "weight units per second"
## (see core/domain/camera_motion.gd doc) — how quickly position closes the
## remaining distance to _target_pos each _process tick. Exported so this
## can be retuned per RISK-005 without editing this script.
@export var lerp_speed: float = 12.0

## Distance (in world units) below which the camera is considered to have
## "arrived" at _target_pos and the lerp stops. Exported for the same
## RISK-005 tunability reason as lerp_speed.
@export var stop_threshold: float = 1.0

## zoom_step / min_zoom / max_zoom — FEAT-009 (US-007, ADR-004/ADR-005):
## `_unhandled_input()` below reacts to InputEventMouseButton wheel events
## (MOUSE_BUTTON_WHEEL_UP/DOWN), adjusting `zoom` by +/- zoom_step per axis
## and delegating the clamp itself to DOMAIN's `ZoomClamp.apply_delta` so
## the "zoom is always in range" guarantee lives in exactly one place.
## Exported per RISK-005 (designer/tunability requirement), matching
## lerp_speed/stop_threshold above -- min_zoom/max_zoom default to
## (0.5,0.5)/(2.0,2.0) per this feature's design notes.
@export var zoom_step: float = 0.1
@export var min_zoom: Vector2 = Vector2(0.5, 0.5)
@export var max_zoom: Vector2 = Vector2(2.0, 2.0)

## The current lerp destination, in world-space coordinates. Only
## meaningful while _moving is true; otherwise stale/unused.
var _target_pos: Vector2 = Vector2.ZERO

## True while a non-instant move_to()'s lerp is in progress (i.e. position
## has not yet arrived within stop_threshold of _target_pos).
var _moving: bool = false


## move_to — see class-level doc for the full contract.
func move_to(world_pos: Vector2, instant: bool = false) -> void:
	if instant:
		position = world_pos
		_target_pos = world_pos
		_moving = false
		return

	_target_pos = world_pos
	_moving = not CameraMotion.has_arrived(position, _target_pos, stop_threshold)


## is_moving — see class-level doc for the full contract.
func is_moving() -> bool:
	return _moving


## set_bounds — see class-level doc for the full contract.
func set_bounds(rect: Rect2) -> void:
	if rect == Rect2():
		limit_left = -_DEFAULT_LIMIT
		limit_right = _DEFAULT_LIMIT
		limit_top = -_DEFAULT_LIMIT
		limit_bottom = _DEFAULT_LIMIT
	else:
		limit_left = rect.position.x
		limit_right = rect.position.x + rect.size.x
		limit_top = rect.position.y
		limit_bottom = rect.position.y + rect.size.y

	_target_pos = _clamp_to_limits(_target_pos)
	position = _clamp_to_limits(position)


## _clamp_to_limits — clamps a world-space point into the current
## limit_left/right/top/bottom rectangle. Shared by set_bounds() (one-time
## clamp on bounds change) and _process() (RISK-001: continuous per-tick
## re-clamp of _target_pos), so the two call sites can never drift apart.
func _clamp_to_limits(pos: Vector2) -> Vector2:
	return Vector2(
		clamp(pos.x, limit_left, limit_right),
		clamp(pos.y, limit_top, limit_bottom)
	)


## _unhandled_input(event) -> void -- FEAT-009 (US-007, ADR-004/ADR-005):
## reacts ONLY to InputEventMouseButton with button_index
## MOUSE_BUTTON_WHEEL_UP/MOUSE_BUTTON_WHEEL_DOWN (checking `event.pressed`
## so the paired press+release wheel event pair only adjusts zoom once, not
## twice); every other InputEvent -- other mouse buttons, mouse motion, etc.
## -- passes through entirely untouched (no zoom change, no
## set_input_as_handled() call), so callers/siblings (e.g. HexGridView) that
## might also implement _unhandled_input() are free to react to those events
## themselves.
##
## Adjusts `zoom` by +/- zoom_step per axis (wheel up = zoom in = larger
## zoom value; wheel down = zoom out = smaller zoom value), delegating the
## actual add-then-clamp math to DOMAIN's ZoomClamp.apply_delta(current,
## delta, min_zoom, max_zoom) rather than re-deriving the clamp here -- this
## guarantees `zoom` can never leave [min_zoom, max_zoom] regardless of how
## many wheel events fire.
##
## A consumed wheel event calls get_viewport().set_input_as_handled() so
## HexGridView does not also react to the same scroll (documented
## event-ownership contract, ADR-005).
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if not event.pressed:
		return

	var delta: Vector2
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		delta = Vector2(zoom_step, zoom_step)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		delta = Vector2(-zoom_step, -zoom_step)
	else:
		return

	zoom = ZoomClamp.apply_delta(zoom, delta, min_zoom, max_zoom)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _moving:
		return

	# RISK-001: re-clamp _target_pos into the CURRENT bounds every tick
	# (not only inside set_bounds()) so a move_to() destination stored
	# while bounds were already active -- or a set_bounds() call that
	# lands mid-lerp -- can never pull position outside the active limits.
	_target_pos = _clamp_to_limits(_target_pos)

	position = CameraMotion.lerp_step(position, _target_pos, lerp_speed, delta)
	position = _clamp_to_limits(position)

	if CameraMotion.has_arrived(position, _target_pos, stop_threshold):
		_moving = false
