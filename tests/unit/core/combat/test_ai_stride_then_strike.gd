extends GutTest
## tests/unit/core/combat/test_ai_stride_then_strike.gd
##
## GUT unit test suite for FEAT-007 (US-007 / FR-005, ADR-105): the FEAT-005
## composite "Stride-then-Strike" decision is REMOVED. core/combat/ai.gd's
## decide_action() now issues EXACTLY ONE action per call — when the nearest
## living target is out of reach, decide_action() Strides toward it (FEAT-004
## logic, unchanged) and ALWAYS reports will_strike: false, even when the
## Stride happens to land the combatant in reach of the target. Any Strike
## the Stride enabled is decided on the combatant's NEXT decide_action() call
## (its next turn), never resolved within the same decision.
##
## This suite calls decide_action() with FEAT-004's (action_economy,
## other_combatants) parameters — the pre-existing FEAT-003/FEAT-004
## contracts (tests/unit/core/combat/test_ai_reach_strike.gd,
## tests/unit/core/combat/test_ai_target_selection.gd) are left untouched
## and are not re-tested here.
##
## Test criteria (feature spec, FEAT-007):
##   1. A Stride that closes the target into reach still reports
##      will_strike: false (never a composite) and spends exactly one action.
##   2. A Stride that does NOT close the target into reach also reports
##      will_strike: false.
##   3. A target already in reach (no Stride needed) is unaffected — it
##      still Strikes immediately with zero Stride issued.

const AIClass             = preload("res://core/combat/ai.gd")
const HexCoordClass       = preload("res://core/geometry/hex_coord.gd")
const HexMathClass        = preload("res://core/geometry/hex_math.gd")
const ActionEconomyClass  = preload("res://core/rules/action_economy.gd")


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


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: a Stride that closes the target into reach still reports
# will_strike: false -- decide_action() never issues a composite decision.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_that_closes_into_reach_still_reports_will_strike_false() -> void:
	var ai = AIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(4, 0)  # hex_distance 4 -- out of melee reach initially
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()
	var actions_before: int = action_economy.get_remaining()

	var result: Dictionary = ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Stride", "the enemy must Stride toward the out-of-reach target first")
	var destination = result.get("destination", null)
	assert_not_null(destination, "a Stride decision must carry a non-null destination")
	assert_true(combatant["hex_coord"].equals(destination), "the combatant must actually be repositioned to the chosen Stride destination")

	# Confirm the fixture actually closed the combatant into melee reach --
	# the point of this criterion is that will_strike stays false even
	# though the target is now reachable.
	var is_adjacent: bool = false
	for neighbor in HexMathClass.hex_neighbors(destination):
		if neighbor.equals(target_hex):
			is_adjacent = true
			break
	assert_true(is_adjacent, "fixture assumption: the chosen Stride destination must land adjacent to the target")

	assert_false(
		result.get("will_strike", true),
		"FEAT-007: will_strike must be false for a Stride decision -- no composite Stride-then-Strike is ever issued, even when the Stride closes the target into reach"
	)
	assert_eq(
		action_economy.get_remaining(), actions_before - 1,
		"only the Stride's own action may be spent by decide_action() -- FEAT-007 defers any Strike to the combatant's next turn"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: a Stride that does NOT close the target into reach also
# reports will_strike: false.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_that_does_not_close_into_reach_reports_will_strike_false() -> void:
	var ai = AIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(9, 0)  # far beyond a single Speed-4 Stride's reach
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var result: Dictionary = ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Stride")
	assert_false(
		result.get("will_strike", true),
		"will_strike must remain false when the target is still out of reach after the Stride"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: a target already in reach (no Stride needed) is unaffected by
# this feature -- will_strike is reported true exactly as FEAT-003
# established, with zero Stride issued.
# ══════════════════════════════════════════════════════════════════════════

func test_already_in_reach_target_unaffected_by_stride_then_strike_removal() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
	var target: Dictionary = _target("Titus", HexCoordClass.new(1, 0))  # adjacent
	var action_economy = ActionEconomyClass.new()
	var actions_before: int = action_economy.get_remaining()

	var result: Dictionary = ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Strike")
	assert_null(result.get("destination", "MISSING"))
	assert_true(result.get("will_strike", false))
	assert_eq(action_economy.get_remaining(), actions_before, "no action may be spent when the target was already in reach")
