## core/application/use_cases/effects_applier_use_case.gd — EffectsApplierUseCase
## (FEAT-002 / US-002, ADR-002/ADR-005)
##
## Application layer (Clean Architecture): the SOLE application-facing seam
## a future ResolveActionUseCase/ApplyOnHitDefenseUseCase (design notes'
## US-004/US-005 retrofit, NOT yet wired by this feature) is meant to route
## every Effect batch through, per api_contracts #1:
##
##   apply(effects: Array[Effect], combatants: Dictionary[String, Combatant])
##       -> AppliedEffectsResult
##
## Depends ONLY on domain (core/domain/effects_applier.gd's EffectsApplier,
## core/domain/effects/effect_kind.gd) and its own sibling application-layer
## DTOs (core/application/dto/applied_effects_result.gd,
## core/application/dto/effect_application_error.gd) — never an adapter/
## infrastructure/presentation type, and never the engine scene tree.
##
## WHY THIS DELEGATES RATHER THAN RE-DISPATCHING ITSELF (single-seam
## architecture, ADR-002/ADR-006): core/domain/effects_applier.gd's
## EffectsApplier is ALREADY the one file every Combatant combat-state
## mutator call (take_damage()/heal()/add_condition()/remove_condition()/
## move_to(), core/domain/combatant.gd) is statically guaranteed to funnel
## through — ci/check_no_duplicate_seams.sh's seam-4 check fails the build
## the moment a second file calls any of those methods directly. Rather
## than re-implementing that dispatch here (which would create exactly the
## second call site that check exists to catch), this use case's job is
## PURELY the application-layer concern api_contracts #1 adds on top:
## validating each effect BEFORE dispatch and turning "should this even be
## attempted?" into a structured, fail-soft AppliedEffectsResult — then
## handing every effect that passes validation to the SAME EffectsApplier
## instance for the actual mutation. ci/check_no_duplicate_seams.sh's
## seam-5 check (added by this feature) statically confirms this file
## itself never calls a Combatant mutator directly, keeping seam-4's
## "exactly one call site" guarantee true even as this application-layer
## wrapper is introduced.
##
## Fail-soft validation, per effect, in list order (api_contracts #1 /
## error_handling policy — collected into AppliedEffectsResult.errors,
## NEVER aborting the rest of the batch):
##   EFFECT_TARGET_NOT_FOUND — effect.target_id is not a key in `combatants`.
##   EFFECT_UNKNOWN_KIND     — effect.kind does not match any recognized
##                             EffectKind member (core/domain/effects/
##                             effect_kind.gd) — defensive; should be
##                             unreachable given typed Effect subtypes.
## An effect that fails EffectBase's OWN construction-time validation
## (effect.is_valid() == false, core/domain/effects/effect_base.gd) is also
## skipped without incrementing applied_count — it already push_error()'d at
## construction time (fail-fast there), so it is silently excluded here
## rather than double-reported as a second, different error class.
##
## Usage:
##   var use_case := EffectsApplierUseCase.new()
##   var combatants := {"enemy_0": some_combatant}
##   var result := use_case.apply([DamageEffect.new("enemy_0", 6)], combatants)
##   result.applied_count      # 1
##   combatants["enemy_0"].hp_current  # reduced by 6, same instance

class_name EffectsApplierUseCase
extends RefCounted

const EffectsApplierClass = preload("res://core/domain/effects_applier.gd")
const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")
const AppliedEffectsResultClass = preload("res://core/application/dto/applied_effects_result.gd")
const EffectApplicationErrorClass = preload("res://core/application/dto/effect_application_error.gd")

## Every EffectKind member this use case recognizes as "known" (design
## notes' data_model: DAMAGE, CONDITION, MOVE, HEAL, ADD_ENERGY). A kind
## outside this set can never have come from a real Effect subtype
## constructor and is flagged EFFECT_UNKNOWN_KIND.
const _KNOWN_KINDS: Array = [
	EffectKindClass.DAMAGE,
	EffectKindClass.CONDITION,
	EffectKindClass.MOVE,
	EffectKindClass.HEAL,
	EffectKindClass.ADD_ENERGY,
]

## The single domain EffectsApplier instance this use case delegates every
## validated effect to (see file-level "WHY THIS DELEGATES" doc above).
## Injectable for tests; defaults to a real EffectsApplier.
var _domain_applier


func _init(p_domain_applier = null) -> void:
	_domain_applier = p_domain_applier if p_domain_applier != null else EffectsApplierClass.new()


## apply(effects, combatants) -> AppliedEffectsResult — validates and
## dispatches every Effect in `effects` against `combatants` (a Dictionary
## keyed by combatant_id -> live Combatant instance, core/domain/
## combatant.gd), mutating matched targets BY REFERENCE (never a copy) via
## the single domain EffectsApplier seam. See the file-level doc for the
## full fail-soft contract.
func apply(effects: Array, combatants: Dictionary) -> AppliedEffectsResultClass:
	var result := AppliedEffectsResultClass.new()

	for effect in effects:
		if effect == null:
			result.add_error(EffectApplicationErrorClass.unknown_kind("", -1))
			continue

		if not _KNOWN_KINDS.has(effect.kind):
			result.add_error(EffectApplicationErrorClass.unknown_kind(effect.target_id, effect.kind))
			continue

		if not combatants.has(effect.target_id):
			result.add_error(EffectApplicationErrorClass.target_not_found(effect.target_id, effect.kind))
			continue

		if effect.has_method("is_valid") and not effect.is_valid():
			# Already push_error()'d at construction time (EffectBase's own
			# fail-fast invariant check) -- not re-reported as a second,
			# different error class here; simply excluded from
			# applied_count.
			continue

		_domain_applier.apply([effect], combatants)
		result.record_applied()

	return result
