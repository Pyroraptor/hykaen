extends GutTest
## tests/integration/test_steel_thread_prologue_encounter.gd
##
## FEAT-113 / US-015: End-to-end steel thread validation.
## FEAT-124 / FIND-120: retargeted at the REAL res://MainScene.tscn/
## MainScene.gd composition root for BOTH halves below.
##
## The FINAL integration/E2E test exercising the complete steel thread from
## entry_point to exit_point, closing out the automated/testable portions of
## US-015. Two complementary halves, BOTH driven through one real, shipped
## composition root instance (res://MainScene.tscn, wired by MainScene.gd,
## corrected by FIX-001 to build the INTERACTIVE RunRoundUseCase.begin_round()
## -> RoundSession pipeline instead of an autonomous run_round() while-loop):
##
##   (A) Headless PRODUCTION BOOT: asserts the hex battlefield/status panel/
##       initiative order are populated correctly from the real
##       prologue_encounter.tres data, and re-confirms determinism
##       (NFR-002/006) by booting the SAME seeded encounter twice (pinned via
##       MainScene's `seed_override` in-process contract, FEAT-002 / US-002 --
##       a real, non-override launch resolves a fresh randomized play seed
##       every boot instead) and diffing the ordered event sequence.
##
##   (B) The INTERACTIVE Presentation pipeline (StrikeActionControl /
##       TurnController / EndTurnControl / ResultScreenView, US-009 through
##       US-012): drives the REAL $StrikeActionControl / $EndTurnControl /
##       $TurnController / $ResultScreenView child nodes already wired on the
##       instantiated MainScene.tscn -- a real player Strike, a real
##       AI-controlled enemy turn auto-driven through the real
##       $TurnController, and a real Win/Loss $ResultScreenView -- exercising
##       the SHIPPED entry point end-to-end rather than a test-only bypass
##       (FEAT-124 / FIND-120). No test-local RunRoundUseCase/RoundSession/
##       TurnController graph is constructed here -- MainScene.gd's own
##       _ready() (composition root, corrected by FIX-001) is the ONLY place
##       Application ports are wired to Infrastructure adapters; this file
##       only drives the resulting real Presentation nodes and observes the
##       real, production GodotRandomAdapter-seeded outcome (a real,
##       non-override boot -- FEAT-002 / US-002 -- so no assumption is made
##       here, nor anywhere in Part (B), about which specific Strikes
##       hit/miss/crit, or about a fixed seed=42 playthrough).
##
## No production code is modified for this feature (ADR-002/CR-001
## guardrail; FEAT-124's files_to_modify is this test file only) -- every
## object driven below is the exact, unmodified, REUSED production class
## already covered by its own unit tests (see tests/unit/test_main_scene_
## interactive_wiring.gd, the established precedent this file's Part (B)
## follows); this file's job is proving they compose correctly end-to-end
## through the ONE real, shipped MainScene.tscn entry point.
##
## test_criteria satisfied:
##   1. test_mainscene_boot_populates_hex_battlefield_status_panel_and_initiative()
##   2. test_player_strike_through_real_pipeline_observable_in_event_log_and_status_panel()
##   3. test_enemy_ai_turn_auto_drives_through_identical_pipeline_after_end_turn()
##   4. test_encounter_concludes_with_result_screen_matching_determine_outcome_use_case()
##   5. test_determinism_two_independent_mainscene_boots_produce_identical_event_sequence()
##   6. (whole-suite regression) -- enforced by test_command, not this file.
##
## FEAT-134 cross-reference: this file's Part (B) exercises the NEWER
## presentation/ interactive stack (StrikeActionControl / EndTurnControl /
## TurnController / ResultScreenView, FEAT-109 onward) through the same real
## res://MainScene.tscn composition root. FEAT-134's sibling end-to-end test,
## tests/gut/test_steel_thread_e2e.gd, closes out the ORIGINAL FEAT-001
## through FEAT-011 steel thread by driving MainScene's other, still-wired
## widget/controller set (HexBattlefield / TurnOrderWidget / EventLogView /
## StrikeInputController / EndTurnController / ResultScreen,
## scenes/battlefield/) under a pinned seed_override=42 -- including the
## final combatant HP/state snapshot and full ordered event log that only
## scenes/battlefield/ResultScreen.gd (not ResultScreenView) renders. Both
## files drive the SAME real MainScene.tscn entry point and the SAME
## resolve_action_use_case/run_round_use_case pipeline (ADR-002/ADR-007); they
## are complementary, not duplicate, coverage of the two widget stacks
## MainScene.gd wires side by side.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const RoundEventsClass    = preload("res://core/rules/round_events.gd")
const TurnControllerClass = preload("res://presentation/turn_controller.gd")
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")

