extends GutTest
## tests/business_logic/test_result_screen_lock.gd — FEAT-005 (US-005 / FR-011,
## ADR-005)
##
## GUT test suite for the post-resolution control-lock wiring migrated from
## the removed scenes/battlefield/ResultScreen.gd (FEAT-162's lock-wiring
## logic) into the kept presentation/result_screen_view.gd. Where the
## removed ResultScreen locked scenes/battlefield/*'s StrikeInputController /
## EndTurnController / MovementInputController as one bundle,
## ResultScreenView now uniformly locks whatever combat input controls are
## injected via configure() — EndTurnControl, MovementInputController, and
## (this suite's FakeLockableStrikeControl standing in for a real
## lock()-capable Strike control, see that class's doc) — via a single
## public lock_all_controls() operation, called once EncounterResolved
## (EncounterResultEvent) fires through the SAME EventSinkPort pipeline
## every other Presentation projection subscribes to (ADR-003).
##
## FEAT-006 (US-006): the real presentation/strike_action_control.gd this
## suite originally exercised was removed (its immediate-resolve-on-click
## UI competed with the new Layer 1/Layer 2 Strike flow). ResultScreenView's
## lock_all_controls() itself is duck-typed/generic — it locks whatever
## object was injected via its first (optional) `strike_action_control`
## parameter, calling nothing but that object's own lock()/is_locked()
## contract — so this suite continues to exercise that generic mechanism
## via FakeLockableStrikeControl below rather than losing coverage of it.
## A future feature is expected to wire a real lock()-capable Strike
## collaborator back into this same, unchanged ResultScreenView contract
## (design notes: "Clears the way for ... post-resolution lock to have a
## single Strike code path").
##
## Verifies (test_criteria):
##   1. The injected Strike control and EndTurnControl are disabled (zero
##      selectable targets / not pressable) once EncounterResolved fires.
##   2. Movement highlight cannot be re-triggered — set_selectable_hexes()
##      stays empty on an injected HexGridView collaborator — even if the
##      active-actor-changed/turn-started flow that would normally
##      reconfigure MovementInputController fires again after resolution.
##   3. Calling lock_all_controls() twice produces no additional side
##      effects (idempotent): locked state / selectable sets / rejection
##      behavior are unchanged by the second call.
##   4. Pre-existing Strike/EndTurn lock coverage
##      (tests/unit/presentation/test_result_screen_view.gd,
##      tests/gut/test_presentation_controls_sticky_lock.gd) keeps passing —
##      this suite adds Movement coverage without altering that contract.

const ResultScreenViewScene: PackedScene    = preload("res://presentation/result_screen_view.tscn")
const EndTurnControlScene: PackedScene      = preload("res://presentation/end_turn_control.tscn")

const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const MovementInputControllerClass = preload("res://presentation/movement_input_controller.gd")


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


## FakeLockableStrikeControl — a duck-typed double standing in for a
## lock()-capable presentation Strike control (FEAT-006: the real
## presentation/strike_action_control.gd was removed; ResultScreenView's
## `strike_action_control` parameter is generic/duck-typed, so any object
## implementing this same configure()/get_button_count()/lock()/
## is_locked()/select_target() contract exercises lock_all_controls()
## identically — see file-level doc).
class FakeLockableStrikeControl:
	extends RefCounted

	var _selectable_target_ids: Array = []
	var _actor: Dictionary = {}
	var _action_economy = null
	var _resolve_action_use_case = null
	var _locked: bool = false

	func configure(actor: Dictionary, action_economy, resolve_action_use_case, candidate_targets: Array, _round_number: int = 1, _cycle_index: int = 0) -> void:
		_actor = actor
		_action_economy = action_economy
		_resolve_action_use_case = resolve_action_use_case
		_selectable_target_ids = []
		if _locked:
			return
		for target in candidate_targets:
			_selectable_target_ids.append(target.get("combatant_id", target.get("name", "")))

	func get_button_count() -> int:
		return _selectable_target_ids.size()

	func lock() -> void:
		_locked = true
		_selectable_target_ids = []

	func is_locked() -> bool:
		return _locked

	func select_target(target_id: String) -> Dictionary:
		if _locked:
			return {"ok": false, "resolved": false, "error": "ENCOUNTER_ALREADY_RESOLVED"}
		if not _selectable_target_ids.has(target_id):
			return {"ok": false, "resolved": false, "error": "ERR_TARGET_NOT_SELECTABLE"}
		return _resolve_action_use_case.resolve(_actor, _action_economy, {"combatant_id": target_id}, "Strike", 1, 0)


## FakeRoundSession — minimal stand-in for core/application/round_session.gd's
## RoundSession, exposing only what EndTurnControl.is_enabled()/press() rely
## on (mirrors tests/unit/presentation/test_result_screen_view.gd's
## identically-named fixture).
class FakeRoundSession:
	var _actor: Dictionary
	var _round_over: bool = false

	func _init(actor: Dictionary) -> void:
		_actor = actor

	func current_actor() -> Dictionary:
		return {} if _round_over else _actor

	func is_round_over() -> bool:
		return _round_over


