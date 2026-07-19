extends GutTest
## tests/unit/test_combine_availability.gd — FEAT-004 (US-004; FR-004)
##
## Iteration N (Combinations): implements CombineActionController.availability()'s
## real three-predicate gate, replacing FEAT-001's permanently fail-closed
## stub. The COMBINE verb is offered to the player (steel thread entry point)
## ONLY when ALL THREE hold for the live current actor:
##   1. actor.stamina >= 1
##   2. actor is NOT Dazed (Combatant.has_condition("Dazed") -- the SAME
##      "Dazed" condition-tag string already used project-wide, e.g.
##      tests/unit/test_resolution.gd / tests/unit/presentation/
##      test_status_panel_view.gd)
##   3. actor has >= 2 combinable actions available this turn
##      (Combatant.combinable_actions_available(), core/domain/combatant.gd)
##
## Mirrors tests/unit/test_combine_stamina_decrement.gd's established
## "minimal fake session / real fake actor, no MainScene.tscn boot required"
## convention -- availability() is a pure function of the live current actor
## entity, so no live RoundSession/ActionEconomy wiring is required here.
##
## test_criteria covered:
##   1. availability() true when stamina>=1, not dazed, >=2 combinable
##      actions available.
##   2. availability() false when stamina==0.
##   3. availability() false when dazed==true.
##   4. availability() false when <2 combinable actions available.
##   All four branches covered by dedicated unit test cases.

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const RoundSessionHolderClass      = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")


## FakeSession -- mirrors tests/unit/test_combine_stamina_decrement.gd's
## established minimal double satisfying the current_actor()/
## current_actor_entity()/current_action_economy() contract
## presentation/action_controller.gd's base class reads through the injected
## session_holder.
class FakeSession:
	var _actor

	func _init(actor) -> void:
		_actor = actor

	func current_actor():
		return {} if _actor == null else {"combatant_id": _actor.combatant_id}

	func current_actor_entity():
		return _actor

	func current_action_economy():
		return null


func _deps(actor = null) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	if actor != null:
		holder.set_current(FakeSession.new(actor))
	return {"session_holder": holder}


## _make_actor(stamina, dazed, combinable_count) -> Combatant -- a real
## Combatant entity (not a mock) with the three availability() inputs set
## directly, so each test below toggles exactly ONE input at a time (mirrors
## the project's established "toggle one live-state input per test"
## convention, e.g. tests/pytest/test_verb_availability.py).
func _make_actor(stamina: int, dazed: bool, combinable_count: int) -> CombatantClass:
	var actor := CombatantClass.new("player_0", "Titus", "Player", HexCoordClass.new(0, 0))
	actor.stamina = stamina
	if dazed:
		actor.add_condition("Dazed")
	actor.actions_this_turn = []
	for i in range(combinable_count):
		actor.actions_this_turn.append("action_%d" % i)
	return actor


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — availability() is TRUE when all three predicates pass:
# stamina >= 1, not Dazed, >= 2 combinable actions available.
# ══════════════════════════════════════════════════════════════════════════

func test_availability_true_when_stamina_not_dazed_and_two_combinable_actions() -> void:
	var actor := _make_actor(1, false, 2)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_true(
		controller.availability(),
		"availability() must be true when stamina>=1, not dazed, and >=2 combinable actions are available"
	)


func test_availability_true_with_more_than_the_minimum_of_each_input() -> void:
	var actor := _make_actor(3, false, 4)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_true(
		controller.availability(),
		"availability() must be true when every predicate comfortably exceeds its minimum threshold"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — availability() is FALSE when stamina == 0, even though the
# other two predicates pass.
# ══════════════════════════════════════════════════════════════════════════

func test_availability_false_when_stamina_is_zero() -> void:
	var actor := _make_actor(0, false, 2)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_false(
		controller.availability(),
		"availability() must be false when stamina == 0, even when not dazed and >=2 combinable actions exist"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — availability() is FALSE when dazed == true, even though the
# other two predicates pass.
# ══════════════════════════════════════════════════════════════════════════

func test_availability_false_when_dazed() -> void:
	var actor := _make_actor(1, true, 2)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_false(
		controller.availability(),
		"availability() must be false when the actor is Dazed, even when stamina>=1 and >=2 combinable actions exist"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — availability() is FALSE when fewer than 2 combinable actions
# are available this turn, even though the other two predicates pass.
# ══════════════════════════════════════════════════════════════════════════

func test_availability_false_when_fewer_than_two_combinable_actions() -> void:
	var actor := _make_actor(1, false, 1)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_false(
		controller.availability(),
		"availability() must be false when fewer than 2 combinable actions are available this turn"
	)


func test_availability_false_when_zero_combinable_actions() -> void:
	var actor := _make_actor(1, false, 0)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_false(
		controller.availability(),
		"availability() must be false when zero combinable actions are available this turn"
	)


# ══════════════════════════════════════════════════════════════════════════
# Fail-safe — no live actor: availability() must not crash and must report
# false (mirrors the FEAT-001 stub's "fails safe rather than crashing"
# no-live-session contract).
# ══════════════════════════════════════════════════════════════════════════

func test_availability_false_with_no_live_session() -> void:
	var controller := CombineActionControllerClass.new(_deps())

	assert_false(
		controller.availability(),
		"availability() with no live actor must report false, never a crash or a false-positive"
	)
