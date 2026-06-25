## core/model/class_resource.gd — ClassData value object (ADR-003)
##
## Custom Resource encoding the immutable rule constants for a playable class.
## Loaded from data/classes/{class_id}.tres at startup via ResourceLoader.
##
## Architecture note (Clean Architecture / ADR-001):
##   This file lives in the DOMAIN layer (core/model/).
##   It extends Resource — NOT Node, Control, or CanvasItem.
##   It carries ZERO business logic; it is a pure typed data container.
##   Validation and derived-stat computation belong in application use cases.
##
## Fields match the v0 spec from US-004:
##   class_id            — canonical string identifier (e.g. "fighter")
##   class_hp            — flat HP contribution added to the character base
##   stamina_base        — base stamina pool before attribute bonuses
##   skills_base         — number of trained skills at character creation
##   spellcasting_attribute — governing attribute for spells; empty string for
##                           non-spellcasting classes (Fighter)

class_name ClassResource
extends Resource

## Canonical string identifier matching the .tres filename (e.g. "fighter").
@export var class_id: String = ""

## Flat HP contribution for this class (added to character HP formula).
@export var class_hp: int = 0

## Base stamina pool before willpower/constitution bonuses are applied.
@export var stamina_base: int = 0

## Number of trained skills available at character creation.
@export var skills_base: int = 0

## Governing attribute used for spellcasting rolls.
## Empty string "" means the class has no spellcasting ability.
@export var spellcasting_attribute: String = ""
