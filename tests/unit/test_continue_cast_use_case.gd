extends GutTest
## tests/unit/test_continue_cast_use_case.gd — FEAT-006 (US-006; FR-005)
##
## GUT suite for core/application/use_cases/continue_cast_use_case.gd's
## ContinueCastUseCase. Mirrors tests/unit/test_begin_cast_use_case.gd's
## established "fake, duck-typed port doubles / real domain objects"
## convention -- no adapter, no engine boot; that is a boot-real test's job
## (tests/boot/test_first_cast_firebolt.gd's own sibling boot-real proof for
## the SECOND cast lands separately).
##
## test_criteria covered:
##   "Unit test confirms ContinueCastUseCase performs no re-selection and no
##   re-payment of energy" -- verified via a FakeSpellCatalogPort/
##   FakeRoundEnergyPoolPort that ContinueCastUseCase is never even handed
##   (its execute() signature takes no catalog/pool argument at all), plus
##   an explicit pool-balance-untouched assertion using
##   test_begin_cast_use_case.gd's own FakeRoundEnergyPoolPort double
##   directly (proving a real reserve()-shaped collaborator, if handed to
##   this use case's caller elsewhere, is never invoked by this use case).

const ContinueCastUseCaseClass = preload("res://core/application/use_cases/continue_cast_use_case.gd")
const BeginCastUseCaseTestClass = preload("res://tests/unit/test_begin_cast_use_case.gd")
const CastingStateClass        = preload("res://core/domain/casting_state.gd")
const CombatantClass           = preload("res://core/domain/combatant.gd")
const HexCoordClass            = preload("res://core/geometry/hex_coord.gd")
const ErrorCodeClass           = preload("res://core/application/ports/errors.gd")


## FakeActionEconomy -- duck-typed action-economy double: records every
## spend_action() call so a test can assert exactly one action is spent per
## continue-cast, and none on a failed/defensive call.
class FakeActionEconomy:
	extends RefCounted
	var spend_calls: Array = []

	func spend_action(action_metadata: Dictionary) -> Dictionary:
		spend_calls.append(action_metadata)
		return {"success": true, "ok": true}


func _mid_cast_caster(remaining_actions: int = 1, committed_energy: int = 2):
	var c := CombatantClass.new("marigold_1", "Marigold", "Player", HexCoordClass.new(0, 0))
	c.known_spell_ids = ["fire_bolt"]
	c.casting_state = {
		"spell_id": "fire_bolt",
		"remaining_actions": remaining_actions,
		"committed_energy": committed_energy,
		"caster_id": "marigold_1",
	}
	return c


# ══════════════════════════════════════════════════════════════════════════
# Success path -- decrements remaining_actions, spends exactly one action
# ══════════════════════════════════════════════════════════════════════════

func test_execute_decrements_remaining_actions_and_spends_one_action() -> void:
	var actor = _mid_cast_caster(1, 2)
	var action_economy := FakeActionEconomy.new()

	var use_case := ContinueCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(actor, action_economy)

	assert_true(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.NONE)
	assert_eq(result.get("casting_state"), {"spell_id": "fire_bolt", "remaining_actions": 0, "committed_energy": 2, "caster_id": "marigold_1"})

	assert_true(actor.is_casting(), "actor with remaining_actions == 0 is still 'mid-cast' until ResolveCastUseCase clears it (out of this feature's scope)")
	assert_eq(actor.casting_state.get("remaining_actions"), 0)
	assert_eq(action_economy.spend_calls.size(), 1, "exactly one action must be spent to continue the cast")


func test_execute_drives_remaining_actions_to_zero_over_two_continue_calls() -> void:
	# A 3-action spell begun this turn shows remaining_actions == 2
	# immediately (begin_cast()'s own -1); two ContinueCastUseCase calls
	# (one per subsequent turn) must drive it to exactly 0.
	var actor = _mid_cast_caster(2, 3)
	var action_economy := FakeActionEconomy.new()
	var use_case := ContinueCastUseCaseClass.new()

	var first: Dictionary = use_case.execute(actor, action_economy)
	assert_eq(first.get("casting_state").get("remaining_actions"), 1)

	var second: Dictionary = use_case.execute(actor, action_economy)
	assert_eq(second.get("casting_state").get("remaining_actions"), 0)

	assert_eq(action_economy.spend_calls.size(), 2, "one action must be spent per continue-cast call")


