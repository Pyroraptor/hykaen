extends GutTest
## tests/unit/test_wait_action.gd
##
## GUT unit test suite for the explicit WAIT action (US-001 / FR-001,
## ADR-010): the business-logic foundation for round termination.
##
## core/rules/actions.gd introduces Actions.resolve_wait() — a resolvable
## "do nothing productive this turn" action with no Movement trait and no
## target, that spends exactly one action from the SAME per-round
## ActionEconomy budget every other resolvable action draws from
## (core/rules/action_economy.gd's spend_action()). core/application/
## round_session.gd's advance_ai_turn() now resolves core/combat/ai.gd's
## null-action AI sentinel (no living target, or the nearest one is
## permanently out of reach and cannot be closed this turn) through WAIT,
## instead of a bare, budget-neutral cursor advance -- guaranteeing an
## idle/unreachable Enemy actually depletes to Spent within
## ActionEconomy.MAX_BUDGET (7) of its own turns.
##
## Verifies (test_criteria):
##   1. An out-of-reach enemy becomes Spent within 7 of its own turns.
##   2. A kiting 1v1 scenario (the enemy can never close the distance)
##      terminates the round.
##   3. WAIT calls ActionEconomy.spend_action() exactly once per resolution.

const ActionsClass                 = preload("res://core/rules/actions.gd")
const AIClass                      = preload("res://core/combat/ai.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")


# ── Test doubles ─────────────────────────────────────────────────────────

## SpyActionEconomy — a real ActionEconomy that additionally counts every
## spend_action() call it receives (mirrors
## tests/unit/test_ai_decision_single_action.gd's identically-named double),
## so criterion 3 can assert the EXACT call count a WAIT resolution makes.
class SpyActionEconomy:
	extends "res://core/rules/action_economy.gd"

	var spend_action_call_count: int = 0

	func spend_action(action_metadata: Dictionary) -> Dictionary:
		spend_action_call_count += 1
		return super.spend_action(action_metadata)


## StuckActionEconomy — a real ActionEconomy that keeps the Movement-trait
## gate permanently tripped across every start_of_turn() call, so a melee
## enemy that is out of reach and can never legally Stride toward its target
## (decide_action()'s Stride-closing path requires
## can_take_movement_action() == true) is forced into the null-action AI
## sentinel EVERY decision cycle -- deterministically simulating "genuinely
## stuck, out of reach, forever" without needing to hand-build an occupied
## hex ring around the combatant.
class StuckActionEconomy:
	extends "res://core/rules/action_economy.gd"

	func start_of_turn(combatant = self) -> void:
		super.start_of_turn(combatant)
		mark_movement_used()


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


# ── Shared fixture helpers ─────────────────────────────────────────────────

func _melee_combatant(hex_coord) -> Dictionary:
	return {
		"name":        "Skeleton",
		"hp_current":  8,
		"ac":          12,
		"strength":    2,
		"hex_coord":   hex_coord,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 6
		}
	}


func _target(name: String, hex_coord, hp: int = 18) -> Dictionary:
	return {"name": name, "hp_current": hp, "ac": 14, "strength": 5, "hex_coord": hex_coord}


func _entry(combatant: Dictionary, action_economy = null) -> Dictionary:
	return {"combatant": combatant, "action_economy": action_economy if action_economy != null else ActionEconomyClass.new()}


func _make_use_case(entries: Array, random_number_port) -> Dictionary:
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

	return {"use_case": run_round_use_case, "history": round_history_port, "events": event_sink_port}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (unit, in isolation): WAIT calls ActionEconomy.spend_action()
# exactly once per resolution.
# ══════════════════════════════════════════════════════════════════════════

func test_resolve_wait_calls_spend_action_exactly_once() -> void:
	var action_economy = SpyActionEconomy.new()
	action_economy.start_of_turn()

	var result: Dictionary = ActionsClass.resolve_wait(action_economy)

	assert_eq(action_economy.spend_action_call_count, 1, "resolve_wait() must call ActionEconomy.spend_action() exactly once")
	assert_true(result.get("success", false), "a fresh combatant's WAIT must succeed")
	assert_eq(result.get("remaining", -1), ActionEconomyClass.MAX_BUDGET - 1, "WAIT must spend exactly one action from the shared budget")


func test_resolve_wait_carries_no_movement_trait() -> void:
	# WAIT must never trip the Movement-trait gate a Step/Stride shares --
	# a combatant that WAITs this turn must remain free to Stride later THIS
	# SAME turn's movement gate (i.e. WAIT never marks movement used).
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	ActionsClass.resolve_wait(action_economy)

	assert_true(
		action_economy.can_take_movement_action(),
		"WAIT must not consume/trip the per-turn Movement-trait gate"
	)


func test_resolve_wait_repeated_calls_each_spend_exactly_one_action() -> void:
	var action_economy = SpyActionEconomy.new()
	action_economy.start_of_round()

	for turn_index in range(ActionEconomyClass.MAX_BUDGET):
		action_economy.start_of_turn()
		var result: Dictionary = ActionsClass.resolve_wait(action_economy)
		assert_true(result.get("success", false), "turn %d: WAIT must succeed while budget remains" % turn_index)

	assert_eq(
		action_economy.spend_action_call_count, ActionEconomyClass.MAX_BUDGET,
		"exactly one spend_action() call must occur per resolve_wait() call, across all %d turns" % ActionEconomyClass.MAX_BUDGET
	)
	assert_true(action_economy.is_spent(), "the budget must be fully exhausted after MAX_BUDGET WAITs")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: an out-of-reach enemy becomes Spent within 7 of its own
