## core/application/use_cases/short_rest_mage_recharge_use_case.gd —
## ShortRestMageRechargeUseCase (FEAT-005 / US-005; FR-006, NFR-001;
## iteration AB-0, rest mechanics steel thread).
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (core/domain/combatant.gd's Combatant / an equipped ItemResource-shaped
## object, via duck-typed field access — no static type dependency on either
## parameter), mirroring core/application/use_cases/short_rest_heal_use_case.gd
## and core/application/use_cases/long_rest_use_case.gd's identical
## convention, and core/application/ports/errors.gd's ErrorCode vocabulary.
## Extends RefCounted only: no Node/Control/SceneTree inheritance, no engine
## lifecycle coupling (ADR-001).
##
## api_contracts #4: execute(combatant, item) recharges a single discharged
## Mage-paradigm equipped item during a Short Rest, spending
## item.energy_cost from combatant.mage_recharge_budget_remaining. Validated
## in this EXACT order — first failure wins, no side effects on failure
## (error_handling design note: "No side effects before all validations
## pass"):
##   a. item == null OR item.is_charged == true      -> ERR_ITEM_ALREADY_CHARGED
##   b. item.energy_cost <= 0                         -> ERR_NOT_DISCHARGEABLE
##   c. combatant.mage_recharge_budget_remaining <
##        item.energy_cost                            -> ERR_INSUFFICIENT_BUDGET
##
## On success, item.is_charged is set true and
## combatant.mage_recharge_budget_remaining is decremented by
## item.energy_cost — applied ATOMICALLY (both mutations happen together, in
## the same call, or neither happens at all).
##
## Returns {success: true, budget_spent: int, budget_remaining: int} on
## success, or {success: false, error: <ErrorCode int>} on any validation
## failure.

class_name ShortRestMageRechargeUseCase
extends RefCounted

const ErrorCodeClass = preload("res://core/application/ports/errors.gd")


## execute(combatant, item) -> Dictionary — api_contracts #4. `combatant` and
## `item` are duck-typed, domain-shaped objects (real core/domain/combatant.gd
## Combatant / core/resources/item_resource.gd ItemResource instances in
## production; duck-typed doubles in tests) exposing
## mage_recharge_budget_remaining / is_charged+energy_cost as plain fields,
## mirroring ShortRestHealUseCase.execute()'s direct field access convention.
func execute(combatant, item) -> Dictionary:
	var is_charged: bool = bool(_duck_get(item, "is_charged", true)) if item != null else true
	if item == null or is_charged:
		return _fail(ErrorCodeClass.ERR_ITEM_ALREADY_CHARGED)

	var energy_cost: int = int(_duck_get(item, "energy_cost", 0))
	if energy_cost <= 0:
		return _fail(ErrorCodeClass.ERR_NOT_DISCHARGEABLE)

	var budget_remaining: int = int(_duck_get(combatant, "mage_recharge_budget_remaining", 0))
	if budget_remaining < energy_cost:
		return _fail(ErrorCodeClass.ERR_INSUFFICIENT_BUDGET)

	# Atomic: both mutations are applied together, right here, with no
	# intervening validation/return that could leave one applied without
	# the other.
	item.is_charged = true
	var new_budget_remaining: int = budget_remaining - energy_cost
	combatant.mage_recharge_budget_remaining = new_budget_remaining

	return {"success": true, "budget_spent": energy_cost, "budget_remaining": new_budget_remaining}


func _fail(error_code: int) -> Dictionary:
	return {"success": false, "error": error_code}


## _duck_get(obj, key, default) -> Variant — the SAME defensive duck-typed
## field read established by BeginCastUseCase._duck_get() / LongRestUseCase
## ._duck_get() / ShortRestHealUseCase._duck_get(): tolerates `obj` being a
## Dictionary (`.get(key, default)`), an Object exposing `key` as a real
## property (`Object.get(key)`, itself null-safe for an undeclared property),
## or null (falls back to `default`) — never raises.
func _duck_get(obj, key: String, default = null):
	if obj == null:
		return default
	if obj is Dictionary:
		return obj.get(key, default)
	var value = obj.get(key)
	return value if value != null else default
