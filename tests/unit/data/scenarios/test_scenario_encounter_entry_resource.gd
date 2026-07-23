extends GutTest
## tests/unit/data/scenarios/test_scenario_encounter_entry_resource.gd
##
## GUT unit tests for FEAT-005 (US-004 / FR-004, NFR-002):
## data/scenarios/scenario_encounter_entry_resource.gd —
## ScenarioEncounterEntryResource, the join entity linking encounter_id,
## EncounterResource, and an optional TriggerResource between a
## ScenarioResource and its EncounterResource(s).
##
## Architecture note (ADR-001, ADR-003):
##   ScenarioEncounterEntryResource lives in the DOMAIN layer
##   (data/scenarios/). It extends Resource (never Node/Control/SceneTree),
##   carries ZERO business logic (no trigger-evaluation/encounter-loading
##   logic), and is constructed/serialized purely via Godot's ResourceLoader.
##
## Test criteria covered:
##   1. encounter_id/encounter/trigger round-trip via ResourceSaver/ResourceLoader.
##   2. Null trigger accepted without error or crash (round-trips as null).
##   3. encounter_id preserved exactly as authored (including edge-case strings).
##   4. Static review: no Node/Control/SceneTree imports, no business-logic methods.

const ScenarioEncounterEntryResource = preload("res://data/scenarios/scenario_encounter_entry_resource.gd")
const EncounterResource = preload("res://data/encounters/encounter_resource.gd")
const ProximityTriggerResource = preload("res://data/triggers/proximity_trigger_resource.gd")

const ROUND_TRIP_TRES_PATH := "user://test_scenario_encounter_entry_resource_round_trip.tres"
const PROLOGUE_ENCOUNTER_PATH := "res://data/encounters/prologue_encounter.tres"


# ══════════════════════════════════════════════════════════════════════════════
# Criterion: default construction
# ══════════════════════════════════════════════════════════════════════════════

func test_default_construction_has_empty_id_null_encounter_and_null_trigger() -> void:
	var entry := ScenarioEncounterEntryResource.new()
	assert_eq(entry.encounter_id, "", "encounter_id must default to an empty string")
	assert_null(entry.encounter, "encounter must default to null")
	assert_null(entry.trigger, "trigger must default to null")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: encounter_id/encounter/trigger round-trip via ResourceLoader
# ══════════════════════════════════════════════════════════════════════════════

func test_round_trip_with_trigger_preserves_all_fields() -> void:
	var entry := ScenarioEncounterEntryResource.new()
	entry.encounter_id = "prologue_fight"
	entry.encounter = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH)

	var trig := ProximityTriggerResource.new()
	trig.trigger_hexes = [{"q": 2, "r": -1}]
	entry.trigger = trig

	var save_err := ResourceSaver.save(entry, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for round-trip fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Round-trip fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(
		reloaded.encounter_id, "prologue_fight",
		"encounter_id must round-trip exactly; got: %s" % reloaded.encounter_id
	)

	assert_not_null(reloaded.encounter, "encounter must round-trip non-null")
	assert_is(reloaded.encounter, EncounterResource, "encounter must round-trip as an EncounterResource")
	if reloaded.encounter != null:
		assert_eq(
			reloaded.encounter.party_resource_paths,
			["res://data/characters/titus.tres", "res://data/characters/marigold.tres"],
			"round-tripped encounter must retain its own fields"
		)

	assert_not_null(reloaded.trigger, "trigger must round-trip non-null")
	assert_is(reloaded.trigger, ProximityTriggerResource, "trigger must round-trip as a ProximityTriggerResource")
	if reloaded.trigger != null:
		assert_eq(reloaded.trigger.trigger_type, "PROXIMITY", "trigger subtype fields must round-trip")
		assert_eq(reloaded.trigger.trigger_hexes, [{"q": 2, "r": -1}], "trigger subtype fields must round-trip")

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: null trigger accepted without error or crash
# ══════════════════════════════════════════════════════════════════════════════

func test_null_trigger_accepted_without_error_and_round_trips_as_null() -> void:
	var entry := ScenarioEncounterEntryResource.new()
	entry.encounter_id = "auto_start_fight"
	entry.encounter = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH)
	entry.trigger = null

	var save_err := ResourceSaver.save(entry, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed with a null trigger")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Null-trigger fixture must reload from disk without error")
	if reloaded == null:
		return

	assert_null(reloaded.trigger, "trigger must round-trip as null (no crash, no error)")
	assert_eq(reloaded.encounter_id, "auto_start_fight", "encounter_id must be unaffected by a null trigger")

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: encounter_id preserved exactly as authored
# ══════════════════════════════════════════════════════════════════════════════

func test_encounter_id_preserved_exactly_as_authored() -> void:
	var raw_ids := ["prologue_fight", "Act1_Ambush-02", "  padded_id  ", ""]

	for raw_id in raw_ids:
		var entry := ScenarioEncounterEntryResource.new()
		entry.encounter_id = raw_id

		var save_err := ResourceSaver.save(entry, ROUND_TRIP_TRES_PATH)
		assert_eq(save_err, OK, "ResourceSaver.save() must succeed for encounter_id: '%s'" % raw_id)

		var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_not_null(reloaded, "Fixture must reload from disk for encounter_id: '%s'" % raw_id)
		if reloaded != null:
			assert_eq(
				reloaded.encounter_id, raw_id,
				"encounter_id must be preserved exactly as authored, with no trimming/normalization"
			)

		var cleanup_dir := DirAccess.open("user://")
		if cleanup_dir != null:
			cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: static review — no business-logic methods, no scene-tree imports
# ══════════════════════════════════════════════════════════════════════════════

func test_scenario_encounter_entry_resource_gd_has_no_business_logic_methods() -> void:
	var file := FileAccess.open("res://data/scenarios/scenario_encounter_entry_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/scenarios/scenario_encounter_entry_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("func "),
		"scenario_encounter_entry_resource.gd must contain no functions — pure @export data"
	)


func test_scenario_encounter_entry_resource_gd_extends_resource_not_scene_tree_types() -> void:
	var file := FileAccess.open("res://data/scenarios/scenario_encounter_entry_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/scenarios/scenario_encounter_entry_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("extends Resource"),
		"scenario_encounter_entry_resource.gd must extend Resource"
	)
	for forbidden in ["extends Node", "extends Control", "extends SceneTree", "extends CanvasItem"]:
		assert_false(
			content.contains(forbidden),
			"scenario_encounter_entry_resource.gd must not contain '%s' (DOMAIN layer purity, ADR-001)" % forbidden
		)
