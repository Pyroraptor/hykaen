extends GutTest
## tests/unit/combat/test_grunt_ai.gd
##
## GUT unit test suite for FEAT-005 (US-005 / FR-012): the DOMAIN-layer
## core/combat/grunt_ai.gd "Step-before-Strike" tier AI planner.
##
## Verifies (this feature's test_criteria):
##   1. Target selection prefers LOWEST HP over NEAREST when they conflict
##      (a nearer, higher-HP target must lose to a farther, lower-HP one).
##   2. 1-hex gap (hex_distance == 2) -> plan is exactly [Step, Strike], with
##      the Step destination one of Movement.get_step_destinations()'s legal
##      candidates.
##   3. 2+ hex gap (hex_distance >= 3) -> plan is exactly [Stride, Strike],
##      with the Stride destination chosen via HexScorer ranking over
##      Movement.get_stride_destinations()'s legal candidates.
##   4. No living targets -> plan is [] (a first-class WAIT, not an error).
##
## Also spot-checks the adjacent (hex_distance == 1) base case (plan is
## exactly [Strike]) since every other gap tier builds on it.
##
## Satisfies: FEAT-005, US-005, FR-012.

const GruntAIClass   = preload("res://core/combat/grunt_ai.gd")
const HexCoordClass  = preload("res://core/geometry/hex_coord.gd")
const MovementClass  = preload("res://core/rules/movement.gd")
const HexMathClass   = preload("res://core/geometry/hex_math.gd")


func _combatant(name: String, hex_coord, hp: int = 10) -> Dictionary:
	return {"name": name, "hp_current": hp, "hex_coord": hex_coord}


func _world_context(party: Array, enemies: Array = []) -> Dictionary:
	return {"party": party, "enemies": enemies, "action_economy": null}


# ══════════════════════════════════════════════════════════════════════════
# Criterion: adjacent target (hex_distance == 1) -> plan is exactly [Strike]
# ══════════════════════════════════════════════════════════════════════════

func test_adjacent_target_plan_is_exactly_strike() -> void:
	var ai := GruntAIClass.new()
	var combatant: Dictionary = _combatant("Grunt", HexCoordClass.new(0, 0))
	var target: Dictionary = _combatant("Titus", HexCoordClass.new(1, 0))

	var plan: Array = ai.plan_turn(combatant, _world_context([target]))

	assert_eq(plan.size(), 1, "an adjacent target must yield a single-item plan")
	assert_eq(plan[0].get("action_type", ""), "Strike", "the single plan item must be a Strike")
	assert_eq(plan[0].get("target", null), target, "the Strike must target the adjacent living combatant")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: target selection prefers LOWEST HP over NEAREST on conflict
# ══════════════════════════════════════════════════════════════════════════

func test_target_selection_prefers_lowest_hp_over_nearest() -> void:
	var ai := GruntAIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _combatant("Grunt", origin_hex)

	# Nearer target with HIGH hp — must lose out despite being adjacent.
	var near_high_hp: Dictionary = _combatant("Tank", HexCoordClass.new(1, 0), 50)
	# Farther target with LOW hp — must be preferred even though it is
	# farther away and requires closing a 1-hex gap first.
	var far_low_hp: Dictionary = _combatant("Wounded", HexCoordClass.new(0, 2), 3)

	var plan: Array = ai.plan_turn(combatant, _world_context([near_high_hp, far_low_hp]))

	assert_false(plan.is_empty(), "a living target exists, so the plan must not be empty")
	var strike_item = plan[plan.size() - 1]
	assert_eq(strike_item.get("action_type", ""), "Strike", "the final plan item must be the Strike")
	assert_eq(strike_item.get("target", null), far_low_hp, "the lower-HP target must be selected even though it is farther away")


func test_target_selection_falls_back_to_nearest_on_hp_tie() -> void:
	var ai := GruntAIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _combatant("Grunt", origin_hex)

	# Equal HP -- distance is the tie-break; the adjacent target must win.
	var near: Dictionary = _combatant("Near", HexCoordClass.new(1, 0), 10)
	var far: Dictionary = _combatant("Far", HexCoordClass.new(0, 3), 10)

	var plan: Array = ai.plan_turn(combatant, _world_context([near, far]))

	assert_eq(plan.size(), 1, "the nearest equal-HP target is adjacent, so the plan must be a single Strike")
	assert_eq(plan[0].get("target", null), near, "on an HP tie, the nearest target must be selected")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: 1-hex gap (hex_distance == 2) -> plan is exactly [Step, Strike]
# via Movement.get_step_destinations()
# ══════════════════════════════════════════════════════════════════════════

