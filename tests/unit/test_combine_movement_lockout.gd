extends GutTest
## tests/unit/test_combine_movement_lockout.gd — FEAT-009 (US-009; FR-008)
##
## Iteration N (Combinations): proves the EXISTING Movement-trait lockout
## gate (core/rules/action_economy.gd's `_movement_used`, tripped by
## `spend_action({"traits": ["Movement"]})` — the SAME gate a standalone
## Stride trips) is also tripped exactly once, at the COMBINE level, when a
## Combine's resolved sub-action queue contains a STRIDE entry (e.g. Charge
## = [STRIDE, STRIKE]).
##
## This is NOT a second/parallel lockout mechanism: it is
## presentation/combine_action_controller.gd's execute() (wired as part of
## FEAT-008's charge-first rework — see that file's own
## "FEAT-008 (US-008; FR-007; ADR-003) — charge FIRST" doc comment) tagging
## its OWN single action-economy charge with the "Movement" trait whenever
## the queue it is about to resolve contains a STRIDE entry, and routing
## that charge through the SAME `ActionEconomy.spend_action()` call every
## standalone Movement-trait verb (Stride) already routes through. This
## suite is this feature's PINNING test for that existing behaviour, plus
## the negative case (no STRIDE in the queue -> no lockout).
##
## There is no separate `actor.status_flags.movement_used` field on
## core/domain/combatant.gd (nor a `core/entities/combatant.gd` module) in
## this codebase: the movement-lockout flag lives EXCLUSIVELY on the
## actor's live ActionEconomy (`_movement_used`, read via
## `can_take_movement_action()`), matching Stride's own
## `availability()` gate (presentation/stride_action_controller.gd) and
## every other movement-lockout test in this suite (e.g.
## tests/unit/core/rules/test_movement_lockout.gd). Duplicating that state
## onto Combatant would create a second, driftable source of truth for the
## SAME per-turn flag — so this suite asserts the lockout the same way the
## rest of the codebase already does: through the actor's ActionEconomy.
##
## Mirrors tests/unit/test_combine_availability.gd / test_sub_action_queue_
## resolution.gd's "real fake session + real ActionEconomy, no MainScene.tscn
## boot required" convention, and test_combine_single_charge.gd's "fake
## sub-controllers resolved via controller_for" convention.
##
## test_criteria covered:
##   1. After a Charge execute() (STRIDE+STRIKE), the actor's live
##      ActionEconomy reports the Movement-trait lockout as tripped
##      (can_take_movement_action() == false) -- the same live-state
##      surface `actor.status_flags.movement_used == true` describes.
##   2. A subsequent standalone Movement-trait spend_action() attempt in the
##      same turn is rejected (success=false, reason="Movement already
##      used"), matching standalone Stride's own lockout behaviour.
##   3. A Combine whose resolved queue does NOT contain a STRIDE entry does
##      not trip the Movement lockout (can_take_movement_action() stays
##      true).

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const RoundSessionHolderClass      = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SubActionQueueEntryClass     = preload("res://core/rules/sub_action_queue_entry.gd")
const MovementClass                = preload("res://core/rules/movement.gd")


## FakeSession — the same minimal current_actor()/current_actor_entity()/
## current_action_economy() double established by
## tests/unit/test_combine_availability.gd / test_combine_stamina_decrement.gd.
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


## FakeSubController — a minimal stand-in for StrideActionController /
## StrikeActionController: its execute() always reports ok=true and never
## touches the actor's ActionEconomy itself (mirrors the REAL
## no_self_spend_execution=true contract those controllers honour when
## resolved as Combine sub-actions -- see presentation/combine_action_
## controller.gd's own `_sub_action_resolver()` doc). This isolates the
## test from Stride/Strike's own targeting/reach logic entirely: the ONLY
## thing under test here is whether CombineActionController.execute() tags
## its own single charge with the "Movement" trait when the QUEUE contains
## a STRIDE entry.
class FakeSubController:
	func execute(_payload = null, _no_self_spend_execution: bool = false) -> Dictionary:
		return {"ok": true}


func _deps(actor, economy) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(actor, economy))
	var controller_for := func(_verb_id: String):
		return FakeSubController.new()
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
# Criterion 1 — after a Charge execute() (STRIDE+STRIKE), the Movement-trait
# lockout is tripped on the actor's live ActionEconomy.
# ══════════════════════════════════════════════════════════════════════════

