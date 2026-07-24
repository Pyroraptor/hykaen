extends GutTest
## tests/boot/test_post_combat_return_to_exploration.gd — FEAT-009
## (US-008 / FR-007).
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root's `_on_round_over()` handler now branches on the just-concluded
## round's outcome and, on a "won" outcome, drives the FULL post-combat
## return-to-exploration handoff (`_on_combat_won()`) — completing the
## exploration<->combat round trip FEAT-008 (US-007) started.
##
## Mirrors tests/boot/test_exploration_to_combat_handoff_trigger.gd's
## established `_boot_main_scene()` convention (real MainScene.tscn, never a
## hand-wired double) and this project's real "drive an actual round to its
## conclusion through the live composition root" style (see
## tests/e2e/test_full_steel_thread_e2e.gd) — the ONE difference is that this
## file forces the winning condition directly (zeroing the live enemy
## Combatant's hp_current) rather than relying on a seed-specific critical
## hit, since this feature's own scope is the POST-round handoff, not how a
## Strike happens to resolve.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_exploration_to_combat_handoff_trigger.gd's
## identically-valued constant).
const PROLOGUE_SEED: int = 42

const PROLOGUE_ENCOUNTER_ID: String = "prologue"


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


## _enter_combat(instance) -> void — drives the SAME real handoff FEAT-008's
## own test file exercises directly (_on_combat_triggered()), landing the
## instance in GameMode.COMBAT with a freshly assembled `_enemies` roster.
func _enter_combat(instance) -> void:
	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)


## _force_win(instance) -> void — zeroes every live enemy Combatant's
## hp_current (the SAME `_enemies` Array `round_session` was begin_round()'d
## with by reference, MainScene.gd's rewire_session() doc) then ends the
## current actor's turn via the real $EndTurnControl node. RoundSession's own
## _after_action_resolved() tail (core/application/round_session.gd) consults
## DetermineOutcomeUseCase.classify(_party, _enemies) on EVERY end_current_turn()
## call, regardless of whether an action was spent — with every enemy's HP
## already at 0, this resolves to "won" and marks the round over immediately,
## without depending on any seed-specific attack-roll outcome.
func _force_win(instance) -> void:
	for enemy in instance._enemies:
		enemy.hp_current = 0
	instance.end_turn_control.press()


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: after a 'won' outcome, _game_mode == EXPLORATION and enemy
# tokens are removed.
# ══════════════════════════════════════════════════════════════════════════

