extends GutTest
## tests/unit/application/test_composition_root_ai_planner_wiring.gd
##
## FEAT-401 (US-011 / FR-019 part 1, ADR-003) — GUT suite for the
## composition-root AIPlannerPort wiring added to
## core/application/run_round_use_case.gd's begin_round() and the
## consuming precedence rule added to
## core/application/round_session.gd's _decide_ai_action().
##
## Verifies (this feature's test_criteria):
##   1. Each enemy entry built at the composition root (begin_round()) has
##      entry['ai_planner'] set to the planner AITierRegistry.get_planner()
##      returns for that combatant's authored ai_tier.
##   2. A pre-existing entry whose combatant carries no ai_tier data at all
##      (e.g. today's core/domain/combatant.gd Combatant entity, built the
##      SAME way every other pre-existing GUT fixture in this codebase
##      builds one) is left WITHOUT an 'ai_planner' key — begin_round()
##      still compiles and completes without error, and
##      entry.get('ai_planner', null) degrades to null, never a crash.
##   3. RoundSession._decide_ai_action() prefers entry['ai_planner'] over the
##      session-level _ai_decision_port whenever both are present.
##
## Mirrors tests/unit/application/test_decide_ai_action_dispatch.gd's
## established "build a REAL RunRoundUseCase/RoundSession, fake only the
## outer ports" rig convention.
##
## Satisfies: FEAT-401, US-011, FR-019 (part 1).

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const MindlessAIClass              = preload("res://core/combat/mindless_ai.gd")
const GruntAIClass                 = preload("res://core/combat/grunt_ai.gd")


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


## FakeAIDecisionPort2Arg — the pre-existing legacy shape (no plan_turn
## method), mirrors test_decide_ai_action_dispatch.gd's own double.
class FakeAIDecisionPort2Arg:
	extends "res://core/application/ai_decision_port.gd"

	var decide_action_calls: int = 0

	func decide_action(_combatant, _targets: Array) -> Dictionary:
		decide_action_calls += 1
		return {"action_type": "", "target": null}


## FakePlannerPort — a NEW-style AIPlannerPort-shaped double, mirrors
## test_decide_ai_action_dispatch.gd's own double.
class FakePlannerPort:
	extends "res://core/application/ai_planner_port.gd"

	var plan_turn_calls: int = 0
	var _plan_to_return: Array

	func _init(plan_to_return: Array) -> void:
		_plan_to_return = plan_to_return

	func plan_turn(_combatant, _world_context: Dictionary) -> Array:
		plan_turn_calls += 1
		return _plan_to_return


## FakeCombatantWithAiTier — a duck-typed combatant double carrying the
## MINIMAL set of properties RoundSession's constructor path
## (_find_first_actionable_index() -> _is_actionable() -> combatant.hp_current)
## requires, PLUS an explicit ai_tier/is_enemy pair — proving the composition
## root's ai_tier read works against ANY Object exposing the property (not
## only a Dictionary), the shape a future CombatSessionFactory update might
## eventually produce (out of scope for this feature; core/domain/
## combatant.gd itself is untouched by this feature — see test 2 below,
## which exercises the REAL entity instead).
class FakeCombatantWithAiTier:
	extends RefCounted

	var hp_current: int = 10
	var is_enemy: bool = true
	var ai_tier: String
	var name: String

	func _init(p_name: String, p_ai_tier: String) -> void:
		name = p_name
		ai_tier = p_ai_tier


# ── Shared fixture helpers ──────────────────────────────────────────────────

