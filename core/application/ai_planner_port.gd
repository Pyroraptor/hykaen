## core/application/ai_planner_port.gd — AIPlannerPort (FEAT-001 / US-001 / FR-001)
##
## Application layer (Clean Architecture): defines the NEW, parallel port
## that tier-specific DOMAIN AI planners (MindlessAI, GruntAI, ...) will
## implement and that RoundSession will duck-type against when deciding an
## enemy combatant's full turn (an ordered plan of Stride/Step/Strike/
## Combine items), rather than a single action/target pair.
##
## Per ADR-001, this is a PARALLEL port — a new, independent contract — not
## an extension of, subclass of, or modification to the existing (frozen)
## core/application/ai_decision_port.gd. That file continues to serve the
## legacy decide_action(combatant, targets) -> Dictionary contract used by
## core/combat/ai.gd and every existing FakeDecisionPort test double.
## ai_decision_port.gd is NOT touched by this feature.
##
## GDScript has no formal interface/Protocol keyword, so — mirroring the
## exact convention already established by ai_decision_port.gd — this base
## class documents the contract and provides an abstract plan_turn() that
## concrete DOMAIN planners MUST override. Concrete planners may extend
## this script directly, or satisfy the contract purely via GDScript
## duck-typing (RoundSession selects this path via
## Callable(x, "plan_turn").is_valid(), never a static AIPlannerPort-typed
## parameter, so a duck-typed-only implementation is never rejected by
## GDScript's static type checking).
##
## Contract:
##   plan_turn(combatant, world_context: Dictionary) -> Array
##     Produces an ORDERED plan (Array of ActionPlanItem Dictionaries, e.g.
##     {action_type: "Strike"|"Step"|"Stride"|"Combine", ...}) for
##     `combatant`'s turn, given `world_context` (expected to carry
##     "party", "enemies", "action_economy" keys — see
##     RoundSession._build_ai_world_context()). An empty Array ([]) is a
##     first-class, legitimate return value meaning WAIT — it is not an
##     error and callers must not treat it as one.
##
## Domain purity boundary (ADR-001): this file extends RefCounted only — no
## Node/Control/SceneTree inheritance — matching the existing port pattern
## established by core/rules/random_port.gd and core/application/
## ai_decision_port.gd.
##
## Usage example:
##   var port: AIPlannerPort = GruntAI.new()   # core/combat/grunt_ai.gd, duck-typed
##   var plan: Array = port.plan_turn(enemy_combatant, world_context)

class_name AIPlannerPort
extends RefCounted


## plan_turn(combatant, world_context) -> Array — abstract; concrete DOMAIN
## planners MUST override. The base implementation exists only to document
## the contract and to fail loudly (via push_error) rather than silently
## returning a usable-looking plan, while still degrading gracefully — the
## caller's WAIT-handling path treats an empty Array identically to a
## legitimate empty plan, so a mis-wired/unimplemented planner degrades to
## an idle turn rather than crashing.
func plan_turn(_combatant, _world_context: Dictionary) -> Array:
	push_error("AIPlannerPort.plan_turn() is abstract — override in a concrete planner")
	return []
