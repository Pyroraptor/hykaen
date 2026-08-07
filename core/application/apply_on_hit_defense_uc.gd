## core/application/apply_on_hit_defense_uc.gd — ApplyOnHitDefenseUseCase
## (FEAT-002 / US-001, ADR-001)
##
## Application layer (Clean Architecture): PHASE 2 of the ADR-001 two-phase
## Strike-resolution split — the counterpart to core/application/
## resolve_to_hit_uc.gd's ResolveToHitUseCase. Given the partial ToHitResult
## Dictionary a to-hit-phase call already produced (roll_total, damage_raw,
## hit, crit, defense_value, defense_type, weapon, ...) and the reactor's
## chosen on-hit mitigation (Block/Parry/none — Dodge/Steel are PRE-hit and
## are never passed here), this use case:
##
##   1. Runs core/rules/resolution.gd's Resolution.apply_on_hit_defense() —
##      via the SAME Resolution instance the to-hit phase used (see
##      resolve_to_hit_uc.gd's get_resolution() doc; ADR-002 RNG-sequence
##      sharing) — to compute the FINAL, post-mitigation damage. This is the
##      fix for the Iteration J defect this feature exists to close: a
##      caller that only ever read a to-hit phase's damage_raw and skipped
##      this step would apply UNMITIGATED damage, silently making Parry/
##      Block no-ops.
##   2. Commits target.hp_current -= final_damage (the ONLY place this two-
##      phase split ever mutates HP).
##   3. Emits exactly one RoundEvents.AttackBroadcast via EventSinkPort, carrying
##      the FINAL (post-mitigation) damage — never the raw, pre-mitigation
##      value.
##   4. Emits RoundEvents.CombatantDefeatedEvent via EventSinkPort IFF
##      target.hp_current <= 0 AFTER mitigation was applied — never from the
##      to-hit phase (which never touches HP at all), and never for a
##      pre-mitigation-lethal hit that Parry/Block reduced back to a
##      survivable amount (the "lethal-but-parried" invariant).
##
## Depends on: an injected Resolution instance (NEVER constructs its own —
## always the SAME instance the to-hit phase used) and an EventSinkPort
## (core/application/event_sink_port.gd). Domain purity boundary (ADR-001):
## extends RefCounted only — no Node/Control/SceneTree inheritance.
##
## FEAT-005 (US-005): the ONLY hp mutation in this file — historically an
## inline `target.take_damage(damage_final)` / `target["hp_current"] -= ...`
## call at step 2 above — is now routed through the SAME domain EffectsApplier
## seam (core/domain/effects_applier.gd) core/application/
## resolve_action_use_case.gd's Strike path (_finalize_strike_result())
## already routes its own damage through (FEAT-004): a DamageEffect is
## constructed from the resolved `damage_final` and handed to
## EffectsApplier.apply(). This is the "enemy on-hit reaction flows through
## the same Effects Applier" requirement the steel thread's design notes
## document — no parallel/duplicate mutation path exists any more (see
## ci/check_no_duplicate_seams.sh check #4, which historically excluded this
## file as a documented legacy take_damage() caller pending exactly this
## retrofit).
##
## Usage example — see core/application/resolve_to_hit_uc.gd's file-level doc
## for the full two-phase call sequence this class is the second half of.

class_name ApplyOnHitDefenseUseCase
extends RefCounted

const RoundEventsClass     = preload("res://core/rules/round_events.gd")
const ResolutionClass      = preload("res://core/rules/resolution.gd")
const CombatantClass       = preload("res://core/domain/combatant.gd")
const DamageEffectClass    = preload("res://core/domain/effects/damage_effect.gd")
const EffectsApplierClass  = preload("res://core/domain/effects_applier.gd")


var _resolution       ## Resolution — the SAME instance the to-hit phase
## used (injected; see resolve_to_hit_uc.gd's ResolveToHitUseCase.get_resolution()).
var _event_sink_port   ## EventSinkPort — injected; every AttackEvent/
## CombatantDefeatedEvent this use case emits goes through this SAME sink.
var _effects_applier   ## EffectsApplier (core/domain/effects_applier.gd,
## FEAT-005/US-005) — the SAME domain seam core/application/
## resolve_action_use_case.gd's Strike path (_finalize_strike_result())
## routes every resolved Strike's damage through — see
## ResolveActionUseCase.get_effects_applier(), which hands its own single
## instance in via this class's _init() below. Defaults to a fresh
## EffectsApplier() instance when no instance is injected (e.g. this file's
## own GUT suite, tests/application/test_apply_on_hit_defense_uc.gd's 2-arg
## _rig()) — EffectsApplier is a pure, stateless domain service
## (core/domain/effects_applier.gd's own file-level doc), so a standalone
## instance behaves byte-for-byte identically to a shared one; the
## constructor injection point exists so production wiring
## (ResolveActionUseCase._init()) can hand in the literal SAME instance
## Strike's own damage routes through — never a second, independently
## constructed EffectsApplier.


