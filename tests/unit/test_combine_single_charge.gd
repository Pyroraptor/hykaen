extends GutTest
## tests/unit/test_combine_single_charge.gd — FEAT-008 (US-008; FR-007;
## ADR-003)
##
## Iteration N (Combinations): proves the single-charge invariant that closes
## out the steel thread's exit point -- a full Combine (Charge = Stride +
## Strike) `execute()` call must apply exactly ONE action-economy charge
## (actions_spent == 1) and exactly ONE Stamina charge (stamina_spent == 1)
## at the COMBINE level, never two separate STRIDE/STRIKE charges, even
## though both sub-actions' own game effects (the move, the attack) fully
## apply.
##
## Boots the REAL res://MainScene.tscn composition root (mirrors
## tests/integration/test_combine_execute_stride_then_strike.gd's established
## "boot-real" convention) and drives the REAL, live CombineActionController
## -- which in turn orchestrates the REAL, live StrideActionController /
## StrikeActionController (resolved via the SAME `_controller(verb_id)`
## table lookup every other verb uses, never a hard preload/class_name
## reference -- see presentation/combine_action_controller.gd's own FEAT-001/
## FEAT-007/FEAT-008 doc). This is a genuine end-to-end exercise of the
## no-self-spend execution-mode flag threaded through both sub-controllers'
## own execute() signatures (presentation/stride_action_controller.gd /
## presentation/strike_action_controller.gd) and the suppression bracket in
## core/rules/action_economy.gd (begin_self_spend_suppression()/
## end_self_spend_suppression()) -- not a re-implemented mock of the
## contract.
##
## Fixture geometry mirrors tests/integration/test_combine_execute_stride_
## then_strike.gd's own "Skeleton repositioned out of melee reach of Titus's
## START hex, but adjacent to the Stride destination" setup, so the queued
## STRIKE genuinely depends on the queued STRIDE having already committed
## (proving this is a REAL two-effect resolution, not a trivially-skipped
## one). Unlike that file, this suite does NOT need to force a guaranteed
## hit or drain the Skeleton's ActionEconomy to the RESERVE floor:
## ActionEconomy.spend_action() (both the sub-actions' suppressed attempt and
## the Combine's own real charge) is entirely independent of the Strike's
## hit/miss/dodge outcome, so the ledger assertions below hold regardless of
## how the attack roll resolves.
##
## test_criteria covered:
##   1. A full Charge (Stride+Strike) execute() results in exactly one
##      action-economy charge (actions_spent == 1) and exactly one Stamina
##      charge (stamina_spent == 1).
##   2. The ledger never contains two separate STRIDE/STRIKE charges for a
##      single Combine execution -- proven both by the aggregate budget delta
##      (exactly one, not two or three) and by directly driving each
##      sub-controller's own no_self_spend_execution=true path in isolation
##      and observing its self-charge is a genuine no-op.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const HexMathClass                 = preload("res://core/geometry/hex_math.gd")
const MovementClass                = preload("res://core/rules/movement.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/integration/test_combine_execute_stride_then_strike.gd's
## identically-named/valued constant).
const PROLOGUE_SEED: int = 42

## SKELETON_REPOSITIONED_HEX_Q / STRIDE_DESTINATION_HEX_Q — see file-level
## doc's "fixture geometry" paragraph for the arithmetic these encode (mirrors
## tests/integration/test_combine_execute_stride_then_strike.gd's identical
## constants/geometry).
const SKELETON_REPOSITIONED_HEX_Q: int = 3
const STRIDE_DESTINATION_HEX_Q: int = 2


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
# Criterion 1 + 2 (aggregate) — a full Charge (Stride+Strike) execute() call
# applies exactly ONE action-economy charge and exactly ONE Stamina charge at
# the Combine level, never a second/duplicate one.
# ══════════════════════════════════════════════════════════════════════════

func test_full_charge_execute_applies_exactly_one_action_and_one_stamina_charge() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)

	var titus_start_hex = titus.hex_coord
	assert_not_null(titus_start_hex, "fixture assumption: Titus carries a hex_coord before the Combine")
	assert_eq([titus_start_hex.q, titus_start_hex.r], [0, 0], "fixture assumption: Titus starts at (0,0) per the prologue encounter resource")

	# ── Reposition the Skeleton (test-fixture-only, mirrors
	# tests/integration/test_combine_execute_stride_then_strike.gd) out of
	# melee reach of Titus's START hex, but adjacent to the Stride
	# destination -- so the queued STRIKE genuinely depends on the queued
	# STRIDE having already committed. ──────────────────────────────────────
	skeleton.hex_coord = HexCoordClass.new(SKELETON_REPOSITIONED_HEX_Q, 0)

	var stride_destination = HexCoordClass.new(STRIDE_DESTINATION_HEX_Q, 0)
	assert_true(
		HexMathClass.hex_distance(titus_start_hex, stride_destination) <= MovementClass.DEFAULT_SPEED,
		"test setup: the Stride destination must be within Titus's real Speed"
	)
	assert_true(
		HexMathClass.hex_distance(titus_start_hex, skeleton.hex_coord) > 1,
		"test setup: the repositioned Skeleton must be OUT of melee reach of Titus's START hex"
	)
	assert_eq(
		HexMathClass.hex_distance(stride_destination, skeleton.hex_coord), 1,
		"test setup: the repositioned Skeleton must be adjacent to the Stride destination"
	)

	var combine_controller = instance._controller("COMBINE")
	assert_true(combine_controller is CombineActionControllerClass, "_controller(\"COMBINE\") must resolve a real CombineActionController")

	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var budget_before: int = economy.get_remaining()
	assert_true(economy.can_take_action(), "fixture assumption: Titus has not yet acted this turn")
	var stamina_before: int = titus.stamina
	assert_true(stamina_before > 0, "fixture assumption: Titus starts with positive Stamina")

	var selection: Dictionary = {
		"STRIDE": stride_destination,
		"STRIKE": skeleton.display_id(),
	}
	var result: Dictionary = await combine_controller.execute(selection)

	assert_true(result.get("ok", false), "a valid STRIDE+STRIKE Combine must resolve ok=true (result: %s)" % [result])
	assert_eq(result.get("resolved_verb_ids", []), ["STRIDE", "STRIKE"], "the Combine must resolve STRIDE then STRIKE, in that order")
	assert_true(titus.hex_coord.equals(stride_destination), "the Stride sub-action's own game effect (the move) must genuinely apply")

	# ── Criterion 1 — actions_spent == 1: the actor's shared per-round
	# ActionEconomy budget dropped by EXACTLY one, never two (one per
	# sub-action) or three (two sub-actions + the Combine's own charge). ────
	assert_eq(
		economy.get_remaining(), budget_before - 1,
		"a full Combine execute() must spend exactly ONE action from the actor's live ActionEconomy, regardless of how many sub-actions it resolved"
	)
	assert_false(economy.can_take_action(), "the actor's one action for the turn must now be spent, via the Combine's own single charge")
	assert_false(
		economy.is_self_spend_suppressed(),
		"the no-self-spend suppression flag must never leak past the Combine's own execute() call -- it must be false once execute() returns"
	)

	# ── Criterion 1 — stamina_spent == 1. ───────────────────────────────────
	assert_eq(
		titus.stamina, stamina_before - 1,
		"a full Combine execute() must spend exactly ONE Stamina, regardless of how many sub-actions it resolved"
	)

	# ── Criterion 2 — the Skeleton took real Strike damage, proving the
	# STRIKE sub-action's own game effect genuinely applied too (its
	# self-charge was suppressed, not its game effect). ─────────────────────
	assert_true(skeleton.hp_current < skeleton.hp_max, "the Strike sub-action's own game effect (the attack) must genuinely apply even though its self-charge was suppressed")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (mechanism) — directly driving StrideActionController.execute()
