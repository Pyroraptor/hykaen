extends GutTest
## tests/boot/test_exploration_to_combat_handoff.gd — FEAT-010 (US-009 /
## FR-009).
##
## The steel thread's FINAL integration smoke test: exercises the complete
## exploration -> trigger -> combat -> completion -> exploration round trip
## against the REAL, shipped res://MainScene.tscn composition root (never a
## mocked/hand-wired double), confirming FEAT-006..FEAT-009's individually
## proven slices compose into one working end-to-end flow with no earlier
## story regressed (RISK-005 confirmation-only role — this file introduces
## no new production behavior of its own).
##
## Unlike tests/boot/test_exploration_to_combat_handoff_trigger.gd (FEAT-008,
## which drives the handoff by calling `_on_combat_triggered()` directly)
## and tests/boot/test_post_combat_return_to_exploration.gd (FEAT-009, which
## enters combat the same direct way), this file drives the ENTRY into
## combat through the genuine player-facing path: real, stepwise adjacent
## hex clicks via `_on_exploration_hex_clicked()`, exactly as a person
## clicking the battlefield would, so `ExplorationController`'s own
## adjacency + trigger-membership logic is exercised for real, not bypassed.
##
## Fixture geometry (data/scenarios/prologue_scenario.tres,
## data/scenarios/prologue_scenario.tres' authored trigger_hexes, mirrors
## tests/boot/test_boot_exploration_mode.gd's established fixture-assumption
## constants):
##   - Titus (player_0) starts at (0, 0) (authored start hex).
##   - (1, -1) is hex-distance 1 from (0, 0) and is NOT an authored
##     trigger_hexes member -- a genuine intermediate, non-triggering step.
##   - (1, -2) is hex-distance 1 from (1, -1) and IS an authored
##     trigger_hexes member for the "prologue" encounter entry -- entering
##     it is what fires `combat_triggered`.
## So the two-hop path (0,0) -> (1,-1) -> (1,-2) is a genuine "stepwise
## adjacent-hex clicks toward the trigger ring" walk, not a single click
## landing directly on a trigger hex.
##
## Mirrors this project's established `_boot_main_scene()` convention (real
## MainScene.tscn via ResourceLoader.load() + instantiate(), pinned
## seed_override=42) used by every other boot-real suite in this directory.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors every other boot-real suite's identically-named/valued
## constant).
const PROLOGUE_SEED: int = 42

const PROLOGUE_ENCOUNTER_ID: String = "prologue"

## The genuine two-hop path from Titus' authored start hex (0, 0) into the
## prologue encounter's trigger ring -- see file-level doc for the geometry
## proof. INTERMEDIATE_HEX is adjacent to START_HEX and is NOT itself a
## trigger hex; TRIGGER_HEX is adjacent to INTERMEDIATE_HEX and IS an
## authored trigger_hexes member.
const START_HEX := Vector2i(0, 0)
const INTERMEDIATE_HEX := Vector2i(1, -1)
const TRIGGER_HEX := Vector2i(1, -2)


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


## _click(instance, hex) -> void — a single real, stepwise exploration hex
## click via the SAME `_on_exploration_hex_clicked()` entry point a real
## player's mouse click on hex_grid_view routes through (FEAT-007).
func _click(instance, hex: Vector2i) -> void:
	instance._on_exploration_hex_clicked(HexCoordClass.new(hex.x, hex.y))


## _drive_titus_into_the_trigger_ring(instance) -> void — the genuine,
## stepwise two-hop walk (0,0) -> (1,-1) -> (1,-2) described in the
## file-level doc. Each click goes through the REAL
## `ExplorationController.move_party_member()` -> `_evaluate_triggers()`
## path; the second click is the one that actually fires
## `combat_triggered`, so this helper awaits two process frames afterward
## for `_on_combat_triggered()`'s own coroutine (rewire_session(), etc.) to
## finish -- mirrors tests/boot/test_exploration_to_combat_handoff_trigger.gd's
## established await convention.
func _drive_titus_into_the_trigger_ring(instance) -> void:
	_click(instance, INTERMEDIATE_HEX)
	await get_tree().process_frame

	_click(instance, TRIGGER_HEX)
	await get_tree().process_frame
	await get_tree().process_frame


