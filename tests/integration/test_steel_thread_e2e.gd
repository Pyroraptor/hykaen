extends GutTest
## tests/integration/test_steel_thread_e2e.gd — FEAT-010 (US-010; the
## capstone integration/E2E test for this iteration's steel thread).
##
## Drives the REAL, shipped res://MainScene.tscn composition root (no
## test-local resolver/use-case graph, no mocked Application-layer port)
## through the complete steel thread this iteration (FEAT-001..FEAT-009)
## built, entry to exit:
##
##   entry_point:  RoundSession's cursor advances to a combatant's turn
##                 (either the initial cursor set in RoundSession._init(),
##                 or a later _advance_cursor()) -> that combatant's
##                 core/rules/action_economy.gd ActionEconomy.start_of_turn()
##                 fires -> can_take_action() reports true -> the Layer 1
##                 verb bar ($VerbBarView) renders Strike/Stride enabled.
##   exit_point:    the acting combatant performs exactly ONE Strike/Stride
##                  this turn (core/rules/action_economy.gd's per-turn
##                  action-used gate, FEAT-003) -> $VerbBarView greys
##                  Strike/Stride until that combatant's NEXT start_of_turn()
##                  -> an enemy Strike (core/combat/ai.gd, FEAT-007's
##                  single-action-per-decision AI) rolls against an AC
##                  sourced from data/enemies/skeleton.tres via
##                  data/enemies/enemy_resource.gd's EnemyResource --
##                  never a hard-coded constant (FEAT-001/FEAT-008).
##
## Every collaborator driven below (`_verb_registry`, `verb_bar_view`,
## `round_session`, `hex_grid_view`, `selection_overlay`, `end_turn_control`,
## `turn_controller`) is the exact, unmodified, REUSED production instance
## MainScene.gd's own _ready() wires (ADR-002/CR-001: no forked resolution
## logic anywhere in this file) -- this feature introduces NO new production
## code (files_to_modify is empty); its sole job is proving FEAT-001..009
## all still compose correctly together, end to end, through the real
## wiring.
##
## This suite does NOT re-test (and therefore does not duplicate) the
## individual unit-level proofs already established by:
##   tests/unit/test_action_economy_gate.gd / test_action_economy_can_take_action.gd
##     (the domain-level per-turn one-action gate in isolation)
##   tests/unit/test_verb_bar_availability.gd (verb-bar greying against a
##     directly-manipulated ActionEconomy, not a real cursor advance)
##   tests/unit/core/combat/test_ai_action_budget.gd / test_ai_reach_strike.gd /
##     test_ai_stride_then_strike.gd (AI single-action decision logic in
##     isolation)
##   tests/unit/test_build_enemy_combatant_defenses.gd / test_enemy_resource_fields.gd
##     (EnemyResource -> Combatant.ac field-sourcing in isolation)
##   tests/integration/test_headless_boot.gd (the exhaustive real-subprocess
##     zero-error/zero-warning headless-boot gate)
## -- this file's job is proving all of that machinery composes correctly
## TOGETHER, through the real cursor-advance seam (core/application/
## round_session.gd's single start_of_turn() call site, FEAT-004) and the
## real $VerbBarView/AI wiring, never a re-derived rule of its own.
##
## test_criteria satisfied by this file:
##   1. Cursor advances to player actor's turn -> start_of_turn() fires ->
##      can_take_action() true -> verb bar shows Strike/Stride enabled.
##   2. Player performs Strike -> spend_action() succeeds -> can_take_action()
##      false -> verb bar greys Strike/Stride -> a second same-turn action
##      attempt returns ACTION_ALREADY_USED.
##   3. Cursor advances to the next actor's turn (through a real enemy
##      activation) and back -> verb bar Strike/Stride re-enable for the
##      returning current actor.
##   4. Cursor advances to the AI-controlled Skeleton's turn -> the AI takes
##      exactly one action (Strike if in reach, else Stride -- never both);
##      the AC used by a Strike against the Skeleton is sourced from
##      skeleton.tres via EnemyResource, not a hard-coded constant.
##   5. A headless MainScene boot completes without error with the full
##      wiring (verb-bar callbacks, RoundSession, ActionEconomy, AI,
##      EnemyResource) active.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const SKELETON_TRES_PATH: String = "res://data/enemies/skeleton.tres"

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const RoundEventsClass = preload("res://core/rules/round_events.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")

