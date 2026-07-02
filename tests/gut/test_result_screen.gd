extends GutTest
## tests/gut/test_result_screen.gd — FEAT-010 (US-010 / FR-010)
##
## GUT test suite for scenes/battlefield/ResultScreen.gd — the terminal
## projection that realizes the steel thread's exit_point: "A Win or Loss
## result screen is displayed after EncounterResultEvent fires, with the full
## event log and final combatant states visible", and blocks further player
## input once shown.
##
## Verifies (test_criteria):
##   1. ResultScreen becomes visible and displays WIN or LOSS text matching
##      EncounterResultEvent.outcome.
##   2. StrikeInputController and EndTurnController reject/ignore further
##      input after EncounterResultEvent fires.
##   3. The final combatant HP/state snapshot and full ordered event log are
##      visible on the result screen.

const ResultScreenScene: PackedScene = preload("res://scenes/battlefield/ResultScreen.tscn")
const StrikeInputControllerClass = preload("res://scenes/battlefield/StrikeInputController.gd")
const EndTurnControllerClass     = preload("res://scenes/battlefield/EndTurnController.gd")

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
const HexCoordClass             = preload("res://core/geometry/hex_coord.gd")

const RESULT_SCREEN_SOURCE_PATH: String = "res://scenes/battlefield/ResultScreen.gd"


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


## FakeRoundSession — minimal stand-in for core/application/round_session.gd's
## RoundSession, exposing only the two methods EndTurnController.is_enabled()
## /press() rely on, mirroring tests/gut/test_end_turn_controller.gd's
## SpyRoundSession.
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


var _view = null


func before_each() -> void:
	_view = ResultScreenScene.instantiate()
	add_child_autofree(_view)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: ResultScreen becomes visible and displays WIN or LOSS text
# matching EncounterResultEvent.outcome.
# ══════════════════════════════════════════════════════════════════════════

func test_not_visible_before_any_encounter_result_event() -> void:
	assert_false(_view.visible)
	assert_false(_view.is_shown())
	assert_eq(_view.get_result_text(), "")


func test_becomes_visible_and_displays_win_for_won_outcome() -> void:
	_view.on_round_event({"round": 1, "outcome": "won"})

	assert_true(_view.visible, "ResultScreen must become visible once EncounterResultEvent fires")
	assert_true(_view.is_shown())
	assert_eq(_view.get_result_text(), "Win")
	assert_string_contains(_view.get_label_text(), "Win")


func test_becomes_visible_and_displays_loss_for_lost_outcome() -> void:
	_view.on_round_event({"round": 1, "outcome": "lost"})

	assert_true(_view.visible, "ResultScreen must become visible once EncounterResultEvent fires")
	assert_true(_view.is_shown())
	assert_eq(_view.get_result_text(), "Loss")
	assert_string_contains(_view.get_label_text(), "Loss")


func test_ignores_unrelated_round_event_shapes() -> void:
	_view.on_round_event({"active_combatant_id": "titus"})
	assert_false(_view.visible, "ResultScreen must ignore any event shape other than EncounterResultEvent")
	assert_false(_view.is_shown())


func test_renders_win_with_real_production_encounter_result_event() -> void:
	var event = RoundEventsClass.EncounterResultEvent.new(3, "won")
	_view.on_round_event(event)
	assert_eq(_view.get_result_text(), "Win")
	assert_true(_view.visible)


func test_result_shown_signal_emits_with_result_text() -> void:
	watch_signals(_view)
	_view.on_round_event({"round": 1, "outcome": "lost"})
	assert_signal_emitted_with_parameters(_view, "result_shown", ["Loss"])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: StrikeInputController and EndTurnController reject/ignore
# further input after EncounterResultEvent fires.
# ══════════════════════════════════════════════════════════════════════════

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


