extends GutTest
## tests/unit/core/rules/test_movement_stride.gd
##
## GUT test suite for FEAT-014 (US-014 / FR-013): core/rules/movement.gd's
## Movement.stride() — move UP TO Speed (4) hexes along adjacent hexes,
## spending exactly ONE action via the existing action economy
## (core/rules/action_economy.gd) + Movement trait.
##
## Verifies (test_criteria):
##   1. Stride moves up to and NOT exceeding Speed (4) hexes along adjacent
##      hexes.
##   2. Stride consumes exactly one action per the existing action economy.
##   3. Stride rejects overshoot (> Speed) and rejects ending on an occupied
##      hex.
##   4. Strike reach is re-gated after a Stride.

const MovementClass    = preload("res://core/rules/movement.gd")
const CombatantClass   = preload("res://core/domain/combatant.gd")
const HexCoordClass    = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")
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
# Criterion 1: Stride moves up to and NOT exceeding Speed (4) hexes along
# adjacent hexes.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_moves_combatant_instance_up_to_four_hexes_away() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	var destination := HexCoordClass.new(4, 0)  # hex_distance 4 from (0,0)

	var result: Dictionary = MovementClass.stride(mover, destination, ae, [])

	assert_true(result.get("ok", false), "a Stride exactly at Speed (4) must succeed")
	assert_true(result.get("resolved", false))
	assert_eq(result.get("distance", -1), 4)
	assert_true(mover.hex_coord.equals(destination), "Combatant.hex_coord must be updated to the destination")


func test_stride_moves_dictionary_shaped_combatant() -> void:
	var mover: Dictionary = {"name": "Titus", "hex_coord": HexCoordClass.new(0, 0)}
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	var destination := HexCoordClass.new(2, 0)  # hex_distance 2

	var result: Dictionary = MovementClass.stride(mover, destination, ae, [])

	assert_true(result.get("ok", false))
	assert_true(mover["hex_coord"].equals(destination))


func test_stride_succeeds_for_each_distance_from_one_to_speed() -> void:
	for distance in range(1, MovementClass.DEFAULT_SPEED + 1):
		var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
		var ae := ActionEconomyClass.new()
		ae.start_of_round()
		var destination := HexCoordClass.new(distance, 0)

		var result: Dictionary = MovementClass.stride(mover, destination, ae, [])

		assert_true(result.get("ok", false), "Stride of distance %d must succeed (Speed=%d)" % [distance, MovementClass.DEFAULT_SPEED])
		assert_eq(result.get("distance", -1), distance)


func test_get_stride_destinations_returns_only_unoccupied_hexes_within_speed() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var blocker := CombatantClass.new("e1", "Skeleton", "Enemy", HexCoordClass.new(1, 0))

	var destinations: Array = MovementClass.get_stride_destinations(mover, [blocker])

	for hex_coord in destinations:
		assert_false(hex_coord.equals(HexCoordClass.new(1, 0)), "the occupied hex must not be offered")
		assert_false(hex_coord.equals(HexCoordClass.new(0, 0)), "the mover's own hex must never be offered")
		var d: int = _hex_distance(HexCoordClass.new(0, 0), hex_coord)
		assert_true(d >= 1 and d <= MovementClass.DEFAULT_SPEED, "every offered hex must be within Speed")

	assert_true(destinations.size() > 0)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: Stride consumes exactly one action per the existing action
# economy.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_spends_exactly_one_action_from_the_shared_budget() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	var budget_before: int = ae.get_remaining()

	var result: Dictionary = MovementClass.stride(mover, HexCoordClass.new(3, 0), ae, [])

	assert_true(result.get("ok", false))
	assert_eq(ae.get_remaining(), budget_before - 1, "Stride must spend exactly one action")
	assert_eq(result.get("budget_remaining", -1), ae.get_remaining())


func test_second_stride_same_turn_fails_via_movement_already_used() -> void:
	# action_economy.gd's per-turn Movement gate: only one Movement-trait
	# action (which Stride spends through) is permitted per turn.
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	var first: Dictionary = MovementClass.stride(mover, HexCoordClass.new(1, 0), ae, [])
	assert_true(first.get("ok", false), "first Stride this turn must succeed")

	var budget_after_first: int = ae.get_remaining()
	var second: Dictionary = MovementClass.stride(mover, HexCoordClass.new(1, -1), ae, [])

	assert_false(second.get("ok", true), "a second Movement-trait action in the same turn must be rejected")
	assert_eq(second.get("error", ""), MovementClass.ERR_ACTION_UNAVAILABLE)
	assert_eq(second.get("reason", ""), "MOVEMENT_ALREADY_USED")
	assert_eq(ae.get_remaining(), budget_after_first, "a rejected Stride must not spend a second action")
	assert_true(mover.hex_coord.equals(HexCoordClass.new(1, 0)), "a rejected Stride must not move the combatant")


