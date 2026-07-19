extends GutTest
## tests/unit/test_sub_action_queue_resolution.gd — FEAT-005 (US-005;
## ADR-005/FR-010)
##
## Iteration N (Combinations): proves the GENERALIZED N-length sub-action
## queue structure (core/rules/sub_action_queue_entry.gd's
## SubActionQueueEntry) and its generic resolution loop
## (CombineActionController.resolve_sub_action_queue()) treat "N" as a real
## variable, not a hard-coded 2:
##   - the v0 2-entry Charge queue (STRIDE, STRIKE) resolves in order via
##     the generic loop.
##   - a SYNTHETIC N=3 queue of three arbitrary verb_ids resolves in order
##     using the SAME loop, with no special-casing for N=2 vs N=3.
##   - order_index — not insertion/array position — is what the loop
##     honors when deciding resolution order.
##
## Mirrors tests/unit/test_combine_stamina_decrement.gd's minimal
## "real fake session, no MainScene.tscn boot required" convention.

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const SubActionQueueEntryClass    = preload("res://core/rules/sub_action_queue_entry.gd")
const RoundSessionHolderClass      = preload("res://infrastructure/round_session_holder.gd")


func _controller():
	return CombineActionControllerClass.new({"session_holder": RoundSessionHolderClass.new()})


## _recording_resolver(resolved_order) -> Callable — a resolver that always
## reports ok=true and appends the resolved entry's verb_id to
## `resolved_order` (a caller-owned Array), so a test can observe the
## ACTUAL order entries were visited in, not merely the loop's own summary.
func _recording_resolver(resolved_order: Array) -> Callable:
	return func(entry):
		resolved_order.append(entry.verb_id)
		return {"ok": true}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — the v0 2-entry Charge queue (STRIDE, STRIKE) resolves in
# order via the generic loop.
# ══════════════════════════════════════════════════════════════════════════

func test_charge_queue_resolves_stride_then_strike_in_order() -> void:
	var controller = _controller()
	var queue: Array = controller.build_charge_queue()
	var resolved_order: Array = []

	var result: Dictionary = controller.resolve_sub_action_queue(queue, _recording_resolver(resolved_order))

	assert_true(result.get("ok", false), "a fully-resolving Charge queue must report ok=true")
	assert_eq(resolved_order, ["STRIDE", "STRIKE"], "Charge's 2-entry queue must resolve STRIDE then STRIKE, in that order")
	assert_eq(result.get("resolved_verb_ids", []), ["STRIDE", "STRIKE"], "the loop's own summary must match the observed resolution order")


func test_charge_queue_has_exactly_two_entries_with_expected_order_indices() -> void:
	var controller = _controller()
	var queue: Array = controller.build_charge_queue()

	assert_eq(queue.size(), 2, "v0 Charge is a 2-entry queue")
	assert_eq(queue[0].verb_id, "STRIDE")
	assert_eq(queue[0].order_index, 0)
	assert_eq(queue[1].verb_id, "STRIKE")
	assert_eq(queue[1].order_index, 1)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — a synthetic N=3 queue of arbitrary verb_ids resolves in
# order using the SAME generic loop, with no special-casing.
# ══════════════════════════════════════════════════════════════════════════

func test_synthetic_n3_queue_resolves_in_order_with_no_special_casing() -> void:
	var controller = _controller()
	var queue: Array = [
		SubActionQueueEntryClass.new(0, "ALPHA"),
		SubActionQueueEntryClass.new(1, "BETA"),
		SubActionQueueEntryClass.new(2, "GAMMA"),
	]
	var resolved_order: Array = []

	var result: Dictionary = controller.resolve_sub_action_queue(queue, _recording_resolver(resolved_order))

	assert_true(result.get("ok", false), "a fully-resolving N=3 queue must report ok=true, exactly like N=2")
	assert_eq(resolved_order, ["ALPHA", "BETA", "GAMMA"], "an arbitrary N=3 queue must resolve via the same generic loop as N=2, in order_index order")
	assert_eq(result.get("resolved_verb_ids", []), ["ALPHA", "BETA", "GAMMA"])


