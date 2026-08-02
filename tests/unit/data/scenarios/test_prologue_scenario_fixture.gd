extends GutTest
## tests/unit/data/scenarios/test_prologue_scenario_fixture.gd
##
## GUT unit tests for FEAT-007 (US-007 / FR-009, NFR-001):
## the steel thread's two authored data fixtures —
## data/parties/default_party.tres and data/scenarios/prologue_scenario.tres
## — validated immediately after their last dependency (FEAT-006) landed,
## per RISK-007 mitigation, so US-008/US-009 are unblocked early rather
## than waiting on a batched end-of-iteration authoring pass.
##
## Architecture note (ADR-001):
##   These are DOMAIN-layer data fixtures (data/parties/, data/scenarios/):
##   plain authored .tres Resource instances with zero business logic. This
##   test file itself performs no production-code changes; it only proves
##   the fixtures load and shape correctly via Godot's ResourceLoader.
##
## Test criteria covered:
##   1. ResourceLoader.load(prologue_scenario.tres) returns a non-null
##      ScenarioResource.
##   2. scenario_id=='prologue', party non-null, encounter_entries.size()==1,
##      encounter_entries[0].encounter_id=='prologue'.
##   3. Regression: prologue_encounter.tres remains unmodified with
##      tiles==[].

const ScenarioResource = preload("res://data/scenarios/scenario_resource.gd")
const PartyResource = preload("res://data/characters/party_resource.gd")
const ScenarioEncounterEntryResource = preload("res://data/scenarios/scenario_encounter_entry_resource.gd")
const EncounterResource = preload("res://data/encounters/encounter_resource.gd")

const DEFAULT_PARTY_PATH := "res://data/parties/default_party.tres"
const PROLOGUE_SCENARIO_PATH := "res://data/scenarios/prologue_scenario.tres"
const PROLOGUE_ENCOUNTER_PATH := "res://data/encounters/prologue_encounter.tres"


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: ResourceLoader.load(prologue_scenario.tres) returns non-null
# ══════════════════════════════════════════════════════════════════════════════

func test_prologue_scenario_loads_as_non_null_scenario_resource() -> void:
	assert_true(
		ResourceLoader.exists(PROLOGUE_SCENARIO_PATH),
		"data/scenarios/prologue_scenario.tres must exist"
	)

	var scenario = ResourceLoader.load(PROLOGUE_SCENARIO_PATH)
	assert_not_null(scenario, "prologue_scenario.tres must load without error")
	assert_is(scenario, ScenarioResource, "prologue_scenario.tres must load as a ScenarioResource")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: scenario_id/party/encounter_entries shape
# ══════════════════════════════════════════════════════════════════════════════

func test_prologue_scenario_has_expected_shape() -> void:
	var scenario = ResourceLoader.load(PROLOGUE_SCENARIO_PATH)
	assert_not_null(scenario, "prologue_scenario.tres must load")
	if scenario == null:
		return

	assert_eq(scenario.scenario_id, "prologue", "scenario_id must be 'prologue'")

	assert_not_null(scenario.party, "party must be non-null")
	assert_is(scenario.party, PartyResource, "party must be a PartyResource")

	assert_eq(scenario.encounter_entries.size(), 1, "encounter_entries must have exactly one entry")
	if scenario.encounter_entries.size() == 1:
		var entry = scenario.encounter_entries[0]
		assert_is(
			entry, ScenarioEncounterEntryResource,
			"the single entry must be a ScenarioEncounterEntryResource"
		)
		assert_eq(entry.encounter_id, "prologue", "encounter_entries[0].encounter_id must be 'prologue'")
		assert_not_null(entry.encounter, "encounter_entries[0].encounter must be non-null")
		assert_is(entry.encounter, EncounterResource, "encounter_entries[0].encounter must be an EncounterResource")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion: default_party.tres itself loads as a well-formed PartyResource
# ══════════════════════════════════════════════════════════════════════════════

func test_default_party_loads_with_titus_and_marigold() -> void:
	assert_true(
		ResourceLoader.exists(DEFAULT_PARTY_PATH),
		"data/parties/default_party.tres must exist"
	)

	var party = ResourceLoader.load(DEFAULT_PARTY_PATH)
	assert_not_null(party, "default_party.tres must load without error")
	assert_is(party, PartyResource, "default_party.tres must load as a PartyResource")
	if party == null:
		return

	assert_eq(
		party.character_resource_paths,
		["res://data/characters/titus.tres", "res://data/characters/marigold.tres", "res://data/characters/gram_marx.tres"],
		"default_party.tres must reference Titus, Marigold, and Gram Marx"
	)

	for path in party.character_resource_paths:
		assert_true(ResourceLoader.exists(path), "referenced character resource must exist: %s" % path)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: regression — prologue_encounter.tres remains unmodified
# ══════════════════════════════════════════════════════════════════════════════

func test_prologue_encounter_remains_unmodified_with_empty_tiles() -> void:
	assert_true(
		ResourceLoader.exists(PROLOGUE_ENCOUNTER_PATH),
		"data/encounters/prologue_encounter.tres must still exist"
	)

	var encounter = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH)
	assert_not_null(encounter, "prologue_encounter.tres must still load")
	if encounter == null:
		return

	assert_eq(
		encounter.party_resource_paths,
		["res://data/characters/titus.tres", "res://data/characters/marigold.tres"],
		"prologue_encounter.tres party_resource_paths must remain unmodified"
	)
	assert_eq(
		encounter.enemy_resource_paths, ["res://data/enemies/skeleton.tres"],
		"prologue_encounter.tres enemy_resource_paths must remain unmodified"
	)
	assert_eq(encounter.seed, 42, "prologue_encounter.tres seed must remain unmodified")
	assert_eq(encounter.tiles, [], "prologue_encounter.tres tiles must remain the empty-array default")
