extends GutTest
## tests/unit/presentation/test_end_turn_control.gd
##
## GUT test suite for FEAT-110 (US-010): EndTurnControl
## (presentation/end_turn_control.gd) is always available for the active
## PLAYER combatant -- whether or not an action was spent this turn -- and
## forwards directly to the injected RoundSession's end_current_turn()
## (core/application/round_session.gd, ADR-007). Also covers
## presentation/turn_controller.gd, the thin presentation-layer turn driver
## that auto-resolves Enemy turns via RoundSession.advance_ai_turn() and
## keeps EndTurnControl's enabled state in sync.
##
## Verifies:
##   1. EndTurnControl is enabled for the active player combatant both when
##      an action has been spent this turn and when it has not (US-010).
##   2. EndTurnControl is disabled while it is an Enemy's turn, once the
##      round is over, and before any RoundSession is configured.
##   3. press() forwards to RoundSession.end_current_turn() and emits
##      turn_ended with that call's result.
##   4. TurnController auto-drives a leading Enemy turn via
##      RoundSession.advance_ai_turn() and enables EndTurnControl once a
##      player's turn comes up.
##   5. Integration (against the REAL RunRoundUseCase, no spy): pressing
##      end-turn drives RoundSession.end_current_turn(), emits a
##      TurnAdvancedEvent, and InitiativeView's active highlight advances
##      accordingly. This test wires the REAL RunRoundUseCase so a
##      phantom-method regression (e.g. begin_round()/end_current_turn()
##      silently missing) cannot pass on a spy alone.

const EndTurnControlScene: PackedScene = preload("res://presentation/end_turn_control.tscn")
const InitiativeViewScene: PackedScene = preload("res://presentation/initiative_view.tscn")

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const TurnControllerClass          = preload("res://presentation/turn_controller.gd")


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
	var forward_to: Array = []  # Array of Nodes exposing on_round_event(event)

	func emit(event) -> void:
		events.append(event)
		for target in forward_to:
			target.on_round_event(event)


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


# ── Shared fixture helpers ─────────────────────────────────────────────────

func _durable_combatant(p_name: String, p_is_enemy: bool, p_combatant_id: String = "") -> Dictionary:
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


## Builds a REAL RunRoundUseCase (per FEAT-110's explicit "no
## phantom-method-on-a-spy" requirement) and returns an already-begun
## RoundSession plus its fake ports.
func _make_session(entries: Array, party: Array, enemies: Array, seed: int) -> Dictionary:
	var turn_order_port     = FakeTurnOrderPort.new(entries)
	var event_sink_port     = FakeEventSinkPort.new()
	var round_history_port  = FakeRoundHistoryPort.new()
	var random_number_port  = SeededRandomAdapterClass.new(seed)

	var resolve_action_use_case    = ResolveActionUseCaseClass.new(random_number_port, event_sink_port, round_history_port)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, FakeAIDecisionPort.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	var session = run_round_use_case.begin_round(1, party, enemies)
	return {
		"session":                 session,
		"event_sink":              event_sink_port,
		"resolve_action_use_case": resolve_action_use_case
	}


var _control = null


func before_each() -> void:
	_control = EndTurnControlScene.instantiate()
	add_child_autofree(_control)


# ══════════════════════════════════════════════════════════════════════════
# Criterion: EndTurnControl is enabled for the active player combatant both
# when an action has been spent and when it has not.
# ══════════════════════════════════════════════════════════════════════════

func test_enabled_for_active_player_combatant_when_no_action_spent() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_session(entries, [alpha], [bravo], 1)
	_control.configure(rig["session"])

	assert_true(_control.is_enabled(), "EndTurnControl must be enabled for the active player combatant even with no action spent")


func test_enabled_for_active_player_combatant_after_an_action_was_spent() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_session(entries, [alpha], [bravo], 1)
	rig["resolve_action_use_case"].resolve(alpha, entries[0]["action_economy"], bravo, "Strike", 1, 0)

	_control.configure(rig["session"])

	assert_true(_control.is_enabled(), "EndTurnControl must remain enabled after an action was spent this turn")


func test_disabled_when_current_actor_is_enemy() -> void:
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_session(entries, [alpha], [bravo], 1)
	_control.configure(rig["session"])

	assert_false(_control.is_enabled(), "EndTurnControl must be disabled while it is an Enemy's turn")


func test_disabled_when_no_session_configured() -> void:
	assert_false(_control.is_enabled(), "EndTurnControl must be disabled before any RoundSession is configured")


