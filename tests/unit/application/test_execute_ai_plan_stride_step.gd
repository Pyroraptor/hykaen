extends GutTest
## tests/unit/application/test_execute_ai_plan_stride_step.gd
##
## FEAT-010 (US-010 / FR-017, FR-018; RISK-001 mitigation: incremental
## commits per action-type branch) — GUT suite for the first increment of
## core/application/round_session.gd's new private helper
## `RoundSession._execute_ai_plan(plan: Array, combatant, action_economy) ->
## Dictionary`.
##
## Verifies (this feature's test_criteria):
##   1. A "Stride" plan item repositions the acting combatant's token to the
##      destination hex AND spends action economy per existing Stride
##      semantics (core/rules/movement.gd Movement.stride() — exactly one
##      Movement-trait action).
##   2. A "Step" plan item calls Movement.step(), repositions the token, and
##      does NOT spend action economy (core/rules/movement.gd's own "free"
##      contract).
##   3. An empty plan ([]) results in any_action_taken == false with no
##      errors.
##
## Mirrors tests/unit/application/test_decide_ai_action_dispatch.gd's
## established "build a REAL RunRoundUseCase/RoundSession, fake only the
## outer ports" rig convention (no phantom-method-on-a-spy risk), and its
## established "call a private-by-convention helper directly on the session"
## pattern (session._execute_ai_plan(...)).

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")


# ── Fake/double port implementations (mirrors test_decide_ai_action_dispatch.gd) ──

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


## FakeAIDecisionPort — a minimal legacy-shaped double, never actually
## exercised by this suite (this file calls session._execute_ai_plan()
## directly, never advance_ai_turn()) — supplied only because
## RunRoundUseCase's constructor requires an ai_decision_port collaborator.
class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant, _targets: Array) -> Dictionary:
		return {"action_type": "", "target": null}


# ── Shared fixture helpers ─────────────────────────────────────────────────

func _combatant_at(p_name: String, p_is_enemy: bool, p_q: int, p_r: int):
	return CombatantClass.from_dict({
		"name":       p_name,
		"hp_current": 10,
		"ac":         10,
		"strength":   1,
		"dexterity":  1,
		"intuition":  1,
		"_is_enemy":  p_is_enemy,
		"hex_coord":  HexCoordClass.new(p_q, p_r),
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 4
		}
	})


## Builds a fully-wired, REAL RunRoundUseCase/RoundSession (mirroring
## test_decide_ai_action_dispatch.gd's rig), returning the RoundSession so
## _execute_ai_plan() can be called directly on it.
func _make_session(party: Array, enemies: Array, seed: int):
	var turn_order_port     = FakeTurnOrderPort.new([])
	var event_sink_port     = FakeEventSinkPort.new()
	var round_history_port  = FakeRoundHistoryPort.new()
	var random_number_port  = SeededRandomAdapterClass.new(seed)
	var ai_decision_port    = FakeAIDecisionPort.new()

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, ai_decision_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	return run_round_use_case.begin_round(1, party, enemies)


# ══════════════════════════════════════════════════════════════════════════
# 1. "Stride" plan item repositions the token AND spends action economy
# ══════════════════════════════════════════════════════════════════════════

func test_stride_plan_item_repositions_token_and_spends_action_economy() -> void:
	var enemy = _combatant_at("Goblin", true, 0, 0)
	var ally  = _combatant_at("Ally", false, 10, 10)
	var session = _make_session([ally], [enemy], 1)

	var reposition_calls: Array = []
	session.set_token_reposition_fn(func(actor_id: String, destination) -> void:
		reposition_calls.append({"actor_id": actor_id, "destination": destination})
	)

	var destination := HexCoordClass.new(1, 0)
	var plan: Array = [{"action_type": "Stride", "destination": destination}]
	var action_economy := ActionEconomyClass.new()
	var budget_before: int = action_economy.get_remaining()

	var result: Dictionary = await session._execute_ai_plan(plan, enemy, action_economy)

	assert_true(result.get("ok", false), "_execute_ai_plan() must report ok == true")
	assert_true(result.get("any_action_taken", false), "a resolved Stride must set any_action_taken == true")
	assert_true(enemy.hex_coord.equals(destination), "a resolved Stride must reposition the combatant's own hex_coord to the destination")
	assert_eq(action_economy.get_remaining(), budget_before - 1, "a resolved Stride must spend exactly one action from action_economy, per Movement.stride()'s existing semantics")
	assert_eq(reposition_calls.size(), 1, "the injected token_reposition_fn must be invoked exactly once for a resolved Stride")
	assert_eq(reposition_calls[0]["actor_id"], enemy.display_id(), "the reposition call must carry the acting combatant's id")
	assert_true(reposition_calls[0]["destination"].equals(destination), "the reposition call must carry the Stride's destination hex")


# ══════════════════════════════════════════════════════════════════════════
# 2. "Step" plan item calls Movement.step(), repositions, spends NO economy
# ══════════════════════════════════════════════════════════════════════════

