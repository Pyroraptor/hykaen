extends GutTest
## tests/integration/test_steel_thread_camera_pan_zoom.gd — FEAT-010 (US-001
## through US-008): the E2E steel-thread integration test for the camera
## pan/clamp/zoom slice ("token click / End Turn -> camera pan, clamp,
## zoom").
##
## Maps to the feature plan's files_to_create entry
## "res://test/integration/test_steel_thread_camera_pan_zoom.gd" — this
## project's actual, established file layout keeps every MainScene
## integration/steel-thread test under tests/integration/ (see
## tests/integration/test_main_scene_combat_camera_follow.gd's and
## tests/integration/test_main_scene_map_bounds.gd's own identical header
## notes, both from this SAME iteration), so this suite lives here rather
## than at the literal res://test/... path the plan names.
##
## Boots the REAL, shipped res://MainScene.tscn composition root headless
## (mirroring every prior FEAT-005..FEAT-009 suite's own established
## `_boot_main_scene_*()` fixture convention -- pinned seed=42, the
## prologue fixture's known-good initiative roll) with NO stub/mock
## standing in for HexGridView, GameCamera, ScenarioSession, or
## ExplorationModeController -- this is the "running-scene smoke test" that
## proves US-001..US-007's individually-unit-tested pieces actually compose
## correctly end-to-end through the ONE real, shipped MainScene.tscn entry
## point:
##
##   1. EXPLORATION mode: simulating a click on a party member's token (by
##      emitting hex_grid_view's REAL `hex_clicked` signal -- the exact
##      production wiring MainScene._ready()/ExplorationModeController.boot()
##      connect to `_on_exploration_hex_clicked`, per
##      tests/integration/test_exploration_click_disambiguation.gd's own
##      established disambiguation-select fixture facts) causes the real
##      GameCamera to become is_moving()==true and then converge on
##      hex_grid_view.axial_to_pixel_with_offset(token.hex_coord).
##   2. COMBAT mode: firing the real End Turn control (end_turn_control.press(),
##      mirroring tests/integration/test_main_scene_combat_camera_follow.gd's
##      criterion 3) causes the camera to pan to the newly-active actor's
##      real token position.
##   3. Throughout BOTH pans (not merely at the final resting position),
##      camera.position and camera._target_pos stay within
##      [limit_left, limit_right] x [limit_top, limit_bottom] -- the exact
##      bounds hex_grid_view.get_world_bounds() computed and FEAT-005/
##      FEAT-008 applied via _game_camera.set_bounds() (see
##      tests/integration/test_main_scene_map_bounds.gd's own identical
##      cross-check convention).
##   4. Synthesized scroll-wheel InputEvents, handed directly to the real,
##      booted _game_camera._unhandled_input() (mirrors
##      tests/unit/presentation/test_game_camera_zoom.gd's own established
##      "call the handler directly" convention -- a real engine mouse-wheel
##      dispatch is not reliable in headless CI), change zoom and clamp it
##      to [0.5, 0.5]..[2.0, 2.0].
##   5. US-008's "full GUT suite reports 0 failing / exit code 0" health
##      signal is satisfied WITHOUT re-spawning a second, nested
##      `--gut-run-all` subprocess from inside this file. The real,
##      authoritative full-suite gate is
##      tests/integration/test_def001_gate_evidence.py's
##      TestRealGutInvocation suite: it already spawns a REAL
##      `godot --headless --path <repo_root> -- --gut-run-all` subprocess and
##      compares the exact failing-test-id set against
##      ci/accepted_known_failures.json (ci/gate_exit_policy.gd's single
##      source of truth, wired via tests/runner/headless_runner.gd's
##      post_run_script hook). Godot/GUT 4.3 does NOT reliably tolerate a
##      nested `--gut-run-all` invocation spawned from inside a running GUT
##      process -- a first attempt at this file confirmed the exact flake
##      class scripts/test_command.sh's own HYKAEN_TEST_COMMAND_E2E_GUARD
##      comment already documents for the analogous recursive pytest
##      meta-tests (stale GutRunner GUI node lookups, "Invalid call ...
##      'clear' in base 'Nil'" teardown errors) -- and doing so from THIS
##      file, which is itself collected BY that very outer gate, corrupted
##      the real gate's own run. Design notes explicitly call this out:
##      "covering US-008's test-suite health signal WITHOUT duplicating
##      downstream CI-gate reporting." This suite's own, safe contribution
##      is instead a cheap, non-recursive static check
##      (test_camera_story_suites_are_not_excused_via_known_failures_manifest())
##      that none of this steel thread's own camera-story test files are
##      quietly carved out of that manifest -- i.e. every camera suite is
##      required to be part of the real gate's "0 failing" set, never a
##      manifest-excused exception.
##
## test_criteria satisfied:
##   1. test_clicking_a_party_member_token_in_exploration_mode_pans_camera_and_stays_within_bounds()
##   2. test_pressing_end_turn_in_combat_mode_pans_camera_to_new_active_actor_and_stays_within_bounds()
##   3. (covered by both of the above, via the shared _pan_converges_within_bounds() helper's
##      per-step bounds assertions)
##   4. test_synthesized_scroll_wheel_input_against_the_running_scene_zooms_and_clamps()
##   5. test_camera_story_suites_are_not_excused_via_known_failures_manifest() -- see this
##      header's own note above for why this does NOT re-spawn a nested `--gut-run-all` run.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/integration/test_main_scene_combat_camera_follow.gd's/
## test_active_actor_selection.gd's identically-valued PINNED_SEED/seed
## constants).
const PROLOGUE_SEED: int = 42

