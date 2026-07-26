extends GutTest
## tests/boot/test_dripping_cave_scenario_boot.gd — FEAT-330 (US-008, resolves
## DEPLOY-BLOCKER-001), migrated by FEAT-336 (US-007, resolves DEF-002).
##
## data/scenarios/dripping_cave_scenario.tres was, until FEAT-330, an
## untracked, working-tree-only file — a fresh `git checkout` would have had
## no copy of it on disk at all, so ANY future composition-root wiring
## pointed at it would fail at ResourceLoader.load() time with a dangling
## reference.
##
## This suite is the executable proof that risk is closed:
##   1. The resource file itself is committed and resolves on disk
##      (ResourceLoader.exists()), loads as a valid, populated
##      ScenarioResource (data/scenarios/scenario_resource.gd) wrapping a
##      real EncounterResource (data/encounters/encounter_resource.gd), and
##      logs zero push_error()s while doing so.
##   2. A REAL, full composition-root boot — res://MainScene.tscn itself,
##      instantiated via add_child_autofree() (ADR-002's preferred test
##      pattern) with CurrentGameState.data already seeded via
##      core/application/new_game_factory.gd's
##      NewGameFactory.create_state_for_scenario(DRIPPING_CAVE_SCENARIO_PATH)
##      — reaches an active EXPLORATION state with the committed dripping
##      cave scenario/encounter wired in, with zero push_error()s logged,
##      AND (FEAT-336 / DEF-002 / FR-007 AC#3) with $HexGridView's
##      set_tile_terrain() proven to have been invoked, during that same
##      boot, once per tile in the encounter's non-empty authored `tiles`
##      array.
##
## FEAT-336 migration rationale (resolves DEF-002 from the change-deployment
## review): the PRE-migration version of criterion 2 above bypassed
## MainScene.gd entirely, hand-constructing a bare core/application/
## scenario_session.gd ScenarioSession + presentation/
## exploration_mode_controller.gd ExplorationModeController directly (the
## SAME two collaborators MainScene.gd's own `_exploration` field
## constructs at `_ready()`, "mirrored here rather than duplicated"). That
## approach never exercised MainScene.gd's own boot code at all — including
## its `_resolve_boot_scenario_path()` CurrentGameState-driven resolution —
## and, because no HexGridView was ever wired into the hand-built
## controller in that path, left FR-007 acceptance criterion #3
## (hex_grid_view.set_tile_terrain() called with a non-empty tiles set
## during boot) completely unverified for the Dripping Cave scenario. This
## migration replaces that shortcut with the SAME generic, scenario-
## agnostic MainScene.tscn boot path the prologue suite (tests/boot/
## test_main_scene_boot_characterization.gd) already exercises — seeding
## CurrentGameState.data via NewGameFactory.create_state_for_scenario()
## instead of driving anything scenario-specific inside MainScene.gd itself
## (no PROLOGUE_* constant, no cave-specific branching) — closing the gap.
##
## NOTE (scope boundary, unchanged from FEAT-330): MainScene.
## PROLOGUE_SCENARIO_PATH_CONST itself is NOT repointed at
## data/scenarios/dripping_cave_scenario.tres by this feature; that remains
## a separate, much larger fixture-migration feature, out of this file's
## scope. This suite proves the committed resource is fully bootable
## through the real, unmodified, scenario-agnostic MainScene boot path on
## its own terms (via CurrentGameState seeding), without touching the
## prologue's own default boot path or its dependent fixture suite.

