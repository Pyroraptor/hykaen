## core/domain/effects/heal_effect.gd — HealEffect (FEAT-001 / US-001)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript, zero engine
## I/O. Concrete EffectBase value object (core/domain/effects/effect_base.gd)
## carrying a positive HP-restoration amount targeted at one combatant. A
## future EffectsApplier (US-002) dispatches this to Combatant.heal(),
## which caps at hp_max — this feature defines the pure data shape only; no
## application-layer wiring exists yet.
##
## Extends the base script BY PATH
## (`extends "res://core/domain/effects/effect_base.gd"`), matching
## core/domain/effects/damage_effect.gd's convention (see its file doc for
## the preload-typing rationale).
##
## Invariant (data_model): amount must be > 0 — mirrors DamageEffect's
## amount>0 rule (api_contracts #1's "DAMAGE with amount<=0 is a contract
## violation caught at construction time" applies identically here).
##
## Usage:
##   var e := HealEffect.new("player_0", 8)
##   e.kind == EffectKind.HEAL  # true
##   e.amount                  # 8
##   e.is_valid()               # true

class_name HealEffect
extends "res://core/domain/effects/effect_base.gd"

const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")

## The HP amount to restore on the target (capped at hp_max by
## Combatant.heal()). Must be > 0 (see file doc).
var amount: int = 0


func _init(p_target_id: String = "", p_amount: int = 0) -> void:
	super(EffectKindClass.HEAL, p_target_id)
	amount = p_amount
	if amount <= 0:
		_reject("amount must be > 0 (got %d)" % amount)
