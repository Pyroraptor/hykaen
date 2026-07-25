## data/tiles/hex_tile_data_resource.gd — HexTileDataResource value object
## (ADR-104 / ADR-001, FEAT-001 / US-001 / FR-001, NFR-002, NFR-003)
##
## Custom Resource encoding a single hex tile's static, authored terrain
## data. Intended as the foundational building block for the future
## EncounterResource.tiles: Array[HexTileDataResource] field (a later
## feature) — a hex-mapped battlefield will be built as a flat array of
## these, keyed by their (q, r) axial coordinate.
##
## Architecture note (Clean Architecture / ADR-001):
##   This file lives in the DOMAIN layer (data/tiles/).
##   It extends Resource — NOT Node, Control, CanvasItem, or SceneTree.
##   It carries ZERO business logic; it is a pure typed data container,
##   constructed/serialized entirely by Godot's ResourceLoader/ResourceSaver.
##
## Fields:
##   q             — axial hex coordinate, column (core/geometry/hex_math.gd
##                    convention).
##   r             — axial hex coordinate, row.
##   passable      — whether a combatant may occupy/move through this tile.
##   difficult     — whether this tile costs extra movement (difficult
##                    terrain), independent of passable.
##   terrain_type  — display/gameplay terrain label (e.g. "floor", "rubble",
##                    "water"). Defaults to "floor".
##
## Usage:
##   var tile := HexTileDataResource.new()
##   tile.q = 2
##   tile.r = -1
##   tile.terrain_type = "rubble"

class_name HexTileDataResource
extends Resource

## Axial hex coordinate, column (core/geometry/hex_math.gd convention).
@export var q: int = 0

## Axial hex coordinate, row.
@export var r: int = 0

## Whether a combatant may occupy/move through this tile.
@export var passable: bool = true

## Whether this tile is difficult terrain (extra movement cost). Independent
## of `passable` — a tile may be both passable and difficult.
@export var difficult: bool = false

## Display/gameplay terrain label (e.g. "floor", "rubble", "water").
@export var terrain_type: String = "floor"

## Relative elevation in abstract height units (negative = low, positive = raised).
@export var elevation: int = 0

## Cover provided by this tile: 0 = none, 1 = partial, 2 = full.
@export var cover: int = 0

## Named feature on this tile (e.g. "door", "chest", "statue"). Empty = none.
@export var feature: String = ""
