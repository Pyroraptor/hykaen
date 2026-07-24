extends GutTest
## tests/unit/core/application/use_cases/test_load_scenario_encounter_use_case_happy_path.gd
##
## GUT unit tests for FEAT-008 (US-008 / FR-007, NFR-002, NFR-005):
## core/application/use_cases/load_scenario_encounter_use_case.gd —
## LoadScenarioEncounterUseCase's HAPPY-PATH assembly only (RISK-002
## mitigation — error branches are a later feature's own dedicated test
## file; see that file's own doc header once it exists).
##
## Uses a prologue-shaped in-memory ScenarioResource (mirrors
## data/scenarios/prologue_scenario.tres's real shape) built from the REAL
## prologue_encounter.tres/titus.tres/marigold.tres/skeleton.tres fixtures
## on disk plus the REAL infrastructure/combatant_factory.gd
## CombatantFactory (no mocked collaborators — see WORKING SOFTWARE
## guidance: a test that mocks everything tells us nothing about whether
## this actually works end-to-end against real authored data).
##
## Test criteria covered:
##   1. happy-path execute() with a prologue-shaped in-memory ScenarioResource
##      returns {ok:true, encounter_resource, party_combatants,
##      enemy_combatants, party_start_positions, enemy_start_positions, tiles}.
##   2. party_combatants are resolved from scenario.party
##      .character_resource_paths EVEN WHEN the matched EncounterResource
##      carries its own (different) party_resource_paths (ADR-002 override
##      verified: the scenario's roster here is a single-member subset,
##      deliberately different from the two-member encounter-level list).
##   3. tiles and start positions are forwarded VERBATIM from the matched
##      EncounterResource.
##   4. Static review: zero Presentation/Node/Control imports in the
##      use-case source file.

const LoadScenarioEncounterUseCaseClass = preload("res://core/application/use_cases/load_scenario_encounter_use_case.gd")
const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")
const ScenarioEncounterEntryResourceClass = preload("res://data/scenarios/scenario_encounter_entry_resource.gd")
const PartyResourceClass = preload("res://data/characters/party_resource.gd")
const EncounterResourceClass = preload("res://data/encounters/encounter_resource.gd")

const TITUS_PATH := "res://data/characters/titus.tres"
const MARIGOLD_PATH := "res://data/characters/marigold.tres"
const PROLOGUE_ENCOUNTER_PATH := "res://data/encounters/prologue_encounter.tres"
const ENCOUNTER_ID := "prologue_fight"


## _build_prologue_shaped_scenario() -> ScenarioResource
##
## Builds an in-memory ScenarioResource mirroring
## data/scenarios/prologue_scenario.tres's real shape, EXCEPT the
## scenario-level party is deliberately a single-member subset
## (Marigold only) — DIFFERENT from the matched EncounterResource's own
## authored party_resource_paths ([titus, marigold], loaded straight from
## prologue_encounter.tres) — so the ADR-002 override is unambiguously
## exercised: if the use case ever fell back to
## encounter_resource.party_resource_paths, party_combatants would come
## back with 2 entries instead of the expected 1.
func _build_prologue_shaped_scenario() -> ScenarioResourceClass:
	var encounter_resource = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH)
	assert_not_null(encounter_resource, "fixture assumption: prologue_encounter.tres must load")
	assert_eq(
		encounter_resource.party_resource_paths, [TITUS_PATH, MARIGOLD_PATH],
		"fixture assumption: prologue_encounter.tres's own party_resource_paths must be [titus, marigold]"
	)

	var entry := ScenarioEncounterEntryResourceClass.new()
	entry.encounter_id = ENCOUNTER_ID
	entry.encounter = encounter_resource

	var party := PartyResourceClass.new()
	party.character_resource_paths = [MARIGOLD_PATH]

	var scenario := ScenarioResourceClass.new()
	scenario.scenario_id = "prologue"
	scenario.display_name = "The Hollow Prologue"
	scenario.party = party
	scenario.encounter_entries = [entry]

	return scenario


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: happy-path execute() returns the full {ok:true, ...} shape
# ══════════════════════════════════════════════════════════════════════════════

func test_happy_path_returns_ok_true_with_full_payload_shape() -> void:
	var scenario := _build_prologue_shaped_scenario()
	var use_case := LoadScenarioEncounterUseCaseClass.new()

	var result: Dictionary = use_case.execute(scenario, ENCOUNTER_ID)

	assert_true(result.get("ok", false), "happy-path execute() must return ok:true")
	assert_true(result.has("encounter_resource"), "result must carry encounter_resource")
	assert_true(result.has("party_combatants"), "result must carry party_combatants")
	assert_true(result.has("enemy_combatants"), "result must carry enemy_combatants")
	assert_true(result.has("party_start_positions"), "result must carry party_start_positions")
	assert_true(result.has("enemy_start_positions"), "result must carry enemy_start_positions")
	assert_true(result.has("tiles"), "result must carry tiles")

	assert_is(
		result["encounter_resource"], EncounterResourceClass,
		"encounter_resource must be the matched EncounterResource"
	)

	assert_eq(result["enemy_combatants"].size(), 1, "prologue fixture authors exactly 1 enemy (skeleton)")
	var enemy_combatant: Dictionary = result["enemy_combatants"][0]
	assert_false(enemy_combatant.has("error"), "enemy_combatants entries must be real combatants, never an error dict")
	assert_eq(enemy_combatant.get("name", ""), "Skeleton", "the enemy combatant must be built from skeleton.tres")


