## core/geometry/encounter_tile_adapter.gd — EncounterTileAdapter
## (FEAT-002 / US-002 / FR-004; ADR-001, ADR-002; NFR-003, RISK-012)
##
## Infrastructure/adapter layer (Clean Architecture): the single translation
## boundary between the data layer's persisted tile schema
## (data/tiles/hex_tile_data_resource.gd's `passable`/`difficult` @export
## fields, reached via a live data/encounters/encounter_resource.gd) and the
## application layer's caller-supplied Callable port shape consumed by
## core/geometry/hex_pathfinder.gd's find_path():
##   PassabilityQuery := Callable(HexCoord) -> bool
##   MoveCostQuery    := Callable(HexCoord) -> float
##
## Like core/geometry/hex_pathfinder.gd, this file is a stateless namespace
## of `static func`s only (no instance state, no `_init`) — it never extends
## Node/Control/CanvasItem and never imports one, and it manufactures fresh
## Callables (closing over a locally-built lookup Dictionary) rather than
## exposing any instance to hold state. This is the RISK-006 mitigation
## extended to this file, verified mechanically by
## tests/unit/core/geometry/test_architecture_purity.gd.
##
## NFR-003 / RISK-012: this adapter is the ONLY place tile-schema knowledge
## is translated into pathfinding queries. It does NOT add any new field to
## HexTileDataResource — see
## tests/unit/core/geometry/test_encounter_tile_adapter.gd's property-list
## diff assertion, which pins HexTileDataResource's exact field set and
## fails this feature if a future edit tries to smuggle a new field in here
## instead of solving the problem via translation.
##
## Open-world default (per this feature's design notes / api_contracts):
## any HexCoord with no authored entry in `encounter.tiles` (either because
## the encounter has no tiles at all, or because that specific hex was never
## edited) resolves to passable=true, cost=1.0 — there is no error path.
## `encounter == null` is a caller contract violation, not guarded here.
##
## Usage:
##   var is_passable: Callable = EncounterTileAdapter.make_is_passable(encounter)
##   var move_cost: Callable = EncounterTileAdapter.make_move_cost(encounter)
##   var path: Array = HexPathfinder.find_path(start, goal, is_passable, move_cost)

class_name EncounterTileAdapter

## Move cost (in abstract move-cost units, matching HexPathfinder's
## move_cost contract) charged for entering a tile authored with
## difficult=true.
const _DIFFICULT_TERRAIN_MOVE_COST: float = 2.0

## Move cost charged for entering any tile that is neither difficult nor
## authored at all (the open-world default).
const _NORMAL_MOVE_COST: float = 1.0


## make_is_passable(encounter) → Callable(HexCoord) -> bool — builds the
## PassabilityQuery port Callable for `encounter`. Any hex not authored in
## encounter.tiles resolves to true (open-world default); an authored tile
## resolves to its own `passable` flag verbatim.
static func make_is_passable(encounter) -> Callable:
	var tiles_by_key: Dictionary = _index_tiles(encounter)
	return func(hex_coord):
		var tile = tiles_by_key.get(_key(hex_coord))
		if tile == null:
			return true
		return tile.passable


## make_move_cost(encounter) → Callable(HexCoord) -> float — builds the
## MoveCostQuery port Callable for `encounter`. Any hex not authored in
## encounter.tiles resolves to 1.0 (open-world default). An authored,
## impassable tile resolves to INF (it can never be legally entered, so its
## "cost" is unreachable by definition); an authored, passable, difficult
## tile resolves to 2.0; any other authored, passable tile resolves to 1.0.
static func make_move_cost(encounter) -> Callable:
	var tiles_by_key: Dictionary = _index_tiles(encounter)
	return func(hex_coord):
		var tile = tiles_by_key.get(_key(hex_coord))
		if tile == null:
			return _NORMAL_MOVE_COST
		if not tile.passable:
			return INF
		if tile.difficult:
			return _DIFFICULT_TERRAIN_MOVE_COST
		return _NORMAL_MOVE_COST


## _index_tiles(encounter) → Dictionary (String -> HexTileDataResource) —
## builds a one-shot (q, r) -> tile lookup from encounter.tiles, keyed with
## the same "%d,%d" convention as core/geometry/hex_pathfinder.gd's `_key()`
## so the two files agree on hex identity.
static func _index_tiles(encounter) -> Dictionary:
	var tiles_by_key: Dictionary = {}
	for tile in encounter.tiles:
		tiles_by_key[_tile_key(tile)] = tile
	return tiles_by_key


## _key(hex_coord) → String — stable Dictionary key for a HexCoord's (q, r)
## pair, matching core/geometry/hex_pathfinder.gd's `_key()` convention.
static func _key(hex_coord) -> String:
	return "%d,%d" % [hex_coord.q, hex_coord.r]


## _tile_key(tile) → String — stable Dictionary key for a HexTileDataResource's
## own (q, r) pair, using the same "%d,%d" convention as `_key()` above so an
## authored tile is found regardless of whether it was looked up by a
## HexCoord or indexed by its own fields.
static func _tile_key(tile) -> String:
	return "%d,%d" % [tile.q, tile.r]