## SpyHexGridView — a minimal stand-in for presentation/hex_grid_view.gd that
## records every set_selectable_hexes() call so this suite can assert the
## highlight stays empty post-resolution, mirroring
## tests/gut/test_movement_input_controller_lock.gd's identically-named
## fixture.
class SpyHexGridView:
	var set_selectable_calls: Array = []

	func set_selectable_hexes(hexes: Array) -> void:
		set_selectable_calls.append(hexes.duplicate())

	func move_token(_combatant_id: String, _hex_coord) -> void:
		pass


var _view = null


func before_each() -> void:
	_view = ResultScreenViewScene.instantiate()
	add_child_autofree(_view)


func _actor(hex_coord) -> Dictionary:
	return {
		"name": "Titus",
		"combatant_id": "titus",
		"strength": 3,
		"hex_coord": hex_coord,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6,
		},
	}


func _enemy(name: String, hex_coord, hp: int = 20, ac: int = 10) -> Dictionary:
	return {"combatant_id": name.to_lower(), "name": name, "hp_current": hp, "ac": ac, "hex_coord": hex_coord}


func _make_use_case(scripted_values: Array) -> Dictionary:
	var rng_port   = ScriptedRandomNumberPort.new(scripted_values)
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "event_sink": event_sink}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: the injected Strike control.disabled == true and
# EndTurnControl.disabled == true after EncounterResolved fires.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_and_end_turn_controls_disabled_after_encounter_resolved() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var strike_control := FakeLockableStrikeControl.new()
	var end_turn_control = EndTurnControlScene.instantiate()
	add_child_autofree(end_turn_control)

	var rig: Dictionary = _make_use_case([12, 4])
	strike_control.configure(_actor(origin), ActionEconomyClass.new(), rig["use_case"], [adjacent_enemy])
	assert_eq(strike_control.get_button_count(), 1, "sanity check: the Strike control starts with one selectable target")

	var session := FakeRoundSession.new({"name": "Titus", "_is_enemy": false})
	end_turn_control.configure(session)
	assert_true(end_turn_control.is_enabled(), "sanity check: EndTurnControl starts enabled")

	_view.configure(strike_control, end_turn_control)
	_view.on_round_event({"round": 1, "outcome": "won"})

	assert_eq(strike_control.get_button_count(), 0, "the injected Strike control must be disabled (zero selectable targets) once EncounterResolved fires")
	assert_true(strike_control.is_locked(), "the injected Strike control must be locked once EncounterResolved fires")
	assert_false(end_turn_control.is_enabled(), "EndTurnControl must be disabled once EncounterResolved fires")
	assert_true(end_turn_control.is_locked(), "EndTurnControl must be locked once EncounterResolved fires")

	var strike_result: Dictionary = strike_control.select_target("skeleton")
	assert_false(strike_result.get("ok", true), "a locked Strike control must reject select_target()")

	var press_result: Dictionary = end_turn_control.press()
	assert_false(press_result.get("ok", true), "a locked EndTurnControl must reject press()")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: movement highlight cannot be re-triggered -- set_selectable_hexes()
# stays empty -- after resolution even if the active-actor-changed/turn-started
# flow that reconfigures MovementInputController fires again.
# ══════════════════════════════════════════════════════════════════════════

func test_movement_highlight_cannot_be_retriggered_after_encounter_resolved_even_if_turn_re_fires() -> void:
	var origin := HexCoordClass.new(0, 0)
	var actor: Dictionary = _actor(origin)
	var hex_grid_view := SpyHexGridView.new()

	var movement_input_controller := MovementInputControllerClass.new()
	movement_input_controller.configure(actor, [], hex_grid_view, "titus")

	assert_true(
		movement_input_controller.get_selectable_step_hexes().size() > 0,
		"sanity check: Step destinations are selectable before resolution"
	)
	assert_true(
		hex_grid_view.set_selectable_calls[hex_grid_view.set_selectable_calls.size() - 1].size() > 0,
		"sanity check: HexGridView was highlighted with a non-empty set before resolution"
	)

	_view.configure(null, null, movement_input_controller)
	_view.on_round_event({"round": 1, "outcome": "won"})

	assert_true(movement_input_controller.is_locked(), "MovementInputController must be locked once EncounterResolved fires")
	assert_eq(movement_input_controller.get_selectable_step_hexes(), [], "no Step destination may remain selectable once locked")
	assert_eq(
		hex_grid_view.set_selectable_calls[hex_grid_view.set_selectable_calls.size() - 1], [],
		"HexGridView's highlight must be cleared once EncounterResolved fires"
	)

	# Simulate turn_started/active_actor_changed re-firing after resolution
	# (e.g. a leftover TurnController signal) -- MainScene would normally
	# respond by re-invoking MovementInputController.configure() with the
	# live actor/occupancy data for whoever the session now (still) sits on.
	movement_input_controller.configure(actor, [], hex_grid_view, "titus")

	assert_true(movement_input_controller.is_locked(), "the lock must survive a stray reconfigure() after resolution")
	assert_eq(
		movement_input_controller.get_selectable_step_hexes(), [],
		"a stray reconfigure() after resolution must never resurrect selectable Step destinations"
	)
	assert_eq(
		hex_grid_view.set_selectable_calls[hex_grid_view.set_selectable_calls.size() - 1], [],
		"a stray reconfigure() after resolution must never re-highlight the HexGridView"
	)

	var step_result: Dictionary = movement_input_controller.step_to(HexCoordClass.new(1, 0))
	assert_false(step_result.get("ok", true), "step_to() must stay rejected after resolution, even after a stray reconfigure()")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: calling lock_all_controls() twice produces no additional
