extends GutTest
## tests/gut/test_verb_bar_view.gd
##
## GUT test suite for FEAT-004 (US-004/FR-001): presentation/verb_bar_view.gd
## VerbBarView renders the Layer 1 verb bar generically from a registry (the
## GDScript-consumable contract mirroring core/application/verb_registry.py's
## VerbRegistry dispatch table, pytest-tested by tests/pytest/test_verb_registry.py
## — VerbRegistry itself has zero Godot imports and is not reachable at
## runtime from GDScript, so this suite exercises VerbBarView against a small,
## stateful FAKE registry satisfying the SAME duck-typed contract:
##   - list_verbs() -> Array[Dictionary], each carrying at least "verb_id"
##   - is_available(verb_id) -> bool
##   - enter_selection(verb_id) -> Variant (a Layer 2 selection descriptor)
##   - execute(verb_id, selection = null) -> Variant (a resolution result)
##
## Covers all three test_criteria from the feature spec:
##   1. exactly one control is rendered per registered verb.
##   2. clicking a Strike/Step/Stride button calls enter_selection(), not
##      execute().
##   3. clicking End Turn calls execute() directly with no Layer 2
##      transition (no enter_selection() call at all).
##
## Also covers the description's "correctly gated controls" requirement:
## a verb whose is_available() reports false is rendered disabled.

const VerbBarViewScene: PackedScene = preload("res://presentation/verb_bar_view.tscn")

const STRIKE: String = "STRIKE"
const STEP: String = "STEP"
const STRIDE: String = "STRIDE"
const END_TURN: String = "END_TURN"


## FakeVerbRegistry — a tiny, stateful, real (not a Mock-everything spy)
## implementation of the VerbBarView registry contract, mirroring
## tests/pytest/test_verb_registry.py's FakeGameState/FakeActionResolver/etc.
## fixtures' "small real fake" philosophy, adapted to GDScript.
class FakeVerbRegistry:
	var _verb_ids: Array = [STRIKE, STEP, STRIDE, END_TURN]
	var available: Dictionary = {STRIKE: true, STEP: true, STRIDE: true, END_TURN: true}

	var enter_selection_calls: Array = []
	var execute_calls: Array = []

	func list_verbs() -> Array:
		var descriptors: Array = []
		for verb_id in _verb_ids:
			descriptors.append({"verb_id": verb_id})
		return descriptors

	func is_available(verb_id: String) -> bool:
		return available.get(verb_id, false)

	func enter_selection(verb_id: String):
		enter_selection_calls.append(verb_id)
		return {"verb_id": verb_id, "candidate_hexes": [], "candidate_targets": []}

	func execute(verb_id: String, selection = null):
		execute_calls.append([verb_id, selection])
		return {"verb_id": verb_id, "success": true}


var _view = null


func before_each() -> void:
	_view = VerbBarViewScene.instantiate()
	add_child_autofree(_view)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: exactly one control is rendered per registered verb.
# ══════════════════════════════════════════════════════════════════════════

func test_renders_exactly_one_button_per_registered_verb() -> void:
	var registry := FakeVerbRegistry.new()
	_view.configure(registry)

	assert_eq(_view.get_button_count(), 4, "exactly one button must be rendered per registered verb")
	assert_eq(_view.get_verb_ids(), [STRIKE, STEP, STRIDE, END_TURN], "buttons must be rendered in registration order")


func test_renders_one_button_per_verb_for_a_fewer_verb_registry() -> void:
	var registry := FakeVerbRegistry.new()
	registry._verb_ids = [STRIKE, END_TURN]
	_view.configure(registry)

	assert_eq(_view.get_button_count(), 2, "exactly one button must be rendered per registered verb, no more no less")
	assert_eq(_view.get_verb_ids(), [STRIKE, END_TURN])


func test_reconfigure_does_not_leak_duplicate_buttons() -> void:
	var registry := FakeVerbRegistry.new()
	_view.configure(registry)
	_view.configure(registry)

	assert_eq(_view.get_button_count(), 4, "a second configure() call must not leak duplicate buttons")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: clicking a Strike/Step/Stride button calls enter_selection(),
# not execute().
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_strike_button_calls_enter_selection_not_execute() -> void:
	var registry := FakeVerbRegistry.new()
	_view.configure(registry)

	_view.press(STRIKE)

	assert_eq(registry.enter_selection_calls, [STRIKE], "clicking Strike must call enter_selection(), not execute()")
	assert_eq(registry.execute_calls, [], "clicking Strike must NOT call execute()")


func test_clicking_step_button_calls_enter_selection_not_execute() -> void:
	var registry := FakeVerbRegistry.new()
	_view.configure(registry)

	_view.press(STEP)

	assert_eq(registry.enter_selection_calls, [STEP], "clicking Step must call enter_selection(), not execute()")
	assert_eq(registry.execute_calls, [], "clicking Step must NOT call execute()")


