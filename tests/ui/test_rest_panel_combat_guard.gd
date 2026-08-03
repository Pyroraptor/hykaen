extends GutTest
## tests/ui/test_rest_panel_combat_guard.gd — FEAT-372 (US-010; FR-012,
## ADR-005; iteration AB-0, rest mechanics steel thread).
##
## GUT UI suite for presentation/rest_panel_controller.gd's
## RestPanelController — API/presentation integration confirming every
## action button routes EXCLUSIVELY through core/api/rest_action_guard.gd's
## RestActionGuard (FEAT-006) rather than calling
## LongRestUseCase/ShortRestHealUseCase/ShortRestMageRechargeUseCase
## directly, and that a guard short-circuit (ERR_OUT_OF_COMBAT_ONLY) is
## surfaced on an on-panel error label. Mirrors tests/ui/
## test_rest_panel_short_rest_heal.gd's / tests/ui/test_rest_panel_long_rest
## .gd's "real scene, real domain Combatant, no MainScene dependency"
## convention: the REAL res://presentation/ui/rest_panel.tscn is
## instantiated and driven through its public surface + real Button
## `pressed` signal emission.
##
## test_criteria covered:
##   1. Simulated COMBAT-mode invocation attempt via the panel is blocked
##      (use case is not invoked, no state mutation occurs).
##   2. Error label becomes visible and displays the
##      ERR_OUT_OF_COMBAT_ONLY condition when a guard short-circuit occurs.
##   3. Mid-session scenario: panel opened in EXPLORATION mode, mode flips
##      to COMBAT while panel remains open, subsequent action press is
##      still blocked by the guard with the error label shown.
##   4. rest_panel_controller.gd contains no direct (unguarded) call path
##      to LongRestUseCase/ShortRestHealUseCase/ShortRestMageRechargeUseCase
##      (static source check).

const RestPanelScene: PackedScene = preload("res://presentation/ui/rest_panel.tscn")
const RestPanelControllerClass = preload("res://presentation/rest_panel_controller.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const GameModeReaderClass = preload("res://core/api/game_mode_reader.gd")
const ErrorCodeClass = preload("res://core/application/ports/errors.gd")


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


func _combatant(
	id: String, name: String,
	hp_current: int, hp_max: int,
	stamina: int, stamina_max: int = 0,
	intellect: int = 0, mage_recharge_budget_remaining: int = 0,
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
# Criteria 1 & 2: COMBAT-mode Heal press is blocked, no mutation, error
# label shown
# ══════════════════════════════════════════════════════════════════════════

func test_error_label_hidden_by_default_on_open() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)

	_panel.open([titus], GameModeReaderClass.EXPLORATION)

	assert_false(_panel.get_error_label().visible, "error label must be hidden before any guard short-circuit")


func test_pressing_heal_button_in_combat_mode_is_blocked_and_shows_error_label() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)
	_panel.open([titus], GameModeReaderClass.COMBAT)

	_panel.get_heal_button(0).pressed.emit()

	assert_eq(titus.hp_current, 10, "hp_current must stay unchanged when the guard blocks the heal action")
	assert_eq(titus.stamina, 3, "stamina must stay unchanged when the guard blocks the heal action")
	assert_eq(_panel.get_last_action_result(), {"success": false, "error": ErrorCodeClass.ERR_OUT_OF_COMBAT_ONLY})
	assert_true(_panel.get_error_label().visible, "error label must become visible when the guard short-circuits")
	assert_true(_panel.get_error_label().text.contains("ERR_OUT_OF_COMBAT_ONLY"),
		"error label text must surface the ERR_OUT_OF_COMBAT_ONLY condition; got: %s" % _panel.get_error_label().text)


func test_pressing_recharge_button_in_combat_mode_is_blocked_and_shows_error_label() -> void:
	var item := FakeEquippedItem.new(false, 2, "Orb of Gram")
	var gram := _combatant("gram_marx_1", "Gram Marx", 15, 15, 4, 4, 5, 5, [item])
	_panel.open([gram], GameModeReaderClass.COMBAT)

	_panel.get_recharge_button(0, item).pressed.emit()

	assert_false(item.is_charged, "item must stay uncharged when the guard blocks the recharge action")
	assert_eq(gram.mage_recharge_budget_remaining, 5, "budget must stay unchanged when the guard blocks the recharge action")
	assert_eq(_panel.get_last_action_result(), {"success": false, "error": ErrorCodeClass.ERR_OUT_OF_COMBAT_ONLY})
	assert_true(_panel.get_error_label().visible, "error label must become visible when the guard short-circuits a recharge attempt")


func test_confirming_long_rest_in_combat_mode_shows_error_label() -> void:
	var titus := _combatant("titus_1", "Titus", 5, 20, 1, 4)
	_panel.open([titus], GameModeReaderClass.COMBAT)
	_panel.get_long_rest_tab_button().pressed.emit()

	_panel.get_confirm_long_rest_button().pressed.emit()

	assert_eq(titus.hp_current, 5, "hp_current must stay unchanged when the guard blocks the confirmation")
	assert_true(_panel.get_error_label().visible, "error label must become visible when the guard short-circuits a Long Rest confirmation")
	assert_true(_panel.is_open(), "panel must remain open when the guard blocks the confirmation")


