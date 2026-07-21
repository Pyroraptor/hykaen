extends GutTest
## tests/unit/application/combine/test_validate_combine_queue_use_case.gd
##
## GUT suite for FEAT-004 (Iteration O "Combine Selection UX"; US-004;
## FR-007; DEF-001): core/application/combine/validate_combine_queue_use_case.gd's
## ValidateCombineQueueUseCase — the authoritative re-validation gate
## execute() must run BEFORE any economy charge.
##
## Verifies:
##   1. A queue of two DIFFERENT verbs ([STRIDE, STRIKE]) is legal (ok=true)
##      -- the happy-path shape execute()'s own regression test relies on.
##   2. A queue of two IDENTICAL verbs ([STRIDE, STRIDE]) whose current
##      VerbResource carries no Repeat trait is rejected
##      (ok=false, error_code=VALIDATION_FAILED).
##   3. The SAME [STRIDE, STRIDE] queue is legal when STRIDE's CURRENT
##      VerbResource (re-read fresh via VerbRegistryPort, never a stale
##      copy) carries the Repeat trait -- proving traits are re-derived at
##      validation time (DEF-001), not trusted from the queue itself.
##   4. Safe degradation (ok=false, no crash) with no live actor / no wired
##      VerbRegistryPort.
##   5. order_index (not insertion/array order) is authoritative for the
##      incremental re-check.

