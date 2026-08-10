## data/enemies/enemy_resource.gd — EnemyResource value object (ADR-003 / FEAT-088)
##
## Custom Resource encoding an enemy's base stats and weapon definition.
## Loaded from data/enemies/{enemy_id}.tres via ResourceLoader.
##
## Architecture note (Clean Architecture / ADR-001):
##   This file lives in the DATA layer (data/enemies/).
##   It extends Resource — NOT Node, Control, or CanvasItem.
##   It carries ZERO business logic; it is a pure typed data container.
##   Domain purity: no SQLAlchemy, FastAPI, or Godot Node/Control imports.
##
## Fields (FEAT-088 / US-009):
##   name    — enemy display name (e.g. "Skeleton")
##   hp      — base hit points (template stat, e.g. 8)
##   str     — strength attribute score
##   dex     — dexterity attribute score
##
## Weapon reference (FEAT-002 / US-002, ADR-001/ADR-002):
##   weapon_paths — ordered Array of res:// path Strings, each a
##       foreign-key-by-URI reference to a normalized WeaponResource
##       (data/weapons/*.tres, core/model/weapon_resource.gd). Index 0 is
##       the primary weapon. Defaults to [] (no weapon configured is a
##       valid, explicitly-erroring state — resolved/validated by
##       infrastructure, never here). This REPLACES the legacy inline
##       `weapon: Dictionary` field and the top-level parry_bonus/
##       block_value/block_die fields that used to duplicate a weapon's
##       stats onto every enemy that carried it; that data now lives
##       exclusively on the referenced WeaponResource.
##
## Defense and attribute fields (FEAT-001 / US-001 / FR-006 / ADR-104):
##   ac, fortitude, reflex, will               — AUTHORED defense scores.
##       These are pinned integers set directly on the .tres asset; they
##       are NEVER derived/recomputed from attributes at load time (see
##       ADR-104 / ADR-004) so balancing can tweak a defense directly
##       without touching attributes.
##   constitution, intuition, willpower,
##   social, intellect                          — remaining attribute
##       scores (alongside str/dex above), also authored, plain data.
##
## Usage:
##   var enemy = ResourceLoader.load("res://data/enemies/skeleton.tres")
##   print(enemy.name)                    # "Skeleton"
##   print(enemy.hp)                      # 8
##   var weapon = ResourceLoader.load(enemy.weapon_paths[0])
##   print(weapon.damage_die)             # 6

class_name EnemyResource
extends Resource

## Enemy display name shown in combat log (e.g. "Skeleton").
@export var name: String = ""

## Base hit points for this enemy type (template value from spec).
@export var hp: int = 0

## Strength attribute score (drives melee damage modifier calculations).
@export var str: int = 0

## Dexterity attribute score (drives ranged/finesse modifier and initiative).
@export var dex: int = 0

## Ordered Array of res:// path Strings, each referencing a normalized
## WeaponResource (data/weapons/*.tres). Index 0 is the primary weapon.
## Defaults to [] — an enemy with no weapon configured is a valid,
## explicitly-erroring state (resolved/validated by infrastructure, e.g.
## infrastructure/combatant_factory.gd, never here — ADR-104). See
## FEAT-002 / US-002 / ADR-001 / ADR-002.
@export var weapon_paths: Array = []

## Armor Class — authored defense score (ADR-104). Static read, never
## recomputed from attributes at load time.
@export var ac: int = 0

## Fortitude defense — authored defense score (ADR-104).
@export var fortitude: int = 0

## Reflex defense — authored defense score (ADR-104).
@export var reflex: int = 0

## Will defense — authored defense score (ADR-104).
@export var will: int = 0

## Constitution attribute score.
@export var constitution: int = 0

## Intuition attribute score.
@export var intuition: int = 0

## Willpower attribute score.
@export var willpower: int = 0

## Social attribute score.
@export var social: int = 0

## Intellect attribute score.
@export var intellect: int = 0

## Skill scores (FEAT-002 / US-006 / FR-007) — arbitrary string keys (e.g.
## "mobility", "determination"), each an int score. Kept SEPARATE from the
## attribute fields above (independent attribute set, not a repeating
## group) so it never perturbs Attributes.point_buy_validate()'s
## REQUIRED_KEYS check (which only ever inspects CharacterResource
## `attributes`, and never touches this field at all).
##
## Accessor pattern: this Resource carries ZERO business logic (ADR-104 —
## enemy_resource.gd must contain no functions), so there is no bespoke
## get_skill() method here. Read a skill score the same way `attributes`
## values are read elsewhere in this codebase: `skills.get(key, 0)`,
## which naturally defaults a missing key to 0.
## Data-layer prerequisite for skill-based reaction/defense checks
## (Dodge/Steel).
@export var skills: Dictionary = {}
