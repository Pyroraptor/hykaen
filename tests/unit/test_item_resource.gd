extends GutTest
## tests/unit/test_item_resource.gd
##
## GUT test suite for FEAT-002: ItemResource pure-data class with
## is_valid()/validation_error() mirroring the existing SpellResource
## pattern. Validates the test_criteria for US-002:
##   - A valid ItemResource (non-empty item_id, slot in [0,14]) passes
##     is_valid()==true with validation_error()==''
##   - An ItemResource with empty item_id fails is_valid()==false and
##     validation_error() is non-empty
##   - An ItemResource with slot outside [0,14] fails is_valid()==false

const ItemResourceClass = preload("res://core/resources/item_resource.gd")
const EquipmentSlotClass = preload("res://core/model/equipment_slot.gd")


# ── Valid ItemResource ────────────────────────────────────────────────────

func test_valid_item_resource_is_valid() -> void:
	var item := ItemResourceClass.new()
	item.item_id = "iron_sword"
	item.display_name = "Iron Sword"
	item.slot = EquipmentSlotClass.MAIN_HAND
	assert_true(item.is_valid(), "a well-formed ItemResource must be valid")
	assert_eq(item.validation_error(), "", "validation_error() must be empty for a valid ItemResource")


func test_valid_item_resource_slot_boundaries() -> void:
	var low := ItemResourceClass.new()
	low.item_id = "min_slot_item"
	low.slot = 0
	assert_true(low.is_valid(), "slot == 0 (lower bound) must be valid")

	var high := ItemResourceClass.new()
	high.item_id = "max_slot_item"
	high.slot = 14
	assert_true(high.is_valid(), "slot == 14 (upper bound) must be valid")


# ── Empty item_id ─────────────────────────────────────────────────────────

func test_empty_item_id_is_invalid() -> void:
	var item := ItemResourceClass.new()
	item.item_id = ""
	item.slot = EquipmentSlotClass.HEAD
	assert_false(item.is_valid(), "empty item_id must fail is_valid()")
	assert_ne(item.validation_error(), "", "validation_error() must be non-empty when item_id is empty")


# ── Out-of-range slot ─────────────────────────────────────────────────────

func test_negative_slot_is_invalid() -> void:
	var item := ItemResourceClass.new()
	item.item_id = "bad_slot_item"
	item.slot = -1
	assert_false(item.is_valid(), "slot < 0 must fail is_valid()")
	assert_ne(item.validation_error(), "", "validation_error() must be non-empty when slot is out of range")


func test_slot_above_14_is_invalid() -> void:
	var item := ItemResourceClass.new()
	item.item_id = "bad_slot_item_2"
	item.slot = 15
	assert_false(item.is_valid(), "slot > 14 must fail is_valid()")
	assert_ne(item.validation_error(), "", "validation_error() must be non-empty when slot is out of range")


# ── Domain purity — no Node/Control inheritance ───────────────────────────

func test_item_resource_gd_no_node_inheritance() -> void:
	var file := FileAccess.open("res://core/resources/item_resource.gd", FileAccess.READ)
	assert_not_null(file, "core/resources/item_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"item_resource.gd must not contain 'extends Node' — ADR-001 domain purity"
	)
	assert_false(
		content.contains("extends Control"),
		"item_resource.gd must not contain 'extends Control' — ADR-001 domain purity"
	)
