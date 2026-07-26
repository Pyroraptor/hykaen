## data/game_state/game_state_data.gd — GameStateData
## (FEAT-001 / US-001, FR-001)
##
## Custom Resource forming the innermost DOMAIN-layer value container for
## persisted game state: which scenario is active, where the party stands on
## the hex grid, which encounters are already resolved, and each
## combatant's HP/stamina/conditions at the last save point. Resource is
## used here purely as Godot's serialisable-struct mechanism (so it can be
## written/read via ResourceSaver/ResourceLoader and, per the JSON
## persistence strategy at the CurrentGameState adapter boundary,
## JSON.stringify/JSON.parse_string) — NOT as a behavioural/engine object.
## GameStateData carries ZERO logic beyond field defaults; it asserts no
## referential integrity of its own (e.g. it never checks that a
## combatant_id still exists in the current encounter) — that is an
## APPLICATION-layer concern performed by callers at load time.
##
## Architecture note (Clean Architecture):
##   This file lives in the DOMAIN layer (data/game_state/). It extends
##   Resource — NOT Node, Control, CanvasItem, or SceneTree. It carries ZERO
##   business logic; it is a pure typed data container, constructed and
##   serialized entirely by Godot's ResourceLoader/ResourceSaver (or, at the
##   infrastructure boundary, plain JSON).
##
## Design default (FR-001 acceptance criterion): GameStateData.new() yields
## scenario_path == "" and all three arrays == [] (empty, never null), so
## callers can safely call .is_empty() without null-guards.
##
## Fields:
##   scenario_path            — res:// path to the active ScenarioResource.
##                               Empty string means "no scenario chosen yet".
##   party_hex_positions       — Array[Dictionary]; each entry shaped
##                               {combatant_id: String, q: int, r: int}
##                               (the HexCoord value-object convention).
##   completed_encounter_ids   — Array[String]; encounter_id values already
##                               resolved this game.
##   combatant_snapshots       — Array[Dictionary]; each entry shaped
##                               {combatant_id: String, hp_current: int,
##                               stamina: int, conditions: Array[String]}.
##
## Usage:
##   var state := GameStateData.new()
##   state.scenario_path = "res://data/scenarios/prologue_scenario.tres"
##   state.party_hex_positions = [{"combatant_id": "hero_1", "q": 2, "r": -1}]

class_name GameStateData
extends Resource

## res:// path to the active ScenarioResource. Empty string means no
## scenario has been chosen yet.
@export var scenario_path: String = ""

## Array[Dictionary]; each entry shaped {combatant_id, q, r}.
@export var party_hex_positions: Array[Dictionary] = []

## Array[String]; encounter_id values already resolved this game.
@export var completed_encounter_ids: Array[String] = []

## Array[Dictionary]; each entry shaped {combatant_id, hp_current, stamina,
## conditions}.
@export var combatant_snapshots: Array[Dictionary] = []
