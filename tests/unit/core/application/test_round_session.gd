extends GutTest
## tests/unit/core/application/test_round_session.gd
##
## GUT test suite for FEAT-110 (US-010): RoundSession
## (core/application/round_session.gd), the ADR-007 stepwise cycle API
## RunRoundUseCase.begin_round() returns.
##
## Exercises the stepwise API (current_actor/current_action_economy/
## advance_ai_turn/end_current_turn/is_round_over/outcome/finish) against
## the REAL RunRoundUseCase and its REAL sibling ResolveActionUseCase /
## DetermineOutcomeUseCase collaborators (wired with a SeededRandomAdapter
## for deterministic rolls) — NOT a test double standing in for
## RunRoundUseCase/RoundSession themselves — so a phantom-method regression
## on begin_round() cannot pass on a spy alone. Only TurnOrderPort,
## EventSinkPort, RoundHistoryPort, and AIDecisionPort are fakes/doubles,
## exactly mirroring tests/test_run_round_use_case.gd's isolation strategy.
##
## Verifies:
##   1. begin_round() grants start-of-round budgets and positions
##      current_actor() at the first living, un-Spent combatant.
##   2. end_current_turn() advances the cursor to the next living, un-Spent
##      combatant and emits a TurnAdvancedEvent; is_round_over() becomes
##      true once every living combatant is Spent. end_current_turn() is
##      ALWAYS available, whether or not an action was spent this turn.
##   3. advance_ai_turn() resolves the current Enemy actor's turn via the
##      SAME resolve_action_use_case pipeline the player's own Strike uses,
##      rejects a non-Enemy current actor, and never stalls on a broken AI
##      decision (CWE-835 defensive fallback).
##   4. The round ending mid-turn (an EncounterResultEvent decided) marks
##      the round over and reports the decided outcome.
## (Byte-for-byte regression coverage for RunRoundUseCase.execute() itself
## is exercised by the pre-existing, UNCHANGED tests/test_run_round_use_case.gd
## suite — see that file's criteria 1-6, all of which must stay green.)

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const RoundEventsClass             = preload("res://core/rules/round_events.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
## CombatantFactoryClass — FEAT-007 (US-007): preloaded ONLY by the
## "Patience real fixture" tests below (Criterion 5), to build a REAL,
## 2-weapon Patience combatant Dictionary from data/characters/
## dwarf_channeler.tres via the actual infrastructure adapter (the same one
## tests/unit/infrastructure/test_combatant_factory.gd already exercises for
## FEAT-005/US-006's weapons array), rather than a hand-authored stand-in.
## This is a TEST-file-only dependency on infrastructure/ — round_session.gd
## itself never imports infrastructure/ (ADR-001/ADR-002 unaffected).
const CombatantFactoryClass        = preload("res://infrastructure/combatant_factory.gd")
const DWARF_CHANNELER_PATH: String = "res://data/characters/dwarf_channeler.tres"


# ── Fake/double port implementations (mirrors tests/test_run_round_use_case.gd) ──

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


## FakeAIDecisionPort — "Strike the first living target" (mirrors
## core/combat/ai.gd's real v0 behavior, used here purely as an isolation
## double for the port itself).
class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant, targets: Array) -> Dictionary:
		for t in targets:
			if t.hp_current > 0:
				return {"action_type": "Strike", "target": t}
		return {"action_type": "", "target": null}


## BrokenAIDecisionPort — always returns an empty/invalid decision, used to
## exercise advance_ai_turn()'s CWE-835 defensive-advance fallback.
class BrokenAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant, _targets: Array) -> Dictionary:
		return {}


