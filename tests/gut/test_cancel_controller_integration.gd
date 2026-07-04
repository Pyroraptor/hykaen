extends GutTest
## tests/gut/test_cancel_controller_integration.gd — FEAT-176 (US-012 /
## FR-007; ADR-005).
##
## Covers presentation/cancel_controller.gd's CancelController: the ONE
## cancel/back affordance (Esc key / right-click / Cancel button) added to
## EVERY Layer 2 mode (Strike/Step/Stride) this steel thread's VerbBarView ->
## SelectionOverlay flow can enter.
##
## test_criteria satisfied:
##   1. test_cancel_controller_never_invokes_action_resolver_movement_or_turn_port_methods()
##      -- unit-level: CancelController never invokes ActionResolverPort/
##      MovementPort/TurnPort methods, proven with spy ports wired underneath
##      a fake registry (no MainScene boot required for this one -- it
##      exercises presentation/selection_overlay.gd's real cancel() directly).
##   2. test_cancel_button_returns_strike_selection_to_layer1_with_zero_mutation()
##      test_esc_key_returns_step_selection_to_layer1_with_zero_mutation()
##      test_right_click_returns_stride_selection_to_layer1_with_zero_mutation()
##      -- integration: cancelling a Strike/Step/Stride selection (one
##      affordance each) returns to Layer 1 with zero board/state mutation and
##      zero actions consumed, booting the REAL res://MainScene.tscn
##      composition root headless (mirroring tests/gut/
##      test_strike_layer2_integration.gd's / test_step_layer2_integration.gd's
##      / test_stride_layer2_integration.gd's `_boot_main_scene_with_seed()`
##      fixture).
##   3. test_cancel_affordance_present_and_functional_in_every_layer2_mode()
##      -- the cancel affordance (CancelController.cancel()) is present and
##      functional in each of Strike/Step/Stride selection modes, and the verb
##      bar remains fully usable afterward (a cancelled verb can be re-entered
##      and re-cancelled repeatedly).
##   4. (whole-suite regression) -- enforced by scripts/test_command.sh, not
##      this file.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const SelectionOverlayClass  = preload("res://presentation/selection_overlay.gd")
const CancelControllerClass  = preload("res://presentation/cancel_controller.gd")


## _boot_main_scene_with_seed(seed_value) -> Node -- instantiates the REAL
## res://MainScene.tscn composition root, pinned to seed=42 (the prologue
## fixture's known-good seed, matching this codebase's established
## convention -- tests/gut/test_strike_layer2_integration.gd /
## test_step_layer2_integration.gd / test_stride_layer2_integration.gd).
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


## _snapshot_positions(instance) -> Dictionary -- combatant_id -> Vector2i(q,r)
## for every combatant currently carrying a hex_coord, used to prove a
## cancelled Step/Stride never moved anyone.
func _snapshot_positions(instance) -> Dictionary:
	var snapshot: Dictionary = {}
	for combatant in instance._party + instance._enemies:
		var combatant_id: String = combatant.get("combatant_id", combatant.get("name", ""))
		var hex_coord = combatant.get("hex_coord", null)
		if hex_coord != null:
			snapshot[combatant_id] = Vector2i(hex_coord.q, hex_coord.r)
	return snapshot


func _make_esc_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_ESCAPE
	return event


func _make_right_click_event() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.pressed = true
	event.button_index = MOUSE_BUTTON_RIGHT
	return event


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (unit-level) -- CancelController never invokes
# ActionResolverPort/MovementPort/TurnPort methods, no matter which verb's
# Layer 2 selection is active when cancel() is called. Proven with spy port
# doubles wired underneath a fake registry -- SelectionOverlay.cancel() (the
# ONLY method CancelController ever calls) is exercised for real; only the
# ports beneath it are doubled.
# ══════════════════════════════════════════════════════════════════════════

class _SpyActionResolverPort:
	var select_target_call_count: int = 0
	func select_target(_combatant_id, _target_id):
		select_target_call_count += 1
		return {"ok": true}


class _SpyMovementPort:
	var move_token_call_count: int = 0
	func move_token(_combatant_id, _destination, _spend_action):
		move_token_call_count += 1
		return {"ok": true}


class _SpyTurnPort:
	var end_turn_call_count: int = 0
	func end_turn():
		end_turn_call_count += 1
		return {"ok": true}


