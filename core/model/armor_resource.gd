## core/model/armor_resource.gd — ArmorResource value object (ADR-003)
##
## Custom Resource encoding a piece of armor's immutable rule constants.
## Loaded from data/armor/{armor_id}.tres via ResourceLoader.
##
## Architecture note (Clean Architecture / ADR-001):
##   This file lives in the DOMAIN layer (core/model/).
##   It extends Resource — NOT Node, Control, or CanvasItem.
##   It carries ZERO business logic; it is a pure typed data container.
##
## Fields match the v0 spec from US-006:
##   armor_id  — canonical string identifier (e.g. "scale_mail")
##   name      — display name (e.g. "Scale Mail")
##   ac_base   — base Armor Class value provided by this armor
##   category  — armor weight category: 'none' | 'light' | 'medium' | 'heavy'
##               (determines whether DEX modifier applies to AC)

class_name ArmorResource
extends Resource

## Canonical string identifier matching the .tres filename (e.g. "scale_mail").
@export var armor_id: String = ""

## Display name shown to the player.
@export var name: String = ""

## Base Armor Class contribution from this armor piece.
@export var ac_base: int = 0

## Weight category controlling DEX applicability to AC.
## Valid values: 'none', 'light', 'medium', 'heavy'.
@export var category: String = ""