# with no_self_spend_execution=true (in isolation, no Combine involved) is a
# genuine self-charge no-op: the actor's own game effect (the move) applies,
# but the shared ActionEconomy budget/Movement-lockout gates are left
# completely untouched, and the suppression flag never leaks past the call.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_with_no_self_spend_execution_true_applies_its_effect_but_never_charges() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var budget_before: int = economy.get_remaining()

	var stride_controller = instance._controller("STRIDE")
	var candidate_hexes: Array = stride_controller.enter_selection().get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "fixture assumption: Titus has at least one legal Stride destination")
	var destination = candidate_hexes[0]

	var result: Dictionary = await stride_controller.execute(destination, true)

	assert_true(result.get("ok", false), "Stride's own game effect (the move) must still apply under no_self_spend_execution=true (result: %s)" % [result])
	assert_true(instance._party[0].hex_coord.equals(destination), "the actor's live position must reflect the move even though the self-charge was suppressed")
	assert_eq(
		economy.get_remaining(), budget_before,
		"no_self_spend_execution=true must leave the shared ActionEconomy budget completely untouched"
	)
	assert_true(economy.can_take_action(), "no_self_spend_execution=true must leave can_take_action() untouched (still available)")
	assert_true(economy.can_take_movement_action(), "no_self_spend_execution=true must leave the Movement-trait lockout untouched")
	assert_false(economy.is_self_spend_suppressed(), "the suppression flag must never leak past a single Stride execute() call -- it must be false once execute() returns")


func test_strike_with_no_self_spend_execution_true_applies_its_effect_but_never_charges() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var skeleton = _skeleton(instance)
	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var budget_before: int = economy.get_remaining()
	var skeleton_hp_before: int = skeleton.hp_current

	var strike_controller = instance._controller("STRIKE")
	assert_true(
		strike_controller.reachable_target_ids().has(skeleton.display_id()),
		"fixture assumption: the Skeleton (authored adjacent to Titus's start hex) is a reachable Strike target"
	)

	var result: Dictionary = await strike_controller.execute(skeleton.display_id(), true)

	assert_true(result.get("resolved", false), "Strike's own game effect (the attack) must still resolve under no_self_spend_execution=true (result: %s)" % [result])
	assert_eq(
		economy.get_remaining(), budget_before,
		"no_self_spend_execution=true must leave the shared ActionEconomy budget completely untouched"
	)
	assert_true(economy.can_take_action(), "no_self_spend_execution=true must leave can_take_action() untouched (still available)")
	assert_false(economy.is_self_spend_suppressed(), "the suppression flag must never leak past a single Strike execute() call -- it must be false once execute() returns")
