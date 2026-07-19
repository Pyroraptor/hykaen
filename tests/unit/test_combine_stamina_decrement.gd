extends GutTest
## tests/unit/test_combine_stamina_decrement.gd — FEAT-002 (US-002; FR-001)
##
## Iteration N (Combinations): wires a REAL, live Stamina decrement into
## CombineActionController.execute(), draining through
## core/domain/combatant.gd's Combatant.spend_stamina() — the single
## source-of-truth Stamina mutator every later Combine validation feature
## (Dazed/Repeat/Stamina>=1 gating, the action-economy ledger, ...) will read
## and write through.
##
## Mirrors tests/unit/test_spell_action_controller_skeleton.gd's established
## "minimal fake session / real fake actor, no MainScene.tscn boot required"
## convention, and tests/unit/test_wait_action.gd's "Spy subclass counts
## real method calls" convention for asserting exactly-once spend semantics.
##
## test_criteria covered:
##   1. Given a Combatant with stamina=3, after a valid (stubbed) Combine
##      execute() call, combatant.stamina == 2.
##   2. No secondary/duplicate Stamina-consuming code path fires for the
##      same execute() call (stamina decremented exactly once via spy/counter).

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const RoundSessionHolderClass      = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")


## FakeSession — a tiny, real (not all-mocked) double satisfying the same
## current_actor()/current_actor_entity()/current_action_economy() contract
## core/application/round_session.gd's RoundSession exposes -- the only
## surface ActionController's base class (presentation/action_controller.gd)
## reads through the injected session_holder.
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


## SpyCombatant — a real Combatant that additionally counts spend_stamina()
## calls, so a test can assert Combine's execute() drains Stamina through
## exactly ONE code path (never a second/duplicate one) rather than merely
## observing the post-call stamina value.
class SpyCombatant:
	extends "res://core/domain/combatant.gd"

	var spend_stamina_call_count: int = 0

	func spend_stamina(amount: int = 1) -> void:
		spend_stamina_call_count += 1
		super.spend_stamina(amount)


func _deps(actor = null) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	if actor != null:
		holder.set_current(FakeSession.new(actor))
	return {"session_holder": holder}


func _make_actor(starting_stamina: int) -> SpyCombatant:
	var actor := SpyCombatant.new("player_0", "Titus", "Player", HexCoordClass.new(0, 0))
	actor.stamina = starting_stamina
	return actor


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — a valid (stubbed) Combine execute() call spends exactly one
# Stamina from the actor's LIVE resource (Combatant.stamina).
# ══════════════════════════════════════════════════════════════════════════

func test_execute_decrements_actor_stamina_by_exactly_one() -> void:
	var actor := _make_actor(3)
	var controller := CombineActionControllerClass.new(_deps(actor))

	var result: Dictionary = controller.execute(null)

	assert_eq(actor.stamina, 2, "a valid Combine execute() call must spend exactly one Stamina from the actor's live resource")
	assert_true(result.get("ok", false), "execute() must report ok=true when it successfully spends the actor's Stamina")


func test_execute_mutates_the_same_live_actor_instance_injected_via_the_session() -> void:
	# The single-source-of-truth requirement (US-002): CombineActionController
	# must reach through to the SAME live Combatant instance the session
	# exposes, not a copy/shadow -- so the caller's own reference observes
	# the decrement.
	var actor := _make_actor(1)
	var controller := CombineActionControllerClass.new(_deps(actor))

	controller.execute(null)

	assert_eq(actor.stamina, 0, "execute() must mutate the live actor instance in place, not a detached copy")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — no secondary/duplicate Stamina-consuming code path fires for
# the same execute() call: Combatant.spend_stamina() is invoked exactly once.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_spends_stamina_via_exactly_one_call_to_spend_stamina() -> void:
	var actor := _make_actor(3)
	var controller := CombineActionControllerClass.new(_deps(actor))

	controller.execute(null)

	assert_eq(
		actor.spend_stamina_call_count, 1,
		"Combine execute() must drain Stamina through exactly one spend_stamina() call -- never a second/duplicate Stamina-consuming code path"
	)


func test_repeated_execute_calls_each_spend_stamina_exactly_once() -> void:
	var actor := _make_actor(5)
	var controller := CombineActionControllerClass.new(_deps(actor))

	controller.execute(null)
	controller.execute(null)

	assert_eq(
		actor.spend_stamina_call_count, 2,
		"each Combine execute() call must independently spend exactly one Stamina -- two calls must total exactly two spend_stamina() invocations, not more"
	)
	assert_eq(actor.stamina, 3, "two valid Combine execute() calls must leave stamina reduced by exactly two, from 5 to 3")


# ══════════════════════════════════════════════════════════════════════════
# Fail-safe — no live actor: execute() must not crash and must not spend
# Stamina (mirrors the FEAT-001 stub's "fails safe rather than crashing"
# no-live-session contract).
# ══════════════════════════════════════════════════════════════════════════

func test_execute_with_no_live_session_fails_safe_without_crashing() -> void:
	var controller := CombineActionControllerClass.new(_deps())

	var result: Dictionary = controller.execute(null)

	assert_false(result.get("ok", true), "execute() with no live actor must report ok=false, never a crash or a false success")
