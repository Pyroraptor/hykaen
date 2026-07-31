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
## prologue fixture's known-good initiative roll, real
## _on_combat_triggered("prologue") handoff) with NO stub/mock standing in
## for HexGridView or GameCamera, proving:
##
##   1. Seeded scenario boot: after MainScene._ready() loads the boot
##      scenario/encounter and calls hex_grid_view.load_combatants(), it
##      also calls hex_grid_view.get_world_bounds() and applies the result
##      via _game_camera.set_bounds() — observable as _game_camera.
##      limit_left < limit_right and limit_top < limit_bottom, AND strictly
##      inside Godot's own +/-10,000,000 "no bounds" sentinel (i.e. NOT the
##      untouched default), proving real, populated bounds were applied,
##      not merely left at Camera2D's engine defaults.
##
##   2. Bounds are recomputed and reapplied immediately after
##      hex_grid_view.set_selectable_hexes() during combat movement
##      highlighting: MainScene._on_active_actor_changed() delegates to
##      TurnPresentationController.on_active_actor_changed(), which calls
##      highlight_legal_moves() -> hex_grid_view.set_selectable_hexes()
##      for the newly-active player actor's legal Step/Stride
##      destinations; this feature's trailing statement in
##      _on_active_actor_changed() must then re-apply
##      _game_camera.set_bounds(hex_grid_view.get_world_bounds()) so the
##      camera's clamp region reflects the CURRENT highlighted hex set, not
##      a stale snapshot taken before highlighting. Proven by forcing a
##      deliberately different "stale" bounds baseline (computed from an
##      artificially emptied selectable-hex set) immediately before the
##      call, then asserting the post-call camera limits match the FRESH
##      get_world_bounds() (which now includes the real highlighted
##      hexes) rather than the stale baseline.
##
## test_criteria covered here:
##   - Seeded scenario boot: after load, _game_camera.limit_left <
##     limit_right and limit_top < limit_bottom (non-default, populated
##     bounds).
##   - Bounds are recomputed and reapplied immediately after
##     set_selectable_hexes() during combat movement highlighting.
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
# Criterion 1 — seeded scenario boot produces populated, non-default
# camera bounds.
# ══════════════════════════════════════════════════════════════════════════

func test_seeded_scenario_boot_applies_populated_camera_bounds() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PINNED_SEED
	add_child_autofree(instance)
	await get_tree().process_frame

	assert_not_null(instance.hex_grid_view, "fixture assumption: hex_grid_view must be wired at boot")
	assert_not_null(instance._game_camera, "fixture assumption: _game_camera must be wired at boot")

	assert_true(
		instance._game_camera.limit_left < instance._game_camera.limit_right,
		"after scenario-load boot, _game_camera.limit_left must be < limit_right (populated bounds)"
	)
	assert_true(
		instance._game_camera.limit_top < instance._game_camera.limit_bottom,
		"after scenario-load boot, _game_camera.limit_top must be < limit_bottom (populated bounds)"
	)

	# "non-default" — the seeded party/enemy tokens loaded at boot must have
	# produced a REAL, margin-expanded AABB strictly inside Godot's own
	# +/-10,000,000 "no bounds" sentinel, not the untouched Camera2D default.
	assert_true(
		instance._game_camera.limit_left > -DEFAULT_LIMIT,
		"boot must apply real bounds, not leave limit_left at the -10,000,000 default sentinel"
	)
	assert_true(
		instance._game_camera.limit_right < DEFAULT_LIMIT,
		"boot must apply real bounds, not leave limit_right at the +10,000,000 default sentinel"
	)
	assert_true(
		instance._game_camera.limit_top > -DEFAULT_LIMIT,
		"boot must apply real bounds, not leave limit_top at the -10,000,000 default sentinel"
	)
	assert_true(
		instance._game_camera.limit_bottom < DEFAULT_LIMIT,
		"boot must apply real bounds, not leave limit_bottom at the +10,000,000 default sentinel"
	)

	# Cross-check against the exact adapter method the feature wires in:
	# applied limits must equal hex_grid_view.get_world_bounds()'s edges.
	# Camera2D.limit_left/right/top/bottom are int-typed engine properties
	# (not float, see tests/unit/presentation/test_game_camera_bounds.gd's
	# identical note) -- Godot truncates a float assignment toward zero, so
	# expected edges are cast through int() here to match the real property
	# type/conversion exactly rather than comparing a raw float.
	var expected_bounds: Rect2 = instance.hex_grid_view.get_world_bounds()
	assert_eq(instance._game_camera.limit_left, int(expected_bounds.position.x),
		"limit_left must equal hex_grid_view.get_world_bounds()'s left edge")
	assert_eq(instance._game_camera.limit_right, int(expected_bounds.position.x + expected_bounds.size.x),
		"limit_right must equal hex_grid_view.get_world_bounds()'s right edge")
	assert_eq(instance._game_camera.limit_top, int(expected_bounds.position.y),
		"limit_top must equal hex_grid_view.get_world_bounds()'s top edge")
	assert_eq(instance._game_camera.limit_bottom, int(expected_bounds.position.y + expected_bounds.size.y),
		"limit_bottom must equal hex_grid_view.get_world_bounds()'s bottom edge")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — bounds are recomputed and reapplied immediately after
