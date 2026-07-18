extends GutTest
## core/application/tests/test_round_session_reaction_window.gd
##
## GUT suite for FEAT-003 (US-002 / FR-002, G3 remediation): proves
## core/application/round_session.gd's advance_ai_turn() genuinely AWAITS the
## on-hit ("OnHitMitigation") reaction window BETWEEN the two phases FEAT-002
## established (core/application/resolve_to_hit_uc.gd /
## core/application/apply_on_hit_defense_uc.gd) and passes the resolved
## reaction into the apply phase -- replacing the prior trace-only stub
## (previously ~round_session.gd lines 1141-1167) that asked for a choice and
## then silently discarded it, leaving damage unmitigated regardless of what
## was chosen.
##
## Unlike core/application/tests/test_round_session_two_phase_wiring.gd
## (which already proved the reaction-window FIRING ORDER never stalls), this
## suite proves the resolved choice actually CHANGES the committed outcome:
##   - a successful Parry/Block genuinely reduces the final damage committed
##     to target.hp_current (per Resolution.apply_on_hit_defense()'s FR-001
##     mitigation formula), not merely asked-about-and-discarded.
##   - Pass reproduces the unmitigated raw damage byte-for-byte.
##   - a lethal-but-parried hit never defeats the target (the CombatantDefeatedEvent
##     gate remains strictly post-mitigation).
##   - the shared <=1-reaction-per-Strike budget-delta gate
##     (ReactionWindowClass.assert_reaction_budget_delta(),
##     round_session.get_reaction_budget_violations()) genuinely observes a
##     second reaction-window spend for the SAME eligible window and flags/
##     records it -- never silently allows it -- now that the two-phase path
##     actually spends a reaction at all (under the old trace-only stub this
##     path never spent anything, so this gate was previously unreachable
##     here).

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const ReactionWindowClass          = preload("res://core/application/reaction_window.gd")
const RoundEventsClass             = preload("res://core/rules/round_events.gd")
const AIClass                      = preload("res://core/combat/ai.gd")


# ── Fake/double port implementations (mirrors core/application/tests/
#    test_round_session_two_phase_wiring.gd's established convention) ──────

class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(_dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


## ScriptedTwoPhaseResolver -- a single ReactionResolverPort double injected
## into BOTH the PreHitAvoidance and OnHitMitigation seams, answering with a
## fixed choice per trigger_type.
class ScriptedTwoPhaseResolver:
	extends RefCounted

	var choice_for_trigger_type: Dictionary = {}
	var call_order: Array = []

	func resolve(trigger: Dictionary) -> Dictionary:
		var trigger_type: String = trigger.get("trigger_type", "")
		call_order.append(trigger_type)
		return {"choice": choice_for_trigger_type.get(trigger_type, "none")}


## RogueDoubleSpendResolver -- simulates "a second reaction-window invocation
## for the same eligible window": when asked for OnHitMitigation, it FIRST
## spends a reaction directly off the reactor's own live ActionEconomy (as if
## some other, buggy call path had already independently resolved a second
## on-hit window for this exact Strike) and THEN answers "parry" as normal --
## so the legitimate apply_on_hit_defense_uc.apply() call spends a SECOND time
## through the ordinary ctx.action_economy path. Two spends for one Strike is
## exactly the contract violation ReactionWindowClass.assert_reaction_budget_delta()
## exists to catch.
class RogueDoubleSpendResolver:
	extends RefCounted

	var _reactor_action_economy
	var call_order: Array = []

	func _init(reactor_action_economy) -> void:
		_reactor_action_economy = reactor_action_economy

	func resolve(trigger: Dictionary) -> Dictionary:
		var trigger_type: String = trigger.get("trigger_type", "")
		call_order.append(trigger_type)
		if trigger_type == "OnHitMitigation":
			_reactor_action_economy.spend_reaction()
			return {"choice": "parry"}
		return {"choice": "none"}


func _entry(combatant, action_economy = null) -> Dictionary:
	return {"combatant": combatant, "action_economy": action_economy if action_economy != null else ActionEconomyClass.new()}


const CombatantClass = preload("res://core/domain/combatant.gd")

## _attacker() -- the enemy (Bravo). roll_total = raw_d20 + strength(3) +
## proficiency_bonus(2) = raw_d20 + 5.
func _attacker():
	return CombatantClass.from_dict({
		"name":         "Bravo",
		"combatant_id": "bravo",
		"hp_current":   2000,
		"ac":           10,
		"strength":     3,
		"_is_enemy":    true,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6,
		},
	})


