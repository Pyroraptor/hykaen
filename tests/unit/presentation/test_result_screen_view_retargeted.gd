extends GutTest
## tests/unit/presentation/test_result_screen_view_retargeted.gd — FEAT-004
## (US-004 / FR-013, iteration D "UI Consolidation + Movement UX").
##
## Retargets tests/gut/test_result_screen.gd (FEAT-010), whose subject -- the
## duplicate scenes/battlefield/ResultScreen.gd terminal projection -- was
## removed from MainScene's composition root (FEAT-001/P0-2).
## presentation/result_screen_view.gd is the ONE kept terminal projection;
## this file closes the coverage gap that suite's deletion would otherwise
## have left open, rather than re-testing what already has an equivalent
## home:
##
##   old criterion                                        | equivalent coverage
##   --------------------------------------------------------+---------------------------------------------------------
##   1. becomes visible, displays WIN/LOSS matching            | tests/unit/presentation/test_result_screen_view.gd
##      EncounterResultEvent.outcome                           (test_renders_win_for_won_outcome, etc.)
##   2. StrikeInputController/EndTurnController reject          | test_result_screen_view.gd (criterion 2) +
##      further input after the result fires, sticky across      tests/gut/test_presentation_controls_sticky_lock.gd
##      a stray reconfigure()                                    (FEAT-137/DEF-004 ports the sticky lock()/is_locked()
##                                                                guard onto StrikeActionControl/EndTurnControl exactly)
##   3. the final combatant HP/state snapshot and full           | NOT previously retargeted -- added below
##      ordered event log remain visible on/around the result
##      screen
##
## Architectural note on criterion 3: the removed scenes/battlefield/
## ResultScreen.gd was a SELF-CONTAINED terminal projection that captured its
## own final-snapshot + event-log state internally (get_final_snapshot(),
## get_event_log_entry_count(), ...). The kept stack instead satisfies the
## SAME player-facing requirement -- "the final combatant state and the full
## event log remain visible once the encounter concludes" -- architecturally,
## via presentation/status_panel_view.gd and presentation/event_log_view.gd,
## which are ALREADY-VISIBLE, ALWAYS-ON projections fed by the same
## EventSinkPort broadcast pipeline as presentation/result_screen_view.gd
## (ADR-003) and are never cleared/hidden when ResultScreenView shows its
## Win/Loss text. presentation/result_screen_view.gd therefore does not need
## (and must not duplicate, ADR-002/CR-001) its own copy of that state. This
## file proves the ARCHITECTURAL claim directly: after ResultScreenView
## processes the terminal EncounterResultEvent, StatusPanelView still
## reflects the encounter's final combatant state and EventLogView still
## holds the complete, correctly ordered event log -- the same event stream,
## the same views, undisturbed by the result screen appearing.

const ResultScreenViewScene: PackedScene = preload("res://presentation/result_screen_view.tscn")
const StatusPanelViewScene: PackedScene = preload("res://presentation/status_panel_view.tscn")
const EventLogViewScene: PackedScene = preload("res://presentation/event_log_view.tscn")

const RoundEventsClass = preload("res://core/rules/round_events.gd")


## FakeEventSinkPort — mirrors MainScene.gd's ConsoleEventSinkAdapter's
## `forward_to` fan-out contract (an Array of Presentation nodes each
## exposing on_round_event(event)), the SAME broadcast shape every
## Presentation projection subscribes to (ADR-003).
class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []
	var forward_to: Array = []

	func emit(event) -> void:
		events.append(event)
		for target in forward_to:
			if target != null:
				target.on_round_event(event)


var _result_screen_view = null
var _status_panel = null
var _event_log = null
var _event_sink: FakeEventSinkPort = null


func before_each() -> void:
	_result_screen_view = ResultScreenViewScene.instantiate()
	add_child_autofree(_result_screen_view)
	_status_panel = StatusPanelViewScene.instantiate()
	add_child_autofree(_status_panel)
	_event_log = EventLogViewScene.instantiate()
	add_child_autofree(_event_log)

	_event_sink = FakeEventSinkPort.new()
	_event_sink.forward_to = [_status_panel, _event_log, _result_screen_view]

	_status_panel.load_combatants([
		{
			"combatant_id": "titus", "name": "Titus",
			"hp_current": 15, "hp_max": 20,
			"stamina_current": 4, "stamina_max": 4,
			"action_budget_remaining": 6, "spent": true, "conditions": [],
		},
		{
			"combatant_id": "skeleton", "name": "Skeleton",
			"hp_current": 12, "hp_max": 12,
			"stamina_current": 0, "stamina_max": 0,
			"action_budget_remaining": 7, "spent": false, "conditions": [],
		},
	])


