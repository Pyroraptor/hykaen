extends GutTest
## tests/ui/test_rest_panel_short_rest_heal.gd — FEAT-008 (US-007; FR-009;
## iteration AB-0, rest mechanics steel thread).
##
## GUT UI suite for presentation/rest_panel_controller.gd's
## RestPanelController — the Short Rest HEAL half of FEAT-008. Mirrors
## tests/ui/test_exploration_hud_rest_button.gd's "real scene, no MainScene
## dependency" convention: the REAL res://presentation/ui/rest_panel.tscn is
## instantiated and driven through its public surface + real Button
## `pressed` signal emission, exercising the panel -> RestActionGuard ->
## ShortRestHealUseCase -> Combatant wiring end-to-end with a real
## core/domain/combatant.gd Combatant (mirrors tests/unit/test_rest_action_
## guard.gd's `_combatant()` convention).
##
## test_criteria covered (heal half of FEAT-008):
##   1. Panel opens defaulting to Short Rest mode with per-member HP/
##      Stamina rows rendered from current Combatant state.
##   2. [+1 Heal] disabled when stamina==0 or hp_current==hp_max, enabled
##      otherwise.
##   3. Pressing [+1 Heal] calls ShortRestHealUseCase via RestActionGuard
##      and re-renders updated hp_current/stamina without closing the panel.
##   7. Repeated Short Rest actions keep the panel open across multiple
##      successive presses.

const RestPanelScene: PackedScene = preload("res://presentation/ui/rest_panel.tscn")
const RestPanelControllerClass = preload("res://presentation/rest_panel_controller.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


func _combatant(id: String, name: String, hp_current: int, hp_max: int, stamina: int) -> Combatant:
	var c := CombatantClass.new(id, name, "Player", HexCoordClass.new(0, 0))
	c.hp_current = hp_current
	c.hp_max = hp_max
	c.stamina = stamina
	return c


var _panel = null


func before_each() -> void:
	_panel = RestPanelScene.instantiate()
	add_child_autofree(_panel)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: opens defaulting to Short Rest mode, per-member rows rendered
# ══════════════════════════════════════════════════════════════════════════

func test_open_defaults_to_short_rest_mode() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)

	_panel.open([titus])

	assert_eq(_panel.get_mode(), RestPanelControllerClass.MODE_SHORT_REST, "panel must default to Short Rest mode on open")
	assert_true(_panel.is_open(), "panel must be open after open()")


func test_open_renders_one_row_per_party_member() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)
	var gram := _combatant("gram_marx_1", "Gram Marx", 15, 15, 4)

	_panel.open([titus, gram])

	assert_eq(_panel.get_member_count(), 2, "panel must render one row per party member")


func test_open_renders_hp_and_stamina_from_current_combatant_state() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)

	_panel.open([titus])

	var info_text: String = _panel.get_info_text(0)
	assert_true(info_text.contains("10"), "rendered row must show current hp_current; got: %s" % info_text)
	assert_true(info_text.contains("20"), "rendered row must show hp_max; got: %s" % info_text)
	assert_true(info_text.contains("Stamina 3"), "rendered row must show current stamina; got: %s" % info_text)


func test_reopening_re_renders_fresh_state() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)
	_panel.open([titus])

	titus.hp_current = 18
	_panel.open([titus])

	assert_true(_panel.get_info_text(0).contains("18"), "re-opening must render the party's CURRENT state, not stale data")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: [+1 Heal] disabled at stamina==0 or hp_current==hp_max
# ══════════════════════════════════════════════════════════════════════════

func test_heal_button_disabled_when_stamina_is_zero() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 0)

	_panel.open([titus])

	assert_true(_panel.get_heal_button(0).disabled, "[+1 Heal] must be disabled when stamina==0")


func test_heal_button_disabled_when_hp_at_max() -> void:
	var titus := _combatant("titus_1", "Titus", 20, 20, 3)

	_panel.open([titus])

	assert_true(_panel.get_heal_button(0).disabled, "[+1 Heal] must be disabled when hp_current==hp_max")


func test_heal_button_enabled_when_stamina_and_hp_allow_healing() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)

	_panel.open([titus])

	assert_false(_panel.get_heal_button(0).disabled, "[+1 Heal] must be enabled when stamina>0 and hp_current<hp_max")


