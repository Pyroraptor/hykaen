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

class_name GameCamera
extends Camera2D

const CameraMotion = preload("res://core/domain/camera_motion.gd")

## Lerp speed used by CameraMotion.lerp_step, in "weight units per second"
## (see core/domain/camera_motion.gd doc) — how quickly position closes the
## remaining distance to _target_pos each _process tick. Exported so this
## can be retuned per RISK-005 without editing this script.
@export var lerp_speed: float = 12.0

## Distance (in world units) below which the camera is considered to have
## "arrived" at _target_pos and the lerp stops. Exported for the same
## RISK-005 tunability reason as lerp_speed.
@export var stop_threshold: float = 1.0

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


func _process(delta: float) -> void:
	if not _moving:
		return

	position = CameraMotion.lerp_step(position, _target_pos, lerp_speed, delta)

	if CameraMotion.has_arrived(position, _target_pos, stop_threshold):
		_moving = false
