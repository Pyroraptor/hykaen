extends GutTest
## tests/unit/application/combine/test_build_verb_queue_use_case.gd
##
## GUT suite for FEAT-002 (Iteration O "Combine Selection UX"; US-002;
## FR-001/FR-003): core/application/combine/build_verb_queue_use_case.gd's
## BuildVerbQueueUseCase.
##
## Verifies:
##   1. enter_selection() at an empty queue returns candidate_options
##      containing both STRIDE and STRIKE (the two combinable VerbResources
##      a FakeVerbRegistryPort offers, mirroring data/verbs/stride.tres /
##      data/verbs/strike.tres's real authored shape).
##   2. enter_selection() excludes CAST_SPELL from candidate_options once
##      CAST_SPELL is already in the queue (CAST_SPELL carries no Repeat
##      trait) -- routed through core/domain/combine/combine_actions.gd's
##      SOLE same-verb/Repeat exclusion rule, never re-derived here.
##      (STRIDE and STRIKE carry repeat=true so they remain offered after
##      being queued; CAST_SPELL is the canonical non-Repeat verb in data/.)
##   3. enter_selection() degrades safely (ok=false, no crash) with no live
##      actor or no wired VerbRegistryPort.
##   4. FEAT-003 (US-003; FR-002): candidate_options does NOT include the
##      Confirm sentinel when the queue length is below the context-specific
##      minimum (1, TURN context), and DOES include it alongside remaining
##      compatible verbs once the minimum (2, TURN context) is reached.
##   5. FEAT-008 (US-008; FR-006): candidate_options does NOT include the
##      Cancel sentinel at an EMPTY queue (nothing in-progress yet to
##      discard), and DOES include it alongside remaining compatible verbs
##      and the Confirm sentinel once at least one verb has been picked.

