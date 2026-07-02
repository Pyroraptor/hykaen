extends GutTest
## tests/gut/test_end_turn_controller.gd — FEAT-008 (US-008 / FR-008)
##
## GUT test suite for scenes/battlefield/EndTurnController.gd — the
## player-facing control that lets the active combatant end their turn/pass
## at any point, completing the steel thread's "passes their turn" step
## alongside scenes/battlefield/StrikeInputController.gd (FEAT-007) and the
## turn-order surface it sits next to (scenes/battlefield/TurnOrderWidget.gd,
## FEAT-006).
##
## Verifies (test_criteria):
##   1. Pressing pass/end-turn invokes the round-advancement path obtained
##      from run_round_use_case (core/application/run_round_use_case.gd's
##      begin_round() -> RoundSession, ADR-007's stepwise API) with the
##      correct target -- this steel thread's RunRoundUseCase manages exactly
##      one encounter/round at a time with no separate encounter_id
##      parameter anywhere in its contract (confirmed by inspection of
##      core/application/run_round_use_case.gd and round_session.gd), so
##      "the correct encounter_id" is realized here as "the correct injected
##      RoundSession instance" -- verified both via a spy RoundSession (exact
##      call count/identity) and against the REAL RunRoundUseCase/RoundSession
##      pipeline (mirrors tests/gut/test_turn_order_widget.gd's isolation
##      strategy: only the ports are fakes).
##   2. InitiativeOrder's active combatant (RoundSession.current_actor())
##      advances to the next combatant after a pass.
##   3. ENCOUNTER_ALREADY_RESOLVED is handled gracefully without crash if
##      pass is issued after resolution (or with no session configured at
##      all) -- no exception, a typed, non-blocking error result instead.
##   4. TurnOrderWidget (FEAT-006) reflects the new active combatant
##      immediately after pass (exercised via the real EventSinkPort ->
##      TurnAdvancedEvent -> TurnOrderWidget.on_round_event() forwarding
##      path RunRoundUseCase/RoundSession already drive, exactly as
##      production MainScene.gd wires it).

const EndTurnControllerClass = preload("res://scenes/battlefield/EndTurnController.gd")
const TurnOrderWidgetScene: PackedScene = preload("res://scenes/battlefield/TurnOrderWidget.tscn")

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")

const END_TURN_CONTROLLER_SOURCE_PATH: String = "res://scenes/battlefield/EndTurnController.gd"


# ── Fake/double port implementations (mirrors test_turn_order_widget.gd) ───

class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []
	var forward_to = null

	func emit(event) -> void:
		events.append(event)
		if forward_to != null:
			forward_to.on_round_event(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


## FakeAIDecisionPort — "Strike the first living target" (mirrors
## core/combat/ai.gd's real v0 behavior).
class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant: Dictionary, targets: Array) -> Dictionary:
		for t in targets:
			if t.get("hp_current", 0) > 0:
				return {"action_type": "Strike", "target": t}
		return {"action_type": "", "target": {}}


## SpyRoundSession — a spy/stub standing in for RoundSession
## (core/application/round_session.gd): records every end_current_turn()
## call and returns a scripted result, without pulling in the full
## RunRoundUseCase/RoundSession machinery. Mirrors
## tests/gut/test_strike_input_controller.gd's ScriptedResolveActionUseCase
## pattern.
class SpyRoundSession:
	var end_current_turn_call_count: int = 0
	var round_over: bool = false
	var actor: Dictionary = {}
	var _result: Dictionary

	func _init(p_actor: Dictionary = {}, p_round_over: bool = false, result: Dictionary = {"ok": true, "round_over": false}) -> void:
		actor = p_actor
		round_over = p_round_over
		_result = result

	func is_round_over() -> bool:
		return round_over

	func current_actor() -> Dictionary:
		return actor

	func end_current_turn() -> Dictionary:
		end_current_turn_call_count += 1
		return _result


var _controller = null


func before_each() -> void:
	_controller = EndTurnControllerClass.new()


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: pressing pass/end-turn invokes the round-advancement path
# (run_round_use_case's RoundSession) with the correct target.
# ══════════════════════════════════════════════════════════════════════════