# ══════════════════════════════════════════════════════════════════════════
# Retarget of Criterion 3 (test_result_screen.gd): the final combatant
# HP/state snapshot remains visible once the encounter concludes --
# StatusPanelView, not ResultScreenView, is the surface that shows it, and it
# is undisturbed by the terminal EncounterResultEvent.
# ══════════════════════════════════════════════════════════════════════════

func test_final_combatant_snapshot_is_visible_on_status_panel_view_after_result_screen_shows() -> void:
	var attack_event = RoundEventsClass.AttackBroadcast.new(2, "Titus", "Skeleton", 17, "ac", 10, true, false, 12)
	var defeated_event = RoundEventsClass.CombatantDefeatedEvent.new(2, "Skeleton", "Titus")
	var result_event = RoundEventsClass.EncounterResultEvent.new(2, "won")

	_event_sink.emit(attack_event)
	_event_sink.emit(defeated_event)
	_event_sink.emit(result_event)

	assert_true(_result_screen_view.is_shown(), "sanity check: the result screen must have processed the terminal event")
	assert_eq(_result_screen_view.get_result_text(), "Win")

	# StatusPanelView reflects the final combatant state -- Skeleton's HP
	# reduced by Titus's killing Strike -- exactly as the old ResultScreen's
	# get_final_snapshot() would have captured, but visible on the
	# ALWAYS-ON status projection instead.
	assert_eq(
		_status_panel.get_status("skeleton").get("hp_current"), 0,
		"StatusPanelView must still reflect the final resolved HP for Skeleton after the result screen shows"
	)
	assert_eq(
		_status_panel.get_status("titus").get("hp_current"), 15,
		"StatusPanelView must still reflect Titus's (unchanged) HP after the result screen shows"
	)
	assert_eq(_status_panel.get_row_count(), 2, "StatusPanelView must not be cleared/hidden by the result screen showing")


# ══════════════════════════════════════════════════════════════════════════
# Retarget of Criterion 3 (test_result_screen.gd): the full, ordered event
# log remains visible once the encounter concludes -- EventLogView, not
# ResultScreenView, is the surface that shows it.
# ══════════════════════════════════════════════════════════════════════════

func test_full_ordered_event_log_is_visible_on_event_log_view_after_result_screen_shows() -> void:
	var attack_event = RoundEventsClass.AttackBroadcast.new(1, "Titus", "Skeleton", 17, "ac", 10, true, false, 12)
	var defeated_event = RoundEventsClass.CombatantDefeatedEvent.new(1, "Skeleton", "Titus")
	var result_event = RoundEventsClass.EncounterResultEvent.new(1, "won")

	_event_sink.emit(attack_event)
	_event_sink.emit(defeated_event)
	_event_sink.emit(result_event)

	assert_true(_result_screen_view.is_shown())

	assert_eq(
		_event_log.get_entry_count(), 3,
		"EventLogView must hold every recognized round event -- AttackEvent, CombatantDefeatedEvent, EncounterResultEvent -- after the result screen shows"
	)
	assert_string_contains(_event_log.get_entry_text(0), "Titus")
	assert_string_contains(_event_log.get_entry_text(0), "Skeleton")
	assert_string_contains(_event_log.get_entry_text(1).to_lower(), "defeated")
	assert_string_contains(_event_log.get_entry_text(2).to_lower(), "won")

	# Dispatch order is preserved -- the log is never re-sorted/cleared by the
	# terminal event.
	var sequence_numbers: Array = _event_log.get_sequence_numbers()
	assert_true(sequence_numbers[0] < sequence_numbers[1])
	assert_true(sequence_numbers[1] < sequence_numbers[2])


# ══════════════════════════════════════════════════════════════════════════
# The result screen showing has no coupling to / side effect on either
# always-on projection beyond the shared event stream both already consume
# (mirrors test_result_screen.gd's "no controllers injected is a safe noop").
# ══════════════════════════════════════════════════════════════════════════

func test_result_screen_view_shown_state_does_not_clear_or_mutate_status_panel_or_event_log() -> void:
	_event_sink.emit(RoundEventsClass.EncounterResultEvent.new(1, "lost"))

	assert_true(_result_screen_view.is_shown())
	assert_eq(_result_screen_view.get_result_text(), "Loss")
	assert_eq(_status_panel.get_row_count(), 2, "ResultScreenView showing must never clear StatusPanelView's rows")
	assert_eq(_event_log.get_entry_count(), 1, "the EncounterResultEvent itself is the only entry -- ResultScreenView must never append/mutate EventLogView directly")
