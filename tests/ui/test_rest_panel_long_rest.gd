extends GutTest
## tests/ui/test_rest_panel_long_rest.gd — FEAT-009 (US-008; FR-010;
## iteration AB-0, rest mechanics steel thread).
##
## GUT UI suite for presentation/rest_panel_controller.gd's
## RestPanelController — the LONG REST half of the Rest Panel (FEAT-009).
## Mirrors tests/ui/test_rest_panel_short_rest_heal.gd's / tests/ui/
## test_rest_panel_short_rest_recharge.gd's "real scene, real domain
## Combatant, no MainScene dependency" convention: the REAL
## res://presentation/ui/rest_panel.tscn is instantiated and driven through
## its public surface + real Button `pressed` signal emission, exercising
## the panel -> RestActionGuard -> LongRestUseCase -> Combatant/ItemResource
## wiring end-to-end.
##
## test_criteria covered (FEAT-009):
##   1. Long Rest tab/toggle is present and switches the panel's displayed
##      mode.
##   2. Confirming Long Rest calls LongRestUseCase (via RestActionGuard)
##      against the full party.
##   3. After a successful confirmation, every party combatant's
##      hp_current/stamina/mage_recharge_budget_remaining/item charged
##      flags reflect full restoration in the rendered UI immediately
##      before close.
##   4. Panel closes automatically after a successful Long Rest
##      confirmation (exit_point behavior for Long Rest).

const RestPanelScene: PackedScene = preload("res://presentation/ui/rest_panel.tscn")
const RestPanelControllerClass = preload("res://presentation/rest_panel_controller.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const GameModeReaderClass = preload("res://core/api/game_mode_reader.gd")
const ErrorCodeClass = preload("res://core/application/ports/errors.gd")


## FakeEquippedItem — the SAME duck-typed equipped-item double convention
## established by tests/ui/test_rest_panel_short_rest_recharge.gd /
## tests/unit/test_long_rest_use_case.gd.
class FakeEquippedItem:
	extends RefCounted
	var is_charged: bool = false
	var energy_cost: int = 0
	var display_name: String = ""

	func _init(p_is_charged: bool = false, p_energy_cost: int = 0, p_display_name: String = "Item") -> void:
		is_charged = p_is_charged
		energy_cost = p_energy_cost
		display_name = p_display_name


func _combatant(
	id: String, name: String,
	hp_current: int, hp_max: int,
	stamina: int, stamina_max: int,
	intellect: int, mage_recharge_budget_remaining: int,
	equipped_items: Array = []
) -> Combatant:
	var c := CombatantClass.new(id, name, "Player", HexCoordClass.new(0, 0))
	c.hp_current = hp_current
	c.hp_max = hp_max
	c.stamina = stamina
	c.stamina_max = stamina_max
	c.intellect = intellect
	c.mage_recharge_budget_remaining = mage_recharge_budget_remaining
	c.equipped_items = equipped_items
	return c


var _panel = null


func before_each() -> void:
	_panel = RestPanelScene.instantiate()
	add_child_autofree(_panel)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: Long Rest tab/toggle present, switches the displayed mode
# ══════════════════════════════════════════════════════════════════════════

func test_long_rest_tab_button_is_present() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 2, 4, 0, 0)
	_panel.open([titus])

	assert_not_null(_panel.get_long_rest_tab_button(), "panel must render a Long Rest tab/toggle button")


func test_short_rest_tab_button_is_present() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 2, 4, 0, 0)
	_panel.open([titus])

	assert_not_null(_panel.get_short_rest_tab_button(), "panel must render a Short Rest tab/toggle button")


func test_pressing_long_rest_tab_switches_the_panels_displayed_mode() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 2, 4, 0, 0)
	_panel.open([titus])
	assert_eq(_panel.get_mode(), RestPanelControllerClass.MODE_SHORT_REST, "panel must default to Short Rest mode on open")

	_panel.get_long_rest_tab_button().pressed.emit()

	assert_eq(_panel.get_mode(), RestPanelControllerClass.MODE_LONG_REST, "pressing the Long Rest tab must switch the panel to Long Rest mode")


func test_pressing_short_rest_tab_after_long_rest_switches_back() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 2, 4, 0, 0)
	_panel.open([titus])
	_panel.get_long_rest_tab_button().pressed.emit()

	_panel.get_short_rest_tab_button().pressed.emit()

	assert_eq(_panel.get_mode(), RestPanelControllerClass.MODE_SHORT_REST, "pressing the Short Rest tab must switch back to Short Rest mode")


func test_confirm_long_rest_button_is_hidden_in_short_rest_mode_and_shown_in_long_rest_mode() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 2, 4, 0, 0)
	_panel.open([titus])

	assert_false(_panel.get_confirm_long_rest_button().visible, "Confirm Long Rest button must be hidden while in Short Rest mode")

	_panel.get_long_rest_tab_button().pressed.emit()

	assert_true(_panel.get_confirm_long_rest_button().visible, "Confirm Long Rest button must become visible once switched to Long Rest mode")


func test_confirm_long_rest_button_text() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 2, 4, 0, 0)
	_panel.open([titus])
	_panel.get_long_rest_tab_button().pressed.emit()

	assert_eq(_panel.get_confirm_long_rest_button().text, "Confirm Long Rest")


func test_reopening_always_resets_to_short_rest_mode_even_after_long_rest_tab() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 2, 4, 0, 0)
	_panel.open([titus])
	_panel.get_long_rest_tab_button().pressed.emit()

	_panel.open([titus])

	assert_eq(_panel.get_mode(), RestPanelControllerClass.MODE_SHORT_REST, "re-opening must always reset to Short Rest mode, even if Long Rest was last active")
	assert_false(_panel.get_confirm_long_rest_button().visible, "Confirm Long Rest button must be hidden again after a re-open resets to Short Rest mode")