const ValidateCombineQueueUseCaseClass = preload("res://core/application/combine/validate_combine_queue_use_case.gd")
const VerbRegistryPortClass = preload("res://core/application/combine/verb_registry_port.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const VerbResourceClass = preload("res://core/resources/verb_resource.gd")

const STRIDE_RESOURCE_PATH: String = "res://data/verbs/stride.tres"
const STRIKE_RESOURCE_PATH: String = "res://data/verbs/strike.tres"


class FakeVerbRegistryPort:
	extends "res://core/application/combine/verb_registry_port.gd"

	var _pool: Array

	func _init(pool: Array) -> void:
		_pool = pool

	func get_available_verbs(_actor, _context) -> Array:
		return _pool


func _stride_and_strike_pool() -> Array:
	return [ResourceLoader.load(STRIDE_RESOURCE_PATH), ResourceLoader.load(STRIKE_RESOURCE_PATH)]


func _repeatable_stride_resource():
	var stride: VerbResource = VerbResourceClass.new()
	stride.verb_id = "STRIDE"
	stride.label = "Stride"
	stride.action_cost = 1
	stride.stamina_cost = 0
	stride.movement = true
	stride.repeat = true
	stride.combinable = true
	return stride


func _non_repeat_stride_resource():
	var stride: VerbResource = VerbResourceClass.new()
	stride.verb_id = "STRIDE"
	stride.label = "Stride"
	stride.action_cost = 1
	stride.stamina_cost = 0
	stride.movement = true
	stride.repeat = false
	stride.combinable = true
	return stride


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — two different verbs are legal.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_then_strike_queue_is_legal() -> void:
	var use_case := ValidateCombineQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]

	var result: Dictionary = use_case.execute(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	assert_true(result.get("ok", false), "[STRIDE, STRIKE] -- two different verbs -- must be legal")
	assert_eq(result.get("error_code"), "")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — duplicate verb without Repeat is rejected.
# Uses a synthetic non-repeat STRIDE so the test is independent of the
# shipped data/verbs/stride.tres (which carries repeat=true).
# ══════════════════════════════════════════════════════════════════════════

func test_duplicate_stride_without_repeat_is_rejected() -> void:
	var use_case := ValidateCombineQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new([_non_repeat_stride_resource()])
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIDE"),
	]

	var result: Dictionary = use_case.execute(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	assert_false(result.get("ok", true), "[STRIDE, STRIDE] with no Repeat trait must be rejected")
	assert_eq(result.get("error_code"), "VALIDATION_FAILED")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — duplicate STRIDE IS legal once STRIDE's current VerbResource
# carries the Repeat trait -- re-derived fresh via VerbRegistryPort, not
# trusted from a stale copy (DEF-001).
# ══════════════════════════════════════════════════════════════════════════

func test_duplicate_stride_with_repeat_trait_set_is_legal() -> void:
	var use_case := ValidateCombineQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new([_repeatable_stride_resource()])
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIDE"),
	]

	var result: Dictionary = use_case.execute(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	assert_true(result.get("ok", false), "[STRIDE, STRIDE] must be legal once STRIDE's current VerbResource carries Repeat")
	assert_eq(result.get("error_code"), "")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — safe degradation with no actor / no registry port.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_degrades_safely_with_no_actor() -> void:
	var use_case := ValidateCombineQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var queue: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var result: Dictionary = use_case.execute(queue, null, CombineQueueClass.Context.TURN, port)

	assert_false(result.get("ok", true), "a null actor must degrade safely to ok=false, never crash")
	assert_eq(result.get("error_code"), "VALIDATION_FAILED")


func test_execute_degrades_safely_with_no_registry_port() -> void:
	var use_case := ValidateCombineQueueUseCaseClass.new()
	var queue: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var result: Dictionary = use_case.execute(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, null)

	assert_false(result.get("ok", true), "an unwired VerbRegistryPort must degrade safely to ok=false, never crash")
	assert_eq(result.get("error_code"), "VALIDATION_FAILED")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — order_index, not insertion order, is authoritative.
# ══════════════════════════════════════════════════════════════════════════

func test_reorders_entries_by_order_index_before_re_checking() -> void:
	var use_case := ValidateCombineQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	# Inserted out of order_index order -- STRIKE (order_index 1) appended
	# to the Array before STRIDE (order_index 0). Both are still legal
	# regardless of check order (different verbs), so this proves the use
	# case does not crash/misbehave on out-of-order input; the duplicate
	# case below is the sharper proof order_index drives the check.
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
	]

	var result: Dictionary = use_case.execute(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	assert_true(result.get("ok", false), "order_index reordering must not spuriously reject a legal [STRIDE, STRIKE] queue")


# ══════════════════════════════════════════════════════════════════════════
# FIND-306 — a queue bypassing add_entry() (e.g. entries assigned directly
# onto CombineQueue.entries) that carries a gapped/non-zero-start
# order_index sequence must be rejected BEFORE any economy charge, even
# though its verb_ids are otherwise perfectly legal (two DIFFERENT verbs).
# ══════════════════════════════════════════════════════════════════════════

func test_gapped_order_index_queue_is_rejected_before_combine_actions_check() -> void:
	var use_case := ValidateCombineQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	# Bypasses CombineQueue.add_entry() entirely -- constructed directly as
	# a raw Array, mirroring how a stale/tampered/hand-built queue might
	# reach execute() (design notes' security section).
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 99, "STRIKE"),
	]

	var result: Dictionary = use_case.execute(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	assert_false(result.get("ok", true), "{0, 99} order_index must be rejected as non-contiguous, even for two legal verbs")
	assert_eq(result.get("error_code"), "VALIDATION_FAILED")


func test_non_zero_start_order_index_queue_is_rejected() -> void:
	var use_case := ValidateCombineQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var queue: Array = [
		VerbQueueEntryClass.new("q1", -1, "STRIDE"),
		VerbQueueEntryClass.new("q1", 3, "STRIKE"),
	]

	var result: Dictionary = use_case.execute(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	assert_false(result.get("ok", true), "{-1, 3} order_index must be rejected as not starting at 0")
	assert_eq(result.get("error_code"), "VALIDATION_FAILED")


func test_contiguous_order_index_queue_still_passes_alongside_new_check() -> void:
	var use_case := ValidateCombineQueueUseCaseClass.new()
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]

	var result: Dictionary = use_case.execute(queue, {"combatant_id": "player_0"}, CombineQueueClass.Context.TURN, port)

	assert_true(result.get("ok", false), "a proper {0,1} contiguous sequence must still be legal after adding the contiguity gate")
	assert_eq(result.get("error_code"), "")
