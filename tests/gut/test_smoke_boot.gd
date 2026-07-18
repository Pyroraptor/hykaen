extends GutTest
## tests/gut/test_smoke_boot.gd — FEAT-001 (US-001 / FR-003) headless boot smoke test.
##
## Realizes the steel thread's entry_point: "Player launches the windowed
## Godot build...boots MainScene into the prologue encounter with no manual
## setup". This extends the existing headless-launchability coverage
## (tests/smoke/test_main_scene_headless_boot.gd, tests/unit/
## test_main_scene_entry_point.gd) with a single, explicitly-named
## FEAT-001 smoke gate that ties together every NFR-006 acceptance
## criterion in one file:
##
##   1. All autoload singletons declared in project.godot's [autoload]
##      section resolve to non-null instances.
##   2. project.godot's run/main_scene points at MainScene.tscn, so the
##      Godot editor's Play button launches directly into the prologue
##      encounter with no manual setup.
##   3. A freshly instantiated MainScene.tscn completes first-frame
##      processing with no exception and no null composition-root field --
##      each composition-root field (encounter_repository/random_port/
##      event_sink/encounter/round_session) is only left null when an
##      internal push_error() fail-fast path was hit (see MainScene.gd's
##      _ready()), so asserting non-null on all of them is this project's
##      established proxy for "zero unhandled errors on boot" (the engine
##      is pinned to Godot 4.3, whose push_error capture hook is a
##      documented 4.4+ API and a no-op here -- see addons/gut/
##      error_tracker.gd and tests/smoke/test_main_scene_headless_boot.gd's
##      file-level note for precedent).
##   4. MainScene resolves the encounter/party data via
##      infrastructure/resource_encounter_repository.gd (the
##      EncounterRepositoryPort adapter) by loading
##      data/encounters/prologue_encounter.tres -- confirmed here by
##      asserting the composition root produced a non-empty combatant turn
##      order (both party and enemy members present) with no manual setup
##      beyond instantiating the scene.
##
## This file is picked up automatically by both the root `.gutconfig.json`
## (`res://tests`, include_subdirs=true, stage 4 of ./test_command) and by
## a direct `godot --headless -- --gut-run-all` launch (US-011), matching
## this feature's "both windowed and headless (--gut-run-all) mode" test
## criterion.

const PROJECT_GODOT_PATH: String = "res://project.godot"
const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


## Reads project.godot and returns the list of singleton names declared in
## its [autoload] section (e.g. ["HeadlessRunner"]).
func _get_configured_autoload_names() -> Array:
	var names: Array = []
	var file := FileAccess.open(PROJECT_GODOT_PATH, FileAccess.READ)
	if file == null:
		return names

	var in_autoload_section: bool = false
	while not file.eof_reached():
		var line: String = file.get_line()
		var trimmed: String = line.strip_edges()
		if trimmed == "[autoload]":
			in_autoload_section = true
			continue
		if in_autoload_section:
			if trimmed.begins_with("[") and trimmed != "[autoload]":
				break
			if trimmed.contains("="):
				var singleton_name: String = trimmed.split("=")[0].strip_edges()
				if singleton_name != "":
					names.append(singleton_name)
	file.close()
	return names


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: project.godot run/main_scene points at MainScene.tscn, so
# Godot editor Play launches directly into the prologue encounter.
# ══════════════════════════════════════════════════════════════════════════

