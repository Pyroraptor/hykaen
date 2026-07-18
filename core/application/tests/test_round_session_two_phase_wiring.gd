extends GutTest
## core/application/tests/test_round_session_two_phase_wiring.gd
##
## GUT suite for FEAT-005 (US-005 / FR-005, Iteration J Part A): wiring the
## two-phase reaction windows (PreHitAvoidance, then conditionally
## OnHitMitigation) through core/application/round_session.gd's
## advance_ai_turn() async AI-turn coroutine, and through MainScene.gd's
## composition root.
##
## Prior features built every piece this feature finally connects together:
##   - FEAT-001 (core/rules/tests/test_resolution_two_phase.gd) split
##     resolve_weapon_attack() into resolve_to_hit()/apply_on_hit_defense().
##   - FEAT-002 (core/application/tests/test_reaction_window_prehit.gd) added
##     the "PreHitAvoidance" trigger_type/window and RoundSession's
##     _prehit_avoidance_resolver_fn seam, and wired advance_ai_turn()'s FIRST
##     await point to it.
##   - FEAT-004 (core/application/tests/test_reaction_window_onhit.gd) added
##     the "OnHitMitigation" trigger_type/window and RoundSession's
##     _onhit_mitigation_resolver_fn seam (_resolve_onhit_mitigation()) --
##     established but, until this feature, never actually invoked from
##     advance_ai_turn().
##
## This feature adds the SECOND await point: once a caller opts into
## two-phase mode by injecting a dedicated OnHitMitigation resolver (see
## set_onhit_mitigation_resolver_fn()), advance_ai_turn()'s Strike branch:
##   1. awaits PreHitAvoidance (Dodge/Steel) BEFORE the roll (unchanged),
##   2. resolves the Strike via the SAME resolve_action_use_case pipeline
##      every other Strike in this codebase uses,
##   3. THEN, only when no reaction was spent in step 1 AND the Strike hit,
##      awaits OnHitMitigation (Parry/Block) -- this feature's new wiring.
## Every pre-existing caller/test double that never injects the OnHitMitigation
## resolver is byte-for-byte unaffected (NFR-004) -- see
## test_legacy_weapon_attack_path_is_unaffected_when_onhit_resolver_is_unset().
##
## Verifies (test_criteria):
##   1. advance_ai_turn()'s coroutine completes without stalling for
##      pass/dodge-fail/dodge-success/hit-then-parry/hit-then-block scenarios.
##   2. Window firing order is asserted as PreHitAvoidance then, conditionally,
##      OnHitMitigation -- never reversed, never duplicated.
##   3. The existing Iteration-I reaction suite
##      (tests/gut/test_steel_thread_e2e.gd,
##      tests/gut/test_mainscene_reaction_resolver_wiring.gd,
##      tests/gut/test_round_continuation_and_enemy_budget_display.gd) is
##      exercised unmodified by the project's normal full-suite run (not
##      duplicated here -- see those files directly).
##   4. A resolver that "times out"/declines (never answers with a legal
##      choice, or is simply never injected) resolves to Pass rather than
##      hanging the coroutine, for either window.

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const AIClass                      = preload("res://core/combat/ai.gd")


# ── Fake/double port implementations (mirrors core/application/tests/
#    test_reaction_window_onhit.gd Section C's established convention) ──────

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


## ScriptedRandomNumberPort -- mirrors core/application/tests/
## test_reaction_budget_gate.gd's identically-named double: returns
## pre-scripted values from `roll(dice_spec)` in call order.
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


## RecordingTwoPhaseResolver -- a SINGLE ReactionResolverPort double
## (`async func(trigger) -> Dictionary`) injected into BOTH the
## PreHitAvoidance and OnHitMitigation seams, so `call_order` directly proves
## cross-window firing ORDER (test_criteria #2) without needing to compare
## two separate doubles' independent state.
class RecordingTwoPhaseResolver:
	extends RefCounted

	## call_order -- the "trigger_type" of each invocation, in call order.
	var call_order: Array = []
	## calls -- the full trigger Dictionary of each invocation, in call order.
	var calls: Array = []
	## choice_for_trigger_type -- {trigger_type: choice String} answered per window.
	var choice_for_trigger_type: Dictionary = {}
	## extra_fields_for_trigger_type -- {trigger_type: {extra key: value}} merged
	## into that window's returned Dictionary (e.g. "on_hit_suppressed").
	var extra_fields_for_trigger_type: Dictionary = {}

	func resolve(trigger: Dictionary) -> Dictionary:
		var trigger_type: String = trigger.get("trigger_type", "")
		call_order.append(trigger_type)
		calls.append(trigger)
		var result: Dictionary = {"choice": choice_for_trigger_type.get(trigger_type, "none")}
		var extras: Dictionary = extra_fields_for_trigger_type.get(trigger_type, {})
		for key in extras:
			result[key] = extras[key]
		return result