# ══════════════════════════════════════════════════════════════════════════════
# Regression (FEAT-008): party/enemy combatants must carry a stable,
# non-empty combatant_id, mirroring infrastructure/resource_encounter_repository.gd's
# "player_%d"/"enemy_%d" convention -- WITHOUT this, every scenario-assembled
# combatant collapsed onto CombatantFactory's "" default id, breaking any
# later caller's ability to correlate a combatant back to its already-
# rendered HexGridView token (e.g. MainScene's exploration-to-combat handoff).
# ══════════════════════════════════════════════════════════════════════════════

func test_party_and_enemy_combatants_carry_stable_combatant_ids() -> void:
	var scenario := _build_prologue_shaped_scenario()
	var use_case := LoadScenarioEncounterUseCaseClass.new()

	var result: Dictionary = use_case.execute(scenario, ENCOUNTER_ID)
	assert_true(result.get("ok", false), "execute() must succeed for this fixture")

	var party_combatants: Array = result.get("party_combatants", [])
	assert_eq(party_combatants.size(), 1, "fixture assumption: 1 party member (Marigold)")
	if party_combatants.size() == 1:
		assert_eq(party_combatants[0].get("combatant_id", ""), "player_0", "the first party combatant must be assigned combatant_id 'player_0'")

	var enemy_combatants: Array = result.get("enemy_combatants", [])
	assert_eq(enemy_combatants.size(), 1, "fixture assumption: 1 enemy (skeleton)")
	if enemy_combatants.size() == 1:
		assert_eq(enemy_combatants[0].get("combatant_id", ""), "enemy_0", "the first enemy combatant must be assigned combatant_id 'enemy_0'")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: party_combatants resolved from scenario.party, overriding
# the matched EncounterResource's own (different) party_resource_paths
# ══════════════════════════════════════════════════════════════════════════════

func test_party_combatants_resolved_from_scenario_party_overrides_encounter_party_paths() -> void:
	var scenario := _build_prologue_shaped_scenario()
	var use_case := LoadScenarioEncounterUseCaseClass.new()

	var result: Dictionary = use_case.execute(scenario, ENCOUNTER_ID)

	assert_true(result.get("ok", false), "execute() must succeed for this fixture")

	var party_combatants: Array = result.get("party_combatants", [])
	assert_eq(
		party_combatants.size(), 1,
		"party_combatants must come from scenario.party (1 member: Marigold), NOT from the matched " +
		"EncounterResource's own party_resource_paths (2 members: titus, marigold) — ADR-002 override"
	)
	if party_combatants.size() == 1:
		assert_false(party_combatants[0].has("error"), "party_combatants entries must be real combatants")
		assert_eq(
			party_combatants[0].get("name", ""), "Marigold",
			"the single resolved party combatant must be built from scenario.party's Marigold path, not Titus"
		)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: tiles and start positions forwarded verbatim
# ══════════════════════════════════════════════════════════════════════════════

func test_tiles_and_start_positions_forwarded_verbatim_from_matched_encounter() -> void:
	var scenario := _build_prologue_shaped_scenario()
	var use_case := LoadScenarioEncounterUseCaseClass.new()

	var result: Dictionary = use_case.execute(scenario, ENCOUNTER_ID)
	assert_true(result.get("ok", false), "execute() must succeed for this fixture")

	var encounter_resource = scenario.encounter_entries[0].encounter

	assert_eq(
		result.get("tiles", null), encounter_resource.tiles,
		"tiles must be forwarded verbatim from the matched EncounterResource"
	)
	assert_eq(
		result.get("party_start_positions", null), encounter_resource.party_hex_positions,
		"party_start_positions must be forwarded verbatim from the matched EncounterResource.party_hex_positions"
	)
	assert_eq(
		result.get("enemy_start_positions", null), encounter_resource.enemy_hex_positions,
		"enemy_start_positions must be forwarded verbatim from the matched EncounterResource.enemy_hex_positions"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: static review — zero Presentation/Node/Control imports
# ══════════════════════════════════════════════════════════════════════════════

func test_use_case_gd_has_no_presentation_or_scene_tree_imports() -> void:
	var file := FileAccess.open("res://core/application/use_cases/load_scenario_encounter_use_case.gd", FileAccess.READ)
	assert_not_null(file, "load_scenario_encounter_use_case.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	for forbidden in ["extends Node", "extends Control", "extends SceneTree", "extends CanvasItem", "res://presentation/", "res://MainScene.gd"]:
		assert_false(
			content.contains(forbidden),
			"load_scenario_encounter_use_case.gd must not reference '%s' (Application layer purity, ADR-001)" % forbidden
		)

	assert_true(content.contains("extends RefCounted"), "load_scenario_encounter_use_case.gd must extend RefCounted")
