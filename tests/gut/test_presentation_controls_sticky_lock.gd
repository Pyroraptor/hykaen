extends GutTest
## tests/gut/test_presentation_controls_sticky_lock.gd — FEAT-137 (DEF-004 /
## US-010 / FR-010)
##
## GUT test suite reproducing DEF-004: presentation/result_screen_view.gd's
## _disable_combat_controls() used to perform a one-time
## configure()-clear on presentation/strike_action_control.gd and
## presentation/end_turn_control.gd rather than a persistent lock, unlike
## scenes/battlefield/ResultScreen.gd's sticky lock()/is_locked() guard on
## StrikeInputController/EndTurnController. A stray reconfigure() call after
## EncounterResultEvent fired could therefore re-enable input through the
## presentation/* path.
##
## This suite ports the sticky lock()/is_locked() pattern verification onto
## presentation/strike_action_control.gd and presentation/end_turn_control.gd,
## mirroring tests/gut/test_result_screen.gd::
## test_locked_controller_stays_locked_even_after_a_stray_reconfigure exactly,
## but scoped to the presentation/* controllers instead of their
## scenes/battlefield/* counterparts.
##
## Verifies (test_criteria):
##   1. select_target() (StrikeActionControl) and press() (EndTurnControl)
##      are rejected once lock() has been engaged, and reject rejection
##      persists across a later, stray configure() call (the reproduction of
##      DEF-004's regression scenario).
##   2. is_locked() returns true on both controls after ResultScreenView
##      observes an EncounterResultEvent, and stays true through any
##      subsequent configure() call on either control.

const StrikeActionControlScene: PackedScene = preload("res://presentation/strike_action_control.tscn")
const EndTurnControlScene: PackedScene      = preload("res://presentation/end_turn_control.tscn")
const ResultScreenViewScene: PackedScene    = preload("res://presentation/result_screen_view.tscn")

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const HexCoordClass             = preload("res://core/geometry/hex_coord.gd")


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


## SpyResolveActionUseCase — used ONLY to assert the use case is never
## invoked once a control is locked (mirrors
## tests/unit/presentation/test_strike_action_control.gd's identically-named
## fixture).
class SpyResolveActionUseCase:
	var call_count: int = 0

	func resolve(combatant, action_economy, target, action_name: String, round_number: int, cycle_index: int) -> Dictionary:
		call_count += 1
		return {"ok": true, "resolved": true}


## FakeRoundSession — minimal stand-in for core/application/round_session.gd's
## RoundSession, exposing only what EndTurnControl.is_enabled()/press() rely
## on (mirrors tests/unit/presentation/test_result_screen_view.gd's
## identically-named fixture).
class FakeRoundSession:
	var _actor: Dictionary
	var _round_over: bool = false
	var end_current_turn_call_count: int = 0

	func _init(actor: Dictionary) -> void:
		_actor = actor

	func current_actor() -> Dictionary:
		return {} if _round_over else _actor

	func is_round_over() -> bool:
		return _round_over

	func end_current_turn() -> Dictionary:
		end_current_turn_call_count += 1
		return {"ok": true, "round_over": false}