func test_error_label_hidden_again_after_a_subsequent_successful_action() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)
	_panel.open([titus], GameModeReaderClass.COMBAT)
	_panel.get_heal_button(0).pressed.emit()
	assert_true(_panel.get_error_label().visible, "sanity: error label must be visible after the blocked attempt")

	_panel.set_game_mode(GameModeReaderClass.EXPLORATION)
	_panel.get_heal_button(0).pressed.emit()

	assert_eq(titus.hp_current, 15, "heal must apply once no longer blocked by the guard")
	assert_false(_panel.get_error_label().visible, "error label must hide again once a subsequent action succeeds")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: mid-session mode flip -- panel opened in EXPLORATION, mode
# flips to COMBAT while the panel remains open, a subsequent action press
# is still blocked with the error label shown (RISK-007 mitigation).
# ══════════════════════════════════════════════════════════════════════════

func test_mid_session_mode_flip_to_combat_blocks_subsequent_action_and_shows_error_label() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)
	_panel.open([titus], GameModeReaderClass.EXPLORATION)
	assert_true(_panel.is_open(), "panel must be open in EXPLORATION mode")
	assert_false(_panel.get_error_label().visible, "error label must not be visible immediately after opening in EXPLORATION mode")

	# Simulate an ambush/mode transition while the panel is still open --
	# the panel's own open/closed state (ADR-006) is untouched by this;
	# only the shared game-mode read changes, exactly mirroring how a real
	# MainScene._current_game_mode flip would be observed by this
	# controller (design notes' RISK-007 mitigation).
	_panel.set_game_mode(GameModeReaderClass.COMBAT)
	assert_true(_panel.is_open(), "the mode flip itself must not close the panel -- only the guard blocks the subsequent action")

	_panel.get_heal_button(0).pressed.emit()

	assert_eq(titus.hp_current, 10, "hp_current must stay unchanged -- the guard must block using the CURRENT (COMBAT) mode, not the mode at open() time")
	assert_eq(titus.stamina, 3, "stamina must stay unchanged when the guard blocks the action")
	assert_eq(_panel.get_last_action_result(), {"success": false, "error": ErrorCodeClass.ERR_OUT_OF_COMBAT_ONLY})
	assert_true(_panel.get_error_label().visible, "error label must become visible once the mid-session mode flip blocks an action")
	assert_true(_panel.is_open(), "panel must remain open (the guard blocks the ACTION, not the panel itself)")


func test_mid_session_mode_flip_back_to_exploration_unblocks_action() -> void:
	var titus := _combatant("titus_1", "Titus", 10, 20, 3)
	_panel.open([titus], GameModeReaderClass.EXPLORATION)
	_panel.set_game_mode(GameModeReaderClass.COMBAT)
	_panel.get_heal_button(0).pressed.emit()
	assert_eq(titus.hp_current, 10, "sanity: blocked while in COMBAT")

	# Combat resolves; back to EXPLORATION while the panel is STILL open.
	_panel.set_game_mode(GameModeReaderClass.EXPLORATION)
	_panel.get_heal_button(0).pressed.emit()

	assert_eq(titus.hp_current, 15, "heal must succeed once the shared game-mode read returns to EXPLORATION")
	assert_false(_panel.get_error_label().visible, "error label must hide again once the action succeeds")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: static check -- no direct (unguarded) call path to any of
# the three rest use cases from rest_panel_controller.gd.
# ══════════════════════════════════════════════════════════════════════════

func test_controller_source_has_no_direct_unguarded_use_case_call() -> void:
	var source := FileAccess.get_file_as_string("res://presentation/rest_panel_controller.gd")
	var use_case_call_needles := [
		"_heal_use_case.execute(",
		"_recharge_use_case.execute(",
		"_long_rest_use_case.execute(",
		"use_case.execute(",
	]
	var found_any_use_case_call := false
	for line in source.split("\n"):
		for needle in use_case_call_needles:
			if line.contains(needle):
				found_any_use_case_call = true
				assert_true(line.contains("_guard.invoke("),
					"every use-case invocation must be routed through _guard.invoke() on the same statement; offending line: %s" % line)
	assert_true(found_any_use_case_call, "sanity: the controller must actually invoke the rest use cases somewhere (otherwise this check is vacuous)")


func test_controller_source_never_calls_use_case_execute_outside_a_guard_invoke_bound_callable() -> void:
	# A stricter complementary check: the controller must never hold a
	# direct reference-call pattern like `_heal_use_case.execute(` /
	# `_recharge_use_case.execute(` / `_long_rest_use_case.execute(` at
	# all -- every call site goes through the local `use_case` alias bound
	# inside a Callable literally passed as _guard.invoke()'s second
	# argument (see rest_panel_controller.gd's own action handlers).
	var source := FileAccess.get_file_as_string("res://presentation/rest_panel_controller.gd")
	for banned in ["_heal_use_case.execute(", "_recharge_use_case.execute(", "_long_rest_use_case.execute("]:
		assert_false(source.contains(banned),
			"%s must not appear -- use cases must only ever be invoked via the `use_case` Callable bound inside _guard.invoke()" % banned)