## _ScriptedPassResolver — synchronous ReactionResolverPort double that
## always returns {"choice": "none"} so the Skeleton's AI-driven Strike
## resolves without suspending on the real reaction prompt UI in headless tests.
class _ScriptedPassResolver:
	extends RefCounted
	func resolve(_trigger: Dictionary) -> Dictionary:
		return {"choice": "none"}

const PROLOGUE_ENCOUNTER_ID: String = "prologue"

## Tolerance (world units) used both for float-clamp bound checks
## (RISK-001 re-clamp math can land a hair outside an exact int-cast
## Camera2D limit) and for the final "converged on target" position check.
const _BOUNDS_EPS: float = 1.5

## Path to the single source-of-truth manifest ci/gate_exit_policy.gd
## compares the REAL, authoritative `--gut-run-all` run's failing-test-id
## set against (see this file's header doc, criterion 5).
const _ACCEPTED_KNOWN_FAILURES_MANIFEST_PATH: String = "res://ci/accepted_known_failures.json"

## This steel thread's own camera-story test scripts (US-001..US-008) --
## the set criterion 5 asserts is never quietly excused via
## ci/accepted_known_failures.json.
const _CAMERA_STORY_SCRIPT_PATHS: Array = [
	"res://tests/unit/core/domain/test_camera_motion.gd",
	"res://tests/unit/presentation/test_game_camera_move_to.gd",
	"res://tests/unit/core/domain/test_map_bounds_calculator.gd",
	"res://tests/unit/presentation/test_hex_grid_view_bounds.gd",
	"res://tests/unit/presentation/test_game_camera_bounds.gd",
	"res://tests/unit/presentation/test_combat_camera_follow_use_case.gd",
	"res://tests/integration/test_main_scene_combat_camera_follow.gd",
	"res://tests/integration/test_main_scene_map_bounds.gd",
	"res://tests/unit/core/domain/test_zoom_clamp.gd",
	"res://tests/unit/presentation/test_game_camera_zoom.gd",
	"res://tests/integration/test_steel_thread_camera_pan_zoom.gd",
]


# ══════════════════════════════════════════════════════════════════════════
# Fixtures
# ══════════════════════════════════════════════════════════════════════════