## FakeStrideAIDecisionPort — FEAT-005 (US-005 / FR-006): always returns a
## Stride decision carrying BOTH "destination" and "path" (mirrors
## core/combat/ai.gd's real FEAT-004 additive Stride-path shape, Contract 7),
## so this suite can deterministically exercise RoundSession's Contract 8
## animate-path preference without depending on ai.gd's own pathfinding/
## target-selection logic.
class FakeStrideAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	var _destination
	var _path: Array

	func _init(p_destination, p_path: Array) -> void:
		_destination = p_destination
		_path = p_path

	func decide_action(_combatant, _targets: Array) -> Dictionary:
		return {"action_type": "Stride", "target": null, "destination": _destination, "path": _path}


## FakeStridePathlessAIDecisionPort — FEAT-005 (US-005 / FR-006): a Stride
## decision with a "destination" but deliberately NO "path" key — exercises
## Contract 8's fallback-to-instant-reposition branch even when the
## animate-path seam IS wired (test_criterion 3).
class FakeStridePathlessAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	var _destination

	func _init(p_destination) -> void:
		_destination = p_destination

	func decide_action(_combatant, _targets: Array) -> Dictionary:
		return {"action_type": "Stride", "target": null, "destination": _destination}


## RecordingInstantRepositionStub — a deterministic (RISK-002 mitigation, no
## real HexGridView/Tween) double for the ITokenRepositionPort seam
## (`_token_reposition_fn`), recording every move_token(actor_id,
## new_hex_coord) call it receives.
class RecordingInstantRepositionStub:
	extends RefCounted

	var calls: Array = []

	func move_token(actor_id: String, new_hex_coord) -> void:
		calls.append({"actor_id": actor_id, "hex": new_hex_coord})


## RecordingAnimatePathStub — FEAT-005 (US-005 / FR-006): a deterministic
## (RISK-002 mitigation, no real Tween) double for the new
## `_token_animate_path_fn` seam, recording every animate_token_to(actor_id,
## path) call it receives.
class RecordingAnimatePathStub:
	extends RefCounted

	var calls: Array = []

	func animate_token_to(actor_id: String, path: Array) -> void:
		calls.append({"actor_id": actor_id, "path": path})


# ── Shared fixture helpers ─────────────────────────────────────────────────

func _durable_combatant(p_name: String, p_is_enemy: bool, p_combatant_id: String = ""):
	return CombatantClass.from_dict({
		"name":         p_name,
		"combatant_id": p_combatant_id,
		"hp_current":   2000,
		"ac":           10,
		"strength":     3,
		"dexterity":    2,
		"intuition":    2,
		"_is_enemy":    p_is_enemy,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	})


func _fragile_combatant(p_name: String, p_is_enemy: bool):
	return CombatantClass.from_dict({
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
	})


func _entry(combatant) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


## Builds a fully-wired, REAL RunRoundUseCase (per FEAT-110's explicit
## "no phantom-method-on-a-spy" requirement) plus its fake ports.
func _make_use_case(entries: Array, ai_port, seed: int) -> Dictionary:
	var turn_order_port     = FakeTurnOrderPort.new(entries)
	var event_sink_port     = FakeEventSinkPort.new()
	var round_history_port  = FakeRoundHistoryPort.new()
	var random_number_port  = SeededRandomAdapterClass.new(seed)

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, ai_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	return {
		"use_case":                run_round_use_case,
		"event_sink":              event_sink_port,
		"history":                 round_history_port,
		"resolve_action_use_case": resolve_action_use_case
	}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: begin_round grants start-of-round budgets and positions
# current_actor() at the first living, un-Spent combatant.
# ══════════════════════════════════════════════════════════════════════════

func test_begin_round_grants_budget_and_positions_at_first_living_unspent() -> void:
	var alpha = _durable_combatant("Alpha", false, "alpha")
	var bravo = _durable_combatant("Bravo", true, "bravo")
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_eq(session.current_actor().name, "Alpha", "current_actor() must be the first entry")
	assert_eq(
		entries[0]["action_economy"].get_remaining(), ActionEconomyClass.MAX_BUDGET,
		"begin_round() must grant the fresh start-of-round budget"
	)
	assert_false(session.is_round_over(), "a freshly begun round with living combatants must not be over")


