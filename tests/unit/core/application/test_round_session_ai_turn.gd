extends GutTest
## tests/unit/core/application/test_round_session_ai_turn.gd
##
## GUT test suite for FEAT-111 (US-011): Enemy turn automation via the
## existing AI module.
##
## FEAT-110 already introduced core/application/round_session.gd's
## advance_ai_turn() (tests/unit/core/application/test_round_session.gd
## exercises it against a FAKE AIDecisionPort double). This suite instead
## proves the FEAT-111 steel-thread criterion that matters end-to-end: for
## an Enemy current_actor(), advance_ai_turn() drives the REAL, existing
## core/combat/ai.gd module (not a test double standing in for it) to pick
## an action, resolves that action via the SAME resolve_action_use_case
## pipeline the player's own Strike goes through (ADR-002 — one identical
## pipeline, no parallel AI code path), and the resulting AttackEvent flows
## through the exact same EventSinkPort broadcast every Presentation
## projection (HexGridView/StatusPanelView/EventLogView) already subscribes
## to for a player-driven Strike (mirrors
## tests/unit/presentation/test_strike_action_control.gd's criterion 3).
## Also proves presentation/turn_controller.gd's US-011 responsibility of
## disabling player input controls (StrikeActionControl, EndTurnControl)
## while it is driving an Enemy's turn.
##
## Verifies (test_criteria):
##   1. Unit: for an Enemy current_actor(), RoundSession.advance_ai_turn()
##      calls the REAL core/combat/ai.gd to select an action, resolves it
##      via resolve_action_use_case.resolve(), then advances the cursor.
##   2. Defensive fallback: an AI-selected action rejected by
##      resolve_action_use_case.resolve() is logged via event_sink_port
##      (a TurnAdvancedEvent is still emitted for the forced cursor
##      advance) and the cursor still advances — the turn loop never
##      stalls.
##   3. Integration: an AI-driven AttackEvent renders through
##      HexGridView/StatusPanelView/EventLogView via the exact same signal
##      path as a player-driven AttackEvent.
##   4. Player input controls (StrikeActionControl, EndTurnControl) are
##      disabled by the turn-driver (presentation/turn_controller.gd) while
##      an Enemy combatant is/was the current_actor() being auto-driven.

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const RoundEventsClass             = preload("res://core/rules/round_events.gd")
const AIClass                      = preload("res://core/combat/ai.gd")
const TurnControllerClass          = preload("res://presentation/turn_controller.gd")

const EndTurnControlScene: PackedScene      = preload("res://presentation/end_turn_control.tscn")
const StrikeActionControlScene: PackedScene = preload("res://presentation/strike_action_control.tscn")
const HexGridViewScene: PackedScene         = preload("res://presentation/hex_grid_view.tscn")
const StatusPanelViewScene: PackedScene     = preload("res://presentation/status_panel_view.tscn")
const EventLogViewScene: PackedScene        = preload("res://presentation/event_log_view.tscn")

const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass  = preload("res://core/geometry/hex_coord.gd")


# ── Fake/double port implementations (mirrors tests/unit/core/application/test_round_session.gd) ──

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


## BrokenAIDecisionPort — always returns an empty/invalid decision, used to
## exercise advance_ai_turn()'s CWE-835 defensive-advance fallback (criterion 2).
class BrokenAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant: Dictionary, _targets: Array) -> Dictionary:
		return {}


