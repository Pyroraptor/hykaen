## core/application/use_cases/short_rest_heal_use_case.gd — ShortRestHealUseCase
## (FEAT-004 / US-004; FR-005, NFR-001; iteration AB-0, rest mechanics steel
## thread).
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (core/domain/combatant.gd's Combatant, via duck-typed field access — no
## static Combatant type dependency on the `combatant` parameter itself,
## mirroring core/application/use_cases/long_rest_use_case.gd's identical
## convention) and core/application/ports/errors.gd's ErrorCode vocabulary.
## Extends RefCounted only: no Node/Control/SceneTree inheritance, no engine
## lifecycle coupling (ADR-001).
##
## api_contracts #3: execute(combatant, stamina_to_spend) spends 1+ Stamina
## points to heal a combatant during a Short Rest. Validated in this EXACT
## order — first failure wins, no side effects on failure (error_handling
## design note: "No side effects before all validations pass"):
##   a. stamina_to_spend < 1                    -> ERR_INSUFFICIENT_STAMINA
##   b. combatant.stamina < stamina_to_spend     -> ERR_INSUFFICIENT_STAMINA
##   c. combatant.hp_current == combatant.hp_max -> ERR_ALREADY_AT_FULL_HP
##
## On success, heals
##   min(stamina_to_spend * ceil(hp_max / 4), hp_max - hp_current)
## and spends `stamina_to_spend` Stamina — applied ATOMICALLY (both mutations
## happen together, in the same call, or neither happens at all) so an
## over-spend request that would exceed hp_max still spends the FULL
## requested stamina while healing caps exactly at hp_max (per-stamina-point
## healing rate is fixed regardless of how much of it a combatant can
## actually use).
##
## Returns {success: true, hp_gained: int, stamina_spent: int} on success, or
## {success: false, error: <ErrorCode int>} on any validation failure.

class_name ShortRestHealUseCase
extends RefCounted

const ErrorCodeClass = preload("res://core/application/ports/errors.gd")


## execute(combatant, stamina_to_spend) -> Dictionary — api_contracts #3.
## `combatant` is a duck-typed combatant-shaped object (a real
## core/domain/combatant.gd Combatant instance in production; a duck-typed
## double in tests) exposing hp_current/hp_max/stamina as plain fields,
## mirroring LongRestUseCase.execute()'s direct field access convention.
func execute(combatant, stamina_to_spend: int) -> Dictionary:
	if stamina_to_spend < 1:
		return _fail(ErrorCodeClass.ERR_INSUFFICIENT_STAMINA)

	var current_stamina: int = int(_duck_get(combatant, "stamina", 0))
	if current_stamina < stamina_to_spend:
		return _fail(ErrorCodeClass.ERR_INSUFFICIENT_STAMINA)

	var hp_current: int = int(_duck_get(combatant, "hp_current", 0))
	var hp_max: int = int(_duck_get(combatant, "hp_max", 0))
	if hp_current == hp_max:
		return _fail(ErrorCodeClass.ERR_ALREADY_AT_FULL_HP)

	var per_stamina_point_heal: int = ceili(float(hp_max) / 4.0)
	var hp_gained: int = mini(stamina_to_spend * per_stamina_point_heal, hp_max - hp_current)

	# Atomic: both mutations are applied together, right here, with no
	# intervening validation/return that could leave one applied without
	# the other.
	combatant.hp_current = hp_current + hp_gained
	combatant.stamina = current_stamina - stamina_to_spend

	return {"success": true, "hp_gained": hp_gained, "stamina_spent": stamina_to_spend}


func _fail(error_code: int) -> Dictionary:
	return {"success": false, "error": error_code}


## _duck_get(obj, key, default) -> Variant — the SAME defensive duck-typed
## field read established by BeginCastUseCase._duck_get() / LongRestUseCase
## ._duck_get() (core/application/use_cases/begin_cast_use_case.gd,
## core/application/use_cases/long_rest_use_case.gd): tolerates `obj` being a
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