## _force_win(instance) -> void — zeroes every live enemy Combatant's
## hp_current then ends the current actor's turn via the real
## $EndTurnControl node, exactly mirroring
## tests/boot/test_post_combat_return_to_exploration.gd's established
## `_force_win()` helper: DetermineOutcomeUseCase.classify() resolves to
## "won" on the very next end_current_turn() call, with no dependency on any
## seed-specific attack-roll outcome.
func _force_win(instance) -> void:
	for enemy in instance._enemies:
		enemy.hp_current = 0
	instance.end_turn_control.press()


# ══════════════════════════════════════════════════════════════════════════
# ENTRY POINT: scene load boots into EXPLORATION with Titus at the authored
# start hex.
# ══════════════════════════════════════════════════════════════════════════

func test_entry_point_boots_into_exploration_with_titus_at_authored_start_hex() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "the steel thread's entry point must boot into GameMode.EXPLORATION")

	var titus_token = instance.hex_grid_view.get_token("player_0")
	assert_not_null(titus_token, "Titus' token (player_0) must be rendered at boot")
	assert_eq(titus_token.hex_coord.q, START_HEX.x, "Titus must start at the authored start hex")
	assert_eq(titus_token.hex_coord.r, START_HEX.y, "Titus must start at the authored start hex")

	assert_eq(
		instance.scenario_session.party_hex_positions["player_0"].q, START_HEX.x,
		"scenario_session must seed Titus' session position at the authored start hex"
	)
	assert_eq(
		instance.scenario_session.party_hex_positions["player_0"].r, START_HEX.y,
		"scenario_session must seed Titus' session position at the authored start hex"
	)


# ══════════════════════════════════════════════════════════════════════════
# Stepwise adjacent-hex clicks move Titus toward the trigger ring without
# error.
# ══════════════════════════════════════════════════════════════════════════

func test_stepwise_adjacent_click_moves_titus_without_error() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	_click(instance, INTERMEDIATE_HEX)
	await get_tree().process_frame

	var titus_token = instance.hex_grid_view.get_token("player_0")
	assert_eq(titus_token.hex_coord.q, INTERMEDIATE_HEX.x, "the first stepwise click must move Titus' token to the intermediate hex")
	assert_eq(titus_token.hex_coord.r, INTERMEDIATE_HEX.y, "the first stepwise click must move Titus' token to the intermediate hex")

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "a non-trigger intermediate hex must not enter combat")
	assert_eq(get_logger().get_errors().size(), 0, "a legal stepwise move must produce no developer-facing errors")


# ══════════════════════════════════════════════════════════════════════════
# Entering the trigger hex hands off into COMBAT with enemy tokens and an
# active TurnController/round_session.
# ══════════════════════════════════════════════════════════════════════════

func test_entering_the_trigger_hex_hands_off_into_combat_with_active_turn_controller() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	await _drive_titus_into_the_trigger_ring(instance)

	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "entering the authored trigger hex must switch _game_mode to COMBAT")
	assert_eq(instance._active_encounter_id, PROLOGUE_ENCOUNTER_ID, "the real handoff must record the prologue encounter_id as active")

	var enemy_token = instance.hex_grid_view.get_token("enemy_0")
	assert_not_null(enemy_token, "enemy token(s) must be rendered once combat is entered")
	assert_true(instance._enemies.size() >= 1, "at least one live enemy Combatant must be assembled by the real handoff")

	assert_not_null(instance.round_session, "a live round_session must exist once combat is entered")
	assert_not_null(instance.turn_controller, "the composition root's TurnController must be wired")

	var actor = instance.round_session.current_actor()
	assert_not_null(actor, "round_session.current_actor() must return a live Combatant -- TurnController/initiative is active")
	assert_is(actor, CombatantClass, "current_actor() must be a real Combatant instance")

	var roster_ids: Array = []
	for combatant in instance._party + instance._enemies:
		roster_ids.append(combatant.combatant_id)
	assert_true(roster_ids.has(actor.combatant_id), "current_actor() must belong to this handoff's freshly assembled roster")


# ══════════════════════════════════════════════════════════════════════════
# Simulated encounter resolution returns _game_mode to EXPLORATION.
# ══════════════════════════════════════════════════════════════════════════

func test_resolving_the_encounter_returns_game_mode_to_exploration() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	await _drive_titus_into_the_trigger_ring(instance)
	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: the handoff into combat must have succeeded")

	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "resolving the encounter (a 'won' outcome) must return _game_mode to EXPLORATION")
	assert_eq(instance._active_encounter_id, "", "resolving the encounter must clear _active_encounter_id")

	var enemy_token = instance.hex_grid_view.get_token("enemy_0")
	assert_null(enemy_token, "resolving the encounter must remove the defeated encounter's enemy token(s)")


