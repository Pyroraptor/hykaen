extends GutTest
## tests/unit/core/combat/test_ai_action_budget.gd
##
## GUT unit test suite for FEAT-006 (US-006 / FR-010, ADR-002): Enemy AI
## respects the SAME per-turn Movement-trait lockout and per-round
## ActionEconomy budget a player-driven Step/Stride/Strike is already gated
## by (core/rules/action_economy.gd) -- decide_action() must never issue a
## second Stride within a turn (no move-then-move) and must never exceed its
## per-turn/per-round action budget, whether driven directly or through
## core/application/round_session.gd's RoundSession.advance_ai_turn()
## orchestration.
##
## This suite deliberately does NOT re-test FEAT-003/FEAT-004/FEAT-005's
## reach/target-selection/Stride-closing/Stride-then-Strike criteria --
## those remain covered by tests/unit/core/combat/test_ai_reach_strike.gd,
## tests/unit/core/combat/test_ai_target_selection.gd, and
## tests/unit/core/combat/test_ai_stride_then_strike.gd.
##
## Verifies (test_criteria):
##   1. Enemy cannot issue two Strides in one turn (no move-then-move).
##   2. Enemy never exceeds its per-turn action budget across multiple
##      simulated turns.
##   3. AI decision executes through the existing AIDecisionPort contract
##      (core/application/round_session.gd's RoundSession.advance_ai_turn())
##      with no new port/use-case class present in core/application/.