## _init(resolution, event_sink_port, effects_applier) — stores the injected
## collaborators. `resolution` MUST be the SAME Resolution instance
## ResolveToHitUseCase.get_resolution() returned for THIS Strike (ADR-002 RNG
## sequencing — the Block/Parry roll(s) below must continue the identical
## seeded RNG sequence the to-hit phase already started) — never a fresh
## Resolution constructed here. `effects_applier` is OPTIONAL (FEAT-005/
## US-005) — when omitted (or explicitly null), a fresh EffectsApplier()
## instance is constructed; a caller holding Strike's own EffectsApplier
## instance (ResolveActionUseCase.get_effects_applier()) should pass it in
## directly so both damage paths route through the identical instance.
func _init(resolution, event_sink_port, effects_applier = null) -> void:
	_resolution      = resolution
	_event_sink_port = event_sink_port
	_effects_applier = effects_applier if effects_applier != null else EffectsApplierClass.new()


## get_effects_applier() -> EffectsApplier — FEAT-005 (US-005): exposes the
## EffectsApplier instance this use case routes damage through, so a test (or
## a caller wiring another use case to share it) can confirm/obtain the
## identical instance/module Strike's own damage path uses.
func get_effects_applier():
	return _effects_applier


## legal_onhit_reactions(weapon) -> Array — iteration K FEAT-004 (US-004,
## ADR-004): the OnHitMitigation-window sibling of core/application/
## resolve_to_hit_uc.gd's legal_prehit_reactions() — returns the SUBSET of
## ["parry", "block"] the REACTOR's own `weapon` Dictionary is currently
## eligible for, computed via the SAME core/rules/resolution.gd static
## predicates (is_parry_eligible()/is_block_eligible())
## core/application/reaction_window.gd's _compute_legal_reactions()
## "OnHitMitigation" branch already uses — never a re-derived rule. Consumed
## by core/application/resolve_action_use_case.gd's resolve_reactive() (this
## feature) to build the `legal_reactions` argument
## core/application/open_reaction_window_use_case.gd's OpenReactionWindowUseCase.
## open() expects for the ON-HIT ask — never Dodge/Steel (those are
## PRE-hit-only, see legal_prehit_reactions()). The caller is responsible for
## the eligibility gate's OTHER two preconditions (the attack actually hit,
## and no reaction was already spent earlier this Strike) BEFORE ever calling
## this method — mirrors core/rules/resolution.gd's is_on_hit_mitigation_eligible()
## style split (this method only ever answers "which weapon-driven reactions
## exist", never "is a window allowed to open at all").
##
## weapon — the REACTOR's (defender's) own weapon Dictionary (NOT the
##          attacker's weapon).
func legal_onhit_reactions(weapon: Dictionary) -> Array:
	var legal: Array = []
	if ResolutionClass.is_parry_eligible(weapon):
		legal.append("parry")
	if ResolutionClass.is_block_eligible(weapon):
		legal.append("block")
	return legal


