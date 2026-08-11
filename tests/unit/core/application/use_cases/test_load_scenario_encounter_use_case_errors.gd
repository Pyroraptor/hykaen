extends GutTest
## tests/unit/core/application/use_cases/test_load_scenario_encounter_use_case_errors.gd
##
## GUT test suite for FEAT-009 (US-008 / FR-007, NFR-002, NFR-005):
## core/application/use_cases/load_scenario_encounter_use_case.gd —
## LoadScenarioEncounterUseCase's THREE explicit error branches, each
## exercised in isolation (RISK-002 mitigation). Companion to
## test_load_scenario_encounter_use_case_happy_path.gd (FEAT-008), which
## covers ONLY the ok:true assembly path.
##
## Verifies, in the strict validation order documented on execute():
##   1. execute(null, "prologue") -> {ok:false, error_code:"NULL_SCENARIO"}.
##   2. execute(scenario_with_unknown_id, "nope") ->
##      {ok:false, error_code:"ENCOUNTER_NOT_FOUND"} (a scenario WITH
##      entries, none of which match the requested encounter_id).
##   3. execute(scenario_with_empty_entries, "prologue") ->
##      {ok:false, error_code:"ENCOUNTER_NOT_FOUND"} (the SAME error_code as
##      #2 — an empty encounter_entries array collapses to the same branch
##      as an unmatched id, per the use case's documented contract).
##   4. execute(scenario, "prologue", {"combatant_factory": <failing double>})
##      -> {ok:false, error_code:"COMBATANT_BUILD_FAILED"}, propagated
##      verbatim from the injected CombatantFactoryPort's failure — and the
##      result carries NO partial/leaking success-shaped keys (no
##      "party_combatants"/"enemy_combatants"/"encounter_resource"/"tiles"/
##      "party_start_positions"/"enemy_start_positions").
##   5. Static review: the use-case source contains zero Node/Control
##      Presentation imports AND zero trigger-evaluation/firing logic
##      (RISK-001/RISK-008 recheck — this steel thread does not evaluate
##      TriggerResource at all).

const LoadScenarioEncounterUseCaseClass = preload("res://core/application/use_cases/load_scenario_encounter_use_case.gd")
const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")
const ScenarioEncounterEntryResourceClass = preload("res://data/scenarios/scenario_encounter_entry_resource.gd")
const PartyResourceClass = preload("res://data/characters/party_resource.gd")

const TITUS_PATH := "res://data/characters/titus.tres"
const MARIGOLD_PATH := "res://data/characters/marigold.tres"
const PROLOGUE_ENCOUNTER_PATH := "res://data/encounters/prologue_encounter.tres"
const ENCOUNTER_ID := "prologue_fight"


## AlwaysFailingCombatantFactory -- a CombatantFactoryPort double whose
## build_party_combatant()/build_enemy_combatant() ALWAYS return an
## {"error": ...} Dictionary, regardless of input, so criterion 4 can
## exercise COMBATANT_BUILD_FAILED propagation without depending on which
## side (party vs enemy) the use case happens to build first.
class AlwaysFailingCombatantFactory:
	extends RefCounted

	const ERR_CODE: String = "ERR_TEST_DOUBLE_BUILD_FAILED"

	func build_party_combatant(_character_path: String, _hex_coord, _combatant_id: String = "") -> Dictionary:
		return {"error": ERR_CODE}

	func build_enemy_combatant(_enemy_path: String, _hex_coord, _combatant_id: String = "", _weapon_path_override: String = "", _off_hand_path_override: String = "") -> Dictionary:
		return {"error": ERR_CODE}


func _build_prologue_shaped_scenario(encounter_id: String = ENCOUNTER_ID) -> ScenarioResourceClass:
	var encounter_resource = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH)
	assert_not_null(encounter_resource, "fixture assumption: prologue_encounter.tres must load")

	var entry := ScenarioEncounterEntryResourceClass.new()
	entry.encounter_id = encounter_id
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
# Criterion 1: NULL_SCENARIO guard
# ══════════════════════════════════════════════════════════════════════════════

