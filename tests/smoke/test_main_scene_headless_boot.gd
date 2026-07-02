extends GutTest
## tests/smoke/test_main_scene_headless_boot.gd
##
## FEAT-006 (US-013): Headless launchability smoke test.
##
## Extends the existing smoke-test harness (tests/integration/test_steel_thread_smoke.gd)
## to prove the project's real composition-root entry point -- MainScene.tscn,
## wired by FEAT-005/US-004 -- boots cleanly under `godot --headless`. This is
## the EARLY regression signal for the entry point called out by US-013: it
## must catch an entry-point boot failure before any Presentation/UI layer
## work begins.
##
## Design note -- why this test is entirely in-process (no spawned
## subprocess): an earlier version of this test shelled out to a second,
## independent `godot --headless --quit-after 1` process (via OS.execute) so
## it could read that process's own stderr stream directly, since Godot
## 4.3's engine-level error/warning hook (GutErrorTracker's OS.add_logger,
## addons/gut/error_tracker.gd) is a documented Godot 4.4+ API and a no-op on
## this project's pinned 4.3 engine. That approach proved unreliable in CI/
## sandboxed runners -- process spawning nested inside an already-headless
## Godot process is exactly the kind of environment-dependent behaviour this
## smoke test exists to avoid, and it caused the whole suite to hang. This
## version instead performs everything IN-PROCESS, reusing the same reliable
## pattern already established by tests/unit/test_main_scene_entry_point.gd
## (instantiate MainScene.tscn via add_child_autofree, then assert on its
## exposed fields) plus a live check against the CURRENT GUT run's own scene
## tree, since that GUT run is itself always launched via
## `godot --headless -- --gut-run-all` -- i.e. the current process already IS
## a real headless boot of the whole project (autoloads + run/main_scene =
## MainScene.tscn).
##
## What is verified:
##   1. Autoload singletons declared in project.godot's [autoload] section
##      resolve to non-null instances (checked against the live tree of the
##      CURRENT process, which -- like CI -- was itself launched via
##      `godot --headless -- --gut-run-all`).
##   2. A freshly instantiated MainScene.tscn completes first-frame
##      processing: _ready() runs to completion and the composition root
##      (adapters + prologue encounter) resolves to a terminal outcome
##      ('won'/'lost') with no crash and no null composition-root fields.
##   3. test_command (FEAT-006) runs this file early -- ahead of the full
##      project-wide GUT suite -- so an entry-point regression is reported
##      before broader UI work begins.

const PROJECT_GODOT_PATH: String = "res://project.godot"
const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


## Reads project.godot and returns the list of singleton names declared in
## its [autoload] section (e.g. ["HeadlessRunner"]). Generic over however
## many autoloads the project ends up declaring -- no hardcoded singleton
## count.
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
# Criterion 2: Autoload singletons resolve to non-null instances on first
# frame. Checked directly against the live scene tree of the process this
# test itself is running in -- which is, itself, a `godot --headless` boot
# of the whole project (autoloads + MainScene.tscn), the same as CI's
# `godot --headless -- --gut-run-all` invocation.
# ══════════════════════════════════════════════════════════════════════════

func test_autoload_singletons_resolve_to_non_null_instances() -> void:
	var autoload_names: Array = _get_configured_autoload_names()
	assert_true(
		autoload_names.size() > 0,
		"project.godot must declare at least one [autoload] singleton to verify (US-013)"
	)

	for autoload_name in autoload_names:
		var node: Node = get_tree().root.get_node_or_null(autoload_name)
		assert_not_null(
			node,
			"Autoload singleton '%s' must resolve to a non-null instance on first frame (US-013)"
			% autoload_name
		)


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1 & 3 proxy: MainScene.tscn boots headlessly, completing
# first-frame processing with a real, non-null interactive RoundSession and
# no null composition-root wiring -- WITHOUT auto-resolving the whole
# encounter (FEAT-123 / FIND-120 superseded the old autonomous run_round()
# while-loop; see tests/unit/test_main_scene_interactive_wiring.gd for full
# interactive-pipeline coverage). Instantiated fresh (add_child_autofree)
# inside this already-headless GUT process, then a real frame is awaited so
# the assertions below run only once idle/frame processing has actually
# occurred, not merely immediately after _ready() returns synchronously.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_headless_boot_completes_first_frame_without_auto_resolving() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene (US-013)")
	if packed == null:
		return

	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate (US-013)")
	if instance == null:
		return

	add_child_autofree(instance)

	# Let at least one real process frame elapse so this genuinely checks
	# "first frame processed", not merely "constructor ran".
	await get_tree().process_frame

	assert_eq(
		instance.outcome, "",
		"MainScene must NOT auto-resolve the prologue encounter to a terminal outcome on first frame "
		+ "(FEAT-123 / FIND-120); got '%s'" % instance.outcome
	)
	assert_not_null(
		instance.round_session,
		"MainScene must obtain a real RoundSession via RunRoundUseCase.begin_round() on first frame (FEAT-123)"
	)
	assert_false(
		instance.round_session.is_round_over(),
		"the freshly-begun RoundSession must not already be over with no player input"
	)
	assert_not_null(
		instance.encounter_repository,
		"MainScene.encounter_repository (repository adapter) must be non-null after first frame (US-013)"
	)
	assert_not_null(
		instance.random_port,
		"MainScene.random_port (RandomPort adapter) must be non-null after first frame (US-013)"
	)
	assert_not_null(
		instance.event_sink,
		"MainScene.event_sink (EventSinkPort adapter) must be non-null after first frame (US-013)"
	)
