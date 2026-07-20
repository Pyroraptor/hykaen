## core/domain/combine/combine_queue.gd — CombineQueue aggregate (FEAT-001,
## Iteration O "Combine Selection UX"; US-001, FR-001).
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript RefCounted
## aggregate root — zero Node/Control/CanvasItem inheritance, zero engine
## I/O, zero imports from application/presentation/infrastructure.
##
## THIS FEATURE'S SCOPE is the SKELETON only (files_to_create's own
## description): the queue_id/actor_id/context/status/entries structure,
## entry addition with the order_index-uniqueness invariant
## (core/domain/combine/verb_queue_entry.gd's static validator), and
## order-preserving read access. The full same-verb/Repeat exclusion rule
## and the reaction-composition minimum-entry rule (design notes'
## combine_actions(queue, candidate_verb) domain service) are a LATER
## feature in this iteration, layered on top of this same aggregate
## without changing its shape.
##
## Fields (design notes' data_model, CombineQueue entity — PK queue_id):
##   queue_id  — String; canonical identifier for this queue instance.
##   actor_id  — String; FK to the owning Actor.
##   context   — Context enum (TURN|REACTION); which combine_actions()
##               composition rule applies (a later feature evaluates this;
##               this feature only carries the value).
##   status    — Status enum (BUILDING|CONFIRMED|EXECUTING|CANCELLED|
##               EXECUTED); the queue's lifecycle state.
##   entries   — Array[VerbQueueEntry]; this queue's sub-actions, NOT
##               guaranteed to be in order_index order at the storage
##               level — sorted_entries() is the sole ordering authority
##               (mirrors core/rules/sub_action_queue_entry.gd's
##               SubActionQueueEntry.sorted() convention).
##
## Relationship (design notes): 1 CombineQueue -> N VerbQueueEntry.
##
## Usage:
##   var queue := CombineQueue.new("q1", "player_0", CombineQueue.Context.TURN)
##   var result := queue.add_entry(VerbQueueEntry.new("q1", 0, "STRIDE"))
##   result.ok            # true
##   queue.sorted_entries()  # [that entry]

class_name CombineQueue
extends RefCounted

const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")

## Which combine_actions() composition rule this queue is built under
## (design notes' data_model: TURN's >=2-entries rule vs REACTION's
## >=2-entries-AND->=1-reaction-verb rule — evaluated by a later feature).
enum Context { TURN, REACTION }

## This queue's lifecycle state.
enum Status { BUILDING, CONFIRMED, EXECUTING, CANCELLED, EXECUTED }

## Canonical identifier for this queue instance.
var queue_id: String = ""

## FK to the owning Actor.
var actor_id: String = ""

## Which combine_actions() composition rule applies to this queue.
var context: int = Context.TURN

## This queue's lifecycle state.
var status: int = Status.BUILDING

## This queue's sub-actions (VerbQueueEntry), NOT guaranteed to be in
## order_index order at the storage level — use sorted_entries().
var entries: Array = []


func _init(
	p_queue_id: String = "",
	p_actor_id: String = "",
	p_context: int = Context.TURN
) -> void:
	queue_id = p_queue_id
	actor_id = p_actor_id
	context = p_context
	status = Status.BUILDING
	entries = []


## add_entry(entry) -> Dictionary {ok, reason} — appends `entry`
## (VerbQueueEntry) to this queue's entries, REJECTING it (no mutation)
## when doing so would violate order_index uniqueness across the
## resulting entry set. Routes through
## VerbQueueEntry.validate_unique_order_index() — the SOLE
## duplicate-order_index check, never re-derived here.
##
## Returns:
##   {"ok": true}                                        — entry appended
##   {"ok": false, "reason": "DUPLICATE_ORDER_INDEX", "error": <msg>}
##                                                         — entry rejected
func add_entry(entry: VerbQueueEntryClass) -> Dictionary:
	var candidate_entries: Array = entries.duplicate()
	candidate_entries.append(entry)
	var validation_error: String = VerbQueueEntryClass.validate_unique_order_index(candidate_entries)
	if validation_error != "":
		return {
			"ok": false,
			"reason": "DUPLICATE_ORDER_INDEX",
			"error": validation_error,
		}
	entries = candidate_entries
	return {"ok": true}


## sorted_entries() -> Array — a NEW Array containing this queue's entries
## ordered by order_index ascending. Never mutates `entries` in place; the
## sole ordering authority any future resolution loop must route through
## (mirrors SubActionQueueEntry.sorted()'s established convention).
func sorted_entries() -> Array:
	var ordered: Array = entries.duplicate()
	ordered.sort_custom(func(a, b): return a.order_index < b.order_index)
	return ordered


## Minimum entries required before the Confirm sentinel may legally be
## offered/accepted for a TURN-context queue (FEAT-003; US-003, FR-002;
## design notes' data_model: "Confirm only offered per context rule ->=2
## entries for TURN"). REACTION context's fuller ">=2 entries AND >=1
## reaction verb" composition rule is a later feature (P1-3) layered on top
## of this same seam — until then REACTION shares this SAME baseline rather
## than silently permitting Confirm at a lower bar.
const MIN_ENTRIES_TO_CONFIRM_TURN: int = 2


## meets_confirm_minimum(context, entry_count) -> bool — true when
## `entry_count` already-picked entries satisfy the context-specific
## Confirm-eligibility minimum. THE single source of truth both
## BuildVerbQueueUseCase (query-time: gating the Confirm sentinel out of
## candidate_options) and ConfirmQueueUseCase (command-time: the
## authoritative confirm-eligibility gate) route through — mirrors
## core/domain/combine/combine_actions.gd's own "one pure function called
## twice, not two implementations" convention for the same-verb/Repeat
## rule.
static func meets_confirm_minimum(context: int, entry_count: int) -> bool:
	match context:
		Context.TURN:
			return entry_count >= MIN_ENTRIES_TO_CONFIRM_TURN
		Context.REACTION:
			return entry_count >= MIN_ENTRIES_TO_CONFIRM_TURN
		_:
			return entry_count >= MIN_ENTRIES_TO_CONFIRM_TURN