const AIClass                      = preload("res://core/combat/ai.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const HexMathClass                 = preload("res://core/geometry/hex_math.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const MovementClass                = preload("res://core/rules/movement.gd")
const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")


# ── Fake/double port implementations (mirrors tests/unit/core/application/test_round_session_ai_turn.gd) ──

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


class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(_dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


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


func _entry(combatant: Dictionary) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


## Builds a fully-wired, REAL RunRoundUseCase plus its fake ports, exactly
## mirroring test_round_session_ai_turn.gd's rig, so this suite exercises
## RoundSession.advance_ai_turn() through the REAL AIDecisionPort
## (core/combat/ai.gd), never a stand-in for RoundSession itself.
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

	return {"use_case": run_round_use_case, "history": round_history_port}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: Enemy cannot issue two Strides in one turn (no move-then-move).
# ══════════════════════════════════════════════════════════════════════════

func test_ai_never_issues_a_second_stride_within_the_same_turn() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
	# Far enough that a single Speed-4 Stride cannot close it into reach --
	# mirrors tests/unit/core/combat/test_ai_stride_then_strike.gd's own
	# "does not close into reach" guard fixture.
	var target: Dictionary = _target("Titus", HexCoordClass.new(9, 0))
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var first_result: Dictionary = ai.decide_action(combatant, [target], action_economy, [])
	assert_eq(first_result.get("action_type", ""), "Stride", "fixture assumption: the first decision this turn must Stride")
	var position_after_first_stride = combatant["hex_coord"]
	var remaining_after_first_stride: int = action_economy.get_remaining()
	assert_false(action_economy.can_take_movement_action(), "fixture assumption: the Movement gate must now be tripped")

	# A SECOND decision cycle in the SAME turn (no start_of_turn() reset in
	# between) must NOT issue another Stride -- the enemy is still out of
	# reach, but Movement is locked out for the rest of this turn.
	var second_result: Dictionary = ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(
		second_result.get("action_type", ""), "",
		"a second decision cycle in the same turn must never issue a second Stride (no move-then-move)"
	)
	assert_null(second_result.get("destination", "MISSING"))
	assert_false(second_result.get("will_strike", true))
	assert_true(
		combatant["hex_coord"].equals(position_after_first_stride),
		"the combatant must not be repositioned a second time within the same turn"
	)
	assert_eq(
		action_economy.get_remaining(), remaining_after_first_stride,
		"a blocked second Stride attempt must not spend a further action"
	)


func test_ai_does_not_stride_when_a_step_already_used_the_movement_gate_this_turn() -> void:
	# The Movement-trait gate is shared across Step and Stride (FEAT-001) --
	# an enemy that has already Stepped this turn (e.g. via some other
	# domain path sharing the SAME ActionEconomy) must not then Stride
	# either, even though its action budget is untouched.
	var ai = AIClass.new()
	var combatant: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
	var target: Dictionary = _target("Titus", HexCoordClass.new(9, 0))
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var step_result: Dictionary = MovementClass.step(combatant, HexCoordClass.new(0, 1), [target], action_economy)
	assert_true(step_result.get("ok", false), "fixture assumption: the Step itself must succeed")
	assert_false(action_economy.can_take_movement_action())
	var budget_before_decision: int = action_economy.get_remaining()

	var result: Dictionary = ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "", "the AI must not Stride once Movement is already locked out this turn, regardless of remaining budget")
	assert_eq(action_economy.get_remaining(), budget_before_decision, "no action may be spent on a blocked Stride attempt")
	assert_true(combatant["hex_coord"].equals(HexCoordClass.new(0, 1)), "the combatant must remain at its post-Step position")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: Enemy never exceeds its per-turn action budget across
# multiple simulated turns.
# ══════════════════════════════════════════════════════════════════════════

func test_ai_never_exceeds_its_action_budget_across_multiple_simulated_turns() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
	# A target far enough away that it can never be closed into reach no
	# matter how many Strides accumulate -- every simulated turn attempts
	# (and, while budget/gate allow, succeeds at) exactly one Stride.
	var target: Dictionary = _target("Titus", HexCoordClass.new(100, 0))
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_round()

	var strides_taken: int = 0
	for turn_index in range(ActionEconomyClass.MAX_BUDGET + 5):
		action_economy.start_of_turn()
		var result: Dictionary = ai.decide_action(combatant, [target], action_economy, [])

		assert_true(
			action_economy.get_remaining() >= 0,
			"the per-round action budget must never go negative (simulated turn %d)" % turn_index
		)
		assert_true(
			action_economy.get_remaining() <= ActionEconomyClass.MAX_BUDGET,
			"the per-round action budget must never exceed its maximum (simulated turn %d)" % turn_index
		)

		if result.get("action_type", "") == "Stride":
			strides_taken += 1
			assert_true(
				strides_taken <= ActionEconomyClass.MAX_BUDGET,
				"the AI must never spend more Strides than the per-round budget allows (simulated turn %d)" % turn_index
			)
		else:
			# Once the round budget is exhausted, every further decision must
			# be a clean no-op -- never an over-budget spend attempt.
			assert_true(
				action_economy.is_spent(),
				"a decision cycle that issues no Stride once movement is otherwise legal must mean the budget is exhausted (simulated turn %d)" % turn_index
			)

	assert_eq(strides_taken, ActionEconomyClass.MAX_BUDGET, "exactly one Stride per turn must be taken until the per-round budget (7) is exhausted, never more")
	assert_true(action_economy.is_spent(), "the round budget must be fully (and only fully) exhausted after MAX_BUDGET Strides")
	assert_eq(action_economy.get_remaining(), 0)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: AI decision executes through the existing AIDecisionPort /
# ResolveActionUseCase / RoundSession.advance_ai_turn() orchestration, with
# no new port or use-case class introduced in core/application/.
# ══════════════════════════════════════════════════════════════════════════

func test_round_session_advance_ai_turn_executes_stride_but_defers_strike_to_next_turn() -> void:
	var goblin: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
	goblin["_is_enemy"] = true
	var titus: Dictionary  = _target("Titus", HexCoordClass.new(4, 0), 200)
	titus["_is_enemy"] = false
	var entries: Array = [_entry(goblin), _entry(titus)]

	# raw=12 -> roll_total = 12 + strength(2) + proficiency(1) = 15 vs ac=14 -> hit,
	# not a crit (15-14=1 < 10); damage roll raw=4 -> 4 + 2 = 6 damage.
	var random_number_port = ScriptedRandomNumberPort.new([12, 4])
	var rig: Dictionary = _make_use_case(entries, random_number_port)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])

	assert_eq(session.current_actor().get("name", ""), "Skeleton", "the enemy must be the current actor")
	var goblin_action_economy = entries[0]["action_economy"]
	var budget_before: int = goblin_action_economy.get_remaining()

	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false))
	assert_true(
		HexMathClass.hex_distance(goblin["hex_coord"], titus["hex_coord"]) <= 1,
		"the enemy must have Strode into melee reach of the target this turn"
	)
	# FEAT-003 (ADR-103): the per-turn one-action gate means the Stride
	# already spent this turn's ONE action -- core/combat/ai.gd still reports
	# a composite will_strike:true decision (it has no visibility into the
	# new _action_used gate), but resolve_action_use_case.resolve()'s own
	# spend_action() call is rejected with ACTION_ALREADY_USED, so no Strike
	# resolves (no history entry, no damage) in the SAME turn as the Stride.
	assert_eq(
		rig["history"].entries.size(), 0,
		"no Strike may resolve in the same turn as the Stride -- only one action is permitted per turn (FEAT-003); the Stride half is executed directly by core/combat/ai.gd and records no history entry of its own"
	)
	assert_eq(
		goblin_action_economy.get_remaining(), budget_before - 1,
		"exactly one action must be spent this turn -- the Stride (core/rules/movement.gd); the Strike attempt must not decrement the budget further"
	)
	assert_eq(titus.get("hp_current", 0), 200, "the target must be undamaged -- the Strike attempt must not resolve in the same turn as the Stride")
	assert_eq(session.current_actor().get("name", ""), "Titus", "advance_ai_turn() must still advance the cursor after the composite decision")


