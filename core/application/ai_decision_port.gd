## core/application/ai_decision_port.gd — AIDecisionPort (FEAT-098 / US-005)
##
## Application layer (Clean Architecture): defines the contract
## RunRoundUseCase depends on to select an enemy combatant's action/target
## for its cycle turn, decoupling the round loop from any particular AI
## implementation (production AI in core/combat/ai.gd today; a counting/spy
## double in tests — see tests/test_encounter_regression.gd's CountingAI and
## tests/test_encounter_round_loop.gd's BrokenAI).
##
## GDScript has no formal interface/Protocol keyword, so this base class
## documents the contract and provides an abstract decide_action() that
## concrete adapters MUST override. Concrete adapters extend this script
## directly (`extends "res://core/application/ai_decision_port.gd"`) — OR,
## per this project's existing established pattern (core/combat/ai.gd is
## NOT modified by this extraction), may satisfy the contract purely via
## GDScript duck-typing without a formal `extends` relationship, since
## RunRoundUseCase never declares a static AIDecisionPort-typed parameter
## (doing so would reject any duck-typed-only implementation under GDScript's
## static type checking).
##
## Contract:
##   decide_action(combatant: Dictionary, targets: Array) -> Dictionary
##     Selects the action/target for `combatant` (an enemy) from the living
##     members of `targets` (the opposing side). Returns:
##       {action_type: String, target: Dictionary}
##     action_type == "" / target == {} signals "no action available" (no
##     living target) — RunRoundUseCase treats this as "skip this
##     combatant's turn for the cycle" rather than an error.
##
## Domain purity boundary (ADR-001): this file extends RefCounted only — no
## Node/Control/SceneTree inheritance — matching the existing port pattern
## established by core/rules/random_port.gd.
##
## Usage example:
##   var port: AIDecisionPort = AIClass.new()   # core/combat/ai.gd, duck-typed
##   var decision: Dictionary = port.decide_action(enemy_combatant, party_array)

class_name AIDecisionPort
extends RefCounted


## decide_action(combatant, targets) -> Dictionary — abstract; concrete
## adapters MUST override. The base implementation exists only to document
## the contract and to fail loudly (rather than silently returning a
## usable-looking decision) if a caller is ever handed a bare
## AIDecisionPort instead of a concrete adapter.
func decide_action(_combatant, _targets: Array) -> Dictionary:
	push_error("AIDecisionPort.decide_action() is abstract — override in a concrete adapter")
	return {"action_type": "", "target": {}}
