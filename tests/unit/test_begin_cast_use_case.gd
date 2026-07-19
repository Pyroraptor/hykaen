extends GutTest
## tests/unit/test_begin_cast_use_case.gd — FEAT-005 (US-005; FR-004)
##
## GUT suite for core/application/use_cases/begin_cast_use_case.gd's
## BeginCastUseCase, core/domain/casting_state.gd's CastingState value
## object, and core/domain/combatant.gd's new begin_cast() domain method.
## Mirrors this project's established "fake, duck-typed port doubles / real
## domain objects" convention (e.g. tests/unit/core/application/
## use_cases/test_resolve_stride_use_case.gd) — no adapter, no engine boot;
## that is tests/boot/test_first_cast_firebolt.gd's job.
##
## test_criteria covered:
##   1. availability() returns true for a castable known spell with
##      sufficient pool energy, or when already casting.
##   3. Unit test: energy reservation failure returns ERR_INSUFFICIENT_ENERGY
##      with no casting_state set and no action spent.

const BeginCastUseCaseClass = preload("res://core/application/use_cases/begin_cast_use_case.gd")
const CastingStateClass     = preload("res://core/domain/casting_state.gd")
const CombatantClass        = preload("res://core/domain/combatant.gd")
const HexCoordClass         = preload("res://core/geometry/hex_coord.gd")
const SpellClass             = preload("res://core/domain/spell.gd")
const ErrorCodeClass        = preload("res://core/application/ports/errors.gd")


## FakeSpellCatalogPort — duck-typed SpellCatalogPort double: a plain
## spell_id -> Spell Dictionary lookup, no ResourceLoader/.tres involved.
class FakeSpellCatalogPort:
	extends RefCounted
	var spells: Dictionary = {}

	func get_spell(spell_id: String):
		return spells.get(spell_id, null)


## FakeRoundEnergyPoolPort — duck-typed RoundEnergyPoolPort double: a single
## in-memory balance, with the SAME atomic check-then-decrement `reserve()`
## contract core/application/ports/round_energy_pool_port.gd's real
## SessionEnergyPoolAdapter implements, plus call-tracking so tests can
## assert "no reservation was even attempted" for a not-castable spell_id.
class FakeRoundEnergyPoolPort:
	extends RefCounted
	var _balance: int
	var reserve_calls: Array = []

	func _init(starting_balance: int) -> void:
		_balance = starting_balance

	func reserve(caster_id: String, amount: int) -> bool:
		reserve_calls.append([caster_id, amount])
		if _balance < amount:
			return false
		_balance -= amount
		return true

	func balance(_caster_id: String) -> int:
		return _balance


## FakeActionEconomy — duck-typed action-economy double: records every
## spend_action() call so a test can assert "no action was spent" on a
## failed reservation.
class FakeActionEconomy:
	extends RefCounted
	var spend_calls: Array = []

	func spend_action(action_metadata: Dictionary) -> Dictionary:
		spend_calls.append(action_metadata)
		return {"success": true, "ok": true}


func _caster(known_spell_ids: Array = ["fire_bolt"]):
	var c := CombatantClass.new("marigold_1", "Marigold", "Player", HexCoordClass.new(0, 0))
	c.known_spell_ids = known_spell_ids
	return c


func _fire_bolt(energy_cost: int = 2, actions_cost: int = 2) -> SpellClass:
	return SpellClass.new("fire_bolt", "Fire Bolt", actions_cost, energy_cost, SpellClass.Defense.REFLEX, 50, "2d8+ATTR", "fire", [])


# ══════════════════════════════════════════════════════════════════════════
# CastingState — value object sanity
# ══════════════════════════════════════════════════════════════════════════

func test_casting_state_to_dict_and_back() -> void:
	var state := CastingStateClass.new("fire_bolt", 1, 2, "marigold_1")
	var d: Dictionary = state.to_dict()

	assert_eq(d, {"spell_id": "fire_bolt", "remaining_actions": 1, "committed_energy": 2, "caster_id": "marigold_1"})

	var rebuilt = CastingStateClass.from_dict(d)
	assert_eq(rebuilt.spell_id, "fire_bolt")
	assert_eq(rebuilt.remaining_actions, 1)
	assert_eq(rebuilt.committed_energy, 2)
	assert_eq(rebuilt.caster_id, "marigold_1")


func test_casting_state_is_complete() -> void:
	assert_false(CastingStateClass.new("fire_bolt", 1, 0, "x").is_complete())
	assert_true(CastingStateClass.new("fire_bolt", 0, 0, "x").is_complete())


# ══════════════════════════════════════════════════════════════════════════
# Combatant.begin_cast() — domain mutator
# ══════════════════════════════════════════════════════════════════════════

