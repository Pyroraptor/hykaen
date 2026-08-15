extends GutTest
## tests/unit/application/test_decide_ai_action_dispatch.gd
##
## FEAT-009 (US-009 / FR-016, ADR-002; RISK-006) — GUT suite for the
## backward-compatible plan_turn() dispatch seam added to
## core/application/round_session.gd's private helper
## `RoundSession._decide_ai_action(combatant, action_economy) -> Array`.
##
## Verifies (this feature's test_criteria):
##   1. Regression: an existing FakeDecisionPort (no plan_turn method) ->
##      _decide_ai_action() returns [legacy_result], byte-for-byte identical
##      to the pre-change (wrapped) behavior, for BOTH the 2-argument and
##      4-argument legacy decide_action() reflection shapes.
##   2. A new FakePlannerPort exposing plan_turn() -> _decide_ai_action()
##      calls plan_turn() and returns its Array VERBATIM, bypassing the
##      legacy decide_action() reflection path entirely (the fake's
##      decide_action(), if present, must never be invoked).
##   3. core/application/ai_decision_port.gd and core/combat/ai.gd remain
##      byte-for-byte unmodified by this feature (git-status diff-free
##      check, mirroring tests/unit/application/test_ai_planner_port.gd's
##      established convention for ai_decision_port.gd).
##
## Mirrors tests/unit/application/test_round_session_ai_world_context.gd's
## established "build a REAL RunRoundUseCase/RoundSession, fake only the
## outer ports" rig convention (no phantom-method-on-a-spy risk), and its
## established "call a private-by-convention helper directly on the session"
## pattern (session._decide_ai_action(...)).

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")

const AI_DECISION_PORT_PATH := "res://core/application/ai_decision_port.gd"
const AI_GD_PATH := "res://core/combat/ai.gd"


# ── Fake/double port implementations (mirrors test_round_session_ai_world_context.gd) ──

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


## FakeAIDecisionPort2Arg — the pre-existing 2-argument legacy shape (e.g.
## every FakeAIDecisionPort double already used across this codebase). No
## plan_turn() method at all -- Callable(self, "plan_turn").is_valid() must
## be false for this double.
class FakeAIDecisionPort2Arg:
	extends "res://core/application/ai_decision_port.gd"

	var decide_action_calls: int = 0

	func decide_action(_combatant, targets: Array) -> Dictionary:
		decide_action_calls += 1
		for t in targets:
			if t.hp_current > 0:
				return {"action_type": "Strike", "target": t}
		return {"action_type": "", "target": null}


## FakeAIDecisionPort4Arg — the pre-existing 4-argument legacy shape
## (mirrors core/combat/ai.gd's own decide_action(combatant, targets,
## action_economy, other_combatants) signature). Extends RefCounted directly
## (pure duck-typing, no formal `extends` relationship to ai_decision_port.gd)
## -- exactly mirroring core/combat/ai.gd's own established pattern (that
## file does not extend ai_decision_port.gd either, see that port's own
## file-level doc) -- since ai_decision_port.gd's base decide_action() is
## declared with a fixed 2-argument signature and GDScript enforces
## signature-compatible overrides for a formal `extends` relationship. No
## plan_turn() method.
class FakeAIDecisionPort4Arg:
	extends RefCounted

	var decide_action_calls: int = 0

	func decide_action(_combatant, targets: Array, _action_economy, _other_combatants: Array) -> Dictionary:
		decide_action_calls += 1
		for t in targets:
			if t.hp_current > 0:
				return {"action_type": "Strike", "target": t}
		return {"action_type": "", "target": null}


## FakePlannerPort — a NEW-style AIPlannerPort-shaped duck-typed double,
## exposing plan_turn(combatant, world_context) -> Array per
## core/application/ai_planner_port.gd's contract. Also exposes a
## decide_action() method (the legacy shape) purely so this suite can assert
## it is NEVER called once plan_turn() is present -- proving the dispatch
## bypasses the legacy reflection path entirely, not merely prefers the new
## one.
class FakePlannerPort:
	extends "res://core/application/ai_planner_port.gd"

	var plan_turn_calls: int = 0
	var decide_action_calls: int = 0
	var last_combatant
	var last_world_context: Dictionary
	var _plan_to_return: Array

	func _init(plan_to_return: Array) -> void:
		_plan_to_return = plan_to_return

	func plan_turn(combatant, world_context: Dictionary) -> Array:
		plan_turn_calls += 1
		last_combatant = combatant
		last_world_context = world_context
		return _plan_to_return

	## Present purely to prove _decide_ai_action() never falls through to it
	## once plan_turn() is valid.
	func decide_action(_combatant, _targets: Array) -> Dictionary:
		decide_action_calls += 1
		return {"action_type": "Strike", "target": null}


