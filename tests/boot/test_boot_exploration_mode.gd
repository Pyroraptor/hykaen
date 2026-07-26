extends GutTest
## tests/boot/test_boot_exploration_mode.gd — FEAT-006 (US-005 / FR-004).
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root (never a hand-wired double) now boots into EXPLORATION mode by
## default: `_game_mode` defaults to GameMode.EXPLORATION, a real
## ScenarioSession (FEAT-003) + ExplorationController (FEAT-005) are
## constructed from data/scenarios/prologue_scenario.tres,
## `exploration_controller.combat_triggered` is wired to the (stub)
## `_on_combat_triggered()`, `hex_grid_view.hex_clicked` is wired to the
## (stub) `_on_exploration_hex_clicked()`, and Titus/Marigold/the skeleton
## enemy's tokens are rendered on the hex grid at their authored start
## hexes -- mirroring tests/boot/test_caster_loads_in_prologue.gd's
## established "_boot_main_scene()" convention.
##
## test_criteria covered here:
##   - _game_mode == GameMode.EXPLORATION after _ready().
##   - Titus (party token) and the active-encounter enemy token(s) are
##     rendered at their authored start hexes.
##   - scenario_session/exploration_controller are real, wired instances
##     (not test doubles).
##   - ExplorationController.combat_triggered -> _on_combat_triggered and
##     hex_grid_view.hex_clicked -> _on_exploration_hex_clicked are both
##     genuinely connected on the real, booted composition root.
##   - Regression: the pre-existing hardcoded PROLOGUE_ENCOUNTER_PATH
##     combat-setup pipeline (`_party`/`_enemies`/`round_session`) still
##     boots successfully alongside the new EXPLORATION-mode wiring -- this
##     feature is additive (mirrors FEAT-010's established coexistence
##     precedent in this same file), so it introduces zero regressions in
##     the pre-existing boot-real/GUT suite.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const ExplorationControllerClass = preload("res://core/application/exploration_controller.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_caster_loads_in_prologue.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# _game_mode defaults to GameMode.EXPLORATION after _ready().
# ══════════════════════════════════════════════════════════════════════════

func test_game_mode_defaults_to_exploration_after_ready() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"a freshly-booted MainScene must default to GameMode.EXPLORATION (US-005)"
	)


# ══════════════════════════════════════════════════════════════════════════
# scenario_session / exploration_controller are real, wired instances.
# ══════════════════════════════════════════════════════════════════════════

func test_scenario_session_is_a_real_instance_with_the_prologue_scenario_loaded() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.scenario_session, "MainScene must construct a real scenario_session at boot")
	assert_true(instance.scenario_session is ScenarioSessionClass, "scenario_session must be a real ScenarioSession instance")
	assert_not_null(instance.scenario_session.scenario, "scenario_session.scenario must be populated from PROLOGUE_SCENARIO_PATH")
	assert_eq(instance.scenario_session.scenario.scenario_id, "prologue", "the loaded scenario must be the authored prologue scenario")


func test_scenario_session_party_hex_positions_seeded_from_authored_start_hexes() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = instance.scenario_session.party_hex_positions.get("player_0")
	assert_not_null(titus, "scenario_session.party_hex_positions must be seeded for Titus (player_0)")
	assert_eq(titus.q, 0, "Titus' seeded exploration hex must match his authored start hex (0, 0)")
	assert_eq(titus.r, 0, "Titus' seeded exploration hex must match his authored start hex (0, 0)")

	var marigold = instance.scenario_session.party_hex_positions.get("player_1")
	assert_not_null(marigold, "scenario_session.party_hex_positions must be seeded for Marigold (player_1)")
	assert_eq(marigold.q, -1, "Marigold's seeded exploration hex must match her authored start hex (-1, 0)")
	assert_eq(marigold.r, 0, "Marigold's seeded exploration hex must match her authored start hex (-1, 0)")


func test_exploration_controller_is_a_real_instance_wrapping_scenario_session() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.exploration_controller, "MainScene must construct a real exploration_controller at boot")
	assert_true(
		instance.exploration_controller is ExplorationControllerClass,
		"exploration_controller must be a real ExplorationController instance"
	)


# ══════════════════════════════════════════════════════════════════════════
# combat_triggered -> _on_combat_triggered / hex_clicked -> _on_exploration_hex_clicked
# are genuinely wired on the real, booted composition root.
# ══════════════════════════════════════════════════════════════════════════

func test_combat_triggered_signal_is_connected_to_the_stub_handler() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_true(
		instance.exploration_controller.combat_triggered.is_connected(Callable(instance, "_on_combat_triggered")),
		"exploration_controller.combat_triggered must be connected to MainScene._on_combat_triggered"
	)