## The pinned deterministic-test fixture seed (matches data/encounters/
## prologue_encounter.tres' own `seed` field, 42) -- this codebase's
## established integration/E2E test convention (injected in-process via
## MainScene's `seed_override` contract, ADR-004 top precedence).
const SEED: int = 42


# ══════════════════════════════════════════════════════════════════════════
# Shared fixture -- mirrors this codebase's established
# `_boot_main_scene_with_seed()` convention (tests/unit/
# test_verb_bar_availability.gd, tests/e2e/test_full_steel_thread_e2e.gd).
# ══════════════════════════════════════════════════════════════════════════

func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


## _resolve_strike_via_full_click_flow(instance, target_id) -> Variant --
## resolves a Strike through the SAME player-facing path a real click
## drives: VerbBarView.press("STRIKE") enters Layer 2 selection, then a left
## click on the target's own on-screen hex (hex_grid_view.hex_clicked, the
## real signal presentation/selection_overlay.gd is subscribed to) resolves
## it through selection_overlay -> `_verb_registry.execute()` ->
## resolve_action_use_case.resolve() -- never a direct
## `_verb_registry.execute()` shortcut, so the full Layer1->Layer2->Layer1
## UI transition (including the post-resolution refresh_availability() call)
## is exercised exactly as the real game drives it.
func _resolve_strike_via_full_click_flow(instance, target_id: String) -> void:
	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the chosen Strike target has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)


func _last_attack_event_by(instance, attacker_name: String):
	var events: Array = instance.event_sink.log
	for i in range(events.size() - 1, -1, -1):
		var event = events[i]
		if event is RoundEventsClass.AttackEvent and event.attacker_name == attacker_name:
			return event
	return null


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (entry_point) -- cursor advance to the player actor's turn ->
# start_of_turn() fires -> can_take_action() true -> verb bar shows
# Strike/Stride enabled.
# ══════════════════════════════════════════════════════════════════════════

func test_criterion1_cursor_advance_to_player_turn_fires_start_of_turn_and_verb_bar_shows_strike_stride_enabled() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: RoundSession._init()'s cursor must settle on the living player combatant (Titus) at seed=42"
	)

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor carries a live domain ActionEconomy")
	assert_true(
		action_economy.can_take_action(),
		"start_of_turn() must already have fired for the initial cursor position (RoundSession._init()) -- can_take_action() must report true before any spend"
	)

	assert_not_null(instance.verb_bar_view, "MainScene must wire a real $VerbBarView (Layer 1 entry point)")
	assert_true(instance._verb_registry.is_available("STRIKE"), "STRIKE must be available at the entry point (Skeleton starts adjacent to Titus per the prologue fixture)")
	assert_true(instance._verb_registry.is_available("STRIDE"), "STRIDE must be available at the entry point (can_take_action() true and a legal Stride destination exists)")

	assert_false(instance.verb_bar_view.get_button("STRIKE").disabled, "the rendered STRIKE button must be enabled at the entry point")
	assert_false(instance.verb_bar_view.get_button("STRIDE").disabled, "the rendered STRIDE button must be enabled at the entry point")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (exit_point, half 1) -- a player Strike spends the turn's one
# action, greys Strike/Stride on the real verb bar, and a second same-turn
# action attempt is rejected with ACTION_ALREADY_USED.
# ══════════════════════════════════════════════════════════════════════════

