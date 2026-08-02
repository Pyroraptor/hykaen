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
const EffectKindClass        = preload("res://core/domain/effects/effect_kind.gd")


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


## FakeEquippedItem — FEAT-006 (US-005; FR-008): a duck-typed equipped-item
## double, deliberately NOT core/resources/item_resource.gd's ItemResource
## (an adapter/infrastructure Resource type) — mirrors this project's
## established "fake, duck-typed... no adapter" convention (file header)
## exactly. Exposes only the two fields castable_spell_ids()'s
## BeginCastUseCase._duck_get() reads: `prepared_spell_id`/`is_charged`.
class FakeEquippedItem:
	extends RefCounted
	var prepared_spell_id: String = ""
	var is_charged: bool = false

	func _init(p_prepared_spell_id: String = "", p_is_charged: bool = false) -> void:
		prepared_spell_id = p_prepared_spell_id
		is_charged = p_is_charged


func _caster(known_spell_ids: Array = ["fire_bolt"]):
	var c := CombatantClass.new("marigold_1", "Marigold", "Player", HexCoordClass.new(0, 0))
	c.known_spell_ids = known_spell_ids
	return c


## FakeItemUserActor — FEAT-006 (US-005; FR-008): a duck-typed actor double
## exposing exactly the surface castable_spell_ids() reads off `actor`
## (`known_spell_ids`, `display_id()`, and — unlike core/domain/combatant.gd's
## Combatant, which carries no such field yet; only infrastructure/
## combatant_factory.gd's OUTPUT DICTIONARY does, FEAT-005 — a REAL,
## declared `equipped_items` property, so `Object.get("equipped_items")`
## resolves it rather than falling back to `_duck_get()`'s default). Stands
## in for the steel thread's item-user caster, Gram Marx (Wizard,
## `known_spell_ids == []`, casts entirely through equipped implements) —
## mirrors this file's own established "fake, duck-typed... no adapter"
## convention (header doc) exactly, matching FakeSpellCatalogPort/
## FakeRoundEnergyPoolPort/FakeActionEconomy above.
##
## FEAT-007 (US-006; FR-009, ADR-006) additionally exercises this double
## through BeginCastUseCase.execute()'s SUCCESS path (not just
## castable_spell_ids()), which -- on a charged item-prepared spell or an
## innate known spell -- calls `actor.begin_cast()`/reads `actor.casting_state`
## exactly as it does on a real core/domain/combatant.gd Combatant. `casting_state`/
## `is_casting()`/`begin_cast()` below mirror Combatant's own identically-named
## members verbatim (Combatant.begin_cast(): "var state :=
## CastingStateClass.new(spell_id, actions_cost - 1, committed_energy,
## display_id()); casting_state = state.to_dict()") so this fake satisfies
## execute()'s full contract, not just castable_spell_ids()'s narrower one.
class FakeItemUserActor:
	extends RefCounted
	var known_spell_ids: Array = []
	var equipped_items: Array = []
	var casting_state: Dictionary = {}
	var _combatant_id: String

	func _init(combatant_id: String, p_known_spell_ids: Array = [], p_equipped_items: Array = []) -> void:
		_combatant_id = combatant_id
		known_spell_ids = p_known_spell_ids
		equipped_items = p_equipped_items

	func display_id() -> String:
		return _combatant_id

	func is_casting() -> bool:
		return not casting_state.is_empty()

	func begin_cast(spell_id: String, actions_cost: int, committed_energy: int) -> void:
		var state := CastingStateClass.new(spell_id, actions_cost - 1, committed_energy, display_id())
		casting_state = state.to_dict()


## _gram_marx_combatant(equipped_items) -> FakeItemUserActor — the steel
## thread's own named scenario actor (AA-3-1's "Gram Marx" caster), a
## known-spell-less item-user whose only castable spells come from
## `equipped_items`.
func _gram_marx_combatant(equipped_items: Array = []) -> FakeItemUserActor:
	return FakeItemUserActor.new("gram_marx_1", [], equipped_items)


func _fire_bolt(energy_cost: int = 2, actions_cost: int = 2) -> SpellClass:
	return SpellClass.new("fire_bolt", "Fire Bolt", actions_cost, energy_cost, SpellClass.Defense.REFLEX, 50, "2d8+ATTR", "fire", [])


func _frost_breath(energy_cost: int = 1) -> SpellClass:
	return SpellClass.new("frost_breath", "Frost Breath", 2, energy_cost, SpellClass.Defense.FORTITUDE, 30, "2d6+ATTR", "cold", ["Concentrate"], EffectKindClass.DAMAGE, {}, "dazed")


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


# ══════════════════════════════════════════════════════════════════════════
# FEAT-007 (US-006; FR-009, ADR-006) — secondary charge-state guard
# ══════════════════════════════════════════════════════════════════════════

func test_execute_uncharged_item_prepared_spell_returns_invalid_state_without_reserving() -> void:
	var orb_gram := FakeEquippedItem.new("frost_breath", false)
	var actor := _gram_marx_combatant([orb_gram])
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["frost_breath"] = _frost_breath(1)
	var pool := FakeRoundEnergyPoolPort.new(5)
	var action_economy := FakeActionEconomy.new()

	var use_case := BeginCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(actor, "frost_breath", catalog, pool, action_economy)

	assert_false(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_INVALID_STATE, "an item-prepared spell whose item.is_charged==false must be rejected as ERR_INVALID_STATE")
	assert_null(result.get("casting_state"))
	assert_true(pool.reserve_calls.is_empty(), "an uncharged item-prepared spell must never even attempt an energy reservation")
	assert_eq(action_economy.spend_calls.size(), 0, "no action may be spent when the charge-state guard rejects the cast")


