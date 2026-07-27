extends GutTest
## tests/unit/core/geometry/test_encounter_tile_adapter.gd
##
## GUT test suite for FEAT-002 / US-002 / FR-004 — EncounterTileAdapter's
## tile-to-pathfinding bridge (core/geometry/encounter_tile_adapter.gd).
##
## Verifies (per this feature's test_criteria):
##   1. make_is_passable returns false for tiles authored with passable=false.
##   2. make_is_passable defaults any unedited/unauthored hex to
##      passable=true (open-world default).
##   3. make_move_cost returns 1.0 for normal, 2.0 for difficult, INF for
##      impassable tiles.
##   4. no new fields exist on HexTileDataResource after this change
##      (property-list diff assertion, NFR-003, RISK-012).
##
## The extended architecture-purity check covering BOTH hex_pathfinder.gd
## and encounter_tile_adapter.gd (RISK-006) lives in its own file,
## tests/unit/core/geometry/test_architecture_purity.gd, per this feature's
## files_to_modify list.

const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")
const EncounterResourceClass: GDScript = preload("res://data/encounters/encounter_resource.gd")
const HexTileDataResourceClass: GDScript = preload("res://data/tiles/hex_tile_data_resource.gd")
const EncounterTileAdapterClass: GDScript = preload("res://core/geometry/encounter_tile_adapter.gd")
const CombatantClass: GDScript = preload("res://core/domain/combatant.gd")

const HEX_TILE_DATA_RESOURCE_PATH: String = "res://data/tiles/hex_tile_data_resource.gd"

## NFR-003 / RISK-012 pin: the exact, complete set of @export fields
## HexTileDataResource is authored with as of this feature. If a future
## edit adds a new field to solve a tile-schema problem instead of
## translating it through EncounterTileAdapter, this list (and therefore
## test_no_new_fields_exist_on_hex_tile_data_resource below) must be
## updated deliberately -- it must never silently grow.
const _EXPECTED_HEX_TILE_DATA_RESOURCE_FIELDS: Array = [
	"q", "r", "passable", "difficult", "terrain_type", "elevation", "cover", "feature"
]


func _make_tile(q: int, r: int, passable: bool, difficult: bool):
	var tile = HexTileDataResourceClass.new()
	tile.q = q
	tile.r = r
	tile.passable = passable
	tile.difficult = difficult
	return tile


func _make_combatant(combatant_id: String, hex_coord, is_enemy: bool) -> CombatantClass:
	var team: String = "Enemy" if is_enemy else "Player"
	var combatant := CombatantClass.new(combatant_id, combatant_id, team, hex_coord)
	combatant.is_enemy = is_enemy
	return combatant


func _make_encounter(tiles: Array[HexTileDataResourceClass]):
	# NOTE: `tiles` must be typed Array[HexTileDataResourceClass] (matching
	# EncounterResource.tiles' own Array[HexTileDataResource] element type),
	# not a bare `Array` -- GDScript 4.3 only auto-converts an Array literal
	# written directly at an assignment site into a typed Array property; a
	# generic `Array`-typed parameter/local (even one holding only
	# HexTileDataResource elements at runtime) fails that property
	# assignment with "Invalid assignment ... value of type 'Array'".
	var encounter := EncounterResourceClass.new()
	encounter.tiles = tiles
	return encounter


# ── Criterion 1: passable=false authored tile ───────────────────────────────

func test_make_is_passable_returns_false_for_tile_authored_impassable() -> void:
	var blocked_hex = HexCoordClass.new(1, 0)
	var encounter = _make_encounter([_make_tile(1, 0, false, false)])

	var is_passable: Callable = EncounterTileAdapterClass.make_is_passable(encounter)

	assert_false(
		is_passable.call(blocked_hex),
		"a tile authored with passable=false must resolve to false"
	)


func test_make_is_passable_returns_true_for_tile_authored_passable() -> void:
	var open_hex = HexCoordClass.new(2, 0)
	var encounter = _make_encounter([_make_tile(2, 0, true, false)])

	var is_passable: Callable = EncounterTileAdapterClass.make_is_passable(encounter)

	assert_true(
		is_passable.call(open_hex),
		"a tile explicitly authored with passable=true must resolve to true"
	)


# ── Criterion 2: open-world default for unauthored hexes ────────────────────

func test_make_is_passable_defaults_unauthored_hex_to_passable_true() -> void:
	var unauthored_hex = HexCoordClass.new(9, -9)
	var encounter = _make_encounter([_make_tile(1, 0, false, false)])

	var is_passable: Callable = EncounterTileAdapterClass.make_is_passable(encounter)

	assert_true(
		is_passable.call(unauthored_hex),
		"any hex with no authored tile entry must default to passable=true (open-world default)"
	)


