extends GutTest
## tests/unit/test_title_screen_buttons.gd — FEAT-008 (US-006; FR-006,
## NFR-006; ADR-002).
##
## Proves scenes/TitleScreen.tscn + presentation/title_screen.gd's three
## button contracts:
##
##   1. New Game — NewGameFactory.create_prologue_state() -> assigned onto
##      CurrentGameState.data -> transition requested to MainScene.tscn; the
##      resulting CurrentGameState.data boots MainScene.tscn cleanly (no
##      push_error(), and — per MainScene.gd's own _resolve_boot_scenario_path()
##      contract — the FR-004 "CurrentGameState was uninitialized" guard
##      warning only ever fires when data.scenario_path == "", so asserting
##      scenario_path is non-empty BEFORE boot is this feature's own direct,
##      deterministic proof that guard branch is never taken; mirrors
##      tests/boot/test_main_scene_party_position_seeding.gd's established
##      "assert_push_error_count(0) after a real boot" convention for the
##      accompanying regression proof).
##   2. Continue — disabled when CurrentGameState.has_save(0) is false,
##      enabled once a slot 0 save exists.
##   3. Continue press with a valid save calls load_from_slot(0) and
##      transitions; a simulated load_from_slot(0) failure (the save file
##      vanishing between the enable-check and the press, i.e. a race
##      condition) logs a push_warning() (proven via source-inspection —
##      mirrors tests/boot/test_main_scene_party_position_seeding.gd's own
##      documented rationale: GUT's assert_push_warning_count() relies on a
##      Godot 4.4+ API that is a no-op on this project's pinned Godot 4.3
##      engine) and blocks the transition (fail-closed).
##   4. Dev: Pick Scenario is present/functional under a simulated
##      debug-build context (debug_build_override) and absent/disabled when
##      OS.is_debug_build() is simulated false.
##   5. Dev: Pick Scenario enumerates res://data/scenarios/*.tres via
##      DirAccess; an empty/missing directory shows a disabled placeholder
##      row without crashing.

const TitleScreenScript = preload("res://presentation/title_screen.gd")
const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")

const TITLE_SCREEN_PATH: String = "res://scenes/TitleScreen.tscn"
const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const PROLOGUE_SCENARIO_PATH: String = "res://data/scenarios/prologue_scenario.tres"
const DRIPPING_CAVE_SCENARIO_PATH: String = "res://data/scenarios/dripping_cave_scenario.tres"

const SAVES_DIR: String = "user://saves"
const SLOT_0_PATH: String = "user://saves/slot_0.json"

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_main_scene_party_position_seeding.gd's
## identically-named/valued constant).
const PROLOGUE_SEED: int = 42


# ══════════════════════════════════════════════════════════════════════════
# Fixture isolation
# ══════════════════════════════════════════════════════════════════════════

func _cleanup_fixtures() -> void:
	CurrentGameState.data = GameStateDataClass.new()
	if DirAccess.dir_exists_absolute(SAVES_DIR):
		var dir := DirAccess.open(SAVES_DIR)
		if dir != null:
			for entry_name in ["slot_0.json", "slot_0.json.tmp"]:
				if dir.file_exists(entry_name):
					dir.remove(entry_name)


func before_each() -> void:
	_cleanup_fixtures()


func after_each() -> void:
	_cleanup_fixtures()


