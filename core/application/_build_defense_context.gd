## core/application/_build_defense_context.gd — BuildDefenseContext
## (iteration K FEAT-004 / US-004, ADR-004)
##
## Application layer (Clean Architecture): a small, STATIC, side-effect-free
## helper that computes the DefenseContext Dictionary core/rules/resolution.gd's
## resolve_to_hit()/apply_on_hit_defense() expect as their trailing `ctx`
## argument, GENERICALLY for any defender Dictionary — never re-deriving
## eligibility/math itself (that remains resolution.gd's/the domain layer's
## exclusive job). Depends only on the defender's own combatant Dictionary and
## its live ActionEconomy (core/rules/action_economy.gd) — never an
## infrastructure/adapter type.
##
## Mirrors core/application/round_session.gd's private
## `_build_defense_context(target, target_action_economy)` method byte-for-byte
## for its `build()` entry point below (that pre-existing method is NOT
## modified/replaced by this feature — round_session.gd is out of this
## feature's file scope; this is a NEW, independent, reusable copy of the SAME
## computation for the player-Strikes-enemy path, extracted so a future pass
## could delegate round_session.gd's own copy to this one without touching
## resolve_action_use_case.gd's contract). Consumed by
## core/application/resolve_action_use_case.gd's resolve_reactive() (FEAT-004)
## to build BOTH:
##   1. the DefenseContext handed to core/rules/resolution.gd's
##      resolve_to_hit()/apply_on_hit_defense() (parrying_weapon/
##      blocking_weapon/parry_attack_bonus/action_economy/
##      open_space_available) — build().
##   2. the `context` Dictionary handed to a ReactionChooserPort's choose()
##      (e.g. infrastructure/ai_reaction_policy.gd's AIReactionPolicy) —
##      build_prehit_context()/build_onhit_context(), which extend (1) with the
##      extra keys AIReactionPolicy's own documented contract reads
##      (mobility/targeted_defense_value/parry_bonus/roll_total/damage_raw/
##      hp_current/action_current).
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O, no RNG.
##
## Usage:
##   var ctx := BuildDefenseContext.build_prehit_context(target, target_ae, "ac")
##   var choice := chooser_port.choose(legal_reactions, ctx)

class_name BuildDefenseContext
extends RefCounted

const ActionEconomyClass = preload("res://core/rules/action_economy.gd")
const FlankingClass      = preload("res://core/rules/flanking.gd")


## build(target, target_action_economy) -> Dictionary — the DefenseContext
## value object core/rules/resolution.gd's resolve_to_hit()/
## apply_on_hit_defense() expect, resolved ENTIRELY from the DEFENDER's
## (`target`'s) own data. Mirrors core/application/round_session.gd's private
## _build_defense_context() byte-for-byte — see that method's own doc for the
## per-key rationale (never duplicated here a second, drifting way):
##   "action_economy"       — the defender's live ActionEconomy (may be null).
##   "parrying_weapon"      — the defender's own weapon Dictionary.
##   "parry_attack_bonus"   — d20 + the defender's own attribute modifier +
##                             weapon proficiency (an opposed ATTACK roll).
##   "blocking_weapon"      — the SAME weapon Dictionary (this project's
##                             combatant model carries only one weapon slot).
##   "open_space_available" — true (default-safe; no hex-grid adjacency query
##                             wired into this application-layer helper).
static func build(target: Dictionary, target_action_economy) -> Dictionary:
	var target_weapon: Dictionary = target.get("weapon", {})
	var parry_attribute: String = target_weapon.get("damage_modifier_attribute", "")
	var parry_attack_bonus: int = (
		int(target.get(parry_attribute, 0)) + int(target_weapon.get("proficiency_bonus", 0))
	)
	return {
		"action_economy":       target_action_economy,
		"parrying_weapon":      target_weapon,
		"parry_attack_bonus":   parry_attack_bonus,
		"blocking_weapon":      target_weapon,
		"open_space_available": true,
	}


## _action_current(target_action_economy) -> int — the defender's CURRENT
## shared per-round action budget (core/rules/action_economy.gd
## ActionEconomy.get_remaining()), or ActionEconomy.MAX_BUDGET (a full,
## unspent budget) when no ActionEconomy was supplied — mirrors
## infrastructure/ai_reaction_policy.gd's own documented default for its
## context["action_current"] key, so a caller that omits target_action_economy
## observes the RESERVE gate as a no-op rather than a spurious forced Pass.
static func _action_current(target_action_economy) -> int:
	if target_action_economy == null:
		return ActionEconomyClass.MAX_BUDGET
	return target_action_economy.get_remaining()


## build_prehit_context(attacker, target, target_action_economy, defense_type)
## -> Dictionary — build()'s output EXTENDED with the extra keys a
## ReactionChooserPort's choose() consults for a PreHitAvoidance (Dodge)
## decision, per infrastructure/ai_reaction_policy.gd's documented `context`
## contract:
##   "mobility"               — the defender's Mobility skill.
##   "targeted_defense_value" — the passive defense value (target[defense_type])
##                               this incoming attack will be resolved against,
##                               reduced by the Off-Guard bonus when applicable
##                               (mirrors core/rules/resolution.gd's
##                               resolve_to_hit() own defense_value derivation,
##                               computed here BEFORE the roll — this is a
##                               PRE-hit ask, so no roll_total/damage_raw exist
##                               yet).
##   "action_current"         — see _action_current() above (RESERVE gate).
static func build_prehit_context(target: Dictionary, target_action_economy, defense_type: String = "ac") -> Dictionary:
	var ctx: Dictionary = build(target, target_action_economy)
	var mobility: int = int(target.get("skills", {}).get("mobility", 0))
	var targeted_defense_value: int = int(target.get(defense_type, 0))
	if FlankingClass.OFF_GUARD_CONDITION in target.get("conditions", []):
		targeted_defense_value -= FlankingClass.OFF_GUARD_BONUS
	ctx["mobility"] = mobility
	ctx["targeted_defense_value"] = targeted_defense_value
	ctx["action_current"] = _action_current(target_action_economy)
	return ctx


## build_onhit_context(target, target_action_economy, to_hit_partial) ->
## Dictionary — build()'s output EXTENDED with the extra keys a
## ReactionChooserPort's choose() consults for an OnHitMitigation
## (Parry/Block) decision, per AIReactionPolicy's documented `context`
## contract:
##   "parry_bonus" — the defender's OWN weapon's parry_bonus (distinct from
##                    "parry_attack_bonus", the defender's attack-roll bonus).
##   "roll_total"  — the attacker's already-rolled attack total (from the
##                    to-hit phase's own result Dictionary — never re-rolled).
##   "damage_raw"  — the already-rolled raw damage (ditto).
##   "hp_current"  — the defender's current hit points.
##   "action_current" — see _action_current() above (RESERVE gate).
static func build_onhit_context(target: Dictionary, target_action_economy, to_hit_partial: Dictionary) -> Dictionary:
	var ctx: Dictionary = build(target, target_action_economy)
	ctx["parry_bonus"]   = target.get("weapon", {}).get("parry_bonus", 0)
	ctx["roll_total"]    = to_hit_partial.get("roll_total", 0)
	ctx["damage_raw"]    = to_hit_partial.get("damage_raw", 0)
	ctx["hp_current"]    = target.get("hp_current", 1)
	ctx["action_current"] = _action_current(target_action_economy)
	return ctx