func test_make_is_passable_defaults_every_hex_to_passable_true_for_empty_encounter() -> void:
	var any_hex = HexCoordClass.new(0, 0)
	var encounter = _make_encounter([])

	var is_passable: Callable = EncounterTileAdapterClass.make_is_passable(encounter)

	assert_true(
		is_passable.call(any_hex),
		"an encounter with zero authored tiles must default every hex to passable=true"
	)


# ── Criterion 3: make_move_cost — 1.0 / 2.0 / INF ────────────────────────────

func test_make_move_cost_returns_one_for_normal_authored_tile() -> void:
	var normal_hex = HexCoordClass.new(0, 0)
	var encounter = _make_encounter([_make_tile(0, 0, true, false)])

	var move_cost: Callable = EncounterTileAdapterClass.make_move_cost(encounter)

	assert_eq(
		move_cost.call(normal_hex), 1.0,
		"a normal (passable, not difficult) authored tile must cost 1.0 to enter"
	)


func test_make_move_cost_returns_one_for_unauthored_hex() -> void:
	var unauthored_hex = HexCoordClass.new(5, 5)
	var encounter = _make_encounter([])

	var move_cost: Callable = EncounterTileAdapterClass.make_move_cost(encounter)

	assert_eq(
		move_cost.call(unauthored_hex), 1.0,
		"an unauthored hex must cost 1.0 to enter (open-world default)"
	)


func test_make_move_cost_returns_two_for_difficult_authored_tile() -> void:
	var difficult_hex = HexCoordClass.new(1, 1)
	var encounter = _make_encounter([_make_tile(1, 1, true, true)])

	var move_cost: Callable = EncounterTileAdapterClass.make_move_cost(encounter)

	assert_eq(
		move_cost.call(difficult_hex), 2.0,
		"a difficult (passable, difficult=true) authored tile must cost 2.0 to enter"
	)


func test_make_move_cost_returns_inf_for_impassable_tile() -> void:
	var blocked_hex = HexCoordClass.new(2, -2)
	var encounter = _make_encounter([_make_tile(2, -2, false, false)])

	var move_cost: Callable = EncounterTileAdapterClass.make_move_cost(encounter)

	assert_eq(
		move_cost.call(blocked_hex), INF,
		"an impassable authored tile must cost INF to enter"
	)


func test_make_move_cost_returns_inf_for_impassable_tile_even_if_also_difficult() -> void:
	# impassable must win over difficult -- a tile can never be entered at
	# all, so "difficult" is moot once it's impassable.
	var blocked_hex = HexCoordClass.new(3, -3)
	var encounter = _make_encounter([_make_tile(3, -3, false, true)])

	var move_cost: Callable = EncounterTileAdapterClass.make_move_cost(encounter)

	assert_eq(
		move_cost.call(blocked_hex), INF,
		"an impassable tile must cost INF to enter regardless of its difficult flag"
	)


# ── Criterion 4: no new fields added to HexTileDataResource (NFR-003, RISK-012) ─

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable to run the property-list diff assertion" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


## _extract_exported_field_names(content) → Array[String] — static-source-scan
## extraction of every `@export var <name>` field declared in
## hex_tile_data_resource.gd, in declaration order. Mirrors this codebase's
## established source-scan test convention (see
## tests/unit/core/geometry/test_architecture_purity.gd) rather than relying
## on runtime Object.get_property_list()'s engine-added bookkeeping entries,
## so the assertion stays a precise diff of exactly the fields THIS project
## authored.
func _extract_exported_field_names(content: String) -> Array:
	var field_names: Array = []
	for line in content.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("@export var "):
			var after_var: String = trimmed.substr("@export var ".length())
			var name_end: int = after_var.length()
			for separator in [":", "=", " "]:
				var idx: int = after_var.find(separator)
				if idx != -1 and idx < name_end:
					name_end = idx
			field_names.append(after_var.substr(0, name_end))
	return field_names


func test_no_new_fields_exist_on_hex_tile_data_resource() -> void:
	var content: String = _read_source(HEX_TILE_DATA_RESOURCE_PATH)
	if content.is_empty():
		return

	var actual_fields: Array = _extract_exported_field_names(content)

	assert_eq(
		actual_fields, _EXPECTED_HEX_TILE_DATA_RESOURCE_FIELDS,
		"HexTileDataResource's @export field set must be unchanged by this feature (NFR-003, RISK-012) -- " +
		"found: %s" % [actual_fields]
	)


func test_hex_tile_data_resource_instance_exposes_no_unexpected_fields() -> void:
	# Belt-and-suspenders runtime check alongside the source-scan diff above:
	# every expected field must actually be readable on a live instance, and
	# passable/difficult (the two fields this adapter reads) must resolve to
	# their documented defaults when unset.
	var tile = HexTileDataResourceClass.new()
	for field_name in _EXPECTED_HEX_TILE_DATA_RESOURCE_FIELDS:
		assert_true(
			field_name in tile,
			"HexTileDataResource instance must expose field '%s'" % field_name
		)
	assert_eq(tile.passable, true, "HexTileDataResource.passable must still default to true")
	assert_eq(tile.difficult, false, "HexTileDataResource.difficult must still default to false")


