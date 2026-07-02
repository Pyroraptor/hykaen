extends GutTest
## tests/test_encounter_multiround_balance_smoke.gd
##
## FEAT-010 (CR-001 AC-4/AC-5, US-004/US-008): Multi-Round Encounter
## Integration Test and N=1000 Balance Simulation Smoke Test.
##
## DEF-005 (US-011) naming note: this suite constructs
## core/combat/encounter.gd DIRECTLY (EncounterClass.new(...).run_round()) —
## a construction path MainScene.gd documents as intentionally never invoked
## in production. It is NOT the "steel thread" in the sense of booting the
## real composition root (res://MainScene.tscn); that end-to-end boot path is
## exercised exclusively by
## tests/integration/test_steel_thread_prologue_encounter.gd and
## tests/gut/test_steel_thread_e2e.gd. This file's name intentionally avoids
## the "steel thread" label to keep that distinction unambiguous.
##
## This is the FINAL CR-001 verification for the multi-round round loop:
##   entry point  — Encounter.run_round() begins a new round and cycles
##                   through _turn_order
##   exit point   — the round terminates with a correct win/loss outcome,
##                   _round_events/_round_history accurately reflect the
##                   corrected per-round economy across the WHOLE encounter
##                   (every round, not just the first), and the N=1000
##                   simulator win-rate reflects it.
##
## Scope (per the FEAT-010 design notes): this file is test-only. It does
## NOT modify core/combat/encounter.gd, core/sim/simulator.gd, any
## character/enemy .tres resource, or any damage die — it exercises the
## real, unmodified production code exactly as written by prior CR-001
## features (FEAT-004 through FEAT-009).
##
## Test criteria covered:
##   1. A full multi-combatant (2v2) encounter is run end-to-end via
##      repeated Encounter.run_round() calls until a win/loss/draw outcome
##      is reached; the outcome is asserted to be exactly 'won' or 'lost'.
##   2. _round_events, concatenated across every round of the encounter,
##      are emitted in the correct shape: only 'attack' / 'combatant_defeated'
##      events occur before the single terminal 'encounter_result' event,
##      which (when present) is always last; every 'combatant_defeated'
##      event is preceded by at least one 'attack' event against that name.
##   3. _round_history entries, across the FULL encounter (every round),
##      all carry budget_remaining values consistent with the shared-budget,
##      round-boundary-reset rules: each combatant's budget strictly counts
##      down by 1 per resolved action within a round, and resets back to
##      MAX_BUDGET-1 (6, the value after the FIRST spend) at the start of
##      every subsequent round.
##   4. core/sim/simulator.gd (unmodified) run at N=1000 against the fixed
##      encounter.gd produces a SimulationReport{win_rate, n:1000} — the
##      report shape is assembled by THIS TEST FILE around simulator.gd's
##      unmodified return Dictionary, with no edits to simulator.gd,
##      character .tres stats, or damage dice.
##   5. The SimulationReport includes flag:'OUT_OF_BALANCE_RANGE' when
##      win_rate falls outside [0.40, 0.80], and omits/falsifies the flag
##      otherwise — verified both against the live N=1000 run and against
##      synthetic win_rate fixtures so both branches are deterministically
##      exercised (a single live run cannot be relied upon to land outside
##      the balance window).
##
## Satisfies: US-004, US-008, FR-008, CR-001 AC-4, CR-001 AC-5

const EncounterClass  = preload("res://core/combat/encounter.gd")
const RNGClass        = preload("res://core/rules/rng.gd")
const SimulatorClass  = preload("res://core/sim/simulator.gd")

## Safety cap on the number of run_round() calls per encounter loop — guards
## against an unexpected non-terminating scenario hanging the test process.
## Genuine v0 encounters with MAX_BUDGET=7 per side terminate in single
## digits of rounds; this is a generous upper bound, never expected to bind.
const MAX_ROUNDS_GUARD: int = 50


# ── Fixture helpers ────────────────────────────────────────────────────────────

## A moderate-durability combatant: survives several rounds of incoming
## Strikes before dying, so the encounter genuinely spans MULTIPLE rounds
## (exercising the round-boundary budget reset) rather than resolving in a
## single round.
func _moderate_combatant(p_name: String) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": 60,
		"ac":         11,
		"strength":   3,
		"dexterity":  2,
		"intuition":  2,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	}


## Builds a fresh 2-vs-2 Encounter: two party combatants against two enemy
## combatants, all moderate-durability, seeded deterministically.
func _make_2v2_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_moderate_combatant("Hero1"), _moderate_combatant("Hero2")],
		[_moderate_combatant("Orc1"), _moderate_combatant("Orc2")],
		RNGClass.new(seed_value)
	)