# ── Shared fixture helpers ─────────────────────────────────────────────────

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


## Builds a fully-wired, REAL RunRoundUseCase/RoundSession (mirroring
## test_round_session_ai_world_context.gd's explicit "no phantom-method-on-a-
## spy" convention), injecting `ai_decision_port` verbatim as the session's
## `_ai_decision_port` collaborator.
func _make_session(entries: Array, party: Array, enemies: Array, ai_decision_port, seed: int):
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
# 1. Regression: legacy FakeDecisionPort (no plan_turn) -> [legacy_result]
# ══════════════════════════════════════════════════════════════════════════

func test_legacy_2arg_port_returns_single_element_array_wrapping_decide_action_result() -> void:
	var enemy = _living_combatant("Goblin", true)
	var ally  = _living_combatant("Ally", false)
	var ai_decision_port = FakeAIDecisionPort2Arg.new()

	var session = _make_session([], [ally], [enemy], ai_decision_port, 1)
	var action_economy := ActionEconomyClass.new()

	var result: Array = await session._decide_ai_action(enemy, action_economy)

	assert_eq(typeof(result), TYPE_ARRAY, "_decide_ai_action() must return an Array")
	assert_eq(result.size(), 1, "the legacy fallback path must wrap decide_action()'s single Dictionary result in exactly one Array element")
	assert_eq(result[0], {"action_type": "Strike", "target": ally}, "the wrapped element must be byte-for-byte identical to decide_action()'s own return value")
	assert_eq(ai_decision_port.decide_action_calls, 1, "the legacy 2-argument decide_action() must have been invoked exactly once")


func test_legacy_4arg_port_returns_single_element_array_wrapping_decide_action_result() -> void:
	var enemy = _living_combatant("Goblin", true)
	var ally  = _living_combatant("Ally", false)
	var ai_decision_port = FakeAIDecisionPort4Arg.new()

	var session = _make_session([], [ally], [enemy], ai_decision_port, 2)
	var action_economy := ActionEconomyClass.new()

	var result: Array = await session._decide_ai_action(enemy, action_economy)

	assert_eq(typeof(result), TYPE_ARRAY, "_decide_ai_action() must return an Array")
	assert_eq(result.size(), 1, "the legacy fallback path must wrap the 4-arg decide_action()'s single Dictionary result in exactly one Array element")
	assert_eq(result[0], {"action_type": "Strike", "target": ally}, "the wrapped element must be byte-for-byte identical to decide_action()'s own return value")
	assert_eq(ai_decision_port.decide_action_calls, 1, "the legacy 4-argument decide_action() must have been invoked exactly once")


func test_legacy_port_with_no_living_target_wraps_empty_decision_verbatim() -> void:
	var enemy     = _living_combatant("Goblin", true)
	var dead_ally = _living_combatant("Dead Ally", false)
	dead_ally.hp_current = 0
	var ai_decision_port = FakeAIDecisionPort2Arg.new()

	var session = _make_session([], [dead_ally], [enemy], ai_decision_port, 3)
	var action_economy := ActionEconomyClass.new()

	var result: Array = await session._decide_ai_action(enemy, action_economy)

	assert_eq(result, [{"action_type": "", "target": null}], "an empty/no-target legacy decision must still be wrapped verbatim in a single-element Array, identical to pre-FEAT-009 behavior")


# ══════════════════════════════════════════════════════════════════════════
# 2. New FakePlannerPort with plan_turn() -> plan_turn's Array verbatim
# ══════════════════════════════════════════════════════════════════════════

