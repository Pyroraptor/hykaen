extends GutTest
## tests/unit/test_unequip_item_use_case.gd
##
## GUT test suite for FEAT-005: UnequipItemUseCase.execute(character, slot) ->
## Dictionary (Application layer, ADR-002 Result-shaped Dictionary
## convention: {ok:true, item:ItemResource} / {ok:false, error:String}).
##
## Covers the design notes' test_criteria for US-005:
##   - Equipping then unequipping the same slot leaves
##     character.equipped_items empty and returns {ok:true, item:<ItemResource>}
##   - Unequipping an already-empty slot returns
##     {ok:false, error:'slot empty'}

const UnequipItemUseCaseClass = preload("res://core/use_cases/unequip_item_use_case.gd")
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


func _make_use_case() -> UnequipItemUseCaseClass:
	return UnequipItemUseCaseClass.new()


# ── Success path ─────────────────────────────────────────────────────────

func test_equip_then_unequip_same_slot_leaves_equipped_items_empty_and_returns_item() -> void:
	var character := CharacterResourceClass.new()
	var sword := _make_item("iron_sword", EquipmentSlotClass.MAIN_HAND, false)

	var equip_result: Dictionary = EquipItemUseCaseClass.new().execute(character, sword)
	assert_true(equip_result.get("ok"), "Precondition: equipping the sword into empty MAIN_HAND must succeed")

	var use_case := _make_use_case()
	var result: Dictionary = use_case.execute(character, EquipmentSlotClass.MAIN_HAND)

	assert_true(result.get("ok"), "Unequipping a previously-equipped slot must return ok:true")
	assert_eq(
		result.get("item"), sword,
		"Unequip must return the ItemResource that occupied the slot"
	)
	assert_true(
		character.equipped_items.is_empty(),
		"character.equipped_items must be empty after unequipping the only equipped item"
	)
	assert_null(
		character.get_item_in_slot(EquipmentSlotClass.MAIN_HAND),
		"MAIN_HAND must no longer resolve to any item after unequip"
	)


# ── slot empty ───────────────────────────────────────────────────────────

func test_unequip_already_empty_slot_fails() -> void:
	var character := CharacterResourceClass.new()
	var use_case := _make_use_case()

	var result: Dictionary = use_case.execute(character, EquipmentSlotClass.MAIN_HAND)

	assert_false(result.get("ok"), "Unequipping an empty slot must return ok:false")
	assert_eq(
		result.get("error"), "slot empty",
		"Empty-slot unequip must return the exact 'slot empty' error string"
	)


func test_unequip_one_of_two_slots_leaves_the_other_intact() -> void:
	var character := CharacterResourceClass.new()
	var sword := _make_item("iron_sword", EquipmentSlotClass.MAIN_HAND, false)
	var helm := _make_item("iron_helm", EquipmentSlotClass.HEAD, false)

	EquipItemUseCaseClass.new().execute(character, sword)
	EquipItemUseCaseClass.new().execute(character, helm)

	var use_case := _make_use_case()
	var result: Dictionary = use_case.execute(character, EquipmentSlotClass.MAIN_HAND)

	assert_true(result.get("ok"), "Unequipping MAIN_HAND must succeed")
	assert_eq(result.get("item"), sword)
	assert_eq(
		character.get_item_in_slot(EquipmentSlotClass.HEAD), helm,
		"HEAD must remain equipped after unequipping a different slot"
	)
	assert_null(character.get_item_in_slot(EquipmentSlotClass.MAIN_HAND))
