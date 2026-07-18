## core/rules/spell_definition.gd — SpellDefinition (FEAT-001 / US-002, FR-008)
##
## Domain layer (Clean Architecture, ADR-001 / ADR-007): custom Resource
## encoding a spell's immutable rule constants. Matches the SAME
## "extends Resource, zero business logic, pure typed data container"
## convention already established by core/model/weapon_resource.gd /
## character_resource.gd (Resource is a data-container base, not a
## scene-tree/engine-lifecycle type — see those files' own "DOMAIN layer"
## notes). Authored directly as resources/spells/{spell_id}.tres and loaded
## via ResourceLoader — see core/rules/infrastructure/spell_resource_loader.gd
## (the SpellRepositoryPort-conformant adapter that performs the
## ResourceLoader.load() call, validates the hydrated fields via
## is_valid()/validation_error() below, and exposes discovery by spell_id).
##
## Fields (design notes' data_model, SpellResource entity):
##   spell_id       — canonical string identifier matching the .tres filename
##                     (e.g. "fire_bolt")
##   name           — display name (e.g. "Fire Bolt")
##   actions        — action-point cost to fully cast (Fire Bolt: 2, Channel: 1)
##   energy_cost    — Channeling-pool energy paid up front (v0: 0 for both)
##   range_ft       — maximum range in feet (0 == self/no target, e.g. Channel)
##   defense_type   — one of core/rules/resolution.gd's VALID_DEFENSE_TYPES
##                     ("ac"/"reflex"/"fortitude"/"will"), or "" when the
##                     spell's effect targets no defense (e.g. Channel)
##   damage_formula — dice spec string (e.g. "2d8"); "" when effect_type
##                     is not DAMAGE
##   damage_type    — elemental/damage type (e.g. "fire"); "" when unused
##   spell_trait    — action trait tag (e.g. "Concentrate", per spec line
##                     355 — every Cast-a-Spell action provokes Opportunistic
##                     Strike identically to Stride); "" when none. Named
##                     `spell_trait` rather than the bare word `trait` —
##                     GDScript 4.3 reserves `trait` as a soft keyword
##                     (future trait/interface language feature), so a
##                     property literally named `trait` fails to parse.
##   effect_type    — core/domain/effects/effect_kind.gd EffectKind
##                     discriminator (DAMAGE, ADD_ENERGY, ...) identifying
##                     which Effect VO a future ResolveSpellUseCase builds
##                     on resolve
##
## Validation invariant (design notes' security policy #1: "untrusted/
## malformed data resources — SpellResource ... fields must be validated at
## load time (bounds-check energy_cost, actions>0, range_ft>=0 ...) so a
## bad .tres cannot crash MainScene or create negative-cost exploits").
## Because Resource subclasses are hydrated field-by-field by ResourceLoader
## (there is no constructor call site to fail fast in, unlike
## core/domain/effects/effect_base.gd's RefCounted VOs), validation is
## exposed as an on-demand predicate — is_valid()/validation_error() —
## which core/rules/infrastructure/spell_resource_loader.gd MUST check
## before ever caching/exposing a hydrated instance through
## SpellRepositoryPort.
##
## Usage:
##   var fire_bolt = ResourceLoader.load("res://resources/spells/fire_bolt.tres")
##   fire_bolt.actions        # 2
##   fire_bolt.is_valid()     # true

class_name SpellDefinition
extends Resource

const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")

## Canonical string identifier matching the .tres filename (e.g. "fire_bolt").
@export var spell_id: String = ""

## Display name shown to the player.
@export var name: String = ""

## Action-point cost to fully cast this spell. Must be > 0.
@export var actions: int = 0

## Channeling-pool energy paid up front at cast-start (ADR-004). Must be >= 0.
@export var energy_cost: int = 0

## Maximum range in feet. 0 == self/no target (e.g. Channel). Must be >= 0.
@export var range_ft: int = 0

## Defense the spell attack targets — one of resolution.gd's
## VALID_DEFENSE_TYPES ("ac"/"reflex"/"fortitude"/"will"), or "" when the
## spell's effect targets no defense (e.g. Channel's ADD_ENERGY).
@export var defense_type: String = ""

## Dice spec string for damage effects (e.g. "2d8"). "" when unused.
@export var damage_formula: String = ""

## Elemental/damage type for damage effects (e.g. "fire"). "" when unused.
@export var damage_type: String = ""

## Action trait tag (e.g. "Concentrate"). "" when the spell carries no
## trait. Named `spell_trait` — GDScript 4.3 reserves the bare word `trait`
## (see file-level doc above).
@export var spell_trait: String = ""

## EffectKind discriminator (core/domain/effects/effect_kind.gd) identifying
## which Effect VO this spell produces on resolve.
@export var effect_type: int = EffectKindClass.DAMAGE


## is_valid() -> bool — true when every load-time invariant holds (see
## file-level doc). Callers (loaders/use cases) MUST check this before
## trusting or caching a hydrated instance.
func is_valid() -> bool:
	return validation_error() == ""


## validation_error() -> String — the human-readable reason this
## SpellDefinition violates a load-time invariant, or "" when valid.
## Computed on demand (not cached at construction) since Resource
## subclasses are hydrated field-by-field by ResourceLoader, not via a
## parameterized constructor call site.
func validation_error() -> String:
	if actions <= 0:
		return "actions must be > 0 (got %d)" % actions
	if energy_cost < 0:
		return "energy_cost must be >= 0 (got %d)" % energy_cost
	if range_ft < 0:
		return "range_ft must be >= 0 (got %d)" % range_ft
	return ""