const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")
const EncounterResourceClass = preload("res://data/encounters/encounter_resource.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")
const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const ExplorationControllerClass = preload("res://core/application/exploration_controller.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## The committed resource this suite proves is no longer a dangling
## reference. Deliberately a local constant (not
## NewGameFactory.PROLOGUE_SCENARIO_PATH_CONST, and not a scenario-specific
## constant declared on MainScene.gd itself) -- see this file's own header
## doc for why MainScene's own prologue default is not repointed at it by
## this feature. tests/unit/test_no_hardcoded_scenario_constants.gd's
## source-scan only bans the removed PROLOGUE_SCENARIO_PATH/
## PROLOGUE_ENCOUNTER_PATH identifiers (word-boundary match); this
## differently-named constant is unaffected by that guard.
const DRIPPING_CAVE_SCENARIO_PATH: String = "res://data/scenarios/dripping_cave_scenario.tres"


# ══════════════════════════════════════════════════════════════════════════
# Fixture isolation: every test in this suite starts (and ends) with the
# REAL CurrentGameState autoload singleton's `data` reset to a fresh, never-
# initialized GameStateData -- mirrors tests/boot/
# test_main_scene_boot_characterization.gd's own established convention, so
# this suite's seeding of CurrentGameState.data never leaks into any other
# suite in the project.
# ══════════════════════════════════════════════════════════════════════════

func before_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func after_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


## _boot_main_scene() -> Node -- instantiates the REAL, unmodified
## res://MainScene.tscn composition root via add_child_autofree() (ADR-002's
## preferred test setup pattern: no UI-click-driven boot required), with
## CurrentGameState.data ALREADY populated by the caller before this runs.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	add_child_autofree(instance)
	return instance


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
# FEAT-336 (US-007, resolves DEF-002): a REAL, full MainScene.tscn boot --
# seeded via NewGameFactory.create_state_for_scenario(), never via a
# hand-built ScenarioSession/ExplorationModeController bypassing MainScene
# -- reaches an active EXPLORATION state using ONLY this committed
# resource, and hex_grid_view.set_tile_terrain() is proven to have been
# invoked with the encounter's non-empty authored tiles during that boot
# (FR-007 acceptance criterion #3).
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_boots_dripping_cave_into_an_active_exploration_state_via_new_game_factory() -> void:
	CurrentGameState.data = NewGameFactoryClass.create_state_for_scenario(DRIPPING_CAVE_SCENARIO_PATH)
	assert_eq(
		CurrentGameState.data.scenario_path, DRIPPING_CAVE_SCENARIO_PATH,
		"fixture precondition: NewGameFactory.create_state_for_scenario() must seed CurrentGameState.data.scenario_path"
	)

	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.scenario_session, "MainScene must construct a real scenario_session at boot")
	assert_true(
		instance.scenario_session is ScenarioSessionClass,
		"scenario_session must be a real ScenarioSession instance"
	)
	assert_not_null(
		instance.scenario_session.scenario,
		"scenario_session.scenario must be populated from the committed dripping_cave_scenario.tres resource -- a dangling reference would leave this null"
	)
	assert_eq(
		instance.scenario_session.scenario.scenario_id, "dripping_cave",
		"the booted scenario_session must wrap the committed dripping_cave scenario (reached via the SAME generic MainScene boot path the prologue uses, with no cave-specific branching)"
	)

	assert_not_null(instance.exploration_controller, "boot() must construct a real exploration_controller")
	assert_true(
		instance.exploration_controller is ExplorationControllerClass,
		"exploration_controller must be a real ExplorationController instance"
	)

	assert_true(
		instance._exploration.is_exploration_active(),
		"MainScene reaches EXPLORATION mode successfully using the committed resource, via the real MainScene.tscn boot path (US-008 / FEAT-336 test_criteria)"
	)

	assert_push_error_count(0, "booting MainScene into exploration mode against the committed scenario resource must not log any push_error()")

	# ── FR-007 AC#3 (FEAT-336 / DEF-002): hex_grid_view.set_tile_terrain()
	# was invoked, during this same boot, once per tile in the dripping
	# cave encounter's non-empty authored `tiles` array -- proven
	# behaviourally (this codebase's established convention for
	# CanvasItem/HexGridView side effects, see tests/unit/presentation/
	# test_hex_grid_view_terrain.gd's own doc: there is no public hook to
	# intercept/count the call directly, so the observable readback via
	# get_tile_terrain() -- which returns exactly what set_tile_terrain()
	# most recently stored for that hex -- is the proof of record) by
	# reading back, from the REAL booted hex_grid_view, the terrain for
	# every hex the encounter authors and asserting it matches.
	assert_not_null(instance.hex_grid_view, "MainScene must wire a real $HexGridView")

	var dripping_cave_scenario = ResourceLoader.load(DRIPPING_CAVE_SCENARIO_PATH)
	var dripping_cave_encounter = dripping_cave_scenario.encounter_entries[0].encounter
	assert_false(
		dripping_cave_encounter.tiles.is_empty(),
		"fixture precondition: the dripping cave encounter must author a non-empty `tiles` array for this assertion to be meaningful"
	)

	if instance.hex_grid_view != null:
		var painted_tile_count: int = 0
		for tile in dripping_cave_encounter.tiles:
			var hex_coord = HexCoordClass.new(tile.q, tile.r)
			assert_eq(
				instance.hex_grid_view.get_tile_terrain(hex_coord), tile.terrain_type,
				"hex_grid_view.set_tile_terrain() must have been called at boot for hex (%d, %d) with terrain_type '%s' (FR-007 AC#3)" % [tile.q, tile.r, tile.terrain_type]
			)
			painted_tile_count += 1
		assert_true(
			painted_tile_count > 0,
			"hex_grid_view.set_tile_terrain() must have been called at least once with a non-empty tiles argument during boot (FR-007 AC#3)"
		)

	# Passability also renders correctly through the same generic boot path
	# (no scenario-specific branching): a tile authored impassable (wall)
	# must resolve as not passable, and a tile authored passable (floor)
	# must resolve as passable, via the SAME cached is_passable_fn Callable
	# MainScene's own click-to-navigate/pathfinding uses.
	var is_passable_fn: Callable = instance._exploration.get_is_passable_fn()
	assert_true(is_passable_fn.is_valid(), "MainScene's boot must build a real is_passable_fn for the dripping cave encounter")
	if is_passable_fn.is_valid():
		assert_false(
			is_passable_fn.call(HexCoordClass.new(0, 5)),
			"the authored wall tile at (0, 5) must resolve as impassable"
		)
		assert_true(
			is_passable_fn.call(HexCoordClass.new(7, -3)),
			"the authored floor tile at (7, -3) must resolve as passable"
		)


func test_main_scene_source_contains_no_dripping_cave_specific_branching() -> void:
	# FEAT-336 test_criteria: "no scenario-specific branching in
	# MainScene.gd" -- MainScene.gd must remain fully scenario-agnostic;
	# the dripping cave scenario is reached purely via CurrentGameState.data
	# seeding (NewGameFactory), never via a MainScene.gd source-level
	# reference to the cave scenario/encounter/scenario_id.
	var file := FileAccess.open("res://MainScene.gd", FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	assert_false(content.contains("dripping_cave"), "MainScene.gd must not contain any dripping-cave-specific branching")
	assert_false(content.contains("Dripping Cave"), "MainScene.gd must not contain any dripping-cave-specific branching")
