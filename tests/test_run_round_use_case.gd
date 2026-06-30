extends GutTest
## tests/test_run_round_use_case.gd
##
## GUT test suite for FEAT-098 (FIND-096): core/application/run_round_use_case.gd
## — the AC-4 interleaved cycle algorithm extracted out of
## core/combat/encounter.gd's run_round() into the Application layer.
##
## Exercises RunRoundUseCase IN ISOLATION via fake/double TurnOrderPort,
## EventSinkPort, RoundHistoryPort, and AIDecisionPort implementations (no
## Encounter instance is constructed anywhere in this suite). ResolveActionUseCase
## and DetermineOutcomeUseCase are used as their REAL, already-tested
## application-layer sibling collaborators (see tests/test_resolve_action_use_case.gd
## and tests/test_determine_outcome_use_case.gd for their own dedicated unit
## coverage) wired with a SeededRandomAdapter (a pre-existing, deterministic
## RandomNumberPort adapter) so attack/damage rolls are fully reproducible.
##
## Validates the AC-4 algorithm:
##   1. Each living, non-Spent combatant takes EXACTLY ONE action per cycle
##      pass — Strikes therefore INTERLEAVE in turn order (A,B,A,B,...).
##   2. Dead/Spent combatants are skipped WITHOUT consuming a cycle slot.
##   3. The round terminates once every living combatant is Spent, even when
##      the outcome is not yet decided.
##   4. The round terminates immediately once DetermineOutcomeUseCase decides
##      an outcome.
##   5. Empty/invalid turn order, zero-living-combatants-on-one-side, and the
##      stalled-cycle backstop all produce a 'DRAW' RoundResult without
##      hanging.

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const RoundEventsClass             = preload("res://core/rules/round_events.gd")

## NOTE (FEAT-100 regression fix / FIND-096): FEAT-099 switched
## EventSinkPort.emit() to receive TYPED RefCounted value objects instead of
## raw Dictionaries (see core/rules/round_events.gd). FakeEventSinkPort.emit()
## below therefore must NOT type-hint its parameter as Dictionary, and event
## introspection uses `is RoundEventsClass.XEvent` + direct field access
## rather than Dictionary-style `.get(key, default)`.


# ── Fake/double port implementations (FEAT-098 isolation doubles) ──────────────

## FakeTurnOrderPort — returns a pre-built Array of
## {"combatant": Dictionary, "action_economy": ActionEconomy} entries, fixed
## at construction time (matches the TurnOrderPort contract: a stable,
## pre-established initiative order for the whole encounter).
class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


## FakeEventSinkPort — captures every emitted event into an inspectable Array.
class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


## FakeRoundHistoryPort — captures every appended entry into an inspectable
## Array and serves get_history() from that same Array (mirrors the
## persists-across-rounds contract).
class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


## FakeAIDecisionPort — independent (NOT core/combat/ai.gd) reimplementation
## of "Strike the first living target", used purely as an isolation double
## here. Tracks call_count/calls_by_name for delegation-count assertions.
class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	var call_count: int = 0
	var calls_by_name: Dictionary = {}

	func decide_action(combatant: Dictionary, targets: Array) -> Dictionary:
		call_count += 1
		var name: String = combatant.get("name", "")
		calls_by_name[name] = calls_by_name.get(name, 0) + 1
		for t in targets:
			if t.get("hp_current", 0) > 0:
				return {"action_type": "Strike", "target": t}
		return {"action_type": "", "target": {}}


## BrokenAIDecisionPort — always returns an empty/invalid decision, so the
## enemy it controls never resolves an action — used to force the
## any_action_resolved_this_cycle stalled-cycle backstop deterministically.
class BrokenAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant: Dictionary, _targets: Array) -> Dictionary:
		return {}


# ── Shared fixture helpers ─────────────────────────────────────────────────────

func _durable_combatant(p_name: String, p_is_enemy: bool) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": 2000,
		"ac":         10,
		"strength":   3,
		"dexterity":  2,
		"intuition":  2,
		"_is_enemy":  p_is_enemy,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	}