## _boot_main_scene_exploration(seed_value) -> Node — boots the REAL,
## shipped res://MainScene.tscn composition root, pinned to `seed_value`,
## and returns it left in EXPLORATION mode (no combat handoff driven) --
## mirrors tests/integration/test_exploration_click_disambiguation.gd's own
## `_boot_main_scene()` fixture.
func _boot_main_scene_exploration(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	await get_tree().process_frame
	return instance


## _boot_main_scene_into_combat(seed_value) -> Node — boots exactly as
## _boot_main_scene_exploration() above, then drives the REAL
## _on_combat_triggered("prologue") handoff -- mirrors
## tests/integration/test_main_scene_combat_camera_follow.gd's/
## test_active_actor_selection.gd's identically-named/shaped
## `_boot_main_scene_with_seed()` fixture.
func _boot_main_scene_into_combat(seed_value: int):
	var instance = await _boot_main_scene_exploration(seed_value)
	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	return instance


## _assert_within_camera_bounds(camera, label) -> void — asserts BOTH
## camera.position and camera._target_pos currently sit within
## [limit_left, limit_right] x [limit_top, limit_bottom] (test_criteria #3).
## Called repeatedly (immediately after a pan is triggered, on every
## intermediate _process() step, and after convergence) by
## _pan_converges_within_bounds() below, so a bounds violation at ANY point
## during a pan -- not merely at the final rest position -- fails the test.
func _assert_within_camera_bounds(camera: Camera2D, label: String) -> void:
	assert_true(
		camera.position.x >= camera.limit_left - _BOUNDS_EPS and camera.position.x <= camera.limit_right + _BOUNDS_EPS,
		"%s: camera.position.x (%s) must stay within [limit_left, limit_right] = [%s, %s]" % [label, camera.position.x, camera.limit_left, camera.limit_right]
	)
	assert_true(
		camera.position.y >= camera.limit_top - _BOUNDS_EPS and camera.position.y <= camera.limit_bottom + _BOUNDS_EPS,
		"%s: camera.position.y (%s) must stay within [limit_top, limit_bottom] = [%s, %s]" % [label, camera.position.y, camera.limit_top, camera.limit_bottom]
	)
	assert_true(
		camera._target_pos.x >= camera.limit_left - _BOUNDS_EPS and camera._target_pos.x <= camera.limit_right + _BOUNDS_EPS,
		"%s: camera._target_pos.x (%s) must stay within [limit_left, limit_right] = [%s, %s]" % [label, camera._target_pos.x, camera.limit_left, camera.limit_right]
	)
	assert_true(
		camera._target_pos.y >= camera.limit_top - _BOUNDS_EPS and camera._target_pos.y <= camera.limit_bottom + _BOUNDS_EPS,
		"%s: camera._target_pos.y (%s) must stay within [limit_top, limit_bottom] = [%s, %s]" % [label, camera._target_pos.y, camera.limit_top, camera.limit_bottom]
	)


## _pan_converges_within_bounds(camera, expected_target, label) -> void —
## the shared assertion sequence for BOTH the exploration click-to-select
## pan and the combat End Turn pan (test_criteria #1/#2/#3):
##   1. camera._target_pos must already equal `expected_target` (the pan
##      was triggered synchronously by the caller, before this helper runs).
##   2. camera.is_moving() must be true immediately after the trigger.
##   3. Bounds hold immediately after the trigger.
##   4. Driving camera._process() forward in small (0.05s) steps -- never a
##      single huge delta that would instantly snap to target via
##      CameraMotion.lerp_step()'s weight-clamp-to-1.0 behavior, which would
##      prove nothing about "throughout the pan" -- bounds hold on EVERY
##      intermediate step, until is_moving() naturally goes false (bounded
##      at 400 steps as a runaway-loop backstop).
##   5. Once converged: is_moving() == false, camera.position is within
##      _BOUNDS_EPS of `expected_target`, and bounds still hold.
func _pan_converges_within_bounds(camera: Camera2D, expected_target: Vector2, label: String) -> void:
	assert_eq(
		camera._target_pos, expected_target,
		"%s: camera's lerp target must equal the expected world position" % label
	)
	assert_true(
		camera.is_moving(),
		"%s: camera must be is_moving()==true immediately after the pan is triggered" % label
	)
	_assert_within_camera_bounds(camera, label + " (immediately after trigger)")

	var steps: int = 0
	while camera.is_moving() and steps < 400:
		camera._process(0.05)
		_assert_within_camera_bounds(camera, label + " (mid-pan, step %d)" % steps)
		steps += 1

	assert_false(
		camera.is_moving(),
		"%s: camera must converge (is_moving()==false) within %d simulated steps" % [label, steps]
	)
	assert_almost_eq(
		camera.position, expected_target, Vector2(_BOUNDS_EPS, _BOUNDS_EPS),
		"%s: camera must converge on the expected target position" % label
	)
	_assert_within_camera_bounds(camera, label + " (after convergence)")


func _wheel_event(button_index: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	return event


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (+3) — clicking a party member's token in EXPLORATION mode
# pans the real GameCamera to that token's world position, staying within
# the scenario's computed map bounds throughout.
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_a_party_member_token_in_exploration_mode_pans_camera_and_stays_within_bounds() -> void:
	var instance = await _boot_main_scene_exploration(PROLOGUE_SEED)

	assert_eq(
		instance._exploration.selected_party_member_id, "player_0",
		"fixture assumption: Titus (player_0) is the default selection at boot"
	)
	assert_eq(instance.scenario_session.party_hex_positions["player_1"].q, -1, "fixture assumption: Marigold (player_1) starts at (-1, 0)")
	assert_eq(instance.scenario_session.party_hex_positions["player_1"].r, 0, "fixture assumption: Marigold (player_1) starts at (-1, 0)")

	var target_hex := HexCoordClass.new(-1, 0)
	var expected_world_pos: Vector2 = instance.hex_grid_view.axial_to_pixel(target_hex)

	# Simulate clicking Marigold's token by emitting the REAL
	# hex_grid_view.hex_clicked signal -- the exact production connection
	# MainScene._ready()/ExplorationModeController.boot() wire to
	# _on_exploration_hex_clicked (never calling the handler method
	# directly), so this exercises the genuine signal-dispatch path a real
	# mouse click on the token would drive.
	instance.hex_grid_view.hex_clicked.emit(target_hex)

	assert_eq(
		instance._exploration.selected_party_member_id, "player_1",
		"clicking Marigold's token must select her (DisambiguateHexClickUseCase, FEAT-006), proving this really was a token click"
	)
	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), "player_1",
		"hex_grid_view's own selection cache must also reflect the click-selected token"
	)

	_pan_converges_within_bounds(instance._game_camera, expected_world_pos, "exploration click-to-select pan")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (+3) — pressing End Turn in COMBAT mode pans the real
