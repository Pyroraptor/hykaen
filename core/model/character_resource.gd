## core/model/character_resource.gd — CharacterResource aggregate root (ADR-003)
##
## Custom Resource encoding a playable character's persistent definition.
## Loaded from data/characters/{character_id}.tres via ResourceLoader.
##
## Architecture note (Clean Architecture / ADR-001):
##   This file lives in the DOMAIN layer (core/model/).
##   It extends Resource — NOT Node, Control, or CanvasItem.
##   It carries ZERO business logic; it is a pure typed data container.
##   Derived-stat computation (hp, stamina, AC, defenses) belongs in use cases.
##
## Fields match the v0 spec from US-006:
##   name               — character display name (e.g. "Titus")
##   race               — character race (cosmetic in v0, e.g. "Human")
##   class_ref          — Resource path to the ClassResource for this character
##   attributes         — Dictionary with seven keys:
##                        {strength, constitution, dexterity, willpower,
##                         intellect, intuition, social} each int in [1–6]
##   skills             — Dictionary of arbitrary skill keys (e.g. "mobility",
##                        "determination") each an int score. Kept SEPARATE
##                        from `attributes` (independent attribute set — no
##                        repeating-group violation) so it never perturbs
##                        Attributes.point_buy_validate()'s REQUIRED_KEYS
##                        check. Missing keys are NOT an error: read via
##                        skills.get(key, 0) — the same pattern already used
##                        to read `attributes` elsewhere in this codebase —
##                        for a 0 default; this class carries zero business
##                        logic, so no bespoke accessor method is added here.
##                        Data-layer prerequisite for skill-based
##                        reaction/defense checks (FR-007, e.g. Dodge/Steel).
##   starting_equipment — Array of Resource paths (WeaponResource / ArmorResource)
##   talent_selections  — Array of talent identifiers chosen at character creation
##   known_spell_ids    — Array of spell_id Strings this character knows
##                        (FEAT-002, Iteration M P0-0). Empty for non-casters.

class_name CharacterResource
extends Resource

## Display name for this character.
@export var name: String = ""

## Race identifier (cosmetic in v0; no mechanical effect yet).
@export var race: String = ""

## Reference to the ClassResource that defines this character's class constants.
@export var class_ref: Resource = null

## Attribute scores — seven keys, each int in [1, 6].
## Keys: strength, constitution, dexterity, willpower, intellect, intuition, social.
@export var attributes: Dictionary = {}

## Skill scores — arbitrary string keys (e.g. "mobility", "determination"),
## each an int score. Distinct Dictionary from `attributes`; unknown/missing
## keys are legal — read via skills.get(key, 0) for a 0 default, never
## raised as an error.
@export var skills: Dictionary = {}

## Array of Resource paths pointing to starting WeaponResource / ArmorResource instances.
@export var starting_equipment: Array = []

## Array of talent identifiers selected during character creation.
@export var talent_selections: Array = []

## Array of spell_id Strings (FK-by-id references into the SpellResource
## catalog, e.g. "fire_bolt"/"channel" — see core/resources/spell_resource.gd)
## this character knows how to cast. Empty by default for non-caster
## characters (e.g. Titus, Gram Marx). The character's spellcasting attribute
## itself is NOT duplicated here — it already lives on class_ref
## (core/model/class_resource.gd's spellcasting_attribute), so a caster's
## governing attribute is read via character.class_ref.spellcasting_attribute,
## never copied onto this resource (3NF: no derived/duplicated field).
@export var known_spell_ids: Array = []

## The attribute that drives this character's primary offensive output.
## Examples: "strength" (melee martial), "dexterity" (finesse/ranged),
## "willpower" (divine caster), "intellect" (arcane caster).
## Empty string ("") is the default for backward compatibility with
## existing .tres files that do not declare this field (e.g. Titus v0).
@export var primary_offensive_attribute: String = ""