func _fragile_combatant(p_name: String, p_is_enemy: bool) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": 1,
		"ac":         1,
		"strength":   1,
		"dexterity":  1,
		"intuition":  1,
		"_is_enemy":  p_is_enemy,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 4
		}
	}


func _entry(combatant: Dictionary) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


## Builds a fully-wired RunRoundUseCase plus its fake ports, for the common
## case of a single party combatant vs a single enemy combatant.
func _make_use_case(entries: Array, ai_port, seed: int) -> Dictionary:
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var event_sink_port    = FakeEventSinkPort.new()
	var round_history_port = FakeRoundHistoryPort.new()
	var random_number_port = SeededRandomAdapterClass.new(seed)

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, ai_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	return {
		"use_case":    run_round_use_case,
		"event_sink":  event_sink_port,
		"history":     round_history_port
	}


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: Interleaved Strike order (A,B,A,B,...) across two opposing
# combatants with equal (MAX_BUDGET) budgets.
# ══════════════════════════════════════════════════════════════════════════════

func test_interleaved_strike_order_two_equal_budget_combatants() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 42)
	var result: Dictionary = rig["use_case"].execute(1, [alpha], [bravo])

	var history: Array = result.get("history", [])
	assert_eq(history.size(), 14, "Two durable equal-budget combatants must produce 14 history entries (7 each)")
	if history.size() != 14:
		return

	for i in range(history.size() - 1):
		var attacker_a: String = history[i].get("attacker", {}).get("name", "")
		var attacker_b: String = history[i + 1].get("attacker", {}).get("name", "")
		assert_ne(attacker_a, attacker_b, "Consecutive history entries must never share the same attacker (AC-4 interleaving)")

	for k in range(7):
		assert_eq(history[2 * k].get("cycle_index", -1), k, "Entry %d must belong to cycle_index %d" % [2 * k, k])
		assert_eq(history[2 * k + 1].get("cycle_index", -1), k, "Entry %d must belong to cycle_index %d" % [2 * k + 1, k])

	assert_eq(result.get("outcome", "MISSING"), "", "Neither combatant dies — outcome must remain undecided")
	assert_eq(result.get("encounter_outcome", "MISSING"), "", "encounter_outcome must remain undecided")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: Dead/Spent combatants are skipped within a cycle without
# consuming a slot for that cycle.
# ══════════════════════════════════════════════════════════════════════════════

func test_dead_combatant_skipped_without_consuming_cycle_slot() -> void:
	var fragile: Dictionary       = _fragile_combatant("Fragile", false)
	var durable_party: Dictionary = _durable_combatant("DurableParty", false)
	var durable_enemy: Dictionary = _durable_combatant("DurableEnemy", true)
	var entries: Array = [_entry(fragile), _entry(durable_party), _entry(durable_enemy)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 7)
	var result: Dictionary = rig["use_case"].execute(1, [fragile, durable_party], [durable_enemy])
	var history: Array = result.get("history", [])

	var fragile_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Fragile")
	var party_entries: Array   = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "DurableParty")
	var enemy_entries: Array   = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "DurableEnemy")

	assert_true(fragile_entries.size() <= 1, "Fragile must die on the first attack against it — at most 1 action")
	assert_eq(party_entries.size(), 7, "DurableParty must take exactly 7 actions despite Fragile's death")
	assert_eq(enemy_entries.size(), 7, "DurableEnemy must take exactly 7 actions despite Fragile's death")
	assert_eq(result.get("encounter_outcome", "MISSING"), "", "Only Fragile died — outcome must remain undecided")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: The round terminates correctly once all living combatants
# reach is_spent()==true (independent of any win/loss decision).
# ══════════════════════════════════════════════════════════════════════════════

