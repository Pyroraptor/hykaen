## core/domain/spell.gd — Spell domain value object (FEAT-001, Iteration M,
## US-002; FR-011, FR-013 data half)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/CanvasItem inheritance, no ResourceLoader/Resource-file
## concerns, no engine I/O. Extends RefCounted only, matching the existing
## value-object convention (core/domain/effects/effect_base.gd,
## core/geometry/hex_coord.gd).
##
## Spell is the runtime-facing projection of the AUTHORED
## core/resources/spell_resource.gd SpellResource data (a Godot Resource,
## loaded from a data/spells/{spell_id}.tres file) — it decouples every
## downstream application-layer use case (a future
## BeginCastUseCase/ContinueCastUseCase/ResolveCastUseCase) from the
## Godot Resource/.tres authoring format: those use cases depend only on
## THIS plain-data type, never on a Resource object, per ADR-001's
## inward-only dependency rule. core/adapters/resource_spell_catalog_adapter.gd
## is the ONE place a SpellResource is mapped into a Spell — every other
## caller only ever sees this class.
##
## Immutable after construction — every field is set exactly once in
## _init() and never mutated again.
##
## Fields mirror core/resources/spell_resource.gd's SpellResource schema
## (see that file's doc for full field semantics):
##   spell_id        — canonical string identifier (e.g. "fire_bolt", "channel")
##   spell_name      — display name (e.g. "Fire Bolt")
##   actions_cost    — number of actions required to fully cast this spell
##   energy_cost     — Channeling-pool energy committed at cast begin
##   defense         — Defense enum value (see below); Defense.NONE when the
##                      spell's effect targets no defense (e.g. Channel's
##                      self-targeted ADD_ENERGY)
##   range_ft        — spell range in feet; 0 for touch/self-only spells
##   damage_formula  — dice/formula expression (e.g. "2d8+ATTR"); "" for
##                      non-damage spells
##   damage_type     — damage type string (e.g. "fire"); "" for non-damage
##                      spells
##   traits          — Array of trait strings (e.g. ["Concentrate"])
##   effect_type     — core/domain/effects/effect_kind.gd EffectKind
##                      discriminator identifying which Effect VO a future
##                      ResolveCastUseCase builds on resolve (DAMAGE,
##                      ADD_ENERGY, ...)
##   effect_params   — effect-type-specific parameters (e.g. {"amount": 1}
##                      for ADD_ENERGY)
##
## Usage:
##   var fire_bolt := Spell.new(
##       "fire_bolt", "Fire Bolt", 2, 0, Spell.Defense.REFLEX, 50,
##       "2d8+ATTR", "fire", [], EffectKind.DAMAGE, {"formula": "2d8+ATTR", "type": "fire"}
##   )
##   fire_bolt.has_trait("Concentrate")  # false

class_name Spell
extends RefCounted

const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")

## Defense a spell attack resolves against. Domain-owned (not declared on
## the authoring core/resources/spell_resource.gd SpellResource) so that
## outer/authoring layer depends inward on this enum, per ADR-001's
## dependency-inversion rule, rather than the domain depending outward on
## an authoring-schema type.
enum Defense {
	NONE,
	AC,
	REFLEX,
	FORTITUDE,
	WILL,
}

## Canonical string identifier (e.g. "fire_bolt", "channel").
var spell_id: String = ""

## Spell display name (e.g. "Fire Bolt").
var spell_name: String = ""

## Number of actions required to fully cast this spell.
var actions_cost: int = 0

## Channeling-pool energy cost committed when the cast begins.
var energy_cost: int = 0

## Defense the target rolls against on resolution (Defense enum). Defense.NONE
## when the spell's effect targets no defense (e.g. Channel).
var defense: int = Defense.NONE

## Spell range in feet. 0 for touch/self-only spells.
var range_ft: int = 0

## Damage/effect formula expression (e.g. "2d8+ATTR"). Empty string for
## non-damage spells.
var damage_formula: String = ""

## Damage type (e.g. "fire"). Empty string for non-damage spells.
var damage_type: String = ""

## Array of trait strings (e.g. ["Concentrate"]).
var traits: Array = []

## Which Effect kind resolution produces on a hit/resolve: an
## EffectKindClass value (DAMAGE, ADD_ENERGY, ...).
var effect_type: int = EffectKindClass.DAMAGE

## Effect-type-specific parameters (e.g. {"amount": 1} for ADD_ENERGY,
## {"formula": ..., "type": ...} for DAMAGE).
var effect_params: Dictionary = {}


func _init(
	p_spell_id: String = "",
	p_spell_name: String = "",
	p_actions_cost: int = 0,
	p_energy_cost: int = 0,
	p_defense: int = Defense.NONE,
	p_range_ft: int = 0,
	p_damage_formula: String = "",
	p_damage_type: String = "",
	p_traits: Array = [],
	p_effect_type: int = EffectKindClass.DAMAGE,
	p_effect_params: Dictionary = {}
) -> void:
	spell_id = p_spell_id
	spell_name = p_spell_name
	actions_cost = p_actions_cost
	energy_cost = p_energy_cost
	defense = p_defense
	range_ft = p_range_ft
	damage_formula = p_damage_formula
	damage_type = p_damage_type
	traits = p_traits.duplicate()
	effect_type = p_effect_type
	effect_params = p_effect_params.duplicate()


## has_trait(trait_name) -> bool — true iff `trait_name` is present in this
## spell's traits Array (e.g. "Concentrate").
func has_trait(trait_name: String) -> bool:
	return traits.has(trait_name)