func test_press_invokes_round_session_end_current_turn_exactly_once() -> void:
	var spy := SpyRoundSession.new({"name": "Titus", "_is_enemy": false})
	_controller.configure(spy)

	var result: Dictionary = _controller.press()

	assert_eq(spy.end_current_turn_call_count, 1, "end_current_turn() must be invoked exactly once")
	assert_true(result.get("ok", false))


func test_press_never_invokes_a_round_session_it_was_not_configured_with() -> void:
	var configured_spy := SpyRoundSession.new({"name": "Titus", "_is_enemy": false})
	var other_spy := SpyRoundSession.new({"name": "Marigold", "_is_enemy": false})

	_controller.configure(configured_spy)
	_controller.press()

	assert_eq(configured_spy.end_current_turn_call_count, 1, "the configured RoundSession must be the one advanced")
	assert_eq(other_spy.end_current_turn_call_count, 0, "an unrelated RoundSession must never be touched")


func test_press_emits_turn_ended_signal_with_the_result() -> void:
	var spy := SpyRoundSession.new({"name": "Titus", "_is_enemy": false}, false, {"ok": true, "round_over": false, "outcome": ""})
	_controller.configure(spy)

	watch_signals(_controller)
	var result: Dictionary = _controller.press()

	assert_signal_emitted(_controller, "turn_ended")
	assert_signal_emitted_with_parameters(_controller, "turn_ended", [result])


func test_reconfiguring_with_a_new_session_directs_subsequent_presses_there() -> void:
	var first_spy := SpyRoundSession.new({"name": "Titus", "_is_enemy": false})
	var second_spy := SpyRoundSession.new({"name": "Marigold", "_is_enemy": false})

	_controller.configure(first_spy)
	_controller.press()
	_controller.configure(second_spy)
	_controller.press()

	assert_eq(first_spy.end_current_turn_call_count, 1)
	assert_eq(second_spy.end_current_turn_call_count, 1)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 + 4: InitiativeOrder's active combatant advances to the next
# combatant after pass, and TurnOrderWidget reflects it immediately --
# exercised against the REAL RunRoundUseCase/RoundSession/EventSinkPort
# pipeline (only the ports are fakes).
# ══════════════════════════════════════════════════════════════════════════

func _durable_combatant(p_name: String, p_is_enemy: bool, p_combatant_id: String) -> Dictionary:
	return {
		"name":         p_name,
		"combatant_id": p_combatant_id,
		"hp_current":   2000,
		"ac":           10,
		"strength":     3,
		"dexterity":    2,
		"intuition":    2,
		"_is_enemy":    p_is_enemy,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	}


func _entry(combatant: Dictionary) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


func _make_use_case(entries: Array, ai_port, seed: int, event_sink) -> Dictionary:
	var turn_order_port     = FakeTurnOrderPort.new(entries)
	var round_history_port  = FakeRoundHistoryPort.new()
	var random_number_port  = SeededRandomAdapterClass.new(seed)

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink, round_history_port, ai_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	return {"use_case": run_round_use_case, "history": round_history_port}


func test_press_advances_current_actor_to_the_next_combatant_via_real_round_session() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var bravo: Dictionary = _durable_combatant("Bravo", true, "bravo")
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var event_sink := FakeEventSinkPort.new()
	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1, event_sink)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_eq(session.current_actor().get("name", ""), "Alpha", "Alpha must be the first active combatant")

	_controller.configure(session)
	_controller.press()

	assert_eq(
		session.current_actor().get("name", ""), "Bravo",
		"pressing pass must advance run_round_use_case's RoundSession to the next combatant"
	)


func test_turn_order_widget_reflects_the_new_active_combatant_immediately_after_pass() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var bravo: Dictionary = _durable_combatant("Bravo", true, "bravo")
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var widget = TurnOrderWidgetScene.instantiate()
	add_child_autofree(widget)
	widget.load_combatants([
		{"combatant_id": "alpha", "name": "Alpha", "initiative_order": 20},
		{"combatant_id": "bravo", "name": "Bravo", "initiative_order": 5},
	])
	assert_true(widget.is_active("alpha"), "Alpha (higher initiative) must be active before any turn advances")

	var event_sink := FakeEventSinkPort.new()
	event_sink.forward_to = widget
	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 2, event_sink)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	_controller.configure(session)
	_controller.press()

	assert_true(
		widget.is_active("bravo"),
		"TurnOrderWidget must flag Bravo active immediately after EndTurnController.press() advances the round"
	)
	assert_false(widget.is_active("alpha"), "Alpha must no longer be flagged active once the turn advances")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: ENCOUNTER_ALREADY_RESOLVED is handled gracefully without
