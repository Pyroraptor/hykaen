extends GutTest
## tests/ui/test_rest_panel_short_rest_recharge.gd — FEAT-008 (US-007;
## FR-009; iteration AB-0, rest mechanics steel thread).
##
## GUT UI suite for presentation/rest_panel_controller.gd's
## RestPanelController — the Short Rest MAGE RECHARGE half of FEAT-008.
## Mirrors tests/ui/test_rest_panel_short_rest_heal.gd's "real scene, real
## domain Combatant, no MainScene dependency" convention. Equipped items are
## a duck-typed FakeEquippedItem double (is_charged/energy_cost/
## display_name) — mirroring tests/unit/test_long_rest_use_case.gd's /
## tests/unit/test_short_rest_mage_recharge_use_case.gd's established
## convention that core/resources/item_resource.gd's ItemResource does not
## yet declare an energy_cost field (a later feature's concern).
##
## test_criteria covered (recharge half of FEAT-008):
##   4. Discharged-item rows render only for Mage members with a
##      dischargeable equipped item.
##   5. [Rech] disabled when mage_recharge_budget_remaining==0, enabled
##      otherwise.
##   6. Pressing [Rech] calls ShortRestMageRechargeUseCase via
##      RestActionGuard and re-renders updated budget/item charged-state
##      without closing the panel.
##   7. Repeated Short Rest actions keep the panel open across multiple
##      successive presses.

const RestPanelScene: PackedScene = preload("res://presentation/ui/rest_panel.tscn")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


## FakeEquippedItem — the SAME duck-typed equipped-item double convention
## established by tests/unit/test_long_rest_use_case.gd /
## tests/unit/test_short_rest_mage_recharge_use_case.gd, extended with an
## optional display_name for row-label assertions.
class FakeEquippedItem:
	extends RefCounted
	var is_charged: bool = false
	var energy_cost: int = 0
	var display_name: String = ""

	func _init(p_is_charged: bool = false, p_energy_cost: int = 0, p_display_name: String = "Item") -> void:
		is_charged = p_is_charged
		energy_cost = p_energy_cost
		display_name = p_display_name


func _mage(id: String, name: String, budget_remaining: int, equipped_items: Array = []) -> Combatant:
	var c := CombatantClass.new(id, name, "Player", HexCoordClass.new(0, 0))
	c.mage_recharge_budget_remaining = budget_remaining
	c.equipped_items = equipped_items
	return c


var _panel = null


func before_each() -> void:
	_panel = RestPanelScene.instantiate()
	add_child_autofree(_panel)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: discharged-item rows render only for a Mage member with a
# dischargeable equipped item
# ══════════════════════════════════════════════════════════════════════════

func test_no_item_row_rendered_for_member_with_no_equipped_items() -> void:
	var titus := _mage("titus_1", "Titus", 0, [])

	_panel.open([titus])

	assert_eq(_panel.get_recharge_item_count(0), 0, "a member with no equipped items must render zero discharged-item rows")


func test_no_item_row_rendered_for_a_never_dischargeable_item() -> void:
	var item := FakeEquippedItem.new(false, 0, "Plain Robe")
	var gram := _mage("gram_marx_1", "Gram Marx", 5, [item])

	_panel.open([gram])

	assert_eq(_panel.get_recharge_item_count(0), 0, "an item with energy_cost==0 never discharges and must not render a row")


func test_no_item_row_rendered_for_an_already_charged_dischargeable_item() -> void:
	var item := FakeEquippedItem.new(true, 2, "Orb of Gram")
	var gram := _mage("gram_marx_1", "Gram Marx", 5, [item])

	_panel.open([gram])

	assert_eq(_panel.get_recharge_item_count(0), 0, "an already-charged item must not render a discharged-item row")


func test_item_row_rendered_for_a_discharged_dischargeable_item() -> void:
	var item := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var gram := _mage("gram_marx_1", "Gram Marx", 5, [item])

	_panel.open([gram])

	assert_eq(_panel.get_recharge_item_count(0), 1, "a discharged, dischargeable item must render exactly one row")
	assert_eq(_panel.get_recharge_items(0), [item])


func test_only_discharged_dischargeable_items_render_rows_among_several() -> void:
	var discharged_dischargeable := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var already_charged := FakeEquippedItem.new(true, 2, "Charged Orb")
	var never_dischargeable := FakeEquippedItem.new(false, 0, "Plain Robe")
	var gram := _mage("gram_marx_1", "Gram Marx", 5, [discharged_dischargeable, already_charged, never_dischargeable])

	_panel.open([gram])

	assert_eq(_panel.get_recharge_item_count(0), 1, "only the discharged, dischargeable item must render a row")
	assert_eq(_panel.get_recharge_items(0), [discharged_dischargeable])