func _instantiate_title_screen():
	var packed: PackedScene = ResourceLoader.load(TITLE_SCREEN_PATH)
	assert_not_null(packed, "TitleScreen.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	add_child_autofree(instance)
	return instance


func _read_title_screen_source() -> String:
	var file := FileAccess.open("res://presentation/title_screen.gd", FileAccess.READ)
	assert_not_null(file, "presentation/title_screen.gd must be readable")
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — New Game
# ══════════════════════════════════════════════════════════════════════════

func test_new_game_seeds_current_game_state_and_requests_transition_to_main_scene() -> void:
	var instance = _instantiate_title_screen()
	var captured_paths: Array = []
	instance.transition_override = func(path): captured_paths.append(path)

	instance.press_new_game()

	assert_eq(
		captured_paths, [MAIN_SCENE_PATH],
		"New Game must request exactly one transition, to MainScene.tscn"
	)
	assert_eq(
		CurrentGameState.data.scenario_path, NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
		"New Game must seed CurrentGameState.data via NewGameFactory.create_prologue_state()"
	)
	assert_false(
		CurrentGameState.data.party_hex_positions.is_empty(),
		"New Game's seeded state must carry non-empty party_hex_positions from NewGameFactory"
	)


func test_new_game_seeded_data_boots_main_scene_with_no_fr004_guard_warning_and_no_push_error() -> void:
	var instance = _instantiate_title_screen()
	instance.transition_override = func(_path): pass

	instance.press_new_game()

	# MainScene._resolve_boot_scenario_path()'s FR-004 guard only ever fires
	# when CurrentGameState.data.scenario_path == "" -- asserting it is
	# non-empty here is this feature's own direct, deterministic proof the
	# guard branch can never trigger for New Game's own seeded data.
	assert_false(
		CurrentGameState.data.scenario_path.is_empty(),
		"New Game's seeded scenario_path must be non-empty so MainScene's FR-004 uninitialized-state guard never fires"
	)

	var main_packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(main_packed, "MainScene.tscn must load as a PackedScene")
	var main_instance = main_packed.instantiate()
	main_instance.seed_override = PROLOGUE_SEED
	add_child_autofree(main_instance)
	await get_tree().process_frame

	assert_push_error_count(0, "booting MainScene from TitleScreen's New Game seeded data must not log any push_error()")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — Continue enabled/disabled gating
# ══════════════════════════════════════════════════════════════════════════

func test_continue_is_disabled_when_no_save_exists() -> void:
	assert_false(CurrentGameState.has_save(0), "fixture precondition: no slot 0 save must exist")

	var instance = _instantiate_title_screen()

	assert_false(instance.is_continue_enabled(), "Continue must be disabled when has_save(0) is false")


func test_continue_is_enabled_once_a_save_exists() -> void:
	CurrentGameState.data = NewGameFactoryClass.create_prologue_state()
	assert_true(CurrentGameState.save_to_slot(0), "fixture setup: save_to_slot(0) must succeed")
	assert_true(CurrentGameState.has_save(0), "fixture precondition: a slot 0 save must now exist")

	var instance = _instantiate_title_screen()

	assert_true(instance.is_continue_enabled(), "Continue must be enabled once has_save(0) is true")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — Continue press: success loads + transitions; a race-
# condition load failure blocks the transition (fail-closed).
# ══════════════════════════════════════════════════════════════════════════

func test_continue_press_with_valid_save_loads_slot_0_and_transitions() -> void:
	CurrentGameState.data = NewGameFactoryClass.create_state_for_scenario(DRIPPING_CAVE_SCENARIO_PATH)
	assert_true(CurrentGameState.save_to_slot(0), "fixture setup: save_to_slot(0) must succeed")

	# Wipe in-memory state so a successful load is unambiguously the source
	# of the restored scenario_path.
	CurrentGameState.data = GameStateDataClass.new()

	var instance = _instantiate_title_screen()
	assert_true(instance.is_continue_enabled(), "fixture precondition: Continue must be enabled")

	var captured_paths: Array = []
	instance.transition_override = func(path): captured_paths.append(path)

	instance.press_continue()

	assert_eq(
		CurrentGameState.data.scenario_path, DRIPPING_CAVE_SCENARIO_PATH,
		"Continue must call load_from_slot(0), restoring the saved scenario_path"
	)
	assert_eq(
		captured_paths, [MAIN_SCENE_PATH],
		"Continue must request exactly one transition, to MainScene.tscn, after a successful load"
	)


func test_continue_press_with_race_condition_load_failure_blocks_transition_and_logs_push_warning() -> void:
	CurrentGameState.data = NewGameFactoryClass.create_prologue_state()
	assert_true(CurrentGameState.save_to_slot(0), "fixture setup: save_to_slot(0) must succeed")

	var instance = _instantiate_title_screen()
	assert_true(instance.is_continue_enabled(), "fixture precondition: Continue must be enabled while the save file still exists")

	# Simulate a race condition: the save file vanishes between the
	# enable-check above and the press below (e.g. deleted by another
	# process, or the disk becoming unavailable) -- load_from_slot(0) must
	# now fail even though the button was enabled a moment ago.
	var dir := DirAccess.open(SAVES_DIR)
	assert_not_null(dir, "fixture setup: user://saves must be openable")
	dir.remove("slot_0.json")
	assert_false(FileAccess.file_exists(SLOT_0_PATH), "fixture setup: slot_0.json must now be gone, simulating the race")

	var pre_press_data = CurrentGameState.data
	var captured_paths: Array = []
	instance.transition_override = func(path): captured_paths.append(path)

	instance.press_continue()

	assert_eq(
		captured_paths.size(), 0,
		"a race-condition load_from_slot(0) failure must block the transition to MainScene entirely (fail-closed)"
	)
	assert_eq(
		CurrentGameState.data, pre_press_data,
		"CurrentGameState.data must be left completely unchanged by a failed load_from_slot(0) (its own fail-closed contract)"
	)

	var content: String = _read_title_screen_source()
	assert_true(
		content.contains("push_warning(") and content.contains("race condition"),
		"TitleScreen.gd must push_warning() when Continue's load_from_slot(0) unexpectedly fails (race condition, fail-closed)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — Dev: Pick Scenario debug-build guard (NFR-006 / RISK-010)
# ══════════════════════════════════════════════════════════════════════════

func test_dev_pick_scenario_is_hidden_when_debug_build_is_simulated_false() -> void:
	var instance = _instantiate_title_screen()
	instance.debug_build_override = false
	instance.refresh()

	assert_false(
		instance.is_dev_scenario_panel_visible(),
		"Dev: Pick Scenario must be absent/hidden when OS.is_debug_build() is false (NFR-006, RISK-010)"
	)


func test_dev_pick_scenario_is_visible_and_functional_when_debug_build_is_simulated_true() -> void:
	var instance = _instantiate_title_screen()
	instance.debug_build_override = true
	instance.refresh()

	assert_true(
		instance.is_dev_scenario_panel_visible(),
		"Dev: Pick Scenario must be present when OS.is_debug_build() is simulated true"
	)

	var paths: Array = instance.get_dev_scenario_paths()
	assert_true(paths.has(PROLOGUE_SCENARIO_PATH), "the real res://data/scenarios/ must enumerate prologue_scenario.tres")
	assert_true(paths.has(DRIPPING_CAVE_SCENARIO_PATH), "the real res://data/scenarios/ must enumerate dripping_cave_scenario.tres")

	var target_index: int = paths.find(DRIPPING_CAVE_SCENARIO_PATH)
	var captured_paths: Array = []
	instance.transition_override = func(path): captured_paths.append(path)

	instance.press_dev_scenario(target_index)

	assert_eq(
		CurrentGameState.data.scenario_path, DRIPPING_CAVE_SCENARIO_PATH,
		"selecting a Dev: Pick Scenario row must call NewGameFactory.create_state_for_scenario() for the chosen path"
	)
	assert_eq(captured_paths, [MAIN_SCENE_PATH], "selecting a Dev: Pick Scenario row must request a transition to MainScene.tscn")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — empty/missing scenarios directory: disabled placeholder,
# no crash.
# ══════════════════════════════════════════════════════════════════════════

func test_dev_pick_scenario_shows_disabled_placeholder_for_an_empty_or_missing_directory() -> void:
	var instance = _instantiate_title_screen()
	instance.debug_build_override = true
	instance.scenarios_dir_override = "res://__nonexistent_scenarios_dir_feat008__"

	# Must not crash when re-populating against a directory that doesn't
	# exist on disk.
	instance.refresh()

	assert_true(instance.is_dev_scenario_panel_visible(), "fixture precondition: the panel must still be visible in a debug-build context")
	assert_true(
		instance.get_dev_scenario_paths().is_empty(),
		"an empty/missing scenarios directory must enumerate zero candidate paths"
	)

	var dev_list: ItemList = instance.get_node("DevScenarioList")
	assert_eq(dev_list.item_count, 1, "an empty/missing scenarios directory must render exactly one placeholder row")
	assert_true(dev_list.is_item_disabled(0), "the placeholder row must be disabled")

	# Selecting the (disabled) placeholder must never crash and must never
	# assign an invalid scenario onto CurrentGameState.data.
	instance.press_dev_scenario(0)
	assert_eq(CurrentGameState.data.scenario_path, "", "a defensive press_dev_scenario() call against an empty candidate list must be a no-op")
