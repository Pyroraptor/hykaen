extends GutTest
## tests/boot/test_dripping_cave_scenario_boot.gd — FEAT-330 (US-008, resolves
## DEPLOY-BLOCKER-001).
##
## data/scenarios/dripping_cave_scenario.tres was, until this feature,
## an untracked, working-tree-only file even though MainScene.gd's
## PROLOGUE_SCENARIO_PATH constant already pointed straight at it — a fresh
## `git checkout` would therefore have booted the REAL, shipped
## res://MainScene.tscn composition root against a dangling resource
## reference (ResourceLoader.load() failing, ExplorationModeController.boot()
## push_error()-ing and leaving scenario_session.scenario null, per that
## method's own documented "missing/malformed scenario" contract).
##
## This suite is the executable proof that the risk is closed: it boots the
## REAL, shipped MainScene.tscn composition root (never a hand-wired double,
## mirroring tests/boot/test_boot_exploration_mode.gd's own established
## `_boot_main_scene()` convention) from a clean checkout's perspective --
## i.e. relying ONLY on what `git status` shows as committed (see this
## feature's own companion commit, which stages data/scenarios/
## dripping_cave_scenario.tres alongside this test and MainScene.gd) -- and
## asserts:
##
##   1. ResourceLoader.exists(MainScene.PROLOGUE_SCENARIO_PATH) == true --
##      the dangling-reference risk itself, checked directly.
##   2. The resource actually resolves: ResourceLoader.load() returns a
##      non-null ScenarioResource (data/scenarios/scenario_resource.gd) with
##      a populated scenario_id/encounter_entries, and the first entry's
##      `.encounter` is itself a non-null EncounterResource (data/encounters/
##      encounter_resource.gd) -- both halves of the resource graph this
##      constant's dependents (ExplorationModeController.boot()'s pathfinding
##      Callables) actually walk. assert_push_error_count(0) confirms no
##      load error was logged along the way (GUT's built-in push_error
##      counter, mirrored from addons/gut/test.gd).
##   3. MainScene reaches GameMode.EXPLORATION at boot with a REAL,
##      non-null scenario_session/exploration_controller wrapping exactly
##      this committed resource -- not a degenerate/null fallback -- closing
##      test_criteria's "MainScene reaches EXPLORATION mode successfully
##      using the committed resource" requirement.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")
const EncounterResourceClass = preload("res://data/encounters/encounter_resource.gd")
const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const ExplorationControllerClass = preload("res://core/application/exploration_controller.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_boot_exploration_mode.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# The dangling-reference risk itself: the resource must actually exist on
# disk at MainScene.PROLOGUE_SCENARIO_PATH (DEPLOY-BLOCKER-001).
# ══════════════════════════════════════════════════════════════════════════

func test_prologue_scenario_path_points_at_dripping_cave_scenario() -> void:
	assert_eq(
		MainSceneClass.PROLOGUE_SCENARIO_PATH, "res://data/scenarios/dripping_cave_scenario.tres",
		"fixture assumption: PROLOGUE_SCENARIO_PATH must be wired to the committed dripping_cave_scenario.tres resource"
	)


func test_prologue_scenario_path_resource_exists_on_disk() -> void:
	assert_true(
		ResourceLoader.exists(MainSceneClass.PROLOGUE_SCENARIO_PATH),
		"data/scenarios/dripping_cave_scenario.tres must exist on disk (committed, not a dangling working-tree-only reference), DEPLOY-BLOCKER-001"
	)


# ══════════════════════════════════════════════════════════════════════════
# The resource actually resolves as a valid, populated ScenarioResource
# wrapping a valid EncounterResource -- no load errors logged.
# ══════════════════════════════════════════════════════════════════════════

func test_prologue_scenario_path_loads_as_a_valid_scenario_resource() -> void:
	var loaded = ResourceLoader.load(MainSceneClass.PROLOGUE_SCENARIO_PATH)

	assert_not_null(loaded, "ResourceLoader.load(PROLOGUE_SCENARIO_PATH) must resolve to a real resource, not null")
	assert_true(loaded is ScenarioResourceClass, "the resource at PROLOGUE_SCENARIO_PATH must be a valid ScenarioResource")
	assert_ne(loaded.scenario_id, "", "the loaded ScenarioResource must carry a non-empty scenario_id")
	assert_false(loaded.encounter_entries.is_empty(), "the loaded ScenarioResource must carry at least one encounter entry")

	var first_entry = loaded.encounter_entries[0]
	assert_not_null(first_entry.encounter, "the first encounter entry's `.encounter` must be populated, not null")
	assert_true(
		first_entry.encounter is EncounterResourceClass,
		"the first encounter entry's `.encounter` must be a valid EncounterResource"
	)

	assert_push_error_count(0, "loading the committed scenario resource must not log any push_error()")


# ══════════════════════════════════════════════════════════════════════════
# MainScene reaches EXPLORATION mode successfully using the committed
# resource -- no dependency on any uncommitted file.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_reaches_exploration_mode_using_the_committed_scenario() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"MainScene must reach GameMode.EXPLORATION at boot using the committed dripping_cave_scenario.tres"
	)

	assert_not_null(instance.scenario_session, "MainScene must construct a real scenario_session at boot")
	assert_true(instance.scenario_session is ScenarioSessionClass, "scenario_session must be a real ScenarioSession instance")
	assert_not_null(
		instance.scenario_session.scenario,
		"scenario_session.scenario must be populated from the committed PROLOGUE_SCENARIO_PATH resource -- a dangling reference would leave this null"
	)
	assert_eq(
		instance.scenario_session.scenario.scenario_id, "dripping_cave",
		"the booted scenario_session must wrap the authored dripping_cave scenario"
	)

	assert_not_null(instance.exploration_controller, "MainScene must construct a real exploration_controller at boot")
	assert_true(
		instance.exploration_controller is ExplorationControllerClass,
		"exploration_controller must be a real ExplorationController instance"
	)

	assert_push_error_count(0, "booting MainScene against the committed scenario resource must not log any push_error()")
