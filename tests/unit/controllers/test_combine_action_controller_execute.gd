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
##
## FEAT-002 (US-002; FR-001/FR-003) regression coverage — added when
## enter_selection() was wired: CombineActionController.enter_selection()
## must delegate to core/application/combine/build_verb_queue_use_case.gd's
## BuildVerbQueueUseCase and return a REAL SelectionDescriptor (ok,
## candidate_options, candidate_hexes, candidate_targets, order_index, meta)
## rather than the original bare {ok, queue}-only Dictionary this
## controller used to be limited to.
##   5. enter_selection() at an empty queue (context.queue omitted) offers
##      both STRIDE and STRIKE in candidate_options, ok=true.
##   6. enter_selection() excludes STRIDE from candidate_options once
##      STRIDE is already in the queue (no Repeat trait on the current
##      data/verbs/stride.tres), routed through the SAME
##      BuildVerbQueueUseCase this controller now delegates to.
##   7. The returned Object is a SelectionDescriptor (ok/candidate_options/
##      candidate_hexes/candidate_targets/order_index/meta), never a bare
##      {ok, queue} Dictionary.

const CombineActionControllerClass = preload("res://core/controllers/combine_action_controller.gd")
const ValidateCombineQueueUseCaseClass = preload("res://core/application/combine/validate_combine_queue_use_case.gd")
const VerbRegistryPortClass = preload("res://core/application/combine/verb_registry_port.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const VerbResourceClass = preload("res://core/resources/verb_resource.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const SelectionDescriptorClass = preload("res://core/domain/combine/selection_descriptor.gd")

const STRIDE_RESOURCE_PATH: String = "res://data/verbs/stride.tres"
const STRIKE_RESOURCE_PATH: String = "res://data/verbs/strike.tres"
const CAST_SPELL_RESOURCE_PATH: String = "res://data/verbs/cast_spell.tres"

## MAIN_SCENE_PATH / PROLOGUE_SEED — FEAT-297 (resolves DEF-NEW-002): the
## boot-real fixture this suite's own "single controller instance" criterion
## (below) drives, mirroring every other boot-real suite's identically-named
## constants (e.g. tests/integration/test_combine_execute_stride_then_strike.gd).
const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const PROLOGUE_SEED: int = 42
const PROLOGUE_ENCOUNTER_ID: String = "prologue"


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
##
## FEAT-307 (US-004; resolves FIND-305) ADDS `action_available` (default
## true) and `has_action_available()` -- the SAME non-mutating economy-
## availability query name core/rules/action_economy.gd's FEAT-307 alias
## exposes -- so this suite can configure a port that reports "no action
## available" (e.g. mirroring an already-used-action combatant) without ever
## touching spend_action() itself, proving execute()'s new preflight gate
## consults this query rather than (mutatively) spending first.
class FakeActionEconomyPort:
	var spend_action_call_count: int = 0
	var action_available: bool = true

	func spend_action(_action_metadata: Dictionary) -> Dictionary:
		spend_action_call_count += 1
		return {"success": true, "ok": true}

	func has_action_available() -> bool:
		return action_available


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

	## has_action_available() — FEAT-307: logs "preflight_check" so this
	## suite's call-order criterion can additionally assert the new
	## non-mutating preflight gate runs strictly between "validate" and
	## "charge_action_economy" -- never after the charge, never skipped.
	func has_action_available() -> bool:
		call_log.append("preflight_check")
		return true


## FakeSubController — FEAT-297 (resolves DEF-NEW-002): a minimal
## VerbControllerPort/ActionController-shaped double standing in for
## presentation/stride_action_controller.gd or
## presentation/strike_action_controller.gd — the REAL sub-action
## controllers a live `controller_for` resolver hands back. Records every
## `execute()` call (verb_id, the selection payload it was dispatched with,
## and the no_self_spend_execution flag) onto a SHARED `call_log`, so this
## suite can assert both dispatch ORDER and the exact targeting payload each
## sub-action received, mirroring
## tests/integration/test_combine_execute_stride_then_strike.gd's own
## established "spy wraps the real controller_for" convention -- except this
## suite's own controller_for is a lightweight fake registry (no live
## MainScene boot required) for FAST, isolated unit coverage.
class FakeSubController:
	var verb_id: String
	var _call_log: Array
	var _response: Dictionary

	func _init(p_verb_id: String, call_log: Array, response: Dictionary) -> void:
		verb_id = p_verb_id
		_call_log = call_log
		_response = response

	func execute(selection = null, no_self_spend_execution: bool = false) -> Dictionary:
		_call_log.append({"verb_id": verb_id, "selection": selection, "no_self_spend_execution": no_self_spend_execution})
		return _response


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


func _double_cast_spell_queue() -> Array:
	return [
		VerbQueueEntryClass.new("q1", 0, "CAST_SPELL"),
		VerbQueueEntryClass.new("q1", 1, "CAST_SPELL"),
	]


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
	# Synthetic non-repeat STRIDE so this test is independent of the shipped
	# data/verbs/stride.tres (which carries repeat=true as of fa7eacc).
	var port := FakeVerbRegistryPort.new([_non_repeat_stride_resource()])
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
	assert_eq(
		call_log, ["validate", "preflight_check", "charge_action_economy"],
		"ValidateCombineQueueUseCase must run first, then the FEAT-307 non-mutating preflight, then (only once both pass) the action-economy charge"
	)


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

	# CAST_SPELL has repeat=false, so [CAST_SPELL, CAST_SPELL] is illegal and
	# must be rejected at the validation step -- never reaching economy charge.
	var result: Dictionary = controller.execute({"queue": _double_cast_spell_queue(), "actor": actor, "context": CombineQueueClass.Context.TURN})

	assert_false(result.get("ok", true), "an illegal queue must still be rejected with a spy use case wired in")
	assert_eq(call_log, ["validate"], "a rejected validation must never reach the action-economy charge at all")


# ══════════════════════════════════════════════════════════════════════════
# FEAT-307 (US-004; resolves FIND-305, critical) — a non-mutating preflight
# economy/Stamina gate runs strictly between the DEF-001 validation gate
# above and `_dispatch_sub_actions()` -- the real Stride move / real Strike
# damage -- guaranteeing ZERO world mutation when the actor cannot actually
# afford the Combine.
# ══════════════════════════════════════════════════════════════════════════

func _wired_sub_action_registry(call_log: Array) -> Dictionary:
	return {
		"STRIDE": FakeSubController.new("STRIDE", call_log, {"ok": true}),
		"STRIKE": FakeSubController.new("STRIKE", call_log, {"ok": true}),
	}


func test_execute_rejects_when_action_economy_reports_no_action_available() -> void:
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var economy := FakeActionEconomyPort.new()
	economy.action_available = false  # e.g. the actor already used their one action this turn
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

	assert_false(result.get("ok", true), "execute() must reject when the action-economy port reports no action available")
	assert_eq(result.get("error_code"), "INSUFFICIENT_RESOURCES")
	assert_eq(result.get("actions_spent"), 0, "a preflight-rejected execute() call must spend zero actions")
	assert_eq(result.get("stamina_spent"), 0, "a preflight-rejected execute() call must spend zero Stamina")
	assert_eq(economy.spend_action_call_count, 0, "the preflight gate must reject BEFORE the action-economy port is ever CHARGED (spend_action())")
	assert_eq(actor.stamina, 1, "a preflight-rejected execute() call must leave the actor's Stamina untouched")
	assert_eq(actor.spend_stamina_call_count, 0, "a preflight-rejected execute() call must never reach Combatant.spend_stamina()")


func test_execute_rejects_when_actor_stamina_is_zero() -> void:
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var economy := FakeActionEconomyPort.new()  # action economy otherwise available (action_available defaults true)
	var actor := _make_actor(0)
	var controller := CombineActionControllerClass.new({
		"verb_registry_port": port,
		"action_economy_port": economy,
	})
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]

	var result: Dictionary = controller.execute({"queue": queue, "actor": actor, "context": CombineQueueClass.Context.TURN})

	assert_false(result.get("ok", true), "execute() must reject when the actor's Stamina is 0")
	assert_eq(result.get("error_code"), "INSUFFICIENT_RESOURCES")
	assert_eq(result.get("actions_spent"), 0, "a preflight-rejected execute() call must spend zero actions")
	assert_eq(result.get("stamina_spent"), 0, "a preflight-rejected execute() call must spend zero Stamina")
	assert_eq(economy.spend_action_call_count, 0, "the action-economy port must never be charged once the preflight Stamina check rejects")
	assert_eq(actor.stamina, 0, "a preflight-rejected execute() call must leave the actor's (already-zero) Stamina untouched")
	assert_eq(actor.spend_stamina_call_count, 0, "a preflight-rejected execute() call must never reach Combatant.spend_stamina()")


