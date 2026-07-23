extends GutTest
## tests/unit/data/tiles/test_hex_tile_data_resource.gd
##
## GUT unit tests for FEAT-001 (US-001 / FR-001, NFR-002, NFR-003):
## data/tiles/hex_tile_data_resource.gd — HexTileDataResource, the pure-data
## tile container that will eventually populate EncounterResource.tiles.
##
## Architecture note (ADR-104 / ADR-001):
##   HexTileDataResource lives in the DOMAIN layer (data/tiles/). It extends
##   Resource (never Node/Control/SceneTree), carries ZERO business logic,
##   and is constructed/serialized purely via Godot's ResourceLoader.
##
## Test criteria covered:
##   1. Default-construction values match spec: q=0, r=0, passable=true,
##      difficult=false, terrain_type='floor'.
##   2. Full round-trip via ResourceSaver.save()/ResourceLoader.load() with
##      no field loss.
##   3. Static review: the file contains no methods beyond trivial
##      defaults/getters and no Node/Control/SceneTree imports.

const HexTileDataResource = preload("res://data/tiles/hex_tile_data_resource.gd")

const ROUND_TRIP_TRES_PATH := "user://test_hex_tile_data_resource_round_trip.tres"


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: default-construction values match spec
# ══════════════════════════════════════════════════════════════════════════════

func test_default_construction_values_match_spec() -> void:
	var res := HexTileDataResource.new()
	assert_eq(res.q, 0, "HexTileDataResource.q must default to 0")
	assert_eq(res.r, 0, "HexTileDataResource.r must default to 0")
	assert_eq(res.passable, true, "HexTileDataResource.passable must default to true")
	assert_eq(res.difficult, false, "HexTileDataResource.difficult must default to false")
	assert_eq(
		res.terrain_type, "floor",
		"HexTileDataResource.terrain_type must default to 'floor'"
	)


func test_fields_are_correctly_typed() -> void:
	var res := HexTileDataResource.new()
	assert_eq(typeof(res.q), TYPE_INT, "q must be typed as int")
	assert_eq(typeof(res.r), TYPE_INT, "r must be typed as int")
	assert_eq(typeof(res.passable), TYPE_BOOL, "passable must be typed as bool")
	assert_eq(typeof(res.difficult), TYPE_BOOL, "difficult must be typed as bool")
	assert_eq(typeof(res.terrain_type), TYPE_STRING, "terrain_type must be typed as String")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: full round-trip via ResourceSaver.save()/ResourceLoader.load()
# ══════════════════════════════════════════════════════════════════════════════

func test_round_trip_save_load_preserves_all_fields() -> void:
	var res := HexTileDataResource.new()
	res.q = 3
	res.r = -2
	res.passable = false
	res.difficult = true
	res.terrain_type = "rubble"

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for round-trip fixture")

	# Force a fresh load from disk rather than returning a cached instance.
	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)

	assert_not_null(reloaded, "Round-trip fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.q, 3, "q must round-trip exactly; got: %d" % reloaded.q)
	assert_eq(reloaded.r, -2, "r must round-trip exactly; got: %d" % reloaded.r)
	assert_eq(reloaded.passable, false, "passable must round-trip exactly")
	assert_eq(reloaded.difficult, true, "difficult must round-trip exactly")
	assert_eq(
		reloaded.terrain_type, "rubble",
		"terrain_type must round-trip exactly; got: %s" % reloaded.terrain_type
	)

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


func test_round_trip_preserves_default_values_too() -> void:
	# Guard against a save/load path that only preserves non-default values
	# (e.g. via a hand-rolled diff-from-default serializer).
	var res := HexTileDataResource.new()

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for default-value fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Default-value fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.q, 0)
	assert_eq(reloaded.r, 0)
	assert_eq(reloaded.passable, true)
	assert_eq(reloaded.difficult, false)
	assert_eq(reloaded.terrain_type, "floor")

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: static review — no business-logic methods, no scene-tree imports
# ══════════════════════════════════════════════════════════════════════════════

func test_hex_tile_data_resource_gd_has_no_business_logic_methods() -> void:
	var file := FileAccess.open("res://data/tiles/hex_tile_data_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/tiles/hex_tile_data_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("func "),
		"hex_tile_data_resource.gd must contain no functions — pure @export data (ADR-104)"
	)


func test_hex_tile_data_resource_gd_extends_resource_not_scene_tree_types() -> void:
	var file := FileAccess.open("res://data/tiles/hex_tile_data_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/tiles/hex_tile_data_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("extends Resource"),
		"hex_tile_data_resource.gd must extend Resource"
	)
	for forbidden in ["extends Node", "extends Control", "extends SceneTree", "extends CanvasItem"]:
		assert_false(
			content.contains(forbidden),
			"hex_tile_data_resource.gd must not contain '%s' (DOMAIN layer purity, ADR-001)" % forbidden
		)
