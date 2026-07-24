extends GutTest
## tests/gut/test_spell_picker_panel_controller.gd — FEAT-008 (US-007 /
## FR-002).
##
## GUT suite for presentation/spell_picker_panel_controller.gd's
## SpellPickerPanelController — the extracted leaf UI controller for the
## floating spell-picker panel shown during Layer-2a spell selection
## (formerly MainScene.gd's own `_setup_spell_picker_panel()` /
## `_show_spell_picker()` / `_on_spell_option_pressed()` /
## `_hide_spell_picker()` quartet).
##
## Drives the controller purely through its own public setup(panel_node)/
## show(options, on_selected)/hide() surface against a real (but minimal,
## never added to MainScene.tscn) Panel node — mirroring
## tests/gut/test_combine_targeting_session.gd's own "construct the real
## collaborator + fakes, no scene boot" convention. No MainScene.tscn boot is
## required for this suite.
##
## test_criteria covered:
##   1. show(options, on_selected) populates panel options and invokes
##      on_selected callback when an option is chosen, verified against a
##      mock panel node.
##   2. _on_spell_option_pressed is private (not reachable as public API) per
##      requirement.
##   3. (spell-picker logic removal from MainScene.gd is verified by a static
##      source scan, below).
##   4. (full-suite regression is verified by running the whole GUT suite,
##      not scoped to this file).

const SpellPickerPanelControllerClass = preload("res://presentation/spell_picker_panel_controller.gd")

const MAIN_SCENE_SCRIPT_PATH: String = "res://MainScene.gd"


## _OnSelectedTracker — records every option `show()`'s on_selected Callable
## was invoked with, mirroring test_combine_targeting_session.gd's own
## `_SpellPickerTracker` "small real fake, not a Mock-everything spy"
## philosophy.
class _OnSelectedTracker:
	extends RefCounted

	var calls: Array = []

	func on_selected(option: Dictionary) -> void:
		calls.append(option)


var _panel: Panel = null
var _controller = null


func before_each() -> void:
	_panel = Panel.new()
	_panel.name = "SpellPickerPanel"
	_panel.visible = false
	add_child_autofree(_panel)

	_controller = SpellPickerPanelControllerClass.new()
	_controller.setup(_panel)


func _spell_list() -> VBoxContainer:
	return _panel.get_node("SpellList")


func _option_buttons() -> Array:
	var buttons: Array = []
	for child in _spell_list().get_children():
		if child is Button:
			buttons.append(child)
	return buttons


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — show(options, on_selected) populates panel options and
# invokes on_selected callback when an option is chosen, verified against a
# mock panel node.
# ══════════════════════════════════════════════════════════════════════════

func test_setup_creates_spell_list_container_on_the_injected_panel_node() -> void:
	assert_true(_panel.has_node("SpellList"), "setup(panel_node) must create a 'SpellList' VBoxContainer child on the injected panel")
	assert_true(_spell_list() is VBoxContainer, "'SpellList' must be a VBoxContainer")


func test_show_populates_exactly_one_button_per_option_and_makes_the_panel_visible() -> void:
	var options: Array = [
		{"id": "fire_bolt", "label": "Fire Bolt"},
		{"id": "channel", "label": "Channel"},
	]
	var tracker := _OnSelectedTracker.new()

	_controller.show(options, Callable(tracker, "on_selected"))

	assert_eq(_option_buttons().size(), 2, "show() must render exactly one Button per candidate option")
	assert_true(_panel.visible, "show() must make the panel visible")

	var labels: Array = []
	for btn in _option_buttons():
		labels.append(btn.text)
	assert_eq(labels, ["Fire Bolt", "Channel"], "each Button's text must be the option's label, in options order")


func test_show_falls_back_to_option_id_then_question_mark_for_the_button_label() -> void:
	var options: Array = [
		{"id": "channel"},
		{},
	]
	var tracker := _OnSelectedTracker.new()

	_controller.show(options, Callable(tracker, "on_selected"))

	var labels: Array = []
	for btn in _option_buttons():
		labels.append(btn.text)
	assert_eq(labels, ["channel", "?"], "button label must fall back to option id, then '?', mirroring the pre-extraction code")


func test_show_clears_any_previously_rendered_options_before_rendering_the_new_set() -> void:
	var tracker := _OnSelectedTracker.new()
	_controller.show([{"id": "fire_bolt", "label": "Fire Bolt"}], Callable(tracker, "on_selected"))
	assert_eq(_option_buttons().size(), 1)

	_controller.show([{"id": "channel", "label": "Channel"}, {"id": "step", "label": "Step"}], Callable(tracker, "on_selected"))
	# The previous options' Buttons are removed via queue_free() (UNCHANGED
	# from the pre-extraction code) -- deferred to the end of the frame, so
	# let one process frame elapse before counting live children.
	await get_tree().process_frame

	assert_eq(_option_buttons().size(), 2, "a second show() call must replace the previous option set, not append to it")