## FEAT-324 (resolves DEF-001): hex_clicked is now wired directly to
## ExplorationModeController._on_exploration_hex_clicked (the FEAT-007/008/
##009 pathfinding-driven, animated handler) -- MainScene no longer owns a
## handler of its own for this signal at all (see tests/boot/
## test_exploration_click_wiring.gd for the dedicated wiring suite this
## feature adds).
func test_hex_grid_view_hex_clicked_is_connected_to_the_exploration_stub_handler() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.hex_grid_view, "MainScene must wire a real $HexGridView")
	assert_true(
		instance.hex_grid_view.hex_clicked.is_connected(Callable(instance._exploration, "_on_exploration_hex_clicked")),
		"hex_grid_view.hex_clicked must be connected to ExplorationModeController._on_exploration_hex_clicked"
	)


## FEAT-008 (US-007 / FR-006) superseded `_on_combat_triggered()` with the
## real exploration-to-combat handoff (tests/boot/
## test_exploration_to_combat_handoff_trigger.gd now owns the "a valid
## trigger switches _game_mode to COMBAT" assertion this test originally
## made against the pre-FEAT-008 no-op stub). This test now only re-confirms
## the narrower, still-true safety guarantee: calling the handler is safe
## and never crashes, whatever encounter_id it is given.
func test_combat_triggered_handler_does_not_crash_when_emitted() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	# no crash -- reaching this line is part of the assertion.
	assert_true(
		instance._game_mode == MainSceneClass.GameMode.EXPLORATION or instance._game_mode == MainSceneClass.GameMode.COMBAT,
		"_game_mode must remain a valid GameMode value after the handler runs"
	)


## FEAT-324 (resolves DEF-001): MainScene no longer owns this handler --
## ExplorationModeController._on_exploration_hex_clicked is the ONLY
## click-to-navigate entry point now (see test_exploration_click_wiring.gd).
func test_exploration_hex_clicked_stub_does_not_crash_when_emitted() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	await instance._exploration._on_exploration_hex_clicked(HexCoordClass.new(2, -1))
	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "a non-trigger click must not itself flip _game_mode")


# ══════════════════════════════════════════════════════════════════════════
# Titus (party token) and all active-encounter enemy tokens are rendered at
# their authored start hexes.
# ══════════════════════════════════════════════════════════════════════════

func test_party_and_enemy_tokens_are_rendered_at_authored_start_hexes() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance.hex_grid_view.get_token_count(), 3, "3 combatants (Titus, Marigold, skeleton) must have rendered tokens at boot")

	var titus_token = instance.hex_grid_view.get_token("player_0")
	assert_not_null(titus_token, "Titus' token (player_0) must be rendered")

	var marigold_token = instance.hex_grid_view.get_token("player_1")
	assert_not_null(marigold_token, "Marigold's token (player_1) must be rendered")

	var enemy_token = instance.hex_grid_view.get_token("enemy_0")
	assert_not_null(enemy_token, "the active encounter's enemy token (enemy_0) must be rendered")


# ══════════════════════════════════════════════════════════════════════════
# Regression: the pre-existing hardcoded PROLOGUE_ENCOUNTER_PATH party/enemy
# build still boots successfully alongside the new EXPLORATION-mode wiring
# (mirrors FEAT-010's established coexistence precedent in this same file).
#
# FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): the legacy
# combat PIPELINE itself (round_session / $VerbBarView / $SelectionOverlay /
# turn_controller.round_over+active_actor_changed) is no longer part of that
# "additive" boot -- it now stays gated behind a real _on_combat_triggered()
## handoff (see MainScene.gd's own FEAT-316 doc), so `round_session` is null
# at boot in EXPLORATION mode; only the `_party`/`_enemies` Combatant build
# remains genuinely unconditional. tests/boot/test_combat_pipeline_gated_by_
# game_mode.gd is the dedicated suite for this feature's own gating
# assertions (round_session null / verb bar & selection overlay unconfigured
# / turn_controller signals disconnected at boot, and the full handoff still
# working end to end via _on_combat_triggered()).
# ══════════════════════════════════════════════════════════════════════════

func test_legacy_party_build_still_boots_alongside_exploration_mode_wiring() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_true(instance._party.size() >= 2, "the pre-existing party build must be unaffected by this feature's additive wiring")
	assert_eq(
		instance.round_session, null,
		"round_session must be null at boot (FEAT-316, resolves DEF-001/PR-001) -- the legacy combat pipeline no longer "
		+ "boots unconditionally; see tests/boot/test_combat_pipeline_gated_by_game_mode.gd for full gating coverage"
	)
