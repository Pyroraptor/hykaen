extends GutTest
## tests/unit/domain/combine/test_combine_queue.gd
##
## GUT suite for FEAT-001 (US-001; FR-001): the domain CombineQueue
## aggregate skeleton (core/domain/combine/combine_queue.gd).
##
## Verifies:
##   1. CombineQueue constructs with queue_id/actor_id/context, defaults to
##      Status.BUILDING and an empty entries Array.
##   2. add_entry() appends a VerbQueueEntry and returns {ok: true}.
##   3. add_entry() REJECTS an entry whose order_index duplicates an
##      existing entry's — {ok: false, reason: "DUPLICATE_ORDER_INDEX"} —
##      via VerbQueueEntry's own static validator (no mutation on
##      rejection).
##   4. sorted_entries() returns entries in order_index order regardless of
##      insertion order, and never mutates the queue's own `entries` Array.

const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: construction defaults
# ══════════════════════════════════════════════════════════════════════════

func test_constructs_with_queue_id_actor_id_context() -> void:
	var q := CombineQueueClass.new("q1", "player_0", CombineQueueClass.Context.TURN)

	assert_eq(q.queue_id, "q1")
	assert_eq(q.actor_id, "player_0")
	assert_eq(q.context, CombineQueueClass.Context.TURN)


func test_new_queue_defaults_to_building_status_and_empty_entries() -> void:
	var q := CombineQueueClass.new("q1", "player_0")

	assert_eq(q.status, CombineQueueClass.Status.BUILDING)
	assert_eq(q.entries, [])


func test_context_defaults_to_turn() -> void:
	var q := CombineQueueClass.new("q1", "player_0")
	assert_eq(q.context, CombineQueueClass.Context.TURN)


func test_reaction_context_is_constructible() -> void:
	var q := CombineQueueClass.new("q1", "player_0", CombineQueueClass.Context.REACTION)
	assert_eq(q.context, CombineQueueClass.Context.REACTION)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: add_entry() appends and returns {ok: true}
# ══════════════════════════════════════════════════════════════════════════

func test_add_entry_appends_and_returns_ok_true() -> void:
	var q := CombineQueueClass.new("q1", "player_0")
	var entry := VerbQueueEntryClass.new("q1", 0, "STRIDE")

	var result: Dictionary = q.add_entry(entry)

	assert_true(result.get("ok", false), "add_entry() of a fresh order_index must succeed")
	assert_eq(q.entries.size(), 1)
	assert_eq(q.entries[0], entry)


func test_add_entry_accepts_multiple_distinct_order_indices() -> void:
	var q := CombineQueueClass.new("q1", "player_0")

	var r0: Dictionary = q.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))
	var r1: Dictionary = q.add_entry(VerbQueueEntryClass.new("q1", 1, "STRIKE"))

	assert_true(r0.get("ok", false))
	assert_true(r1.get("ok", false))
	assert_eq(q.entries.size(), 2)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: add_entry() rejects a duplicate order_index, no mutation
# ══════════════════════════════════════════════════════════════════════════

func test_add_entry_rejects_duplicate_order_index() -> void:
	var q := CombineQueueClass.new("q1", "player_0")
	q.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))

	var result: Dictionary = q.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIKE"))

	assert_false(result.get("ok", true), "add_entry() must reject a duplicate order_index")
	assert_eq(result.get("reason", ""), "DUPLICATE_ORDER_INDEX")


func test_add_entry_rejection_does_not_mutate_the_queue() -> void:
	var q := CombineQueueClass.new("q1", "player_0")
	q.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))

	q.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIKE"))

	assert_eq(q.entries.size(), 1, "a rejected add_entry() call must leave the queue's entries unchanged")
	assert_eq(q.entries[0].verb_id, "STRIDE", "the original entry must survive a rejected duplicate add")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: sorted_entries() orders by order_index, never mutates
# ══════════════════════════════════════════════════════════════════════════

