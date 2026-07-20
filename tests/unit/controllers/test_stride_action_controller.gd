extends GutTest
## tests/unit/controllers/test_stride_action_controller.gd
##
## GUT suite for FEAT-006 hand-fix (Iteration O "Combine Selection UX"; US-006;
## FR-005; ADR-006): core/controllers/stride_action_controller.gd's
## StrideActionController.enter_selection() — legal destination offer + validated
## selected_hex threading.
##
## Verifies (test_criteria):
##   1. Offer path: actor with legal destinations returns ok with candidate_hexes.
##   2. Null actor returns NO_LEGAL_OPTIONS.
##   3. Zero destinations (speed=0) returns NO_LEGAL_OPTIONS.
##   4. selected_hex present AND in destinations: ok, meta.chosen_hex set,
##      candidate_hexes still populated.
##   5. selected_hex present but NOT in destinations: NO_LEGAL_OPTIONS (the
##      fix: callers cannot inject an illegal hex via context).
##   6. Invalid other_combatants_fn degrades to empty list (no crash, offer still
##      works).
##   7. Actor's real hex_coord is never mutated by any enter_selection() call.
##   8. Speed override expands reachable destinations.

const StrideActionControllerClass = preload("res://core/controllers/stride_action_controller.gd")
const SelectionDescriptorClass = preload("res://core/domain/combine/selection_descriptor.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const MovementClass = preload("res://core/rules/movement.gd")


func _combatant(id: String, hex: HexCoordClass) -> CombatantClass:
	var c := CombatantClass.new(id, id, "Player", hex)
	c.weapon = {"name": "Sword"}
	c.hp_current = 10
	c.hp_max = 10
	return c


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1 — offer path.
# ══════════════════════════════════════════════════════════════════════════════

func test_offer_returns_non_empty_candidate_hexes() -> void:
	var actor := _combatant("actor_0", HexCoordClass.new(0, 0))
	var controller := StrideActionControllerClass.new({})
	var result: Object = controller.enter_selection({"actor_id": actor, "order_index": 0})
	assert_true(result.ok, "should succeed when legal destinations exist")
	assert_true(result.candidate_hexes.size() > 0, "should offer at least one Stride destination")
	assert_eq(result.meta.size(), 0, "offer shape has no meta keys (no chosen_hex yet)")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2 — null actor.
# ══════════════════════════════════════════════════════════════════════════════

func test_null_actor_returns_no_legal_options() -> void:
	var controller := StrideActionControllerClass.new({})
	var result: Object = controller.enter_selection({"order_index": 0})
	assert_false(result.ok)
	assert_eq(result.meta.get("error_code"), "NO_LEGAL_OPTIONS")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3 — zero legal destinations.
# Speed=0 collapses _hex_range's radius-0 loop to an empty result (every
# candidate except the origin itself, and radius=0 has no such candidates).
# ══════════════════════════════════════════════════════════════════════════════

func test_zero_destinations_returns_no_legal_options() -> void:
	var actor := _combatant("actor_0", HexCoordClass.new(0, 0))
	var controller := StrideActionControllerClass.new({"speed": 0})
	var result: Object = controller.enter_selection({"actor_id": actor, "order_index": 0})
	assert_false(result.ok)
	assert_eq(result.meta.get("error_code"), "NO_LEGAL_OPTIONS")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4 — selected_hex in destinations: confirmed selection shape.
# ══════════════════════════════════════════════════════════════════════════════

func test_selected_hex_in_destinations_returns_chosen_hex_in_meta() -> void:
	var actor := _combatant("actor_0", HexCoordClass.new(0, 0))
	var controller := StrideActionControllerClass.new({})
	# First call: get the real list of legal destinations.
	var offer: Object = controller.enter_selection({"actor_id": actor, "order_index": 0})
	assert_true(offer.ok)
	var valid_hex = offer.candidate_hexes[0]
	# Second call: resolve the first destination.
	var result: Object = controller.enter_selection({
		"actor_id": actor,
		"order_index": 0,
		"selected_hex": valid_hex,
	})
	assert_true(result.ok, "a valid in-range hex must be accepted")
	assert_eq(result.meta.get("chosen_hex"), valid_hex,
		"resolved meta.chosen_hex must equal the supplied selected_hex")
	assert_true(result.candidate_hexes.size() > 0,
		"candidate_hexes must remain populated for UI awareness")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5 — selected_hex NOT in destinations: rejected.
# Hex (100,100) is 200 hexes from (0,0), far beyond DEFAULT_SPEED=4.
# ══════════════════════════════════════════════════════════════════════════════

func test_selected_hex_not_in_destinations_returns_no_legal_options() -> void:
	var actor := _combatant("actor_0", HexCoordClass.new(0, 0))
	var controller := StrideActionControllerClass.new({})
	var illegal_hex := HexCoordClass.new(100, 100)
	var result: Object = controller.enter_selection({
		"actor_id": actor,
		"order_index": 0,
		"selected_hex": illegal_hex,
	})
	assert_false(result.ok,
		"a selected_hex outside the computed destinations must be rejected")
	assert_eq(result.meta.get("error_code"), "NO_LEGAL_OPTIONS")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 6 — invalid other_combatants_fn degrades gracefully.
# ══════════════════════════════════════════════════════════════════════════════

func test_invalid_other_combatants_fn_degrades_to_empty_list() -> void:
	# Default _init({}) sets _other_combatants_fn to Callable() which is_valid() == false.
	var actor := _combatant("actor_0", HexCoordClass.new(0, 0))
	var controller := StrideActionControllerClass.new({})
	var result: Object = controller.enter_selection({"actor_id": actor, "order_index": 0})
	assert_true(result.ok,
		"an invalid other_combatants_fn must degrade to [] (treat all hexes as unoccupied), not crash")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 7 — actor real hex_coord never mutated.
# ══════════════════════════════════════════════════════════════════════════════

func test_actor_real_hex_coord_never_mutated_by_enter_selection() -> void:
	var actor := _combatant("actor_0", HexCoordClass.new(0, 0))
	var controller := StrideActionControllerClass.new({})
	var offer: Object = controller.enter_selection({"actor_id": actor, "order_index": 0})
	assert_true(offer.ok)
	var valid_hex = offer.candidate_hexes[0]
	controller.enter_selection({
		"actor_id": actor,
		"order_index": 0,
		"selected_hex": valid_hex,
	})
	assert_eq(actor.hex_coord.q, 0, "actor's real hex_coord.q must be unchanged")
	assert_eq(actor.hex_coord.r, 0, "actor's real hex_coord.r must be unchanged")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 8 — speed override expands destinations.
# speed=1 yields only adjacent hexes; DEFAULT_SPEED=4 yields all hexes within
# 4 steps (strictly more).
# ══════════════════════════════════════════════════════════════════════════════

func test_speed_override_expands_destinations() -> void:
	var actor := _combatant("actor_0", HexCoordClass.new(0, 0))
	var ctrl_slow := StrideActionControllerClass.new({"speed": 1})
	var ctrl_fast := StrideActionControllerClass.new({"speed": 4})
	var slow: Object = ctrl_slow.enter_selection({"actor_id": actor, "order_index": 0})
	var fast: Object = ctrl_fast.enter_selection({"actor_id": actor, "order_index": 0})
	assert_true(slow.ok)
	assert_true(fast.ok)
	assert_true(fast.candidate_hexes.size() > slow.candidate_hexes.size(),
		"higher speed must yield more reachable destinations than lower speed")