func test_execute_preflight_action_unavailable_never_dispatches_sub_actions_or_mutates_actor_position() -> void:
	# Criteria 3 + 5: no world mutation occurs on the preflight-failure path --
	# proven via a spy on `_dispatch_sub_actions()`'s own sub-controllers
	# (FakeSubController) showing ZERO invocations, and the actor's own
	# hex_coord (Stride's would-be mutation target) staying byte-for-byte
	# unchanged.
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var economy := FakeActionEconomyPort.new()
	economy.action_available = false
	var actor := _make_actor(1)
	var starting_hex := actor.hex_coord
	var call_log: Array = []
	var registry := _wired_sub_action_registry(call_log)
	var controller := CombineActionControllerClass.new({
		"verb_registry_port": port,
		"action_economy_port": economy,
		"controller_for": func(verb_id: String): return registry.get(verb_id),
	})
	var stride_destination := HexCoordClass.new(2, 0)
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]
	var accumulated: Dictionary = {
		"STRIDE": _stride_descriptor(stride_destination),
		"STRIKE": _strike_descriptor(["skeleton_1"], stride_destination),
	}

	var result: Dictionary = controller.execute({
		"queue": queue, "actor": actor, "context": CombineQueueClass.Context.TURN, "accumulated": accumulated,
	})

	assert_false(result.get("ok", true), "a preflight rejection must still report ok=false with the real controller_for resolver wired")
	assert_eq(result.get("error_code"), "INSUFFICIENT_RESOURCES")
	assert_eq(result.get("resolution_log"), [], "resolution_log must stay empty -- _dispatch_sub_actions() must never even begin")
	assert_eq(call_log.size(), 0, "neither STRIDE nor STRIKE's sub-controller may ever be dispatched once the preflight gate rejects")
	assert_true(actor.hex_coord.equals(starting_hex), "the actor's position must be completely unchanged -- Stride's own effect never dispatched")


