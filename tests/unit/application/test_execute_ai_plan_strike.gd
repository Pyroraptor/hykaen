extends GutTest
## tests/unit/application/test_execute_ai_plan_strike.gd
##
## FEAT-399 (US-010 / FR-017, FR-018, ADR-007) — GUT suite for the SECOND
## increment of core/application/round_session.gd's private helper
## `RoundSession._execute_ai_plan(plan: Array, combatant, action_economy) ->
## Dictionary`: the "Strike" match case now dispatches the EXACT
## reaction-window/two-phase-commit resolution logic that used to live
## directly inside advance_ai_turn()'s own body (cut-pasted verbatim, no
## logic simplification/reordering), and advance_ai_turn() itself is
## refactored into the two-call sequence `_decide_ai_action() ->
## _execute_ai_plan()`.
##
## Verifies (this feature's test_criteria):
##   1. All existing reaction-window/two-phase-commit GUT suites still pass
##      unmodified (exercised by the full project suite, not re-asserted
##      here — this file focuses on the NEW dispatch seam itself).
##   2. A FakePlannerPort-produced [Stride, Strike] plan causes BOTH items
##      to be attempted, in order, within a SINGLE advance_ai_turn() call.
##   3. A Strike item soft-stops the dispatch loop (no exception) once
##      action_economy.can_take_action() is false, leaving every
##      already-applied prior plan item's effects in place.
##   4. any_action_taken/WAIT semantics of advance_ai_turn() are unchanged
##      versus pre-refactor behavior (legacy no-target sentinel -> WAIT;
##      legacy Strike-with-target -> resolved via the SAME verbatim logic,
##      now living inside _execute_ai_plan()).
##   5. core/application/reaction_window.gd and
##      core/controllers/combine_action_controller.gd's execute() signature
##      remain byte-for-byte unmodified (git-diff-free check, mirroring
##      tests/unit/application/test_decide_ai_action_dispatch.gd's
##      established convention).
##
## Mirrors tests/unit/application/test_execute_ai_plan_stride_step.gd's and
## test_decide_ai_action_dispatch.gd's established "build a REAL
## RunRoundUseCase/RoundSession, fake only the outer ports" rig convention.

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")

const REACTION_WINDOW_PATH: String = "res://core/application/reaction_window.gd"
const COMBINE_ACTION_CONTROLLER_PATH: String = "res://core/controllers/combine_action_controller.gd"


# ── Fake/double port implementations (mirrors test_execute_ai_plan_stride_step.gd) ──

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

	var _decision: Dictionary

	func _init(decision: Dictionary = {"action_type": "", "target": null}) -> void:
		_decision = decision

	func decide_action(_combatant, _targets: Array) -> Dictionary:
		return _decision


## FakePlannerPort — a NEW-style AIPlannerPort-shaped duck-typed double
## (mirrors test_decide_ai_action_dispatch.gd's own double), exposing
## plan_turn(combatant, world_context) -> Array.
class FakePlannerPort:
	extends "res://core/application/ai_planner_port.gd"

	var _plan_to_return: Array

	func _init(plan_to_return: Array) -> void:
		_plan_to_return = plan_to_return

	func plan_turn(_combatant, _world_context: Dictionary) -> Array:
		return _plan_to_return


# ── Shared fixture helpers (mirrors test_execute_ai_plan_stride_step.gd) ────

func _combatant_at(p_name: String, p_is_enemy: bool, p_q: int, p_r: int, p_hp: int = 10):
	return CombatantClass.from_dict({
		"name":       p_name,
		"hp_current": p_hp,
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


## A combatant whose weapon/attribute modifiers are large enough that a
## Strike against a p_target_ac-low target hits UNCONDITIONALLY regardless
## of the d20 roll (core/rules/resolution.gd resolve_to_hit(): roll_total =
## d20 (>=1) + attribute_mod + proficiency_bonus; a proficiency_bonus of 50
## dwarfs any target AC used in this suite) -- avoids depending on a
## lucky/pinned RNG seed for the "Strike genuinely resolves" assertions.
func _guaranteed_hit_attacker(p_name: String, p_is_enemy: bool, p_q: int, p_r: int):
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
			"proficiency_bonus": 50,
			"damage_die": 4
		}
	})


