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
const RoundEventsClass   = preload("res://core/rules/round_events.gd")

## NOTE (FEAT-100 regression fix / FIND-096): FEAT-099 switched
## get_round_events() to carry TYPED RefCounted value objects (see
## core/rules/round_events.gd) instead of raw Dictionaries. Event
## introspection below therefore uses `is RoundEventsClass.XEvent` + direct
## field access rather than Dictionary-style `.get(key, default)` (Object.get()
## has no 2-arg/default overload and errors at runtime when called with one).


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
	# One action per TURN (ADR-103 / FEAT-003): spend_action() sets the
	# per-turn _action_used gate, so start_of_turn() must clear it before each
	# of the seven spends — otherwise spends 2..7 return "Action already used"
	# and the round budget never actually reaches Spent. Models "up to seven
	# turns per round, one action each".
	for _i in range(ActionEconomyClass.MAX_BUDGET):
		ae_standalone.start_of_turn()
		ae_standalone.spend_action({})
	assert_true(ae_standalone.is_spent(), "sanity check: standalone ActionEconomy must be Spent after MAX_BUDGET per-turn spends")
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


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-007 (US-004 / US-005, AC-4 / AC-5): observability wiring — _round_events
# (attack / combatant_defeated / encounter_result, correct order) and
# _round_history (one entry per resolved action/reaction, correct post-spend
# budget_remaining and cycle_index) must be populated by run_round() itself,
# not merely inferable from side effects.
# ══════════════════════════════════════════════════════════════════════════════

## Criterion: _round_events contains an 'attack' entry for every resolved
## Strike, in the order resolved — i.e. the 'attack' subsequence of
## get_round_events() lines up 1:1, in order, with get_round_history().
func test_round_events_contains_attack_entry_per_resolved_strike_in_order() -> void:
	var enc = EncounterClass.new(
		[_durable_combatant("Alpha")], [_durable_combatant("Bravo")], RNGClass.new(42)
	)
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var history: Array = result.get("history", [])
	var events: Array  = enc.get_round_events()

	var attack_events: Array = events.filter(func(e): return e is RoundEventsClass.AttackEvent)

	assert_eq(
		attack_events.size(), history.size(),
		"There must be exactly one 'attack' event per resolved action/reaction recorded in history"
	)
	assert_eq(attack_events.size(), 14, "Sanity: two durable equal-budget combatants resolve 14 Strikes")

	# Order: the Nth 'attack' event must describe the same attacker/target as
	# the Nth round_history entry, in the exact order resolved (AC-4).
	for i in range(history.size()):
		var hist_entry: Dictionary = history[i]
		var ev = attack_events[i]
		assert_eq(
			ev.attacker_name, hist_entry.get("attacker", {}).get("name", ""),
			"attack event %d attacker_name must match round_history entry %d's attacker, in resolved order" % [i, i]
		)
		assert_eq(
			ev.target_name, hist_entry.get("target", {}).get("name", ""),
			"attack event %d target_name must match round_history entry %d's target, in resolved order" % [i, i]
		)
		assert_eq(
			ev.damage_final, hist_entry.get("damage_final", -2),
			"attack event %d damage_final must match round_history entry %d's damage_final" % [i, i]
		)


## Criterion: _round_events contains exactly one 'combatant_defeated' entry
## per combatant whose HP transitions to <= 0 — never zero, never duplicated,
## even when multiple combatants die within the same round.
func test_round_events_exactly_one_combatant_defeated_entry_per_dead_combatant() -> void:
	var fragile_1: Dictionary = _fragile_combatant("Fragile1")
	var fragile_2: Dictionary = _fragile_combatant("Fragile2")
	var durable_party: Dictionary = _durable_combatant("DurableParty")

	# DurableParty (str=3, prof=2) attacking ac=1 targets always hits and
	# always deals lethal (>=1) damage to hp=1 targets — deterministic kills,
	# independent of RNG seed/roll value (see resolve_weapon_attack: roll_total
	# = raw(>=1) + 3 + 2 >= 6 > ac=1).
	var enc = EncounterClass.new(
		[durable_party], [fragile_1, fragile_2], RNGClass.new(99)
	)
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var events: Array = enc.get_round_events()

	var defeated_events: Array = events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)

	assert_eq(
		defeated_events.size(), 2,
		"Exactly one combatant_defeated event must be emitted per combatant that died (Fragile1 and Fragile2), no duplicates"
	)

	var defeated_names: Array = []
	for ev in defeated_events:
		defeated_names.append(ev.name)
	defeated_names.sort()
	assert_eq(
		defeated_names, ["Fragile1", "Fragile2"],
		"combatant_defeated events must name each distinct dead combatant exactly once"
	)

	# Both enemies dead → the encounter outcome must be decided 'won'.
	assert_eq(result.get("outcome", ""), "won", "DurableParty defeating both enemies must decide the encounter 'won'")


