extends GutTest
## tests/unit/data/encounters/test_encounter_resource_tiles.gd
##
## GUT unit tests for FEAT-004 (US-002 / FR-002, NFR-001):
## data/encounters/encounter_resource.gd — additive `tiles:
## Array[HexTileDataResource] = []` field on the existing EncounterResource.
##
## Also covers FEAT-004 (US-004 / FR-004, NFR-005) — the steel thread's
## additive `weapon_path_overrides: Array = []` field, positionally
## parallel to enemy_resource_paths, enabling an optional per-encounter-slot
## weapon override. Backward-compatible: defaults to [] so every
## pre-existing encounter .tres continues to load unmodified.
##
## Also covers FEAT-003 (US-003 / FR-005) — the additive
## `off_hand_path_overrides: Array[String] = []` field, positionally
## parallel to enemy_resource_paths (matching the weapon_path_overrides
## convention, ADR-005), enabling an optional per-encounter-slot off-hand
## weapon override. Backward-compatible: defaults to [] so every
## pre-existing encounter .tres continues to load unmodified (RISK-009).
##
## Architecture note (Clean Architecture / ADR-001):
##   EncounterResource lives in the DOMAIN layer (data/encounters/). It
##   extends Resource (never Node/Control/SceneTree), carries ZERO business
##   logic, and is constructed/serialized purely via Godot's
##   ResourceLoader/ResourceSaver. This feature ONLY adds a new optional
##   field — no prior field is renamed, removed, or altered (RISK-003).
##
## Test criteria covered:
##   1. Static diff-review guard: EncounterResource still exposes every
##      pre-existing field (party_resource_paths, enemy_resource_paths,
##      party_hex_positions, enemy_hex_positions, seed) with unchanged
##      default values and types, PLUS the new `tiles` field defaulting to [],
##      PLUS the new `weapon_path_overrides` field defaulting to [].
##   2. GUT regression: load data/encounters/prologue_encounter.tres and
##      assert tiles == [], weapon_path_overrides == [], and
##      off_hand_path_overrides == [] while every prior field is intact
##      (matches the committed .tres content verbatim).
##   3. GUT: a populated tiles array of HexTileDataResource entries
##      round-trips via ResourceSaver.save()/ResourceLoader.load() with no
##      field loss (encounter-level fields AND per-tile fields).
##   4. GUT: a weapon_path_overrides array with mixed empty-string and
##      non-empty-string entries round-trips via ResourceSaver.save()/
##      ResourceLoader.load() with no entry loss or mutation.
##   5. GUT: an off_hand_path_overrides array with mixed empty-string and
##      non-empty-string entries round-trips via ResourceSaver.save()/
##      ResourceLoader.load() with no entry loss or mutation, and every
##      pre-existing encounter .tres file loads without error reporting
##      off_hand_path_overrides == [].

const EncounterResource  = preload("res://data/encounters/encounter_resource.gd")
const HexTileDataResource = preload("res://data/tiles/hex_tile_data_resource.gd")

const ROUND_TRIP_TRES_PATH := "user://test_encounter_resource_tiles_round_trip.tres"
const PROLOGUE_ENCOUNTER_PATH := "res://data/encounters/prologue_encounter.tres"


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: no existing field renamed/removed/altered; new `tiles` field
# defaults to an empty array (diff-review regression guard, RISK-003)
# ══════════════════════════════════════════════════════════════════════════════

