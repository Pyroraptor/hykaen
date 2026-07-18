extends GutTest
## tests/unit/test_spell_definition.gd
##
## GUT unit test suite for FEAT-001 (US-002 / FR-008): Author Fire Bolt and
## Channel spell data.
##
## Confirms core/rules/spell_definition.gd hydrates the exact field values
## the design notes' data_model prescribes for both v0 spell fixtures
## (loaded straight from resources/spells/*.tres via ResourceLoader,
## matching the project's established WeaponResource/CharacterResource
## test convention), and that its is_valid()/validation_error() load-time
## invariant (actions>0, energy_cost>=0, range_ft>=0) rejects malformed
## field combinations.

const SpellDefinitionClass = preload("res://core/rules/spell_definition.gd")
const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")


# ══════════════════════════════════════════════════════════════════════════
# Fire Bolt (US-002, FR-008): 2 actions, 0 energy, 50ft, Reflex, 2d8 fire, DAMAGE
# ══════════════════════════════════════════════════════════════════════════

func test_fire_bolt_hydrates_expected_fields() -> void:
	var spell = ResourceLoader.load("res://resources/spells/fire_bolt.tres")
	assert_not_null(spell, "resources/spells/fire_bolt.tres must load")
	if spell == null:
		return
	assert_eq(spell.spell_id, "fire_bolt")
	assert_eq(spell.actions, 2, "Fire Bolt costs 2 actions")
	assert_eq(spell.energy_cost, 0, "Fire Bolt is 0-energy in v0")
	assert_eq(spell.range_ft, 50, "Fire Bolt range is 50ft")
	assert_eq(spell.defense_type, "reflex", "Fire Bolt targets Reflex")
	assert_eq(spell.damage_formula, "2d8")
	assert_eq(spell.damage_type, "fire")
	assert_eq(spell.effect_type, EffectKindClass.DAMAGE)


func test_fire_bolt_has_concentrate_trait() -> void:
	var spell = ResourceLoader.load("res://resources/spells/fire_bolt.tres")
	assert_not_null(spell)
	if spell == null:
		return
	assert_eq(
		spell.spell_trait, "Concentrate",
		"Cast-a-Spell actions are Concentrate-trait (spec line 355) so they provoke Opportunistic Strike like Stride"
	)


func test_fire_bolt_is_valid() -> void:
	var spell = ResourceLoader.load("res://resources/spells/fire_bolt.tres")
	assert_not_null(spell)
	if spell == null:
		return
	assert_true(spell.is_valid())
	assert_eq(spell.validation_error(), "")


# ══════════════════════════════════════════════════════════════════════════
# Channel (US-002, FR-008): 1 action, 0 energy, Concentrate, ADD_ENERGY
# ══════════════════════════════════════════════════════════════════════════

func test_channel_hydrates_expected_fields() -> void:
	var spell = ResourceLoader.load("res://resources/spells/channel.tres")
	assert_not_null(spell, "resources/spells/channel.tres must load")
	if spell == null:
		return
	assert_eq(spell.spell_id, "channel")
	assert_eq(spell.actions, 1, "Channel costs 1 action")
	assert_eq(spell.energy_cost, 0, "Channel is 0-energy")
	assert_eq(spell.spell_trait, "Concentrate")
	assert_eq(spell.effect_type, EffectKindClass.ADD_ENERGY)


func test_channel_is_valid() -> void:
	var spell = ResourceLoader.load("res://resources/spells/channel.tres")
	assert_not_null(spell)
	if spell == null:
		return
	assert_true(spell.is_valid())
	assert_eq(spell.validation_error(), "")


# ══════════════════════════════════════════════════════════════════════════
# Validation invariant — malformed field combinations are rejected
# (design notes' security policy #1: energy_cost>=0, actions>0, range_ft>=0)
# ══════════════════════════════════════════════════════════════════════════

func test_rejects_negative_energy_cost() -> void:
	var spell = SpellDefinitionClass.new()
	spell.spell_id = "bad_energy"
	spell.actions = 1
	spell.energy_cost = -1
	spell.range_ft = 0
	assert_false(spell.is_valid(), "energy_cost < 0 must be invalid")
	assert_true(
		spell.validation_error().find("energy_cost") != -1,
		"validation_error must mention energy_cost, got: %s" % spell.validation_error()
	)


func test_rejects_non_positive_actions() -> void:
	var spell = SpellDefinitionClass.new()
	spell.spell_id = "bad_actions"
	spell.actions = 0
	spell.energy_cost = 0
	spell.range_ft = 0
	assert_false(spell.is_valid(), "actions <= 0 must be invalid")
	assert_true(
		spell.validation_error().find("actions") != -1,
		"validation_error must mention actions, got: %s" % spell.validation_error()
	)


func test_rejects_negative_actions() -> void:
	var spell = SpellDefinitionClass.new()
	spell.spell_id = "bad_actions_neg"
	spell.actions = -2
	spell.energy_cost = 0
	spell.range_ft = 0
	assert_false(spell.is_valid(), "negative actions must be invalid")


func test_rejects_negative_range_ft() -> void:
	var spell = SpellDefinitionClass.new()
	spell.spell_id = "bad_range"
	spell.actions = 1
	spell.energy_cost = 0
	spell.range_ft = -10
	assert_false(spell.is_valid(), "range_ft < 0 must be invalid")
	assert_true(
		spell.validation_error().find("range_ft") != -1,
		"validation_error must mention range_ft, got: %s" % spell.validation_error()
	)


func test_valid_minimal_spell_reports_no_validation_error() -> void:
	var spell = SpellDefinitionClass.new()
	spell.spell_id = "ok"
	spell.actions = 1
	spell.energy_cost = 0
	spell.range_ft = 0
	assert_true(spell.is_valid())
	assert_eq(spell.validation_error(), "")