func test_application_layer_contains_no_new_port_or_use_case_class() -> void:
	# ADR-002 enforcement (mirrors this project's CI static-check gate):
	# FEAT-006 wires the extended AI decision through the EXISTING
	# AIDecisionPort/ResolveActionUseCase/RoundSession orchestration only --
	# no new port or use-case file may appear in core/application/.
	var expected_files: Array = [
		"ai_decision_port.gd",
		"determine_outcome_use_case.gd",
		"event_sink_port.gd",
		"resolve_action_use_case.gd",
		"round_history_port.gd",
		"round_session.gd",
		"run_round_use_case.gd",
		"turn_order_port.gd",
	]

	var dir := DirAccess.open("res://core/application")
	assert_not_null(dir, "fixture assumption: core/application/ must exist")

	# Only .gd class files are in scope for this ADR-002 port/use-case check --
	# unrelated non-GDScript tooling artifacts (e.g. __pycache__/, *.py) are
	# not application-layer classes and are ignored here.
	var actual_files: Array = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".gd"):
			actual_files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	actual_files.sort()

	assert_eq(
		actual_files, expected_files,
		"core/application/ must contain no new port/use-case class beyond the pre-existing set (ADR-002)"
	)


func test_ai_decision_port_contract_is_unchanged_two_argument_shape() -> void:
	# The abstract base contract (core/application/ai_decision_port.gd) must
	# still declare exactly the pre-existing (combatant, targets) signature --
	# core/combat/ai.gd's FEAT-004/005 extra parameters are OPTIONAL additions
	# on the concrete adapter, never a change to the port's own contract.
	var port := AIDecisionPortStub.new()
	var callable := Callable(port, "decide_action")
	assert_eq(callable.get_argument_count(), 2, "AIDecisionPort.decide_action()'s declared contract must remain exactly 2 arguments")


class AIDecisionPortStub:
	extends "res://core/application/ai_decision_port.gd"
