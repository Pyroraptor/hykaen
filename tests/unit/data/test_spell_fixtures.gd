extends GutTest
## tests/unit/data/test_spell_fixtures.gd
##
## GUT test suite for FEAT-002 (US-002; FR-003, FR-004; AA-1-0 fixture
## table): fixture-loading regression test guarding the data-driven
## SpellResource .tres fixture that feeds the item-prepared-spell steel
## thread's exit-point assertions:
##   data/spells/frost_breath.tres
##
## Mirrors the established test_prologue_item_fixtures.gd /
## test_ranged_weapon_fixtures.gd conventions: the fixture is loaded via
## the existing generic Resource loading path (ResourceLoader.load()) —
## never constructed in-memory — so an authoring mistake in the committed
## .tres file itself (not just in the SpellResource script) is caught
## here, per the design notes' security section ("a malformed .tres
## cannot silently corrupt the cast/discharge/condition chain").
##
## Test criteria (FEAT-002):
##   - frost_breath.tres loads as a valid SpellResource with no load errors
##   - actions_cost==2, energy_cost==1, defense==Spell.Defense.FORTITUDE,
##     range_ft==30, damage_formula=='2d6+ATTR', damage_type=='cold',
##     condition_on_hit=='dazed', effect_type==EffectKind.DAMAGE,
##     traits contains 'Concentrate'

const SpellResourceClass = preload("res://core/resources/spell_resource.gd")
const SpellClass = preload("res://core/domain/spell.gd")
const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")

const FROST_BREATH_PATH := "res://data/spells/frost_breath.tres"


# ── Fixture loads, is a SpellResource, and is valid ────────────────────

func test_frost_breath_loads_as_valid_spell_resource() -> void:
	var spell = ResourceLoader.load(FROST_BREATH_PATH)
	assert_not_null(spell, "ResourceLoader.load('%s') must return non-null" % FROST_BREATH_PATH)
	if spell == null:
		return
	assert_is(spell, SpellResourceClass, "%s must be a SpellResource" % FROST_BREATH_PATH)
	assert_true(spell.is_valid(), "%s must be valid: %s" % [FROST_BREATH_PATH, spell.validation_error()])
	assert_eq(spell.validation_error(), "", "%s validation_error() must be empty" % FROST_BREATH_PATH)


# ── frost_breath field assertions (AA-1-0 fixture table) ───────────────

func test_frost_breath_fields() -> void:
	var spell = ResourceLoader.load(FROST_BREATH_PATH)
	assert_not_null(spell, "frost_breath.tres must load")
	if spell == null:
		return
	assert_eq(spell.spell_id, "frost_breath", "frost_breath.spell_id must be 'frost_breath'")
	assert_eq(spell.actions_cost, 2, "frost_breath.actions_cost must be 2")
	assert_eq(spell.energy_cost, 1, "frost_breath.energy_cost must be 1")
	assert_eq(spell.defense, SpellClass.Defense.FORTITUDE, "frost_breath.defense must be FORTITUDE")
	assert_eq(spell.range_ft, 30, "frost_breath.range_ft must be 30")
	assert_eq(spell.damage_formula, "2d6+ATTR", "frost_breath.damage_formula must be '2d6+ATTR'")
	assert_eq(spell.damage_type, "cold", "frost_breath.damage_type must be 'cold'")
	assert_eq(spell.condition_on_hit, "dazed", "frost_breath.condition_on_hit must be 'dazed'")
	assert_eq(spell.effect_type, EffectKindClass.DAMAGE, "frost_breath.effect_type must be DAMAGE")
	assert_true(spell.traits.has("Concentrate"), "frost_breath.traits must contain 'Concentrate'")
