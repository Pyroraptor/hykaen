## core/domain/combine/verb_queue_entry.gd — VerbQueueEntry value object
## (FEAT-001, Iteration O "Combine Selection UX"; US-001, FR-001).
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript RefCounted
## value object — zero Node/Control/CanvasItem inheritance, zero engine
## I/O, zero imports from application/presentation/infrastructure. Mirrors
## the established core/rules/sub_action_queue_entry.gd SubActionQueueEntry
## convention one layer up (this iteration's CombineQueue aggregate, rather
## than a single Combine's hardcoded sub-action pair).
##
## Fields (design notes' data_model, VerbQueueEntry entity — PK
## (queue_id FK, order_index)):
##   queue_id    — String; FK to the owning CombineQueue.queue_id.
##   order_index — int; this entry's position within its queue's
##                 resolution order. Authoritative — resolution walks
##                 entries in order_index order, never insertion order
##                 (mirrors SubActionQueueEntry.sorted()'s established
##                 convention).
##   verb_id     — String; the sub-action's verb identifier (e.g.
##                 "STRIDE"/"STRIKE"), looked up against VerbRegistryPort
##                 by whatever resolver a caller supplies. This file never
##                 hard-references a concrete verb controller.
##   params      — Dictionary; verb-specific parameters (e.g. the chosen
##                 hex/target once resolved during targeting). Empty
##                 Dictionary for a not-yet-targeted entry.
##
## 3NF note (design notes' data_model): params depends on the WHOLE key
## (queue_id, order_index), not on verb_id alone — the same verb_id could
## recur across order_index within a Repeat-flagged queue. Traits
## (repeat/reaction_follow_up/movement/...) are NEVER copied onto this
## entry; they live solely on VerbResource/VerbTraits and are re-read via
## VerbRegistryPort at validation time (DEF-001), so a later trait-rule
## change can never desync from an already-built queue.
##
## order_index uniqueness (test_criteria): a single VerbQueueEntry cannot
## enforce uniqueness against its SIBLINGS on its own (uniqueness is a
## property of a whole entry SET, not one entry in isolation), so this
## class exposes the static validation primitive
## has_duplicate_order_index()/validate_unique_order_index() that both this
## file's own test suite and core/domain/combine/combine_queue.gd's
## add_entry() call — the SAME "one static validator, reused everywhere it
## applies" convention SubActionQueueEntry.sorted() already establishes for
## ordering.
##
## Usage:
##   var entry := VerbQueueEntry.new("q1", 0, "STRIDE", {})
##   entry.verb_id       # "STRIDE"
##   VerbQueueEntry.has_duplicate_order_index([entry, entry2])  # false

class_name VerbQueueEntry
extends RefCounted

## FK to the owning CombineQueue.queue_id.
var queue_id: String = ""

## This entry's position within its queue's resolution order.
var order_index: int = 0

## The sub-action's verb identifier (e.g. "STRIDE"/"STRIKE").
var verb_id: String = ""

## Verb-specific parameters (e.g. the chosen hex/target once resolved).
var params: Dictionary = {}


func _init(
	p_queue_id: String = "",
	p_order_index: int = 0,
	p_verb_id: String = "",
	p_params: Dictionary = {}
) -> void:
	queue_id = p_queue_id
	order_index = p_order_index
	verb_id = p_verb_id
	params = p_params


## has_duplicate_order_index(entries) -> bool — true when two or more
## entries in `entries` (an Array of VerbQueueEntry) share the same
## order_index. The sole duplicate-detection primitive this feature's
## uniqueness invariant is built on (see this file's own doc).
static func has_duplicate_order_index(entries: Array) -> bool:
	return validate_unique_order_index(entries) != ""


## validate_unique_order_index(entries) -> String — "" when every entry in
## `entries` (an Array of VerbQueueEntry) has a distinct order_index;
## otherwise a human-readable reason naming the first duplicated
## order_index encountered. CombineQueue.add_entry() calls this BEFORE
## appending a new entry so order_index uniqueness is enforced at the
## aggregate boundary, not re-derived ad hoc by callers.
static func validate_unique_order_index(entries: Array) -> String:
	var seen: Dictionary = {}
	for entry in entries:
		if seen.has(entry.order_index):
			return "duplicate order_index %d within queue" % entry.order_index
		seen[entry.order_index] = true
	return ""


## has_non_contiguous_order_index(entries) -> bool — true when `entries`
## (an Array of VerbQueueEntry) does NOT form an exact contiguous 0..N-1
## order_index sequence. Sibling primitive to has_duplicate_order_index()
## above, following the SAME "one static validator, reused everywhere it
## applies" convention (FIND-306): uniqueness alone does not rule out
## gapped ({0,99}) or non-zero-start ({-1,3}) index sets, which would
## silently corrupt a sequential order_index-driven resolution loop
## (design notes' security section: "order_index bounds checking").
static func has_non_contiguous_order_index(entries: Array) -> bool:
	return validate_contiguous_order_index(entries) != ""


## validate_contiguous_order_index(entries) -> String — "" when `entries`
## (an Array of VerbQueueEntry) has EXACTLY N entries whose order_index
## values are the set {0, 1, ..., N-1} (N = entries.size()); otherwise a
## human-readable reason naming the first missing index in that expected
## range. An empty `entries` Array is trivially contiguous ("").
##
## This check is independent of (and complementary to)
## validate_unique_order_index() above: a set with duplicates (e.g.
## {0,0}) is also flagged here as non-contiguous (it is missing 1), but
## callers should typically check uniqueness FIRST so a duplicate-index
## rejection reports as DUPLICATE_ORDER_INDEX rather than
## NON_CONTIGUOUS_ORDER_INDEX (see CombineQueue.add_entry()).
static func validate_contiguous_order_index(entries: Array) -> String:
	var expected_count: int = entries.size()
	if expected_count == 0:
		return ""

	var seen: Dictionary = {}
	for entry in entries:
		seen[_order_index_of(entry)] = true

	for expected_index in range(expected_count):
		if not seen.has(expected_index):
			return (
				"order_index sequence must be contiguous 0..%d; missing %d"
				% [expected_count - 1, expected_index]
			)
	return ""


## _order_index_of(entry) -> int — duck-typed order_index accessor: accepts
## either a VerbQueueEntry instance (production shape) or an equivalent
## {"order_index": ...} Dictionary, mirroring
## core/domain/combine/combine_actions.gd's own _verb_id_of() convention
## for accepting either shape. Used only by validate_contiguous_order_index()
## above so it stays safely callable from ValidateCombineQueueUseCase, which
## also accepts Dictionary-shaped queue entries.
static func _order_index_of(entry) -> int:
	if entry is Dictionary:
		return entry.get("order_index", 0)
	return entry.order_index
