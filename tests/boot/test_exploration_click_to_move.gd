extends GutTest
## tests/boot/test_exploration_click_to_move.gd — FEAT-007 (US-006 / FR-005).
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root's `_on_exploration_hex_clicked(hex_coord)` handler (wired to
## `hex_grid_view.hex_clicked` by FEAT-006's `_boot_exploration_mode()`) now
## actually drives movement instead of being a no-op stub:
##
##   - While `_game_mode == GameMode.EXPLORATION`, clicking an adjacent hex
##     calls `exploration_controller.move_party_member()` for `_party[0]`
##     (Titus, "player_0") and repositions his rendered token via
##     `hex_grid_view.move_token()` on success.
##   - Clicking a non-adjacent hex is a silent no-op (FEAT-005's fail-closed
##     contract): no token movement, no error.
##   - While `_game_mode == GameMode.COMBAT`, the handler must return before
##     ever touching `exploration_controller` at all -- verified with a spy
##     substituted for the real `exploration_controller`, asserting its
##     `move_party_member()` is never invoked.
##
## Mirrors tests/boot/test_boot_exploration_mode.gd's established
## `_boot_main_scene()` convention (real MainScene.tscn, never a hand-wired
## double, for the boot/composition-root assertions).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_boot_exploration_mode.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


## _ExplorationControllerSpy — a hand-written spy (this codebase's
## established convention for call-count assertions, e.g.
## tests/gut/test_cancel_controller_integration.gd's `select_target_call_count`
## pattern, rather than a mocking framework). Records every
## `move_party_member()` invocation so a test can assert it was NEVER
## called, without depending on any real ScenarioSession state.
class _ExplorationControllerSpy:
	var move_party_member_call_count: int = 0

	func move_party_member(_combatant_id: String, _target_hex) -> bool:
		move_party_member_call_count += 1
		return false


# ══════════════════════════════════════════════════════════════════════════
# EXPLORATION mode: clicking an adjacent hex moves Titus's rendered token.
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_adjacent_hex_moves_titus_token_to_that_hex() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "fixture assumption: boot must default to EXPLORATION mode")

	var titus_token = instance.hex_grid_view.get_token("player_0")
	assert_not_null(titus_token, "fixture assumption: Titus' token (player_0) must be rendered at boot")
	assert_eq(titus_token.hex_coord.q, 0, "fixture assumption: Titus starts at (0, 0)")
	assert_eq(titus_token.hex_coord.r, 0, "fixture assumption: Titus starts at (0, 0)")

	# (1, 0) is hex-distance 1 from Titus' authored start hex (0, 0) and is
	# NOT one of the prologue scenario's authored proximity-trigger hexes
	# (data/scenarios/prologue_scenario.tres), so this move cannot also
	# trigger a combat handoff and confound the assertion below.
	var target := HexCoordClass.new(1, 0)
	instance._on_exploration_hex_clicked(target)

	assert_eq(instance.scenario_session.party_hex_positions["player_0"].q, 1, "ExplorationController.move_party_member must update Titus' session position")
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "ExplorationController.move_party_member must update Titus' session position")

	var moved_token = instance.hex_grid_view.get_token("player_0")
	assert_eq(moved_token.hex_coord.q, 1, "Titus' rendered token must be repositioned to the clicked adjacent hex")
	assert_eq(moved_token.hex_coord.r, 0, "Titus' rendered token must be repositioned to the clicked adjacent hex")


# ══════════════════════════════════════════════════════════════════════════
# EXPLORATION mode: clicking a non-adjacent hex is a silent no-op.
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_non_adjacent_hex_produces_no_token_movement_and_no_error() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "fixture assumption: boot must default to EXPLORATION mode")

	# (5, 5) is far outside hex-distance 1 from Titus' authored start hex
	# (0, 0) -- an illegal move under ExplorationController.move_party_member's
	# fail-closed adjacency contract.
	var target := HexCoordClass.new(5, 5)
	instance._on_exploration_hex_clicked(target)

	assert_eq(instance.scenario_session.party_hex_positions["player_0"].q, 0, "an illegal (non-adjacent) click must leave Titus' session position untouched")
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "an illegal (non-adjacent) click must leave Titus' session position untouched")

	var titus_token = instance.hex_grid_view.get_token("player_0")
	assert_eq(titus_token.hex_coord.q, 0, "an illegal (non-adjacent) click must produce no rendered token movement")
	assert_eq(titus_token.hex_coord.r, 0, "an illegal (non-adjacent) click must produce no rendered token movement")

	assert_eq(get_logger().get_errors().size(), 0, "an illegal (non-adjacent) click is a silent UX no-op, not a developer-facing push_error")


# ══════════════════════════════════════════════════════════════════════════
# COMBAT mode: the handler never calls ExplorationController.move_party_member
# at all (mock/spy assertion).
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_any_hex_in_combat_mode_never_calls_move_party_member() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var spy := _ExplorationControllerSpy.new()
	instance.exploration_controller = spy
	instance._game_mode = MainSceneClass.GameMode.COMBAT

	instance._on_exploration_hex_clicked(HexCoordClass.new(1, 0))

	assert_eq(spy.move_party_member_call_count, 0, "the handler must return before ever touching exploration_controller while _game_mode == COMBAT")
