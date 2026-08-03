extends GutTest
## tests/ui/test_rest_panel_toggle.gd — FEAT-010 (US-009; FR-011; ADR-006;
## iteration AB-0, rest mechanics steel thread).
##
## GUT UI suite covering the Rest Panel's open/close TOGGLE behavior.
## Mirrors tests/ui/test_exploration_hud_rest_button.gd's / tests/ui/
## test_rest_panel_long_rest.gd's "real scene(s), no MainScene dependency"
## convention: the REAL res://presentation/exploration_hud.tscn and the REAL
## res://presentation/ui/rest_panel.tscn are instantiated together and wired
## exactly the way a composition root (MainScene.gd, out of this feature's
## scope) would wire them — ExplorationHUD.set_rest_panel(panel) — then
## driven through real Button `pressed` signal emission.
##
## test_criteria covered (FEAT-010):
##   1. First press of HUD Rest button opens the panel.
##   2. Second press of HUD Rest button while panel is open closes the
##      panel.
##   3. Pressing the explicit close (X) button closes the panel regardless
##      of prior open state.
##   4. Panel open/closed boolean is not read from or written to any
##      Combatant/domain/application object — toggling performs no use-case
##      invocation and mutates no Combatant/item field.

const ExplorationHudScene: PackedScene = preload("res://presentation/exploration_hud.tscn")
const RestPanelScene: PackedScene = preload("res://presentation/ui/rest_panel.tscn")
const RestPanelControllerClass = preload("res://presentation/rest_panel_controller.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


## FakeEquippedItem — the SAME duck-typed equipped-item double convention
## established by tests/ui/test_rest_panel_short_rest_recharge.gd /
## tests/ui/test_rest_panel_long_rest.gd.
class FakeEquippedItem:
	extends RefCounted
	var is_charged: bool = false
	var energy_cost: int = 0
	var display_name: String = ""

	func _init(p_is_charged: bool = false, p_energy_cost: int = 0, p_display_name: String = "Item") -> void:
		is_charged = p_is_charged
		energy_cost = p_energy_cost
		display_name = p_display_name


func _combatant(id: String, name: String, hp_current: int, hp_max: int, stamina: int, equipped_items: Array = []) -> Combatant:
	var c := CombatantClass.new(id, name, "Player", HexCoordClass.new(0, 0))
	c.hp_current = hp_current
	c.hp_max = hp_max
	c.stamina = stamina
	c.equipped_items = equipped_items
	return c


var _hud = null
var _panel = null


func before_each() -> void:
	_hud = ExplorationHudScene.instantiate()
	add_child_autofree(_hud)
	_panel = RestPanelScene.instantiate()
	add_child_autofree(_panel)
	_hud.set_rest_panel(_panel)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: first press of HUD Rest button opens the panel
# ══════════════════════════════════════════════════════════════════════════

func test_first_press_of_rest_button_opens_the_panel() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1)
	_hud.set_party([titus])
	assert_false(_panel.is_open(), "panel must start closed")

	_hud.get_rest_button().pressed.emit()

	assert_true(_panel.is_open(), "first press of the Rest Button must open the panel")
	assert_true(_panel.visible, "the panel Control node must become visible on open")


func test_first_press_of_rest_button_still_emits_rest_panel_requested() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1)
	_hud.set_party([titus])
	watch_signals(_hud)

	_hud.get_rest_button().pressed.emit()

	assert_signal_emitted(_hud, "rest_panel_requested", "wiring a panel must not remove the existing FEAT-007 signal contract")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: second press while open closes the panel (re-press to close)
# ══════════════════════════════════════════════════════════════════════════

func test_second_press_of_rest_button_while_open_closes_the_panel() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1)
	_hud.set_party([titus])
	_hud.get_rest_button().pressed.emit()
	assert_true(_panel.is_open(), "sanity: panel must be open after the first press")

	_hud.get_rest_button().pressed.emit()

	assert_false(_panel.is_open(), "second press of the Rest Button while open must close the panel")
	assert_false(_panel.visible, "the panel Control node must become invisible on close")


func test_third_press_of_rest_button_reopens_the_panel() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1)
	_hud.set_party([titus])
	_hud.get_rest_button().pressed.emit()  # open
	_hud.get_rest_button().pressed.emit()  # close

	_hud.get_rest_button().pressed.emit()  # open again

	assert_true(_panel.is_open(), "a third press must re-open the panel (toggle, not a one-shot latch)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: explicit close (X) button closes the panel regardless of
# prior open state
# ══════════════════════════════════════════════════════════════════════════

func test_close_button_is_present() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1)
	_panel.open([titus])

	assert_not_null(_panel.get_close_button(), "panel must render an explicit close (X) button")


func test_pressing_close_button_closes_an_open_panel_in_short_rest_mode() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1)
	_panel.open([titus])
	assert_true(_panel.is_open())

	_panel.get_close_button().pressed.emit()

	assert_false(_panel.is_open(), "pressing the close button must close the panel")
	assert_false(_panel.visible, "the panel Control node must become invisible on close")


func test_pressing_close_button_closes_an_open_panel_in_long_rest_mode() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1)
	_panel.open([titus])
	_panel.get_long_rest_tab_button().pressed.emit()
	assert_eq(_panel.get_mode(), RestPanelControllerClass.MODE_LONG_REST)

	_panel.get_close_button().pressed.emit()

	assert_false(_panel.is_open(), "the close button must close the panel regardless of which tab/mode is active")


func test_pressing_close_button_via_hud_wiring_closes_the_panel() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1)
	_hud.set_party([titus])
	_hud.get_rest_button().pressed.emit()
	assert_true(_panel.is_open())

	_panel.get_close_button().pressed.emit()

	assert_false(_panel.is_open(), "the close button must close a panel that was opened via the HUD Rest Button")


func test_pressing_close_button_when_already_closed_is_a_safe_no_op() -> void:
	assert_false(_panel.is_open(), "sanity: panel must start closed")

	_panel.get_close_button().pressed.emit()

	assert_false(_panel.is_open(), "pressing close on an already-closed panel must remain closed, not toggle back open")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: open/closed boolean is pure UI state — never read from or
# written to any Combatant/domain/application object
# ══════════════════════════════════════════════════════════════════════════

func test_toggling_open_and_closed_mutates_no_combatant_or_item_field() -> void:
	var item := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var titus := _combatant("titus_1", "Titus", 5, 20, 1, [item])
	var before_hp := titus.hp_current
	var before_stamina := titus.stamina
	var before_charged := item.is_charged

	_hud.set_party([titus])
	_hud.get_rest_button().pressed.emit()  # open
	_hud.get_rest_button().pressed.emit()  # close
	_panel.open([titus])
	_panel.get_close_button().pressed.emit()  # close via X button

	assert_eq(titus.hp_current, before_hp, "toggling open/closed must never mutate hp_current")
	assert_eq(titus.stamina, before_stamina, "toggling open/closed must never mutate stamina")
	assert_eq(item.is_charged, before_charged, "toggling open/closed must never mutate an equipped item's is_charged")
	assert_eq(_panel.get_last_action_result(), {}, "toggling open/closed must never invoke a use case via RestActionGuard")


func test_combatant_object_exposes_no_panel_open_state() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1)
	_panel.open([titus])

	assert_null(titus.get("is_open"), "the domain Combatant must never carry the panel's open/closed boolean")
	assert_null(titus.get("panel_open"), "the domain Combatant must never carry the panel's open/closed boolean")