func test_sorted_entries_orders_by_order_index_regardless_of_insertion_order() -> void:
	var q := CombineQueueClass.new("q1", "player_0")
	var second := VerbQueueEntryClass.new("q1", 1, "STRIKE")
	var first := VerbQueueEntryClass.new("q1", 0, "STRIDE")

	# Insert out of order_index order.
	q.entries = [second, first]

	var ordered: Array = q.sorted_entries()

	assert_eq(ordered[0], first, "sorted_entries()[0] must be the order_index=0 entry")
	assert_eq(ordered[1], second, "sorted_entries()[1] must be the order_index=1 entry")


func test_sorted_entries_does_not_mutate_the_queues_own_entries_array() -> void:
	var q := CombineQueueClass.new("q1", "player_0")
	var second := VerbQueueEntryClass.new("q1", 1, "STRIKE")
	var first := VerbQueueEntryClass.new("q1", 0, "STRIDE")
	q.entries = [second, first]

	q.sorted_entries()

	assert_eq(q.entries[0], second, "sorted_entries() must never mutate the queue's own entries Array in place")
	assert_eq(q.entries[1], first)


# ══════════════════════════════════════════════════════════════════════════
# FIND-306: add_entry() rejects a non-contiguous order_index sequence
# ══════════════════════════════════════════════════════════════════════════

func test_add_entry_rejects_gapped_order_index_0_and_99() -> void:
	var q := CombineQueueClass.new("q1", "player_0")
	q.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))

	var result: Dictionary = q.add_entry(VerbQueueEntryClass.new("q1", 99, "STRIKE"))

	assert_false(result.get("ok", true), "add_entry() must reject a gapped order_index sequence {0, 99}")
	assert_eq(result.get("reason", ""), "NON_CONTIGUOUS_ORDER_INDEX")


func test_add_entry_rejects_gapped_order_index_does_not_mutate_the_queue() -> void:
	var q := CombineQueueClass.new("q1", "player_0")
	q.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))

	q.add_entry(VerbQueueEntryClass.new("q1", 99, "STRIKE"))

	assert_eq(q.entries.size(), 1, "a rejected non-contiguous add_entry() call must leave the queue's entries unchanged")


func test_add_entry_rejects_order_index_not_starting_at_zero() -> void:
	var q := CombineQueueClass.new("q1", "player_0")
	q.add_entry(VerbQueueEntryClass.new("q1", -1, "STRIDE"))

	var result: Dictionary = q.add_entry(VerbQueueEntryClass.new("q1", 3, "STRIKE"))

	assert_false(result.get("ok", true), "add_entry() must reject an order_index sequence {-1, 3} that does not start at 0")
	assert_eq(result.get("reason", ""), "NON_CONTIGUOUS_ORDER_INDEX")


func test_add_entry_accepts_contiguous_two_entry_sequence() -> void:
	var q := CombineQueueClass.new("q1", "player_0")

	var r0: Dictionary = q.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))
	var r1: Dictionary = q.add_entry(VerbQueueEntryClass.new("q1", 1, "STRIKE"))

	assert_true(r0.get("ok", false), "{0} must be accepted as a contiguous sequence")
	assert_true(r1.get("ok", false), "{0,1} must be accepted as a contiguous sequence")
	assert_eq(q.entries.size(), 2)


func test_add_entry_accepts_contiguous_three_entry_sequence() -> void:
	var q := CombineQueueClass.new("q1", "player_0")

	var r0: Dictionary = q.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))
	var r1: Dictionary = q.add_entry(VerbQueueEntryClass.new("q1", 1, "STRIKE"))
	var r2: Dictionary = q.add_entry(VerbQueueEntryClass.new("q1", 2, "STRIDE"))

	assert_true(r0.get("ok", false), "{0} must be accepted as a contiguous sequence")
	assert_true(r1.get("ok", false), "{0,1} must be accepted as a contiguous sequence")
	assert_true(r2.get("ok", false), "{0,1,2} must be accepted as a contiguous sequence")
	assert_eq(q.entries.size(), 3)