## _defender(hp_current) -- the player (Alpha). Carries a weapon eligible for
## BOTH Parry (parry_bonus 3) and Block (block_value 2).
func _defender(hp_current: int = 2000):
	return CombatantClass.from_dict({
		"name":         "Alpha",
		"combatant_id": "alpha",
		"hp_current":   hp_current,
		"hp_max":       2000,
		"ac":           10,
		"conscious":    true,
		"conditions":   [],
		"skills":       {"mobility": 1, "determination": 1},
		"_is_enemy":    false,
		"weapon": {
			"damage_modifier_attribute": "dexterity",
			"proficiency_bonus": 0,
			"damage_die": 6,
			"parry_bonus": 3,
			"block_value": 2,
		},
	})


func _make_session(entries: Array, party: Array, enemies: Array, random_number_port) -> Dictionary:
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var event_sink_port    = FakeEventSinkPort.new()
	var round_history_port = FakeRoundHistoryPort.new()

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, AIClass.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	var session = run_round_use_case.begin_round(1, party, enemies)
	return {"session": session, "history": round_history_port, "event_sink": event_sink_port}


# ══════════════════════════════════════════════════════════════════════════
# A resolved Parry/Block choice must GENUINELY reduce the damage committed --
# not merely be asked about and discarded (the G3 remediation this feature
# fixes).
# ══════════════════════════════════════════════════════════════════════════

func test_successful_parry_reduces_committed_damage_to_zero_per_mitigation_formula() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# attack_d20=10 -> roll_total=10+strength(3)+prof(2)=15, hits ac(10).
	# damage_die=6 -> damage_raw=6+strength(3)=9.
	# parry_d20=13 -> parry_roll=13+parry_bonus(3)=16, STRICTLY exceeds 15 -> Parry SUCCEEDS.
	var rng := ScriptedRandomNumberPort.new([10, 6, 13])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var hp_before: int = alpha.get("hp_current", 0)

	var resolver := ScriptedTwoPhaseResolver.new()
	resolver.choice_for_trigger_type["PreHitAvoidance"] = "none"
	resolver.choice_for_trigger_type["OnHitMitigation"] = "parry"
	session.set_prehit_avoidance_resolver_fn(Callable(resolver, "resolve"))
	session.set_onhit_mitigation_resolver_fn(Callable(resolver, "resolve"))

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false))
	var attack_event = rig["event_sink"].events[0]
	assert_true(attack_event.hit, "fixture assumption: the scripted roll must hit")
	assert_eq(attack_event.damage_final, 0, "a successful Parry must reduce the committed final damage to 0 (FR-001 mitigation formula)")
	assert_eq(alpha.get("hp_current", 0), hp_before, "Alpha must take ZERO damage once a successful Parry is GENUINELY applied")


func test_block_reduces_committed_damage_by_the_mitigation_formula_not_to_raw() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# attack_d20=10 -> roll_total=15, hits ac(10). damage_die=6 -> damage_raw=9.
	# block_reduction_die=1 -> block_reduction=1+block_value(2)=3 -> damage_final=max(0,9-3)=6.
	var rng := ScriptedRandomNumberPort.new([10, 6, 1])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var hp_before: int = alpha.get("hp_current", 0)

	var resolver := ScriptedTwoPhaseResolver.new()
	resolver.choice_for_trigger_type["PreHitAvoidance"] = "none"
	resolver.choice_for_trigger_type["OnHitMitigation"] = "block"
	session.set_prehit_avoidance_resolver_fn(Callable(resolver, "resolve"))
	session.set_onhit_mitigation_resolver_fn(Callable(resolver, "resolve"))

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false))
	var attack_event = rig["event_sink"].events[0]
	assert_true(attack_event.hit, "fixture assumption: the scripted roll must hit")
	assert_eq(attack_event.damage_final, 6, "Block must reduce committed damage per FR-001's formula: raw(9) - reduction(3) = 6")
	assert_ne(attack_event.damage_final, 9, "the mitigated damage must differ from the raw damage -- proving Block genuinely changed the outcome, not a no-op")
	assert_eq(hp_before - alpha.get("hp_current", 0), 6, "Alpha must take exactly the MITIGATED amount, never the raw amount")


func test_pass_choice_leaves_full_unmitigated_raw_damage_committed() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# attack_d20=10 -> roll_total=15, hits ac(10). damage_die=6 -> damage_raw=6+3=9.
	# No RNG draw for on-hit mitigation at all -- Pass never invokes
	# Resolution.apply_on_hit_defense()'s block/parry branches.
	var rng := ScriptedRandomNumberPort.new([10, 6])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var hp_before: int = alpha.get("hp_current", 0)

	var resolver := ScriptedTwoPhaseResolver.new()
	resolver.choice_for_trigger_type["PreHitAvoidance"] = "none"
	resolver.choice_for_trigger_type["OnHitMitigation"] = "none"
	session.set_prehit_avoidance_resolver_fn(Callable(resolver, "resolve"))
	session.set_onhit_mitigation_resolver_fn(Callable(resolver, "resolve"))

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false))
	var attack_event = rig["event_sink"].events[0]
	assert_true(attack_event.hit, "fixture assumption: the scripted roll must hit")
	assert_eq(attack_event.damage_final, 9, "Pass must reproduce the exact raw/unmitigated damage byte-for-byte")
	assert_eq(hp_before - alpha.get("hp_current", 0), 9, "Alpha must take the full raw damage when Pass is chosen")


