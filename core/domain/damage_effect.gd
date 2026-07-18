## core/domain/damage_effect.gd — DamageEffect (FEAT-001 / US-001)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript, zero engine
## I/O. Concrete Effect value object (core/domain/effect.gd) carrying a
## positive HP-reduction amount targeted at one combatant. A future
## ResolveActionUseCase/ApplyOnHitDefenseUseCase (US-004/US-005) constructs
## this from resolved Strike damage, and a future EffectsApplier (US-002)
## dispatches it to Combatant.take_damage() — this feature defines the pure
## data shape only; no application-layer wiring exists yet.
##
## Extends the base script BY PATH
## (`extends "res://core/domain/effect.gd"`) rather than by class_name, per
## this project's established preload-typing convention for concrete
## adapters/subtypes (see core/combat/godot_random_adapter.gd, and
## core/domain/combatant.gd's hex_coord doc on why: a bare global class_name
## as a static type/extends target needs Godot's global script-class cache
## to already know a brand-new script, which is not guaranteed headless/CI).
##
## Invariant (data_model): amount must be > 0. amount<=0 is rejected at
## construction (api_contracts #1: "DAMAGE with amount<=0 is a contract
## violation caught at construction time (VO validates in _init)") — see
## Effect.is_valid()/validation_error().
##
## Usage:
##   var e := DamageEffect.new("enemy_0", 6)
##   e.kind == EffectKind.DAMAGE  # true
##   e.amount                     # 6
##   e.is_valid()                 # true

class_name DamageEffect
extends "res://core/domain/effect.gd"

const EffectKindClass = preload("res://core/domain/effect_kind.gd")

## The HP amount to subtract from the target. Must be > 0 (see file doc).
var amount: int = 0


func _init(p_target_id: String = "", p_amount: int = 0) -> void:
	super(EffectKindClass.DAMAGE, p_target_id)
	amount = p_amount
	if amount <= 0:
		_reject("amount must be > 0 (got %d)" % amount)
