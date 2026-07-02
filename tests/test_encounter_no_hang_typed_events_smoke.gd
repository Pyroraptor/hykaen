extends GutTest
## tests/test_encounter_no_hang_typed_events_smoke.gd
##
## FEAT-100 (CR-001 final verification, US-004/US-005/US-008): End-to-end
## smoke test of the REMEDIATED encounter round loop, exercising the
## complete entry point (Encounter.run_round() / Encounter.run()) through the
## exit point (correct outcome, typed _round_events/_round_history,
## unmodified N=1000 simulator win-rate) with BOTH fixes applied together:
##
## DEF-005 (US-011) naming note: this suite constructs
## core/combat/encounter.gd DIRECTLY — a construction path MainScene.gd
## documents as intentionally never invoked in production. It is NOT the
## "steel thread" in the sense of booting the real composition root
## (res://MainScene.tscn); that end-to-end boot path is exercised
## exclusively by tests/integration/test_steel_thread_prologue_encounter.gd
## and tests/gut/test_steel_thread_e2e.gd. This file's name intentionally
## avoids the "steel thread"/"steelthread" label to keep that distinction
## unambiguous.
##
##   FIND-095 (CWE-835 unbounded-loop hang) — a side with zero living
##   combatants (empty array, or a non-empty array of already-dead
##   combatants) must decide an outcome immediately, without ever entering
##   the AC-4 cycle loop and without hanging.
##
##   FIND-096 (Clean Architecture gap / untyped events) — run_round()'s
##   cycle algorithm now lives in core/application/run_round_use_case.gd /
##   resolve_action_use_case.gd / determine_outcome_use_case.gd (the
##   Application layer), and the observability surface
##   (_round_events / get_round_history()'s "entry" key) carries TYPED
##   core/rules/round_events.gd value objects (RoundEvents.AttackEvent,
##   RoundEvents.CombatantDefeatedEvent, RoundEvents.EncounterResultEvent,
##   RoundEvents.RoundHistoryEntry) rather than raw Dictionaries.
##
## This suite proves both fixes hold IN COMBINATION — a no-hang guarantee
## that ALSO produces correctly-typed events/history across a real
## multi-round encounter, and an UNMODIFIED core/sim/simulator.gd running
## N=1000 battles against the fixed encounter.gd without hanging.
##
## Scope: test-only. Does NOT modify core/combat/encounter.gd,
## core/sim/simulator.gd, core/application/*, core/rules/*, any
## character/enemy .tres resource, or any damage die.
##
## Test criteria covered (see FEAT-100 spec):
##   1. Encounter.new([living_party], [], rng).run_round() and
##      Encounter.new([living_party], [dead_enemy], rng).run_round() both
##      return promptly (no hang) with correct outcomes.
##   2. A full multi-round 2v2 encounter runs to completion via run() (the
##      entry point) and produces an interleaved A,B,A,B,... attack order
##      verifiable from typed RoundEvents.AttackEvent instances in
##      _round_events.
##   3. get_round_history() contains RoundEvents.RoundHistoryEntry instances
##      (via each entry's "entry" key) with correct, monotonically-consistent
##      budget_remaining values across the FULL encounter (every round, not
##      just the first).
##   4. core/sim/simulator.gd (UNMODIFIED) executes 1000 battles against the
##      fixed encounter.gd to completion without hanging and reports a
##      win_rate value.
##   5. Full GUT headless run of the affected suites passes with zero
##      failures (verified out-of-band by running the suite; not asserted
##      from within this file).
##
## Satisfies: US-004, US-005, US-008, FIND-095, FIND-096

const EncounterClass    = preload("res://core/combat/encounter.gd")
const RNGClass          = preload("res://core/rules/rng.gd")
const SimulatorClass    = preload("res://core/sim/simulator.gd")
const RoundEventsClass  = preload("res://core/rules/round_events.gd")

## Safety cap on the number of run_round() calls per encounter loop — guards
## the TEST process (not production code) against an unexpected
## non-terminating scenario. Genuine v0 encounters with MAX_BUDGET=7 per side
## terminate in single digits of rounds; this is a generous upper bound.
const MAX_ROUNDS_GUARD: int = 50


