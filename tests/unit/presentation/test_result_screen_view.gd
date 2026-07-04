extends GutTest
## tests/unit/presentation/test_result_screen_view.gd
##
## GUT test suite for FEAT-112 (US-012): ResultScreenView subscribes to
## EncounterResultEvent via the shared EventSinkPort pipeline (ADR-003) and
## renders Win/Loss, disabling all combat input controls once shown.
##
## Verifies:
##   1. ResultScreenView renders 'Win' for a simulated EncounterResultEvent
##      with outcome == 'won' (the party's winning side, per
##      determine_outcome_use_case.classify()'s contract) and 'Loss' for
##      outcome == 'lost'.
##   2. The injected Strike control and EndTurnControl are disabled
##      immediately after an EncounterResultEvent is received by
##      ResultScreenView. FEAT-006 (US-006) removed the real
##      presentation/strike_action_control.gd (its immediate-resolve-on-click
##      UI competed with the new Layer 1/Layer 2 Strike flow);
##      ResultScreenView's `strike_action_control` parameter/lock_all_controls()
##      remain generic/duck-typed (calling only lock()/is_locked()/
##      get_button_count()), so FakeLockableStrikeControl below continues to
##      exercise that same mechanism.
##   3. The displayed outcome matches determine_outcome_use_case.classify()
##      (+ build_event()) for an equivalent encounter state — no divergent
##      classification between the real use case and this view.
##   4. Code-review assertion (source-inspection): result_screen_view.gd
##      contains no direct reference to resolve_action_use_case or
##      run_round_use_case — ResultScreenView must never call into a use
##      case (read-only terminal projection).

const ResultScreenViewScene: PackedScene    = preload("res://presentation/result_screen_view.tscn")
const EndTurnControlScene: PackedScene      = preload("res://presentation/end_turn_control.tscn")

const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const RoundEventsClass             = preload("res://core/rules/round_events.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")

const RESULT_SCREEN_VIEW_PATH: String = "res://presentation/result_screen_view.gd"


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
## RoundSession, exposing only the two methods EndTurnControl.is_enabled()
## relies on (current_actor()/is_round_over()), so criterion 2 does not need
## to spin up a full RunRoundUseCase rig just to prove EndTurnControl starts
## enabled and ends up disabled.
class FakeRoundSession:
	var _actor: Dictionary
	var _round_over: bool = false

	func _init(actor: Dictionary) -> void:
		_actor = actor

	func current_actor() -> Dictionary:
		return {} if _round_over else _actor

	func is_round_over() -> bool:
		return _round_over


var _view = null


func before_each() -> void:
	_view = ResultScreenViewScene.instantiate()
	add_child_autofree(_view)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: renders 'Win' for outcome == 'won', 'Loss' for outcome == 'lost'.
# ══════════════════════════════════════════════════════════════════════════

func test_renders_win_for_won_outcome() -> void:
	_view.on_round_event({"round": 1, "outcome": "won"})
	assert_eq(_view.get_result_text(), "Win")
	assert_true(_view.is_shown())
	assert_string_contains(_view.get_label_text(), "Win")


func test_renders_loss_for_lost_outcome() -> void:
	_view.on_round_event({"round": 1, "outcome": "lost"})
	assert_eq(_view.get_result_text(), "Loss")
	assert_true(_view.is_shown())
	assert_string_contains(_view.get_label_text(), "Loss")


func test_not_shown_before_any_encounter_result_event() -> void:
	assert_false(_view.is_shown())
	assert_eq(_view.get_result_text(), "")


func test_ignores_unrelated_round_event_shapes() -> void:
	_view.on_round_event({"target_name": "Titus", "damage_final": 5})
	_view.on_round_event({"name": "Goblin", "defeated_by": "Titus"})
	_view.on_round_event({"active_combatant_id": "titus"})
	assert_false(_view.is_shown(), "ResultScreenView must ignore any event shape other than EncounterResultEvent")


func test_renders_win_with_real_production_encounter_result_event() -> void:
	# Exercises the ACTUAL core/rules/round_events.gd shape, not only the
	# Dictionary test double above.
	var event = RoundEventsClass.EncounterResultEvent.new(3, "won")
	_view.on_round_event(event)
	assert_eq(_view.get_result_text(), "Win")


func test_result_shown_signal_emits_with_result_text() -> void:
	watch_signals(_view)
	_view.on_round_event({"round": 1, "outcome": "lost"})
	assert_signal_emitted_with_parameters(_view, "result_shown", ["Loss"])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: StrikeActionControl and EndTurnControl are disabled
# immediately after EncounterResultEvent is received.
# ══════════════════════════════════════════════════════════════════════════