# set_selectable_hexes() during combat movement highlighting.
# ══════════════════════════════════════════════════════════════════════════

func test_active_actor_changed_recomputes_and_reapplies_bounds_after_movement_highlighting() -> void:
	var instance = await _boot_main_scene_with_seed(PINNED_SEED)

	var actor = instance.round_session.current_actor_entity()
	assert_not_null(actor, "fixture assumption: a seeded combat boot must settle on a live current actor")

	# Force the selectable-hex set to empty and seed the camera's bounds
	# from THAT stale/empty state, so this test can prove
	# _on_active_actor_changed() genuinely recomputes bounds using the
	# FRESH selectable-hex state highlight_legal_moves() sets during THIS
	# call -- not merely leaving whatever bounds were already applied at
	# boot untouched.
	instance.hex_grid_view.set_selectable_hexes([])
	var stale_bounds: Rect2 = instance.hex_grid_view.get_world_bounds()
	instance._game_camera.set_bounds(stale_bounds)

	instance._on_active_actor_changed(actor)

	# highlight_legal_moves() must have populated a non-empty selectable-hex
	# set for a live player actor's turn, so the fresh bounds computed now
	# differ from the artificially-emptied stale baseline above -- otherwise
	# this test would pass even if the recompute used stale state.
	assert_true(
		instance.hex_grid_view._selectable_hexes.size() > 0,
		"fixture assumption: the active player actor's turn must highlight at least one legal Step/Stride hex"
	)

	var fresh_bounds: Rect2 = instance.hex_grid_view.get_world_bounds()
	assert_ne(
		fresh_bounds, stale_bounds,
		"fixture assumption: fresh bounds (post-highlight) must differ from the artificially stale baseline"
	)

	# Camera2D.limit_left/right/top/bottom are int-typed engine properties
	# (not float) -- expected edges are cast through int() to match Godot's
	# own float->int truncation on assignment (see criterion 1's identical
	# note above).
	assert_eq(instance._game_camera.limit_left, int(fresh_bounds.position.x),
		"_on_active_actor_changed() must reapply limit_left from the FRESH post-highlight get_world_bounds(), not the stale baseline")
	assert_eq(instance._game_camera.limit_right, int(fresh_bounds.position.x + fresh_bounds.size.x),
		"_on_active_actor_changed() must reapply limit_right from the FRESH post-highlight get_world_bounds(), not the stale baseline")
	assert_eq(instance._game_camera.limit_top, int(fresh_bounds.position.y),
		"_on_active_actor_changed() must reapply limit_top from the FRESH post-highlight get_world_bounds(), not the stale baseline")
	assert_eq(instance._game_camera.limit_bottom, int(fresh_bounds.position.y + fresh_bounds.size.y),
		"_on_active_actor_changed() must reapply limit_bottom from the FRESH post-highlight get_world_bounds(), not the stale baseline")
