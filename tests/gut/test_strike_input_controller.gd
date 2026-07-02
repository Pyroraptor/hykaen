extends GutTest
## tests/gut/test_strike_input_controller.gd — FEAT-007 (US-007)
##
## GUT test suite for scenes/battlefield/StrikeInputController.gd: lets the
## active combatant select Strike as their one action and pick an in-range
## target, gated by the SAME domain reach rule the Application layer uses
## (core/geometry/hex_math.gd HexMath.hex_neighbors(), mirrored here for UX
## only, ADR-001), forwarding the selection to the injected, REUSED
## resolve_action_use_case (core/application/resolve_action_use_case.gd,
## ADR-002/ADR-003 -- no forked action path).
##
## Verifies (test_criteria):
##   1. Selecting Strike + an in-range target invokes
##      resolve_action_use_case.resolve() with a correctly populated call
##      (actor/action_economy/target/action_name/round_number/cycle_index/
##      active_combatant_id).
##   2. Out-of-range targets are never selectable -- neither offered by
##      get_selectable_target_ids()/is_target_selectable(), nor accepted by
##      select_target() even when called directly with that target's id --
##      and are visibly marked not-selectable on a collaborating
##      HexBattlefield (scenes/battlefield/HexBattlefield.gd, FEAT-005).
##   3. ACTOR_NOT_ACTIVE (ERR_NOT_ACTIVE_COMBATANT) / ACTION_BUDGET_EXHAUSTED
##      (ERR_NO_ACTION_REMAINING) / TARGET_OUT_OF_REACH
##      (ERR_TARGET_NOT_ADJACENT) error responses surface as a non-blocking
##      inline message and leave the controller/turn usable for another
##      attempt (no crash, no lock-up, no budget spent).
##   4. Code-review guardrail (source-inspection, mirrors
##      tests/gut/test_hex_battlefield.gd's equivalent): StrikeInputController.gd
##      contains no hit/damage computation of its own.

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const HexMathClass  = preload("res://core/geometry/hex_math.gd")
const StrikeInputControllerClass = preload("res://scenes/battlefield/StrikeInputController.gd")
const HexBattlefieldScene: PackedScene = preload("res://scenes/battlefield/HexBattlefield.tscn")
const ResourceEncounterRepositoryClass = preload("res://infrastructure/resource_encounter_repository.gd")

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")

const STRIKE_INPUT_CONTROLLER_SOURCE_PATH: String = "res://scenes/battlefield/StrikeInputController.gd"
const PROLOGUE_ENCOUNTER_PATH: String = "res://data/encounters/prologue_encounter.tres"


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


class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


## ScriptedResolveActionUseCase — a spy/stub standing in for
## resolve_action_use_case: records every call's full argument list and
## returns the next queued canned result Dictionary. Extends
## tests/unit/presentation/test_strike_action_control.gd's SpyResolveActionUseCase
## pattern with a result queue, so error-path scenarios (Criterion 3) can be
## exercised directly without needing to reverse-engineer which exact domain
## precondition ordering would produce a given error code.
class ScriptedResolveActionUseCase:
	var call_count: int = 0
	var last_args: Array = []
	var _results: Array

	func _init(results: Array = [{"ok": true, "resolved": true}]) -> void:
		_results = results

	func resolve(
		combatant, action_economy, target, action_name: String,
		round_number: int, cycle_index: int, active_combatant_id: String = ""
	) -> Dictionary:
		call_count += 1
		last_args = [combatant, action_economy, target, action_name, round_number, cycle_index, active_combatant_id]
		var index: int = mini(call_count - 1, _results.size() - 1)
		return _results[index]


var _controller = null


func before_each() -> void:
	_controller = StrikeInputControllerClass.new()


# ── Shared fixtures ──────────────────────────────────────────────────────────

func _actor(hex_coord, combatant_id: String = "titus") -> Dictionary:
	return {
		"combatant_id": combatant_id,
		"name": "Titus",
		"strength": 3,
		"hex_coord": hex_coord,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6,
		},
	}


func _enemy(name: String, hex_coord, hp: int = 20, ac: int = 10) -> Dictionary:
	return {"combatant_id": name.to_lower(), "name": name, "hp_current": hp, "ac": ac, "hex_coord": hex_coord}