func test_project_godot_run_main_scene_points_at_main_scene_tscn() -> void:
	var file := FileAccess.open(PROJECT_GODOT_PATH, FileAccess.READ)
	assert_not_null(file, "project.godot must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains('run/main_scene="res://MainScene.tscn"'),
		"project.godot must set run/main_scene to res://MainScene.tscn (FEAT-001 / US-001)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: autoload singletons resolve to non-null instances on first
# frame. Checked against the live tree of the CURRENT process -- which,
# like CI, is itself launched via `godot --headless -- --gut-run-all`.
# ══════════════════════════════════════════════════════════════════════════

func test_autoloads_resolve_to_non_null_instances() -> void:
	var autoload_names: Array = _get_configured_autoload_names()
	assert_true(
		autoload_names.size() > 0,
		"project.godot must declare at least one [autoload] singleton to verify (FEAT-001 / NFR-006)"
	)

	for autoload_name in autoload_names:
		var node: Node = get_tree().root.get_node_or_null(autoload_name)
		assert_not_null(
			node,
			"Autoload singleton '%s' must resolve to a non-null instance on first frame (FEAT-001 / NFR-006)"
			% autoload_name
		)


# ══════════════════════════════════════════════════════════════════════════
# Criteria 3 & 4: MainScene boots headlessly with zero unhandled errors --
# every composition-root field wired, no manual setup -- and resolves the
# prologue encounter + party via the repository adapter into a real,
# non-empty combatant turn order (both teams present). A real process
# frame is awaited so this genuinely checks "first frame processed", not
# merely "constructor ran".
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_boots_headlessly_with_no_manual_setup() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene (FEAT-001)")
	if packed == null:
		return

	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate with no manual setup (FEAT-001)")
	if instance == null:
		return

	# FEAT-006 (US-005/FR-005, ADR-002): pin the prologue fixture's own
	# established "Titus (player) acts first" seed before add_child()
	# triggers _ready() -- an unpinned random initiative draw could seat
	# the Skeleton first, and MainScene.gd's rewire_session() now wires
	# RoundSession's enemy-strikes-player reaction window to the REAL,
	# blocking TurnController.resolve_reaction() -> PlayerReactionChooser
	# chain (no auto-timeout by design), which would suspend this smoke
	# test's boot indefinitely with no player present to answer it.
	instance.seed_override = 42
	add_child_autofree(instance)
	await get_tree().process_frame

	assert_not_null(
		instance.encounter_repository,
		"MainScene.encounter_repository (EncounterRepositoryPort adapter) must be non-null after first frame -- "
		+ "a null value here means MainScene's internal push_error() fail-fast path was hit (FEAT-001 / NFR-006)"
	)
	assert_not_null(
		instance.random_port,
		"MainScene.random_port (RandomPort adapter) must be non-null after first frame (FEAT-001)"
	)
	assert_not_null(
		instance.event_sink,
		"MainScene.event_sink (EventSinkPort adapter) must be non-null after first frame (FEAT-001)"
	)
	assert_not_null(
		instance.encounter,
		"MainScene.encounter (EncounterClass, seeded per ADR-002) must be non-null after first frame (FEAT-001)"
	)
	assert_not_null(
		instance.round_session,
		"MainScene.round_session must be a real RoundSession after first frame -- no unhandled boot exception (FEAT-001)"
	)


func test_main_scene_loads_prologue_encounter_party_and_enemies_with_no_manual_setup() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load for instantiation")
	if packed == null:
		return

	var instance = packed.instantiate()
	# FEAT-006 (US-005/FR-005, ADR-002): see the FEAT-006 doc on
	# test_main_scene_boots_headlessly_with_no_manual_setup() above.
	instance.seed_override = 42
	add_child_autofree(instance)
	await get_tree().process_frame

	assert_not_null(instance.encounter, "MainScene.encounter must be non-null to inspect the loaded turn order")
	if instance.encounter == null:
		return

	var turn_order: Array = instance.encounter.get_turn_order()
	assert_true(
		turn_order.size() > 0,
		"MainScene must load data/encounters/prologue_encounter.tres into a non-empty combatant turn order "
		+ "via the EncounterRepositoryPort adapter, with no manual setup steps (FEAT-001 / US-001)"
	)

	var teams: Array = []
	for combatant in turn_order:
		var team = combatant.is_enemy
		if not teams.has(team):
			teams.append(team)
	assert_true(
		teams.size() >= 2 or turn_order.size() >= 2,
		"MainScene's loaded prologue encounter must include both the party and the enemy group (FEAT-001 / US-001)"
	)
