extends GutTest
## tests/gut/test_movement_input_controller_lock.gd — FEAT-162 (US-010 /
## US-013 / US-014, resolves DEF-001)
##
## GUT test suite for presentation/movement_input_controller.gd's
## lock()/is_locked() contract — the SAME persistent, sticky post-resolution
## guard already added to scenes/battlefield/StrikeInputController.gd
## (FEAT-010) and presentation/end_turn_control.gd (FEAT-137 / DEF-004),
## closing the last of the four post-resolution input surfaces called out by
## peer review (DEF-001 BLOCKING). MovementInputController itself does not
## subscribe to any port directly — exactly like StrikeInputController and
## EndTurnControl, its lock() is intended to be called by whichever
## presentation-layer widget already subscribes to EventSinkPort
## (scenes/battlefield/ResultScreen.gd / presentation/result_screen_view.gd)
## the moment it observes an EncounterResultEvent (ADR-005: no new event
## bus/signal is introduced by this feature).
##
## Verifies (test_criteria):
##   1. Before lock() has ever been called, step_to()/stride_to() function
##      completely normally (unlocked) — mirroring the pre-existing US-013/
##      US-014 behavior exactly.
##   2. Once lock() has been called (simulating the moment
##      EncounterResultEvent fires and the composition root's EventSinkPort
##      subscriber reacts), step_to()/stride_to() are BOTH rejected with the
##      same ERR_ENCOUNTER_ALREADY_RESOLVED-style error code
##      StrikeInputController/EndTurnControl already use, with no positional
##      mutation, no action-economy spend, and no domain call at all.
##   3. is_locked()/is_hex_selectable()/is_stride_hex_selectable() all
##      reflect the locked state, and the lock is STICKY — surviving a stray
##      reconfigure() call after lock(), exactly mirroring
##      StrikeInputController.gd's FEAT-156/FIND-149 regression coverage.
##   4. lock() immediately clears any selectable-hex highlighting on an
##      injected HexGridView collaborator, mirroring StrikeInputController's
##      lock() clearing HexBattlefield highlighting.

const MovementInputControllerClass = preload("res://presentation/movement_input_controller.gd")
const MovementClass                = preload("res://core/rules/movement.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")


## SpyHexGridView — a minimal stand-in for presentation/hex_grid_view.gd that
## records every set_selectable_hexes()/move_token() call so tests can assert
## on exactly what the controller reports post-lock(), without needing the
## real HexGridView scene.
class SpyHexGridView:
	var set_selectable_calls: Array = []
	var move_token_calls: Array = []

	func set_selectable_hexes(hexes: Array) -> void:
		set_selectable_calls.append(hexes.duplicate())

	func move_token(combatant_id: String, hex_coord) -> void:
		move_token_calls.append({"combatant_id": combatant_id, "hex_coord": hex_coord})


var _controller = null


func before_each() -> void:
	_controller = MovementInputControllerClass.new()


func _actor(hex_coord, combatant_id: String = "titus") -> Dictionary:
	return {"name": "Titus", "combatant_id": combatant_id, "hex_coord": hex_coord}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: step_to()/stride_to() function normally (unlocked) before
# EncounterResultEvent fires (i.e. before lock() is ever called).
# ══════════════════════════════════════════════════════════════════════════

func test_is_not_locked_by_default() -> void:
	_controller.configure(_actor(HexCoordClass.new(0, 0)), [])
	assert_false(_controller.is_locked())


func test_step_to_functions_normally_before_lock() -> void:
	var actor: Dictionary = _actor(HexCoordClass.new(0, 0))
	_controller.configure(actor, [])

	var result: Dictionary = _controller.step_to(HexCoordClass.new(1, 0))

	assert_true(result.get("ok", false), "step_to() must succeed normally before lock() has been called")
	assert_true(actor["hex_coord"].equals(HexCoordClass.new(1, 0)))


