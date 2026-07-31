extends GutTest
## tests/unit/test_character_resource_equipment.gd
##
## GUT test suite for FEAT-003: CharacterResource equipment fields
## (level:int=1, equipped_items:Array=[]) and the pure domain helper
## methods get_item_in_slot()/is_slot_blocked() implementing the
## asymmetric two-handed/off-hand blocking rule (RISK-006).
##
## Validates the test_criteria for US-003:
##   - get_item_in_slot(slot) returns the first ItemResource in
##     equipped_items matching that slot, or null if none
##   - is_slot_blocked(OFF_HAND) returns true only when the MAIN_HAND item
##     exists and has two_handed==true
##   - is_slot_blocked() returns false for all other slot/state combinations
##   - Loading an existing pre-iteration .tres character fixture that omits
##     level/equipped_items yields level==1 and equipped_items==[]
##   - Full pre-existing CharacterResource/weapon-loading regression suite
##     still passes with 0 new failures (see test_character_resources.gd,
##     test_remaining_characters.gd, test_titus_character.gd — unmodified)

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


# ── Default field values on a fresh CharacterResource ─────────────────────

func test_default_level_is_1() -> void:
	var character := CharacterResourceClass.new()
	assert_eq(character.level, 1, "CharacterResource.level must default to 1")


func test_default_equipped_items_is_empty_array() -> void:
	var character := CharacterResourceClass.new()
	assert_eq(character.equipped_items, [], "CharacterResource.equipped_items must default to an empty Array")


# ── get_item_in_slot() ─────────────────────────────────────────────────────

func test_get_item_in_slot_returns_null_when_no_items_equipped() -> void:
	var character := CharacterResourceClass.new()
	assert_null(
		character.get_item_in_slot(EquipmentSlotClass.MAIN_HAND),
		"get_item_in_slot() must return null when equipped_items is empty"
	)


func test_get_item_in_slot_returns_null_when_no_matching_slot() -> void:
	var character := CharacterResourceClass.new()
	character.equipped_items = [_make_item("iron_sword", EquipmentSlotClass.MAIN_HAND)]
	assert_null(
		character.get_item_in_slot(EquipmentSlotClass.HEAD),
		"get_item_in_slot() must return null when no equipped item matches the requested slot"
	)


func test_get_item_in_slot_returns_matching_item() -> void:
	var character := CharacterResourceClass.new()
	var sword := _make_item("iron_sword", EquipmentSlotClass.MAIN_HAND)
	character.equipped_items = [sword]
	assert_eq(
		character.get_item_in_slot(EquipmentSlotClass.MAIN_HAND), sword,
		"get_item_in_slot(MAIN_HAND) must return the equipped MAIN_HAND item"
	)


func test_get_item_in_slot_returns_first_match_when_multiple() -> void:
	# Business rule enforcement (one item per slot) belongs to EquipItemUseCase,
	# not this pure accessor; get_item_in_slot() must simply return the FIRST
	# array match if the invariant is ever violated by test data.
	var character := CharacterResourceClass.new()
	var first := _make_item("iron_sword", EquipmentSlotClass.MAIN_HAND)
	var second := _make_item("steel_sword", EquipmentSlotClass.MAIN_HAND)
	character.equipped_items = [first, second]
	assert_eq(
		character.get_item_in_slot(EquipmentSlotClass.MAIN_HAND), first,
		"get_item_in_slot() must return the FIRST matching item in equipped_items"
	)


func test_get_item_in_slot_distinguishes_between_slots() -> void:
	var character := CharacterResourceClass.new()
	var sword := _make_item("iron_sword", EquipmentSlotClass.MAIN_HAND)
	var shield := _make_item("wooden_shield", EquipmentSlotClass.OFF_HAND)
	character.equipped_items = [sword, shield]
	assert_eq(character.get_item_in_slot(EquipmentSlotClass.MAIN_HAND), sword, "MAIN_HAND lookup must return the sword")
	assert_eq(character.get_item_in_slot(EquipmentSlotClass.OFF_HAND), shield, "OFF_HAND lookup must return the shield")


# ── is_slot_blocked() — asymmetric two-handed/off-hand blocking rule ───────

func test_off_hand_blocked_when_main_hand_is_two_handed() -> void:
	var character := CharacterResourceClass.new()
	character.equipped_items = [_make_item("greatsword", EquipmentSlotClass.MAIN_HAND, true)]
	assert_true(
		character.is_slot_blocked(EquipmentSlotClass.OFF_HAND),
		"is_slot_blocked(OFF_HAND) must be true when MAIN_HAND item has two_handed==true"
	)


