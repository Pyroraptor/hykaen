## infrastructure/auto_reaction_chooser.gd — AutoReactionChooser
## (FEAT-009 / US-009 / FR-005, ADR-014)
##
## Infrastructure/adapter layer (Clean Architecture): a headless,
## no-UI-present implementation of core/application/ports/
## reaction_chooser_port.gd's ReactionChooserPort contract — used to drive
## resolution to completion in tests/sim runs where no
## presentation/-layer PlayerReactionChooser exists (this feature's
## test_criteria #3), and interchangeably with a future AIReactionPolicy
## wherever a fully-automated reaction decision is required.
##
## Two policies, selected at construction:
##   "pass"        (default) — ALWAYS declines every offered reaction
##                  (returns ReactionChooserPort.PASS), regardless of what
##                  legal_reactions offers. The safest/simplest headless
##                  default — guarantees deterministic, side-effect-free
##                  resolution runs (e.g. tests/sim/test_balance_sim.gd-style
##                  N-round simulations) with zero extra reaction-spend
##                  variance.
##   "first_legal" — always takes the FIRST entry of legal_reactions when
##                   non-empty, else PASS. Useful for exercising the
##                   "a reaction fires" path headlessly (e.g. proving
##                   resume() applies a real non-Pass choice end-to-end)
##                   without needing a live UI or a fully-fledged AI policy.
##
## Domain purity boundary (ADR-001): this file lives in infrastructure/
## (an adapter), never imported by core/ itself — core/application/
## reaction_window.gd only ever depends on the ReactionChooserPort
## contract, never on this concrete class.
##
## Usage example:
##   var chooser := AutoReactionChooser.new("pass")
##   var choice: String = chooser.choose(["dodge"], {})
##   # choice -> "none" (PASS)
##
##   var eager_chooser := AutoReactionChooser.new("first_legal")
##   var eager_choice: String = eager_chooser.choose(["dodge", "parry"], {})
##   # eager_choice -> "dodge"

class_name AutoReactionChooser
extends "res://core/application/ports/reaction_chooser_port.gd"

## Recognized policy names — an unrecognized value falls back to "pass"
## (fail-safe: never a hang/crash, per this feature's error_handling design
## note).
const POLICY_PASS: String = "pass"
const POLICY_FIRST_LEGAL: String = "first_legal"

var _policy: String


## _init(policy) — policy defaults to POLICY_PASS ("pass").
func _init(policy: String = POLICY_PASS) -> void:
	_policy = policy


## choose(legal_reactions, context) -> String — see class-level doc for the
## two supported policies. `context` is accepted (matching
## ReactionChooserPort's contract) but never inspected — both policies are
## purely a function of legal_reactions.
func choose(legal_reactions: Array, _context: Dictionary) -> String:
	if _policy == POLICY_FIRST_LEGAL and not legal_reactions.is_empty():
		return legal_reactions[0]
	return PASS