# turns.
# ══════════════════════════════════════════════════════════════════════════

func test_out_of_reach_enemy_becomes_spent_within_seven_of_its_own_turns() -> void:
	var goblin: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
	goblin["_is_enemy"] = true
	# Out of melee reach and permanently unable to close the distance
	# (StuckActionEconomy keeps the Movement-trait gate tripped every turn),
	# so decide_action() must return the null-action AI sentinel every
	# decision cycle -- exactly the "genuinely idle" case WAIT exists for.
	var titus: Dictionary = _target("Titus", HexCoordClass.new(9, 0), 200)
	titus["_is_enemy"] = false

	var goblin_action_economy = StuckActionEconomy.new()
	var entries: Array = [_entry(goblin, goblin_action_economy), _entry(titus)]

	var random_number_port = SeededRandomAdapterClass.new(1)
	var rig: Dictionary = _make_use_case(entries, random_number_port)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])

	assert_eq(session.current_actor().name, "Skeleton", "fixture assumption: the enemy must start as current actor")

	var enemy_turns_taken: int = 0
	while not goblin_action_economy.is_spent() and enemy_turns_taken < ActionEconomyClass.MAX_BUDGET:
		assert_eq(session.current_actor().name, "Skeleton", "iteration %d: the enemy must be current actor" % enemy_turns_taken)
		var result: Dictionary = session.advance_ai_turn()
		assert_true(result.get("ok", false), "iteration %d: advance_ai_turn() must never fail/stall" % enemy_turns_taken)
		enemy_turns_taken += 1

		# Player's turn: passes without spending (mirrors end_current_turn()'s
		# documented "always available regardless of what was spent" contract)
		# so control returns to the enemy for its next turn.
		if not session.is_round_over():
			session.end_current_turn()

	assert_true(
		goblin_action_economy.is_spent(),
		"the out-of-reach enemy must become Spent within %d of its own turns" % ActionEconomyClass.MAX_BUDGET
	)
	assert_true(
		enemy_turns_taken <= ActionEconomyClass.MAX_BUDGET,
		"the enemy must not require more than %d of its own turns to become Spent (took %d)" % [ActionEconomyClass.MAX_BUDGET, enemy_turns_taken]
	)
	assert_eq(goblin_action_economy.get_remaining(), 0)
	assert_true(
		titus.get("hp_current", 0) == 200,
		"the out-of-reach enemy must never have landed a Strike -- every one of its turns must have been a WAIT"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: a kiting 1v1 scenario (the enemy can never close the
# distance) terminates the round.
# ══════════════════════════════════════════════════════════════════════════

func test_kiting_1v1_scenario_terminates_the_round() -> void:
	var goblin: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
	goblin["_is_enemy"] = true
	var titus: Dictionary = _target("Titus", HexCoordClass.new(9, 0), 200)
	titus["_is_enemy"] = false

	# Both combatants are "stuck": the enemy can never close the distance
	# (StuckActionEconomy keeps Movement locked), and the player -- kiting,
	# never engaging -- simply WAITs out its own turns too, so BOTH sides'
	# budgets deplete and the round genuinely reaches its terminal state
	# rather than looping forever waiting on one side that never spends.
	var goblin_action_economy = StuckActionEconomy.new()
	var titus_action_economy  = ActionEconomyClass.new()
	var entries: Array = [_entry(goblin, goblin_action_economy), _entry(titus, titus_action_economy)]

	var random_number_port = SeededRandomAdapterClass.new(2)
	var rig: Dictionary = _make_use_case(entries, random_number_port)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])

	# A generous bound (well beyond the 7+7=14 turns this scenario actually
	# needs) proving the round terminates rather than hanging -- this test
	# fails loudly (via the round_over assertion below) rather than looping
	# forever if WAIT's guarantee ever regresses.
	var max_steps: int = 50
	var steps_taken: int = 0

	while not session.is_round_over() and steps_taken < max_steps:
		var actor = session.current_actor()
		if actor.is_enemy:
			session.advance_ai_turn()
		else:
			var actor_economy = session.current_action_economy()
			ActionsClass.resolve_wait(actor_economy)
			session.end_current_turn()
		steps_taken += 1

	assert_true(
		session.is_round_over(),
		"a kiting 1v1 scenario must terminate the round within %d steps, not hang forever" % max_steps
	)
	assert_true(steps_taken < max_steps, "the round must terminate well before the generous safety bound")

	# Assert budget depletion BEFORE finish() -- finish() calls
	# ActionEconomy.end_of_round() on every combatant, which resets the
	# budget for the NEXT round (by design), so it must be inspected first.
	assert_true(goblin_action_economy.is_spent(), "the enemy's budget must be fully depleted once the round terminates")
	assert_true(titus_action_economy.is_spent(), "the player's budget must be fully depleted once the round terminates")

	var round_result: Dictionary = session.finish()
	assert_eq(
		round_result.get("outcome", ""), "",
		"neither combatant was ever defeated in a pure kiting scenario -- the round-level outcome must remain undecided"
	)
