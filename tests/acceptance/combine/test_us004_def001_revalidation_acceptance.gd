extends GutTest
## tests/acceptance/combine/test_us004_def001_revalidation_acceptance.gd —
## FEAT-303 (Iteration O "Combine Selection UX"; CHECKLIST-3).
##
## Scripted acceptance-test evidence for US-004 ("As the system, before
## charging any action economy, execute() must re-validate the confirmed
## queue against the SAME same-verb/Repeat rule the pick loop used --
## DEF-001 -- so a stale/tampered queue can never spend a Combine's cost on
## an illegal combo").
##
## Exercises the REAL, already-shipped
## core/controllers/combine_action_controller.gd CombineActionController's
## execute() (the concrete VerbControllerPort seam a player's Confirm press
## actually drives) -- never a hand-rolled re-implementation of the
## DEF-001 gate. Deeper coverage of the underlying
## core/application/combine/validate_combine_queue_use_case.gd
## ValidateCombineQueueUseCase already lives in
## tests/unit/application/combine/test_validate_combine_queue_use_case.gd
## and tests/unit/controllers/ -- this suite exists to give the
## deployment-readiness checklist an explicit, individually-named,
## CI-verifiable trace back to US-004's own acceptance behavior.
##
## test_criteria (feature spec, verbatim): "test_us004 asserts
## [STRIDE,STRIDE] without Repeat is rejected with VALIDATION_FAILED before
## any economy charge, and accepted with Repeat=true."

const CombineActionControllerClass = preload("res://core/controllers/combine_action_controller.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const VerbResourceClass = preload("res://core/resources/verb_resource.gd")

const STRIDE_RESOURCE_PATH: String = "res://data/verbs/stride.tres"


class FakeVerbRegistryPort:
	extends "res://core/application/combine/verb_registry_port.gd"

	var _pool: Array

	func _init(pool: Array) -> void:
		_pool = pool

	func get_available_verbs(_actor, _context) -> Array:
		return _pool


## FakeActionEconomyPort — spies on spend_action() calls so this suite can
## assert ZERO economy is ever charged on the VALIDATION_FAILED path
## (US-004's own "before any economy charge" acceptance requirement).
class FakeActionEconomyPort:
	var spend_action_calls: Array = []

	func spend_action(metadata: Dictionary) -> Dictionary:
		spend_action_calls.append(metadata)
		return {"success": true}


## FakeActor — spies on spend_stamina() calls for the SAME "zero economy
## charged" acceptance proof, on the Stamina side.
class FakeActor:
	var spend_stamina_calls: int = 0

	func spend_stamina() -> void:
		spend_stamina_calls += 1


func _queue_entries() -> Array:
	return [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIDE"),
	]


# ══════════════════════════════════════════════════════════════════════════
# US-004 -- [STRIDE, STRIDE] without Repeat: VALIDATION_FAILED, ZERO economy
# charged (neither the action-economy port nor the actor's own Stamina spend
# is ever invoked).
# ══════════════════════════════════════════════════════════════════════════

func test_us004_stride_stride_without_repeat_rejected_before_any_economy_charge() -> void:
	# Use a synthetic non-repeat STRIDE to test the DEF-001 gate independently
	# of the shipped data/verbs/stride.tres (which carries repeat=true so that
	# STRIDE+STRIDE is a valid authored combo). The rule under test is universal:
	# any [VERB, VERB] pair where VERB lacks the Repeat trait must be rejected.
	var non_repeat_stride := VerbResourceClass.new()
	non_repeat_stride.verb_id = "STRIDE"
	non_repeat_stride.label = "Stride"
	non_repeat_stride.combinable = true
	non_repeat_stride.repeat = false
	var port := FakeVerbRegistryPort.new([non_repeat_stride])
	var action_economy_port := FakeActionEconomyPort.new()
	var actor := FakeActor.new()
	var controller := CombineActionControllerClass.new({
		"verb_registry_port": port,
		"action_economy_port": action_economy_port,
	})

	var result: Dictionary = controller.execute({
		"queue": _queue_entries(),
		"actor": actor,
		"context": CombineQueueClass.Context.TURN,
	})

	assert_false(result.get("ok", true), "US-004: [STRIDE, STRIDE] without Repeat must be rejected")
	assert_eq(result.get("error_code", ""), "VALIDATION_FAILED", "US-004: the DEF-001 gate's own error_code must be VALIDATION_FAILED")
	assert_eq(result.get("actions_spent", -1), 0, "US-004: actions_spent must be 0 on a VALIDATION_FAILED result")
	assert_eq(result.get("stamina_spent", -1), 0, "US-004: stamina_spent must be 0 on a VALIDATION_FAILED result")
	assert_eq(action_economy_port.spend_action_calls.size(), 0, "US-004: the action-economy port must NEVER be charged before/on a DEF-001 rejection")
	assert_eq(actor.spend_stamina_calls, 0, "US-004: the actor's own Stamina must NEVER be spent before/on a DEF-001 rejection")


# ══════════════════════════════════════════════════════════════════════════
# US-004 -- [STRIDE, STRIDE] WITH Repeat=true: accepted, economy charged
# normally.
# ══════════════════════════════════════════════════════════════════════════

func test_us004_stride_stride_with_repeat_true_is_accepted_and_charges_economy() -> void:
	var repeatable_stride := VerbResourceClass.new()
	repeatable_stride.verb_id = "STRIDE"
	repeatable_stride.label = "Stride"
	repeatable_stride.combinable = true
	repeatable_stride.repeat = true

	var port := FakeVerbRegistryPort.new([repeatable_stride])
	var action_economy_port := FakeActionEconomyPort.new()
	var actor := FakeActor.new()
	var controller := CombineActionControllerClass.new({
		"verb_registry_port": port,
		"action_economy_port": action_economy_port,
	})

	var result: Dictionary = controller.execute({
		"queue": _queue_entries(),
		"actor": actor,
		"context": CombineQueueClass.Context.TURN,
	})

	assert_true(result.get("ok", false), "US-004: [STRIDE, STRIDE] WITH Repeat=true must be accepted (result: %s)" % [result])
	assert_eq(result.get("error_code", ""), "")
	assert_eq(result.get("actions_spent", 0), 1, "US-004: an accepted Combine must charge exactly 1 action")
	assert_eq(result.get("stamina_spent", 0), 1, "US-004: an accepted Combine must charge exactly 1 Stamina")
	assert_eq(action_economy_port.spend_action_calls.size(), 1, "US-004: the action-economy port must be charged exactly once on acceptance")
	assert_eq(actor.spend_stamina_calls, 1, "US-004: the actor's own Stamina must be spent exactly once on acceptance")
