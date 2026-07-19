extends GutTest
## tests/unit/test_combine_enter_selection.gd — FEAT-006 (US-006; FR-005)
##
## Iteration N (Combinations): CombineActionController.enter_selection()
## is the player-facing entry point for choosing the ordered pair of
## sub-actions to fuse. It enforces the different-verb OR
## same-verb-with-Repeat rule by routing through the EXISTING
## core/rules/action_economy.gd ActionEconomy.combine_actions() validation
## -- no parallel/duplicate rule is authored in the controller or the test.
##
## test_criteria covered:
##   1. enter_selection() with an identical non-Repeat verb pair returns
##      SelectionResult.ok==false, reason IDENTICAL_NON_REPEAT_VERBS.
##   2. enter_selection() with an identical Repeat-trait verb pair returns
##      ok==true.
##   3. enter_selection() with two different verbs (STRIDE, STRIKE) returns
##      ok==true, subject to availability rules (Dazed/Stamina).
##   4. The returned SelectionResult.queue matches the FEAT-005 queue
##      structure (order_index/verb_id/targeting_payload shape, and for the
##      default Charge pair, the SAME content build_charge_queue() produces).

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const RoundSessionHolderClass      = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")


class FakeSession:
	var _actor

	func _init(actor) -> void:
		_actor = actor

	func current_actor():
		return {} if _actor == null else {"combatant_id": _actor.combatant_id}

	func current_actor_entity():
		return _actor

	func current_action_economy():
		return null


func _deps(actor = null) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	if actor != null:
		holder.set_current(FakeSession.new(actor))
	return {"session_holder": holder}


func _make_actor(stamina: int = 3, dazed: bool = false) -> CombatantClass:
	var actor := CombatantClass.new("player_0", "Titus", "Player", HexCoordClass.new(0, 0))
	actor.stamina = stamina
	if dazed:
		actor.add_condition("Dazed")
	return actor


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — identical, non-Repeat verb pair is rejected with reason
# IDENTICAL_NON_REPEAT_VERBS.
# ══════════════════════════════════════════════════════════════════════════

func test_identical_non_repeat_verb_pair_returns_ok_false_reason_identical_non_repeat_verbs() -> void:
	var actor := _make_actor()
	var controller := CombineActionControllerClass.new(_deps(actor))
	var pair: Array = [
		{"verb_id": "STRIKE", "traits": []},
		{"verb_id": "STRIKE", "traits": []},
	]

	var result: Dictionary = controller.enter_selection(pair)

	assert_false(result.get("ok", true), "an identical, non-Repeat verb pair must be rejected")
	assert_eq(
		result.get("reason"), "IDENTICAL_NON_REPEAT_VERBS",
		"an identical, non-Repeat verb pair must report reason=IDENTICAL_NON_REPEAT_VERBS"
	)


func test_identical_non_repeat_verb_pair_has_no_queue() -> void:
	var actor := _make_actor()
	var controller := CombineActionControllerClass.new(_deps(actor))
	var pair: Array = [
		{"verb_id": "STRIKE", "traits": []},
		{"verb_id": "STRIKE", "traits": []},
	]

	var result: Dictionary = controller.enter_selection(pair)

	assert_false(result.has("queue"), "a rejected selection must not carry a queue")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — identical, Repeat-trait verb pair is accepted.
# ══════════════════════════════════════════════════════════════════════════

func test_identical_repeat_trait_verb_pair_returns_ok_true() -> void:
	var actor := _make_actor()
	var controller := CombineActionControllerClass.new(_deps(actor))
	var pair: Array = [
		{"verb_id": "STRIKE", "traits": ["Repeat"]},
		{"verb_id": "STRIKE", "traits": ["Repeat"]},
	]

	var result: Dictionary = controller.enter_selection(pair)

	assert_true(result.get("ok", false), "an identical, Repeat-trait verb pair must be accepted")


func test_identical_repeat_trait_verb_pair_queue_has_two_strike_entries_in_order() -> void:
	var actor := _make_actor()
	var controller := CombineActionControllerClass.new(_deps(actor))
	var pair: Array = [
		{"verb_id": "STRIKE", "traits": ["Repeat"]},
		{"verb_id": "STRIKE", "traits": ["Repeat"]},
	]

	var result: Dictionary = controller.enter_selection(pair)
	var queue: Array = result.get("queue", [])

	assert_eq(queue.size(), 2, "the accepted identical-Repeat pair must produce a 2-entry queue")
	assert_eq(queue[0].verb_id, "STRIKE")
	assert_eq(queue[0].order_index, 0)
	assert_eq(queue[1].verb_id, "STRIKE")
	assert_eq(queue[1].order_index, 1)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — two different verbs (STRIDE, STRIKE) are accepted, subject
