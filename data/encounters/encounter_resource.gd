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
## Fields (FEAT-089 / FR-012; hex position fields added FEAT-001 / US-001;
## tiles field added FEAT-004 / US-002, FR-002; weapon_path_overrides field
## added FEAT-004 / US-004, FR-004, NFR-005; off_hand_path_overrides field
## added FEAT-003 / US-003, FR-005 — additive-only, no prior
## field renamed/removed/altered):
##   party_resource_paths  — Array of res:// paths to CharacterResource .tres files
##                           for party members (e.g. ["res://data/characters/titus.tres"])
##   enemy_resource_paths  — Array of res:// paths to EnemyResource .tres files
##                           for enemies (e.g. ["res://data/enemies/skeleton.tres"])
##   party_hex_positions   — Array of {"q": int, "r": int} Dictionaries, parallel
##                           (by index) to party_resource_paths — each party
##                           member's starting flat-top axial hex position
##                           (v0-release-2 spec, Amendment log — movement).
##   enemy_hex_positions   — Array of {"q": int, "r": int} Dictionaries, parallel
##                           (by index) to enemy_resource_paths — each enemy's
##                           starting flat-top axial hex position.
##   seed                  — Non-negative int; RNG seed for deterministic encounter
##                           replay. Tests pin this value for reproducible outcomes.
##   tiles                 — Array[HexTileDataResource]; optional hex battlefield
##                           layout for this encounter (FEAT-004 / US-002).
##                           Defaults to [] so pre-existing .tres fixtures that
##                           omit this field (e.g. prologue_encounter.tres) load
##                           unchanged. Each entry is keyed by its own (q, r);
##                           duplicate (q, r) pairs are not yet validated (future
##                           extension point).
##   weapon_path_overrides — Array of res:// paths to WeaponResource .tres files,
##                           positionally parallel (by index) to
##                           enemy_resource_paths — slot i's override lives at
##                           weapon_path_overrides[i] (FEAT-004 / US-004, FR-004,
##                           NFR-005). An empty string, or an index beyond the
##                           array's bounds, both mean "no override — use the
##                           enemy's own weapon_paths[0]"; resolution happens at
##                           combatant-build time, not at authoring time.
##                           Defaults to [] so pre-existing .tres fixtures that
##                           omit this field continue to load unchanged, with no
##                           migration required (purely additive, backward
##                           compatible).
##   off_hand_path_overrides — Array of res:// paths to WeaponResource .tres
##                           files, positionally parallel (by index) to
##                           enemy_resource_paths — slot i's off-hand override
##                           lives at off_hand_path_overrides[i] (FEAT-003 /
##                           US-003, FR-005). An empty string, or an index
##                           beyond the array's bounds, both mean "no
##                           override — use the enemy's own weapon_paths[1]
##                           if present"; resolution happens at
##                           combatant-build time, not at authoring time.
##                           Defaults to [] so pre-existing .tres fixtures
##                           that omit this field continue to load unchanged,
##                           with no migration required (purely additive,
##                           backward compatible, matching
##                           weapon_path_overrides above).
##
## Usage:
##   var enc = ResourceLoader.load("res://data/encounters/prologue_encounter.tres")
##   print(enc.party_resource_paths)      # ["res://data/characters/titus.tres"]
##   print(enc.enemy_resource_paths)      # ["res://data/enemies/skeleton.tres"]
##   print(enc.party_hex_positions)       # [{"q": 0, "r": 0}]
##   print(enc.enemy_hex_positions)       # [{"q": 1, "r": 0}]
##   print(enc.seed)                      # 42
##   print(enc.tiles)                     # [] (unless a tiles layout was authored)
##   print(enc.weapon_path_overrides)     # [] (unless per-slot weapon overrides were authored)
##   print(enc.off_hand_path_overrides)   # [] (unless per-slot off-hand overrides were authored)

class_name EncounterResource
extends Resource

## Array of res:// paths to CharacterResource .tres files for party members.
## Must be non-empty for a valid encounter.
@export var party_resource_paths: Array = []

## Array of res:// paths to EnemyResource .tres files for enemies.
## Must be non-empty for a valid encounter.
@export var enemy_resource_paths: Array = []

## Array of {"q": int, "r": int} Dictionaries, parallel to party_resource_paths —
## each party member's starting flat-top axial hex position (FEAT-001 / US-001).
@export var party_hex_positions: Array = []

## Array of {"q": int, "r": int} Dictionaries, parallel to enemy_resource_paths —
## each enemy's starting flat-top axial hex position (FEAT-001 / US-001).
@export var enemy_hex_positions: Array = []

## Non-negative integer seed for the encounter's RNG.
## Injected into core/rules/rng.gd (ADR-002) at encounter construction time.
## Same seed always produces the same sequence of rolls and outcome.
@export var seed: int = 0

## Optional hex battlefield layout for this encounter (FEAT-004 / US-002,
## FR-002). Additive field: defaults to [] so pre-existing .tres fixtures
## that predate this field (e.g. prologue_encounter.tres) continue to load
## with an empty tiles array and every other field unchanged (RISK-003).
@export var tiles: Array[HexTileDataResource] = []

## Optional per-encounter-slot weapon overrides (FEAT-004 / US-004, FR-004,
## NFR-005), positionally parallel to enemy_resource_paths: slot i's override
## lives at weapon_path_overrides[i]. An empty string, or an index beyond the
## array's bounds, both mean "no override — use the enemy's own
## weapon_paths[0]". Additive field: defaults to [] so pre-existing .tres
## fixtures that predate this field continue to load unmodified with every
## other field unchanged (RISK-003 pattern, matching `tiles` above).
@export var weapon_path_overrides: Array[String] = []

## Optional per-encounter-slot off-hand weapon overrides (FEAT-003 / US-003,
## FR-005), positionally parallel to enemy_resource_paths: slot i's override
## lives at off_hand_path_overrides[i]. An empty string, or an index beyond
## the array's bounds, both mean "no override — use the enemy's own
## weapon_paths[1] if present". Additive field: defaults to [] so
## pre-existing .tres fixtures that predate this field continue to load
## unmodified with every other field unchanged (RISK-009, matching the
## weapon_path_overrides convention above per ADR-005).
@export var off_hand_path_overrides: Array[String] = []
