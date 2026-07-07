extends GutTest
## tests/unit/test_verb_bar_availability.gd — FEAT-009 (US-009 / FR-004).
##
## GUT test suite proving MainScene.gd's `_verb_bar_strike_availability()`
## and `_verb_bar_stride_availability()` now gate on the active actor's live
## core/rules/action_economy.gd ActionEconomy.can_take_action() (FEAT-005)
## rather than the coarser "an action point remains" (get_remaining() > 0)
## check they used to perform — the fix that produces the steel thread's
## user-visible exit criterion: Strike/Stride visibly grey out the instant
## this turn's ONE action has been spent, even though the shared 7-action
## round budget may still have several points left. Step's own availability
## (`_verb_bar_step_availability()`) is left completely untouched by this
## feature — it depends solely on the independent
## ActionEconomy.can_take_movement_action() gate.
##
## This suite boots the REAL, shipped res://MainScene.tscn composition root
## headless (mirroring tests/unit/presentation/test_verb_bar_lockout.gd's/
## tests/gut/test_status_bar_verb_flow_regression.gd's
## `_boot_main_scene_with_seed()` convention), pinned to the prologue
## fixture's known-good seed=42, and drives the SAME live
## `round_session.current_action_economy()` object `_verb_registry`'s
## closures already read from — never a re-derived/forked notion of the
## gate — so this proves the verb bar's gating reflects the live domain
## ActionEconomy, exactly as test_verb_bar_lockout.gd does for the
## Movement-trait gate.
##
## test_criteria satisfied:
##   1. Strike and Stride buttons are disabled (grey) immediately after
##      can_take_action() becomes false following a spend.
##   2. Step button availability is unaffected by can_take_action() and
##      depends solely on the movement-used gate.
##   3. On the actor's next turn (after start_of_turn()), Strike and Stride
##      buttons re-enable.
##   4. Verb-bar callback wiring does not throw when invoked for both player
##      and AI-controlled actor turns.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## The pinned deterministic-test fixture seed (matches
## data/encounters/prologue_encounter.tres' own `seed` field, 42), mirroring
## this codebase's established integration/E2E test convention.
const SEED: int = 42


## _boot_main_scene_with_seed(seed_value) -> Node -- instantiates the REAL
## res://MainScene.tscn composition root, pinned to a deterministic seed.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — Strike and Stride are disabled (grey) immediately after
# can_take_action() becomes false following a spend, even though the shared
# round budget still has action points left (proving the fix reads
# can_take_action(), not the old get_remaining() > 0 proxy).
# ══════════════════════════════════════════════════════════════════════════