func test_default_construction_preserves_all_prior_fields() -> void:
	var res := EncounterResource.new()

	assert_true(
		res.party_resource_paths is Array,
		"party_resource_paths must remain an Array (pre-existing field, unaltered)"
	)
	assert_eq(
		res.party_resource_paths, [],
		"party_resource_paths must still default to [] (pre-existing field, unaltered)"
	)
	assert_true(
		res.enemy_resource_paths is Array,
		"enemy_resource_paths must remain an Array (pre-existing field, unaltered)"
	)
	assert_eq(
		res.enemy_resource_paths, [],
		"enemy_resource_paths must still default to [] (pre-existing field, unaltered)"
	)
	assert_true(
		res.party_hex_positions is Array,
		"party_hex_positions must remain an Array (pre-existing field, unaltered)"
	)
	assert_eq(
		res.party_hex_positions, [],
		"party_hex_positions must still default to [] (pre-existing field, unaltered)"
	)
	assert_true(
		res.enemy_hex_positions is Array,
		"enemy_hex_positions must remain an Array (pre-existing field, unaltered)"
	)
	assert_eq(
		res.enemy_hex_positions, [],
		"enemy_hex_positions must still default to [] (pre-existing field, unaltered)"
	)
	assert_eq(
		typeof(res.seed), TYPE_INT,
		"seed must remain typed as int (pre-existing field, unaltered)"
	)
	assert_eq(
		res.seed, 0,
		"seed must still default to 0 (pre-existing field, unaltered)"
	)


func test_new_tiles_field_defaults_to_empty_array() -> void:
	var res := EncounterResource.new()
	assert_true(
		res.tiles is Array,
		"EncounterResource.tiles must be an Array (FEAT-004 additive field)"
	)
	assert_eq(
		res.tiles, [],
		"EncounterResource.tiles must default to [] (FEAT-004 additive field)"
	)


func test_new_weapon_path_overrides_field_defaults_to_empty_array() -> void:
	var res := EncounterResource.new()
	assert_true(
		res.weapon_path_overrides is Array,
		"EncounterResource.weapon_path_overrides must be an Array (FEAT-004 / US-004 additive field)"
	)
	assert_eq(
		res.weapon_path_overrides, [],
		"EncounterResource.weapon_path_overrides must default to [] (FEAT-004 / US-004 additive field)"
	)


func test_new_off_hand_path_overrides_field_defaults_to_empty_array() -> void:
	var res := EncounterResource.new()
	assert_true(
		res.off_hand_path_overrides is Array,
		"EncounterResource.off_hand_path_overrides must be an Array (FEAT-003 / US-003 additive field)"
	)
	assert_eq(
		res.off_hand_path_overrides, [],
		"EncounterResource.off_hand_path_overrides must default to [] (FEAT-003 / US-003 additive field)"
	)


func test_encounter_resource_gd_extends_resource_not_scene_tree_types() -> void:
	var file := FileAccess.open("res://data/encounters/encounter_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/encounters/encounter_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("extends Resource"),
		"encounter_resource.gd must extend Resource (DOMAIN layer purity, ADR-001)"
	)
	for forbidden in ["extends Node", "extends Control", "extends SceneTree", "extends CanvasItem"]:
		assert_false(
			content.contains(forbidden),
			"encounter_resource.gd must not contain '%s' (DOMAIN layer purity, ADR-001)" % forbidden
		)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: GUT regression — prologue_encounter.tres loads with tiles == []
# and every prior field intact (matches the committed .tres content verbatim)
# ══════════════════════════════════════════════════════════════════════════════

