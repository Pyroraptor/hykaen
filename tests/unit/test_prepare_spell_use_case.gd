extends GutTest
## tests/unit/test_prepare_spell_use_case.gd
##
## GUT test suite for FEAT-006: PrepareSpellUseCase.execute(character, slot,
## spell_id) -> Dictionary (Application layer, ADR-002 Result-shaped
## Dictionary convention: {ok:true} / {ok:false, error:String}).
##
## Covers the design notes' test_criteria for US-006:
##   - For a level-1 character with two equipped items, preparing a spell on
##     the first item succeeds with {ok:true} and is_charged==true
##   - Preparing a second spell on the second item for the same level-1
##     character fails with {ok:false, error:'prepared spell count (2)
##     exceeds level (1)'}
##   - Clearing a prepared spell (empty spell_id) succeeds, sets
##     prepared_spell_id=='' and is_charged==false
##   - Re-preparing after clearing succeeds and does not exceed the level cap
##   - Preparing a spell targeting an empty slot returns {ok:false,
##     error:'no item in slot'}

const PrepareSpellUseCaseClass = preload("res://core/use_cases/prepare_spell_use_case.gd")
const EquipItemUseCaseClass = preload("res://core/use_cases/equip_item_use_case.gd")
const CharacterResourceClass = preload("res://core/model/character_resource.gd")
const ItemResourceClass = preload("res://core/resources/item_resource.gd")
const EquipmentSlotClass = preload("res://core/model/equipment_slot.gd")


# ── Helpers ──────────────────────────────────────────────────────────────

func _make_item(item_id: String, slot: int, is_implement: bool = true) -> ItemResourceClass:
	var item := ItemResourceClass.new()
	item.item_id = item_id
	item.slot = slot
	item.is_implement = is_implement
	return item


func _make_use_case() -> PrepareSpellUseCaseClass:
	return PrepareSpellUseCaseClass.new()


func _make_level_1_character_with_two_items() -> Dictionary:
	var character := CharacterResourceClass.new()
	character.level = 1
	var wand := _make_item("oak_wand", EquipmentSlotClass.MAIN_HAND)
	var orb := _make_item("crystal_orb", EquipmentSlotClass.OFF_HAND)

	assert_true(
		EquipItemUseCaseClass.new().execute(character, wand).get("ok"),
		"Precondition: equipping the wand into MAIN_HAND must succeed"
	)
	assert_true(
		EquipItemUseCaseClass.new().execute(character, orb).get("ok"),
		"Precondition: equipping the orb into OFF_HAND must succeed"
	)

	return {"character": character, "wand": wand, "orb": orb}


# ── Success path ─────────────────────────────────────────────────────────

func test_prepare_spell_on_first_item_of_level_1_character_succeeds_and_charges() -> void:
	var setup := _make_level_1_character_with_two_items()
	var character = setup["character"]
	var use_case := _make_use_case()

	var result: Dictionary = use_case.execute(character, EquipmentSlotClass.MAIN_HAND, "fire_bolt")

	assert_true(result.get("ok"), "Preparing a spell on the first item of a level-1 character must return ok:true")
	assert_eq(
		setup["wand"].prepared_spell_id, "fire_bolt",
		"MAIN_HAND item's prepared_spell_id must be set to the prepared spell"
	)
	assert_true(
		setup["wand"].is_charged,
		"MAIN_HAND item must be charged after successfully preparing a spell"
	)


# ── Cross-item prepared-spell-count-vs-level cap ────────────────────────

func test_prepare_second_spell_on_second_item_exceeds_level_1_cap() -> void:
	var setup := _make_level_1_character_with_two_items()
	var character = setup["character"]
	var use_case := _make_use_case()

	var first_result: Dictionary = use_case.execute(character, EquipmentSlotClass.MAIN_HAND, "fire_bolt")
	assert_true(first_result.get("ok"), "Precondition: preparing the first spell must succeed")

	var second_result: Dictionary = use_case.execute(character, EquipmentSlotClass.OFF_HAND, "frost_ray")

	assert_false(
		second_result.get("ok"),
		"Preparing a second spell for a level-1 character must return ok:false"
	)
	assert_eq(
		second_result.get("error"), "prepared spell count (2) exceeds level (1)",
		"Over-cap prepare must return the exact expected error string"
	)
	assert_eq(
		setup["orb"].prepared_spell_id, "",
		"OFF_HAND item must remain unprepared after a rejected prepare attempt"
	)
	assert_false(
		setup["orb"].is_charged,
		"OFF_HAND item must remain uncharged after a rejected prepare attempt"
	)


# ── Clearing ─────────────────────────────────────────────────────────────

func test_clearing_prepared_spell_with_empty_spell_id_succeeds() -> void:
	var setup := _make_level_1_character_with_two_items()
	var character = setup["character"]
	var use_case := _make_use_case()

	var prepare_result: Dictionary = use_case.execute(character, EquipmentSlotClass.MAIN_HAND, "fire_bolt")
	assert_true(prepare_result.get("ok"), "Precondition: preparing the spell must succeed")

	var clear_result: Dictionary = use_case.execute(character, EquipmentSlotClass.MAIN_HAND, "")

	assert_true(clear_result.get("ok"), "Clearing a prepared spell must return ok:true")
	assert_eq(
		setup["wand"].prepared_spell_id, "",
		"prepared_spell_id must be '' after clearing"
	)
	assert_false(
		setup["wand"].is_charged,
		"is_charged must be false after clearing"
	)


func test_re_preparing_after_clearing_succeeds_without_exceeding_level_cap() -> void:
	var setup := _make_level_1_character_with_two_items()
	var character = setup["character"]
	var use_case := _make_use_case()

	assert_true(
		use_case.execute(character, EquipmentSlotClass.MAIN_HAND, "fire_bolt").get("ok"),
		"Precondition: preparing the first spell must succeed"
	)
	assert_true(
		use_case.execute(character, EquipmentSlotClass.MAIN_HAND, "").get("ok"),
		"Precondition: clearing the prepared spell must succeed"
	)

	var reprepare_result: Dictionary = use_case.execute(character, EquipmentSlotClass.OFF_HAND, "frost_ray")

	assert_true(
		reprepare_result.get("ok"),
		"Re-preparing after clearing must succeed since the cross-item count no longer exceeds level"
	)
	assert_eq(setup["orb"].prepared_spell_id, "frost_ray")
	assert_true(setup["orb"].is_charged)


# ── no item in slot ──────────────────────────────────────────────────────

func test_prepare_spell_targeting_empty_slot_fails() -> void:
	var character := CharacterResourceClass.new()
	character.level = 1
	var use_case := _make_use_case()

	var result: Dictionary = use_case.execute(character, EquipmentSlotClass.MAIN_HAND, "fire_bolt")

	assert_false(result.get("ok"), "Preparing a spell targeting an empty slot must return ok:false")
	assert_eq(
		result.get("error"), "no item in slot",
		"Empty-slot prepare must return the exact 'no item in slot' error string"
	)
