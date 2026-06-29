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
##   weapon  — Dictionary with keys: die (int), proficiency_bonus (int), attribute (String)
##
## Usage:
##   var enemy = ResourceLoader.load("res://data/enemies/skeleton.tres")
##   print(enemy.name)                    # "Skeleton"
##   print(enemy.hp)                      # 8
##   print(enemy.weapon.get("die"))       # 6

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

## Weapon definition Dictionary with keys:
##   die              (int)    — damage die size (e.g. 6 for d6)
##   proficiency_bonus (int)   — flat bonus added to attack rolls when proficient
##   attribute        (String) — attribute driving damage modifier: 'str' or 'dex'
@export var weapon: Dictionary = {}
