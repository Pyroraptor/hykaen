extends GutTest
## tests/application/test_resolve_action_use_case_resolve_reactive.gd
##
## GUT suite for iteration K FEAT-004 (US-004, ADR-004):
## core/application/resolve_action_use_case.gd's resolve_reactive() — the
## two-phase, reaction-ENABLED sibling of resolve() that opens the DEFENDER's
## PreHitAvoidance window before the to-hit roll and OnHitMitigation window
## after a hit, synchronously (no `await`), via an injected
## ReactionChooserPort — see that method's own file-level doc.
##
## Validates (test_criteria):
##   1. A null reaction_chooser_port produces the exact same unmitigated
##      outcome as resolve()'s own default "none" active_defense path.
##   2. A chosen, TRIGGERED PreHitAvoidance Dodge that SUCCEEDS negates the
##      hit (defender_stepped=true, damage_final=0) and spends exactly one
##      reaction from target_action_economy.
##   3. A chosen, TRIGGERED PreHitAvoidance Dodge that FAILS still hits, and
##      suppresses the OnHitMitigation window entirely (<=1 reaction per
##      Strike).
##   4. A chosen OnHitMitigation Parry genuinely reduces damage_final below
##      damage_raw, and spends exactly one reaction.
##   5. A Pass answer at both windows reproduces the fully unmitigated
##      outcome and spends zero reactions.
##   6. The RESERVE gate: a target with only 1 action remaining never
##      reacts, regardless of what the chooser would otherwise pick.
##   7. Determinism: two resolve_reactive() calls with identical scripted
##      RNG/chooser answers/fresh state produce identical results.
##   8. Only "Strike" engages the reaction machinery; any other action_name
##      falls back to the unmitigated path even with a chooser injected.

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")


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

	func roll(dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


## ScriptedChooser -- answers a PreHitAvoidance ask (legal_reactions contains
## "dodge"/"steel") with `prehit_answer` and an OnHitMitigation ask
## (legal_reactions contains "parry"/"block") with `onhit_answer`. Records
## every call it receives so a test can assert whether/how many times each
## window was actually consulted (each suite in this project owns its own
## doubles).
class ScriptedChooser:
	extends "res://core/application/ports/reaction_chooser_port.gd"

	var prehit_answer: String
	var onhit_answer: String
	var prehit_calls: Array = []
	var onhit_calls: Array = []

	func _init(p_prehit_answer: String = "none", p_onhit_answer: String = "none") -> void:
		prehit_answer = p_prehit_answer
		onhit_answer = p_onhit_answer

	func choose(legal_reactions: Array, context: Dictionary) -> String:
		if legal_reactions.has("dodge") or legal_reactions.has("steel"):
			prehit_calls.append({"legal_reactions": legal_reactions, "context": context})
			return prehit_answer
		onhit_calls.append({"legal_reactions": legal_reactions, "context": context})
		return onhit_answer


# ── Shared fixtures ──────────────────────────────────────────────────────────

func _attacker() -> Dictionary:
	return {
		"name":     "Attacker",
		"strength": 0,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 0, "damage_die": 6},
	}


func _target(overrides: Dictionary = {}) -> Dictionary:
	var target: Dictionary = {
		"name":       "Skeleton",
		"hp_current": 20,
		"ac":         10,
		"strength":   0,
		"skills":     {"mobility": 5},
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus":         0,
			"parry_bonus":               4,
			"block_value":               2,
			"damage_die":                6,
		},
	}
	for key in overrides:
		target[key] = overrides[key]
	return target


func _fresh_action_economy():
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	return ae


func _rig(values: Array) -> Dictionary:
	var rng = ScriptedRandomNumberPort.new(values)
	var event_sink = FakeEventSinkPort.new()
	var history = FakeRoundHistoryPort.new()
	var use_case = ResolveActionUseCaseClass.new(rng, event_sink, history)
	return {"use_case": use_case, "event_sink": event_sink, "history": history}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — a null chooser reproduces resolve()'s default unmitigated
# outcome byte-for-byte.
# ══════════════════════════════════════════════════════════════════════════

