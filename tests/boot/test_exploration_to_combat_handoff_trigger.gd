extends GutTest
## tests/boot/test_exploration_to_combat_handoff_trigger.gd — FEAT-008
## (US-007 / FR-006).
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root's `_on_combat_triggered(encounter_id)` handler (wired to
## `exploration_controller.combat_triggered` by FEAT-006's
## `_boot_exploration_mode()`) now drives the full exploration-to-combat
## handoff instead of being a no-op stub (tests/boot/test_boot_exploration_mode.gd's
## `test_combat_triggered_stub_does_not_crash_when_emitted` covers the
## pre-existing stub behavior; this file supersedes it with real assertions).
##
## Per RISK-003 (incremental slices: use-case call -> mode switch -> token
## render -> initiative activation), the FAILURE-path test is written FIRST
## as the safety net every later, successful-path assertion builds on top of.
##
## Mirrors tests/boot/test_exploration_click_to_move.gd's established
## `_boot_main_scene()` convention (real MainScene.tscn, never a hand-wired
## double, for boot/composition-root assertions).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_boot_exploration_mode.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42

const PROLOGUE_ENCOUNTER_ID: String = "prologue"


## before_each()/after_each() — reseed CurrentGameState.data with a fresh
## GameStateDataClass instance so no test in this file (or any test that
## runs before/after it in the full suite) can leak scenario_path/session
## state across test boundaries (ADR-008). Copy-identical to
## tests/boot/test_exploration_to_combat_handoff.gd's established pattern
## (FEAT-002) to avoid divergence (mitigates RISK-008): this guarantees
## _boot_main_scene() -> MainScene._ready() always takes the same
## prologue-fallback boot path regardless of suite ordering.
func before_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func after_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# FAILURE PATH (written first, per RISK-003 mitigation): an unknown
# encounter_id must leave exploration mode completely untouched and must not
# crash the game.
# ══════════════════════════════════════════════════════════════════════════

func test_failed_load_leaves_game_mode_and_active_encounter_id_untouched() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "fixture assumption: boot must default to EXPLORATION mode")
	assert_eq(instance._active_encounter_id, "", "fixture assumption: _active_encounter_id must default unset")

	instance._on_combat_triggered("no-such-encounter-id")
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"a failed LoadScenarioEncounterUseCase (ok=false) must leave _game_mode == EXPLORATION"
	)
	assert_eq(
		instance._active_encounter_id, "",
		"a failed LoadScenarioEncounterUseCase (ok=false) must leave _active_encounter_id unset"
	)


func test_failed_load_reconnects_hex_click_handling_so_exploration_continues() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._on_combat_triggered("no-such-encounter-id")
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(
		instance.hex_grid_view.hex_clicked.is_connected(Callable(instance._exploration, "_on_exploration_hex_clicked")),
		"a failed handoff must re-connect hex_clicked -> _on_exploration_hex_clicked so exploration keeps working"
	)

	# Prove exploration is genuinely still alive, not merely re-connected --
	# an adjacent, non-trigger-hex click still moves Titus' token exactly as
	# tests/boot/test_exploration_click_to_move.gd already proves for a
	# never-triggered boot.
	var target := HexCoordClass.new(1, 0)
	await instance._exploration._on_exploration_hex_clicked(target)

	var moved_token = instance.hex_grid_view.get_token("player_0")
	assert_eq(moved_token.hex_coord.q, 1, "exploration movement must still work after a failed combat handoff")
	assert_eq(moved_token.hex_coord.r, 0, "exploration movement must still work after a failed combat handoff")


# ══════════════════════════════════════════════════════════════════════════
# SUCCESS PATH: a valid trigger commits the mode switch and records the
# active encounter_id.
# ══════════════════════════════════════════════════════════════════════════

func test_valid_trigger_switches_game_mode_to_combat_and_records_active_encounter_id() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "a valid trigger must switch _game_mode to COMBAT")
	assert_eq(instance._active_encounter_id, PROLOGUE_ENCOUNTER_ID, "a valid trigger must record encounter_id in _active_encounter_id")


# ══════════════════════════════════════════════════════════════════════════
# SUCCESS PATH: enemy tokens appear on the SAME HexGridView instance; party
# tokens remain at their pre-handoff (exploration) positions (ADR-001).
# ══════════════════════════════════════════════════════════════════════════

