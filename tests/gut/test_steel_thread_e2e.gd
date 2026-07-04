extends GutTest
## tests/gut/test_steel_thread_e2e.gd — FEAT-180 (US-015 / FR-015; the
## in-process portion of US-017/NFR-003/NFR-004).
##
## THE mandatory integration test suite exercising the FULL steel thread
## end-to-end through the REAL, shipped res://MainScene.tscn composition root
## (project.godot's own run/main_scene target) — no test-local resolver/
## use-case/registry graph, no mocked Application-layer port anywhere in this
## file. Every collaborator driven below (`_verb_registry`, `verb_bar_view`,
## `selection_overlay`, `cancel_controller`, `hex_grid_view`,
## `movement_input_controller`, `round_session`, `status_panel_view`,
## `event_log_view`, `end_turn_control`) is the exact, unmodified, REUSED
## production instance MainScene.gd's own _ready() wires (ADR-002/CR-001: no
## duplicate/forked resolution logic anywhere in this suite).
##
## This file consolidates, under one steel-thread-shaped narrative, coverage
## already individually proven by tests/gut/test_strike_layer2_integration.gd,
## test_step_layer2_integration.gd, test_stride_layer2_integration.gd,
## test_end_turn_integration.gd, test_cancel_controller_integration.gd, and
## test_verb_bar_view.gd -- this suite is the single, explicitly-named FEAT-180
## smoke gate proving all of it composes correctly TOGETHER through the one
## real entry point (verb bar renders, correctly gated) to the one real exit
## point (action resolved, board/status/lock updated), matching this
## project's established "capstone E2E suite" precedent
## (tests/e2e/test_full_steel_thread_e2e.gd,
## tests/e2e/test_steel_thread_post_remediation_smoke.gd).
##
## test_criteria satisfied:
##   1. test_entry_point_verb_bar_renders_correctly_gated_at_turn_start()
##   2. test_strike_flow_resolves_via_select_target_with_board_status_lock_updating()
##   3. test_step_flow_moves_token_via_move_token_with_no_action_spent()
##   4. test_stride_flow_moves_token_via_move_token_with_one_action_spent()
##   5. test_end_turn_flow_transitions_turn_state_with_no_layer2_step()
##   6. test_cancel_from_strike_layer2_produces_zero_side_effects_and_returns_to_layer1()
##      test_cancel_from_step_layer2_produces_zero_side_effects_and_returns_to_layer1()
##      test_cancel_from_stride_layer2_produces_zero_side_effects_and_returns_to_layer1()
##   7. (headless-boot / zero ERROR-WARNING / viewport-bounds) — covered by
##      tests/integration/test_headless_boot_smoke.py (this feature's sibling
##      file) and tests/gut/test_viewport_centering.gd, reused rather than
##      re-derived here.
##
## No production Application/Domain/Presentation code is modified for this
## feature (files_to_modify is empty) — every object driven below is already
## covered by its own unit/integration suite; this file's sole job is proving
## they ALL still compose correctly, together, through the ONE real MainScene
## entry point.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const SelectionOverlayClass = preload("res://presentation/selection_overlay.gd")
const CancelControllerClass = preload("res://presentation/cancel_controller.gd")
const RoundEventsClass       = preload("res://core/rules/round_events.gd")

const STRIKE: String = "STRIKE"
const STEP: String = "STEP"
const STRIDE: String = "STRIDE"
const END_TURN: String = "END_TURN"

## The pinned deterministic-test fixture seed (matches
## data/encounters/prologue_encounter.tres' own `seed` field, 42) — injected
## in-process via MainScene's `seed_override` contract (ADR-004 top
## precedence), matching every other integration/E2E suite's established
## convention in this codebase.
const SEED: int = 42


# ══════════════════════════════════════════════════════════════════════════
# Shared fixture / helpers — mirrors this codebase's established
# `_boot_main_scene_with_seed()` convention (tests/gut/
# test_strike_layer2_integration.gd, test_step_layer2_integration.gd,
# test_stride_layer2_integration.gd, test_end_turn_integration.gd,
# test_cancel_controller_integration.gd), duplicated here rather than shared
# across files, matching this project's per-suite-file convention.
# ══════════════════════════════════════════════════════════════════════════

func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


