extends GutTest
## tests/unit/domain/combine/test_verb_queue_entry.gd
##
## GUT suite for FEAT-001 (US-001; FR-001): the domain VerbQueueEntry
## value object (core/domain/combine/verb_queue_entry.gd).
##
## Verifies (test_criteria):
##   1. VerbQueueEntry constructs with (queue_id, order_index, verb_id,
##      params), all readable back exactly as passed in.
##   2. It enforces order_index uniqueness WITHIN A QUEUE when validated —
##      via its static has_duplicate_order_index()/
##      validate_unique_order_index() primitives, the sole
##      duplicate-detection authority core/domain/combine/combine_queue.gd's
##      add_entry() also routes through (proven independently by
##      test_combine_queue.gd).

const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: constructs with (queue_id, order_index, verb_id, params)
# ══════════════════════════════════════════════════════════════════════════

func test_constructs_with_all_fields_readable_back() -> void:
	var params: Dictionary = {"hex": Vector2i(1, 0)}
	var entry := VerbQueueEntryClass.new("q1", 0, "STRIDE", params)

	assert_eq(entry.queue_id, "q1")
	assert_eq(entry.order_index, 0)
	assert_eq(entry.verb_id, "STRIDE")
	assert_eq(entry.params, params)


func test_params_defaults_to_empty_dictionary() -> void:
	var entry := VerbQueueEntryClass.new("q1", 1, "STRIKE")
	assert_eq(entry.params, {}, "params must default to an empty Dictionary for a not-yet-targeted entry")


func test_default_valued_params_are_not_shared_across_instances() -> void:
	var a := VerbQueueEntryClass.new("q1", 0, "STRIDE")
	var b := VerbQueueEntryClass.new("q1", 1, "STRIKE")

	a.params["injected"] = true

	assert_false(
		b.params.has("injected"),
		"mutating one entry's default-valued params Dictionary must never affect a sibling entry's params"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: order_index uniqueness within a queue, enforced when
# validated
# ══════════════════════════════════════════════════════════════════════════

func test_has_duplicate_order_index_false_for_distinct_indices() -> void:
	var entries: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]
	assert_false(VerbQueueEntryClass.has_duplicate_order_index(entries))


func test_has_duplicate_order_index_true_for_repeated_index() -> void:
	var entries: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 0, "STRIKE"),
	]
	assert_true(
		VerbQueueEntryClass.has_duplicate_order_index(entries),
		"two entries sharing order_index=0 within the same queue must be flagged as duplicate"
	)


func test_has_duplicate_order_index_false_for_empty_or_single_entry_list() -> void:
	assert_false(VerbQueueEntryClass.has_duplicate_order_index([]))
	assert_false(
		VerbQueueEntryClass.has_duplicate_order_index([VerbQueueEntryClass.new("q1", 0, "STRIDE")])
	)


func test_validate_unique_order_index_returns_empty_string_when_valid() -> void:
	var entries: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]
	assert_eq(VerbQueueEntryClass.validate_unique_order_index(entries), "")


func test_validate_unique_order_index_returns_reason_naming_the_duplicated_index() -> void:
	var entries: Array = [
		VerbQueueEntryClass.new("q1", 3, "STRIDE"),
		VerbQueueEntryClass.new("q1", 3, "STRIDE"),
	]
	var reason: String = VerbQueueEntryClass.validate_unique_order_index(entries)
	assert_ne(reason, "", "a duplicated order_index must produce a non-empty validation reason")
	assert_true(
		reason.contains("3"),
		"the validation reason must name the duplicated order_index (3); got: %s" % reason
	)


func test_repeat_flagged_same_verb_id_across_distinct_order_indices_is_allowed() -> void:
	# 3NF note (design notes' data_model): the SAME verb_id may legally
	# recur across order_index within a Repeat-flagged queue — uniqueness
	# is keyed on order_index alone, never on verb_id.
	var entries: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIKE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]
	assert_false(
		VerbQueueEntryClass.has_duplicate_order_index(entries),
		"the same verb_id at two distinct order_index values is not an order_index duplicate"
	)