## DelayedTwoPhaseResolver -- a GENUINELY suspending resolver (awaits a real
## SceneTree timer, mirroring tests/gut/test_async_reaction_propagation.gd's
## DelayedReactionResolver double) so "the coroutine completes without
## stalling" (test_criteria #1) is proven against a resolver that actually
## exercises the `await` machinery, not one that returns on the same frame.
class DelayedTwoPhaseResolver:
	extends RefCounted

	var call_order: Array = []
	var resolved_count: int = 0
	var choice_for_trigger_type: Dictionary = {}

	var _scene_tree
	var _delay_seconds: float

	func _init(scene_tree, delay_seconds: float = 0.02) -> void:
		_scene_tree = scene_tree
		_delay_seconds = delay_seconds

	func resolve(trigger: Dictionary) -> Dictionary:
		var trigger_type: String = trigger.get("trigger_type", "")
		call_order.append(trigger_type)
		await _scene_tree.create_timer(_delay_seconds).timeout
		resolved_count += 1
		return {"choice": choice_for_trigger_type.get(trigger_type, "none")}


## MalformedResolver -- answers with a Dictionary carrying no "choice" key at
## all (a misbehaving/"cancelled" adapter), used to prove the coroutine still
## resolves to Pass rather than hanging or crashing (test_criteria #4).
class MalformedResolver:
	extends RefCounted

	var calls: Array = []

	func resolve(trigger: Dictionary) -> Dictionary:
		calls.append(trigger)
		return {}


const CombatantClass = preload("res://core/domain/combatant.gd")

func _entry(combatant) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


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


## _defender() -- the player (Alpha). Carries a weapon eligible for BOTH
## Parry (parry_bonus 3) and Block (block_value 2), and a Mobility skill
## Dodge's substituted defense value is computed from.
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


## _make_session(entries, party, enemies, random_number_port) -> Dictionary --
## builds a fully-wired, REAL RunRoundUseCase (the SAME production
## resolve_action_use_case/AIClass pipeline every other RoundSession suite in
## this codebase exercises) and begins round 1.
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


## _assert_valid_firing_order(call_order) -- shared helper (test_criteria #2):
## a valid call_order is EITHER [] (nothing asked), ["PreHitAvoidance"], or
## ["PreHitAvoidance", "OnHitMitigation"] in that EXACT order -- never
## reversed, never duplicated, never OnHitMitigation alone.
func _assert_valid_firing_order(call_order: Array, context: String) -> void:
	assert_true(
		call_order.size() <= 2,
		"%s: at most two reaction windows may fire per Strike, got %s" % [context, str(call_order)]
	)
	if call_order.size() >= 1:
		assert_eq(call_order[0], "PreHitAvoidance", "%s: PreHitAvoidance must always fire FIRST when anything fires at all" % context)
	if call_order.size() == 2:
		assert_eq(call_order[1], "OnHitMitigation", "%s: the second window (if any) must be OnHitMitigation, never a repeat of PreHitAvoidance" % context)


# ══════════════════════════════════════════════════════════════════════════
# Scenario: Pass (both windows declined) -- attack misses. No stall; only
# PreHitAvoidance fires (a miss never opens the on-hit window).
# ══════════════════════════════════════════════════════════════════════════

