extends GutTest
## tests/gut/test_post_resolution_lock_regression.gd — FEAT-177 (US-013 /
## FR-013)
##
## GUT test suite extending the EXISTING presentation/result_screen_view.gd
## post-resolution lock mechanism (FEAT-005/FEAT-137/FEAT-162, exercised by
## tests/business_logic/test_result_screen_lock.gd and tests/gut/
## test_presentation_controls_sticky_lock.gd) to the Layer 1 verb bar
## (presentation/verb_bar_view.gd) and any open Layer 2 selection
## (presentation/selection_overlay.gd) — the steel thread's exit-point
## guarantee: "controls lock post-resolution" (US-013/FR-013).
##
## No new lock mechanism is introduced: VerbBarView.lock()/is_locked() and
## SelectionOverlay.lock()/is_locked() mirror the SAME sticky contract
## presentation/movement_input_controller.gd/presentation/end_turn_control.gd
## already established, and ResultScreenView.lock_all_controls() simply
## grows two more (optional, duck-typed) collaborators to call lock() on —
## exactly the pattern FEAT-005/FEAT-167 already used to add
## MovementInputController/MoveActionControl.
##
## Verifies (test_criteria):
##   1. Regression: prior Iteration D lock behavior (Strike/EndTurn/Movement)
##      remains green through the SAME configure()/lock_all_controls()
##      contract, unaffected by the two new optional trailing parameters.
##   2. New: after a Strike/Step/Stride/End Turn resolution (an
##      EncounterResultEvent reaching ResultScreenView), the verb bar's
##      buttons and any open SelectionOverlay become non-interactive — not
##      merely visually disabled (press()/activate()/hex-click dispatch are
##      ALL actively rejected, not just Button.disabled cosmetically set).
##   3. A click event dispatched at a locked control (VerbBarView button
##      press, or a hex_clicked signal reaching a locked SelectionOverlay)
##      never reaches the injected registry's enter_selection()/execute()
##      methods — i.e. never reaches the application-layer port the
##      registry composes over (ADR-002).

const ResultScreenViewScene: PackedScene = preload("res://presentation/result_screen_view.tscn")
const VerbBarViewScene: PackedScene      = preload("res://presentation/verb_bar_view.tscn")
const EndTurnControlScene: PackedScene   = preload("res://presentation/end_turn_control.tscn")

const SelectionOverlayClass         = preload("res://presentation/selection_overlay.gd")
const MovementInputControllerClass  = preload("res://presentation/movement_input_controller.gd")
const HexCoordClass                 = preload("res://core/geometry/hex_coord.gd")

const STRIKE: String    = "STRIKE"
const STEP: String      = "STEP"
const STRIDE: String    = "STRIDE"
const END_TURN: String  = "END_TURN"


## FakeVerbRegistry — a small, stateful, real (not all-mocked) double
## satisfying VerbBarView's/SelectionOverlay's duck-typed registry contract,
## mirroring tests/gut/test_verb_bar_view.gd's identically-named fixture,
## extended with a "candidate_hexes" descriptor so Step/Stride can drive a
## real SelectionOverlay Layer 2 activation.
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
		return {"verb_id": verb_id, "candidate_hexes": [HexCoordClass.new(1, 0)], "candidate_targets": []}

	func execute(verb_id: String, selection = null):
		execute_calls.append([verb_id, selection])
		return {"verb_id": verb_id, "success": true}


## SpyHexGridView — a minimal RefCounted stand-in for presentation/
## hex_grid_view.gd exposing exactly what SelectionOverlay.configure()
## relies on: a `hex_clicked` signal it subscribes to, set_selectable_hexes(),
## and get_token() (unused here since this suite drives Step/Stride's
## candidate_hexes path, never candidate_targets).
class SpyHexGridView:
	extends RefCounted

	signal hex_clicked(hex_coord)

	var set_selectable_calls: Array = []

	func set_selectable_hexes(hexes: Array) -> void:
		set_selectable_calls.append(hexes.duplicate())

	func get_token(_combatant_id: String):
		return null