## _MAX_DRIVE_ITERATIONS -- an upper bound on how many player-turn/End-Turn
## cycles test_encounter_concludes_with_result_screen_matching_determine_outcome_use_case()
## will drive before giving up. core/rules/action_economy.gd caps every
## combatant at MAX_BUDGET=7 actions PER ROUND, and this steel thread's only
## action is a 1-action Strike, so the round MUST end (either by a decided
## outcome or by both sides exhausting their budget) within 7 player turns --
## this guard is a generous multiple of that hard ceiling, purely defensive
## against a stalled drive hanging the test suite.
const _MAX_DRIVE_ITERATIONS: int = 20


# ══════════════════════════════════════════════════════════════════════════
# Shared fixture: boot the REAL res://MainScene.tscn composition root -- the
# SAME entry point project.godot's run/main_scene points at. Mirrors
# tests/smoke/test_main_scene_headless_boot.gd's already-established,
# reliable in-process boot pattern (also used by tests/unit/
# test_main_scene_interactive_wiring.gd, this file's Part (B) precedent).
# ══════════════════════════════════════════════════════════════════════════

## FEAT-006 (US-005/FR-005, ADR-002): MainScene now wires RoundSession's
## enemy-strikes-player reaction window to the REAL, blocking
## TurnController.resolve_reaction() -> PlayerReactionChooser ->
## $ReactionPromptUI chain, which has "no auto-timeout" by design and
## suspends until an actual player clicks an option. This helper boots with
## no seed pinned, so an enemy-led initiative draw is possible; the injected
## ReactionChooserPort is swapped for infrastructure/auto_reaction_chooser.gd's
## AutoReactionChooser("pass") immediately after boot -- the SAME headless
## double every other reaction-system suite already uses -- via
## TurnController.configure_reactions()'s own documented "safe to call any
## number of times" contract, so this suite's automated AI-turn drive never
## suspends on a real, un-clickable pop-up. Reproduces the exact
## pre-FEAT-006 "none"/PASS default this suite's assertions were written
## against; the REAL PlayerReactionChooser is still what MainScene.gd wires
## for an actual player session.
## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): round_session/
## the Layer 1 verb bar/Layer 2 selection overlay/turn_controller signal
## wiring are no longer live unconditionally at boot -- they now stay
## dormant until a real combat trigger fires (see MainScene.gd's own
## FEAT-316 doc). Part (A)/(B) of this suite both depend on a genuinely live
## round_session/verb registry, so _boot_main_scene() now also drives the
## SAME real handoff tests/boot/test_exploration_to_combat_handoff_trigger.gd
## exercises directly (mirrors tests/boot/test_first_cast_firebolt.gd's
## established convention), landing the instance in GameMode.COMBAT with a
## live round_session before returning.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	add_child_autofree(instance)
	await get_tree().process_frame

	# Pre-existing, out-of-scope UI-timing flake (see commit ef34ccc,
	# "fix(FEAT-344): make the real-invocation gate robust to a pre-existing
	# UI-timing flake"): a bare, un-awaited `_on_combat_triggered()` call only
	# STARTS the coroutine -- it suspends at its own internal
	# `await rewire_session()` and resumes on a later frame. The two
	# `await get_tree().process_frame` calls below were a guess at "enough
	# frames" for that resumption to land, which occasionally reads
	# initiative_view.get_row_count()/status_panel_view population before the
	# coroutine genuinely finishes under load. Awaiting the call itself
	# suspends THIS coroutine until `_on_combat_triggered()` (including its
	# own internal awaits) has fully completed, closing the race
	# deterministically rather than guessing a frame count.
	await instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	if instance.turn_controller != null and instance.reaction_window != null:
		instance.turn_controller.configure_reactions(instance.reaction_window, AutoReactionChooserClass.new("pass"))
	return instance