## Criterion: _round_events contains exactly one terminal 'encounter_result'
## entry per round, and it is the LAST event in the queue (emitted only once
## the outcome is actually decided).
func test_round_events_exactly_one_terminal_encounter_result_entry() -> void:
	var fragile_1: Dictionary = _fragile_combatant("Fragile1")
	var fragile_2: Dictionary = _fragile_combatant("Fragile2")
	var durable_party: Dictionary = _durable_combatant("DurableParty")

	var enc = EncounterClass.new(
		[durable_party], [fragile_1, fragile_2], RNGClass.new(99)
	)
	enc.initialize()
	enc.run_round()
	var events: Array = enc.get_round_events()

	var result_events: Array = events.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(
		result_events.size(), 1,
		"Exactly one terminal encounter_result event must be emitted for a round whose outcome is decided"
	)
	if result_events.size() != 1:
		return

	assert_eq(result_events[0].outcome, "won", "encounter_result event must carry the decided outcome")
	assert_true(
		events[events.size() - 1] is RoundEventsClass.EncounterResultEvent,
		"encounter_result must be the terminal (last) event in the per-round queue"
	)

	# A round that does NOT decide an outcome (both sides durable, Spent-out
	# termination) must emit ZERO encounter_result events — 'terminal' means
	# emitted only when the outcome is actually decided, never speculatively.
	var enc_undecided = EncounterClass.new(
		[_durable_combatant("X")], [_durable_combatant("Y")], RNGClass.new(123)
	)
	enc_undecided.initialize()
	enc_undecided.run_round()
	var undecided_events: Array = enc_undecided.get_round_events()
	var undecided_result_events: Array = undecided_events.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(
		undecided_result_events.size(), 0,
		"A round that Spent-out without deciding the outcome must emit zero encounter_result events"
	)


## Criterion: _round_history contains one entry per resolved action/reaction
## with budget_remaining equal to the correct post-spend value (cross-checked
## against the ActionEconomy contract directly, not just inferred from count).
func test_round_history_budget_remaining_matches_post_spend_sequence() -> void:
	var enc = EncounterClass.new(
		[_durable_combatant("Alpha")], [_durable_combatant("Bravo")], RNGClass.new(7)
	)
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var history: Array = result.get("history", [])

	var alpha_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Alpha")
	var bravo_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Bravo")

	# Each combatant spends its MAX_BUDGET=7 one at a time; budget_remaining
	# must strictly count down 6,5,4,3,2,1,0 across that combatant's own
	# resolved actions, in resolved order — the precise post-spend sequence.
	var expected: Array = [6, 5, 4, 3, 2, 1, 0]
	for i in range(alpha_entries.size()):
		assert_eq(
			alpha_entries[i].get("budget_remaining", -1), expected[i],
			"Alpha's action %d must show post-spend budget_remaining == %d" % [i, expected[i]]
		)
	for i in range(bravo_entries.size()):
		assert_eq(
			bravo_entries[i].get("budget_remaining", -1), expected[i],
			"Bravo's action %d must show post-spend budget_remaining == %d" % [i, expected[i]]
		)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-097 (CWE-835, FIND-095): run_round() must never hang when one side has
