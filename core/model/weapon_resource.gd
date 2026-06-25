## core/model/weapon_resource.gd — WeaponResource value object (ADR-003)
##
## Custom Resource encoding a weapon's immutable rule constants.
## Loaded from data/weapons/{weapon_id}.tres via ResourceLoader.
##
## Architecture note (Clean Architecture / ADR-001):
##   This file lives in the DOMAIN layer (core/model/).
##   It extends Resource — NOT Node, Control, or CanvasItem.
##   It carries ZERO business logic; it is a pure typed data container.
##
## Fields match the v0 spec from US-006:
##   weapon_id                  — canonical string identifier (e.g. "longsword")
##   name                       — display name (e.g. "Longsword")
##   damage_die                 — die size for damage rolls (e.g. 6 for d6)
##   damage_count               — number of dice rolled for damage (1 in v0)
##   damage_modifier_attribute  — attribute added to damage: 'str' or 'dex'
##   proficiency_bonus          — flat bonus added when proficient (+1–3)

class_name WeaponResource
extends Resource

## Canonical string identifier matching the .tres filename (e.g. "longsword").
@export var weapon_id: String = ""

## Display name shown to the player.
@export var name: String = ""

## Die size used when rolling weapon damage (e.g. 6 = d6).
@export var damage_die: int = 0

## Number of damage dice rolled per attack (v0: always 1).
@export var damage_count: int = 1

## Attribute whose modifier is added to damage rolls: 'str' or 'dex'.
@export var damage_modifier_attribute: String = ""

## Flat proficiency bonus added to attack rolls when the character is trained.
@export var proficiency_bonus: int = 0
