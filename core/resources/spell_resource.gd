## core/resources/spell_resource.gd — SpellResource authoring schema
## (FEAT-001, Iteration M, US-002; FR-011, FR-013 data half)
##
## Custom Resource encoding a spell's immutable rule constants, authored
## directly as data/spells/{spell_id}.tres and loaded via ResourceLoader
## (see core/adapters/resource_spell_catalog_adapter.gd's
## ResourceSpellCatalogAdapter, the sole adapter permitted to call
## ResourceLoader.load() against this schema).
##
## Architecture note (Clean Architecture / ADR-001), matching the SAME
## established convention as core/model/weapon_resource.gd and
## core/rules/spell_definition.gd: this file extends Resource — NOT Node,
## Control, or CanvasItem — and carries ZERO business logic; it is a pure
## typed data container for the AUTHORING/on-disk shape. It is the
## authored counterpart to core/domain/spell.gd's Spell — Spell is the
## runtime domain VALUE the adapter maps a loaded SpellResource into, so
## application-layer use cases never touch a Godot Resource object
## directly.
##
## Fields (design notes' data_model, SpellResource entity):
##   spell_id       — canonical string identifier matching the .tres
##                     filename (e.g. "fire_bolt")
##   name           — display name (e.g. "Fire Bolt")
##   actions_cost   — action-point cost to fully cast (Fire Bolt: 2,
##                     Channel: 1). Must be > 0.
##   energy_cost    — Channeling-pool energy paid up front at cast-start.
##                     Must be >= 0. (Fire Bolt/Channel: 0.)
##   defense        — core/domain/spell.gd Spell.Defense enum value the
##                     target rolls against on resolution. Spell.Defense.NONE
##                     when the spell's effect targets no defense (e.g.
##                     Channel's ADD_ENERGY).
##   range_ft       — maximum range in feet. 0 == self/no target (e.g.
##                     Channel). Must be >= 0.
##   damage_formula — dice/formula expression (e.g. "2d8+ATTR"); "" when
##                     effect_type is not DAMAGE.
##   damage_type    — elemental/damage type (e.g. "fire"); "" when unused.
##   traits         — Array of trait strings (e.g. ["Concentrate"] — per
##                     spec, every Cast-a-Spell action carrying the
##                     Concentrate trait provokes Opportunistic Strike
##                     identically to Stride).
##   effect_type    — core/domain/effects/effect_kind.gd EffectKind
##                     discriminator (DAMAGE, ADD_ENERGY, ...) identifying
##                     which Effect VO a future ResolveCastUseCase builds on
##                     resolve.
##   effect_params  — effect-type-specific parameters Dictionary (e.g.
##                     {"amount": 1} for ADD_ENERGY; {"formula": ...,
##                     "type": ...} for DAMAGE).
##
## Usage:
##   var fire_bolt = ResourceLoader.load("res://data/spells/fire_bolt.tres")
##   fire_bolt.actions_cost   # 2
##   fire_bolt.is_valid()     # true

class_name SpellResource
extends Resource

const SpellClass = preload("res://core/domain/spell.gd")
const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")

## Canonical string identifier matching the .tres filename (e.g. "fire_bolt").
@export var spell_id: String = ""

## Display name shown to the player.
@export var name: String = ""

## Action-point cost to fully cast this spell. Must be > 0.
@export var actions_cost: int = 0

## Channeling-pool energy paid up front at cast-start. Must be >= 0.
@export var energy_cost: int = 0

## Defense the spell attack targets — a core/domain/spell.gd
## Spell.Defense enum value, or Spell.Defense.NONE when the spell's effect
## targets no defense (e.g. Channel's ADD_ENERGY).
@export var defense: int = SpellClass.Defense.NONE

## Maximum range in feet. 0 == self/no target (e.g. Channel). Must be >= 0.
@export var range_ft: int = 0

## Dice/formula expression string for damage effects (e.g. "2d8+ATTR"). ""
## when unused.
@export var damage_formula: String = ""

## Elemental/damage type for damage effects (e.g. "fire"). "" when unused.
@export var damage_type: String = ""

## Array of trait strings (e.g. ["Concentrate"]). Empty when this spell
## carries no trait.
@export var traits: Array = []

## EffectKind discriminator (core/domain/effects/effect_kind.gd) identifying
## which Effect VO this spell produces on resolve.
@export var effect_type: int = EffectKindClass.DAMAGE

## Effect-type-specific parameters (e.g. {"amount": 1} for ADD_ENERGY).
@export var effect_params: Dictionary = {}


## is_valid() -> bool — true when every load-time invariant holds (see
## validation_error()). Callers (adapters) MUST check this before trusting
## or exposing a hydrated instance.
func is_valid() -> bool:
	return validation_error() == ""


## validation_error() -> String — the human-readable reason this
## SpellResource violates a load-time invariant, or "" when valid.
## Computed on demand (not cached at construction) since Resource
## subclasses are hydrated field-by-field by ResourceLoader, not via a
## parameterized constructor call site.
func validation_error() -> String:
	if spell_id == "":
		return "spell_id must not be empty"
	if actions_cost <= 0:
		return "actions_cost must be > 0 (got %d)" % actions_cost
	if energy_cost < 0:
		return "energy_cost must be >= 0 (got %d)" % energy_cost
	if range_ft < 0:
		return "range_ft must be >= 0 (got %d)" % range_ft
	return ""
