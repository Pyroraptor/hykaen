extends GutTest
## tests/unit/test_new_game_factory.gd
##
## GUT unit tests for FEAT-002 (US-003 / FR-003, NFR-002, NFR-003):
## core/application/new_game_factory.gd — NewGameFactory, the pure
## APPLICATION-layer use-case service that seeds a GameStateData for either
## the authored prologue scenario or an arbitrary scenario path.
##
## Test criteria covered (per FEAT-002 spec):
##   1. create_prologue_state() returns GameStateData with scenario_path ==
##      PROLOGUE_SCENARIO_PATH_CONST and party_hex_positions seeded from
##      that scenario's encounter_entries[0].
##   2. create_state_for_scenario(dripping_cave_path) returns cave-specific
##      scenario_path and seeded positions.
##   3. Unloadable scenario path triggers push_error and still returns a
##      non-null GameStateData with scenario_path set (fail-loud, never
##      null).
##
## Source-scan/domain-purity fitness tests for this file live in the
## SEPARATE tests/unit/test_core_purity_source_scan.gd suite (per the
## feature spec's files_to_create split), not duplicated here.

const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")

const DRIPPING_CAVE_SCENARIO_PATH: String = "res://data/scenarios/dripping_cave_scenario.tres"
const UNLOADABLE_SCENARIO_PATH: String = "res://data/scenarios/does_not_exist_feat002.tres"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: create_prologue_state()
# ══════════════════════════════════════════════════════════════════════════

func test_create_prologue_state_sets_prologue_scenario_path() -> void:
	var state := NewGameFactoryClass.create_prologue_state()

	assert_not_null(state, "create_prologue_state() must never return null")
	assert_true(state is GameStateDataClass, "create_prologue_state() must return a GameStateData")
	assert_eq(
		state.scenario_path, NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
		"create_prologue_state() must set scenario_path to PROLOGUE_SCENARIO_PATH_CONST"
	)


func test_create_prologue_state_seeds_party_hex_positions_from_first_encounter_entry() -> void:
	var state := NewGameFactoryClass.create_prologue_state()

	# prologue_scenario.tres's party is default_party.tres (titus, marigold,
	# gram_marx) and its sole encounter_entries[0].encounter
	# (prologue_encounter.tres) authors party_hex_positions ==
	# [{q:0,r:0}, {q:-1,r:0}, {q:-2,r:0}].
	assert_eq(
		state.party_hex_positions,
		[
			{"combatant_id": "player_0", "q": 0, "r": 0},
			{"combatant_id": "player_1", "q": -1, "r": 0},
			{"combatant_id": "player_2", "q": -2, "r": 0},
		],
		"party_hex_positions must be seeded from prologue_scenario.tres's first encounter entry"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: create_state_for_scenario(dripping_cave_path)
# ══════════════════════════════════════════════════════════════════════════

func test_create_state_for_scenario_sets_cave_specific_scenario_path() -> void:
	var state := NewGameFactoryClass.create_state_for_scenario(DRIPPING_CAVE_SCENARIO_PATH)

	assert_not_null(state, "create_state_for_scenario() must never return null")
	assert_eq(
		state.scenario_path, DRIPPING_CAVE_SCENARIO_PATH,
		"create_state_for_scenario() must set scenario_path to the requested cave scenario path"
	)


func test_create_state_for_scenario_seeds_cave_specific_party_hex_positions() -> void:
	var state := NewGameFactoryClass.create_state_for_scenario(DRIPPING_CAVE_SCENARIO_PATH)

	# dripping_cave_scenario.tres's party is default_party.tres (titus,
	# marigold, gram_marx — 3 members); the scenario-authoritative roster
	# (ADR-002) yields 3 seeded entries, positioned from the encounter's
	# party_hex_positions[0]/[1]/[2] == {q:-8,r:4}/{q:-9,r:4}/{q:-9,r:5}.
	assert_eq(
		state.party_hex_positions,
		[
			{"combatant_id": "player_0", "q": -8, "r": 4},
			{"combatant_id": "player_1", "q": -9, "r": 4},
			{"combatant_id": "player_2", "q": -9, "r": 5},
		],
		"party_hex_positions must be seeded from dripping_cave_scenario.tres's encounter entry"
	)


func test_create_prologue_state_and_create_state_for_scenario_dripping_cave_differ() -> void:
	var prologue_state := NewGameFactoryClass.create_prologue_state()
	var cave_state := NewGameFactoryClass.create_state_for_scenario(DRIPPING_CAVE_SCENARIO_PATH)

	assert_ne(
		prologue_state.scenario_path, cave_state.scenario_path,
		"the two factory entry points must produce distinct scenario_path values"
	)
	assert_ne(
		prologue_state.party_hex_positions, cave_state.party_hex_positions,
		"the two factory entry points must produce distinct seeded party_hex_positions"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: unloadable scenario path — fail-loud, never null
#
# NOTE: verified via the OBSERVABLE return-value contract, not via GUT's
# push_error capture -- this mirrors tests/gut/test_combat_session_factory.gd
# and tests/unit/presentation/test_main_scene_load_encounter_from_scenario.gd's
# established convention: push_error() capture is unreliable on this
# project's pinned Godot 4.3 engine. new_game_factory.gd still calls
# push_error() at each failure branch (see its own source) -- this suite
# asserts the resulting GameStateData shape, which is both observable and
# reliable.
# ══════════════════════════════════════════════════════════════════════════

func test_unloadable_scenario_path_returns_non_null_state_with_scenario_path_set() -> void:
	var state := NewGameFactoryClass.create_state_for_scenario(UNLOADABLE_SCENARIO_PATH)

	assert_not_null(state, "an unloadable scenario path must still return a non-null GameStateData (fail-loud)")
	assert_true(state is GameStateDataClass, "the fail-loud fallback must still be a GameStateData")
	assert_eq(
		state.scenario_path, UNLOADABLE_SCENARIO_PATH,
		"scenario_path must be set to the (unloadable) requested path even on failure"
	)
	assert_true(
		state.party_hex_positions.is_empty(),
		"party_hex_positions must be empty (never partially seeded) when the scenario fails to load"
	)


# ══════════════════════════════════════════════════════════════════════════
# Bonus: default construction guarantee still holds for a totally empty
# scenario_path (matches GameStateData.new()'s own FR-001 contract).
# ══════════════════════════════════════════════════════════════════════════

func test_empty_scenario_path_is_treated_as_unloadable_and_still_returns_non_null_state() -> void:
	var state := NewGameFactoryClass.create_state_for_scenario("")

	assert_not_null(state, "an empty scenario_path must still return a non-null GameStateData")
	assert_eq(state.scenario_path, "", "scenario_path must round-trip the (invalid) empty input verbatim")
	assert_true(state.party_hex_positions.is_empty(), "party_hex_positions must be empty for an empty scenario_path")