# ── TestCombatPassability — FEAT-001 / US-001 (FR-001/NFR-003) ──────────────
# make_combat_is_passable(encounter, all_combatants, mover_id, mover_is_enemy)
# -> Callable(HexCoord) -> bool. Frozen contract — see this feature's design
# notes ("RISK-001 mitigation: treat signature as frozen once this feature
# lands").

func test_combat_is_passable_returns_false_when_tile_is_impassable_regardless_of_occupant() -> void:
	var blocked_hex = HexCoordClass.new(1, 0)
	var encounter = _make_encounter([_make_tile(1, 0, false, false)])
	var all_combatants: Array = []

	var is_passable: Callable = EncounterTileAdapterClass.make_combat_is_passable(
		encounter, all_combatants, "player_0", false
	)

	assert_false(
		is_passable.call(blocked_hex),
		"tile.passable=false must block regardless of occupant"
	)


func test_combat_is_passable_returns_false_when_opposing_faction_occupies_hex() -> void:
	var contested_hex = HexCoordClass.new(2, 0)
	var encounter = _make_encounter([_make_tile(2, 0, true, false)])
	var enemy := _make_combatant("enemy_0", contested_hex, true)
	var all_combatants: Array = [enemy]

	var is_passable: Callable = EncounterTileAdapterClass.make_combat_is_passable(
		encounter, all_combatants, "player_0", false
	)

	assert_false(
		is_passable.call(contested_hex),
		"an opposing-faction occupant must block passability for the mover"
	)


func test_combat_is_passable_returns_true_when_ally_occupies_hex() -> void:
	var ally_hex = HexCoordClass.new(3, 0)
	var encounter = _make_encounter([_make_tile(3, 0, true, false)])
	var ally := _make_combatant("player_1", ally_hex, false)
	var all_combatants: Array = [ally]

	var is_passable: Callable = EncounterTileAdapterClass.make_combat_is_passable(
		encounter, all_combatants, "player_0", false
	)

	assert_true(
		is_passable.call(ally_hex),
		"an ally (same-faction) occupant must NOT block passability"
	)


func test_combat_is_passable_returns_true_for_movers_own_hex() -> void:
	var own_hex = HexCoordClass.new(4, 0)
	var encounter = _make_encounter([_make_tile(4, 0, true, false)])
	var mover := _make_combatant("player_0", own_hex, false)
	var all_combatants: Array = [mover]

	var is_passable: Callable = EncounterTileAdapterClass.make_combat_is_passable(
		encounter, all_combatants, "player_0", false
	)

	assert_true(
		is_passable.call(own_hex),
		"the mover's own hex must always be passable"
	)


func test_combat_is_passable_returns_true_for_untiled_unoccupied_hex() -> void:
	var open_hex = HexCoordClass.new(9, -9)
	var encounter = _make_encounter([])
	var all_combatants: Array = []

	var is_passable: Callable = EncounterTileAdapterClass.make_combat_is_passable(
		encounter, all_combatants, "player_0", false
	)

	assert_true(
		is_passable.call(open_hex),
		"an untiled, unoccupied hex must be passable (open-world default)"
	)


func test_combat_is_passable_with_unknown_mover_id_does_not_crash_and_defaults_to_no_self_exception() -> void:
	var contested_hex = HexCoordClass.new(5, 0)
	var encounter = _make_encounter([_make_tile(5, 0, true, false)])
	var enemy := _make_combatant("enemy_0", contested_hex, true)
	var all_combatants: Array = [enemy]

	# mover_id "" does not match any combatant in all_combatants -- must not
	# crash, and must NOT grant a self-exception to the (nonexistent) mover,
	# so an opposing occupant still blocks.
	var is_passable: Callable = EncounterTileAdapterClass.make_combat_is_passable(
		encounter, all_combatants, "", false
	)

	assert_false(
		is_passable.call(contested_hex),
		"an unknown/undefined mover_id must default to no self-exception -- opposing occupant still blocks"
	)


func test_combat_is_passable_opposing_occupant_on_difficult_terrain_still_blocks() -> void:
	# Sanity cross-check: passability and occupancy are independent of the
	# move-cost/difficult flag -- an opposing occupant blocks even on
	# otherwise-passable difficult terrain.
	var contested_hex = HexCoordClass.new(6, 0)
	var encounter = _make_encounter([_make_tile(6, 0, true, true)])
	var enemy := _make_combatant("enemy_0", contested_hex, true)
	var all_combatants: Array = [enemy]

	var is_passable: Callable = EncounterTileAdapterClass.make_combat_is_passable(
		encounter, all_combatants, "player_0", false
	)

	assert_false(
		is_passable.call(contested_hex),
		"an opposing occupant blocks regardless of the tile's difficult flag"
	)