## _SpyRegistry -- a fake VerbRegistry-shaped object (the SAME duck-typed
## contract presentation/selection_overlay.gd/verb_bar_view.gd already rely
## on) whose execute() forwards to whichever spy port the verb_id names. Its
## execute_call_count is the single choke point every one of the three real
## ports' mutating methods is reachable through -- if CancelController never
## drives execute_call_count above zero, none of the three spy ports' call
## counts can be nonzero either (asserted independently below regardless).
class _SpyRegistry:
	var action_resolver_port
	var movement_port
	var turn_port
	var execute_call_count: int = 0

	func execute(verb_id: String, selection = null):
		execute_call_count += 1
		if verb_id == "STRIKE":
			return action_resolver_port.select_target("actor-1", selection)
		if verb_id == "STEP":
			return movement_port.move_token("actor-1", selection, false)
		if verb_id == "STRIDE":
			return movement_port.move_token("actor-1", selection, true)
		if verb_id == "END_TURN":
			return turn_port.end_turn()
		return {"ok": false}


func test_cancel_controller_never_invokes_action_resolver_movement_or_turn_port_methods() -> void:
	var action_resolver_port := _SpyActionResolverPort.new()
	var movement_port := _SpyMovementPort.new()
	var turn_port := _SpyTurnPort.new()

	var registry := _SpyRegistry.new()
	registry.action_resolver_port = action_resolver_port
	registry.movement_port = movement_port
	registry.turn_port = turn_port

	for verb_id in ["STRIKE", "STEP", "STRIDE"]:
		var overlay := SelectionOverlayClass.new()
		overlay.configure(registry, null)
		overlay.activate(verb_id, {"candidate_targets": ["enemy-1"], "candidate_hexes": []})
		assert_true(overlay.is_active(), "sanity check: %s Layer 2 selection must be active before cancelling" % verb_id)

		var controller = CancelControllerClass.new()
		controller.configure(overlay)

		var cancelled: bool = controller.cancel()

		assert_true(cancelled, "cancel() must report a real cancellation while a %s selection was active" % verb_id)
		assert_false(overlay.is_active(), "cancelling %s must return to Layer 1" % verb_id)

	assert_eq(registry.execute_call_count, 0, "CancelController must NEVER call registry.execute() for any verb")
	assert_eq(action_resolver_port.select_target_call_count, 0, "CancelController must NEVER call ActionResolverPort.select_target()")
	assert_eq(movement_port.move_token_call_count, 0, "CancelController must NEVER call MovementPort.move_token()")
	assert_eq(turn_port.end_turn_call_count, 0, "CancelController must NEVER call TurnPort.end_turn()")


## test_cancel_with_no_active_selection_is_a_true_no_op() -- pressing
## cancel outside of any Layer 2 selection (Layer 1 already active) must do
## nothing at all: no signal, false return.
func test_cancel_with_no_active_selection_is_a_true_no_op() -> void:
	var overlay := SelectionOverlayClass.new()
	overlay.configure(null, null)
	var controller = CancelControllerClass.new()
	controller.configure(overlay)

	watch_signals(controller)
	watch_signals(overlay)

	var cancelled: bool = controller.cancel()

	assert_false(cancelled, "cancel() with nothing active must return false")
	assert_signal_not_emitted(controller, "selection_cancelled")
	assert_signal_not_emitted(overlay, "selection_cancelled")


# ══════════════════════════════════════════════════════════════════════════
# Criteria 2 & 3 (integration) -- cancelling a real Strike/Step/Stride
# selection, one affordance each, returns to Layer 1 with zero board/state
# mutation and zero actions consumed; the cancel affordance is present and
# functional in every Layer 2 mode, and the verb bar remains usable
# afterward.
# ══════════════════════════════════════════════════════════════════════════

func test_cancel_button_returns_strike_selection_to_layer1_with_zero_mutation() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_true(
		is_instance_of(instance.cancel_controller, CancelControllerClass),
		"MainScene must wire the REAL presentation/cancel_controller.gd CancelController -- no stub/mock"
	)
	assert_true(instance._verb_registry.is_available("STRIKE"), "fixture assumption: STRIKE is available at seed=42")

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	var events_before: int = instance.event_log_view.get_entry_count()
	var positions_before: Dictionary = _snapshot_positions(instance)

	instance.verb_bar_view.press("STRIKE")
	assert_true(instance.selection_overlay.is_active(), "sanity check: STRIKE Layer 2 selection must be active")

	watch_signals(instance.selection_overlay)

	# The "Cancel button" affordance -- a future Cancel Button Control's
	# `pressed` signal would connect straight to this method.
	var cancelled: bool = instance.cancel_controller.press_cancel_button()

	assert_true(cancelled, "press_cancel_button() must report a real cancellation")
	assert_false(instance.selection_overlay.is_active(), "cancelling STRIKE must return to Layer 1")
	assert_signal_emitted_with_parameters(instance.selection_overlay, "selection_cancelled", ["STRIKE"])
	assert_signal_not_emitted(instance.selection_overlay, "selection_resolved", "a cancel must NEVER resolve through the verb registry")

	assert_eq(
		instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1), before_remaining,
		"cancelling STRIKE must spend no action"
	)
	assert_eq(instance.event_log_view.get_entry_count(), events_before, "cancelling STRIKE must log no event")
	assert_eq(_snapshot_positions(instance), positions_before, "cancelling STRIKE must move nobody")


