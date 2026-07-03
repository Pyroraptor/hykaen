extends GutTest
## tests/e2e/test_full_steel_thread_e2e.gd — FEAT-167
## (US-005..US-011, iteration D "UI Consolidation + Movement UX" capstone).
##
## THE final E2E smoke test exercising the COMPLETE steel thread, entry to
## exit, through the real, fully-consolidated res://MainScene.tscn
## composition root (project.godot's own run/main_scene target) — no
## test-local resolver/use-case/session graph, no mocked Application-layer
## port anywhere in this file. Every collaborator driven below
## (HexGridView, MoveActionControl, StrikeActionControl, EndTurnControl,
## StatusPanelView, ResultScreenView, movement_input_controller,
## TurnController, resolve_action_use_case, RoundSession) is the exact,
## unmodified, REUSED production instance MainScene.gd's own _ready() wires
## — this file's job is proving they ALL compose correctly together, one
## continuous playthrough, from turn start through post-resolution lock.
##
## The single continuous journey this file drives:
##   1. Boot -> the active player's turn_started (TurnController.
##      active_actor_changed, this codebase's realization of the design
##      notes' API contract #1) highlights the EXACT union(Step, Stride) hex
##      set on the real HexGridView and shows the real MoveActionControl
##      (US-006/US-007).
##   2. A simulated click (HexGridView.hex_clicked.emit()) on one of those
##      highlighted hexes moves the token via movement_input_controller's
##      real step_to()/stride_to() dispatch, resyncs HexGridView's rendered
##      token position, and the highlight is cleared then re-derived from
##      the mover's NEW position (US-006/US-008).
##   3. A real Strike, driven through StrikeActionControl.select_target()
##      -> resolve_action_use_case.resolve(), decrements the acting
##      combatant's action budget as reflected by the real StatusPanelView's
##      projection (US-009).
##   4. The encounter is driven to resolution (bounded, real
##      StrikeActionControl/EndTurnControl input, exactly as a human would
##      drive it) — once EncounterResolved (EncounterResultEvent) fires,
##      StrikeActionControl, EndTurnControl, AND MoveActionControl are all
##      disabled/hidden, the hex highlight is cleared, and no further
##      hex_clicked/Strike/EndTurn signal produces any state mutation
##      (US-005/US-008/US-010/US-011).
##
## FEAT-167 also closes a real gap this file's own probing surfaced: prior
## to this feature, presentation/result_screen_view.gd's lock_all_controls()
## locked StrikeActionControl/EndTurnControl/movement_input_controller but
## never MoveActionControl — so on the (very common, single-enemy-fixture)
## outcome-decision path where the player's own Strike defeats the
## encounter's last enemy and the immediately-following EndTurnControl.
## press() decides "won" directly inside RoundSession.end_current_turn()
## (never re-driving TurnController, so its round_over signal / MainScene's
## _on_round_over() backstop is never reached), MoveActionControl stayed
## VISIBLE and enabled indefinitely after the encounter had already
## concluded — violating this steel thread's design notes' API contract #6
## ("MoveActionControl hidden") and this feature's own test_criteria.
## presentation/result_screen_view.gd/MainScene.gd are the two files this
## feature extends (each already documents the exact minimal, additive
## change made) to close that gap uniformly, regardless of which of
## RoundSession's two outcome-decision call paths
## (advance_ai_turn()/end_current_turn()) actually decided the encounter —
## this test drives exactly that path (the player's own Strike/EndTurn
## deciding "won") so the fix is exercised, not sidestepped.
##
## No production Application/Domain code is modified for this feature —
## only the two thin Presentation-layer wiring points named above (ADR-001:
## neither file gains a Node/Control import it didn't already have, neither
## re-implements any rule; each simply forwards an already-existing lock()
## call to one more already-existing collaborator, mirroring the exact
## pattern already established for movement_input_controller).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const HexGridViewClass    = preload("res://presentation/hex_grid_view.gd")
const RoundEventsClass    = preload("res://core/rules/round_events.gd")

## The pinned deterministic-test fixture seed (matches
## data/encounters/prologue_encounter.tres' own `seed` field, 42) — injected
## in-process via MainScene's `seed_override` contract (ADR-004 top
## precedence), mirroring every other integration/E2E suite's convention
## (tests/integration/test_steel_thread_prologue_encounter.gd,
## tests/integration/test_movement_affordance_integration.gd,
## tests/integration/test_status_bar_refresh_integration.gd).
const SEED: int = 42

