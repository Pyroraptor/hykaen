extends GutTest
## tests/unit/test_round_session_turn_cursor.gd
##
## GUT test suite for FEAT-004 (US-004; ADR-101/ADR-102): wires
## ActionEconomy.start_of_turn() to the SINGLE cursor-advance call site on
## core/application/round_session.gd's RoundSession —
## RoundSession._advance_cursor() (and the initial cursor assignment in
## _init) — for BOTH player and AI actors, replacing the previous
## enemy-only call that lived directly inside advance_ai_turn(). Closes the
## P0-1 movement-lockout defect (a Player actor's movement_used_this_turn
## flag was never cleared, because start_of_turn() was previously only ever
## invoked from advance_ai_turn()) and gives every later layer one
## authoritative, testable turn-boundary seam.
##
## Verifies (test_criteria):
##   1. start_of_turn() is invoked exactly once when _advance_cursor() moves
##      the cursor to a new actor, for both player and AI actors.
##   2. start_of_turn() is invoked exactly once for the initial actor set in
##      _init.
##   3. advance_ai_turn() no longer independently calls start_of_turn()
##      (verified via a call-count spy ActionEconomy).
##   4. Stride-then-next-turn sequence: movement_used_this_turn resets to
##      false on the following turn for the same actor.
##   5. start_of_turn() does not mutate actions_remaining or is_spent
##      (regression check against ADR-102).

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")


# ── Spy ActionEconomy — counts start_of_turn() calls without changing any
# other observable behavior (delegates every call to the real parent
# implementation via super()). ────────────────────────────────────────────
class SpyActionEconomy:
	extends "res://core/rules/action_economy.gd"

	var start_of_turn_call_count: int = 0

	func start_of_turn(combatant = null) -> void:
		start_of_turn_call_count += 1
		if combatant == null:
			combatant = self
		super.start_of_turn(combatant)


# ── Fake/double port implementations (mirrors
# tests/unit/core/application/test_round_session.gd's isolation strategy) ──

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
## core/combat/ai.gd's real v0 behavior for combatants without hex_coord
## data), used here purely as an isolation double for the port itself.
class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant, targets: Array) -> Dictionary:
		for t in targets:
			if t.hp_current > 0:
				return {"action_type": "Strike", "target": t}
		return {"action_type": "", "target": null}


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


func _entry(combatant) -> Dictionary:
	return {"combatant": combatant, "action_economy": SpyActionEconomy.new()}


## Builds a fully-wired, REAL RunRoundUseCase (no phantom-method-on-a-spy)
## plus its fake ports.
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
# Criterion 2: start_of_turn() is invoked exactly once for the initial actor
# set in _init.
# ══════════════════════════════════════════════════════════════════════════

func test_init_calls_start_of_turn_exactly_once_for_the_initial_actor() -> void:
	var alpha = _durable_combatant("Alpha", false, "alpha")
	var bravo = _durable_combatant("Bravo", true, "bravo")
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_eq(session.current_actor().get("name", ""), "Alpha", "fixture assumption: Alpha is the initial current actor")
	assert_eq(
		entries[0]["action_economy"].start_of_turn_call_count, 1,
		"the initial cursor assignment in _init must call start_of_turn() exactly once for the initial actor"
	)
	assert_eq(
		entries[1]["action_economy"].start_of_turn_call_count, 0,
		"start_of_turn() must NOT be called yet for an actor whose turn has not started"
	)