## ScriptedRandomNumberPort — deterministic rolls, mirrors
## tests/unit/presentation/test_strike_action_control.gd's double, used so
## criterion 3's rendered AttackEvent text/damage is exactly known (a
## guaranteed hit) rather than relying on statistical luck from a seed.
class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(_dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


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


## Builds a fully-wired, REAL RunRoundUseCase plus its fake ports, exactly
## mirroring test_round_session.gd's "no phantom-method-on-a-spy" rig, but
## parameterized so callers can inject the REAL AIDecisionPort
## (core/combat/ai.gd) or a scripted RNG.
func _make_use_case(entries: Array, ai_port, random_number_port, event_sink_port) -> Dictionary:
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var round_history_port = FakeRoundHistoryPort.new()

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, ai_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	return {
		"use_case":                run_round_use_case,
		"history":                 round_history_port,
		"resolve_action_use_case": resolve_action_use_case
	}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: for an Enemy current_actor(), advance_ai_turn() calls the
# REAL core/combat/ai.gd to select an action, resolves it via
# resolve_action_use_case.resolve(), then advances the cursor.
# ══════════════════════════════════════════════════════════════════════════

func test_advance_ai_turn_drives_the_real_ai_module_and_resolves_via_the_shared_pipeline() -> void:
	var bravo: Dictionary = _durable_combatant("Bravo", true, "bravo")
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(42)
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_eq(session.current_actor().get("name", ""), "Bravo", "the Enemy must be the current actor")
	var hp_before: int = alpha.get("hp_current", 0)

	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false))
	assert_eq(
		rig["history"].entries.size(), 1,
		"advance_ai_turn() must resolve exactly one action via resolve_action_use_case — the SAME pipeline the player's own Strike uses"
	)
	assert_eq(
		rig["history"].entries[0]["attacker"].get("name", ""), "Bravo",
		"the resolved action must belong to the AI-selected (real ai.gd) actor/target pair"
	)
	assert_true(alpha.get("hp_current", 0) <= hp_before, "the AI's resolved Strike must be able to damage its target")
	assert_eq(session.current_actor().get("name", ""), "Alpha", "advance_ai_turn() must advance the cursor to the next living, un-Spent actor")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: an AI-selected action rejected by resolve_action_use_case is
# logged via event_sink_port and the cursor still advances (no stall).
# ══════════════════════════════════════════════════════════════════════════

func test_advance_ai_turn_defensive_fallback_logs_via_event_sink_port_and_still_advances() -> void:
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(1)
	var rig: Dictionary = _make_use_case(entries, BrokenAIDecisionPort.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false), "a rejected AI decision must not stall/deadlock the session (CWE-835 guard)")
	assert_false(result.get("resolved", true), "no action was actually resolved for the broken AI decision")
	assert_eq(rig["history"].entries.size(), 0, "no action-resolution history entry may be recorded for a rejected AI decision")
	assert_eq(
		session.current_actor().get("name", ""), "Alpha",
		"the cursor must still advance past the broken AI turn so the turn loop can never stall"
	)

	var turn_events: Array = event_sink_port.events.filter(func(e): return e is RoundEventsClass.TurnAdvancedEvent)
	assert_eq(
		turn_events.size(), 1,
		"the forced cursor advance from a rejected AI decision must still be logged via event_sink_port (TurnAdvancedEvent)"
	)
	assert_eq(turn_events[0].active_combatant_name, "Alpha")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (integration): an AI-driven AttackEvent renders through
# HexGridView/StatusPanelView/EventLogView via the exact same signal path a
# player-driven AttackEvent uses (mirrors test_strike_action_control.gd's
# criterion 3, driven now by advance_ai_turn() instead of
# StrikeActionControl.select_target()).
# ══════════════════════════════════════════════════════════════════════════

func test_ai_driven_attack_event_renders_through_hex_grid_status_panel_and_event_log_views() -> void:
	var goblin: Dictionary = _durable_combatant("Goblin", true, "goblin")
	var titus: Dictionary  = _durable_combatant("Titus", false, "titus")
	var entries: Array = [_entry(goblin), _entry(titus)]

	var hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(hex_grid_view)
	var status_panel = StatusPanelViewScene.instantiate()
	add_child_autofree(status_panel)
	var event_log = EventLogViewScene.instantiate()
	add_child_autofree(event_log)

	# HexGridView renders real domain Combatant view models (combatant_id/
	# name/team/hex_coord) — a different shape from the plain Dictionaries
	# RoundSession/resolve_action_use_case operate on, exactly as the rest
	# of this codebase already separates the two (see
	# tests/unit/presentation/test_hex_grid_view_mapping.gd).
	hex_grid_view.load_combatants([
		CombatantClass.new("goblin", "Goblin", "Enemy", HexCoordClass.new(0, 0)),
		CombatantClass.new("titus", "Titus", "Player", HexCoordClass.new(1, 0)),
	])
	status_panel.load_combatants([
		{
			"combatant_id": "titus", "name": "Titus",
			"hp_current": 2000, "hp_max": 2000,
			"stamina_current": 0, "stamina_max": 0,
			"action_budget_remaining": 7, "spent": false, "conditions": [],
		},
	])

	# raw=12 -> roll_total = 12 + strength(3) + proficiency(2) = 17 vs ac=10 -> hit;
	# damage roll raw=4 -> 4 + 3 = 7 damage (mirrors test_strike_action_control.gd's
	# guaranteed-hit fixture exactly).
	var event_sink_port    = FakeEventSinkPort.new()
	event_sink_port.forward_to = [status_panel, event_log]
	var random_number_port = ScriptedRandomNumberPort.new([12, 4])
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])

	assert_eq(session.current_actor().get("name", ""), "Goblin")
	var result: Dictionary = session.advance_ai_turn()
	assert_true(result.get("ok", false))

	assert_eq(
		event_log.get_entry_count(), 1,
		"EventLogView must observe exactly one entry for the AI-resolved Strike's AttackEvent — the SAME EventSinkPort broadcast a player-driven Strike uses"
	)
	assert_string_contains(event_log.get_entry_text(0), "Goblin")
	assert_string_contains(event_log.get_entry_text(0), "Titus")

	assert_eq(
		status_panel.get_status("titus").get("hp_current"), 1993,
		"StatusPanelView must reflect the AI-resolved Strike's damage (2000 - 7 = 1993) via the same event pipeline"
	)

	# HexGridView is not itself an EventSinkPort subscriber (Strike does not
	# move a combatant), but it must remain unaffected/intact — the SAME
	# battlefield tokens the player-driven path already renders — proving
	# the AI-driven action flowed through the shared pipeline without
	# disturbing the one other UI surface subscribed to the encounter.
	assert_eq(hex_grid_view.get_token_count(), 2)
	assert_not_null(hex_grid_view.get_token("goblin"))
	assert_not_null(hex_grid_view.get_token("titus"))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: player input controls (StrikeActionControl, EndTurnControl)
