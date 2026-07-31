extends GutTest
## tests/integration/test_main_scene_map_bounds.gd — FEAT-008 (US-006):
## "Wire recomputed map bounds into scenario load and selectable-hex
## updates".
##
## Maps to the feature plan's files_to_create entry
## "res://test/integration/test_main_scene_map_bounds.gd" — this project's
## actual, established file layout keeps every MainScene integration test
## under tests/integration/ (see tests/integration/
## test_main_scene_combat_camera_follow.gd, test_steel_thread_selection_
## e2e.gd, etc.), so this suite lives here rather than at the literal
## res://test/... path the plan names, matching every prior feature's own
## documented precedent (e.g. tests/unit/presentation/
## test_hex_grid_view_bounds.gd's identical header note).
##
## Boots the REAL, shipped res://MainScene.tscn composition root headless
## (mirroring tests/integration/test_main_scene_combat_camera_follow.gd's
## `_boot_main_scene_with_seed()` fixture convention — pinned seed=42, the
## prologue fixture's known-good initiative roll) with NO stub/mock standing
## in for HexGridView or GameCamera, proving:
##
##   1. Seeded scenario boot: after MainScene._ready() loads the boot
##      scenario/encounter, _game_camera retains the default "free pan"
##      limits (±10,000,000 sentinels). Tight token-based bounds were
##      removed because the hex map is typically smaller than the viewport,
##      causing contradictory Camera2D limits that blocked all panning and
##      prevented move_to() from reaching its target.
##
## test_criteria covered here:
##   - Seeded scenario boot: camera retains default free-pan limits at boot
##     (no artificial bounds applied by load_combatants()).
##   - Existing scenario-load and combat-mode test suites still pass with
##     no regressions (verified by running the full GUT suite alongside
##     this file, not a criterion this file can itself assert).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const PINNED_SEED: int = 42

## Godot's own Camera2D default limit_left/right/top/bottom sentinel
## values (mirrors tests/unit/presentation/test_game_camera_bounds.gd's
## identically-named/valued constant).
const DEFAULT_LIMIT: int = 10000000


## _boot_main_scene_with_seed(seed_value) -> Node — mirrors tests/
## integration/test_main_scene_combat_camera_follow.gd's identically-named
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


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — seeded scenario boot leaves camera with default free-pan
# limits (no artificial tight bounds that would block panning).
# ══════════════════════════════════════════════════════════════════════════

func test_seeded_scenario_boot_leaves_camera_at_default_free_pan_limits() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PINNED_SEED
	add_child_autofree(instance)
	await get_tree().process_frame

	assert_not_null(instance.hex_grid_view, "fixture assumption: hex_grid_view must be wired at boot")
	assert_not_null(instance._game_camera, "fixture assumption: _game_camera must be wired at boot")

	# After load_combatants(), set_bounds() is NOT called: tight token-based
	# bounds would make the camera's limits contradictory when the map is
	# smaller than the viewport, freezing the camera at the bounds midpoint
	# and blocking both panning and move_to() targets.
	assert_eq(
		instance._game_camera.limit_left, -DEFAULT_LIMIT,
		"after scenario-load boot, limit_left must be the default free-pan sentinel (-10,000,000)"
	)
	assert_eq(
		instance._game_camera.limit_right, DEFAULT_LIMIT,
		"after scenario-load boot, limit_right must be the default free-pan sentinel (+10,000,000)"
	)
	assert_eq(
		instance._game_camera.limit_top, -DEFAULT_LIMIT,
		"after scenario-load boot, limit_top must be the default free-pan sentinel (-10,000,000)"
	)
	assert_eq(
		instance._game_camera.limit_bottom, DEFAULT_LIMIT,
		"after scenario-load boot, limit_bottom must be the default free-pan sentinel (+10,000,000)"
	)

