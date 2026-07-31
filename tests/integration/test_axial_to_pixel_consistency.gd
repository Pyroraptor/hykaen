extends GutTest
## tests/integration/test_axial_to_pixel_consistency.gd — FEAT-008 (US-006,
## mitigates RISK-002): "cross-story coordinate-conversion consistency
## test".
##
## Maps to the feature plan's files_to_create entry
## "res://test/integration/test_axial_to_pixel_consistency.gd" — this
## project's actual, established file layout keeps every MainScene
## integration test under tests/integration/ (see tests/integration/
## test_main_scene_combat_camera_follow.gd, test_steel_thread_selection_
## e2e.gd, etc.), so this suite lives here rather than at the literal
## res://test/... path the plan names, matching every prior feature's own
## documented precedent (e.g. tests/unit/presentation/
## test_hex_grid_view_bounds.gd's identical header note).
##
## RISK-002 (per this steel thread's design notes): three independent call
## sites each convert a hex coordinate to world-space pixels via
## presentation/hex_grid_view.gd's HexGridView.axial_to_pixel_with_offset():
##   1. HexGridView.get_world_bounds() (FEAT-004/US-002) — internally calls
##      axial_to_pixel_with_offset() on every token/selectable-hex position
##      before handing the resulting points to MapBoundsCalculator.
##   2. ExplorationModeController._select_party_member() (FEAT-006/US-004)
##      — the exploration-mode camera-follow path — calls
##      _hex_grid_view.axial_to_pixel_with_offset(hex_coord) before
##      invoking on_camera_follow.
##   3. presentation/combat_camera_follow_use_case.gd's
##      CombatCameraFollowUseCase.execute() (FEAT-007/US-005) — the
##      combat-mode camera-follow path, invoked by MainScene.
##      _on_active_actor_changed() — calls
##      _hex_grid_view.axial_to_pixel_with_offset(hex_coord) before
##      invoking the camera_follow_fn.
##
## A regression that introduced a SECOND, subtly different offset/scale
## conversion at any one of these three call sites (rather than every call
## site sharing the exact same HexGridView.axial_to_pixel_with_offset()
## method on the exact same HexGridView instance) would desync the camera
## bounds computed at boot from where the camera actually pans during
## exploration/combat follow -- this suite pins that all three call sites
## are provably the SAME function on the SAME instance, by boot-ing the
## REAL res://MainScene.tscn composition root (no stub/mock HexGridView)
## and asserting all three produce IDENTICAL Vector2 world output for the
## SAME Vector2i hex coordinate.
##
## test_criteria covered here:
##   - RISK-002 test: the same Vector2i hex coordinate produces identical
##     Vector2 world output whether converted via HexGridView.
##     get_world_bounds()'s internal conversion, ExplorationModeController's
##     follow path, or MainScene's combat follow path.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const PINNED_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PINNED_SEED
	add_child_autofree(instance)
	await get_tree().process_frame
	return instance


func _find_combatant_by_id(instance, combatant_id: String):
	for combatant in instance._party + instance._enemies:
		if combatant.combatant_id == combatant_id:
			return combatant
	return null


# ══════════════════════════════════════════════════════════════════════════
# Source-inspection precondition — proves get_world_bounds() really does
# route through axial_to_pixel_with_offset() (established as the "bounds
# computation's internal conversion" call path this test's Path A stands
# in for), so a direct call to hex_grid_view.axial_to_pixel_with_offset()
# on the same instance is a faithful proxy for it.
# ══════════════════════════════════════════════════════════════════════════