func _real_use_case(scripted_values: Array) -> Dictionary:
	var rng_port   = ScriptedRandomNumberPort.new(scripted_values)
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "event_sink": event_sink, "history": history}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: selecting Strike + an in-range target invokes
# resolve_action_use_case with a correctly populated call.
# ══════════════════════════════════════════════════════════════════════════

func test_select_in_range_target_invokes_resolve_action_use_case_with_populated_request() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()

	var spy := ScriptedResolveActionUseCase.new()
	var actor: Dictionary = _actor(origin)
	_controller.configure(actor, action_economy, spy, [adjacent_enemy], "titus", 3, 1)

	var result: Dictionary = _controller.select_target("skeleton")

	assert_true(result.get("ok", false))
	assert_eq(spy.call_count, 1, "resolve_action_use_case must be invoked exactly once")
	assert_eq(spy.last_args[0], actor, "actor must be forwarded verbatim")
	assert_eq(spy.last_args[1], action_economy, "the actor's ActionEconomy must be forwarded")
	assert_eq(spy.last_args[2], adjacent_enemy, "the selected target must be forwarded")
	assert_eq(spy.last_args[3], "Strike", "action_name must be Strike")
	assert_eq(spy.last_args[4], 3, "round_number must be forwarded")
	assert_eq(spy.last_args[5], 1, "cycle_index must be forwarded")
	assert_eq(spy.last_args[6], "titus", "active_combatant_id must be forwarded so the domain can enforce turn order")


func test_select_in_range_target_resolves_against_the_real_use_case_and_spends_the_budget() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var budget_before: int = action_economy.get_remaining()

	# raw=12 -> roll_total = 12 + strength(3) + proficiency(2) = 17 vs ac=10 -> hit.
	var rig: Dictionary = _real_use_case([12, 4])
	_controller.configure(_actor(origin), action_economy, rig["use_case"], [adjacent_enemy], "titus")

	var result: Dictionary = _controller.select_target("skeleton")

	assert_true(result.get("ok", false), "selecting a valid in-range target must resolve successfully")
	assert_eq(rig["event_sink"].events.size(), 1, "exactly one AttackEvent must be emitted")
	assert_eq(
		action_economy.get_remaining(), budget_before - 1,
		"the active combatant's action budget must be decremented by exactly one Strike"
	)


func test_select_target_emits_strike_resolved_signal() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()

	var rig: Dictionary = _real_use_case([12, 4])
	_controller.configure(_actor(origin), action_economy, rig["use_case"], [adjacent_enemy], "titus")

	watch_signals(_controller)
	_controller.select_target("skeleton")

	assert_signal_emitted(_controller, "strike_resolved")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: out-of-range targets are never selectable in the UI.
# ══════════════════════════════════════════════════════════════════════════

func test_out_of_range_target_is_excluded_from_selectable_ids() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))
	var far_enemy: Dictionary = _enemy("Goblin", HexCoordClass.new(3, 0))

	var spy := ScriptedResolveActionUseCase.new()
	_controller.configure(_actor(origin), ActionEconomyClass.new(), spy, [adjacent_enemy, far_enemy])

	assert_eq(_controller.get_selectable_target_ids(), ["skeleton"])
	assert_true(_controller.is_target_selectable("skeleton"))
	assert_false(_controller.is_target_selectable("goblin"), "a non-adjacent enemy must not be selectable")


func test_all_six_neighbors_are_selectable_when_occupied() -> void:
	var origin := HexCoordClass.new(0, 0)
	var neighbor_coords: Array = HexMathClass.hex_neighbors(origin)

	var enemies: Array = []
	var expected_ids: Array = []
	for i in range(neighbor_coords.size()):
		var enemy_name: String = "Enemy%d" % i
		enemies.append(_enemy(enemy_name, neighbor_coords[i]))
		expected_ids.append(enemy_name.to_lower())

	var spy := ScriptedResolveActionUseCase.new()
	_controller.configure(_actor(origin), ActionEconomyClass.new(), spy, enemies)

	var actual_ids: Array = _controller.get_selectable_target_ids()
	assert_eq(actual_ids.size(), 6, "all 6 neighbors must be selectable when all are occupied by enemies")
	for expected_id in expected_ids:
		assert_true(actual_ids.has(expected_id), "expected neighbor target '%s' to be selectable" % expected_id)