func test_begin_round_skips_a_dead_combatant_when_positioning_cursor() -> void:
	var dead = CombatantClass.from_dict({"name": "Dead", "hp_current": 0, "ac": 10, "_is_enemy": false})
	var alpha = _durable_combatant("Alpha", false)
	var bravo = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(dead), _entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [dead, alpha], [bravo])

	assert_eq(session.current_actor().name, "Alpha", "current_actor() must skip the dead first entry")


func test_current_action_economy_matches_current_actor() -> void:
	var alpha = _durable_combatant("Alpha", false)
	var bravo = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_eq(session.current_action_economy(), entries[0]["action_economy"])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: end_current_turn() advances the cursor and emits
# TurnAdvancedEvent; is_round_over() becomes true when all are Spent;
# ALWAYS available whether or not an action was spent.
# ══════════════════════════════════════════════════════════════════════════

func test_end_current_turn_advances_cursor_and_emits_turn_advanced_event() -> void:
	var alpha = _durable_combatant("Alpha", false, "alpha")
	var bravo = _durable_combatant("Bravo", true, "bravo")
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_eq(session.current_actor().name, "Alpha")

	var result: Dictionary = session.end_current_turn()

	assert_true(result.get("ok", false))
	assert_eq(
		session.current_actor().name, "Bravo",
		"end_current_turn() must advance to the next living, un-Spent combatant"
	)

	var turn_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.TurnAdvancedEvent)
	assert_eq(turn_events.size(), 1, "exactly one TurnAdvancedEvent must be emitted")
	assert_eq(turn_events[0].active_combatant_name, "Bravo")
	assert_eq(turn_events[0].active_combatant_id, "bravo")


func test_end_current_turn_is_always_available_even_when_no_action_was_spent() -> void:
	var alpha = _durable_combatant("Alpha", false)
	var bravo = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	# Alpha's action budget is fully untouched (no Strike resolved) -- yet
	# end_current_turn() must still succeed and advance (US-010).
	assert_eq(entries[0]["action_economy"].get_remaining(), ActionEconomyClass.MAX_BUDGET)
	var result: Dictionary = session.end_current_turn()
	assert_true(result.get("ok", false), "end_current_turn() must succeed whether or not an action was spent")
	assert_eq(session.current_actor().name, "Bravo")


func test_end_current_turn_is_also_available_when_an_action_was_spent() -> void:
	var alpha = _durable_combatant("Alpha", false)
	var bravo = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	# Simulate StrikeActionControl having resolved the player's Strike
	# directly via resolve_action_use_case BEFORE end_current_turn() is
	# pressed (US-009/US-010's documented division of responsibility).
	var resolve_result: Dictionary = rig["resolve_action_use_case"].resolve(
		alpha, entries[0]["action_economy"], bravo, "Strike", 1, 0
	)
	assert_true(resolve_result.get("resolved", false))

	var result: Dictionary = session.end_current_turn()
	assert_true(result.get("ok", false), "end_current_turn() must succeed after an action was spent too")
	assert_eq(session.current_actor().name, "Bravo")


func test_is_round_over_becomes_true_once_every_living_combatant_is_spent() -> void:
	var alpha = _durable_combatant("Alpha", false)
	var bravo = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	# FEAT-003 (ADR-103): only one spend_action() succeeds per turn, so
	# exhausting each combatant's round budget requires a fresh
	# start_of_turn() before each spend (AC-4 interleaving simulated across
	# MAX_BUDGET turns).
	for i in range(ActionEconomyClass.MAX_BUDGET):
		entries[0]["action_economy"].start_of_turn()
		entries[0]["action_economy"].spend_action({"name": "Strike", "traits": []})
	assert_true(entries[0]["action_economy"].is_spent())

	var result_1: Dictionary = session.end_current_turn()  # Alpha -> Bravo
	assert_true(result_1.get("ok", false))
	assert_false(session.is_round_over(), "Bravo is still living and un-Spent")
	assert_eq(session.current_actor().name, "Bravo")

	for i in range(ActionEconomyClass.MAX_BUDGET):
		entries[1]["action_economy"].start_of_turn()
		entries[1]["action_economy"].spend_action({"name": "Strike", "traits": []})
	assert_true(entries[1]["action_economy"].is_spent())

	var result_2: Dictionary = session.end_current_turn()  # Bravo -> round over
	assert_true(result_2.get("ok", false))
	assert_true(session.is_round_over(), "is_round_over() must become true once every living combatant is Spent")
	assert_null(session.current_actor(), "current_actor() must be null once the round is over")


