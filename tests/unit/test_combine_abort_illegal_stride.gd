extends GutTest
## tests/unit/test_combine_abort_illegal_stride.gd — FEAT-010 (US-010;
## FR-009; ADR-006)
##
## Iteration N (Combinations): proves the abort-safe execution half of
## FEAT-010's invariant — when a Combine's queued STRIDE sub-action targets
## an illegal (no longer/never selectable) destination, the WHOLE Combine
## aborts BEFORE any effect applies and BEFORE any action-economy/Stamina
## charge is ever committed. This closes the "orphaned spend" gap
## FEAT-008's charge-first rework left open (that earlier design committed
## the Combine's own charge BEFORE resolving the sub-action queue, so an
## illegal Stride destination could previously leave a committed charge with
## zero corresponding effect).
##
## Mirrors tests/unit/test_combine_movement_lockout.gd's "real fake session +
## real ActionEconomy, no MainScene.tscn boot required" convention for the
## isolated unit-level suite, plus tests/unit/test_combine_single_charge.gd's
## "boot the REAL res://MainScene.tscn composition root" convention for a
## genuine end-to-end proof against the REAL StrideActionController (not a
## re-implemented mock of its contract).
##
## test_criteria covered:
##   1. Illegal Stride destination: execute() returns ok==false, reason
##      ILLEGAL_SUB_TARGET, actor position unchanged, no ledger entry
##      appended (action-economy budget/can_take_action() untouched),
##      Stamina unchanged.
##   3. State-consistency assertion: for the aborted scenario,
##      count(effects applied) == count(ledger charges committed) == 0 (no
##      orphaned spend) — proven both by the isolated-unit fakes (the Strike
##      sub-controller is never even reached) and by the boot-real suite
##      (Titus's position/HP-affecting Strike never applies, and the
##      Skeleton takes no damage).

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const RoundSessionHolderClass      = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")


## FakeSession — mirrors tests/unit/test_combine_movement_lockout.gd's
## established minimal double satisfying the current_actor()/
## current_actor_entity()/current_action_economy() contract
## presentation/action_controller.gd's base class reads through the
## injected session_holder.
class FakeSession:
	var _actor
	var _economy

	func _init(actor, economy) -> void:
		_actor = actor
		_economy = economy

	func current_actor():
		return {} if _actor == null else {"combatant_id": _actor.combatant_id}

	func current_actor_entity():
		return _actor

	func current_action_economy():
		return _economy


## FakeIllegalStrideController — a minimal stand-in for a real
## StrideActionController whose execute() call rejects an illegal/no-longer-
## selectable destination BEFORE any positional mutation, mirroring
## presentation/movement_input_controller.gd's own real
## ERR_STRIDE_DESTINATION_NOT_SELECTABLE contract exactly (same "ok"/"error"
## keys, same "no mutation on rejection" behaviour). Also counts its own
## execute() calls so a test can assert it was genuinely invoked.
class FakeIllegalStrideController:
	var execute_call_count: int = 0

	func execute(_payload = null, _no_self_spend_execution: bool = false) -> Dictionary:
		execute_call_count += 1
		return {"ok": false, "resolved": false, "error": "ERR_STRIDE_DESTINATION_NOT_SELECTABLE"}


## FakeUnreachedStrikeController — a stand-in Strike sub-controller that
## must NEVER be invoked once the queued Stride ahead of it aborts (the
## resolution loop stops at the first failing entry). Tracks its own
## execute() call count so this can be asserted directly rather than merely
## inferred from the overall result.
class FakeUnreachedStrikeController:
	var execute_call_count: int = 0

	func execute(_payload = null, _no_self_spend_execution: bool = false) -> Dictionary:
		execute_call_count += 1
		return {"ok": true, "resolved": true}


func _deps(actor, economy, stride_controller, strike_controller) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(actor, economy))
	var controllers := {"STRIDE": stride_controller, "STRIKE": strike_controller}
	var controller_for := func(verb_id: String):
		return controllers.get(verb_id, null)
	return {"session_holder": holder, "controller_for": controller_for}


func _make_actor(stamina: int = 3) -> CombatantClass:
	var actor := CombatantClass.new("player_0", "Titus", "Player", HexCoordClass.new(0, 0))
	actor.stamina = stamina
	actor.actions_this_turn = ["MOVEMENT", "PRIMARY"]
	return actor


func _make_economy() -> ActionEconomyClass:
	var economy := ActionEconomyClass.new()
	economy.start_of_turn()
	return economy


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — an illegal Stride destination aborts the whole Combine:
# ok==false, reason==ILLEGAL_SUB_TARGET, zero mutation.
# ══════════════════════════════════════════════════════════════════════════

func test_illegal_stride_destination_returns_ok_false_reason_illegal_sub_target() -> void:
	var actor := _make_actor()
	var economy := _make_economy()
	var stride_controller := FakeIllegalStrideController.new()
	var strike_controller := FakeUnreachedStrikeController.new()

	var controller := CombineActionControllerClass.new(_deps(actor, economy, stride_controller, strike_controller))
	var result: Dictionary = await controller.execute(null)

	assert_false(result.get("ok", true), "an illegal Stride destination must abort the whole Combine (ok=false)")
	assert_eq(
		result.get("reason"), "ILLEGAL_SUB_TARGET",
		"an illegal Stride destination must be reported as reason=ILLEGAL_SUB_TARGET"
	)


func test_illegal_stride_destination_leaves_actor_position_unchanged() -> void:
	var actor := _make_actor()
	var economy := _make_economy()
	var stride_controller := FakeIllegalStrideController.new()
	var strike_controller := FakeUnreachedStrikeController.new()
	var start_hex := actor.hex_coord

	var controller := CombineActionControllerClass.new(_deps(actor, economy, stride_controller, strike_controller))
	await controller.execute(null)

	assert_true(
		actor.hex_coord.equals(start_hex),
		"an aborted (illegal Stride) Combine must leave the actor's position completely unchanged"
	)


