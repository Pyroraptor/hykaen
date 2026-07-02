extends GutTest
## tests/e2e/test_prologue_encounter_e2e_smoke.gd
##
## FEAT-127 (US-004/US-009/US-010/US-011/US-012, FIND-120): headless
## end-to-end smoke test of the REAL interactive steel thread, driven
## through the actual, shipped project entry point.
##
## Unlike tests/unit/test_main_scene_interactive_wiring.gd (which exercises
## the same wiring but is scoped as a unit-level test of MainScene's own
## responsibilities), this test's job is narrower and stricter: prove that
## booting the EXACT node tree project.godot's run/main_scene points at
## (res://MainScene.tscn, attaching MainScene.gd) yields a fully playable,
## input-awaiting encounter -- and that driving it via the REAL, unmocked
## $StrikeActionControl / $EndTurnControl / $TurnController /
## core/application/round_session.gd RoundSession / $ResultScreenView node
## tree carries a Strike and an End Turn all the way through to a concluded
## encounter. This is the regression guard called out by FIND-120: if
## MainScene.gd ever reverts to auto-resolving the whole encounter via the
## old autonomous core/combat/encounter.gd run_round() batch loop instead of
## exposing controls to real input, this file fails.
##
## Design note -- why the enemy's hp_current is bumped mid-test (not a mock,
## not a test double): Titus's real weapon/attribute stats are strong enough
## to one-shot-kill the Skeleton (8 HP) on a single landed Strike -- so an
## unmodified playthrough is likely to conclude before the enemy AI ever gets
## a turn, whatever seed a given boot resolves to (FEAT-002 / US-002: a real,
## non-override MainScene launch resolves a fresh random play seed every
## boot, so this test no longer assumes the fixture's old fixed seed=42). To
## reliably exercise
## (and prove) the enemy-AI-turn leg of the SAME real pipeline within one
## continuous playthrough, this test raises the live enemy combatant
## Dictionary's hp_current up front -- the exact same reference-type
## Dictionary MainScene itself mutates on every resolved Strike (no clone, no
## substitute object) -- so several genuine Strike / End Turn / AI-turn
## exchanges occur before the Skeleton is finally defeated. Every single one
## of those exchanges, player's and AI's alike, still flows through the
## SAME real $StrikeActionControl/$EndTurnControl/$TurnController/
## RoundSession/resolve_action_use_case instances MainScene wired at boot --
## nothing about the pipeline itself is altered or stubbed.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const RoundEventsClass = preload("res://core/rules/round_events.gd")

## The enemy hp handicap applied mid-test so the deterministic seed-42
## encounter takes several Strike/AI-turn exchanges to resolve instead of
## ending on Titus's first (one-shot) Strike.
const _ENEMY_HP_HANDICAP: int = 100

## Safety bound on the player-Strike/End-Turn exchange loop below --
## mirrors this codebase's established CWE-835 "never loop unbounded"
## guard philosophy (e.g. presentation/turn_controller.gd's
## _MAX_AI_TURNS_PER_DRIVE). The real fight concludes in well under 10
## exchanges given the fixture above; 30 leaves generous headroom without
## risking a genuine hang if a future regression stalls the cycle.
const _MAX_TURN_EXCHANGES: int = 30