# ── Fixture helpers ──────────────────────────────────────────────────────────

## A durable combatant (hp=2000) that cannot die mid-round — isolates AC-4
## interleaving behavior from win/loss early-termination.
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


## A moderate-durability combatant: survives several rounds of incoming
## Strikes before dying, so a full encounter genuinely spans MULTIPLE rounds
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


## A dead combatant fixture — already at 0 HP before the round starts (used
## to exercise the FIND-095 "non-empty but fully-dead turn_order" guard path,
## distinct from the "empty array" guard path).
func _dead_combatant(p_name: String) -> Dictionary:
	return {
		"name": p_name, "hp_current": 0, "ac": 10, "intuition": 0, "dexterity": 0,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 0, "damage_die": 4}
	}


## Builds a fresh 2-vs-2 Encounter: two party combatants against two enemy
## combatants, all moderate-durability, seeded deterministically — used to
## exercise a genuine multi-round encounter end-to-end.
func _make_2v2_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_moderate_combatant("Hero1"), _moderate_combatant("Hero2")],
		[_moderate_combatant("Orc1"), _moderate_combatant("Orc2")],
		RNGClass.new(seed_value)
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1 (FIND-095 / CWE-835): the two literal no-hang scenarios named in
# the FEAT-100 spec — a living party against a wholly-absent enemy side, and a
# living party against an enemy side whose only member is already dead — must
# both return PROMPTLY from run_round() with the correct outcome. Each test's
# mere completion (within GUT's normal per-test time budget, rather than
# hanging the runner indefinitely) is itself part of the proof.
# ══════════════════════════════════════════════════════════════════════════════

func test_run_round_with_empty_enemy_array_returns_promptly_with_won_outcome() -> void:
	var living_party: Dictionary = _durable_combatant("Alpha")
	var enc = EncounterClass.new([living_party], [], RNGClass.new(1))
	enc.initialize()

	# Reaching this assertion at all (rather than the test process hanging)
	# is the primary FIND-095 proof for the empty-array guard path.
	var result: Dictionary = enc.run_round()

	assert_eq(
		result.get("outcome", ""), "won",
		"A living party with a wholly empty enemy Array must resolve 'won' immediately without hanging"
	)
	assert_eq(enc.get_outcome(), "won", "get_outcome() must also report 'won' once decided by the up-front guard")
	assert_eq(
		result.get("history", null), [],
		"The up-front guard must decide the outcome WITHOUT entering the cycle loop — no actions resolved, empty history"
	)


func test_run_round_with_already_dead_enemy_returns_promptly_with_won_outcome() -> void:
	var living_party: Dictionary = _durable_combatant("Alpha")
	var dead_enemy: Dictionary = _dead_combatant("Corpse")
	var enc = EncounterClass.new([living_party], [dead_enemy], RNGClass.new(1))
	enc.initialize()

	# _turn_order is non-empty here (it contains the dead enemy) — this
	# exercises the "non-empty but fully-dead turn_order" guard path
	# specifically, distinct from the empty-Array guard path above. Reaching
	# this assertion at all (rather than hanging) is the primary FIND-095
	# proof for this guard path.
	var result: Dictionary = enc.run_round()

	assert_eq(
		result.get("outcome", ""), "won",
		"A living party whose only enemy is already dead must resolve 'won' immediately without hanging, even with a non-empty turn_order"
	)
	assert_eq(enc.get_outcome(), "won", "get_outcome() must also report 'won' once decided by the up-front guard")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2 (FIND-096): a full multi-round 2v2 encounter, driven via run()
# (the steel-thread entry point), terminates with a correct outcome and
# produces an interleaved A,B,A,B,... attack order verifiable from TYPED
# RoundEvents.AttackEvent instances.
# ══════════════════════════════════════════════════════════════════════════════

