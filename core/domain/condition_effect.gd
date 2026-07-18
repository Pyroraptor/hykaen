## core/domain/condition_effect.gd — ConditionEffect (FEAT-001 / US-001)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript, zero engine
## I/O. Concrete Effect value object (core/domain/effect.gd) carrying a
## condition-tag add/remove instruction targeted at one combatant. A future
## EffectsApplier (US-002) dispatches this to Combatant.add_condition()/
## remove_condition() — this feature defines the pure data shape only; no
## application-layer wiring exists yet.
##
## Extends the base script BY PATH
## (`extends "res://core/domain/effect.gd"`), matching
## core/domain/damage_effect.gd's convention (see its file doc for the
## preload-typing rationale).
##
## Invariants (data_model): target_id must be non-empty (enforced by the
## Effect base class every subtype inherits) and `condition` must be
## non-empty (an empty condition tag has no meaning — Combatant.
## has_condition()/add_condition()/remove_condition() all key on the tag
## string). `add` selects direction: true adds the tag, false removes it.
##
## Usage:
##   var e := ConditionEffect.new("enemy_0", "Off-Guard", true)
##   e.kind == EffectKind.CONDITION  # true
##   e.condition                     # "Off-Guard"
##   e.add                           # true
##   e.is_valid()                    # true
##   var bad := ConditionEffect.new("", "Off-Guard", true)
##   bad.is_valid()                  # false — empty target_id

class_name ConditionEffect
extends "res://core/domain/effect.gd"

const EffectKindClass = preload("res://core/domain/effect_kind.gd")

## The condition tag to add or remove (e.g. "Off-Guard", "Immobilized").
## Must be non-empty (see file doc).
var condition: String = ""

## true = add the tag (Combatant.add_condition()); false = remove it
## (Combatant.remove_condition()).
var add: bool = true


func _init(p_target_id: String = "", p_condition: String = "", p_add: bool = true) -> void:
	super(EffectKindClass.CONDITION, p_target_id)
	condition = p_condition
	add = p_add
	if condition == "":
		_reject("condition must not be empty")