# are disabled by the turn-driver (presentation/turn_controller.gd) while an
# Enemy combatant is the current_actor() being auto-driven.
# ══════════════════════════════════════════════════════════════════════════

func test_turn_controller_disables_strike_action_control_and_end_turn_control_while_driving_enemy_turn() -> void:
	var goblin: Dictionary = _durable_combatant("Goblin", true, "goblin")
	var titus: Dictionary  = _durable_combatant("Titus", false, "titus")
	var entries: Array = [_entry(goblin), _entry(titus)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(7)
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])
	assert_eq(session.current_actor().get("name", ""), "Goblin", "Goblin (Enemy) must start as the current actor")

	var end_turn_control = EndTurnControlScene.instantiate()
	add_child_autofree(end_turn_control)
	var strike_action_control = StrikeActionControlScene.instantiate()
	add_child_autofree(strike_action_control)

	# Simulate a StrikeActionControl left configured/enabled from a prior
	# state (e.g. a previous player's turn) — the turn-driver must actively
	# disable it while it is driving an Enemy turn, not merely rely on it
	# having never been configured.
	var origin := HexCoordClass.new(0, 0)
	var stale_actor: Dictionary = {
		"name": "Titus", "strength": 3, "hex_coord": origin,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 2, "damage_die": 6},
	}
	var stale_enemy: Dictionary = {"combatant_id": "stale", "name": "Stale", "hp_current": 20, "ac": 10, "hex_coord": HexCoordClass.new(1, 0)}
	strike_action_control.configure(stale_actor, ActionEconomyClass.new(), rig["resolve_action_use_case"], [stale_enemy])
	assert_eq(strike_action_control.get_button_count(), 1, "fixture assumption: StrikeActionControl starts out enabled/configured")

	var turn_controller = TurnControllerClass.new()
	add_child_autofree(turn_controller)
	turn_controller.set_session(session, end_turn_control, strike_action_control)

	assert_eq(
		strike_action_control.get_button_count(), 0,
		"TurnController must disable StrikeActionControl (no selectable targets) while driving an Enemy's turn"
	)
	assert_eq(strike_action_control.get_selectable_target_ids(), [])

	# The Goblin's single-enemy turn auto-resolves and settles on Titus
	# (the player) — EndTurnControl re-derives its own enabled state from
	# the RoundSession every time (already covered by
	# tests/unit/presentation/test_end_turn_control.gd), so it becomes
	# enabled again once the driver settles on the player; StrikeActionControl
	# has no such live-target data to re-derive from and stays disabled
	# until whichever composition-root code owns the player's turn setup
	# reconfigures it (out of this feature's scope, mirroring
	# presentation/turn_controller.gd's documented division of responsibility).
	assert_eq(session.current_actor().get("name", ""), "Titus")
	assert_true(end_turn_control.is_enabled(), "EndTurnControl must be enabled once the driver settles on the player's turn")
	assert_eq(strike_action_control.get_button_count(), 0, "StrikeActionControl must remain disabled (no leaked stale targets) after the driver settles")
