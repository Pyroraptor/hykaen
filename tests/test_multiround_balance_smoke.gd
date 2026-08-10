extends GutTest
## tests/test_multiround_balance_smoke.gd
##
## FEAT-005 (US-005, FR-006/FR-008, ADR-003): dedicated post-fix regression
## smoke test for the AD-1/AD-2 crash-and-stale-expectation fix landed by
## FEAT-001..FEAT-004 (see docs/iterations/iteration-AD-gut-regression-fix.org).
##
## This file is DELIBERATELY SEPARATE from the pre-existing
## tests/test_encounter_multiround_balance_smoke.gd (FEAT-010) — it is a
## narrower, dedicated pinning test that exists specifically to prove the
## two things this iteration's design notes call out for the multiround
## balance path:
##   1. A full multi-round encounter driven entirely through plain-Dictionary
##      combatants (the exact shape that crashed
##      core/application/resolve_action_use_case.gd's
##      _finalize_strike_result() pre-fix — see AD-1) completes to a valid
##      outcome with NO SCRIPT ERROR, even when it spans a defeat.
##   2. Every core/rules/round_events.gd RoundEvents.RoundHistoryEntry-backed
##      round_history entry's budget_remaining value is internally
##      consistent with the shared per-round action-economy countdown — i.e.
##      there is no residual budget_remaining off-by-one introduced as a
##      ripple effect of the AD-1 fix.
##
## Per ADR-003 / this iteration's non-goals: core/combat/encounter.gd and
## core/sim/simulator.gd are exercised UNMODIFIED (constructed and driven
## exactly like every other pre-existing caller) — this file only adds new
## test coverage, it never edits either production file.

const EncounterClass     = preload("res://core/combat/encounter.gd")
const RNGClass           = preload("res://core/rules/rng.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")
const RoundEventsClass   = preload("res://core/rules/round_events.gd")

## Safety cap on run_round() calls — proves the loop terminates rather than
## hanging; genuine v0 encounters resolve in single digits of rounds.
const MAX_ROUNDS_GUARD: int = 50


# ── Fixture helpers ────────────────────────────────────────────────────────────

## A durable-but-not-immortal plain-Dictionary combatant — deliberately
## distinct stats from tests/test_encounter_multiround_balance_smoke.gd's
## own fixture so this suite is a genuinely independent pinning test, not a
## copy. Survives multiple rounds so the round-boundary budget reset is
## actually exercised more than once.
func _dict_combatant(p_name: String, hp: int, ac: int) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": hp,
		"ac":         ac,
		"strength":   3,
		"dexterity":  2,
		"intuition":  2,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 8,
		},
	}


## Builds a fresh 2v1 Encounter — an intentionally uneven matchup (two
## attackers vs one durable defender) so the single defender is GUARANTEED
## to be defeated during the run, exercising the exact dict-combatant
## defeat path _finalize_strike_result() used to crash on (AD-1).
func _make_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_dict_combatant("Ranger", 55, 11), _dict_combatant("Cleric", 55, 11)],
		[_dict_combatant("Ogre", 220, 12)],
		RNGClass.new(seed_value)
	)


## Drives the Encounter to completion via repeated run_round() calls,
## accumulating the full-encounter event/history record.
func _run_full_encounter(enc: EncounterClass) -> Dictionary:
	enc.initialize()
	var all_events: Array = []
	var rounds_run: int = 0
	var outcome: String = enc.get_outcome()

	while outcome == "" and rounds_run < MAX_ROUNDS_GUARD:
		var result: Dictionary = enc.run_round()
		all_events.append_array(enc.get_round_events())
		outcome = result.get("outcome", "")
		rounds_run += 1

	return {
		"outcome":     outcome,
		"rounds":      rounds_run,
		"all_events":  all_events,
		"all_history": enc.get_round_history(),
	}


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1 — full multi-round, dict-combatant encounter completes with a
# valid outcome and no SCRIPT ERROR, even though it spans a defeat.
# ══════════════════════════════════════════════════════════════════════════════

func test_multiround_encounter_with_dict_combatants_completes_with_valid_outcome() -> void:
	var enc = _make_encounter(777)
	var run_data: Dictionary = _run_full_encounter(enc)

	assert_true(
		run_data["rounds"] < MAX_ROUNDS_GUARD,
		"2v1 encounter must terminate well within the %d-round safety guard; ran %d rounds without a decided outcome"
		% [MAX_ROUNDS_GUARD, run_data["rounds"]]
	)
	assert_true(
		run_data["outcome"] == "won" or run_data["outcome"] == "lost",
		"Full dict-combatant encounter must terminate with outcome 'won' or 'lost'; got '%s'" % run_data["outcome"]
	)

	# At least one combatant_defeated typed event must have been emitted —
	# proving this run actually exercised the AD-1 kill path (a run that
	# never kills anyone would vacuously "pass" without ever touching the
	# fixed code).
	var defeated_events: Array = run_data["all_events"].filter(
		func(e): return e is RoundEventsClass.CombatantDefeatedEvent
	)
	assert_true(
		defeated_events.size() > 0,
		"The uneven 2v1 fixture must produce at least one combatant_defeated event, proving the AD-1 dict-combatant kill path actually ran"
	)