func test_pass_scenario_completes_without_stalling_and_never_asks_onhit_on_a_miss() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# attack_d20=1 -> roll_total = 1 + 3 + 2 = 6 < ac(10) -> MISS.
	var rng := ScriptedRandomNumberPort.new([1])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var resolver := RecordingTwoPhaseResolver.new()
	session.set_prehit_avoidance_resolver_fn(Callable(resolver, "resolve"))
	session.set_onhit_mitigation_resolver_fn(Callable(resolver, "resolve"))

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false), "advance_ai_turn() must complete without stalling for the Pass/miss scenario")
	assert_eq(rig["history"].entries.size(), 1, "exactly one Strike must be resolved")
	assert_false(rig["event_sink"].events[0].hit, "fixture assumption: the scripted roll must miss")

	assert_eq(resolver.call_order, ["PreHitAvoidance"], "a miss must never open the OnHitMitigation window")
	_assert_valid_firing_order(resolver.call_order, "Pass/miss")
	assert_eq(session.current_actor().name, "Alpha", "the cursor must still advance -- no stall")


# ══════════════════════════════════════════════════════════════════════════
# Scenario: Dodge FAILS to protect -- attack still hits, but the reaction was
# already spent pre-hit, so OnHitMitigation must never be offered (budget
# rule). No stall.
# ══════════════════════════════════════════════════════════════════════════

func test_dodge_fail_scenario_completes_without_stalling_and_never_asks_onhit() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# mob_d20=2 -> mobility_check=2+1=3. attack_d20=10 -> roll_total=15.
	# 15 >= 3 -> Dodge FAILS to protect (still a hit); damage die=4 -> damage_raw=7.
	var rng := ScriptedRandomNumberPort.new([2, 10, 4])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var resolver := RecordingTwoPhaseResolver.new()
	resolver.choice_for_trigger_type["PreHitAvoidance"] = "dodge"
	resolver.extra_fields_for_trigger_type["PreHitAvoidance"] = {"on_hit_suppressed": true}
	session.set_prehit_avoidance_resolver_fn(Callable(resolver, "resolve"))
	session.set_onhit_mitigation_resolver_fn(Callable(resolver, "resolve"))

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false), "advance_ai_turn() must complete without stalling for the dodge-fail scenario")
	assert_true(rig["event_sink"].events[0].hit, "fixture assumption: the failed Dodge still results in a hit")

	assert_eq(resolver.call_order, ["PreHitAvoidance"], "a failed-but-triggered Dodge must never let OnHitMitigation open (<=1 reaction per Strike)")
	_assert_valid_firing_order(resolver.call_order, "dodge-fail")
	assert_eq(session.current_actor().name, "Alpha", "the cursor must still advance -- no stall")


# ══════════════════════════════════════════════════════════════════════════
# Scenario: Dodge SUCCEEDS -- attack is avoided entirely. No stall; only
# PreHitAvoidance fires.
# ══════════════════════════════════════════════════════════════════════════

func test_dodge_success_scenario_completes_without_stalling_and_never_asks_onhit() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# mob_d20=15 -> mobility_check=16. attack_d20=1 -> roll_total=6 < 16 -> Dodge SUCCEEDS.
	var rng := ScriptedRandomNumberPort.new([15, 1])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var resolver := RecordingTwoPhaseResolver.new()
	resolver.choice_for_trigger_type["PreHitAvoidance"] = "dodge"
	session.set_prehit_avoidance_resolver_fn(Callable(resolver, "resolve"))
	session.set_onhit_mitigation_resolver_fn(Callable(resolver, "resolve"))

	var hp_before: int = alpha.get("hp_current", 0)
	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false), "advance_ai_turn() must complete without stalling for the dodge-success scenario")
	assert_false(rig["event_sink"].events[0].hit, "PINNED: a successful Dodge must negate the Strike")
	assert_eq(alpha.get("hp_current", 0), hp_before, "a negated Strike must deal zero damage")

	assert_eq(resolver.call_order, ["PreHitAvoidance"], "a successful Dodge must never let OnHitMitigation open")
	_assert_valid_firing_order(resolver.call_order, "dodge-success")
	assert_eq(session.current_actor().name, "Alpha", "the cursor must still advance -- no stall")


# ══════════════════════════════════════════════════════════════════════════
# Scenario: hit-then-parry -- PreHitAvoidance is Passed, the Strike hits, and
# OnHitMitigation is offered and answered with Parry. Firing order:
# PreHitAvoidance then OnHitMitigation, never reversed/duplicated.
# ══════════════════════════════════════════════════════════════════════════