func test_stride_fails_when_action_budget_already_exhausted() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	for i in range(ActionEconomyClass.MAX_BUDGET):
		ae.spend_action({"traits": []})
	assert_true(ae.is_spent(), "fixture assumption: budget fully exhausted")

	var result: Dictionary = MovementClass.stride(mover, HexCoordClass.new(1, 0), ae, [])

	assert_false(result.get("ok", true))
	assert_eq(result.get("error", ""), MovementClass.ERR_ACTION_UNAVAILABLE)
	assert_eq(result.get("reason", ""), "ALREADY_SPENT")
	assert_true(mover.hex_coord.equals(HexCoordClass.new(0, 0)), "a rejected Stride must not move the combatant")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: Stride rejects overshoot (> Speed) and rejects ending on an
# occupied hex.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_rejects_overshoot_beyond_speed() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	var budget_before: int = ae.get_remaining()

	var result: Dictionary = MovementClass.stride(mover, HexCoordClass.new(5, 0), ae, [])

	assert_false(result.get("ok", true), "a hex_distance-5 destination must be rejected (Speed=4)")
	assert_eq(result.get("error", ""), MovementClass.ERR_DESTINATION_EXCEEDS_SPEED)
	assert_true(mover.hex_coord.equals(HexCoordClass.new(0, 0)), "a rejected Stride must not move the combatant")
	assert_eq(ae.get_remaining(), budget_before, "a rejected Stride must not spend an action")


func test_stride_rejects_occupied_destination() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var blocker := CombatantClass.new("e1", "Skeleton", "Enemy", HexCoordClass.new(2, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	var budget_before: int = ae.get_remaining()

	var result: Dictionary = MovementClass.stride(mover, HexCoordClass.new(2, 0), ae, [blocker])

	assert_false(result.get("ok", true), "an occupied destination must be rejected")
	assert_eq(result.get("error", ""), MovementClass.ERR_DESTINATION_OCCUPIED)
	assert_true(mover.hex_coord.equals(HexCoordClass.new(0, 0)), "a rejected Stride must not move the combatant")
	assert_eq(ae.get_remaining(), budget_before, "a rejected Stride must not spend an action")


func test_stride_rejects_when_combatant_has_no_positional_data() -> void:
	var mover: Dictionary = {"name": "Titus"}  # no "hex_coord" key at all
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	var result: Dictionary = MovementClass.stride(mover, HexCoordClass.new(1, 0), ae, [])

	assert_false(result.get("ok", true))
	assert_eq(result.get("error", ""), MovementClass.ERR_ORIGIN_MISSING)


func test_stride_respects_a_custom_speed_override() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	var result: Dictionary = MovementClass.stride(mover, HexCoordClass.new(3, 0), ae, [], 2)

	assert_false(result.get("ok", true), "distance 3 must exceed a Speed override of 2")
	assert_eq(result.get("error", ""), MovementClass.ERR_DESTINATION_EXCEEDS_SPEED)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: Strike reach is re-gated after a Stride.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_out_of_reach_becomes_in_reach_after_striding_adjacent() -> void:
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
	var target: Dictionary = {"name": "Target", "hp_current": 50, "ac": 10, "hex_coord": HexCoordClass.new(4, -2)}

	# Before striding: hex_distance(attacker, target) == 4 -- out of melee reach.
	var before_result: Dictionary = use_case.resolve(attacker, ae, target, "Strike", 1, 0)
	assert_false(before_result.get("ok", true), "target at hex_distance 4 must be out of reach before the Stride")
	assert_eq(before_result.get("error", ""), "ERR_TARGET_NOT_ADJACENT")

	# Stride the attacker to a hex adjacent to the target: (3, -2) is
	# hex_distance 3 from (0,0) (within Speed) AND adjacent to (4,-2).
	var stride_result: Dictionary = MovementClass.stride(attacker, HexCoordClass.new(3, -2), ae, [target])
	assert_true(stride_result.get("ok", false), "fixture assumption: (3,-2) must be a legal, unoccupied Stride destination")

	# After striding: the SAME use case, called again, must recompute reach
	# from the attacker's NEW position and now accept the Strike. Spending
	# the Stride's action does not itself exhaust the shared budget (default
	# MAX_BUDGET=7), so the subsequent Strike still has an action to spend.
	var after_result: Dictionary = use_case.resolve(attacker, ae, target, "Strike", 1, 0)
	assert_true(after_result.get("ok", false), "target must now be in reach after Stride brought the attacker adjacent")
	assert_true(after_result.get("resolved", false))


func _hex_distance(a, b) -> int:
	var dq: int = absi(a.q - b.q)
	var dr: int = absi(a.r - b.r)
	var ds: int = absi(a.get_s() - b.get_s())
	return int((dq + dr + ds) / 2.0)