func test_won_outcome_switches_game_mode_back_to_exploration_and_removes_enemy_tokens() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	_enter_combat(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: the handoff into combat must have succeeded")
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter has exactly one enemy")
	var enemy_id: String = instance._enemies[0].combatant_id
	assert_not_null(instance.hex_grid_view.get_token(enemy_id), "fixture assumption: the enemy token must be rendered before the win")

	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"a 'won' outcome must switch _game_mode back to EXPLORATION"
	)
	assert_null(
		instance.hex_grid_view.get_token(enemy_id),
		"a 'won' outcome must remove the defeated encounter's enemy token(s) from hex_grid_view"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 + 3: ScenarioSession.completed_encounter_ids contains the
# just-won encounter_id, and get_active_encounter_entries() no longer
# includes it.
# ══════════════════════════════════════════════════════════════════════════

func test_won_outcome_marks_the_encounter_complete_in_scenario_session() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	_enter_combat(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(
		instance.scenario_session.completed_encounter_ids.has(PROLOGUE_ENCOUNTER_ID),
		"fixture assumption: the encounter must not already be marked complete before it is won"
	)

	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(
		instance.scenario_session.completed_encounter_ids.has(PROLOGUE_ENCOUNTER_ID),
		"a 'won' outcome must add encounter_id to ScenarioSession.completed_encounter_ids"
	)

	var active_ids: Array = []
	for entry in instance.scenario_session.get_active_encounter_entries():
		active_ids.append(entry.encounter_id)
	assert_false(
		active_ids.has(PROLOGUE_ENCOUNTER_ID),
		"get_active_encounter_entries() must no longer include the just-won encounter"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: re-clicking/re-entering the same trigger hex after completion
# does not re-enter COMBAT (no combat_triggered emission, _game_mode stays
# EXPLORATION) — driven through the REAL exploration click path, not a
# direct _on_combat_triggered() call, so ExplorationController's own
# get_active_encounter_entries()-backed exclusion is genuinely exercised.
# ══════════════════════════════════════════════════════════════════════════

func test_reclicking_the_trigger_hex_after_completion_does_not_re_enter_combat() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	watch_signals(instance.exploration_controller)

	# (-1, 0) is one of prologue_scenario.tres' authored trigger_hexes AND is
	# hex-adjacent to Titus' authored start hex (0, 0) — a real click there
	# fires combat_triggered through the genuine
	# ExplorationController.move_party_member() -> _evaluate_triggers() path.
	instance._on_exploration_hex_clicked(HexCoordClass.new(-1, 0))
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: the real click must have triggered combat")
	assert_signal_emit_count(instance.exploration_controller, "combat_triggered", 1, "fixture assumption: exactly one combat_triggered emission for the first entry")

	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "fixture assumption: the win must have returned to EXPLORATION")

	# Step off the trigger hex onto Titus' original (non-trigger) start hex,
	# then back onto a DIFFERENT trigger hex belonging to the SAME (now
	# completed) entry -- proving this is a genuine re-entry attempt, not
	# merely a zero-distance non-move.
	instance._on_exploration_hex_clicked(HexCoordClass.new(0, 0))
	await get_tree().process_frame

	instance._on_exploration_hex_clicked(HexCoordClass.new(0, -1))
	await get_tree().process_frame
	await get_tree().process_frame

	assert_signal_emit_count(
		instance.exploration_controller, "combat_triggered", 1,
		"re-entering an already-completed encounter's trigger hex must NOT emit a second combat_triggered"
	)
	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"re-entering an already-completed encounter's trigger hex must leave _game_mode at EXPLORATION"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: a signal-connection-count assertion confirms no duplicate/
# dangling hex_clicked or combat-signal listeners after teardown+reconnect
# (RISK-010 mitigation).
# ══════════════════════════════════════════════════════════════════════════

func _count_connections(emitter: Object, signal_name: String, target: Object, method_name: String) -> int:
	var count: int = 0
	for connection in emitter.get_signal_connection_list(signal_name):
		var callable: Callable = connection["callable"]
		if callable.get_object() == target and callable.get_method() == method_name:
			count += 1
	return count


func test_teardown_and_reconnect_leaves_no_duplicate_or_dangling_listeners() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(
		_count_connections(instance.hex_grid_view, "hex_clicked", instance, "_on_exploration_hex_clicked"), 1,
		"fixture assumption: exactly one hex_clicked -> _on_exploration_hex_clicked connection at boot"
	)
	# FEAT-316 (resolves DEF-001/PR-001): these two connections are no longer
	# established unconditionally at boot (see MainScene.gd's _ready() /
	# _on_combat_triggered() FEAT-316 doc) -- they stay at zero connections
	# throughout EXPLORATION mode and are only wired the instant a real combat
	# trigger fires, exercised by _enter_combat() below.
	assert_eq(
		_count_connections(instance.turn_controller, "round_over", instance, "_on_round_over"), 0,
		"fixture assumption: zero round_over -> _on_round_over connections at boot (FEAT-316)"
	)
	assert_eq(
		_count_connections(instance.turn_controller, "active_actor_changed", instance, "_on_active_actor_changed"), 0,
		"fixture assumption: zero active_actor_changed -> _on_active_actor_changed connections at boot (FEAT-316)"
	)

	_enter_combat(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(
		_count_connections(instance.hex_grid_view, "hex_clicked", instance, "_on_exploration_hex_clicked"), 0,
		"the exploration-to-combat handoff must leave hex_clicked disconnected from _on_exploration_hex_clicked while in COMBAT"
	)

	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(
		_count_connections(instance.hex_grid_view, "hex_clicked", instance, "_on_exploration_hex_clicked"), 1,
		"after teardown+reconnect, hex_clicked -> _on_exploration_hex_clicked must be connected EXACTLY once (no duplicate, no dangling disconnect)"
	)
	assert_eq(
		_count_connections(instance.turn_controller, "round_over", instance, "_on_round_over"), 1,
		"after teardown+reconnect, round_over -> _on_round_over must be connected EXACTLY once"
	)
	assert_eq(
		_count_connections(instance.turn_controller, "active_actor_changed", instance, "_on_active_actor_changed"), 1,
		"after teardown+reconnect, active_actor_changed -> _on_active_actor_changed must be connected EXACTLY once"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6: a 'lost' outcome triggers push_error with no crash and no
# state corruption; pre-existing '' round-continuation path is unaffected
# (regression check).
# ══════════════════════════════════════════════════════════════════════════

func test_lost_outcome_pushes_error_without_crashing_or_corrupting_state() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	_enter_combat(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: the handoff into combat must have succeeded")
	var encounter_id_before: String = instance._active_encounter_id

	for party_member in instance._party:
		party_member.hp_current = 0
	instance.end_turn_control.press()
	await get_tree().process_frame
	await get_tree().process_frame

	# no crash -- reaching this line is part of the assertion.
	assert_eq(instance.round_session.outcome(), "lost", "fixture assumption: zeroing every party member's HP must decide the round as 'lost'")
	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.COMBAT,
		"the FEAT-009 'lost' placeholder must never mutate _game_mode -- no state corruption"
	)
	assert_eq(
		instance._active_encounter_id, encounter_id_before,
		"the FEAT-009 'lost' placeholder must never mutate _active_encounter_id -- no state corruption"
	)


## test_round_continuation_outcome_is_unaffected_by_this_feature — regression
## check: an undecided ('') round-over must still increment ROUND_NUMBER and
## call rewire_session() exactly as it did before this feature, never routing
## through _on_combat_won() or the 'lost' placeholder.
##
## Each living combatant has its own per-round ActionEconomy budget (up to
## MAX_BUDGET=7 actions, core/rules/action_economy.gd) and `end_current_turn()`
## leaves `is_spent()` untouched when no action was taken (round_session.gd's
## own documented contract) -- so passing a party member's turn once does NOT
## end the round; the turn cursor simply cycles back to them again on a later
## pass. This helper drives that real cycling to its natural conclusion
## (repeatedly passing every living party member's turn, letting
## TurnController auto-drive the Skeleton's own turns exactly as the real
## game would, and declining -- Pass, mirroring a player choosing not to
## react -- any reaction pop-up a Skeleton attack opens) until EITHER
## ROUND_NUMBER first increments (the "" / undecided round-over this test
## exists to verify) or the round is otherwise decided, bounded by `guard` so
## a genuine regression fails fast rather than hanging.
func test_undecided_round_continuation_is_unaffected_by_this_feature() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	_enter_combat(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	var round_number_before: int = instance.ROUND_NUMBER

	var guard: int = 0
	while instance.ROUND_NUMBER == round_number_before and not instance.round_session.is_round_over() and guard < 60:
		var actor = instance.round_session.current_actor()
		if actor != null and not actor.is_enemy:
			instance.end_turn_control.press()
		await get_tree().process_frame
		await get_tree().process_frame

		var reaction_guard: int = 0
		while instance.reaction_prompt_ui != null and instance.reaction_prompt_ui.is_open() and reaction_guard < 5:
			instance.reaction_prompt_ui.press_option("none")
			await get_tree().process_frame
			await get_tree().process_frame
			reaction_guard += 1

		guard += 1

	assert_eq(
		instance.ROUND_NUMBER, round_number_before + 1,
		"fixture assumption: driving the round to its natural conclusion must increment ROUND_NUMBER before the encounter is otherwise decided"
	)
	assert_eq(instance.round_session.outcome(), "", "an undecided ('') round-over must leave the FRESH next round's own outcome undecided too")
	assert_eq(
		instance.ROUND_NUMBER, round_number_before + 1,
		"an undecided ('') round-over must still increment ROUND_NUMBER exactly as before this feature"
	)
	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.COMBAT,
		"an undecided ('') round-over must never switch _game_mode back to EXPLORATION"
	)
