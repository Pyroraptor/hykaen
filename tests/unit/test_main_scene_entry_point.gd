extends GutTest
## tests/unit/test_main_scene_entry_point.gd
##
## GUT test suite for FEAT-005 (US-004): Main scene entry point and project
## wiring. Verifies MainScene.tscn is the project's composition root
## (ADR-006) -- wiring the repository/random/event-sink adapters and
## reusing prologue_encounter.tres / the existing party -- and that
## project.godot boots directly into it.

const GodotRandomAdapterClass          = preload("res://core/combat/godot_random_adapter.gd")
const ResourceEncounterRepositoryClass = preload("res://infrastructure/resource_encounter_repository.gd")
const EncounterClass                   = preload("res://core/combat/encounter.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MAIN_SCENE_SCRIPT_PATH: String = "res://MainScene.gd"
const PROJECT_GODOT_PATH: String = "res://project.godot"


# ── Criterion 1: project.godot run/main_scene references MainScene.tscn ─────

func test_project_godot_run_main_scene_references_main_scene_tscn() -> void:
	var file := FileAccess.open(PROJECT_GODOT_PATH, FileAccess.READ)
	assert_not_null(file, "project.godot must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains('run/main_scene="res://MainScene.tscn"'),
		"project.godot must set run/main_scene to res://MainScene.tscn (FEAT-005 / US-004)"
	)


# ── Criterion: MainScene.tscn is text-format (.tscn, not binary .scn) ────────

func test_main_scene_tscn_is_text_format() -> void:
	var file := FileAccess.open(MAIN_SCENE_PATH, FileAccess.READ)
	assert_not_null(file, "MainScene.tscn must be readable")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.begins_with("[gd_scene"),
		"MainScene.tscn first line must begin with '[gd_scene' -- text-format required"
	)


# ── Criterion: MainScene.tscn loads as a PackedScene ─────────────────────────

func test_main_scene_tscn_loads_as_packed_scene() -> void:
	var res = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(res, "ResourceLoader.load('res://MainScene.tscn') must return non-null")
	if res == null:
		return
	assert_is(res, PackedScene, "MainScene.tscn must load as a PackedScene instance")


# ── Regression guard: every ext_resource MainScene.tscn declares must exist ──
# on disk. A dangling ext_resource path (referencing a file that was since
# deleted/renamed elsewhere in the project) does not fail ResourceLoader.load()
# outright, nor any of the outcome/round_count assertions above -- Godot just
# prints "Cannot open file"/"Parse Error: [ext_resource] referenced
# non-existent resource" to the console and silently drops that child node.
# That violates the manual smoke test's "zero console errors" criterion
# (FEAT-005 test_criteria) even though every other automated assertion here
# still passes. Parse the .tscn text directly and assert each declared
# ext_resource path resolves to a real file, so a future deletion of a
# Presentation scene/script this composition root still references is
# caught here instead of only surfacing as a runtime console error.