func test_execute_charged_item_prepared_spell_succeeds() -> void:
	var orb_gram := FakeEquippedItem.new("frost_breath", true)
	var actor := _gram_marx_combatant([orb_gram])
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["frost_breath"] = _frost_breath(1)
	var pool := FakeRoundEnergyPoolPort.new(5)
	var action_economy := FakeActionEconomy.new()

	var use_case := BeginCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(actor, "frost_breath", catalog, pool, action_economy)

	assert_true(result.get("success"), "a charged item-prepared spell must be castable")
	assert_eq(result.get("error"), ErrorCodeClass.NONE)
	# Mage paradigm: energy comes from the item's discharge, not the pool.
	assert_eq(pool.balance("gram_marx_1"), 5, "item-prepared (Mage) spell energy comes from the item — the round pool must NOT be debited")
	assert_eq(action_economy.spend_calls.size(), 1)


func test_execute_innate_known_spell_unaffected_by_charge_state_guard() -> void:
	# A known (non-item) spell must never be gated by the new charge-state
	# guard, even for an actor that also happens to carry an uncharged item
	# whose prepared_spell_id differs from the requested spell_id.
	var orb_gram := FakeEquippedItem.new("frost_breath", false)
	var actor := FakeItemUserActor.new("marigold_1", ["fire_bolt"], [orb_gram])
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt(2, 2)
	catalog.spells["frost_breath"] = _frost_breath(1)
	var pool := FakeRoundEnergyPoolPort.new(5)

	var use_case := BeginCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(actor, "fire_bolt", catalog, pool)

	assert_true(result.get("success"), "an innate known spell must be unaffected by the item charge-state guard")
	assert_eq(result.get("error"), ErrorCodeClass.NONE)


func test_castable_spell_ids_and_execute_round_trip_for_uncharged_item_prepared_spell() -> void:
	# Incremental smoke check (test_criteria #4): an uncharged item-prepared
	# spell must be BOTH excluded from castable_spell_ids() AND blocked on a
	# direct execute() attempt -- the two surfaces must agree.
	var orb_gram := FakeEquippedItem.new("frost_breath", false)
	var actor := _gram_marx_combatant([orb_gram])
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["frost_breath"] = _frost_breath(1)
	var pool := FakeRoundEnergyPoolPort.new(5)

	var use_case := BeginCastUseCaseClass.new()

	var castable: Array = use_case.castable_spell_ids(actor, catalog, pool)
	assert_false(castable.has("frost_breath"), "an uncharged item-prepared spell must not appear in the castable pick list")

	var result: Dictionary = use_case.execute(actor, "frost_breath", catalog, pool)
	assert_false(result.get("success"), "the same uncharged item-prepared spell must also be blocked on direct execute()")
	assert_eq(result.get("error"), ErrorCodeClass.ERR_INVALID_STATE)


# ══════════════════════════════════════════════════════════════════════════
# FEAT-008 (US-009; FR-013, RISK-007) — regression-protect free-cast innate
# spell behavior against the FEAT-007 item-charge gate. Mirrors
# tests/unit/core/application/test_castable_spell_ids_regression.gd's
# broader multi-fixture snapshot suite; this file's own narrower, fully
# fake-port version pins the exact "0-cost/innate spell, no equipped items
# at all" shape Marigold's real fire_bolt cast exercises (real fire_bolt.tres
# has energy_cost == 0), so a future change to the charge-state guard's
# `is_known` short-circuit (execute(), above) cannot silently regress the
# single most common cast in the game.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_zero_cost_innate_spell_with_no_equipped_items_unaffected_by_charge_state_guard() -> void:
	var actor = _caster(["fire_bolt"])
	assert_eq(_duck_get_equipped_items_for_test(actor), [], "fixture assumption: a plain Combatant carries no equipped_items at all -- the FEAT-007 guard's _find_item_preparing() must never even be reached for this actor")

	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt(0, 2)
	var pool := FakeRoundEnergyPoolPort.new(5)
	var action_economy := FakeActionEconomy.new()

	var use_case := BeginCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(actor, "fire_bolt", catalog, pool, action_economy)

	assert_true(result.get("success"), "a 0-cost/innate known spell with no equipped items must cast identically pre- and post-FEAT-007")
	assert_eq(result.get("error"), ErrorCodeClass.NONE, "no ERR_INVALID_STATE regression for a 0-cost/innate spell")
	assert_eq(pool.balance("marigold_1"), 5, "a 0-cost spell must reserve exactly 0 energy from the round pool")
	assert_eq(action_economy.spend_calls.size(), 1)


## _duck_get_equipped_items_for_test(actor) -> Array — a plain Combatant
## (core/domain/combatant.gd) declares no `equipped_items` field, so
## `Object.get("equipped_items")` resolves to null; this local helper
## mirrors that exact read (never the production _duck_get(), which is a
## private method on BeginCastUseCase) purely to make the fixture assumption
## above self-documenting.
func _duck_get_equipped_items_for_test(actor) -> Array:
	var value = actor.get("equipped_items")
	return [] if value == null else value