## FakeRoundSession — minimal stand-in for core/application/round_session.gd's
## RoundSession, exposing only what EndTurnControl.is_enabled()/press() rely
## on (mirrors tests/business_logic/test_result_screen_lock.gd's
## identically-named fixture).
class FakeRoundSession:
	var _actor: Dictionary

	func _init(actor: Dictionary) -> void:
		_actor = actor

	func current_actor() -> Dictionary:
		return _actor

	func is_round_over() -> bool:
		return false


var _view = null
var _verb_bar_view = null
var _selection_overlay = null
var _hex_grid_view = null
var _registry = null


func before_each() -> void:
	_view = ResultScreenViewScene.instantiate()
	add_child_autofree(_view)

	_verb_bar_view = VerbBarViewScene.instantiate()
	add_child_autofree(_verb_bar_view)

	_hex_grid_view = SpyHexGridView.new()
	_registry = FakeVerbRegistry.new()
	_selection_overlay = SelectionOverlayClass.new()

	_verb_bar_view.configure(_registry)
	_selection_overlay.configure(_registry, _hex_grid_view)

	# Mirrors MainScene.gd's own wiring: a non-END_TURN Layer 1 press enters
	# Layer 2 through the SAME verb_selection_entered -> activate() hand-off.
	_verb_bar_view.verb_selection_entered.connect(_on_verb_selection_entered)