func test_init_calls_start_of_turn_exactly_once_for_an_initial_ai_actor() -> void:
	# The initial actor may just as well be an Enemy -- _init's call site
	# must not distinguish between player and AI actors (ADR-101).
	var bravo = _durable_combatant("Bravo", true, "bravo")
	var alpha = _durable_combatant("Alpha", false, "alpha")
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_eq(session.current_actor().get("name", ""), "Bravo", "fixture assumption: Bravo (Enemy) is the initial current actor")
	assert_eq(
		entries[0]["action_economy"].start_of_turn_call_count, 1,
		"the initial cursor assignment in _init must call start_of_turn() exactly once for an initial AI actor too"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: start_of_turn() is invoked exactly once when _advance_cursor()
# moves the cursor to a new actor, for both player and AI actors.
# ══════════════════════════════════════════════════════════════════════════

func test_advance_cursor_calls_start_of_turn_exactly_once_for_the_next_player_actor() -> void:
	var alpha = _durable_combatant("Alpha", false, "alpha")
	var bravo = _durable_combatant("Bravo", true, "bravo")
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	# Cursor: Alpha (Player) -> Bravo (Enemy)
	assert_eq(session.current_actor().get("name", ""), "Alpha")
	session.end_current_turn()

	assert_eq(session.current_actor().get("name", ""), "Bravo")
	assert_eq(
		entries[1]["action_economy"].start_of_turn_call_count, 1,
		"_advance_cursor() must call start_of_turn() exactly once for the new current (Enemy) actor"
	)
	assert_eq(
		entries[0]["action_economy"].start_of_turn_call_count, 1,
		"advancing PAST Alpha must not call start_of_turn() on Alpha again"
	)


func test_advance_cursor_calls_start_of_turn_exactly_once_for_the_next_ai_actor_via_advance_ai_turn() -> void:
	var bravo = _durable_combatant("Bravo", true, "bravo")
	var alpha = _durable_combatant("Alpha", false, "alpha")
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	# Cursor: Bravo (Enemy) -> Alpha (Player), driven by advance_ai_turn().
	assert_eq(session.current_actor().get("name", ""), "Bravo")
	var result: Dictionary = session.advance_ai_turn()
	assert_true(result.get("ok", false))

	assert_eq(session.current_actor().get("name", ""), "Alpha")
	assert_eq(
		entries[1]["action_economy"].start_of_turn_call_count, 1,
		"_advance_cursor() must call start_of_turn() exactly once for the new current (Player) actor, even when the advance is driven by advance_ai_turn()"
	)
	assert_eq(
		entries[0]["action_economy"].start_of_turn_call_count, 1,
		"advancing PAST Bravo must not call start_of_turn() on Bravo again"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: advance_ai_turn() no longer independently calls
# start_of_turn() -- verified via the call-count spy.
# ══════════════════════════════════════════════════════════════════════════

func test_advance_ai_turn_does_not_independently_call_start_of_turn_on_the_current_actor() -> void:
	var bravo = _durable_combatant("Bravo", true, "bravo")
	var alpha = _durable_combatant("Alpha", false, "alpha")
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_eq(session.current_actor().get("name", ""), "Bravo")
	# start_of_turn() for Bravo was already invoked exactly once by _init's
	# cursor-positioning call site (criterion 2) -- reset the spy so this
	# assertion isolates ONLY what advance_ai_turn() itself does.
	var bravo_action_economy = entries[0]["action_economy"]
	assert_eq(bravo_action_economy.start_of_turn_call_count, 1, "fixture assumption: _init already called start_of_turn() once for Bravo")
	bravo_action_economy.start_of_turn_call_count = 0

	var result: Dictionary = session.advance_ai_turn()
	assert_true(result.get("ok", false))

	assert_eq(
		bravo_action_economy.start_of_turn_call_count, 0,
		"advance_ai_turn() must NOT independently call start_of_turn() on the acting (Bravo) combatant -- that call site was removed"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: Stride-then-next-turn sequence -- movement_used_this_turn
# resets to false on the following turn for the same actor.
# ══════════════════════════════════════════════════════════════════════════

func test_movement_lockout_resets_on_the_actors_following_turn() -> void:
	var alpha = _durable_combatant("Alpha", false, "alpha")
	var bravo = _durable_combatant("Bravo", true, "bravo")
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_eq(session.current_actor().get("name", ""), "Alpha")
	var alpha_action_economy = entries[0]["action_economy"]

	# Simulate a Stride having been taken this turn (the same gate
	# core/rules/movement.gd's stride()/step() trip).
	alpha_action_economy.mark_movement_used()
	assert_false(alpha_action_economy.can_take_movement_action(), "fixture assumption: the Movement gate must be tripped after a Stride")

	# Alpha's turn ends -> Bravo's (AI) turn is fully driven and resolved ->
	# the cursor cycles back around to Alpha (the only two combatants).
	session.end_current_turn()
	assert_eq(session.current_actor().get("name", ""), "Bravo")

	var ai_result: Dictionary = session.advance_ai_turn()
	assert_true(ai_result.get("ok", false))

	assert_eq(session.current_actor().get("name", ""), "Alpha", "the cursor must have cycled back around to Alpha")
	assert_true(
		alpha_action_economy.can_take_movement_action(),
		"movement_used_this_turn must reset to false on Alpha's following turn, via the single _advance_cursor() start_of_turn() call site"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: start_of_turn() does not mutate actions_remaining or
# is_spent (regression check against ADR-102).
# ══════════════════════════════════════════════════════════════════════════

func test_start_of_turn_does_not_mutate_actions_remaining_or_is_spent() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.spend_action({"name": "Strike", "traits": []})
	var remaining_before: int = ae.get_remaining()
	var is_spent_before: bool = ae.is_spent()

	ae.start_of_turn()

	assert_eq(ae.get_remaining(), remaining_before, "start_of_turn() must never mutate actions_remaining")
	assert_eq(ae.is_spent(), is_spent_before, "start_of_turn() must never mutate is_spent")


func test_advance_cursor_start_of_turn_call_site_does_not_refill_budget_or_clear_is_spent() -> void:
	# Integration-level companion to the direct check above: drive the SAME
	# call site _advance_cursor() uses and prove a partially-spent (but not
	# yet Spent) actor's budget survives the cursor cycling back to it.
	var alpha = _durable_combatant("Alpha", false, "alpha")
	var bravo = _durable_combatant("Bravo", true, "bravo")
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 7)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	var alpha_action_economy = entries[0]["action_economy"]
	alpha_action_economy.spend_action({"name": "Strike", "traits": []})
	var remaining_before: int = alpha_action_economy.get_remaining()
	assert_eq(remaining_before, ActionEconomyClass.MAX_BUDGET - 1)
	assert_false(alpha_action_economy.is_spent())

	session.end_current_turn()                # Alpha -> Bravo
	assert_eq(session.current_actor().get("name", ""), "Bravo")
	session.advance_ai_turn()                  # Bravo -> Alpha (cycles back)
	assert_eq(session.current_actor().get("name", ""), "Alpha")

	assert_eq(
		alpha_action_economy.get_remaining(), remaining_before,
		"the _advance_cursor() start_of_turn() call site must not refill actions_remaining when the cursor cycles back to a partially-spent actor"
	)
	assert_false(alpha_action_economy.is_spent(), "the _advance_cursor() start_of_turn() call site must not clear is_spent")
