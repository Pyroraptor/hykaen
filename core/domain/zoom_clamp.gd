## core/domain/zoom_clamp.gd — ZoomClamp domain pure function
## (FEAT-009 / US-007, ADR-004/ADR-005 camera zoom steel thread).
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/CanvasItem inheritance, no SceneTree/engine I/O, no RNG.
## Extends RefCounted only, matching the existing domain-service convention
## (core/domain/camera_motion.gd, core/domain/map_bounds_calculator.gd).
## Vector2 is treated as a language primitive here (per this iteration's
## design notes), not as an engine/framework dependency.
##
## Backs US-007's "scroll wheel zooms the camera, clamped to a sane range"
## logic at the math level, decoupled from any Camera2D/Node so it is
## unit-testable with GUT without a running SceneTree. The GameCamera
## infrastructure adapter (presentation/game_camera.gd) calls this function
## from its own _unhandled_input() rather than re-deriving the clamp math
## itself, so the "zoom is always in range" guarantee lives in exactly one
## place (RISK-005 tunability + this feature's error_handling design note).
##
## apply_delta(current, delta, min_zoom, max_zoom) -> Vector2
##   Adds `delta` to `current` and clamps each axis of the result
##   independently to [min_zoom, max_zoom] — this guarantees the returned
##   zoom can never leave the caller-supplied range regardless of how many
##   times apply_delta is called in a row (e.g. repeated wheel ticks at an
##   extreme), matching this feature's test_criteria: "clamps result to
##   [Vector2(0.5,0.5), Vector2(2.0,2.0)]" for GameCamera's default range.
##
## Usage:
##   zoom = ZoomClamp.apply_delta(zoom, Vector2(0.1, 0.1), min_zoom, max_zoom)

class_name ZoomClamp
extends RefCounted


## apply_delta — see class-level doc for the full contract.
static func apply_delta(current: Vector2, delta: Vector2, min_zoom: Vector2, max_zoom: Vector2) -> Vector2:
	var result: Vector2 = current + delta
	return Vector2(
		clamp(result.x, min_zoom.x, max_zoom.x),
		clamp(result.y, min_zoom.y, max_zoom.y)
	)