# zero living combatants. An up-front guard, evaluated immediately after
# _turn_order is built and BEFORE the cycle loop begins, must detect this
# case and return the appropriate outcome ('won'/'lost'/'DRAW') without ever
# entering the while loop — mirroring the existing post-attack win/loss
# detection. A defensive any_action_resolved_this_cycle backstop inside the
# loop guards against any OTHER unforeseen stall (e.g. a target that never
# resolves an action for reasons other than "opposing side fully dead").
#
# Every test in this section completing at all (rather than hanging the test
# runner) is itself part of the proof; the assertions further pin the exact
# outcome contract.
# ══════════════════════════════════════════════════════════════════════════════

## BrokenAI — AIDecisionPort test double (FEAT-097). Always returns an empty/
## invalid decision, so the enemy it controls never finds a usable
## action_name/target and therefore never calls spend_action() — used to
## force a stalled cycle (a full pass that resolves zero actions) WITHOUT
## relying on the "one side has zero living combatants" up-front guard: both
## sides have a living combatant throughout this scenario, so only the
## any_action_resolved_this_cycle backstop can terminate it.
class BrokenAI:
	extends "res://core/combat/ai.gd"

	func decide_action(_combatant: Dictionary, _targets: Array, _action_economy = null, _other_combatants: Array = []) -> Dictionary:
		return {}


func test_run_round_no_living_enemies_returns_won_without_hanging() -> void:
	var living_party_member: Dictionary = _durable_combatant("Alpha")
	var enc = EncounterClass.new([living_party_member], [], RNGClass.new(1))
	enc.initialize()

	# Must not hang — reaching the assertions below already proves the
	# up-front guard fired instead of entering the cycle loop.
	var result: Dictionary = enc.run_round()

	assert_eq(
		result.get("outcome", ""), "won",
		"A round with a living party and zero enemies must return outcome 'won' immediately"
	)
	assert_eq(enc.get_outcome(), "won", "get_outcome() must also report 'won' once decided by the up-front guard")
	assert_eq(
		result.get("history", null), [],
		"The up-front guard must decide the outcome WITHOUT entering the cycle loop — no actions resolved, empty history"
	)


func test_run_round_all_enemies_already_dead_returns_won_without_hanging() -> void:
	var living_party_member: Dictionary = _durable_combatant("Alpha")
	var dead_enemy: Dictionary = {
		"name": "Corpse", "hp_current": 0, "ac": 10, "intuition": 0, "dexterity": 0,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 0, "damage_die": 4}
	}
	var enc = EncounterClass.new([living_party_member], [dead_enemy], RNGClass.new(1))
	enc.initialize()

	# _turn_order is non-empty here (it contains the dead enemy) — this
	# exercises the "non-empty but fully-dead turn_order" guard path
	# specifically, not the empty-turn-order guard.
	var result: Dictionary = enc.run_round()

	assert_eq(
		result.get("outcome", ""), "won",
		"A round whose only enemy is already dead must return outcome 'won' immediately, even with a non-empty turn_order"
	)
	assert_eq(enc.get_outcome(), "won", "get_outcome() must also report 'won' once decided by the up-front guard")


func test_run_round_no_living_party_returns_lost_without_hanging() -> void:
	var living_enemy: Dictionary = _durable_combatant("Bravo")
	var enc = EncounterClass.new([], [living_enemy], RNGClass.new(1))
	enc.initialize()

	var result: Dictionary = enc.run_round()

	assert_eq(
		result.get("outcome", ""), "lost",
		"A round with a living enemy and zero party members must return outcome 'lost' immediately"
	)
	assert_eq(enc.get_outcome(), "lost", "get_outcome() must also report 'lost' once decided by the up-front guard")
	assert_eq(
		result.get("history", null), [],
		"The up-front guard must decide the outcome WITHOUT entering the cycle loop — no actions resolved, empty history"
	)


