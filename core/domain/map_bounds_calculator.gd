## core/domain/map_bounds_calculator.gd — MapBoundsCalculator domain pure
## function (FEAT-003 / US-002, ADR-001 camera/panning steel thread).
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/CanvasItem inheritance, no SceneTree/engine I/O, no RNG.
## Extends RefCounted only, matching the existing domain-service convention
## (core/domain/camera_motion.gd, core/domain/hex_ring_calculator.gd,
## core/domain/mobility_dodge_rule.gd). Vector2/Rect2 are treated as
## language primitives here (per this iteration's design notes), not as an
## engine/framework dependency.
##
## Backs US-002's "camera bounds hug the placed tokens/selectable hexes"
## logic at the math level, decoupled from HexGridView's Node/_tokens
## Dictionary storage so it is unit-testable with GUT without a running
## SceneTree. The future HexGridView.get_world_bounds() infrastructure
## adapter (presentation/hex_grid_view.gd, a later feature in this
## iteration) gathers its token/selectable-hex Vector2 positions and
## delegates the AABB + margin math to this function rather than
## re-deriving it.
##
## compute_bounds(points, margin) -> Rect2
##   Computes the axis-aligned bounding box (AABB) over `points`, then
##   expands it by `margin` on all four sides (left/right/top/bottom each
##   grow by `margin`, so width/height each grow by `margin * 2`).
##   - Empty `points` -> returns Rect2() (a default-constructed, zero-area
##     rect). This is a defined "no bounds" contract, not an error —
##     callers MUST check for this before treating the result as
##     authoritative bounds. Note: Godot 4.3's built-in Rect2 has no
##     is_empty() method; the operational check is either equality with
##     Rect2() or `not result.has_area()` (the latter also matches a
##     single point expanded by margin=0, which is a legitimate
##     zero-size-but-non-default rect — prefer equality with Rect2() when
##     that distinction matters to the caller).
##   - Single point -> returns a zero-size rect positioned at that point,
##     then expanded symmetrically by `margin` (so the point ends up
##     dead-center of a margin*2 x margin*2 square).
##
## Usage:
##   var bounds := MapBoundsCalculator.compute_bounds(token_positions, HEX_SIZE * 1.5)
##   if bounds.has_area():
##       camera.set_bounds(bounds)

class_name MapBoundsCalculator
extends RefCounted


## compute_bounds — see class-level doc for the full contract.
static func compute_bounds(points: Array, margin: float) -> Rect2:
	if points.is_empty():
		return Rect2()

	var first_point: Vector2 = points[0]
	var rect := Rect2(first_point, Vector2.ZERO)
	for i in range(1, points.size()):
		rect = rect.expand(points[i])

	return rect.grow(margin)
