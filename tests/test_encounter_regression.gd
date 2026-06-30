extends GutTest
## tests/test_encounter_regression.gd
##
## GUT regression suite for FEAT-008 (CR-001 AC-5, US-005): verifies that the
## interleaved cycle-based round loop introduced by FEAT-006/FEAT-007 has not
## altered the OBSERVABLE behavior of four pre-refactor surfaces:
##
##   1. Initiative tagging — format ("_initiative_roll" / "_is_enemy" keys)
##      and ordering (descending d20()+intuition+dexterity) are unchanged.
##   2. Enemy AI delegation — enemies are routed through the AIDecisionPort
##      contract (decide_action(combatant, targets) -> Dictionary) EXACTLY
##      ONCE per their cycle turn, never zero, never duplicated.
##   3. Party Strike targeting/damage — target selection (first living
##      opposing combatant) and damage application (hp_current -=
##      damage_final) match the pre-refactor Resolution contract bit-for-bit
##      given identical seeded RNG.
##   4. Outcome detection — win/loss/draw classification (PARTY_WIN ==
##      'won', ENEMY_WIN == 'lost', DRAW == 'DRAW') is correct for
##      representative fixtures, and the terminal 'encounter_result' event
##      payload always matches the outcome returned by run_round().
##
## Baseline reference: core/combat/encounter.gd as of commit 04598c0^ (the
## last commit before FEAT-006's interleaved-cycle refactor) — see this
## suite's helper functions for a literal reproduction of that algorithm's
## initiative formula and first-strike RNG-consumption order, used as the
## "pre-refactor" comparison baseline.

const EncounterClass     = preload("res://core/combat/encounter.gd")
const RNGClass            = preload("res://core/rules/rng.gd")
const ResolutionClass     = preload("res://core/rules/resolution.gd")
const AIClass             = preload("res://core/combat/ai.gd")
const RoundEventsClass    = preload("res://core/rules/round_events.gd")

## NOTE (FEAT-100 regression fix / FIND-096): FEAT-099 switched
## get_round_events() to carry TYPED RefCounted value objects (see
## core/rules/round_events.gd) instead of raw Dictionaries. Event
## introspection below therefore uses `is RoundEventsClass.XEvent` + direct
## field access rather than Dictionary-style `.get(key, default)`.


## CountingAI — AIDecisionPort test double (FEAT-008). Wraps the production
## AI class (core/combat/ai.gd) and records every decide_action() call
## (which combatant invoked it, and how many times) without altering its
## decision logic — proves delegation count without changing behavior.
class CountingAI:
	extends "res://core/combat/ai.gd"

	var call_count: int = 0
	var calls_by_name: Dictionary = {}  # combatant name -> call count

	func decide_action(combatant: Dictionary, targets: Array) -> Dictionary:
		call_count += 1
		var name: String = combatant.get("name", "")
		calls_by_name[name] = calls_by_name.get(name, 0) + 1
		return super.decide_action(combatant, targets)


# ── Shared fixture helpers (mirrors tests/test_encounter_round_loop.gd) ────────

## A durable combatant (hp=2000) that cannot die mid-round — isolates AC-4
## cycling behavior from win/loss early-termination.
func _durable_combatant(p_name: String) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": 2000,
		"ac":         10,
		"strength":   3,
		"dexterity":  2,
		"intuition":  2,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	}


## A fragile combatant (hp=1, ac=1) guaranteed to die on the first attack
## landed against it.
func _fragile_combatant(p_name: String) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": 1,
		"ac":         1,
		"strength":   1,
		"dexterity":  1,
		"intuition":  1,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 4
		}
	}


## A deterministic one-shot killer: high strength/proficiency guarantees a
## hit and lethal damage against any ac<=1 / hp<=1 target, regardless of
## RNG seed/roll value (roll_total = raw(>=1) + 3 + 2 >= 6 > ac=1).
func _lethal_combatant(p_name: String) -> Dictionary:
	return _durable_combatant(p_name)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: Initiative tagging format and ordering are unchanged compared
