extends GutTest
## tests/unit/test_equip_item_use_case.gd
##
## GUT test suite for FEAT-004: EquipItemUseCase.execute(character, item) ->
## Dictionary (Application layer, ADR-002 Result-shaped Dictionary
## convention: {ok:true} / {ok:false, error:String}).
##
## Directly mitigates RISK-001 by exercising all four specified edge cases
## (design notes' test_criteria for US-004):
##   - Equipping a two-handed staff into MAIN_HAND on an empty character
##     returns {ok:true}
##   - Subsequently attempting to equip a shield into OFF_HAND on that same
##     character returns {ok:false, error:'OFF_HAND blocked by two-handed
##     item'}
##   - Equipping two distinct one-handed items into two different empty
##     slots both return {ok:true}
##   - Attempting to equip into an already-occupied slot returns
##     {ok:false, error:'slot occupied'}
##   - Attempting to equip with an out-of-range slot returns
##     {ok:false, error:'invalid slot'}
##   - Equipping a two-handed item when OFF_HAND is already occupied
##     returns {ok:false, error:'two-handed item requires empty OFF_HAND'}
##
## Checked in order per design notes' api_contracts #5: invalid slot ->
## slot occupied -> OFF_HAND blocked by two-handed item -> two-handed item
## requires empty OFF_HAND -> success.

const EquipItemUseCaseClass = preload("res://core/use_cases/equip_item_use_case.gd")
const CharacterResourceClass = preload("res://core/model/character_resource.gd")
const ItemResourceClass = preload("res://core/resources/item_resource.gd")
const EquipmentSlotClass = preload("res://core/model/equipment_slot.gd")


# ── Helpers ──────────────────────────────────────────────────────────────

func _make_item(item_id: String, slot: int, two_handed: bool = false) -> ItemResourceClass:
	var item := ItemResourceClass.new()
	item.item_id = item_id
	item.slot = slot
	item.two_handed = two_handed
	return item


func _make_use_case() -> EquipItemUseCaseClass:
	return EquipItemUseCaseClass.new()


# ── Success paths ────────────────────────────────────────────────────────

func test_equip_two_handed_staff_into_empty_main_hand_succeeds() -> void:
	var character := CharacterResourceClass.new()
	var staff := _make_item("oak_staff", EquipmentSlotClass.MAIN_HAND, true)
	var use_case := _make_use_case()

	var result: Dictionary = use_case.execute(character, staff)

	assert_true(result.get("ok"), "Equipping a two-handed staff into empty MAIN_HAND must return ok:true")
	assert_eq(
		character.get_item_in_slot(EquipmentSlotClass.MAIN_HAND), staff,
		"MAIN_HAND must hold the equipped staff after a successful execute()"
	)


func test_equip_two_distinct_one_handed_items_into_different_slots_both_succeed() -> void:
	var character := CharacterResourceClass.new()
	var sword := _make_item("iron_sword", EquipmentSlotClass.MAIN_HAND, false)
	var helm := _make_item("iron_helm", EquipmentSlotClass.HEAD, false)
	var use_case := _make_use_case()

	var result_sword: Dictionary = use_case.execute(character, sword)
	var result_helm: Dictionary = use_case.execute(character, helm)

	assert_true(result_sword.get("ok"), "Equipping a one-handed sword into empty MAIN_HAND must return ok:true")
	assert_true(result_helm.get("ok"), "Equipping a one-handed helm into empty HEAD must return ok:true")
	assert_eq(character.get_item_in_slot(EquipmentSlotClass.MAIN_HAND), sword)
	assert_eq(character.get_item_in_slot(EquipmentSlotClass.HEAD), helm)


# ── OFF_HAND blocked by two-handed item ─────────────────────────────────