func test_begin_cast_sets_casting_state_with_decremented_remaining_actions() -> void:
	var c = _caster()
	assert_false(c.is_casting())

	c.begin_cast("fire_bolt", 2, 2)

	assert_true(c.is_casting())
	assert_eq(c.casting_state.get("spell_id"), "fire_bolt")
	assert_eq(c.casting_state.get("remaining_actions"), 1, "a 2-action spell begun this turn must show 1 remaining action immediately")
	assert_eq(c.casting_state.get("committed_energy"), 2)
	assert_eq(c.casting_state.get("caster_id"), "marigold_1")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — availability()
# ══════════════════════════════════════════════════════════════════════════

func test_availability_true_when_known_spell_energy_is_affordable() -> void:
	var actor = _caster(["fire_bolt"])
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt(2)
	var pool := FakeRoundEnergyPoolPort.new(3)

	var use_case := BeginCastUseCaseClass.new()
	assert_true(use_case.availability(actor, catalog, pool), "a known spell whose energy_cost <= pool balance must be available")


func test_availability_false_when_known_spell_energy_is_unaffordable() -> void:
	var actor = _caster(["fire_bolt"])
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt(2)
	var pool := FakeRoundEnergyPoolPort.new(1)

	var use_case := BeginCastUseCaseClass.new()
	assert_false(use_case.availability(actor, catalog, pool), "the sole known spell's energy_cost exceeding the pool balance must be unavailable")


func test_availability_true_when_already_casting_regardless_of_energy() -> void:
	var actor = _caster(["fire_bolt"])
	actor.casting_state = {"spell_id": "fire_bolt", "remaining_actions": 1, "committed_energy": 2, "caster_id": "marigold_1"}
	var catalog := FakeSpellCatalogPort.new()
	var pool := FakeRoundEnergyPoolPort.new(0)

	var use_case := BeginCastUseCaseClass.new()
	assert_true(use_case.availability(actor, catalog, pool), "an already-mid-cast actor is available (continue-casting path) regardless of pool balance")


func test_availability_false_when_actor_knows_no_spells() -> void:
	var actor = _caster([])
	var catalog := FakeSpellCatalogPort.new()
	var pool := FakeRoundEnergyPoolPort.new(99)

	var use_case := BeginCastUseCaseClass.new()
	assert_false(use_case.availability(actor, catalog, pool))


# ══════════════════════════════════════════════════════════════════════════
# execute() — success path
# ══════════════════════════════════════════════════════════════════════════

func test_execute_success_reserves_energy_sets_casting_state_and_spends_action() -> void:
	var actor = _caster(["fire_bolt"])
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt(2, 2)
	var pool := FakeRoundEnergyPoolPort.new(5)
	var action_economy := FakeActionEconomy.new()

	var use_case := BeginCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(actor, "fire_bolt", catalog, pool, action_economy)

	assert_true(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.NONE)
	assert_eq(result.get("casting_state"), {"spell_id": "fire_bolt", "remaining_actions": 1, "committed_energy": 2, "caster_id": "marigold_1"})

	assert_eq(pool.balance("marigold_1"), 3, "the spell's energy_cost (2) must be deducted from the round pool immediately")
	assert_eq(action_economy.spend_calls.size(), 1, "exactly one action must be spent to begin the cast")
	assert_true(actor.is_casting())
	assert_eq(actor.casting_state.get("remaining_actions"), 1)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — insufficient energy fails with NO side effects
# ══════════════════════════════════════════════════════════════════════════

func test_execute_insufficient_energy_returns_error_with_no_casting_state_and_no_action_spent() -> void:
	var actor = _caster(["fire_bolt"])
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt(2, 2)
	var pool := FakeRoundEnergyPoolPort.new(1)
	var action_economy := FakeActionEconomy.new()

	var use_case := BeginCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(actor, "fire_bolt", catalog, pool, action_economy)

	assert_false(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_INSUFFICIENT_ENERGY)
	assert_null(result.get("casting_state"))

	assert_false(actor.is_casting(), "no casting_state must be set on a failed reservation")
	assert_eq(actor.casting_state, {}, "casting_state must remain untouched")
	assert_eq(action_economy.spend_calls.size(), 0, "no action may be spent when the energy reservation fails")
	assert_eq(pool.balance("marigold_1"), 1, "a failed reservation must leave the pool balance untouched")


func test_execute_unknown_spell_id_returns_not_castable_without_reserving() -> void:
	var actor = _caster(["fire_bolt"])
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt(0)
	var pool := FakeRoundEnergyPoolPort.new(5)

	var use_case := BeginCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(actor, "fireball", catalog, pool)

	assert_false(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_NOT_CASTABLE)
	assert_null(result.get("casting_state"))
	assert_true(pool.reserve_calls.is_empty(), "an unknown/not-known spell_id must never even attempt a reservation")
	assert_false(actor.is_casting())