# GameCamera to the newly-active actor's token position, staying within the
# scenario's computed map bounds throughout.
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_end_turn_in_combat_mode_pans_camera_to_new_active_actor_and_stays_within_bounds() -> void:
	var instance = await _boot_main_scene_into_combat(PROLOGUE_SEED)

	assert_true(instance.end_turn_control.is_enabled(), "fixture assumption: End Turn must be enabled at combat entry")

	# Inject a synchronous pass resolver so the Skeleton's AI-driven Strike
	# resolves without blocking on the real reaction prompt UI in headless tests.
	var pass_resolver := _ScriptedPassResolver.new()
	instance.round_session.set_prehit_avoidance_resolver_fn(Callable(pass_resolver, "resolve"))
	instance.round_session.set_onhit_mitigation_resolver_fn(Callable(pass_resolver, "resolve"))

	instance.end_turn_control.press()

	# await one process frame: the async signal handler's _drive() chain
	# defers at least one frame in Godot 4.3 even with synchronous reactions.
	await get_tree().process_frame

	var new_actor = instance.round_session.current_actor_entity()
	assert_not_null(new_actor, "pressing End Turn must settle on a live current actor (or the round ends)")

	var expected_world_pos: Vector2 = instance.hex_grid_view.axial_to_pixel(new_actor.hex_coord)

	_pan_converges_within_bounds(instance._game_camera, expected_world_pos, "combat End Turn pan")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — synthesized scroll-wheel InputEvents against the running
