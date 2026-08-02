extends GutTest
## tests/integration/test_main_scene_combat_camera_follow.gd — FEAT-007
## (US-005, mitigates RISK-009): combat-mode camera follow on active actor
## change.
##
## Boots the REAL, shipped res://MainScene.tscn composition root headless
## (mirroring tests/integration/test_active_actor_selection.gd's established
## `_boot_main_scene_with_seed()` fixture convention -- pinned seed=42, the
## prologue fixture's known-good initiative roll, real
## _on_combat_triggered("prologue") handoff) with NO stub/mock standing in
## for HexGridView or GameCamera, proving MainScene._on_active_actor_changed()
## pans _game_camera to the newly-active actor's REAL, live hex through the
## exact TurnController.active_actor_changed signal wiring a real player turn
## drives (not merely the handler's method signature in isolation).
##
## Verifies (test_criteria):
##   1. Firing _on_active_actor_changed with a resolvable combatant hex
##      results in _game_camera.is_moving() == true and the correct target
##      position (hex_grid_view.axial_to_pixel_with_offset(actor.hex_coord)).
##   2. Firing _on_active_actor_changed with an unresolved hex results in no
##      exception, no camera movement, and a push_warning() breadcrumb
##      (RISK-009) -- proven via the observable no-crash/no-movement
##      contract plus a source-inspection check that the push_warning() call
##      site exists, mirroring tests/boot/test_main_scene_party_position_
##      seeding.gd's and tests/test_encounter_round_loop.gd's documented
##      GUT-4.3-cannot-observe-push_warning() convention (see their header
##      docs: assert_push_warning_count() relies on OS.add_logger(), a
##      Godot 4.4+ API that is a no-op on this project's pinned 4.3 engine).
##   3. Boots a seeded combat scenario and confirms pressing End Turn (the
##      steel thread's own "presses End Turn in combat mode" entry point)
##      drives the real EndTurnControl -> RoundSession -> TurnController ->
##      active_actor_changed -> MainScene._on_active_actor_changed signal
##      path end-to-end, resulting in the camera panning toward the newly
##      -settled actor's real hex.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const PINNED_SEED: int = 42

## _ScriptedPassResolver — synchronous ReactionResolverPort double that
## always returns {"choice": "none"} (Pass) so the Skeleton's AI-driven
## Strike resolves without opening the real reaction prompt UI. Without this,
## advance_ai_turn() suspends waiting for a never-delivered reaction_chosen
## signal in headless tests, deferring _drive() beyond the synchronous
## window the camera-pan assertion must check.
class _ScriptedPassResolver:
	extends RefCounted
	func resolve(_trigger: Dictionary) -> Dictionary:
		return {"choice": "none"}


## _boot_main_scene_with_seed(seed_value) -> Node — mirrors
## tests/integration/test_active_actor_selection.gd's identically-named
## fixture: boots the real MainScene.tscn pinned to `seed_value`, triggers
## the real exploration->combat handoff via _on_combat_triggered("prologue"),
## and returns the settled instance with a live round_session and the
## TurnController.active_actor_changed signal already wired to
## MainScene._on_active_actor_changed.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


## _find_combatant_by_id(instance, combatant_id) -> Combatant or null.
func _find_combatant_by_id(instance, combatant_id: String):
	for combatant in instance._party + instance._enemies:
		if combatant.combatant_id == combatant_id:
			return combatant
	return null


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — a resolvable combatant hex results in _game_camera.
# is_moving() == true and the correct target position.
# ══════════════════════════════════════════════════════════════════════════