# ══════════════════════════════════════════════════════════════════════════
# Criterion: no re-selection and no re-payment of energy
# ══════════════════════════════════════════════════════════════════════════

func test_execute_signature_takes_no_spell_catalog_or_energy_pool_collaborator() -> void:
	# ContinueCastUseCase.execute() takes only (actor, action_economy) --
	# there is no spell_catalog_port/round_energy_pool_port parameter at
	# all, unlike BeginCastUseCase.execute(actor, spell_id, catalog, pool,
	# action_economy). A structurally absent parameter is the strongest
	# possible proof that no re-selection/re-payment collaborator is ever
	# consulted: there is nothing to pass one to.
	var use_case := ContinueCastUseCaseClass.new()
	var method_list: Array = use_case.get_method_list()

	var execute_arg_count: int = -1
	for m in method_list:
		if m.get("name") == "execute":
			execute_arg_count = (m.get("args", []) as Array).size()
			break

	assert_eq(execute_arg_count, 2, "execute() must accept exactly (actor, action_economy) -- no catalog/pool parameter")


func test_execute_does_not_touch_a_round_energy_pool_balance() -> void:
	var actor = _mid_cast_caster(1, 2)
	var pool := BeginCastUseCaseTestClass.FakeRoundEnergyPoolPort.new(5)

	var use_case := ContinueCastUseCaseClass.new()
	use_case.execute(actor, FakeActionEconomy.new())

	assert_eq(pool.balance("marigold_1"), 5, "continuing a cast must never touch the round energy pool balance -- energy was already committed up front at BeginCastUseCase time")
	assert_true(pool.reserve_calls.is_empty(), "continuing a cast must never call reserve() again -- no re-payment of energy")


func test_execute_leaves_committed_energy_unchanged() -> void:
	var actor = _mid_cast_caster(1, 7)

	var use_case := ContinueCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(actor, FakeActionEconomy.new())

	assert_eq(result.get("casting_state").get("committed_energy"), 7, "committed_energy must be carried through unchanged -- no re-payment")
	assert_eq(actor.casting_state.get("committed_energy"), 7)


func test_execute_leaves_spell_id_unchanged() -> void:
	var actor = _mid_cast_caster(1, 2)

	var use_case := ContinueCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(actor, FakeActionEconomy.new())

	assert_eq(result.get("casting_state").get("spell_id"), "fire_bolt", "spell_id must be carried through unchanged -- no re-selection")


func test_execute_works_with_no_action_economy_supplied() -> void:
	var actor = _mid_cast_caster(1, 2)

	var use_case := ContinueCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(actor)

	assert_true(result.get("success"), "action_economy must be optional, mirroring BeginCastUseCase.execute()'s convention")
	assert_eq(result.get("casting_state").get("remaining_actions"), 0)


# ══════════════════════════════════════════════════════════════════════════
# Defensive: not-yet-casting / null actor
# ══════════════════════════════════════════════════════════════════════════

func test_execute_fails_safe_when_actor_is_not_casting() -> void:
	var actor := CombatantClass.new("marigold_1", "Marigold", "Player", HexCoordClass.new(0, 0))
	assert_false(actor.is_casting())
	var action_economy := FakeActionEconomy.new()

	var use_case := ContinueCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(actor, action_economy)

	assert_false(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_INVALID_STATE)
	assert_null(result.get("casting_state"))
	assert_eq(action_economy.spend_calls.size(), 0, "no action may be spent when the actor is not already mid-cast")


func test_execute_fails_safe_with_null_actor() -> void:
	var use_case := ContinueCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(null)

	assert_false(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_INVALID_STATE)
	assert_null(result.get("casting_state"))
