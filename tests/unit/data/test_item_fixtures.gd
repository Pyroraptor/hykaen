extends GutTest
## tests/unit/data/test_item_fixtures.gd
##
## GUT test suite for FEAT-002 (US-002; FR-003, FR-004; AA-2-0 fixture
## table): fixture-loading regression test guarding the data-driven
## ItemResource .tres fixture that feeds the item-prepared-spell steel
## thread's exit-point assertions:
##   data/items/orb_gram.tres
##
## Mirrors the established test_prologue_item_fixtures.gd /
## test_ranged_weapon_fixtures.gd conventions: the fixture is loaded via
## the existing generic Resource loading path (ResourceLoader.load()) —
## never constructed in-memory — so an authoring mistake in the committed
## .tres file itself (not just in the ItemResource script) is caught
## here, per the design notes' security section ("a malformed .tres
## cannot silently corrupt the cast/discharge/condition chain").
##
## Test criteria (FEAT-002):
##   - orb_gram.tres loads as a valid ItemResource with no load errors
##   - display_name=="Gram's Focus Orb", slot==EquipmentSlot.ACCESSORY_1,
##     two_handed==false, is_implement==true,
##     prepared_spell_id=='frost_breath', is_charged==true

const ItemResourceClass = preload("res://core/resources/item_resource.gd")
const EquipmentSlotClass = preload("res://core/model/equipment_slot.gd")

const ORB_GRAM_PATH := "res://data/items/orb_gram.tres"


# ── Fixture loads, is an ItemResource, and is valid ────────────────────

func test_orb_gram_loads_as_valid_item_resource() -> void:
	var item = ResourceLoader.load(ORB_GRAM_PATH)
	assert_not_null(item, "ResourceLoader.load('%s') must return non-null" % ORB_GRAM_PATH)
	if item == null:
		return
	assert_is(item, ItemResourceClass, "%s must be an ItemResource" % ORB_GRAM_PATH)
	assert_true(item.is_valid(), "%s must be valid: %s" % [ORB_GRAM_PATH, item.validation_error()])
	assert_eq(item.validation_error(), "", "%s validation_error() must be empty" % ORB_GRAM_PATH)


# ── orb_gram field assertions (AA-2-0 fixture table) ────────────────────

func test_orb_gram_fields() -> void:
	var item = ResourceLoader.load(ORB_GRAM_PATH)
	assert_not_null(item, "orb_gram.tres must load")
	if item == null:
		return
	assert_eq(item.item_id, "orb_gram", "orb_gram.item_id must be 'orb_gram'")
	assert_eq(item.display_name, "Gram's Focus Orb", "orb_gram.display_name must be \"Gram's Focus Orb\"")
	assert_eq(item.slot, EquipmentSlotClass.ACCESSORY_1, "orb_gram.slot must be ACCESSORY_1")
	assert_false(item.two_handed, "orb_gram.two_handed must be false")
	assert_true(item.is_implement, "orb_gram.is_implement must be true")
	assert_eq(item.prepared_spell_id, "frost_breath", "orb_gram.prepared_spell_id must be 'frost_breath'")
	assert_true(item.is_charged, "orb_gram.is_charged must be true")
