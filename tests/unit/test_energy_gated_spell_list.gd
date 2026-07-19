extends GutTest
## tests/unit/test_energy_gated_spell_list.gd — FEAT-278 (US-013; FR-014)
##
## GUT suite for:
##   - data/spells/fireball.tres (this feature's new authored SpellResource,
##     energy_cost=2 -- "min energy 2" per the source spell card) and
##     core/adapters/resource_spell_catalog_adapter.gd's
##     ResourceSpellCatalogAdapter mapping it into a Spell domain object --
##     mirrors tests/unit/test_spell_catalog.gd's established convention for
##     Fire Bolt/Channel.
##   - core/application/use_cases/begin_cast_use_case.gd's new
##     BeginCastUseCase.castable_spell_ids() -- the energy-gated PICK LIST
##     filtering known_spell_ids by round energy pool balance.
##   - presentation/verbs/spell_action_controller.gd's SpellActionController
##     .enter_selection(), wiring castable_spell_ids() into candidate_targets
##     against a REAL (not all-mocked) session double exposing
##     get_energy_pool(), confirming Fireball is never offered as castable at
##     L1 through the full controller-level path (this feature's "boot-real/
##     unit test" criterion).
##
## test_criteria covered:
##   1. Unit test confirms Fireball is excluded from the castable pick list
##      when pool balance < 2.
##   2. Boot-real/unit test confirms Fireball spell data authors correctly
##      (energy_cost=2) but is never offered as castable at L1.

const SpellClass                       = preload("res://core/domain/spell.gd")
const EffectKindClass                  = preload("res://core/domain/effects/effect_kind.gd")
const ResourceSpellCatalogAdapterClass = preload("res://core/adapters/resource_spell_catalog_adapter.gd")
const BeginCastUseCaseClass            = preload("res://core/application/use_cases/begin_cast_use_case.gd")
const CombatantClass                   = preload("res://core/domain/combatant.gd")
const HexCoordClass                    = preload("res://core/geometry/hex_coord.gd")
const EnergyPoolClass                  = preload("res://core/domain/energy_pool.gd")
const SpellActionControllerClass       = preload("res://presentation/verbs/spell_action_controller.gd")
const RoundSessionHolderClass          = preload("res://infrastructure/round_session_holder.gd")

const FIREBALL_PATH: String = "res://data/spells/fireball.tres"


## FakeSpellCatalogPort — duck-typed SpellCatalogPort double, mirrors
## tests/unit/test_begin_cast_use_case.gd's own fake: a plain spell_id ->
## Spell Dictionary lookup, no ResourceLoader/.tres involved.
class FakeSpellCatalogPort:
	extends RefCounted
	var spells: Dictionary = {}

	func get_spell(spell_id: String):
		return spells.get(spell_id, null)


## FakeRoundEnergyPoolPort — duck-typed RoundEnergyPoolPort double, mirrors
## tests/unit/test_begin_cast_use_case.gd's own fake: a single in-memory
## balance.
class FakeRoundEnergyPoolPort:
	extends RefCounted
	var _balance: int

	func _init(starting_balance: int) -> void:
		_balance = starting_balance

	func reserve(_caster_id: String, amount: int) -> bool:
		if _balance < amount:
			return false
		_balance -= amount
		return true

	func balance(_caster_id: String) -> int:
		return _balance


## FakeSession — mirrors tests/unit/test_resolve_spell_controller_targeting.gd's
## own FakeSession: a small, real (not all-mocked) double exposing
## get_energy_pool(caster), so SpellActionController.enter_selection() drives
## its REAL BeginCastUseCase.castable_spell_ids() path end-to-end.
##
## `pool_balance` seeds the pool's CURRENT (already-banked) energy directly
## -- mirroring how a real RoundSession pool only ever holds energy banked
## via a prior Channel (ADD_ENERGY) cast this round (capacity alone, with a
## freshly-created pool's current always starting at 0, would never actually
## exercise the "affordable" branch of the filter).
class FakeSession:
	var _actor
	var _pool_balance: int
	var _pools: Dictionary = {}

	func _init(actor, pool_balance: int) -> void:
		_actor = actor
		_pool_balance = pool_balance

	func current_actor():
		return {} if _actor == null else {"combatant_id": _actor.combatant_id}

	func current_actor_entity():
		return _actor

	func current_action_economy():
		return null

	func get_energy_pool(caster):
		var key: String = caster.display_id()
		if not _pools.has(key):
			_pools[key] = EnergyPoolClass.new(_pool_balance, _pool_balance)
		return _pools[key]