func test_stride_to_functions_normally_before_lock() -> void:
	var actor: Dictionary = _actor(HexCoordClass.new(0, 0))
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var budget_before: int = action_economy.get_remaining()

	_controller.configure(actor, [], null, "titus", action_economy)

	var result: Dictionary = _controller.stride_to(HexCoordClass.new(2, 0))

	assert_true(result.get("ok", false), "stride_to() must succeed normally before lock() has been called")
	assert_true(actor["hex_coord"].equals(HexCoordClass.new(2, 0)))
	assert_eq(action_economy.get_remaining(), budget_before - 1, "an unlocked Stride must spend exactly one action")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: once lock() has been called (i.e. once EncounterResultEvent
# has fired), step_to()/stride_to() are both rejected with the same
# ERR_ENCOUNTER_ALREADY_RESOLVED-style error code as
# StrikeInputController/EndTurnControl.
# ══════════════════════════════════════════════════════════════════════════

func test_error_code_matches_strike_input_controller_and_end_turn_control() -> void:
	assert_eq(
		MovementInputControllerClass.ERR_ENCOUNTER_ALREADY_RESOLVED, "ENCOUNTER_ALREADY_RESOLVED",
		"MovementInputController's error code must be the SAME value StrikeInputController/EndTurnControl use"
	)


func test_step_to_is_rejected_with_encounter_already_resolved_after_lock() -> void:
	var actor: Dictionary = _actor(HexCoordClass.new(0, 0))
	_controller.configure(actor, [])

	_controller.lock()
	var result: Dictionary = _controller.step_to(HexCoordClass.new(1, 0))

	assert_false(result.get("ok", true), "step_to() must be rejected once locked")
	assert_eq(result.get("error", ""), MovementInputControllerClass.ERR_ENCOUNTER_ALREADY_RESOLVED)
	assert_true(actor["hex_coord"].equals(HexCoordClass.new(0, 0)), "a locked step_to() must never mutate the actor's position")


func test_stride_to_is_rejected_with_encounter_already_resolved_after_lock() -> void:
	var actor: Dictionary = _actor(HexCoordClass.new(0, 0))
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var budget_before: int = action_economy.get_remaining()

	_controller.configure(actor, [], null, "titus", action_economy)
	_controller.lock()

	var result: Dictionary = _controller.stride_to(HexCoordClass.new(2, 0))

	assert_false(result.get("ok", true), "stride_to() must be rejected once locked")
	assert_eq(result.get("error", ""), MovementInputControllerClass.ERR_ENCOUNTER_ALREADY_RESOLVED)
	assert_true(actor["hex_coord"].equals(HexCoordClass.new(0, 0)), "a locked stride_to() must never mutate the actor's position")
	assert_eq(
		action_economy.get_remaining(), budget_before,
		"a locked stride_to() must never spend the action economy"
	)


func test_step_rejected_signal_emitted_when_locked() -> void:
	_controller.configure(_actor(HexCoordClass.new(0, 0)), [])
	_controller.lock()

	watch_signals(_controller)
	_controller.step_to(HexCoordClass.new(1, 0))

	assert_signal_emitted(_controller, "step_rejected")
	assert_signal_not_emitted(_controller, "step_resolved")


func test_stride_rejected_signal_emitted_when_locked() -> void:
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	_controller.configure(_actor(HexCoordClass.new(0, 0)), [], null, "titus", action_economy)
	_controller.lock()

	watch_signals(_controller)
	_controller.stride_to(HexCoordClass.new(2, 0))

	assert_signal_emitted(_controller, "stride_rejected")
	assert_signal_not_emitted(_controller, "stride_resolved")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: is_locked()/selectability reflect the locked state, and the
# lock is STICKY across a stray reconfigure() call.
# ══════════════════════════════════════════════════════════════════════════

func test_is_locked_true_after_lock() -> void:
	_controller.configure(_actor(HexCoordClass.new(0, 0)), [])
	assert_false(_controller.is_locked())

	_controller.lock()

	assert_true(_controller.is_locked())


func test_selectable_hexes_are_cleared_once_locked() -> void:
	var actor: Dictionary = _actor(HexCoordClass.new(0, 0))
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	_controller.configure(actor, [], null, "titus", action_economy)

	assert_true(_controller.get_selectable_step_hexes().size() > 0, "sanity check: destinations are selectable before lock()")
	assert_true(_controller.get_selectable_stride_hexes().size() > 0, "sanity check: stride destinations are selectable before lock()")

	_controller.lock()

	assert_eq(_controller.get_selectable_step_hexes(), [], "lock() must clear every selectable Step destination")
	assert_eq(_controller.get_selectable_stride_hexes(), [], "lock() must clear every selectable Stride destination")
	assert_false(_controller.is_hex_selectable(HexCoordClass.new(1, 0)))
	assert_false(_controller.is_stride_hex_selectable(HexCoordClass.new(2, 0)))


func test_stray_configure_after_lock_does_not_unlock_or_resurrect_selectable_destinations() -> void:
	var actor: Dictionary = _actor(HexCoordClass.new(0, 0))
	_controller.configure(actor, [])
	_controller.lock()
	assert_true(_controller.is_locked())

	# The DEF-001-adjacent regression this mirrors (FIND-149 on
	# StrikeInputController): a stray reconfigure() call (e.g. a leftover
	# TurnController signal) after lock() must NOT re-enable movement.
	_controller.configure(actor, [])

	assert_true(_controller.is_locked(), "is_locked() must stay true through a later configure() call")
	assert_eq(_controller.get_selectable_step_hexes(), [], "a stray reconfigure() must not resurrect selectable Step destinations")
	assert_false(_controller.is_hex_selectable(HexCoordClass.new(1, 0)))

	var result: Dictionary = _controller.step_to(HexCoordClass.new(1, 0))
	assert_false(result.get("ok", true), "step_to() must be rejected once locked, even after a stray reconfigure()")
	assert_eq(result.get("error", ""), MovementInputControllerClass.ERR_ENCOUNTER_ALREADY_RESOLVED)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: lock() immediately clears any selectable-hex highlighting on
# an injected HexGridView collaborator, mirroring StrikeInputController's
# lock() clearing HexBattlefield highlighting.
# ══════════════════════════════════════════════════════════════════════════

func test_lock_clears_selectable_highlighting_on_the_hex_grid_view() -> void:
	var actor: Dictionary = _actor(HexCoordClass.new(0, 0))
	var hex_grid_view := SpyHexGridView.new()

	_controller.configure(actor, [], hex_grid_view, "titus")

	assert_true(
		hex_grid_view.set_selectable_calls[hex_grid_view.set_selectable_calls.size() - 1].size() > 0,
		"sanity check: configure() must report non-empty selectable hexes before lock()"
	)

	_controller.lock()

	assert_eq(
		hex_grid_view.set_selectable_calls[hex_grid_view.set_selectable_calls.size() - 1], [],
		"lock() must immediately clear any selectable-hex highlighting on the HexGridView"
	)


func test_stray_configure_after_lock_does_not_re_highlight_hexes_on_the_hex_grid_view() -> void:
	var actor: Dictionary = _actor(HexCoordClass.new(0, 0))
	var hex_grid_view := SpyHexGridView.new()

	_controller.configure(actor, [], hex_grid_view, "titus")
	_controller.lock()
	var calls_at_lock_time: int = hex_grid_view.set_selectable_calls.size()

	_controller.configure(actor, [], hex_grid_view, "titus")

	for i in range(calls_at_lock_time, hex_grid_view.set_selectable_calls.size()):
		assert_eq(
			hex_grid_view.set_selectable_calls[i], [],
			"set_selectable_hexes() must never be called with a non-empty list once locked, even after a stray reconfigure()"
		)