# to the pre-refactor baseline.
#
# Pre-refactor baseline (commit 04598c0^, core/combat/encounter.gd
# initialize()):
##   for combatant in (_party + _enemies):
##     roll = rng.d20() + combatant.intuition + combatant.dexterity
##     combatant["_initiative_roll"] = roll
##   sort descending by roll
## This formula/tagging code path is UNCHANGED by FEAT-006/FEAT-007 — this
## test pins the contract directly so any future accidental edit is caught.
# ══════════════════════════════════════════════════════════════════════════════

func test_initiative_roll_format_matches_pre_refactor_formula() -> void:
	var alpha: Dictionary = {"name": "Alpha", "hp_current": 10, "ac": 10, "intuition": 3, "dexterity": 4}
	var bravo: Dictionary = {"name": "Bravo", "hp_current": 10, "ac": 10, "intuition": 1, "dexterity": 1}

	# Reference RNG fed the SAME seed, consumed in the SAME order
	# (_party + _enemies, i.e. Alpha then Bravo) the pre-refactor algorithm used.
	var reference_rng = RNGClass.new(42)
	var expected_alpha_roll: int = reference_rng.d20() + alpha["intuition"] + alpha["dexterity"]
	var expected_bravo_roll: int = reference_rng.d20() + bravo["intuition"] + bravo["dexterity"]

	var enc = EncounterClass.new([alpha], [bravo], RNGClass.new(42))
	enc.initialize()

	var turn_order: Array = enc.get_turn_order()
	var found_alpha: Dictionary = {}
	var found_bravo: Dictionary = {}
	for c in turn_order:
		if c.get("name", "") == "Alpha":
			found_alpha = c
		elif c.get("name", "") == "Bravo":
			found_bravo = c

	assert_true(found_alpha.has("_initiative_roll"), "Combatant dict must carry '_initiative_roll' key (unchanged tag format)")
	assert_true(found_bravo.has("_initiative_roll"), "Combatant dict must carry '_initiative_roll' key (unchanged tag format)")
	assert_eq(
		found_alpha["_initiative_roll"], expected_alpha_roll,
		"Alpha's _initiative_roll must equal d20() + intuition + dexterity, consumed party-then-enemies order (pre-refactor formula)"
	)
	assert_eq(
		found_bravo["_initiative_roll"], expected_bravo_roll,
		"Bravo's _initiative_roll must equal d20() + intuition + dexterity, consumed party-then-enemies order (pre-refactor formula)"
	)


func test_initiative_faction_tag_format_unchanged() -> void:
	var party_member: Dictionary = {"name": "Titus", "hp_current": 10, "ac": 10, "intuition": 1, "dexterity": 1}
	var enemy_member: Dictionary = {"name": "Skeleton", "hp_current": 10, "ac": 10, "intuition": 1, "dexterity": 1}

	var enc = EncounterClass.new([party_member], [enemy_member], RNGClass.new(7))
	enc.initialize()

	for c in enc.get_turn_order():
		assert_true(c.has("_is_enemy"), "Every combatant must carry the '_is_enemy' faction tag (unchanged format)")
		if c.get("name", "") == "Titus":
			assert_false(c["_is_enemy"], "Party combatant must be tagged _is_enemy == false")
		elif c.get("name", "") == "Skeleton":
			assert_true(c["_is_enemy"], "Enemy combatant must be tagged _is_enemy == true")


func test_turn_order_sorted_descending_by_initiative_roll() -> void:
	# Five combatants with distinct intuition/dexterity spreads — sufficient
	# entropy that ties are vanishingly unlikely across the chosen seed, and
	# even if a tie occurs the monotonic non-increasing assertion still holds.
	var combatants: Array = []
	for i in range(5):
		combatants.append({
			"name": "C%d" % i, "hp_current": 10, "ac": 10,
			"intuition": i, "dexterity": i
		})

	var enc = EncounterClass.new([combatants[0], combatants[1]], [combatants[2], combatants[3], combatants[4]], RNGClass.new(99))
	enc.initialize()
	var turn_order: Array = enc.get_turn_order()

	assert_eq(turn_order.size(), 5, "All 5 combatants must appear in turn order")
	for i in range(turn_order.size() - 1):
		assert_true(
			turn_order[i]["_initiative_roll"] >= turn_order[i + 1]["_initiative_roll"],
			"Turn order must be sorted descending by _initiative_roll — entry %d (%d) must be >= entry %d (%d)"
			% [i, turn_order[i]["_initiative_roll"], i + 1, turn_order[i + 1]["_initiative_roll"]]
		)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: Enemy combatants under the new loop are delegated to AI via
