## infrastructure/ai_reaction_policy.gd — AIReactionPolicy (FEAT-002 / US-002)
##
## Infrastructure/adapter layer (Clean Architecture): a deterministic,
## RNG-free implementation of core/application/ports/reaction_chooser_port.gd's
## ReactionChooserPort contract — the enemy AI's actual reaction "brain" for
## Dodge/Parry/Block. This is a NEW, INDEPENDENT ReactionChooserPort
## implementation, distinct from infrastructure/auto_reaction_chooser.gd's
## AutoReactionChooser: that file is a headless TEST DOUBLE
## (pass/first-legal only, no rule-driven reasoning at all — see its own
## file-level doc) used to drive resolution in tests/sim runs where no real
## AI brain is needed. AIReactionPolicy never imports, extends, aliases, or
## otherwise references AutoReactionChooser (ADR-001; this feature's
## test_criteria #4) — the two are parallel, swappable adapters behind the
## SAME port, selected at the composition root (MainScene), never confused
## with one another.
##
## Decision rules (delegated entirely to core/domain/mobility_dodge_rule.gd's
## MobilityDodgeRule and core/domain/defense_mitigation_calculator.gd's
## DefenseMitigationCalculator — this file owns ZERO comparison math of its
## own, only which legal_reactions entry to consult and in what priority
## order, per this feature's design notes' governing constants):
##
##   1. Dodge  — chosen when "dodge" is offered (legal_reactions) AND
##               MobilityDodgeRule.dodge_worthwhile(mobility,
##               targeted_defense_value) is true.
##   2. Parry  — else chosen when "parry" is offered AND
##               DefenseMitigationCalculator.parry_worthwhile(
##               parry_attack_bonus, parry_bonus, roll_total) is true.
##   3. Block  — else chosen when "block" is offered AND
##               DefenseMitigationCalculator.block_worthwhile(damage_raw,
##               hp_current) is true.
##   4. Pass   — otherwise (ReactionChooserPort.PASS) — matches Dodge being a
##               PreHitAvoidance-only reaction and Parry/Block being
##               OnHitMitigation-only reactions (core/application/
##               reaction_window.gd never offers both windows' legal
##               reactions to a single choose() call in the split-window
##               flow; a combined "WeaponAttack" trigger's legal_reactions
##               may list all three at once, in which case Dodge is
##               evaluated first, matching the real turn order — Dodge
##               happens BEFORE the attack roll, Parry/Block only after).
##
## No RNG of any kind is consumed by choose() — every input is read verbatim
## from `context` (the SAME Dictionary reaction_window.gd forwards straight
## through from trigger["attack_context"]), so two calls with identical
## (legal_reactions, context) ALWAYS return the identical choice (this
## feature's determinism test_criteria #3). The only "seeded roll" anywhere
## in this feature's scope is whatever pre-existing RNG produced
## roll_total/damage_raw upstream (core/rules/resolution.gd) — this policy
## never re-rolls, never seeds, never reads a RandomNumberGenerator.
##
## context (Dictionary) keys consulted — all default to 0 (hp_current
## defaults to 1, never 0, so a missing key can never divide by zero):
##   "mobility"               — int — the reactor's Mobility skill (Dodge).
##   "targeted_defense_value" — int — the passive defense value the attack
##                                targets (Dodge).
##   "parry_attack_bonus"     — int — the reactor's own attack-roll bonus
##                                (Parry).
##   "parry_bonus"            — int — the reactor's weapon's parry_bonus
##                                (Parry).
##   "roll_total"             — int — the attacker's already-rolled attack
##                                total (Parry).
##   "damage_raw"             — int — the already-rolled raw damage (Block).
##   "hp_current"             — int — the reactor's current hp (Block).
##
## Domain purity boundary (ADR-001): extends RefCounted only (via
## ReactionChooserPort) — no Node/Control/SceneTree inheritance. Lives in
## infrastructure/ (an adapter) since it implements the ReactionChooserPort
## seam and is bound to it only at the composition root (MainScene), per
## ADR-002 injection — never imported by core/ itself.
##
## Usage example:
##   var policy := AIReactionPolicy.new()
##   var choice: String = policy.choose(
##       ["dodge"], {"mobility": 1, "targeted_defense_value": 10}
##   )
##   # choice -> "dodge" (10+1=11 > 10)

class_name AIReactionPolicy
extends "res://core/application/ports/reaction_chooser_port.gd"

const MobilityDodgeRuleClass = preload("res://core/domain/mobility_dodge_rule.gd")
const DefenseMitigationCalculatorClass = preload("res://core/domain/defense_mitigation_calculator.gd")

## Lowercase reaction names — matches core/application/reaction_window.gd's
## REACTION_DODGE/REACTION_PARRY/REACTION_BLOCK constants (this file
## deliberately does not preload that class merely to reuse its String
## constants — reusing the literal values keeps this adapter dependency-free
## of the application layer, matching every other ReactionChooserPort
## implementation in this project).
const REACTION_DODGE: String = "dodge"
const REACTION_PARRY: String = "parry"
const REACTION_BLOCK: String = "block"


## choose(legal_reactions, context) -> String — see class-level doc for the
## full priority-ordered rule set. Never rolls RNG, never mutates
## `legal_reactions`/`context`, and always returns either one of
## `legal_reactions`' own entries or ReactionChooserPort.PASS.
func choose(legal_reactions: Array, context: Dictionary) -> String:
	if legal_reactions.has(REACTION_DODGE):
		var mobility: int = context.get("mobility", 0)
		var targeted_defense_value: int = context.get("targeted_defense_value", 0)
		if MobilityDodgeRuleClass.dodge_worthwhile(mobility, targeted_defense_value):
			return REACTION_DODGE

	if legal_reactions.has(REACTION_PARRY):
		var parry_attack_bonus: int = context.get("parry_attack_bonus", 0)
		var parry_bonus: int = context.get("parry_bonus", 0)
		var roll_total: int = context.get("roll_total", 0)
		if DefenseMitigationCalculatorClass.parry_worthwhile(parry_attack_bonus, parry_bonus, roll_total):
			return REACTION_PARRY

	if legal_reactions.has(REACTION_BLOCK):
		var damage_raw: int = context.get("damage_raw", 0)
		var hp_current: int = context.get("hp_current", 1)
		if DefenseMitigationCalculatorClass.block_worthwhile(damage_raw, hp_current):
			return REACTION_BLOCK

	return PASS