# crash if pass is issued after resolution.
# ══════════════════════════════════════════════════════════════════════════

func test_press_after_round_already_over_returns_typed_error_without_crashing() -> void:
	var spy := SpyRoundSession.new({}, true)
	_controller.configure(spy)

	var result: Dictionary = _controller.press()

	assert_false(result.get("ok", true), "pressing pass after resolution must not report success")
	assert_eq(result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")
	assert_eq(spy.end_current_turn_call_count, 0, "an already-resolved session must never be asked to advance again")


func test_press_with_no_session_configured_returns_typed_error_without_crashing() -> void:
	var result: Dictionary = _controller.press()

	assert_false(result.get("ok", true))
	assert_eq(result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")


func test_press_surfaces_inline_error_and_emits_action_error_signal() -> void:
	var spy := SpyRoundSession.new({}, true)
	_controller.configure(spy)

	watch_signals(_controller)
	_controller.press()

	assert_true(_controller.has_error())
	assert_signal_emitted(_controller, "action_error")


func test_a_defensively_failed_end_current_turn_result_is_also_treated_as_already_resolved() -> void:
	# Even when is_round_over() had not yet flipped true but the underlying
	# RoundSession itself declines to advance (e.g. a race/edge condition),
	# EndTurnController must never crash or report false success.
	var spy := SpyRoundSession.new({"name": "Titus", "_is_enemy": false}, false, {"ok": false})
	_controller.configure(spy)

	var result: Dictionary = _controller.press()

	assert_false(result.get("ok", true))
	assert_eq(result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")


func test_real_round_session_driven_to_completion_then_pressed_again_does_not_crash() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var entries: Array = [_entry(alpha)]

	var event_sink := FakeEventSinkPort.new()
	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 3, event_sink)
	var session = rig["use_case"].begin_round(1, [alpha], [])

	_controller.configure(session)
	_controller.press()  # the only living combatant ends their turn -> round over

	assert_true(session.is_round_over(), "a single-combatant round must be over once that combatant's turn ends")

	var result: Dictionary = _controller.press()  # pass again after resolution

	assert_false(result.get("ok", true), "a pass issued after resolution must not succeed")
	assert_eq(result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")


# ══════════════════════════════════════════════════════════════════════════
# is_enabled() -- proactive UI affordance gating (error_handling design note:
# "UI disables/greys the affordance proactively"), mirroring the prior
# iteration's presentation/end_turn_control.gd contract.
# ══════════════════════════════════════════════════════════════════════════

func test_is_enabled_true_for_a_living_player_actor_with_the_round_not_over() -> void:
	var spy := SpyRoundSession.new({"name": "Titus", "_is_enemy": false}, false)
	_controller.configure(spy)
	assert_true(_controller.is_enabled())


func test_is_enabled_false_once_the_round_is_over() -> void:
	var spy := SpyRoundSession.new({}, true)
	_controller.configure(spy)
	assert_false(_controller.is_enabled())


func test_is_enabled_false_with_no_session_configured() -> void:
	assert_false(_controller.is_enabled())


# ══════════════════════════════════════════════════════════════════════════
# Code-review guardrail: no combat computation / no duplicate action path --
# EndTurnController never resolves an action itself.
# ══════════════════════════════════════════════════════════════════════════

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_never_calls_resolve_action_use_case() -> void:
	var source: String = _read_source(END_TURN_CONTROLLER_SOURCE_PATH)
	assert_eq(
		source.findn("resolve_action_use_case"), -1,
		"EndTurnController.gd must never call resolve_action_use_case -- it only ends turns, never resolves an action"
	)


func test_source_contains_no_hit_or_damage_computation_keywords() -> void:
	var source: String = _read_source(END_TURN_CONTROLLER_SOURCE_PATH).to_lower()
	var forbidden_keywords: Array = [
		"roll_attack", "damage_die", "compute_ac", "compute_hp", "hit_chance", "randi(", "randf(",
	]
	for keyword in forbidden_keywords:
		assert_eq(
			source.find(keyword), -1,
			"scenes/battlefield/EndTurnController.gd must contain no hit/damage computation ('%s' found)" % keyword
		)