func test_null_chooser_produces_the_same_outcome_as_resolve_with_default_none() -> void:
	var rig_a: Dictionary = _rig([10, 4])
	var result_a: Dictionary = rig_a["use_case"].resolve_reactive(
		_attacker(), _fresh_action_economy(), _target(), "Strike", 1, 0, _fresh_action_economy(), null
	)

	var rig_b: Dictionary = _rig([10, 4])
	var result_b: Dictionary = rig_b["use_case"].resolve(
		_attacker(), _fresh_action_economy(), _target(), "Strike", 1, 0
	)

	assert_eq(result_a.get("damage_final"), result_b.get("damage_final"))
	assert_eq(result_a["event"].hit, result_b["event"].hit)
	assert_eq(result_a["event"].defense_value, result_b["event"].defense_value)
	assert_eq(result_a.get("reaction_choice"), "none")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — a successful Dodge negates the hit and spends one reaction.
# ══════════════════════════════════════════════════════════════════════════

func test_prehit_dodge_success_negates_the_hit_and_spends_one_reaction() -> void:
	# mob_roll(15)+mobility(5)=20; attack raw(5)+0+0=5 < 20 -> miss.
	var rig: Dictionary = _rig([15, 5])
	var target: Dictionary = _target()
	var target_ae = _fresh_action_economy()
	var chooser := ScriptedChooser.new("dodge", "none")

	var result: Dictionary = rig["use_case"].resolve_reactive(
		_attacker(), _fresh_action_economy(), target, "Strike", 1, 0, target_ae, chooser
	)

	assert_false(result["event"].hit, "a successful Dodge must negate the hit")
	assert_eq(result["damage_final"], 0)
	assert_true(result["defender_stepped"])
	assert_eq(result["reaction_choice"], "dodge")
	assert_eq(
		target_ae.get_remaining(), ActionEconomyClass.MAX_BUDGET - 1,
		"a triggered Dodge must spend exactly one reaction from the DEFENDER's own budget"
	)
	assert_eq(chooser.onhit_calls.size(), 0, "OnHitMitigation must never be asked once Dodge already negated the hit")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — a Dodge that FAILS still hits and suppresses OnHitMitigation.
# ══════════════════════════════════════════════════════════════════════════

