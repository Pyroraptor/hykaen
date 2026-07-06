extends GutTest
## tests/unit/core/rules/test_movement_lockout.gd
##
## GUT test suite for FEAT-001 (US-001 / FR-001 / FR-002 / FR-005 / FR-006 /
## ADR-003): Movement-trait lockout via the EXISTING ActionEconomy gate.
##
## core/rules/movement.gd's Movement.step() now optionally accepts the
## mover's core/rules/action_economy.gd ActionEconomy instance and, when
## supplied, trips the SAME per-turn _movement_used gate Movement.stride()
## already trips (via action_economy.mark_movement_used()) -- WITHOUT
## decrementing actions_remaining/budget_remaining. Stride already spends
## through this gate via spend_action({"traits": ["Movement"]}); this suite
## proves Step and Stride are now mutually exclusive within the same turn,
## that the lockout clears via the EXISTING start_of_turn() reset (no new
## flag/state machine), and that Strike availability is a completely
## separate concern unaffected by _movement_used.
##
## Verifies (test_criteria):
##   1. Step blocks Stride in the same turn and leaves actions_remaining
##      unchanged.
##   2. Stride blocks Step in the same turn.
##   3. Lockout (_movement_used) resets correctly at the start of the actor's
##      next turn via the existing reset_for_new_turn() mechanism
##      (start_of_turn()).
##   4. Regression: Strike availability is unaffected by _movement_used
##      state.

const MovementClass       = preload("res://core/rules/movement.gd")
const CombatantClass      = preload("res://core/domain/combatant.gd")
const HexCoordClass       = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass  = preload("res://core/rules/action_economy.gd")
const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")


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


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: Step blocks Stride in the same turn and leaves
# actions_remaining unchanged.
# ══════════════════════════════════════════════════════════════════════════

func test_step_trips_the_movement_gate_leaving_budget_unchanged() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	var budget_before: int = ae.get_remaining()

	assert_true(ae.can_take_movement_action(), "fixture assumption: movement must be available before any Movement-trait action")

	var step_result: Dictionary = MovementClass.step(mover, HexCoordClass.new(1, 0), [], ae)

	assert_true(step_result.get("ok", false), "Step to an adjacent, unoccupied hex must still succeed")
	assert_eq(ae.get_remaining(), budget_before, "Step must NEVER decrement actions_remaining -- it is a free action")
	assert_false(ae.is_spent(), "Step must never mark the combatant Spent")
	assert_false(ae.can_take_movement_action(), "Step must trip the SAME Movement gate Stride trips")


func test_step_blocks_a_subsequent_stride_the_same_turn() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	var budget_before: int = ae.get_remaining()

	var step_result: Dictionary = MovementClass.step(mover, HexCoordClass.new(1, 0), [], ae)
	assert_true(step_result.get("ok", false), "fixture assumption: the Step itself must succeed")

	var stride_result: Dictionary = MovementClass.stride(mover, HexCoordClass.new(3, 0), ae, [])

	assert_false(stride_result.get("ok", true), "a Stride after a Step in the same turn must be rejected")
	assert_eq(stride_result.get("error", ""), MovementClass.ERR_ACTION_UNAVAILABLE)
	assert_eq(stride_result.get("reason", ""), "MOVEMENT_ALREADY_USED")
	assert_eq(ae.get_remaining(), budget_before, "a rejected Stride must not spend an action, and the earlier Step never did either")
	assert_true(mover.hex_coord.equals(HexCoordClass.new(1, 0)), "a rejected Stride must not move the combatant past its post-Step position")