## _boot_main_scene() -- instantiates the REAL res://MainScene.tscn (the
## exact PackedScene project.godot's run/main_scene launches), attaching the
## REAL MainScene.gd composition root. No mock/double is substituted
## anywhere in this node tree.
##
## FEAT-002 / US-002: some scenarios below (e.g. the "zero pre-existing
## events" fixture assumption) depend on the prologue fixture's known-good
## playthrough, where Titus (the party member) acts first -- true only for
## the fixture's original seed=42 initiative roll. A real (non-override)
## MainScene launch now resolves a fresh, randomized play seed every boot
## (which could just as validly seat the Skeleton first), so every boot here
## pins that known-good seed explicitly via the in-process `seed_override`
## composition-root contract instead of relying on MainScene's randomized
## default.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(
		packed,
		"MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene"
	)
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Regression guard (test_criteria #1 & #5): booting the real entry point
# reaches an interactive, input-awaiting state on the very first frame --
# NOT an already-concluded encounter. Guards against a regression back to
# the old autonomous batch-loop entry point (FIND-120).
# ══════════════════════════════════════════════════════════════════════════

func test_boot_reaches_interactive_state_not_already_concluded_on_first_frame() -> void:
	var instance = _boot_main_scene()

	# Let a real process frame elapse so this genuinely checks "first frame
	# processed", matching tests/smoke/test_main_scene_headless_boot.gd's
	# established convention -- not merely "constructor ran synchronously".
	await get_tree().process_frame

	assert_eq(
		instance.outcome, "",
		"the real entry point must NOT auto-resolve the encounter to a terminal outcome on the very first frame"
	)
	assert_not_null(
		instance.round_session,
		"MainScene must obtain a real RoundSession via RunRoundUseCase.begin_round()"
	)
	assert_false(
		instance.round_session.is_round_over(),
		"the freshly-begun RoundSession must not already be over with zero player input"
	)
	assert_false(
		instance.result_screen_view.is_shown(),
		"the real ResultScreenView must not show a result before any input has been given"
	)
	assert_true(
		instance.strike_action_control.get_selectable_target_ids().size() > 0,
		"the real StrikeActionControl must be configured with live, in-reach targets, awaiting player input"
	)
	assert_true(
		instance.end_turn_control.is_enabled(),
		"the real EndTurnControl must be enabled for the active player, awaiting player input"
	)


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #2: a simulated Strike through the real $StrikeActionControl
# produces an AttackEvent visible in the real event log / UI state.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_via_real_control_produces_attack_event_visible_in_event_log() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var target_ids: Array = instance.strike_action_control.get_selectable_target_ids()
	assert_true(
		target_ids.size() > 0,
		"fixture assumption: the prologue encounter's first actor has at least one in-reach target"
	)

	assert_eq(
		instance.event_log_view.get_entry_count(), 0,
		"fixture assumption: no events are logged before any Strike is simulated"
	)

	var result: Dictionary = instance.strike_action_control.select_target(target_ids[0])

	assert_true(result.get("resolved", false), "the real resolve_action_use_case must resolve the simulated Strike")

	assert_true(
		instance.event_log_view.get_entry_count() >= 1,
		"the resulting AttackEvent must be visible in the real, unmocked EventLogView"
	)
	assert_true(
		instance.event_log_view.get_row_text(0).contains("Titus"),
		"the real EventLogView's rendered entry must describe the real attacker's Strike"
	)

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(
		attack_events.size(), 1,
		"exactly one AttackEvent must have been observed through the real event-sink adapter"
	)


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #3 & #4: driving the encounter to completion through the
# REAL controls -- the enemy AI turn is auto-driven through the real
# $TurnController/RoundSession, resolving via the SAME resolve_action_use_case
# pipeline as the player's own Strike (proven by inspecting the emitted
# events' and round-history entries' resolution source), and the encounter
# eventually concludes with EncounterResultEvent -- the real $ResultScreenView
# renders Win/Loss and disables all combat input controls.
# ══════════════════════════════════════════════════════════════════════════

func test_end_turn_drives_ai_turn_through_same_pipeline_and_concludes_encounter() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter has exactly one enemy")
	# See file-level design note: bumping the REAL, live enemy Dictionary's
	# hp_current (no mock/double) so the deterministic seed-42 fight takes
	# several genuine exchanges -- long enough for the enemy AI to actually
	# take a turn -- before concluding.
	instance._enemies[0]["hp_current"] = _ENEMY_HP_HANDICAP
	instance._enemies[0]["hp_max"] = _ENEMY_HP_HANDICAP

	var exchanges: int = 0
	while not instance.round_session.is_round_over() and exchanges < _MAX_TURN_EXCHANGES:
		exchanges += 1

		var actor: Dictionary = instance.round_session.current_actor()
		assert_false(actor.is_empty(), "a living actor must be active while the round is not yet over")
		assert_false(
			actor.get("_is_enemy", false),
			"the real TurnController must always auto-drive Enemy turns before yielding control back "
			+ "(US-011) -- this test loop must only ever observe a player actor here"
		)

		var target_ids: Array = instance.strike_action_control.get_selectable_target_ids()
		assert_true(target_ids.size() > 0, "the active player actor must have a live, in-reach target")

		var strike_result: Dictionary = instance.strike_action_control.select_target(target_ids[0])
		assert_true(
			strike_result.get("resolved", false),
			"the real resolve_action_use_case must resolve every simulated player Strike"
		)

		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(
			press_result.get("ok", false),
			"the real EndTurnControl.press() must forward to RoundSession.end_current_turn() successfully"
		)

	assert_true(
		instance.round_session.is_round_over(),
		"the encounter must reach a conclusion well within this loop's safety bound"
	)

	# ── The enemy AI turn genuinely resolved through the real pipeline ──────
	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent)
	var attacker_names: Array = attack_events.map(func(e): return e.attacker_name)
	assert_true(
		attacker_names.has("Titus"),
		"the player's Strike(s) must have been resolved through the real pipeline"
	)
	assert_true(
		attacker_names.has("Skeleton"),
		"the enemy AI's turn must have been auto-driven by the real TurnController/RoundSession "
		+ "and resolved through the real pipeline (US-011) -- this fails if AI turns never actually run"
	)

	# ── "same resolve_action_use_case pipeline" proof (resolution
	# path/source): core/application/resolve_action_use_case.gd's resolve()
	# is the ONLY code path that ever appends to RoundHistoryPort -- neither
	# StrikeActionControl nor RoundSession.advance_ai_turn() append to it
	# directly. An entry existing for BOTH attacker names therefore proves
	# both the player's and the AI's actions funnelled through the exact
	# SAME resolve_action_use_case instance MainScene wired at boot, never a
	# parallel/duplicate resolution path. ───────────────────────────────────
	var history_attackers: Array = []
	for entry in instance.round_history_port.get_history():
		history_attackers.append(entry["attacker"].get("name", ""))
	assert_true(
		history_attackers.has("Titus"),
		"round_history_port must record the player's action, appended only from inside resolve_action_use_case.resolve()"
	)
	assert_true(
		history_attackers.has("Skeleton"),
		"round_history_port must record the AI's action, appended only from inside the SAME "
		+ "resolve_action_use_case.resolve() instance -- proving one identical pipeline, not a parallel path"
	)

	# ── Encounter concludes with EncounterResultEvent -> the real
	# ResultScreenView renders Win/Loss and disables all combat input. ──────
	var result_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(
		result_events.size(), 1,
		"exactly one EncounterResultEvent must be emitted through the real event sink"
	)

	assert_true(
		instance.result_screen_view.is_shown(),
		"the real ResultScreenView must render once EncounterResultEvent is received"
	)
	assert_true(
		["Win", "Loss"].has(instance.result_screen_view.get_result_text()),
		"the real ResultScreenView must render either 'Win' or 'Loss'"
	)
	assert_eq(
		instance.result_screen_view.get_label_text(), instance.result_screen_view.get_result_text(),
		"the rendered Label text must match the displayed result text"
	)

	assert_eq(
		instance.strike_action_control.get_button_count(), 0,
		"the real ResultScreenView must have disabled StrikeActionControl once the encounter concluded (US-012)"
	)
	assert_false(
		instance.end_turn_control.is_enabled(),
		"the real ResultScreenView must have disabled EndTurnControl once the encounter concluded (US-012)"
	)