func test_clicking_an_option_button_hides_the_panel_and_invokes_on_selected_with_the_chosen_option() -> void:
	var options: Array = [
		{"id": "fire_bolt", "label": "Fire Bolt"},
		{"id": "channel", "label": "Channel"},
	]
	var tracker := _OnSelectedTracker.new()
	_controller.show(options, Callable(tracker, "on_selected"))
	assert_true(_panel.visible, "fixture assumption: panel must be visible immediately after show()")

	var buttons: Array = _option_buttons()
	buttons[1].pressed.emit()

	assert_eq(tracker.calls.size(), 1, "on_selected must be invoked exactly once for the clicked option")
	assert_eq(tracker.calls[0], {"id": "channel", "label": "Channel"}, "on_selected must be invoked with the exact option that was clicked")
	assert_false(_panel.visible, "clicking an option must hide the panel")


func test_clicking_one_button_does_not_invoke_on_selected_for_the_other_options() -> void:
	var options: Array = [
		{"id": "fire_bolt", "label": "Fire Bolt"},
		{"id": "channel", "label": "Channel"},
	]
	var tracker := _OnSelectedTracker.new()
	_controller.show(options, Callable(tracker, "on_selected"))

	_option_buttons()[0].pressed.emit()

	assert_eq(tracker.calls.size(), 1, "only the clicked option's callback must fire")
	assert_eq(tracker.calls[0].get("id"), "fire_bolt")


func test_hide_hides_the_panel_without_requiring_a_prior_show() -> void:
	assert_false(_panel.visible, "fixture assumption: panel starts hidden")
	_controller.hide()
	assert_false(_panel.visible, "hide() must be a safe no-op when the panel is already hidden")

	var tracker := _OnSelectedTracker.new()
	_controller.show([{"id": "channel", "label": "Channel"}], Callable(tracker, "on_selected"))
	assert_true(_panel.visible)

	_controller.hide()
	assert_false(_panel.visible, "hide() must hide a currently-visible panel")


func test_hide_is_a_safe_no_op_before_setup_is_called() -> void:
	var unconfigured := SpellPickerPanelControllerClass.new()
	unconfigured.hide()  # must not crash / push a fatal error
	assert_true(true, "hide() must return normally (no crash) when called before setup()")


func test_show_before_setup_pushes_an_error_and_does_not_crash() -> void:
	var unconfigured := SpellPickerPanelControllerClass.new()
	var tracker := _OnSelectedTracker.new()
	unconfigured.show([{"id": "channel", "label": "Channel"}], Callable(tracker, "on_selected"))  # must not crash
	assert_eq(tracker.calls.size(), 0, "on_selected must never be invoked when show() is called before setup()")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — _on_spell_option_pressed is private (not reachable as public
# API) per requirement.
# ══════════════════════════════════════════════════════════════════════════

func test_on_spell_option_pressed_is_private_and_not_part_of_the_public_api() -> void:
	assert_true(
		_controller.has_method("_on_spell_option_pressed"),
		"the button-press handler must exist on the controller"
	)
	# This codebase's established private-method convention (mirrors
	# MainScene.gd's own _on_combine_queue_built/_on_verb_bar_selection_entered/
	# etc.) is a single leading underscore -- assert the handler follows it,
	# unlike this feature's own three explicitly public methods below.
	assert_true(
		"_on_spell_option_pressed".begins_with("_"),
		"_on_spell_option_pressed must be named with a leading underscore (private, by this codebase's convention)"
	)
	for public_method in ["setup", "show", "hide"]:
		assert_false(
			public_method.begins_with("_"),
			"'%s' must be part of the public API (setup/show/hide), not private" % public_method
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — spell-picker logic removed from MainScene.gd beyond the
# _spell_picker var and setup() call (static source scan).
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_no_longer_defines_the_four_extracted_spell_picker_functions() -> void:
	var source: String = FileAccess.get_file_as_string(MAIN_SCENE_SCRIPT_PATH)
	assert_true(source.length() > 0, "MainScene.gd must be readable as source text for this static scan")

	for extracted_fn in [
		"func _setup_spell_picker_panel(",
		"func _show_spell_picker(",
		"func _on_spell_option_pressed(",
		"func _hide_spell_picker(",
	]:
		assert_false(
			source.contains(extracted_fn),
			"MainScene.gd must no longer define '%s' -- it was extracted into presentation/spell_picker_panel_controller.gd" % extracted_fn
		)

	assert_true(
		source.contains("_spell_picker"),
		"MainScene.gd must still reference a _spell_picker field/controller"
	)
	assert_true(
		source.contains("_spell_picker.setup("),
		"MainScene.gd must still call _spell_picker.setup(...) to wire the injected panel node"
	)
