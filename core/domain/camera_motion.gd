## core/domain/camera_motion.gd — CameraMotion domain pure functions
## (FEAT-001 / US-001, ADR-001 camera/panning steel thread).
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/CanvasItem inheritance, no SceneTree/engine I/O, no RNG.
## Extends RefCounted only, matching the existing domain-service convention
## (core/domain/mobility_dodge_rule.gd, core/domain/hex_ring_calculator.gd,
## core/domain/opportunistic_strike_eligibility.gd). Vector2/Rect2 are
## treated as language primitives here (per this iteration's design notes),
## not as an engine/framework dependency.
##
## Backs US-001's "camera visibly pans (lerp) and stops on arrival" logic at
## the math level, decoupled from any Camera2D/Node so it is unit-testable
## with GUT without a running SceneTree. The future GameCamera infrastructure
## adapter (presentation/game_camera.gd, a later feature in this iteration)
## calls these two functions from its own _process()/is_moving() rather than
## re-deriving the lerp/arrival math itself.
##
## Exposes speed/epsilon as ordinary function parameters (not hard-coded
## constants) per RISK-005, so GameCamera can later surface them as
## designer-tunable values without touching this file.
##
## lerp_step(current, target, speed, delta) -> Vector2
##   Moves `current` toward `target` proportionally to `speed * delta`,
##   expressed as a lerp weight clamped to [0.0, 1.0] — this guarantees the
##   result never overshoots `target` regardless of how large speed*delta
##   grows (e.g. a large delta from a hitched frame), and delta <= 0 is a
##   defensive no-op (returns `current` unchanged; no division, so no
##   NaN/inf can be produced).
##
## has_arrived(current, target, epsilon) -> bool
##   True iff current.distance_to(target) is STRICTLY less than epsilon
##   (default 1.0). A distance exactly equal to epsilon is NOT "arrived"
##   (matches this feature's test_criteria: "returns false when
##   distance_to(target) >= epsilon").
##
## Usage:
##   var next_pos := CameraMotion.lerp_step(position, target, 8.0, delta)
##   if CameraMotion.has_arrived(next_pos, target):
##       ...

class_name CameraMotion
extends RefCounted


## lerp_step — see class-level doc for the full contract.
static func lerp_step(current: Vector2, target: Vector2, speed: float, delta: float) -> Vector2:
	if delta <= 0.0:
		return current
	var weight: float = clamp(speed * delta, 0.0, 1.0)
	return current.lerp(target, weight)


## has_arrived — see class-level doc for the full contract.
static func has_arrived(current: Vector2, target: Vector2, epsilon: float = 1.0) -> bool:
	return current.distance_to(target) < epsilon