func test_end_current_turn_is_a_no_op_after_round_over() -> void:
	var alpha = _durable_combatant("Alpha", false)
	var entries: Array = [_entry(alpha)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [])

	for i in range(ActionEconomyClass.MAX_BUDGET):
		entries[0]["action_economy"].spend_action({"name": "Strike", "traits": []})

	session.end_current_turn()
	assert_true(session.is_round_over())

	var result: Dictionary = session.end_current_turn()
	assert_false(result.get("ok", true), "a step method called after is_round_over() must be a no-op")


# ══════════════════════════════════════════════════════════════════════════
# advance_ai_turn(): resolves via the REAL resolve_action_use_case pipeline
# and advances the cursor; rejects a non-Enemy current actor; never stalls.
# ══════════════════════════════════════════════════════════════════════════

func test_advance_ai_turn_resolves_via_the_real_pipeline_and_advances_cursor() -> void:
	var bravo = _durable_combatant("Bravo", true)
	var alpha = _durable_combatant("Alpha", false)
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 42)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_eq(session.current_actor().name, "Bravo")
	var hp_before: int = alpha.hp_current

	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false))
	assert_eq(rig["history"].entries.size(), 1, "advance_ai_turn() must resolve exactly one action via resolve_action_use_case")
	assert_true(alpha.hp_current <= hp_before, "the AI's resolved Strike must be able to damage its target")
	assert_eq(session.current_actor().name, "Alpha", "advance_ai_turn() must advance the cursor")


func test_advance_ai_turn_rejects_when_current_actor_is_not_enemy() -> void:
	var alpha = _durable_combatant("Alpha", false)
	var bravo = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	var result: Dictionary = session.advance_ai_turn()

	assert_false(result.get("ok", true), "advance_ai_turn() must reject a Player current actor")
	assert_eq(rig["history"].entries.size(), 0)
	assert_eq(session.current_actor().name, "Alpha", "a rejected call must not advance the cursor")


func test_advance_ai_turn_defensive_fallback_still_advances_on_broken_ai() -> void:
	var bravo = _durable_combatant("Bravo", true)
	var alpha = _durable_combatant("Alpha", false)
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_use_case(entries, BrokenAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false), "a rejected AI decision must not stall the session (CWE-835 guard)")
	assert_eq(session.current_actor().name, "Alpha", "the cursor must still advance past a broken AI turn")


# ══════════════════════════════════════════════════════════════════════════
# FEAT-005 (US-005 / FR-006, NFR-001, NFR-003; Contract 8): the enemy token
# animate-path seam (`set_token_animate_path_fn()`) on RoundSession.
# ══════════════════════════════════════════════════════════════════════════