## _run_full_encounter(enc) → Dictionary{outcome, rounds, all_events, all_history}
##
## Drives the Encounter to completion by repeatedly calling run_round() —
## the steel-thread entry point — exactly as a real game loop would, while
## independently accumulating the per-round observer queue (get_round_events()
## is cleared at the START of every run_round() call, so it must be captured
## immediately after each call to reconstruct the FULL encounter's event
## sequence across every round).
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
		"all_history": enc.get_round_history()
	}


## _build_simulation_report(sim_result) → Dictionary{win_rate, n, [flag]}
##
## Wraps simulator.gd's UNMODIFIED return Dictionary (win_rate, avg_rounds,
## total_damage_dealt, total_battles, confidence_interval) into the
## SimulationReport{win_rate, n} shape required by the FEAT-010 exit
## criteria, and attaches flag:'OUT_OF_BALANCE_RANGE' when win_rate falls
## outside [0.40, 0.80]. This composition lives entirely in the TEST file —
## simulator.gd itself is never edited to produce this shape.
func _build_simulation_report(sim_result: Dictionary) -> Dictionary:
	var win_rate: float = sim_result.get("win_rate", 0.0)
	var report: Dictionary = {
		"win_rate": win_rate,
		"n":        sim_result.get("total_battles", 0),
	}
	if win_rate < 0.40 or win_rate > 0.80:
		report["flag"] = "OUT_OF_BALANCE_RANGE"
	return report


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1 — full multi-combatant encounter terminates with a correct
# win/loss/draw outcome via repeated run_round() calls.
# ══════════════════════════════════════════════════════════════════════════════

func test_full_2v2_encounter_terminates_with_valid_outcome() -> void:
	var enc = _make_2v2_encounter(4242)
	var run_data: Dictionary = _run_full_encounter(enc)

	assert_true(
		run_data["rounds"] < MAX_ROUNDS_GUARD,
		"2v2 encounter must terminate well within the %d-round safety guard; ran %d rounds without a decided outcome"
		% [MAX_ROUNDS_GUARD, run_data["rounds"]]
	)
	assert_true(
		run_data["outcome"] == "won" or run_data["outcome"] == "lost",
		"Full multi-combatant encounter must terminate with outcome 'won' or 'lost'; got '%s'" % run_data["outcome"]
	)
	assert_true(
		run_data["rounds"] >= 1,
		"Full encounter must execute at least 1 round; got %d" % run_data["rounds"]
	)
	assert_eq(
		enc.get_outcome(), run_data["outcome"],
		"Encounter.get_outcome() must match the outcome reported by the final run_round() call"
	)


