extends GutTest
## tests/unit/core/application/test_encounter_spawner_weapon_overrides.gd
##
## GUT test suite for FEAT-007 (US-007 / FR-006, ADR-005/ADR-006): wires
## EncounterResource.weapon_path_overrides (added by FEAT-004) through to
## every spawn-orchestration call site that iterates
## encounter_resource.enemy_resource_paths and invokes
## CombatantFactory.build_enemy_combatant() -- namely
## core/application/combat_session_factory.gd's CombatSessionFactory.build()
## (the MainScene._ready() boot path, exercised end-to-end by
## tests/integration/test_mainscene_skeleton_defense_eligibility.gd) and
## core/application/use_cases/load_scenario_encounter_use_case.gd's
## LoadScenarioEncounterUseCase.execute() (the exploration->combat handoff
## path).
##
## Per the design notes' api_contracts "Encounter spawn-slot override
## lookup" contract: for spawn slot i, the override passed as
## build_enemy_combatant()'s 4th argument is
## encounter.weapon_path_overrides[i] when i < weapon_path_overrides.size()
## AND that entry is non-empty, else "" -- never an index-out-of-range
## error, regardless of how weapon_path_overrides.size() relates to
## enemy_resource_paths.size().
##
## RISK-007 mitigation: this suite exercises the exact slot/override index
## math directly (via a recording combatant_factory double), rather than
## relying solely on the mainscene smoke test (which only proves ONE
## specific fixture -- zero overrides -- works end-to-end).
##
## test_criteria covered:
##   1. slot i with weapon_path_overrides.size() <= i -> override == ''.
##   2. slot i with a non-empty weapon_path_overrides[i] -> that exact
##      string is passed as the 4th argument.
##   3. zero overrides -> combatant output identical to pre-refactor
##      baseline (i.e. build_enemy_combatant is invoked with override == ''
##      for every enemy, same as before this feature existed).
##   4. more enemy slots than override entries -> correct per-slot
##      defaulting, no index-out-of-range errors/crashes.
##   5. test_mainscene_skeleton_defense_eligibility.gd continues to pass
##      unmodified against this wiring (verified by running the full suite,
##      not re-asserted in this file).

