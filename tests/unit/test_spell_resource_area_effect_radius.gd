extends GutTest
## tests/unit/test_spell_resource_area_effect_radius.gd
##
## GUT test suite for FEAT-001 (US-001; FR-001/ADR-001 part 1): SpellResource
## gains a typed @export var area_effect_radius_ft: int = 0 field, giving AoE
## radius a single source of truth in the persistence layer and replacing the
## previous untyped effect_params['radius_ft'] convention.
##
## Test criteria covered:
##   1. area_effect_radius_ft defaults to 0 on a freshly-constructed
##      SpellResource.
##   2. .tres round-trip serialization (ResourceSaver.save()/
##      ResourceLoader.load()) preserves a non-zero area_effect_radius_ft
##      value.
##   3. Regression: a pre-existing spell .tres file authored WITHOUT the
##      field (e.g. data/spells/fire_bolt.tres) loads fail-safe with
##      area_effect_radius_ft == 0 -- no crash.

const SpellResourceClass = preload("res://core/resources/spell_resource.gd")

const ROUND_TRIP_TRES_PATH := "user://test_spell_resource_area_effect_radius_round_trip.tres"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: defaults to 0 on a freshly-constructed SpellResource
# ══════════════════════════════════════════════════════════════════════════

func test_area_effect_radius_ft_defaults_to_zero() -> void:
	var spell := SpellResourceClass.new()
	assert_eq(spell.area_effect_radius_ft, 0, "area_effect_radius_ft must default to 0")


func test_area_effect_radius_ft_is_typed_as_int() -> void:
	var spell := SpellResourceClass.new()
	assert_eq(typeof(spell.area_effect_radius_ft), TYPE_INT, "area_effect_radius_ft must be typed as int")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: .tres round-trip preserves a non-zero value
# ══════════════════════════════════════════════════════════════════════════

func test_round_trip_save_load_preserves_area_effect_radius_ft() -> void:
	var spell := SpellResourceClass.new()
	spell.spell_id = "test_aoe_spell"
	spell.name = "Test AoE Spell"
	spell.actions_cost = 2
	spell.energy_cost = 2
	spell.range_ft = 100
	spell.area_effect_radius_ft = 20

	var save_err := ResourceSaver.save(spell, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for round-trip fixture")

	# Force a fresh load from disk rather than returning a cached instance.
	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)

	assert_not_null(reloaded, "Round-trip fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.spell_id, "test_aoe_spell", "spell_id must round-trip exactly")
	assert_eq(
		reloaded.area_effect_radius_ft, 20,
		"area_effect_radius_ft must round-trip exactly; got: %d" % reloaded.area_effect_radius_ft
	)

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


func test_round_trip_preserves_default_area_effect_radius_ft_too() -> void:
	# Guard against a save/load path that only preserves non-default values.
	var spell := SpellResourceClass.new()
	spell.spell_id = "test_non_aoe_spell"
	spell.actions_cost = 1
	spell.energy_cost = 0

	var save_err := ResourceSaver.save(spell, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for default-value fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Default-value fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.area_effect_radius_ft, 0, "area_effect_radius_ft must round-trip as default 0")

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: pre-existing .tres files without the field load fail-safe
# ══════════════════════════════════════════════════════════════════════════

func test_pre_existing_fire_bolt_tres_without_field_loads_with_zero_default() -> void:
	# fire_bolt.tres predates area_effect_radius_ft and does not author it;
	# loading must not crash and must fail safe to the non-AoE default.
	var spell = ResourceLoader.load("res://data/spells/fire_bolt.tres")
	assert_not_null(spell, "data/spells/fire_bolt.tres must still load")
	if spell == null:
		return
	assert_eq(
		spell.area_effect_radius_ft, 0,
		"pre-existing fire_bolt.tres (authored without area_effect_radius_ft) must fail-safe to 0"
	)


func test_existing_validity_rules_unaffected_by_area_effect_radius_ft_field() -> void:
	var spell := SpellResourceClass.new()
	spell.spell_id = "unaffected_check"
	spell.actions_cost = 1
	spell.energy_cost = 0
	spell.range_ft = 0
	assert_true(spell.is_valid(), "a well-formed SpellResource must remain valid after adding area_effect_radius_ft")
	assert_eq(spell.validation_error(), "", "validation_error() must remain empty")

	spell.area_effect_radius_ft = 20
	assert_true(spell.is_valid(), "setting a non-zero area_effect_radius_ft must not affect validity")
