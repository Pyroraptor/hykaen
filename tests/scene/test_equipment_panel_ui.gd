extends GutTest
## tests/scene/test_equipment_panel_ui.gd
##
## GUT test suite for FEAT-009 (US-010 / FR-009): EquipmentPanelUI is a
## read-only Presentation-layer projection of a CharacterResource's
## equipped items -- one row per EquipmentSlot.ALL_SLOTS slot (slot label +
## item display_name, or "—" when empty) plus a charged/uncharged
## indicator for any equipped item with a non-empty prepared_spell_id.
##
## Verifies the feature's test_criteria:
##   1. scenes/equipment_panel.tscn instantiates hidden by default and
##      exposes exactly 15 slot rows in EquipmentSlot.ALL_SLOTS order.
##   2. setup(gram_marx) renders staff_gram's display_name in the
##      MAIN_HAND row with a charged indicator, and ring_channeling's
##      display_name in the RING_1 row (the "right ring" slot) with a
##      charged indicator.
##   3. setup(character) renders "—" for every slot with no equipped item.
##   4. clear() resets every row back to "—" with no leftover item data
##      after a prior setup() call.
##   5. No row Control node in the scene has a connected input/click/
##      button-pressed signal handler (source-inspection + live-tree
##      assertion: this panel is confirmed read-only, ADR-003).

const EquipmentPanelScene: PackedScene = preload("res://scenes/equipment_panel.tscn")
const EquipmentSlotClass = preload("res://core/model/equipment_slot.gd")
const CharacterResourceClass = preload("res://core/model/character_resource.gd")
const ItemResourceClass = preload("res://core/resources/item_resource.gd")

const EQUIPMENT_PANEL_UI_PATH: String = "res://presentation/equipment_panel_ui.gd"
const EQUIPMENT_PANEL_SCENE_PATH: String = "res://scenes/equipment_panel.tscn"

var _panel = null


func before_each() -> void:
	_panel = EquipmentPanelScene.instantiate()
	add_child_autofree(_panel)


# ── Helpers ──────────────────────────────────────────────────────────────

func _make_item(item_id: String, slot: int, display_name: String, prepared_spell_id: String = "", is_charged: bool = false) -> ItemResourceClass:
	var item := ItemResourceClass.new()
	item.item_id = item_id
	item.slot = slot
	item.display_name = display_name
	item.prepared_spell_id = prepared_spell_id
	item.is_charged = is_charged
	return item


func _load_gram_marx():
	return ResourceLoader.load("res://data/characters/gram_marx.tres")


# ── Criterion 1: instantiates hidden, exposes exactly 15 rows in order ────

func test_panel_is_hidden_by_default() -> void:
	assert_false(_panel.visible, "EquipmentPanelUI must be hidden (visible=false) by default")


func test_panel_exposes_exactly_15_rows() -> void:
	assert_eq(_panel.get_row_count(), 15, "EquipmentPanelUI must expose exactly 15 slot rows")


func test_panel_rows_are_in_all_slots_order() -> void:
	assert_eq(
		_panel.get_row_slots(), EquipmentSlotClass.ALL_SLOTS,
		"EquipmentPanelUI rows must be in EquipmentSlot.ALL_SLOTS order"
	)


func test_panel_row_count_is_15_before_any_setup_call() -> void:
	# A fresh instantiate (before_each already instantiated + added the
	# panel, but setup() has never been called yet) must already expose
	# all 15 rows.
	assert_eq(_panel.get_row_count(), 15)
	for slot in EquipmentSlotClass.ALL_SLOTS:
		assert_eq(_panel.get_item_text(slot), "—", "slot %d must show '—' before any setup() call" % slot)


# ── Criterion 2: setup(gram_marx) renders staff_gram/ring_channeling ──────

func test_setup_gram_marx_renders_staff_gram_in_main_hand_with_charge_indicator() -> void:
	var gram_marx = _load_gram_marx()
	assert_not_null(gram_marx, "gram_marx.tres must load non-null")
	if gram_marx == null:
		return

	_panel.setup(gram_marx)

	assert_eq(
		_panel.get_item_text(EquipmentSlotClass.MAIN_HAND), "Gram's Quarterstaff",
		"MAIN_HAND row must show staff_gram's display_name"
	)
	assert_true(
		_panel.has_charge_indicator(EquipmentSlotClass.MAIN_HAND),
		"MAIN_HAND row must show a charged indicator for staff_gram (non-empty prepared_spell_id)"
	)


func test_setup_gram_marx_renders_empty_ring_1_slot() -> void:
	var gram_marx = _load_gram_marx()
	assert_not_null(gram_marx, "gram_marx.tres must load non-null")
	if gram_marx == null:
		return

	_panel.setup(gram_marx)

	# Gram Marx is a Wizard — he does not Channel; ring_channeling is a
	# Channeler item and is not in his loadout. RING_1 must show "—".
	assert_eq(
		_panel.get_item_text(EquipmentSlotClass.RING_1), "—",
		"RING_1 (right ring) row must show '—' — Wizards do not Channel; gram_marx has no ring equipped"
	)
	assert_false(
		_panel.has_charge_indicator(EquipmentSlotClass.RING_1),
		"RING_1 row must have no charge indicator — no ring is equipped"
	)