func test_planner_port_with_plan_turn_bypasses_legacy_reflection_entirely() -> void:
	var enemy = _living_combatant("Grunt", true)
	var ally  = _living_combatant("Ally", false)
	var expected_plan: Array = [
		{"action_type": "Step", "destination": null},
		{"action_type": "Strike", "target": ally},
	]
	var ai_planner_port = FakePlannerPort.new(expected_plan)

	var session = _make_session([], [ally], [enemy], ai_planner_port, 4)
	var action_economy := ActionEconomyClass.new()

	var result: Array = await session._decide_ai_action(enemy, action_economy)

	assert_same(result, expected_plan, "plan_turn()'s Array must be returned VERBATIM (the same object), not copied/rewrapped")
	assert_eq(ai_planner_port.plan_turn_calls, 1, "plan_turn() must be called exactly once")
	assert_eq(ai_planner_port.decide_action_calls, 0, "the legacy decide_action() reflection path must NEVER be invoked once plan_turn() is valid")


func test_planner_port_receives_combatant_and_world_context() -> void:
	var enemy = _living_combatant("Grunt", true)
	var ally  = _living_combatant("Ally", false)
	var ai_planner_port = FakePlannerPort.new([])

	var session = _make_session([], [ally], [enemy], ai_planner_port, 5)
	var action_economy := ActionEconomyClass.new()

	await session._decide_ai_action(enemy, action_economy)

	assert_same(ai_planner_port.last_combatant, enemy, "plan_turn() must receive the acting combatant verbatim")
	assert_true(ai_planner_port.last_world_context.has("party"), "plan_turn() must receive a world_context carrying 'party'")
	assert_true(ai_planner_port.last_world_context.has("enemies"), "plan_turn() must receive a world_context carrying 'enemies'")
	assert_same(ai_planner_port.last_world_context.get("action_economy"), action_economy, "plan_turn()'s world_context.action_economy must be the SAME ActionEconomy instance passed in")


func test_planner_port_empty_plan_is_returned_verbatim_as_empty_array() -> void:
	var enemy = _living_combatant("Grunt", true)
	var ally  = _living_combatant("Ally", false)
	var ai_planner_port = FakePlannerPort.new([])

	var session = _make_session([], [ally], [enemy], ai_planner_port, 6)
	var action_economy := ActionEconomyClass.new()

	var result: Array = await session._decide_ai_action(enemy, action_economy)

	assert_eq(result, [], "an empty plan_turn() Array (WAIT) must be returned verbatim, not coerced into a single-element wrapper")


# ══════════════════════════════════════════════════════════════════════════
# 3. Frozen files remain byte-for-byte unmodified (diff-free git check)
# ══════════════════════════════════════════════════════════════════════════

func _repo_root() -> String:
	return ProjectSettings.globalize_path("res://")


func _git_available() -> bool:
	var out: Array = []
	var rc: int = OS.execute("git", ["-C", _repo_root(), "rev-parse", "--is-inside-work-tree"], out, true)
	return rc == 0


func _assert_file_unmodified(path: String) -> void:
	if not _git_available():
		pending("git unavailable in this sandbox -- skipping %s diff-free check" % path)
		return

	var relative_path: String = path.replace("res://", "")
	var out: Array = []
	var rc: int = OS.execute(
		"git",
		["-C", _repo_root(), "status", "--porcelain", "--", relative_path],
		out,
		true
	)
	var combined: String = ""
	for line in out:
		combined += String(line)

	assert_eq(rc, 0, "git status --porcelain -- %s must exit 0" % relative_path)
	assert_eq(
		combined.strip_edges(), "",
		(
			"%s must remain byte-for-byte unmodified/untouched by FEAT-009 "
			+ "(the plan_turn() dispatch is established entirely inside "
			+ "round_session.gd's own duck-typed Callable check). Offending "
			+ "git status output:\n%s"
		) % [relative_path, combined]
	)


func test_ai_decision_port_is_unmodified_by_feat_009() -> void:
	_assert_file_unmodified(AI_DECISION_PORT_PATH)


func test_ai_gd_is_unmodified_by_feat_009() -> void:
	_assert_file_unmodified(AI_GD_PATH)


func test_frozen_files_still_exist_and_are_readable() -> void:
	assert_true(FileAccess.file_exists(AI_DECISION_PORT_PATH), "ai_decision_port.gd must still exist at its frozen path")
	assert_true(FileAccess.file_exists(AI_GD_PATH), "core/combat/ai.gd must still exist at its frozen path")