func test_criterion2_player_strike_spends_the_one_action_and_greys_strike_and_stride_on_the_real_verb_bar() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available("STRIKE"), "fixture assumption: STRIKE is available at seed=42 before any spend")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor carries a live domain ActionEconomy")
	assert_true(action_economy.can_take_action(), "fixture assumption: can_take_action() is true before any spend")

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	assert_true(instance.selection_overlay.is_active(), "STRIKE must enter Layer 2 (SelectionOverlay active)")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "entering STRIKE's Layer 2 selection must surface at least one in-reach target")
	var target_id: String = target_ids[0]

	_resolve_strike_via_full_click_flow(instance, target_id)

	assert_false(action_economy.can_take_action(), "ActionEconomy.spend_action() must succeed and can_take_action() must report false immediately after the real Strike resolves")

	assert_false(instance._verb_registry.is_available("STRIKE"), "STRIKE must become unavailable immediately after this turn's one action has been spent")
	assert_false(instance._verb_registry.is_available("STRIDE"), "STRIDE must become unavailable immediately after this turn's one action has been spent")
	assert_true(instance.verb_bar_view.get_button("STRIKE").disabled, "the real, rendered STRIKE button must be visibly greyed (disabled) after the Strike resolves")
	assert_true(instance.verb_bar_view.get_button("STRIDE").disabled, "the real, rendered STRIDE button must be visibly greyed (disabled) after the Strike resolves")

	# A second same-turn action attempt against the SAME live ActionEconomy
	# `_verb_registry`'s closures already read from must be rejected with the
	# domain gate's documented ACTION_ALREADY_USED reason code (core/rules/
	# action_economy.gd's spend_action() contract), checked BEFORE any further
	# budget mutation.
	var remaining_before_rejected_attempt: int = action_economy.get_remaining()
	var second_attempt: Dictionary = action_economy.spend_action({})
	assert_false(second_attempt.get("success", true), "a second same-turn spend_action() call must be rejected")
	assert_eq(second_attempt.get("reason", ""), "ACTION_ALREADY_USED", "a second same-turn action attempt must be rejected with reason ACTION_ALREADY_USED")
	assert_eq(
		action_economy.get_remaining(), remaining_before_rejected_attempt,
		"a rejected ACTION_ALREADY_USED attempt must never decrement the shared per-round action budget"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (exit_point, half 2) -- the AC a Strike resolves against the
# Skeleton with is sourced from data/enemies/skeleton.tres via EnemyResource,
# never a hard-coded constant.
# ══════════════════════════════════════════════════════════════════════════

func test_criterion2_strike_against_the_skeleton_uses_the_ac_sourced_from_its_own_enemy_resource() -> void:
	# Load the SAME .tres fixture MainScene.gd's own _build_enemy_combatant()
	# reads at boot, and read its `ac` field fresh -- never assert against a
	# bare literal `14` alone, so this test fails loudly if the resource's
	# authored value ever changes instead of silently passing against a
	# stale hard-coded expectation.
	var skeleton_resource = ResourceLoader.load(SKELETON_TRES_PATH)
	assert_not_null(skeleton_resource, "fixture assumption: skeleton.tres must load as an EnemyResource")
	var expected_ac: int = skeleton_resource.ac
	assert_eq(expected_ac, 14, "fixture assumption: skeleton.tres' own authored ac field is 14")

	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: the Skeleton is in reach at the entry point")
	var target_id: String = target_ids[0]

	_resolve_strike_via_full_click_flow(instance, target_id)

	var attack_event = _last_attack_event_by(instance, "Titus")
	assert_not_null(attack_event, "resolving the player's Strike must emit a real AttackEvent via the SAME EventSinkPort broadcast every other round event uses")
	assert_eq(
		attack_event.defense_value, expected_ac,
		"the Strike must roll against the Skeleton's AC as read DIRECTLY off skeleton.tres via EnemyResource "
		+ "(MainScene.gd's _build_enemy_combatant(), FEAT-008) -- not a hard-coded fallback constant"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 -- the cursor advances through a real enemy activation and back
# -> Strike/Stride re-enable for the returning current actor.
# ══════════════════════════════════════════════════════════════════════════

func test_criterion3_cursor_advances_through_an_enemy_turn_and_back_reenabling_strike_and_stride() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_false(instance.round_session.current_actor().get("_is_enemy", true), "fixture assumption: Titus acts first at seed=42")
	assert_true(instance._verb_registry.is_available("STRIKE"), "fixture assumption: STRIKE is available at the entry point")
	assert_true(instance._verb_registry.is_available("STRIDE"), "fixture assumption: STRIDE is available at the entry point")

	# End the player's turn WITHOUT acting (US-010: End Turn is ALWAYS
	# available) -- the SAME real $EndTurnControl.press() the verb bar's
	# END_TURN entry itself delegates to. MainScene's own turn_ended wiring
	# re-invokes the real $TurnController, which auto-resolves the Skeleton's
	# turn via RoundSession.advance_ai_turn() (it starts adjacent to Titus, so
	# it Strikes immediately) before the cursor returns to Titus for his
	# SECOND turn this round.
	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "ending the player's turn (no action taken) must succeed")

	assert_false(instance.round_session.is_round_over(), "fixture assumption: neither combatant is defeated by this exchange -- the round must still be ongoing")
	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"the cursor must have advanced through the Skeleton's own turn and landed back on the living player combatant (Titus)"
	)

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the returning current actor carries a live domain ActionEconomy")
	assert_true(
		action_economy.can_take_action(),
		"the returning actor's NEW turn must have had start_of_turn() invoked by the SAME single cursor-advance call site (RoundSession._advance_cursor(), FEAT-004) -- can_take_action() must report true again"
	)

	assert_true(instance._verb_registry.is_available("STRIKE"), "STRIKE must re-enable for the returning current actor's fresh turn")
	assert_true(instance._verb_registry.is_available("STRIDE"), "STRIDE must re-enable for the returning current actor's fresh turn")
	assert_false(instance.verb_bar_view.get_button("STRIKE").disabled, "the real, rendered STRIKE button must be visibly re-enabled for the returning current actor")
	assert_false(instance.verb_bar_view.get_button("STRIDE").disabled, "the real, rendered STRIDE button must be visibly re-enabled for the returning current actor")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 -- the AI-controlled Skeleton takes EXACTLY ONE action per
