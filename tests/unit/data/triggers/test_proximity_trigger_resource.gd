extends GutTest
## tests/unit/data/triggers/test_proximity_trigger_resource.gd
##
## GUT unit tests for FEAT-002 (US-003 / FR-003, NFR-002, NFR-003):
## data/triggers/proximity_trigger_resource.gd — ProximityTriggerResource,
## a TriggerResource subclass (ADR-003) describing a set of hexes that
## fire the trigger when occupied by the party.
##
## Test criteria covered:
##   1. Default trigger_type == 'PROXIMITY'; trigger_hexes defaults to [].
##   2. Full round-trip via ResourceSaver.save()/ResourceLoader.load() with
##      no field loss (including inherited trigger_type).
##   3. Static review: no trigger-evaluation/firing logic and no
##      Node/Control/SceneTree imports.

const ProximityTriggerResource = preload("res://data/triggers/proximity_trigger_resource.gd")
const TriggerResource = preload("res://data/triggers/trigger_resource.gd")

const ROUND_TRIP_TRES_PATH := "user://test_proximity_trigger_resource_round_trip.tres"


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: default field values + subclass relationship
# ══════════════════════════════════════════════════════════════════════════════

func test_default_trigger_type_is_proximity() -> void:
	var res := ProximityTriggerResource.new()
	assert_eq(
		res.trigger_type, "PROXIMITY",
		"ProximityTriggerResource.trigger_type must default to 'PROXIMITY'"
	)


func test_default_trigger_hexes_is_empty_array() -> void:
	var res := ProximityTriggerResource.new()
	assert_eq(typeof(res.trigger_hexes), TYPE_ARRAY, "trigger_hexes must be typed as Array")
	assert_eq(res.trigger_hexes.size(), 0, "trigger_hexes must default to an empty Array")


func test_proximity_trigger_resource_is_a_trigger_resource() -> void:
	var res := ProximityTriggerResource.new()
	assert_true(
		res is TriggerResource,
		"ProximityTriggerResource must inherit from TriggerResource (ADR-003 closed hierarchy)"
	)


func test_trigger_hexes_holds_axial_coordinate_dictionaries() -> void:
	var res := ProximityTriggerResource.new()
	res.trigger_hexes = [{"q": 2, "r": -1}, {"q": 0, "r": 0}]
	assert_eq(res.trigger_hexes.size(), 2)
	assert_eq(res.trigger_hexes[0]["q"], 2)
	assert_eq(res.trigger_hexes[0]["r"], -1)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: full round-trip via ResourceSaver.save()/ResourceLoader.load()
# ══════════════════════════════════════════════════════════════════════════════

func test_round_trip_save_load_preserves_all_fields() -> void:
	var res := ProximityTriggerResource.new()
	res.trigger_hexes = [{"q": 1, "r": 3}]

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for round-trip fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Round-trip fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.trigger_type, "PROXIMITY", "trigger_type must round-trip exactly")
	assert_eq(reloaded.trigger_hexes.size(), 1, "trigger_hexes must round-trip exactly")
	assert_eq(reloaded.trigger_hexes[0]["q"], 1)
	assert_eq(reloaded.trigger_hexes[0]["r"], 3)

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


func test_round_trip_preserves_default_values_too() -> void:
	var res := ProximityTriggerResource.new()

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for default-value fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Default-value fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.trigger_type, "PROXIMITY")
	assert_eq(reloaded.trigger_hexes.size(), 0)

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: static review — no firing/evaluation logic, no scene-tree imports
# ══════════════════════════════════════════════════════════════════════════════

func test_proximity_trigger_resource_gd_has_no_business_logic_methods() -> void:
	# The ONLY function permitted in a subclass is a trivial _init() that
	# assigns a literal default to the inherited trigger_type field (Godot 4
	# forbids redeclaring an @export member already declared on the parent
	# class). No other function — and no trigger-evaluation/firing logic —
	# may exist here (ADR-003 / RISK-001, RISK-008).
	var file := FileAccess.open("res://data/triggers/proximity_trigger_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/triggers/proximity_trigger_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	var func_count: int = content.count("func ")
	assert_eq(
		func_count, 1,
		"proximity_trigger_resource.gd must contain exactly one function " +
		"(the trivial _init() default override) — no other business logic"
	)
	assert_true(
		content.contains("func _init("),
		"the sole function in proximity_trigger_resource.gd must be _init()"
	)
	for forbidden in ["func _process", "func _physics_process", "func _ready", "\tif ", "\twhile ", "\tfor ", "\tmatch "]:
		assert_false(
			content.contains(forbidden),
			"proximity_trigger_resource.gd must not contain '%s' — no evaluation/firing logic" % forbidden
		)


func test_proximity_trigger_resource_gd_extends_trigger_resource_not_scene_tree_types() -> void:
	var file := FileAccess.open("res://data/triggers/proximity_trigger_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/triggers/proximity_trigger_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("extends TriggerResource"),
		"proximity_trigger_resource.gd must extend TriggerResource"
	)
	for forbidden in ["extends Node", "extends Control", "extends SceneTree", "extends CanvasItem"]:
		assert_false(
			content.contains(forbidden),
			(
				"proximity_trigger_resource.gd must not contain '%s' (DOMAIN layer purity, ADR-001)"
				% forbidden
			)
		)