func test_advance_ai_turn_uses_animate_path_fn_when_wired_and_decision_has_path_key() -> void:
	var goblin = _durable_combatant("Goblin", true, "goblin")
	var titus = _durable_combatant("Titus", false, "titus")
	var entries: Array = [_entry(goblin), _entry(titus)]

	var start := HexCoordClass.new(0, 0)
	var dest := HexCoordClass.new(2, 0)
	var stride_path: Array = [start, HexCoordClass.new(1, 0), dest]

	var rig: Dictionary = _make_use_case(entries, FakeStrideAIDecisionPort.new(dest, stride_path), 1)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])
	assert_eq(session.current_actor().name, "Goblin")

	var instant_stub := RecordingInstantRepositionStub.new()
	var animate_stub := RecordingAnimatePathStub.new()
	session.set_token_reposition_fn(Callable(instant_stub, "move_token"))
	session.set_token_animate_path_fn(Callable(animate_stub, "animate_token_to"))

	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false))
	assert_eq(
		animate_stub.calls.size(), 1,
		"the animate-path fn must be called exactly once for a Stride decision carrying a 'path' key when wired"
	)
	assert_eq(animate_stub.calls[0]["actor_id"], "goblin")
	assert_eq(animate_stub.calls[0]["path"], stride_path)
	assert_eq(
		instant_stub.calls.size(), 0,
		"the instant reposition fn must NOT be called when the animate-path fn is preferred (Contract 8)"
	)


func test_advance_ai_turn_falls_back_to_instant_reposition_when_animate_path_fn_unwired() -> void:
	var goblin = _durable_combatant("Goblin", true, "goblin")
	var titus = _durable_combatant("Titus", false, "titus")
	var entries: Array = [_entry(goblin), _entry(titus)]

	var start := HexCoordClass.new(0, 0)
	var dest := HexCoordClass.new(2, 0)
	var stride_path: Array = [start, HexCoordClass.new(1, 0), dest]

	var rig: Dictionary = _make_use_case(entries, FakeStrideAIDecisionPort.new(dest, stride_path), 1)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])

	var instant_stub := RecordingInstantRepositionStub.new()
	session.set_token_reposition_fn(Callable(instant_stub, "move_token"))
	# set_token_animate_path_fn() is deliberately never called — the seam
	# stays unwired, matching every pre-existing caller/test double.

	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false))
	assert_eq(
		instant_stub.calls.size(), 1,
		"an unwired animate-path fn must fall back to the existing instant _token_reposition_fn (unchanged legacy behavior)"
	)
	assert_eq(instant_stub.calls[0]["actor_id"], "goblin")
	assert_eq(instant_stub.calls[0]["hex"], dest)


func test_advance_ai_turn_falls_back_to_instant_reposition_when_decision_lacks_path_key() -> void:
	var goblin = _durable_combatant("Goblin", true, "goblin")
	var titus = _durable_combatant("Titus", false, "titus")
	var entries: Array = [_entry(goblin), _entry(titus)]

	var dest := HexCoordClass.new(2, 0)

	var rig: Dictionary = _make_use_case(entries, FakeStridePathlessAIDecisionPort.new(dest), 1)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])

	var instant_stub := RecordingInstantRepositionStub.new()
	var animate_stub := RecordingAnimatePathStub.new()
	session.set_token_reposition_fn(Callable(instant_stub, "move_token"))
	session.set_token_animate_path_fn(Callable(animate_stub, "animate_token_to"))

	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false))
	assert_eq(
		animate_stub.calls.size(), 0,
		"the animate-path fn must NOT be called when the decision Dictionary lacks a 'path' key, even though it is wired"
	)
	assert_eq(
		instant_stub.calls.size(), 1,
		"a wired-but-inapplicable animate-path fn must fall back to the instant _token_reposition_fn"
	)
	assert_eq(instant_stub.calls[0]["actor_id"], "goblin")
	assert_eq(instant_stub.calls[0]["hex"], dest)


func test_advance_ai_turn_stride_with_neither_reposition_seam_wired_does_not_raise() -> void:
	var goblin = _durable_combatant("Goblin", true, "goblin")
	var titus = _durable_combatant("Titus", false, "titus")
	var entries: Array = [_entry(goblin), _entry(titus)]

	var start := HexCoordClass.new(0, 0)
	var dest := HexCoordClass.new(2, 0)
	var stride_path: Array = [start, HexCoordClass.new(1, 0), dest]

	var rig: Dictionary = _make_use_case(entries, FakeStrideAIDecisionPort.new(dest, stride_path), 1)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])
	# Neither set_token_reposition_fn() nor set_token_animate_path_fn() is
	# ever called — mirrors every pre-existing headless/sim caller.

	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false), "an unwired reposition seam pair must never raise/stall the round loop")
	assert_eq(session.current_actor().name, "Titus", "the cursor must still advance")


