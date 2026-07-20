extends GutTest
## tests/unit/domain/combine/test_combine_actions.gd
##
## GUT suite for FEAT-002 (Iteration O "Combine Selection UX"; US-002;
## FR-001): the domain CombineActions.combine_actions(queue, candidate)
## service (core/domain/combine/combine_actions.gd) — the SOLE source of
## truth for the same-verb/Repeat exclusion rule.
##
## Verifies:
##   1. combine_actions() on an empty queue (adding STRIDE), then again on
##      the resulting queue (adding STRIKE), both report legal=true — two
##      DIFFERENT verbs never require the Repeat trait.
##   2. combine_actions() rejects re-adding STRIDE to a queue that already
##      contains STRIDE when the candidate's VerbTraits.repeat is false.
##   3. combine_actions() accepts re-adding STRIDE to a queue that already
##      contains STRIDE when the candidate's VerbTraits.repeat is true.

const CombineActionsClass = preload("res://core/domain/combine/combine_actions.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const VerbTraitsClass = preload("res://core/domain/combine/verb_traits.gd")


func _candidate(verb_id: String, repeat: bool = false) -> Dictionary:
	return {"verb_id": verb_id, "traits": VerbTraitsClass.new(repeat)}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — different verbs are always legal; Repeat is never required.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_then_strike_on_different_verbs_are_both_legal() -> void:
	var empty_queue: Array = []
	var stride_verdict: Dictionary = CombineActionsClass.combine_actions(empty_queue, _candidate("STRIDE"))
	assert_true(stride_verdict.get("legal", false), "STRIDE must be legal to add to an empty queue")

	var queue_with_stride: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]
	var strike_verdict: Dictionary = CombineActionsClass.combine_actions(queue_with_stride, _candidate("STRIKE"))
	assert_true(strike_verdict.get("legal", false), "STRIKE must be legal to add after STRIDE -- different verbs never require Repeat")


func test_empty_queue_is_never_illegal() -> void:
	var verdict: Dictionary = CombineActionsClass.combine_actions([], _candidate("STRIKE"))
	assert_true(verdict.get("legal", false))
	assert_eq(verdict.get("reason"), "")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — same verb without Repeat is illegal.
# ══════════════════════════════════════════════════════════════════════════

func test_duplicate_stride_without_repeat_is_illegal() -> void:
	var queue_with_stride: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var verdict: Dictionary = CombineActionsClass.combine_actions(queue_with_stride, _candidate("STRIDE", false))

	assert_false(verdict.get("legal", true), "a second STRIDE without Repeat must be illegal")
	assert_eq(verdict.get("reason"), "DUPLICATE_VERB_WITHOUT_REPEAT")


func test_duplicate_stride_with_no_traits_supplied_defaults_to_illegal() -> void:
	var queue_with_stride: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var verdict: Dictionary = CombineActionsClass.combine_actions(queue_with_stride, {"verb_id": "STRIDE"})

	assert_false(verdict.get("legal", true), "a candidate with no traits supplied must default to no-Repeat (illegal on duplicate)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — same verb WITH Repeat is legal.
# ══════════════════════════════════════════════════════════════════════════

func test_duplicate_stride_with_repeat_is_legal() -> void:
	var queue_with_stride: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var verdict: Dictionary = CombineActionsClass.combine_actions(queue_with_stride, _candidate("STRIDE", true))

	assert_true(verdict.get("legal", false), "a second STRIDE WITH Repeat must be legal")
	assert_eq(verdict.get("reason"), "")


func test_accepts_dictionary_shaped_queue_entries_too() -> void:
	# combine_actions() must accept either a real VerbQueueEntry OR an
	# equivalent {"verb_id": ...} Dictionary in `queue` (see this file's own
	# `_verb_id_of()` doc) -- a lighter-weight shape some callers/tests may
	# prefer over constructing a full VerbQueueEntry.
	var queue_with_stride: Array = [{"verb_id": "STRIDE"}]

	var verdict: Dictionary = CombineActionsClass.combine_actions(queue_with_stride, _candidate("STRIDE", false))

	assert_false(verdict.get("legal", true), "Dictionary-shaped queue entries must be checked identically to VerbQueueEntry instances")
