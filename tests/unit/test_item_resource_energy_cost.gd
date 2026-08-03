extends GutTest
## tests/unit/test_item_resource_energy_cost.gd
##
## GUT test suite for FEAT-376 (DEF-001; US-001/US-005): ItemResource gains
## a formally declared @export var energy_cost: int = 0 field alongside the
## existing is_charged field.
##
## Background: the Mage-recharge branch (FR-003, FR-006, FR-009, FR-013)
## was previously only reachable via FakeEquippedItem test doubles because
## the production core/resources/item_resource.gd script had no declared
## energy_cost field -- CombatantFactory's _duck_get() walk and
## ShortRestMageRechargeUseCase could only see energy_cost via duck-typing
## on doubles, never on a real .tres-backed ItemResource. This suite proves
## the real class now carries the field directly.
##
## Test criteria covered:
##   1. ItemResource.energy_cost defaults to 0 on a newly instantiated
##      resource (never-dischargeable by default -- no existing item's
##      behavior changes until data is authored, FIX-002).
##   2. energy_cost is readable/writable and round-trips through
##      ResourceSaver.save()/ResourceLoader.load() without loss (including
##      the untouched-default case).
##   3. Existing ItemResource/is_charged behavior (is_valid()/
##      validation_error()) is unaffected by the new field.

const ItemResourceClass = preload("res://core/resources/item_resource.gd")
const EquipmentSlotClass = preload("res://core/model/equipment_slot.gd")

const ROUND_TRIP_TRES_PATH := "user://test_item_resource_energy_cost_round_trip.tres"


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: energy_cost defaults to 0
# ══════════════════════════════════════════════════════════════════════════════

func test_energy_cost_defaults_to_zero() -> void:
	var item := ItemResourceClass.new()
	assert_eq(item.energy_cost, 0, "ItemResource.energy_cost must default to 0 (never-dischargeable)")


func test_energy_cost_is_typed_as_int() -> void:
	var item := ItemResourceClass.new()
	assert_eq(typeof(item.energy_cost), TYPE_INT, "energy_cost must be typed as int")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1b: is_charged still present alongside energy_cost
# ══════════════════════════════════════════════════════════════════════════════

func test_is_charged_still_defaults_to_false_alongside_energy_cost() -> void:
	var item := ItemResourceClass.new()
	assert_eq(item.is_charged, false, "is_charged must still default to false")
	assert_eq(item.energy_cost, 0, "energy_cost must default to 0")


# ══════════════════════════════════════════════════════════════════════════════
# energy_cost is readable/writable
# ══════════════════════════════════════════════════════════════════════════════

func test_energy_cost_is_writable_and_readable() -> void:
	var item := ItemResourceClass.new()
	item.energy_cost = 3
	assert_eq(item.energy_cost, 3, "energy_cost must be writable and readable")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: full round-trip via ResourceSaver.save()/ResourceLoader.load()
# ══════════════════════════════════════════════════════════════════════════════

func test_round_trip_save_load_preserves_energy_cost() -> void:
	var item := ItemResourceClass.new()
	item.item_id = "mage_orb"
	item.display_name = "Mage Orb"
	item.slot = EquipmentSlotClass.MAIN_HAND
	item.is_charged = false
	item.energy_cost = 2

	var save_err := ResourceSaver.save(item, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for round-trip fixture")

	# Force a fresh load from disk rather than returning a cached instance.
	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)

	assert_not_null(reloaded, "Round-trip fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.item_id, "mage_orb", "item_id must round-trip exactly")
	assert_eq(reloaded.energy_cost, 2, "energy_cost must round-trip exactly; got: %d" % reloaded.energy_cost)
	assert_eq(reloaded.is_charged, false, "is_charged must round-trip exactly")

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


func test_round_trip_preserves_default_energy_cost_too() -> void:
	# Guard against a save/load path that only preserves non-default values.
	var item := ItemResourceClass.new()
	item.item_id = "plain_dagger"
	item.slot = EquipmentSlotClass.MAIN_HAND

	var save_err := ResourceSaver.save(item, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for default-value fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Default-value fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.energy_cost, 0, "energy_cost must round-trip as default 0")
	assert_eq(reloaded.is_charged, false, "is_charged must round-trip as default false")

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: existing is_valid()/validation_error() behavior unaffected
# ══════════════════════════════════════════════════════════════════════════════

func test_existing_validity_rules_unaffected_by_energy_cost_field() -> void:
	var item := ItemResourceClass.new()
	item.item_id = "iron_sword"
	item.slot = EquipmentSlotClass.MAIN_HAND
	assert_true(item.is_valid(), "a well-formed ItemResource must remain valid after adding energy_cost")
	assert_eq(item.validation_error(), "", "validation_error() must remain empty for a valid ItemResource")

	item.energy_cost = 5
	assert_true(item.is_valid(), "setting a non-zero energy_cost must not affect validity")