func test_prehit_dodge_failure_still_hits_and_suppresses_onhit_mitigation() -> void:
	# mob_roll(1)+mobility(5)=6; attack raw(15)+0+0=15 >= 6 -> hit; damage roll(4)+0=4.
	var rig: Dictionary = _rig([1, 15, 4])
	var target: Dictionary = _target()
	var target_ae = _fresh_action_economy()
	var chooser := ScriptedChooser.new("dodge", "block")

	var result: Dictionary = rig["use_case"].resolve_reactive(
		_attacker(), _fresh_action_economy(), target, "Strike", 1, 0, target_ae, chooser
	)

	assert_true(result["event"].hit)
	assert_eq(result["damage_final"], 4, "a Dodge that FAILS must never suppress on-hit damage -- it was never asked")
	assert_eq(result["reaction_choice"], "dodge")
	assert_eq(
		chooser.onhit_calls.size(), 0,
		"the <=1-reaction-per-Strike budget invariant must suppress the OnHitMitigation ask once Dodge already triggered"
	)
	assert_eq(
		target_ae.get_remaining(), ActionEconomyClass.MAX_BUDGET - 1,
		"exactly one reaction must be spent for this Strike, never two"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — a successful Parry negates damage and spends one reaction.
# ══════════════════════════════════════════════════════════════════════════

func test_onhit_parry_success_negates_damage_and_spends_one_reaction() -> void:
	# attack raw(10)+0+0=10 >= ac(10) -> hit; damage roll(5)+0=5;
	# parry roll(15)+parry_attack_bonus(0)+parry_bonus(4)=19 > roll_total(10) -> succeeds.
	var rig: Dictionary = _rig([10, 5, 15])
	var target: Dictionary = _target()
	var target_ae = _fresh_action_economy()
	var chooser := ScriptedChooser.new("none", "parry")

	var result: Dictionary = rig["use_case"].resolve_reactive(
		_attacker(), _fresh_action_economy(), target, "Strike", 1, 0, target_ae, chooser
	)

	assert_true(result["event"].hit)
	assert_eq(result["damage_final"], 0, "a successful Parry must negate ALL raw damage")
	assert_true(result["on_hit_suppressed"])
	assert_eq(result["reaction_choice"], "parry")
	assert_eq(target_ae.get_remaining(), ActionEconomyClass.MAX_BUDGET - 1)
	assert_eq(chooser.prehit_calls.size(), 1, "PreHitAvoidance must still be asked first, even though it declined")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — declining every reaction reproduces the fully unmitigated
# outcome and spends nothing.
# ══════════════════════════════════════════════════════════════════════════

func test_pass_at_both_windows_reproduces_the_fully_unmitigated_outcome_and_spends_no_reaction() -> void:
	var rig: Dictionary = _rig([10, 5])
	var target: Dictionary = _target()
	var target_ae = _fresh_action_economy()
	var chooser := ScriptedChooser.new("none", "none")

	var result: Dictionary = rig["use_case"].resolve_reactive(
		_attacker(), _fresh_action_economy(), target, "Strike", 1, 0, target_ae, chooser
	)

	assert_eq(result["damage_final"], 5, "declining every reaction must leave the raw, unmitigated damage in place")
	assert_eq(result["reaction_choice"], "none")
	assert_eq(target_ae.get_remaining(), ActionEconomyClass.MAX_BUDGET, "declining every reaction must spend nothing")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 — the RESERVE gate forces Pass at both windows, defense-in-depth.
# ══════════════════════════════════════════════════════════════════════════

func test_reserve_gate_prevents_any_reaction_when_only_one_action_remains() -> void:
	var rig: Dictionary = _rig([10, 5])
	var target: Dictionary = _target()
	var target_ae = _fresh_action_economy()
	for _i in range(6):
		target_ae.spend_reaction()
	assert_eq(target_ae.get_remaining(), 1, "fixture assumption: exactly 1 action remains before this Strike")

	var chooser := ScriptedChooser.new("dodge", "block")
	var result: Dictionary = rig["use_case"].resolve_reactive(
		_attacker(), _fresh_action_economy(), target, "Strike", 1, 0, target_ae, chooser
	)

	assert_eq(result["damage_final"], 5, "the RESERVE gate must force Pass at both windows once reacting would leave 0 actions")
	assert_eq(target_ae.get_remaining(), 1, "the RESERVE gate must spend nothing")
	assert_eq(chooser.prehit_calls.size(), 0, "chooser.choose() must never be invoked once the RESERVE gate has already forced Pass")
	assert_eq(chooser.onhit_calls.size(), 0)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 7 — determinism across two independent, identically-scripted runs.
# ══════════════════════════════════════════════════════════════════════════

func test_resolve_reactive_is_deterministic_across_two_runs_with_identical_inputs() -> void:
	var rig_a: Dictionary = _rig([15, 5])
	var rig_b: Dictionary = _rig([15, 5])

	var result_a: Dictionary = rig_a["use_case"].resolve_reactive(
		_attacker(), _fresh_action_economy(), _target(), "Strike", 1, 0, _fresh_action_economy(), ScriptedChooser.new("dodge", "none")
	)
	var result_b: Dictionary = rig_b["use_case"].resolve_reactive(
		_attacker(), _fresh_action_economy(), _target(), "Strike", 1, 0, _fresh_action_economy(), ScriptedChooser.new("dodge", "none")
	)

	assert_eq(result_a["event"].hit, result_b["event"].hit)
	assert_eq(result_a["damage_final"], result_b["damage_final"])
	assert_eq(result_a["reaction_choice"], result_b["reaction_choice"])
	assert_eq(result_a["defender_stepped"], result_b["defender_stepped"])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 8 — only "Strike" engages the reaction machinery.
# ══════════════════════════════════════════════════════════════════════════

func test_only_strike_action_name_engages_the_reaction_machinery() -> void:
	var rig: Dictionary = _rig([10, 5])
	var target: Dictionary = _target()
	var target_ae = _fresh_action_economy()
	var chooser := ScriptedChooser.new("dodge", "block")

	var result: Dictionary = rig["use_case"].resolve_reactive(
		_attacker(), _fresh_action_economy(), target, "Wait", 1, 0, target_ae, chooser
	)

	assert_eq(result["damage_final"], 5, "a non-Strike action_name must fall back to the unmitigated path even with a chooser injected")
	assert_eq(
		chooser.prehit_calls.size() + chooser.onhit_calls.size(), 0,
		"the chooser must never be consulted for a non-Strike action"
	)