func test_execute_preflight_zero_stamina_never_dispatches_sub_actions_or_mutates_actor_position() -> void:
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var economy := FakeActionEconomyPort.new()
	var actor := _make_actor(0)
	var starting_hex := actor.hex_coord
	var call_log: Array = []
	var registry := _wired_sub_action_registry(call_log)
	var controller := CombineActionControllerClass.new({
		"verb_registry_port": port,
		"action_economy_port": economy,
		"controller_for": func(verb_id: String): return registry.get(verb_id),
	})
	var stride_destination := HexCoordClass.new(2, 0)
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]
	var accumulated: Dictionary = {
		"STRIDE": _stride_descriptor(stride_destination),
		"STRIKE": _strike_descriptor(["skeleton_1"], stride_destination),
	}

	var result: Dictionary = controller.execute({
		"queue": queue, "actor": actor, "context": CombineQueueClass.Context.TURN, "accumulated": accumulated,
	})

	assert_false(result.get("ok", true), "a preflight rejection must still report ok=false with the real controller_for resolver wired")
	assert_eq(result.get("error_code"), "INSUFFICIENT_RESOURCES")
	assert_eq(result.get("resolution_log"), [], "resolution_log must stay empty -- _dispatch_sub_actions() must never even begin")
	assert_eq(call_log.size(), 0, "neither STRIDE nor STRIKE's sub-controller may ever be dispatched once the preflight Stamina check rejects")
	assert_true(actor.hex_coord.equals(starting_hex), "the actor's position must be completely unchanged -- Stride's own effect never dispatched")


func test_execute_happy_path_unaffected_by_preflight_gate_when_resources_are_sufficient() -> void:
	# Regression guard (test_criteria #4): sufficient action + Stamina still
	# succeeds and still dispatches/charges exactly as before -- the FEAT-307
	# gate is additive, never a behavior change to the legal/affordable path.
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

	assert_true(result.get("ok", false), "sufficient action + Stamina must still succeed with the FEAT-307 preflight gate in place")
	assert_eq(result.get("actions_spent"), 1)
	assert_eq(result.get("stamina_spent"), 1)
	assert_eq(economy.spend_action_call_count, 1)
	assert_eq(actor.stamina, 0)


