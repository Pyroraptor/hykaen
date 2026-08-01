extends GutTest
## tests/unit/presentation/test_equipment_panel_toggle_controller.gd —
## FEAT-010 (US-011 / FR-010, mitigates RISK-007).
##
## Unit-level GUT suite for the new presentation/
## equipment_panel_toggle_controller.gd -- EquipmentPanelToggleController --
## in isolation, against hand-written fakes standing in for the
## EquipmentPanelUI panel / ExplorationModeController / ScenarioSession /
## Combatant roster (mirrors tests/unit/presentation/
## test_combat_camera_follow_use_case.gd's own fake-collaborator
## convention). The REAL, booted res://MainScene.tscn end-to-end scenarios
## (actual 'E' keypress, actual CharacterResource fixtures) are covered
## separately by tests/scene/test_main_scene_equipment_toggle.gd; this suite
## instead pins the controller's own unit-level contract so a future
## refactor of MainScene.gd's wiring can't silently break it without a
## fast, non-headless-boot signal.
##
## test_criteria covered (unit-level restatement of FEAT-010's own):
##   1. handle_input() returns false (event not consumed) for any event that
##      is not a fresh, pressed 'E' keydown -- an echo, a keyup, a
##      different keycode, or a non-InputEventKey event.
##   2. toggle() while closed with a resolvable selection calls setup() on
##      the panel with the resolved character and shows it.
##   3. toggle() while open calls clear() on the panel, hides it, and flips
##      is_open() back to false.
##   4. toggle() while closed with NO resolvable selection (no selection at
##      all, no scenario/party, or an unmatched/unmapped id) is a no-op --
##      the panel is never shown/setup(), and is_open() stays false. This is
##      RISK-007's dedicated negative-case coverage at the unit level.
##   5. A null `panel` is a safe no-op (defensive guard).

