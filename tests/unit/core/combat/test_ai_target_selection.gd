extends GutTest
## tests/unit/core/combat/test_ai_target_selection.gd
##
## GUT unit test suite for FEAT-004 (US-004 / FR-008, ADR-005 groundwork): an
## enemy whose nearest living target is OUT of reach (per the SAME
## melee-adjacency/ranged-range reach check FEAT-003 already established)
## Strides toward it — choosing a LEGAL destination
## (core/rules/movement.gd Movement.get_stride_destinations()) that
## minimises hex_distance to that target, spending exactly one action and
## marking the Movement trait via the SAME core/rules/action_economy.gd
## ActionEconomy gate FEAT-001's Step hook and a player-driven Stride both
## use.
##
## This suite calls core/combat/ai.gd's decide_action() with its two NEW
## FEAT-004 optional parameters (`action_economy`, `other_combatants`) — the
## pre-existing 2-argument contract (exercised by tests/unit/test_ai.gd and
## tests/unit/core/combat/test_ai_reach_strike.gd) is left completely
## untouched and is not re-tested here.
##
## Test criteria (feature spec):
##   1. Chosen Stride destination is legal (unoccupied and within actor
##      Speed) per Movement.get_stride_destinations().
##   2. Chosen destination strictly reduces hex_distance to the nearest
##      living target versus the actor's current position.
##   3. ActionEconomy.actions_remaining is decremented by one and
##      movement_used is set true on the chosen Stride.
##   4. Static check: zero 'extends Node'/'extends Control' occurrences
##      introduced in core/combat/ai.gd.

const AIClass             = preload("res://core/combat/ai.gd")
const HexCoordClass       = preload("res://core/geometry/hex_coord.gd")
const HexMathClass        = preload("res://core/geometry/hex_math.gd")
const MovementClass       = preload("res://core/rules/movement.gd")
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
# Criterion 1 + 2: an out-of-reach melee enemy Strides to a LEGAL destination
# (per Movement.get_stride_destinations()) that strictly reduces hex_distance
# to the nearest living target.
# ══════════════════════════════════════════════════════════════════════════

func test_out_of_reach_enemy_strides_to_a_legal_destination_that_reduces_distance() -> void:
	var ai = AIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(6, 0)
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()

	# The legal candidate set BEFORE the move, computed independently via
	# the SAME domain function decide_action() must source destinations
	# from — this is the "legal per Movement.get_stride_destinations()"
	# criterion, verified against a snapshot of the actor's pre-move hex.
	var expected_destinations: Array = MovementClass.get_stride_destinations({"hex_coord": origin_hex}, [target])
	assert_false(expected_destinations.is_empty(), "fixture assumption: at least one legal Stride destination must exist")

	var original_distance: int = HexMathClass.hex_distance(origin_hex, target_hex)

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Stride", "an out-of-reach enemy with an ActionEconomy supplied must Stride toward its target")
	var destination = result.get("destination", null)
	assert_not_null(destination, "a Stride decision must carry a non-null destination")

	var is_legal: bool = false
	for candidate in expected_destinations:
		if candidate.equals(destination):
			is_legal = true
			break
	assert_true(is_legal, "the chosen destination must be one of Movement.get_stride_destinations()'s legal candidates")

	var new_distance: int = HexMathClass.hex_distance(destination, target_hex)
	assert_true(new_distance < original_distance, "the chosen destination must strictly reduce hex_distance to the nearest living target")

	# The domain mutation must actually have happened (combatant repositioned).
	assert_true(combatant["hex_coord"].equals(destination), "decide_action() must actually reposition the combatant to the chosen Stride destination")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: ActionEconomy.actions_remaining is decremented by one and
# movement_used is set true on the chosen Stride.
# ══════════════════════════════════════════════════════════════════════════