func test_step_plan_item_repositions_token_and_spends_no_action_economy() -> void:
	var enemy = _combatant_at("Skeleton", true, 0, 0)
	var ally  = _combatant_at("Ally", false, 10, 10)
	var session = _make_session([ally], [enemy], 2)

	var reposition_calls: Array = []
	session.set_token_reposition_fn(func(actor_id: String, destination) -> void:
		reposition_calls.append({"actor_id": actor_id, "destination": destination})
	)

	var destination := HexCoordClass.new(1, 0)
	var plan: Array = [{"action_type": "Step", "destination": destination}]
	var action_economy := ActionEconomyClass.new()
	var budget_before: int = action_economy.get_remaining()

	var result: Dictionary = await session._execute_ai_plan(plan, enemy, action_economy)

	assert_true(result.get("ok", false), "_execute_ai_plan() must report ok == true")
	assert_true(result.get("any_action_taken", false), "a resolved Step must set any_action_taken == true")
	assert_true(enemy.hex_coord.equals(destination), "a resolved Step must reposition the combatant's own hex_coord to the destination")
	assert_eq(action_economy.get_remaining(), budget_before, "a Step must NEVER spend action economy — Movement.step() is called without an action_economy argument")
	assert_false(action_economy.is_spent(), "a Step must never mark action_economy as Spent")
	assert_eq(reposition_calls.size(), 1, "the injected token_reposition_fn must be invoked exactly once for a resolved Step")
	assert_eq(reposition_calls[0]["actor_id"], enemy.display_id(), "the reposition call must carry the acting combatant's id")
	assert_true(reposition_calls[0]["destination"].equals(destination), "the reposition call must carry the Step's destination hex")


func test_step_plan_item_only_moves_one_hex_regardless_of_budget() -> void:
	# Movement.step()'s own domain contract limits a Step to exactly one
	# adjacent hex; passing a non-adjacent "destination" must fail the
	# underlying Movement.step() call and therefore NOT reposition/mark
	# progress — proving _execute_ai_plan() never re-implements adjacency
	# itself, it only ever delegates to Movement.step().
	var enemy = _combatant_at("Skeleton", true, 0, 0)
	var ally  = _combatant_at("Ally", false, 10, 10)
	var session = _make_session([ally], [enemy], 3)

	var far_destination := HexCoordClass.new(3, 0)
	var plan: Array = [{"action_type": "Step", "destination": far_destination}]
	var action_economy := ActionEconomyClass.new()

	var result: Dictionary = await session._execute_ai_plan(plan, enemy, action_economy)

	assert_false(result.get("any_action_taken", true), "a non-adjacent Step destination must fail Movement.step() and never report any_action_taken")
	assert_true(enemy.hex_coord.equals(HexCoordClass.new(0, 0)), "a failed Step must leave the combatant's hex_coord untouched")


# ══════════════════════════════════════════════════════════════════════════
# 3. Empty plan [] -> any_action_taken == false, no errors
# ══════════════════════════════════════════════════════════════════════════

func test_empty_plan_results_in_no_action_taken_and_no_errors() -> void:
	var enemy = _combatant_at("Idle Enemy", true, 0, 0)
	var ally  = _combatant_at("Ally", false, 10, 10)
	var session = _make_session([ally], [enemy], 4)

	var action_economy := ActionEconomyClass.new()
	var budget_before: int = action_economy.get_remaining()

	var result: Dictionary = await session._execute_ai_plan([], enemy, action_economy)

	assert_true(result.get("ok", false), "an empty plan must still report ok == true")
	assert_false(result.get("any_action_taken", true), "an empty plan (WAIT) must result in any_action_taken == false")
	assert_eq(action_economy.get_remaining(), budget_before, "an empty plan must never spend action economy")
	assert_true(enemy.hex_coord.equals(HexCoordClass.new(0, 0)), "an empty plan must never reposition the combatant")


# ══════════════════════════════════════════════════════════════════════════
# 4. Combine stub — still a documented no-op (real dispatch lands in a
#    later feature). "Strike" is deliberately no longer part of this test:
#    FEAT-399 (US-010 / FR-017, FR-018) gave _execute_ai_plan()'s "Strike"
#    match case its own real, verbatim reaction-window/two-phase-commit
#    dispatch (cut-pasted from the pre-FEAT-399 advance_ai_turn() Strike
#    branch) -- it is no longer a no-op stub, so pinning "Strike never sets
#    any_action_taken/never spends economy" here would now pin a behavior
#    this feature was explicitly required to REMOVE. Strike's real dispatch
#    (including its own soft-stop precondition) is covered by
#    tests/unit/application/test_execute_ai_plan_strike.gd instead.
# ══════════════════════════════════════════════════════════════════════════

func test_combine_item_is_a_no_op_stub_for_this_increment() -> void:
	var enemy  = _combatant_at("Grunt", true, 0, 0)
	var target = _combatant_at("Target", false, 1, 0)
	var session = _make_session([target], [enemy], 5)

	var plan: Array = [
		{"action_type": "Combine", "combined_queue": ["Stride", "Strike"]},
	]
	var action_economy := ActionEconomyClass.new()
	var budget_before: int = action_economy.get_remaining()

	var result: Dictionary = await session._execute_ai_plan(plan, enemy, action_economy)

	assert_true(result.get("ok", false), "a Combine stub item must still report ok == true")
	assert_false(result.get("any_action_taken", true), "a Combine stub item must NOT set any_action_taken (real dispatch lands in a later feature)")
	assert_eq(action_economy.get_remaining(), budget_before, "a Combine stub item must never spend action economy")
	assert_eq(target.hp_current, 10, "a stubbed Combine must never deal damage")