func _caster(known_spell_ids: Array) -> CombatantClass:
	var c := CombatantClass.new("marigold_1", "Marigold", "Player", HexCoordClass.new(0, 0))
	c.known_spell_ids = known_spell_ids
	return c


func _fireball(energy_cost: int = 2) -> SpellClass:
	return SpellClass.new("fireball", "Fireball", 2, energy_cost, SpellClass.Defense.REFLEX, 100, "3d6+ATTR", "fire", ["Concentrate"])


func _fire_bolt(energy_cost: int = 0) -> SpellClass:
	return SpellClass.new("fire_bolt", "Fire Bolt", 2, energy_cost, SpellClass.Defense.REFLEX, 50, "2d8+ATTR", "fire", [])


# ══════════════════════════════════════════════════════════════════════════
# Fireball SpellResource authoring data (data/spells/fireball.tres)
# ══════════════════════════════════════════════════════════════════════════

func test_fireball_resource_fields() -> void:
	var fireball = ResourceLoader.load(FIREBALL_PATH)
	assert_not_null(fireball, "fireball.tres must load")
	assert_eq(fireball.spell_id, "fireball")
	assert_eq(fireball.actions_cost, 2)
	assert_eq(fireball.energy_cost, 2, "Fireball's min energy is 2 per the source spell card")
	assert_eq(fireball.defense, SpellClass.Defense.REFLEX)
	assert_eq(fireball.range_ft, 100)
	assert_eq(fireball.damage_type, "fire")
	assert_true(fireball.traits.has("Concentrate"), "fireball.tres traits must contain 'Concentrate'")
	assert_eq(fireball.effect_type, EffectKindClass.DAMAGE)
	assert_true(fireball.is_valid(), "fireball.tres must satisfy SpellResource load-time invariants")


func test_adapter_get_spell_fireball_returns_populated_spell() -> void:
	var adapter := ResourceSpellCatalogAdapterClass.new()
	var spell = adapter.get_spell("fireball")

	assert_not_null(spell, "get_spell('fireball') must return a Spell")
	assert_true(spell is SpellClass, "get_spell('fireball') must return a Spell domain object")
	assert_eq(spell.spell_id, "fireball")
	assert_eq(spell.spell_name, "Fireball")
	assert_eq(spell.actions_cost, 2)
	assert_eq(spell.energy_cost, 2)
	assert_eq(spell.defense, SpellClass.Defense.REFLEX)
	assert_eq(spell.range_ft, 100)
	assert_eq(spell.damage_type, "fire")
	assert_true(spell.has_trait("Concentrate"))
	assert_eq(spell.effect_type, EffectKindClass.DAMAGE)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: BeginCastUseCase.castable_spell_ids() energy-gates the pick
# list (unit-level, fake ports).
# ══════════════════════════════════════════════════════════════════════════

func test_castable_spell_ids_excludes_fireball_when_pool_balance_below_min_energy() -> void:
	var actor = _caster(["fire_bolt", "fireball"])
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt(0)
	catalog.spells["fireball"] = _fireball(2)
	var pool := FakeRoundEnergyPoolPort.new(1)

	var use_case := BeginCastUseCaseClass.new()
	var castable: Array = use_case.castable_spell_ids(actor, catalog, pool)

	assert_true(castable.has("fire_bolt"), "Fire Bolt (energy_cost=0) must remain castable at any pool balance")
	assert_false(castable.has("fireball"), "Fireball (energy_cost=2) must be excluded when pool balance (1) < 2")