func test_hit_then_parry_scenario_fires_prehit_then_onhit_in_order_without_stalling() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# attack_d20=10 -> roll_total=15, hits ac(10). damage die=4 -> damage_raw=7.
	# FEAT-003 (G3 remediation): the on-hit window's chosen Parry is now
	# GENUINELY applied via Resolution.apply_on_hit_defense() -- a third RNG
	# draw is the parry d20 check: parry_d20=15 -> parry_roll=15+parry_bonus(3)
	# =18, which STRICTLY exceeds the attacker's roll_total(15) -> Parry
	# SUCCEEDS -> damage_final=0. Previously (the trace-only bug this feature
	# fixes) only 2 draws were ever consumed because the chosen reaction was
	# asked about and discarded without ever calling apply_on_hit_defense().
	var rng := ScriptedRandomNumberPort.new([10, 4, 15])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var hp_before: int = alpha.get("hp_current", 0)

	var resolver := RecordingTwoPhaseResolver.new()
	resolver.choice_for_trigger_type["PreHitAvoidance"] = "none"
	resolver.choice_for_trigger_type["OnHitMitigation"] = "parry"
	session.set_prehit_avoidance_resolver_fn(Callable(resolver, "resolve"))
	session.set_onhit_mitigation_resolver_fn(Callable(resolver, "resolve"))

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false), "advance_ai_turn() must complete without stalling for the hit-then-parry scenario")
	assert_true(rig["event_sink"].events[0].hit, "fixture assumption: the scripted roll must hit")

	assert_eq(resolver.call_order, ["PreHitAvoidance", "OnHitMitigation"], "a Passed PreHitAvoidance + a hit must fire OnHitMitigation SECOND, in order")
	_assert_valid_firing_order(resolver.call_order, "hit-then-parry")

	var onhit_trigger: Dictionary = resolver.calls[1]
	assert_eq(onhit_trigger.get("trigger_type", ""), "OnHitMitigation")
	assert_true(onhit_trigger.get("attack_hit", false), "the OnHitMitigation trigger must carry the ALREADY-KNOWN hit result")
	assert_eq(onhit_trigger.get("attacker_id", ""), "bravo")
	assert_eq(onhit_trigger.get("target_id", ""), "alpha")

	# FEAT-003 (G3 remediation): the chosen Parry must GENUINELY reduce the
	# committed damage -- not merely be asked about and discarded.
	assert_eq(rig["event_sink"].events[0].damage_final, 0, "a successful Parry must reduce the committed final damage to 0 (FR-001 mitigation formula)")
	assert_eq(alpha.get("hp_current", 0), hp_before, "Alpha must take ZERO damage once Parry genuinely mitigates the hit")

	assert_eq(session.current_actor().name, "Alpha", "the cursor must still advance -- no stall")


# ══════════════════════════════════════════════════════════════════════════
# Scenario: hit-then-block -- same shape as hit-then-parry, answered with
# Block instead.
# ══════════════════════════════════════════════════════════════════════════

func test_hit_then_block_scenario_fires_prehit_then_onhit_in_order_without_stalling() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# FEAT-003 (G3 remediation): the on-hit window's chosen Block is now
	# GENUINELY applied -- a third RNG draw is the block-reduction die:
	# block_reduction_die=3 -> block_reduction=3+block_value(2)=5 ->
	# damage_final=max(0, damage_raw(7)-5)=2 (mirrors core/application/tests/
	# test_reaction_budget_gate.gd's identical fixture/math for the legacy
	# WeaponAttack path -- same underlying Resolution.apply_on_hit_defense()).
	var rng := ScriptedRandomNumberPort.new([10, 4, 3])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var hp_before: int = alpha.get("hp_current", 0)

	var resolver := RecordingTwoPhaseResolver.new()
	resolver.choice_for_trigger_type["PreHitAvoidance"] = "none"
	resolver.choice_for_trigger_type["OnHitMitigation"] = "block"
	session.set_prehit_avoidance_resolver_fn(Callable(resolver, "resolve"))
	session.set_onhit_mitigation_resolver_fn(Callable(resolver, "resolve"))

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false), "advance_ai_turn() must complete without stalling for the hit-then-block scenario")
	assert_true(rig["event_sink"].events[0].hit, "fixture assumption: the scripted roll must hit")

	assert_eq(resolver.call_order, ["PreHitAvoidance", "OnHitMitigation"], "a Passed PreHitAvoidance + a hit must fire OnHitMitigation SECOND, in order")
	_assert_valid_firing_order(resolver.call_order, "hit-then-block")

	# FEAT-003 (G3 remediation): the chosen Block must GENUINELY reduce the
	# committed damage -- not merely be asked about and discarded.
	assert_eq(rig["event_sink"].events[0].damage_final, 2, "Block must reduce the committed final damage per FR-001's mitigation formula: raw(7) - reduction(5) = 2")
	assert_eq(hp_before - alpha.get("hp_current", 0), 2, "Alpha must take exactly the mitigated (not raw) damage once Block genuinely applies")

	assert_eq(session.current_actor().name, "Alpha", "the cursor must still advance -- no stall")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #1/#4: a genuinely suspending resolver (real SceneTree timer)
