extends GutTest
## tests/unit/data/characters/test_party_resource.gd
##
## GUT unit tests for FEAT-003 (US-005 / FR-005, NFR-002):
## data/characters/party_resource.gd — PartyResource, the scenario-authoritative
## cross-encounter party definition (ADR-002).
##
## Architecture note (ADR-001, ADR-002):
##   PartyResource lives in the DOMAIN layer (data/characters/). It extends
##   Resource (never Node/Control/SceneTree), carries ZERO business logic,
##   and is constructed/serialized purely via Godot's ResourceLoader.
##
## Test criteria covered:
##   1. Default character_resource_paths is an empty array (empty is valid).
##   2. Full round-trip via ResourceSaver.save()/ResourceLoader.load() with
##      no field loss.
##   3. Empty character_resource_paths array round-trips as valid/empty.
##   4. PartyResource referencing real marigold.tres/titus.tres loads
##      without error.
##   5. Static review: no Node/Control/SceneTree imports, no business-logic
##      methods.

const PartyResource = preload("res://data/characters/party_resource.gd")

const ROUND_TRIP_TRES_PATH := "user://test_party_resource_round_trip.tres"

const MARIGOLD_PATH := "res://data/characters/marigold.tres"
const TITUS_PATH := "res://data/characters/titus.tres"


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: default construction
# ══════════════════════════════════════════════════════════════════════════════

func test_default_character_resource_paths_is_empty_array() -> void:
	var res := PartyResource.new()
	assert_eq(
		res.character_resource_paths, [],
		"PartyResource.character_resource_paths must default to an empty array"
	)


func test_character_resource_paths_is_array_typed() -> void:
	var res := PartyResource.new()
	assert_eq(
		typeof(res.character_resource_paths), TYPE_ARRAY,
		"character_resource_paths must be typed as Array"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: full round-trip via ResourceSaver.save()/ResourceLoader.load()
# ══════════════════════════════════════════════════════════════════════════════

func test_round_trip_save_load_preserves_all_fields() -> void:
	var res := PartyResource.new()
	res.character_resource_paths = [TITUS_PATH, MARIGOLD_PATH]

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for round-trip fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Round-trip fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(
		reloaded.character_resource_paths, [TITUS_PATH, MARIGOLD_PATH],
		"character_resource_paths must round-trip exactly; got: %s" % [reloaded.character_resource_paths]
	)

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: empty character_resource_paths array is valid
# ══════════════════════════════════════════════════════════════════════════════

func test_empty_character_resource_paths_array_is_valid_and_round_trips() -> void:
	var res := PartyResource.new()
	res.character_resource_paths = []

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for empty-array fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Empty-array fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(
		reloaded.character_resource_paths, [],
		"An empty character_resource_paths array must remain empty (and valid) after round-trip"
	)

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: PartyResource referencing real marigold.tres/titus.tres loads
# ══════════════════════════════════════════════════════════════════════════════

func test_party_resource_referencing_real_marigold_and_titus_loads_without_error() -> void:
	assert_true(
		ResourceLoader.exists(MARIGOLD_PATH),
		"Fixture data/characters/marigold.tres must exist for this test"
	)
	assert_true(
		ResourceLoader.exists(TITUS_PATH),
		"Fixture data/characters/titus.tres must exist for this test"
	)

	var res := PartyResource.new()
	res.character_resource_paths = [TITUS_PATH, MARIGOLD_PATH]

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for real-fixture party")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Real-fixture party must reload from disk without error")
	if reloaded == null:
		return

	assert_eq(reloaded.character_resource_paths.size(), 2, "Real-fixture party must retain both entries")

	for path in reloaded.character_resource_paths:
		var character = ResourceLoader.load(path)
		assert_not_null(character, "Referenced character resource must load without error: %s" % path)

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5: static review — no business-logic methods, no scene-tree imports
# ══════════════════════════════════════════════════════════════════════════════

func test_party_resource_gd_has_no_business_logic_methods() -> void:
	var file := FileAccess.open("res://data/characters/party_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/characters/party_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("func "),
		"party_resource.gd must contain no functions — pure @export data (ADR-002)"
	)


func test_party_resource_gd_extends_resource_not_scene_tree_types() -> void:
	var file := FileAccess.open("res://data/characters/party_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/characters/party_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("extends Resource"),
		"party_resource.gd must extend Resource"
	)
	for forbidden in ["extends Node", "extends Control", "extends SceneTree", "extends CanvasItem"]:
		assert_false(
			content.contains(forbidden),
			"party_resource.gd must not contain '%s' (DOMAIN layer purity, ADR-001)" % forbidden
		)
