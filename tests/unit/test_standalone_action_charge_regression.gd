extends GutTest
## tests/unit/test_standalone_action_charge_regression.gd — FEAT-008 (US-008;
## FR-007; ADR-003)
##
## Regression complement to tests/unit/test_combine_single_charge.gd: FEAT-008
## threaded an ADDITIVE `no_self_spend_execution` execution-mode flag into
## StrideActionController.execute()/StrikeActionController.execute() (see
## those files' own FEAT-008 doc) so presentation/combine_action_controller.gd
## can suppress each sub-action's own action-economy self-charge while
## resolving them AS Combine sub-actions. This suite proves that flag is
## STRICTLY additive: every PRE-EXISTING standalone (non-Combine) caller,
## which never supplies the flag at all -- mirroring MainScene.gd's own
## `_verb_bar_stride_execute()`/`_verb_bar_strike_execute()` shims,
## `_controller(verb_id).execute(selection)` with no second argument -- still
## self-charges exactly ONE action from the actor's live, shared
## ActionEconomy, exactly as every verb behaved before FEAT-008 ever
## introduced the flag.
##
## Boots the REAL res://MainScene.tscn composition root (mirrors
## tests/unit/test_combine_action_controller_registration.gd's established
## "boot-real, no all-mocked doubles" convention) and drives
## StrideActionController/StrikeActionController DIRECTLY via
## `_controller(verb_id)` -- never through CombineActionController -- so this
## suite is a pure, no-Combine-involved sanity check on the two
## sub-controllers' own default behavior.
##
## test_criteria covered:
##   1. Standalone StrideActionController.execute() (no Combine context)
##      still self-charges exactly one action, as before FEAT-008.
##   2. Standalone StrikeActionController.execute() (no Combine context)
##      still self-charges exactly one action, as before FEAT-008.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/integration/test_combine_execute_stride_then_strike.gd's
## identically-named/valued constant).
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _titus(instance):
	assert_true(instance._party.size() > 0, "fixture assumption: the prologue encounter has at least one party member")
	var titus = instance._party[0]
	assert_eq(titus.name, "Titus", "fixture assumption: the first party member is Titus")
	return titus


func _skeleton(instance):
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — standalone StrideActionController.execute() (default,
# no_self_spend_execution omitted -> false) still self-charges exactly one
# action from the actor's live ActionEconomy, precisely as it did before
# FEAT-008 introduced the flag.
# ══════════════════════════════════════════════════════════════════════════

func test_standalone_stride_execute_still_self_charges_one_action() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)

	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var budget_before: int = economy.get_remaining()
	assert_true(economy.can_take_action(), "fixture assumption: Titus has not yet acted this turn")
	assert_true(economy.can_take_movement_action(), "fixture assumption: Titus has not yet used Movement this turn")

	var stride_controller = instance._controller("STRIDE")
	var selection: Dictionary = stride_controller.enter_selection()
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "fixture assumption: Titus has at least one legal Stride destination")

	# Mirrors MainScene.gd's own `_verb_bar_stride_execute()` shim exactly:
	# `_controller("STRIDE").execute(selection)` -- no second argument, so
	# no_self_spend_execution defaults to false (the pre-FEAT-008 contract).
	var result: Dictionary = await stride_controller.execute(candidate_hexes[0])

	assert_true(result.get("ok", false), "a standalone Stride execute() call against a legal destination must resolve ok=true (result: %s)" % [result])
	assert_eq(
		economy.get_remaining(), budget_before - 1,
		"a standalone (non-Combine) Stride must still self-charge exactly one action from the actor's live ActionEconomy"
	)
	assert_false(economy.can_take_action(), "the actor's one action for the turn must now be spent")
	assert_false(economy.can_take_movement_action(), "the Movement-trait lockout must still trip for a standalone Stride, exactly as before FEAT-008")
	assert_false(economy.is_self_spend_suppressed(), "a standalone Stride execute() call must never leave the no-self-spend suppression flag engaged")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — standalone StrikeActionController.execute() (default,
# no_self_spend_execution omitted -> false) still self-charges exactly one
# action from the actor's live ActionEconomy.
# ══════════════════════════════════════════════════════════════════════════

func test_standalone_strike_execute_still_self_charges_one_action() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)

	var skeleton = _skeleton(instance)

	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var budget_before: int = economy.get_remaining()
	assert_true(economy.can_take_action(), "fixture assumption: Titus has not yet acted this turn")

	var strike_controller = instance._controller("STRIKE")
	assert_true(
		strike_controller.reachable_target_ids().has(skeleton.display_id()),
		"fixture assumption: the Skeleton (authored adjacent to Titus's start hex) is a reachable Strike target"
	)

	# Mirrors MainScene.gd's own `_verb_bar_strike_execute()` shim exactly:
	# `_controller("STRIKE").execute(selection)` -- no second argument, so
	# no_self_spend_execution defaults to false (the pre-FEAT-008 contract).
	# Note: ActionEconomy.spend_action() runs BEFORE hit/miss resolution
	# (core/application/resolve_action_use_case.gd's own
	# _check_preconditions_and_spend()), so the budget spend is deterministic
	# regardless of the Strike's roll outcome -- no AC/seed rigging required.
	var result: Dictionary = await strike_controller.execute(skeleton.display_id())

	assert_true(result.get("resolved", false), "a standalone Strike execute() call against a reachable target must resolve (result: %s)" % [result])
	assert_eq(
		economy.get_remaining(), budget_before - 1,
		"a standalone (non-Combine) Strike must still self-charge exactly one action from the actor's live ActionEconomy"
	)
	assert_false(economy.can_take_action(), "the actor's one action for the turn must now be spent")
	assert_false(economy.is_self_spend_suppressed(), "a standalone Strike execute() call must never leave the no-self-spend suppression flag engaged")