func test_off_hand_blocked_by_two_handed_main_hand_item() -> void:
	var character := CharacterResourceClass.new()
	var staff := _make_item("oak_staff", EquipmentSlotClass.MAIN_HAND, true)
	var shield := _make_item("wooden_shield", EquipmentSlotClass.OFF_HAND, false)
	var use_case := _make_use_case()

	var staff_result: Dictionary = use_case.execute(character, staff)
	assert_true(staff_result.get("ok"), "Precondition: equipping the two-handed staff must succeed")

	var shield_result: Dictionary = use_case.execute(character, shield)

	assert_false(shield_result.get("ok"), "Equipping OFF_HAND while MAIN_HAND is two-handed must return ok:false")
	assert_eq(
		shield_result.get("error"), "OFF_HAND blocked by two-handed item",
		"Blocked OFF_HAND equip must return the exact 'OFF_HAND blocked by two-handed item' error string"
	)
	assert_null(
		character.get_item_in_slot(EquipmentSlotClass.OFF_HAND),
		"OFF_HAND must remain empty after a blocked equip attempt"
	)


# ── slot occupied ────────────────────────────────────────────────────────

func test_equip_into_already_occupied_slot_fails() -> void:
	var character := CharacterResourceClass.new()
	var first_sword := _make_item("iron_sword", EquipmentSlotClass.MAIN_HAND, false)
	var second_sword := _make_item("steel_sword", EquipmentSlotClass.MAIN_HAND, false)
	var use_case := _make_use_case()

	var first_result: Dictionary = use_case.execute(character, first_sword)
	assert_true(first_result.get("ok"), "Precondition: first equip into empty MAIN_HAND must succeed")

	var second_result: Dictionary = use_case.execute(character, second_sword)

	assert_false(second_result.get("ok"), "Equipping into an already-occupied slot must return ok:false")
	assert_eq(
		second_result.get("error"), "slot occupied",
		"Occupied-slot equip must return the exact 'slot occupied' error string"
	)
	assert_eq(
		character.get_item_in_slot(EquipmentSlotClass.MAIN_HAND), first_sword,
		"MAIN_HAND must still hold the original item after a rejected equip attempt"
	)


# ── invalid slot ─────────────────────────────────────────────────────────

func test_equip_with_out_of_range_slot_fails() -> void:
	var character := CharacterResourceClass.new()
	var bad_item := _make_item("mystery_item", 99, false)
	var use_case := _make_use_case()

	var result: Dictionary = use_case.execute(character, bad_item)

	assert_false(result.get("ok"), "Equipping with an out-of-range slot must return ok:false")
	assert_eq(
		result.get("error"), "invalid slot",
		"Out-of-range slot equip must return the exact 'invalid slot' error string"
	)


func test_equip_with_negative_slot_fails() -> void:
	var character := CharacterResourceClass.new()
	var bad_item := _make_item("mystery_item", -1, false)
	var use_case := _make_use_case()

	var result: Dictionary = use_case.execute(character, bad_item)

	assert_false(result.get("ok"), "Equipping with a negative slot must return ok:false")
	assert_eq(result.get("error"), "invalid slot")


# ── two-handed item requires empty OFF_HAND ─────────────────────────────

func test_equip_two_handed_item_when_off_hand_occupied_fails() -> void:
	var character := CharacterResourceClass.new()
	var shield := _make_item("wooden_shield", EquipmentSlotClass.OFF_HAND, false)
	var staff := _make_item("oak_staff", EquipmentSlotClass.MAIN_HAND, true)
	var use_case := _make_use_case()

	var shield_result: Dictionary = use_case.execute(character, shield)
	assert_true(shield_result.get("ok"), "Precondition: equipping the shield into empty OFF_HAND must succeed")

	var staff_result: Dictionary = use_case.execute(character, staff)

	assert_false(staff_result.get("ok"), "Equipping a two-handed item while OFF_HAND is occupied must return ok:false")
	assert_eq(
		staff_result.get("error"), "two-handed item requires empty OFF_HAND",
		"Two-handed-vs-occupied-OFF_HAND equip must return the exact expected error string"
	)
	assert_null(
		character.get_item_in_slot(EquipmentSlotClass.MAIN_HAND),
		"MAIN_HAND must remain empty after a rejected two-handed equip attempt"
	)
