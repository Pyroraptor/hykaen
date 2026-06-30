extends GutTest
## tests/test_encounter_round_loop.gd
##
## GUT test suite for FEAT-006 / US-004 (CR-001 AC-4): the interleaved
## cycle-based round loop in core/combat/encounter.gd's run_round().
##
## Validates the AC-4 algorithm:
##   1. start_of_round() is granted once per combatant, then _turn_order is
##      cycled repeatedly; each living, non-Spent combatant takes EXACTLY
##      ONE action per cycle pass — Strikes therefore INTERLEAVE in
##      initiative order (e.g. A,B,A,B,... for two combatants) instead of
##      one side firing all of its actions before the other acts.
##   2. Dead/Spent combatants are skipped WITHOUT consuming a cycle slot —
##      the other living combatants keep getting exactly one action per
##      cycle regardless.
##   3. The round terminates once every living combatant is Spent, even
##      when the outcome is not yet decided.
##   4. A failed spend_action()/spend_reaction() Result (ALREADY_SPENT) is
##      treated as "skip this combatant, continue the cycle" — never an
##      abort/crash.
##   5. run_round() with an empty/invalid _turn_order returns
##      RoundResult{outcome: 'DRAW'} and logs push_warning() rather than
##      throwing.
##
## Note on push_warning() capture: GUT's push_error/push_warning capture
## relies on OS.add_logger(), a Godot 4.4+ API that is a documented no-op
## on this project's pinned Godot 4.3 engine (see addons/gut/error_tracker.gd
## and the identical note in tests/unit/test_action_economy.gd). Rather than
## relying on assert_push_warning() — which cannot observe anything on 4.3 —
## this suite asserts the no-throw/DRAW-result CONTRACT directly, plus a
## source-inspection check that the push_warning() call site exists.

const EncounterClass     = preload("res://core/combat/encounter.gd")
const RNGClass           = preload("res://core/rules/rng.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")


# ── Shared fixture helpers ─────────────────────────────────────────────────────

## A durable combatant (hp=2000) that cannot die mid-round — used to isolate
## the AC-4 cycling/interleaving behavior from win/loss early-termination.
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
## landed against it — used to test the dead-combatant-skip behavior.
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


## Returns the set of distinct cycle_index values present in `entries`, as an
## Array sorted ascending (helper for asserting "exactly one action per cycle").
func _distinct_cycle_indices(entries: Array) -> Array:
	var seen: Dictionary = {}
	for e in entries:
		seen[e.get("cycle_index", -1)] = true
	var result: Array = seen.keys()
	result.sort()
	return result


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: Interleaved Strike order (A,B,A,B,...) across two opposing
# combatants with equal (MAX_BUDGET) budgets.
# ══════════════════════════════════════════════════════════════════════════════

func test_interleaved_strike_order_two_equal_budget_combatants() -> void:
	var enc = EncounterClass.new(
		[_durable_combatant("Alpha")], [_durable_combatant("Bravo")], RNGClass.new(42)
	)
	enc.initialize()
	var result: Dictionary = enc.run_round()

	var history: Array = result.get("history", [])
	# Both combatants share MAX_BUDGET=7 and neither dies (durable) → each
	# takes exactly 7 actions this round → 14 total interleaved entries.
	assert_eq(
		history.size(), 14,
		"Two durable equal-budget combatants must produce 14 history entries (7 each) in round 1"
	)
	if history.size() != 14:
		return

	# Strict alternation: consecutive entries must never share the same attacker.
	for i in range(history.size() - 1):
		var attacker_a: String = history[i].get("attacker", {}).get("name", "")
		var attacker_b: String = history[i + 1].get("attacker", {}).get("name", "")
		assert_ne(
			attacker_a, attacker_b,
			"History entries %d and %d must have different attackers (interleaved Strike order, AC-4); got '%s' twice"
			% [i, i + 1, attacker_a]
		)

	# Each pair of consecutive entries belongs to the same cycle_index, and
	# cycle_index strictly increases pair-over-pair (0,0,1,1,2,2,...,6,6).
	for k in range(7):
		var first: Dictionary  = history[2 * k]
		var second: Dictionary = history[2 * k + 1]
		assert_eq(
			first.get("cycle_index", -1), k,
			"Entry %d must belong to cycle_index %d" % [2 * k, k]
		)
		assert_eq(
			second.get("cycle_index", -1), k,
			"Entry %d must belong to cycle_index %d" % [2 * k + 1, k]
		)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: Spent/dead combatants are skipped within a cycle without
# consuming a slot for that cycle — the other living combatants still get
# exactly one action per cycle.
# ══════════════════════════════════════════════════════════════════════════════