func test_valid_trigger_places_enemy_tokens_and_preserves_party_token_positions() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# Move Titus off his authored start hex first, mirroring
	# tests/boot/test_exploration_click_to_move.gd's established non-trigger
	# adjacent target -- so party token preservation is a MEANINGFUL
	# assertion (not merely "never moved in the first place").
	var target := HexCoordClass.new(1, 0)
	await instance._exploration._on_exploration_hex_clicked(target)
	var titus_token_before = instance.hex_grid_view.get_token("player_0")
	assert_eq(titus_token_before.hex_coord.q, 1, "fixture assumption: Titus must have moved off his authored start hex before the handoff")
	assert_eq(titus_token_before.hex_coord.r, 0, "fixture assumption: Titus must have moved off his authored start hex before the handoff")

	var marigold_token_before = instance.hex_grid_view.get_token("player_1")
	assert_not_null(marigold_token_before, "fixture assumption: Marigold's token must be rendered before the handoff")
	var marigold_hex_before := HexCoordClass.new(marigold_token_before.hex_coord.q, marigold_token_before.hex_coord.r)

	var token_count_before: int = instance.hex_grid_view.get_token_count()

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: the handoff must have succeeded")

	var titus_token_after = instance.hex_grid_view.get_token("player_0")
	assert_eq(titus_token_after.hex_coord.q, 1, "Titus' rendered token must remain at his pre-handoff exploration position (ADR-001)")
	assert_eq(titus_token_after.hex_coord.r, 0, "Titus' rendered token must remain at his pre-handoff exploration position (ADR-001)")

	var marigold_token_after = instance.hex_grid_view.get_token("player_1")
	assert_eq(marigold_token_after.hex_coord.q, marigold_hex_before.q, "Marigold's rendered token must remain at her pre-handoff exploration position (ADR-001)")
	assert_eq(marigold_token_after.hex_coord.r, marigold_hex_before.r, "Marigold's rendered token must remain at her pre-handoff exploration position (ADR-001)")

	var enemy_token = instance.hex_grid_view.get_token("enemy_0")
	assert_not_null(enemy_token, "the encounter's enemy token (enemy_0) must be present on hex_grid_view after the handoff")

	assert_eq(
		instance.hex_grid_view.get_token_count(), token_count_before,
		"add_combatants() must place enemy tokens on the SAME HexGridView instance, never resetting/duplicating existing tokens"
	)

	assert_eq(instance._enemies.size(), 1, "_enemies must contain exactly the 1 live combatant (Skeleton) assembled by this handoff")
	assert_is(instance._enemies[0], CombatantClass, "the assembled enemy must be a live Combatant instance")


# ══════════════════════════════════════════════════════════════════════════
# SUCCESS PATH: TurnController/RoundSession is active with initiative
# rolled -- current_actor() returns a live Combatant from the freshly
# assembled roster.
# ══════════════════════════════════════════════════════════════════════════

func test_valid_trigger_rolls_initiative_and_current_actor_is_a_live_combatant() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_not_null(instance.round_session, "a valid trigger must leave a real, non-null round_session in place")

	var actor = instance.round_session.current_actor()
	assert_not_null(actor, "round_session.current_actor() must return a live Combatant once initiative is rolled")
	assert_is(actor, CombatantClass, "current_actor() must be a real Combatant instance")

	var roster: Array = instance._party + instance._enemies
	var roster_ids: Array = []
	for combatant in roster:
		roster_ids.append(combatant.combatant_id)
	assert_true(
		roster_ids.has(actor.combatant_id),
		"current_actor() must belong to THIS handoff's freshly assembled _party/_enemies roster, not a stale boot-time one"
	)


# ══════════════════════════════════════════════════════════════════════════
# Exploration hex-click handling is disconnected BEFORE the handoff's
# multi-step work begins (guards against a second click racing the handoff).
# ══════════════════════════════════════════════════════════════════════════

func test_hex_click_handling_is_disconnected_before_the_handoff_multistep_work_begins() -> void:
	# Static/code-inspection complement (this codebase's established
	# convention for ordering guarantees -- see e.g.
	# tests/unit/presentation/test_main_scene_load_encounter_from_scenario.gd's
	# own source-substring test): the disconnect statement must appear
	# textually BEFORE the load_encounter_from_scenario() call inside
	# _on_combat_triggered()'s body, proving disconnection is the very first
	# step of the handoff, not something interleaved with or after the
	# use-case call / mode switch / token placement / initiative roll.
	var file := FileAccess.open("res://MainScene.gd", FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	var func_start: int = content.find("func _on_combat_triggered(")
	assert_true(func_start >= 0, "MainScene.gd must declare _on_combat_triggered()")
	var next_func_start: int = content.find("\nfunc ", func_start + 1)
	assert_true(next_func_start > func_start, "must be able to locate the end of _on_combat_triggered()'s body")
	var body: String = content.substr(func_start, next_func_start - func_start)

	var disconnect_index: int = body.find("hex_clicked.disconnect(")
	var load_call_index: int = body.find("load_encounter_from_scenario(")
	assert_true(disconnect_index >= 0, "_on_combat_triggered() must disconnect hex_clicked")
	assert_true(load_call_index >= 0, "_on_combat_triggered() must call load_encounter_from_scenario()")
	assert_true(
		disconnect_index < load_call_index,
		"hex_clicked must be disconnected BEFORE load_encounter_from_scenario() is invoked -- guards against a click racing the handoff"
	)

	# Runtime complement: after a successful handoff, the connection is
	# genuinely gone (not merely textually-ordered-but-never-executed).
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(
		instance.hex_grid_view.hex_clicked.is_connected(Callable(instance._exploration, "_on_exploration_hex_clicked")),
		"a successful handoff must leave hex_clicked disconnected from _on_exploration_hex_clicked"
	)


func test_click_after_successful_handoff_never_reaches_exploration_controller() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	var spy := _ExplorationControllerSpy.new()
	instance.exploration_controller = spy

	# Even a raw click on the (now-disconnected) hex_grid_view must not
	# resolve into exploration movement -- both because the signal is
	# disconnected AND because _on_exploration_hex_clicked's own
	# _game_mode != EXPLORATION guard would reject it if it were somehow
	# still reachable.
	instance._on_exploration_hex_clicked(HexCoordClass.new(2, 0))

	assert_eq(spy.move_party_member_call_count, 0, "a click after a successful combat handoff must never reach ExplorationController.move_party_member")


## _ExplorationControllerSpy — a hand-written spy (this codebase's
## established convention for call-count assertions, mirrors
## tests/boot/test_exploration_click_to_move.gd's identically-named class).
class _ExplorationControllerSpy:
	var move_party_member_call_count: int = 0

	func move_party_member(_combatant_id: String, _target_hex) -> bool:
		move_party_member_call_count += 1
		return false
