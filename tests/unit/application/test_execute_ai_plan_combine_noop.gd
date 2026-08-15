extends GutTest
## tests/unit/application/test_execute_ai_plan_combine_noop.gd
##
## FEAT-400 (US-010 / FR-017, FR-018) — GUT suite for the FINAL increment of
## core/application/round_session.gd's private helper
## `RoundSession._execute_ai_plan(plan: Array, combatant, action_economy) ->
## Dictionary`: its "Combine" match case now delegates to an OPTIONAL,
## injected `_enemy_combine_resolver` collaborator (wired via the new
## `set_enemy_combine_resolver()` setter) when one is present, or remains
## the SAME documented full no-op FEAT-010 established when
## `_enemy_combine_resolver` is left null (the default, and the case for
## the ENTIRE pre-existing GUT suite).
##
## Verifies (this feature's test_criteria):
##   1. A "Combine" plan item with no resolver wired is a full no-op:
##      any_action_taken unaffected, no errors.
##   2. set_enemy_combine_resolver() correctly stores a resolver that is
##      invoked (with the plan item, the acting combatant, and the
##      action_economy) for subsequent "Combine" items, and that its
##      {"resolved": true} response drives any_action_taken exactly like
##      the Stride/Step/Strike cases already do.
##   3. A FakePlannerPort returning [] still results in WAIT
##      (any_action_taken == false) end-to-end through advance_ai_turn().
##   4. Pre-existing headless GUT tests that never wire a resolver remain
##      unaffected — exercised by the full project suite, not re-asserted
##      here (this file focuses on the NEW seam itself); mirrors
##      tests/unit/application/test_execute_ai_plan_stride_step.gd's own
##      pre-existing "Combine stub" no-op test, unmodified by this feature.
##
## Mirrors tests/unit/application/test_execute_ai_plan_strike.gd's and
## test_execute_ai_plan_stride_step.gd's established "build a REAL
## RunRoundUseCase/RoundSession, fake only the outer ports" rig convention.

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")


# ── Fake/double port implementations (mirrors test_execute_ai_plan_strike.gd) ──

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
## exercised by this suite's direct _execute_ai_plan() calls — supplied only
## because RunRoundUseCase's constructor requires an ai_decision_port
## collaborator.
class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant, _targets: Array) -> Dictionary:
		return {"action_type": "", "target": null}


## FakePlannerPort — a NEW-style AIPlannerPort-shaped duck-typed double
## (mirrors test_execute_ai_plan_strike.gd's own double), exposing
## plan_turn(combatant, world_context) -> Array.
class FakePlannerPort:
	extends "res://core/application/ai_planner_port.gd"

	var _plan_to_return: Array

	func _init(plan_to_return: Array) -> void:
		_plan_to_return = plan_to_return

	func plan_turn(_combatant, _world_context: Dictionary) -> Array:
		return _plan_to_return


## FakeEnemyCombineResolver — a duck-typed double satisfying the
## `resolve(item, combatant, action_economy) -> Dictionary` shape
## `_enemy_combine_resolver` documents (core/application/round_session.gd).
## Records every call it receives and returns whatever Dictionary the test
## configures, so callers can assert both "was it invoked, with what
## arguments" and "did its response drive any_action_taken".
class FakeEnemyCombineResolver:
	var calls: Array = []
	var _result_to_return: Dictionary

	func _init(result_to_return: Dictionary = {"resolved": true}) -> void:
		_result_to_return = result_to_return

	func resolve(item: Dictionary, combatant, action_economy) -> Dictionary:
		calls.append({"item": item, "combatant": combatant, "action_economy": action_economy})
		return _result_to_return


# ── Shared fixture helpers (mirrors test_execute_ai_plan_strike.gd) ────────

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


func _entry(combatant) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


