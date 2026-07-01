extends GutTest
## tests/unit/presentation/test_end_turn_control.gd
##
## GUT test suite for FEAT-110 (US-010): EndTurnControl is always available
## for the active combatant -- enabled whether or not an action has been
## spent this turn -- and forwards a press directly to the injected, REUSED
## run_round_use_case.advance_turn() (ADR-002 -- no duplicate turn-
## advancement path), which advances initiative and emits a
## TurnAdvancedEvent observable by InitiativeView (ADR-003).
##
## Verifies:
##   1. EndTurnControl is enabled for the active player combatant both when
##      an action has been spent and when it has not.
##   2. Pressing end-turn invokes run_round_use_case.advance_turn(), emits a
##      TurnAdvancedEvent-shaped payload, and InitiativeView's active
##      highlight advances accordingly.
##   3. When no active combatant is configured, EndTurnControl is disabled
##      and end_turn() never invokes the injected use case.

const EndTurnControlScene: PackedScene = preload("res://presentation/end_turn_control.tscn")
const InitiativeViewScene: PackedScene = preload("res://presentation/initiative_view.tscn")

const ActionEconomyClass = preload("res://core/rules/action_economy.gd")
const EventSinkPortClass = preload("res://core/application/event_sink_port.gd")


## FakeEventSinkPort -- mirrors test_strike_action_control.gd's fixture:
## records every emitted event and optionally forwards it to Nodes exposing
## on_round_event(event) (e.g. InitiativeView), simulating the real
## SignalEventSinkAdapter integration point (ADR-003) without depending on
## a concrete adapter (out of scope for this feature).
class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []
	var forward_to: Array = []  # Array of Nodes exposing on_round_event(event)

	func emit(event) -> void:
		events.append(event)
		for target in forward_to:
			target.on_round_event(event)


## SpyRunRoundUseCase -- a spy standing in for run_round_use_case (this
## feature's documented contract: advance_turn(encounter_id) -> Dictionary)
## -- used to assert invocation without depending on a real turn-order rig.
class SpyRunRoundUseCase:
	var call_count: int = 0
	var last_encounter_id: String = ""
	var _result: Dictionary

	func _init(result: Dictionary = {"ok": true}) -> void:
		_result = result

	func advance_turn(encounter_id: String) -> Dictionary:
		call_count += 1
		last_encounter_id = encounter_id
		return _result


## ScriptedRunRoundUseCase -- a fuller fake that, like the real
## run_round_use_case would via its injected EventSinkPort, emits a
## TurnAdvancedEvent-shaped payload through the injected event sink when
## advance_turn() is invoked, so the InitiativeView integration criterion
## can be exercised end-to-end without depending on a concrete production
## adapter (out of scope for this feature).
class ScriptedRunRoundUseCase:
	var call_count: int = 0
	var _event_sink
	var _next_active_combatant_id: String

	func _init(event_sink, next_active_combatant_id: String) -> void:
		_event_sink = event_sink
		_next_active_combatant_id = next_active_combatant_id

	func advance_turn(encounter_id: String) -> Dictionary:
		call_count += 1
		var event: Dictionary = {"active_combatant_id": _next_active_combatant_id}
		_event_sink.emit(event)
		return {"ok": true, "event": event}


var _control = null


func before_each() -> void:
	_control = EndTurnControlScene.instantiate()
	add_child_autofree(_control)


func _actor(name: String = "Titus") -> Dictionary:
	return {"combatant_id": "titus", "name": name}


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: EndTurnControl is enabled for the active combatant both when
# an action has been spent and when it has not.
# ══════════════════════════════════════════════════════════════════════════════

func test_enabled_for_active_combatant_when_no_action_spent() -> void:
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	assert_false(action_economy.is_spent(), "sanity check: fresh action economy is not spent")

	var spy := SpyRunRoundUseCase.new()
	_control.configure(_actor(), action_economy, spy)

	assert_true(
		_control.is_enabled(),
		"EndTurnControl must be enabled for the active combatant when no action has been spent"
	)


func test_enabled_for_active_combatant_when_action_has_been_spent() -> void:
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	for i in range(ActionEconomyClass.MAX_BUDGET):
		action_economy.spend_action({})
	assert_true(action_economy.is_spent(), "sanity check: action economy is fully spent")

	var spy := SpyRunRoundUseCase.new()
	_control.configure(_actor(), action_economy, spy)

	assert_true(
		_control.is_enabled(),
		"EndTurnControl must remain enabled for the active combatant even after an action has been spent"
	)


func test_button_reflects_enabled_state_after_configure() -> void:
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()

	var spy := SpyRunRoundUseCase.new()
	_control.configure(_actor(), action_economy, spy)

	var button: Button = _control.get_node("EndTurnButton")
	assert_false(button.disabled, "the End Turn button must not be disabled for the active combatant")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: pressing end-turn invokes run_round_use_case.advance_turn,
