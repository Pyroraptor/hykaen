extends GutTest
## tests/integration/test_steel_thread_scenario_boot_e2e.gd
##
## FEAT-310 (US-010; NFR-004, NFR-001, NFR-002): the FINAL steel-thread smoke
## test for the scenario-boot slice this iteration built (FEAT-008/009/010).
## Exercises MainScene.load_encounter_from_scenario(prologue_scenario.tres,
## 'prologue') FOR REAL, inside the live Godot/GUT runtime, against a real,
## booted res://MainScene.tscn instance -- NO mocked/stubbed collaborator
## anywhere on the path: the real ScenarioResource is loaded via
## ResourceLoader, the real LoadScenarioEncounterUseCase (core/application/
## use_cases/load_scenario_encounter_use_case.gd) drives the real, unmodified
## infrastructure/combatant_factory.gd CombatantFactory, and the resulting
## live Combatant instances are threaded through the SAME EncounterClass.new()/
## initialize() call MainScene.gd's own composition root uses everywhere else
## (ADR-006 — no test-only bypass).
##
## Contrasts with tests/unit/presentation/
## test_main_scene_load_encounter_from_scenario.gd (FEAT-010's own unit
## suite): that file drives `MainSceneScript.new()` directly (never added to
## the scene tree, so every @onready field -- hex_grid_view/status_panel_view/
## turn_controller/verb_bar_view/etc -- stays null and _ready() never runs).
## THIS file instead instantiates the real, shipped res://MainScene.tscn
## PackedScene (mirroring tests/integration/test_steel_thread_prologue_
## encounter.gd's/test_steel_thread_e2e.gd's own established
## `_boot_main_scene_with_seed()` boot-real convention) so _ready()'s FULL
## composition-root wiring (encounter_repository, random_port, event_sink,
## `_verb_registry`, every Presentation projection) has already run BEFORE
## load_encounter_from_scenario() is invoked a second time against it --
## proving the scenario-driven path composes correctly with a fully-wired,
## living MainScene, not merely a bare, disconnected instance.
##
## test_criteria satisfied:
##   1. load_encounter_from_scenario(prologue_scenario.tres, 'prologue') on a
##      real, unmocked, booted MainScene returns true --
##      test_load_encounter_from_scenario_boot_real_populates_live_combatants_and_initializes_encounter().
##   2. Post-call _party == [live Marigold Combatant, live Titus Combatant]
##      and _enemies == [live Skeleton Combatant] -- same test.
##   3. EncounterClass.initialize() has run (a real, non-null EncounterClass
##      instance with a rolled, non-empty turn order) and the round-session/
##      verb-bar/status-panel pipeline is reachable exactly as the legacy
##      _ready() path wires it -- combat is genuinely playable: rewire_session()
##      (the SAME single reusable composition-root method _ready()/
##      _on_round_over() already call, ADR-006/FEAT-006 -- never a
##      second/duplicated wiring path) is invoked to seat a real RoundSession
##      over the newly-loaded live combatants, then the real `_verb_registry`
##      STRIKE entry resolves an actual player Strike against the live
##      Skeleton --
##      test_load_encounter_from_scenario_boot_real_combat_pipeline_is_playable_via_verb_bar().
##   4. (RISK-005 mitigation) GUT reports the expected new test count for this
##      iteration's one new file (no silently-skipped file), via the SAME
##      script.get_script_method_list() reflection GUT's own
##      addons/gut/test_collector.gd._populate_tests() uses internally to
##      discover tests -- distinct from the KNOWN, pre-existing,
##      already-documented tests/test_encounter_round_loop.gd top-level parse
##      failure (which causes THAT file, not this one, to be silently excluded
##      from every GUT run/count) --
##      test_this_suite_loads_cleanly_and_registers_the_expected_gut_test_count().

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const PROLOGUE_ENCOUNTER_ID: String = "prologue"
const THIS_SUITE_PATH: String = "res://tests/integration/test_steel_thread_scenario_boot_e2e.gd"

## The pre-existing, already-documented parse-failure fixture this feature's
## test-count check must stay distinct from (see the file-level doc's
## criterion 4). Not exercised/asserted against here -- referenced only so a
## reader (or a future static audit) can see the two are deliberately
## different files, never conflated.
const KNOWN_PREEXISTING_PARSE_FAILURE_PATH: String = "res://tests/test_encounter_round_loop.gd"

const CombatantClass = preload("res://core/domain/combatant.gd")
const EncounterClass = preload("res://core/combat/encounter.gd")

## FEAT-009 (FR-007/ADR-002): seed CurrentGameState.data via
## NewGameFactory.create_prologue_state() before every boot -- explicit,
## rather than relying on MainScene's own ADR-005 never-initialized fallback
## -- and reset it afterward so this suite never leaks state into another
## test file sharing the same autoload singleton across the one GUT process.
func before_each() -> void:
	CurrentGameState.data = NewGameFactoryClass.create_prologue_state()


func after_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