func test_clicking_stride_button_calls_enter_selection_not_execute() -> void:
	var registry := FakeVerbRegistry.new()
	_view.configure(registry)

	_view.press(STRIDE)

	assert_eq(registry.enter_selection_calls, [STRIDE], "clicking Stride must call enter_selection(), not execute()")
	assert_eq(registry.execute_calls, [], "clicking Stride must NOT call execute()")


func test_pressing_the_real_rendered_strike_button_calls_enter_selection() -> void:
	var registry := FakeVerbRegistry.new()
	_view.configure(registry)

	var button: Button = _view.get_button(STRIKE)
	assert_not_null(button, "a real Button must be rendered for STRIKE")
	button.pressed.emit()

	assert_eq(registry.enter_selection_calls, [STRIKE], "emitting the rendered Strike Button's pressed signal must call enter_selection()")
	assert_eq(registry.execute_calls, [])


func test_entering_selection_emits_verb_selection_entered_signal() -> void:
	var registry := FakeVerbRegistry.new()
	_view.configure(registry)

	watch_signals(_view)
	_view.press(STRIKE)

	assert_signal_emitted(_view, "verb_selection_entered")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: clicking End Turn calls execute() directly with no Layer 2
# transition.
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_end_turn_button_calls_execute_directly_with_no_layer2_transition() -> void:
	var registry := FakeVerbRegistry.new()
	_view.configure(registry)

	_view.press(END_TURN)

	assert_eq(registry.execute_calls, [[END_TURN, null]], "clicking End Turn must call execute() directly")
	assert_eq(registry.enter_selection_calls, [], "clicking End Turn must NEVER call enter_selection() (no Layer 2)")


func test_pressing_the_real_rendered_end_turn_button_calls_execute_directly() -> void:
	var registry := FakeVerbRegistry.new()
	_view.configure(registry)

	var button: Button = _view.get_button(END_TURN)
	assert_not_null(button, "a real Button must be rendered for END_TURN")
	button.pressed.emit()

	assert_eq(registry.execute_calls, [[END_TURN, null]])
	assert_eq(registry.enter_selection_calls, [])


func test_executing_end_turn_emits_verb_executed_signal() -> void:
	var registry := FakeVerbRegistry.new()
	_view.configure(registry)

	watch_signals(_view)
	_view.press(END_TURN)

	assert_signal_emitted(_view, "verb_executed")


# ══════════════════════════════════════════════════════════════════════════
# Gating: a verb whose is_available() reports false is rendered disabled.
# ══════════════════════════════════════════════════════════════════════════

func test_unavailable_verb_is_rendered_disabled() -> void:
	var registry := FakeVerbRegistry.new()
	registry.available[STRIKE] = false
	_view.configure(registry)

	assert_true(_view.get_button(STRIKE).disabled, "STRIKE must be rendered disabled when is_available(STRIKE) is false")
	assert_false(_view.get_button(STEP).disabled, "STEP must remain enabled when is_available(STEP) is true")


func test_end_turn_is_always_enabled() -> void:
	var registry := FakeVerbRegistry.new()
	registry.available[STRIKE] = false
	registry.available[STEP] = false
	registry.available[STRIDE] = false
	_view.configure(registry)

	assert_false(_view.get_button(END_TURN).disabled, "End Turn must always remain enabled")


func test_pressing_a_disabled_verb_button_does_not_dispatch() -> void:
	var registry := FakeVerbRegistry.new()
	registry.available[STRIKE] = false
	_view.configure(registry)

	var result = _view.press(STRIKE)

	assert_eq(registry.enter_selection_calls, [], "pressing a disabled/unavailable verb must not call enter_selection()")
	assert_eq(registry.execute_calls, [], "pressing a disabled/unavailable verb must not call execute()")
	assert_false(result.get("ok", true), "press() must report rejection for an unavailable verb")


func test_refresh_availability_updates_disabled_state_without_reconfigure() -> void:
	var registry := FakeVerbRegistry.new()
	_view.configure(registry)
	assert_false(_view.get_button(STRIKE).disabled)

	registry.available[STRIKE] = false
	_view.refresh_availability()

	assert_true(_view.get_button(STRIKE).disabled, "refresh_availability() must re-query is_available() and update the disabled state")


# ══════════════════════════════════════════════════════════════════════════
# No registry configured yet: safe no-op, zero buttons.
# ══════════════════════════════════════════════════════════════════════════

func test_no_buttons_rendered_before_any_configure_call() -> void:
	assert_eq(_view.get_button_count(), 0, "VerbBarView must render no buttons before configure() is ever called")


func test_press_before_configure_is_a_safe_no_op() -> void:
	var result = _view.press(STRIKE)
	assert_false(result.get("ok", true))