func test_synthetic_n1_and_n4_queues_also_resolve_via_the_same_loop() -> void:
	# Further proof the loop makes no length assumption at all: N=1 and N=4
	# both resolve correctly through the identical resolve_sub_action_queue()
	# call used for N=2 and N=3 above.
	var controller = _controller()

	var n1_queue: Array = [SubActionQueueEntryClass.new(0, "SOLO")]
	var n1_order: Array = []
	var n1_result: Dictionary = controller.resolve_sub_action_queue(n1_queue, _recording_resolver(n1_order))
	assert_true(n1_result.get("ok", false))
	assert_eq(n1_order, ["SOLO"])

	var n4_queue: Array = [
		SubActionQueueEntryClass.new(0, "W"),
		SubActionQueueEntryClass.new(1, "X"),
		SubActionQueueEntryClass.new(2, "Y"),
		SubActionQueueEntryClass.new(3, "Z"),
	]
	var n4_order: Array = []
	var n4_result: Dictionary = controller.resolve_sub_action_queue(n4_queue, _recording_resolver(n4_order))
	assert_true(n4_result.get("ok", false))
	assert_eq(n4_order, ["W", "X", "Y", "Z"])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — order_index, not insertion/array position, is what the
# loop honors when deciding resolution order.
# ══════════════════════════════════════════════════════════════════════════

func test_order_index_is_honored_even_when_entries_are_inserted_out_of_order() -> void:
	var controller = _controller()
	var queue: Array = [
		SubActionQueueEntryClass.new(2, "THIRD"),
		SubActionQueueEntryClass.new(0, "FIRST"),
		SubActionQueueEntryClass.new(1, "SECOND"),
	]
	var resolved_order: Array = []

	var result: Dictionary = controller.resolve_sub_action_queue(queue, _recording_resolver(resolved_order))

	assert_true(result.get("ok", false))
	assert_eq(resolved_order, ["FIRST", "SECOND", "THIRD"], "resolution order must follow order_index, not the entries' insertion/array position")


func test_sub_action_queue_entry_sorted_orders_by_index_without_mutating_the_original() -> void:
	var queue: Array = [
		SubActionQueueEntryClass.new(1, "SECOND"),
		SubActionQueueEntryClass.new(0, "FIRST"),
	]

	var ordered: Array = SubActionQueueEntryClass.sorted(queue)

	assert_eq(ordered[0].verb_id, "FIRST")
	assert_eq(ordered[1].verb_id, "SECOND")
	assert_eq(queue[0].verb_id, "SECOND", "sorted() must not mutate the caller's original queue array")
	assert_eq(queue[1].verb_id, "FIRST", "sorted() must not mutate the caller's original queue array")


func test_sub_action_queue_entry_preserves_order_index_verb_id_and_targeting_payload() -> void:
	var entry := SubActionQueueEntryClass.new(4, "STRIKE", {"target_id": "enemy_0"})

	assert_eq(entry.order_index, 4)
	assert_eq(entry.verb_id, "STRIKE")
	assert_eq(entry.targeting_payload, {"target_id": "enemy_0"})


func test_sub_action_queue_entry_targeting_payload_defaults_to_null() -> void:
	var entry := SubActionQueueEntryClass.new(0, "STRIDE")

	assert_null(entry.targeting_payload, "targeting_payload must default to null when not supplied at construction")


# ══════════════════════════════════════════════════════════════════════════
# Failure handling — the loop stops at the first failing entry and reports
# only the entries resolved before it, never resolving beyond a failure.
# ══════════════════════════════════════════════════════════════════════════

func test_loop_stops_at_first_failing_entry_and_never_reaches_later_entries() -> void:
	var controller = _controller()
	var queue: Array = [
		SubActionQueueEntryClass.new(0, "FIRST"),
		SubActionQueueEntryClass.new(1, "SECOND"),
		SubActionQueueEntryClass.new(2, "THIRD"),
	]
	var resolved_order: Array = []
	var resolver := func(entry):
		if entry.verb_id == "SECOND":
			return {"ok": false, "reason": "SYNTHETIC_FAILURE"}
		resolved_order.append(entry.verb_id)
		return {"ok": true}

	var result: Dictionary = controller.resolve_sub_action_queue(queue, resolver)

	assert_false(result.get("ok", true), "the loop must report ok=false once any entry fails")
	assert_eq(result.get("resolved_verb_ids", []), ["FIRST"], "only entries resolved BEFORE the failing entry are reported")
	assert_eq(resolved_order, ["FIRST"], "THIRD must never be reached once SECOND fails")
	assert_eq(result.get("reason"), "SYNTHETIC_FAILURE", "the failing entry's own reason must be surfaced")
