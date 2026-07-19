extends GutTest
## tests/unit/test_spell_catalog.gd
##
## GUT suite for FEAT-001 (US-002; FR-011, FR-013 data half): the authored
## Fire Bolt / Channel spell data (core/resources/spell_resource.gd
## SpellResource + data/spells/fire_bolt.tres / channel.tres) and
## core/adapters/resource_spell_catalog_adapter.gd's
## ResourceSpellCatalogAdapter, which maps a loaded SpellResource into a
## core/domain/spell.gd Spell domain value object.
##
## Verifies (test_criteria):
##   1. Fire Bolt resource: actions_cost=2, energy_cost=0, defense=REFLEX,
##      range_ft=50, damage_formula='2d8+ATTR', damage_type='fire'.
##   2. Channel resource: actions_cost=1, energy_cost=0, traits contains
##      'Concentrate', effect_type=ADD_ENERGY, effect_params.amount=1.
##   3. ResourceSpellCatalogAdapter.get_spell('fire_bolt') and
##      get_spell('channel') return correctly-populated Spell domain
##      objects.

const SpellClass = preload("res://core/domain/spell.gd")
const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")
const ResourceSpellCatalogAdapterClass = preload("res://core/adapters/resource_spell_catalog_adapter.gd")

const FIRE_BOLT_PATH: String = "res://data/spells/fire_bolt.tres"
const CHANNEL_PATH: String = "res://data/spells/channel.tres"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: Fire Bolt SpellResource authoring data
# ══════════════════════════════════════════════════════════════════════════

func test_fire_bolt_resource_fields() -> void:
	var fire_bolt = ResourceLoader.load(FIRE_BOLT_PATH)
	assert_not_null(fire_bolt, "fire_bolt.tres must load")
	assert_eq(fire_bolt.spell_id, "fire_bolt")
	assert_eq(fire_bolt.actions_cost, 2)
	assert_eq(fire_bolt.energy_cost, 0)
	assert_eq(fire_bolt.defense, SpellClass.Defense.REFLEX)
	assert_eq(fire_bolt.range_ft, 50)
	assert_eq(fire_bolt.damage_formula, "2d8+ATTR")
	assert_eq(fire_bolt.damage_type, "fire")
	assert_true(fire_bolt.is_valid(), "fire_bolt.tres must satisfy SpellResource load-time invariants")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: Channel SpellResource authoring data
# ══════════════════════════════════════════════════════════════════════════

func test_channel_resource_fields() -> void:
	var channel = ResourceLoader.load(CHANNEL_PATH)
	assert_not_null(channel, "channel.tres must load")
	assert_eq(channel.spell_id, "channel")
	assert_eq(channel.actions_cost, 1)
	assert_eq(channel.energy_cost, 0)
	assert_true(channel.traits.has("Concentrate"), "channel.tres traits must contain 'Concentrate'")
	assert_eq(channel.effect_type, EffectKindClass.ADD_ENERGY)
	assert_eq(channel.effect_params.get("amount"), 1)
	assert_true(channel.is_valid(), "channel.tres must satisfy SpellResource load-time invariants")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: ResourceSpellCatalogAdapter maps SpellResource -> Spell
# ══════════════════════════════════════════════════════════════════════════

func test_adapter_get_spell_fire_bolt_returns_populated_spell() -> void:
	var adapter := ResourceSpellCatalogAdapterClass.new()
	var spell = adapter.get_spell("fire_bolt")
	assert_not_null(spell, "get_spell('fire_bolt') must return a Spell")
	assert_true(spell is SpellClass, "get_spell('fire_bolt') must return a Spell domain object")
	assert_eq(spell.spell_id, "fire_bolt")
	assert_eq(spell.spell_name, "Fire Bolt")
	assert_eq(spell.actions_cost, 2)
	assert_eq(spell.energy_cost, 0)
	assert_eq(spell.defense, SpellClass.Defense.REFLEX)
	assert_eq(spell.range_ft, 50)
	assert_eq(spell.damage_formula, "2d8+ATTR")
	assert_eq(spell.damage_type, "fire")
	assert_eq(spell.effect_type, EffectKindClass.DAMAGE)


func test_adapter_get_spell_channel_returns_populated_spell() -> void:
	var adapter := ResourceSpellCatalogAdapterClass.new()
	var spell = adapter.get_spell("channel")
	assert_not_null(spell, "get_spell('channel') must return a Spell")
	assert_true(spell is SpellClass, "get_spell('channel') must return a Spell domain object")
	assert_eq(spell.spell_id, "channel")
	assert_eq(spell.spell_name, "Channel")
	assert_eq(spell.actions_cost, 1)
	assert_eq(spell.energy_cost, 0)
	assert_true(spell.has_trait("Concentrate"), "Channel Spell must carry the Concentrate trait")
	assert_eq(spell.effect_type, EffectKindClass.ADD_ENERGY)
	assert_eq(spell.effect_params.get("amount"), 1)


func test_adapter_get_spell_unknown_id_returns_null() -> void:
	var adapter := ResourceSpellCatalogAdapterClass.new()
	var spell = adapter.get_spell("does_not_exist")
	assert_null(spell, "get_spell() for an unknown spell_id must return null")