func test_prologue_encounter_tres_loads_with_empty_tiles_and_intact_fields() -> void:
	var enc = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(enc, "prologue_encounter.tres must load non-null (FEAT-004 regression gate)")
	if enc == null:
		return

	assert_eq(
		enc.tiles, [],
		"prologue_encounter.tres must load with tiles == [] — no .tres edit was made in FEAT-004"
	)
	assert_eq(
		enc.party_resource_paths,
		["res://data/characters/titus.tres", "res://data/characters/marigold.tres"],
		"prologue_encounter.tres party_resource_paths must be unchanged by FEAT-004"
	)
	assert_eq(
		enc.enemy_resource_paths,
		["res://data/enemies/skeleton.tres"],
		"prologue_encounter.tres enemy_resource_paths must be unchanged by FEAT-004"
	)
	assert_eq(
		enc.party_hex_positions,
		[{"q": 0, "r": 0}, {"q": -1, "r": 0}, {"q": -2, "r": 0}],
		"prologue_encounter.tres party_hex_positions must be unchanged by FEAT-004"
	)
	assert_eq(
		enc.enemy_hex_positions,
		[{"q": 1, "r": 0}],
		"prologue_encounter.tres enemy_hex_positions must be unchanged by FEAT-004"
	)
	assert_eq(
		enc.seed, 42,
		"prologue_encounter.tres seed must be unchanged by FEAT-004"
	)
	assert_eq(
		enc.weapon_path_overrides, [],
		"prologue_encounter.tres must load with weapon_path_overrides == [] — no .tres edit was made in FEAT-004 / US-004"
	)
	assert_eq(
		enc.off_hand_path_overrides, [],
		"prologue_encounter.tres must load with off_hand_path_overrides == [] — no .tres edit was made in FEAT-003 / US-003"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: a populated tiles array of HexTileDataResource entries
# round-trips via ResourceSaver.save()/ResourceLoader.load() with no field loss
# ══════════════════════════════════════════════════════════════════════════════

func test_populated_tiles_array_round_trips_with_no_field_loss() -> void:
	var res := EncounterResource.new()
	res.party_resource_paths = ["res://data/characters/titus.tres"]
	res.enemy_resource_paths = ["res://data/enemies/skeleton.tres"]
	res.party_hex_positions  = [{"q": 0, "r": 0}]
	res.enemy_hex_positions  = [{"q": 1, "r": 0}]
	res.seed = 7

	var tile_a := HexTileDataResource.new()
	tile_a.q = 0
	tile_a.r = 0
	tile_a.passable = true
	tile_a.difficult = false
	tile_a.terrain_type = "floor"

	var tile_b := HexTileDataResource.new()
	tile_b.q = 2
	tile_b.r = -1
	tile_b.passable = false
	tile_b.difficult = true
	tile_b.terrain_type = "rubble"

	res.tiles = [tile_a, tile_b]

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for populated-tiles fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Populated-tiles round-trip fixture must reload from disk")
	if reloaded == null:
		return

	# Prior fields intact
	assert_eq(reloaded.party_resource_paths, ["res://data/characters/titus.tres"])
	assert_eq(reloaded.enemy_resource_paths, ["res://data/enemies/skeleton.tres"])
	assert_eq(reloaded.party_hex_positions, [{"q": 0, "r": 0}])
	assert_eq(reloaded.enemy_hex_positions, [{"q": 1, "r": 0}])
	assert_eq(reloaded.seed, 7)

	# New tiles field intact, with no per-tile field loss
	assert_eq(reloaded.tiles.size(), 2, "tiles array must round-trip with exactly 2 entries")
	if reloaded.tiles.size() == 2:
		var r_tile_a = reloaded.tiles[0]
		var r_tile_b = reloaded.tiles[1]

		assert_is(r_tile_a, HexTileDataResource, "tiles[0] must round-trip as a HexTileDataResource")
		assert_eq(r_tile_a.q, 0, "tiles[0].q must round-trip exactly")
		assert_eq(r_tile_a.r, 0, "tiles[0].r must round-trip exactly")
		assert_eq(r_tile_a.passable, true, "tiles[0].passable must round-trip exactly")
		assert_eq(r_tile_a.difficult, false, "tiles[0].difficult must round-trip exactly")
		assert_eq(r_tile_a.terrain_type, "floor", "tiles[0].terrain_type must round-trip exactly")

		assert_is(r_tile_b, HexTileDataResource, "tiles[1] must round-trip as a HexTileDataResource")
		assert_eq(r_tile_b.q, 2, "tiles[1].q must round-trip exactly")
		assert_eq(r_tile_b.r, -1, "tiles[1].r must round-trip exactly")
		assert_eq(r_tile_b.passable, false, "tiles[1].passable must round-trip exactly")
		assert_eq(r_tile_b.difficult, true, "tiles[1].difficult must round-trip exactly")
		assert_eq(r_tile_b.terrain_type, "rubble", "tiles[1].terrain_type must round-trip exactly")

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-004 / US-004 / FR-004, NFR-005: weapon_path_overrides — additive,
# positionally-parallel-to-enemy_resource_paths field on EncounterResource
# ══════════════════════════════════════════════════════════════════════════════

func test_weapon_path_overrides_round_trips_mixed_empty_and_non_empty_entries() -> void:
	var res := EncounterResource.new()
	res.enemy_resource_paths = [
		"res://data/enemies/skeleton.tres",
		"res://data/enemies/skeleton.tres",
		"res://data/enemies/skeleton.tres",
	]
	res.weapon_path_overrides = [
		"res://data/weapons/arming_sword.tres",
		"",
		"res://data/weapons/dagger.tres",
	]

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for weapon_path_overrides fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "weapon_path_overrides round-trip fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(
		reloaded.weapon_path_overrides,
		[
			"res://data/weapons/arming_sword.tres",
			"",
			"res://data/weapons/dagger.tres",
		],
		"weapon_path_overrides must round-trip with mixed empty-string and non-empty-string entries preserved exactly"
	)

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