func test_run_entry_point_drives_full_2v2_encounter_to_correct_outcome() -> void:
	var enc = _make_2v2_encounter(4242)

	# run() is the steel-thread ENTRY POINT named in the FEAT-100 spec — it
	# calls initialize() then loops run_round() internally until decided.
	# Its mere completion (rather than hanging) is itself part of the proof.
	enc.run()

	assert_true(
		enc.get_outcome() == "won" or enc.get_outcome() == "lost",
		"A full 2v2 encounter driven via run() must terminate with outcome 'won' or 'lost'; got '%s'" % enc.get_outcome()
	)
	assert_true(enc.get_round_count() >= 1, "run() must execute at least 1 round")
	assert_true(
		enc.get_round_count() < MAX_ROUNDS_GUARD,
		"run() must terminate well within the %d-round safety guard; ran %d rounds" % [MAX_ROUNDS_GUARD, enc.get_round_count()]
	)


## Interleaving is observable per-round (get_round_events() is cleared at the
## START of each run_round() call) — a single round between two equal-budget
## durable combatants is sufficient to verify the A,B,A,B,... order using
## TYPED RoundEvents.AttackEvent instances (never raw Dictionaries).
func test_round_events_attack_instances_interleave_in_strict_alternation() -> void:
	var enc = EncounterClass.new(
		[_durable_combatant("Alpha")], [_durable_combatant("Bravo")], RNGClass.new(42)
	)
	enc.initialize()
	enc.run_round()

	var events: Array = enc.get_round_events()
	var attack_events: Array = events.filter(func(e): return e is RoundEventsClass.AttackEvent)

	# Both combatants share MAX_BUDGET=7 and neither dies (durable) — each
	# takes exactly 7 actions this round, 14 total interleaved AttackEvents.
	assert_eq(attack_events.size(), 14, "Two durable equal-budget combatants must emit 14 typed AttackEvent instances")
	if attack_events.size() != 14:
		return

	for ev in attack_events:
		assert_true(ev is RoundEventsClass.AttackEvent, "Every 'attack' round event must be a typed RoundEvents.AttackEvent instance")

	# Strict alternation: consecutive AttackEvents must never share an attacker.
	for i in range(attack_events.size() - 1):
		assert_ne(
			attack_events[i].attacker_name, attack_events[i + 1].attacker_name,
			"Consecutive typed AttackEvent instances %d and %d must have different attacker_name (A,B,A,B,... interleaving)" % [i, i + 1]
		)

	# The full A,B,A,B,... pattern, explicitly: even indices are Alpha (the
	# higher-or-equal initiative combatant resolved first within each cycle),
	# odd indices are Bravo.
	var attacker_sequence: Array = []
	for ev in attack_events:
		attacker_sequence.append(ev.attacker_name)
	var first_attacker: String = attacker_sequence[0]
	var second_attacker: String = attacker_sequence[1]
	assert_ne(first_attacker, second_attacker, "Sanity: the two combatants must be distinct")
	for i in range(attack_events.size()):
		var expected: String = first_attacker if i % 2 == 0 else second_attacker
		assert_eq(
			attacker_sequence[i], expected,
			"AttackEvent %d must continue the strict A,B,A,B,... interleave pattern" % i
		)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3 (FIND-096): get_round_history() carries TYPED
# RoundEvents.RoundHistoryEntry instances (via the "entry" key) with correct,
# monotonically-consistent budget_remaining values across the FULL encounter
# — every round, not just the first.
# ══════════════════════════════════════════════════════════════════════════════

