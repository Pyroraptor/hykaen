## data/encounters/encounter_resource.gd — EncounterResource schema (FEAT-089 / FR-012)
##
## Custom Resource encoding a loadable, data-driven encounter definition.
## Loaded from data/encounters/{encounter_id}.tres via ResourceLoader.
##
## Architecture note (Clean Architecture / ADR-001):
##   This file lives in the DATA layer (data/encounters/).
##   It extends Resource — NOT Node, Control, or CanvasItem.
##   It carries ZERO business logic; it is a pure typed data container.
##   Domain purity: no SQLAlchemy, FastAPI, or Godot Node/Control imports.
##
## Fields (FEAT-089 / FR-012):
##   party_resource_paths  — Array of res:// paths to CharacterResource .tres files
##                           for party members (e.g. ["res://data/characters/titus.tres"])
##   enemy_resource_paths  — Array of res:// paths to EnemyResource .tres files
##                           for enemies (e.g. ["res://data/enemies/skeleton.tres"])
##   seed                  — Non-negative int; RNG seed for deterministic encounter
##                           replay. Tests pin this value for reproducible outcomes.
##
## Usage:
##   var enc = ResourceLoader.load("res://data/encounters/prologue_encounter.tres")
##   print(enc.party_resource_paths)   # ["res://data/characters/titus.tres"]
##   print(enc.enemy_resource_paths)   # ["res://data/enemies/skeleton.tres"]
##   print(enc.seed)                   # 42

class_name EncounterResource
extends Resource

## Array of res:// paths to CharacterResource .tres files for party members.
## Must be non-empty for a valid encounter.
@export var party_resource_paths: Array = []

## Array of res:// paths to EnemyResource .tres files for enemies.
## Must be non-empty for a valid encounter.
@export var enemy_resource_paths: Array = []

## Non-negative integer seed for the encounter's RNG.
## Injected into core/rules/rng.gd (ADR-002) at encounter construction time.
## Same seed always produces the same sequence of rolls and outcome.
@export var seed: int = 0
