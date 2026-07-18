extends GutTest
## core/application/tests/test_reaction_budget_gate.gd
##
## GUT suite for FEAT-003 (US-003 / FR-002): the shared spend_reaction()
## budget gate. Prior features (FEAT-002/FEAT-004) proved the PreHitAvoidance
## seam could be awaited safely and that its answer negates/suppresses the
## Strike correctly; this feature proves the ≤1-reaction-per-Strike INVARIANT
## itself is defended by a single shared mechanism rather than trusted at
## each call site:
##
##   - Every reaction (Dodge today; Parry/Block/Steel too) ultimately spends
##     through the SAME ActionEconomy.spend_reaction() gate
##     (core/rules/resolution.gd's _try_spend_reaction()) -- never a second,
##     parallel spend implementation -- and is invoked AT MOST ONCE per
##     Strike, whether the reaction succeeds or fails to protect.
##   - core/application/reaction_window.gd's is_on_hit_mitigation_eligible()
##     gates a later on-hit (Parry/Block) window on "no reaction already
##     spent AND the attack hit", checking the already-spent condition FIRST
##     so it reports false "regardless of hit result" once a reaction was
##     already spent pre-hit.
##   - core/application/reaction_window.gd's assert_reaction_budget_delta()
##     is the shared budget-delta assertion core/application/round_session.gd's
##     advance_ai_turn() invokes once per resolved Strike -- a delta of 0 or
##     1 is silently accepted; a delta > 1 is a genuine contract violation
##     that fails loudly (assert()/push_error()) and is additionally recorded
##     via RoundSession.get_reaction_budget_violations() so a GUT test can
##     observe the violation directly (this project's Godot 4.3 engine
##     cannot capture assert()/push_error() output from GUT -- see
##     core/rules/resolution.gd's apply_on_hit_defense() doc for this same
##     documented limitation).
##
## Sections:
##   A. Pure, static gate functions (reaction_window.gd) exercised in
##      isolation -- no RoundSession/RNG rig required.
##   B. core/application/round_session.gd's advance_ai_turn(), proving
##      spend_reaction() fires EXACTLY ONCE per Strike for both a
##      successful and a failed Dodge (test_criteria #1), and that the
##      gate records zero violations for every correctly-behaving path
##      (a detective regression guard, NFR-004 -- never a behavior change
##      for a well-behaved call path).
##   C. Regression coverage (test_criteria #4): reproduces the exact shape
##      of the previously-fixed "enemy-budget-display desync" defect
##      (tests/gut/test_round_continuation_and_enemy_budget_display.gd,
##      fixed 2026-07-08) -- a reaction spend must be reflected EXACTLY
##      once in both the live ActionEconomy AND
##      RoundSession.action_budget_snapshot(), never twice (a double-spend
##      re-introducing the desync) and never zero (a swallowed spend that
##      would leave the display stale).

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const ReactionWindowClass          = preload("res://core/application/reaction_window.gd")
const AIClass                      = preload("res://core/combat/ai.gd")


# ══════════════════════════════════════════════════════════════════════════
# Section A: pure static gate functions
# ══════════════════════════════════════════════════════════════════════════

func test_on_hit_mitigation_ineligible_when_reaction_already_spent_and_attack_hits() -> void:
	assert_false(
		ReactionWindowClass.is_on_hit_mitigation_eligible(true, true),
		"an on-hit window must never open once a reaction was already spent this Strike, even on a hit"
	)


func test_on_hit_mitigation_ineligible_when_reaction_already_spent_and_attack_misses() -> void:
	assert_false(
		ReactionWindowClass.is_on_hit_mitigation_eligible(true, false),
		"a reaction already spent this Strike must gate the on-hit window closed regardless of hit result (test_criteria #3)"
	)


func test_on_hit_mitigation_eligible_when_no_reaction_spent_and_attack_hits() -> void:
	assert_true(
		ReactionWindowClass.is_on_hit_mitigation_eligible(false, true),
		"an on-hit window must be offered when no reaction has been spent yet AND the attack actually hit"
	)


func test_on_hit_mitigation_ineligible_when_no_reaction_spent_but_attack_misses() -> void:
	assert_false(
		ReactionWindowClass.is_on_hit_mitigation_eligible(false, false),
		"an on-hit (mitigation) window is meaningless against a miss -- there is no hit to mitigate"
	)


func test_budget_delta_of_zero_or_one_is_not_a_violation() -> void:
	assert_true(ReactionWindowClass.assert_reaction_budget_delta(0, "no reaction spent"), "a delta of 0 (no reaction spent) must never be flagged")
	assert_true(ReactionWindowClass.assert_reaction_budget_delta(1, "one reaction spent"), "a delta of 1 (the single allowed reaction) must never be flagged")