# to availability rules (Dazed / insufficient Stamina still reject).
# ══════════════════════════════════════════════════════════════════════════

func test_different_verbs_stride_strike_returns_ok_true_by_default() -> void:
	var actor := _make_actor()
	var controller := CombineActionControllerClass.new(_deps(actor))

	var result: Dictionary = controller.enter_selection()

	assert_true(result.get("ok", false), "the default (STRIDE, STRIKE) pair must be accepted -- different verbs need no Repeat trait")


func test_different_verbs_explicit_pair_returns_ok_true() -> void:
	var actor := _make_actor()
	var controller := CombineActionControllerClass.new(_deps(actor))
	var pair: Array = [
		{"verb_id": "STRIDE", "traits": []},
		{"verb_id": "STRIKE", "traits": []},
	]

	var result: Dictionary = controller.enter_selection(pair)

	assert_true(result.get("ok", false), "an explicit (STRIDE, STRIKE) pair must be accepted without a Repeat trait")


func test_different_verbs_rejected_when_dazed() -> void:
	var actor := _make_actor(3, true)
	var controller := CombineActionControllerClass.new(_deps(actor))

	var result: Dictionary = controller.enter_selection()

	assert_false(result.get("ok", true), "a Dazed actor must not be able to select a Combine pair")
	assert_eq(result.get("reason"), "DAZED")


func test_different_verbs_rejected_when_insufficient_stamina() -> void:
	var actor := _make_actor(0, false)
	var controller := CombineActionControllerClass.new(_deps(actor))

	var result: Dictionary = controller.enter_selection()

	assert_false(result.get("ok", true), "an actor with 0 Stamina must not be able to select a Combine pair")
	assert_eq(result.get("reason"), "INSUFFICIENT_STAMINA")


func test_enter_selection_false_with_no_live_actor() -> void:
	var controller := CombineActionControllerClass.new(_deps())

	var result: Dictionary = controller.enter_selection()

	assert_false(result.get("ok", true), "enter_selection() with no live actor must fail closed, not crash")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — the returned queue matches the FEAT-005 queue structure; for
# the default Charge pair it matches build_charge_queue()'s own output.
# ══════════════════════════════════════════════════════════════════════════

func test_default_pair_queue_matches_build_charge_queue_structure() -> void:
	var actor := _make_actor()
	var controller := CombineActionControllerClass.new(_deps(actor))

	var result: Dictionary = controller.enter_selection()
	var queue: Array = result.get("queue", [])
	var expected: Array = controller.build_charge_queue()

	assert_eq(queue.size(), expected.size(), "the default pair's queue must have the same length as build_charge_queue()")
	for i in range(expected.size()):
		assert_eq(queue[i].verb_id, expected[i].verb_id, "entry %d verb_id must match build_charge_queue()" % i)
		assert_eq(queue[i].order_index, expected[i].order_index, "entry %d order_index must match build_charge_queue()" % i)
		assert_eq(queue[i].targeting_payload, expected[i].targeting_payload, "entry %d targeting_payload must match build_charge_queue()" % i)


func test_returned_queue_entries_are_sub_action_queue_entry_instances_with_null_targeting_payload() -> void:
	var actor := _make_actor()
	var controller := CombineActionControllerClass.new(_deps(actor))

	var result: Dictionary = controller.enter_selection()
	var queue: Array = result.get("queue", [])

	for entry in queue:
		assert_null(entry.targeting_payload, "targeting_payload must still be null -- populated later by each sub-action's own targeting pass")


func test_returned_queue_resolves_via_the_shared_resolve_sub_action_queue_loop() -> void:
	# Regression: the FEAT-006 queue must be consumable by the FEAT-005
	# generic resolution loop with zero special-casing.
	var actor := _make_actor()
	var controller := CombineActionControllerClass.new(_deps(actor))

	var result: Dictionary = controller.enter_selection()
	var queue: Array = result.get("queue", [])
	var resolved_order: Array = []
	var resolver := func(entry):
		resolved_order.append(entry.verb_id)
		return {"ok": true}

	var resolution: Dictionary = await controller.resolve_sub_action_queue(queue, resolver)

	assert_true(resolution.get("ok", false))
	assert_eq(resolved_order, ["STRIDE", "STRIKE"])