func _find_combatant_by_id(instance, combatant_id: String) -> Dictionary:
	for combatant in instance._party + instance._enemies:
		if combatant.get("combatant_id", "") == combatant_id:
			return combatant
	return {}


## _snapshot_positions(instance) -> Dictionary — combatant_id -> Vector2i(q,r)
## for every combatant currently carrying a hex_coord, mirroring
## tests/gut/test_cancel_controller_integration.gd's identically-named
## helper, used to prove a cancelled Step/Stride/Strike moves nobody.
func _snapshot_positions(instance) -> Dictionary:
	var snapshot: Dictionary = {}
	for combatant in instance._party + instance._enemies:
		var combatant_id: String = combatant.get("combatant_id", combatant.get("name", ""))
		var hex_coord = combatant.get("hex_coord", null)
		if hex_coord != null:
			snapshot[combatant_id] = Vector2i(hex_coord.q, hex_coord.r)
	return snapshot


func _snapshot_hp(instance) -> Dictionary:
	var snapshot: Dictionary = {}
	for combatant in instance._party + instance._enemies:
		var combatant_id: String = combatant.get("combatant_id", combatant.get("name", ""))
		snapshot[combatant_id] = combatant.get("hp_current", -1)
	return snapshot


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (entry_point) — Layer 1's verb bar renders at the active
# player's turn start with Strike/Step/Stride/End Turn correctly gated by
# LIVE game state (US-015/FR-015 "entry point" contract).
# ══════════════════════════════════════════════════════════════════════════

func test_entry_point_verb_bar_renders_correctly_gated_at_turn_start() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: the first actor must be the living player combatant (Titus) at seed=42"
	)

	assert_not_null(instance.verb_bar_view, "MainScene must wire a real $VerbBarView (Layer 1 entry point)")
	assert_eq(
		instance.verb_bar_view.get_verb_ids(), [STRIKE, STEP, STRIDE, END_TURN],
		"the Layer 1 verb bar must render exactly one button per Strike/Step/Stride/End Turn, in that order"
	)
	assert_eq(instance.verb_bar_view.get_button_count(), 4, "exactly four verb buttons must be rendered")

	# Each verb's rendered enabled/disabled state must agree EXACTLY with live
	# game-state availability -- never a stale/hardcoded gate.
	var action_economy = instance.round_session.current_action_economy()
	var remaining: int = action_economy.get_remaining() if action_economy != null else 0

	var expected_strike_available: bool = remaining > 0 and instance._strike_reachable_target_ids().size() > 0
	var expected_step_available: bool = instance.movement_input_controller.get_selectable_step_hexes().size() > 0
	var expected_stride_available: bool = remaining > 0 and instance.movement_input_controller.get_selectable_stride_hexes().size() > 0

	assert_eq(instance._verb_registry.is_available(STRIKE), expected_strike_available, "STRIKE gating must reflect live actions-remaining + in-reach-target state")
	assert_eq(instance._verb_registry.is_available(STEP), expected_step_available, "STEP gating must reflect a live legal-adjacent-hex set")
	assert_eq(instance._verb_registry.is_available(STRIDE), expected_stride_available, "STRIDE gating must reflect live actions-remaining + legal-Speed-hex state")
	assert_true(instance._verb_registry.is_available(END_TURN), "END_TURN must always be available")

	assert_eq(instance.verb_bar_view.get_button(STRIKE).disabled, not expected_strike_available)
	assert_eq(instance.verb_bar_view.get_button(STEP).disabled, not expected_step_available)
	assert_eq(instance.verb_bar_view.get_button(STRIDE).disabled, not expected_stride_available)
	assert_false(instance.verb_bar_view.get_button(END_TURN).disabled, "End Turn's rendered button must never be disabled")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — Strike: verb -> target -> resolves via