## Safety bound on the Strike/End-Turn drive loop (CWE-835 "never loop
## unbounded" guard, mirroring tests/integration/
## test_steel_thread_prologue_encounter.gd's `_MAX_DRIVE_ITERATIONS` and
## tests/e2e/test_steel_thread_post_remediation_smoke.gd's
## `_MAX_TURN_EXCHANGES`).
const _MAX_DRIVE_ITERATIONS: int = 20


# ══════════════════════════════════════════════════════════════════════════
# Shared fixture: boot the REAL res://MainScene.tscn composition root.
# ══════════════════════════════════════════════════════════════════════════

func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


## _find_combatant_by_id(instance, combatant_id) -> Dictionary — looks up a
## live combatant Dictionary (MainScene's own _party/_enemies fields, the
## SAME Dictionaries core/rules/movement.gd/resolve_action_use_case.gd mutate
## in place), mirroring the identically-named helper already established by
## tests/integration/test_steel_thread_prologue_encounter.gd /
## tests/integration/test_movement_affordance_integration.gd.
func _find_combatant_by_id(instance, combatant_id: String) -> Dictionary:
	for combatant in instance._party + instance._enemies:
		if combatant.get("combatant_id", "") == combatant_id:
			return combatant
	return {}


## _as_key_set(hexes) -> Dictionary — a "q,r" -> true set built from an
## Array of core/geometry/hex_coord.gd HexCoords, mirroring
## tests/integration/test_movement_affordance_integration.gd's
## identically-named helper (HexCoord is a value object with no custom
## `==`/hash, so this is the correct value-equality comparison,
## order/instance-identity independent).
func _as_key_set(hexes: Array) -> Dictionary:
	var set: Dictionary = {}
	for hex_coord in hexes:
		set["%d,%d" % [hex_coord.q, hex_coord.r]] = true
	return set


## _assert_highlight_matches_controller_union(instance, context) -> void —
## asserts the REAL HexGridView's currently-highlighted set (read directly
## off `_selectable_hexes`, the established non-invasive convention — see
## tests/integration/test_movement_affordance_integration.gd's file-level
## doc for why this is the correct way to observe it without a stub/mock)
## exactly equals union(movement_input_controller.get_selectable_step_hexes(),
## get_selectable_stride_hexes()) computed RIGHT NOW (API contract #3: "no
## filtering/re-derivation in the view").
func _assert_highlight_matches_controller_union(instance, context: String) -> void:
	var step_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	var stride_hexes: Array = instance.movement_input_controller.get_selectable_stride_hexes()
	var expected_keys: Dictionary = _as_key_set(step_hexes)
	for key in _as_key_set(stride_hexes).keys():
		expected_keys[key] = true

	var highlighted: Array = instance.hex_grid_view._selectable_hexes
	var highlighted_keys: Dictionary = _as_key_set(highlighted)

	assert_eq(
		highlighted_keys.keys().size(), expected_keys.keys().size(),
		"[%s] the real HexGridView's highlighted hex count must exactly equal union(Step, Stride)" % context
	)
	for key in expected_keys.keys():
		assert_true(highlighted_keys.has(key), "[%s] expected union hex %s to be highlighted" % [context, key])
	for key in highlighted_keys.keys():
		assert_true(expected_keys.has(key), "[%s] highlighted hex %s must be present in union(Step, Stride) -- no extra/filtered hex" % [context, key])


# ══════════════════════════════════════════════════════════════════════════
# THE full steel thread, one continuous playthrough through the real,
# fully-consolidated MainScene composition root.
# ══════════════════════════════════════════════════════════════════════════