func _actor(hex_coord) -> Dictionary:
	return {
		"combatant_id": "titus",
		"name": "Titus",
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
# Criterion 1: select_target()/press() are rejected once lock() is engaged,
# and rejection is sticky across a later, stray configure() call — the
# DEF-004 regression scenario.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_action_control_stays_locked_even_after_a_stray_reconfigure() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var control = StrikeActionControlScene.instantiate()
	add_child_autofree(control)

	var rig: Dictionary = _make_use_case([12, 4])
	control.configure(_actor(origin), ActionEconomyClass.new(), rig["use_case"], [adjacent_enemy])
	assert_true(control.is_target_selectable("skeleton"), "sanity check: target is selectable before lock()")

	control.lock()

	assert_true(control.is_locked(), "StrikeActionControl must report is_locked() == true once lock() is engaged")
	assert_false(control.is_target_selectable("skeleton"), "no target may remain selectable once locked")
	assert_eq(control.get_button_count(), 0, "every selectable-target button must be cleared once locked")

	# The DEF-004 regression: a stray reconfigure() call (e.g. a leftover
	# TurnController signal) after lock() must NOT re-enable input.
	var spy := SpyResolveActionUseCase.new()
	control.configure(_actor(origin), ActionEconomyClass.new(), spy, [adjacent_enemy])

	assert_true(control.is_locked(), "is_locked() must stay true through a later configure() call")
	assert_false(control.is_target_selectable("skeleton"), "a stray reconfigure() must not re-enable target selection")
	assert_eq(control.get_button_count(), 0, "a stray reconfigure() must not re-render any selectable-target button")

	var result: Dictionary = control.select_target("skeleton")
	assert_false(result.get("ok", true), "select_target() must be rejected once locked, even after a stray reconfigure()")
	assert_eq(result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")
	assert_eq(spy.call_count, 0, "resolve_action_use_case must never be invoked once locked")


func test_end_turn_control_stays_locked_even_after_a_stray_reconfigure() -> void:
	var control = EndTurnControlScene.instantiate()
	add_child_autofree(control)

	var session := FakeRoundSession.new({"name": "Titus", "_is_enemy": false})
	control.configure(session)
	assert_true(control.is_enabled(), "sanity check: control is enabled before lock()")

	control.lock()

	assert_true(control.is_locked(), "EndTurnControl must report is_locked() == true once lock() is engaged")
	assert_false(control.is_enabled(), "EndTurnControl must be disabled once locked")

	# The DEF-004 regression: a stray reconfigure() call with a fresh
	# RoundSession must NOT re-enable input.
	var fresh_session := FakeRoundSession.new({"name": "Titus", "_is_enemy": false})
	control.configure(fresh_session)

	assert_true(control.is_locked(), "is_locked() must stay true through a later configure() call")
	assert_false(control.is_enabled(), "a stray reconfigure() must not re-enable the control")

	var result: Dictionary = control.press()
	assert_false(result.get("ok", true), "press() must be rejected once locked, even after a stray reconfigure()")
	assert_eq(result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")
	assert_eq(fresh_session.end_current_turn_call_count, 0, "end_current_turn() must never be invoked once locked")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: is_locked() returns true on both controls after
# ResultScreenView observes an EncounterResultEvent, and stays true through
# any subsequent configure() call.
# ══════════════════════════════════════════════════════════════════════════

func test_is_locked_true_after_encounter_result_event_via_result_screen_view_and_stays_true_through_reconfigure() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var strike_control = StrikeActionControlScene.instantiate()
	add_child_autofree(strike_control)
	var end_turn_control = EndTurnControlScene.instantiate()
	add_child_autofree(end_turn_control)
	var view = ResultScreenViewScene.instantiate()
	add_child_autofree(view)

	var rig: Dictionary = _make_use_case([12, 4])
	strike_control.configure(_actor(origin), ActionEconomyClass.new(), rig["use_case"], [adjacent_enemy])
	end_turn_control.configure(FakeRoundSession.new({"name": "Titus", "_is_enemy": false}))

	assert_false(strike_control.is_locked())
	assert_false(end_turn_control.is_locked())

	view.configure(strike_control, end_turn_control)
	view.on_round_event({"round": 1, "outcome": "won"})

	assert_true(strike_control.is_locked(), "StrikeActionControl.is_locked() must be true after EncounterResultEvent fires")
	assert_true(end_turn_control.is_locked(), "EndTurnControl.is_locked() must be true after EncounterResultEvent fires")

	# A stray reconfigure() call on either control after the encounter has
	# concluded must not unlock either one (the DEF-004 regression).
	var spy := SpyResolveActionUseCase.new()
	strike_control.configure(_actor(origin), ActionEconomyClass.new(), spy, [adjacent_enemy])
	end_turn_control.configure(FakeRoundSession.new({"name": "Titus", "_is_enemy": false}))

	assert_true(strike_control.is_locked(), "StrikeActionControl must stay locked through a later configure() call")
	assert_true(end_turn_control.is_locked(), "EndTurnControl must stay locked through a later configure() call")

	var strike_result: Dictionary = strike_control.select_target("skeleton")
	assert_false(strike_result.get("ok", true))
	assert_eq(strike_result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")
	assert_eq(spy.call_count, 0)

	var press_result: Dictionary = end_turn_control.press()
	assert_false(press_result.get("ok", true))
	assert_eq(press_result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")