# ══════════════════════════════════════════════════════════════════════════
# FEAT-002 — enter_selection() delegates to BuildVerbQueueUseCase and
# returns a real SelectionDescriptor, not a bare {ok, queue} Dictionary.
# ══════════════════════════════════════════════════════════════════════════

func _option_ids(candidate_options: Array) -> Array:
	var ids: Array = []
	for option in candidate_options:
		ids.append(option.get("id"))
	return ids


func test_enter_selection_at_empty_queue_offers_stride_and_strike() -> void:
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var actor := _make_actor(1)
	var controller := CombineActionControllerClass.new({"verb_registry_port": port})

	var descriptor = controller.enter_selection({"actor_id": actor, "mode": "BUILD_QUEUE", "combine_context": CombineQueueClass.Context.TURN})

	assert_true(descriptor.ok, "an empty queue with a live actor + registry must offer at least one legal candidate")
	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_true(ids.has("STRIDE"), "candidate_options must include STRIDE at an empty queue")
	assert_true(ids.has("STRIKE"), "candidate_options must include STRIKE at an empty queue")


func test_enter_selection_stride_remains_offered_once_queued_with_repeat() -> void:
	# data/verbs/stride.tres carries repeat=true, so STRIDE must remain offered
	# even after being queued once. The no-Repeat exclusion rule is still
	# exercised via CAST_SPELL (repeat=false) in the separate non-repeat test.
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var actor := _make_actor(1)
	var controller := CombineActionControllerClass.new({"verb_registry_port": port})
	var queue: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	var descriptor = controller.enter_selection({
		"actor_id": actor,
		"mode": "BUILD_QUEUE",
		"combine_context": CombineQueueClass.Context.TURN,
		"queue": queue,
	})

	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_true(ids.has("STRIDE"), "STRIDE (repeat=true) must remain offered after being queued once")
	assert_true(ids.has("STRIKE"), "STRIKE must still be offered")
	assert_true(descriptor.ok, "ok must remain true with legal options remaining")


func test_enter_selection_returns_a_real_selection_descriptor_not_a_bare_ok_queue_dict() -> void:
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var actor := _make_actor(1)
	var controller := CombineActionControllerClass.new({"verb_registry_port": port})

	var descriptor = controller.enter_selection({"actor_id": actor, "mode": "BUILD_QUEUE", "combine_context": CombineQueueClass.Context.TURN})

	assert_false(descriptor is Dictionary, "enter_selection() must return a SelectionDescriptor object, not a bare Dictionary")
	assert_true(descriptor.ok is bool, "the returned SelectionDescriptor must carry an `ok` field")
	assert_true(descriptor.candidate_options is Array, "the returned SelectionDescriptor must carry a `candidate_options` field")
	assert_true(descriptor.candidate_hexes is Array, "the returned SelectionDescriptor must carry a `candidate_hexes` field")
	assert_true(descriptor.candidate_targets is Array, "the returned SelectionDescriptor must carry a `candidate_targets` field")
	assert_true(descriptor.meta is Dictionary, "the returned SelectionDescriptor must carry a `meta` field")


func test_enter_selection_degrades_safely_with_no_live_actor() -> void:
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var controller := CombineActionControllerClass.new({"verb_registry_port": port})

	var descriptor = controller.enter_selection({"mode": "BUILD_QUEUE", "combine_context": CombineQueueClass.Context.TURN})

	assert_false(descriptor.ok, "enter_selection() with no live actor must fail closed, not crash")


# ══════════════════════════════════════════════════════════════════════════
# FEAT-297 (Iteration O; US-004/005/006; resolves DEF-NEW-002) — execute(),
# after the DEF-001 gate passes, dispatches the REAL Stride-then-Strike
# sub-action chain and populates resolution_log. This is the fix for
# DEF-NEW-002: two disconnected CombineActionController classes existed —
# THIS controller (core/controllers/combine_action_controller.gd, wired live
# into MultiPhaseTargetingController) only re-validated and charged economy;
# presentation/combine_action_controller.gd DID dispatch real sub-actions but
# was never reached by the live interactive flow. The sub-action dispatch is
# now merged into THIS controller's own execute().
# ══════════════════════════════════════════════════════════════════════════

