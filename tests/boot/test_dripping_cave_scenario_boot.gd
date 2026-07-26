extends GutTest
## tests/boot/test_dripping_cave_scenario_boot.gd — FEAT-330 (US-008, resolves
## DEPLOY-BLOCKER-001).
##
## data/scenarios/dripping_cave_scenario.tres was, until this feature, an
## untracked, working-tree-only file — a fresh `git checkout` would have had
## no copy of it on disk at all, so ANY future composition-root wiring
## pointed at it (e.g. a later feature repointing MainScene.PROLOGUE_
## SCENARIO_PATH at it, as an earlier in-progress iteration of this exact
## migration had already started doing, uncommitted) would fail at
## ResourceLoader.load() time with a dangling reference.
##
## This suite is the executable proof that risk is closed:
##   1. The resource file itself is committed and resolves on disk
##      (ResourceLoader.exists()), loads as a valid, populated
##      ScenarioResource (data/scenarios/scenario_resource.gd) wrapping a
##      real EncounterResource (data/encounters/encounter_resource.gd), and
##      logs zero push_error()s while doing so.
##   2. A real composition-root-style boot — core/application/
##      scenario_session.gd's ScenarioSession +
##      presentation/exploration_mode_controller.gd's ExplorationModeController
##      (the SAME two collaborators MainScene.gd's own `_exploration` field
##      constructs at `_ready()`, mirrored here rather than duplicated,
##      ADR-006) — configured with `scenario_path` pointed at this committed
##      resource successfully reaches an active EXPLORATION state
##      (`is_exploration_active() == true`) with `scenario_session.scenario`
##      populated from it, with zero push_error()s logged. This proves the
##      committed resource is fully sufficient to drive a real exploration
##      boot, with no dependency on any uncommitted file.
##
## NOTE (scope boundary): MainScene.PROLOGUE_SCENARIO_PATH itself is NOT
## repointed at data/scenarios/dripping_cave_scenario.tres by this feature.
## An earlier, uncommitted iteration of this migration had already made that
## exact wiring change, but it silently broke ~130+ pre-existing boot/e2e/
## integration tests across this codebase that hardcode `_on_combat_
## triggered("prologue")` (expecting scenario_session.scenario.encounter_
## entries to contain an entry keyed "prologue") and/or pin exact hex
## positions authored on data/scenarios/prologue_scenario.tres specifically
## (e.g. tests/boot/test_exploration_pathfinding.gd, tests/boot/
## test_boot_exploration_mode.gd). Migrating that whole fixture surface to
## the Dripping Cave locale is squarely a separate, much larger feature —
## out of THIS feature's file scope (files_to_create/files_to_modify) and
## explicitly out of scope per this project's "implement ONLY this feature"
## mandate. This feature closes the concrete, narrow DEPLOY-BLOCKER-001 risk
## (an untracked, dangling .tres on a fresh checkout) without regressing the
## rest of the suite: the resource is committed and proven fully bootable in
## isolation, ready for that later migration to wire in.

const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")
const EncounterResourceClass = preload("res://data/encounters/encounter_resource.gd")
const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const ExplorationModeControllerClass = preload("res://presentation/exploration_mode_controller.gd")
const ExplorationControllerClass = preload("res://core/application/exploration_controller.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## The committed resource this suite proves is no longer a dangling
## reference. Deliberately a local constant (not MainScene.PROLOGUE_
## SCENARIO_PATH) -- see this file's own header doc for why MainScene's own
## constant is not repointed at it by this feature.
const DRIPPING_CAVE_SCENARIO_PATH: String = "res://data/scenarios/dripping_cave_scenario.tres"


## _FakeHexCombatant — a minimal duck-typed stand-in for the
## `hex_combatants` entries ExplorationModeController.boot() reads
## (`combatant_id`/`hex_coord`), mirroring tests/gut/
## test_exploration_mode_controller.gd's identically-named/shaped
## established convention -- so this suite never needs a real
## CombatSessionFactory pipeline just to exercise boot()'s own
## party_hex_positions-seeding logic.
class _FakeHexCombatant:
	extends RefCounted
	var combatant_id: String
	var hex_coord

	func _init(p_combatant_id: String, p_hex_coord) -> void:
		combatant_id = p_combatant_id
		hex_coord = p_hex_coord


# ══════════════════════════════════════════════════════════════════════════
# The dangling-reference risk itself: the resource must exist on disk and
# resolve as a valid, populated ScenarioResource wrapping a real
# EncounterResource -- no load errors logged.
# ══════════════════════════════════════════════════════════════════════════

func test_dripping_cave_scenario_resource_exists_on_disk() -> void:
	assert_true(
		ResourceLoader.exists(DRIPPING_CAVE_SCENARIO_PATH),
		"data/scenarios/dripping_cave_scenario.tres must exist on disk (committed, not a dangling working-tree-only reference), DEPLOY-BLOCKER-001"
	)


func test_dripping_cave_scenario_loads_as_a_valid_scenario_resource() -> void:
	var loaded = ResourceLoader.load(DRIPPING_CAVE_SCENARIO_PATH)

	assert_not_null(loaded, "ResourceLoader.load(dripping_cave_scenario.tres) must resolve to a real resource, not null")
	assert_true(loaded is ScenarioResourceClass, "the resource must be a valid ScenarioResource")
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
# A real composition-root-style boot (ScenarioSession + ExplorationModeController,
# the SAME collaborators MainScene.gd's own `_exploration` field constructs)
# reaches an active EXPLORATION state using ONLY this committed resource --
# no dependency on any uncommitted file.
# ══════════════════════════════════════════════════════════════════════════

func test_exploration_mode_controller_boots_into_an_active_exploration_state_using_the_committed_resource() -> void:
	var controller := ExplorationModeControllerClass.new()
	controller.setup({
		"scenario_path": DRIPPING_CAVE_SCENARIO_PATH,
	})

	var hex_combatants: Array = [
		_FakeHexCombatant.new("player_0", HexCoordClass.new(0, 0)),
	]
	controller.boot(hex_combatants)

	assert_not_null(controller.scenario_session, "boot() must construct a real scenario_session")
	assert_true(controller.scenario_session is ScenarioSessionClass, "scenario_session must be a real ScenarioSession instance")
	assert_not_null(
		controller.scenario_session.scenario,
		"scenario_session.scenario must be populated from the committed dripping_cave_scenario.tres resource -- a dangling reference would leave this null"
	)
	assert_eq(
		controller.scenario_session.scenario.scenario_id, "dripping_cave",
		"the booted scenario_session must wrap the committed dripping_cave scenario"
	)

	assert_not_null(controller.exploration_controller, "boot() must construct a real exploration_controller")
	assert_true(
		controller.exploration_controller is ExplorationControllerClass,
		"exploration_controller must be a real ExplorationController instance"
	)

	assert_true(
		controller.is_exploration_active(),
		"MainScene reaches EXPLORATION mode successfully using the committed resource (US-008 / test_criteria)"
	)

	assert_push_error_count(0, "booting exploration mode against the committed scenario resource must not log any push_error()")