# turn (Strike if in reach, else Stride -- never both), driven through the
# real RoundSession.advance_ai_turn() seam.
# ══════════════════════════════════════════════════════════════════════════

func test_criterion4_ai_controlled_skeleton_strikes_immediately_with_exactly_one_action_when_already_in_reach() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	# End the player's turn without acting so the cursor lands on the
	# Skeleton, which starts adjacent to Titus per the prologue fixture --
	# the "Strike if in reach" branch.
	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "ending the player's turn (no action taken) must succeed")

	var attack_event = _last_attack_event_by(instance, "Skeleton")
	assert_not_null(attack_event, "the already-in-reach Skeleton must Strike on its own turn -- no AttackEvent authored by the Skeleton was found")

	# Exactly one action was spent this turn -- never a composite
	# Stride-then-Strike (FEAT-007 removed that composite path).
	assert_eq(
		attack_event.actor_updated_action_budget.get("remaining", -1), ActionEconomyClass.MAX_BUDGET - 1,
		"the Skeleton's own ActionEconomy must reflect EXACTLY one action spent this turn (the Strike itself), never two"
	)


func test_criterion4_ai_controlled_skeleton_strides_toward_target_and_does_not_strike_the_same_turn_when_out_of_reach() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter has exactly one enemy")
	var enemy: Dictionary = instance._enemies[0]
	var enemy_id: String = enemy.get("combatant_id", "")
	assert_ne(enemy_id, "", "fixture assumption: the enemy combatant carries a non-empty combatant_id")

	var player: Dictionary = instance._party[0]
	var player_hex = player.get("hex_coord")
	assert_not_null(player_hex, "fixture assumption: the player combatant carries positional hex_coord data")

	# Relocate the Skeleton out of melee reach, but within a single Stride's
	# reach (Movement.DEFAULT_SPEED == 4 hexes) -- mirrors the SAME
	# "hex_coord" Dictionary-key mutation point core/rules/movement.gd's own
	# _set_hex() writes, then resyncs the on-screen token via the SAME
	# hex_grid_view.move_token() call the AI-Stride path itself invokes, so
	# domain state and the rendered token agree before the real AI turn below.
	var far_hex := HexCoordClass.new(player_hex.q + 3, player_hex.r)
	enemy["hex_coord"] = far_hex
	instance.hex_grid_view.move_token(enemy_id, far_hex)

	var attack_events_before: int = instance.event_sink.log.filter(
		func(e): return e is RoundEventsClass.AttackEvent and e.attacker_name == "Skeleton"
	).size()

	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "ending the player's turn (no action taken) must succeed")

	# The Skeleton must have Strode toward Titus (its hex position changed)...
	assert_false(enemy.get("hex_coord").equals(far_hex), "the out-of-reach Skeleton must Stride toward Titus rather than standing still")

	# ...and issued ZERO Strike in the SAME turn as the Stride (FEAT-007: one
	# action per decision, never a composite).
	var attack_events_after: int = instance.event_sink.log.filter(
		func(e): return e is RoundEventsClass.AttackEvent and e.attacker_name == "Skeleton"
	).size()
	assert_eq(attack_events_after, attack_events_before, "no Strike may resolve in the same turn as the Stride -- the AI issues exactly ONE action per decision")

	var enemy_action_economy = null
	for entry in instance.round_session._entries:
		if entry.get("combatant", {}).get("combatant_id", "") == enemy_id:
			enemy_action_economy = entry.get("action_economy")
	assert_not_null(enemy_action_economy, "fixture assumption: the Skeleton carries a live domain ActionEconomy")
	assert_false(enemy_action_economy.can_take_movement_action(), "the Skeleton's Stride must trip the per-turn Movement-trait gate")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 -- a headless MainScene boot completes without error with the