# ══════════════════════════════════════════════════════════════════════════
# Outcome decided mid-turn: EncounterResultEvent emitted, round ends.
# ══════════════════════════════════════════════════════════════════════════

func test_end_current_turn_decides_outcome_and_emits_encounter_result_event() -> void:
	var lethal = _durable_combatant("Lethal", false)
	var fragile = _fragile_combatant("Fragile", true)
	var entries: Array = [_entry(lethal), _entry(fragile)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 99)
	var session = rig["use_case"].begin_round(1, [lethal], [fragile])

	# The player's own Strike is resolved directly via resolve_action_use_case
	# (exactly as StrikeActionControl does) -- RoundSession never wraps that
	# call itself, per the design's stepwise API contract.
	var resolve_result: Dictionary = rig["resolve_action_use_case"].resolve(
		lethal, entries[0]["action_economy"], fragile, "Strike", 1, 0
	)
	assert_true(resolve_result.get("resolved", false))
	assert_true(fragile.hp_current <= 0, "Fragile must have died to this Strike (fixture assumption)")

	var result: Dictionary = session.end_current_turn()

	assert_true(result.get("ok", false))
	assert_eq(result.get("outcome", ""), "won")
	assert_true(session.is_round_over())
	assert_eq(session.outcome(), "won")

	var result_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(result_events.size(), 1)
	assert_eq(result_events[0].outcome, "won")


# ══════════════════════════════════════════════════════════════════════════
# finish() shape/contract: matches RunRoundUseCase.execute()'s pre-FEAT-110
# RoundResult shape and resets every combatant's ActionEconomy.
# ══════════════════════════════════════════════════════════════════════════

func test_finish_resets_action_economy_and_returns_round_result_shape() -> void:
	var alpha = _durable_combatant("Alpha", false)
	var bravo = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(5, [alpha], [bravo])

	entries[0]["action_economy"].spend_action({"name": "Strike", "traits": []})

	var result: Dictionary = session.finish()

	assert_eq(result.get("round_number", -1), 5)
	assert_eq(result.get("outcome", "MISSING"), "")
	assert_eq(result.get("encounter_outcome", "MISSING"), "")
	assert_eq(result.get("history", null), [])
	assert_false(entries[0]["action_economy"].is_spent())
	assert_eq(entries[0]["action_economy"].get_remaining(), ActionEconomyClass.MAX_BUDGET, "finish() must call end_of_round() on every combatant")


# ══════════════════════════════════════════════════════════════════════════
# FEAT-007 (US-007, ADR-002): _safe_weapons() and the "weapons" key the
# three ReactionTrigger builders (_build_reaction_trigger/
# _build_prehit_avoidance_trigger/_build_onhit_mitigation_trigger) now
# populate alongside the existing "weapon" key.
# ══════════════════════════════════════════════════════════════════════════

## _session_for_trigger_tests() — a minimally-wired, REAL RoundSession (same
## rig convention as every other suite in this file) whose only purpose here
## is to expose the private _safe_weapons()/_build_*_trigger() methods under
## test — the round's own cursor/turn-order state is irrelevant to these
## pure, side-effect-free helpers.
func _session_for_trigger_tests():
	var alpha = _durable_combatant("Alpha", false)
	var entries: Array = [_entry(alpha)]
	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	return rig["use_case"].begin_round(1, [alpha], [])


func _attacker_fixture():
	return _durable_combatant("Attacker", true, "attacker")