# select_target()/ResolveAction, with board (HP)/status (action budget)/lock
# (event log) all updating.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_flow_resolves_via_select_target_with_board_status_lock_updating() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available(STRIKE), "fixture assumption: STRIKE is available at seed=42")

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_true(before_remaining > 0, "sanity check: the acting combatant starts with a positive action budget")
	var events_before: int = instance.event_log_view.get_entry_count()

	# Layer 1 -> Layer 2: pressing STRIKE calls enter_selection(), never
	# execute() directly (mirrors tests/gut/test_verb_bar_view.gd's Criterion
	# 2, proven here through the REAL registry rather than a fake one).
	var selection: Dictionary = instance.verb_bar_view.press(STRIKE)
	assert_true(instance.selection_overlay.is_active(), "STRIKE must enter Layer 2 (SelectionOverlay active)")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "entering STRIKE's Layer 2 selection must surface at least one in-reach target")
	var target_id: String = target_ids[0]

	var target_hp_before: int = instance.status_panel_view.get_status(target_id).get("hp_current", -1)
	assert_true(target_hp_before > 0, "sanity check: the target starts alive")

	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the chosen target has a rendered HexGridView token")

	# Layer 2 -> resolve: simulate the real player interaction (a left-click
	# on the highlighted target's own hex, via the REAL HexGridView.hex_clicked
	# signal presentation/selection_overlay.gd is subscribed to), which
	# resolves through the SAME ActionResolverPort.select_target()/
	# ResolveActionUseCase path every other Strike path in this codebase uses
	# (ADR-002: no forked resolution logic) -- never a direct
	# `_verb_registry.execute()` shortcut, so the full Layer2->Layer1 UI
	# transition is exercised too.
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	# Board updates: the target's HP.
	var target_hp_after: int = instance.status_panel_view.get_status(target_id).get("hp_current", -1)
	assert_true(target_hp_after < target_hp_before, "the target's HP must decrease -- the real Strike must have actually damaged it")

	# Status updates: the acting combatant's action budget.
	var after_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(after_remaining, before_remaining - 1, "the acting combatant's action_budget_remaining must decrease by EXACTLY 1 after the real Strike resolves")

	# Lock/log updates: at least one new event was recorded through the real
	# event sink, and Layer 2 has returned to Layer 1.
	assert_true(instance.event_log_view.get_entry_count() > events_before, "resolving STRIKE must log at least one real event")
	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once STRIKE resolves")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — Step: verb -> destination -> moves the token via
# move_token() with NO action spent.
# ══════════════════════════════════════════════════════════════════════════

func test_step_flow_moves_token_via_move_token_with_no_action_spent() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available(STEP), "fixture assumption: STEP is available at seed=42")

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_true(before_remaining > 0, "sanity check: the acting combatant starts with a positive action budget")

	var selection: Dictionary = instance.verb_bar_view.press(STEP)
	assert_true(instance.selection_overlay.is_active(), "STEP must enter Layer 2 (SelectionOverlay active)")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "entering STEP's Layer 2 selection must surface at least one legal destination hex")
	var destination = candidate_hexes[0]

	var token_before = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_before, "the real HexGridView must already carry a token for the active actor")
	assert_false(token_before.hex_coord.equals(destination), "sanity check: the chosen destination hex must differ from the actor's starting hex")

	# Simulate the real player interaction: a left-click resolving to the
	# highlighted destination's own hex, via the REAL HexGridView.hex_clicked
	# signal presentation/selection_overlay.gd is subscribed to -- resolves
	# through the real MovementPort (movement_input_controller.step_to() ->
	# move_token()), never a direct `_verb_registry.execute()` shortcut, so
	# the full Layer2->Layer1 UI transition is exercised too.
	instance.hex_grid_view.hex_clicked.emit(destination)

	var moved_combatant: Dictionary = _find_combatant_by_id(instance, actor_id)
	assert_true(moved_combatant.get("hex_coord").equals(destination), "the live combatant Dictionary's hex_coord must move to the selected hex via move_token()")

	var token_after = instance.hex_grid_view.get_token(actor_id)
	assert_true(token_after.hex_coord.equals(destination), "the real HexGridView's token must resync to the new hex after the Step")

	var after_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(after_remaining, before_remaining, "a Step is a FREE move -- action_budget_remaining must be COMPLETELY UNCHANGED")
	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once STEP resolves")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — Stride: verb -> destination -> moves the token via
