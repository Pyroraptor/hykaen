extends GutTest
## tests/unit/data/triggers/test_trigger_resource.gd
##
## GUT unit tests for FEAT-002 (US-003 / FR-003, NFR-002, NFR-003):
## data/triggers/trigger_resource.gd — TriggerResource, the base schema for
## the closed polymorphic trigger hierarchy (ADR-003).
##
## Architecture note (ADR-001, ADR-003):
##   TriggerResource lives in the DOMAIN layer (data/triggers/). It extends
##   Resource (never Node/Control/SceneTree), carries ZERO business logic
##   (no evaluation/firing logic — RISK-001 / RISK-008 mitigation), and is
##   constructed/serialized purely via Godot's ResourceLoader.
##
## Test criteria covered:
##   1. Default trigger_type == 'AUTO'.
##   2. Full round-trip via ResourceSaver.save()/ResourceLoader.load() with
##      no field loss.
##   3. Static review: no trigger-evaluation/firing logic (no methods
##      beyond trivial defaults) and no Node/Control/SceneTree imports.

const TriggerResource = preload("res://data/triggers/trigger_resource.gd")

const ROUND_TRIP_TRES_PATH := "user://test_trigger_resource_round_trip.tres"


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: default trigger_type
# ══════════════════════════════════════════════════════════════════════════════

func test_default_trigger_type_is_auto() -> void:
	var res := TriggerResource.new()
	assert_eq(res.trigger_type, "AUTO", "TriggerResource.trigger_type must default to 'AUTO'")


func test_trigger_type_is_string_typed() -> void:
	var res := TriggerResource.new()
	assert_eq(typeof(res.trigger_type), TYPE_STRING, "trigger_type must be typed as String")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: full round-trip via ResourceSaver.save()/ResourceLoader.load()
# ══════════════════════════════════════════════════════════════════════════════

func test_round_trip_save_load_preserves_all_fields() -> void:
	var res := TriggerResource.new()
	res.trigger_type = "CUSTOM"

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for round-trip fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Round-trip fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(
		reloaded.trigger_type, "CUSTOM",
		"trigger_type must round-trip exactly; got: %s" % reloaded.trigger_type
	)

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


func test_round_trip_preserves_default_value_too() -> void:
	var res := TriggerResource.new()

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for default-value fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Default-value fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.trigger_type, "AUTO")

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: static review — no firing/evaluation logic, no scene-tree imports
# ══════════════════════════════════════════════════════════════════════════════

func test_trigger_resource_gd_has_no_business_logic_methods() -> void:
	var file := FileAccess.open("res://data/triggers/trigger_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/triggers/trigger_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("func "),
		"trigger_resource.gd must contain no functions — pure @export data (ADR-003), " +
		"no trigger-evaluation/firing logic (RISK-001, RISK-008)"
	)


func test_trigger_resource_gd_extends_resource_not_scene_tree_types() -> void:
	var file := FileAccess.open("res://data/triggers/trigger_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/triggers/trigger_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("extends Resource"),
		"trigger_resource.gd must extend Resource"
	)
	for forbidden in ["extends Node", "extends Control", "extends SceneTree", "extends CanvasItem"]:
		assert_false(
			content.contains(forbidden),
			"trigger_resource.gd must not contain '%s' (DOMAIN layer purity, ADR-001)" % forbidden
		)