func test_one_hex_gap_plan_is_exactly_step_then_strike() -> void:
	var ai := GruntAIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _combatant("Grunt", origin_hex)
	var target_hex = HexCoordClass.new(2, 0)
	var target: Dictionary = _combatant("Titus", target_hex)

	assert_eq(HexMathClass.hex_distance(origin_hex, target_hex), 2, "fixture assumption: a 1-hex gap is hex_distance == 2")

	var expected_destinations: Array = MovementClass.get_step_destinations({"hex_coord": origin_hex}, [target])
	assert_false(expected_destinations.is_empty(), "fixture assumption: at least one legal Step destination must exist")

	var plan: Array = ai.plan_turn(combatant, _world_context([target]))

	assert_eq(plan.size(), 2, "a 1-hex gap target must yield a two-item plan")
	assert_eq(plan[0].get("action_type", ""), "Step", "the first plan item must be a Step")
	assert_eq(plan[1].get("action_type", ""), "Strike", "the second plan item must be a Strike")
	assert_eq(plan[1].get("target", null), target, "the Strike must target the same combatant the Step closed on")

	var destination = plan[0].get("destination", null)
	assert_not_null(destination, "the Step plan item must carry a non-null destination")

	var is_legal: bool = false
	for candidate in expected_destinations:
		if candidate.equals(destination):
			is_legal = true
			break
	assert_true(is_legal, "the chosen Step destination must be one of Movement.get_step_destinations()'s legal candidates")

	var new_distance: int = HexMathClass.hex_distance(destination, target_hex)
	assert_eq(new_distance, 1, "a Step across a 1-hex gap must land adjacent to the target")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: 2+ hex gap (hex_distance >= 3) -> plan is exactly
# [Stride, Strike], destination chosen via HexScorer-ranked
# Movement.get_stride_destinations()
# ══════════════════════════════════════════════════════════════════════════

func test_two_plus_hex_gap_plan_is_exactly_stride_then_strike() -> void:
	var ai := GruntAIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _combatant("Grunt", origin_hex)
	var target_hex = HexCoordClass.new(6, 0)
	var target: Dictionary = _combatant("Titus", target_hex)

	assert_true(HexMathClass.hex_distance(origin_hex, target_hex) >= 3, "fixture assumption: a 2+ hex gap is hex_distance >= 3")

	var expected_destinations: Array = MovementClass.get_stride_destinations({"hex_coord": origin_hex}, [target])
	assert_false(expected_destinations.is_empty(), "fixture assumption: at least one legal Stride destination must exist")

	var plan: Array = ai.plan_turn(combatant, _world_context([target]))

	assert_eq(plan.size(), 2, "a 2+ hex gap target must yield a two-item plan")
	assert_eq(plan[0].get("action_type", ""), "Stride", "the first plan item must be a Stride")
	assert_eq(plan[1].get("action_type", ""), "Strike", "the second plan item must be a Strike")
	assert_eq(plan[1].get("target", null), target, "the Strike must target the same combatant the Stride closed on")

	var destination = plan[0].get("destination", null)
	assert_not_null(destination, "the Stride plan item must carry a non-null destination")

	var is_legal: bool = false
	for candidate in expected_destinations:
		if candidate.equals(destination):
			is_legal = true
			break
	assert_true(is_legal, "the chosen Stride destination must be one of Movement.get_stride_destinations()'s legal candidates")

	# HexScorer.score_hex() is a zero-weighted stub today (NFR-005), so every
	# legal candidate ties on score; the tie-break (minimise hex_distance to
	# the target) must still yield a destination that strictly reduces
	# distance to the target -- proving the HexScorer ranking path was
	# actually exercised (not skipped) and did not produce a degenerate
	# destination.
	var original_distance: int = HexMathClass.hex_distance(origin_hex, target_hex)
	var new_distance: int = HexMathClass.hex_distance(destination, target_hex)
	assert_true(new_distance < original_distance, "the chosen Stride destination must strictly reduce hex_distance to the target")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: no living targets -> plan is []
# ══════════════════════════════════════════════════════════════════════════

func test_no_living_targets_plan_is_empty() -> void:
	var ai := GruntAIClass.new()
	var combatant: Dictionary = _combatant("Grunt", HexCoordClass.new(0, 0))
	var dead_target: Dictionary = _combatant("Titus", HexCoordClass.new(1, 0), 0)

	var plan: Array = ai.plan_turn(combatant, _world_context([dead_target]))

	assert_eq(plan, [], "no living targets must yield an empty (WAIT) plan")


func test_empty_party_plan_is_empty() -> void:
	var ai := GruntAIClass.new()
	var combatant: Dictionary = _combatant("Grunt", HexCoordClass.new(0, 0))

	var plan: Array = ai.plan_turn(combatant, _world_context([]))

	assert_eq(plan, [], "an empty party (no targets at all) must yield an empty (WAIT) plan")
