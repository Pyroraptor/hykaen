## infrastructure/ai_reaction_policy.gd — AIReactionPolicy (FEAT-002 / US-002;
## RESERVE gate: iteration K FEAT-003 / US-003, ADR-003;
## Opportunistic Strike branch: iteration K FEAT-225, resolves DEF-001)
##
## Infrastructure/adapter layer (Clean Architecture): a deterministic,
## RNG-free implementation of core/application/ports/reaction_chooser_port.gd's
## ReactionChooserPort contract — the enemy AI's actual reaction "brain" for
## Dodge/Parry/Block/Opportunistic Strike. This is a NEW, INDEPENDENT ReactionChooserPort
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
## Opportunistic Strike (iteration K FEAT-225, resolves DEF-001): a
## standalone OpportunisticStrike-window rule, evaluated ahead of the
## Dodge/Parry/Block priority chain above (inert in practice, since
## reaction_window.gd never offers "opportunistic_strike" alongside
## dodge/parry/block in the same legal_reactions list — see this file's own
## choose() comment for detail):
##
##   0. Opportunistic Strike — chosen when "opportunistic_strike" is offered
##      (legal_reactions) AND context["melee_reach"] is true, subject to the
##      SAME RESERVE gate below (a Stride by either side can trigger this
##      window; FR-005 exit criterion "a Stride by either side"). No
##      worthwhileness calculus beyond melee-legality — mirrors the existing
##      reserve-gate pattern already applied to Dodge/Parry/Block, per this
##      feature's design notes.
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
##   "action_current"         — int — the reactor's CURRENT shared per-round
##                                action budget (core/rules/action_economy.gd's
##                                ActionEconomy.get_remaining()), consulted by
##                                the RESERVE gate below (iteration K FEAT-003
##                                / US-003, ADR-003). Defaults to
##                                ActionEconomy.MAX_BUDGET (a full, unspent
##                                budget) when omitted, so callers that never
##                                populate this key (e.g. every pre-FEAT-003
##                                test) observe the gate as a no-op and see
##                                unchanged Dodge/Parry/Block/Pass behavior.
##   "melee_reach"            — bool — true iff the reactor's weapon has
##                                melee reach (Opportunistic Strike; iteration
##                                K FEAT-225). Defaults to false when omitted,
##                                so callers that never populate this key
##                                observe an offered "opportunistic_strike"
##                                as declined (Pass) rather than silently
##                                assumed melee-legal.
##
## Budget-aware RESERVE gate (iteration K FEAT-003 / US-003, ADR-003) —
## applies to BOTH windows this policy ever answers for (PreHitAvoidance
## Dodge; OnHitMitigation Parry/Block): reacting always costs exactly one
## action via ActionEconomy.spend_reaction(), so choose() forces PASS
## whenever action_current - 1 < ActionEconomyClass.RESERVE — i.e. whenever
## reacting would leave the reactor with fewer than RESERVE (>=1) actions
## for its own next turn — BEFORE ever evaluating the Dodge/Mobility, Parry,
## or Block rules below. This is checked FIRST and unconditionally: even a
## legal, worthwhile Dodge/Parry/Block is downgraded to Pass once the
## reserve would be broken. No RNG, no mutation of `context` — purely a
## read of context["action_current"] against the single authoritative
## ActionEconomyClass.RESERVE constant (never a re-derived/duplicated
## literal here).
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
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")

## Lowercase reaction names — matches core/application/reaction_window.gd's
## REACTION_DODGE/REACTION_PARRY/REACTION_BLOCK constants (this file
## deliberately does not preload that class merely to reuse its String
## constants — reusing the literal values keeps this adapter dependency-free
## of the application layer, matching every other ReactionChooserPort
## implementation in this project).
const REACTION_DODGE: String = "dodge"
const REACTION_PARRY: String = "parry"
const REACTION_BLOCK: String = "block"
const REACTION_OPPORTUNISTIC_STRIKE: String = "opportunistic_strike"


## choose(legal_reactions, context) -> String — see class-level doc for the
## full priority-ordered rule set. Never rolls RNG, never mutates
## `legal_reactions`/`context`, and always returns either one of
## `legal_reactions`' own entries or ReactionChooserPort.PASS.
func choose(legal_reactions: Array, context: Dictionary) -> String:
	# Budget-aware RESERVE gate (iteration K FEAT-003 / US-003, ADR-003):
	# checked FIRST, before any Dodge/Parry/Block rule is evaluated, and
	# applies uniformly to whichever window (PreHitAvoidance or
	# OnHitMitigation) this call represents. Reacting always spends exactly
	# one action; forcing Pass here guarantees the reactor never reacts
	# itself down to zero actions for its own next turn.
	var action_current: int = context.get("action_current", ActionEconomyClass.MAX_BUDGET)
	if action_current - 1 < ActionEconomyClass.RESERVE:
		return PASS

	# Opportunistic Strike (iteration K FEAT-225 / DEF-001): reaction_window.gd
	# only ever offers "opportunistic_strike" on its own, standalone
	# OpportunisticStrike trigger_type (never combined with dodge/parry/block
	# in the same legal_reactions list), so this branch's position relative
	# to the Dodge/Parry/Block branches below is inert in practice -- it is
	# placed first purely because it answers a different reaction window.
	# Melee-legality has ALREADY been screened upstream by
	# core/domain/opportunistic_strike_eligibility.gd's OpportunisticStrikeEligibility
	# (resolve_stride_use_case.gd, before a window is ever opened) AND by
	# reaction_window.gd's own "melee_reach" gate before "opportunistic_strike"
	# is ever added to `legal_reactions`; this policy re-confirms the same
	# context["melee_reach"] flag (mirroring the Dodge/Parry/Block branches'
	# own pattern of reading their governing context key directly rather than
	# trusting legal_reactions membership alone) and, since the RESERVE gate
	# above has already passed, takes the strike deterministically -- no
	# further worthwhileness calculus, matching this feature's design notes
	# ("take the strike when melee-legal and the >=1-action reserve gate
	# allows it, else Pass").
	if legal_reactions.has(REACTION_OPPORTUNISTIC_STRIKE):
		var melee_reach: bool = context.get("melee_reach", false)
		if melee_reach:
			return REACTION_OPPORTUNISTIC_STRIKE

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