# full wiring (verb-bar callbacks, RoundSession, ActionEconomy, AI,
# EnemyResource) active. In-process complement to tests/integration/
# test_headless_boot.gd's exhaustive real-subprocess console-output gate --
# mirrors this codebase's established "every composition-root field resolves
# non-null after a real frame" proxy (tests/infrastructure/
# test_mainscene_headless_boot.gd, tests/gut/test_smoke_boot.gd) rather than
# re-deriving a second subprocess-spawning mechanism.
# ══════════════════════════════════════════════════════════════════════════

func test_criterion5_headless_mainscene_boot_completes_without_error_with_the_full_steel_thread_wiring_active() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return

	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate with no manual setup")
	if instance == null:
		return

	instance.seed_override = SEED
	add_child_autofree(instance)
	await get_tree().process_frame

	# RoundSession / ActionEconomy.
	assert_not_null(instance.round_session, "MainScene.round_session must be a real RoundSession after first frame")
	assert_false(instance.round_session.is_round_over(), "the freshly-begun RoundSession must not already be over with no player input")
	assert_not_null(instance.round_session.current_action_economy(), "the active actor must carry a live domain ActionEconomy after boot")

	# Verb-bar callbacks (the entry_point's Layer 1 surface).
	assert_not_null(instance.verb_bar_view, "MainScene.verb_bar_view must be wired to a real $VerbBarView node")
	assert_not_null(instance._verb_registry, "MainScene._verb_registry must be wired -- Strike/Step/Stride/End Turn are driven solely through it")
	assert_gt(instance.verb_bar_view.get_button_count(), 0, "the verb bar must render at least one verb button after boot")
	assert_true(typeof(instance._verb_registry.is_available("STRIKE")) == TYPE_BOOL, "is_available('STRIKE') must resolve to a bool without throwing")
	assert_true(typeof(instance._verb_registry.is_available("STRIDE")) == TYPE_BOOL, "is_available('STRIDE') must resolve to a bool without throwing")

	# AI / EnemyResource-sourced defenses.
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter has exactly one EnemyResource-backed enemy")
	assert_eq(instance._enemies[0].get("ac", -1), 14, "the booted Skeleton combatant's AC must already be sourced from its EnemyResource (skeleton.tres) at boot, not a hard-coded constant")

	# Driving one full turn cycle (through the real AI wiring) must not throw.
	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(typeof(end_turn_result) == TYPE_DICTIONARY, "driving one full player-end-turn -> AI-turn cycle through the real composition root must not throw")