func test_illegal_stride_destination_never_appends_a_ledger_charge() -> void:
	var actor := _make_actor()
	var economy := _make_economy()
	var stride_controller := FakeIllegalStrideController.new()
	var strike_controller := FakeUnreachedStrikeController.new()
	var budget_before: int = economy.get_remaining()

	var controller := CombineActionControllerClass.new(_deps(actor, economy, stride_controller, strike_controller))
	await controller.execute(null)

	assert_eq(
		economy.get_remaining(), budget_before,
		"an aborted (illegal Stride) Combine must never append an action-economy ledger charge -- the budget must be completely untouched"
	)
	assert_true(
		economy.can_take_action(),
		"an aborted (illegal Stride) Combine must leave can_take_action() true -- no charge was ever committed"
	)
	assert_true(
		economy.can_take_movement_action(),
		"an aborted (illegal Stride) Combine must leave the Movement-trait lockout completely untouched -- no charge was ever committed"
	)
	assert_false(
		economy.is_self_spend_suppressed(),
		"the no-self-spend suppression flag must never leak past an aborted execute() call"
	)


func test_illegal_stride_destination_leaves_stamina_unchanged() -> void:
	var actor := _make_actor(3)
	var economy := _make_economy()
	var stride_controller := FakeIllegalStrideController.new()
	var strike_controller := FakeUnreachedStrikeController.new()

	var controller := CombineActionControllerClass.new(_deps(actor, economy, stride_controller, strike_controller))
	await controller.execute(null)

	assert_eq(actor.stamina, 3, "an aborted (illegal Stride) Combine must never spend Stamina")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — state-consistency: count(effects applied) ==
# count(ledger charges committed) == 0. Proven directly: the queued Strike
# sub-action (which would be the second effect) is NEVER reached once the
# Stride ahead of it aborts, and the Stride's own controller was invoked
# exactly once (attempted, but its own effect never committed either).
# ══════════════════════════════════════════════════════════════════════════

func test_illegal_stride_destination_never_reaches_the_queued_strike_sub_action() -> void:
	var actor := _make_actor()
	var economy := _make_economy()
	var stride_controller := FakeIllegalStrideController.new()
	var strike_controller := FakeUnreachedStrikeController.new()

	var controller := CombineActionControllerClass.new(_deps(actor, economy, stride_controller, strike_controller))
	var result: Dictionary = await controller.execute(null)

	assert_eq(stride_controller.execute_call_count, 1, "the illegal Stride sub-action must be attempted exactly once")
	assert_eq(
		strike_controller.execute_call_count, 0,
		"the queued Strike sub-action must NEVER be reached once the preceding Stride aborts -- zero effects applied, matching zero ledger charges committed"
	)
	assert_eq(result.get("resolved_verb_ids", []), [], "no sub-action verb_id may be reported as resolved when the very first entry aborts")


# ══════════════════════════════════════════════════════════════════════════
# Boot-real complement — drives the REAL, live StrideActionController
# (resolved via the SAME `_controller(verb_id)` table lookup every other
# verb uses) with a genuinely illegal Stride destination (far outside the
# actor's real Speed), proving this is not merely a property of a
# hand-rolled fake but of the real production sub-controller's own
# rejection contract.
# ══════════════════════════════════════════════════════════════════════════

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
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


func test_boot_real_illegal_stride_destination_aborts_combine_with_zero_mutation() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)

	var titus_start_hex = titus.hex_coord
	assert_eq([titus_start_hex.q, titus_start_hex.r], [0, 0], "fixture assumption: Titus starts at (0,0) per the prologue encounter resource")

	var combine_controller = instance._controller("COMBINE")
	assert_true(combine_controller is CombineActionControllerClass, "_controller(\"COMBINE\") must resolve a real CombineActionController")

	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var budget_before: int = economy.get_remaining()
	var stamina_before: int = titus.stamina
	var skeleton_hp_before: int = skeleton.hp_current

	# A hex far outside Titus's real Speed (Movement.DEFAULT_SPEED = 4) is
	# never a legal Stride destination -- this exercises the REAL
	# movement_input_controller rejection path (ERR_STRIDE_DESTINATION_NOT_SELECTABLE)
	# via the actual, booted StrideActionController.
	var illegal_destination := HexCoordClass.new(999, 999)

	var result: Dictionary = await combine_controller.execute({
		"STRIDE": illegal_destination,
		"STRIKE": skeleton.display_id(),
	})

	assert_false(result.get("ok", true), "an illegal Stride destination must abort the real, booted Combine (ok=false)")
	assert_eq(result.get("reason"), "ILLEGAL_SUB_TARGET", "the real, booted Combine must report reason=ILLEGAL_SUB_TARGET for an illegal Stride destination")

	assert_true(titus.hex_coord.equals(titus_start_hex), "Titus must NOT have moved -- the illegal Stride's own effect must never apply")
	assert_eq(skeleton.hp_current, skeleton_hp_before, "the Skeleton must take no damage -- the queued Strike must never be reached")
	assert_eq(titus.stamina, stamina_before, "Stamina must be completely unchanged on an aborted (illegal Stride) Combine")
	assert_eq(economy.get_remaining(), budget_before, "the action-economy budget must be completely unchanged -- no ledger charge was ever committed")
	assert_true(economy.can_take_action(), "the actor's action must remain available -- no charge was ever committed")
	assert_false(economy.is_self_spend_suppressed(), "the suppression flag must never leak past an aborted execute() call")
