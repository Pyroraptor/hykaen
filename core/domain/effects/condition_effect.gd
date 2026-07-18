## core/domain/effects/condition_effect.gd — ConditionEffect (FEAT-001 / US-001)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript, zero engine
## I/O. Concrete EffectBase value object (core/domain/effects/effect_base.gd)
## carrying a condition-tag add/remove instruction targeted at one
## combatant. The domain EffectsApplier (core/domain/effects_applier.gd,
## FEAT-002/US-002) dispatches this to Combatant.add_condition()/
## remove_condition() (core/domain/combatant.gd) — this feature defines the
## pure data shape only.
##
## Extends the base script BY PATH
## (`extends "res://core/domain/effects/effect_base.gd"`), matching
## core/domain/effects/damage_effect.gd's convention (see its file doc for
## the preload-typing rationale).
##
## Invariants (data_model): target_id must be non-empty (enforced by
## EffectBase, every subtype inherits it) and `condition` must be
## non-empty (an empty condition tag has no meaning — Combatant.
## has_condition()/add_condition()/remove_condition() all key on the tag
## string). `add` selects direction: true adds the tag, false removes it.
## `op` mirrors `add` as a two-member enum (Op.ADD / Op.REMOVE) so a
## dispatcher can match on a discriminator rather than branching on a bare
## bool.
##
## Usage:
##   var e := ConditionEffect.new("enemy_0", "Off-Guard", true)
##   e.kind == EffectKind.CONDITION  # true
##   e.condition                     # "Off-Guard"
##   e.add                           # true
##   e.op == ConditionEffect.Op.ADD  # true
##   e.is_valid()                    # true
##   var bad := ConditionEffect.new("", "Off-Guard", true)
##   bad.is_valid()                  # false — empty target_id

class_name ConditionEffect
extends "res://core/domain/effects/effect_base.gd"

const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")

## Discriminator mirroring the `add` bool — Op.ADD when add=true,
## Op.REMOVE when add=false (see file doc).
enum Op { ADD, REMOVE }

## The condition tag to add or remove (e.g. "Off-Guard", "Immobilized").
## Must be non-empty (see file doc).
var condition: String = ""

## true = add the tag (Combatant.add_condition()); false = remove it
## (Combatant.remove_condition()).
var add: bool = true

## Op.ADD / Op.REMOVE, mirroring `add` (see file doc).
var op: int = Op.ADD


func _init(p_target_id: String = "", p_condition: String = "", p_add: bool = true) -> void:
	super(EffectKindClass.CONDITION, p_target_id)
	condition = p_condition
	add = p_add
	op = Op.ADD if p_add else Op.REMOVE
	if condition == "":
		_reject("condition must not be empty")