const BuildVerbQueueUseCaseClass = preload("res://core/application/combine/build_verb_queue_use_case.gd")
const VerbRegistryPortClass = preload("res://core/application/combine/verb_registry_port.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const CancelCombineUseCaseClass = preload("res://core/application/combine/cancel_combine_use_case.gd")

const STRIDE_RESOURCE_PATH: String = "res://data/verbs/stride.tres"
const STRIKE_RESOURCE_PATH: String = "res://data/verbs/strike.tres"
const CAST_SPELL_RESOURCE_PATH: String = "res://data/verbs/cast_spell.tres"
const VerbResourceClass = preload("res://core/resources/verb_resource.gd")


class FakeVerbRegistryPort:
	extends "res://core/application/combine/verb_registry_port.gd"

	var _pool: Array

	func _init(pool: Array) -> void:
		_pool = pool

	func get_available_verbs(_actor, _context) -> Array:
		return _pool


func _stride_and_strike_pool() -> Array:
	return [ResourceLoader.load(STRIDE_RESOURCE_PATH), ResourceLoader.load(STRIKE_RESOURCE_PATH)]


func _option_ids(candidate_options: Array) -> Array:
	var ids: Array = []
	for option in candidate_options:
		ids.append(option.get("id"))
	return ids


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — empty queue offers both STRIDE and STRIKE.
# ══════════════════════════════════════════════════════════════════════════

func test_enter_selection_at_empty_queue_offers_stride_and_strike() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())

	var descriptor = use_case.enter_selection([], {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	assert_true(descriptor.ok, "an empty queue with a live actor + registry must offer at least one legal candidate")
	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_true(ids.has("STRIDE"), "candidate_options must include STRIDE at an empty queue")
	assert_true(ids.has("STRIKE"), "candidate_options must include STRIKE at an empty queue")
	assert_eq(descriptor.order_index, 0, "order_index must mirror the (empty) queue's length")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — a verb without Repeat already queued is excluded.
# CAST_SPELL (repeat=false) is the canonical non-Repeat verb in data/.
# STRIDE and STRIKE both carry repeat=true so they remain offered after
# being queued -- tested by the criterion 4 test below.
# ══════════════════════════════════════════════════════════════════════════

func test_enter_selection_excludes_verb_without_repeat_once_queued() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new([
		ResourceLoader.load(STRIDE_RESOURCE_PATH),
		ResourceLoader.load(CAST_SPELL_RESOURCE_PATH),
	])
	var queue: Array = [VerbQueueEntryClass.new("q1", 0, "CAST_SPELL")]

	var descriptor = use_case.enter_selection(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_false(ids.has("CAST_SPELL"), "CAST_SPELL must be excluded once already queued (no Repeat trait on data/verbs/cast_spell.tres)")
	assert_true(ids.has("STRIDE"), "STRIDE must still be offered -- it has Repeat=true and is a different verb")
	assert_true(descriptor.ok, "STRIDE remaining legal must keep ok=true")
	assert_eq(descriptor.order_index, 1, "order_index must mirror the queue's current length")


func test_enter_selection_only_offers_combinable_verb_resources() -> void:
	var non_combinable := VerbResource.new()
	non_combinable.verb_id = "END_TURN"
	non_combinable.label = "End Turn"
	non_combinable.combinable = false

	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new([non_combinable, ResourceLoader.load(STRIDE_RESOURCE_PATH)])

	var descriptor = use_case.enter_selection([], {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_false(ids.has("END_TURN"), "a non-combinable VerbResource must never be offered as a Combine candidate")
	assert_true(ids.has("STRIDE"))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — safe degradation with no legal options / no collaborators.
# ══════════════════════════════════════════════════════════════════════════

func test_enter_selection_returns_ok_false_with_no_legal_options() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new([])

	var descriptor = use_case.enter_selection([], {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	assert_false(descriptor.ok, "no legal candidates must report ok=false, never a silently-empty success")
	assert_eq(descriptor.candidate_options, [])


func test_enter_selection_degrades_safely_with_no_registry_port() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()

	var descriptor = use_case.enter_selection([], {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, null)

	assert_false(descriptor.ok, "an unwired VerbRegistryPort must degrade safely to ok=false, never crash")


func test_enter_selection_degrades_safely_with_no_actor() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())

	var descriptor = use_case.enter_selection([], null, CombineQueueClass.Context.TURN, port)

	assert_false(descriptor.ok, "a null actor must degrade safely to ok=false, never crash")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (FEAT-003) — Confirm sentinel gating by queue length.
# ══════════════════════════════════════════════════════════════════════════

func test_enter_selection_excludes_confirm_sentinel_below_minimum_queue_length() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var queue: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var descriptor = use_case.enter_selection(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_false(ids.has("CONFIRM"), "Confirm sentinel must not be offered below the TURN minimum queue length (2)")


func test_enter_selection_offers_confirm_sentinel_alongside_remaining_verbs_at_minimum_queue_length() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var third_verb := VerbResource.new()
	third_verb.verb_id = "PARRY"
	third_verb.label = "Parry"
	third_verb.combinable = true
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool() + [third_verb])
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]

	var descriptor = use_case.enter_selection(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_true(ids.has("CONFIRM"), "Confirm sentinel must be offered once the TURN minimum queue length (2) is reached")
	assert_true(ids.has("PARRY"), "remaining compatible verbs must still be offered alongside Confirm")
	assert_true(ids.has("STRIDE"), "STRIDE (repeat=true) must remain offered even after being queued")
	assert_true(ids.has("STRIKE"), "STRIKE (repeat=true) must remain offered even after being queued")
	assert_true(descriptor.ok, "Confirm sentinel alongside remaining verbs must keep ok=true")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 (FEAT-008; US-008; FR-006) — Cancel sentinel gating by queue
# length (in-progress-or-not), offered alongside Confirm/remaining verbs.
# ══════════════════════════════════════════════════════════════════════════

func test_enter_selection_excludes_cancel_sentinel_at_empty_queue() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())

	var descriptor = use_case.enter_selection([], {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_false(ids.has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "Cancel must not be offered at an empty queue -- nothing in-progress yet to discard")


func test_enter_selection_offers_cancel_sentinel_once_a_verb_is_queued() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var queue: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var descriptor = use_case.enter_selection(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_true(ids.has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "Cancel must be offered once at least one verb is in-progress")
	assert_true(ids.has("STRIKE"), "Cancel must be offered ALONGSIDE remaining compatible verbs, never in place of them")
	assert_true(descriptor.ok, "Cancel sentinel alongside remaining verbs must keep ok=true")


func test_enter_selection_offers_cancel_alongside_confirm_at_minimum_queue_length() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]

	var descriptor = use_case.enter_selection(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_true(ids.has("CONFIRM"), "Confirm must still be offered at the minimum queue length")
	assert_true(ids.has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "Cancel must ALSO be offered alongside Confirm, not superseded by it")
