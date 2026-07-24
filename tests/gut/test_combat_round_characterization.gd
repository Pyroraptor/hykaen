extends GutTest
## tests/gut/test_combat_round_characterization.gd — FEAT-001 (RISK-001
## mitigation: "add characterization/golden-path tests for combat round
## flow before extraction begins").
##
## This suite is the pre-refactor SAFETY NET for the whole MainScene.gd ->
## Clean-Architecture steel thread (FEAT-002..FEAT-010). It pins down, as an
## executable, headless-runnable regression oracle, the CURRENT (unmodified)
## MainScene.gd's own golden path end-to-end:
##
##   boot exploration -> trigger a combat encounter -> dispatch a
##   verb/combine/spell action, targeted -> the round resolves to
##   completion (round-over state/signal fires).
##
## Every extraction feature that follows (CombatSessionFactory,
## VerbDispatchController, CombineQueueBuildSession, CombineTargetingSession,
## RoundFlowController, ExplorationModeController, the composition-root
## slimdown, ...) MUST leave this file GREEN, unmodified, run exactly as-is
## -- that is this file's entire purpose as "the primary regression oracle
## for RISK-001" (test_criteria). It is intentionally NOT rewritten to
## reference any new extracted class; it only ever drives the same public
## surface (`_on_combat_triggered`, `verb_bar_view`, `hex_grid_view`,
## `end_turn_control`, `round_session`, `turn_controller`, `_game_mode`)
## a post-extraction MainScene.gd is required to keep exposing/behaving
## identically through (composition root re-wiring is invisible from here
## by design).
##
## Mirrors this codebase's already-established real-composition-root
## conventions rather than inventing a new one (ADR-002 "no duplicate
## seam"): the same `_boot_main_scene()` shape as
## tests/boot/test_boot_exploration_mode.gd /
## tests/boot/test_exploration_to_combat_handoff_trigger.gd, the same real
## Strike verb dispatch+targeting flow as
## tests/gut/test_steel_thread_e2e.gd's
## test_strike_flow_resolves_via_select_target_with_board_status_lock_updating(),
## and the same real "force the win, end the turn, let
## DetermineOutcomeUseCase decide the round" convention as
## tests/boot/test_post_combat_return_to_exploration.gd's `_force_win()` --
## no new resolution/seam logic is introduced by this file, only assertions
## over the existing, real composition root.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")

## PROLOGUE_SEED — this project's established known-good deterministic
## fixture seed (Titus + Marigold vs. one Skeleton), matching every other
## boot-real suite's identically-valued constant.
const PROLOGUE_SEED: int = 42
const PROLOGUE_ENCOUNTER_ID: String = "prologue"

const STRIKE: String = "STRIKE"


## _boot_main_scene() -> Node — instantiates the REAL, shipped
## res://MainScene.tscn composition root with the pinned deterministic
## seed, exactly mirroring tests/boot/test_boot_exploration_mode.gd's own
## helper. Deliberately does NOT trigger combat -- callers that need COMBAT
## mode do so explicitly via _enter_combat(), so this baseline also
## separately proves the EXPLORATION boot step in isolation.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


## _enter_combat(instance) -> void — drives the SAME real
## `_on_combat_triggered()` handoff tests/boot/
## test_exploration_to_combat_handoff_trigger.gd exercises directly, landing
## the instance in GameMode.COMBAT with a live round_session/enemy roster.
func _enter_combat(instance) -> void:
	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)


## _force_win(instance) -> void — mirrors tests/boot/
## test_post_combat_return_to_exploration.gd's identically-named helper:
## zeroes every live enemy Combatant's hp_current (the SAME `_enemies`
## Array round_session was begin_round()'d with, by reference) then ends
## the current actor's turn via the real $EndTurnControl node.
## RoundSession's own _after_action_resolved() tail consults
## DetermineOutcomeUseCase.classify(_party, _enemies) on every
## end_current_turn() call -- with every enemy's HP already at 0, this
## resolves to "won" and marks the round over immediately, deterministically,
## without depending on any seed-specific attack-roll outcome.
func _force_win(instance) -> void:
	for enemy in instance._enemies:
		enemy.hp_current = 0
	instance.end_turn_control.press()


# ══════════════════════════════════════════════════════════════════════════
# Step 1 (test_criteria): exploration boot succeeds.
# ══════════════════════════════════════════════════════════════════════════