# ══════════════════════════════════════════════════════════════════════════
# Lethal-but-parried invariant: CombatantDefeatedEvent is gated STRICTLY on
# hp_current <= 0 AFTER mitigation -- never on the pre-mitigation raw damage.
# ══════════════════════════════════════════════════════════════════════════

func test_lethal_but_parried_hit_never_defeats_the_target_or_emits_a_defeated_event() -> void:
	var bravo: Dictionary = _attacker()
	# Alpha starts at 1 HP -- ANY unmitigated hit from Bravo's weapon
	# (damage_die 6, +strength 3 => at least 4 raw) would be lethal.
	var alpha: Dictionary = _defender(1)
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# attack_d20=10 -> roll_total=15, hits ac(10). damage_die=6 -> damage_raw=9
	# (would be lethal against Alpha's 1 HP if unmitigated).
	# parry_d20=13 -> parry_roll=16 > 15 -> Parry SUCCEEDS -> damage_final=0.
	var rng := ScriptedRandomNumberPort.new([10, 6, 13])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var resolver := ScriptedTwoPhaseResolver.new()
	resolver.choice_for_trigger_type["PreHitAvoidance"] = "none"
	resolver.choice_for_trigger_type["OnHitMitigation"] = "parry"
	session.set_prehit_avoidance_resolver_fn(Callable(resolver, "resolve"))
	session.set_onhit_mitigation_resolver_fn(Callable(resolver, "resolve"))

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false))
	assert_eq(alpha.get("hp_current", 0), 1, "a lethal-but-PARRIED hit must never reduce hp_current -- Alpha must survive at her pre-Strike HP")

	for event in rig["event_sink"].events:
		assert_false(
			event is RoundEventsClass.CombatantDefeatedEvent,
			"no CombatantDefeatedEvent may ever be emitted for a lethal-but-parried hit"
		)


# ══════════════════════════════════════════════════════════════════════════
# Budget gate: a second reaction-window invocation for the SAME eligible
# window must be flagged/recorded -- never silently allowed. (Previously, under
# the trace-only stub this feature fixes, the two-phase path never spent a
# reaction at all, so this gate was unreachable here; it is now genuinely live.)
# ══════════════════════════════════════════════════════════════════════════

func test_a_second_reaction_spend_for_the_same_eligible_window_is_flagged_by_the_budget_gate_not_silently_allowed() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var alpha_ae: ActionEconomyClass = ActionEconomyClass.new()
	var entries: Array = [_entry(bravo), _entry(alpha, alpha_ae)]

	var budget_before: int = alpha_ae.get_remaining()

	# attack_d20=10 -> roll_total=15, hits ac(10). damage_die=6 -> damage_raw=9.
	# parry_d20=13 -> parry_roll=16 > 15 -> Parry SUCCEEDS (the LEGITIMATE spend).
	var rng := ScriptedRandomNumberPort.new([10, 6, 13])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var prehit_resolver := ScriptedTwoPhaseResolver.new()
	prehit_resolver.choice_for_trigger_type["PreHitAvoidance"] = "none"
	session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))

	# RogueDoubleSpendResolver simulates a SECOND, illegitimate invocation of
	# the on-hit window for this SAME Strike spending an EXTRA reaction (as if
	# some other buggy call path re-opened it) on top of the legitimate spend
	# apply_on_hit_defense_uc.apply() performs for the "parry" choice it
	# returns -- two spends total for one Strike.
	var onhit_resolver := RogueDoubleSpendResolver.new(alpha_ae)
	session.set_onhit_mitigation_resolver_fn(Callable(onhit_resolver, "resolve"))

	await session.advance_ai_turn()

	var budget_after: int = alpha_ae.get_remaining()
	assert_eq(budget_before - budget_after, 2, "fixture: the rogue double-invocation must genuinely spend TWO reactions for this one Strike")

	assert_false(
		session.get_reaction_budget_violations().is_empty(),
		"a double-spend within the SAME eligible reaction window must be FLAGGED/RECORDED by the shared budget-delta gate, never silently allowed"
	)
	var violation: Dictionary = session.get_reaction_budget_violations()[0]
	assert_eq(violation.get("delta", -1), 2, "the recorded violation must carry the actual observed delta (2), proving the gate genuinely measured the double-spend rather than a placeholder")

	assert_false(
		ReactionWindowClass.assert_reaction_budget_delta(2, "regression-proof"),
		"ReactionWindowClass.assert_reaction_budget_delta() itself must report false (a rejection) for a delta of 2 -- it must never silently report success for a second invocation of the same eligible window"
	)