func _living_combatant(p_name: String, p_is_enemy: bool):
	return CombatantClass.from_dict({
		"name":       p_name,
		"hp_current": 10,
		"ac":         10,
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


func _make_run_round_use_case(entries: Array, ai_decision_port, seed: int):
	var turn_order_port     = FakeTurnOrderPort.new(entries)
	var event_sink_port     = FakeEventSinkPort.new()
	var round_history_port  = FakeRoundHistoryPort.new()
	var random_number_port  = SeededRandomAdapterClass.new(seed)

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()

	return RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, ai_decision_port,
		resolve_action_use_case, determine_outcome_use_case
	)


# ══════════════════════════════════════════════════════════════════════════
# 1. Each enemy entry gets entry['ai_planner'] from AITierRegistry.get_planner
# ══════════════════════════════════════════════════════════════════════════

func test_begin_round_wires_grunt_tier_entry_to_grunt_ai_planner() -> void:
	var ally  = _living_combatant("Ally", false)
	var grunt = FakeCombatantWithAiTier.new("Grunt", "grunt")

	var entries: Array = [
		{"combatant": grunt, "action_economy": ActionEconomyClass.new()},
	]
	var ai_decision_port = FakeAIDecisionPort2Arg.new()
	var use_case = _make_run_round_use_case(entries, ai_decision_port, 1)

	use_case.begin_round(1, [ally], [grunt])

	assert_true(entries[0].has("ai_planner"), "an enemy entry with ai_tier='grunt' must have 'ai_planner' wired by begin_round()")
	assert_true(
		is_instance_of(entries[0]["ai_planner"], GruntAIClass),
		"AITierRegistry.get_planner('grunt') must produce a GruntAI instance"
	)


func test_begin_round_wires_mindless_tier_entry_to_mindless_ai_planner() -> void:
	var ally     = _living_combatant("Ally", false)
	var skeleton = FakeCombatantWithAiTier.new("Skeleton", "mindless")

	var entries: Array = [
		{"combatant": skeleton, "action_economy": ActionEconomyClass.new()},
	]
	var ai_decision_port = FakeAIDecisionPort2Arg.new()
	var use_case = _make_run_round_use_case(entries, ai_decision_port, 2)

	use_case.begin_round(1, [ally], [skeleton])

	assert_true(entries[0].has("ai_planner"), "an enemy entry with ai_tier='mindless' must have 'ai_planner' wired by begin_round()")
	assert_true(
		is_instance_of(entries[0]["ai_planner"], MindlessAIClass),
		"AITierRegistry.get_planner('mindless') must produce a MindlessAI instance"
	)


func test_begin_round_wires_unrecognized_tier_entry_to_mindless_ai_fallback() -> void:
	var ally    = _living_combatant("Ally", false)
	var soldier = FakeCombatantWithAiTier.new("Soldier", "soldier")

	var entries: Array = [
		{"combatant": soldier, "action_economy": ActionEconomyClass.new()},
	]
	var ai_decision_port = FakeAIDecisionPort2Arg.new()
	var use_case = _make_run_round_use_case(entries, ai_decision_port, 7)

	use_case.begin_round(1, [ally], [soldier])

	assert_true(
		is_instance_of(entries[0]["ai_planner"], MindlessAIClass),
		"AITierRegistry's own unrecognized-tier fallback (e.g. TEMPORARY 'soldier' alias) must still apply when wiring via the composition root"
	)


# ══════════════════════════════════════════════════════════════════════════
# 2. Pre-existing entries whose combatant carries no ai_tier data are
#    unaffected — entry.get('ai_planner', null) still degrades safely
# ══════════════════════════════════════════════════════════════════════════

func test_begin_round_leaves_ai_planner_unset_for_combatant_without_ai_tier() -> void:
	var ally  = _living_combatant("Ally", false)
	var enemy = _living_combatant("Goblin", true)   # REAL Combatant entity -- no ai_tier property

	var entries: Array = [
		{"combatant": enemy, "action_economy": ActionEconomyClass.new()},
	]
	var ai_decision_port = FakeAIDecisionPort2Arg.new()
	var use_case = _make_run_round_use_case(entries, ai_decision_port, 3)

	var session = use_case.begin_round(1, [ally], [enemy])

	assert_not_null(session, "begin_round() must not crash/return null for a combatant with no ai_tier data")
	assert_eq(
		entries[0].get("ai_planner", null), null,
		"a combatant carrying no ai_tier data at all must NOT have 'ai_planner' set -- this would otherwise silently override every pre-existing test's session-level _ai_decision_port double"
	)


func test_legacy_entry_omitting_ai_planner_key_still_falls_back_to_session_port() -> void:
	var ally  = _living_combatant("Ally", false)
	var enemy = _living_combatant("Goblin", true)

	var entries: Array = [
		{"combatant": enemy, "action_economy": ActionEconomyClass.new()},
	]
	var ai_decision_port = FakeAIDecisionPort2Arg.new()
	var use_case = _make_run_round_use_case(entries, ai_decision_port, 4)

	var session = use_case.begin_round(1, [ally], [enemy])
	var action_economy = entries[0]["action_economy"]

	var result: Array = await session._decide_ai_action(enemy, action_economy, entries[0])

	assert_eq(ai_decision_port.decide_action_calls, 1, "an entry without 'ai_planner' must fall back to the session-level _ai_decision_port's decide_action()")
	assert_eq(result, [{"action_type": "", "target": null}], "the legacy fallback result must be wrapped verbatim, exactly as pre-FEAT-401")


func test_decide_ai_action_without_entry_arg_still_falls_back_to_session_port() -> void:
	var ally  = _living_combatant("Ally", false)
	var enemy = _living_combatant("Goblin", true)

	var ai_decision_port = FakeAIDecisionPort2Arg.new()
	var use_case = _make_run_round_use_case([], ai_decision_port, 6)
	var session = use_case.begin_round(1, [ally], [enemy])

	var action_economy := ActionEconomyClass.new()
	var result: Array = await session._decide_ai_action(enemy, action_economy)

	assert_eq(ai_decision_port.decide_action_calls, 1, "_decide_ai_action() called with no 'entry' argument (the pre-FEAT-401 2-argument call convention) must still fall back to _ai_decision_port")
	assert_eq(result, [{"action_type": "", "target": null}])


# ══════════════════════════════════════════════════════════════════════════
# 3. entry['ai_planner'] takes precedence over the session-level
#    _ai_decision_port when both are present
# ══════════════════════════════════════════════════════════════════════════

func test_decide_ai_action_prefers_entry_ai_planner_over_session_level_port() -> void:
	var ally  = _living_combatant("Ally", false)
	var enemy = _living_combatant("Goblin", true)

	var entries: Array = [
		{"combatant": enemy, "action_economy": ActionEconomyClass.new()},
	]
	# Session-level port: a legacy double with NO plan_turn() method.
	var ai_decision_port = FakeAIDecisionPort2Arg.new()
	var use_case = _make_run_round_use_case(entries, ai_decision_port, 5)

	var session = use_case.begin_round(1, [ally], [enemy])

	# Entry-level planner hand-wired directly here: end-to-end wiring through
	# begin_round() itself is exercised by test 1 above; this test isolates
	# _decide_ai_action()'s OWN precedence logic against a fully-formed entry,
	# independent of begin_round()'s ai_tier-presence gating.
	var expected_plan: Array = [{"action_type": "Strike", "target": ally}]
	var entry_planner = FakePlannerPort.new(expected_plan)
	entries[0]["ai_planner"] = entry_planner

	var action_economy = entries[0]["action_economy"]
	var result: Array = await session._decide_ai_action(enemy, action_economy, entries[0])

	assert_same(result, expected_plan, "_decide_ai_action() must return the entry-level planner's plan verbatim")
	assert_eq(entry_planner.plan_turn_calls, 1, "the entry-level ai_planner's plan_turn() must be called exactly once")
	assert_eq(ai_decision_port.decide_action_calls, 0, "the session-level _ai_decision_port must NEVER be consulted once an entry-level ai_planner is present")


func test_decide_ai_action_prefers_entry_ai_planner_even_when_session_port_also_plan_turn_shaped() -> void:
	var ally  = _living_combatant("Ally", false)
	var enemy = _living_combatant("Goblin", true)

	var entries: Array = [
		{"combatant": enemy, "action_economy": ActionEconomyClass.new()},
	]
	# Session-level port is ITSELF a new-style AIPlannerPort double this time,
	# proving entry-level precedence holds even when the session-level
	# fallback would otherwise be perfectly usable.
	var session_plan: Array = [{"action_type": "Strike", "target": ally}]
	var session_level_planner = FakePlannerPort.new(session_plan)
	var use_case = _make_run_round_use_case(entries, session_level_planner, 8)

	var session = use_case.begin_round(1, [ally], [enemy])

	var entry_plan: Array = []
	var entry_planner = FakePlannerPort.new(entry_plan)
	entries[0]["ai_planner"] = entry_planner

	var action_economy = entries[0]["action_economy"]
	var result: Array = await session._decide_ai_action(enemy, action_economy, entries[0])

	assert_same(result, entry_plan, "the entry-level ai_planner's plan must win even though the session-level port is ALSO plan_turn-shaped")
	assert_eq(entry_planner.plan_turn_calls, 1)
	assert_eq(session_level_planner.plan_turn_calls, 0, "the session-level planner must never be consulted once an entry-level ai_planner is present")