func test_budget_delta_assertion_flags_a_second_spend_within_the_same_strike() -> void:
	# Simulate the exact contract violation this gate exists to catch: a
	# hypothetical buggy call path that spends the SAME defender's reaction
	# TWICE for ONE Strike (e.g. both the PreHitAvoidance and the on-hit
	# WeaponAttack window spending against the same ActionEconomy instead of
	# the on-hit window being suppressed).
	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var before: int = ae.get_remaining()
	ae.spend_reaction()
	ae.spend_reaction()
	var after: int = ae.get_remaining()
	var delta: int = before - after

	assert_eq(delta, 2, "fixture: two spends against the same Strike must show a delta of 2")
	assert_false(
		ReactionWindowClass.assert_reaction_budget_delta(delta, "test_budget_delta_assertion_flags_a_second_spend_within_the_same_strike"),
		"a delta > 1 (a second spend_reaction() call within the same Strike) must be flagged as a budget-invariant violation (test_criteria #2)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Section B: core/application/round_session.gd integration -- spend_reaction()
# fires EXACTLY ONCE per Strike
# ══════════════════════════════════════════════════════════════════════════

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


## SpyActionEconomy -- a real ActionEconomy that records every
## spend_reaction() call, so "spend_reaction() is called exactly once" can
## be proven directly (test_criteria #1) rather than merely inferred from
## the resulting budget delta.
class SpyActionEconomy:
	extends "res://core/rules/action_economy.gd"

	var spend_reaction_call_count: int = 0

	func spend_reaction() -> Dictionary:
		spend_reaction_call_count += 1
		return super.spend_reaction()


## ScriptedRandomNumberPort -- mirrors tests/gut/test_enemy_strike_reaction_window.gd's
## identically-named double: returns pre-scripted values from `roll(dice_spec)`
## in call order.
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


## ScriptedPrehitAvoidanceResolver -- a ReactionResolverPort double
## (`async func(trigger) -> Dictionary`) for the "PreHitAvoidance" seam,
## mirroring core/application/tests/test_reaction_window_prehit.gd's
## identically-named double.
class ScriptedPrehitAvoidanceResolver:
	extends RefCounted

	var result_to_return: Dictionary
	var calls: Array = []

	func _init(result: Dictionary) -> void:
		result_to_return = result

	func resolve(trigger: Dictionary) -> Dictionary:
		calls.append(trigger)
		return result_to_return


## ScriptedReactionResolver -- the existing WeaponAttack-window (on-hit)
## resolver double, used here purely to PROVE it is never invoked/never
## spends a second reaction once PreHitAvoidance already decided/suppressed
## this Strike's one reaction.
class ScriptedReactionResolver:
	extends RefCounted

	var choice_to_return: String
	var calls: Array = []

	func _init(choice: String) -> void:
		choice_to_return = choice

	func resolve(trigger: Dictionary) -> Dictionary:
		calls.append(trigger)
		return {"choice": choice_to_return}


const CombatantClass = preload("res://core/domain/combatant.gd")

func _entry(combatant, action_economy = null) -> Dictionary:
	return {"combatant": combatant, "action_economy": action_economy if action_economy != null else ActionEconomyClass.new()}


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


func _defender():
	return CombatantClass.from_dict({
		"name":         "Alpha",
		"combatant_id": "alpha",
		"hp_current":   2000,
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


func test_spend_reaction_called_exactly_once_when_dodge_succeeds() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var alpha_ae: SpyActionEconomy = SpyActionEconomy.new()
	var entries: Array = [_entry(bravo), _entry(alpha, alpha_ae)]

	# mob_d20=15 -> mobility_check=15+mobility(1)=16. attack_d20=1 -> roll_total=1+3+2=6.
	# 6 < 16 -> Dodge SUCCEEDS: the Strike is negated.
	var rng := ScriptedRandomNumberPort.new([15, 1])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var prehit_resolver := ScriptedPrehitAvoidanceResolver.new({"choice": "dodge"})
	session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))

	await session.advance_ai_turn()

	assert_eq(alpha_ae.spend_reaction_call_count, 1,
		"a successful Dodge must call ActionEconomy.spend_reaction() exactly once (test_criteria #1)")
	assert_true(session.get_reaction_budget_violations().is_empty(),
		"a well-behaved single-spend Strike must never be recorded as a budget-delta violation")


func test_spend_reaction_called_exactly_once_when_dodge_fails() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var alpha_ae: SpyActionEconomy = SpyActionEconomy.new()
	var entries: Array = [_entry(bravo), _entry(alpha, alpha_ae)]

	# mob_d20=2 -> mobility_check=2+1=3. attack_d20=10 -> roll_total=10+3+2=15.
	# 15 >= 3 -> Dodge FAILS to protect: the Strike still hits, but the
	# reactor's one reaction for this Strike is already spent
	# (on_hit_suppressed) -- the existing on-hit WeaponAttack window must
	# never additionally spend a second reaction.
	var rng := ScriptedRandomNumberPort.new([2, 10, 4])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var prehit_resolver := ScriptedPrehitAvoidanceResolver.new({"choice": "dodge", "on_hit_suppressed": true})
	session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))

	# If the existing on-hit WeaponAttack window were ever (wrongly) asked
	# again for this Strike, it would offer Block a SECOND reaction --
	# exactly the double-spend this gate exists to prevent.
	var weapon_attack_resolver := ScriptedReactionResolver.new("block")
	session.set_reaction_resolver_fn(Callable(weapon_attack_resolver, "resolve"))

	await session.advance_ai_turn()

	assert_eq(weapon_attack_resolver.calls.size(), 0,
		"the on-hit WeaponAttack window must never be asked once PreHitAvoidance already spent this Strike's one reaction")
	assert_eq(alpha_ae.spend_reaction_call_count, 1,
		"a failed-but-triggered Dodge must call ActionEconomy.spend_reaction() exactly once -- never a second time for the same Strike (test_criteria #1)")
	assert_true(session.get_reaction_budget_violations().is_empty(),
		"a well-behaved single-spend Strike must never be recorded as a budget-delta violation")