func _stride_descriptor(chosen_hex) -> Object:
	return SelectionDescriptorClass.new(true, [], [chosen_hex], [], 0, {"chosen_hex": chosen_hex})


func _strike_descriptor(candidate_targets: Array, origin_hex = null) -> Object:
	return SelectionDescriptorClass.new(true, [], [], candidate_targets, 1, {"origin_hex": origin_hex})


func test_execute_dispatches_stride_then_strike_in_order_index_order_and_populates_resolution_log() -> void:
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var economy := FakeActionEconomyPort.new()
	var actor := _make_actor(1)
	var call_log: Array = []
	var stride_response := {"ok": true, "resolved": true}
	var strike_response := {"ok": true, "resolved": true, "damage_final": 5}
	var registry := {
		"STRIDE": FakeSubController.new("STRIDE", call_log, stride_response),
		"STRIKE": FakeSubController.new("STRIKE", call_log, strike_response),
	}
	var controller := CombineActionControllerClass.new({
		"verb_registry_port": port,
		"action_economy_port": economy,
		"controller_for": func(verb_id: String): return registry.get(verb_id),
	})
	var stride_destination := HexCoordClass.new(2, 0)
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]
	var accumulated: Dictionary = {
		"STRIDE": _stride_descriptor(stride_destination),
		"STRIKE": _strike_descriptor(["skeleton_1"], stride_destination),
	}

	var result: Dictionary = controller.execute({
		"queue": queue, "actor": actor, "context": CombineQueueClass.Context.TURN, "accumulated": accumulated,
	})

	assert_true(result.get("ok", false), "a fully-dispatched STRIDE+STRIKE Combine must resolve ok=true (result: %s)" % [result])

	var log: Array = result.get("resolution_log", [])
	assert_eq(log.size(), 2, "resolution_log must carry exactly one entry per dispatched sub-action")
	assert_eq(log[0].get("verb_id"), "STRIDE")
	assert_eq(log[0].get("outcome"), stride_response, "resolution_log's STRIDE entry must carry StrideActionController.execute()'s own real outcome verbatim")
	assert_eq(log[1].get("verb_id"), "STRIKE")
	assert_eq(log[1].get("outcome"), strike_response, "resolution_log's STRIKE entry must carry StrikeActionController.execute()'s own real outcome verbatim")

	assert_eq(call_log.size(), 2, "exactly one execute() call per sub-action")
	assert_eq(call_log[0].get("verb_id"), "STRIDE", "STRIDE must be dispatched BEFORE STRIKE (order_index order)")
	assert_eq(call_log[1].get("verb_id"), "STRIKE")
	assert_true(call_log[0].get("selection").equals(stride_destination), "STRIDE must be dispatched with its own resolved chosen_hex")
	assert_eq(call_log[1].get("selection"), "skeleton_1", "STRIKE must be dispatched with a real, post-move-computed candidate target")
	assert_eq(call_log[0].get("no_self_spend_execution"), true, "sub-actions must dispatch under no-self-spend execution -- the Combine charges the ONE real action/Stamina, not each sub-action")
	assert_eq(call_log[1].get("no_self_spend_execution"), true)

	assert_eq(result.get("actions_spent"), 1, "a fully-dispatched Combine must still charge exactly one action")
	assert_eq(result.get("stamina_spent"), 1, "a fully-dispatched Combine must still charge exactly one Stamina")