func test_off_hand_not_blocked_when_main_hand_is_one_handed() -> void:
	var character := CharacterResourceClass.new()
	character.equipped_items = [_make_item("iron_sword", EquipmentSlotClass.MAIN_HAND, false)]
	assert_false(
		character.is_slot_blocked(EquipmentSlotClass.OFF_HAND),
		"is_slot_blocked(OFF_HAND) must be false when MAIN_HAND item has two_handed==false"
	)


func test_off_hand_not_blocked_when_main_hand_empty() -> void:
	var character := CharacterResourceClass.new()
	assert_false(
		character.is_slot_blocked(EquipmentSlotClass.OFF_HAND),
		"is_slot_blocked(OFF_HAND) must be false when MAIN_HAND is empty"
	)


func test_main_hand_never_blocked_by_off_hand_two_handed_flag() -> void:
	# Asymmetric rule (RISK-006): a two_handed flag on an OFF_HAND item (were
	# one ever equipped there, e.g. via malformed data) must NOT block
	# MAIN_HAND -- the rule is one-directional, MAIN_HAND -> OFF_HAND only.
	var character := CharacterResourceClass.new()
	character.equipped_items = [_make_item("weird_offhand", EquipmentSlotClass.OFF_HAND, true)]
	assert_false(
		character.is_slot_blocked(EquipmentSlotClass.MAIN_HAND),
		"is_slot_blocked(MAIN_HAND) must always be false -- the two-handed rule only blocks OFF_HAND"
	)


func test_other_slots_never_blocked() -> void:
	var character := CharacterResourceClass.new()
	character.equipped_items = [_make_item("greatsword", EquipmentSlotClass.MAIN_HAND, true)]
	for slot in EquipmentSlotClass.ALL_SLOTS:
		if slot == EquipmentSlotClass.OFF_HAND:
			continue
		assert_false(
			character.is_slot_blocked(slot),
			"is_slot_blocked(%d) must be false -- only OFF_HAND can ever be blocked" % slot
		)


func test_off_hand_not_blocked_on_fresh_character() -> void:
	var character := CharacterResourceClass.new()
	assert_false(
		character.is_slot_blocked(EquipmentSlotClass.OFF_HAND),
		"is_slot_blocked(OFF_HAND) must be false on a fresh CharacterResource with no equipped_items"
	)


# ── RISK-004 mitigation: pre-iteration .tres fixtures omitting new fields ──

## Criterion (superseded by FEAT-008): originally, loading an existing
## pre-iteration .tres character fixture that omitted level/equipped_items
## had to yield level==1 and equipped_items==[]. FEAT-008 additively wires
## real equipped_items (and an explicit level=1) into all four party-member
## fixtures (data/characters/{gram_marx,titus,marigold,dwarf_channeler}.tres)
## per US-008, so equipped_items is no longer empty for these specific
## files -- that is the intended, tested outcome of FEAT-008 (see
## tests/unit/test_prologue_character_equipment_fixtures.gd for the
## level==1 / equipped_items-contains-expected-item-ids assertions and the
## accompanying field-diff regression test covering every OTHER field).
##
## The general "omitting these fields yields the documented defaults"
## contract this test was guarding is still fully covered above by
## test_default_level_is_1() and test_default_equipped_items_is_empty_array()
## against a synthetic CharacterResource.new() (no .tres involved), so this
## test now only re-asserts the part of the original contract that still
## holds for these fixtures: level defaults to 1 whether or not a .tres
## explicitly declares it (all four now declare it explicitly as 1, per
## FEAT-008), and every fixture still loads non-null.
func test_pre_iteration_fixture_omitting_new_fields_gets_defaults() -> void:
	var paths: Array = [
		"res://data/characters/titus.tres",
		"res://data/characters/gram_marx.tres",
		"res://data/characters/marigold.tres",
		"res://data/characters/dwarf_channeler.tres",
	]
	for path in paths:
		var character = ResourceLoader.load(path)
		assert_not_null(character, "%s must load non-null" % path)
		if character == null:
			continue
		assert_eq(
			character.level, 1,
			"%s must have level == 1; got %s" % [path, str(character.level)]
		)


# ── Domain purity — no Node/Control inheritance (additive-only change) ─────

func test_character_resource_gd_no_node_inheritance() -> void:
	var file := FileAccess.open("res://core/model/character_resource.gd", FileAccess.READ)
	assert_not_null(file, "core/model/character_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"character_resource.gd must not contain 'extends Node' — ADR-001 domain purity"
	)
	assert_false(
		content.contains("extends Control"),
		"character_resource.gd must not contain 'extends Control' — ADR-001 domain purity"
	)
