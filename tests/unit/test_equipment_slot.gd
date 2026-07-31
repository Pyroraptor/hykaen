extends GutTest
## tests/unit/test_equipment_slot.gd
##
## GUT test suite for FEAT-001: EquipmentSlot enum with 15 named slots and
## slot_name(). Validates all test_criteria for US-001:
##   - ALL_SLOTS.size() == 15
##   - slot_name(MAIN_HAND) == 'Main Hand'
##   - slot_name() returns a non-empty String for all 15 defined slot constants
##   - ALL_SLOTS contains all 15 values in the specified order with no duplicates

const EquipmentSlotClass = preload("res://core/model/equipment_slot.gd")


# ── ALL_SLOTS shape ───────────────────────────────────────────────────────────

func test_all_slots_size_is_15() -> void:
	assert_eq(EquipmentSlotClass.ALL_SLOTS.size(), 15, "ALL_SLOTS must contain exactly 15 slots")


func test_all_slots_has_no_duplicates() -> void:
	var seen: Dictionary = {}
	var duplicates: Array = []
	for slot in EquipmentSlotClass.ALL_SLOTS:
		if seen.has(slot):
			duplicates.append(slot)
		seen[slot] = true
	assert_eq(duplicates.size(), 0, "ALL_SLOTS must contain no duplicate values: %s" % str(duplicates))


func test_all_slots_order_matches_spec() -> void:
	var expected: Array = [
		EquipmentSlotClass.MAIN_HAND,
		EquipmentSlotClass.OFF_HAND,
		EquipmentSlotClass.HEAD,
		EquipmentSlotClass.NECK,
		EquipmentSlotClass.SHOULDERS,
		EquipmentSlotClass.CHEST,
		EquipmentSlotClass.BACK,
		EquipmentSlotClass.HANDS,
		EquipmentSlotClass.WAIST,
		EquipmentSlotClass.LEGS,
		EquipmentSlotClass.FEET,
		EquipmentSlotClass.RING_1,
		EquipmentSlotClass.RING_2,
		EquipmentSlotClass.ACCESSORY_1,
		EquipmentSlotClass.ACCESSORY_2,
	]
	assert_eq(EquipmentSlotClass.ALL_SLOTS, expected, "ALL_SLOTS must contain all 15 values in the specified order (MAIN_HAND..ACCESSORY_2)")


func test_all_slots_first_is_main_hand_last_is_accessory_2() -> void:
	assert_eq(EquipmentSlotClass.ALL_SLOTS[0], EquipmentSlotClass.MAIN_HAND, "ALL_SLOTS[0] must be MAIN_HAND")
	assert_eq(EquipmentSlotClass.ALL_SLOTS[14], EquipmentSlotClass.ACCESSORY_2, "ALL_SLOTS[14] must be ACCESSORY_2")


# ── slot_name() ───────────────────────────────────────────────────────────────

func test_slot_name_main_hand() -> void:
	assert_eq(EquipmentSlotClass.slot_name(EquipmentSlotClass.MAIN_HAND), "Main Hand", "slot_name(MAIN_HAND) must be 'Main Hand'")


func test_slot_name_non_empty_for_all_15_defined_slots() -> void:
	var empty_for: Array = []
	for slot in EquipmentSlotClass.ALL_SLOTS:
		var label: String = EquipmentSlotClass.slot_name(slot)
		if label == "":
			empty_for.append(slot)
	assert_eq(empty_for.size(), 0, "slot_name() must return a non-empty String for all 15 defined slots: %s" % str(empty_for))


func test_slot_name_returns_string_type_for_all_15_defined_slots() -> void:
	for slot in EquipmentSlotClass.ALL_SLOTS:
		var label = EquipmentSlotClass.slot_name(slot)
		assert_true(label is String, "slot_name(%d) must return a String" % slot)


func test_slot_name_out_of_range_does_not_crash() -> void:
	var label: String = EquipmentSlotClass.slot_name(999)
	assert_true(label is String and label != "", "slot_name() on an out-of-range value must return a non-empty fallback String, not crash")


# ── Domain purity — no Node/Control inheritance ───────────────────────────────

func test_equipment_slot_gd_no_node_inheritance() -> void:
	var file := FileAccess.open("res://core/model/equipment_slot.gd", FileAccess.READ)
	assert_not_null(file, "core/model/equipment_slot.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"equipment_slot.gd must not contain 'extends Node' — ADR-001 domain purity"
	)
	assert_false(
		content.contains("extends Control"),
		"equipment_slot.gd must not contain 'extends Control' — ADR-001 domain purity"
	)
