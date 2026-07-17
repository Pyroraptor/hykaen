extends GutTest
## tests/unit/core/rules/test_movement_step.gd
##
## GUT test suite for FEAT-013 (US-013 / FR-012): core/rules/movement.gd's
## Movement.step() — a FREE, no-reaction, exactly-1-hex move to an adjacent
## UNOCCUPIED hex.
##
## Verifies (test_criteria):
##   1. Step moves the active combatant to any adjacent, unoccupied hex.
##   2. Step does NOT decrement the action budget (action_economy unchanged)
##      and provokes no reaction.
##   3. Step rejects non-adjacent targets and occupied hexes.
##   4. Strike reach is re-gated after a Step (in-reach set recomputed from
##      the new position).

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
# Criterion 1: Step moves the active combatant to any adjacent, unoccupied hex.
# ══════════════════════════════════════════════════════════════════════════

func test_step_moves_combatant_instance_to_adjacent_unoccupied_hex() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var destination := HexCoordClass.new(1, 0)  # a neighbor of (0,0)

	var result: Dictionary = MovementClass.step(mover, destination, [])

	assert_true(result.get("ok", false), "Step to an adjacent, unoccupied hex must succeed")
	assert_true(result.get("resolved", false))
	assert_true(mover.hex_coord.equals(destination), "Combatant.hex_coord must be updated to the destination")


func test_step_moves_dictionary_shaped_combatant_to_adjacent_unoccupied_hex() -> void:
	# The interactive combat pipeline (MainScene.gd / resolve_action_use_case.gd)
	# represents combatants as Dictionaries carrying a "hex_coord" key —
	# Movement.step() must drive that SAME shape, not only Combatant instances.
	var mover: Dictionary = {"name": "Titus", "hex_coord": HexCoordClass.new(0, 0)}
	var destination := HexCoordClass.new(0, 1)

	var result: Dictionary = MovementClass.step(mover, destination, [])

	assert_true(result.get("ok", false))
	assert_true(mover["hex_coord"].equals(destination))


func test_step_succeeds_to_each_of_the_six_neighbors() -> void:
	var neighbor_offsets: Array = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]]
	for offset in neighbor_offsets:
		var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
		var destination := HexCoordClass.new(offset[0], offset[1])
		var result: Dictionary = MovementClass.step(mover, destination, [])
		assert_true(
			result.get("ok", false),
			"Step to neighbor offset (%d,%d) must succeed" % [offset[0], offset[1]]
		)


func test_get_step_destinations_returns_exactly_the_unoccupied_neighbors() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var blocker := CombatantClass.new("e1", "Skeleton", "Enemy", HexCoordClass.new(1, 0))

	var destinations: Array = MovementClass.get_step_destinations(mover, [blocker])

	assert_eq(destinations.size(), 5, "one of the 6 neighbors is occupied and must be excluded")
	for hex_coord in destinations:
		assert_false(hex_coord.equals(HexCoordClass.new(1, 0)), "the occupied neighbor must not be offered")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: Step does NOT decrement the action budget (action_economy
# unchanged) and provokes no reaction.
# ══════════════════════════════════════════════════════════════════════════

func test_step_does_not_touch_action_economy_budget_or_spent_state() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	var budget_before: int = ae.get_remaining()
	var spent_before: bool = ae.is_spent()

	# Movement.step() has no ActionEconomy parameter at all -- it is
	# structurally impossible for it to spend an action or a reaction here.
	var result: Dictionary = MovementClass.step(mover, HexCoordClass.new(1, 0), [])

	assert_true(result.get("ok", false))
	assert_eq(ae.get_remaining(), budget_before, "Step must leave the action budget completely unchanged")
	assert_eq(ae.is_spent(), spent_before, "Step must not mark the combatant Spent")
	assert_eq(ae.get_remaining(), ActionEconomyClass.MAX_BUDGET, "budget must remain at the full per-round maximum")


func test_step_never_provokes_a_reaction() -> void:
	# A "reaction" in this ruleset is spent via ActionEconomy.spend_reaction()
	# (core/rules/action_economy.gd) -- Step never calls it: repeated Steps
	# never move an ActionEconomy toward Spent via the reaction path either.
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	for offset in [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]]:
		mover.hex_coord = HexCoordClass.new(0, 0)
		MovementClass.step(mover, HexCoordClass.new(offset[0], offset[1]), [])

	assert_eq(
		ae.get_remaining(), ActionEconomyClass.MAX_BUDGET,
		"repeated Steps must never provoke a reaction (no budget_remaining change at all)"
	)
	assert_false(ae.is_spent())


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: Step rejects non-adjacent targets and occupied hexes.
# ══════════════════════════════════════════════════════════════════════════