func _make_session(party: Array, enemies: Array, ai_decision_port, seed: int):
	var turn_order_port     = FakeTurnOrderPort.new([])
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


func _entry(combatant) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


## Builds a session via an EXPLICIT turn order (mirrors
## tests/integration/test_ai_token_reposition.gd's own `_make_use_case`
## convention) — needed by the advance_ai_turn()-driving tests below, which
## (unlike test_execute_ai_plan_stride_step.gd's direct
## session._execute_ai_plan() calls) genuinely depend on current_actor()
## resolving to the acting Enemy.
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
# 1. "Strike" plan item resolves via the (relocated) verbatim reaction-
#    window/two-phase-commit logic — a real hit deals real damage.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_plan_item_resolves_and_deals_damage_on_a_guaranteed_hit() -> void:
	var enemy  = _guaranteed_hit_attacker("Grunt", true, 0, 0)
	var target = _combatant_at("Target", false, 1, 0)
	var session = _make_session([target], [enemy], FakeAIDecisionPort2Arg.new(), 10)

	var plan: Array = [{"action_type": "Strike", "target": target}]
	var action_economy := ActionEconomyClass.new()
	var budget_before: int = action_economy.get_remaining()
	var hp_before: int = target.hp_current

	var result: Dictionary = await session._execute_ai_plan(plan, enemy, action_economy)

	assert_true(result.get("ok", false), "_execute_ai_plan() must report ok == true")
	assert_true(result.get("any_action_taken", false), "a resolved Strike must set any_action_taken == true")
	assert_eq(action_economy.get_remaining(), budget_before - 1, "a resolved Strike must spend exactly one action")
	assert_lt(target.hp_current, hp_before, "a guaranteed-hit Strike must actually deal damage — proves the real resolution logic ran, not a stub")


# ══════════════════════════════════════════════════════════════════════════
# 2. A "Strike" item with a null target is skipped (malformed-plan
#    convention shared with Stride/Step), never raises.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_plan_item_with_null_target_is_skipped_not_crashed_on() -> void:
	var enemy = _combatant_at("Grunt", true, 0, 0)
	var session = _make_session([], [enemy], FakeAIDecisionPort2Arg.new(), 11)

	var plan: Array = [{"action_type": "Strike", "target": null}]
	var action_economy := ActionEconomyClass.new()
	var budget_before: int = action_economy.get_remaining()

	var result: Dictionary = await session._execute_ai_plan(plan, enemy, action_economy)

	assert_true(result.get("ok", false), "a null-target Strike item must still report ok == true")
	assert_false(result.get("any_action_taken", true), "a null-target Strike item must never set any_action_taken")
	assert_eq(action_economy.get_remaining(), budget_before, "a skipped Strike item must never spend action economy")


# ══════════════════════════════════════════════════════════════════════════
# 3. Soft-stop (US-010 / FR-018): a Strike item breaks the dispatch loop,
#    no exception, when action_economy.can_take_action() is already false
#    — leaving a PRIOR plan item's effects (a successful Stride) applied.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_soft_stops_the_loop_when_action_economy_already_exhausted_leaving_prior_stride_applied() -> void:
	var enemy  = _combatant_at("Grunt", true, 0, 0)
	var target = _combatant_at("Target", false, 5, 0)
	var session = _make_session([target], [enemy], FakeAIDecisionPort2Arg.new(), 12)

	var destination := HexCoordClass.new(1, 0)
	var plan: Array = [
		{"action_type": "Stride", "destination": destination},
		{"action_type": "Strike", "target": target},
	]
	var action_economy := ActionEconomyClass.new()
	var budget_before: int = action_economy.get_remaining()
	var hp_before: int = target.hp_current

	var result: Dictionary = await session._execute_ai_plan(plan, enemy, action_economy)

	assert_true(result.get("ok", false), "a soft-stopped plan must still report ok == true, never an exception/crash")
	assert_true(
		result.get("any_action_taken", false),
		"the Stride's already-applied effect must keep any_action_taken true even though the Strike after it soft-stopped"
	)
	assert_true(enemy.hex_coord.equals(destination), "the Stride's repositioning must remain applied — partial-plan execution is never rolled back")
	assert_eq(
		action_economy.get_remaining(), budget_before - 1,
		"only the Stride's single action must be spent — the Strike must soft-stop BEFORE ever attempting its own spend_action() call"
	)
	assert_eq(target.hp_current, hp_before, "the soft-stopped Strike must never deal damage")


