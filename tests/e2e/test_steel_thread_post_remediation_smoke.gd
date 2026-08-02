extends GutTest
## tests/e2e/test_steel_thread_post_remediation_smoke.gd — FEAT-141
## (US-001..US-011, DEF-001..DEF-007, depends_on FIX-001..FIX-006)
##
## Final "steel thread" post-remediation smoke test: boots the REAL,
## shipped res://MainScene.tscn composition root (project.godot's own
## run/main_scene target — no test-local resolver/use-case graph, no mock) and
## proves every one of the individually-shipped remediations (FIX-001
## through FIX-006) still composes correctly end-to-end, in the SAME
## continuous playthrough wherever the test_criteria allow it:
##
##   1. the real MainScene.tscn boots headlessly with no manual setup, pinned
##      to seed=42 via the in-process `seed_override` injection point
##      (infrastructure/seed_policy.gd's ADR-004 top-precedence contract) —
##      test_boots_real_main_scene_with_injected_seed_and_reaches_interactive_state()
##
##   2. the full journey — hex grid / event log render at boot, a player
##      Strike, a pass, an AI-resolved enemy turn (through the SAME
##      resolve_action_use_case pipeline, core/combat/ai.gd), and the round
##      concluding with exactly one EncounterResultEvent and a Win/Loss
##      $ResultScreenView — completes and is asserted, immediately followed
##      by test_criteria #4 (a stray reconfigure() call on
##      $StrikeActionControl/$EndTurnControl after the result screen has
##      shown must remain locked/rejected — the FEAT-137/DEF-004
##      regression) —
##      test_full_journey_strike_pass_ai_turn_and_result_screen_stays_locked_through_stray_reconfigure()
##
##   3. a ranged Strike within weapon range resolves successfully and one
##      beyond range is rejected with ERR_TARGET_OUT_OF_REACH, both driven
##      through MainScene's own real, wired resolve_action_use_case instance
##      — the FEAT-140/DEF-007 regression —
##      test_ranged_strike_within_reach_succeeds_and_beyond_reach_rejected_through_real_pipeline()
##
##   4. scripts/test_command.sh (the sole canonical CI entry point, FEAT-133/
##      FEAT-136) exercises this file with no additional wiring required:
##      this file lives under res://tests/e2e, already covered by the root
##      .gutconfig.json's ("res://tests", include_subdirs=true) scope, which
##      is what both `godot --headless -- --gut-run-all` (stage 4,
##      tests/runner/headless_runner.gd hardcodes loading
##      res://.gutconfig.json) and .github/workflows/test.yml's "Run GUT
##      tests" step already run.
##
## FEAT-001 / US-001 (iteration D, "UI Consolidation + Movement UX", P0-2):
## the duplicate res://scenes/battlefield/* UI stack this file's original
## criterion 3 exercised through MainScene ($HexBattlefield's agreement with
## $HexGridView after a Step/Stride) has been REMOVED from MainScene's
## composition — there is now exactly one hex grid renderer. That criterion
## is retired here rather than retargeted; only the now-meaningless "do the
## two renderers agree" comparison is gone, since only one renderer remains.
##
## FEAT-004 (US-004 / FR-013, same iteration): the once-independent
## tests/gut/test_hex_battlefield_movement_resync.gd and tests/gut/
## test_movement_resync_wiring.gd suites this doc used to cross-reference
## have themselves since been deleted — they exclusively exercised
## scenes/battlefield/HexBattlefield.gd's now-unwired move_token()/resync
## path and the cross-renderer agreement this file also retired above. The
## still-relevant half of test_movement_resync_wiring.gd (HexGridView resync
## through the real movement_input_controller.gd path, with no
## HexBattlefield collaborator configured) remains covered by
## tests/unit/presentation/test_movement_input_controller.gd's
## test_successful_step_repositions_token_on_hex_grid_view() — no coverage
## is lost, only the dangling scenes/battlefield/* preloads are gone.
##
## No production code is modified for this feature (files_to_modify is empty)
## — every object driven below is the exact, unmodified, REUSED production
## class already covered by its own unit/integration suites (see
## tests/integration/test_steel_thread_prologue_encounter.gd, tests/gut/
## test_presentation_controls_sticky_lock.gd, tests/unit/presentation/
## test_movement_input_controller.gd, tests/unit/core/application/
## test_resolve_action_ranged_reach.gd) — this file's job is proving they
## ALL still compose correctly, together, through the ONE real, shipped
## MainScene.tscn entry point, post-remediation.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const RoundEventsClass    = preload("res://core/rules/round_events.gd")
const HexCoordClass       = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass  = preload("res://core/rules/action_economy.gd")
const HexGridViewClass    = preload("res://presentation/hex_grid_view.gd")

