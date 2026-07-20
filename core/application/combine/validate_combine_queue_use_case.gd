## core/application/combine/validate_combine_queue_use_case.gd —
## ValidateCombineQueueUseCase (FEAT-004, Iteration O "Combine Selection
## UX"; US-004; FR-007; DEF-001).
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (core/domain/combine/combine_actions.gd's CombineActions,
## core/domain/combine/verb_traits.gd's VerbTraits) and its own sibling
## application-layer port (VerbRegistryPort) — never an adapter/
## infrastructure/presentation type, and never the engine scene tree.
##
## THE authoritative re-validation gate DEF-001 calls for (design notes'
## security section: "even if a malformed or stale CombineQueue reaches
## execute() ... combine_actions() is re-run against the real VerbResource
## data before any economy is charged"). This use case re-derives each
## queue entry's VerbTraits FRESH from `verb_registry_port` — never trusting
## any traits a caller may have cached/copied earlier — and re-runs
## core/domain/combine/combine_actions.gd's combine_actions() incrementally,
## entry by entry, in order_index order. This is the SAME domain service
## core/application/combine/build_verb_queue_use_case.gd's query-time
## candidate filtering already routes through (design notes' architecture:
## "Having one pure function called twice (not two implementations) is the
## core correctness guarantee for this steel thread") — this use case never
## re-derives its own copy of the same-verb/Repeat rule.
##
## Intended call site: core/controllers/combine_action_controller.gd's
## execute(), invoked as the FIRST statement — before any action-economy/
## Stamina charge — so an illegal combo (e.g. two STRIDEs with no Repeat
## trait) is rejected with ZERO economy spent (test_criteria).
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage:
##   var queue := [VerbQueueEntry.new("q1", 0, "STRIDE"), VerbQueueEntry.new("q1", 1, "STRIDE")]
##   var use_case := ValidateCombineQueueUseCase.new()
##   use_case.execute(queue, actor, CombineQueue.Context.TURN, verb_registry_port)
##   # {"ok": false, "error_code": "VALIDATION_FAILED"} -- duplicate STRIDE, no Repeat trait

class_name ValidateCombineQueueUseCase
extends RefCounted

const CombineActionsClass = preload("res://core/domain/combine/combine_actions.gd")
const VerbTraitsClass = preload("res://core/domain/combine/verb_traits.gd")


## execute(queue_entries, actor, context, verb_registry_port) -> Dictionary{ok, error_code}
##
## queue_entries      — Array of the CONFIRMED queue's already-picked
##                       entries (VerbQueueEntry instances, or equivalent
##                       {"verb_id": ...} Dictionaries — see
##                       core/domain/combine/combine_actions.gd's own
##                       `queue` contract for the accepted shapes).
## actor              — the combatant executing the Combine; forwarded
##                       verbatim to `verb_registry_port.get_available_verbs()`.
##                       A null actor degrades safely (VALIDATION_FAILED)
##                       rather than crashing.
## context            — one of core/domain/combine/combine_queue.gd's
##                       CombineQueue.Context enum members (TURN|REACTION),
##                       forwarded verbatim to `verb_registry_port`.
## verb_registry_port — a VerbRegistryPort implementation (or a duck-typed
##                       fake exposing the same get_available_verbs(actor,
##                       context) -> Array[VerbResource] contract) — the
##                       SOLE source this use case re-reads VerbTraits from.
##                       A null port degrades safely (VALIDATION_FAILED)
##                       rather than crashing.
##
## Returns:
##   {"ok": true, "error_code": ""} — every entry, re-checked incrementally
##       in order_index order against FRESHLY-derived VerbTraits, is legal.
##   {"ok": false, "error_code": "VALIDATION_FAILED"} — the first entry whose
##       re-derived candidate combine_actions() rejects (e.g. a duplicate
##       verb whose current VerbResource does not carry the Repeat trait),
##       OR `actor`/`verb_registry_port` was null.
func execute(queue_entries: Array, actor, context: int, verb_registry_port) -> Dictionary:
	if actor == null or verb_registry_port == null:
		return {"ok": false, "error_code": "VALIDATION_FAILED"}

	var traits_by_verb_id: Dictionary = {}
	var pool: Array = verb_registry_port.get_available_verbs(actor, context)
	for verb_resource in pool:
		if verb_resource == null:
			continue
		traits_by_verb_id[verb_resource.verb_id] = VerbTraitsClass.from_verb_resource(verb_resource)

	var validated_so_far: Array = []
	for entry in _sorted_by_order_index(queue_entries):
		var verb_id: String = _verb_id_of(entry)
		var candidate: Dictionary = {
			"verb_id": verb_id,
			"traits": traits_by_verb_id.get(verb_id),
		}
		var verdict: Dictionary = CombineActionsClass.combine_actions(validated_so_far, candidate)
		if not verdict.get("legal", false):
			return {"ok": false, "error_code": "VALIDATION_FAILED"}
		validated_so_far.append(entry)

	return {"ok": true, "error_code": ""}


## _verb_id_of(entry) -> String — duck-typed verb_id accessor mirroring
## core/domain/combine/combine_actions.gd's own `_verb_id_of()` convention,
## so this use case accepts the SAME entry shapes (VerbQueueEntry or an
## equivalent {"verb_id": ...} Dictionary) that domain service does.
func _verb_id_of(entry) -> String:
	if entry is Dictionary:
		return entry.get("verb_id", "")
	return entry.verb_id


## _sorted_by_order_index(entries) -> Array — a NEW Array of `entries`
## ordered by order_index ascending, mirroring
## core/domain/combine/combine_queue.gd's CombineQueue.sorted_entries()
## convention: order_index, never insertion/array position, is
## authoritative for resolution order. Dictionary-shaped entries (which may
## omit "order_index") sort as 0, matching VerbQueueEntry's own default.
func _sorted_by_order_index(entries: Array) -> Array:
	var ordered: Array = entries.duplicate()
	ordered.sort_custom(func(a, b): return _order_index_of(a) < _order_index_of(b))
	return ordered


## _order_index_of(entry) -> int — duck-typed order_index accessor, mirrors
## `_verb_id_of()` above.
func _order_index_of(entry) -> int:
	if entry is Dictionary:
		return entry.get("order_index", 0)
	return entry.order_index