func test_castable_spell_ids_excludes_fireball_when_pool_balance_is_zero() -> void:
	var actor = _caster(["fire_bolt", "fireball"])
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt(0)
	catalog.spells["fireball"] = _fireball(2)
	var pool := FakeRoundEnergyPoolPort.new(0)

	var use_case := BeginCastUseCaseClass.new()
	var castable: Array = use_case.castable_spell_ids(actor, catalog, pool)

	assert_eq(castable, ["fire_bolt"], "at pool balance 0, only Fire Bolt is castable -- Fireball must not appear anywhere in the list")


func test_castable_spell_ids_includes_fireball_once_pool_balance_reaches_min_energy() -> void:
	var actor = _caster(["fire_bolt", "fireball"])
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt(0)
	catalog.spells["fireball"] = _fireball(2)
	var pool := FakeRoundEnergyPoolPort.new(2)

	var use_case := BeginCastUseCaseClass.new()
	var castable: Array = use_case.castable_spell_ids(actor, catalog, pool)

	assert_true(castable.has("fireball"), "Fireball must be offered once the pool balance meets its min energy (2)")


func test_castable_spell_ids_fails_safe_to_empty_array_with_no_ports() -> void:
	var actor = _caster(["fire_bolt"])
	var use_case := BeginCastUseCaseClass.new()

	assert_eq(use_case.castable_spell_ids(null, null, null), [], "a null actor/ports must fail safe to an empty Array, never crash")
	assert_eq(use_case.castable_spell_ids(actor, null, null), [], "missing ports must fail safe to an empty Array")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: boot-real/unit test — Fireball is never offered as castable
# at L1 through the full SpellActionController.enter_selection() path.
# ══════════════════════════════════════════════════════════════════════════

func test_enter_selection_never_offers_fireball_at_l1_pool_capacity() -> void:
	# An L1 Channeling pool balance of 1 mirrors the spec's "prepared/
	# channeled energy budget at Level 1 is well below Fireball's min energy
	# of 2" (docs/iterations/iteration-M-cast-a-spell.org: "NO Fireball
	# castable at L1 (min energy 2 > L1 budget) — data only.").
	var actor = _caster(["fire_bolt", "channel", "fireball"])
	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(actor, 1))
	var controller := SpellActionControllerClass.new({"session_holder": holder})

	var selection: Dictionary = controller.enter_selection()

	assert_eq(selection.get("verb_id"), "CAST_SPELL")
	assert_true(selection.get("candidate_options", []).any(func(o): return o.get("id") == "fire_bolt"), "Fire Bolt must still be offered at L1")
	assert_true(selection.get("candidate_options", []).any(func(o): return o.get("id") == "channel"), "Channel must still be offered at L1")
	assert_false(selection.get("candidate_options", []).any(func(o): return o.get("id") == "fireball"), "Fireball must NEVER be offered as castable at L1 (min energy 2 > L1 pool budget)")


func test_enter_selection_offers_fireball_once_pool_balance_is_sufficient() -> void:
	# Sanity check on the OTHER side of the gate: the filter is genuinely
	# energy-driven, not a hardcoded Fireball exclusion -- once the live
	# pool's balance meets Fireball's min energy, it IS offered.
	var actor = _caster(["fireball"])
	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(actor, 2))
	var controller := SpellActionControllerClass.new({"session_holder": holder})

	var selection: Dictionary = controller.enter_selection()

	assert_true(selection.get("candidate_options", []).any(func(o): return o.get("id") == "fireball"), "Fireball must be offered once the live pool balance meets its min energy (2)")


func test_enter_selection_degrades_to_empty_candidates_with_no_live_session() -> void:
	# Fail-safe degrade (file-level doc on spell_action_controller.gd): no
	# live session/actor at all must never crash and must keep the FEAT-004
	# skeleton shape.
	var holder := RoundSessionHolderClass.new()
	var controller := SpellActionControllerClass.new({"session_holder": holder})

	var selection: Dictionary = controller.enter_selection()

	assert_eq(selection.get("verb_id"), "CAST_SPELL")
	assert_eq(selection.get("candidate_options"), [], "no live session must still fail safe to empty candidate_options, never crash")
