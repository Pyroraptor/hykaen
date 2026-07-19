## core/domain/effects/add_energy_effect.gd — AddEnergyEffect (FEAT-001 / US-001)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript, zero engine
## I/O. Concrete EffectBase value object (core/domain/effects/effect_base.gd).
## Originally reserved-but-unused (design notes' data_model: "defined only to
## prevent a future breaking schema change in Iteration M") — core/domain/
## effects_applier.gd's Combatant-mutator dispatch still guards this kind
## with a push_error() no-op (Combatant has no energy-pool concept; energy
## lives on core/application/round_session.gd's RoundSession instead, one
## core/domain/energy_pool.gd EnergyPool per caster).
##
## FEAT-277 (US-012; FR-013) is this VO's first real consumer:
## core/application/use_cases/resolve_cast_use_case.gd's ResolveCastUseCase
## constructs one whenever `spell.effect_type == EffectKind.ADD_ENERGY`
## (e.g. Channel), and applies its `amount` directly to the CASTER's own
## round-scoped EnergyPool (obtained via an injected `energy_pool_fn`
## Callable) rather than through the Combatant-mutator EffectsApplier seam
## above — that seam remains an unwired no-op for this kind, since there is
## still no Combatant-level energy field to mutate.
##
## Extends the base script BY PATH
## (`extends "res://core/domain/effects/effect_base.gd"`), matching
## core/domain/effects/damage_effect.gd's convention (see its file doc for
## the preload-typing rationale).
##
## Invariant (data_model): amount must be > 0 — mirrors DamageEffect/
## HealEffect's amount>0 rule, kept consistent even though this VO is not
## yet consumed.
##
## Usage:
##   var e := AddEnergyEffect.new("player_0", 3)
##   e.kind == EffectKind.ADD_ENERGY  # true
##   e.amount                         # 3
##   e.is_valid()                     # true

class_name AddEnergyEffect
extends "res://core/domain/effects/effect_base.gd"

const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")

## The energy amount to add to the target. Must be > 0 (see file doc).
var amount: int = 0


func _init(p_target_id: String = "", p_amount: int = 0) -> void:
	super(EffectKindClass.ADD_ENERGY, p_target_id)
	amount = p_amount
	if amount <= 0:
		_reject("amount must be > 0 (got %d)" % amount)