# ══════════════════════════════════════════════════════════════════════════
# ScenarioSession.completed_encounter_ids records the prologue encounter_id
# post-resolution.
# ══════════════════════════════════════════════════════════════════════════

func test_completed_encounter_ids_records_the_prologue_encounter_post_resolution() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_false(
		instance.scenario_session.completed_encounter_ids.has(PROLOGUE_ENCOUNTER_ID),
		"fixture assumption: the encounter must not already be marked complete before it is resolved"
	)

	await _drive_titus_into_the_trigger_ring(instance)
	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(
		instance.scenario_session.completed_encounter_ids.has(PROLOGUE_ENCOUNTER_ID),
		"resolving the encounter must record its encounter_id in ScenarioSession.completed_encounter_ids"
	)


# ══════════════════════════════════════════════════════════════════════════
# EXIT POINT: re-entering the trigger hex after completion does not
# re-enter COMBAT.
# ══════════════════════════════════════════════════════════════════════════

func test_reentering_the_trigger_hex_after_completion_does_not_reenter_combat() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	watch_signals(instance.exploration_controller)

	await _drive_titus_into_the_trigger_ring(instance)
	assert_signal_emit_count(instance.exploration_controller, "combat_triggered", 1, "fixture assumption: exactly one combat_triggered emission for the first entry")

	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "fixture assumption: resolution must have returned to EXPLORATION")

	# Step off the (now-completed) trigger hex onto the same non-trigger
	# intermediate hex used on the way in, then back onto TRIGGER_HEX -- a
	# genuine re-entry attempt through the REAL click path, not merely a
	# zero-distance non-move.
	_click(instance, INTERMEDIATE_HEX)
	await get_tree().process_frame

	_click(instance, TRIGGER_HEX)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"re-entering an already-completed encounter's trigger hex must NOT re-enter COMBAT (exit-point invariant)"
	)
	assert_signal_emit_count(
		instance.exploration_controller, "combat_triggered", 1,
		"re-entering an already-completed encounter's trigger hex must not emit a second combat_triggered"
	)

	var titus_token = instance.hex_grid_view.get_token("player_0")
	assert_eq(titus_token.hex_coord.q, TRIGGER_HEX.x, "fixture assumption: the re-entry click must still move Titus onto the trigger hex")
	assert_eq(titus_token.hex_coord.r, TRIGGER_HEX.y, "fixture assumption: the re-entry click must still move Titus onto the trigger hex")


# ══════════════════════════════════════════════════════════════════════════
# CAPSTONE: the complete entry-point-to-exit-point round trip in one
# continuous run, confirming every stage composes end to end with nothing
# hand-wired/mocked (RISK-005 confirmation-only role).
# ══════════════════════════════════════════════════════════════════════════

func test_full_exploration_to_combat_to_exploration_round_trip() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# Entry point: EXPLORATION, Titus at the authored start hex.
	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "entry point must boot into EXPLORATION")
	var titus_start = instance.hex_grid_view.get_token("player_0")
	assert_eq(titus_start.hex_coord.q, START_HEX.x, "entry point: Titus must start at the authored start hex")
	assert_eq(titus_start.hex_coord.r, START_HEX.y, "entry point: Titus must start at the authored start hex")

	# Stepwise adjacent clicks toward the trigger ring.
	await _drive_titus_into_the_trigger_ring(instance)

	# Real handoff into COMBAT.
	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "stepwise clicks into the trigger ring must hand off into COMBAT")
	assert_not_null(instance.hex_grid_view.get_token("enemy_0"), "enemy tokens must be present after the handoff")
	var actor = instance.round_session.current_actor()
	assert_not_null(actor, "TurnController/current_actor() must be active after the handoff")

	# Resolve the encounter.
	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	# Return to EXPLORATION with the encounter recorded complete.
	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "resolving the encounter must return to EXPLORATION")
	assert_true(
		instance.scenario_session.completed_encounter_ids.has(PROLOGUE_ENCOUNTER_ID),
		"the prologue encounter_id must be recorded complete post-resolution"
	)

	# Exit point: re-entering the trigger hex does not re-enter combat.
	_click(instance, INTERMEDIATE_HEX)
	await get_tree().process_frame
	_click(instance, TRIGGER_HEX)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"exit point: re-entering the completed trigger hex must never re-enter COMBAT"
	)