func test_dictionary_shaped_combatant_step_also_trips_the_gate() -> void:
	# The interactive combat pipeline represents combatants as Dictionaries
	# carrying a "hex_coord" key -- the lockout must hold for that shape too.
	var mover: Dictionary = {"name": "Titus", "hex_coord": HexCoordClass.new(0, 0)}
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	var step_result: Dictionary = MovementClass.step(mover, HexCoordClass.new(0, 1), [], ae)
	assert_true(step_result.get("ok", false))

	var stride_result: Dictionary = MovementClass.stride(mover, HexCoordClass.new(0, 3), ae, [])
	assert_false(stride_result.get("ok", true), "Step must lock out Stride for a Dictionary-shaped combatant too")
	assert_eq(stride_result.get("reason", ""), "MOVEMENT_ALREADY_USED")


func test_step_without_an_action_economy_argument_does_not_touch_any_gate() -> void:
	# Backward compatibility (ADR-002 -- no forked/duplicate movement path):
	# omitting action_economy entirely must reproduce the EXACT pre-FEAT-001
	# behavior -- Step remains structurally incapable of touching any
	# ActionEconomy when the caller doesn't supply one.
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	var result: Dictionary = MovementClass.step(mover, HexCoordClass.new(1, 0), [])

	assert_true(result.get("ok", false))
	assert_true(ae.can_take_movement_action(), "an ActionEconomy never passed to step() must be completely untouched")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: Stride blocks Step in the same turn.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_blocks_a_subsequent_step_the_same_turn() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	var budget_before: int = ae.get_remaining()

	var stride_result: Dictionary = MovementClass.stride(mover, HexCoordClass.new(3, 0), ae, [])
	assert_true(stride_result.get("ok", false), "fixture assumption: the Stride itself must succeed")
	assert_eq(ae.get_remaining(), budget_before - 1, "Stride must still spend exactly one action")

	var step_result: Dictionary = MovementClass.step(mover, HexCoordClass.new(4, 0), [], ae)

	assert_false(step_result.get("ok", true), "a Step after a Stride in the same turn must be rejected")
	assert_eq(step_result.get("error", ""), MovementClass.ERR_MOVEMENT_LOCKED)
	assert_eq(ae.get_remaining(), budget_before - 1, "a rejected Step must not spend a further action")
	assert_true(mover.hex_coord.equals(HexCoordClass.new(3, 0)), "a rejected Step must not move the combatant past its post-Stride position")


func test_stride_without_action_economy_leaves_step_unaffected_since_no_gate_is_shared() -> void:
	# Sanity/negative check: the lockout is a property of a SHARED
	# ActionEconomy instance, not of the destination/positions -- a Step call
	# that is never handed an action_economy at all is never gated, even if
	# a Stride happened moments earlier on the SAME actor with the SAME
	# ActionEconomy elsewhere in the call graph.
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	MovementClass.stride(mover, HexCoordClass.new(3, 0), ae, [])
	assert_false(ae.can_take_movement_action(), "fixture assumption: Stride must have tripped the gate on ae")

	var step_result: Dictionary = MovementClass.step(mover, HexCoordClass.new(4, 0), [])

	assert_true(step_result.get("ok", false), "a Step call that omits action_economy is never gated by any ActionEconomy's state")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: Lockout resets correctly at the start of the actor's next
# turn via the existing reset_for_new_turn() mechanism (start_of_turn()).
# ══════════════════════════════════════════════════════════════════════════

func test_lockout_clears_via_existing_start_of_turn_reset() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	var step_result: Dictionary = MovementClass.step(mover, HexCoordClass.new(1, 0), [], ae)
	assert_true(step_result.get("ok", false))
	assert_false(ae.can_take_movement_action(), "fixture assumption: the gate must be tripped after the Step")

	var blocked_stride: Dictionary = MovementClass.stride(mover, HexCoordClass.new(1, 1), ae, [])
	assert_false(blocked_stride.get("ok", true), "fixture assumption: Stride must still be locked out this turn")

	# The actor's NEXT turn begins -- the existing start_of_turn() call
	# (core/rules/action_economy.gd) is the sole mechanism that clears
	# _movement_used; no new flag/state machine is introduced for this.
	ae.start_of_turn()

	assert_true(ae.can_take_movement_action(), "start_of_turn() must clear the lockout for the new turn")

	var stride_after_reset: Dictionary = MovementClass.stride(mover, HexCoordClass.new(1, 1), ae, [])
	assert_true(stride_after_reset.get("ok", false), "Stride must succeed again once the new turn's start_of_turn() has cleared the gate")

	var second_step_after_reset: Dictionary = MovementClass.step(mover, HexCoordClass.new(2, 1), [], ae)
	assert_false(second_step_after_reset.get("ok", true), "the Stride just taken THIS new turn must immediately re-lock Step again")
	assert_eq(second_step_after_reset.get("error", ""), MovementClass.ERR_MOVEMENT_LOCKED)