# is awaited to completion for BOTH windows with no deadlock -- the test
# itself completing is the proof (a real self-deadlock would hang this test/
# CI forever), mirroring tests/gut/test_async_reaction_propagation.gd's own
# established proof technique.
# ══════════════════════════════════════════════════════════════════════════

func test_advance_ai_turn_awaits_a_genuinely_delayed_resolver_for_both_windows_without_deadlock() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# FEAT-003 (G3 remediation): the chosen Block is now genuinely applied, so
	# a third RNG draw (the block-reduction die) is consumed -- see the
	# hit-then-block scenario above for the identical math.
	var rng := ScriptedRandomNumberPort.new([10, 4, 3])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var resolver := DelayedTwoPhaseResolver.new(get_tree(), 0.02)
	resolver.choice_for_trigger_type["PreHitAvoidance"] = "none"
	resolver.choice_for_trigger_type["OnHitMitigation"] = "block"
	session.set_prehit_avoidance_resolver_fn(Callable(resolver, "resolve"))
	session.set_onhit_mitigation_resolver_fn(Callable(resolver, "resolve"))

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false), "a genuinely suspending resolver must not stall advance_ai_turn()'s coroutine")
	assert_eq(resolver.resolved_count, 2, "BOTH windows' delayed awaits must have actually completed before advance_ai_turn() resumed")
	assert_eq(resolver.call_order, ["PreHitAvoidance", "OnHitMitigation"], "the delayed resolver must still observe the correct firing order")
	assert_eq(rig["history"].entries.size(), 1, "a suspending await must never cause a double-resolve")
	assert_eq(session.current_actor().name, "Alpha", "the cursor must advance exactly once, only after both delayed awaits fully resolved")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #4: a malformed/"cancelled" resolver answer (no "choice" key
# at all) on EITHER window must resolve to Pass rather than hanging or
# crashing the coroutine.
# ══════════════════════════════════════════════════════════════════════════

func test_malformed_onhit_resolver_answer_falls_back_to_pass_without_stalling() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rng := ScriptedRandomNumberPort.new([10, 4])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var prehit_resolver := RecordingTwoPhaseResolver.new()
	prehit_resolver.choice_for_trigger_type["PreHitAvoidance"] = "none"
	session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))

	var onhit_resolver := MalformedResolver.new()
	session.set_onhit_mitigation_resolver_fn(Callable(onhit_resolver, "resolve"))

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false), "a malformed OnHitMitigation answer must not stall/crash the coroutine")
	assert_eq(onhit_resolver.calls.size(), 1, "the OnHitMitigation resolver must still be invoked exactly once")
	assert_eq(session.current_actor().name, "Alpha", "the cursor must still advance -- no stall")


## An UNSET OnHitMitigation resolver (the pre-FEAT-005 default state for every
## caller that never opts in) must resolve synchronously to Pass -- the
## existing default-safety contract established by FEAT-004's own
## _resolve_onhit_mitigation() doc, exercised here end-to-end through
## advance_ai_turn() rather than by calling the seam directly.
func test_unset_onhit_resolver_still_completes_the_hit_scenario_without_stalling() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rng := ScriptedRandomNumberPort.new([10, 4])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	assert_false(session._onhit_mitigation_resolver_fn.is_valid(), "fixture assumption: no OnHitMitigation resolver was injected")

	# No prehit resolver either -- this session never opted into two-phase
	# mode at all, so it must take the LEGACY WeaponAttack path unchanged.
	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false), "the fully-un-injected default path must still resolve synchronously without stalling")
	assert_eq(session.current_actor().name, "Alpha", "the cursor must still advance")