## Builds a session via an EXPLICIT turn order (mirrors
## test_execute_ai_plan_strike.gd's own `_make_session_with_entries`
## convention) — needed by the advance_ai_turn()-driving WAIT test below.
func _make_session_with_entries(entries: Array, party: Array, enemies: Array, ai_decision_port, seed: int):
	var turn_order_port     = FakeTurnOrderPort.new(entries)
	var event_sink_port     = FakeEventSinkPort.new()
	var round_history_port  = FakeRoundHistoryPort.new()
	var random_number_port  = SeededRandomAdapterClass.new(seed)

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
# 1. "Combine" plan item with NO resolver wired is a full no-op.
# ══════════════════════════════════════════════════════════════════════════

func test_combine_item_with_no_resolver_wired_is_a_full_noop() -> void:
	var enemy  = _combatant_at("Grunt", true, 0, 0)
	var target = _combatant_at("Target", false, 1, 0)
	var session = _make_session([target], [enemy], 100)

	var plan: Array = [
		{"action_type": "Combine", "combined_queue": ["Stride", "Strike"]},
	]
	var action_economy := ActionEconomyClass.new()
	var budget_before: int = action_economy.get_remaining()

	var result: Dictionary = await session._execute_ai_plan(plan, enemy, action_economy)

	assert_true(result.get("ok", false), "a Combine item with no resolver wired must still report ok == true")
	assert_false(result.get("any_action_taken", true), "a Combine item with no resolver wired must NOT set any_action_taken")
	assert_eq(action_economy.get_remaining(), budget_before, "a Combine item with no resolver wired must never spend action economy")
	assert_eq(enemy.hex_coord.q, 0, "a Combine item with no resolver wired must never reposition the combatant")
	assert_eq(enemy.hex_coord.r, 0, "a Combine item with no resolver wired must never reposition the combatant")
	assert_eq(target.hp_current, 10, "a Combine item with no resolver wired must never deal damage")


func test_combine_item_with_no_resolver_wired_does_not_affect_a_prior_resolved_stride() -> void:
	# Mirrors the soft-stop/partial-plan-execution convention already
	# established for Strike (test_execute_ai_plan_strike.gd): a Combine
	# no-op must never retroactively clear any_action_taken set by an
	# earlier, genuinely resolved plan item.
	var enemy  = _combatant_at("Grunt", true, 0, 0)
	var target = _combatant_at("Target", false, 5, 0)
	var session = _make_session([target], [enemy], 101)

	var destination := HexCoordClass.new(1, 0)
	var plan: Array = [
		{"action_type": "Stride", "destination": destination},
		{"action_type": "Combine", "combined_queue": ["Stride", "Strike"]},
	]
	var action_economy := ActionEconomyClass.new()

	var result: Dictionary = await session._execute_ai_plan(plan, enemy, action_economy)

	assert_true(result.get("ok", false), "ok must be true")
	assert_true(result.get("any_action_taken", false), "the prior Stride's resolution must keep any_action_taken true despite the trailing Combine no-op")
	assert_true(enemy.hex_coord.equals(destination), "the Stride's repositioning must remain applied")


# ══════════════════════════════════════════════════════════════════════════
# 2. set_enemy_combine_resolver() stores a resolver invoked for subsequent
#    "Combine" items, whose response drives any_action_taken.
# ══════════════════════════════════════════════════════════════════════════

func test_set_enemy_combine_resolver_is_invoked_for_a_combine_item_with_expected_args() -> void:
	var enemy  = _combatant_at("Grunt", true, 0, 0)
	var target = _combatant_at("Target", false, 1, 0)
	var session = _make_session([target], [enemy], 102)

	var resolver := FakeEnemyCombineResolver.new({"resolved": true})
	session.set_enemy_combine_resolver(resolver)

	var combine_item: Dictionary = {"action_type": "Combine", "combined_queue": ["Stride", "Strike"], "target": target}
	var plan: Array = [combine_item]
	var action_economy := ActionEconomyClass.new()

	var result: Dictionary = await session._execute_ai_plan(plan, enemy, action_economy)

	assert_eq(resolver.calls.size(), 1, "a wired resolver's resolve() must be invoked exactly once for a Combine item")
	assert_same(resolver.calls[0]["item"], combine_item, "resolve() must receive the plan item verbatim")
	assert_same(resolver.calls[0]["combatant"], enemy, "resolve() must receive the acting combatant")
	assert_same(resolver.calls[0]["action_economy"], action_economy, "resolve() must receive the SAME ActionEconomy instance")
	assert_true(result.get("any_action_taken", false), "a resolver response of {resolved: true} must set any_action_taken, mirroring the Stride/Step/Strike convention")