func test_esc_key_returns_step_selection_to_layer1_with_zero_mutation() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available("STEP"), "fixture assumption: STEP is available at seed=42")

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	var events_before: int = instance.event_log_view.get_entry_count()
	var positions_before: Dictionary = _snapshot_positions(instance)

	instance.verb_bar_view.press("STEP")
	assert_true(instance.selection_overlay.is_active(), "sanity check: STEP Layer 2 selection must be active")

	watch_signals(instance.selection_overlay)

	# The Esc-key affordance -- fed straight into CancelController's real
	# _unhandled_input() handler (never through a simulated OS input queue,
	# mirroring this suite's siblings' hex_clicked.emit() click-simulation
	# convention).
	instance.cancel_controller.handle_input(_make_esc_event())

	assert_false(instance.selection_overlay.is_active(), "Esc must return STEP's Layer 2 selection to Layer 1")
	assert_signal_emitted_with_parameters(instance.selection_overlay, "selection_cancelled", ["STEP"])
	assert_signal_not_emitted(instance.selection_overlay, "selection_resolved", "Esc must NEVER resolve through the verb registry")

	assert_eq(
		instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1), before_remaining,
		"cancelling STEP must spend no action (Step never spends one anyway, but must still be exactly unchanged)"
	)
	assert_eq(instance.event_log_view.get_entry_count(), events_before, "cancelling STEP must log no event")
	assert_eq(_snapshot_positions(instance), positions_before, "cancelling STEP must move nobody")


func test_right_click_returns_stride_selection_to_layer1_with_zero_mutation() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available("STRIDE"), "fixture assumption: STRIDE is available at seed=42")

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	var events_before: int = instance.event_log_view.get_entry_count()
	var positions_before: Dictionary = _snapshot_positions(instance)

	instance.verb_bar_view.press("STRIDE")
	assert_true(instance.selection_overlay.is_active(), "sanity check: STRIDE Layer 2 selection must be active")

	watch_signals(instance.selection_overlay)

	# The right-click affordance -- fed straight into CancelController's real
	# _unhandled_input() handler.
	instance.cancel_controller.handle_input(_make_right_click_event())

	assert_false(instance.selection_overlay.is_active(), "right-click must return STRIDE's Layer 2 selection to Layer 1")
	assert_signal_emitted_with_parameters(instance.selection_overlay, "selection_cancelled", ["STRIDE"])
	assert_signal_not_emitted(instance.selection_overlay, "selection_resolved", "right-click must NEVER resolve through the verb registry")

	assert_eq(
		instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1), before_remaining,
		"cancelling STRIDE must spend no action -- the one action Stride WOULD have spent must remain unspent"
	)
	assert_eq(instance.event_log_view.get_entry_count(), events_before, "cancelling STRIDE must log no event")
	assert_eq(_snapshot_positions(instance), positions_before, "cancelling STRIDE must move nobody")


## test_cancel_affordance_present_and_functional_in_every_layer2_mode() --
## the cancel affordance is present (CancelController wired, selection_overlay
## reachable) and FUNCTIONAL for each of Strike/Step/Stride: entering that
## verb's Layer 2 selection, cancelling, and confirming the verb bar remains
## fully usable afterward (the SAME verb can be re-entered and re-cancelled,
## proving cancel never leaves Layer 2/the verb bar in a stuck state).
func test_cancel_affordance_present_and_functional_in_every_layer2_mode() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	for verb_id in ["STRIKE", "STEP", "STRIDE"]:
		assert_true(instance._verb_registry.is_available(verb_id), "fixture assumption: %s is available at seed=42" % verb_id)

		instance.verb_bar_view.press(verb_id)
		assert_true(instance.selection_overlay.is_active(), "%s Layer 2 selection must be active before cancelling" % verb_id)
		assert_eq(instance.selection_overlay.get_active_verb_id(), verb_id)

		var cancelled: bool = instance.cancel_controller.cancel()
		assert_true(cancelled, "cancel() must succeed for %s" % verb_id)
		assert_false(instance.selection_overlay.is_active(), "%s must return to Layer 1 after cancel" % verb_id)

		# The verb bar itself must remain usable -- re-pressing the SAME verb
		# after a cancel must re-enter Layer 2 exactly as before (no stuck
		# disabled button, no leftover Layer 2 state from the cancelled
		# attempt).
		instance.verb_bar_view.press(verb_id)
		assert_true(instance.selection_overlay.is_active(), "%s must be re-enterable after a prior cancel" % verb_id)
		assert_eq(instance.selection_overlay.get_active_verb_id(), verb_id)

		# Cancel again, leaving Layer 1 active for the next verb in this loop.
		instance.cancel_controller.cancel()
		assert_false(instance.selection_overlay.is_active())
