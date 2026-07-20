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
##   2. enter_selection() excludes STRIDE from candidate_options once STRIDE
##      is already in the queue (STRIDE carries no Repeat trait) -- routed
##      through core/domain/combine/combine_actions.gd's SOLE same-verb/
##      Repeat exclusion rule, never re-derived here.
##   3. enter_selection() degrades safely (ok=false, no crash) with no live
##      actor or no wired VerbRegistryPort.
##   4. FEAT-003 (US-003; FR-002): candidate_options does NOT include the
##      Confirm sentinel when the queue length is below the context-specific
##      minimum (1, TURN context), and DOES include it alongside remaining
##      compatible verbs once the minimum (2, TURN context) is reached.

const BuildVerbQueueUseCaseClass = preload("res://core/application/combine/build_verb_queue_use_case.gd")
const VerbRegistryPortClass = preload("res://core/application/combine/verb_registry_port.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")

const STRIDE_RESOURCE_PATH: String = "res://data/verbs/stride.tres"
const STRIKE_RESOURCE_PATH: String = "res://data/verbs/strike.tres"
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
# Criterion 2 — STRIDE already queued excludes STRIDE (no Repeat trait).
# ══════════════════════════════════════════════════════════════════════════

func test_enter_selection_excludes_stride_once_queued_without_repeat() -> void:
	var use_case := BuildVerbQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var queue: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var descriptor = use_case.enter_selection(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_false(ids.has("STRIDE"), "STRIDE must be excluded once already queued (no Repeat trait on data/verbs/stride.tres)")
	assert_true(ids.has("STRIKE"), "STRIKE must still be offered -- a different verb is unaffected by STRIDE's own exclusion")
	assert_true(descriptor.ok, "STRIKE remaining legal must keep ok=true")
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
	assert_false(ids.has("STRIDE"), "STRIDE must remain excluded once queued (no Repeat)")
	assert_false(ids.has("STRIKE"), "STRIKE must remain excluded once queued (no Repeat)")
	assert_true(descriptor.ok, "Confirm sentinel alongside remaining verbs must keep ok=true")