## _boot_main_scene_with_seed(seed_value) -- identical to _boot_main_scene()
## above, but pins MainScene's `seed_override` (FEAT-002/003 / US-002/003
## in-process composition-root contract, formalized as the top-precedence
## branch of infrastructure/seed_policy.gd's SeedPolicy.resolve_from_
## environment(), ADR-004: in-process override > HYKAEN_SEED env var >
## random) BEFORE add_child() triggers _ready(), so the resulting boot is
## reproducible. Since FEAT-002, a real (non-override, no-env-var) MainScene
## launch resolves a fresh, randomized play seed every time (by design --
## see MainScene.gd's `resolved_seed`), so the determinism regression below
## (booting the SAME seeded encounter twice and diffing the event log
## byte-for-byte, NFR-002/006) must pin an explicit seed via this injection
## point rather than relying on the prologue fixture's default or the
## environment. infrastructure/seed_policy.gd's own precedence/fail-open
## unit coverage lives in tests/gut/test_seed_policy.gd (FEAT-003); this
## file only asserts the resulting composition-root behavior end-to-end.
## See _boot_main_scene()'s FEAT-006 doc immediately above -- the same
## headless AutoReactionChooser swap applies here regardless of the pinned
## seed, since a fixed seed can still place the enemy first in initiative.
## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): see
## _boot_main_scene()'s identical FEAT-316 doc immediately above --
## _boot_main_scene_with_seed() drives the SAME real _on_combat_triggered()
## handoff before returning, so this seeded-boot variant lands the instance
## in GameMode.COMBAT with a live round_session too.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	await get_tree().process_frame

	# See _boot_main_scene()'s identical doc immediately above -- awaiting the
	# call itself (rather than guessing a frame count) closes the same
	# pre-existing, out-of-scope UI-timing flake deterministically.
	await instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	if instance.turn_controller != null and instance.reaction_window != null:
		instance.turn_controller.configure_reactions(instance.reaction_window, AutoReactionChooserClass.new("pass"))
	return instance


## _find_combatant_by_id(instance, combatant_id) -> Dictionary -- looks up a
## live combatant Dictionary (MainScene's own _party/_enemies fields, the SAME
## Dictionaries every resolve_action_use_case.resolve() call mutates in
## place) by combatant_id, mirroring the lookup already established by
## tests/unit/test_main_scene_interactive_wiring.gd.
func _find_combatant_by_id(instance, combatant_id: String):
	for combatant in instance._party + instance._enemies:
		if combatant.combatant_id == combatant_id:
			return combatant
	return null