# ══════════════════════════════════════════════════════════════════════════
# Regression guard: the legacy WeaponAttack (combined) window must remain
# COMPLETELY UNAFFECTED when a caller injects ONLY the pre-existing
# `set_reaction_resolver_fn` seam (never the new OnHitMitigation one) --
# exactly the shape of every Iteration-I test (tests/gut/
# test_enemy_strike_reaction_window.gd, core/application/tests/
# test_reaction_budget_gate.gd) this feature must not disturb.
# ══════════════════════════════════════════════════════════════════════════

func test_legacy_weapon_attack_path_is_unaffected_when_onhit_resolver_is_unset() -> void:
	var bravo = _attacker()
	var alpha = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# RNG order for the legacy combined WeaponAttack path choosing "block":
	# attack_d20=10 -> hit; damage die=4 -> damage_raw=7; block-reduction
	# die=3 -> block_reduction=3+block_value(2)=5 -> damage_final=2 (mirrors
	# tests/gut/test_enemy_strike_reaction_window.gd's own Block fixture).
	var rng := ScriptedRandomNumberPort.new([10, 4, 3])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var weapon_attack_resolver := RecordingTwoPhaseResolver.new()
	weapon_attack_resolver.choice_for_trigger_type["WeaponAttack"] = "block"
	session.set_reaction_resolver_fn(Callable(weapon_attack_resolver, "resolve"))
	assert_false(session._onhit_mitigation_resolver_fn.is_valid(), "fixture assumption: two-phase mode is NOT opted into")

	var hp_before: int = alpha.get("hp_current", 0)
	await session.advance_ai_turn()

	assert_eq(weapon_attack_resolver.call_order, ["WeaponAttack"], "the legacy combined window must still be asked exactly once, unchanged by this feature")
	var attack_event = rig["event_sink"].events[0]
	assert_true(attack_event.hit)
	assert_eq(attack_event.damage_final, 2, "PINNED (unchanged Block math): damage_raw(7) - block_reduction(5) = 2")
	assert_eq(hp_before - alpha.get("hp_current", 0), 2)


# ══════════════════════════════════════════════════════════════════════════
# Static source-shape audit (mirrors tests/gut/test_async_reaction_propagation
# .gd's established convention): pins the SECOND await point this feature
# introduces and proves no self-deadlock back-edge was created.
# ══════════════════════════════════════════════════════════════════════════

func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func _extract_function_body(content: String, func_signature_needle: String) -> String:
	var fn_start: int = content.find(func_signature_needle)
	assert_true(fn_start >= 0, "fixture assumption: '%s' must exist" % func_signature_needle)
	if fn_start < 0:
		return ""
	var next_fn_start: int = content.find("\nfunc ", fn_start + 1)
	if next_fn_start == -1:
		next_fn_start = content.length()
	var raw_body: String = content.substr(fn_start, next_fn_start - fn_start)
	return _strip_comment_lines(raw_body)


func _strip_comment_lines(text: String) -> String:
	var kept_lines: Array = []
	for line in text.split("\n"):
		if not line.strip_edges().begins_with("#"):
			kept_lines.append(line)
	return "\n".join(kept_lines)


func test_audit_advance_ai_turn_awaits_onhit_mitigation_exactly_once_after_prehit_avoidance() -> void:
	var content: String = _read_file("res://core/application/round_session.gd")
	var body: String = _extract_function_body(content, "func advance_ai_turn(")

	assert_eq(
		body.count("await _resolve_onhit_mitigation("), 1,
		"advance_ai_turn() must await _resolve_onhit_mitigation() exactly once -- the SECOND new await point this feature introduces"
	)
	# The pre-existing FIRST await point (FEAT-002/003) must remain exactly
	# once too -- this feature must not remove or duplicate it.
	assert_eq(
		body.count("await _resolve_prehit_avoidance("), 1,
		"advance_ai_turn() must still await _resolve_prehit_avoidance() exactly once, unchanged"
	)
	# The legacy WeaponAttack await point must ALSO still exist exactly once
	# (guarded by the `else` branch for un-opted-in callers) -- proving this
	# feature is additive, not a removal (NFR-004; also pinned independently
	# by tests/gut/test_async_reaction_propagation.gd's own identical count
	# assertion, which this file must not cause to regress).
	assert_eq(
		body.count("await _resolve_reaction("), 1,
		"advance_ai_turn() must still await the legacy _resolve_reaction() exactly once for un-opted-in callers"
	)

	# Ordering: PreHitAvoidance's await point must appear BEFORE
	# OnHitMitigation's in the source -- matching the runtime firing order
	# this feature guarantees (test_criteria #2).
	var prehit_pos: int = body.find("await _resolve_prehit_avoidance(")
	var onhit_pos: int = body.find("await _resolve_onhit_mitigation(")
	assert_true(prehit_pos >= 0 and onhit_pos >= 0 and prehit_pos < onhit_pos, "PreHitAvoidance's await must be coded strictly before OnHitMitigation's")

	# No back-edge: advance_ai_turn() must never call back into anything that
	# itself (transitively) awaits advance_ai_turn() -- the classic
	# self-deadlock failure mode (mirrors test_async_reaction_propagation.gd's
	# identical guard).
	assert_false(body.contains("_drive("), "advance_ai_turn() must never call back into TurnController._drive() (no self-deadlock cycle)")
	assert_false(body.contains("set_session("), "advance_ai_turn() must never call back into TurnController.set_session() (no self-deadlock cycle)")