## This suite defines exactly 3 test_ methods below. A mismatch here would
## mean GUT silently discovered MORE or FEWER tests than this file actually
## declares -- e.g. a parse error truncating the script, or a future edit
## adding a test without updating this constant -- which is precisely the
## silent-skip failure mode RISK-005 flags (mirrored by the KNOWN pre-existing
## tests/test_encounter_round_loop.gd issue, criterion 4 above).
const EXPECTED_TEST_METHOD_COUNT: int = 3


## _boot_main_scene_with_seed(seed_value) -> Node -- boots the REAL
## res://MainScene.tscn composition root (the same entry point project.godot's
## run/main_scene points at) with a pinned `seed_override` (FEAT-002/003 /
## ADR-004 in-process injection contract) so this suite's initiative-order
## fixture assumption (Titus acts first, per prologue_encounter.tres' seed=42
## roll) is reproducible. Mirrors tests/integration/
## test_steel_thread_prologue_encounter.gd's identically-named helper exactly.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1 & 2 & 3 (partial) — boot-real happy path: true return, live
# Marigold+Titus party / live Skeleton enemy, EncounterClass.initialize() ran.
# ══════════════════════════════════════════════════════════════════════════

func test_load_encounter_from_scenario_boot_real_populates_live_combatants_and_initializes_encounter() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	# Fixture assumption: _ready()'s own hardcoded boot path has already run
	# against this real, live instance BEFORE load_encounter_from_scenario()
	# is ever called -- proving the scenario-driven path is exercised against
	# a fully-composed MainScene, not a bare `.new()`.
	assert_not_null(instance.encounter, "fixture assumption: the legacy _ready() boot path must have already built an Encounter before load_encounter_from_scenario() is called")
	assert_not_null(instance._verb_registry, "fixture assumption: the legacy _ready() boot path must have already built the real _verb_registry")

	var scenario = ResourceLoader.load(NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST)
	assert_not_null(scenario, "fixture assumption: prologue_scenario.tres must load as a real ScenarioResource")

	var ok: bool = instance.load_encounter_from_scenario(scenario, PROLOGUE_ENCOUNTER_ID)
	assert_true(ok, "load_encounter_from_scenario() must return true for the real, unmocked prologue_scenario.tres fixture on a fully-booted MainScene")

	# ── Criterion 2: _party == [live Marigold, live Titus], _enemies == [live Skeleton]. ──
	assert_eq(instance._party.size(), 2, "_party must contain exactly 2 live combatants (Titus + Marigold)")
	var party_by_name: Dictionary = {}
	for combatant in instance._party:
		assert_is(combatant, CombatantClass, "every _party entry must be a live Combatant instance, not a Dictionary")
		party_by_name[combatant.name] = combatant
	assert_true(party_by_name.has("Titus"), "_party must contain a live Titus Combatant")
	assert_true(party_by_name.has("Marigold"), "_party must contain a live Marigold Combatant")
	assert_false(party_by_name["Titus"].is_enemy, "the live Titus Combatant must be party-aligned")
	assert_false(party_by_name["Marigold"].is_enemy, "the live Marigold Combatant must be party-aligned")

	assert_eq(instance._enemies.size(), 1, "_enemies must contain exactly 1 live combatant (Skeleton)")
	if instance._enemies.size() == 1:
		assert_is(instance._enemies[0], CombatantClass, "the _enemies entry must be a live Combatant instance, not a Dictionary")
		assert_eq(instance._enemies[0].name, "Skeleton", "_enemies must contain a live Skeleton Combatant")
		assert_true(instance._enemies[0].is_enemy, "the live Skeleton Combatant must be enemy-aligned")

	# ── Criterion 3 (partial): EncounterClass.initialize() genuinely ran --
	# a real, non-null EncounterClass instance with a rolled, non-empty turn
	# order (the SAME EncounterClass.new()/initialize() call path _ready()
	# itself uses, reused verbatim by load_encounter_from_scenario()). ──────
	assert_is(instance.encounter, EncounterClass, "encounter must be a real EncounterClass instance after load_encounter_from_scenario()")
	assert_true(
		instance.encounter._turn_order.size() > 0,
		"EncounterClass.initialize() must have run against the scenario-loaded combatants (a non-empty turn order was rolled)"
	)
	assert_eq(
		instance.encounter._turn_order.size(), instance._party.size() + instance._enemies.size(),
		"the rolled turn order must include every scenario-loaded combatant exactly once"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (playability) — the round-session/verb-bar/status-panel
# pipeline is reachable exactly as the legacy path wires it: rewire_session()
# seats a real RoundSession over the newly-loaded live combatants, and the
# real `_verb_registry` STRIKE entry resolves an actual Strike against them.
# ══════════════════════════════════════════════════════════════════════════

func test_load_encounter_from_scenario_boot_real_combat_pipeline_is_playable_via_verb_bar() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var scenario = ResourceLoader.load(NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST)
	assert_not_null(scenario, "fixture assumption: prologue_scenario.tres must load as a real ScenarioResource")

	var ok: bool = instance.load_encounter_from_scenario(scenario, PROLOGUE_ENCOUNTER_ID)
	assert_true(ok, "fixture assumption: load_encounter_from_scenario() must succeed before this criterion can be exercised")

	# rewire_session() -- the SAME single reusable composition-root method
	# _ready() (for round 1) and _on_round_over() (for every automatic round
	# continuation, FEAT-006/ADR-012) already call -- reused verbatim here
	# to seat a real RoundSession/ActionEconomy set over the FRESH live
	# combatants load_encounter_from_scenario() just assigned to
	# `_party`/`_enemies`. No new/duplicated wiring is introduced by this test
	# (ADR-002/CR-001 guardrail); this is the production call path a future
	# scenario-boot menu flow would drive too.
	instance.rewire_session()

	assert_not_null(instance.round_session, "rewire_session() must seat a real RoundSession over the scenario-loaded combatants")
	assert_false(instance.round_session.is_round_over(), "the freshly-seated RoundSession must not already be over with no player input")
	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption (seed=42, prologue_encounter.tres' hex layout): the first actor must be a living player combatant (Titus)"
	)

	# ── Drive the REAL `_verb_registry` STRIKE entry -- no test-local
	# resolver, no mocked port -- against the scenario-loaded live Skeleton. ──
	var selection: Dictionary = instance._verb_registry.enter_selection("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(
		target_ids.size() > 0,
		"the real _verb_registry STRIKE entry must be configured with at least one in-reach target for the active player combatant once round_session is seated over the scenario-loaded combatants"
	)
	var target_id: String = target_ids[0]

	var result: Dictionary = instance._verb_registry.execute("STRIKE", target_id)
	assert_true(result.get("ok", false), "the player's Strike against the scenario-loaded, in-reach target must resolve successfully through the real _verb_registry STRIKE entry")
	assert_true(result.get("resolved", false), "the Strike must be marked resolved by MainScene's real, wired resolve_action_use_case -- proving combat is genuinely playable against the scenario-loaded combatants")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (RISK-005 mitigation) — GUT reports the expected new test count
# for this iteration's one new file; distinct from the known pre-existing
# tests/test_encounter_round_loop.gd parse-error silent-skip issue.
# ══════════════════════════════════════════════════════════════════════════

func test_this_suite_loads_cleanly_and_registers_the_expected_gut_test_count() -> void:
	# ResourceLoader.load() returning a real, non-null GDScript here is
	# itself the affirmative proof this file does NOT suffer the same
	# top-level-parse-failure defect class documented for
	# KNOWN_PREEXISTING_PARSE_FAILURE_PATH (tests/test_encounter_round_loop.gd)
	# -- a script with a genuine parse error fails to load entirely (GUT's
	# own addons/gut/test_collector.gd._populate_tests() prints
	# "!!! <path> could not be loaded" and returns false, silently excluding
	# that file from every discovered-test count), so this suite could never
	# reach the assertions below at all if it were similarly broken.
	var script := ResourceLoader.load(THIS_SUITE_PATH) as GDScript
	assert_not_null(script, "this suite's own file must load cleanly under GUT (RISK-005: a parse error here would leave the whole file silently skipped, exactly like the known pre-existing %s issue)" % KNOWN_PREEXISTING_PARSE_FAILURE_PATH)
	if script == null:
		return

	# Mirrors addons/gut/test_collector.gd's OWN _populate_tests() discovery
	# algorithm exactly: script.get_script_method_list(), filtered to names
	# beginning with the "test_" prefix -- this is not a reimplementation of
	# a DIFFERENT counting strategy, it is the SAME mechanism GUT itself uses
	# to decide what counts as a test, applied here to this file's own script
	# for a self-verifying regression guard.
	var discovered_test_names: Array = []
	for method in script.get_script_method_list():
		var method_name: String = method.get("name", "")
		if method_name.begins_with("test_"):
			discovered_test_names.append(method_name)

	assert_eq(
		discovered_test_names.size(), EXPECTED_TEST_METHOD_COUNT,
		"this iteration's new integration test file must register exactly %d test_ methods with GUT (got %d: %s) -- a mismatch would indicate a silently-skipped/truncated test, the exact failure mode RISK-005 flags" % [EXPECTED_TEST_METHOD_COUNT, discovered_test_names.size(), str(discovered_test_names)]
	)
	assert_true(
		discovered_test_names.has("test_load_encounter_from_scenario_boot_real_populates_live_combatants_and_initializes_encounter"),
		"GUT must discover this file's happy-path boot-real test"
	)
	assert_true(
		discovered_test_names.has("test_load_encounter_from_scenario_boot_real_combat_pipeline_is_playable_via_verb_bar"),
		"GUT must discover this file's playability boot-real test"
	)
	assert_true(
		discovered_test_names.has("test_this_suite_loads_cleanly_and_registers_the_expected_gut_test_count"),
		"GUT must discover this self-verifying test-count check itself"
	)