const CombatSessionFactoryClass = preload("res://core/application/combat_session_factory.gd")
const CombatResourceLoaderPortClass = preload("res://core/application/ports/combat_resource_loader_port.gd")
const LoadScenarioEncounterUseCaseClass = preload("res://core/application/use_cases/load_scenario_encounter_use_case.gd")
const EncounterResourceClass = preload("res://data/encounters/encounter_resource.gd")
const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")
const ScenarioEncounterEntryResourceClass = preload("res://data/scenarios/scenario_encounter_entry_resource.gd")
const PartyResourceClass = preload("res://data/characters/party_resource.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const FIXTURE_ENCOUNTER_PATH: String = "res://data/encounters/fake_weapon_override_encounter_feat007.tres"


## RecordingCombatantFactory -- a duck-typed combatant_factory double that
## records every build_enemy_combatant() call's (enemy_path, combatant_id,
## weapon_path_override) tuple, in call order, so this suite can assert the
## EXACT override value each spawn slot resolved to, independent of
## whichever call site (CombatSessionFactory / LoadScenarioEncounterUseCase)
## is under test.
class RecordingCombatantFactory:
	extends RefCounted

	var enemy_calls: Array = []

	func build_party_combatant(_path: String, hex_coord, combatant_id: String = "") -> Dictionary:
		return {
			"combatant_id": combatant_id,
			"name": "Fake Party Member",
			"team": "Player",
			"hex_coord": hex_coord,
			"hp_current": 10,
			"hp_max": 10,
		}

	func build_enemy_combatant(enemy_path: String, hex_coord, combatant_id: String = "", weapon_path_override: String = "") -> Dictionary:
		enemy_calls.append({
			"enemy_path": enemy_path,
			"hex_coord": hex_coord,
			"combatant_id": combatant_id,
			"weapon_path_override": weapon_path_override,
		})
		return {
			"combatant_id": combatant_id,
			"name": "Fake Enemy",
			"team": "Enemy",
			"hex_coord": hex_coord,
			"hp_current": 8,
			"hp_max": 8,
		}


## FakeCombatResourceLoaderPort -- mirrors tests/gut/test_combat_session_factory.gd's
## own fixture double: returns a canned in-memory EncounterResource for
## `known_path`, null otherwise.
class FakeCombatResourceLoaderPort:
	extends "res://core/application/ports/combat_resource_loader_port.gd"

	var known_path: String
	var resource_to_return: Resource

	func _init(p_known_path: String, p_resource_to_return: Resource) -> void:
		known_path = p_known_path
		resource_to_return = p_resource_to_return

	func load_resource(path: String):
		if path == known_path:
			return resource_to_return
		return null


## FakeEncounterRepository -- duck-typed encounter_repository collaborator
## (load_combatants(path) -> Array), returning one Combatant per party/enemy
## slot, mirroring tests/gut/test_combat_session_factory.gd's own fixture.
class FakeEncounterRepository:
	var combatants_to_return: Array

	func _init(p_combatants_to_return: Array) -> void:
		combatants_to_return = p_combatants_to_return

	func load_combatants(_path: String) -> Array:
		return combatants_to_return


func _encounter_resource(enemy_paths: Array, weapon_overrides: Array) -> EncounterResourceClass:
	var res := EncounterResourceClass.new()
	res.party_resource_paths = ["res://data/characters/fake_party_member.tres"]
	res.enemy_resource_paths = enemy_paths
	# EncounterResource.weapon_path_overrides is typed Array[String] -- an
	# untyped Array literal (even an empty one) cannot be assigned directly
	# in Godot 4.3's strict typed-array runtime check, so it must be
	# rebuilt into an explicitly-typed Array[String] first.
	var typed_overrides: Array[String] = []
	for entry in weapon_overrides:
		typed_overrides.append(entry)
	res.weapon_path_overrides = typed_overrides
	return res


func _hex_combatants_for(enemy_count: int) -> Array:
	var combatants: Array = [
		CombatantClass.new("player_0", "Party Member", "Player", HexCoordClass.new(0, 0))
	]
	for i in range(enemy_count):
		combatants.append(CombatantClass.new("enemy_%d" % i, "Enemy %d" % i, "Enemy", HexCoordClass.new(i + 1, 0)))
	return combatants


# ══════════════════════════════════════════════════════════════════════════
# CombatSessionFactory.build() (core/application/combat_session_factory.gd)
# ══════════════════════════════════════════════════════════════════════════

func _build_via_combat_session_factory(enemy_paths: Array, weapon_overrides: Array) -> RecordingCombatantFactory:
	var encounter_resource := _encounter_resource(enemy_paths, weapon_overrides)
	var factory := RecordingCombatantFactory.new()
	var deps: Dictionary = {
		"resource_loader": FakeCombatResourceLoaderPort.new(FIXTURE_ENCOUNTER_PATH, encounter_resource),
		"encounter_repository": FakeEncounterRepository.new(_hex_combatants_for(enemy_paths.size())),
		"combatant_factory": factory,
		"encounter_path": FIXTURE_ENCOUNTER_PATH,
	}
	var session: Dictionary = CombatSessionFactoryClass.build(deps)
	assert_false(session.is_empty(), "build() must succeed against this fixture")
	return factory


func test_combat_session_factory_slot_beyond_overrides_size_passes_empty_override() -> void:
	var factory := _build_via_combat_session_factory(
		["res://data/enemies/fake_enemy.tres"],
		[]  # weapon_path_overrides shorter than enemy_resource_paths
	)

	assert_eq(factory.enemy_calls.size(), 1)
	assert_eq(factory.enemy_calls[0]["weapon_path_override"], "",
		"slot 0 must resolve to '' when weapon_path_overrides.size() <= 0")


func test_combat_session_factory_slot_with_non_empty_override_passes_exact_string() -> void:
	var factory := _build_via_combat_session_factory(
		["res://data/enemies/fake_enemy.tres"],
		["res://data/weapons/arming_sword.tres"]
	)

	assert_eq(factory.enemy_calls.size(), 1)
	assert_eq(factory.enemy_calls[0]["weapon_path_override"], "res://data/weapons/arming_sword.tres",
		"slot 0's non-empty override must be passed VERBATIM as the 4th argument")


func test_combat_session_factory_zero_overrides_matches_pre_refactor_baseline() -> void:
	var factory := _build_via_combat_session_factory(
		["res://data/enemies/fake_enemy.tres", "res://data/enemies/fake_enemy.tres"],
		[]
	)

	assert_eq(factory.enemy_calls.size(), 2)
	for call in factory.enemy_calls:
		assert_eq(call["weapon_path_override"], "",
			"with an encounter authoring NO overrides at all, every enemy build call must resolve override='' " +
			"-- identical to the pre-FEAT-007 call shape (no 4th argument supplied)")


func test_combat_session_factory_more_enemy_slots_than_overrides_defaults_per_slot_no_crash() -> void:
	var factory := _build_via_combat_session_factory(
		[
			"res://data/enemies/fake_enemy.tres",
			"res://data/enemies/fake_enemy.tres",
			"res://data/enemies/fake_enemy.tres",
		],
		["res://data/weapons/arming_sword.tres"]  # only slot 0 has an override authored
	)

	assert_eq(factory.enemy_calls.size(), 3, "no index-out-of-range crash for the two extra enemy slots")
	assert_eq(factory.enemy_calls[0]["weapon_path_override"], "res://data/weapons/arming_sword.tres",
		"slot 0 has an authored override")
	assert_eq(factory.enemy_calls[1]["weapon_path_override"], "", "slot 1 has no authored override -> ''")
	assert_eq(factory.enemy_calls[2]["weapon_path_override"], "", "slot 2 has no authored override -> ''")


# ══════════════════════════════════════════════════════════════════════════
# LoadScenarioEncounterUseCase.execute()
# (core/application/use_cases/load_scenario_encounter_use_case.gd)
# ══════════════════════════════════════════════════════════════════════════

func _scenario_for(enemy_paths: Array, weapon_overrides: Array) -> ScenarioResourceClass:
	var encounter_resource := _encounter_resource(enemy_paths, weapon_overrides)
	encounter_resource.party_hex_positions = [{"q": 0, "r": 0}]
	encounter_resource.enemy_hex_positions = []
	for i in range(enemy_paths.size()):
		encounter_resource.enemy_hex_positions.append({"q": i + 1, "r": 0})

	var entry := ScenarioEncounterEntryResourceClass.new()
	entry.encounter_id = "feat007_fixture"
	entry.encounter = encounter_resource

	var party := PartyResourceClass.new()
	party.character_resource_paths = ["res://data/characters/fake_party_member.tres"]

	var scenario := ScenarioResourceClass.new()
	scenario.scenario_id = "feat007_fixture_scenario"
	scenario.party = party
	scenario.encounter_entries = [entry]
	return scenario


func _execute_use_case(enemy_paths: Array, weapon_overrides: Array) -> RecordingCombatantFactory:
	var scenario := _scenario_for(enemy_paths, weapon_overrides)
	var factory := RecordingCombatantFactory.new()
	var use_case := LoadScenarioEncounterUseCaseClass.new()

	var result: Dictionary = use_case.execute(scenario, "feat007_fixture", {"combatant_factory": factory})
	assert_true(result.get("ok", false), "execute() must succeed against this fixture")
	return factory


func test_load_scenario_encounter_use_case_slot_beyond_overrides_size_passes_empty_override() -> void:
	var factory := _execute_use_case(["res://data/enemies/fake_enemy.tres"], [])

	assert_eq(factory.enemy_calls.size(), 1)
	assert_eq(factory.enemy_calls[0]["weapon_path_override"], "",
		"slot 0 must resolve to '' when weapon_path_overrides.size() <= 0")


func test_load_scenario_encounter_use_case_slot_with_non_empty_override_passes_exact_string() -> void:
	var factory := _execute_use_case(
		["res://data/enemies/fake_enemy.tres"],
		["res://data/weapons/arming_sword.tres"]
	)

	assert_eq(factory.enemy_calls.size(), 1)
	assert_eq(factory.enemy_calls[0]["weapon_path_override"], "res://data/weapons/arming_sword.tres",
		"slot 0's non-empty override must be passed VERBATIM as the 4th argument")


func test_load_scenario_encounter_use_case_zero_overrides_matches_pre_refactor_baseline() -> void:
	var factory := _execute_use_case(
		["res://data/enemies/fake_enemy.tres", "res://data/enemies/fake_enemy.tres"],
		[]
	)

	assert_eq(factory.enemy_calls.size(), 2)
	for call in factory.enemy_calls:
		assert_eq(call["weapon_path_override"], "",
			"with an encounter authoring NO overrides at all, every enemy build call must resolve override=''")


func test_load_scenario_encounter_use_case_more_enemy_slots_than_overrides_defaults_per_slot_no_crash() -> void:
	var factory := _execute_use_case(
		[
			"res://data/enemies/fake_enemy.tres",
			"res://data/enemies/fake_enemy.tres",
			"res://data/enemies/fake_enemy.tres",
		],
		["res://data/weapons/arming_sword.tres"]
	)

	assert_eq(factory.enemy_calls.size(), 3, "no index-out-of-range crash for the two extra enemy slots")
	assert_eq(factory.enemy_calls[0]["weapon_path_override"], "res://data/weapons/arming_sword.tres")
	assert_eq(factory.enemy_calls[1]["weapon_path_override"], "")
	assert_eq(factory.enemy_calls[2]["weapon_path_override"], "")