func test_dead_combatant_skipped_without_consuming_cycle_slot() -> void:
	# Party: Fragile (dies almost immediately) + Durable (survives the round).
	# Enemy: Durable (survives the round).
	# Neither side is ever fully wiped out, so the round only ends once every
	# LIVING combatant (Durable party member + Durable enemy) is Spent —
	# proving Fragile's death does not stall or shortchange the others.
	var fragile: Dictionary = _fragile_combatant("Fragile")
	var durable_party: Dictionary = _durable_combatant("DurableParty")
	var durable_enemy: Dictionary = _durable_combatant("DurableEnemy")

	var enc = EncounterClass.new(
		[fragile, durable_party], [durable_enemy], RNGClass.new(7)
	)
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var history: Array = result.get("history", [])

	var fragile_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Fragile")
	var party_entries: Array   = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "DurableParty")
	var enemy_entries: Array   = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "DurableEnemy")

	# Fragile dies on the first attack landed against it (ac=1, hp=1) —
	# at most 1 action before death, regardless of initiative order.
	assert_true(
		fragile_entries.size() <= 1,
		"Fragile (hp=1, ac=1) must die on the first attack against it — expected <= 1 action; got %d"
		% fragile_entries.size()
	)

	# DurableParty and DurableEnemy both survive the entire round and must
	# each get their FULL 7 actions — Fragile's death must NOT have consumed
	# a cycle slot on their behalf, and must not have caused the round to end
	# early (since the encounter is not yet decided — DurableParty is alive).
	assert_eq(
		party_entries.size(), 7,
		"DurableParty must take exactly 7 actions this round despite Fragile's death; got %d"
		% party_entries.size()
	)
	assert_eq(
		enemy_entries.size(), 7,
		"DurableEnemy must take exactly 7 actions this round despite Fragile's death; got %d"
		% enemy_entries.size()
	)

	# Exactly one action per cycle for each surviving combatant: 7 distinct
	# cycle_index values, 0 through 6, no gaps and no duplicates.
	assert_eq(
		_distinct_cycle_indices(party_entries), [0, 1, 2, 3, 4, 5, 6],
		"DurableParty must act in cycles 0-6 with no gaps (no slot consumed by Fragile's skip)"
	)
	assert_eq(
		_distinct_cycle_indices(enemy_entries), [0, 1, 2, 3, 4, 5, 6],
		"DurableEnemy must act in cycles 0-6 with no gaps (no slot consumed by Fragile's skip)"
	)

	# The encounter must NOT be decided — only Fragile died, both sides still
	# have a living combatant (DurableParty / DurableEnemy).
	assert_eq(
		enc.get_outcome(), "",
		"Outcome must remain undecided — Fragile's death alone must not end the encounter"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: The round loop terminates correctly when all living combatants
# reach is_spent()==true (independent of any win/loss decision).
# ══════════════════════════════════════════════════════════════════════════════

func test_round_terminates_when_all_living_combatants_spent() -> void:
	var enc = EncounterClass.new(
		[_durable_combatant("X")], [_durable_combatant("Y")], RNGClass.new(123)
	)
	enc.initialize()

	# If run_round() failed to terminate (e.g. an infinite cycling bug), this
	# call itself would hang the test process — its mere completion plus the
	# assertions below prove correct termination.
	var result: Dictionary = enc.run_round()
	var history: Array = result.get("history", [])

	assert_eq(enc.get_outcome(), "",
		"Neither combatant dies (durable) — outcome must remain undecided; the round must have "
		+ "terminated purely because every living combatant reached is_spent()==true")

	# end_of_round() (called once run_round() finishes cycling) resets every
	# combatant's budget back to MAX_BUDGET per CR-001 AC-2 — so the Spent
	# state that actually TERMINATED the cycle loop is only observable via
	# the round_history trail, not via post-call ActionEconomy inspection.
	assert_eq(
		history.size(), 14,
		"A terminated round with two equal-budget durable combatants must record exactly 14 actions (7 each)"
	)
	var x_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "X")
	var y_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Y")
	assert_eq(x_entries.size(), 7, "X must take exactly 7 actions before being Spent")
	assert_eq(y_entries.size(), 7, "Y must take exactly 7 actions before being Spent")
	assert_eq(
		x_entries[x_entries.size() - 1].get("budget_remaining", -1), 0,
		"X's final recorded action must show budget_remaining==0 (the Spent state that ended the cycle loop)"
	)
	assert_eq(
		y_entries[y_entries.size() - 1].get("budget_remaining", -1), 0,
		"Y's final recorded action must show budget_remaining==0 (the Spent state that ended the cycle loop)"
	)

	# CR-001 AC-2: end_of_round() grants the fresh per-round budget back —
	# this is the expected POST-round state, proving the round boundary
	# reset fired (rather than the loop simply giving up mid-cycle).
	assert_false(
		enc.get_action_economy(0).is_spent(),
		"end_of_round() must reset is_spent()==false once the terminated round completes (AC-2)"
	)
	assert_eq(
		enc.get_action_economy(0).get_remaining(), 7,
		"end_of_round() must reset budget_remaining to MAX_BUDGET once the terminated round completes (AC-2)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: A failed spend_action()/spend_reaction() Result (ALREADY_SPENT)
# causes the loop to skip that combatant's action and continue — never
# abort/crash the round.
# ══════════════════════════════════════════════════════════════════════════════

func test_already_spent_result_skips_and_continues_without_crashing() -> void:
	var enc = EncounterClass.new(
		[_durable_combatant("X")], [_durable_combatant("Y")], RNGClass.new(321)
	)
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var history: Array = result.get("history", [])

	# Both combatants reach is_spent()==true at budget 0; no 8th entry was
	# ever recorded for either — proving the engine skipped (rather than
	# crashed on) every subsequent ALREADY_SPENT attempt and the round
	# continued cleanly through to completion for the OTHER combatant.
	var x_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "X")
	var y_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Y")
	assert_eq(x_entries.size(), 7, "X must have exactly 7 recorded actions, never 8+ (ALREADY_SPENT skipped)")
	assert_eq(y_entries.size(), 7, "Y must have exactly 7 recorded actions, never 8+ (ALREADY_SPENT skipped)")

	var x_last: Dictionary = x_entries[x_entries.size() - 1]
	assert_eq(x_last.get("budget_remaining", -1), 0,
		"X's 7th (final) action must show budget_remaining==0 (Spent reached)")

	# The round itself completed and returned a well-formed RoundResult —
	# proof the engine did not abort/crash once X and Y each hit the
	# is_spent()==true boundary partway through the cycle loop.
	assert_true(result.has("round_number"), "run_round() must return a RoundResult with round_number")
	assert_true(result.has("outcome"), "run_round() must return a RoundResult with outcome")
	assert_true(result.has("history"), "run_round() must return a RoundResult with history")

	# Directly exercise the exact ActionEconomy contract run_round() relies
	# on internally to implement "skip and continue rather than abort/crash":
	# spend_action() on an already-Spent combatant returns a failed Result
	# (success:false, error:'Spent') rather than throwing. (A fresh
	# ActionEconomy is used here because end_of_round() — called once
	# run_round() finishes cycling, per CR-001 AC-2 — resets the round's own
	# instances back to a fresh budget, so the Spent state mid-round is not
	# observable via post-call inspection; round_history above is the proof
	# that this exact contract fired correctly during the live round.)
	var ae_standalone = ActionEconomyClass.new()
	ae_standalone.start_of_round()
	for _i in range(ActionEconomyClass.MAX_BUDGET):
		ae_standalone.spend_action({})
	assert_true(ae_standalone.is_spent(), "sanity check: standalone ActionEconomy must be Spent after MAX_BUDGET spends")
	var post_spend: Dictionary = ae_standalone.spend_action({})
	assert_false(
		post_spend["success"],
		"spend_action() on an already-Spent ActionEconomy must return success:false (ALREADY_SPENT contract)"
	)
	assert_eq(
		post_spend["error"], "Spent",
		"spend_action() on an already-Spent ActionEconomy must report error:'Spent'"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5: run_round() with empty/invalid turn order returns
# RoundResult{outcome: DRAW} and logs push_warning rather than throwing.
# ══════════════════════════════════════════════════════════════════════════════

func test_run_round_empty_turn_order_returns_draw_result() -> void:
	# Deliberately skip initialize() so _turn_order stays at its default
	# empty Array — simulates a malformed/uninitialized encounter.
	var enc = EncounterClass.new([], [], RNGClass.new(1))

	# Must not throw/crash — reaching the assertions below already proves it.
	var result: Dictionary = enc.run_round()

	assert_true(result is Dictionary, "run_round() with empty turn order must still return a Dictionary RoundResult")
	assert_eq(
		result.get("outcome", ""), "DRAW",
		"run_round() with empty/invalid turn order must return RoundResult.outcome == 'DRAW'"
	)
	assert_eq(
		result.get("history", null), [],
		"run_round() with empty/invalid turn order must return an empty RoundResult.history"
	)
	assert_true(
		result.has("round_number"),
		"run_round() with empty/invalid turn order must still report round_number"
	)


func test_run_round_empty_turn_order_does_not_throw_and_round_count_advances() -> void:
	var enc = EncounterClass.new([], [], RNGClass.new(2))
	enc.run_round()
	# round_count still advances — run_round() degrades gracefully (DRAW)
	# rather than refusing to complete the call.
	assert_eq(
		enc.get_round_count(), 1,
		"run_round() with empty/invalid turn order must still increment get_round_count() exactly once"
	)
	# get_outcome() (the overall encounter outcome) is untouched by a single
	# DRAW round — only the returned RoundResult communicates the DRAW.
	assert_eq(
		enc.get_outcome(), "",
		"A DRAW round must not set the overall encounter outcome to 'won'/'lost'"
	)


## Source-inspection check standing in for push_warning() capture, which is a
## documented no-op on this project's pinned Godot 4.3 engine (see header
## comment and the identical pattern in tests/unit/test_action_economy.gd).
func test_encounter_gd_logs_push_warning_for_empty_turn_order() -> void:
	var file := FileAccess.open("res://core/combat/encounter.gd", FileAccess.READ)
	assert_not_null(file, "core/combat/encounter.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("push_warning") and content.contains("empty/invalid turn order"),
		"encounter.gd must call push_warning() describing the empty/invalid turn order case (FEAT-006)"
	)