## Patience's real 2-weapon loadout (mace primary, small shield off-hand),
## built via the ACTUAL infrastructure adapter from her real character
## resource — not a hand-authored stand-in — mirroring
## tests/unit/infrastructure/test_combatant_factory.gd's own established
## Patience fixture convention.
func _patience_combatant():
	var factory := CombatantFactoryClass.new()
	var combatant_dict: Dictionary = factory.build_party_combatant(DWARF_CHANNELER_PATH, null, "patience_1")
	assert_false(combatant_dict.has("error"), "fixture: dwarf_channeler.tres must build without error")
	return CombatantClass.from_dict(combatant_dict)


# ── _safe_weapons() ─────────────────────────────────────────────────────────

func test_safe_weapons_returns_the_entitys_weapons_array_when_present() -> void:
	var session = _session_for_trigger_tests()
	var patience = _patience_combatant()

	assert_eq(patience.weapons.size(), 2, "fixture assumption: Patience must have 2 weapons (mace + small shield)")

	var weapons: Array = session._safe_weapons(patience)

	assert_eq(weapons, patience.weapons, "_safe_weapons() must return the entity's own weapons array when present")
	assert_eq(weapons.size(), 2)


func test_safe_weapons_falls_back_to_weapon_for_an_entity_lacking_a_weapons_key() -> void:
	var session = _session_for_trigger_tests()
	# CombatantClass.from_dict() itself always derives a non-empty `weapons`
	# array once a spec carries a `weapon` (see combatant.gd's own doc) --
	# to genuinely exercise the empty-`weapons` fallback branch on the
	# ENTITY side, this fixture blanks `weapons` back out after construction.
	var solo = CombatantClass.from_dict({
		"name":   "Solo",
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 1, "damage_die": 6},
	})
	solo.weapons = []

	var weapons: Array = session._safe_weapons(solo)

	assert_eq(weapons, [solo.weapon], "_safe_weapons() must fall back to [weapon] when the entity's own weapons array is empty")


func test_safe_weapons_falls_back_to_weapon_for_a_dictionary_lacking_a_weapons_key() -> void:
	var session = _session_for_trigger_tests()
	var legacy_fixture: Dictionary = {
		"name":   "Legacy",
		"weapon": {"damage_modifier_attribute": "dexterity", "proficiency_bonus": 2, "damage_die": 4},
	}

	var weapons: Array = session._safe_weapons(legacy_fixture)

	assert_eq(weapons, [legacy_fixture["weapon"]], "_safe_weapons() must fall back to [weapon] for a Dictionary fixture lacking a 'weapons' key")


func test_safe_weapons_returns_the_dictionarys_weapons_array_when_present() -> void:
	var session = _session_for_trigger_tests()
	var weapons_array: Array = [{"name": "Mace"}, {"name": "Small Shield"}]
	var legacy_fixture: Dictionary = {
		"name":    "Legacy",
		"weapon":  {"name": "Mace"},
		"weapons": weapons_array,
	}

	var weapons: Array = session._safe_weapons(legacy_fixture)

	assert_eq(weapons, weapons_array, "_safe_weapons() must return the Dictionary's own 'weapons' array when present")


# ── Trigger builders populate 'weapons' alongside 'weapon' ─────────────────

func test_build_reaction_trigger_populates_weapons_key_alongside_weapon() -> void:
	var session = _session_for_trigger_tests()
	var attacker = _attacker_fixture()
	var target = _durable_combatant("Target", false)

	var trigger: Dictionary = session._build_reaction_trigger(attacker, target)

	assert_true(trigger.has("weapon"), "the pre-existing 'weapon' key must remain, byte-for-byte unchanged")
	assert_eq(trigger["weapon"], target.weapon)
	assert_true(trigger.has("weapons"), "_build_reaction_trigger() must now also populate a 'weapons' key")
	assert_eq(trigger["weapons"], session._safe_weapons(target))