func test_strike_input_controller_rejects_further_input_after_encounter_result_event() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var rng_port   = ScriptedRandomNumberPort.new([12, 4, 12, 4])
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)

	var strike_controller = StrikeInputControllerClass.new()
	strike_controller.configure(_actor(origin), ActionEconomyClass.new(), use_case, [adjacent_enemy], "titus")
	assert_true(strike_controller.is_target_selectable("skeleton"), "sanity check: target is selectable before the encounter concludes")

	_view.configure([], strike_controller, null)
	_view.on_round_event({"round": 1, "outcome": "won"})

	assert_true(strike_controller.is_locked(), "StrikeInputController must be locked once the result screen is shown")
	assert_false(strike_controller.is_target_selectable("skeleton"), "no target may remain selectable once the encounter concludes")

	var result: Dictionary = strike_controller.select_target("skeleton")
	assert_false(result.get("ok", true), "select_target() must be rejected once the encounter has concluded")
	assert_eq(result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")
	assert_eq(event_sink.events.size(), 0, "no further AttackEvent may be emitted once the encounter has concluded")


func test_end_turn_controller_rejects_further_input_after_encounter_result_event() -> void:
	var session := FakeRoundSession.new({"name": "Titus", "_is_enemy": false})
	var end_turn_controller = EndTurnControllerClass.new()
	end_turn_controller.configure(session)
	assert_true(end_turn_controller.is_enabled(), "sanity check: EndTurnController starts enabled for the active player combatant")

	_view.configure([], null, end_turn_controller)
	_view.on_round_event({"round": 1, "outcome": "lost"})

	assert_true(end_turn_controller.is_locked(), "EndTurnController must be locked once the result screen is shown")
	assert_false(end_turn_controller.is_enabled(), "EndTurnController must be disabled once the result screen is shown")

	var result: Dictionary = end_turn_controller.press()
	assert_false(result.get("ok", true), "press() must be rejected once the encounter has concluded")
	assert_eq(result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")
	assert_eq(session.end_current_turn_call_count, 0, "end_current_turn() must never be invoked once the encounter has concluded")


func test_locked_controller_stays_locked_even_after_a_stray_reconfigure() -> void:
	# Defense-in-depth: lock() is sticky even across a later configure() call
	# (e.g. a leftover signal from elsewhere) -- see file-level doc.
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))
	var spy_use_case = ResolveActionUseCaseClass.new(
		ScriptedRandomNumberPort.new([12, 4]), FakeEventSinkPort.new(), FakeRoundHistoryPort.new()
	)

	var strike_controller = StrikeInputControllerClass.new()
	var end_turn_controller = EndTurnControllerClass.new()
	_view.configure([], strike_controller, end_turn_controller)
	_view.on_round_event({"round": 1, "outcome": "won"})

	# A stray reconfigure after the encounter concluded must not unlock either controller.
	strike_controller.configure(_actor(origin), ActionEconomyClass.new(), spy_use_case, [adjacent_enemy], "titus")
	end_turn_controller.configure(FakeRoundSession.new({"name": "Titus", "_is_enemy": false}))

	assert_true(strike_controller.is_locked())
	assert_false(strike_controller.is_target_selectable("skeleton"))
	assert_true(end_turn_controller.is_locked())
	assert_false(end_turn_controller.is_enabled())


func test_no_controllers_injected_is_a_safe_noop() -> void:
	# configure() never called with controllers -- both remain null. Must not error.
	_view.on_round_event({"round": 1, "outcome": "won"})
	assert_true(_view.is_shown())


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: the final combatant HP/state snapshot and full ordered event
# log are visible on the result screen.
# ══════════════════════════════════════════════════════════════════════════