func test_strike_and_stride_disabled_immediately_after_a_spend_via_can_take_action_gate() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available("STRIKE"), "fixture assumption: STRIKE is available at seed=42 before any spend")
	assert_true(instance._verb_registry.is_available("STRIDE"), "fixture assumption: STRIDE is available at seed=42 before any spend")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor carries a live domain ActionEconomy")
	assert_true(action_economy.can_take_action(), "fixture assumption: can_take_action() is true before any spend")

	var remaining_before: int = action_economy.get_remaining()

	# Spend this turn's one action directly against the SAME live
	# ActionEconomy `_verb_registry`'s closures read from (no combat RNG
	# involved, so no risk of ending the encounter mid-test).
	var spend_result: Dictionary = action_economy.spend_action({})
	assert_true(spend_result.get("success", false), "fixture assumption: spend_action() must succeed")

	assert_false(action_economy.can_take_action(), "sanity check: can_take_action() must be false immediately after the spend")
	assert_true(
		action_economy.get_remaining() > 0,
		"fixture assumption: the shared round budget must still have action points left -- Strike/Stride's unavailability below must come from "
		+ "can_take_action(), not a starved budget (the OLD get_remaining() > 0 check would have still reported both available here)"
	)
	assert_eq(action_economy.get_remaining(), remaining_before - 1, "sanity check: exactly one action point was spent")

	assert_false(
		instance._verb_registry.is_available("STRIKE"),
		"STRIKE must be disabled immediately after can_take_action() becomes false following a spend"
	)
	assert_false(
		instance._verb_registry.is_available("STRIDE"),
		"STRIDE must be disabled immediately after can_take_action() becomes false following a spend"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — Step's availability is unaffected by can_take_action() and
# depends solely on the independent movement-used gate.
# ══════════════════════════════════════════════════════════════════════════

func test_step_availability_is_unaffected_by_can_take_action_and_depends_solely_on_movement_gate() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available("STEP"), "fixture assumption: STEP is available at seed=42 before any spend")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor carries a live domain ActionEconomy")

	var spend_result: Dictionary = action_economy.spend_action({})
	assert_true(spend_result.get("success", false), "fixture assumption: spend_action() must succeed")
	assert_false(action_economy.can_take_action(), "sanity check: can_take_action() must be false immediately after the spend")
	assert_true(
		action_economy.can_take_movement_action(),
		"sanity check: a non-Movement spend_action() call must NOT trip the independent movement-used gate"
	)

	assert_true(
		instance._verb_registry.is_available("STEP"),
		"STEP must remain available even though can_take_action() is now false -- it is gated solely by the movement-used gate"
	)

	# Now trip the movement-used gate directly (independent of can_take_action()
	# — e.g. as a prior Step/Stride this turn would) and confirm STEP responds
	# to THAT gate, pinning that it depends "solely" on it.
	action_economy.mark_movement_used()
	assert_false(
		instance._verb_registry.is_available("STEP"),
		"STEP must become unavailable once the movement-used gate trips, regardless of can_take_action()'s value"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — Strike and Stride re-enable on the actor's next turn, once
# start_of_turn() clears the per-turn action-used gate.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_and_stride_reenable_after_the_actors_next_start_of_turn() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor carries a live domain ActionEconomy")

	var spend_result: Dictionary = action_economy.spend_action({})
	assert_true(spend_result.get("success", false), "fixture assumption: spend_action() must succeed")

	assert_false(instance._verb_registry.is_available("STRIKE"), "sanity check: STRIKE must be disabled right after the spend")
	assert_false(instance._verb_registry.is_available("STRIDE"), "sanity check: STRIDE must be disabled right after the spend")

	# The actor's next turn: start_of_turn() clears the per-turn action-used
	# flag WITHOUT refilling/touching the round budget (core/rules/
	# action_economy.gd's documented contract) -- the SAME call
	# RoundSession's cursor-advance seam invokes for every actor's turn.
	action_economy.start_of_turn()

	assert_true(action_economy.can_take_action(), "sanity check: can_take_action() must be true again after start_of_turn()")
	assert_true(
		instance._verb_registry.is_available("STRIKE"),
		"STRIKE must re-enable on the actor's next turn, after start_of_turn() clears the action-used gate"
	)
	assert_true(
		instance._verb_registry.is_available("STRIDE"),
		"STRIDE must re-enable on the actor's next turn, after start_of_turn() clears the action-used gate"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — the verb-bar availability callback wiring does not throw
# when invoked for both a player-controlled and an AI-controlled actor's
# turn.
# ══════════════════════════════════════════════════════════════════════════

func test_verb_bar_availability_does_not_throw_while_the_player_is_the_current_actor() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_false(instance.round_session.current_actor().get("_is_enemy", false), "fixture assumption: the player acts first at seed=42")

	var strike_available = instance._verb_registry.is_available("STRIKE")
	var stride_available = instance._verb_registry.is_available("STRIDE")
	var step_available = instance._verb_registry.is_available("STEP")

	assert_true(typeof(strike_available) == TYPE_BOOL, "is_available('STRIKE') must return a bool without throwing for a player-controlled turn")
	assert_true(typeof(stride_available) == TYPE_BOOL, "is_available('STRIDE') must return a bool without throwing for a player-controlled turn")
	assert_true(typeof(step_available) == TYPE_BOOL, "is_available('STEP') must return a bool without throwing for a player-controlled turn")


func test_verb_bar_availability_does_not_throw_while_the_enemy_is_the_current_actor() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_false(instance.round_session.current_actor().get("_is_enemy", false), "fixture assumption: the player acts first at seed=42")

	# Advance the cursor directly (bypassing EndTurnControl's own auto-drive
	# wiring) so the Enemy becomes current_actor() while the availability
	# closures are queried, without immediately auto-resolving its turn.
	var end_turn_result: Dictionary = instance.round_session.end_current_turn()
	assert_true(end_turn_result.get("ok", false), "fixture assumption: end_current_turn() must succeed")
	assert_true(instance.round_session.current_actor().get("_is_enemy", false), "fixture assumption: the cursor now sits on the Enemy")

	var strike_available = instance._verb_registry.is_available("STRIKE")
	var stride_available = instance._verb_registry.is_available("STRIDE")
	var step_available = instance._verb_registry.is_available("STEP")

	assert_true(typeof(strike_available) == TYPE_BOOL, "is_available('STRIKE') must return a bool without throwing while an Enemy is the current actor")
	assert_true(typeof(stride_available) == TYPE_BOOL, "is_available('STRIDE') must return a bool without throwing while an Enemy is the current actor")
	assert_true(typeof(step_available) == TYPE_BOOL, "is_available('STEP') must return a bool without throwing while an Enemy is the current actor")


## Exercises presentation/turn_controller.gd's FEAT-009 VerbBarView refresh
## wiring end to end through the REAL composition root: pressing End Turn
## hands the cursor to the (single) Enemy and re-invokes
## TurnController.set_session() (MainScene.gd's
## _on_end_turn_control_turn_ended()), which refreshes $VerbBarView while the
## Enemy is still the current actor AND again once the auto-drive settles —
## neither refresh may throw, whether it lands on a player or an
## AI-controlled turn.
func test_turn_controller_refreshes_verb_bar_across_the_ai_drive_without_throwing() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var press_result: Dictionary = instance.end_turn_control.press()
	assert_true(press_result.get("ok", false), "fixture assumption: End Turn must succeed")

	assert_false(instance.verb_bar_view.is_locked(), "sanity check: a normal turn cycle must not sticky-lock the verb bar")

	# The wiring survived the full drive without throwing -- confirm the
	# availability callbacks still resolve cleanly for whoever now holds the
	# cursor (the round may have ended, or returned to the player).
	var strike_available = instance._verb_registry.is_available("STRIKE")
	assert_true(typeof(strike_available) == TYPE_BOOL, "is_available('STRIKE') must return a bool without throwing after the AI-turn auto-drive")
