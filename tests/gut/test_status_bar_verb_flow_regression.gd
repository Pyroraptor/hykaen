extends GutTest
## tests/gut/test_status_bar_verb_flow_regression.gd — FEAT-178
## (US-014 / FR-014).
##
## Iteration D introduced the status bar's Actions/Spent readout
## (presentation/status_panel_view.gd, FEAT-008/FEAT-009) and pinned that a
## resolved Strike decrements the acting combatant's displayed
## action_budget_remaining/spent (tests/integration/
## test_status_bar_refresh_integration.gd, tests/gut/
## test_strike_layer2_integration.gd). Iteration E then routed Strike/Step/
## Stride through the new two-layer verb flow (Layer 1 VerbBarView ->
## Layer 2 SelectionOverlay -> `_verb_registry`.execute()) -- but ONLY
## Strike's post-resolution status-bar push survived that migration, since
## it rides an AttackEvent (StatusPanelView.on_attack_event() ->
## update_action_budget(), see status_panel_view.gd's file-level doc). A
## Stride spends an action too (core/rules/movement.gd Movement.stride())
## but emits no AttackEvent at all, so nothing pushed its post-resolution
## action-budget snapshot to the status bar -- a real regression the
## exit-criterion "action/status counters update correctly" catches.
##
## This suite is this feature's dedicated, self-contained regression/
## coverage suite, exercising the REAL, unmodified res://MainScene.tscn
## composition root headless (mirroring every other integration/E2E suite's
## `_boot_main_scene_with_seed()` convention) -- no mocked/stubbed
## Application-layer port, no test-local `_verb_registry`.
##
## test_criteria satisfied:
##   1. test_iteration_d_strike_status_bar_decrement_behavior_remains_green()
##      -- the Iteration D regression pin, re-affirmed through the NEW
##      two-layer verb flow (VerbBarView.press("STRIKE") ->
##      `_verb_registry`.execute()), not a legacy call path.
##   2. test_stride_resolution_decrements_action_budget_and_updates_spent_on_status_bar()
##      -- the FEAT-178 fix: a Stride executed through the two-layer flow
##      now pushes its post-resolution action-budget snapshot to the real
##      StatusPanelView, exactly like Strike already does.
##   3. test_step_resolution_leaves_action_budget_and_spent_unchanged_on_status_bar()
##      -- a Step (free, no action-economy cost, core/rules/movement.gd's
##      file-level doc) must never move the displayed counters at all.
##   4. (whole-suite regression) -- enforced by scripts/test_command.sh, not
##      this file.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## The pinned deterministic-test fixture seed (matches
## data/encounters/prologue_encounter.tres' own `seed` field, 42),
## mirroring every other integration/E2E suite's established convention
## (tests/integration/test_status_bar_refresh_integration.gd,
## tests/gut/test_strike_layer2_integration.gd,
## tests/e2e/test_full_steel_thread_e2e.gd).
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
# Criterion 1 (regression) — the Iteration D "a resolved Strike decrements
# the status bar's Actions/Spent readout" behavior remains green when driven
# through the NEW two-layer verb flow (VerbBarView.press("STRIKE") ->
# `_verb_registry`.execute()), not the legacy call path Iteration D itself
# used.
# ══════════════════════════════════════════════════════════════════════════

func test_iteration_d_strike_status_bar_decrement_behavior_remains_green() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().display_id()
	assert_ne(actor_id, "", "fixture assumption: the active actor carries a non-empty combatant_id")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor has a live domain ActionEconomy")

	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_true(before_remaining > 0, "sanity check: the acting combatant starts with a positive action budget")

	assert_true(
		instance._verb_registry.is_available("STRIKE"),
		"fixture assumption: the active actor has at least one in-reach target at seed=42"
	)
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: at least one in-reach target exists")

	var strike_result = instance._verb_registry.execute("STRIKE", target_ids[0])
	assert_true(strike_result.get("resolved", false), "the real resolve_action_use_case must resolve the player's Strike")

	var after_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(
		after_remaining, before_remaining - 1,
		"StatusPanelView.action_budget_remaining for the acting combatant must decrease by EXACTLY 1 after a Strike resolved through the two-layer verb flow"
	)
	assert_eq(
		instance.status_panel_view.get_status(actor_id).get("spent"), action_economy.is_spent(),
		"StatusPanelView's displayed Spent value must track the domain ActionEconomy.is_spent() value after a Strike resolved through the two-layer verb flow"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (FEAT-178 fix) — a Stride resolved through the two-layer verb
# flow (VerbBarView.press("STRIDE") -> `_verb_registry`.execute()) pushes
# its post-resolution action-budget snapshot to the real StatusPanelView,
# exactly like Strike already does -- even though a Stride emits no
# AttackEvent to ride along on.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_resolution_decrements_action_budget_and_updates_spent_on_status_bar() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().display_id()
	assert_ne(actor_id, "", "fixture assumption: the active actor carries a non-empty combatant_id")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor has a live domain ActionEconomy")

	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_true(before_remaining > 0, "sanity check: the acting combatant starts with a positive action budget")
	assert_false(
		instance.status_panel_view.get_status(actor_id).get("spent", true),
		"sanity check: the acting combatant does not start Spent"
	)

	assert_true(
		instance._verb_registry.is_available("STRIDE"),
		"fixture assumption: the active actor has at least one legal Stride destination at seed=42"
	)
	var selection: Dictionary = instance.verb_bar_view.press("STRIDE")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "fixture assumption: at least one legal Stride destination exists")

	var destination = candidate_hexes[0]
	var stride_result: Dictionary = instance._verb_registry.execute("STRIDE", destination)
	assert_true(stride_result.get("ok", false), "the real Movement.stride() must resolve the player's Stride")

	var after_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(
		after_remaining, before_remaining - 1,
		"StatusPanelView.action_budget_remaining for the acting combatant must decrease by EXACTLY 1 after a Stride resolved through the two-layer verb flow"
	)
	assert_eq(
		instance.status_panel_view.get_status(actor_id).get("spent"), action_economy.is_spent(),
		"StatusPanelView's displayed Spent value must track the domain ActionEconomy.is_spent() value after a Stride resolved through the two-layer verb flow"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — a Step (free, no action-economy cost) leaves the status
# bar's Actions/Spent readout completely unchanged.
# ══════════════════════════════════════════════════════════════════════════

func test_step_resolution_leaves_action_budget_and_spent_unchanged_on_status_bar() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().display_id()
	assert_ne(actor_id, "", "fixture assumption: the active actor carries a non-empty combatant_id")

	var before_status: Dictionary = instance.status_panel_view.get_status(actor_id)
	var before_remaining: int = before_status.get("action_budget_remaining", -1)
	var before_spent = before_status.get("spent")

	assert_true(
		instance._verb_registry.is_available("STEP"),
		"fixture assumption: the active actor has at least one legal Step destination at seed=42"
	)
	var selection: Dictionary = instance.verb_bar_view.press("STEP")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "fixture assumption: at least one legal Step destination exists")

	var destination = candidate_hexes[0]
	var step_result: Dictionary = instance._verb_registry.execute("STEP", destination)
	assert_true(step_result.get("ok", false), "the real Movement.step() must resolve the player's Step")

	var after_status: Dictionary = instance.status_panel_view.get_status(actor_id)
	assert_eq(
		after_status.get("action_budget_remaining", -1), before_remaining,
		"a Step must never change the acting combatant's displayed action_budget_remaining -- it is free"
	)
	assert_eq(
		after_status.get("spent"), before_spent,
		"a Step must never change the acting combatant's displayed Spent value -- it is free"
	)