func test_chosen_stride_spends_one_action_and_marks_movement_used() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
	var target: Dictionary = _target("Titus", HexCoordClass.new(6, 0))
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var actions_before: int = action_economy.get_remaining()
	assert_true(action_economy.can_take_movement_action(), "fixture assumption: movement must be available before the Stride")

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Stride")
	assert_eq(
		action_economy.get_remaining(), actions_before - 1,
		"a chosen Stride must decrement ActionEconomy.actions_remaining by exactly one"
	)
	assert_false(
		action_economy.can_take_movement_action(),
		"a chosen Stride must mark the ActionEconomy Movement trait used (the SAME gate FEAT-001's Step hook trips)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Guard: a target already in reach still Strikes immediately, even when the
# new (action_economy, other_combatants) parameters are supplied — no
# pointless Stride is issued and the budget is left untouched.
# ══════════════════════════════════════════════════════════════════════════

func test_already_in_reach_target_still_strikes_with_action_economy_supplied() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
	var target: Dictionary = _target("Titus", HexCoordClass.new(1, 0))  # adjacent
	var action_economy = ActionEconomyClass.new()
	var actions_before: int = action_economy.get_remaining()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Strike", "an already-adjacent target must still Strike immediately, not Stride")
	assert_null(result.get("destination", "MISSING"))
	assert_eq(action_economy.get_remaining(), actions_before, "no action may be spent when the target was already in reach")
	assert_true(action_economy.can_take_movement_action(), "the Movement gate must be untouched when no Stride was issued")


# ══════════════════════════════════════════════════════════════════════════
# Guard: an enemy that has ALREADY used its Movement trait this turn
# (MOVEMENT_ALREADY_USED) must not Stride — the FEAT-001 gate is respected,
# never bypassed by the AI's own decision path.
# ══════════════════════════════════════════════════════════════════════════

func test_movement_already_used_this_turn_prevents_a_second_stride() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
	var target: Dictionary = _target("Titus", HexCoordClass.new(6, 0))
	var action_economy = ActionEconomyClass.new()
	action_economy.mark_movement_used()  # simulate an earlier Step/Stride this turn
	var actions_before: int = action_economy.get_remaining()
	var hex_before = combatant["hex_coord"]

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", "MISSING"), "", "no Stride may be issued once the Movement trait was already used this turn")
	assert_null(result.get("destination", "MISSING"))
	assert_eq(action_economy.get_remaining(), actions_before, "no action may be spent for a rejected Stride")
	assert_true(combatant["hex_coord"].equals(hex_before), "the combatant must not move when the Stride's ActionEconomy spend is rejected")


# ══════════════════════════════════════════════════════════════════════════
# Guard: legacy 2-argument calls (no action_economy/other_combatants
# supplied) are completely unaffected by FEAT-004 — the exact FEAT-003
# "no Stride issued" contract holds for an out-of-reach target.
# ══════════════════════════════════════════════════════════════════════════

func test_legacy_two_argument_call_issues_no_stride_for_out_of_reach_target() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
	var target: Dictionary = _target("Titus", HexCoordClass.new(6, 0))

	var result: Dictionary = await ai.decide_action(combatant, [target])

	assert_eq(result.get("action_type", "MISSING"), "", "legacy 2-argument callers must retain the FEAT-003 no-Stride contract")
	assert_null(result.get("destination", "MISSING"))
	assert_false(result.get("will_strike", true))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: Static check — core/combat/ai.gd must not introduce
# 'extends Node' or 'extends Control' (domain purity, ADR-001).
# ══════════════════════════════════════════════════════════════════════════

func test_ai_gd_does_not_extend_node_or_control() -> void:
	var file := FileAccess.open("res://core/combat/ai.gd", FileAccess.READ)
	assert_not_null(file, "core/combat/ai.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(content.contains("extends Node"), "ai.gd must not contain 'extends Node' — domain purity (ADR-001)")
	assert_false(content.contains("extends Control"), "ai.gd must not contain 'extends Control' — domain purity (ADR-001)")
