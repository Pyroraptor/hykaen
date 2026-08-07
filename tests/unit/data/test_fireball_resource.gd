extends GutTest
## tests/unit/data/test_fireball_resource.gd
##
## GUT test suite for FEAT-002 (US-002/FR-002; ADR-001): guards the
## promotion of data/spells/fireball.tres's area-of-effect radius from
## the legacy denormalized effect_params['radius_ft'] convention to the
## first-class typed area_effect_radius_ft field established by FEAT-001
## on core/resources/spell_resource.gd / core/domain/spell.gd.
##
## Mirrors the established test_spell_fixtures.gd convention: the fixture
## is loaded via the real ResourceLoader.load() path (never constructed
## in-memory) so an authoring mistake in the committed .tres file itself
## is caught here, and is additionally mapped through the real
## ResourceSpellCatalogAdapter (core/adapters/resource_spell_catalog_adapter.gd)
## into the domain core/domain/spell.gd Spell VO built by FEAT-001, since
## FEAT-002's test criteria are phrased in terms of that domain VO's
## behavior (is_area_effect(), area_hex_radius()), not the raw
## SpellResource authoring type.
##
## Test criteria (FEAT-002):
##   - Loaded fireball.tres yields area_effect_radius_ft==20 on the domain
##     Spell VO
##   - is_area_effect() is true and area_hex_radius() returns 4 for the
##     loaded Fireball spell
##   - effect_params dictionary no longer contains 'radius_ft' key
##   - All other pre-existing effect_params keys on fireball.tres are
##     unchanged (diffed against baseline)

const SpellResourceClass = preload("res://core/resources/spell_resource.gd")
const ResourceSpellCatalogAdapterClass = preload("res://core/adapters/resource_spell_catalog_adapter.gd")

const FIREBALL_PATH := "res://data/spells/fireball.tres"

## Baseline effect_params keys/values that existed on fireball.tres BEFORE
## this feature's change, minus the removed 'radius_ft' key. Any other
## pre-existing key (formula, type) must survive unchanged.
const BASELINE_EFFECT_PARAMS := {
	"formula": "3d6+ATTR",
	"type": "fire",
}


# ── Domain Spell VO assertions (via the real adapter seam) ─────────────

func test_fireball_spell_vo_has_area_effect_radius_ft_20() -> void:
	var adapter := ResourceSpellCatalogAdapterClass.new()
	var fireball = adapter.get_spell("fireball")
	assert_not_null(fireball, "ResourceSpellCatalogAdapter.get_spell('fireball') must return a Spell VO")
	if fireball == null:
		return
	assert_eq(fireball.area_effect_radius_ft, 20, "fireball Spell VO area_effect_radius_ft must be 20")


func test_fireball_spell_vo_is_area_effect_and_hex_radius_4() -> void:
	var adapter := ResourceSpellCatalogAdapterClass.new()
	var fireball = adapter.get_spell("fireball")
	assert_not_null(fireball, "ResourceSpellCatalogAdapter.get_spell('fireball') must return a Spell VO")
	if fireball == null:
		return
	assert_true(fireball.is_area_effect(), "fireball Spell VO is_area_effect() must be true")
	assert_eq(fireball.area_hex_radius(), 4, "fireball Spell VO area_hex_radius() must be 4 (20 ft / 5 ft-per-hex)")


# ── Raw SpellResource authoring-file assertions ─────────────────────────

func test_fireball_resource_loads_as_valid_spell_resource() -> void:
	var spell = ResourceLoader.load(FIREBALL_PATH)
	assert_not_null(spell, "ResourceLoader.load('%s') must return non-null" % FIREBALL_PATH)
	if spell == null:
		return
	assert_is(spell, SpellResourceClass, "%s must be a SpellResource" % FIREBALL_PATH)
	assert_true(spell.is_valid(), "%s must be valid: %s" % [FIREBALL_PATH, spell.validation_error()])


func test_fireball_resource_area_effect_radius_ft_field_is_20() -> void:
	var spell = ResourceLoader.load(FIREBALL_PATH)
	assert_not_null(spell, "fireball.tres must load")
	if spell == null:
		return
	assert_eq(spell.area_effect_radius_ft, 20, "fireball.tres area_effect_radius_ft must be 20")


func test_fireball_effect_params_no_longer_contains_radius_ft() -> void:
	var spell = ResourceLoader.load(FIREBALL_PATH)
	assert_not_null(spell, "fireball.tres must load")
	if spell == null:
		return
	assert_false(
		spell.effect_params.has("radius_ft"),
		"fireball.tres effect_params must no longer contain the redundant 'radius_ft' key: %s" % [spell.effect_params]
	)


func test_fireball_effect_params_other_keys_unchanged() -> void:
	var spell = ResourceLoader.load(FIREBALL_PATH)
	assert_not_null(spell, "fireball.tres must load")
	if spell == null:
		return
	for key in BASELINE_EFFECT_PARAMS.keys():
		assert_true(
			spell.effect_params.has(key),
			"fireball.tres effect_params must still contain pre-existing key '%s'" % key
		)
		assert_eq(
			spell.effect_params[key], BASELINE_EFFECT_PARAMS[key],
			"fireball.tres effect_params['%s'] must be unchanged from baseline" % key
		)
	assert_eq(
		spell.effect_params.size(), BASELINE_EFFECT_PARAMS.size(),
		"fireball.tres effect_params must contain exactly the baseline keys (plus removal of 'radius_ft'), got: %s" % [spell.effect_params]
	)