## apply(partial, attacker, target, on_hit_defense, ctx, round_number,
##       actor_updated_action_budget) -> Dictionary
##
## partial          — the Dictionary a to-hit-phase call (ResolveToHitUseCase.
##                     resolve_to_hit() / Resolution.resolve_to_hit()) already
##                     produced for THIS Strike.
## attacker, target  — the same combatant Dictionaries the to-hit phase was
##                     called with. target.hp_current is committed here — the
##                     ONLY mutation this two-phase split ever performs.
## on_hit_defense    — String, one of "none" | "block" | "parry" — the
##                     ON-HIT reaction to attempt. Dodge/Steel are ON-ATTACKED
##                     and are never passed here (they were already resolved
##                     inside the to-hit phase's `pre_hit_defense` argument).
## ctx               — the DefenseContext Dictionary (e.g. "blocking_weapon",
##                     "blocking_weapon_tier", "parrying_weapon",
##                     "action_economy" — see Resolution.apply_on_hit_defense()'s
##                     own contract for the full shape).
## round_number      — stamped onto the emitted AttackEvent /
##                     CombatantDefeatedEvent.
## actor_updated_action_budget — OPTIONAL {remaining, spent} snapshot of the
##                     ACTING combatant's ActionBudget, forwarded onto the
##                     emitted AttackEvent verbatim; defaults to null (matches
##                     RoundEvents.AttackBroadcast's own default) when the caller
##                     does not supply one.
##
## On a MISS (partial.hit == false): Resolution.apply_on_hit_defense() is
## NEVER invoked (its own documented precondition — Block/Parry are ON-HIT-
## only reactions) — damage_final stays 0 regardless of `on_hit_defense`, no
## HP is committed, and the emitted AttackEvent simply reports hit:false,
## damage_final:0 (mirrors the pre-existing single-phase
## resolve_action_use_case.gd contract for a miss).
##
## Returns Dictionary:
##   "damage_final"           — int, the FINAL post-mitigation damage
##                               actually committed to target.hp_current.
##   "active_defense_applied" — String — "block" | "parry" | whatever the
##                               to-hit phase already recorded (e.g. "dodge"/
##                               "steel"/"none") when on_hit_defense is "none".
##   "on_hit_suppressed"      — bool.
##   "defender_defeated"      — bool — true iff target.hp_current <= 0 AFTER
##                               this commit (never before mitigation).
##   "event"                  — the emitted RoundEvents.AttackBroadcast instance.
func apply(
	partial: Dictionary,
	attacker,
	target,
	on_hit_defense: String = "none",
	ctx: Dictionary = {},
	round_number: int = 0,
	actor_updated_action_budget = null
) -> Dictionary:
	var damage_final: int = 0
	var active_defense_applied: String = partial.get("active_defense_applied", "none")
	var on_hit_suppressed: bool = false

	# Block/Parry are ON-HIT-only reactions (Resolution.apply_on_hit_defense()'s
	# own documented precondition) — only ever invoke it on an actual hit; a
	# miss has nothing to mitigate and damage_final correctly stays 0.
	if partial.get("hit", false):
		var post: Dictionary = _resolution.apply_on_hit_defense(partial, on_hit_defense, ctx)
		damage_final           = post.get("damage_final", 0)
		active_defense_applied = post.get("active_defense_applied", active_defense_applied)
		on_hit_suppressed      = post.get("on_hit_suppressed", false)

	# ── The ONLY hp mutation in this entire two-phase split — routed
	# through the SAME EffectsApplier seam Strike's ResolveActionUseCase
	# uses (FEAT-005/US-005), never an inline hp_current mutation. A
	# DamageEffect is constructed from the resolved damage_final and
	# dispatched via _effects_applier.apply(), which mutates the live
	# Combatant entity BY REFERENCE (Combatant.take_damage()), so the hit
	# persists on the same instance the container holds — identical
	# end-observable behavior to the historical inline call, but now
	# funneled through the single domain mutation seam
	# ci/check_no_duplicate_seams.sh's EffectsApplier check (#4) requires.
	if damage_final > 0:
		if target is CombatantClass:
			var target_id: String = target.display_id()
			var damage_effect = DamageEffectClass.new(target_id, damage_final)
			_effects_applier.apply([damage_effect], {target_id: target})
		else:
			# Dict-tolerant shim (mirrors resolve_action_use_case.gd's
			# _finalize_strike_result() identically-purposed fallback):
			# EffectsApplier/DamageEffect require a real Combatant instance
			# (display_id(), take_damage() are Combatant methods) — a
			# caller still handing a plain Dictionary falls back to the
			# legacy direct-mutation path instead of crashing.
			target["hp_current"] = target.get("hp_current", 0) - damage_final

	var attack_event = RoundEventsClass.AttackBroadcast.new(
		round_number,
		attacker.name,
		target.name,
		partial.get("roll_total", 0),
		partial.get("defense_type", "ac"),
		partial.get("defense_value", 0),
		partial.get("hit", false),
		partial.get("crit", false),
		damage_final,
		actor_updated_action_budget
	)
	_event_sink_port.emit(attack_event)

	# ── CombatantDefeatedEvent: gated STRICTLY on hp_current <= 0 AFTER
	# mitigation. Never evaluated against damage_raw/pre-mitigation state —
	# this is the "lethal-but-parried" invariant test_criteria pins. ────────
	var defender_defeated: bool = target.hp_current <= 0
	if defender_defeated:
		var defeated_event = RoundEventsClass.CombatantDefeatedEvent.new(
			round_number, target.name, attacker.name, target.combatant_id
		)
		_event_sink_port.emit(defeated_event)

	return {
		"damage_final":           damage_final,
		"active_defense_applied": active_defense_applied,
		"on_hit_suppressed":      on_hit_suppressed,
		"defender_defeated":      defender_defeated,
		"event":                  attack_event,
	}