func test_round_terminates_when_all_living_combatants_spent() -> void:
	var x: Dictionary = _durable_combatant("X", false)
	var y: Dictionary = _durable_combatant("Y", true)
	var entries: Array = [_entry(x), _entry(y)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 123)
	# Completion of this call (rather than hanging the test process) is part
	# of the termination proof.
	var result: Dictionary = rig["use_case"].execute(1, [x], [y])
	var history: Array = result.get("history", [])

	assert_eq(result.get("encounter_outcome", "MISSING"), "", "Neither combatant dies — outcome must remain undecided")
	assert_eq(history.size(), 14, "A terminated round with two equal-budget durable combatants must record 14 actions")

	var x_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "X")
	var y_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Y")
	assert_eq(x_entries.size(), 7, "X must take exactly 7 actions before being Spent")
	assert_eq(y_entries.size(), 7, "Y must take exactly 7 actions before being Spent")
	assert_eq(x_entries[6].get("budget_remaining", -1), 0, "X's final action must show budget_remaining==0")
	assert_eq(y_entries[6].get("budget_remaining", -1), 0, "Y's final action must show budget_remaining==0")

	# end_of_round() must have reset every combatant's ActionEconomy (AC-2).
	assert_false(entries[0]["action_economy"].is_spent(), "end_of_round() must reset is_spent()==false")
	assert_eq(entries[0]["action_economy"].get_remaining(), 7, "end_of_round() must reset budget_remaining to MAX_BUDGET")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: The round terminates IMMEDIATELY once DetermineOutcomeUseCase
# decides an outcome (before all combatants are necessarily Spent).
# ══════════════════════════════════════════════════════════════════════════════

func test_round_terminates_on_decided_outcome_before_all_spent() -> void:
	var lethal: Dictionary  = _durable_combatant("Lethal", false)
	var fragile: Dictionary = _fragile_combatant("Fragile", true)
	var entries: Array = [_entry(lethal), _entry(fragile)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 99)
	var result: Dictionary = rig["use_case"].execute(1, [lethal], [fragile])

	assert_eq(result.get("outcome", ""), "won", "Lethal defeating the only enemy must decide 'won'")
	assert_eq(result.get("encounter_outcome", ""), "won", "encounter_outcome must also report 'won'")

	var events: Array = rig["event_sink"].events
	var result_events: Array = events.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(result_events.size(), 1, "Exactly one terminal encounter_result event must be emitted")
	if not result_events.is_empty():
		assert_eq(result_events[0].outcome, "won", "encounter_result payload must match the decided outcome")
	assert_true(events[events.size() - 1] is RoundEventsClass.EncounterResultEvent, "encounter_result must be the LAST event emitted")

	# Lethal must not have resolved all 7 actions — the round halted early.
	var history: Array = result.get("history", [])
	var lethal_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Lethal")
	assert_true(lethal_entries.size() <= 1, "Round must halt as soon as the outcome is decided, not continue cycling")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5: empty/invalid turn order, zero-living-combatants-on-one-side,
# and the stalled-cycle backstop all degrade to a 'DRAW' RoundResult.
# ══════════════════════════════════════════════════════════════════════════════

func test_empty_turn_order_returns_draw_without_cycling() -> void:
	var rig: Dictionary = _make_use_case([], FakeAIDecisionPort.new(), 1)
	var result: Dictionary = rig["use_case"].execute(1, [], [])

	assert_eq(result.get("outcome", ""), "DRAW", "Empty turn order must return RoundResult.outcome == 'DRAW'")
	assert_eq(result.get("history", null), [], "Empty turn order must return empty history")
	assert_eq(result.get("encounter_outcome", "MISSING"), "", "Empty turn order must never set encounter_outcome")
	assert_eq(rig["history"].entries.size(), 0, "No round history entries may be recorded")


