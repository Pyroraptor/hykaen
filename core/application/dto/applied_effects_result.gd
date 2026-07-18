## core/application/dto/applied_effects_result.gd — AppliedEffectsResult
## (FEAT-002 / US-002, ADR-002/ADR-005)
##
## Application layer (Clean Architecture): a plain RefCounted DATA object —
## no ports, no I/O, no engine imports — returned by EffectsApplierUseCase.
## apply() (core/application/use_cases/effects_applier_use_case.gd,
## api_contracts #1). Depends only on core/application/dto/
## effect_application_error.gd (a sibling application-layer DTO).
##
## Shape (design notes' api_contracts #1):
##   applied_count — how many effects in the batch were actually dispatched
##                   to a live Combatant mutator (take_damage/heal/
##                   add_condition/remove_condition/move_to).
##   errors        — one EffectApplicationError per effect that was instead
##                   skipped fail-soft (EFFECT_TARGET_NOT_FOUND /
##                   EFFECT_UNKNOWN_KIND) — see that DTO's file doc.
##
## applied_count + errors.size() == effects.size() always holds for a batch
## with no null entries: every effect in the input Array is accounted for
## exactly once, either as an application or as a collected error — apply()
## never silently drops an effect without a trace.
##
## Usage:
##   var result := use_case.apply(effects, combatants)
##   result.applied_count   # e.g. 2
##   result.has_errors()    # true
##   for err in result.errors:
##       print(err.code_name())

class_name AppliedEffectsResult
extends RefCounted

## Count of effects successfully dispatched to a Combatant mutator this
## batch.
var applied_count: int = 0

## Array[EffectApplicationError] — one per fail-soft-skipped effect, in the
## order they were encountered.
var errors: Array = []


func _init(p_applied_count: int = 0, p_errors: Array = []) -> void:
	applied_count = p_applied_count
	errors = p_errors


## has_errors() -> bool — true when at least one effect in the batch was
## skipped fail-soft.
func has_errors() -> bool:
	return not errors.is_empty()


## record_applied() -> void — EffectsApplierUseCase calls this once per
## effect it successfully dispatches.
func record_applied() -> void:
	applied_count += 1


## add_error(error) -> void — EffectsApplierUseCase calls this once per
## effect it skips fail-soft, appending the EffectApplicationError
## (core/application/dto/effect_application_error.gd) describing why.
func add_error(error) -> void:
	errors.append(error)
