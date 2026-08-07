extends GutTest
## tests/unit/data/test_gram_marx_fireball_grant.gd — FEAT-004 (US-006;
## FR-006)
##
## Guards the data-only grant of Fireball to Gram Marx
## (data/characters/gram_marx.tres): 'fireball' is added to
## known_spell_ids, and the change is minimal-diff (RISK-008) — Gram
## Marx's effective energy capacity (Combatant.spellcasting_attribute_score,
## resolved by infrastructure/combatant_factory.gd's CombatantFactory from
## his Wizard class_ref.spellcasting_attribute == "intellect" and his own
## authored intellect attribute) is already 5 (>= 2), so this feature must
## NOT touch gram_marx.tres's `attributes` dict at all — the minimal-diff
## rule only raises capacity when the pre-change value is BELOW 2.
##
## Mirrors tests/unit/test_caster_combatant_factory.gd's established
## "load the real .tres via ResourceLoader, then hydrate through the real
## CombatantFactory" convention (no synthetic in-memory CharacterResource),
## and tests/unit/test_spell_action_controller_skeleton.gd's
## "FakeSession double satisfying current_actor_entity()" convention for
## exercising SpellActionController without a full MainScene boot.
##
## test_criteria covered:
##   1. known_spell_ids on gram_marx.tres contains 'fireball'
##   2. energy_capacity change diff is minimal (raised only if pre-change
##      value was <2; unchanged if already >=2) — gram_marx.tres's
##      authored `attributes.intellect` (the source of his resolved
##      spellcasting capacity) stays at its pre-existing value of 5.
##   3. CharacterFactory-hydrated Gram Marx Combatant.known_spell_ids
##      includes 'fireball'
##   4. SpellActionController.availability(fireball_spell,
##      gram_marx_combatant) returns true when energy_current>=2

const CombatantFactoryClass       = preload("res://infrastructure/combatant_factory.gd")
const CombatantClass              = preload("res://core/domain/combatant.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")
const RoundEnergyPoolPortClass    = preload("res://core/application/ports/round_energy_pool_port.gd")
const SpellActionControllerClass  = preload("res://presentation/verbs/spell_action_controller.gd")
const RoundSessionHolderClass     = preload("res://infrastructure/round_session_holder.gd")
const ResourceSpellCatalogAdapterClass = preload("res://core/adapters/resource_spell_catalog_adapter.gd")

const GRAM_MARX_PATH: String = "res://data/characters/gram_marx.tres"


## FakeEnergyPool — a minimal duck-typed double exposing ONLY the `current`
## field core/application/ports/round_energy_pool_port.gd's
## SessionEnergyPoolAdapter.balance()/reserve() read (via
## `_session.get_energy_pool(_caster).current`) — mirrors
## tests/unit/test_begin_cast_use_case.gd's established "small duck-typed
## port double, no real RoundSession" convention.
class FakeEnergyPool:
	extends RefCounted
	var current: int

	func _init(p_current: int) -> void:
		current = p_current


## FakeSession — the SAME minimal current_actor_entity()/get_energy_pool()
## double tests/unit/test_spell_action_controller_skeleton.gd's FakeSession
## establishes, extended with get_energy_pool() so
## SpellActionController._round_energy_pool_port() resolves a REAL
## SessionEnergyPoolAdapter instead of degrading to the FEAT-004 skeleton
## fallback (see that file's own "fail-safe degrade" doc).
class FakeSession:
	extends RefCounted
	var _actor
	var _pool: FakeEnergyPool

	func _init(actor, starting_energy_current: int) -> void:
		_actor = actor
		_pool = FakeEnergyPool.new(starting_energy_current)

	func current_actor():
		return {} if _actor == null else {"combatant_id": _actor.combatant_id}

	func current_actor_entity():
		return _actor

	func current_action_economy():
		return null

	func get_energy_pool(_caster):
		return _pool


func _load_gram_marx_character():
	return ResourceLoader.load(GRAM_MARX_PATH)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: known_spell_ids on gram_marx.tres contains 'fireball'
# ══════════════════════════════════════════════════════════════════════════

