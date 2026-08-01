## core/resources/item_resource.gd — ItemResource authoring schema
## (FEAT-002, Iteration M, US-002; FR-002 data half)
##
## Custom Resource encoding an item's immutable authoring data, authored
## directly as data/items/{item_id}.tres and loaded via the project's
## existing generic .tres loading path (ResourceLoader), exactly like the
## established core/resources/spell_resource.gd SpellResource pattern.
##
## Architecture note (Clean Architecture / ADR-001), matching the SAME
## established convention as core/resources/spell_resource.gd: this file
## extends Resource — NOT Node, Control, or CanvasItem — and carries ZERO
## business logic; it is a pure typed data container for the
## AUTHORING/on-disk shape. is_valid()/validation_error() perform only
## local field validation (no cross-entity logic, no I/O), mirroring the
## existing SpellResource contract.
##
## Fields (design notes' data_model, ITEM entity):
##   item_id           — canonical string identifier matching the .tres
##                        filename by convention (e.g. "iron_sword").
##   display_name       — human-readable name shown to the player.
##   slot               — core/model/equipment_slot.gd EquipmentSlot constant
##                        this item occupies. Must be in [0, 14].
##   two_handed         — true when equipping this item in MAIN_HAND blocks
##                        OFF_HAND (see CharacterResource.is_slot_blocked()).
##   is_implement       — true when this item can hold a prepared spell.
##   prepared_spell_id  — spell catalog spell_id currently prepared on this
##                        item; "" == none prepared.
##   is_charged         — true when this item currently holds a charge.
##   damage_type        — (FEAT-004; US-003/FR-005/FR-006) the damage type
##                        this item deals when used as a weapon (e.g.
##                        "slashing", "bludgeoning", "piercing"); "" ==
##                        not applicable (non-weapon items). Additive/
##                        backward-compatible: a pre-existing fixture
##                        lacking this field loads with damage_type=="" and
##                        identical prior behavior (NFR-001).
##
## Usage:
##   var sword = ResourceLoader.load("res://data/items/iron_sword.tres")
##   sword.slot         # EquipmentSlot.MAIN_HAND
##   sword.is_valid()   # true

class_name ItemResource
extends Resource

## Canonical string identifier matching the .tres filename (e.g. "iron_sword").
@export var item_id: String = ""

## Display name shown to the player.
@export var display_name: String = ""

## EquipmentSlot constant (core/model/equipment_slot.gd) this item occupies.
## Must be in [0, 14] — see EquipmentSlot.ALL_SLOTS.
@export var slot: int = 0

## True when equipping this item in MAIN_HAND blocks OFF_HAND.
@export var two_handed: bool = false

## True when this item can hold a prepared spell.
@export var is_implement: bool = false

## Spell catalog spell_id currently prepared on this item; "" == none.
@export var prepared_spell_id: String = ""

## True when this item currently holds a charge.
@export var is_charged: bool = false

## Damage type this item deals when used as a weapon (e.g. "slashing",
## "bludgeoning", "piercing"); "" == not applicable. FEAT-004 (US-003;
## FR-005/FR-006). Defaults to "" so pre-existing fixtures/callers are
## unaffected (NFR-001 backward compatibility).
@export var damage_type: String = ""


## is_valid() -> bool — true when every load-time invariant holds (see
## validation_error()). Callers (adapters) MUST check this before trusting
## or exposing a hydrated instance.
func is_valid() -> bool:
	return validation_error() == ""


## validation_error() -> String — the human-readable reason this
## ItemResource violates a load-time invariant, or "" when valid.
## Computed on demand (not cached at construction) since Resource
## subclasses are hydrated field-by-field by ResourceLoader, not via a
## parameterized constructor call site. Mirrors the existing
## SpellResource.validation_error() contract.
func validation_error() -> String:
	if item_id == "":
		return "item_id must not be empty"
	if slot < 0 or slot > 14:
		return "slot must be in [0, 14] (got %d)" % slot
	return ""
