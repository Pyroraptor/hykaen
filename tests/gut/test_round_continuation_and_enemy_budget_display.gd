extends GutTest
## tests/gut/test_round_continuation_and_enemy_budget_display.gd
##
## Real-play regression coverage for the two Iteration-H "Part A" defects that
## survived the sprint's 1408/1408 headless suite and were only caught in
## interactive play (fixed 2026-07-08):
##
##   1. ROUND STALL — when the player ends their turn and every living combatant
##      is now Spent, the round must roll over into the next round. The bug:
##      MainScene._on_end_turn_control_turn_ended() bailed with a bare `return`
##      the instant round_session.is_round_over() went true, but the round_over
##      signal only ever fires from inside TurnController._drive() (which that
##      early return skips) — so _on_round_over()'s finish()/ROUND_NUMBER++/
##      rewire_session() continuation never ran and the game wedged ("End Turn
##      does nothing, no Round 2"). Fixed by invoking _on_round_over() directly.
##
##   2. ENEMY-STRIDE DISPLAY — an enemy Stride/WAIT resolved through
##      RoundSession.advance_ai_turn() spends a budget action but emits NO event
##      (unlike a Strike's AttackEvent, or a player Stride's inline push), so the
##      enemy's StatusPanelView row went stale. Fixed by MainScene re-pushing
##      every combatant's budget (RoundSession.action_budget_snapshot()) once
##      control settles back on the player after any auto-driven AI turn.
##
## Both tests boot the REAL, shipped res://MainScene.tscn composition root
## headless (the same fixture convention as tests/gut/test_end_turn_integration.gd),
## driving the exact objects a real player drives — no stubs — because that is
## the only level at which either defect actually manifests.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const PLAYER_SEED: int = 42
const END_TURN: String = "END_TURN"


## _boot_main_scene_with_seed(seed_value) -> Node — instantiates the REAL
## res://MainScene.tscn composition root, pinned to the prologue's known-good
## seed (matching tests/gut/test_end_turn_integration.gd).
## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): MainScene now
## boots into EXPLORATION mode with round_session/verb_bar_view/
## selection_overlay/turn_controller signal wiring gated behind a real
## _on_combat_triggered() handoff (see MainScene.gd's own FEAT-316 doc). Both
## tests below drive `round_session`/`verb_bar_view` directly, so this helper
## now also drives the SAME real handoff tests/boot/
## test_exploration_to_combat_handoff_trigger.gd exercises directly, landing
## the instance in GameMode.COMBAT with a live round_session before returning.
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


## _force_all_spent(instance) — drives every combatant's ActionEconomy to Spent
## via the public spend_reaction() path (deliberately NOT spend_action(): reaction
## spends are gated ONLY by _is_spent, never the per-turn _action_used gate, so
## they can be applied in a tight loop from a test without staging start_of_turn()
## boundaries). These are the SAME economy instances RoundSession reads, since
## MainScene's _EncounterTurnOrderAdapter hands the session
## encounter.get_action_economy(i) directly (MainScene.gd).
func _force_all_spent(instance) -> void:
	var order: Array = instance.encounter.get_turn_order()
	for i in range(order.size()):
		var action_economy = instance.encounter.get_action_economy(i)
		while not action_economy.is_spent():
			action_economy.spend_reaction()


## _enemy_index(instance) -> int — turn-order index of the (first) enemy, or -1.
func _enemy_index(instance) -> int:
	var order: Array = instance.encounter.get_turn_order()
	for i in range(order.size()):
		if order[i].is_enemy:
			return i
	return -1


## _enemy_combatant_id(instance) -> String — the combatant_id of the (first)
## enemy in turn order, resolved via the SAME "combatant_id else name" fallback
## RoundSession.action_budget_snapshot() and the AI path use, so it matches the
## key StatusPanelView rows are stored under.
func _enemy_combatant_id(instance) -> String:
	var i: int = _enemy_index(instance)
	if i == -1:
		return ""
	var combatant = instance.encounter.get_turn_order()[i]
	return combatant.display_id()


## _displayed_budget(instance, combatant_id) -> int — the action budget currently
## rendered on that combatant's StatusPanelView row, or -1 if it has no row.
func _displayed_budget(instance, combatant_id: String) -> int:
	return instance.status_panel_view.get_status(combatant_id).get("action_budget_remaining", -1)


