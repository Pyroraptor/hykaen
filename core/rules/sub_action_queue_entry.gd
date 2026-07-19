## core/rules/sub_action_queue_entry.gd — SubActionQueueEntry value object
## (FEAT-005; US-005; ADR-005/FR-010, Iteration N Combinations).
##
## Domain layer (ADR-001): pure GDScript RefCounted value object — zero
## Node/Control/CanvasItem inheritance, zero engine I/O, zero framework
## imports. Carries the data a single queued sub-action needs to be
## resolved as part of a Combine's N-length sub-action queue:
##
##   order_index       — int; this entry's position in the queue's
##                        resolution order. Authoritative: resolution walks
##                        entries in ORDER_INDEX order, never insertion
##                        order (see sorted() below and
##                        presentation/combine_action_controller.gd's
##                        resolve_sub_action_queue(), which sorts by this
##                        field before iterating).
##   verb_id           — String; the sub-action's verb identifier (e.g.
##                        "STRIDE"/"STRIKE"), looked up against the
##                        data-driven VERB_TABLE registry by whatever
##                        resolver a caller supplies. This file never
##                        hard-references a concrete verb controller.
##   targeting_payload — Variant; the sub-action's target data (a hex for
##                        Stride, a target combatant id for Strike, ...).
##                        Populated during enter_selection(); may be null
##                        for a not-yet-targeted entry (e.g. the synthetic
##                        entries this feature's own tests construct).
##
## Generalizes to ANY N — nothing here (or in the resolution loop that
## consumes a list of these) assumes exactly two entries. The v0 Charge
## queue (build_charge_queue() below) happens to author exactly two
## (STRIDE, STRIKE), but the structure and its resolution loop treat N=2
## as just one instance of the general case, proven by this feature's own
## synthetic N=3 test (tests/unit/test_sub_action_queue_resolution.gd).
class_name SubActionQueueEntry
extends RefCounted

var order_index: int
var verb_id: String
var targeting_payload


func _init(p_order_index: int, p_verb_id: String, p_targeting_payload = null) -> void:
	order_index = p_order_index
	verb_id = p_verb_id
	targeting_payload = p_targeting_payload


## sorted(queue) -> Array — returns a NEW Array containing `queue`'s entries
## ordered by order_index ascending. Never mutates the Array passed in, so
## a caller's own queue (e.g. one built out of order, or shuffled) is left
## untouched; only the returned copy is ordered. This is the SOLE ordering
## authority every resolution loop (e.g.
## CombineActionController.resolve_sub_action_queue()) must route through,
## so order_index — not insertion/array position — is what determines
## resolution order.
static func sorted(queue: Array) -> Array:
	var ordered: Array = queue.duplicate()
	ordered.sort_custom(func(a, b): return a.order_index < b.order_index)
	return ordered


## build_charge_queue() -> Array[SubActionQueueEntry] — the v0 2-entry
## Charge queue (Stride then Strike), authored ON the generalized N-length
## structure rather than as a bespoke fixed-pair shape. Iteration N's
## follow-on features (real sub-controller resolution via the verb
## registry) build on top of exactly this queue shape without changing it.
static func build_charge_queue() -> Array:
	return [
		SubActionQueueEntry.new(0, "STRIDE"),
		SubActionQueueEntry.new(1, "STRIKE"),
	]