## A multi-round encounter is required to genuinely exercise the
## round-boundary budget reset (Criterion 3 below needs >= 2 rounds to be
## meaningful) — this test pins that the chosen fixture/seed actually spans
## more than one round, so the budget-reset assertions are not vacuous.
func test_full_2v2_encounter_spans_multiple_rounds() -> void:
	var enc = _make_2v2_encounter(4242)
	var run_data: Dictionary = _run_full_encounter(enc)

	assert_true(
		run_data["rounds"] >= 2,
		"Steel-thread fixture (seed 4242, 60hp/ac11 2v2) must span >= 2 rounds to exercise the "
		+ "round-boundary budget reset across rounds; got %d round(s)" % run_data["rounds"]
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2 — _round_events, concatenated across the FULL encounter, are
# emitted in the correct shape: attack*/combatant_defeated* before a single
# terminal encounter_result, which is always last when present.
# ══════════════════════════════════════════════════════════════════════════════

func test_full_encounter_events_emitted_in_correct_order() -> void:
	var enc = _make_2v2_encounter(4242)
	var run_data: Dictionary = _run_full_encounter(enc)
	var all_events: Array = run_data["all_events"]

	assert_true(all_events.size() > 0, "Full encounter must emit at least one round event")

	# Every event must be one of the three documented types.
	for ev in all_events:
		var t: String = ev.get("type", "")
		assert_true(
			t == "attack" or t == "combatant_defeated" or t == "encounter_result",
			"Every round event must have type in ['attack','combatant_defeated','encounter_result']; got '%s'" % t
		)

	# Exactly one terminal encounter_result event across the whole encounter,
	# and it must be the LAST event emitted overall.
	var result_events: Array = all_events.filter(func(e): return e.get("type", "") == "encounter_result")
	assert_eq(
		result_events.size(), 1,
		"Exactly one terminal 'encounter_result' event must be emitted across the full encounter; got %d"
		% result_events.size()
	)
	if result_events.size() == 1:
		assert_eq(
			all_events[all_events.size() - 1].get("type", ""), "encounter_result",
			"'encounter_result' must be the LAST event in the full encounter's concatenated event sequence"
		)
		assert_eq(
			result_events[0].get("outcome", ""), run_data["outcome"],
			"The terminal encounter_result event's outcome must match the final run_round() outcome"
		)

	# No 'attack' or 'combatant_defeated' event may occur AFTER the terminal
	# encounter_result — i.e. encounter_result, when present, is strictly
	# last; every event before it is an 'attack' or 'combatant_defeated'.
	for i in range(all_events.size() - 1):
		assert_ne(
			all_events[i].get("type", ""), "encounter_result",
			"'encounter_result' may only appear as the FINAL event; found a non-terminal occurrence at index %d" % i
		)

	# Every 'combatant_defeated' event must be preceded (earlier in the
	# concatenated sequence) by at least one 'attack' event against that
	# same combatant — a defeat cannot occur without a prior attack causing it.
	var attacked_names: Dictionary = {}
	for ev in all_events:
		var t: String = ev.get("type", "")
		if t == "attack":
			attacked_names[ev.get("target_name", "")] = true
		elif t == "combatant_defeated":
			var defeated_name: String = ev.get("name", "")
			assert_true(
				attacked_names.get(defeated_name, false),
				"combatant_defeated event for '%s' must be preceded by at least one prior 'attack' event targeting it"
				% defeated_name
			)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3 — _round_history entries across the FULL encounter all carry
# budget_remaining values consistent with the shared-budget,
# round-boundary-reset rules.
# ══════════════════════════════════════════════════════════════════════════════

func test_full_encounter_round_history_budget_remaining_consistent_with_round_reset() -> void:
	var enc = _make_2v2_encounter(4242)
	var run_data: Dictionary = _run_full_encounter(enc)
	var all_history: Array = run_data["all_history"]

	assert_true(all_history.size() > 0, "Full encounter must record at least one round_history entry")

	# Group entries by (combatant name, round) preserving resolved order.
	var by_combatant_round: Dictionary = {}  # name -> { round_number -> Array[entry] }
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
		var round_numbers: Array = rounds_for_name.keys()
		round_numbers.sort()

		for round_number in round_numbers:
			var entries: Array = rounds_for_name[round_number]

			# Within a single round, a combatant's budget_remaining must
			# strictly count down 6,5,4,...,(7 - count) — one action per
			# entry, never skipping, never repeating a value (CR-001 AC-3:
			# the shared per-round budget pool, decremented by 1 per spend).
			for i in range(entries.size()):
				var expected_budget: int = 6 - i
				assert_eq(
					entries[i].get("budget_remaining", -999), expected_budget,
					"%s's action %d in round %d must show budget_remaining == %d (shared-budget countdown); got %d"
					% [name, i, round_number, expected_budget, entries[i].get("budget_remaining", -999)]
				)

			# Round-boundary reset: the FIRST action a combatant takes in
			# round N+1 must again start the countdown at 6 — proving the
			# budget reset at the round boundary (start_of_round()/
			# end_of_round()), not a continuation of a prior round's
			# leftover budget.
			assert_eq(
				entries[0].get("budget_remaining", -999), 6,
				"%s's FIRST action in round %d must show budget_remaining == 6 (fresh per-round budget granted at the round boundary); got %d"
				% [name, round_number, entries[0].get("budget_remaining", -999)]
			)

	# Cross-round proof: at least one combatant must have acted in 2+
	# distinct rounds, each restarting its countdown at 6 — otherwise the
	# round-boundary-reset assertion above would be checking only round 1
	# for every combatant (vacuously consistent with a single-round bug).
	var any_combatant_spans_multiple_rounds: bool = false
	for name in by_combatant_round.keys():
		if by_combatant_round[name].keys().size() >= 2:
			any_combatant_spans_multiple_rounds = true
			break
	assert_true(
		any_combatant_spans_multiple_rounds,
		"At least one combatant must have recorded actions across >= 2 distinct rounds, "
		+ "so the round-boundary reset assertion is exercised more than once"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4 — core/sim/simulator.gd (UNMODIFIED) run at N=1000 against the
# fixed encounter.gd produces a SimulationReport{win_rate, n:1000}.
# ══════════════════════════════════════════════════════════════════════════════

func test_simulator_n1000_unmodified_produces_simulation_report() -> void:
	var sim = SimulatorClass.new()
	var sim_result: Dictionary = sim.run(1000, 12345)

	# Sanity: simulator.gd's own (unmodified) Dictionary contract is intact.
	assert_true(sim_result.has("win_rate"), "simulator.run(1000, ...) must return a Dictionary with 'win_rate' (unmodified contract)")
	assert_true(sim_result.has("total_battles"), "simulator.run(1000, ...) must return a Dictionary with 'total_battles' (unmodified contract)")
	assert_eq(
		sim_result.get("total_battles", -1), 1000,
		"simulator.run(1000, ...) must report total_battles == 1000 (unmodified simulator.gd, N=1000 per FR-008)"
	)

	# The SimulationReport{win_rate, n} shape required by FEAT-010, assembled
	# in this test file around simulator.gd's unmodified output.
	var report: Dictionary = _build_simulation_report(sim_result)
	assert_true(report.has("win_rate"), "SimulationReport must contain 'win_rate'")
	assert_true(report.has("n"), "SimulationReport must contain 'n'")
	assert_eq(report["n"], 1000, "SimulationReport.n must equal 1000 (FR-008 minimum sample size)")
	assert_true(
		report["win_rate"] >= 0.0 and report["win_rate"] <= 1.0,
		"SimulationReport.win_rate must be a valid proportion in [0.0, 1.0]; got %f" % report["win_rate"]
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5 — SimulationReport carries flag:'OUT_OF_BALANCE_RANGE' when
# win_rate falls outside [0.40, 0.80], and omits/falsifies it otherwise.
# Exercised against BOTH the live N=1000 run and synthetic fixtures so both
# branches of the flagging logic are deterministically proven (a single live
# run is not guaranteed to land outside the balance window).
# ══════════════════════════════════════════════════════════════════════════════

func test_live_n1000_report_flag_matches_balance_window() -> void:
	var sim = SimulatorClass.new()
	var sim_result: Dictionary = sim.run(1000, 12345)
	var report: Dictionary = _build_simulation_report(sim_result)
	var win_rate: float = report["win_rate"]

	if win_rate < 0.40 or win_rate > 0.80:
		assert_eq(
			report.get("flag", ""), "OUT_OF_BALANCE_RANGE",
			"win_rate=%f falls outside [0.40, 0.80] — SimulationReport must carry flag:'OUT_OF_BALANCE_RANGE'" % win_rate
		)
	else:
		assert_false(
			report.has("flag"),
			"win_rate=%f falls inside [0.40, 0.80] — SimulationReport must omit the flag key" % win_rate
		)
		gut.p("STEEL THREAD N=1000 BALANCE REPORT: win_rate=%f n=%d (in-balance, no flag)" % [win_rate, report["n"]])


func test_simulation_report_flags_out_of_range_win_rate_synthetic() -> void:
	# Synthetic fixtures deterministically exercise the OUT_OF_BALANCE_RANGE
	# branch without depending on the live simulator landing outside the
	# window (which it should not, under a balanced v0 encounter).
	var too_low: Dictionary = _build_simulation_report({"win_rate": 0.10, "total_battles": 1000})
	assert_eq(
		too_low.get("flag", ""), "OUT_OF_BALANCE_RANGE",
		"win_rate=0.10 (< 0.40) must produce flag:'OUT_OF_BALANCE_RANGE'"
	)

	var too_high: Dictionary = _build_simulation_report({"win_rate": 0.95, "total_battles": 1000})
	assert_eq(
		too_high.get("flag", ""), "OUT_OF_BALANCE_RANGE",
		"win_rate=0.95 (> 0.80) must produce flag:'OUT_OF_BALANCE_RANGE'"
	)


func test_simulation_report_omits_flag_for_in_range_win_rate_synthetic() -> void:
	var lower_edge: Dictionary = _build_simulation_report({"win_rate": 0.40, "total_battles": 1000})
	assert_false(lower_edge.has("flag"), "win_rate==0.40 is inside the closed interval — flag must be omitted")

	var mid: Dictionary = _build_simulation_report({"win_rate": 0.60, "total_battles": 1000})
	assert_false(mid.has("flag"), "win_rate==0.60 is well inside [0.40, 0.80] — flag must be omitted")

	var upper_edge: Dictionary = _build_simulation_report({"win_rate": 0.80, "total_battles": 1000})
	assert_false(upper_edge.has("flag"), "win_rate==0.80 is inside the closed interval — flag must be omitted")


func test_simulation_report_n_field_reflects_battle_count_not_simulator_edited() -> void:
	## Proves the report's 'n' field is derived purely from simulator.gd's own
	## (unmodified) total_battles output — no hardcoded literal in the report
	## builder — by checking two different battle_count values both flow
	## through correctly.
	var sim = SimulatorClass.new()
	var small_result: Dictionary = sim.run(10, 1)
	var small_report: Dictionary = _build_simulation_report(small_result)
	assert_eq(small_report["n"], 10, "SimulationReport.n must mirror whatever battle_count simulator.gd was actually run with")

	var large_result: Dictionary = sim.run(1000, 1)
	var large_report: Dictionary = _build_simulation_report(large_result)
	assert_eq(large_report["n"], 1000, "SimulationReport.n must mirror whatever battle_count simulator.gd was actually run with")