func test_heal_button_text_is_plus_one_heal() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)

	_panel.open([titus])

	assert_eq(_panel.get_heal_button(0).text, "[+1 Heal]")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: pressing [+1 Heal] re-renders updated state, panel stays open
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_heal_button_heals_and_spends_stamina_and_keeps_panel_open() -> void:
	# hp_max 20 -> per-stamina-point heal is ceil(20/4) == 5.
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)

	_panel.open([titus])
	_panel.get_heal_button(0).pressed.emit()

	assert_eq(titus.hp_current, 15, "hp_current must increase by ceil(hp_max/4) for the 1 stamina spent")
	assert_eq(titus.stamina, 2, "stamina must decrement by 1 per press")
	assert_true(_panel.is_open(), "panel must remain open after a successful heal action")
	assert_eq(_panel.get_last_action_result(), {"success": true, "hp_gained": 5, "stamina_spent": 1})


func test_pressing_heal_button_re_renders_updated_hp_and_stamina_text() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)
	_panel.open([titus])

	_panel.get_heal_button(0).pressed.emit()

	var info_text: String = _panel.get_info_text(0)
	assert_true(info_text.contains("15"), "re-rendered row must show updated hp_current; got: %s" % info_text)
	assert_true(info_text.contains("Stamina 2"), "re-rendered row must show updated stamina; got: %s" % info_text)


func test_heal_button_becomes_disabled_once_re_rendered_at_full_hp() -> void:
	# hp_max 4 -> heal amount ceil(4/4) == 1 exactly fills from 3 -> 4.
	var titus := _combatant("titus_1", "Titus", 3, 4, 5)
	_panel.open([titus])

	_panel.get_heal_button(0).pressed.emit()

	assert_eq(titus.hp_current, 4)
	assert_true(_panel.get_heal_button(0).disabled, "re-rendered [+1 Heal] must be disabled once hp_current reaches hp_max")


func test_pressing_heal_button_at_full_hp_is_a_safe_no_op() -> void:
	var titus := _combatant("titus_1", "Titus", 20, 20, 3)
	_panel.open([titus])

	_panel.get_heal_button(0).pressed.emit()

	assert_eq(titus.hp_current, 20, "hp_current must stay unchanged when already full")
	assert_eq(titus.stamina, 3, "stamina must stay unchanged when the heal use case rejects the action")
	assert_true(_panel.is_open(), "panel must remain open even after a rejected action")


func test_pressing_heal_button_with_zero_stamina_is_a_safe_no_op() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 0)
	_panel.open([titus])

	_panel.get_heal_button(0).pressed.emit()

	assert_eq(titus.hp_current, 10, "hp_current must stay unchanged when stamina is insufficient")
	assert_eq(titus.stamina, 0, "stamina must stay unchanged (0) when the heal use case rejects the action")
	assert_true(_panel.is_open(), "panel must remain open even after a rejected action")


func test_healing_one_member_does_not_affect_another_members_row() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)
	var gram := _combatant("gram_marx_1", "Gram Marx", 15, 15, 4)
	_panel.open([titus, gram])

	_panel.get_heal_button(0).pressed.emit()

	assert_eq(gram.hp_current, 15, "healing titus must not change gram's hp_current")
	assert_eq(gram.stamina, 4, "healing titus must not change gram's stamina")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 7: repeated Short Rest actions keep the panel open
# ══════════════════════════════════════════════════════════════════════════

func test_repeated_heal_presses_keep_panel_open_across_multiple_actions() -> void:
	# hp_max 20 -> per-stamina-point heal is ceil(20/4) == 5.
	var titus := _combatant("titus_1", "Titus", 0, 20, 5)
	_panel.open([titus])

	for i in range(3):
		_panel.get_heal_button(0).pressed.emit()
		assert_true(_panel.is_open(), "panel must remain open after press #%d" % (i + 1))

	assert_eq(titus.hp_current, 15, "three heal presses at 5 hp/point must total 15 hp gained")
	assert_eq(titus.stamina, 2, "three heal presses must spend 3 stamina total")
	assert_eq(_panel.get_member_count(), 1, "the panel must still render the (single) party member's row after repeated actions")