func test_charge_execute_trips_movement_lockout() -> void:
	var actor := _make_actor()
	var economy := _make_economy()
	assert_true(economy.can_take_movement_action(), "fixture assumption: Movement lockout must be clear before the Combine executes")

	var controller := CombineActionControllerClass.new(_deps(actor, economy))
	var result: Dictionary = await controller.execute(null)

	assert_true(result.get("ok", false), "a valid Charge (STRIDE+STRIKE) Combine execute() must succeed (result: %s)" % [result])
	assert_eq(result.get("resolved_verb_ids", []), ["STRIDE", "STRIKE"], "the default queue must resolve STRIDE then STRIKE")
	assert_false(
		economy.can_take_movement_action(),
		"after a Charge execute() containing a STRIDE sub-action, the actor's Movement-trait lockout must be tripped, matching standalone Stride's own lockout behaviour"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — a subsequent standalone Movement-trait action attempt in
# the same turn is rejected, exactly as it would be after a standalone
# Stride.
#
# Uses core/rules/movement.gd's Movement.step() (a FREE move, per that
# file's own doc, that never touches the shared action budget/
# `_action_used` gate at all) as the "subsequent standalone Movement-trait
# action attempt" -- this isolates the assertion to the Movement-trait
# lockout specifically (`can_take_movement_action()` / ERR_MOVEMENT_LOCKED),
# the SAME gate a standalone Stride's own availability()/spend_action()
# reads. A second economy.spend_action() call would ALSO be rejected here,
# but via the unrelated per-turn "one action already spent" gate
# (ACTION_ALREADY_USED) -- true, but not what this criterion is pinning.
# ══════════════════════════════════════════════════════════════════════════

func test_standalone_movement_action_rejected_after_charge_execute() -> void:
	var actor := _make_actor()
	var economy := _make_economy()

	var controller := CombineActionControllerClass.new(_deps(actor, economy))
	await controller.execute(null)
	assert_false(economy.can_take_movement_action(), "fixture assumption: the Charge above must have tripped the Movement lockout")

	var step_result: Dictionary = MovementClass.step(actor, HexCoordClass.new(1, 0), [], economy)

	assert_false(
		step_result.get("ok", true),
		"a standalone Movement-trait action attempted after a Charge Combine must be rejected, matching standalone Stride's own lockout"
	)
	assert_eq(
		step_result.get("error"), MovementClass.ERR_MOVEMENT_LOCKED,
		"the rejection must be the SAME ERR_MOVEMENT_LOCKED gate a standalone double-Stride/Step attempt reports"
	)
	assert_true(actor.hex_coord.equals(HexCoordClass.new(0, 0)), "the rejected Step must not move the actor")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — a Combine without a STRIDE sub-action must NOT trip the
# Movement lockout.
# ══════════════════════════════════════════════════════════════════════════

func test_combine_without_stride_does_not_trip_movement_lockout() -> void:
	var actor := _make_actor()
	var economy := _make_economy()

	var controller := CombineActionControllerClass.new(_deps(actor, economy))

	# A synthetic Combine queue with no STRIDE entry at all (e.g. two
	# Repeat-tagged STRIKEs) -- exercised via execute()'s own
	# `selection["queue"]` override (see that method's doc).
	var no_stride_queue: Array = [
		SubActionQueueEntryClass.new(0, "STRIKE"),
		SubActionQueueEntryClass.new(1, "STRIKE"),
	]

	var result: Dictionary = await controller.execute({"queue": no_stride_queue})

	assert_true(result.get("ok", false), "a valid Combine execute() with no STRIDE sub-action must still succeed (result: %s)" % [result])
	assert_eq(result.get("resolved_verb_ids", []), ["STRIKE", "STRIKE"], "the synthetic no-STRIDE queue must resolve both STRIKE entries in order")
	assert_true(
		economy.can_take_movement_action(),
		"a Combine whose resolved queue contains no STRIDE entry must NOT trip the Movement-trait lockout"
	)


func test_repeated_combine_without_stride_never_trips_movement_lockout() -> void:
	var actor := _make_actor(5)
	var economy := _make_economy()

	var controller := CombineActionControllerClass.new(_deps(actor, economy))
	var no_stride_queue: Array = [
		SubActionQueueEntryClass.new(0, "STRIKE"),
		SubActionQueueEntryClass.new(1, "STRIKE"),
	]

	await controller.execute({"queue": no_stride_queue})

	assert_true(
		economy.can_take_movement_action(),
		"a no-STRIDE Combine must leave the Movement-trait lockout untouched even after execute() completes"
	)
	# The actor's OWN action for the turn is still consumed (single-charge
	# invariant, FEAT-008) -- only the MOVEMENT-specific gate is unaffected.
	assert_false(economy.can_take_action(), "the Combine's own single action charge must still apply even when no STRIDE sub-action is present")