func test_zero_living_enemies_returns_won_without_cycling() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var entries: Array = [_entry(alpha)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var result: Dictionary = rig["use_case"].execute(1, [alpha], [])

	assert_eq(result.get("outcome", ""), "won", "A living party with zero enemies must resolve 'won' immediately")
	assert_eq(result.get("encounter_outcome", ""), "won", "encounter_outcome must also report 'won'")
	assert_eq(result.get("history", null), [], "The up-front guard must decide the outcome WITHOUT entering the cycle loop")


func test_zero_living_party_returns_lost_without_cycling() -> void:
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var result: Dictionary = rig["use_case"].execute(1, [], [bravo])

	assert_eq(result.get("outcome", ""), "lost", "A living enemy with zero party members must resolve 'lost' immediately")
	assert_eq(result.get("encounter_outcome", ""), "lost", "encounter_outcome must also report 'lost'")


func test_both_sides_fully_dead_returns_draw_without_cycling() -> void:
	var dead_party: Dictionary = {"name": "DeadParty", "hp_current": 0, "ac": 10, "_is_enemy": false}
	var dead_enemy: Dictionary = {"name": "DeadEnemy", "hp_current": 0, "ac": 10, "_is_enemy": true}
	var entries: Array = [_entry(dead_party), _entry(dead_enemy)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var result: Dictionary = rig["use_case"].execute(1, [dead_party], [dead_enemy])

	assert_eq(result.get("outcome", ""), "DRAW", "Both sides fully dead must return 'DRAW', not a false win/loss")
	assert_eq(result.get("encounter_outcome", "MISSING"), "", "A DRAW round must never set encounter_outcome")


func test_stalled_cycle_backstop_terminates_with_draw() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	# Bravo's AIDecisionPort never returns a usable decision — only the
	# any_action_resolved_this_cycle backstop can prevent this from hanging.
	var rig: Dictionary = _make_use_case(entries, BrokenAIDecisionPort.new(), 42)
	var result: Dictionary = rig["use_case"].execute(1, [alpha], [bravo])

	assert_eq(result.get("outcome", ""), "DRAW", "A permanently stalled combatant must terminate the round via the backstop with 'DRAW'")
	assert_eq(result.get("encounter_outcome", "MISSING"), "", "A backstop DRAW must never set encounter_outcome")

	var history: Array = result.get("history", [])
	var alpha_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Alpha")
	assert_eq(alpha_entries.size(), 7, "Alpha must still resolve its own 7 actions before the backstop fires")
	var bravo_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Bravo")
	assert_eq(bravo_entries.size(), 0, "Bravo (broken AI) must never resolve a single action")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 6: history is scoped to the requested round only (RoundHistoryPort
# accumulates across multiple execute() calls; "history" in the result must
# only contain entries from THIS round_number).
# ══════════════════════════════════════════════════════════════════════════════

func test_history_result_scoped_to_requested_round_number() -> void:
	var x: Dictionary = _durable_combatant("X", false)
	var y: Dictionary = _durable_combatant("Y", true)
	var entries: Array = [_entry(x), _entry(y)]

	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var event_sink_port    = FakeEventSinkPort.new()
	var round_history_port = FakeRoundHistoryPort.new()
	var random_number_port = SeededRandomAdapterClass.new(55)
	var resolve_action_use_case = ResolveActionUseCaseClass.new(random_number_port, event_sink_port, round_history_port)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, FakeAIDecisionPort.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	var round_1: Dictionary = run_round_use_case.execute(1, [x], [y])
	var round_2: Dictionary = run_round_use_case.execute(2, [x], [y])

	assert_eq(round_1.get("history", []).size(), 14, "Round 1 result must contain only round 1's 14 entries")
	assert_eq(round_2.get("history", []).size(), 14, "Round 2 result must contain only round 2's 14 entries")
	assert_eq(round_history_port.get_history().size(), 28, "RoundHistoryPort accumulates across both rounds (28 total)")
	for e in round_1.get("history", []):
		assert_eq(e.get("round", -1), 1, "Every round 1 result entry must carry round==1")
	for e in round_2.get("history", []):
		assert_eq(e.get("round", -1), 2, "Every round 2 result entry must carry round==2")