# emits a TurnAdvancedEvent-shaped payload, and InitiativeView's active
# highlight advances accordingly.
# ══════════════════════════════════════════════════════════════════════════════

func test_end_turn_invokes_advance_turn_with_the_configured_encounter_id() -> void:
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()

	var spy := SpyRunRoundUseCase.new({"ok": true})
	_control.configure(_actor(), action_economy, spy, "prologue_encounter")

	var result: Dictionary = _control.end_turn()

	assert_eq(spy.call_count, 1, "end_turn() must invoke run_round_use_case.advance_turn() exactly once")
	assert_eq(spy.last_encounter_id, "prologue_encounter")
	assert_true(result.get("ok", false))


func test_end_turn_invokes_advance_turn_whether_or_not_action_was_spent() -> void:
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	for i in range(ActionEconomyClass.MAX_BUDGET):
		action_economy.spend_action({})
	assert_true(action_economy.is_spent())

	var spy := SpyRunRoundUseCase.new({"ok": true})
	_control.configure(_actor(), action_economy, spy, "prologue_encounter")

	var result: Dictionary = _control.end_turn()

	assert_eq(
		spy.call_count, 1,
		"end_turn() must still invoke run_round_use_case.advance_turn() after an action was spent"
	)
	assert_true(result.get("ok", false))


func test_end_turn_emits_turn_ended_signal() -> void:
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var spy := SpyRunRoundUseCase.new({"ok": true})
	_control.configure(_actor(), action_economy, spy)

	watch_signals(_control)
	_control.end_turn()

	assert_signal_emitted(_control, "turn_ended")


func test_end_turn_button_press_invokes_advance_turn() -> void:
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var spy := SpyRunRoundUseCase.new({"ok": true})
	_control.configure(_actor(), action_economy, spy)

	var button: Button = _control.get_node("EndTurnButton")
	button.pressed.emit()

	assert_eq(spy.call_count, 1, "pressing the End Turn button must invoke advance_turn()")


func test_end_turn_emits_turn_advanced_event_and_initiative_view_active_highlight_advances() -> void:
	var initiative_view = InitiativeViewScene.instantiate()
	add_child_autofree(initiative_view)
	initiative_view.load_combatants([
		{"combatant_id": "titus", "name": "Titus", "initiative_order": 17},
		{"combatant_id": "skeleton", "name": "Skeleton", "initiative_order": 9},
	])
	assert_eq(initiative_view.get_active_combatant_id(), "titus", "sanity check: Titus acts first")

	var event_sink := FakeEventSinkPort.new()
	event_sink.forward_to = [initiative_view]

	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var use_case := ScriptedRunRoundUseCase.new(event_sink, "skeleton")
	_control.configure(_actor(), action_economy, use_case, "prologue_encounter")

	var result: Dictionary = _control.end_turn()

	assert_eq(use_case.call_count, 1, "end_turn() must invoke run_round_use_case.advance_turn() exactly once")
	assert_eq(event_sink.events.size(), 1, "exactly one TurnAdvancedEvent-shaped payload must be emitted")
	assert_eq(event_sink.events[0].get("active_combatant_id"), "skeleton")
	assert_eq(
		result.get("event", {}).get("active_combatant_id"), "skeleton",
		"the returned result must carry the emitted TurnAdvancedEvent"
	)

	assert_eq(
		initiative_view.get_active_combatant_id(), "skeleton",
		"InitiativeView's active highlight must advance to the next combatant after end_turn()"
	)
	assert_true(initiative_view.is_active("skeleton"))
	assert_false(initiative_view.is_active("titus"), "the previously active entry must no longer be highlighted")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: with no active combatant configured, EndTurnControl is
# disabled and end_turn() never invokes the injected use case.
# ══════════════════════════════════════════════════════════════════════════════

func test_disabled_and_no_op_with_no_active_combatant_configured() -> void:
	assert_false(_control.is_enabled(), "EndTurnControl must be disabled before any active combatant is configured")

	var button: Button = _control.get_node("EndTurnButton")
	assert_true(button.disabled, "the End Turn button must be disabled before any active combatant is configured")


func test_end_turn_is_a_no_op_when_no_active_combatant_configured() -> void:
	var spy := SpyRunRoundUseCase.new({"ok": true})
	_control._run_round_use_case = spy

	var result: Dictionary = _control.end_turn()

	assert_false(result.get("ok", true))
	assert_eq(result.get("error", ""), "ERR_NO_ACTIVE_COMBATANT")
	assert_eq(spy.call_count, 0, "run_round_use_case.advance_turn() must never be invoked with no active combatant")