func test_selecting_an_out_of_range_target_id_is_rejected_with_no_use_case_call() -> void:
	var origin := HexCoordClass.new(0, 0)
	var far_enemy: Dictionary = _enemy("Goblin", HexCoordClass.new(3, 0))
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var budget_before: int = action_economy.get_remaining()

	var spy := ScriptedResolveActionUseCase.new()
	_controller.configure(_actor(origin), action_economy, spy, [far_enemy])

	var result: Dictionary = _controller.select_target("goblin")

	assert_false(result.get("ok", true), "selecting an out-of-range target id must be rejected")
	assert_eq(result.get("error", ""), "ERR_TARGET_NOT_SELECTABLE")
	assert_eq(spy.call_count, 0, "resolve_action_use_case must never be invoked for an out-of-range target")
	assert_eq(
		action_economy.get_remaining(), budget_before,
		"the actor's action budget must remain unspent when the target is rejected at the UI layer"
	)


func test_selecting_unknown_target_id_is_rejected() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var spy := ScriptedResolveActionUseCase.new()
	_controller.configure(_actor(origin), ActionEconomyClass.new(), spy, [adjacent_enemy])

	var result: Dictionary = _controller.select_target("does_not_exist")

	assert_false(result.get("ok", true))
	assert_eq(spy.call_count, 0)


func test_out_of_range_target_is_marked_not_selectable_on_the_hex_battlefield() -> void:
	var repo = ResourceEncounterRepositoryClass.new()
	var combatants: Array = repo.load_combatants(PROLOGUE_ENCOUNTER_PATH)
	assert_true(combatants.size() >= 2, "prologue_encounter.tres must yield at least an actor and one enemy")

	var battlefield = HexBattlefieldScene.instantiate()
	add_child_autofree(battlefield)
	battlefield.load_combatants(combatants)

	var actor_combatant = combatants[0]
	var target_combatant = combatants[combatants.size() - 1]

	var actor_dict: Dictionary = {
		"combatant_id": actor_combatant.combatant_id, "name": actor_combatant.name, "strength": 3,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 2, "damage_die": 6},
	}
	var target_dict: Dictionary = {
		"combatant_id": target_combatant.combatant_id, "name": target_combatant.name, "hp_current": 20, "ac": 10,
	}

	var spy := ScriptedResolveActionUseCase.new()
	_controller.configure(actor_dict, ActionEconomyClass.new(), spy, [target_dict], "", 1, 0, battlefield)

	var is_neighbor: bool = false
	for neighbor in HexMathClass.hex_neighbors(actor_combatant.hex_coord):
		if neighbor.equals(target_combatant.hex_coord):
			is_neighbor = true
			break

	assert_eq(
		_controller.is_target_selectable(target_combatant.combatant_id), is_neighbor,
		"controller selectability must match real hex-neighbor adjacency for the loaded encounter"
	)
	assert_eq(
		battlefield.is_selectable(target_combatant.combatant_id), is_neighbor,
		"the HexBattlefield must be told the same selectability the controller computed"
	)
	if not is_neighbor:
		assert_true(
			battlefield.is_marked_not_selectable(target_combatant.combatant_id),
			"an out-of-range target must be visibly marked not-selectable on the battlefield"
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: ACTOR_NOT_ACTIVE / ACTION_BUDGET_EXHAUSTED / TARGET_OUT_OF_REACH
# error responses surface as a non-blocking inline message and leave the
# controller/turn usable for another attempt.
# ══════════════════════════════════════════════════════════════════════════

func test_actor_not_active_error_surfaces_as_inline_message_and_leaves_controller_usable() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))
	var spy := ScriptedResolveActionUseCase.new([{"ok": false, "resolved": false, "error": "ERR_NOT_ACTIVE_COMBATANT"}])
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()

	_controller.configure(_actor(origin), action_economy, spy, [adjacent_enemy], "someone_else")

	watch_signals(_controller)
	var result: Dictionary = _controller.select_target("skeleton")

	assert_false(result.get("ok", true))
	assert_eq(result.get("error", ""), "ERR_NOT_ACTIVE_COMBATANT")
	assert_true(_controller.has_error())
	assert_string_contains(_controller.get_last_error_message().to_lower(), "turn")
	assert_signal_emitted(_controller, "action_error")
	assert_eq(
		action_economy.get_remaining(), ActionEconomyClass.MAX_BUDGET,
		"a rejected out-of-turn action must not spend the actor's budget"
	)

	# The turn/controller stays usable -- the same target is still offered.
	assert_true(_controller.is_target_selectable("skeleton"), "the controller must remain usable for another attempt")