# move_token() with EXACTLY ONE action spent.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_flow_moves_token_via_move_token_with_one_action_spent() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available(STRIDE), "fixture assumption: STRIDE is available at seed=42")

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the acting combatant carries a live ActionEconomy")
	var before_remaining: int = action_economy.get_remaining()
	assert_true(before_remaining > 0, "sanity check: the acting combatant starts with a positive action budget")

	var selection: Dictionary = instance.verb_bar_view.press(STRIDE)
	assert_true(instance.selection_overlay.is_active(), "STRIDE must enter Layer 2 (SelectionOverlay active)")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "entering STRIDE's Layer 2 selection must surface at least one legal destination hex")
	var destination = candidate_hexes[0]

	var token_before = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_before, "the real HexGridView must already carry a token for the active actor")
	assert_false(token_before.hex_coord.equals(destination), "sanity check: the chosen destination hex must differ from the actor's starting hex")

	# Simulate the real player interaction: a left-click resolving to the
	# highlighted destination's own hex, via the REAL HexGridView.hex_clicked
	# signal presentation/selection_overlay.gd is subscribed to -- resolves
	# through the real MovementPort (movement_input_controller.stride_to() ->
	# move_token()), never a direct `_verb_registry.execute()` shortcut, so
	# the full Layer2->Layer1 UI transition is exercised too.
	instance.hex_grid_view.hex_clicked.emit(destination)

	var moved_combatant: Dictionary = _find_combatant_by_id(instance, actor_id)
	assert_true(moved_combatant.get("hex_coord").equals(destination), "the live combatant Dictionary's hex_coord must move to the selected hex via move_token()")

	var token_after = instance.hex_grid_view.get_token(actor_id)
	assert_true(token_after.hex_coord.equals(destination), "the real HexGridView's token must resync to the new hex after the Stride")

	assert_eq(action_economy.get_remaining(), before_remaining - 1, "a Stride must spend EXACTLY ONE action -- unlike a Step, which is free")
	assert_eq(
		instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1), before_remaining - 1,
		"StatusPanelView's displayed action budget must reflect the one action the Stride spent"
	)
	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once STRIDE resolves")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — End Turn: transitions turn state with NO Layer 2 step at all.
# ══════════════════════════════════════════════════════════════════════════

func test_end_turn_flow_transitions_turn_state_with_no_layer2_step() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available(END_TURN), "End Turn must always be available")
	assert_false(instance.selection_overlay.is_active(), "fixture assumption: Layer 2 is inactive before any verb is pressed")

	watch_signals(instance.verb_bar_view)
	watch_signals(instance.selection_overlay)

	var events_before: int = instance.event_sink.log.size()
	var result: Dictionary = instance.verb_bar_view.press(END_TURN)

	# No Layer 2 step whatsoever: End Turn calls execute() DIRECTLY.
	assert_signal_emitted(instance.verb_bar_view, "verb_executed", "pressing End Turn must call execute() directly")
	assert_signal_not_emitted(instance.verb_bar_view, "verb_selection_entered", "pressing End Turn must NEVER enter Layer 2")
	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must remain inactive -- End Turn produces no SelectionDescriptor")

	assert_true(result.get("ok", false), "End Turn must resolve successfully through the real TurnPort.end_turn() path")

	# Turn state genuinely transitioned -- proven via the real event sink's
	# TurnAdvancedEvent trail (the prologue's two combatants alternate turns,
	# so comparing actor identity alone would be ambiguous once TurnController
	# auto-drives the enemy's turn in between).
	var turn_advanced_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.TurnAdvancedEvent)
	assert_true(
		instance.round_session.is_round_over() or turn_advanced_events.size() >= 1,
		"clicking End Turn must advance RoundSession's turn cursor (or conclude the round)"
	)
	assert_true(instance.event_sink.log.size() > events_before, "ending the turn must emit at least one new round event")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 — cancel/back from ANY Layer 2 mode produces ZERO side effects
# (no board mutation, no action spent, no event logged) and returns to
# Layer 1.
# ══════════════════════════════════════════════════════════════════════════