func test_step_rejects_non_adjacent_destination() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var origin_snapshot := HexCoordClass.new(0, 0)

	var result: Dictionary = MovementClass.step(mover, HexCoordClass.new(2, -1), [])

	assert_false(result.get("ok", true), "a hex_distance-2 destination must be rejected")
	assert_eq(result.get("error", ""), MovementClass.ERR_DESTINATION_NOT_ADJACENT)
	assert_true(mover.hex_coord.equals(origin_snapshot), "a rejected Step must not move the combatant")


func test_step_rejects_occupied_destination() -> void:
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var blocker := CombatantClass.new("e1", "Skeleton", "Enemy", HexCoordClass.new(1, 0))
	var origin_snapshot := HexCoordClass.new(0, 0)

	var result: Dictionary = MovementClass.step(mover, HexCoordClass.new(1, 0), [blocker])

	assert_false(result.get("ok", true), "an occupied adjacent hex must be rejected")
	assert_eq(result.get("error", ""), MovementClass.ERR_DESTINATION_OCCUPIED)
	assert_true(mover.hex_coord.equals(origin_snapshot), "a rejected Step must not move the combatant")


func test_step_rejects_when_combatant_has_no_positional_data() -> void:
	var mover: Dictionary = {"name": "Titus"}  # no "hex_coord" key at all

	var result: Dictionary = MovementClass.step(mover, HexCoordClass.new(1, 0), [])

	assert_false(result.get("ok", true))
	assert_eq(result.get("error", ""), MovementClass.ERR_ORIGIN_MISSING)


func test_step_occupied_check_ignores_the_mover_itself() -> void:
	# The mover is never included in its own `other_combatants` list by
	# convention -- stepping onto its OWN current hex is already impossible
	# because hex_neighbors() never includes the origin hex itself, but this
	# guards against a caller accidentally including the mover in the
	# occupancy list from double-blocking a legitimate neighbor.
	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var ally := CombatantClass.new("p2", "Marigold", "Player", HexCoordClass.new(-1, 0))

	var result: Dictionary = MovementClass.step(mover, HexCoordClass.new(1, 0), [ally])

	assert_true(result.get("ok", false), "an unrelated ally elsewhere on the field must not block this Step")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: Strike reach is re-gated after a Step (in-reach set
# recomputed from the new position).
# ══════════════════════════════════════════════════════════════════════════

func test_strike_out_of_reach_becomes_in_reach_after_stepping_adjacent() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	var rng := ScriptedRandomNumberPort.new([12, 4])
	var event_sink := FakeEventSinkPort.new()
	var history := FakeRoundHistoryPort.new()
	var use_case := ResolveActionUseCaseClass.new(rng, event_sink, history)

	var attacker = CombatantClass.from_dict({
		"name": "Attacker", "strength": 3, "hex_coord": HexCoordClass.new(0, 0),
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 2, "damage_die": 6}
	})
	var target = CombatantClass.from_dict({"name": "Target", "hp_current": 50, "ac": 10, "hex_coord": HexCoordClass.new(2, -1)})

	# Before stepping: hex_distance(attacker, target) == 2 -- out of melee reach.
	var before_result: Dictionary = use_case.resolve(attacker, ae, target, "Strike", 1, 0)
	assert_false(before_result.get("ok", true), "target at hex_distance 2 must be out of reach before the Step")
	assert_eq(before_result.get("error", ""), "ERR_TARGET_NOT_ADJACENT")

	# Step the attacker into a hex adjacent to the target: (1, -1) is one of
	# (0,0)'s neighbors AND one of (2,-1)'s neighbors.
	var step_result: Dictionary = MovementClass.step(attacker, HexCoordClass.new(1, -1), [target])
	assert_true(step_result.get("ok", false), "fixture assumption: (1,-1) must be a legal, unoccupied Step destination")

	# After stepping: the SAME use case, called again, must recompute reach
	# from the attacker's NEW position and now accept the Strike.
	var after_result: Dictionary = use_case.resolve(attacker, ae, target, "Strike", 1, 0)
	assert_true(after_result.get("ok", false), "target must now be in reach after Step brought the attacker adjacent")
	assert_true(after_result.get("resolved", false))
