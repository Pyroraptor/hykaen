extends GutTest
## tests/unit/controllers/test_combine_action_controller_execute.gd
##
## GUT suite for FEAT-004 (Iteration O "Combine Selection UX"; US-004;
## FR-007; DEF-001): core/controllers/combine_action_controller.gd's
## CombineActionController.execute() — the authoritative re-validation gate
## must run BEFORE any action-economy/Stamina charge.
##
## Verifies (test_criteria):
##   1. execute() with queue [STRIDE, STRIDE] and no Repeat trait returns
##      {ok:false, error_code:VALIDATION_FAILED, actions_spent:0,
##      stamina_spent:0} -- zero economy spent.
##   2. execute() with queue [STRIDE, STRIDE] and Repeat trait set (on
##      STRIDE's CURRENT VerbResource) returns ok:true and proceeds to
##      charge economy (one action + one Stamina).
##   3. The happy-path [STRIDE, STRIKE] queue succeeds and is unaffected by
##      the new validation gate.
##   4. ValidateCombineQueueUseCase is invoked as the FIRST statement in
##      execute(), strictly before any action-economy charge -- proven via
##      a call-order spy shared between the injected use case and the
##      injected action-economy port.

const CombineActionControllerClass = preload("res://core/controllers/combine_action_controller.gd")
const ValidateCombineQueueUseCaseClass = preload("res://core/application/combine/validate_combine_queue_use_case.gd")
const VerbRegistryPortClass = preload("res://core/application/combine/verb_registry_port.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const VerbResourceClass = preload("res://core/resources/verb_resource.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const STRIDE_RESOURCE_PATH: String = "res://data/verbs/stride.tres"
const STRIKE_RESOURCE_PATH: String = "res://data/verbs/strike.tres"


class FakeVerbRegistryPort:
	extends "res://core/application/combine/verb_registry_port.gd"

	var _pool: Array

	func _init(pool: Array) -> void:
		_pool = pool

	func get_available_verbs(_actor, _context) -> Array:
		return _pool


## SpyCombatant — mirrors tests/unit/test_combine_stamina_rejection.gd's
## established Spy convention: a real Combatant that additionally counts
## spend_stamina() calls, so a rejected execute() call can be proven to
## never reach the mutator.
class SpyCombatant:
	extends "res://core/domain/combatant.gd"

	var spend_stamina_call_count: int = 0

	func spend_stamina(amount: int = 1) -> void:
		spend_stamina_call_count += 1
		super.spend_stamina(amount)


## FakeActionEconomyPort — a minimal duck-typed collaborator matching
## core/application/ports/action_economy_port.gd's spend_action() contract,
## always reporting success and counting how many times it was called.
class FakeActionEconomyPort:
	var spend_action_call_count: int = 0

	func spend_action(_action_metadata: Dictionary) -> Dictionary:
		spend_action_call_count += 1
		return {"success": true, "ok": true}


## SpyValidateUseCase / SpyActionEconomyPort — share a single `call_log`
## Array so this suite's call-order criterion can assert
## ValidateCombineQueueUseCase.execute() is invoked strictly BEFORE
## _action_economy_port.spend_action() is ever reached.
class SpyValidateUseCase:
	extends "res://core/application/combine/validate_combine_queue_use_case.gd"

	var call_log: Array

	func _init(log: Array) -> void:
		call_log = log

	func execute(queue_entries: Array, actor, context: int, verb_registry_port) -> Dictionary:
		call_log.append("validate")
		return super.execute(queue_entries, actor, context, verb_registry_port)


class SpyActionEconomyPort:
	var call_log: Array

	func _init(log: Array) -> void:
		call_log = log

	func spend_action(_action_metadata: Dictionary) -> Dictionary:
		call_log.append("charge_action_economy")
		return {"success": true, "ok": true}


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


func _make_actor(starting_stamina: int = 1) -> SpyCombatant:
	var actor := SpyCombatant.new("player_0", "Titus", "Player", HexCoordClass.new(0, 0))
	actor.stamina = starting_stamina
	return actor


func _double_stride_queue() -> Array:
	return [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIDE"),
	]


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — [STRIDE, STRIDE] with no Repeat trait is rejected with ZERO
# economy spent.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_rejects_duplicate_stride_without_repeat_with_zero_economy_spent() -> void:
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var economy := FakeActionEconomyPort.new()
	var actor := _make_actor(1)
	var controller := CombineActionControllerClass.new({
		"verb_registry_port": port,
		"action_economy_port": economy,
	})

	var result: Dictionary = controller.execute({"queue": _double_stride_queue(), "actor": actor, "context": CombineQueueClass.Context.TURN})

	assert_false(result.get("ok", true), "an illegal [STRIDE, STRIDE] combo must report ok=false")
	assert_eq(result.get("error_code"), "VALIDATION_FAILED")
	assert_eq(result.get("actions_spent"), 0, "a rejected execute() call must spend zero actions")
	assert_eq(result.get("stamina_spent"), 0, "a rejected execute() call must spend zero Stamina")
	assert_eq(economy.spend_action_call_count, 0, "the DEF-001 gate must reject BEFORE the action-economy port is ever charged")
	assert_eq(actor.stamina, 1, "a rejected execute() call must leave the actor's Stamina untouched")
	assert_eq(actor.spend_stamina_call_count, 0, "a rejected execute() call must never reach Combatant.spend_stamina()")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — [STRIDE, STRIDE] IS legal once STRIDE's current VerbResource
# carries the Repeat trait, and execute() proceeds to charge economy.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_accepts_duplicate_stride_with_repeat_trait_and_charges_economy() -> void:
	var port := FakeVerbRegistryPort.new([_repeatable_stride_resource()])
	var economy := FakeActionEconomyPort.new()
	var actor := _make_actor(1)
	var controller := CombineActionControllerClass.new({
		"verb_registry_port": port,
		"action_economy_port": economy,
	})

	var result: Dictionary = controller.execute({"queue": _double_stride_queue(), "actor": actor, "context": CombineQueueClass.Context.TURN})

	assert_true(result.get("ok", false), "[STRIDE, STRIDE] with STRIDE's current VerbResource carrying Repeat must be legal")
	assert_eq(result.get("actions_spent"), 1, "a legal execute() call must charge exactly one action")
	assert_eq(result.get("stamina_spent"), 1, "a legal execute() call must charge exactly one Stamina")
	assert_eq(economy.spend_action_call_count, 1, "the action-economy port must be charged exactly once on a legal execute() call")
	assert_eq(actor.stamina, 0, "a legal execute() call must decrement the actor's Stamina by one")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — the happy-path [STRIDE, STRIKE] queue remains green,
# unaffected by the new validation gate.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_happy_path_stride_then_strike_still_succeeds() -> void:
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var economy := FakeActionEconomyPort.new()
	var actor := _make_actor(1)
	var controller := CombineActionControllerClass.new({
		"verb_registry_port": port,
		"action_economy_port": economy,
	})
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]

	var result: Dictionary = controller.execute({"queue": queue, "actor": actor, "context": CombineQueueClass.Context.TURN})

	assert_true(result.get("ok", false), "[STRIDE, STRIKE] -- two different verbs -- must still succeed")
	assert_eq(result.get("error_code"), "")
	assert_eq(result.get("actions_spent"), 1)
	assert_eq(result.get("stamina_spent"), 1)
	assert_eq(actor.stamina, 0)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — ValidateCombineQueueUseCase is invoked as the FIRST
