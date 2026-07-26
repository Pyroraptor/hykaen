extends GutTest
## tests/unit/test_game_state_data.gd
##
## GUT unit tests for FEAT-001 (US-001 / FR-001):
## data/game_state/game_state_data.gd — GameStateData, the innermost
## DOMAIN-layer value container all later layers (NewGameFactory,
## CurrentGameState, MainScene, TitleScreen) build on.
##
## Architecture note (Clean Architecture):
##   GameStateData lives in the DOMAIN layer (data/game_state/). It extends
##   Resource (Godot's serialisable-struct mechanism only, never as a
##   behavioural/engine object) — never Node, Control, CanvasItem, or
##   SceneTree — and carries ZERO business logic beyond field defaults.
##
## Test criteria covered (per FEAT-001 spec):
##   1. GameStateData.new() yields scenario_path == "" and
##      party_hex_positions / completed_encounter_ids / combatant_snapshots
##      all == [] (never null) — safe-empty-defaults guarantee (FR-001).
##   2. Round-trip test: set all fields including nested dictionaries, read
##      them back, assert exact equality with no data loss.
##   3. Field-shape test: party_hex_positions entries expose
##      combatant_id/q/r keys and combatant_snapshots entries expose
##      combatant_id/hp_current/stamina/conditions keys.

const GameStateData = preload("res://data/game_state/game_state_data.gd")

const ROUND_TRIP_TRES_PATH := "user://test_game_state_data_round_trip.tres"


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: safe empty defaults — never null
# ══════════════════════════════════════════════════════════════════════════════

func test_default_construction_yields_empty_scenario_path() -> void:
	var state := GameStateData.new()
	assert_eq(state.scenario_path, "", "GameStateData.scenario_path must default to \"\"")


func test_default_construction_yields_empty_never_null_arrays() -> void:
	var state := GameStateData.new()

	assert_not_null(
		state.party_hex_positions, "party_hex_positions must never be null"
	)
	assert_true(
		state.party_hex_positions.is_empty(),
		"party_hex_positions must default to an empty array"
	)

	assert_not_null(
		state.completed_encounter_ids, "completed_encounter_ids must never be null"
	)
	assert_true(
		state.completed_encounter_ids.is_empty(),
		"completed_encounter_ids must default to an empty array"
	)

	assert_not_null(
		state.combatant_snapshots, "combatant_snapshots must never be null"
	)
	assert_true(
		state.combatant_snapshots.is_empty(),
		"combatant_snapshots must default to an empty array"
	)


func test_default_arrays_are_correctly_typed() -> void:
	var state := GameStateData.new()
	assert_eq(typeof(state.scenario_path), TYPE_STRING, "scenario_path must be typed as String")
	assert_eq(
		typeof(state.party_hex_positions), TYPE_ARRAY,
		"party_hex_positions must be typed as Array"
	)
	assert_eq(
		typeof(state.completed_encounter_ids), TYPE_ARRAY,
		"completed_encounter_ids must be typed as Array"
	)
	assert_eq(
		typeof(state.combatant_snapshots), TYPE_ARRAY,
		"combatant_snapshots must be typed as Array"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: round-trip with nested dictionaries — no data loss
# ══════════════════════════════════════════════════════════════════════════════

func test_round_trip_save_load_preserves_all_fields_with_no_data_loss() -> void:
	var state := GameStateData.new()
	state.scenario_path = "res://data/scenarios/prologue_scenario.tres"
	state.party_hex_positions = [
		{"combatant_id": "hero_1", "q": 2, "r": -1},
		{"combatant_id": "hero_2", "q": 3, "r": -1},
	]
	state.completed_encounter_ids = ["prologue_ambush"]
	state.combatant_snapshots = [
		{
			"combatant_id": "hero_1",
			"hp_current": 14,
			"stamina": 3,
			"conditions": [],
		},
		{
			"combatant_id": "hero_2",
			"hp_current": 8,
			"stamina": 1,
			"conditions": ["prone", "bleeding"],
		},
	]

	var save_err := ResourceSaver.save(state, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for round-trip fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Round-trip fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(
		reloaded.scenario_path, "res://data/scenarios/prologue_scenario.tres",
		"scenario_path must round-trip exactly"
	)
	assert_eq(
		reloaded.party_hex_positions, state.party_hex_positions,
		"party_hex_positions must round-trip exactly, including nested dictionaries"
	)
	assert_eq(
		reloaded.completed_encounter_ids, state.completed_encounter_ids,
		"completed_encounter_ids must round-trip exactly"
	)
	assert_eq(
		reloaded.combatant_snapshots, state.combatant_snapshots,
		"combatant_snapshots must round-trip exactly, including nested dictionaries/arrays"
	)

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


func test_round_trip_preserves_default_empty_values_too() -> void:
	var state := GameStateData.new()

	var save_err := ResourceSaver.save(state, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for default-value fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Default-value fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.scenario_path, "")
	assert_true(reloaded.party_hex_positions.is_empty())
	assert_true(reloaded.completed_encounter_ids.is_empty())
	assert_true(reloaded.combatant_snapshots.is_empty())

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: field-shape assertions on nested dictionary entries
# ══════════════════════════════════════════════════════════════════════════════

func test_party_hex_position_entries_expose_expected_keys() -> void:
	var state := GameStateData.new()
	state.party_hex_positions = [{"combatant_id": "hero_1", "q": 2, "r": -1}]

	var entry: Dictionary = state.party_hex_positions[0]
	assert_true(entry.has("combatant_id"), "party_hex_positions entry must expose combatant_id")
	assert_true(entry.has("q"), "party_hex_positions entry must expose q")
	assert_true(entry.has("r"), "party_hex_positions entry must expose r")


func test_combatant_snapshot_entries_expose_expected_keys() -> void:
	var state := GameStateData.new()
	state.combatant_snapshots = [
		{
			"combatant_id": "hero_1",
			"hp_current": 14,
			"stamina": 3,
			"conditions": ["prone"],
		}
	]

	var entry: Dictionary = state.combatant_snapshots[0]
	assert_true(
		entry.has("combatant_id"), "combatant_snapshots entry must expose combatant_id"
	)
	assert_true(entry.has("hp_current"), "combatant_snapshots entry must expose hp_current")
	assert_true(entry.has("stamina"), "combatant_snapshots entry must expose stamina")
	assert_true(entry.has("conditions"), "combatant_snapshots entry must expose conditions")


# ══════════════════════════════════════════════════════════════════════════════
# Bonus: static review — pure data container, no business logic, domain-pure
# ══════════════════════════════════════════════════════════════════════════════

func test_game_state_data_gd_has_no_business_logic_methods() -> void:
	var file := FileAccess.open("res://data/game_state/game_state_data.gd", FileAccess.READ)
	assert_not_null(file, "data/game_state/game_state_data.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("func "),
		"game_state_data.gd must contain no functions — pure @export data (FR-001)"
	)


func test_game_state_data_gd_extends_resource_not_scene_tree_types() -> void:
	var file := FileAccess.open("res://data/game_state/game_state_data.gd", FileAccess.READ)
	assert_not_null(file, "data/game_state/game_state_data.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("extends Resource"),
		"game_state_data.gd must extend Resource"
	)
	for forbidden in ["extends Node", "extends Control", "extends SceneTree", "extends CanvasItem"]:
		assert_false(
			content.contains(forbidden),
			"game_state_data.gd must not contain '%s' (DOMAIN layer purity)" % forbidden
		)
