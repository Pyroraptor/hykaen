## core/domain/add_energy_effect.gd — AddEnergyEffect (FEAT-001 / US-001)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript, zero engine
## I/O. Concrete Effect value object (core/domain/effect.gd). RESERVED,
## UNUSED this sprint (design notes' data_model: "defined only to prevent a
## future breaking schema change in Iteration M") — no use case constructs
## this yet and no EffectsApplier dispatch exists for it. Defined now so
## the Effect family's discriminated-subtype shape (EffectKind.ADD_ENERGY)
## is reserved ahead of time rather than added as a later breaking change.
##
## Extends the base script BY PATH
## (`extends "res://core/domain/effect.gd"`), matching
## core/domain/damage_effect.gd's convention (see its file doc for the
## preload-typing rationale).
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
extends "res://core/domain/effect.gd"

const EffectKindClass = preload("res://core/domain/effect_kind.gd")

## The energy amount to add to the target. Must be > 0 (see file doc).
var amount: int = 0


func _init(p_target_id: String = "", p_amount: int = 0) -> void:
	super(EffectKindClass.ADD_ENERGY, p_target_id)
	amount = p_amount
	if amount <= 0:
		_reject("amount must be > 0 (got %d)" % amount)