## _snapshot_remaining(instance, combatant_id) -> int — the live action budget
## RoundSession reports for a combatant, or -1 if not present.
func _snapshot_remaining(instance, combatant_id: String) -> int:
	for row in instance.round_session.action_budget_snapshot():
		if row["combatant_id"] == combatant_id:
			return row["remaining"]
	return -1


# ══════════════════════════════════════════════════════════════════════════
# Defect 1 — ending the turn with every actor Spent begins the NEXT round
# (rather than stalling with End Turn doing nothing).
# ══════════════════════════════════════════════════════════════════════════

func test_ending_turn_with_all_actors_spent_begins_the_next_round() -> void:
	var instance = await _boot_main_scene_with_seed(PLAYER_SEED)
	await get_tree().process_frame

	assert_eq(instance.ROUND_NUMBER, 1, "fixture assumption: the encounter opens in round 1")
	assert_false(instance.round_session.current_actor().is_enemy, "fixture assumption: the player (Titus) is the current actor before End Turn")

	# Precondition: every living combatant is Spent, so the player's End Turn
	# below advances the cursor to nobody and drives the round over.
	_force_all_spent(instance)
	assert_false(instance.round_session.is_round_over(), "the round is not over until the cursor is actually advanced off the last actor")

	instance.verb_bar_view.press(END_TURN)
	await get_tree().process_frame

	assert_eq(
		instance.ROUND_NUMBER, 2,
		"ending the turn with all actors Spent must roll the encounter into round 2 (regression: the round-over transition was swallowed and the game stalled)"
	)
	assert_false(
		instance.round_session.is_round_over(),
		"the freshly begun round 2 must be a LIVE session, not left reporting round-over"
	)
	assert_false(
		instance.round_session.current_actor() == null,
		"round 2 must sit on a live current actor ready to act"
	)

	# Round 2 granted fresh, un-Spent budgets to everyone (the continuation ran
	# finish()->begin_round()'s per-round budget reset, not just an incremented
	# counter).
	var order: Array = instance.encounter.get_turn_order()
	for i in range(order.size()):
		assert_false(
			instance.encounter.get_action_economy(i).is_spent(),
			"round 2 must grant a fresh un-Spent action budget to every combatant"
		)


# ══════════════════════════════════════════════════════════════════════════
# Defect 2 — a NO-EVENT enemy budget spend (as an enemy Stride or WAIT is:
# unlike a Strike, it emits no AttackEvent) must still be reflected on the
# enemy's StatusPanelView row once control settles back on the player.
#
# This is driven deterministically rather than through the live AI: at the
# prologue's seed the enemy starts adjacent and STRIKES, whose AttackEvent
# already self-updates the row (masking the bug). To exercise the actual gap we
# spend the enemy's budget through the SAME economy the session holds, via
# spend_reaction() — which, exactly like a Stride/WAIT, drops the budget with no
# status event — then fire the SAME settle handler TurnController.active_actor_changed
# invokes when it lands back on the player after an AI turn.
# ══════════════════════════════════════════════════════════════════════════

func test_no_event_enemy_spend_is_synced_to_the_status_row_on_settle() -> void:
	var instance = await _boot_main_scene_with_seed(PLAYER_SEED)
	await get_tree().process_frame

	var enemy_index: int = _enemy_index(instance)
	assert_ne(enemy_index, -1, "fixture assumption: an enemy combatant exists in turn order")
	var enemy_id: String = _enemy_combatant_id(instance)
	assert_eq(_displayed_budget(instance, enemy_id), 7, "fixture assumption: the enemy row starts at the full 7-action budget (also proves the row is keyed under the id the fix pushes to)")

	# Simulate the enemy Stride/WAIT: spend one budget action with NO event
	# emitted (the exact condition that left the row stale). spend_reaction()
	# draws from the same shared per-round budget and is gated only by is_spent,
	# so it needs no per-turn staging.
	instance.encounter.get_action_economy(enemy_index).spend_reaction()

	assert_eq(_snapshot_remaining(instance, enemy_id), 6, "guard: the enemy's live economy is now 6")

	# Control settles back on the player after an AI turn — the moment MainScene
	# must re-push every combatant's budget to the panel.
	instance._on_active_actor_changed(instance.round_session.current_actor_entity())

	assert_eq(
		_displayed_budget(instance, enemy_id), 6,
		"the enemy's displayed action budget must sync to its live economy (6) on settle (regression: a no-event Stride/WAIT left the row stale at 7)"
	)
	assert_eq(
		_displayed_budget(instance, enemy_id), _snapshot_remaining(instance, enemy_id),
		"the displayed budget must equal the session's live budget for the enemy"
	)