func test_run_round_both_sides_fully_dead_returns_draw_without_hanging() -> void:
	var dead_party: Dictionary = {
		"name": "DeadParty", "hp_current": 0, "ac": 10, "intuition": 0, "dexterity": 0,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 0, "damage_die": 4}
	}
	var dead_enemy: Dictionary = {
		"name": "DeadEnemy", "hp_current": 0, "ac": 10, "intuition": 0, "dexterity": 0,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 0, "damage_die": 4}
	}
	var enc = EncounterClass.new([dead_party], [dead_enemy], RNGClass.new(1))
	enc.initialize()

	var result: Dictionary = enc.run_round()

	assert_eq(
		result.get("outcome", ""), "DRAW",
		"A round where BOTH sides have zero living combatants must return outcome 'DRAW' immediately, not a false win/loss"
	)
	assert_eq(
		enc.get_outcome(), "",
		"get_outcome() (the overall encounter outcome) must remain undecided for a both-sides-dead DRAW round, mirroring the empty-turn-order DRAW contract"
	)


func test_run_round_stalled_cycle_backstop_terminates_with_draw_and_warning() -> void:
	var broken_ai := BrokenAI.new()
	var party_member: Dictionary = _durable_combatant("Alpha")
	var enemy: Dictionary = _durable_combatant("Bravo")

	var enc = EncounterClass.new([party_member], [enemy], RNGClass.new(42), broken_ai)
	enc.initialize()

	# Both sides have a living combatant the entire time — the up-front guard
	# does NOT fire here. Only the any_action_resolved_this_cycle backstop
	# can prevent this from hanging forever (Bravo's AIDecisionPort never
	# returns a usable decision, so Bravo never reaches is_spent()).
	var result: Dictionary = enc.run_round()

	assert_eq(
		result.get("outcome", ""), "DRAW",
		"A round where one combatant's action selection never resolves must terminate via the any_action_resolved_this_cycle backstop with outcome 'DRAW'"
	)

	# Alpha (unaffected by the broken AI) still resolves its own full 7
	# actions against the living Bravo before the stall is detected and the
	# backstop fires on a cycle where NEITHER combatant resolves an action
	# (Alpha now Spent, Bravo still stalled).
	var history: Array = result.get("history", [])
	var alpha_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Alpha")
	assert_eq(
		alpha_entries.size(), 7,
		"Alpha must still resolve its own 7 actions normally before the backstop fires on Bravo's permanent stall"
	)
	var bravo_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Bravo")
	assert_eq(bravo_entries.size(), 0, "Bravo (broken AI) must never resolve a single action")


## Source-inspection check standing in for push_warning() capture (see header
## note on Godot 4.3's no-op OS.add_logger()) — pins that the backstop
## mechanism and its warning call site actually exist in encounter.gd.
func test_encounter_gd_logs_push_warning_for_stalled_cycle_backstop() -> void:
	var file := FileAccess.open("res://core/combat/encounter.gd", FileAccess.READ)
	assert_not_null(file, "core/combat/encounter.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("any_action_resolved_this_cycle"),
		"encounter.gd must track any_action_resolved_this_cycle to back-stop a stalled cycle (FEAT-097)"
	)
	assert_true(
		content.contains("push_warning"),
		"encounter.gd must call push_warning() when the stalled-cycle backstop fires (FEAT-097)"
	)


## Criterion: _round_history entries' cycle_index values reflect the actual
## interleave cycle in which the action occurred — verified directly against
## the position of each entry's resolved order (entry N for a given combatant
## occurred in cycle N, since each combatant takes exactly one action/cycle).
func test_round_history_cycle_index_matches_actual_interleave_cycle() -> void:
	var enc = EncounterClass.new(
		[_durable_combatant("Alpha")], [_durable_combatant("Bravo")], RNGClass.new(7)
	)
	enc.initialize()
	var result: Dictionary = enc.run_round()
	var history: Array = result.get("history", [])

	var alpha_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Alpha")
	var bravo_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Bravo")

	for i in range(alpha_entries.size()):
		assert_eq(
			alpha_entries[i].get("cycle_index", -1), i,
			"Alpha's action %d must record cycle_index == %d (its Nth action occurs in interleave cycle N)" % [i, i]
		)
	for i in range(bravo_entries.size()):
		assert_eq(
			bravo_entries[i].get("cycle_index", -1), i,
			"Bravo's action %d must record cycle_index == %d (its Nth action occurs in interleave cycle N)" % [i, i]
		)