func test_gram_marx_resource_known_spell_ids_contains_fireball() -> void:
	var character = _load_gram_marx_character()
	assert_not_null(character, "gram_marx.tres must load")
	if character == null:
		return

	assert_true(
		character.known_spell_ids.has("fireball"),
		"gram_marx.tres known_spell_ids must contain 'fireball', got: %s" % [character.known_spell_ids]
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: energy_capacity change diff is minimal
# ══════════════════════════════════════════════════════════════════════════

func test_gram_marx_intellect_unchanged_since_already_at_or_above_capacity_floor() -> void:
	# fixture assumption: Gram Marx is a Wizard (spellcasting_attribute ==
	# "intellect") whose pre-existing authored intellect was already 5 (>=
	# 2) — RISK-008's minimal-diff rule therefore forbids this feature from
	# touching `attributes` at all.
	var character = _load_gram_marx_character()
	assert_not_null(character, "gram_marx.tres must load")
	if character == null:
		return

	assert_eq(
		character.class_ref.spellcasting_attribute, "intellect",
		"fixture assumption: gram_marx's class_ref (wizard) spellcasting_attribute must be 'intellect'"
	)
	assert_eq(
		int(character.attributes.get("intellect", -1)), 5,
		"gram_marx.tres's authored intellect must remain unchanged at 5 -- minimal-diff rule forbids raising an already->=2 capacity"
	)


func test_gram_marx_resolved_energy_capacity_is_at_least_two() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_0")
	assert_false(combatant.has("error"), "fixture assumption: gram_marx.tres must build a valid combatant with no error")

	assert_true(
		int(combatant.get("spellcasting_attribute_score", -1)) >= 2,
		"gram_marx's resolved spellcasting_attribute_score (energy capacity) must be >= 2, got: %s" % [combatant.get("spellcasting_attribute_score")]
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: CharacterFactory-hydrated Combatant.known_spell_ids includes
# 'fireball'
# ══════════════════════════════════════════════════════════════════════════

func test_gram_marx_hydrated_combatant_known_spell_ids_includes_fireball() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant_dict: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, HexCoordClass.new(0, 0), "gram_marx_0")
	assert_false(combatant_dict.has("error"), "fixture assumption: gram_marx.tres must build a valid combatant with no error")

	var combatant := CombatantClass.from_dict(combatant_dict)

	assert_true(
		combatant.known_spell_ids.has("fireball"),
		"CombatantFactory-hydrated Gram Marx Combatant.known_spell_ids must include 'fireball', got: %s" % [combatant.known_spell_ids]
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: SpellActionController.availability(fireball_spell,
# gram_marx_combatant) returns true when energy_current>=2
# ══════════════════════════════════════════════════════════════════════════

func _build_gram_marx_combatant() -> CombatantClass:
	var factory := CombatantFactoryClass.new()
	var combatant_dict: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, HexCoordClass.new(0, 0), "gram_marx_0")
	return CombatantClass.from_dict(combatant_dict)


func test_availability_true_for_gram_marx_when_energy_current_is_two() -> void:
	var actor := _build_gram_marx_combatant()
	assert_true(actor.known_spell_ids.has("fireball"), "fixture assumption: hydrated Gram Marx must know fireball")

	var adapter := ResourceSpellCatalogAdapterClass.new()
	var fireball_spell = adapter.get_spell("fireball")
	assert_not_null(fireball_spell, "fixture assumption: fireball must resolve through the real spell catalog")
	assert_eq(fireball_spell.energy_cost, 2, "fixture assumption: fireball's energy_cost must be 2")

	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(actor, 2))
	var controller := SpellActionControllerClass.new({"session_holder": holder})

	assert_true(
		controller.availability(),
		"SpellActionController.availability() must return true for Gram Marx when energy_current (2) >= fireball's energy_cost (2)"
	)


func test_availability_false_for_gram_marx_when_energy_current_is_zero_and_no_other_castable_source() -> void:
	# Sanity/contrast case: with the round energy pool balance at 0 and no
	# charged item preparing a spell, Gram Marx must NOT be available to
	# cast (guards against a vacuously-true availability() implementation).
	var actor := _build_gram_marx_combatant()
	# Strip the Mage-paradigm item-discharge path so this assertion isolates
	# the Channeler (known_spell_ids + pool) path exactly.
	actor.equipped_items = []

	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(actor, 0))
	var controller := SpellActionControllerClass.new({"session_holder": holder})

	assert_false(
		controller.availability(),
		"SpellActionController.availability() must return false for Gram Marx when the round energy pool balance is 0 and no item is charged"
	)