func test_lockout_persists_across_repeated_start_of_turn_calls_within_the_same_turn_only_clears_the_flag_itself() -> void:
	# start_of_turn() clearing the gate is idempotent/safe to call repeatedly
	# (mirrors action_economy.gd's own AC-4 interleaving contract) -- calling
	# it again after it already cleared the gate must not somehow re-lock it.
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	MovementClass.step(mover, HexCoordClass.new(1, 0), [], ae)
	assert_false(ae.can_take_movement_action())

	ae.start_of_turn()
	ae.start_of_turn()

	assert_true(ae.can_take_movement_action(), "repeated start_of_turn() calls must not re-lock the Movement gate")


func test_lockout_does_not_reset_at_round_boundary_start_of_round_only_since_that_also_clears_it() -> void:
	# start_of_round()/end_of_round() ALSO clear per-turn flags as part of the
	# full round-boundary reset (core/rules/action_economy.gd) -- confirming
	# the SAME existing mechanism, not a parallel one, governs this lockout.
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	MovementClass.step(mover, HexCoordClass.new(1, 0), [], ae)
	assert_false(ae.can_take_movement_action())

	ae.start_of_round()

	assert_true(ae.can_take_movement_action(), "start_of_round() must also clear the Movement gate (existing round-boundary reset)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: Regression -- Strike availability is unaffected by
# _movement_used state.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_still_resolves_normally_while_movement_gate_is_locked() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	var rng := ScriptedRandomNumberPort.new([12, 4])
	var event_sink := FakeEventSinkPort.new()
	var history := FakeRoundHistoryPort.new()
	var use_case := ResolveActionUseCaseClass.new(rng, event_sink, history)

	var attacker: Dictionary = {
		"name": "Attacker", "strength": 3, "hex_coord": HexCoordClass.new(0, 0),
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 2, "damage_die": 6}
	}
	var target: Dictionary = {"name": "Target", "hp_current": 50, "ac": 10, "hex_coord": HexCoordClass.new(1, 0)}

	# Trip the Movement gate first (a Step that carries the action_economy).
	var step_result: Dictionary = MovementClass.step(attacker, HexCoordClass.new(0, 1), [target], ae)
	assert_true(step_result.get("ok", false), "fixture assumption: the Step must succeed")
	assert_false(ae.can_take_movement_action(), "fixture assumption: the Movement gate must now be locked")

	# hex_distance((0,1), (1,0)) == 1 -- still adjacent, so Strike must
	# resolve completely independently of the Movement lockout.
	var strike_result: Dictionary = use_case.resolve(attacker, ae, target, "Strike", 1, 0)

	assert_true(strike_result.get("ok", false), "Strike must be completely unaffected by _movement_used -- Movement and Strike are separate traits")
	assert_true(strike_result.get("resolved", false))


func test_can_take_movement_action_does_not_gate_spend_action_without_movement_trait() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.mark_movement_used()

	var non_movement_result: Dictionary = ae.spend_action({"name": "Strike", "traits": ["Strike"]})

	assert_true(non_movement_result.get("success", false), "a non-Movement-trait action must succeed regardless of the Movement gate's state")
	assert_false(ae.is_spent())
