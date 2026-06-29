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
##   starting_equipment — Array of Resource paths (WeaponResource / ArmorResource)
##   talent_selections  — Array of talent identifiers chosen at character creation

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

## Array of Resource paths pointing to starting WeaponResource / ArmorResource instances.
@export var starting_equipment: Array = []

## Array of talent identifiers selected during character creation.
@export var talent_selections: Array = []

## The attribute that drives this character's primary offensive output.
## Examples: "strength" (melee martial), "dexterity" (finesse/ranged),
## "willpower" (divine caster), "intellect" (arcane caster).
## Empty string ("") is the default for backward compatibility with
## existing .tres files that do not declare this field (e.g. Titus v0).
@export var primary_offensive_attribute: String = ""
