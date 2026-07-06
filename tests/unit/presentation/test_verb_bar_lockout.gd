extends GutTest
## tests/unit/presentation/test_verb_bar_lockout.gd — FEAT-002 (US-002,
## FR-003, FR-004; Iteration F, P0-1).
##
## GUT test suite proving `_verb_bar_step_availability()` and
## `_verb_bar_stride_availability()` (MainScene.gd) additionally query the
## active actor's core/rules/action_economy.gd ActionEconomy.
## can_take_movement_action() (read-only, ADR-003) -- disabling BOTH
## movement verbs once either Step or Stride has been taken this turn (the
## Movement-trait lockout core/rules/action_economy.gd/movement.gd already
## enforce at the domain level, per FEAT-001).
##
## This suite boots the REAL, shipped res://MainScene.tscn composition root
## headless (mirroring tests/integration/test_movement_affordance_
## integration.gd's / tests/gut/test_status_bar_verb_flow_regression.gd's
## `_boot_main_scene_with_seed()` convention), pinned to the prologue
## fixture's known-good seed=42, and drives Step/Stride through the REAL
## `_verb_registry`.execute() -- the SOLE Step/Stride entry point (FEAT-007)
## -- so this proves the verb bar's gating reflects the live domain
## ActionEconomy, never a re-derived/forked notion of the lockout.
##
## test_criteria satisfied:
##   1. test_step_is_disabled_after_a_stride_while_hexes_and_action_points_remain()
##   2. test_step_is_disabled_after_a_step_self_lockout()
##   3. test_stride_is_disabled_after_a_step()

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
# Criterion 1 — Step is disabled after a Stride, while hexes and action
# points otherwise remain available (proving the lockout, not a starved
# hex-set or an exhausted action budget, is what disables STEP).
# ══════════════════════════════════════════════════════════════════════════

func test_step_is_disabled_after_a_stride_while_hexes_and_action_points_remain() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available("STEP"), "fixture assumption: STEP is available at seed=42 before any Movement-trait action")
	assert_true(instance._verb_registry.is_available("STRIDE"), "fixture assumption: STRIDE is available at seed=42 before any Movement-trait action")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor carries a live domain ActionEconomy")
	var remaining_before: int = action_economy.get_remaining()

	var stride_hexes: Array = instance.movement_input_controller.get_selectable_stride_hexes()
	assert_true(stride_hexes.size() > 0, "fixture assumption: at least one legal Stride destination exists")
	var destination = stride_hexes[0]

	var stride_result: Dictionary = instance._verb_registry.execute("STRIDE", destination)
	assert_true(stride_result.get("ok", false), "fixture assumption: the Stride itself must succeed")

	assert_false(
		action_economy.can_take_movement_action(),
		"fixture assumption: a resolved Stride must trip the domain Movement-trait gate"
	)
	assert_true(
		action_economy.get_remaining() < remaining_before,
		"fixture assumption: a Stride must spend an action (so the OLD remaining-count check alone would still have allowed a subsequent Stride)"
	)
	assert_true(
		action_economy.get_remaining() > 0,
		"fixture assumption: an action point must still remain -- STEP's unavailability below must come from the lockout, not a starved budget"
	)
	assert_true(
		instance.movement_input_controller.get_selectable_step_hexes().size() > 0,
		"fixture assumption: a legal Step hex still exists from the actor's NEW post-Stride position -- STEP's unavailability below must come "
		+ "from the lockout, not an empty selectable-hex set"
	)

	assert_false(
		instance._verb_registry.is_available("STEP"),
		"STEP must be disabled once a Stride has been taken this turn, even though hexes and action points remain"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — Step is disabled after a Step (self-lockout: a Movement-
# trait action locks out FURTHER Movement-trait actions, including itself).
# ══════════════════════════════════════════════════════════════════════════

func test_step_is_disabled_after_a_step_self_lockout() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available("STEP"), "fixture assumption: STEP is available at seed=42 before any Movement-trait action")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor carries a live domain ActionEconomy")

	var step_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	assert_true(step_hexes.size() > 0, "fixture assumption: at least one legal Step destination exists")
	var destination = step_hexes[0]

	var step_result: Dictionary = instance._verb_registry.execute("STEP", destination)
	assert_true(step_result.get("ok", false), "fixture assumption: the Step itself must succeed")

	assert_false(
		action_economy.can_take_movement_action(),
		"fixture assumption: a resolved Step must trip the domain Movement-trait gate (Step is FREE but still counts as this turn's Movement action)"
	)

	assert_false(
		instance._verb_registry.is_available("STEP"),
		"STEP must be disabled after a Step this turn -- a Movement-trait action locks out FURTHER Movement-trait actions, including a second Step"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — Stride is disabled after a Step.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_is_disabled_after_a_step() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available("STEP"), "fixture assumption: STEP is available at seed=42 before any Movement-trait action")
	assert_true(instance._verb_registry.is_available("STRIDE"), "fixture assumption: STRIDE is available at seed=42 before any Movement-trait action")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor carries a live domain ActionEconomy")

	var step_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	assert_true(step_hexes.size() > 0, "fixture assumption: at least one legal Step destination exists")
	var destination = step_hexes[0]

	var step_result: Dictionary = instance._verb_registry.execute("STEP", destination)
	assert_true(step_result.get("ok", false), "fixture assumption: the Step itself must succeed")

	assert_false(
		action_economy.can_take_movement_action(),
		"fixture assumption: a resolved Step must trip the domain Movement-trait gate"
	)

	assert_false(
		instance._verb_registry.is_available("STRIDE"),
		"STRIDE must be disabled after a Step this turn -- both movement verbs share the SAME Movement-trait gate"
	)


# ══════════════════════════════════════════════════════════════════════════
# Regression guard — Strike availability is completely unaffected by the
# Movement-trait lockout (mirrors core/rules/test_movement_lockout.gd's own
# domain-level regression pin, re-affirmed here at the verb-bar level).
# ══════════════════════════════════════════════════════════════════════════

func test_strike_availability_is_unaffected_by_the_movement_lockout() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var strike_available_before: bool = instance._verb_registry.is_available("STRIKE")

	var step_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	assert_true(step_hexes.size() > 0, "fixture assumption: at least one legal Step destination exists")
	instance._verb_registry.execute("STEP", step_hexes[0])

	var action_economy = instance.round_session.current_action_economy()
	assert_false(action_economy.can_take_movement_action(), "fixture assumption: the Step must have tripped the Movement gate")

	assert_eq(
		instance._verb_registry.is_available("STRIKE"), strike_available_before,
		"STRIKE availability must be completely unaffected by the Movement-trait lockout -- Movement and Strike are separate traits"
	)