func test_execute_strike_dispatch_targets_the_first_post_move_computed_candidate_when_no_explicit_pick_was_recorded() -> void:
	# Iteration O's core StrikeActionController (core/controllers/strike_action_controller.gd)
	# computes candidate_targets from the accumulated STRIDE's post-move hex
	# (ADR-006) but does not itself record which candidate a player clicked.
	# Dispatch must still target a REAL, post-move-reachable candidate --
	# never a stale pre-move one -- rather than failing to dispatch at all.
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var economy := FakeActionEconomyPort.new()
	var actor := _make_actor(1)
	var call_log: Array = []
	var registry := {
		"STRIDE": FakeSubController.new("STRIDE", call_log, {"ok": true}),
		"STRIKE": FakeSubController.new("STRIKE", call_log, {"ok": true}),
	}
	var controller := CombineActionControllerClass.new({
		"verb_registry_port": port,
		"action_economy_port": economy,
		"controller_for": func(verb_id: String): return registry.get(verb_id),
	})
	var stride_destination := HexCoordClass.new(2, 0)
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]
	var accumulated: Dictionary = {
		"STRIDE": _stride_descriptor(stride_destination),
		"STRIKE": _strike_descriptor(["goblin_2", "goblin_3"], stride_destination),
	}

	controller.execute({"queue": queue, "actor": actor, "context": CombineQueueClass.Context.TURN, "accumulated": accumulated})

	assert_eq(call_log[1].get("selection"), "goblin_2", "with no explicit chosen target recorded, STRIKE must dispatch against the first real, POST-move-computed reachable candidate")


func test_execute_aborts_with_zero_economy_and_no_strike_dispatch_when_stride_sub_action_fails() -> void:
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var economy := FakeActionEconomyPort.new()
	var actor := _make_actor(1)
	var call_log: Array = []
	var registry := {
		"STRIDE": FakeSubController.new("STRIDE", call_log, {"ok": false, "error": "ERR_ILLEGAL_SUB_TARGET"}),
		"STRIKE": FakeSubController.new("STRIKE", call_log, {"ok": true}),
	}
	var controller := CombineActionControllerClass.new({
		"verb_registry_port": port,
		"action_economy_port": economy,
		"controller_for": func(verb_id: String): return registry.get(verb_id),
	})
	var stride_destination := HexCoordClass.new(2, 0)
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]
	var accumulated: Dictionary = {
		"STRIDE": _stride_descriptor(stride_destination),
		"STRIKE": _strike_descriptor(["skeleton_1"], stride_destination),
	}

	var result: Dictionary = controller.execute({"queue": queue, "actor": actor, "context": CombineQueueClass.Context.TURN, "accumulated": accumulated})

	assert_false(result.get("ok", true), "a failing sub-action must abort the whole Combine")
	assert_eq(result.get("actions_spent"), 0, "an aborted dispatch must spend zero actions -- no orphaned spend")
	assert_eq(result.get("stamina_spent"), 0, "an aborted dispatch must spend zero Stamina -- no orphaned spend")
	assert_eq(economy.spend_action_call_count, 0, "the action-economy port must never be charged once a sub-action fails")
	assert_eq(actor.spend_stamina_call_count, 0, "Combatant.spend_stamina() must never be reached once a sub-action fails")

	assert_eq(call_log.size(), 1, "STRIKE must NEVER be dispatched once the preceding STRIDE fails")
	var log: Array = result.get("resolution_log", [])
	assert_eq(log.size(), 1, "resolution_log must still record the failing STRIDE attempt")
	assert_eq(log[0].get("verb_id"), "STRIDE")
	assert_false(log[0].get("outcome").get("ok", true))


func test_execute_skips_dispatch_entirely_when_no_controller_for_resolver_is_wired() -> void:
	# Pre-FEAT-297 degrade path (every criterion-1..4 test in this suite,
	# above, exercises exactly this): with no `controller_for` resolver
	# injected, execute() must still validate-then-charge exactly as before,
	# with an empty (never null) resolution_log.
	var port := FakeVerbRegistryPort.new(_stride_and_strike_pool())
	var economy := FakeActionEconomyPort.new()
	var actor := _make_actor(1)
	var controller := CombineActionControllerClass.new({"verb_registry_port": port, "action_economy_port": economy})
	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]

	var result: Dictionary = controller.execute({"queue": queue, "actor": actor, "context": CombineQueueClass.Context.TURN})

	assert_true(result.get("ok", false))
	assert_eq(result.get("resolution_log"), [], "with no controller_for resolver wired, resolution_log must be an empty Array, not missing/null")


# ══════════════════════════════════════════════════════════════════════════
# FEAT-297 test_criteria #4 — presentation/combine_action_controller.gd is no
# longer independently reachable from the LIVE dispatch seam: a single
# controller instance (core/controllers/combine_action_controller.gd's
# CombineActionController) handles both the DEF-001 validation gate AND the
# real sub-action dispatch for the live COMBINE verb, reached through
# MultiPhaseTargetingController -- the actual live signal chain
# selection_overlay.selection_resolved ultimately drives (see MainScene.gd's
## own start_combine_targeting()/_finish_combine_targeting() doc).
# ══════════════════════════════════════════════════════════════════════════

