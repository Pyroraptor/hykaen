extends GutTest
## tests/unit/data/scenarios/test_scenario_resource.gd
##
## GUT unit tests for FEAT-006 (US-006 / FR-006, NFR-002):
## data/scenarios/scenario_resource.gd — ScenarioResource, the top-level
## locale container composing scenario_id, display_name, a
## scenario-authoritative PartyResource (ADR-002), and an ordered
## Array[ScenarioEncounterEntryResource] (FEAT-005) — completing the domain
## data graph consumed by the future LoadScenarioEncounterUseCase.
##
## Architecture note (ADR-001):
##   ScenarioResource lives in the DOMAIN layer (data/scenarios/). It
##   extends Resource (never Node/Control/SceneTree), carries ZERO business
##   logic (no loading/lookup/trigger-evaluation logic), and is
##   constructed/serialized purely via Godot's ResourceLoader.
##
## Test criteria covered:
##   1. scenario_id/display_name round-trip via ResourceLoader.
##   2. party sub-resource loads correctly as PartyResource.
##   3. encounter_entries with one entry loads correctly.
##   4. Empty encounter_entries is valid and does not crash the loader.
##   5. Static review: no Node/Control/SceneTree imports, no business-logic
##      methods.

const ScenarioResource = preload("res://data/scenarios/scenario_resource.gd")
const PartyResource = preload("res://data/characters/party_resource.gd")
const ScenarioEncounterEntryResource = preload("res://data/scenarios/scenario_encounter_entry_resource.gd")
const EncounterResource = preload("res://data/encounters/encounter_resource.gd")

const ROUND_TRIP_TRES_PATH := "user://test_scenario_resource_round_trip.tres"

const MARIGOLD_PATH := "res://data/characters/marigold.tres"
const TITUS_PATH := "res://data/characters/titus.tres"
const PROLOGUE_ENCOUNTER_PATH := "res://data/encounters/prologue_encounter.tres"


func _cleanup_round_trip_fixture() -> void:
	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion: default construction
# ══════════════════════════════════════════════════════════════════════════════

func test_default_construction_has_empty_ids_null_party_and_empty_entries() -> void:
	var scenario := ScenarioResource.new()
	assert_eq(scenario.scenario_id, "", "scenario_id must default to an empty string")
	assert_eq(scenario.display_name, "", "display_name must default to an empty string")
	assert_null(scenario.party, "party must default to null")
	assert_eq(scenario.encounter_entries, [], "encounter_entries must default to an empty array")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: scenario_id/display_name round-trip via ResourceLoader
# ══════════════════════════════════════════════════════════════════════════════

func test_scenario_id_and_display_name_round_trip() -> void:
	var scenario := ScenarioResource.new()
	scenario.scenario_id = "prologue"
	scenario.display_name = "The Hollow Prologue"

	var save_err := ResourceSaver.save(scenario, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for round-trip fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Round-trip fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(
		reloaded.scenario_id, "prologue",
		"scenario_id must round-trip exactly; got: %s" % reloaded.scenario_id
	)
	assert_eq(
		reloaded.display_name, "The Hollow Prologue",
		"display_name must round-trip exactly; got: %s" % reloaded.display_name
	)

	_cleanup_round_trip_fixture()


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: party sub-resource loads correctly as PartyResource
# ══════════════════════════════════════════════════════════════════════════════

func test_party_sub_resource_round_trips_as_party_resource() -> void:
	var scenario := ScenarioResource.new()
	scenario.scenario_id = "prologue"

	var party := PartyResource.new()
	party.character_resource_paths = [TITUS_PATH, MARIGOLD_PATH]
	scenario.party = party

	var save_err := ResourceSaver.save(scenario, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed when party is set")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Fixture with a party sub-resource must reload from disk")
	if reloaded == null:
		return

	assert_not_null(reloaded.party, "party must round-trip non-null")
	assert_is(reloaded.party, PartyResource, "party must round-trip as a PartyResource")
	if reloaded.party != null:
		assert_eq(
			reloaded.party.character_resource_paths, [TITUS_PATH, MARIGOLD_PATH],
			"party's own fields must be preserved across the round-trip"
		)

	_cleanup_round_trip_fixture()


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: encounter_entries with one entry loads correctly
# ══════════════════════════════════════════════════════════════════════════════

func test_encounter_entries_with_one_entry_loads_correctly() -> void:
	var scenario := ScenarioResource.new()
	scenario.scenario_id = "prologue"

	var entry := ScenarioEncounterEntryResource.new()
	entry.encounter_id = "prologue_fight"
	entry.encounter = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH)
	scenario.encounter_entries = [entry]

	var save_err := ResourceSaver.save(scenario, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed with one encounter entry")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Fixture with one encounter entry must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.encounter_entries.size(), 1, "encounter_entries must retain exactly one entry")
	if reloaded.encounter_entries.size() == 1:
		var reloaded_entry = reloaded.encounter_entries[0]
		assert_is(
			reloaded_entry, ScenarioEncounterEntryResource,
			"the single entry must round-trip as a ScenarioEncounterEntryResource"
		)
		assert_eq(reloaded_entry.encounter_id, "prologue_fight", "the entry's encounter_id must be preserved")
		assert_not_null(reloaded_entry.encounter, "the entry's encounter must round-trip non-null")
		assert_is(reloaded_entry.encounter, EncounterResource, "the entry's encounter must round-trip as an EncounterResource")

	_cleanup_round_trip_fixture()


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: empty encounter_entries is valid and does not crash the loader
# ══════════════════════════════════════════════════════════════════════════════

func test_empty_encounter_entries_is_valid_and_round_trips_without_crashing() -> void:
	var scenario := ScenarioResource.new()
	scenario.scenario_id = "empty_scenario"
	scenario.display_name = "Under Construction"
	scenario.encounter_entries = []

	var save_err := ResourceSaver.save(scenario, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed with empty encounter_entries")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Fixture with empty encounter_entries must reload from disk without error")
	if reloaded == null:
		return

	assert_eq(
		reloaded.encounter_entries, [],
		"An empty encounter_entries array must remain empty (and valid) after round-trip"
	)
	assert_eq(reloaded.scenario_id, "empty_scenario", "scenario_id must be unaffected by empty encounter_entries")

	_cleanup_round_trip_fixture()


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5: static review — no business-logic methods, no scene-tree imports
# ══════════════════════════════════════════════════════════════════════════════

func test_scenario_resource_gd_has_no_business_logic_methods() -> void:
	var file := FileAccess.open("res://data/scenarios/scenario_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/scenarios/scenario_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("func "),
		"scenario_resource.gd must contain no functions — pure @export data"
	)


func test_scenario_resource_gd_extends_resource_not_scene_tree_types() -> void:
	var file := FileAccess.open("res://data/scenarios/scenario_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/scenarios/scenario_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("extends Resource"),
		"scenario_resource.gd must extend Resource"
	)
	for forbidden in ["extends Node", "extends Control", "extends SceneTree", "extends CanvasItem"]:
		assert_false(
			content.contains(forbidden),
			"scenario_resource.gd must not contain '%s' (DOMAIN layer purity, ADR-001)" % forbidden
		)
