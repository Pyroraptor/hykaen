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

## Preloaded (not referenced via bare global class_name) because the
## project's .godot/global_script_class_cache.cfg is not guaranteed to be
## regenerated between headless CI test runs -- using preload() here keeps
## this file's dependency on EquipmentSlot's constants resolvable
## regardless of global class cache state.
const _EquipmentSlot = preload("res://core/model/equipment_slot.gd")

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

## Character level (FEAT-003, Iteration steel-thread equipment/spell-prep).
## Drives PrepareSpellUseCase's prepared-spell-count cap (design notes'
## API contract #7). Defaults to 1 for backward compatibility with
## existing .tres files that do not declare this field (RISK-004).
@export var level: int = 1

## Array of ItemResource instances (core/resources/item_resource.gd)
## currently equipped by this character, keyed implicitly by each item's
## own `slot` field (see EquipmentSlot). Composite conceptual key
## (character, slot) uniqueness is enforced by EquipItemUseCase, not by
## this Resource (design notes' data_model, CHARACTER_EQUIPMENT). Empty
## by default for backward compatibility with existing .tres files that
## do not declare this field (RISK-004).
@export var equipped_items: Array = []


## get_item_in_slot(slot: int) -> ItemResource
##
## Returns the first ItemResource in `equipped_items` whose `slot` field
## matches `slot`, or null if no equipped item occupies that slot. Pure
## domain accessor: never raises, never mutates state (API contract #3).
func get_item_in_slot(slot: int) -> Resource:
	for item in equipped_items:
		if item != null and item.slot == slot:
			return item
	return null


## is_slot_blocked(slot: int) -> bool
##
## True only when `slot` is OFF_HAND and the currently equipped MAIN_HAND
## item exists and has `two_handed == true` (RISK-006's asymmetric
## two-handed/off-hand blocking rule: MAIN_HAND's two_handed flag blocks
## OFF_HAND, never the reverse). False for every other slot/state
## combination. Pure predicate: never raises (API contract #4).
func is_slot_blocked(slot: int) -> bool:
	if slot != _EquipmentSlot.OFF_HAND:
		return false
	var main_hand_item: Resource = get_item_in_slot(_EquipmentSlot.MAIN_HAND)
	return main_hand_item != null and main_hand_item.two_handed == true