func test_exploration_boot_succeeds() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"a freshly-booted MainScene must default to GameMode.EXPLORATION"
	)
	assert_not_null(instance.scenario_session, "MainScene must construct a real scenario_session at boot")
	assert_not_null(instance.exploration_controller, "MainScene must construct a real exploration_controller at boot")
	assert_not_null(instance.hex_grid_view, "MainScene must wire a real hex_grid_view at boot")

	# Fixture roster: Titus' party token is already rendered on the
	# exploration hex grid before any encounter is triggered.
	assert_true(instance._party.size() > 0, "exploration boot must already assemble a real party roster")
	var party_token = instance.hex_grid_view.get_token(instance._party[0].combatant_id)
	assert_not_null(party_token, "the exploration boot must render a token for the party's lead combatant")


# ══════════════════════════════════════════════════════════════════════════
# Step 2 (test_criteria): a combat encounter can be triggered.
# ══════════════════════════════════════════════════════════════════════════

func test_combat_encounter_can_be_triggered() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	_enter_combat(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.COMBAT,
		"_on_combat_triggered('prologue') must switch _game_mode to COMBAT"
	)
	assert_eq(instance._active_encounter_id, PROLOGUE_ENCOUNTER_ID, "the just-triggered encounter_id must be recorded")
	assert_not_null(instance.round_session, "triggering combat must assemble a real, live round_session")
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter has exactly one enemy (the Skeleton)")
	assert_false(instance.round_session.is_round_over(), "a freshly-triggered round must not already be over")


# ══════════════════════════════════════════════════════════════════════════
# Step 3 (test_criteria): a verb/combine action can be dispatched and
# targeted -- driven the SAME way tests/gut/test_steel_thread_e2e.gd's own
# Strike criterion does (verb_bar_view.press() -> Layer 2 selection ->
# hex_grid_view.hex_clicked resolves the target), through the REAL
# ActionResolverPort/ResolveActionUseCase path (ADR-002: no forked
# resolution logic).
# ══════════════════════════════════════════════════════════════════════════

func test_verb_dispatch_and_targeting_resolves_a_strike() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	_enter_combat(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available(STRIKE), "fixture assumption: STRIKE must be available against the Skeleton at seed=42")

	var actor_id: String = instance.round_session.current_actor().display_id()
	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	var events_before: int = instance.event_log_view.get_entry_count()

	# Dispatch: pressing STRIKE enters Layer 2 selection (never executes
	# directly) with at least one in-reach candidate target.
	var selection: Dictionary = instance.verb_bar_view.press(STRIKE)
	assert_true(instance.selection_overlay.is_active(), "STRIKE must enter Layer 2 targeting selection")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "entering STRIKE's Layer 2 selection must surface at least one in-reach target")
	var target_id: String = target_ids[0]

	var target_hp_before: int = instance.status_panel_view.get_status(target_id).get("hp_current", -1)
	assert_true(target_hp_before > 0, "sanity check: the target starts alive")

	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the chosen target has a rendered HexGridView token")

	# Targeted: the real player-interaction path -- a hex click on the
	# highlighted target -- resolves through select_target()/
	# ResolveActionUseCase.
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	var target_hp_after: int = instance.status_panel_view.get_status(target_id).get("hp_current", -1)
	assert_true(target_hp_after < target_hp_before, "a dispatched, targeted Strike must actually damage the target")

	var after_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(after_remaining, before_remaining - 1, "the acting combatant's action budget must decrease by exactly 1")

	assert_true(instance.event_log_view.get_entry_count() > events_before, "a dispatched, targeted Strike must log at least one real event")
	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the dispatched Strike resolves")


# ══════════════════════════════════════════════════════════════════════════
# Step 4 (test_criteria): the round resolves to completion -- the
# round-over equivalent signal/state fires.
# ══════════════════════════════════════════════════════════════════════════

