extends GutTest
## tests/unit/test_combine_availability.gd — FEAT-004 (US-004; FR-004) +
## FEAT-008 (US-008; FR-007; ADR-003)
##
## Iteration N (Combinations): CombineActionController.availability() gates
## the COMBINE verb on preconditions:
##   1. actor.stamina >= 1
##   2. actor is NOT Dazed
##   3. actor.combinable_actions_available() >= 2 — the live per-turn
##      combinable-action-slot count sourced from the Combatant entity
##      (core/domain/combatant.gd's `actions_this_turn`).
##   4. live ActionEconomy.can_take_action() — actor has not already used their
##      action this turn AND is not round-spent (FEAT-008: mirroring the gate
##      Strike/Stride already apply via their own availability()).
##
## test_criteria covered:
##   1. availability() true when stamina>=1, not dazed, and >=2 combinable
##      actions are available.
##   2. availability() false when stamina==0.
##   3. availability() false when dazed==true.
##   4. availability() false when <2 combinable actions are available.
##   5. availability() false with no live actor (fail-safe).
##   6. availability() false when can_take_action() is false (action already used).

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const RoundSessionHolderClass      = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")


class FakeSession:
	var _actor
	var _economy

	func _init(actor, economy = null) -> void:
		_actor = actor
		_economy = economy

	func current_actor():
		return {} if _actor == null else {"combatant_id": _actor.combatant_id}

	func current_actor_entity():
		return _actor

	func current_action_economy():
		return _economy


func _deps(actor = null) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	if actor != null:
		holder.set_current(FakeSession.new(actor))
	return {"session_holder": holder}


func _deps_with_economy(actor, economy) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(actor, economy))
	return {"session_holder": holder}


## _make_actor(stamina, dazed, combinable_actions) -> Combatant
##
## combinable_actions defaults to 2 -- a fresh turn's Movement + Primary
## slot count (Combatant's own default) -- so every PRE-EXISTING test below
## that doesn't care about the ">=2 combinable actions" predicate keeps
## exercising exactly the stamina/dazed branch its name describes, isolated
## from this newer predicate.
func _make_actor(stamina: int, dazed: bool, combinable_actions: int = 2) -> CombatantClass:
	var actor := CombatantClass.new("player_0", "Titus", "Player", HexCoordClass.new(0, 0))
	actor.stamina = stamina
	if dazed:
		actor.add_condition("Dazed")
	actor.actions_this_turn = []
	for i in range(combinable_actions):
		actor.actions_this_turn.append("SLOT_%d" % i)
	return actor


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — availability() is TRUE when stamina >= 1, not Dazed, and
# >=2 combinable actions are available this turn.
# ══════════════════════════════════════════════════════════════════════════

func test_availability_true_when_stamina_and_not_dazed() -> void:
	var actor := _make_actor(1, false)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_true(
		controller.availability(),
		"availability() must be true when stamina>=1, actor is not Dazed, and >=2 combinable actions are available"
	)


func test_availability_true_with_surplus_stamina() -> void:
	var actor := _make_actor(3, false)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_true(
		controller.availability(),
		"availability() must be true when stamina comfortably exceeds 1, actor is not Dazed, and >=2 combinable actions are available"
	)


func test_availability_true_with_more_than_two_combinable_actions() -> void:
	var actor := _make_actor(1, false, 3)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_true(
		controller.availability(),
		"availability() must be true when combinable actions available exceeds 2"
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
# Criterion 4 — availability() is FALSE when fewer than 2 combinable
# actions are available this turn (Combatant.actions_this_turn-sourced).
# ══════════════════════════════════════════════════════════════════════════

func test_availability_false_when_only_one_combinable_action_available() -> void:
	var actor := _make_actor(1, false, 1)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_false(
		controller.availability(),
		"availability() must be false when only 1 combinable action is available this turn"
	)


func test_availability_false_when_zero_combinable_actions_available() -> void:
	var actor := _make_actor(1, false, 0)
	var controller := CombineActionControllerClass.new(_deps(actor))

	assert_false(
		controller.availability(),
		"availability() must be false when 0 combinable actions are available this turn"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — fail-safe: no live actor must not crash, must return false.
# ══════════════════════════════════════════════════════════════════════════

func test_availability_false_with_no_live_session() -> void:
	var controller := CombineActionControllerClass.new(_deps())

	assert_false(
		controller.availability(),
		"availability() with no live actor must return false without crashing"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 — availability() is FALSE when can_take_action() is false
# (FEAT-008: live ActionEconomy gate, mirrors Strike/Stride availability).
# ══════════════════════════════════════════════════════════════════════════

func test_availability_false_when_action_already_used_this_turn() -> void:
	var actor := _make_actor(3, false)
	var economy := ActionEconomyClass.new()
	economy.start_of_turn()
	economy.spend_action({"name": "STRIKE", "traits": []})
	assert_false(economy.can_take_action(), "fixture: action must be used before testing availability")

	var controller := CombineActionControllerClass.new(_deps_with_economy(actor, economy))

	assert_false(
		controller.availability(),
		"availability() must be false when the actor has already used their action this turn"
	)


func test_availability_false_when_round_budget_exhausted() -> void:
	var actor := _make_actor(3, false)
	var economy := ActionEconomyClass.new()
	while economy.can_take_action():
		economy.spend_action({"name": "WAIT", "traits": []})
		economy.start_of_turn()
	assert_false(economy.can_take_action(), "fixture: budget must be exhausted before testing availability")

	var controller := CombineActionControllerClass.new(_deps_with_economy(actor, economy))

	assert_false(
		controller.availability(),
		"availability() must be false when the actor's round budget is exhausted"
	)