func test_cancel_from_strike_layer2_produces_zero_side_effects_and_returns_to_layer1() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available(STRIKE), "fixture assumption: STRIKE is available at seed=42")

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	var events_before: int = instance.event_log_view.get_entry_count()
	var positions_before: Dictionary = _snapshot_positions(instance)
	var hp_before: Dictionary = _snapshot_hp(instance)

	instance.verb_bar_view.press(STRIKE)
	assert_true(instance.selection_overlay.is_active(), "sanity check: STRIKE Layer 2 selection must be active before cancelling")

	watch_signals(instance.selection_overlay)
	var cancelled: bool = instance.cancel_controller.cancel()

	assert_true(cancelled, "cancel() must report a real cancellation while STRIKE's selection was active")
	assert_false(instance.selection_overlay.is_active(), "cancelling STRIKE must return to Layer 1")
	assert_signal_emitted_with_parameters(instance.selection_overlay, "selection_cancelled", [STRIKE])
	assert_signal_not_emitted(instance.selection_overlay, "selection_resolved", "a cancel must NEVER resolve through the verb registry")

	assert_eq(instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1), before_remaining, "cancelling STRIKE must spend no action")
	assert_eq(instance.event_log_view.get_entry_count(), events_before, "cancelling STRIKE must log no event")
	assert_eq(_snapshot_positions(instance), positions_before, "cancelling STRIKE must move nobody")
	assert_eq(_snapshot_hp(instance), hp_before, "cancelling STRIKE must damage nobody")

	# The verb bar remains fully usable afterward -- STRIKE can be re-entered.
	instance.verb_bar_view.press(STRIKE)
	assert_true(instance.selection_overlay.is_active(), "STRIKE must be re-enterable after a prior cancel")


func test_cancel_from_step_layer2_produces_zero_side_effects_and_returns_to_layer1() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available(STEP), "fixture assumption: STEP is available at seed=42")

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	var events_before: int = instance.event_log_view.get_entry_count()
	var positions_before: Dictionary = _snapshot_positions(instance)

	instance.verb_bar_view.press(STEP)
	assert_true(instance.selection_overlay.is_active(), "sanity check: STEP Layer 2 selection must be active before cancelling")

	watch_signals(instance.selection_overlay)
	var cancelled: bool = instance.cancel_controller.cancel()

	assert_true(cancelled, "cancel() must report a real cancellation while STEP's selection was active")
	assert_false(instance.selection_overlay.is_active(), "cancelling STEP must return to Layer 1")
	assert_signal_emitted_with_parameters(instance.selection_overlay, "selection_cancelled", [STEP])
	assert_signal_not_emitted(instance.selection_overlay, "selection_resolved", "a cancel must NEVER resolve through the verb registry")

	assert_eq(instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1), before_remaining, "cancelling STEP must spend no action")
	assert_eq(instance.event_log_view.get_entry_count(), events_before, "cancelling STEP must log no event")
	assert_eq(_snapshot_positions(instance), positions_before, "cancelling STEP must move nobody")

	instance.verb_bar_view.press(STEP)
	assert_true(instance.selection_overlay.is_active(), "STEP must be re-enterable after a prior cancel")


func test_cancel_from_stride_layer2_produces_zero_side_effects_and_returns_to_layer1() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available(STRIDE), "fixture assumption: STRIDE is available at seed=42")

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	var action_economy = instance.round_session.current_action_economy()
	var before_remaining: int = action_economy.get_remaining()
	var events_before: int = instance.event_log_view.get_entry_count()
	var positions_before: Dictionary = _snapshot_positions(instance)

	instance.verb_bar_view.press(STRIDE)
	assert_true(instance.selection_overlay.is_active(), "sanity check: STRIDE Layer 2 selection must be active before cancelling")

	watch_signals(instance.selection_overlay)
	var cancelled: bool = instance.cancel_controller.cancel()

	assert_true(cancelled, "cancel() must report a real cancellation while STRIDE's selection was active")
	assert_false(instance.selection_overlay.is_active(), "cancelling STRIDE must return to Layer 1")
	assert_signal_emitted_with_parameters(instance.selection_overlay, "selection_cancelled", [STRIDE])
	assert_signal_not_emitted(instance.selection_overlay, "selection_resolved", "a cancel must NEVER resolve through the verb registry")

	assert_eq(
		action_economy.get_remaining(), before_remaining,
		"cancelling STRIDE must spend no action -- the one action a real Stride WOULD have spent must remain unspent"
	)
	assert_eq(instance.event_log_view.get_entry_count(), events_before, "cancelling STRIDE must log no event")
	assert_eq(_snapshot_positions(instance), positions_before, "cancelling STRIDE must move nobody")

	instance.verb_bar_view.press(STRIDE)
	assert_true(instance.selection_overlay.is_active(), "STRIDE must be re-enterable after a prior cancel")