func test_round_history_entry_typed_objects_consistent_across_full_encounter() -> void:
	var enc = _make_2v2_encounter(4242)
	enc.initialize()

	var rounds_run: int = 0
	while enc.get_outcome() == "" and rounds_run < MAX_ROUNDS_GUARD:
		enc.run_round()
		rounds_run += 1

	assert_true(rounds_run < MAX_ROUNDS_GUARD, "Full 2v2 encounter must terminate within the safety guard")
	assert_true(
		rounds_run >= 2,
		"Steel-thread fixture (seed 4242, 60hp/ac11 2v2) must span >= 2 rounds so the round-boundary "
		+ "reset assertions below are not vacuous; got %d round(s)" % rounds_run
	)

	var all_history: Array = enc.get_round_history()
	assert_true(all_history.size() > 0, "Full encounter must record at least one round_history entry")

	# Every entry must carry a typed RoundEvents.RoundHistoryEntry under its
	# "entry" key (FEAT-099/FIND-096) — never absent, never a raw Dictionary.
	for entry in all_history:
		assert_true(entry.has("entry"), "Every round_history entry must carry an 'entry' key holding the typed RoundHistoryEntry")
		assert_true(
			entry["entry"] is RoundEventsClass.RoundHistoryEntry,
			"The 'entry' key must hold a typed RoundEvents.RoundHistoryEntry instance, not a raw Dictionary"
		)
		# The typed object's own fields must agree with the surrounding
		# Dictionary's pre-existing keys (both views of the same resolved action).
		var typed_entry = entry["entry"]
		assert_eq(typed_entry.round_number, entry.get("round", -1), "typed entry.round_number must match the Dictionary's 'round' key")
		assert_eq(typed_entry.cycle_index, entry.get("cycle_index", -2), "typed entry.cycle_index must match the Dictionary's 'cycle_index' key")
		assert_eq(typed_entry.budget_remaining, entry.get("budget_remaining", -3), "typed entry.budget_remaining must match the Dictionary's 'budget_remaining' key")
		assert_eq(typed_entry.combatant_id, entry.get("attacker", {}).get("name", ""), "typed entry.combatant_id must match the attacker's name")

	# Group by (combatant name, round) preserving resolved order, to verify
	# the shared-budget countdown and round-boundary reset across the WHOLE
	# encounter (mirrors the pre-existing tests/test_encounter_multiround_balance_smoke.gd
	# pattern, now driven through the typed "entry" objects).
	var by_combatant_round: Dictionary = {}  # name -> { round_number -> Array[typed entry] }
	for entry in all_history:
		var typed_entry = entry["entry"]
		var name: String = typed_entry.combatant_id
		var round_number: int = typed_entry.round_number
		if not by_combatant_round.has(name):
			by_combatant_round[name] = {}
		if not by_combatant_round[name].has(round_number):
			by_combatant_round[name][round_number] = []
		by_combatant_round[name][round_number].append(typed_entry)

	var any_combatant_spans_multiple_rounds: bool = false
	for name in by_combatant_round.keys():
		var rounds_for_name: Dictionary = by_combatant_round[name]
		if rounds_for_name.keys().size() >= 2:
			any_combatant_spans_multiple_rounds = true

		var round_numbers: Array = rounds_for_name.keys()
		round_numbers.sort()

		for round_number in round_numbers:
			var typed_entries: Array = rounds_for_name[round_number]

			# Within a single round, a combatant's budget_remaining must
			# strictly count down 6,5,4,...,(7 - count) — one action per
			# entry (CR-001 AC-3: the shared per-round budget pool).
			for i in range(typed_entries.size()):
				var expected_budget: int = 6 - i
				assert_eq(
					typed_entries[i].budget_remaining, expected_budget,
					"%s's typed entry %d in round %d must show budget_remaining == %d (shared-budget countdown); got %d"
					% [name, i, round_number, expected_budget, typed_entries[i].budget_remaining]
				)

			# Round-boundary reset: the FIRST typed entry a combatant records
			# in any round must again start the countdown at 6 — proving the
			# budget reset at the round boundary (start_of_round()/
			# end_of_round()), not a continuation of a prior round's leftover
			# budget.
			assert_eq(
				typed_entries[0].budget_remaining, 6,
				"%s's FIRST typed entry in round %d must show budget_remaining == 6 (fresh per-round budget at the round boundary); got %d"
				% [name, round_number, typed_entries[0].budget_remaining]
			)

	# Cross-round proof: at least one combatant must have acted in 2+
	# distinct rounds — otherwise the round-boundary-reset assertion above
	# would be vacuously checking only round 1 for every combatant.
	assert_true(
		any_combatant_spans_multiple_rounds,
		"At least one combatant must have recorded typed entries across >= 2 distinct rounds, "
		+ "so the round-boundary reset assertion is exercised more than once"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4 (FIND-095 + FIND-096 in combination): core/sim/simulator.gd
# (UNMODIFIED per CR-001 scope) executes N=1000 battles against the FIXED
# encounter.gd to completion without hanging, and reports a valid win_rate.
# ══════════════════════════════════════════════════════════════════════════════

func test_unmodified_simulator_runs_n1000_against_fixed_encounter_without_hanging() -> void:
	var sim = SimulatorClass.new()

	# sim.run(1000, ...) internally constructs 1000 fresh Encounter instances
	# and calls enc.run() (the entry point) on each, exactly as a real game
	# loop would — exercising both FIND-095 (no encounter may hang, even if
	# RNG produces a one-sided fixture) and FIND-096 (the typed event/history
	# surface, indirectly, via get_round_history() inside simulator.gd) 1000
	# times over. Mere completion of this call (rather than hanging the test
	# process for 1000 encounters) is itself the primary FIND-095 proof at scale.
	var sim_result: Dictionary = sim.run(1000, 31415)

	assert_true(sim_result.has("win_rate"), "Unmodified simulator.gd must return a Dictionary with 'win_rate'")
	assert_eq(sim_result.get("total_battles", -1), 1000, "simulator.run(1000, ...) must report total_battles == 1000")

	var win_rate: float = sim_result.get("win_rate", -1.0)
	assert_true(
		win_rate >= 0.0 and win_rate <= 1.0,
		"N=1000 win_rate must be a valid proportion in [0.0, 1.0]; got %f" % win_rate
	)
	gut.p("FEAT-100 STEEL THREAD N=1000 SMOKE: win_rate=%f total_battles=%d avg_rounds=%f"
		% [win_rate, sim_result.get("total_battles", -1), sim_result.get("avg_rounds", -1.0)])


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1+2+3 combined: the SAME Encounter instance whose construction
# exercises a FIND-095 guard path (a side starts with zero living combatants)
# must ALSO be capable of producing correctly-typed events on a SEPARATE,
# independent encounter that proceeds normally — proving the guard paths and
# the typed-event paths are not mutually exclusive code paths that happen to
# each work in isolation, but are both reachable in the SAME run_round_use_case
# implementation.
# ══════════════════════════════════════════════════════════════════════════════

func test_no_hang_guard_path_and_typed_event_path_coexist_in_same_suite_run() -> void:
	# First: a FIND-095 guard-path encounter — must resolve immediately
	# without entering the cycle loop, hence zero typed events emitted other
	# than the terminal EncounterResultEvent.
	var guarded_enc = EncounterClass.new([_durable_combatant("Solo")], [], RNGClass.new(2024))
	guarded_enc.initialize()
	var guarded_result: Dictionary = guarded_enc.run_round()
	assert_eq(guarded_result.get("outcome", ""), "won", "Guard-path encounter must resolve 'won' without hanging")

	var guarded_events: Array = guarded_enc.get_round_events()
	assert_eq(guarded_events.size(), 1, "The up-front guard path emits exactly one event: the terminal EncounterResultEvent")
	assert_true(
		guarded_events[0] is RoundEventsClass.EncounterResultEvent,
		"The guard path's single emitted event must be a typed RoundEvents.EncounterResultEvent"
	)
	assert_eq(guarded_events[0].outcome, "won", "The typed EncounterResultEvent's outcome must match the RoundResult's outcome")

	# Second: an ordinary cycling encounter, run in the SAME test — must
	# still produce the full typed AttackEvent interleave, proving the guard
	# path did not somehow short-circuit or corrupt the normal cycle path.
	var normal_enc = EncounterClass.new(
		[_durable_combatant("X")], [_durable_combatant("Y")], RNGClass.new(2025)
	)
	normal_enc.initialize()
	normal_enc.run_round()
	var normal_events: Array = normal_enc.get_round_events()
	var normal_attack_events: Array = normal_events.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(normal_attack_events.size(), 14, "An ordinary durable-vs-durable round must still emit 14 typed AttackEvent instances")
	assert_eq(normal_enc.get_outcome(), "", "Neither combatant dies — outcome must remain undecided for the ordinary encounter")
