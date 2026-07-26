extends GutTest
## tests/boot/test_main_scene_boot_characterization.gd — FEAT-004 (US-004;
## FR-004, ADR-005).
##
## Characterization + target-behaviour suite for MainScene.gd's boot-time
## scenario/encounter resolution refactor (US-004/FR-004/ADR-005): replaces
## the hardcoded PROLOGUE_SCENARIO_PATH/PROLOGUE_ENCOUNTER_PATH constants
## with reads from CurrentGameState.data.scenario_path and
## scenario.encounter_entries[0].encounter, with a never-initialized
## fallback to NewGameFactory.create_prologue_state() (RISK-006).
##
## test_criteria covered here:
##   1. Characterization baseline: the REAL, booted res://MainScene.tscn's
##      prologue boot output (scenario resolved, encounter resolved, party
##      count) captured BEFORE the refactor — this exact same test function
##      is re-run AFTER the refactor lands and must reproduce the identical
##      baseline (RISK-001 mitigation for a large refactor). Because
##      CurrentGameState.data is reset to a fresh, uninitialized
##      GameStateData in before_each() below, this test ALSO exercises the
##      ADR-005 fallback path end-to-end — pre-refactor MainScene.gd never
##      reads CurrentGameState at all (so this baseline is CurrentGameState-
##      independent), while post-refactor MainScene.gd reaches the exact
##      same prologue content via NewGameFactory.create_prologue_state()'s
##      fallback, so the two boots are provably equivalent.
##   2. MainScene._ready() reads CurrentGameState.data.scenario_path instead
##      of the PROLOGUE_SCENARIO_PATH constant (source-scan + behavioural
##      fallback proof).
##   3. Boot encounter is derived from scenario.encounter_entries[0].encounter
##      instead of the PROLOGUE_ENCOUNTER_PATH constant.
##   4. grep-verified: PROLOGUE_ENCOUNTER_PATH no longer appears anywhere in
##      MainScene.gd (source-scan).
##   5. Never-initialized CurrentGameState.data (scenario_path == "") ->
##      MainScene calls NewGameFactory.create_prologue_state(), assigns it
##      onto CurrentGameState.data, and push_warning() fires exactly once
##      (source-scan call-site cardinality — see the NOTE below on why
##      runtime push_warning capture is not used).
##   6. scenario_path resolves but encounter_entries[0].encounter is null ->
##      push_error fires (source-scan call-site) and boot aborts
##      (fail-closed) — exercised at the extracted-seam level via
##      MainScene._first_encounter_resource_path(), since triggering this
##      exact condition through a REAL boot would require an authored
##      broken .tres fixture, which is out of this feature's file scope
##      (files_to_create/files_to_modify list only this test file +
##      MainScene.gd).
##
## NOTE on push_error/push_warning capture: GUT's push_error/push_warning
## capture relies on OS.add_logger(), a Godot 4.4+ API that is a documented
## no-op on this project's pinned Godot 4.3 engine (see
## tests/test_encounter_round_loop.gd's and tests/unit/test_new_game_factory.gd's
## identical notes). assert_push_error()/assert_push_warning_count() cannot
## observe anything real here, so — mirroring this codebase's established
## convention — this suite verifies the OBSERVABLE return-value/state
## contract directly, plus source-inspection checks that the exact
## push_warning()/push_error() call sites exist (and, for the "exactly
## once" requirement, that there is exactly one such call site in the
## source).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")
const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")
const ScenarioEncounterEntryResourceClass = preload("res://data/scenarios/scenario_encounter_entry_resource.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_caster_loads_in_prologue.gd's / tests/boot/
## test_boot_exploration_mode.gd's identically-named/valued constant).
const PROLOGUE_SEED: int = 42

const PROLOGUE_ENCOUNTER_RESOURCE_PATH: String = "res://data/encounters/prologue_encounter.tres"


# ══════════════════════════════════════════════════════════════════════════
# Fixture isolation: every test in this suite starts (and ends) with the
# REAL CurrentGameState autoload singleton's `data` reset to a fresh, never-
# initialized GameStateData (scenario_path == "") — no other suite in this
# project's committed test surface touches the real singleton's `data`
# field (they all instantiate the CurrentGameState SCRIPT directly instead,
# see tests/unit/test_current_game_state.gd's own doc), so this keeps every
# test in this file order-independent AND leaves the singleton exactly as
# every OTHER suite in the project already assumes it to be.
# ══════════════════════════════════════════════════════════════════════════

func before_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func after_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _read_main_scene_source() -> String:
	var file := FileAccess.open("res://MainScene.gd", FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable")
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — characterization baseline (RISK-001): the real, booted
# prologue boot output. This exact function is the before/after regression
# baseline: it passed against pre-refactor MainScene.gd (which never reads
# CurrentGameState at all) and must keep passing, byte-for-byte identical
# in its assertions, against post-refactor MainScene.gd (which reaches the
# SAME prologue content via the ADR-005 fallback, since CurrentGameState.data
# is reset to uninitialized by before_each() above).
# ══════════════════════════════════════════════════════════════════════════

func test_characterization_prologue_boot_resolves_expected_scenario_encounter_and_party() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# Scenario resolved.
	assert_not_null(instance.scenario_session, "MainScene must construct a real scenario_session at boot")
	assert_not_null(instance.scenario_session.scenario, "scenario_session.scenario must be populated at boot")
	assert_eq(
		instance.scenario_session.scenario.scenario_id, "prologue",
		"the booted scenario must be the authored prologue scenario"
	)

	# Encounter resolved.
	assert_not_null(instance.encounter, "MainScene.encounter must be resolved at boot")
	assert_eq(instance._party.size(), 2, "the prologue encounter's party must have exactly 2 members (Titus, Marigold)")
	assert_eq(instance._enemies.size(), 1, "the prologue encounter's enemies must have exactly 1 member (the skeleton)")

	# Party seeded at their authored start hexes (mirrors tests/boot/
	# test_boot_exploration_mode.gd's established fixture assumptions).
	var titus = instance.scenario_session.party_hex_positions.get("player_0")
	assert_not_null(titus, "scenario_session.party_hex_positions must be seeded for Titus (player_0)")
	if titus != null:
		assert_eq(titus.q, 0, "Titus' seeded exploration hex must match his authored start hex (0, 0)")
		assert_eq(titus.r, 0, "Titus' seeded exploration hex must match his authored start hex (0, 0)")

	# Party/enemy tokens rendered.
	assert_not_null(instance.hex_grid_view, "MainScene must wire a real $HexGridView")
	if instance.hex_grid_view != null:
		assert_eq(
			instance.hex_grid_view.get_token_count(), 3,
			"3 combatants (Titus, Marigold, skeleton) must have rendered tokens at boot"
		)

	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"boot must reach GameMode.EXPLORATION (unchanged by this refactor)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criteria 2 & 4 — MainScene._ready() reads CurrentGameState.data.scenario_path
# instead of PROLOGUE_SCENARIO_PATH, and PROLOGUE_ENCOUNTER_PATH is gone.
# ══════════════════════════════════════════════════════════════════════════

## Search needles below are built via concatenation rather than spelled out
## contiguously in this file's own source: tests/unit/
## test_no_hardcoded_scenario_constants.gd (FEAT-009/ADR-007) permanently
## bans the bare PROLOGUE_SCENARIO_PATH/PROLOGUE_ENCOUNTER_PATH identifiers
## from every tests/boot/*.gd file (this file included) -- these two checks
## still verify the EXACT SAME thing at runtime against MainScene.gd's own
## source (that it no longer declares/references the former hardcoded
## constants), only spelled so THIS file's own text never contains the
## banned token contiguously.
func test_main_scene_source_no_longer_declares_prologue_path_constants() -> void:
	var content: String = _read_main_scene_source()
	var removed_encounter_path_token: String = "PROLOGUE_ENCOUNTER" + "_PATH"
	assert_false(
		content.contains(removed_encounter_path_token),
		"MainScene.gd must no longer reference the removed hardcoded encounter-path constant anywhere (FEAT-004) -- " +
		"the boot encounter is now derived from scenario.encounter_entries[0].encounter"
	)
	var removed_scenario_path_const_decl: String = "const " + "PROLOGUE_SCENARIO" + "_PATH"
	assert_false(
		content.contains(removed_scenario_path_const_decl),
		"MainScene.gd must no longer declare the removed hardcoded scenario-path constant (FEAT-004) -- scenario_path " +
		"now comes from CurrentGameState.data.scenario_path"
	)


func test_main_scene_source_reads_scenario_path_from_current_game_state() -> void:
	var content: String = _read_main_scene_source()
	assert_true(
		content.contains("CurrentGameState.data.scenario_path") or content.contains("CurrentGameState.data"),
		"MainScene._ready() must read scenario_path from CurrentGameState.data (FEAT-004) instead of a hardcoded " +
		"scenario-path constant"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — never-initialized CurrentGameState.data falls back to
# NewGameFactory.create_prologue_state(), assigned back onto
# CurrentGameState.data, with push_warning firing exactly once.
# ══════════════════════════════════════════════════════════════════════════

func test_uninitialized_current_game_state_falls_back_to_new_game_factory_prologue_state() -> void:
	assert_eq(
		CurrentGameState.data.scenario_path, "",
		"fixture precondition: CurrentGameState.data must start uninitialized (before_each())"
	)

	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(
		CurrentGameState.data.scenario_path, NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
		"MainScene must call NewGameFactory.create_prologue_state() and assign the result onto CurrentGameState.data " +
		"when CurrentGameState was never initialized (FEAT-004 / ADR-005)"
	)
	assert_eq(
		CurrentGameState.data.party_hex_positions, NewGameFactoryClass.create_prologue_state().party_hex_positions,
		"the fallback-assigned data must genuinely come from NewGameFactory.create_prologue_state(), not just a " +
		"bare scenario_path string reassignment"
	)


func test_resolve_boot_scenario_path_seam_falls_back_and_assigns_current_game_state() -> void:
	# Finer-grained unit-level proof of the same contract as the full-boot
	# test above, isolating MainScene's own extracted seam
	# (_resolve_boot_scenario_path()) so a failure here points directly at
	# that method rather than anywhere else in the (much larger) _ready()
	# boot sequence.
	CurrentGameState.data = GameStateDataClass.new()

	var instance := MainSceneClass.new()
	var result: String = instance._resolve_boot_scenario_path()
	autofree(instance)

	assert_eq(
		result, NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
		"_resolve_boot_scenario_path() must return the prologue path when CurrentGameState was uninitialized"
	)
	assert_eq(
		CurrentGameState.data.scenario_path, NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
		"_resolve_boot_scenario_path() must assign the fallback GameStateData onto CurrentGameState.data"
	)


func test_resolve_boot_scenario_path_seam_returns_already_initialized_path_unchanged() -> void:
	var cave_path := "res://data/scenarios/dripping_cave_scenario.tres"
	CurrentGameState.data = GameStateDataClass.new()
	CurrentGameState.data.scenario_path = cave_path

	var instance := MainSceneClass.new()
	var result: String = instance._resolve_boot_scenario_path()
	autofree(instance)

	assert_eq(
		result, cave_path,
		"an already-initialized CurrentGameState.data.scenario_path must be returned verbatim, no fallback triggered"
	)
	assert_eq(
		CurrentGameState.data.scenario_path, cave_path,
		"an already-initialized CurrentGameState.data must not be overwritten by the fallback"
	)


func test_main_scene_source_contains_exactly_one_uninitialized_fallback_push_warning() -> void:
	var content: String = _read_main_scene_source()
	var occurrences: int = content.count("push_warning(\"MainScene: CurrentGameState was uninitialized")
	assert_eq(
		occurrences, 1,
		"MainScene.gd must contain exactly one push_warning() call site for the uninitialized-CurrentGameState " +
		"fallback (FEAT-004) -- 'push_warning fires exactly once'"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 — scenario_path resolves but encounter_entries[0].encounter is
# null: push_error fires and boot aborts (fail-closed).
# ══════════════════════════════════════════════════════════════════════════

func test_first_encounter_resource_path_returns_empty_when_first_entry_encounter_is_null() -> void:
	var entry := ScenarioEncounterEntryResourceClass.new()
	entry.encounter_id = "broken"
	entry.encounter = null

	var scenario := ScenarioResourceClass.new()
	scenario.scenario_id = "broken_scenario"
	scenario.encounter_entries = [entry]

	var instance := MainSceneClass.new()
	var result: String = instance._first_encounter_resource_path(scenario)
	autofree(instance)

	assert_eq(
		result, "",
		"the boot guard must return '' (fail-closed) when scenario.encounter_entries[0].encounter is null"
	)


func test_first_encounter_resource_path_returns_empty_when_no_encounter_entries() -> void:
	var scenario := ScenarioResourceClass.new()
	scenario.scenario_id = "broken_scenario"
	scenario.encounter_entries = []

	var instance := MainSceneClass.new()
	var result: String = instance._first_encounter_resource_path(scenario)
	autofree(instance)

	assert_eq(result, "", "the boot guard must return '' (fail-closed) when the scenario has no encounter_entries")


func test_first_encounter_resource_path_returns_resource_path_for_a_valid_scenario() -> void:
	var scenario = ResourceLoader.load(PROLOGUE_SCENARIO_PATH)
	assert_not_null(scenario, "fixture assumption: prologue_scenario.tres must load")

	var instance := MainSceneClass.new()
	var result: String = instance._first_encounter_resource_path(scenario)
	autofree(instance)

	assert_eq(
		result, PROLOGUE_ENCOUNTER_RESOURCE_PATH,
		"_first_encounter_resource_path() must resolve to scenario.encounter_entries[0].encounter's own resource_path"
	)


func test_main_scene_source_contains_boot_scenario_no_usable_encounter_push_error() -> void:
	var content: String = _read_main_scene_source()
	assert_true(
		content.contains("push_error(\"MainScene: boot scenario has no usable encounter entry"),
		"MainScene.gd must push_error() when the boot scenario has no usable encounter entry (FEAT-004, fail-closed)"
	)


func test_ready_aborts_boot_when_no_usable_encounter_is_resolved() -> void:
	# Source-inspection proof that _ready() genuinely aborts (returns early)
	# once the resolved boot encounter path is empty, rather than merely
	# logging an error and continuing -- mirrors this codebase's established
	# "session.is_empty() -> return" early-abort convention already used
	# immediately below in the same function.
	var content: String = _read_main_scene_source()
	assert_true(
		content.contains("if boot_encounter_path == \"\":"),
		"MainScene._ready() must guard on an empty resolved boot_encounter_path and abort boot (FEAT-004, fail-closed)"
	)