func test_final_combatant_snapshot_reflects_live_combatant_state_at_conclusion() -> void:
	var titus: Dictionary = {"combatant_id": "titus", "name": "Titus", "hp_current": 15, "hp_max": 20}
	var skeleton: Dictionary = {"combatant_id": "skeleton", "name": "Skeleton", "hp_current": 0, "hp_max": 12}

	_view.configure([titus, skeleton], null, null)

	# The combatant dictionaries are LIVE references -- mutate them in place,
	# exactly as resolve_action_use_case does throughout an encounter, before
	# the terminal event fires.
	titus["hp_current"] = 9

	_view.on_round_event({"round": 2, "outcome": "won"})

	var snapshot: Array = _view.get_final_snapshot()
	assert_eq(snapshot.size(), 2, "the final snapshot must contain every injected combatant")
	assert_eq(snapshot[0], {"combatant_id": "titus", "name": "Titus", "hp_current": 9, "hp_max": 20})
	assert_eq(snapshot[1], {"combatant_id": "skeleton", "name": "Skeleton", "hp_current": 0, "hp_max": 12})

	assert_eq(_view.get_snapshot_row_count(), 2, "one rendered row per combatant")
	assert_string_contains(_view.get_snapshot_row_text(0), "Titus")
	assert_string_contains(_view.get_snapshot_row_text(0), "9")
	assert_string_contains(_view.get_snapshot_row_text(1), "Skeleton")
	assert_string_contains(_view.get_snapshot_row_text(1).to_lower(), "defeated")


func test_final_snapshot_empty_before_any_encounter_result_event() -> void:
	_view.configure([{"combatant_id": "titus", "name": "Titus", "hp_current": 15, "hp_max": 20}], null, null)
	assert_eq(_view.get_final_snapshot(), [])
	assert_eq(_view.get_snapshot_row_count(), 0)


func test_full_event_log_is_visible_in_dispatch_order_after_encounter_result_event() -> void:
	var attack_event = RoundEventsClass.AttackEvent.new(1, "Titus", "Skeleton", 17, "ac", 10, true, false, 6)
	var defeated_event = RoundEventsClass.CombatantDefeatedEvent.new(1, "Skeleton", "Titus")
	var result_event = RoundEventsClass.EncounterResultEvent.new(1, "won")

	_view.on_round_event(attack_event)
	_view.on_round_event(defeated_event)
	_view.on_round_event(result_event)

	assert_eq(_view.get_event_log_entry_count(), 3, "every recognized round event must be recorded, in order")

	assert_string_contains(_view.get_event_log_entry_text(0), "Titus")
	assert_string_contains(_view.get_event_log_entry_text(0), "Skeleton")
	assert_string_contains(_view.get_event_log_entry_text(1), "Skeleton")
	assert_string_contains(_view.get_event_log_entry_text(1).to_lower(), "defeated")
	assert_string_contains(_view.get_event_log_entry_text(2).to_lower(), "won")

	# Rendered rows mirror the recorded entries verbatim, in the same order.
	assert_eq(_view.get_event_log_row_text(0), _view.get_event_log_entry_text(0))
	assert_eq(_view.get_event_log_row_text(1), _view.get_event_log_entry_text(1))
	assert_eq(_view.get_event_log_row_text(2), _view.get_event_log_entry_text(2))


func test_event_log_ignores_unrecognized_event_shapes() -> void:
	_view.on_round_event({"active_combatant_id": "titus", "round": 1})
	_view.on_round_event(RoundEventsClass.EncounterResultEvent.new(1, "won"))
	# Only the recognized EncounterResultEvent must be logged.
	assert_eq(_view.get_event_log_entry_count(), 1)


func test_event_log_empty_before_any_event_received() -> void:
	assert_eq(_view.get_event_log_entry_count(), 0)


# ══════════════════════════════════════════════════════════════════════════
# Code-review guardrail: ResultScreen is a read-only terminal projection --
# it must never call into either combat-state-mutating use case.
# ══════════════════════════════════════════════════════════════════════════

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_contains_no_direct_resolve_action_use_case_reference() -> void:
	var source: String = _read_source(RESULT_SCREEN_SOURCE_PATH)
	assert_eq(
		source.findn("resolve_action_use_case"), -1,
		"ResultScreen.gd must never reference resolve_action_use_case (read-only terminal projection)"
	)


func test_source_contains_no_direct_run_round_use_case_reference() -> void:
	var source: String = _read_source(RESULT_SCREEN_SOURCE_PATH)
	assert_eq(
		source.findn("run_round_use_case"), -1,
		"ResultScreen.gd must never reference run_round_use_case (read-only terminal projection)"
	)
