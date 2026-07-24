extends GutTest
## tests/gut/test_combat_session_factory.gd — FEAT-003 (US-001; FR-008;
## ADR-004/ADR-005).
##
## GUT suite for core/application/combat_session_factory.gd's
## CombatSessionFactory — the entry-point-adjacent factory MainScene._ready()
## (the composition root) delegates its resource-loading + party/enemy/
## hex_combatants assembly to, per the design notes' architecture section
## ("MainScene._ready() now delegates scene construction to
## CombatSessionFactory.build()").
##
## test_criteria satisfied:
##   1. build(deps) returns {round_session, party, enemies, hex_combatants}
##      given valid deps and a fake CombatResourceLoaderPort.
##   2. build(deps) with an invalid/missing resource path returns {} with no
##      exceptions (ADR-005) — verified via the observable return-value
##      contract rather than GUT's push_error capture, which is unreliable
##      on this project's pinned Godot 4.3 engine (see e.g.
##      tests/unit/presentation/test_main_scene_load_encounter_from_scenario.gd's
##      identical note) — push_error() is still fired at the call site
##      itself (see combat_session_factory.gd's own source).
##   3. (Verified in tests/unit/test_main_scene_entry_point.gd-adjacent
##      review, not here): MainScene._ready() line count after extraction.
##   4. Full GUT suite passes with no regression vs. FEAT-001 baseline
##      (verified by running the whole suite, not scoped to this file).

