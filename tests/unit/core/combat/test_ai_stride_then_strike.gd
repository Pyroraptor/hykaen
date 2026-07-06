extends GutTest
## tests/unit/core/combat/test_ai_stride_then_strike.gd
##
## GUT unit test suite for FEAT-005 (US-005 / FR-009, ADR-004): immediately
## after core/combat/ai.gd's decide_action() closes distance with a Stride
## (FEAT-004), it re-checks reach in the SAME decision cycle — against the
## combatant's NEW (post-Stride) position — and reports will_strike: true
## when the target is now in reach AND an action remains after the Stride's
## own spend. This composite AIDecision{destination, will_strike} is what a
## later RoundSession/ResolveActionUseCase integration executes sequentially
## (Stride, then Strike) within the SAME turn.
##
## This suite calls decide_action() with FEAT-004's (action_economy,
## other_combatants) parameters — the pre-existing FEAT-003/FEAT-004
## contracts (tests/unit/core/combat/test_ai_reach_strike.gd,
## tests/unit/core/combat/test_ai_target_selection.gd) are left untouched
## and are not re-tested here.
##
## Test criteria (feature spec):
##   1. Stride-then-Strike occurs in the same turn when an action remains
##      after closing distance into reach.
##   2. No Strike is attempted when no action remains after the Stride.

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
# Criterion 1: Stride-then-Strike occurs in the same turn when an action
# remains after closing distance into reach.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_that_closes_into_reach_reports_will_strike_true_when_action_remains() -> void:
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

	# Confirm the fixture actually closed the combatant into melee reach.
	var is_adjacent: bool = false
	for neighbor in HexMathClass.hex_neighbors(destination):
		if neighbor.equals(target_hex):
			is_adjacent = true
			break
	assert_true(is_adjacent, "fixture assumption: the chosen Stride destination must land adjacent to the target")

	assert_true(
		result.get("will_strike", false),
		"will_strike must be true when the Stride closes the target into reach and an action remains"
	)
	assert_eq(
		action_economy.get_remaining(), actions_before - 1,
		"only the Stride's own action may be spent by decide_action() -- the Strike itself is executed by a later caller"
	)
	assert_true(
		action_economy.get_remaining() > 0,
		"fixture assumption: an action must remain after the Stride for this criterion to be meaningful"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: No Strike is attempted (will_strike stays false) when no
# action remains after the Stride.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_that_closes_into_reach_reports_will_strike_false_when_no_action_remains() -> void:
	var ai = AIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(4, 0)
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_round()

	# Drain the round budget down to exactly one action remaining, so the
	# Stride itself consumes the LAST available action.
	for i in range(ActionEconomyClass.MAX_BUDGET - 1):
		action_economy.spend_action({"traits": []})
	assert_eq(action_economy.get_remaining(), 1, "fixture assumption: exactly one action must remain before the Stride")

	var result: Dictionary = ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Stride", "the Stride itself must still be issued -- it is what spends the last action")
	var destination = result.get("destination", null)
	assert_not_null(destination, "a Stride decision must still carry a non-null destination")

	var is_adjacent: bool = false
	for neighbor in HexMathClass.hex_neighbors(destination):
		if neighbor.equals(target_hex):
			is_adjacent = true
			break
	assert_true(is_adjacent, "fixture assumption: the chosen Stride destination must land adjacent to the target")

	assert_eq(action_economy.get_remaining(), 0, "fixture assumption: the Stride must consume the last remaining action")
	assert_false(
		result.get("will_strike", true),
		"will_strike must be false when no action remains after the Stride, even though the target is now in reach"
	)


# ══════════════════════════════════════════════════════════════════════════
# Guard: a target still out of reach after the Stride must not falsely
# report will_strike:true even when an action remains.
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
# Guard: a target already in reach (no Stride needed) is unaffected by this
# feature -- will_strike is reported true exactly as FEAT-003 established.
# ══════════════════════════════════════════════════════════════════════════

func test_already_in_reach_target_unaffected_by_stride_then_strike_logic() -> void:
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