func test_round_resolves_to_completion() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	_enter_combat(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(instance.round_session.is_round_over(), "fixture assumption: the round must not already be over right after triggering combat")

	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	# The round-over STATE fires: RoundSession reports the round concluded,
	# with a decided 'won' outcome. NOTE: when end_current_turn() itself
	# already drives the round to its conclusion (as here — every enemy is
	# already dead when the turn ends), MainScene.gd's own
	# _on_end_turn_control_turn_ended() documents that it invokes
	# _on_round_over() DIRECTLY rather than through
	# TurnController.set_session()/_drive() -- turn_controller's `round_over`
	# Signal deliberately only fires from inside _drive() (see
	# presentation/turn_controller.gd's own doc), so the STATE (below) is the
	# correct, always-observable golden-path oracle for this path; the SIGNAL
	# variant is separately characterized by
	# test_round_over_signal_fires_when_the_ai_auto_drive_loop_concludes_the_round().
	assert_true(instance.round_session.is_round_over(), "the round must resolve to completion once every enemy is defeated")
	assert_eq(instance.round_session.outcome(), "won", "the concluded round's outcome must be 'won'")

	# Downstream of the round-over state firing, the composition
	# root's own post-combat handoff (_on_combat_won()) commits the mode
	# switch back to EXPLORATION -- proving the round-over firing genuinely
	# propagated end-to-end, not merely flipped an inert flag.
	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"a 'won' round-over must switch _game_mode back to EXPLORATION via the real post-combat handoff"
	)


## test_round_over_signal_fires_when_the_ai_auto_drive_loop_concludes_the_round
## -- the SIGNAL half of "round-over equivalent signal/state fires"
## (test_criteria). presentation/turn_controller.gd's own doc is explicit:
## `round_over` is emitted ONLY from inside `_drive()`, once its auto-drive
## loop settles with `is_round_over()` true — NOT from MainScene's own
## `_on_end_turn_control_turn_ended()` shortcut (the "round-stall fix" path
## test_round_resolves_to_completion() above exercises). Driving the SAME
## real, composition-root `turn_controller` node's own `on_end_turn_pressed()`
## public method directly (rather than through `$EndTurnControl`) reaches
## that real `_drive()` call, so this test observes the genuine `round_over`
## Signal firing on the actual production TurnController instance -- no
## test-local double, no forked resolution logic (ADR-002).
func test_round_over_signal_fires_when_the_ai_auto_drive_loop_concludes_the_round() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	_enter_combat(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	for enemy in instance._enemies:
		enemy.hp_current = 0

	watch_signals(instance.turn_controller)
	await instance.turn_controller.on_end_turn_pressed()
	await get_tree().process_frame

	assert_signal_emitted(
		instance.turn_controller, "round_over",
		"TurnController.on_end_turn_pressed() must emit its own round_over signal once _drive() observes the round has resolved to completion"
	)
	assert_true(instance.round_session.is_round_over(), "the underlying RoundSession state must agree the round is over")


# ══════════════════════════════════════════════════════════════════════════
# Capstone: the FULL golden path in one continuous run -- boot exploration,
# trigger the encounter, dispatch+target a real Strike, then drive the round
# to completion -- exactly the ordered sequence test_criteria describes.
# This is the single test every subsequent extraction feature must keep
# green, unmodified, as its concrete RISK-001 regression oracle.
# ══════════════════════════════════════════════════════════════════════════

func test_full_combat_round_golden_path_characterization_baseline() -> void:
	# 1. Exploration boot succeeds.
	var instance = _boot_main_scene()
	await get_tree().process_frame
	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "step 1: exploration boot must succeed")

	# 2. A combat encounter can be triggered.
	_enter_combat(instance)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "step 2: the prologue encounter must be triggerable")
	assert_not_null(instance.round_session, "step 2: a real round_session must be live once combat is triggered")

	# 3. A verb (Strike) can be dispatched and targeted.
	assert_true(instance._verb_registry.is_available(STRIKE), "step 3 fixture assumption: STRIKE must be available")
	var selection: Dictionary = instance.verb_bar_view.press(STRIKE)
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "step 3: STRIKE's Layer 2 selection must surface at least one target")
	var target_id: String = target_ids[0]
	var target_hp_before: int = instance.status_panel_view.get_status(target_id).get("hp_current", -1)
	var target_token = instance.hex_grid_view.get_token(target_id)

	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	var target_hp_after: int = instance.status_panel_view.get_status(target_id).get("hp_current", -1)
	assert_true(target_hp_after < target_hp_before, "step 3: the dispatched, targeted Strike must actually resolve and damage the target")

	# 4. The round resolves to completion (round-over state fires -- see
	# test_round_over_signal_fires_when_the_ai_auto_drive_loop_concludes_the_round()
	# above for this same golden path's SIGNAL-firing variant).
	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(instance.round_session.is_round_over(), "step 4: the round must resolve to completion")
	assert_eq(instance.round_session.outcome(), "won", "step 4: the concluded round's outcome must be 'won'")
	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "step 4: a concluded, 'won' round must hand control back to EXPLORATION mode")