func test_audit_resolve_onhit_mitigation_never_calls_back_into_advance_ai_turn() -> void:
	var content: String = _read_file("res://core/application/round_session.gd")
	var body: String = _extract_function_body(content, "func _resolve_onhit_mitigation(")

	assert_eq(body.count("await "), 1, "_resolve_onhit_mitigation() must contain exactly one await point -- the injected resolver Callable")
	assert_false(
		body.contains("advance_ai_turn("),
		"_resolve_onhit_mitigation() must never call back into advance_ai_turn() -- it only awaits the externally-injected resolver Callable, a leaf call with no path back into RoundSession's own coroutines"
	)


# ══════════════════════════════════════════════════════════════════════════
# MainScene.gd composition-root wiring audit: both new resolver seams must be
# wired to the SAME real ReactionResolverPort adapter (turn_controller.
# resolve_reaction()) already used for the legacy WeaponAttack seam.
# ══════════════════════════════════════════════════════════════════════════

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


func test_mainscene_wires_prehit_and_onhit_resolvers_to_the_real_turn_controller() -> void:
	var instance = _boot_main_scene()

	assert_not_null(instance.round_session, "MainScene.round_session must be a real RoundSession after boot")
	assert_not_null(instance.turn_controller, "MainScene.turn_controller must be wired after boot")

	var prehit_fn: Callable = instance.round_session._prehit_avoidance_resolver_fn
	assert_true(prehit_fn.is_valid(), "MainScene must inject a REAL PreHitAvoidance resolver (FEAT-005 -- previously left permanently unset)")
	assert_eq(prehit_fn.get_object(), instance.turn_controller)
	assert_eq(prehit_fn.get_method(), &"resolve_reaction")

	var onhit_fn: Callable = instance.round_session._onhit_mitigation_resolver_fn
	assert_true(onhit_fn.is_valid(), "MainScene must inject a REAL OnHitMitigation resolver (FEAT-005 -- previously left permanently unset)")
	assert_eq(onhit_fn.get_object(), instance.turn_controller)
	assert_eq(onhit_fn.get_method(), &"resolve_reaction")

	# The pre-existing legacy seam must remain wired too (unchanged, NFR-004).
	var legacy_fn: Callable = instance.round_session._reaction_resolver_fn
	assert_true(legacy_fn.is_valid())
	assert_eq(legacy_fn.get_object(), instance.turn_controller)


func test_rewire_session_reapplies_both_new_resolver_seams_on_round_continuation() -> void:
	var instance = _boot_main_scene()

	await instance.rewire_session()

	var prehit_fn: Callable = instance.round_session._prehit_avoidance_resolver_fn
	var onhit_fn: Callable = instance.round_session._onhit_mitigation_resolver_fn
	assert_true(prehit_fn.is_valid(), "a freshly begin_round()'d RoundSession must never be left without a PreHitAvoidance resolver")
	assert_true(onhit_fn.is_valid(), "a freshly begin_round()'d RoundSession must never be left without an OnHitMitigation resolver")
	assert_eq(prehit_fn.get_object(), instance.turn_controller)
	assert_eq(onhit_fn.get_object(), instance.turn_controller)
