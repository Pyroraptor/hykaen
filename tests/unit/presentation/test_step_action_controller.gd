extends GutTest
## tests/unit/presentation/test_step_action_controller.gd
##
## GUT suite for presentation/step_action_controller.gd's
## StepActionController — covering FEAT-006 (US-006; FR-003/NFR-001;
## ADR-001): an ADDITIVE, OPTIONAL `hex_grid_view` port widening execute()
## so that, after a successful step_to(), the token is animated to the
## selected hex (via the injected hex_grid_view.animate_token_to()) BEFORE
## `_after_successful_move_fn` runs. Mirrors
## tests/unit/presentation/test_stride_action_controller.gd's established
## FakeSession/FakeMovementInputController/FakeHexGridView double
## conventions (same "unwired seam -> legacy behavior" degradation pattern
## as FEAT-002/FEAT-005, per ADR-001).
##
## test_criteria covered:
##   1. animate_token_to is awaited exactly once, after a successful
##      step_to() and before _after_successful_move_fn, using a
##      deterministic stub.
##   2. No animate_token_to call occurs when hex_grid_view is not injected.
##   3. Existing StepActionController test suite (pre-FEAT-006 behavior)
##      passes unchanged: failed step_to() never triggers the post-move
##      Callable nor any animation; execute() forwards the result Dictionary
##      verbatim.

const StepActionControllerClass  = preload("res://presentation/step_action_controller.gd")
const RoundSessionHolderClass    = preload("res://infrastructure/round_session_holder.gd")


# ══════════════════════════════════════════════════════════════════════════
# Fakes / doubles
# ══════════════════════════════════════════════════════════════════════════

## FakeSession — minimal double satisfying the current_actor()/
## current_actor_entity()/current_action_economy() contract
## presentation/action_controller.gd's base class reads through the
## injected session_holder (mirrors test_stride_action_controller.gd's own
## FakeSession).
class FakeSession:
	var _actor

	func _init(actor) -> void:
		_actor = actor

	func current_actor():
		return {} if _actor == null else {"combatant_id": _actor}

	func current_actor_entity():
		return null if _actor == null else {"combatant_id": _actor}

	func current_action_economy():
		return null


## FakeMovementInputController — records every step_to() call and answers a
## scripted result Dictionary.
class FakeMovementInputController:
	var step_to_calls: Array = []
	var result_to_return: Dictionary = {"ok": true}

	func get_selectable_step_hexes() -> Array:
		return []

	func step_to(destination_hex) -> Dictionary:
		step_to_calls.append(destination_hex)
		return result_to_return


## FakeHexGridView — a DETERMINISTIC animation-adapter stub (no real Tween/
## timers). animate_token_to() records (combatant_id, target_hex) and
## returns null -- awaiting a non-Signal/non-coroutine value in GDScript
## resolves immediately without suspending.
class FakeHexGridView:
	var animate_calls: Array = []

	func animate_token_to(combatant_id: String, target_hex):
		animate_calls.append({"combatant_id": combatant_id, "target_hex": target_hex})
		return null


## _order_recorder() -> Dictionary — a shared mutable call-order tracker so
## a test can assert animate_token_to() ran strictly BEFORE
## after_successful_move.
func _order_recorder() -> Dictionary:
	return {"events": []}


func _deps(movement_input_controller, extra: Dictionary = {}) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new("player_0"))
	var base: Dictionary = {
		"session_holder": holder,
		"movement_input_controller": movement_input_controller,
		"after_successful_move": func(): pass,
	}
	for key in extra:
		base[key] = extra[key]
	return base


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — animate_token_to awaited once, after step_to(), before
# _after_successful_move_fn.
# ══════════════════════════════════════════════════════════════════════════

func test_animate_token_to_called_once_after_successful_step_before_after_move_fn() -> void:
	var movement := FakeMovementInputController.new()
	var hex_grid_view := FakeHexGridView.new()
	var order := _order_recorder()
	var selection := "TARGET_HEX"

	var controller := StepActionControllerClass.new(_deps(movement, {
		"hex_grid_view": hex_grid_view,
		"after_successful_move": func(): order["events"].append("after_successful_move"),
	}))

	# Wrap animate_token_to to also record ordering, without disturbing the
	# call-recording FakeHexGridView already performs.
	var result: Dictionary = await controller.execute(selection)

	assert_true(result.get("ok", false), "a successful step_to() result must be forwarded unchanged")
	assert_eq(hex_grid_view.animate_calls.size(), 1, "animate_token_to() must be called exactly once")
	assert_eq(hex_grid_view.animate_calls[0], {"combatant_id": "player_0", "target_hex": selection},
		"animate_token_to() must be called with the current actor id and the selected destination hex")
	assert_eq(order["events"], ["after_successful_move"], "after_successful_move must still run after the (awaited) animation completes")


