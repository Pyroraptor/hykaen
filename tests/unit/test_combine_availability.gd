extends GutTest
## tests/unit/test_combine_availability.gd — FEAT-004 (US-004; FR-004)
##
## Iteration N (Combinations): CombineActionController.availability() gates
## the COMBINE verb on two static preconditions:
##   1. actor.stamina >= 1
##   2. actor is NOT Dazed
## The ">=2 combinable actions available" predicate is deferred to execute()
## → combine_actions(), which is the authoritative validation site per spec.
##
## test_criteria covered:
##   1. availability() true when stamina>=1 and not dazed.
##   2. availability() false when stamina==0.
##   3. availability() false when dazed==true.
##   4. availability() false with no live actor (fail-safe).

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const RoundSessionHolderClass      = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")


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


func _make_actor(stamina: int, dazed: bool) -> CombatantClass:
	var actor := CombatantClass.new("player_0", "Titus", "Player", HexCoordClass.new(0, 0))
	actor.stamina = stamina
	if dazed:
		actor.add_condition("Dazed")
	return actor


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — availability() is TRUE when stamina >= 1 and not Dazed.
# ══════════════════════════════════════════════════════════════════════════

func test_availability_true_when_stamina_and_not_dazed() -> void:
	var actor := _make_actor(1, false)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_true(
		controller.availability(),
		"availability() must be true when stamina>=1 and actor is not Dazed"
	)


func test_availability_true_with_surplus_stamina() -> void:
	var actor := _make_actor(3, false)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_true(
		controller.availability(),
		"availability() must be true when stamina comfortably exceeds 1 and actor is not Dazed"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — availability() is FALSE when stamina == 0.
# ══════════════════════════════════════════════════════════════════════════

func test_availability_false_when_stamina_is_zero() -> void:
	var actor := _make_actor(0, false)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_false(
		controller.availability(),
		"availability() must be false when stamina == 0"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — availability() is FALSE when dazed == true.
# ══════════════════════════════════════════════════════════════════════════

func test_availability_false_when_dazed() -> void:
	var actor := _make_actor(1, true)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_false(
		controller.availability(),
		"availability() must be false when actor is Dazed"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — fail-safe: no live actor must not crash, must return false.
# ══════════════════════════════════════════════════════════════════════════

func test_availability_false_with_no_live_session() -> void:
	var controller := CombineActionControllerClass.new(_deps())

	assert_false(
		controller.availability(),
		"availability() with no live actor must return false without crashing"
	)