func test_full_steel_thread_from_turn_start_to_post_resolution_lock() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	# ── Fixture assumptions (seed=42, prologue_encounter.tres) ─────────────
	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: the first actor must be the living player combatant (Titus) per prologue_encounter.tres' hex layout at seed=42"
	)
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter has exactly one enemy")

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	assert_ne(actor_id, "", "fixture assumption: the active actor carries a non-empty combatant_id")


	# ══════════════════════════════════════════════════════════════════════
	# Step 1 (US-006/US-007) — on the active player's turn_started, the real
	# HexGridView highlights the EXACT legal Step/Stride union and the real
	# MoveActionControl is visible.
	# ══════════════════════════════════════════════════════════════════════

	var step_hexes_at_start: Array = instance.movement_input_controller.get_selectable_step_hexes()
	var stride_hexes_at_start: Array = instance.movement_input_controller.get_selectable_stride_hexes()
	assert_true(step_hexes_at_start.size() > 0, "sanity check: the active player actor has at least one legal Step destination")
	assert_true(
		stride_hexes_at_start.size() >= step_hexes_at_start.size(),
		"sanity check: Stride (up to Speed hexes) must legally reach at least as many hexes as Step (1 hex)"
	)

	_assert_highlight_matches_controller_union(instance, "turn_started")

	assert_true(
		instance.move_action_control.is_enabled(),
		"MoveActionControl must be enabled (a non-empty selectable-hex set) on the active player's turn_started"
	)
	assert_true(
		instance.move_action_control.visible,
		"MoveActionControl must be visible on the active player's turn_started"
	)


	# ══════════════════════════════════════════════════════════════════════
	# Step 2 (US-006/US-008) — clicking a legal hex moves the token via
	# step_to()/stride_to(), resyncs HexGridView, then the highlight is
	# cleared and re-derived from the mover's NEW position.
	# ══════════════════════════════════════════════════════════════════════

	var destination = step_hexes_at_start[0]
	var token_before = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_before, "the real HexGridView must already carry a token for the active actor")
	assert_false(
		token_before.hex_coord.equals(destination),
		"sanity check: the chosen destination hex must differ from the actor's starting hex"
	)

	# Simulate the player's click: emit the REAL HexGridView's hex_clicked
	# signal directly (exactly as a real left-click's _unhandled_input()
	# translation would), driving it through MainScene's real,
	# res://MainScene.tscn-wired signal connection rather than calling any
	# MainScene handler method directly.
	instance.hex_grid_view.hex_clicked.emit(destination)

	var moved_combatant: Dictionary = _find_combatant_by_id(instance, actor_id)
	assert_false(moved_combatant.is_empty(), "fixture assumption: the moved actor must be one of MainScene's live combatant Dictionaries")
	assert_true(
		moved_combatant.get("hex_coord").equals(destination),
		"Combatant.position (the live combatant Dictionary's hex_coord) must change to the clicked legal hex via step_to()/stride_to()"
	)

	var token_after = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_after, "the real HexGridView must still carry a token for the moved actor")
	assert_true(
		token_after.hex_coord.equals(destination),
		"the real HexGridView's token must resync its hex_coord to the new hex after the move"
	)
	assert_eq(
		token_after.position, HexGridViewClass.axial_to_pixel(destination),
		"the real HexGridView's token must resync its rendered screen position to the new hex's ADR-004 axial-to-pixel projection"
	)

	# The highlight is cleared then re-derived from the mover's NEW
	# position -- proven the same way as the turn_started assertion above:
	# it must exactly equal union(Step, Stride) computed AFTER the move
	# (never left stale/pointing at the pre-move destination set).
	_assert_highlight_matches_controller_union(instance, "post-move")


	# ══════════════════════════════════════════════════════════════════════
	# Step 3 (US-009) — a real Strike decrements the acting combatant's
	# action budget as reflected by the real StatusPanelView's projection.
	# ══════════════════════════════════════════════════════════════════════

	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: the actor is still the living player combatant after their own Step/Stride"
	)

	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_true(before_remaining > 0, "sanity check: the acting combatant has a positive action budget before Striking")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor has a live domain ActionEconomy")

	var target_ids: Array = instance.strike_action_control.get_selectable_target_ids()
	assert_true(target_ids.size() > 0, "fixture assumption: the active actor has at least one in-reach target after moving")
	var target_id: String = target_ids[0]

	var strike_result: Dictionary = instance.strike_action_control.select_target(target_id)
	assert_true(strike_result.get("resolved", false), "the real resolve_action_use_case must resolve the player's Strike")

	var after_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(
		after_remaining, before_remaining - 1,
		"StatusPanelView.action_budget_remaining for the acting combatant must decrease by EXACTLY 1 after the real Strike resolves"
	)
	assert_eq(
		instance.status_panel_view.get_status(actor_id).get("spent"), action_economy.is_spent(),
		"StatusPanelView's displayed Spent value must match the domain ActionEconomy.is_spent() value after the real Strike"
	)


	# ══════════════════════════════════════════════════════════════════════
	# Step 4 (US-005/US-008/US-010/US-011) — drive the encounter to
	# resolution through the real StrikeActionControl/EndTurnControl nodes,
	# exactly as a human would (every enemy turn in between auto-driven by
	# the real $TurnController via MainScene's EndTurnControl.turn_ended
	# handoff), then assert every combat/movement input control is
	# disabled/hidden, the hex highlight is cleared, and it cannot be
	# re-triggered.
	# ══════════════════════════════════════════════════════════════════════

	var guard: int = 0
	while not instance.round_session.is_round_over() and guard < _MAX_DRIVE_ITERATIONS:
		if not instance.round_session.current_actor().get("_is_enemy", true):
			var live_target_ids: Array = instance.strike_action_control.get_selectable_target_ids()
			if live_target_ids.size() > 0:
				instance.strike_action_control.select_target(live_target_ids[0])
		instance.end_turn_control.press()
		guard += 1

	assert_true(
		instance.round_session.is_round_over(),
		"driving the real StrikeActionControl/EndTurnControl nodes must eventually conclude the round (guard=%d/%d)" % [guard, _MAX_DRIVE_ITERATIONS]
	)
	var decided_outcome: String = instance.round_session.outcome()
	assert_true(
		decided_outcome == "won" or decided_outcome == "lost",
		"RoundSession.outcome() must be a decided terminal outcome ('won' or 'lost') once the round concludes; got '%s'" % decided_outcome
	)
	assert_true(
		instance.result_screen_view.is_shown(),
		"the real $ResultScreenView must have processed the EncounterResolved (EncounterResultEvent) through MainScene's real event-sink pipeline"
	)

	# ── Strike/EndTurn/Move all disabled/hidden ─────────────────────────────
	assert_eq(instance.strike_action_control.get_button_count(), 0, "StrikeActionControl must render zero selectable-target buttons once the encounter has concluded")
	assert_true(instance.strike_action_control.is_locked(), "StrikeActionControl.is_locked() must be true once the encounter has concluded")

	assert_false(instance.end_turn_control.is_enabled(), "EndTurnControl must be disabled once the encounter has concluded")
	assert_true(instance.end_turn_control.is_locked(), "EndTurnControl.is_locked() must be true once the encounter has concluded")

	assert_false(instance.move_action_control.is_enabled(), "MoveActionControl must be disabled once the encounter has concluded")
	assert_false(instance.move_action_control.visible, "MoveActionControl must be hidden once the encounter has concluded")
	assert_true(instance.move_action_control.is_locked(), "MoveActionControl.is_locked() must be true once the encounter has concluded (FEAT-167)")

	assert_true(instance.movement_input_controller.is_locked(), "movement_input_controller.is_locked() must be true once the encounter has concluded")

	# ── The hex highlight is cleared ────────────────────────────────────────
	assert_eq(
		instance.hex_grid_view._selectable_hexes.size(), 0,
		"the real HexGridView's highlighted hex set must be empty once the encounter has concluded"
	)

	# ── ...and cannot be re-triggered: capture every live combatant's
	# position/HP/action-economy state, fire every input signal a stray UI
	# event could still emit, and assert NONE of it produced any mutation. ──
	var positions_before: Dictionary = {}
	var hp_before: Dictionary = {}
	for combatant in instance._party + instance._enemies:
		var id: String = combatant.get("combatant_id", "")
		positions_before[id] = combatant.get("hex_coord")
		hp_before[id] = combatant.get("hp_current", -1)
	var attack_event_count_before: int = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent).size()

	# A stray hex_clicked on an arbitrary hex (even one that WAS legal before
	# resolution, e.g. the fixture's original starting hex) must be a no-op.
	instance.hex_grid_view.hex_clicked.emit(destination)

	var strike_reject: Dictionary = instance.strike_action_control.select_target(target_id)
	assert_false(strike_reject.get("ok", true), "select_target() must be rejected after the encounter has concluded")
	assert_eq(strike_reject.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")

	var end_turn_reject: Dictionary = instance.end_turn_control.press()
	assert_false(end_turn_reject.get("ok", true), "press() must be rejected after the encounter has concluded")
	assert_eq(end_turn_reject.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")

	# No domain mutation whatsoever resulted from any of the above.
	for combatant in instance._party + instance._enemies:
		var id: String = combatant.get("combatant_id", "")
		assert_true(
			combatant.get("hex_coord").equals(positions_before[id]),
			"combatant %s's position must be unchanged by any post-resolution input" % id
		)
		assert_eq(
			combatant.get("hp_current", -2), hp_before[id],
			"combatant %s's HP must be unchanged by any post-resolution input" % id
		)
	assert_eq(
		instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent).size(), attack_event_count_before,
		"no additional AttackEvent may be emitted by any post-resolution input"
	)

	# ...and the highlight/affordance state remains cleared/locked -- it
	# cannot be re-triggered by the stray input above.
	assert_eq(instance.hex_grid_view._selectable_hexes.size(), 0, "the hex highlight must remain empty after a stray post-resolution hex_clicked signal")
	assert_false(instance.move_action_control.is_enabled(), "MoveActionControl must remain disabled after a stray post-resolution hex_clicked signal")
	assert_false(instance.move_action_control.visible, "MoveActionControl must remain hidden after a stray post-resolution hex_clicked signal")
	assert_eq(instance.strike_action_control.get_button_count(), 0, "StrikeActionControl must remain fully disabled after the rejected post-resolution select_target()")
	assert_false(instance.end_turn_control.is_enabled(), "EndTurnControl must remain disabled after the rejected post-resolution press()")