## The pinned deterministic-test fixture seed (matches
## data/encounters/prologue_encounter.tres' own `seed` field, 42) — injected
## in-process via MainScene's `seed_override` contract (ADR-004 top
## precedence) so every scenario below is reproducible.
const SEED: int = 42

## The enemy hp handicap bumped mid-test (mirrors tests/e2e/
## test_prologue_encounter_e2e_smoke.gd's identically-motivated fixture): the
## real prologue fixture's Skeleton (8 HP) is one-shot-killable by Titus's
## real stats under seed=42, so a handicap is applied to the SAME live,
## reference-type enemy Dictionary MainScene itself mutates (no clone, no
## double) to force several genuine Strike/AI-turn exchanges — long enough to
## exercise the enemy-AI-turn leg of the pipeline within one continuous
## playthrough — before the round concludes.
const _ENEMY_HP_HANDICAP: int = 100

## Safety bound on the player-Strike/End-Turn exchange loop below (CWE-835
## "never loop unbounded" guard, mirroring this codebase's established
## convention — see tests/e2e/test_prologue_encounter_e2e_smoke.gd /
## tests/gut/test_steel_thread_e2e.gd's identically-motivated guards).
const _MAX_TURN_EXCHANGES: int = 30


# ══════════════════════════════════════════════════════════════════════════
# Shared fixture helper
# ══════════════════════════════════════════════════════════════════════════

## _boot_main_scene_with_seed(seed_value) — instantiates the REAL
## res://MainScene.tscn (project.godot's own run/main_scene, the steel
## thread's entry_point), pinning `seed_override` BEFORE add_child() triggers
## _ready() so the resulting boot is reproducible (ADR-004's in-process
## composition-root contract). No manual setup beyond this one injected
## property — MainScene.gd's own _ready() performs every other wiring step.
## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): MainScene now
## boots into EXPLORATION mode with the legacy combat pipeline (round_session,
## $VerbBarView/$SelectionOverlay configuration, turn_controller signal
## wiring) gated behind a real _on_combat_triggered() handoff -- see
## MainScene.gd's own FEAT-316 doc. This suite drives the whole post-
## remediation steel thread directly against `round_session`/
## `strike_action_control`/`end_turn_control`, so
## `_boot_main_scene_with_seed()` now also drives the SAME real handoff,
## landing the instance in GameMode.COMBAT with a live round_session before
## returning.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — the real MainScene.tscn boots headlessly with no manual
# setup, pinned to seed=42 via the in-process injection point, and reaches an
# interactive, input-awaiting state (not an already-concluded encounter).
# ══════════════════════════════════════════════════════════════════════════