func test_all_preexisting_encounter_tres_files_load_without_error() -> void:
	# long_hall.tres is intentionally excluded here because it now carries a
	# non-empty off_hand_path_overrides (slot 1 = small_shield) — see
	# test_long_hall_encounter_has_shielded_skeleton() below.
	var encounter_paths := [
		"res://data/encounters/prologue_encounter.tres",
		"res://data/encounters/batty_guard.tres",
		"res://data/encounters/dripping_cave.tres",
	]
	for path in encounter_paths:
		var enc = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_not_null(enc, "%s must load without error after the weapon_path_overrides schema change (FEAT-004 / US-004)" % path)
		if enc != null:
			assert_true(
				enc.weapon_path_overrides is Array,
				"%s must expose weapon_path_overrides as an Array after the schema change" % path
			)
			assert_true(
				enc.off_hand_path_overrides is Array,
				"%s must expose off_hand_path_overrides as an Array after the FEAT-003 / US-003 schema change" % path
			)
			assert_eq(
				enc.off_hand_path_overrides, [],
				"%s must load with off_hand_path_overrides == [] — no pre-existing .tres file was edited by FEAT-003 / US-003" % path
			)


func test_long_hall_encounter_has_shielded_skeleton() -> void:
	var enc = ResourceLoader.load("res://data/encounters/long_hall.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(enc, "long_hall.tres must load without error")
	if enc == null:
		return
	assert_eq(enc.off_hand_path_overrides.size(), 2,
		"long_hall.tres must have 2 off_hand_path_overrides entries (one per enemy slot)")
	assert_eq(enc.off_hand_path_overrides[0], "",
		"long_hall slot 0 (plain skeleton) must have no off-hand override")
	assert_eq(enc.off_hand_path_overrides[1], "res://data/weapons/small_shield.tres",
		"long_hall slot 1 must carry a small shield override")


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-003 / US-003 / FR-005: off_hand_path_overrides — additive,
# positionally-parallel-to-enemy_resource_paths field on EncounterResource
# (mirrors weapon_path_overrides per ADR-005)
# ══════════════════════════════════════════════════════════════════════════════

func test_off_hand_path_overrides_round_trips_mixed_empty_and_non_empty_entries() -> void:
	var res := EncounterResource.new()
	res.enemy_resource_paths = [
		"res://data/enemies/skeleton.tres",
		"res://data/enemies/skeleton.tres",
		"res://data/enemies/skeleton.tres",
	]
	res.off_hand_path_overrides = [
		"res://data/weapons/small_shield.tres",
		"",
		"res://data/weapons/buckler.tres",
	]

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for off_hand_path_overrides fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "off_hand_path_overrides round-trip fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(
		reloaded.off_hand_path_overrides,
		[
			"res://data/weapons/small_shield.tres",
			"",
			"res://data/weapons/buckler.tres",
		],
		"off_hand_path_overrides must round-trip with mixed empty-string and non-empty-string entries preserved exactly"
	)

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)