func test_build_prehit_avoidance_trigger_populates_weapons_key_alongside_weapon() -> void:
	var session = _session_for_trigger_tests()
	var attacker = _attacker_fixture()
	var target = _durable_combatant("Target", false)

	var trigger: Dictionary = session._build_prehit_avoidance_trigger(attacker, target)

	assert_true(trigger.has("weapon"))
	assert_eq(trigger["weapon"], target.weapon)
	assert_true(trigger.has("weapons"), "_build_prehit_avoidance_trigger() must now also populate a 'weapons' key")
	assert_eq(trigger["weapons"], session._safe_weapons(target))


func test_build_onhit_mitigation_trigger_populates_weapons_key_alongside_weapon() -> void:
	var session = _session_for_trigger_tests()
	var attacker = _attacker_fixture()
	var target = _durable_combatant("Target", false)

	var trigger: Dictionary = session._build_onhit_mitigation_trigger(attacker, target, true, 15, 6)

	assert_true(trigger.has("weapon"))
	assert_eq(trigger["weapon"], target.weapon)
	assert_true(trigger.has("weapons"), "_build_onhit_mitigation_trigger() must now also populate a 'weapons' key")
	assert_eq(trigger["weapons"], session._safe_weapons(target))


# ── Patience's real 2-element weapons array reaches every trigger builder ──

func test_build_reaction_trigger_weapons_reflects_patiences_2_element_array_when_she_is_the_target() -> void:
	var session = _session_for_trigger_tests()
	var attacker = _attacker_fixture()
	var patience = _patience_combatant()

	var trigger: Dictionary = session._build_reaction_trigger(attacker, patience)

	assert_eq(trigger["weapons"].size(), 2, "Patience's 'weapons' array on the trigger must reflect her real 2-weapon loadout (mace + small shield)")
	assert_eq(trigger["weapons"], patience.weapons)
	assert_eq(trigger["weapons"][0].get("name", ""), "Mace")
	assert_eq(trigger["weapons"][1].get("name", ""), "Small Shield")


func test_build_prehit_avoidance_trigger_weapons_reflects_patiences_2_element_array_when_she_is_the_target() -> void:
	var session = _session_for_trigger_tests()
	var attacker = _attacker_fixture()
	var patience = _patience_combatant()

	var trigger: Dictionary = session._build_prehit_avoidance_trigger(attacker, patience)

	assert_eq(trigger["weapons"].size(), 2)
	assert_eq(trigger["weapons"], patience.weapons)


func test_build_onhit_mitigation_trigger_weapons_reflects_patiences_2_element_array_when_she_is_the_target() -> void:
	var session = _session_for_trigger_tests()
	var attacker = _attacker_fixture()
	var patience = _patience_combatant()

	var trigger: Dictionary = session._build_onhit_mitigation_trigger(attacker, patience, true, 15, 6)

	assert_eq(trigger["weapons"].size(), 2)
	assert_eq(trigger["weapons"], patience.weapons)


# ── Regression: pre-existing trigger-builder fixtures lacking a 'weapons'
#    key (built with only a 'weapon' key, the pre-FEAT-007 shape) still
#    resolve a single-element 'weapons' array and never raise. ─────────────

func test_build_reaction_trigger_regresses_safely_for_a_pre_existing_single_weapon_fixture() -> void:
	var session = _session_for_trigger_tests()
	var attacker = _attacker_fixture()
	# A pre-FEAT-007-shaped fixture: only a "weapon" key, no "weapons" array
	# authored -- CombatantClass.from_dict() derives weapons=[weapon] for it
	# automatically (combatant.gd's own established derivation), exactly the
	# ADR-002 backward-compatibility seam this feature relies on.
	var legacy_target = _durable_combatant("LegacyTarget", false)

	var trigger: Dictionary = session._build_reaction_trigger(attacker, legacy_target)

	assert_eq(trigger["weapons"], [legacy_target.weapon], "a pre-existing single-weapon fixture must degrade to a 1-element weapons array matching 'weapon'")