# ══════════════════════════════════════════════════════════════════════════
# Part (A) — Criterion 1: MainScene boots headlessly into prologue_encounter
# .tres and populates the hex battlefield/status panel/initiative order.
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_boot_populates_hex_battlefield_status_panel_and_initiative() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	# FEAT-123 / FIND-120: MainScene no longer auto-resolves the encounter on
	# boot -- it wires a real, interactive RoundSession instead (full
	# interactive-pipeline coverage lives in
	# tests/unit/test_main_scene_interactive_wiring.gd).
	assert_eq(
		instance.outcome, "",
		"MainScene must NOT auto-resolve the prologue encounter to a terminal outcome on boot; got '%s'" % instance.outcome
	)
	assert_not_null(instance.round_session, "MainScene must obtain a real RoundSession via RunRoundUseCase.begin_round()")
	assert_false(instance.round_session.is_round_over(), "the freshly-begun RoundSession must not already be over with no player input")

	# Hex battlefield (US-005): one token per combatant loaded from
	# prologue_encounter.tres (Titus + Marigold + Gram Marx + Skeleton,
	# the current 4-combatant roster).
	var hex_grid_view = instance.hex_grid_view
	assert_not_null(hex_grid_view, "MainScene must expose a non-null hex_grid_view")
	assert_eq(hex_grid_view.get_token_count(), 4, "the hex battlefield must render one token per prologue combatant")
	assert_not_null(hex_grid_view.get_token("player_0"), "the hex battlefield must render Titus's token (player_0)")
	assert_not_null(hex_grid_view.get_token("player_1"), "the hex battlefield must render Marigold's token (player_1)")
	assert_not_null(hex_grid_view.get_token("player_2"), "the hex battlefield must render Gram Marx's token (player_2)")
	assert_not_null(hex_grid_view.get_token("enemy_0"), "the hex battlefield must render the Skeleton's token (enemy_0)")

	# Status panel (US-006): populated for all four combatants.
	var status_panel_view = instance.status_panel_view
	assert_not_null(status_panel_view, "MainScene must expose a non-null status_panel_view")
	assert_eq(status_panel_view.get_row_count(), 4, "the status panel must show one row per prologue combatant")
	assert_eq(status_panel_view.get_status("player_0").get("name", ""), "Titus")
	assert_eq(status_panel_view.get_status("player_1").get("name", ""), "Marigold")
	assert_eq(status_panel_view.get_status("player_2").get("name", ""), "Gram Marx")
	assert_eq(status_panel_view.get_status("enemy_0").get("name", ""), "Skeleton")

	# Initiative order (US-007): populated for all four combatants.
	var initiative_view = instance.initiative_view
	assert_not_null(initiative_view, "MainScene must expose a non-null initiative_view")
	assert_eq(initiative_view.get_row_count(), 4, "the initiative list must show one row per prologue combatant")
	var ordered_ids: Array = initiative_view.get_ordered_combatant_ids()
	assert_true(ordered_ids.has("player_0"), "the initiative order must include Titus (player_0)")
	assert_true(ordered_ids.has("player_1"), "the initiative order must include Marigold (player_1)")
	assert_true(ordered_ids.has("player_2"), "the initiative order must include Gram Marx (player_2)")
	assert_true(ordered_ids.has("enemy_0"), "the initiative order must include the Skeleton (enemy_0)")


# ══════════════════════════════════════════════════════════════════════════
# Part (A) — Determinism regression (NFR-002/006): re-running the SAME
# seeded prologue encounter (the real entry_point, booted twice) produces an
# identical ordered event sequence.
# ══════════════════════════════════════════════════════════════════════════

func test_determinism_two_independent_mainscene_boots_produce_identical_event_sequence() -> void:
	# FEAT-002 / US-002: real (non-override) launches now resolve a fresh,
	# randomized play seed every boot, so this determinism regression pins
	# `seed_override` explicitly (matching the prologue fixture's original
	# seed=42) rather than relying on MainScene's default.
	var instance_1 = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame
	var instance_2 = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	# FEAT-123 / FIND-120: MainScene no longer auto-resolves the encounter on
	# boot -- both independent boots must still agree on the (now-undecided)
	# outcome and on the RoundSession's initial state, proving the
	# interactive wiring itself is deterministic.
	assert_eq(instance_1.outcome, "", "MainScene must NOT auto-resolve the prologue encounter to a terminal outcome on boot")
	assert_eq(instance_2.outcome, instance_1.outcome, "two independent boots of the same seeded encounter must reach the identical (undecided) outcome")
	assert_eq(
		instance_2.round_session.current_actor().name, instance_1.round_session.current_actor().name,
		"two independent boots of the same seeded encounter must position the RoundSession cursor on the identical first actor"
	)

	var log_1: Array = instance_1.event_sink.log
	var log_2: Array = instance_2.event_sink.log

	assert_eq(log_2.size(), log_1.size(), "two independent boots of the same seeded encounter must emit the same NUMBER of events")

	var count: int = mini(log_1.size(), log_2.size())
	for i in range(count):
		assert_eq(
			log_2[i].to_dict(), log_1[i].to_dict(),
			"event[%d] must be byte-identical across two independent boots of the same seed (NFR-002/006 determinism)" % i
		)


# ══════════════════════════════════════════════════════════════════════════
# Part (B) — Criterion 2: driving a player melee Strike through the REAL
# $StrikeActionControl node on the instantiated MainScene.tscn; the resulting
# AttackEvent appears in the real EventLogView/StatusPanelView, observed via
# MainScene's real event-sink adapter (instance.event_sink).
# ══════════════════════════════════════════════════════════════════════════