func test_null_scenario_returns_null_scenario_error() -> void:
	var use_case := LoadScenarioEncounterUseCaseClass.new()

	var result: Dictionary = use_case.execute(null, "prologue")

	assert_false(result.get("ok", true), "execute(null, ...) must return ok:false")
	assert_eq(
		result.get("error_code", ""), "NULL_SCENARIO",
		"execute(null, ...) must return error_code:NULL_SCENARIO"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: ENCOUNTER_NOT_FOUND -- unknown encounter_id
# ══════════════════════════════════════════════════════════════════════════════

func test_unknown_encounter_id_returns_encounter_not_found_error() -> void:
	var scenario := _build_prologue_shaped_scenario(ENCOUNTER_ID)
	var use_case := LoadScenarioEncounterUseCaseClass.new()

	var result: Dictionary = use_case.execute(scenario, "nope")

	assert_false(result.get("ok", true), "execute() with an unmatched encounter_id must return ok:false")
	assert_eq(
		result.get("error_code", ""), "ENCOUNTER_NOT_FOUND",
		"an unknown encounter_id must return error_code:ENCOUNTER_NOT_FOUND"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: ENCOUNTER_NOT_FOUND -- empty encounter_entries
# ══════════════════════════════════════════════════════════════════════════════

func test_empty_encounter_entries_returns_encounter_not_found_error() -> void:
	var party := PartyResourceClass.new()
	party.character_resource_paths = [MARIGOLD_PATH]

	var scenario := ScenarioResourceClass.new()
	scenario.scenario_id = "prologue"
	scenario.display_name = "The Hollow Prologue"
	scenario.party = party
	scenario.encounter_entries = []

	var use_case := LoadScenarioEncounterUseCaseClass.new()

	var result: Dictionary = use_case.execute(scenario, "prologue")

	assert_false(result.get("ok", true), "execute() against an empty encounter_entries array must return ok:false")
	assert_eq(
		result.get("error_code", ""), "ENCOUNTER_NOT_FOUND",
		"an empty encounter_entries array must collapse to the SAME error_code as an unmatched id: ENCOUNTER_NOT_FOUND"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: COMBATANT_BUILD_FAILED -- propagated verbatim, no partial payload
# ══════════════════════════════════════════════════════════════════════════════

func test_combatant_build_failure_returns_combatant_build_failed_with_no_partial_payload() -> void:
	var scenario := _build_prologue_shaped_scenario(ENCOUNTER_ID)
	var use_case := LoadScenarioEncounterUseCaseClass.new()
	var failing_factory := AlwaysFailingCombatantFactory.new()

	var result: Dictionary = use_case.execute(scenario, ENCOUNTER_ID, {"combatant_factory": failing_factory})

	assert_false(result.get("ok", true), "a failing combatant_factory must produce ok:false")
	assert_eq(
		result.get("error_code", ""), "COMBATANT_BUILD_FAILED",
		"a failing combatant_factory must produce error_code:COMBATANT_BUILD_FAILED"
	)

	for leaking_key in [
		"party_combatants", "enemy_combatants", "encounter_resource",
		"tiles", "party_start_positions", "enemy_start_positions"
	]:
		assert_false(
			result.has(leaking_key),
			"a COMBATANT_BUILD_FAILED result must carry no partial success payload; found leaking key '%s'" % leaking_key
		)

	assert_eq(result.size(), 2, "a COMBATANT_BUILD_FAILED result must contain ONLY {ok, error_code} -- nothing else")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5: static review -- no Presentation imports, no trigger logic
# ══════════════════════════════════════════════════════════════════════════════

func test_use_case_gd_has_no_presentation_imports_or_trigger_evaluation_logic() -> void:
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

	for trigger_symbol in ["TriggerResource", "trigger_type", "trigger_hexes", "evaluate_trigger", "fire_trigger", ".trigger"]:
		assert_false(
			content.contains(trigger_symbol),
			"load_scenario_encounter_use_case.gd must contain no trigger-evaluation/firing logic (RISK-001/RISK-008); found '%s'" % trigger_symbol
		)

	assert_true(content.contains("extends RefCounted"), "load_scenario_encounter_use_case.gd must extend RefCounted")