func test_get_world_bounds_source_routes_through_axial_to_pixel_with_offset() -> void:
	var source: String = FileAccess.get_file_as_string("res://presentation/hex_grid_view.gd")
	var method_start: int = source.find("func get_world_bounds(")
	assert_true(method_start >= 0, "HexGridView must define get_world_bounds()")
	var method_end: int = source.find("\nfunc ", method_start + 1)
	if method_end < 0:
		method_end = source.length()  # get_world_bounds() may be the last function in the file
	var method_body: String = source.substr(method_start, method_end - method_start)
	assert_true(
		method_body.contains("axial_to_pixel_with_offset("),
		"get_world_bounds() must convert its points via axial_to_pixel_with_offset() (RISK-002's canonical call path)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion — identical Vector2i hex coordinate produces identical Vector2
# world output across all three call sites.
# ══════════════════════════════════════════════════════════════════════════

func test_axial_to_pixel_with_offset_is_consistent_across_bounds_exploration_and_combat_call_sites() -> void:
	var instance = await _boot_main_scene()

	# player_1 (Marigold) — this project's established prologue fixture
	# assumption (tests/integration/test_steel_thread_selection_e2e.gd):
	# seated at (-1, 0), a live, resolvable party member at boot.
	assert_true(
		instance.scenario_session.party_hex_positions.has("player_1"),
		"fixture assumption: scenario_session.party_hex_positions must seat 'player_1' at boot"
	)
	var hex_coord = instance.scenario_session.party_hex_positions["player_1"]

	# ── Path A: the canonical conversion get_world_bounds() itself uses
	# internally -- the SAME HexGridView instance's axial_to_pixel_with_
	# offset(), called directly (proven above to be get_world_bounds()'s own
	# internal call path). ──────────────────────────────────────────────────
	var bounds_path_world_pos: Vector2 = instance.hex_grid_view.axial_to_pixel_with_offset(hex_coord)

	# ── Path B: ExplorationModeController's follow path. ────────────────────
	instance._exploration._select_party_member("player_1")
	var exploration_path_world_pos: Vector2 = instance._game_camera._target_pos

	# ── Path C: MainScene's combat follow path (CombatCameraFollowUseCase,
	# via _on_active_actor_changed()). ──────────────────────────────────────
	var actor = _find_combatant_by_id(instance, "player_1")
	assert_not_null(actor, "fixture assumption: 'player_1' must be a live Combatant in _party")
	instance._on_active_actor_changed(actor)
	var combat_path_world_pos: Vector2 = instance._game_camera._target_pos

	assert_eq(
		exploration_path_world_pos, bounds_path_world_pos,
		"ExplorationModeController's camera-follow conversion must match the bounds-computation conversion for the same hex"
	)
	assert_eq(
		combat_path_world_pos, bounds_path_world_pos,
		"MainScene's combat camera-follow conversion must match the bounds-computation conversion for the same hex"
	)
	assert_eq(
		exploration_path_world_pos, combat_path_world_pos,
		"exploration-mode and combat-mode camera-follow conversions must agree with each other for the same hex"
	)


## A second, distinct hex (player_0 / Titus at (0,0), also an established
## prologue fixture assumption) guards against a false-positive that could
## arise if all three paths coincidentally agreed only at one particular
## coordinate (e.g. an implementation that ignores origin_offset entirely
## would still match at (0,0) alone).
func test_axial_to_pixel_with_offset_is_consistent_for_a_second_distinct_hex() -> void:
	var instance = await _boot_main_scene()

	assert_true(
		instance.scenario_session.party_hex_positions.has("player_0"),
		"fixture assumption: scenario_session.party_hex_positions must seat 'player_0' at boot"
	)
	var hex_coord = instance.scenario_session.party_hex_positions["player_0"]

	var bounds_path_world_pos: Vector2 = instance.hex_grid_view.axial_to_pixel_with_offset(hex_coord)

	instance._exploration._select_party_member("player_0")
	var exploration_path_world_pos: Vector2 = instance._game_camera._target_pos

	var actor = _find_combatant_by_id(instance, "player_0")
	assert_not_null(actor, "fixture assumption: 'player_0' must be a live Combatant in _party")
	instance._on_active_actor_changed(actor)
	var combat_path_world_pos: Vector2 = instance._game_camera._target_pos

	assert_eq(exploration_path_world_pos, bounds_path_world_pos,
		"ExplorationModeController's camera-follow conversion must match the bounds-computation conversion for player_0's hex")
	assert_eq(combat_path_world_pos, bounds_path_world_pos,
		"MainScene's combat camera-follow conversion must match the bounds-computation conversion for player_0's hex")
