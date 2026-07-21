extends GutTest
## tests/acceptance/combine/test_us002_repeat_exclusion_acceptance.gd —
## FEAT-303 (Iteration O "Combine Selection UX"; CHECKLIST-3).
##
## Scripted acceptance-test evidence for US-002 ("As a player picking a
## second sub-action for a Combine, a verb I've already queued must NOT be
## offered again unless it carries the Repeat trait").
##
## Exercises the REAL, already-shipped
## core/domain/combine/combine_actions.gd CombineActions.combine_actions()
## domain service directly (the single source of truth for this rule) AND
## the REAL core/application/combine/build_verb_queue_use_case.gd
## BuildVerbQueueUseCase (the query-time seam a player's second verb pick
## actually drives), never a re-derived copy of the rule. Deeper coverage of
## these classes already lives in
## tests/unit/domain/combine/test_combine_actions.gd and
## tests/unit/application/combine/test_build_verb_queue_use_case.gd -- this
## suite exists to give the deployment-readiness checklist an explicit,
## individually-named, CI-verifiable trace back to US-002's own acceptance
## behavior.
##
## Acceptance behavior verified:
##   1. A same-verb candidate with no Repeat trait is illegal
##      (DUPLICATE_VERB_WITHOUT_REPEAT) once that verb already appears in
##      the queue.
##   2. A same-verb candidate WITH the Repeat trait IS legal.
##   3. A different-verb candidate is ALWAYS legal regardless of Repeat.
##   4. The candidate-options filtering seam a real verb press drives
##      (BuildVerbQueueUseCase.enter_selection()) excludes an
##      already-queued, non-Repeat verb from candidate_options while still
##      offering a different, legal verb.

const CombineActionsClass = preload("res://core/domain/combine/combine_actions.gd")
const VerbTraitsClass = preload("res://core/domain/combine/verb_traits.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const BuildVerbQueueUseCaseClass = preload("res://core/application/combine/build_verb_queue_use_case.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")

const STRIDE_RESOURCE_PATH: String = "res://data/verbs/stride.tres"
const STRIKE_RESOURCE_PATH: String = "res://data/verbs/strike.tres"


class FakeVerbRegistryPort:
	extends "res://core/application/combine/verb_registry_port.gd"

	var _pool: Array

	func _init(pool: Array) -> void:
		_pool = pool

	func get_available_verbs(_actor, _context) -> Array:
		return _pool


func _option_ids(candidate_options: Array) -> Array:
	var ids: Array = []
	for option in candidate_options:
		ids.append(option.get("id"))
	return ids


# ══════════════════════════════════════════════════════════════════════════
# US-002, criteria 1-3 -- the domain rule itself.
# ══════════════════════════════════════════════════════════════════════════

func test_us002_same_verb_without_repeat_is_illegal() -> void:
	var queue := [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var verdict: Dictionary = CombineActionsClass.combine_actions(queue, {"verb_id": "STRIDE", "traits": VerbTraitsClass.new(false)})

	assert_false(verdict.get("legal", true), "US-002: an already-queued verb with no Repeat trait must be rejected as a candidate")
	assert_eq(verdict.get("reason", ""), "DUPLICATE_VERB_WITHOUT_REPEAT")


func test_us002_same_verb_with_repeat_is_legal() -> void:
	var queue := [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var verdict: Dictionary = CombineActionsClass.combine_actions(queue, {"verb_id": "STRIDE", "traits": VerbTraitsClass.new(true)})

	assert_true(verdict.get("legal", false), "US-002: a Repeat-flagged verb must be legal even when already queued")
	assert_eq(verdict.get("reason", ""), "")


func test_us002_different_verb_is_always_legal() -> void:
	var queue := [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var verdict: Dictionary = CombineActionsClass.combine_actions(queue, {"verb_id": "STRIKE", "traits": VerbTraitsClass.new(false)})

	assert_true(verdict.get("legal", false), "US-002: a genuinely different verb is unaffected by the same-verb/Repeat rule")


# ══════════════════════════════════════════════════════════════════════════
# US-002, criterion 4 -- the real candidate-picking seam a player's second
# verb press drives excludes the already-queued, non-Repeat verb.
# ══════════════════════════════════════════════════════════════════════════

func test_us002_build_verb_queue_use_case_excludes_already_queued_verb_from_candidates() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new([
		ResourceLoader.load(STRIDE_RESOURCE_PATH),
		ResourceLoader.load(STRIKE_RESOURCE_PATH),
	])
	var queue: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var descriptor = use_case.enter_selection(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_false(ids.has("STRIDE"), "US-002: an already-queued verb (STRIDE, no Repeat trait) must not be offered again as a candidate")
	assert_true(ids.has("STRIKE"), "US-002: a different, still-legal verb must remain offered")