func test_strike_soft_stops_immediately_when_action_economy_is_already_spent_before_the_plan_begins() -> void:
	var enemy  = _guaranteed_hit_attacker("Grunt", true, 0, 0)
	var target = _combatant_at("Target", false, 1, 0)
	var session = _make_session([target], [enemy], FakeAIDecisionPort2Arg.new(), 13)

	var action_economy := ActionEconomyClass.new()
	# Pre-exhaust the one action-per-turn gate BEFORE the plan ever runs —
	# mirrors "the budget was already exhausted before this plan began"
	# (this method's own doc).
	action_economy.spend_action({"name": "SomethingElse", "traits": []})
	var budget_after_pre_spend: int = action_economy.get_remaining()
	var hp_before: int = target.hp_current

	var plan: Array = [{"action_type": "Strike", "target": target}]

	var result: Dictionary = await session._execute_ai_plan(plan, enemy, action_economy)

	assert_true(result.get("ok", false), "an already-exhausted-economy plan must still report ok == true")
	assert_false(result.get("any_action_taken", true), "an already-exhausted-economy Strike must never set any_action_taken")
	assert_eq(action_economy.get_remaining(), budget_after_pre_spend, "a soft-stopped Strike must never spend a second action")
	assert_eq(target.hp_current, hp_before, "a soft-stopped Strike must never deal damage")


# ══════════════════════════════════════════════════════════════════════════
# 4. advance_ai_turn() end-to-end: a FakePlannerPort-produced [Stride,
#    Strike] plan is processed, in order, within ONE advance_ai_turn() call
#    — the Stride genuinely resolves (real Movement.stride() dispatch, per
#    FEAT-010), and the Strike is genuinely ATTEMPTED immediately after it,
#    in the SAME call, soft-stopping gracefully (this ActionEconomy's own
#    one-action-per-turn gate — core/rules/action_economy.gd — makes a
#    Stride+Strike SAME-turn double-resolve structurally impossible; see
#    core/combat/ai.gd's own "Stride now, Strike next turn" contract) rather
#    than requiring a second advance_ai_turn() call or ever raising.
# ══════════════════════════════════════════════════════════════════════════

func test_fake_planner_port_stride_then_strike_both_processed_within_one_advance_ai_turn_call() -> void:
	var goblin = _combatant_at("Goblin", true, 0, 0)
	var titus  = _combatant_at("Titus", false, 5, 0)

	var destination := HexCoordClass.new(1, 0)
	var plan: Array = [
		{"action_type": "Stride", "destination": destination},
		{"action_type": "Strike", "target": titus},
	]
	var ai_planner_port = FakePlannerPort.new(plan)
	var entries: Array = [_entry(goblin), _entry(titus)]
	var session = _make_session_with_entries(entries, [titus], [goblin], ai_planner_port, 14)
	assert_eq(session.current_actor().name, "Goblin", "fixture assumption: the Enemy must act first")

	var reposition_calls: Array = []
	session.set_token_reposition_fn(func(actor_id: String, hex) -> void:
		reposition_calls.append({"actor_id": actor_id, "hex": hex})
	)

	var hp_before: int = titus.hp_current

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false), "advance_ai_turn() must report ok == true")
	assert_true(goblin.hex_coord.equals(destination), "the plan's Stride item must have actually executed within this single advance_ai_turn() call")
	assert_eq(reposition_calls.size(), 1, "the token-reposition seam must have been invoked exactly once, for the Stride")
	assert_eq(titus.hp_current, hp_before, "the plan's Strike item, reached immediately after the Stride in the SAME call, must soft-stop (this ActionEconomy's one-action-per-turn gate) rather than deal damage or raise")


