extends GutTest
## tests/unit/core/combat/test_ai_reach_strike.gd
##
## GUT unit test suite for FEAT-003 (US-003 / FR-007): the reach check at
## the TOP of core/combat/ai.gd's decide_action() — an enemy already in
## reach (melee adjacency, or listed range for a ranged weapon) of the
## nearest living target Strikes immediately, with NO Stride issued. This
## establishes the baseline AI decision path before movement/closing-
## distance logic is layered on by a later feature.
##
## decide_action() is extended (not replaced) to additionally report
## "destination" (null when no movement was needed) and "will_strike"
## (bool) alongside the pre-existing "action_type"/"target" keys, so
## downstream orchestration (RoundSession.advance_ai_turn(), a future
## feature) can distinguish "Strike with zero Stride issued" from a
## composite Stride-then-Strike outcome.
##
## Test criteria (feature spec):
##   Adjacent (melee) or in-range (ranged) enemy target results in
##   AIDecision{destination: null, will_strike: true} with zero Stride
##   issued.

const AIClass        = preload("res://core/combat/ai.gd")
const HexCoordClass  = preload("res://core/geometry/hex_coord.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")


func _melee_combatant(hex_coord):
	return CombatantClass.from_dict({
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
	})


func _ranged_combatant(hex_coord, range_hexes: int):
	return CombatantClass.from_dict({
		"name":        "Archer",
		"hp_current":  8,
		"ac":          12,
		"dexterity":   2,
		"hex_coord":   hex_coord,
		"weapon": {
			"damage_modifier_attribute": "dexterity",
			"proficiency_bonus": 1,
			"damage_die": 6,
			"range_hexes": range_hexes
		}
	})


func _target(name: String, hex_coord, hp: int = 18):
	return CombatantClass.from_dict({"name": name, "hp_current": hp, "ac": 14, "strength": 5, "hex_coord": hex_coord})


# ══════════════════════════════════════════════════════════════════════════
# Criterion: a melee enemy already adjacent to a living target Strikes with
# destination:null, will_strike:true, and zero Stride issued.
# ══════════════════════════════════════════════════════════════════════════

func test_melee_enemy_adjacent_to_target_strikes_with_null_destination() -> void:
	var ai = AIClass.new()
	var combatant = _melee_combatant(HexCoordClass.new(0, 0))
	var target = _target("Titus", HexCoordClass.new(1, 0))  # adjacent neighbor

	var result: Dictionary = await ai.decide_action(combatant, [target])

	assert_eq(result.get("action_type", ""), "Strike", "an already-adjacent target must be Struck immediately")
	assert_eq(result.get("target").name, "Titus")
	assert_null(result.get("destination", "MISSING"), "no destination/Stride is needed when already in reach")
	assert_true(result.get("will_strike", false), "will_strike must be true when the target is already in reach")


func test_melee_enemy_adjacent_to_target_issues_zero_stride() -> void:
	# decide_action() must not itself perform any movement/Stride side effect
	# when the target is already in reach — the returned decision simply
	# carries destination:null, which is the caller's (RoundSession's)
	# signal that no Stride is required this turn.
	var ai = AIClass.new()
	var combatant = _melee_combatant(HexCoordClass.new(0, 0))
	var target = _target("Titus", HexCoordClass.new(0, 1))  # adjacent neighbor
	var combatant_hex_before = combatant["hex_coord"]

	var result: Dictionary = await ai.decide_action(combatant, [target])

	assert_null(result.get("destination", "MISSING"))
	assert_true(
		combatant["hex_coord"].equals(combatant_hex_before),
		"decide_action() must never move the acting combatant itself — zero Stride issued"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion: a ranged enemy already within its weapon's range_hexes of a
# living target Strikes with destination:null, will_strike:true, zero Stride.
# ══════════════════════════════════════════════════════════════════════════

func test_ranged_enemy_within_range_strikes_with_null_destination() -> void:
	var ai = AIClass.new()
	var combatant = _ranged_combatant(HexCoordClass.new(0, 0), 8)
	var target = _target("Titus", HexCoordClass.new(5, 0))  # distance 5, within range 8

	var result: Dictionary = await ai.decide_action(combatant, [target])

	assert_eq(result.get("action_type", ""), "Strike", "a target within range_hexes must be Struck immediately")
	assert_eq(result.get("target").name, "Titus")
	assert_null(result.get("destination", "MISSING"), "no destination/Stride is needed when already in range")
	assert_true(result.get("will_strike", false), "will_strike must be true when the target is already in range")


func test_ranged_enemy_exactly_at_range_hexes_strikes_immediately() -> void:
	var ai = AIClass.new()
	var combatant = _ranged_combatant(HexCoordClass.new(0, 0), 8)
	var target = _target("Titus", HexCoordClass.new(8, 0))  # distance == range_hexes

	var result: Dictionary = await ai.decide_action(combatant, [target])

	assert_eq(result.get("action_type", ""), "Strike")
	assert_true(result.get("will_strike", false))
	assert_null(result.get("destination", "MISSING"))


# ══════════════════════════════════════════════════════════════════════════
# Guard: a target out of reach (melee non-adjacent, no movement logic layered
# on yet by this feature) must NOT be falsely reported as will_strike:true —
# this feature only establishes the "already in reach" baseline path.
# ══════════════════════════════════════════════════════════════════════════

func test_melee_enemy_out_of_reach_does_not_falsely_report_will_strike() -> void:
	var ai = AIClass.new()
	var combatant = _melee_combatant(HexCoordClass.new(0, 0))
	var target = _target("Titus", HexCoordClass.new(3, 0))  # hex_distance 3 -- not adjacent

	var result: Dictionary = await ai.decide_action(combatant, [target])

	assert_false(result.get("will_strike", true), "an out-of-reach target must not report will_strike:true")
	assert_null(result.get("destination", "MISSING"), "this feature issues no Stride destination yet — movement is a later feature")


func test_ranged_enemy_beyond_range_hexes_does_not_falsely_report_will_strike() -> void:
	var ai = AIClass.new()
	var combatant = _ranged_combatant(HexCoordClass.new(0, 0), 8)
	var target = _target("Titus", HexCoordClass.new(9, 0))  # 1 hex beyond range

	var result: Dictionary = await ai.decide_action(combatant, [target])

	assert_false(result.get("will_strike", true), "a target beyond range_hexes must not report will_strike:true")


# ══════════════════════════════════════════════════════════════════════════
# Backward compatibility: combatants/targets without hex_coord data are
# never reach-gated (pre-existing callers, e.g. legacy encounter.gd
# Dictionaries) — the v0 "always Strike the first living target" behavior
# is preserved exactly, now also reporting destination:null/will_strike:true.
# ══════════════════════════════════════════════════════════════════════════

func test_combatant_without_hex_coord_is_not_reach_gated_and_still_strikes() -> void:
	var ai = AIClass.new()
	var combatant = CombatantClass.from_dict({
		"name": "Skeleton", "hp_current": 8, "ac": 12, "strength": 2,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 1, "damage_die": 6}
	})
	var target = CombatantClass.from_dict({"name": "Titus", "hp_current": 18, "ac": 14, "strength": 5})

	var result: Dictionary = await ai.decide_action(combatant, [target])

	assert_eq(result.get("action_type", ""), "Strike", "legacy callers without hex_coord data must not be reach-gated")
	assert_true(result.get("will_strike", false))
	assert_null(result.get("destination", "MISSING"))