func test_recharge_button_text_is_rech() -> void:
	var item := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var gram := _mage("gram_marx_1", "Gram Marx", 5, [item])

	_panel.open([gram])

	assert_eq(_panel.get_recharge_button(0, item).text, "[Rech]")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: [Rech] disabled at budget==0, enabled otherwise
# ══════════════════════════════════════════════════════════════════════════

func test_recharge_button_disabled_when_budget_is_zero() -> void:
	var item := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var gram := _mage("gram_marx_1", "Gram Marx", 0, [item])

	_panel.open([gram])

	assert_true(_panel.get_recharge_button(0, item).disabled, "[Rech] must be disabled when mage_recharge_budget_remaining==0")


func test_recharge_button_enabled_when_budget_is_positive() -> void:
	var item := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var gram := _mage("gram_marx_1", "Gram Marx", 5, [item])

	_panel.open([gram])

	assert_false(_panel.get_recharge_button(0, item).disabled, "[Rech] must be enabled when mage_recharge_budget_remaining>0")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6: pressing [Rech] re-renders updated budget/item state, panel
# stays open
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_recharge_button_charges_item_and_spends_budget_and_keeps_panel_open() -> void:
	var item := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var gram := _mage("gram_marx_1", "Gram Marx", 5, [item])
	_panel.open([gram])

	_panel.get_recharge_button(0, item).pressed.emit()

	assert_true(item.is_charged, "item must become charged after a successful recharge")
	assert_eq(gram.mage_recharge_budget_remaining, 3, "budget must decrement by item.energy_cost")
	assert_true(_panel.is_open(), "panel must remain open after a successful recharge action")
	assert_eq(_panel.get_last_action_result(), {"success": true, "budget_spent": 2, "budget_remaining": 3})


func test_pressing_recharge_button_removes_the_items_row_once_charged() -> void:
	var item := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var gram := _mage("gram_marx_1", "Gram Marx", 5, [item])
	_panel.open([gram])

	_panel.get_recharge_button(0, item).pressed.emit()

	assert_eq(_panel.get_recharge_item_count(0), 0, "a now-charged item must no longer render a discharged-item row")
	assert_null(_panel.get_recharge_button(0, item), "a now-charged item must have no rendered [Rech] button")


func test_pressing_recharge_button_re_renders_updated_budget_text() -> void:
	var item := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var gram := _mage("gram_marx_1", "Gram Marx", 5, [item])
	_panel.open([gram])

	_panel.get_recharge_button(0, item).pressed.emit()

	assert_true(_panel.get_info_text(0).contains("Budget 3"), "re-rendered row must show the updated budget; got: %s" % _panel.get_info_text(0))


func test_pressing_recharge_button_at_zero_budget_is_a_safe_no_op() -> void:
	var item := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var gram := _mage("gram_marx_1", "Gram Marx", 0, [item])
	_panel.open([gram])

	_panel.get_recharge_button(0, item).pressed.emit()

	assert_false(item.is_charged, "item must remain uncharged when budget is insufficient")
	assert_eq(gram.mage_recharge_budget_remaining, 0, "budget must stay unchanged when the recharge use case rejects the action")
	assert_true(_panel.is_open(), "panel must remain open even after a rejected action")
	assert_eq(_panel.get_recharge_item_count(0), 1, "a still-discharged item must keep rendering its row after a rejected action")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 7: repeated Short Rest actions keep the panel open
# ══════════════════════════════════════════════════════════════════════════

func test_repeated_recharge_presses_across_multiple_items_keep_panel_open() -> void:
	var item_a := FakeEquippedItem.new(false, 2, "Orb A")
	var item_b := FakeEquippedItem.new(false, 3, "Orb B")
	var gram := _mage("gram_marx_1", "Gram Marx", 5, [item_a, item_b])
	_panel.open([gram])

	assert_eq(_panel.get_recharge_item_count(0), 2, "both discharged items must render a row before any recharge")

	_panel.get_recharge_button(0, item_a).pressed.emit()
	assert_true(_panel.is_open(), "panel must remain open after the first recharge")
	assert_eq(_panel.get_recharge_item_count(0), 1, "only item_b's row should remain after item_a is recharged")

	_panel.get_recharge_button(0, item_b).pressed.emit()
	assert_true(_panel.is_open(), "panel must remain open after the second recharge")

	assert_true(item_a.is_charged)
	assert_true(item_b.is_charged)
	assert_eq(gram.mage_recharge_budget_remaining, 0, "both recharges together must exactly deplete the budget")
	assert_eq(_panel.get_recharge_item_count(0), 0, "no discharged-item rows should remain once both items are charged")