# ══════════════════════════════════════════════════════════════════════════
# 5. any_action_taken/WAIT semantics of advance_ai_turn() are unchanged:
#    the legacy no-target sentinel still resolves as an explicit WAIT, and
#    a legacy Strike-with-target decision still resolves via the (now
#    relocated) verbatim logic — both driven through the real, refactored
#    advance_ai_turn() -> _execute_ai_plan() two-call sequence.
# ══════════════════════════════════════════════════════════════════════════

func test_legacy_no_target_decision_still_resolves_as_wait_through_advance_ai_turn() -> void:
	var enemy = _combatant_at("Idle Enemy", true, 0, 0)
	var ally  = _combatant_at("Ally", false, 10, 10)
	var ai_decision_port = FakeAIDecisionPort2Arg.new({"action_type": "", "target": null})
	var entries: Array = [_entry(enemy), _entry(ally)]
	var session = _make_session_with_entries(entries, [ally], [enemy], ai_decision_port, 15)
	assert_eq(session.current_actor().name, "Idle Enemy", "fixture assumption: the Enemy must act first")

	var entry: Dictionary = session._entries[session._cursor]
	var budget_before: int = entry["action_economy"].get_remaining()

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false), "advance_ai_turn() must report ok == true even for a WAIT")
	assert_eq(
		entry["action_economy"].get_remaining(), budget_before - 1,
		"a legacy no-target decision must still resolve via Actions.resolve_wait(), spending exactly one action (US-001's CWE-835 round-termination guarantee, unchanged by this feature)"
	)


func test_legacy_strike_decision_still_resolves_via_the_relocated_verbatim_logic_through_advance_ai_turn() -> void:
	var enemy  = _guaranteed_hit_attacker("Grunt", true, 0, 0)
	var target = _combatant_at("Target", false, 1, 0)
	var ai_decision_port = FakeAIDecisionPort2Arg.new({"action_type": "Strike", "target": target})
	var entries: Array = [_entry(enemy), _entry(target)]
	var session = _make_session_with_entries(entries, [target], [enemy], ai_decision_port, 16)
	assert_eq(session.current_actor().name, "Grunt", "fixture assumption: the Enemy must act first")

	var hp_before: int = target.hp_current

	var result: Dictionary = await session.advance_ai_turn()

	assert_true(result.get("ok", false), "advance_ai_turn() must report ok == true")
	assert_lt(target.hp_current, hp_before, "a legacy Strike-with-target decision must still deal real damage via the relocated verbatim resolution logic")


# ══════════════════════════════════════════════════════════════════════════
# 6. Frozen files remain byte-for-byte unmodified (diff-free git check) —
#    mirrors test_decide_ai_action_dispatch.gd's established convention.
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
			"%s must remain byte-for-byte unmodified/untouched by FEAT-399 "
			+ "(the Strike branch was cut-pasted verbatim into "
			+ "_execute_ai_plan(), never edited in place). Offending git "
			+ "status output:\n%s"
		) % [relative_path, combined]
	)


func test_reaction_window_is_unmodified_by_feat_399() -> void:
	_assert_file_unmodified(REACTION_WINDOW_PATH)


func test_combine_action_controller_is_unmodified_by_feat_399() -> void:
	_assert_file_unmodified(COMBINE_ACTION_CONTROLLER_PATH)


func test_frozen_files_still_exist_and_are_readable() -> void:
	assert_true(FileAccess.file_exists(REACTION_WINDOW_PATH), "reaction_window.gd must still exist at its frozen path")
	assert_true(FileAccess.file_exists(COMBINE_ACTION_CONTROLLER_PATH), "combine_action_controller.gd must still exist at its frozen path")