func test_main_scene_tscn_ext_resources_all_exist_on_disk() -> void:
	var file := FileAccess.open(MAIN_SCENE_PATH, FileAccess.READ)
	assert_not_null(file, "MainScene.tscn must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	var regex := RegEx.new()
	regex.compile('\\[ext_resource type="[^"]+" path="(res://[^"]+)"')
	var matches: Array = regex.search_all(content)
	assert_true(
		matches.size() > 0,
		"MainScene.tscn must declare at least one ext_resource to check"
	)

	for m in matches:
		var res_path: String = m.get_string(1)
		assert_true(
			FileAccess.file_exists(res_path) or ResourceLoader.exists(res_path),
			"MainScene.tscn references ext_resource '%s' which must exist on disk (dangling scene reference)" % res_path
		)


# ── Criterion 2: MainScene wires the repository/random/event-sink adapters ──
# and loads data/encounters/prologue_encounter.tres, per ADR-006
# composition-root wiring. Verified against MainScene.gd's source text (the
# script MainScene.tscn attaches via ext_resource).

func test_main_scene_source_wires_repository_adapter() -> void:
	var content: String = _read_main_scene_script_source()
	assert_true(
		content.contains("ResourceEncounterRepository"),
		"MainScene must instantiate the ResourceEncounterRepository adapter (ADR-006)"
	)


func test_main_scene_source_wires_random_port_adapter() -> void:
	var content: String = _read_main_scene_script_source()
	assert_true(
		content.contains("GodotRandomAdapter"),
		"MainScene must instantiate a RandomPort adapter (GodotRandomAdapter, ADR-006)"
	)


func test_main_scene_source_wires_event_sink_adapter() -> void:
	var content: String = _read_main_scene_script_source()
	assert_true(
		content.contains("EventSinkPort"),
		"MainScene must instantiate an EventSinkPort adapter (ADR-006)"
	)


func test_main_scene_source_loads_prologue_encounter_resource() -> void:
	var content: String = _read_main_scene_script_source()
	assert_true(
		content.contains("data/encounters/prologue_encounter.tres"),
		"MainScene must load data/encounters/prologue_encounter.tres (US-004 entry_point)"
	)


func _read_main_scene_script_source() -> String:
	var file := FileAccess.open(MAIN_SCENE_SCRIPT_PATH, FileAccess.READ)
	if file == null:
		fail_test("MainScene.gd must be readable")
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


# ── Criterion: MainScene.gd contains no DisplayServer/Input calls ───────────
# (safe under --headless).

func test_main_scene_source_no_display_server_calls() -> void:
	var content: String = _read_main_scene_script_source()
	assert_false(
		content.contains("DisplayServer"),
		"MainScene.gd must not call DisplayServer -- unsafe in --headless mode"
	)


func test_main_scene_source_no_input_calls() -> void:
	var content: String = _read_main_scene_script_source()
	assert_false(
		content.contains("Input."),
		"MainScene.gd must not call Input methods -- unsafe in --headless mode"
	)


# ── Criterion 3 (headless proxy for the manual smoke test): instantiating ───
# MainScene boots the prologue encounter cleanly, wiring real adapters (not
# mocks) and a real, interactive RoundSession -- WITHOUT auto-resolving the
# whole encounter (FEAT-123 / FIND-120 superseded the old autonomous
# run_round() while-loop; see tests/unit/test_main_scene_interactive_wiring.gd
# for full interactive-pipeline coverage).

func test_main_scene_instantiated_boots_prologue_encounter_without_auto_resolving() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load for instantiation")
	if packed == null:
		return

	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return

	add_child_autofree(instance)
	await get_tree().process_frame

	# FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): round_session
	# is no longer live immediately on boot -- it stays null throughout
	# EXPLORATION mode until a real combat trigger's _on_combat_triggered()
	# calls rewire_session() (see MainScene.gd's own FEAT-316 doc; the gating
	# itself is covered end-to-end by tests/boot/
	# test_combat_pipeline_gated_by_game_mode.gd). Drive the SAME real handoff
	# here so this criterion's "a real, interactive RoundSession, without
	# auto-resolving the whole encounter" assertion still exercises a live
	# RoundSession.
	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(
		instance.outcome, "",
		"MainScene must NOT auto-resolve the prologue encounter to a terminal outcome on boot (FEAT-123 / FIND-120) -- got '%s'" % instance.outcome
	)
	assert_not_null(
		instance.round_session,
		"MainScene must obtain a real RoundSession via RunRoundUseCase.begin_round() (FEAT-123)"
	)
	assert_false(
		instance.round_session.is_round_over(),
		"the freshly-begun RoundSession must not already be over with no player input"
	)


func test_main_scene_instantiated_random_port_is_godot_random_adapter() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load for instantiation")
	if packed == null:
		return

	var instance = packed.instantiate()
	add_child_autofree(instance)

	assert_is(
		instance.random_port, GodotRandomAdapterClass,
		"MainScene.random_port must be a GodotRandomAdapter instance (production RandomPort adapter)"
	)


func test_main_scene_instantiated_repository_is_resource_encounter_repository() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load for instantiation")
	if packed == null:
		return

	var instance = packed.instantiate()
	add_child_autofree(instance)

	assert_is(
		instance.encounter_repository, ResourceEncounterRepositoryClass,
		"MainScene.encounter_repository must be a ResourceEncounterRepository instance"
	)


func test_main_scene_instantiated_encounter_is_encounter_instance() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load for instantiation")
	if packed == null:
		return

	var instance = packed.instantiate()
	add_child_autofree(instance)

	assert_is(
		instance.encounter, EncounterClass,
		"MainScene.encounter must be the reused Encounter composition root (ADR-006)"
	)


# ══════════════════════════════════════════════════════════════════════════
# FEAT-002 / US-002: real (non-override) launches must resolve a random play
# seed, never the hardcoded prologue_encounter.tres fixture seed (42) --
# while an explicit in-process `seed_override` (the composition-root contract
# GUT tests use to pin determinism regressions, e.g. tests/integration/
# test_steel_thread_prologue_encounter.gd) must still be honored exactly.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_instantiated_without_override_does_not_use_fixture_seed_42() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load for instantiation")
	if packed == null:
		return

	var instance = packed.instantiate()
	add_child_autofree(instance)

	assert_ne(
		instance.resolved_seed, 42,
		"MainScene must NOT resolve to data/encounters/prologue_encounter.tres' hardcoded "
		+ "fixture seed (42) on a real (non-override) launch (FEAT-002 / US-002)"
	)


func test_main_scene_two_boots_without_override_resolve_different_seeds() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load for instantiation")
	if packed == null:
		return

	var instance_1 = packed.instantiate()
	add_child_autofree(instance_1)
	var instance_2 = packed.instantiate()
	add_child_autofree(instance_2)

	assert_ne(
		instance_1.resolved_seed, instance_2.resolved_seed,
		"two independent real (non-override) MainScene launches must resolve to different "
		+ "play seeds (FEAT-002 / US-002 / FR-001)"
	)


func test_main_scene_honors_explicit_seed_override() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load for instantiation")
	if packed == null:
		return

	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)

	assert_eq(
		instance.resolved_seed, 42,
		"MainScene must honor an explicit in-process seed_override set before add_child() "
		+ "triggers _ready() (FEAT-002 / US-002 composition-root contract)"
	)