## FEAT-316 (resolves DEF-001/PR-001): MainScene now boots into EXPLORATION
## mode with the legacy combat pipeline (round_session, verb bar/selection
## overlay configuration, turn_controller signal wiring) gated behind a real
## _on_combat_triggered() handoff -- see MainScene.gd's own FEAT-316 doc.
## This suite drives the live _core_combine_action_controller/round_session,
## so _boot_main_scene() now also drives that SAME real handoff (mirroring
## tests/boot/test_first_cast_firebolt.gd's established convention), landing
## the instance in GameMode.COMBAT with a live round_session before returning.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


func test_live_signal_chain_dispatches_through_a_single_combine_action_controller_instance() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance._core_combine_action_controller, "the composition root must construct a real core CombineActionController")
	assert_true(instance._core_combine_action_controller is CombineActionControllerClass, "_core_combine_action_controller must be a real core/controllers/combine_action_controller.gd instance")

	# The SAME instance is the one MultiPhaseTargetingController -- the real
	# object the live selection_resolved signal chain ultimately drives via
	# start_combine_targeting()/_finish_combine_targeting() -- invokes on
	# loop exhaustion. Never a second/forked instance.
	assert_same(
		instance._core_combine_action_controller,
		instance.multi_phase_targeting_controller._combine_action_controller,
		"MultiPhaseTargetingController must dispatch through the EXACT SAME CombineActionController instance this feature wires controller_for onto"
	)

	# FEAT-297: that SAME instance must now carry a real, live controller_for
	# resolver -- the wiring that lets it actually dispatch Stride/Strike,
	# not just validate-then-charge.
	assert_true(
		instance._core_combine_action_controller._controller_for_fn.is_valid(),
		"the live core CombineActionController must carry a real controller_for resolver so it performs real sub-action dispatch (FEAT-297)"
	)

	# The live sub-action registry MultiPhaseTargetingController resolves
	# STRIDE/STRIKE through never itself contains a "COMBINE" entry -- a
	# Combine can never recursively dispatch into a second/independent
	# COMBINE-handling controller through this seam.
	assert_false(
		instance._combine_controller_registry.has("COMBINE"),
		"the live sub-action registry must never route COMBINE back through a second controller"
	)


# ══════════════════════════════════════════════════════════════════════════
# FEAT-298 (resolves DEF-NEW-003) — MainScene.gd's composition root must
# inject a real, non-null `action_economy_port` into `_core_combine_action_
# controller` so a successful live-wired execute() actually charges the
# documented 1-action cost (FR-007) alongside the 1-Stamina cost, rather
# than `_charge_action_economy()` silently skipping the action charge
# because `_action_economy_port` was null.
# ══════════════════════════════════════════════════════════════════════════

## SKELETON_REPOSITIONED_HEX_Q / STRIDE_DESTINATION_HEX_Q — mirrors
## tests/e2e/combine/test_charge_end_to_end.gd's own established fixture
## geometry: repositions the Skeleton (test-fixture-only) out of Titus's
## melee reach but adjacent to a hex already within his real, boot-time-
## computed legal Stride destination set, so a real Charge (Stride then
## Strike) genuinely succeeds end-to-end.
const SKELETON_REPOSITIONED_HEX_Q: int = 3
const STRIDE_DESTINATION_HEX_Q: int = 2


func test_main_scene_constructs_core_combine_action_controller_with_a_non_null_action_economy_port() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance._core_combine_action_controller, "the composition root must construct a real core CombineActionController")
	assert_not_null(
		instance._core_combine_action_controller._action_economy_port,
		"DEF-NEW-003: MainScene.gd's composition root must inject a non-null action_economy_port into _core_combine_action_controller"
	)


