extends GutTest
## tests/unit/controllers/test_strike_action_controller_post_move.gd
##
## GUT suite for FEAT-006 (Iteration O "Combine Selection UX"; US-006;
## FR-005; ADR-006): core/controllers/strike_action_controller.gd's
## StrikeActionController.enter_selection() — post-move-aware targeting for
## chained sub-actions.
##
## Verifies (test_criteria):
##   1. enter_selection() with accumulated['STRIDE'] carrying a resolved
##      chosen_hex X returns candidate_targets reachable from hex X, NOT the
##      actor's own current (real) hex_coord.
##   2. Without an accumulated STRIDE selection, enter_selection() falls back
##      to the actor's own current hex_coord (standalone/unchained Strike
##      behaviour is unaffected).
##   3. The actor's real hex_coord is never mutated by any enter_selection()
##      call this controller makes.
##   4. Ranged weapons use the same accumulated-origin substitution (distance
##      <= range_hexes from the hypothetical hex, not the real one).
##   5. A target reachable from the actor's REAL hex but NOT from the
##      hypothetical post-move hex is correctly excluded (proves the
##      substitution is a genuine replacement, not an additive union).

const StrikeActionControllerClass = preload("res://core/controllers/strike_action_controller.gd")
const SelectionDescriptorClass = preload("res://core/domain/combine/selection_descriptor.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


func _melee_combatant(id: String, hex: HexCoordClass) -> CombatantClass:
	var c := CombatantClass.new(id, id, "Player", hex)
	c.weapon = {"name": "Sword"}
	c.hp_current = 10
	c.hp_max = 10
	return c


func _ranged_combatant(id: String, hex: HexCoordClass, range_hexes: int) -> CombatantClass:
	var c := CombatantClass.new(id, id, "Player", hex)
	c.weapon = {"name": "Bow", "range_hexes": range_hexes}
	c.hp_current = 10
	c.hp_max = 10
	return c


## _stride_selection(chosen_hex) -> SelectionDescriptor — mirrors
## core/controllers/stride_action_controller.gd's own already-resolved
## SelectionDescriptor shape ({"chosen_hex": ...} on `meta`), the SAME shape
## accumulated['STRIDE'] carries per multi_phase_targeting_controller.gd's
## own accumulated[verb_id]=descriptor convention.
func _stride_selection(chosen_hex: HexCoordClass) -> Object:
	return SelectionDescriptorClass.new(true, [], [chosen_hex], [], 0, {"chosen_hex": chosen_hex})


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 + 5 — candidate_targets computed from accumulated['STRIDE']'s
# hypothetical hex, replacing (not unioning with) the actor's real hex.
# ══════════════════════════════════════════════════════════════════════════

func test_candidate_targets_computed_from_accumulated_stride_hex_not_actor_real_hex() -> void:
	var actor := _melee_combatant("actor_0", HexCoordClass.new(0, 0))
	# Only reachable from the hypothetical post-move hex (2,0), NOT from the
	# actor's real (0,0) starting hex.
	var far_target := _melee_combatant("enemy_far", HexCoordClass.new(3, 0))

	var controller := StrikeActionControllerClass.new({
		"candidate_targets_fn": func(): return [far_target],
	})

	var post_move_hex := HexCoordClass.new(2, 0)
	var result: Object = controller.enter_selection({
		"actor_id": actor,
		"order_index": 1,
		"accumulated": {"STRIDE": _stride_selection(post_move_hex)},
	})

	assert_true(result.ok, "a target reachable from the hypothetical post-move hex must be offered")
	assert_eq(result.candidate_targets, ["enemy_far"], "candidate_targets must be computed from accumulated['STRIDE']'s hex, not the actor's real hex")


func test_target_reachable_only_from_actors_real_hex_is_excluded_once_a_stride_hex_is_accumulated() -> void:
	var actor := _melee_combatant("actor_0", HexCoordClass.new(0, 0))
	# Reachable from the actor's REAL (0,0) hex (adjacent, distance 1), but
	# NOT from the hypothetical post-move (2,0) hex (distance 3, well
	# outside melee reach).
	var near_target := _melee_combatant("enemy_near", HexCoordClass.new(-1, 0))

	var controller := StrikeActionControllerClass.new({
		"candidate_targets_fn": func(): return [near_target],
	})

	var post_move_hex := HexCoordClass.new(2, 0)
	var result: Object = controller.enter_selection({
		"actor_id": actor,
		"order_index": 1,
		"accumulated": {"STRIDE": _stride_selection(post_move_hex)},
	})

	assert_false(result.ok, "a target reachable only from the actor's REAL hex must NOT be offered once a post-move hex is accumulated")
	assert_eq(result.meta.get("error_code"), "NO_LEGAL_OPTIONS")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — no accumulated STRIDE selection: falls back to the actor's
# own current hex_coord (unchanged standalone behaviour).
# ══════════════════════════════════════════════════════════════════════════

func test_falls_back_to_actors_real_hex_when_no_accumulated_stride_selection() -> void:
	var actor := _melee_combatant("actor_0", HexCoordClass.new(0, 0))
	var adjacent_target := _melee_combatant("enemy_adjacent", HexCoordClass.new(1, 0))

	var controller := StrikeActionControllerClass.new({
		"candidate_targets_fn": func(): return [adjacent_target],
	})

	var result: Object = controller.enter_selection({"actor_id": actor, "order_index": 0})

	assert_true(result.ok)
	assert_eq(result.candidate_targets, ["enemy_adjacent"], "with no accumulated STRIDE selection, reach must be computed from the actor's own current hex_coord")


func test_falls_back_to_actors_real_hex_when_accumulated_stride_entry_has_no_chosen_hex() -> void:
	var actor := _melee_combatant("actor_0", HexCoordClass.new(0, 0))
	var adjacent_target := _melee_combatant("enemy_adjacent", HexCoordClass.new(1, 0))

	var controller := StrikeActionControllerClass.new({
		"candidate_targets_fn": func(): return [adjacent_target],
	})

	# An accumulated STRIDE entry that only OFFERED candidate_hexes (no
	# resolved chosen_hex yet) must not be treated as a hypothetical origin.
	var unresolved_stride := SelectionDescriptorClass.new(true, [], [HexCoordClass.new(2, 0)], [], 0, {})
	var result: Object = controller.enter_selection({
		"actor_id": actor,
		"order_index": 1,
		"accumulated": {"STRIDE": unresolved_stride},
	})

	assert_true(result.ok)
	assert_eq(result.candidate_targets, ["enemy_adjacent"], "an unresolved (no chosen_hex) accumulated STRIDE entry must not override the actor's real hex")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — the actor's real position is never mutated.
# ══════════════════════════════════════════════════════════════════════════

func test_actor_real_hex_coord_never_mutated_by_enter_selection() -> void:
	var actor := _melee_combatant("actor_0", HexCoordClass.new(0, 0))
	var far_target := _melee_combatant("enemy_far", HexCoordClass.new(3, 0))

	var controller := StrikeActionControllerClass.new({
		"candidate_targets_fn": func(): return [far_target],
	})

	var post_move_hex := HexCoordClass.new(2, 0)
	controller.enter_selection({
		"actor_id": actor,
		"order_index": 1,
		"accumulated": {"STRIDE": _stride_selection(post_move_hex)},
	})

	assert_eq(actor.hex_coord.q, 0, "the actor's real hex_coord.q must be unchanged")
	assert_eq(actor.hex_coord.r, 0, "the actor's real hex_coord.r must be unchanged")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — ranged weapons: same accumulated-origin substitution.
# ══════════════════════════════════════════════════════════════════════════

func test_ranged_weapon_reach_computed_from_accumulated_stride_hex() -> void:
	var actor := _ranged_combatant("archer_0", HexCoordClass.new(0, 0), 3)
	# 5 hexes from the actor's real (0,0) start (out of a 3-range bow), but
	# only 2 hexes from the hypothetical post-move hex (3,0) -- in range.
	var target := _ranged_combatant("target_0", HexCoordClass.new(5, 0), 0)

	var controller := StrikeActionControllerClass.new({
		"candidate_targets_fn": func(): return [target],
	})

	var post_move_hex := HexCoordClass.new(3, 0)
	var result: Object = controller.enter_selection({
		"actor_id": actor,
		"order_index": 1,
		"accumulated": {"STRIDE": _stride_selection(post_move_hex)},
	})

	assert_true(result.ok, "a ranged target within range of the hypothetical post-move hex must be offered")
	assert_eq(result.candidate_targets, ["target_0"])


# ══════════════════════════════════════════════════════════════════════════
# Fail-safe shapes.
# ══════════════════════════════════════════════════════════════════════════

func test_no_actor_returns_no_legal_options() -> void:
	var controller := StrikeActionControllerClass.new({"candidate_targets_fn": func(): return []})
	var result: Object = controller.enter_selection({"order_index": 0})
	assert_false(result.ok)
	assert_eq(result.meta.get("error_code"), "NO_LEGAL_OPTIONS")


func test_no_candidates_in_reach_returns_no_legal_options() -> void:
	var actor := _melee_combatant("actor_0", HexCoordClass.new(0, 0))
	var controller := StrikeActionControllerClass.new({"candidate_targets_fn": func(): return []})
	var result: Object = controller.enter_selection({"actor_id": actor, "order_index": 0})
	assert_false(result.ok)
	assert_eq(result.meta.get("error_code"), "NO_LEGAL_OPTIONS")