func test_player_strike_through_real_pipeline_observable_in_event_log_and_status_panel() -> void:
	# FEAT-002 / US-002: this scenario's fixture assumptions (Titus acts
	# first, zero events logged before any Strike) depend on the specific
	# initiative roll order the prologue fixture's original seed=42
	# produces -- a real (non-override) launch now resolves a fresh random
	# play seed every boot (which could just as validly seat the Skeleton
	# first), so this test pins that known-good seed explicitly rather than
	# relying on MainScene's randomized default.
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"the first actor must be a living player combatant (Titus) per prologue_encounter.tres' hex layout"
	)

	var selection: Dictionary = instance._verb_registry.enter_selection("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(
		target_ids.size() > 0,
		"the real _verb_registry STRIKE entry must be configured with at least one in-reach target for the active player combatant immediately after MainScene._ready()"
	)
	var target_id: String = target_ids[0]

	assert_eq(instance.event_log_view.get_entry_count(), 0, "fixture assumption: no events logged yet before any Strike")

	# ── Drive the real _verb_registry STRIKE entry -- no test-local resolver. ──
	var result: Dictionary = instance._verb_registry.execute("STRIKE", target_id)

	assert_true(result.get("ok", false), "the player's melee Strike on the in-reach target must resolve successfully through the real _verb_registry STRIKE entry")
	assert_true(result.get("resolved", false), "the player's Strike must be marked resolved by MainScene's real, wired resolve_action_use_case")

	# At least one entry (the AttackEvent) -- possibly a second
	# (CombatantDefeatedEvent) if the Strike also proved fatal; the
	# AttackEvent is always emitted FIRST (resolve_action_use_case.resolve()'s
	# documented emission order), so index 0 is always the Strike's own entry.
	assert_true(
		instance.event_log_view.get_entry_count() >= 1,
		"the real EventLogView must observe at least one entry for the player's resolved Strike's AttackEvent"
	)
	var log_text: String = instance.event_log_view.get_entry_text(0)
	assert_string_contains(log_text, "player_0")
	assert_string_contains(log_text, target_id)

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "MainScene's real event-sink adapter must have observed exactly one AttackEvent")
	assert_eq(attack_events[0].attacker_name, "Titus", "the AttackEvent must attribute the Strike to Titus, the player-controlled actor")
	assert_eq(attack_events[0].target_name, "Skeleton", "the AttackEvent must target the Skeleton")

	var target_combatant = _find_combatant_by_id(instance, target_id)
	assert_false(target_combatant == null, "fixture assumption: the selected target must be one of MainScene's live combatant Dictionaries")

	# StatusPanelView clamps a displayed HP at 0 (it never shows an
	# "overkill" negative value), while the live domain Dictionary MainScene
	# mutates may go negative -- compare against the same floor
	# StatusPanelView applies.
	var status: Dictionary = instance.status_panel_view.get_status(target_id)
	assert_eq(
		status.get("hp_current", -1), maxi(target_combatant.hp_current, 0),
		"the real StatusPanelView must reflect the target's post-Strike HP via MainScene's real event-sink pipeline"
	)