func test_live_wired_controller_charges_one_action_and_one_stamina_on_successful_execute() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var titus = instance._party[0]
	var skeleton = instance._enemies[0]
	skeleton.hex_coord = HexCoordClass.new(SKELETON_REPOSITIONED_HEX_Q, 0)
	var stride_destination := HexCoordClass.new(STRIDE_DESTINATION_HEX_Q, 0)

	var stride_controller = instance._combine_controller_registry["STRIDE"]
	var strike_controller = instance._combine_controller_registry["STRIKE"]

	var stride_offer = stride_controller.enter_selection({"actor_id": titus, "order_index": 0})
	assert_true(stride_offer.ok, "fixture assumption: Titus has at least one legal Stride destination at boot")
	var chosen_hex = null
	for h in stride_offer.candidate_hexes:
		if h.equals(stride_destination):
			chosen_hex = h
			break
	assert_not_null(chosen_hex, "fixture assumption: the intended Stride destination must be a legal candidate")

	var resolved_stride = stride_controller.enter_selection({"actor_id": titus, "order_index": 0, "selected_hex": chosen_hex})
	assert_true(resolved_stride.ok)

	var strike_offer = strike_controller.enter_selection({
		"actor_id": titus, "order_index": 1, "accumulated": {"STRIDE": resolved_stride},
	})
	assert_true(strike_offer.ok, "fixture assumption: the repositioned Skeleton must be reachable from the chosen Stride hex")
	assert_true(strike_offer.candidate_targets.has(skeleton.display_id()))

	var economy = instance._verb_bar_current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var actions_before: int = economy.get_remaining()
	var stamina_before: int = titus.stamina
	assert_true(stamina_before > 0)

	var queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]
	var accumulated: Dictionary = {"STRIDE": resolved_stride, "STRIKE": strike_offer}

	var result: Dictionary = instance._core_combine_action_controller.execute({
		"queue": queue, "actor": titus, "context": CombineQueueClass.Context.TURN, "accumulated": accumulated,
	})

	assert_true(result.get("ok", false), "a valid, real COMBINE Charge dispatched through the live-wired controller must succeed (result: %s)" % [result])
	assert_eq(result.get("actions_spent"), 1, "execute()'s own Dictionary must report exactly one action spent")
	assert_eq(result.get("stamina_spent"), 1, "execute()'s own Dictionary must report exactly one Stamina spent")

	# The REAL, live ActionEconomy — not just execute()'s reported Dictionary
	# — must reflect exactly one action spent (DEF-NEW-003's own regression:
	# before this feature, actions_spent stayed 0 because the injected
	# action_economy_port was null and _charge_action_economy() silently
	# skipped the charge).
	assert_eq(actions_before - economy.get_remaining(), 1, "the live ActionEconomy.get_remaining() must reflect exactly one action spent, not zero")
	assert_eq(stamina_before - titus.stamina, 1, "the live actor's Stamina must reflect exactly one Stamina spent")


func test_live_wired_controller_validation_failed_path_still_charges_zero_actions_and_stamina() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var titus = instance._party[0]
	var economy = instance._verb_bar_current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var actions_before: int = economy.get_remaining()
	var stamina_before: int = titus.stamina

	# [CAST_SPELL, CAST_SPELL] is illegal (DEF-001, repeat=false on cast_spell.tres)
	# -- the ValidateCombineQueueUseCase gate must reject it BEFORE
	# _charge_action_economy() is ever reached, through the SAME live-wired
	# instance FEAT-298 injects a real action_economy_port into.
	# (stride.tres carries repeat=true so [STRIDE, STRIDE] is now a valid combo.)
	var result: Dictionary = instance._core_combine_action_controller.execute({
		"queue": _double_cast_spell_queue(), "actor": titus, "context": CombineQueueClass.Context.TURN,
	})

	assert_false(result.get("ok", true), "an illegal [CAST_SPELL, CAST_SPELL] combo must still report ok=false through the live-wired controller")
	assert_eq(result.get("error_code"), "VALIDATION_FAILED")
	assert_eq(result.get("actions_spent"), 0, "a rejected live-wired execute() call must spend zero actions")
	assert_eq(result.get("stamina_spent"), 0, "a rejected live-wired execute() call must spend zero Stamina")
	assert_eq(economy.get_remaining(), actions_before, "the live ActionEconomy must be completely untouched by a rejected execute() call")
	assert_eq(titus.stamina, stamina_before, "the live actor's Stamina must be completely untouched by a rejected execute() call")