# statement in execute(), strictly before any action-economy charge.
# ══════════════════════════════════════════════════════════════════════════

func test_validation_gate_runs_before_action_economy_charge() -> void:
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var call_log: Array = []
	var spy_validate := SpyValidateUseCase.new(call_log)
	var spy_economy := SpyActionEconomyPort.new(call_log)
	var actor := _make_actor(1)
	var controller := CombineActionControllerClass.new({
		"validate_combine_queue_use_case": spy_validate,
		"verb_registry_port": port,
		"action_economy_port": spy_economy,
	})
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]

	var result: Dictionary = controller.execute({"queue": queue, "actor": actor, "context": CombineQueueClass.Context.TURN})

	assert_true(result.get("ok", false), "the legal queue backing this call-order check must itself succeed")
	assert_eq(call_log, ["validate", "charge_action_economy"], "ValidateCombineQueueUseCase must run strictly before the action-economy charge")


func test_validation_gate_runs_before_action_economy_charge_even_when_it_rejects() -> void:
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var call_log: Array = []
	var spy_validate := SpyValidateUseCase.new(call_log)
	var spy_economy := SpyActionEconomyPort.new(call_log)
	var actor := _make_actor(1)
	var controller := CombineActionControllerClass.new({
		"validate_combine_queue_use_case": spy_validate,
		"verb_registry_port": port,
		"action_economy_port": spy_economy,
	})

	var result: Dictionary = controller.execute({"queue": _double_stride_queue(), "actor": actor, "context": CombineQueueClass.Context.TURN})

	assert_false(result.get("ok", true), "an illegal queue must still be rejected with a spy use case wired in")
	assert_eq(call_log, ["validate"], "a rejected validation must never reach the action-economy charge at all")
