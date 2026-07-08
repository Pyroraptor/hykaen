## core/application/ports/reaction_chooser_port.gd — ReactionChooserPort
## (FEAT-009 / US-009)
##
## Application layer (Clean Architecture): the contract
## core/application/reaction_window.gd's ReactionWindow depends on to ask
## "what do you want to do?" once a reaction window has opened, without
## knowing whether the answer comes from a human (a blocking modal pop-up),
## an AI policy, or a headless auto-responder. Every implementation is
## interchangeable — infrastructure/auto_reaction_chooser.gd's
## AutoReactionChooser (headless Pass/fixed-policy), a future
## AIReactionPolicy, and the eventual presentation/-layer
## PlayerReactionChooser (a blocking modal pop-up) all satisfy this SAME
## contract, so reaction_window.gd never knows/cares which one it was
## handed (ADR-002 injection).
##
## GDScript has no formal interface/Protocol keyword, so this base class
## documents the contract and provides an abstract choose() that concrete
## adapters MUST override. Concrete adapters extend this script directly
## (`extends "res://core/application/ports/reaction_chooser_port.gd"`),
## matching the existing port pattern established by
## core/application/ai_decision_port.gd / core/application/event_sink_port.gd.
##
## Contract:
##   choose(legal_reactions: Array, context: Dictionary) -> String
##     Returns exactly one of `legal_reactions`' entries, or PASS ("none")
##     to decline every offered reaction. `context` carries whatever the
##     caller finds useful for the decision (attacker name, damage at
##     stake, etc.) — this port never inspects its shape itself, it is
##     passed straight through by reaction_window.gd from the trigger's own
##     "attack_context".
##
## Error handling (per this feature's error_handling design note): an
## unavailable or misbehaving chooser must NEVER hang the resolution
## pipeline. This base class's own abstract choose() returns PASS (after
## logging via push_error()) rather than raising/blocking, so a bare
## ReactionChooserPort instance handed to reaction_window.gd degrades
## safely instead of ever stalling the engine thread.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance.
##
## Usage example:
##   var chooser: ReactionChooserPort = AutoReactionChooserClass.new("pass")
##   var choice: String = chooser.choose(["dodge", "parry"], {"attacker_name": "Goblin"})
##   # choice -> "none" (PASS) for the headless "pass" policy

class_name ReactionChooserPort
extends RefCounted

## PASS — the sentinel choice meaning "decline every offered reaction".
## Deliberately matches core/rules/resolution.gd's VALID_ACTIVE_DEFENSES
## "none" entry so a chooser's PASS choice can be forwarded directly as
## resolve_weapon_attack()'s active_defense argument without translation.
const PASS: String = "none"


## choose(legal_reactions, context) -> String — abstract; concrete adapters
## MUST override. The base implementation exists only to document the
## contract and to fail safe (PASS, never a hang or a crash) if a caller is
## ever handed a bare ReactionChooserPort instead of a concrete adapter.
func choose(_legal_reactions: Array, _context: Dictionary) -> String:
	push_error("ReactionChooserPort.choose() is abstract — override in a concrete adapter")
	return PASS