func test_spend_reaction_called_exactly_once_for_an_on_hit_block_when_no_prehit_reaction_was_spent() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var alpha_ae: SpyActionEconomy = SpyActionEconomy.new()
	var entries: Array = [_entry(bravo), _entry(alpha, alpha_ae)]

	# No pre-hit reaction chosen -- straight to a plain roll: attack_d20=10 ->
	# roll_total=15 -> hit (ac=10). damage die=4 -> damage_raw=7. Block-reduction
	# die=3 -> block_reduction=3+block_value(2)=5 -> damage_final=2.
	var rng := ScriptedRandomNumberPort.new([10, 4, 3])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var prehit_resolver := ScriptedPrehitAvoidanceResolver.new({"choice": "none"})
	session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))

	var weapon_attack_resolver := ScriptedReactionResolver.new("block")
	session.set_reaction_resolver_fn(Callable(weapon_attack_resolver, "resolve"))

	await session.advance_ai_turn()

	assert_eq(weapon_attack_resolver.calls.size(), 1,
		"declining the PreHitAvoidance offer must still let the on-hit WeaponAttack window run")
	assert_eq(alpha_ae.spend_reaction_call_count, 1,
		"an on-hit Block must ALSO route through the SAME shared spend_reaction() gate, called exactly once")
	assert_true(session.get_reaction_budget_violations().is_empty(),
		"a well-behaved single-spend Strike must never be recorded as a budget-delta violation")


# ══════════════════════════════════════════════════════════════════════════
# Section C: regression coverage -- the previously-fixed "enemy-budget-display
# desync" defect (tests/gut/test_round_continuation_and_enemy_budget_display.gd)
# must not recur for a reaction spend routed through this gate.
# ══════════════════════════════════════════════════════════════════════════

func test_reaction_spend_stays_in_sync_between_live_economy_and_budget_snapshot() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# Same failed-Dodge scenario as above: exactly one reaction must be spent.
	var rng := ScriptedRandomNumberPort.new([2, 10, 4])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var alpha_budget_before: int = entries[1]["action_economy"].get_remaining()

	var prehit_resolver := ScriptedPrehitAvoidanceResolver.new({"choice": "dodge", "on_hit_suppressed": true})
	session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))

	await session.advance_ai_turn()

	var live_remaining: int = entries[1]["action_economy"].get_remaining()
	assert_eq(live_remaining, alpha_budget_before - 1,
		"the defender's live ActionEconomy must reflect exactly one reaction spent")

	var snapshot_remaining: int = -1
	for row in session.action_budget_snapshot():
		if row["combatant_id"] == "alpha":
			snapshot_remaining = row["remaining"]

	assert_eq(snapshot_remaining, live_remaining,
		"RoundSession.action_budget_snapshot() must exactly match the live ActionEconomy after a reaction spend -- " +
		"a double-spend (snapshot showing budget_before - 2) or a swallowed spend (snapshot stuck at budget_before) " +
		"would reproduce the previously-fixed enemy-budget-display desync (test_criteria #4)")
	assert_true(session.get_reaction_budget_violations().is_empty(),
		"the budget-delta gate must record zero violations for this well-behaved, single-spend Strike")