# ══════════════════════════════════════════════════════════════════════════
# Criteria 2 & 3: confirming Long Rest calls LongRestUseCase (via
# RestActionGuard) against the full party; rendered UI reflects full
# restoration before close
# ══════════════════════════════════════════════════════════════════════════

func test_confirming_long_rest_restores_every_party_members_hp_and_stamina() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1, 4, 0, 0)
	var gram := _combatant("gram_marx_1", "Gram Marx", 3, 15, 0, 4, 5, 1)
	_panel.open([titus, gram])
	_panel.get_long_rest_tab_button().pressed.emit()

	_panel.get_confirm_long_rest_button().pressed.emit()

	assert_eq(titus.hp_current, 20, "Titus's hp_current must be fully restored")
	assert_eq(titus.stamina, 4, "Titus's stamina must be fully restored")
	assert_eq(gram.hp_current, 15, "Gram's hp_current must be fully restored")
	assert_eq(gram.stamina, 4, "Gram's stamina must be fully restored")


func test_confirming_long_rest_restores_mage_recharge_budget_and_recharges_items() -> void:
	var item := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var gram := _combatant("gram_marx_1", "Gram Marx", 3, 15, 0, 4, 5, 1, [item])
	_panel.open([gram])
	_panel.get_long_rest_tab_button().pressed.emit()

	_panel.get_confirm_long_rest_button().pressed.emit()

	assert_eq(gram.mage_recharge_budget_remaining, 5, "Gram's mage_recharge_budget_remaining must restore to intellect")
	assert_true(item.is_charged, "Gram's discharged item must become charged")


func test_confirming_long_rest_returns_success_and_restored_combatants_count() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1, 4, 0, 0)
	var gram := _combatant("gram_marx_1", "Gram Marx", 3, 15, 0, 4, 5, 1)
	_panel.open([titus, gram])
	_panel.get_long_rest_tab_button().pressed.emit()

	_panel.get_confirm_long_rest_button().pressed.emit()

	assert_eq(_panel.get_last_action_result(), {"success": true, "restored_combatants": 2},
		"confirming Long Rest must call LongRestUseCase against the FULL party (both members), not a single row")


func test_confirming_long_rest_rendered_ui_shows_fully_restored_hp_and_stamina_before_close() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1, 4, 0, 0)
	_panel.open([titus])
	_panel.get_long_rest_tab_button().pressed.emit()

	_panel.get_confirm_long_rest_button().pressed.emit()

	var info_text: String = _panel.get_info_text(0)
	assert_true(info_text.contains("20/20"), "rendered row must show fully-restored hp_current/hp_max; got: %s" % info_text)
	assert_true(info_text.contains("Stamina 4"), "rendered row must show fully-restored stamina; got: %s" % info_text)


func test_confirming_long_rest_rendered_ui_shows_restored_budget_before_close() -> void:
	var orb := FakeEquippedItem.new(true, 1, "Orb of Gram")
	var gram := _combatant("gram_marx_1", "Gram Marx", 3, 15, 0, 4, 5, 1, [orb])
	_panel.open([gram])
	_panel.get_long_rest_tab_button().pressed.emit()

	_panel.get_confirm_long_rest_button().pressed.emit()

	var info_text: String = _panel.get_info_text(0)
	assert_true(info_text.contains("Budget 5"), "rendered row must show the fully-restored mage_recharge_budget_remaining; got: %s" % info_text)


func test_confirming_long_rest_rendered_ui_shows_no_discharged_item_rows_before_close() -> void:
	var item := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var gram := _combatant("gram_marx_1", "Gram Marx", 3, 15, 0, 4, 5, 1, [item])
	_panel.open([gram])
	_panel.get_long_rest_tab_button().pressed.emit()

	_panel.get_confirm_long_rest_button().pressed.emit()

	assert_eq(_panel.get_recharge_item_count(0), 0, "no discharged-item rows should remain rendered once every item is recharged by Long Rest")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: panel closes automatically after a successful confirmation
# ══════════════════════════════════════════════════════════════════════════

func test_confirming_long_rest_closes_the_panel() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1, 4, 0, 0)
	_panel.open([titus])
	_panel.get_long_rest_tab_button().pressed.emit()

	_panel.get_confirm_long_rest_button().pressed.emit()

	assert_false(_panel.is_open(), "panel must close automatically after a successful Long Rest confirmation")
	assert_false(_panel.visible, "the panel Control node must become invisible after an automatic close")


# ══════════════════════════════════════════════════════════════════════════
# Out-of-combat guard: Long Rest is routed through RestActionGuard exactly
# like Short Rest actions -- blocked in COMBAT mode, no state mutation, no
# automatic close.
# ══════════════════════════════════════════════════════════════════════════

func test_confirming_long_rest_in_combat_mode_is_blocked_by_the_guard_and_does_not_close() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1, 4, 0, 0)
	_panel.open([titus], GameModeReaderClass.COMBAT)
	_panel.get_long_rest_tab_button().pressed.emit()

	_panel.get_confirm_long_rest_button().pressed.emit()

	assert_eq(titus.hp_current, 5, "hp_current must stay unchanged when the guard blocks the confirmation")
	assert_eq(titus.stamina, 1, "stamina must stay unchanged when the guard blocks the confirmation")
	assert_true(_panel.is_open(), "panel must remain open when the guard blocks the confirmation")
	assert_eq(_panel.get_last_action_result(), {"success": false, "error": ErrorCodeClass.ERR_OUT_OF_COMBAT_ONLY})
