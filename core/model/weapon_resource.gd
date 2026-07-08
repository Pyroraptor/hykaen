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
##
## FEAT-140 (DEF-007 / FR-014, US-007) addition:
##   range_hexes                — maximum core/geometry/hex_math.gd
##                                 HexMath.hex_distance() at which this
##                                 weapon may Strike a target. Melee weapons
##                                 (all fixtures prior to FEAT-140) use the
##                                 default of 1 hex — equivalent to the
##                                 existing hex_neighbors()-based adjacency
##                                 precondition (FEAT-003/US-003). Ranged
##                                 weapons (e.g. a shortbow/longbow) set this
##                                 to their listed range converted to hexes
##                                 (5 ft. == 1 hex, per docs/design-source/
##                                 Weapons.pdf), reusing the SAME hex
##                                 distance math rather than a re-derived
##                                 notion of range (core/application/
##                                 resolve_action_use_case.gd).

class_name WeaponResource
extends Resource

## Canonical string identifier matching the .tres filename (e.g. "longsword").
@export var weapon_id: String = ""

## Display name shown to the player.
@export var name: String = ""

## Die size used when rolling weapon damage (e.g. 6 = d6).
@export var damage_die: int = 0

## Damage type letter: 'S' (slashing), 'P' (piercing), 'B' (bludgeoning).
## Source: docs/design-source/Weapons.pdf (Dam. column letter suffix).
@export var damage_type: String = ""

## Number of damage dice rolled per attack (v0: always 1).
@export var damage_count: int = 1

## Attribute whose modifier is added to damage rolls: 'str' or 'dex'.
@export var damage_modifier_attribute: String = ""

## Flat proficiency bonus added to attack rolls when the character is trained.
@export var proficiency_bonus: int = 0

## Flat bonus applied when using the Block reaction.
## Reduces incoming damage by 1[W] + block_value (scales 2[W] at tier 2, 3[W] at tier 3).
## Zero means this weapon cannot Block effectively.
## Source: docs/design-source/Weapons.pdf (Block column).
@export var block_value: int = 0

## Flat bonus added to the defender's attack roll when using the Parry reaction.
## A parry roll of (d20 + parry_bonus) > attacker's attack roll negates the attack.
## Zero means this weapon has no parry capability.
## Source: docs/design-source/Weapons.pdf (Parry column).
@export var parry_bonus: int = 0

## Die size used for the Block reaction's damage-reduction roll, for weapons
## (e.g. shields) that block with a die distinct from their damage_die.
## Zero means "unset" — core/rules/resolution.gd's Block reaction falls back
## to the blocking weapon's damage_die when this is 0/absent. No v0 weapon
## fixture sets this (no shield weapon exists yet — see iteration-H B-1);
## it exists so future shield resources can override the fallback.
## Source: docs/design-source/Weapons.pdf (Block column, shield entries).
@export var block_die: int = 0

## Maximum hex_distance (core/geometry/hex_math.gd HexMath.hex_distance())
## at which this weapon may Strike a target. Defaults to 1 — melee reach,
## i.e. adjacency-only (5 ft. per docs/design-source/Weapons.pdf's Range
## column == 1 hex), matching every pre-FEAT-140 melee weapon fixture
## without requiring their .tres files to be touched. Ranged weapons set
## this higher (e.g. a shortbow's 40 ft. short range == 8 hexes).
## Source: docs/design-source/Weapons.pdf (Range column).
@export var range_hexes: int = 1