func _actor(hex_coord) -> Dictionary:
	return {
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


func test_strike_action_control_disabled_after_encounter_result_event() -> void:
	var strike_control = StrikeActionControlScene.instantiate()
	add_child_autofree(strike_control)

	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var rng_port   = ScriptedRandomNumberPort.new([12, 4])
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)

	strike_control.configure(_actor(origin), ActionEconomyClass.new(), use_case, [adjacent_enemy])
	assert_eq(strike_control.get_button_count(), 1, "sanity check: StrikeActionControl starts with one selectable target")

	_view.configure(strike_control, null)
	_view.on_round_event({"round": 1, "outcome": "won"})

	assert_eq(strike_control.get_button_count(), 0, "StrikeActionControl must be disabled (zero selectable targets) once the result screen is shown")
	assert_eq(strike_control.get_selectable_target_ids(), [])


func test_end_turn_control_disabled_after_encounter_result_event() -> void:
	var end_turn_control = EndTurnControlScene.instantiate()
	add_child_autofree(end_turn_control)

	var session = FakeRoundSession.new({"name": "Titus", "_is_enemy": false})
	end_turn_control.configure(session)
	assert_true(end_turn_control.is_enabled(), "sanity check: EndTurnControl starts enabled for the active player combatant")

	_view.configure(null, end_turn_control)
	_view.on_round_event({"round": 1, "outcome": "lost"})

	assert_false(end_turn_control.is_enabled(), "EndTurnControl must be disabled once the result screen is shown")


func test_both_controls_disabled_together_after_encounter_result_event() -> void:
	var strike_control = StrikeActionControlScene.instantiate()
	add_child_autofree(strike_control)
	var end_turn_control = EndTurnControlScene.instantiate()
	add_child_autofree(end_turn_control)

	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))
	var rng_port   = ScriptedRandomNumberPort.new([12, 4])
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	strike_control.configure(_actor(origin), ActionEconomyClass.new(), use_case, [adjacent_enemy])

	var session = FakeRoundSession.new({"name": "Titus", "_is_enemy": false})
	end_turn_control.configure(session)

	_view.configure(strike_control, end_turn_control)
	_view.on_round_event({"round": 1, "outcome": "won"})

	assert_eq(strike_control.get_button_count(), 0)
	assert_false(end_turn_control.is_enabled())


func test_no_controls_injected_is_a_safe_noop() -> void:
	# configure() never called -- both controls remain null. Must not error.
	_view.on_round_event({"round": 1, "outcome": "won"})
	assert_true(_view.is_shown())


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: displayed outcome matches determine_outcome_use_case.classify()
# (+ build_event()) for an equivalent encounter state.
# ══════════════════════════════════════════════════════════════════════════

func test_displayed_outcome_matches_determine_outcome_use_case_for_a_won_encounter() -> void:
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var party: Array = [{"name": "Titus", "hp_current": 10}]
	var enemies: Array = [{"name": "Goblin", "hp_current": 0}]

	var outcome: String = determine_outcome_use_case.classify(party, enemies)
	assert_eq(outcome, "won", "sanity check: enemies fully defeated must classify as 'won'")

	var event = determine_outcome_use_case.build_event(2, outcome)
	_view.on_round_event(event)

	assert_eq(_view.get_result_text(), "Win", "ResultScreenView must render 'Win' for the SAME outcome determine_outcome_use_case classified")


func test_displayed_outcome_matches_determine_outcome_use_case_for_a_lost_encounter() -> void:
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var party: Array = [{"name": "Titus", "hp_current": 0}]
	var enemies: Array = [{"name": "Goblin", "hp_current": 10}]

	var outcome: String = determine_outcome_use_case.classify(party, enemies)
	assert_eq(outcome, "lost", "sanity check: party fully defeated must classify as 'lost'")

	var event = determine_outcome_use_case.build_event(2, outcome)
	_view.on_round_event(event)

	assert_eq(_view.get_result_text(), "Loss", "ResultScreenView must render 'Loss' for the SAME outcome determine_outcome_use_case classified")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: code-review assertion -- no direct use-case calls.
# ══════════════════════════════════════════════════════════════════════════

func _read_source() -> String:
	var file := FileAccess.open(RESULT_SCREEN_VIEW_PATH, FileAccess.READ)
	assert_not_null(file, "presentation/result_screen_view.gd must be readable to verify its source")
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_contains_no_direct_resolve_action_use_case_reference() -> void:
	var source: String = _read_source()
	assert_eq(
		source.findn("resolve_action_use_case"), -1,
		"result_screen_view.gd must never reference resolve_action_use_case (read-only terminal projection)"
	)


func test_source_contains_no_direct_run_round_use_case_reference() -> void:
	var source: String = _read_source()
	assert_eq(
		source.findn("run_round_use_case"), -1,
		"result_screen_view.gd must never reference run_round_use_case (read-only terminal projection)"
	)
