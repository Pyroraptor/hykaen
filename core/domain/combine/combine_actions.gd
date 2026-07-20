## core/domain/combine/combine_actions.gd — CombineActions.combine_actions()
## domain service (FEAT-002, Iteration O "Combine Selection UX"; US-002;
## FR-001).
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript RefCounted —
## zero Node/Control/CanvasItem inheritance, zero engine I/O, zero imports
## from application/presentation/infrastructure. Depends only on this
## iteration's own domain siblings (core/domain/combine/verb_queue_entry.gd,
## core/domain/combine/verb_traits.gd) — never a Resource-backed
## VerbResource (core/resources/verb_resource.gd), which stays strictly an
## adapter/application-layer concern (design notes' architecture section:
## "traits live only on VerbResource, never copied onto VerbQueueEntry" —
## this domain service only ever evaluates the already-derived VerbTraits
## snapshot a caller hands it, never re-reads authored data itself).
##
## THE single source of truth for the same-verb/Repeat exclusion rule
## (design notes' architecture: "combine_actions(queue, candidate_verb) —
## the ONE source of truth ... Called from two seams: (a) query-time,
## filtering candidate_options in the queue builder [this feature's
## core/application/combine/build_verb_queue_use_case.gd], and (b)
## command-time, as the authoritative DEF-001 gate inside execute() [a later
## feature]. Having one pure function called twice (not two implementations)
## is the core correctness guarantee for this steel thread.").
##
## THIS FEATURE'S SCOPE is the same-verb/Repeat exclusion rule only — the
## reaction-composition minimum-entry rule (design notes' data_model:
## REACTION context's ">=2 entries AND >=1 reaction verb" Confirm gate) is a
## later P1 feature (P1-3) layered on top of this same function without
## changing its shape.
##
## Contract:
##   queue     — Array of already-picked queue entries. Each entry may be a
##               core/domain/combine/verb_queue_entry.gd VerbQueueEntry
##               instance (production shape) OR a plain Dictionary carrying
##               a "verb_id" key (a lighter-weight shape some callers/tests
##               may prefer) — duck-typed via _verb_id_of() below, mirroring
##               this codebase's established "accept either a value object
##               or an equivalent Dictionary" convention.
##   candidate — Dictionary {"verb_id": String, "traits": VerbTraits} —
##               the verb being considered as the NEXT queue entry. `traits`
##               is a core/domain/combine/verb_traits.gd VerbTraits
##               instance (or null, treated as "no traits set" — repeat
##               defaults to false).
##
## Returns {"legal": bool, "reason": String} — "reason" is "" when legal,
## "DUPLICATE_VERB_WITHOUT_REPEAT" when `candidate`'s verb_id already
## appears in `queue` and `candidate.traits.repeat` is not true. Two
## DIFFERENT verbs are ALWAYS legal with respect to this rule — Repeat is
## only ever relevant to a same-verb (self-combined) candidate (mirrors
## core/rules/action_economy.gd's own combine_actions() pairwise
## precedent: "Two DIFFERENT verbs ... skip this check entirely").
##
## Usage:
##   var queue := [VerbQueueEntry.new("q1", 0, "STRIDE")]
##   CombineActions.combine_actions(queue, {"verb_id": "STRIKE", "traits": VerbTraits.new()})
##   # {"legal": true, "reason": ""} -- different verb, no Repeat required
##
##   CombineActions.combine_actions(queue, {"verb_id": "STRIDE", "traits": VerbTraits.new()})
##   # {"legal": false, "reason": "DUPLICATE_VERB_WITHOUT_REPEAT"} -- same verb, no Repeat
##
##   CombineActions.combine_actions(queue, {"verb_id": "STRIDE", "traits": VerbTraits.new(true)})
##   # {"legal": true, "reason": ""} -- same verb, candidate carries Repeat

class_name CombineActions
extends RefCounted


## combine_actions(queue, candidate) -> Dictionary{legal, reason} — see
## file-level doc for the full contract.
static func combine_actions(queue: Array, candidate) -> Dictionary:
	var candidate_verb_id: String = _verb_id_of(candidate)
	var repeat: bool = _repeat_of(candidate)

	if not repeat:
		for entry in queue:
			if _verb_id_of(entry) == candidate_verb_id:
				return {"legal": false, "reason": "DUPLICATE_VERB_WITHOUT_REPEAT"}

	return {"legal": true, "reason": ""}


## _verb_id_of(entry) -> String — duck-typed verb_id accessor shared by
## every queue-entry/candidate shape this service accepts (see file-level
## doc's `queue`/`candidate` contract).
static func _verb_id_of(entry) -> String:
	if entry is Dictionary:
		return entry.get("verb_id", "")
	return entry.verb_id


## _repeat_of(candidate) -> bool — reads `candidate.traits.repeat`, treating
## a missing/null "traits" value as "no Repeat trait" (false) rather than
## erroring — a candidate Dictionary that omits "traits" entirely is still
## a well-formed (just non-repeatable) candidate.
static func _repeat_of(candidate: Dictionary) -> bool:
	var traits = candidate.get("traits")
	if traits == null:
		return false
	return traits.repeat