func test_disabled_once_round_is_over() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var entries: Array = [_entry(alpha)]

	var rig: Dictionary = _make_session(entries, [alpha], [], 1)
	for i in range(ActionEconomyClass.MAX_BUDGET):
		entries[0]["action_economy"].spend_action({"name": "Strike", "traits": []})
	rig["session"].end_current_turn()
	assert_true(rig["session"].is_round_over())

	_control.configure(rig["session"])
	assert_false(_control.is_enabled(), "EndTurnControl must be disabled once the round is over")


# ══════════════════════════════════════════════════════════════════════════
# press() forwards to RoundSession.end_current_turn() and emits turn_ended.
# ══════════════════════════════════════════════════════════════════════════

func test_press_forwards_to_end_current_turn_and_emits_turn_ended() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_session(entries, [alpha], [bravo], 1)
	_control.configure(rig["session"])

	watch_signals(_control)
	var result: Dictionary = _control.press()

	assert_true(result.get("ok", false))
	assert_eq(rig["session"].current_actor().get("name", ""), "Bravo")
	assert_signal_emitted(_control, "turn_ended")


func test_press_without_a_configured_session_is_a_no_op() -> void:
	var result: Dictionary = _control.press()
	assert_false(result.get("ok", true))


# ══════════════════════════════════════════════════════════════════════════
# TurnController: auto-drives a leading Enemy turn and enables
# EndTurnControl once a player's turn comes up.
# ══════════════════════════════════════════════════════════════════════════

func test_turn_controller_auto_drives_leading_enemy_turn_via_advance_ai_turn() -> void:
	var goblin: Dictionary = _durable_combatant("Goblin", true, "goblin")
	var titus: Dictionary  = _durable_combatant("Titus", false, "titus")
	var entries: Array = [_entry(goblin), _entry(titus)]

	var rig: Dictionary = _make_session(entries, [titus], [goblin], 3)
	assert_eq(rig["session"].current_actor().get("name", ""), "Goblin")

	var turn_controller = TurnControllerClass.new()
	add_child_autofree(turn_controller)
	turn_controller.set_session(rig["session"], _control)

	assert_eq(
		rig["session"].current_actor().get("name", ""), "Titus",
		"TurnController must auto-drive the leading Enemy turn via advance_ai_turn(), leaving Titus as the active actor"
	)
	assert_true(_control.is_enabled(), "EndTurnControl must be enabled once TurnController settles on the player's turn")


# ══════════════════════════════════════════════════════════════════════════
# Integration (REAL RunRoundUseCase, no spy): pressing end-turn drives
# RoundSession.end_current_turn(), emits TurnAdvancedEvent, and
# InitiativeView's active highlight advances accordingly.
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_end_turn_drives_real_session_and_advances_initiative_view_highlight() -> void:
	var titus: Dictionary    = _durable_combatant("Titus", false, "titus")
	var marigold: Dictionary = _durable_combatant("Marigold", false, "marigold")
	var goblin: Dictionary   = _durable_combatant("Goblin", true, "goblin")
	var entries: Array = [_entry(titus), _entry(marigold), _entry(goblin)]

	var rig: Dictionary = _make_session(entries, [titus, marigold], [goblin], 11)

	var initiative_view = InitiativeViewScene.instantiate()
	add_child_autofree(initiative_view)
	initiative_view.load_combatants([
		{"combatant_id": "titus",    "name": "Titus",    "initiative_order": 3},
		{"combatant_id": "marigold", "name": "Marigold", "initiative_order": 2},
		{"combatant_id": "goblin",  "name": "Goblin",   "initiative_order": 1},
	])
	rig["event_sink"].forward_to = [initiative_view]

	var turn_controller = TurnControllerClass.new()
	add_child_autofree(turn_controller)
	turn_controller.set_session(rig["session"], _control)

	assert_eq(initiative_view.get_active_combatant_id(), "titus", "InitiativeView must start highlighting Titus (the first actor)")
	assert_true(_control.is_enabled(), "EndTurnControl must be enabled for Titus's turn")

	var press_result: Dictionary = _control.press()

	assert_true(press_result.get("ok", false))
	assert_eq(rig["session"].current_actor().get("name", ""), "Marigold", "RoundSession.end_current_turn() must advance to Marigold")
	assert_eq(
		initiative_view.get_active_combatant_id(), "marigold",
		"pressing end-turn must drive RoundSession.end_current_turn(), whose TurnAdvancedEvent must advance InitiativeView's highlight to Marigold"
	)
	assert_true(initiative_view.is_active("marigold"))
	assert_false(initiative_view.is_active("titus"))