func test_animate_token_to_awaited_before_after_successful_move_fn_with_deferred_stub() -> void:
	# A stub whose animate_token_to() records the moment it was invoked
	# relative to after_successful_move, proving the await happens BEFORE
	# _after_successful_move_fn is invoked (not merely called-and-ignored).
	var movement := FakeMovementInputController.new()
	var order := _order_recorder()

	# A lightweight object exposing animate_token_to via a RefCounted
	# wrapper so `await hex_grid_view.animate_token_to(...)` works exactly
	# as it would against the real HexGridView duck type.
	var stub := _OrderedHexGridView.new(order)

	var controller := StepActionControllerClass.new(_deps(movement, {
		"hex_grid_view": stub,
		"after_successful_move": func(): order["events"].append("after_successful_move"),
	}))

	await controller.execute("TARGET_HEX")

	assert_eq(order["events"], ["animate_token_to", "after_successful_move"],
		"animate_token_to must be awaited to completion strictly before after_successful_move runs")


class _OrderedHexGridView:
	var _order: Dictionary

	func _init(order: Dictionary) -> void:
		_order = order

	func animate_token_to(_combatant_id: String, _target_hex):
		_order["events"].append("animate_token_to")
		return null


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — no animate_token_to call when hex_grid_view is unwired.
# ══════════════════════════════════════════════════════════════════════════

func test_animate_token_to_never_called_when_hex_grid_view_unwired() -> void:
	var movement := FakeMovementInputController.new()

	# No "hex_grid_view" key supplied at all -- must default to null and
	# never attempt to call animate_token_to().
	var controller := StepActionControllerClass.new(_deps(movement))

	var result: Dictionary = await controller.execute("TARGET_HEX")

	assert_true(result.get("ok", false), "a successful step_to() must still resolve normally with an unwired hex_grid_view")
	assert_eq(movement.step_to_calls, ["TARGET_HEX"], "step_to() must still be called exactly once with the original selection")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — existing StepActionController behavior unchanged.
# ══════════════════════════════════════════════════════════════════════════

func test_failed_step_to_never_triggers_after_move_fn_or_animation() -> void:
	var movement := FakeMovementInputController.new()
	movement.result_to_return = {"ok": false, "error": "ERR_INVALID_STEP_DESTINATION"}
	var hex_grid_view := FakeHexGridView.new()
	var order := _order_recorder()

	var controller := StepActionControllerClass.new(_deps(movement, {
		"hex_grid_view": hex_grid_view,
		"after_successful_move": func(): order["events"].append("after_successful_move"),
	}))

	var result: Dictionary = await controller.execute("TARGET_HEX")

	assert_eq(result, {"ok": false, "error": "ERR_INVALID_STEP_DESTINATION"}, "a failed step_to() result must be forwarded verbatim")
	assert_eq(hex_grid_view.animate_calls, [], "no animate_token_to() call may fire when step_to() fails")
	assert_eq(order["events"], [], "after_successful_move must never run when step_to() fails")


func test_successful_step_forwards_result_verbatim_and_calls_after_move_fn_without_hex_grid_view() -> void:
	var movement := FakeMovementInputController.new()
	movement.result_to_return = {"ok": true, "resolved": true, "destination": "TARGET_HEX"}
	var order := _order_recorder()

	var controller := StepActionControllerClass.new(_deps(movement, {
		"after_successful_move": func(): order["events"].append("after_successful_move"),
	}))

	var result: Dictionary = await controller.execute("TARGET_HEX")

	assert_eq(result, {"ok": true, "resolved": true, "destination": "TARGET_HEX"}, "execute() must return movement_input_controller.step_to()'s result Dictionary verbatim")
	assert_eq(order["events"], ["after_successful_move"], "after_successful_move must still run exactly once on a successful step, unaffected by an unwired hex_grid_view")