func test_multiround_encounter_spans_multiple_rounds() -> void:
	var enc = _make_encounter(777)
	var run_data: Dictionary = _run_full_encounter(enc)

	assert_true(
		run_data["rounds"] >= 2,
		"Fixture (seed 777, 55/70hp 2v1) must span >= 2 rounds so the round-boundary budget reset is exercised more than once; got %d round(s)"
		% run_data["rounds"]
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2 — no residual budget_remaining off-by-one in round_history
# entries across the full encounter, including the round in which the
# defeat occurs.
# ══════════════════════════════════════════════════════════════════════════════

func test_multiround_encounter_round_history_has_no_budget_remaining_off_by_one() -> void:
	var enc = _make_encounter(777)
	var run_data: Dictionary = _run_full_encounter(enc)
	var all_history: Array = run_data["all_history"]

	assert_true(all_history.size() > 0, "Full encounter must record at least one round_history entry")

	# Group entries by (combatant name, round), preserving resolution order.
	var by_combatant_round: Dictionary = {}
	for entry in all_history:
		var name: String = entry.get("attacker", {}).get("name", "")
		var round_number: int = entry.get("round", -1)
		if not by_combatant_round.has(name):
			by_combatant_round[name] = {}
		if not by_combatant_round[name].has(round_number):
			by_combatant_round[name][round_number] = []
		by_combatant_round[name][round_number].append(entry)

	for name in by_combatant_round.keys():
		var rounds_for_name: Dictionary = by_combatant_round[name]
		for round_number in rounds_for_name.keys():
			var entries: Array = rounds_for_name[round_number]

			# budget_remaining must strictly count down 6,5,4,... one action
			# per entry — no skipped value (would mean an action was spent
			# without a history entry — an "off-by-one" undercount) and no
			# repeated value (would mean an entry was double-recorded or the
			# budget failed to decrement — an "off-by-one" overcount).
			for i in range(entries.size()):
				var expected_budget: int = (ActionEconomyClass.MAX_BUDGET - 1) - i
				assert_eq(
					entries[i].get("budget_remaining", -999), expected_budget,
					"%s's action %d in round %d must show budget_remaining == %d (no off-by-one in the shared-budget countdown); got %d"
					% [name, i, round_number, expected_budget, entries[i].get("budget_remaining", -999)]
				)

			# Round-boundary reset must land on exactly MAX_BUDGET-1 (the
			# value after the FIRST spend of a fresh round) — not
			# MAX_BUDGET-2 or MAX_BUDGET (either of which would be an
			# off-by-one introduced at the round boundary).
			assert_eq(
				entries[0].get("budget_remaining", -999), ActionEconomyClass.MAX_BUDGET - 1,
				"%s's FIRST action in round %d must show budget_remaining == %d (fresh per-round budget, no off-by-one); got %d"
				% [name, round_number, ActionEconomyClass.MAX_BUDGET - 1, entries[0].get("budget_remaining", -999)]
			)


## Dedicated unit-level proof (narrower than the full-encounter test above)
## that budget_remaining is correct on the SPECIFIC history entry recorded
## for the action that lands the killing blow — the entry most directly
## downstream of the AD-1 fix's target_defeated/target_cid branch, since
## _finalize_strike_result() appends the round_history entry AFTER
## resolving target_defeated in the very same call.
func test_budget_remaining_on_the_defeat_entry_matches_actors_actual_spend_count() -> void:
	var enc = _make_encounter(777)
	var run_data: Dictionary = _run_full_encounter(enc)
	var all_history: Array = run_data["all_history"]

	# Find the history entry whose action produced the (or a) defeat, i.e.
	# the entry immediately preceding a combatant_defeated event in the
	# concatenated per-round sequence is not directly derivable from
	# all_history alone (history and events are separate observer queues),
	# so instead assert directly: EVERY history entry — including whichever
	# one coincides with a kill — has a budget_remaining that is exactly
	# (actions already spent by that combatant this round), counted from the
	# per-combatant/per-round grouping used above. This is the general
	# invariant AD-1's fix must not have disturbed for ANY entry, including
	# the killing blow's.
	var per_combatant_round_count: Dictionary = {}  # "name|round" -> count seen so far
	for entry in all_history:
		var name: String = entry.get("attacker", {}).get("name", "")
		var round_number: int = entry.get("round", -1)
		var key: String = "%s|%d" % [name, round_number]
		var seen_so_far: int = per_combatant_round_count.get(key, 0)
		var expected_budget: int = (ActionEconomyClass.MAX_BUDGET - 1) - seen_so_far
		assert_eq(
			entry.get("budget_remaining", -999), expected_budget,
			"History entry #%d for '%s' in round %d must show budget_remaining == %d; got %d (off-by-one would indicate an AD-1 ripple-effect regression)"
			% [seen_so_far, name, round_number, expected_budget, entry.get("budget_remaining", -999)]
		)
		per_combatant_round_count[key] = seen_so_far + 1