func test_action_budget_exhausted_error_surfaces_as_inline_message() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))
	var spy := ScriptedResolveActionUseCase.new([{"ok": false, "resolved": false, "error": "ERR_NO_ACTION_REMAINING"}])

	_controller.configure(_actor(origin), ActionEconomyClass.new(), spy, [adjacent_enemy], "titus")

	watch_signals(_controller)
	var result: Dictionary = _controller.select_target("skeleton")

	assert_false(result.get("ok", true))
	assert_eq(result.get("error", ""), "ERR_NO_ACTION_REMAINING")
	assert_true(_controller.has_error())
	assert_string_contains(_controller.get_last_error_message().to_lower(), "action")
	assert_signal_emitted(_controller, "action_error")
	assert_true(_controller.is_target_selectable("skeleton"), "the controller must remain usable for another attempt")


func test_target_out_of_reach_error_surfaces_as_inline_message() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))
	var spy := ScriptedResolveActionUseCase.new([{"ok": false, "resolved": false, "error": "ERR_TARGET_NOT_ADJACENT"}])

	_controller.configure(_actor(origin), ActionEconomyClass.new(), spy, [adjacent_enemy], "titus")

	watch_signals(_controller)
	var result: Dictionary = _controller.select_target("skeleton")

	assert_false(result.get("ok", true))
	assert_eq(result.get("error", ""), "ERR_TARGET_NOT_ADJACENT")
	assert_true(_controller.has_error())
	assert_string_contains(_controller.get_last_error_message().to_lower(), "range")
	assert_signal_emitted(_controller, "action_error")
	assert_true(_controller.is_target_selectable("skeleton"), "the controller must remain usable for another attempt")


func test_a_subsequent_successful_selection_clears_the_prior_inline_error() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))
	var spy := ScriptedResolveActionUseCase.new([
		{"ok": false, "resolved": false, "error": "ERR_NO_ACTION_REMAINING"},
		{"ok": true, "resolved": true},
	])

	_controller.configure(_actor(origin), ActionEconomyClass.new(), spy, [adjacent_enemy], "titus")
	_controller.select_target("skeleton")
	assert_true(_controller.has_error(), "the first, rejected selection must record an inline error")

	var second_result: Dictionary = _controller.select_target("skeleton")

	assert_true(second_result.get("ok", false), "a subsequent selection must still be possible -- the turn was left active")
	assert_false(_controller.has_error(), "a subsequent successful selection must clear the prior inline error")
	assert_eq(_controller.get_last_error_message(), "")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (code-review guardrail): no hit/damage computation of its own.
# ══════════════════════════════════════════════════════════════════════════

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_contains_no_hit_or_damage_computation_keywords() -> void:
	var source: String = _read_source(STRIKE_INPUT_CONTROLLER_SOURCE_PATH).to_lower()
	var forbidden_keywords: Array = [
		"roll_attack", "damage_die", "compute_ac", "compute_hp", "hit_chance", "randi(", "randf(",
	]
	for keyword in forbidden_keywords:
		assert_eq(
			source.find(keyword), -1,
			"scenes/battlefield/StrikeInputController.gd must contain no hit/damage computation ('%s' found) -- it only delegates to the domain" % keyword
		)


func test_source_never_calls_a_round_advancing_use_case() -> void:
	var source: String = _read_source(STRIKE_INPUT_CONTROLLER_SOURCE_PATH)
	assert_eq(
		source.findn("run_round_use_case"), -1,
		"StrikeInputController.gd must never call a round-advancing use case -- a rejected action must leave the turn active"
	)