# AIDecisionPort exactly once per their cycle turn.
# ══════════════════════════════════════════════════════════════════════════════

func test_enemy_delegated_to_ai_exactly_once_per_cycle_turn() -> void:
	var spy := CountingAI.new()
	var party_member: Dictionary = _durable_combatant("Titus")
	var enemy: Dictionary = _durable_combatant("Skeleton")

	var enc = EncounterClass.new([party_member], [enemy], RNGClass.new(13), spy)
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var history: Array = result.get("history", [])

	var enemy_history_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Skeleton")

	# Both combatants are durable (never die) and share MAX_BUDGET=7, so the
	# enemy resolves exactly 7 Strikes this round (one per cycle turn).
	assert_eq(enemy_history_entries.size(), 7, "Sanity: durable equal-budget enemy must resolve exactly 7 Strikes")
	assert_eq(
		spy.call_count, 7,
		"AIDecisionPort.decide_action() must be invoked exactly once per enemy cycle turn — got %d calls for %d resolved Strikes"
		% [spy.call_count, enemy_history_entries.size()]
	)
	assert_eq(
		spy.calls_by_name.get("Skeleton", 0), 7,
		"decide_action() must be called exactly 7 times for the single enemy combatant — once per its 7 cycle turns"
	)

	# The party member (non-enemy) must NEVER be routed through AIDecisionPort.
	assert_eq(
		spy.calls_by_name.get("Titus", 0), 0,
		"Party combatants must never be delegated to AIDecisionPort — only enemies"
	)


func test_multiple_enemies_each_delegated_to_ai_exactly_once_per_cycle_turn() -> void:
	var spy := CountingAI.new()
	var party_member: Dictionary = _durable_combatant("Titus")
	var enemy_a: Dictionary = _durable_combatant("Skeleton")
	var enemy_b: Dictionary = _durable_combatant("Goblin")

	var enc = EncounterClass.new([party_member], [enemy_a, enemy_b], RNGClass.new(21), spy)
	enc.initialize()
	enc.run_round()

	# Each of the two durable enemies resolves exactly 7 Strikes (one per
	# cycle turn) — 14 decide_action() calls total, 7 per enemy, none for
	# the party member.
	assert_eq(spy.calls_by_name.get("Skeleton", 0), 7, "Skeleton must be delegated to AI exactly 7 times (once per cycle turn)")
	assert_eq(spy.calls_by_name.get("Goblin", 0), 7, "Goblin must be delegated to AI exactly 7 times (once per cycle turn)")
	assert_eq(spy.calls_by_name.get("Titus", 0), 0, "Party combatant must never be delegated to AIDecisionPort")
	assert_eq(spy.call_count, 14, "Total AIDecisionPort delegations must equal the sum of each enemy's resolved cycle turns")