func test_boots_real_main_scene_with_injected_seed_and_reaches_interactive_state() -> void:
	var instance = await _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_eq(
		instance.resolved_seed, SEED,
		"seed_override=42 must be honored as the resolved seed via the in-process injection point (ADR-004 top precedence)"
	)
	assert_eq(
		instance.outcome, "",
		"the real entry point must NOT auto-resolve the encounter to a terminal outcome on first frame"
	)
	assert_not_null(instance.round_session, "MainScene must obtain a real RoundSession via RunRoundUseCase.begin_round()")
	assert_false(instance.round_session.is_round_over(), "the freshly-begun RoundSession must not already be over with zero player input")

	assert_not_null(instance.hex_grid_view, "MainScene must expose a non-null hex_grid_view")
	assert_eq(instance.hex_grid_view.get_token_count(), 4, "HexGridView must render one token per live combatant (Titus + Marigold + Gram Marx + Skeleton)")

	assert_not_null(instance.event_log_view, "MainScene must expose a non-null event_log_view")
	assert_eq(instance.event_log_view.get_entry_count(), 0, "fixture assumption: no events have been logged yet before any player input")

	assert_true(
		instance.strike_action_control.get_selectable_target_ids().size() > 0,
		"the real StrikeActionControl must be configured with live, in-reach targets, awaiting player input"
	)
	assert_true(instance.end_turn_control.is_enabled(), "the real EndTurnControl must be enabled for the active player, awaiting player input")
	assert_false(instance.result_screen_view.is_shown(), "the real ResultScreenView must not show a result before any input has been given")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (+ test_criteria #4) — the full journey: hex battlefield/turn
# order/event log render at boot, a Strike, a pass, an AI-resolved enemy
# turn, and EncounterResultEvent -> Win/Loss ResultScreenView, all through
# the REAL pipeline in one continuous playthrough; then a stray
# reconfigure() call on strike_action_control/end_turn_control after the
# result screen has shown is asserted to remain locked/rejected
# (FEAT-137/DEF-004).
# ══════════════════════════════════════════════════════════════════════════

func test_full_journey_strike_pass_ai_turn_and_result_screen_stays_locked_through_stray_reconfigure() -> void:
	var instance = await _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	# ── Boot-time render assertions (hex grid + event log) ──────────────────
	assert_eq(instance.hex_grid_view.get_token_count(), 4, "HexGridView must render all combatant tokens at boot (Titus + Marigold + Gram Marx + Skeleton)")
	assert_eq(instance.event_log_view.get_entry_count(), 0, "fixture assumption: no events logged before any input")
	assert_false(instance.result_screen_view.is_shown(), "fixture assumption: no result is shown before any input")

	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter has exactly one enemy")
	# See file-level design note: bumping the REAL, live enemy Dictionary's
	# hp_current (no mock/double) so this deterministic seed-42 fight takes
	# several genuine exchanges -- long enough for the enemy AI to actually
	# take a turn -- before concluding.
	instance._enemies[0]["hp_current"] = _ENEMY_HP_HANDICAP
	instance._enemies[0]["hp_max"] = _ENEMY_HP_HANDICAP

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption (seed 42): the first actor is the living player combatant Titus"
	)

	# ── First exchange, driven explicitly so the Strike and the AI-driven pass
	# are each individually asserted (test_criteria #2's "Strike, pass, AI
	# enemy turn" wording), before folding into the bounded drive loop below. ──
	var first_target_ids: Array = instance.strike_action_control.get_selectable_target_ids()
	assert_true(first_target_ids.size() > 0, "the active player actor must have a live, in-reach target")
	var strike_result: Dictionary = instance.strike_action_control.select_target(first_target_ids[0])
	assert_true(strike_result.get("resolved", false), "the real resolve_action_use_case must resolve the player's Strike")

	var press_result: Dictionary = instance.end_turn_control.press()
	assert_true(press_result.get("ok", false), "the real EndTurnControl.press() must forward to RoundSession.end_current_turn() successfully")

	assert_false(
		instance.round_session.is_round_over(),
		"the enemy hp handicap must prevent the round from concluding after only one exchange"
	)

	var attack_events_after_first_exchange: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	var attacker_names_after_first_exchange: Array = attack_events_after_first_exchange.map(func(e): return e.attacker_name)
	assert_true(attacker_names_after_first_exchange.has("Titus"), "the player's Strike must have been resolved through the real pipeline")
	assert_true(
		attacker_names_after_first_exchange.has("Skeleton"),
		"passing the player's turn must auto-drive the enemy AI's turn through the SAME resolve_action_use_case pipeline (core/combat/ai.gd)"
	)

	# ── Drive the remaining exchanges (bounded) until the round concludes. ─────
	var exchanges: int = 0
	while not instance.round_session.is_round_over() and exchanges < _MAX_TURN_EXCHANGES:
		exchanges += 1

		var actor = instance.round_session.current_actor()
		assert_false(actor == null, "a living actor must be active while the round is not yet over")
		assert_false(
			actor.is_enemy,
			"the real TurnController must always auto-drive Enemy turns before yielding control back -- this loop must only ever observe a player actor here"
		)

		var target_ids: Array = instance.strike_action_control.get_selectable_target_ids()
		assert_true(target_ids.size() > 0, "the active player actor must have a live, in-reach target")

		var loop_strike_result: Dictionary = instance.strike_action_control.select_target(target_ids[0])
		assert_true(loop_strike_result.get("resolved", false), "the real resolve_action_use_case must resolve every simulated player Strike")

		var loop_press_result: Dictionary = instance.end_turn_control.press()
		assert_true(loop_press_result.get("ok", false), "the real EndTurnControl.press() must forward successfully on every exchange")

	assert_true(
		instance.round_session.is_round_over(),
		"the encounter must reach a conclusion well within this loop's safety bound"
	)

	# ── EncounterResultEvent -> real ResultScreenView renders Win/Loss and
	# disables all combat input controls (US-010/US-012). ──────────────────────
	var decided_outcome: String = instance.round_session.outcome()
	assert_true(
		decided_outcome == "won" or decided_outcome == "lost",
		"RoundSession.outcome() must be a decided terminal outcome once the round concludes; got '%s'" % decided_outcome
	)

	var result_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(result_events.size(), 1, "exactly one EncounterResultEvent must be emitted through the real event sink")
	assert_eq(result_events[0].outcome, decided_outcome, "the terminal event's outcome must match RoundSession.outcome()")

	assert_true(instance.result_screen_view.is_shown(), "the real ResultScreenView must render once EncounterResultEvent is received")
	var expected_text: String = "Win" if decided_outcome == "won" else "Loss"
	assert_eq(instance.result_screen_view.get_result_text(), expected_text, "ResultScreenView must render the text matching the decided outcome")
	assert_eq(instance.result_screen_view.get_label_text(), expected_text, "the rendered Label text must match the displayed result text")

	assert_true(instance.event_log_view.get_entry_count() > 0, "the full encounter must have logged at least one entry")

	assert_eq(
		instance.strike_action_control.get_button_count(), 0,
		"the real ResultScreenView must have disabled StrikeActionControl once the encounter concluded"
	)
	assert_true(instance.strike_action_control.is_locked(), "StrikeActionControl.is_locked() must be true once the encounter has concluded")
	assert_false(instance.end_turn_control.is_enabled(), "the real ResultScreenView must have disabled EndTurnControl once the encounter concluded")
	assert_true(instance.end_turn_control.is_locked(), "EndTurnControl.is_locked() must be true once the encounter has concluded")

	# ══════════════════════════════════════════════════════════════════════
	# test_criteria #4 (FEAT-137/DEF-004 regression): a stray reconfigure()
	# call on strike_action_control/end_turn_control AFTER the result screen
	# has shown must remain locked/rejected.
	# ══════════════════════════════════════════════════════════════════════
	var stray_actor = instance._party[0]
	instance.strike_action_control.configure(
		stray_actor, ActionEconomyClass.new(), instance.resolve_action_use_case, instance._enemies
	)
	instance.end_turn_control.configure(instance.round_session)

	assert_true(instance.strike_action_control.is_locked(), "StrikeActionControl must stay locked through a later, stray configure() call")
	assert_eq(instance.strike_action_control.get_button_count(), 0, "a stray reconfigure() must not re-render any selectable-target button")
	assert_true(instance.end_turn_control.is_locked(), "EndTurnControl must stay locked through a later, stray configure() call")
	assert_false(instance.end_turn_control.is_enabled(), "a stray reconfigure() must not re-enable EndTurnControl")

	var stray_target_id: String = instance._enemies[0].combatant_id
	var stray_strike_result: Dictionary = instance.strike_action_control.select_target(stray_target_id)
	assert_false(stray_strike_result.get("ok", true), "select_target() must be rejected after the result screen has shown, even after a stray reconfigure()")
	assert_eq(stray_strike_result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")

	var stray_press_result: Dictionary = instance.end_turn_control.press()
	assert_false(stray_press_result.get("ok", true), "press() must be rejected after the result screen has shown, even after a stray reconfigure()")
	assert_eq(stray_press_result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (retargeted, FEAT-001 / US-001) — HexGridView (the ONE kept hex
# renderer, per iteration D's UI consolidation) resyncs a combatant's
# rendered token position after a Step AND after a subsequent Stride, driven
# through the REAL presentation/movement_input_controller.gd MainScene
# wires (configured exactly as MainScene.gd's own
# _on_active_actor_changed() does it). The original "HexBattlefield and
# HexGridView agree" comparison (FEAT-138/DEF-006) is retired along with the
# removed $HexBattlefield node -- see this file's header doc.
#
# FEAT-002 (US-002 / FR-003 / FR-004; Iteration F P0-1): Step and Stride now
# share the SAME per-turn Movement-trait gate (core/rules/action_economy.gd
# ActionEconomy.can_take_movement_action()) -- a Step, though free, locks out
# a Stride for the REST OF THAT TURN, and vice versa. To keep exercising
# BOTH movement verbs' token-resync behavior in one continuous playthrough
# (this file's own "same continuous playthrough wherever test_criteria
# allow" convention, see header doc), the turn boundary between the Step and
# the Stride is simulated via the EXISTING, already-tested
# start_of_turn() reset (core/rules/action_economy.gd, core/rules/
# test_movement_lockout.gd's own regression pin) rather than by asserting
# something the domain rule now correctly forbids.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_grid_view_resyncs_token_position_after_step_and_stride() -> void:
	var instance = await _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption (seed 42): the first actor is the living player combatant Titus"
	)

	const PLAYER_ID: String = "player_0"

	# Titus starts at (0,0) (prologue_encounter.tres); the Skeleton occupies
	# (1,0), Marigold (the prologue roster's second party member) occupies
	# (-1,0), and Gram Marx (the third party member) occupies (-2,0). (0,1)
	# is one of (0,0)'s 6 flat-top axial neighbors and remains unoccupied --
	# a legal Step destination.
	var step_destination := HexCoordClass.new(0, 1)
	var step_result: Dictionary = instance.movement_input_controller.step_to(step_destination)
	assert_true(step_result.get("ok", false), "fixture assumption: Step to (0,1) must succeed: %s" % step_result)

	var domain_actor = instance._party[0]
	assert_true(
		domain_actor["hex_coord"].equals(step_destination),
		"the real Movement.step() must update the live combatant Dictionary's hex_coord in place"
	)

	var grid_token = instance.hex_grid_view.get_token(PLAYER_ID)
	assert_not_null(grid_token, "HexGridView must still have a token for the mover after a Step")
	var expected_position_after_step: Vector2 = instance.hex_grid_view.axial_to_pixel(step_destination)
	assert_almost_eq(
		grid_token.position, expected_position_after_step, Vector2(0.01, 0.01),
		"HexGridView's token must resync to the combatant's new hex position after a Step via the real composition-root wiring"
	)

	# FEAT-002: the Step just taken above tripped this turn's Movement-trait
	# gate -- simulate the actor's next turn beginning via the existing
	# start_of_turn() reset so the Stride below is legal again, exactly as it
	# would be once TurnController actually advances the turn.
	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor carries a live domain ActionEconomy")
	assert_false(
		action_economy.can_take_movement_action(),
		"fixture assumption: the Step just taken must have tripped the Movement-trait gate (FEAT-002)"
	)
	action_economy.start_of_turn()

	# From (0,1), Stride to (0,4) -- hex_distance 3, within Speed (4) and unoccupied.
	var stride_destination := HexCoordClass.new(0, 4)
	var stride_result: Dictionary = instance.movement_input_controller.stride_to(stride_destination)
	assert_true(stride_result.get("ok", false), "fixture assumption: Stride to (0,4) must succeed: %s" % stride_result)

	assert_true(
		domain_actor["hex_coord"].equals(stride_destination),
		"the real Movement.stride() must update the live combatant Dictionary's hex_coord in place"
	)

	var grid_token_after_stride = instance.hex_grid_view.get_token(PLAYER_ID)
	assert_not_null(grid_token_after_stride, "HexGridView must still have a token for the mover after a Stride")
	var expected_position_after_stride: Vector2 = instance.hex_grid_view.axial_to_pixel(stride_destination)
	assert_almost_eq(
		grid_token_after_stride.position, expected_position_after_stride, Vector2(0.01, 0.01),
		"HexGridView's token must resync to the combatant's new hex position after a Stride via the real composition-root wiring"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (test_criteria list item 4 for this file's numbering) — a
# ranged Strike within range succeeds and one beyond range is rejected,
# within the same test run, driven through MainScene's own real, wired
# resolve_action_use_case instance (FEAT-140/DEF-007).
# ══════════════════════════════════════════════════════════════════════════

func test_ranged_strike_within_reach_succeeds_and_beyond_reach_rejected_through_real_pipeline() -> void:
	var instance = await _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	const RANGE_HEXES: int = 8  # mirrors shortbow's short range, per tests/unit/core/application/test_resolve_action_ranged_reach.gd

	var attacker_origin := HexCoordClass.new(20, 0)  # far from the live Titus/Skeleton fixture -- isolates this scenario
	var ranged_attacker: Dictionary = {
		"name":      "Archer",
		"dexterity": 3,
		"hex_coord": attacker_origin,
		"weapon": {
			"damage_modifier_attribute": "dexterity",
			"proficiency_bonus": 2,
			"damage_die": 6,
			"range_hexes": RANGE_HEXES
		}
	}

	# ── Within range: hex_distance == range_hexes must succeed. ────────────────
	var in_range_target: Dictionary = {
		"name": "InRangeTarget", "hp_current": 50, "ac": 10,
		"hex_coord": HexCoordClass.new(20 + RANGE_HEXES, 0)
	}
	var ae_in_range := ActionEconomyClass.new()
	ae_in_range.start_of_round()

	var in_range_result: Dictionary = instance.resolve_action_use_case.resolve(
		ranged_attacker, ae_in_range, in_range_target, "Strike", 1, 0
	)
	assert_true(in_range_result.get("ok", false), "a ranged Strike within range_hexes must resolve successfully through MainScene's real resolve_action_use_case")
	assert_true(in_range_result.get("resolved", false), "a ranged Strike within range_hexes must be marked resolved")
	assert_true(
		in_range_result.get("event", null) is RoundEventsClass.AttackBroadcast,
		"a resolved ranged Strike must carry the emitted AttackEvent under the 'event' key"
	)

	# ── Beyond range: hex_distance == range_hexes + 1 must be rejected. ─────────
	var out_of_range_target: Dictionary = {
		"name": "OutOfRangeTarget", "hp_current": 50, "ac": 10,
		"hex_coord": HexCoordClass.new(20 + RANGE_HEXES + 1, 0)
	}
	var ae_out_of_range := ActionEconomyClass.new()
	ae_out_of_range.start_of_round()

	var out_of_range_result: Dictionary = instance.resolve_action_use_case.resolve(
		ranged_attacker, ae_out_of_range, out_of_range_target, "Strike", 1, 0
	)
	assert_false(out_of_range_result.get("ok", true), "a ranged Strike beyond range_hexes must be rejected through the same real resolve_action_use_case")
	assert_eq(
		out_of_range_result.get("error", ""), "ERR_TARGET_OUT_OF_REACH",
		"the rejection must carry error code ERR_TARGET_OUT_OF_REACH"
	)
	assert_eq(out_of_range_target.get("hp_current", -1), 50, "target HP must be untouched when the ranged Strike is rejected")
	assert_eq(
		ae_out_of_range.get_remaining(), ActionEconomyClass.MAX_BUDGET,
		"the actor's action budget must remain unspent when the ranged reach precondition rejects the Strike"
	)

	# The two scenarios above must not have perturbed the real, live
	# Titus-vs-Skeleton fixture this composition root also boots into.
	assert_false(instance.round_session.is_round_over(), "the unrelated ranged-reach scenario must not affect the live prologue encounter's round state")