# scene change zoom and clamp it to [0.5, 0.5]..[2.0, 2.0].
# ══════════════════════════════════════════════════════════════════════════

func test_synthesized_scroll_wheel_input_against_the_running_scene_zooms_and_clamps() -> void:
	var instance = await _boot_main_scene_exploration(PROLOGUE_SEED)
	var camera: Camera2D = instance._game_camera
	camera.zoom = Vector2(1.0, 1.0)

	assert_eq(camera.min_zoom, Vector2(0.5, 0.5), "the real, booted GameCamera's min_zoom must be the documented 0.5 clamp bound")
	assert_eq(camera.max_zoom, Vector2(2.0, 2.0), "the real, booted GameCamera's max_zoom must be the documented 2.0 clamp bound")

	camera._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))
	assert_almost_eq(
		camera.zoom, Vector2(1.1, 1.1), Vector2(0.0001, 0.0001),
		"a synthesized wheel-up event handed to the running scene's real GameCamera._unhandled_input() must increase zoom by its configured step"
	)

	camera._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_DOWN))
	camera._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_DOWN))
	assert_almost_eq(
		camera.zoom, Vector2(0.9, 0.9), Vector2(0.0001, 0.0001),
		"synthesized wheel-down events must decrease zoom"
	)

	# Drive well past the max clamp bound -- zoom must never exceed it.
	for i in range(30):
		camera._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))
	assert_eq(camera.zoom, Vector2(2.0, 2.0), "repeated wheel-up input against the running scene must clamp zoom at max_zoom (2.0, 2.0), never exceed it")

	# Drive well past the min clamp bound -- zoom must never go below it.
	for i in range(40):
		camera._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_DOWN))
	assert_eq(camera.zoom, Vector2(0.5, 0.5), "repeated wheel-down input against the running scene must clamp zoom at min_zoom (0.5, 0.5), never go below it")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — US-008's "full GUT suite: 0 failing / exit code 0" health
# signal, WITHOUT re-spawning a second, nested `--gut-run-all` subprocess
# from inside this file (see this file's header doc for the full
# rationale: the real, authoritative check already lives in
# tests/integration/test_def001_gate_evidence.py's TestRealGutInvocation
# suite, and a nested invocation from inside a running GUT process is both
# redundant and unsafe on this project's pinned Godot/GUT 4.3).
# ══════════════════════════════════════════════════════════════════════════

func _read_file_text_or_empty(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_camera_story_suites_are_not_excused_via_known_failures_manifest() -> void:
	var manifest_text: String = _read_file_text_or_empty(_ACCEPTED_KNOWN_FAILURES_MANIFEST_PATH)
	assert_false(manifest_text.is_empty(), "%s must exist and be readable" % _ACCEPTED_KNOWN_FAILURES_MANIFEST_PATH)
	if manifest_text.is_empty():
		return

	var parsed = JSON.parse_string(manifest_text)
	assert_not_null(parsed, "%s must be valid JSON" % _ACCEPTED_KNOWN_FAILURES_MANIFEST_PATH)
	if parsed == null:
		return

	var accepted_known_failures: Array = parsed.get("accepted_known_failures", [])

	for camera_script_path in _CAMERA_STORY_SCRIPT_PATHS:
		for entry in accepted_known_failures:
			assert_false(
				String(entry).begins_with(camera_script_path + "::"),
				(
					"%s must not be excused via %s -- this steel thread's own camera-story "
					+ "suites are required to be part of the real full-suite gate's '0 failing' "
					+ "set (tests/integration/test_def001_gate_evidence.py), never a "
					+ "manifest-excused exception (found: %s)"
				) % [camera_script_path, _ACCEPTED_KNOWN_FAILURES_MANIFEST_PATH, entry]
			)