func test_dead_enemy_is_not_delegated_to_ai_after_death() -> void:
	var spy := CountingAI.new()
	var lethal_party: Dictionary = _lethal_combatant("Titus")
	var fragile_enemy: Dictionary = _fragile_combatant("Skeleton")

	var enc = EncounterClass.new([lethal_party], [fragile_enemy], RNGClass.new(99), spy)
	enc.initialize()
	enc.run_round()

	# Titus (lethal, high initiative roll formula doesn't matter — fragile
	# enemy dies on its FIRST hit landed against it regardless of who acts
	# first) — once the enemy is dead, it must never be re-delegated to AI
	# for any subsequent cycle.
	assert_true(
		spy.calls_by_name.get("Skeleton", 0) <= 1,
		"A fragile enemy that dies on the first attack against it must be delegated to AI at most once (never after death); got %d calls"
		% spy.calls_by_name.get("Skeleton", 0)
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: Party Strike targeting and damage application produce
# equivalent results to the pre-refactor implementation given identical
# seeded RNG.
#
# The very FIRST resolved Strike of a round is bit-for-bit identical between
# the pre-refactor sequential-loop algorithm and the new interleaved-cycle
# algorithm: both begin by consuming the SAME initiative rolls in the SAME
# order, then immediately resolve the highest-initiative combatant's FIRST
# action via the SAME Resolution.resolve_weapon_attack() contract — no
## divergence is possible until a second action is resolved. This test
## reconstructs that first-strike RNG consumption independently (via a fresh
## Resolution/RNG pair fed the identical seed) and asserts the new
## Encounter's first round_history entry matches it exactly.
# ══════════════════════════════════════════════════════════════════════════════

func test_first_strike_targeting_and_damage_match_pre_refactor_rng_sequence() -> void:
	var seed_value: int = 555
	var attacker_fixture: Dictionary = _durable_combatant("Titus")
	var target_fixture: Dictionary = _durable_combatant("Skeleton")

	# Independently reconstruct the pre-refactor RNG consumption order:
	# initiative rolls for (party + enemies) — Titus then Skeleton — followed
	# immediately by the highest-initiative combatant's first Strike via
	# Resolution.resolve_weapon_attack(). This mirrors EXACTLY what both the
	# pre- and post-refactor encounter.gd do for the very first action.
	var reference_rng = RNGClass.new(seed_value)
	var titus_roll: int = reference_rng.d20() + attacker_fixture.get("intuition", 0) + attacker_fixture.get("dexterity", 0)
	var skeleton_roll: int = reference_rng.d20() + target_fixture.get("intuition", 0) + target_fixture.get("dexterity", 0)

	var reference_resolution = ResolutionClass.new(reference_rng)
	var first_actor: Dictionary = attacker_fixture if titus_roll >= skeleton_roll else target_fixture
	var first_target: Dictionary = target_fixture if titus_roll >= skeleton_roll else attacker_fixture
	var expected_first_result: Dictionary = reference_resolution.resolve_weapon_attack(
		first_actor, first_target, first_actor["weapon"], "ac"
	)

	# Now drive the real Encounter with an identical fresh seed/fixtures.
	var party_member: Dictionary = _durable_combatant("Titus")
	var enemy_member: Dictionary = _durable_combatant("Skeleton")
	var enc = EncounterClass.new([party_member], [enemy_member], RNGClass.new(seed_value))
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var history: Array = result.get("history", [])

	assert_true(history.size() > 0, "Round must have resolved at least one Strike")
	if history.is_empty():
		return

	var first_entry: Dictionary = history[0]
	assert_eq(
		first_entry.get("attacker", {}).get("name", ""), first_actor.get("name", ""),
		"The first resolved Strike's attacker must be the highest-initiative combatant, matching pre-refactor targeting order"
	)
	assert_eq(
		first_entry.get("target", {}).get("name", ""), first_target.get("name", ""),
		"The first resolved Strike's target must be the first living opposing combatant, matching pre-refactor targeting"
	)
	assert_eq(
		first_entry.get("roll", -1), expected_first_result.get("roll_total", -2),
		"The first resolved Strike's roll must match the independently-reconstructed pre-refactor RNG sequence"
	)
	assert_eq(
		first_entry.get("damage_final", -1), expected_first_result.get("damage_final", -2),
		"The first resolved Strike's damage_final must match the independently-reconstructed pre-refactor RNG sequence"
	)


func test_party_strike_targets_first_living_enemy_and_applies_damage_to_hp_current() -> void:
	var lethal_party: Dictionary = _lethal_combatant("Titus")
	var dead_enemy: Dictionary = {"name": "Corpse", "hp_current": 0, "ac": 10, "intuition": 0, "dexterity": 0,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 0, "damage_die": 4}}
	var living_enemy: Dictionary = _fragile_combatant("Skeleton")

	var enc = EncounterClass.new([lethal_party], [dead_enemy, living_enemy], RNGClass.new(77))
	enc.initialize()
	enc.run_round()

	var history: Array = enc.get_round_history()
	var titus_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Titus")

	assert_true(titus_entries.size() > 0, "Titus must have resolved at least one Strike")
	if titus_entries.is_empty():
		return

	# Targeting: the already-dead "Corpse" must NEVER be selected as target —
	# only the living "Skeleton" (pre-refactor "first living combatant" rule).
	for entry in titus_entries:
		assert_eq(
			entry.get("target", {}).get("name", ""), "Skeleton",
			"Strike targeting must skip dead combatants and select the first LIVING opposing combatant"
		)

	# Damage application: hp_current must have been reduced by the recorded
	# damage_final (applied via target["hp_current"] -= damage, unchanged
	# from pre-refactor).
	assert_true(
		living_enemy.get("hp_current", 1) <= 0,
		"Lethal Strike's damage_final must be subtracted from target.hp_current — Skeleton (hp=1, ac=1) must be reduced to <= 0"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: DetermineOutcomeUseCase (outcome detection: all-enemies-dead →
# PARTY_WIN/'won', all-party-dead → ENEMY_WIN/'lost', invalid/empty turn
# order → DRAW) produces correct outcomes for representative fixtures, and
# the terminal 'encounter_result' event payload always matches the outcome
# returned by run_round().
# ══════════════════════════════════════════════════════════════════════════════

func test_outcome_detection_party_win_all_enemies_dead() -> void:
	var lethal_party: Dictionary = _lethal_combatant("Titus")
	var fragile_enemy: Dictionary = _fragile_combatant("Skeleton")

	var enc = EncounterClass.new([lethal_party], [fragile_enemy], RNGClass.new(99))
	enc.initialize()
	var result: Dictionary = enc.run_round()

	assert_eq(result.get("outcome", ""), "won", "All enemies dead must produce a PARTY_WIN ('won') outcome from run_round()")
	assert_eq(enc.get_outcome(), "won", "get_outcome() must also report 'won' (PARTY_WIN) once decided")


func test_outcome_detection_enemy_win_all_party_dead() -> void:
	var fragile_party: Dictionary = _fragile_combatant("Titus")
	var lethal_enemy: Dictionary = _lethal_combatant("Skeleton")

	var enc = EncounterClass.new([fragile_party], [lethal_enemy], RNGClass.new(99))
	enc.initialize()
	var result: Dictionary = enc.run_round()

	assert_eq(result.get("outcome", ""), "lost", "All party dead must produce an ENEMY_WIN ('lost') outcome from run_round()")
	assert_eq(enc.get_outcome(), "lost", "get_outcome() must also report 'lost' (ENEMY_WIN) once decided")


func test_outcome_detection_draw_on_empty_invalid_turn_order() -> void:
	# Deliberately skip initialize() — empty/invalid turn order is the
	# documented DRAW contract (FEAT-006).
	var enc = EncounterClass.new([], [], RNGClass.new(1))
	var result: Dictionary = enc.run_round()

	assert_eq(result.get("outcome", ""), "DRAW", "An empty/invalid turn order must produce a DRAW outcome from run_round()")


func test_outcome_detection_undecided_round_does_not_falsely_report_win_or_loss() -> void:
	# Two durable combatants that Spend-out without either side dying — the
	# round must terminate WITHOUT deciding an outcome (neither 'won' nor
	# 'lost' nor 'DRAW' — outcome stays '' / undecided).
	var enc = EncounterClass.new([_durable_combatant("X")], [_durable_combatant("Y")], RNGClass.new(123))
	enc.initialize()
	var result: Dictionary = enc.run_round()

	assert_eq(result.get("outcome", "MISSING"), "", "A round that Spends-out without a kill must report outcome == '' (undecided), not a false win/loss/draw")
	assert_eq(enc.get_outcome(), "", "get_outcome() must also report '' while undecided")


func test_encounter_result_event_payload_matches_run_round_outcome_on_win() -> void:
	var lethal_party: Dictionary = _lethal_combatant("Titus")
	var fragile_enemy: Dictionary = _fragile_combatant("Skeleton")

	var enc = EncounterClass.new([lethal_party], [fragile_enemy], RNGClass.new(99))
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var events: Array = enc.get_round_events()

	var result_events: Array = events.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(result_events.size(), 1, "Exactly one terminal encounter_result event must be emitted for a decided round")
	if result_events.is_empty():
		return
	assert_eq(
		result_events[0].outcome, result.get("outcome", ""),
		"encounter_result event payload outcome must exactly match the outcome returned by run_round()"
	)


func test_encounter_result_event_payload_matches_run_round_outcome_on_loss() -> void:
	var fragile_party: Dictionary = _fragile_combatant("Titus")
	var lethal_enemy: Dictionary = _lethal_combatant("Skeleton")

	var enc = EncounterClass.new([fragile_party], [lethal_enemy], RNGClass.new(99))
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var events: Array = enc.get_round_events()

	var result_events: Array = events.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(result_events.size(), 1, "Exactly one terminal encounter_result event must be emitted for a decided round")
	if result_events.is_empty():
		return
	assert_eq(
		result_events[0].outcome, result.get("outcome", ""),
		"encounter_result event payload outcome must exactly match the outcome returned by run_round()"
	)


## FEAT-097 (CWE-835 / FIND-095) regression: zero-living-combatants-on-one-side
## no longer hangs run_round(), and the terminal encounter_result event
## payload still matches run_round()'s returned outcome exactly for these
## new up-front-guard-decided paths — the same contract already proven for
## the post-attack win/loss paths above.
func test_encounter_result_event_payload_matches_run_round_outcome_when_no_living_enemies_upfront() -> void:
	var living_party_member: Dictionary = _durable_combatant("Titus")

	var enc = EncounterClass.new([living_party_member], [], RNGClass.new(1))
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var events: Array = enc.get_round_events()

	var result_events: Array = events.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(result_events.size(), 1, "Exactly one terminal encounter_result event must be emitted when the up-front guard decides a 'won' outcome")
	if result_events.is_empty():
		return
	assert_eq(
		result_events[0].outcome, result.get("outcome", ""),
		"encounter_result event payload outcome must exactly match the outcome returned by run_round() for the no-living-enemies guard path"
	)
	assert_eq(result.get("outcome", ""), "won", "Sanity: a living party with zero enemies must resolve 'won'")


func test_encounter_result_event_payload_matches_run_round_outcome_when_no_living_party_upfront() -> void:
	var living_enemy: Dictionary = _durable_combatant("Skeleton")

	var enc = EncounterClass.new([], [living_enemy], RNGClass.new(1))
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var events: Array = enc.get_round_events()

	var result_events: Array = events.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(result_events.size(), 1, "Exactly one terminal encounter_result event must be emitted when the up-front guard decides a 'lost' outcome")
	if result_events.is_empty():
		return
	assert_eq(
		result_events[0].outcome, result.get("outcome", ""),
		"encounter_result event payload outcome must exactly match the outcome returned by run_round() for the no-living-party guard path"
	)
	assert_eq(result.get("outcome", ""), "lost", "Sanity: a living enemy with zero party members must resolve 'lost'")


## Direct CWE-835 regression: this scenario hung the test runner indefinitely
## before FEAT-097 (a party member whose target pool is permanently empty
## never calls spend_action(), never becomes Spent, and
## _round_has_living_unspent_combatant() looped forever). Its mere completion
## — within GUT's normal per-test time budget — is the primary proof; the
## assertion pins the now-correct, no-hang outcome.
func test_run_round_with_empty_enemy_array_does_not_hang_and_resolves_won() -> void:
	var living_party_member: Dictionary = _durable_combatant("Titus")
	var enc = EncounterClass.new([living_party_member], [], RNGClass.new(2024))
	enc.initialize()
	var result: Dictionary = enc.run_round()
	assert_eq(result.get("outcome", ""), "won", "A living party member with no enemies must resolve 'won' without hanging (CWE-835 / FIND-095)")


func test_encounter_result_event_absent_when_round_undecided() -> void:
	var enc = EncounterClass.new([_durable_combatant("X")], [_durable_combatant("Y")], RNGClass.new(123))
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var events: Array = enc.get_round_events()

	var result_events: Array = events.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(
		result_events.size(), 0,
		"No encounter_result event may be emitted when run_round() returns an undecided ('') outcome"
	)
	assert_eq(result.get("outcome", "MISSING"), "", "Sanity: this round's outcome must indeed be undecided")