func test_set_enemy_combine_resolver_unresolved_response_leaves_any_action_taken_false() -> void:
	var enemy  = _combatant_at("Grunt", true, 0, 0)
	var target = _combatant_at("Target", false, 1, 0)
	var session = _make_session([target], [enemy], 103)

	var resolver := FakeEnemyCombineResolver.new({"resolved": false})
	session.set_enemy_combine_resolver(resolver)

	var plan: Array = [{"action_type": "Combine", "combined_queue": []}]
	var action_economy := ActionEconomyClass.new()

	var result: Dictionary = await session._execute_ai_plan(plan, enemy, action_economy)

	assert_eq(resolver.calls.size(), 1, "the resolver must still be invoked even when it reports resolved == false")
	assert_false(result.get("any_action_taken", true), "a resolver response of {resolved: false} must NOT set any_action_taken")


func test_set_enemy_combine_resolver_is_invoked_once_per_combine_item_across_multiple_items() -> void:
	var enemy  = _combatant_at("Grunt", true, 0, 0)
	var target = _combatant_at("Target", false, 1, 0)
	var session = _make_session([target], [enemy], 104)

	var resolver := FakeEnemyCombineResolver.new({"resolved": true})
	session.set_enemy_combine_resolver(resolver)

	var plan: Array = [
		{"action_type": "Combine", "combined_queue": ["Stride"]},
		{"action_type": "Combine", "combined_queue": ["Strike"]},
	]
	var action_economy := ActionEconomyClass.new()

	await session._execute_ai_plan(plan, enemy, action_economy)

	assert_eq(resolver.calls.size(), 2, "a wired resolver must be invoked once per Combine item encountered in the plan")


# ══════════════════════════════════════════════════════════════════════════
# 3. FakePlannerPort returning [] still results in WAIT (any_action_taken
#    == false) end-to-end through advance_ai_turn() — no resolver wired.
# ══════════════════════════════════════════════════════════════════════════

func test_fake_planner_port_empty_plan_still_results_in_wait_through_advance_ai_turn() -> void:
	var goblin = _combatant_at("Goblin", true, 0, 0)
	var titus  = _combatant_at("Titus", false, 5, 0)

	var ai_planner_port = FakePlannerPort.new([])
	var entries: Array = [_entry(goblin), _entry(titus)]
	var session = _make_session_with_entries(entries, [titus], [goblin], ai_planner_port, 105)
	assert_eq(session.current_actor().name, "Goblin", "fixture assumption: the Enemy must act first")

	var entry: Dictionary = session._entries[session._cursor]
	var budget_before: int = entry["action_economy"].get_remaining()
	var hp_before: int = titus.hp_current

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false), "advance_ai_turn() must report ok == true even for a WAIT")
	assert_eq(
		entry["action_economy"].get_remaining(), budget_before - 1,
		"an empty plan_turn() Array must still resolve as an explicit WAIT (Actions.resolve_wait()), spending exactly one action — US-001's CWE-835 round-termination guarantee, unaffected by this feature"
	)
	assert_true(goblin.hex_coord.equals(HexCoordClass.new(0, 0)), "an empty plan must never reposition the combatant")
	assert_eq(titus.hp_current, hp_before, "an empty plan must never deal damage")
