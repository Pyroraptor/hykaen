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
# (safe under --headless, matching the game/main.gd convention).

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
# MainScene boots the prologue encounter to a valid terminal outcome with
# zero console errors, wiring real adapters (not mocks).

func test_main_scene_instantiated_boots_prologue_encounter_to_valid_outcome() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load for instantiation")
	if packed == null:
		return

	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return

	add_child_autofree(instance)

	assert_true(
		instance.outcome == "won" or instance.outcome == "lost",
		"MainScene must boot the prologue encounter to a terminal outcome ('won'/'lost'); got '%s'" % instance.outcome
	)
	assert_true(
		instance.round_count >= 1,
		"MainScene's booted encounter must run at least 1 round; got %d" % instance.round_count
	)
	assert_true(
		instance.event_count > 0,
		"MainScene's event-sink adapter must have received at least one round event"
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