# side effects (idempotency).
# ══════════════════════════════════════════════════════════════════════════

func test_lock_all_controls_is_idempotent_across_all_three_controls() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var strike_control := FakeLockableStrikeControl.new()
	var end_turn_control = EndTurnControlScene.instantiate()
	add_child_autofree(end_turn_control)

	var rig: Dictionary = _make_use_case([12, 4])
	strike_control.configure(_actor(origin), ActionEconomyClass.new(), rig["use_case"], [adjacent_enemy])
	end_turn_control.configure(FakeRoundSession.new({"name": "Titus", "_is_enemy": false}))

	var hex_grid_view := SpyHexGridView.new()
	var movement_input_controller := MovementInputControllerClass.new()
	movement_input_controller.configure(_actor(origin), [], hex_grid_view, "titus")

	_view.configure(strike_control, end_turn_control, movement_input_controller)

	_view.lock_all_controls()

	assert_true(strike_control.is_locked())
	assert_true(end_turn_control.is_locked())
	assert_true(movement_input_controller.is_locked())
	assert_eq(strike_control.get_button_count(), 0)
	assert_false(end_turn_control.is_enabled())
	assert_eq(movement_input_controller.get_selectable_step_hexes(), [])

	var calls_after_first_lock: int = hex_grid_view.set_selectable_calls.size()

	# A spy resolve_action_use_case detects whether locking a second time ever
	# reaches into the use-case pipeline (it must not).
	var spy := SpyResolveActionUseCase.new()
	strike_control.configure(_actor(origin), ActionEconomyClass.new(), spy, [adjacent_enemy])

	_view.lock_all_controls()
	_view.lock_all_controls()

	assert_true(strike_control.is_locked(), "a repeated lock_all_controls() call must leave the Strike control locked")
	assert_true(end_turn_control.is_locked(), "a repeated lock_all_controls() call must leave EndTurnControl locked")
	assert_true(movement_input_controller.is_locked(), "a repeated lock_all_controls() call must leave MovementInputController locked")

	assert_eq(strike_control.get_button_count(), 0, "no new buttons may appear from a repeated lock_all_controls() call")
	assert_false(end_turn_control.is_enabled(), "EndTurnControl must stay disabled through a repeated lock_all_controls() call")
	assert_eq(movement_input_controller.get_selectable_step_hexes(), [], "no selectable destination may reappear from a repeated lock_all_controls() call")

	for i in range(calls_after_first_lock, hex_grid_view.set_selectable_calls.size()):
		assert_eq(
			hex_grid_view.set_selectable_calls[i], [],
			"every set_selectable_hexes() call made by a repeated lock_all_controls() must still report an empty set"
		)

	var strike_result: Dictionary = strike_control.select_target("skeleton")
	assert_false(strike_result.get("ok", true))
	assert_eq(spy.call_count, 0, "a repeated lock_all_controls() call must never allow the underlying use case to be invoked")

	var press_result: Dictionary = end_turn_control.press()
	assert_false(press_result.get("ok", true))

	var step_result: Dictionary = movement_input_controller.step_to(HexCoordClass.new(1, 0))
	assert_false(step_result.get("ok", true))


## SpyResolveActionUseCase — used ONLY to assert the use case is never
## invoked once a control is locked (mirrors
## tests/gut/test_presentation_controls_sticky_lock.gd's identically-named
## fixture).
class SpyResolveActionUseCase:
	var call_count: int = 0

	func resolve(combatant, action_economy, target, action_name: String, round_number: int, cycle_index: int) -> Dictionary:
		call_count += 1
		return {"ok": true, "resolved": true}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (regression guard): configure() with no MovementInputController
# injected remains a safe no-op -- pre-existing Strike/EndTurn-only callers
# are unaffected by this feature's additive third parameter.
# ══════════════════════════════════════════════════════════════════════════

func test_configure_without_movement_input_controller_is_a_safe_noop() -> void:
	_view.configure(null, null)
	_view.on_round_event({"round": 1, "outcome": "won"})
	assert_true(_view.is_shown())

	_view.lock_all_controls()
	_view.lock_all_controls()
	assert_true(_view.is_shown())