func _on_verb_selection_entered(verb_id: String, selection) -> void:
	_selection_overlay.activate(verb_id, selection)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (regression): prior Iteration D lock behavior (Strike/EndTurn/
# Movement) remains green through the SAME configure()/lock_all_controls()
# contract, unaffected by the two new trailing (optional) parameters.
# ══════════════════════════════════════════════════════════════════════════

func test_pre_existing_three_argument_configure_call_still_locks_end_turn_and_movement() -> void:
	var end_turn_control = EndTurnControlScene.instantiate()
	add_child_autofree(end_turn_control)
	end_turn_control.configure(FakeRoundSession.new({"name": "Titus", "_is_enemy": false}))
	assert_true(end_turn_control.is_enabled(), "sanity check: EndTurnControl starts enabled")

	var movement_input_controller := MovementInputControllerClass.new()
	movement_input_controller.configure({"name": "Titus", "combatant_id": "titus", "hex_coord": HexCoordClass.new(0, 0)}, [])
	assert_false(movement_input_controller.is_locked(), "sanity check: MovementInputController starts unlocked")

	# The EXACT pre-FEAT-177 call shape (three positional arguments) must
	# keep working unchanged.
	_view.configure(null, end_turn_control, movement_input_controller)
	_view.on_round_event({"round": 1, "outcome": "won"})

	assert_true(end_turn_control.is_locked(), "EndTurnControl must still be locked by the pre-existing three-argument configure() call")
	assert_true(movement_input_controller.is_locked(), "MovementInputController must still be locked by the pre-existing three-argument configure() call")
	assert_false(end_turn_control.press().get("ok", true))


func test_lock_all_controls_remains_idempotent_with_the_two_new_collaborators_injected() -> void:
	var end_turn_control = EndTurnControlScene.instantiate()
	add_child_autofree(end_turn_control)
	end_turn_control.configure(FakeRoundSession.new({"name": "Titus", "_is_enemy": false}))

	_view.configure(null, end_turn_control, null, null, _verb_bar_view, _selection_overlay)

	_view.lock_all_controls()
	_view.lock_all_controls()

	assert_true(end_turn_control.is_locked())
	assert_true(_verb_bar_view.is_locked())
	assert_true(_selection_overlay.is_locked())
	assert_eq(_registry.execute_calls, [], "a repeated lock_all_controls() call must never allow any registry method to be invoked")
	assert_eq(_registry.enter_selection_calls, [], "a repeated lock_all_controls() call must never allow any registry method to be invoked")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — after any Strike/Step/Stride resolution, the verb bar
# buttons AND any open SelectionOverlay become non-interactive (not merely
# visually disabled).
# ══════════════════════════════════════════════════════════════════════════

func test_verb_bar_buttons_and_open_selection_overlay_lock_after_step_resolution() -> void:
	_view.configure(null, null, null, null, _verb_bar_view, _selection_overlay)

	_verb_bar_view.press(STEP)
	assert_true(_selection_overlay.is_active(), "sanity check: pressing STEP must enter Layer 2")
	assert_eq(_registry.enter_selection_calls, [STEP])

	_view.on_round_event({"round": 1, "outcome": "won"})

	assert_true(_verb_bar_view.is_locked(), "VerbBarView must be locked once EncounterResolved fires")
	assert_true(_selection_overlay.is_locked(), "SelectionOverlay must be locked once EncounterResolved fires")
	assert_false(_selection_overlay.is_active(), "any open Layer 2 selection must be discarded once EncounterResolved fires")

	for verb_id in _verb_bar_view.get_verb_ids():
		assert_true(_verb_bar_view.get_button(verb_id).disabled, "every verb button must be visually disabled once locked (verb=%s)" % verb_id)


func test_verb_bar_buttons_and_open_selection_overlay_lock_after_stride_resolution() -> void:
	_view.configure(null, null, null, null, _verb_bar_view, _selection_overlay)

	_verb_bar_view.press(STRIDE)
	assert_true(_selection_overlay.is_active(), "sanity check: pressing STRIDE must enter Layer 2")

	_view.on_round_event({"round": 1, "outcome": "lost"})

	assert_true(_verb_bar_view.is_locked())
	assert_true(_selection_overlay.is_locked())
	assert_false(_selection_overlay.is_active())


func test_verb_bar_locks_after_strike_resolution() -> void:
	_view.configure(null, null, null, null, _verb_bar_view, _selection_overlay)

	_verb_bar_view.press(STRIKE)
	assert_true(_selection_overlay.is_active(), "sanity check: pressing STRIKE must enter Layer 2")

	_view.on_round_event({"round": 1, "outcome": "won"})

	assert_true(_verb_bar_view.is_locked())
	assert_true(_selection_overlay.is_locked())
	assert_false(_selection_overlay.is_active())


func test_verb_bar_locks_after_end_turn_resolution() -> void:
	_view.configure(null, null, null, null, _verb_bar_view, _selection_overlay)

	_verb_bar_view.press(END_TURN)
	assert_eq(_registry.execute_calls, [[END_TURN, null]], "sanity check: pressing END_TURN must execute() directly")
	assert_false(_selection_overlay.is_active(), "sanity check: END_TURN never opens Layer 2")

	_view.on_round_event({"round": 1, "outcome": "won"})

	assert_true(_verb_bar_view.is_locked(), "VerbBarView must be locked once EncounterResolved fires, even though END_TURN itself opened no Layer 2")
	assert_true(_selection_overlay.is_locked())


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — a click event dispatched at a locked control never reaches
# any application-layer port (the injected registry's enter_selection()/
# execute()).
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_any_verb_button_after_lock_never_reaches_the_registry() -> void:
	_view.configure(null, null, null, null, _verb_bar_view, _selection_overlay)
	_view.on_round_event({"round": 1, "outcome": "won"})

	for verb_id in [STRIKE, STEP, STRIDE, END_TURN]:
		var result = _verb_bar_view.press(verb_id)
		assert_false(result.get("ok", true), "press(%s) must be rejected once locked" % verb_id)
		assert_eq(result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")

	assert_eq(_registry.enter_selection_calls, [], "no registry.enter_selection() call may ever be reached once VerbBarView is locked")
	assert_eq(_registry.execute_calls, [], "no registry.execute() call may ever be reached once VerbBarView is locked")


func test_hex_click_dispatched_at_a_locked_selection_overlay_never_reaches_the_registry() -> void:
	_view.configure(null, null, null, null, _verb_bar_view, _selection_overlay)

	_verb_bar_view.press(STEP)
	assert_true(_selection_overlay.is_active(), "sanity check: STEP opens Layer 2 with candidate_hexes=[(1,0)]")

	_view.on_round_event({"round": 1, "outcome": "won"})
	assert_true(_selection_overlay.is_locked())

	# Simulate a click event landing on the PREVIOUSLY highlighted candidate
	# hex, dispatched exactly as HexGridView would (the click-event path a
	# real player drives) — this must be a total no-op now that the overlay
	# is locked: no selection_resolved, no registry.execute() call at all.
	watch_signals(_selection_overlay)
	_hex_grid_view.hex_clicked.emit(HexCoordClass.new(1, 0))

	assert_signal_not_emitted(_selection_overlay, "selection_resolved", "a click dispatched at a locked SelectionOverlay must never resolve")
	assert_signal_not_emitted(_selection_overlay, "selection_rejected", "a click dispatched at a locked SelectionOverlay must be a total no-op, not even a rejection")
	assert_eq(_registry.execute_calls, [], "a click dispatched at a locked SelectionOverlay must never reach registry.execute()")


func test_activate_on_a_locked_selection_overlay_is_rejected_even_if_verb_bar_verb_selection_entered_stray_refires() -> void:
	_view.configure(null, null, null, null, _verb_bar_view, _selection_overlay)
	_view.on_round_event({"round": 1, "outcome": "won"})
	assert_true(_selection_overlay.is_locked())

	# A stray verb_selection_entered-shaped re-entry (e.g. a leftover signal
	# firing after resolution) must never resurrect Layer 2.
	_selection_overlay.activate(STEP, {"candidate_hexes": [HexCoordClass.new(1, 0)], "candidate_targets": []})

	assert_false(_selection_overlay.is_active(), "activate() must be rejected once SelectionOverlay is locked")
	assert_eq(_selection_overlay.get_active_verb_id(), "")


func test_cancel_on_a_locked_selection_overlay_makes_no_registry_call_and_reports_nothing_to_cancel() -> void:
	_view.configure(null, null, null, null, _verb_bar_view, _selection_overlay)

	_verb_bar_view.press(STRIDE)
	_view.on_round_event({"round": 1, "outcome": "won"})

	var cancelled: bool = _selection_overlay.cancel()

	assert_false(cancelled, "cancel() on an already-locked (and therefore already-inactive) SelectionOverlay must report nothing to cancel")
	assert_eq(_registry.execute_calls, [])


# ══════════════════════════════════════════════════════════════════════════
# Stickiness: a stray re-configure()/refresh_availability() call after
# resolution must never re-enable the verb bar (mirrors the DEF-004/DEF-001
# sticky-lock regressions already covered for the other three controls).
# ══════════════════════════════════════════════════════════════════════════

func test_stray_refresh_availability_after_lock_does_not_reenable_the_verb_bar() -> void:
	_view.configure(null, null, null, null, _verb_bar_view, _selection_overlay)
	_view.on_round_event({"round": 1, "outcome": "won"})

	_registry.available[STRIKE] = true
	_registry.available[STEP] = true
	_verb_bar_view.refresh_availability()

	assert_true(_verb_bar_view.get_button(STRIKE).disabled, "a stray refresh_availability() call must not re-enable a button once locked")
	assert_true(_verb_bar_view.get_button(STEP).disabled, "a stray refresh_availability() call must not re-enable a button once locked")


func test_stray_reconfigure_after_lock_does_not_reenable_the_verb_bar() -> void:
	_view.configure(null, null, null, null, _verb_bar_view, _selection_overlay)
	_view.on_round_event({"round": 1, "outcome": "won"})

	# A stray reconfigure() with a fresh, fully-available registry (e.g. a
	# leftover turn-start signal) must not resurrect a clickable button set.
	var fresh_registry := FakeVerbRegistry.new()
	_verb_bar_view.configure(fresh_registry)

	assert_true(_verb_bar_view.is_locked(), "is_locked() must stay true through a later configure() call")
	for verb_id in _verb_bar_view.get_verb_ids():
		assert_true(_verb_bar_view.get_button(verb_id).disabled, "a stray reconfigure() must not re-render an enabled button once locked")

	var result = _verb_bar_view.press(STRIKE)
	assert_false(result.get("ok", true), "press() must stay rejected after a stray reconfigure(), even against a fresh registry")
	assert_eq(fresh_registry.enter_selection_calls, [], "the fresh registry injected by a stray reconfigure() must never be called into")
