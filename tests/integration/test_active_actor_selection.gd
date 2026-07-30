extends GutTest
## tests/integration/test_active_actor_selection.gd — FEAT-008 (US-008 /
## FR-008, ADR-005): "Auto-select active actor's ring and status highlight
## in combat" — MainScene's AutoSelectActiveActorUseCase.
##
## Boots the REAL, shipped res://MainScene.tscn composition root headless
## (mirroring tests/integration/test_movement_affordance_integration.gd's
## and tests/infrastructure/test_presentation_stack_wiring.gd's
## `_boot_main_scene_with_seed()` fixture convention) with NO stub/mock
## standing in for HexGridView, StatusPanelView, or TurnController -- proving
## the auto-select behavior works end-to-end through the exact
## TurnController.active_actor_changed signal wiring a real player turn
## drives, not merely through MainScene.gd's handler method signature in
## isolation.
##
## Because TurnController's own auto-drive loop (presentation/
## turn_controller.gd's _drive()) NEVER actually settles/emits
## active_actor_changed while an Enemy is current_actor() -- it auto-resolves
## every consecutive Enemy turn internally and only emits once it settles
## back on a Player (or the round ends) -- this suite drives
## MainScene._on_active_actor_changed() directly with the REAL, live
## Combatant instances drawn from the booted instance's own `_party`/
## `_enemies` arrays for the enemy-turn and subsequent-player-turn
## scenarios. This is the deterministic technique the design notes call for
## (RISK-002: "avoiding flicker/race conditions from mid-signal mutation") --
## it exercises the exact handler TurnController's signal is wired to,
## against real domain Combatant entities, without depending on the AI's
## own nondeterministic-looking multi-turn drive to happen to produce an
## observable mid-drive enemy actor.
##
## Verifies (test_criteria):
##   1. Boot into prologue/combat entry with a player actor active:
##      hex_grid_view and status_panel_view both reflect actor.combatant_id.
##   2. Enemy turn: active_actor_changed fires (handler invoked) for an enemy
##      actor and neither hex_grid_view nor status_panel_view selection
##      changes from the prior state.
##   3. Subsequent player turn: ring and status highlight shift to the new
##      active player actor's combatant_id.
##   4. Selection consistency invariant holds after each transition:
##      hex_grid_view.get_selected_combatant() ==
##      status_panel_view.get_selected_combatant_id() whenever a change
##      occurs.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


## _boot_main_scene_with_seed(seed_value) -> Node — boots the real
## MainScene.tscn, pinned to seed=42 (the prologue fixture's known-good
## seed, matching this codebase's established convention -- see
## tests/integration/test_movement_affordance_integration.gd), triggers the
## real exploration->combat handoff via _on_combat_triggered("prologue"),
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
# Criterion 1 — booting into combat with a player actor active reflects that
# actor's combatant_id on BOTH hex_grid_view and status_panel_view.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_into_combat_with_player_active_selects_that_players_ring_and_highlight() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var actor = instance.round_session.current_actor_entity()
	assert_not_null(actor, "fixture assumption: a live current actor must be seated at boot")
	assert_false(actor.is_enemy, "fixture assumption: the first actor at seed=42 is a living player combatant (Titus)")
	assert_eq(actor.combatant_id, "player_0", "fixture assumption: Titus is party index 0 -> combatant_id 'player_0'")

	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), actor.combatant_id,
		"hex_grid_view's selection ring must reflect the active player actor's combatant_id at combat entry"
	)
	assert_eq(
		instance.status_panel_view.get_selected_combatant_id(), actor.combatant_id,
		"status_panel_view's gold highlight must reflect the active player actor's combatant_id at combat entry"
	)
	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), instance.status_panel_view.get_selected_combatant_id(),
		"selection consistency invariant: hex_grid_view and status_panel_view selections must be equal"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — an enemy actor becoming active leaves both selections
# unchanged from whatever the prior (player) selection was.
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_turn_leaves_hex_grid_and_status_panel_selection_unchanged() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var player_actor = instance.round_session.current_actor_entity()
	assert_false(player_actor.is_enemy, "fixture assumption: boot settles on the player Titus")

	var prior_hex_selection: String = instance.hex_grid_view.get_selected_combatant()
	var prior_status_selection: String = instance.status_panel_view.get_selected_combatant_id()
	assert_eq(prior_hex_selection, "player_0", "sanity check: prior selection is Titus per criterion 1")

	var enemy_actor = _find_combatant_by_id(instance, "enemy_0")
	assert_not_null(enemy_actor, "fixture assumption: prologue_encounter.tres seats a live 'enemy_0' (Skeleton)")
	assert_true(enemy_actor.is_enemy, "fixture assumption: 'enemy_0' is on the Enemy team")

	# Drive the SAME handler TurnController.active_actor_changed is wired to
	# (see this file's header doc for why an enemy actor is exercised via a
	# direct handler call rather than waiting on TurnController's own
	# auto-drive loop, which never emits mid-Enemy-run).
	instance._on_active_actor_changed(enemy_actor)
	await get_tree().process_frame

	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), prior_hex_selection,
		"an enemy actor's turn must NOT change hex_grid_view's selection ring"
	)
	assert_eq(
		instance.status_panel_view.get_selected_combatant_id(), prior_status_selection,
		"an enemy actor's turn must NOT change status_panel_view's gold highlight"
	)
	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), instance.status_panel_view.get_selected_combatant_id(),
		"selection consistency invariant must still hold after an enemy turn (no divergence introduced)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — a subsequent player turn (a different party member) shifts
# the ring/highlight to that new active player actor's combatant_id.
# ══════════════════════════════════════════════════════════════════════════

func test_subsequent_player_turn_shifts_ring_and_highlight_to_the_new_active_actor() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	# Deterministic player -> enemy -> player sequence, per this feature's
	# own test_criteria (mirrors criterion 2's direct-handler-call technique
	# for the enemy leg, then follows with a second, DIFFERENT party
	# member's turn).
	var enemy_actor = _find_combatant_by_id(instance, "enemy_0")
	instance._on_active_actor_changed(enemy_actor)
	await get_tree().process_frame

	var next_player_actor = _find_combatant_by_id(instance, "player_1")
	assert_not_null(next_player_actor, "fixture assumption: prologue_encounter.tres seats a live 'player_1' (Marigold)")
	assert_false(next_player_actor.is_enemy, "fixture assumption: 'player_1' is on the Player team")

	instance._on_active_actor_changed(next_player_actor)
	await get_tree().process_frame

	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), "player_1",
		"hex_grid_view's selection ring must shift to the new active player actor's combatant_id"
	)
	assert_eq(
		instance.status_panel_view.get_selected_combatant_id(), "player_1",
		"status_panel_view's gold highlight must shift to the new active player actor's combatant_id"
	)
	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), instance.status_panel_view.get_selected_combatant_id(),
		"selection consistency invariant must hold after the subsequent player turn transition"
	)