# ── Criterion 3: empty slots render "—" ────────────────────────────────────

func test_setup_renders_em_dash_for_every_empty_slot() -> void:
	var character := CharacterResourceClass.new()
	var sword := _make_item("iron_sword", EquipmentSlotClass.MAIN_HAND, "Iron Sword")
	character.equipped_items = [sword]

	_panel.setup(character)

	for slot in EquipmentSlotClass.ALL_SLOTS:
		if slot == EquipmentSlotClass.MAIN_HAND:
			continue
		assert_eq(_panel.get_item_text(slot), "—", "empty slot %d must render '—'" % slot)
		assert_false(
			_panel.has_charge_indicator(slot), "empty slot %d must show no charge indicator" % slot
		)


func test_setup_with_no_equipped_items_renders_em_dash_for_all_15_slots() -> void:
	var character := CharacterResourceClass.new()
	character.equipped_items = []

	_panel.setup(character)

	for slot in EquipmentSlotClass.ALL_SLOTS:
		assert_eq(_panel.get_item_text(slot), "—")
		assert_false(_panel.has_charge_indicator(slot))


func test_setup_item_with_no_prepared_spell_shows_no_charge_indicator() -> void:
	var character := CharacterResourceClass.new()
	var shield := _make_item("wooden_shield", EquipmentSlotClass.OFF_HAND, "Wooden Shield", "")
	character.equipped_items = [shield]

	_panel.setup(character)

	assert_eq(_panel.get_item_text(EquipmentSlotClass.OFF_HAND), "Wooden Shield")
	assert_false(
		_panel.has_charge_indicator(EquipmentSlotClass.OFF_HAND),
		"an item with an empty prepared_spell_id must show no charge indicator"
	)


# ── Criterion 4: clear() resets every row, no leftover item data ──────────

func test_clear_resets_every_row_after_prior_setup() -> void:
	var gram_marx = _load_gram_marx()
	assert_not_null(gram_marx, "gram_marx.tres must load non-null")
	if gram_marx == null:
		return

	_panel.setup(gram_marx)
	assert_eq(_panel.get_item_text(EquipmentSlotClass.MAIN_HAND), "Gram's Quarterstaff")

	_panel.clear()

	for slot in EquipmentSlotClass.ALL_SLOTS:
		assert_eq(_panel.get_item_text(slot), "—", "slot %d must be reset to '—' after clear()" % slot)
		assert_false(
			_panel.has_charge_indicator(slot), "slot %d must show no charge indicator after clear()" % slot
		)


func test_clear_does_not_change_row_count_or_order() -> void:
	var gram_marx = _load_gram_marx()
	if gram_marx == null:
		return
	_panel.setup(gram_marx)

	_panel.clear()

	assert_eq(_panel.get_row_count(), 15)
	assert_eq(_panel.get_row_slots(), EquipmentSlotClass.ALL_SLOTS)


func test_setup_after_clear_re_renders_correctly() -> void:
	var gram_marx = _load_gram_marx()
	if gram_marx == null:
		return
	_panel.setup(gram_marx)
	_panel.clear()

	_panel.setup(gram_marx)

	assert_eq(_panel.get_item_text(EquipmentSlotClass.MAIN_HAND), "Gram's Quarterstaff")
	assert_true(_panel.has_charge_indicator(EquipmentSlotClass.MAIN_HAND))


# ── Criterion 5: no row Control has a connected input/click handler ───────

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_script_source_contains_no_button_or_pressed_handler() -> void:
	var source: String = _read_source(EQUIPMENT_PANEL_UI_PATH)
	assert_eq(
		source.findn("Button.new"), -1,
		"equipment_panel_ui.gd must never construct a Button (read-only panel, no interaction)"
	)
	assert_eq(
		source.findn(".pressed.connect"), -1,
		"equipment_panel_ui.gd must never connect a 'pressed' signal handler (read-only panel)"
	)
	assert_eq(
		source.findn("gui_input"), -1,
		"equipment_panel_ui.gd must never handle gui_input (read-only panel, no click handling)"
	)


func test_scene_source_contains_no_connection_block() -> void:
	var source: String = _read_source(EQUIPMENT_PANEL_SCENE_PATH)
	assert_eq(
		source.findn("[connection"), -1,
		"scenes/equipment_panel.tscn must declare no [connection] signal handler blocks"
	)
	assert_eq(
		source.findn("type=\"Button\""), -1,
		"scenes/equipment_panel.tscn must declare no Button nodes"
	)


func test_no_row_node_has_a_connected_signal() -> void:
	_panel.setup(_load_gram_marx())
	for slot in EquipmentSlotClass.ALL_SLOTS:
		var row: Node = _panel.get_node_or_null("Rows/Row_%d" % slot)
		assert_not_null(row, "row node for slot %d must exist" % slot)
		if row == null:
			continue
		assert_eq(
			row.get_signal_connection_list("gui_input").size(), 0,
			"row %d gui_input must have no connected handlers" % slot
		)
		for child in row.get_children():
			assert_false(
				child is BaseButton, "row %d must contain no BaseButton (Button/CheckBox/etc.) child" % slot
			)