# ══════════════════════════════════════════════════════════════════════════
# Part (B) — Criterion 3: pressing the REAL $EndTurnControl node drives the
# enemy's turn automatically through the REAL $TurnController, producing an
# AttackEvent/log entry indistinguishable in shape from the player's own.
#
# The player's turn is passed here WITHOUT Striking first (EndTurnControl is
# documented as "ALWAYS available regardless of whether/what action was
# spent", US-010), so the turn cursor advances directly onto the Skeleton
# (the encounter's only Enemy) with zero prior RandomNumberPort draws
# consumed -- guaranteeing the real $TurnController's AI-auto-drive path
# (RoundSession.advance_ai_turn(), US-011) is deterministically exercised by
# this run regardless of exactly which values the fixed seed=42 production
# RNG happens to yield (unlike Striking first, which -- for this particular
# seed -- lands a critical hit that outright defeats the Skeleton on the
# very first player action, ending the round before any Enemy turn is ever
# reached; see test_encounter_concludes_with_result_screen_matching_
# determine_outcome_use_case() below, which exercises exactly that
# legitimate alternate playthrough).
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_ai_turn_auto_drives_through_identical_pipeline_after_end_turn() -> void:
	# FEAT-002 / US-002: pinned for the same reason as the test above -- this
	# scenario's fixture assumption ("the first actor must be Titus") only
	# holds for the prologue fixture's original seed=42 initiative roll; a
	# real (non-override) launch now resolves a fresh random play seed every
	# boot.
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_is(instance.turn_controller, TurnControllerClass, "MainScene must wire the real $TurnController (presentation/turn_controller.gd)")
	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: the first actor must be the living player combatant (Titus)"
	)
	assert_eq(
		instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast).size(), 0,
		"fixture assumption: no Strike has been made yet"
	)

	# ── Pass the player's opening turn via the real $EndTurnControl node --
	# no Strike, no test-local TurnController. ─────────────────────────────
	var press_result: Dictionary = instance.end_turn_control.press()
	assert_true(press_result.get("ok", false), "the real $EndTurnControl must forward to RoundSession.end_current_turn() successfully")

	assert_false(
		instance.round_session.is_round_over(),
		"passing the player's turn with no damage yet dealt must not conclude the round"
	)

	# At seed=42 the initiative order is: Titus → Skeleton → Marigold →
	# Gram Marx. Titus's END_TURN press above auto-drives the Skeleton's full
	# AI turn (1 attack event), settling the cursor on Marigold (player_1) --
	# RoundSession/TurnController only auto-drives Enemy turns, never another
	# living player-controlled combatant. An EXTRA manual End Turn press
	# (Marigold passing, with no action spent) advances the cursor to Gram
	# Marx (player_2), the third living player combatant.
	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Marigold (player_1) must hold the cursor after the Skeleton's auto-driven turn"
	)
	var pass_result: Dictionary = instance.end_turn_control.press()
	assert_true(pass_result.get("ok", false), "the real $EndTurnControl must forward to RoundSession.end_current_turn() successfully for Marigold's passed turn")

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(
		attack_events.size(), 1,
		"the real $TurnController, driven via MainScene's EndTurnControl.turn_ended handoff, must auto-drive exactly one AI-controlled enemy Strike through resolve_action_use_case"
	)
	var ai_attack_event = attack_events[0]
	assert_true(ai_attack_event is RoundEventsClass.AttackBroadcast, "the AI-resolved event must be a real RoundEvents.AttackBroadcast")
	assert_eq(ai_attack_event.attacker_name, "Skeleton", "the auto-driven Strike must be attributed to the AI-controlled Skeleton")
	assert_eq(ai_attack_event.target_name, "Titus", "the auto-driven Strike must target the player-controlled Titus")

	assert_true(
		instance.event_log_view.get_entry_count() >= 1,
		"the real EventLogView must observe a new entry for the AI-resolved Strike's AttackEvent through MainScene's real event-sink pipeline"
	)

	# TurnController settles back on the player, ready for the next turn.
	assert_false(
		instance.round_session.current_actor().is_enemy,
		"the real $TurnController must auto-drive the Enemy's full turn so the session settles back on a living player combatant"
	)
	var selection2: Dictionary = instance._verb_registry.enter_selection("STRIKE")
	var target_ids: Array = selection2.get("candidate_targets", [])
	assert_true(
		target_ids.size() > 0,
		"MainScene must have reconfigured _verb_registry STRIKE with live targets once the real TurnController settles back on the player (FIND-120)"
	)

	# ── Now the player Strikes for real, through the real _verb_registry STRIKE
	# entry, giving a second, player-attributed AttackEvent to compare shapes with. ──
	var player_result: Dictionary = instance._verb_registry.execute("STRIKE", target_ids[0])
	assert_true(player_result.get("resolved", false), "the player's Strike through the real StrikeActionControl must resolve")

	var attack_events_after: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events_after.size(), 2, "exactly one additional AttackEvent (the player's) must now exist")
	var player_attack_event = attack_events_after[1]
	assert_true(player_attack_event is RoundEventsClass.AttackBroadcast, "the player-resolved event must be a real RoundEvents.AttackBroadcast")
	assert_eq(player_attack_event.attacker_name, "Titus", "the player's own Strike must be attributed to Titus")

	# "Indistinguishable in shape": both events are the SAME AttackEvent type
	# carrying the SAME field set, since both flow through the identical
	# resolve_action_use_case.resolve() pipeline -- never a parallel one.
	assert_eq(
		ai_attack_event.to_dict().keys(), player_attack_event.to_dict().keys(),
		"the AI-resolved AttackEvent must carry the identical field shape as the player's own AttackEvent"
	)