const EquipmentPanelToggleControllerClass = preload("res://presentation/equipment_panel_toggle_controller.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

class _FakePanel:
	extends RefCounted
	var visible: bool = false
	var setup_calls: Array = []
	var clear_call_count: int = 0

	func setup(character) -> void:
		setup_calls.append(character)

	func clear() -> void:
		clear_call_count += 1


class _FakeExploration:
	extends RefCounted
	var selected_party_member_id: String = ""


class _FakeParty:
	extends RefCounted
	var character_resource_paths: Array = []


class _FakeScenario:
	extends RefCounted
	var party = null


class _FakeScenarioSession:
	extends RefCounted
	var scenario = null


class _FakeCombatant:
	extends RefCounted
	var _id: String

	func _init(id: String) -> void:
		_id = id

	func display_id() -> String:
		return _id


func _make_e_key_event(pressed: bool = true, echo: bool = false, keycode: int = KEY_E) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = pressed
	event.echo = echo
	event.keycode = keycode
	return event


## _make_resolvable_context() -> Dictionary — a fully-wired
## exploration/scenario_session/party trio where "player_0" resolves to a
## fake CharacterResource stand-in via character_resource_paths[0].
func _make_resolvable_context() -> Dictionary:
	var exploration := _FakeExploration.new()
	exploration.selected_party_member_id = "player_0"

	var party_resource := _FakeParty.new()
	party_resource.character_resource_paths = ["res://data/characters/titus.tres"]

	var scenario := _FakeScenario.new()
	scenario.party = party_resource

	var scenario_session := _FakeScenarioSession.new()
	scenario_session.scenario = scenario

	var party: Array = [_FakeCombatant.new("player_0")]

	return {
		"exploration": exploration,
		"scenario_session": scenario_session,
		"party": party,
	}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — handle_input() only consumes a fresh, pressed 'E' keydown.
# ══════════════════════════════════════════════════════════════════════════

func test_handle_input_returns_false_for_echo_e_keydown() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var panel := _FakePanel.new()
	var ctx: Dictionary = _make_resolvable_context()

	var consumed: bool = controller.handle_input(
		_make_e_key_event(true, true), panel, ctx["exploration"], ctx["scenario_session"], ctx["party"]
	)

	assert_false(consumed, "an echo 'E' keydown must not be consumed")
	assert_false(panel.visible, "an echo 'E' keydown must never open the panel")


func test_handle_input_returns_false_for_e_keyup() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var panel := _FakePanel.new()
	var ctx: Dictionary = _make_resolvable_context()

	var consumed: bool = controller.handle_input(
		_make_e_key_event(false), panel, ctx["exploration"], ctx["scenario_session"], ctx["party"]
	)

	assert_false(consumed, "an 'E' keyup must not be consumed")


func test_handle_input_returns_false_for_a_different_keycode() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var panel := _FakePanel.new()
	var ctx: Dictionary = _make_resolvable_context()

	var consumed: bool = controller.handle_input(
		_make_e_key_event(true, false, KEY_Q), panel, ctx["exploration"], ctx["scenario_session"], ctx["party"]
	)

	assert_false(consumed, "a non-'E' keycode must not be consumed")


func test_handle_input_returns_false_for_a_non_key_event() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var panel := _FakePanel.new()
	var ctx: Dictionary = _make_resolvable_context()
	var mouse_event := InputEventMouseButton.new()
	mouse_event.pressed = true

	var consumed: bool = controller.handle_input(
		mouse_event, panel, ctx["exploration"], ctx["scenario_session"], ctx["party"]
	)

	assert_false(consumed, "a non-InputEventKey event must not be consumed")


func test_handle_input_returns_true_and_toggles_for_a_fresh_e_keydown() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var panel := _FakePanel.new()
	var ctx: Dictionary = _make_resolvable_context()

	var consumed: bool = controller.handle_input(
		_make_e_key_event(), panel, ctx["exploration"], ctx["scenario_session"], ctx["party"]
	)

	assert_true(consumed, "a fresh, pressed 'E' keydown must be consumed")
	assert_true(panel.visible, "handle_input() must drive toggle() through to opening the panel")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — toggle() while closed, resolvable selection: setup() + show.
# ══════════════════════════════════════════════════════════════════════════

func test_toggle_while_closed_with_resolvable_selection_calls_setup_and_shows_panel() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var panel := _FakePanel.new()
	var ctx: Dictionary = _make_resolvable_context()

	controller.toggle(panel, ctx["exploration"], ctx["scenario_session"], ctx["party"])

	assert_true(panel.visible, "toggle() while closed must show the panel on a resolvable selection")
	assert_eq(panel.setup_calls.size(), 1, "toggle() while closed must call setup() exactly once")
	assert_true(controller.is_open(), "is_open() must be true after opening")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — toggle() while open: clear() + hide + is_open() false.
# ══════════════════════════════════════════════════════════════════════════

func test_toggle_while_open_calls_clear_and_hides_panel() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var panel := _FakePanel.new()
	var ctx: Dictionary = _make_resolvable_context()

	controller.toggle(panel, ctx["exploration"], ctx["scenario_session"], ctx["party"])  # open
	controller.toggle(panel, ctx["exploration"], ctx["scenario_session"], ctx["party"])  # close

	assert_false(panel.visible, "toggle() while open must hide the panel")
	assert_eq(panel.clear_call_count, 1, "toggle() while open must call clear() exactly once")
	assert_false(controller.is_open(), "is_open() must be false after closing")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (RISK-007) — toggle() while closed, no resolvable selection:
# a no-op that never opens/setup()s and never crashes.
# ══════════════════════════════════════════════════════════════════════════

func test_toggle_with_no_selection_is_a_noop() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var panel := _FakePanel.new()
	var ctx: Dictionary = _make_resolvable_context()
	ctx["exploration"].selected_party_member_id = ""

	controller.toggle(panel, ctx["exploration"], ctx["scenario_session"], ctx["party"])

	assert_false(panel.visible, "no selection must leave the panel hidden")
	assert_eq(panel.setup_calls.size(), 0, "no selection must never call setup()")
	assert_false(controller.is_open(), "no selection must leave is_open() false")


func test_toggle_with_no_scenario_session_is_a_noop() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var panel := _FakePanel.new()
	var exploration := _FakeExploration.new()
	exploration.selected_party_member_id = "player_0"

	controller.toggle(panel, exploration, null, [_FakeCombatant.new("player_0")])

	assert_false(panel.visible, "a null scenario_session must leave the panel hidden")
	assert_false(controller.is_open())


func test_toggle_with_unmatched_party_member_id_is_a_noop() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var panel := _FakePanel.new()
	var ctx: Dictionary = _make_resolvable_context()
	ctx["exploration"].selected_party_member_id = "player_99"

	controller.toggle(panel, ctx["exploration"], ctx["scenario_session"], ctx["party"])

	assert_false(panel.visible, "an id absent from `party` must leave the panel hidden")
	assert_false(controller.is_open())


func test_toggle_with_index_beyond_character_resource_paths_is_a_noop() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var panel := _FakePanel.new()
	var ctx: Dictionary = _make_resolvable_context()
	ctx["scenario_session"].scenario.party.character_resource_paths = []

	controller.toggle(panel, ctx["exploration"], ctx["scenario_session"], ctx["party"])

	assert_false(panel.visible, "an out-of-range character_resource_paths index must leave the panel hidden")
	assert_false(controller.is_open())


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — a null panel is a safe no-op.
# ══════════════════════════════════════════════════════════════════════════

func test_toggle_with_null_panel_does_not_crash() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var ctx: Dictionary = _make_resolvable_context()

	controller.toggle(null, ctx["exploration"], ctx["scenario_session"], ctx["party"])

	assert_false(controller.is_open(), "a null panel must never flip is_open() true")


func test_handle_input_with_null_panel_does_not_crash() -> void:
	var controller := EquipmentPanelToggleControllerClass.new()
	var ctx: Dictionary = _make_resolvable_context()

	var consumed: bool = controller.handle_input(
		_make_e_key_event(), null, ctx["exploration"], ctx["scenario_session"], ctx["party"]
	)

	assert_true(consumed, "handle_input() still reports the event as consumed even if toggle() itself no-ops")