const CombatSessionFactoryClass = preload("res://core/application/combat_session_factory.gd")
const CombatResourceLoaderPortClass = preload("res://core/application/ports/combat_resource_loader_port.gd")
const EncounterResourceClass = preload("res://data/encounters/encounter_resource.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const FIXTURE_ENCOUNTER_PATH: String = "res://data/encounters/prologue_encounter.tres"
const MISSING_ENCOUNTER_PATH: String = "res://data/encounters/does_not_exist_feat003.tres"


## FakeCombatResourceLoaderPort — implements CombatResourceLoaderPort by
## returning a canned in-memory EncounterResource for `known_path`, and null
## for anything else — mirroring GdResourceLoaderAdapter's documented
## null-on-unresolvable contract without touching the real filesystem.
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


## FakeEncounterRepository — duck-typed encounter_repository collaborator
## (load_combatants(path) -> Array), returning one Combatant per party/enemy
## slot with a deterministic hex_coord/combatant_id, mirroring
## infrastructure/resource_encounter_repository.gd's ResourceEncounterRepository
## shape without touching the real filesystem.
class FakeEncounterRepository:
	var combatants_to_return: Array

	func _init(p_combatants_to_return: Array) -> void:
		combatants_to_return = p_combatants_to_return

	func load_combatants(_path: String) -> Array:
		return combatants_to_return


## FakeCombatantFactory — duck-typed combatant_factory collaborator
## (build_party_combatant/build_enemy_combatant), returning a minimal
## well-formed combatant dict per call, or (when `fail_enemy_build` is set)
## the {"error": ERR_...} shape CombatantFactory.build_enemy_combatant()
## returns on a fail-fast validation failure.
class FakeCombatantFactory:
	var fail_enemy_build: bool = false

	func build_party_combatant(_path: String, hex_coord, combatant_id: String) -> Dictionary:
		return {
			"combatant_id": combatant_id,
			"name": "Fake Party Member",
			"team": "Player",
			"hex_coord": hex_coord,
			"hp_current": 10,
			"hp_max": 10,
		}

	func build_enemy_combatant(_path: String, hex_coord, combatant_id: String) -> Dictionary:
		if fail_enemy_build:
			return {"error": "ERR_TEST_ENEMY_BUILD_FAILED", "enemy_path": _path}
		return {
			"combatant_id": combatant_id,
			"name": "Fake Enemy",
			"team": "Enemy",
			"hex_coord": hex_coord,
			"hp_current": 8,
			"hp_max": 8,
		}


## FakeRunRoundUseCase — duck-typed run_round_use_case collaborator
## (begin_round(round_number, party, enemies) -> RoundSession-shaped value),
## returning a canned sentinel so build()'s optional round_session-assembly
## branch is exercised without constructing a real RunRoundUseCase's full
## dependency graph (turn_order_port/ai_decision_port/etc — out of this
## factory's resource-loading-focused scope).
class FakeRunRoundUseCase:
	var round_session_to_return

	func _init(p_round_session_to_return) -> void:
		round_session_to_return = p_round_session_to_return

	func begin_round(_round_number: int, _party: Array, _enemies: Array):
		return round_session_to_return


func _fake_encounter_resource() -> EncounterResourceClass:
	var res := EncounterResourceClass.new()
	res.party_resource_paths = ["res://data/characters/fake_party_member.tres"]
	res.enemy_resource_paths = ["res://data/enemies/fake_enemy.tres"]
	return res


func _fake_hex_combatants() -> Array:
	return [
		CombatantClass.new("player_0", "Party Member", "Player", HexCoordClass.new(0, 0)),
		CombatantClass.new("enemy_0", "Enemy", "Enemy", HexCoordClass.new(1, 0)),
	]


func _valid_deps(extra: Dictionary = {}) -> Dictionary:
	var deps: Dictionary = {
		"resource_loader": FakeCombatResourceLoaderPort.new(FIXTURE_ENCOUNTER_PATH, _fake_encounter_resource()),
		"encounter_repository": FakeEncounterRepository.new(_fake_hex_combatants()),
		"combatant_factory": FakeCombatantFactory.new(),
		"encounter_path": FIXTURE_ENCOUNTER_PATH,
	}
	for key in extra:
		deps[key] = extra[key]
	return deps


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: build(deps) returns {round_session, party, enemies,
# hex_combatants} given valid deps and a fake CombatResourceLoaderPort.
# ══════════════════════════════════════════════════════════════════════════

func test_build_returns_dictionary_with_all_four_expected_keys() -> void:
	var session: Dictionary = CombatSessionFactoryClass.build(_valid_deps())

	assert_true(session.has("round_session"), "build() result must have a 'round_session' key")
	assert_true(session.has("party"), "build() result must have a 'party' key")
	assert_true(session.has("enemies"), "build() result must have a 'enemies' key")
	assert_true(session.has("hex_combatants"), "build() result must have a 'hex_combatants' key")


func test_build_assembles_one_combatant_per_party_and_enemy_resource_path() -> void:
	var session: Dictionary = CombatSessionFactoryClass.build(_valid_deps())

	assert_eq(session["party"].size(), 1, "party must contain one Combatant per party_resource_paths entry")
	assert_eq(session["enemies"].size(), 1, "enemies must contain one Combatant per enemy_resource_paths entry")
	assert_is(session["party"][0], CombatantClass, "each assembled party member must be a Combatant instance")
	assert_is(session["enemies"][0], CombatantClass, "each assembled enemy must be a Combatant instance")
	assert_eq(session["party"][0].team, "Player")
	assert_eq(session["enemies"][0].team, "Enemy")


func test_build_returns_the_hex_combatants_from_the_injected_encounter_repository() -> void:
	var hex_combatants: Array = _fake_hex_combatants()
	var session: Dictionary = CombatSessionFactoryClass.build(_valid_deps({
		"encounter_repository": FakeEncounterRepository.new(hex_combatants),
	}))

	assert_eq(session["hex_combatants"], hex_combatants,
		"hex_combatants must be exactly what the injected encounter_repository.load_combatants() returned")


func test_build_without_a_run_round_use_case_leaves_round_session_null() -> void:
	var session: Dictionary = CombatSessionFactoryClass.build(_valid_deps())

	assert_null(session["round_session"],
		"round_session must be null when deps supplies no run_round_use_case (MainScene's own _ready() " +
		"composition-root wiring at this point in FEAT-003's extraction)")


func test_build_with_a_run_round_use_case_populates_round_session() -> void:
	var fake_round_session := RefCounted.new()
	var session: Dictionary = CombatSessionFactoryClass.build(_valid_deps({
		"run_round_use_case": FakeRunRoundUseCase.new(fake_round_session),
		"round_number": 1,
	}))

	assert_same(session["round_session"], fake_round_session,
		"round_session must be whatever the injected run_round_use_case.begin_round() returned")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: build(deps) with an invalid/missing resource path returns {}
# (no exceptions, ADR-005).
# ══════════════════════════════════════════════════════════════════════════

func test_build_with_unresolvable_encounter_path_returns_empty_dictionary() -> void:
	var deps: Dictionary = _valid_deps({"encounter_path": MISSING_ENCOUNTER_PATH})

	var session: Dictionary = CombatSessionFactoryClass.build(deps)

	assert_true(session.is_empty(), "build() must return an empty Dictionary for an unresolvable resource path")


func test_build_with_missing_required_deps_key_returns_empty_dictionary_no_crash() -> void:
	var deps: Dictionary = _valid_deps()
	deps.erase("resource_loader")

	var session: Dictionary = CombatSessionFactoryClass.build(deps)

	assert_true(session.is_empty(), "build() must fail safe (empty Dictionary) when a required deps key is missing")


func test_build_with_enemy_build_failure_returns_empty_dictionary_no_crash() -> void:
	var failing_factory := FakeCombatantFactory.new()
	failing_factory.fail_enemy_build = true
	var deps: Dictionary = _valid_deps({"combatant_factory": failing_factory})

	var session: Dictionary = CombatSessionFactoryClass.build(deps)

	assert_true(session.is_empty(),
		"build() must return an empty Dictionary (not a party of half-built combatants) when the injected " +
		"combatant_factory reports a fail-fast enemy-build error")


# ══════════════════════════════════════════════════════════════════════════
# Contract type check: the port itself extends CombatResourceLoaderPort.
# ══════════════════════════════════════════════════════════════════════════

func test_fake_resource_loader_extends_combat_resource_loader_port() -> void:
	var fake := FakeCombatResourceLoaderPort.new(FIXTURE_ENCOUNTER_PATH, _fake_encounter_resource())
	assert_true(fake is CombatResourceLoaderPortClass,
		"the fake collaborator used above must genuinely satisfy the CombatResourceLoaderPort contract " +
		"(is-a, not just duck-typed) so this suite proves the real port shape, not just a lookalike")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: MainScene._ready() delegates its former inline resource-
# loading + party/enemy/hex_combatants assembly to CombatSessionFactory.
# build() -- the extracted init block this feature targets (design notes'
# architecture section). The full "MainScene._ready() ≤ 150 lines" gate is
# US-009's hard composition-root gate, reached only once every one of
# US-002..US-009's later extractions (VerbDispatchController,
# RoundFlowController, reaction/hex-choice-resolver wiring, etc.) has ALSO
# landed -- out of THIS feature's scope. What this suite verifies now is
# that FEAT-003's own slice of that reduction genuinely happened: the
# former inline resource-loading/party/enemy-construction block is gone
# from MainScene.gd's source, replaced by a single delegating call.
# ══════════════════════════════════════════════════════════════════════════

func _read_main_scene_script_source() -> String:
	var file := FileAccess.open("res://MainScene.gd", FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable")
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_main_scene_ready_delegates_to_combat_session_factory() -> void:
	var content: String = _read_main_scene_script_source()
	assert_true(
		content.contains("CombatSessionFactoryClass.build("),
		"MainScene._ready() must delegate session assembly to CombatSessionFactory.build() (FEAT-003 / US-001)"
	)


func test_main_scene_no_longer_loads_encounter_resource_inline() -> void:
	var content: String = _read_main_scene_script_source()
	assert_false(
		content.contains("ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH)"),
		"MainScene.gd must no longer call ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH) directly -- that seam now " +
		"lives ONLY behind GdResourceLoaderAdapter (ADR-005), reached via CombatSessionFactory.build()"
	)


func test_main_scene_no_longer_builds_party_and_enemies_inline() -> void:
	var content: String = _read_main_scene_script_source()
	assert_false(
		content.contains("for i in range(encounter_resource.party_resource_paths.size())"),
		"MainScene.gd must no longer construct the party Array inline -- that loop now lives inside " +
		"CombatSessionFactory.build() (FEAT-003 / US-001)"
	)
	assert_false(
		content.contains("for j in range(encounter_resource.enemy_resource_paths.size())"),
		"MainScene.gd must no longer construct the enemies Array inline -- that loop now lives inside " +
		"CombatSessionFactory.build() (FEAT-003 / US-001)"
	)