# ══════════════════════════════════════════════════════════════════════════
# Part (B) — Criterion 4: driving the encounter to conclusion entirely
# through the REAL $StrikeActionControl/$EndTurnControl nodes; the REAL
# $ResultScreenView displays Win or Loss and combat input controls are
# disabled afterward.
# ══════════════════════════════════════════════════════════════════════════

func test_encounter_concludes_with_result_screen_matching_determine_outcome_use_case() -> void:
	# Pinned seed (FIX for pre-existing flakiness): this is the only test in
	# this file that DRIVES the real combat all the way to a decided outcome
	# within a bounded turn guard. Booting via the unseeded _boot_main_scene()
	# left the attack/damage RNG random, so an unlucky run of misses could fail
	# to conclude within _MAX_DRIVE_ITERATIONS -- an intermittent failure
	# independent of this iteration's work. Seed 42 (this codebase's standard
	# fixture seed) makes the Titus-vs-Skeleton resolution deterministic so the
	# round reliably reaches a 'won'/'lost' terminal outcome.
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_false(instance.result_screen_view.is_shown(), "fixture assumption: no result is shown before any input")

	# ── Drive the REAL controls, one player turn at a time, until the round
	# concludes -- every enemy turn in between is auto-driven by the real
	# $TurnController via MainScene's EndTurnControl.turn_ended handoff
	# (see presentation/turn_controller.gd / MainScene.gd). ─────────────────
	var guard: int = 0
	while not instance.round_session.is_round_over() and guard < _MAX_DRIVE_ITERATIONS:
		if not instance.round_session.current_actor().is_enemy:
			var sel: Dictionary = instance._verb_registry.enter_selection("STRIKE")
			var target_ids: Array = sel.get("candidate_targets", [])
			if target_ids.size() > 0:
				instance._verb_registry.execute("STRIKE", target_ids[0])
		instance.end_turn_control.press()
		guard += 1

	assert_true(
		instance.round_session.is_round_over(),
		"driving the real StrikeActionControl/EndTurnControl nodes must eventually conclude the round (guard=%d/%d)" % [guard, _MAX_DRIVE_ITERATIONS]
	)
	# Queried via the real RoundSession (round_session.outcome() -- the
	# authoritative source per its documented API contract), not MainScene's
	# own `outcome` mirror field -- see the analogous comment in
	# test_enemy_ai_turn_auto_drives_through_identical_pipeline_after_end_turn()
	# above for why that field is not relied on here.
	var decided_outcome: String = instance.round_session.outcome()
	assert_true(
		decided_outcome == "won" or decided_outcome == "lost",
		"RoundSession.outcome() must be a decided terminal outcome ('won' or 'lost') once the round concludes; got '%s'" % decided_outcome
	)

	assert_true(instance.result_screen_view.is_shown(), "the real $ResultScreenView must have processed the EncounterResultEvent through MainScene's real event-sink pipeline")
	var expected_text: String = "Win" if decided_outcome == "won" else "Loss"
	assert_eq(instance.result_screen_view.get_result_text(), expected_text, "ResultScreenView must render the text matching MainScene's decided outcome")
	assert_eq(instance.result_screen_view.get_label_text(), expected_text, "ResultScreenView's rendered label text must match the decided outcome")

	# Combat input controls disabled after conclusion (US-012).
	assert_false(instance._verb_registry.is_available("STRIKE"), "STRIKE must be unavailable (no selectable targets) once the encounter has concluded")
	assert_false(instance.end_turn_control.is_enabled(), "the real $EndTurnControl must be disabled once the encounter has concluded")

	# Further input after conclusion must be a defensive no-op -- no further
	# use-case call can reach the concluded encounter.
	var post_conclusion_press: Dictionary = instance.end_turn_control.press()
	assert_false(post_conclusion_press.get("ok", true), "the real $EndTurnControl must reject input after the encounter has concluded")