func test_active_actor_changed_with_resolvable_hex_pans_camera_to_correct_target() -> void:
	var instance = await _boot_main_scene_with_seed(PINNED_SEED)

	var actor = _find_combatant_by_id(instance, "player_1")
	assert_not_null(actor, "fixture assumption: prologue_encounter.tres seats a live 'player_1' (Marigold)")

	var expected_world_pos: Vector2 = instance.hex_grid_view.axial_to_pixel(actor.hex_coord)

	instance._on_active_actor_changed(actor)

	assert_true(
		instance._game_camera.is_moving(),
		"_game_camera must be moving after _on_active_actor_changed fires with a resolvable combatant hex"
	)
	assert_eq(
		instance._game_camera._target_pos, expected_world_pos,
		"_game_camera's lerp target must equal hex_grid_view.axial_to_pixel(actor.hex_coord) (FEAT-002: pure world coords)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — an unresolved combatant hex results in no exception, no
# camera movement, and a push_warning() breadcrumb (RISK-009).
# ══════════════════════════════════════════════════════════════════════════

func test_active_actor_changed_with_unresolved_hex_is_a_silent_no_op() -> void:
	var instance = await _boot_main_scene_with_seed(PINNED_SEED)

	# First, establish a known camera state via a resolvable actor, so we
	# can prove the unresolved-hex case below leaves it untouched.
	var known_actor = _find_combatant_by_id(instance, "player_0")
	instance._on_active_actor_changed(known_actor)
	var prior_target_pos: Vector2 = instance._game_camera._target_pos
	var prior_moving: bool = instance._game_camera.is_moving()

	# A live Combatant instance whose combatant_id is deliberately absent
	# from scenario_session.party_hex_positions AND the live _party/_enemies
	# roster -- an actor "not yet placed" per the design notes' error_handling
	# contract for US-005.
	var unresolved_actor = CombatantClass.new("ghost_actor_not_seated", "Ghost", "player", HexCoordClass.new(0, 0))

	# Must not throw / must not crash the test run.
	instance._on_active_actor_changed(unresolved_actor)

	assert_eq(
		instance._game_camera._target_pos, prior_target_pos,
		"an unresolved combatant hex must NOT change _game_camera's lerp target"
	)
	assert_eq(
		instance._game_camera.is_moving(), prior_moving,
		"an unresolved combatant hex must NOT start/stop camera movement"
	)

	# Source-inspection check (GUT 4.3 cannot observe push_warning() at
	# runtime -- see this file's header doc): the guard-clause skip path
	# must emit a push_warning() breadcrumb (RISK-009), never a silent
	# no-op with zero trace. MainScene.gd delegates this handling to
	# presentation/combat_camera_follow_use_case.gd's execute() (extracted
	# to keep MainScene.gd inside its FR-009/ADR-001 1000-line budget --
	# see tests/ci/test_mainscene_gate.gd), so the call site lives there.
	var source: String = FileAccess.get_file_as_string("res://presentation/combat_camera_follow_use_case.gd")
	var method_start: int = source.find("func execute(")
	assert_true(method_start >= 0, "CombatCameraFollowUseCase must define execute()")
	var method_end: int = source.find("\nfunc ", method_start + 1)
	var method_body: String = source.substr(method_start, method_end - method_start)
	assert_true(
		method_body.contains("push_warning("),
		"execute()'s unresolved-hex guard clause must push_warning() a breadcrumb (RISK-009)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — booting a seeded combat scenario and pressing End Turn
# drives the real signal path end-to-end, panning the camera toward the
# newly-settled actor's real hex.
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_end_turn_in_combat_mode_pans_camera_to_the_new_active_actor() -> void:
	var instance = await _boot_main_scene_with_seed(PINNED_SEED)

	assert_true(instance.end_turn_control.is_enabled(), "fixture assumption: End Turn must be enabled at combat entry")

	# Inject a synchronous pass resolver so the Skeleton's AI-driven Strike
	# (which fires on the next turn) resolves without waiting on the real
	# reaction prompt UI (which blocks on a signal that never fires in headless).
	# With this resolver, the full advance_ai_turn() → _drive() chain settles
	# within one process frame rather than suspending indefinitely.
	var pass_resolver := _ScriptedPassResolver.new()
	instance.round_session.set_prehit_avoidance_resolver_fn(Callable(pass_resolver, "resolve"))
	instance.round_session.set_onhit_mitigation_resolver_fn(Callable(pass_resolver, "resolve"))

	instance.end_turn_control.press()

	# await one process frame: _on_end_turn_control_turn_ended is an async
	# signal handler whose await _drive() chain (advance_ai_turn → Strike →
	# advance cursor → active_actor_changed → camera pan) defers at least one
	# frame even when its internal awaits are synchronous (Godot 4.3 coroutine
	# scheduling). One frame is sufficient for the chain to settle.
	await get_tree().process_frame

	var new_actor = instance.round_session.current_actor_entity()
	assert_not_null(new_actor, "pressing End Turn must settle on a live current actor (or the round ends)")

	var expected_world_pos: Vector2 = instance.hex_grid_view.axial_to_pixel(new_actor.hex_coord)

	assert_eq(
		instance._game_camera._target_pos, expected_world_pos,
		"pressing End Turn must, end-to-end, pan _game_camera toward the newly-active actor's real hex"
	)
