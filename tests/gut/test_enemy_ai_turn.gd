extends GutTest
## tests/gut/test_enemy_ai_turn.gd — FEAT-009 (US-009 / FR-009)
##
## GUT test suite proving the steel thread's "watches the existing AI resolve
## enemy turns" step: enemy turns are driven through the IDENTICAL
## resolve_action_use_case / run_round_use_case pipeline the player's own
## Strike goes through (ADR-002/ADR-003), using the REAL core/combat/ai.gd
## module — no bespoke enemy-only code path — and the resulting round events
## surface on every Presentation projection a person running the project
## actually sees: scenes/battlefield/HexBattlefield.gd's per-combatant
## CombatantReadout children, its nested TurnOrderWidget
## (scenes/battlefield/TurnOrderWidget.gd), and
## presentation/event_log_view.gd's EventLogView.
##
## Verifies (test_criteria):
##   1. When the active combatant is on the ENEMY team, ai.gd selects and
##      executes an action via resolve_action_use_case (not a bespoke code
##      path) — proven by driving core/application/round_session.gd's
##      advance_ai_turn() with the REAL AI class and asserting the resolved
##      action lands in round_history_port, the ONE audit trail
##      resolve_action_use_case itself appends to.
##   2. Enemy movement/attacks are reflected in HexBattlefield readouts and
##      TurnOrderWidget — both subscribed to the SAME EventSinkPort broadcast
##      every other Presentation projection uses (ADR-003).
##   3. Enemy actions appear in EventLogView output in correct chronological
##      (append) order.
##   4. Control correctly returns to the next player turn (or triggers
##      outcome evaluation) once all enemy turns resolve.

const HexBattlefieldScene: PackedScene = preload("res://scenes/battlefield/HexBattlefield.tscn")
const EventLogViewScene: PackedScene   = preload("res://presentation/event_log_view.tscn")

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const RoundEventsClass             = preload("res://core/rules/round_events.gd")
const AIClass                      = preload("res://core/combat/ai.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")


# ── Fake/double port implementations (mirrors test_round_session_ai_turn.gd) ──

class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


## FakeEventSinkPort — mirrors MainScene.gd's ConsoleEventSinkAdapter's
## `forward_to` fan-out contract (an Array of Presentation nodes each
## exposing on_round_event(event)) without the console-printing side effect,
## so this suite exercises the SAME broadcast shape every Presentation
## projection already subscribes to (ADR-003) — no parallel event bus.
class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []
	var forward_to: Array = []

	func emit(event) -> void:
		events.append(event)
		for target in forward_to:
			if target != null:
				target.on_round_event(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


## ScriptedRandomNumberPort — deterministic rolls (mirrors
## tests/unit/core/application/test_round_session_ai_turn.gd's double) so
## every AI-driven Strike this suite resolves is a guaranteed, exactly-known
## hit rather than relying on statistical luck from a seed.
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

## _durable_combatant() builds the plain Dictionary shape
## resolve_action_use_case.gd/round_session.gd operate on -- deliberately
## carrying NO "hex_coord" key, so the melee reach precondition stays a no-op
## (mirrors test_round_session_ai_turn.gd's fixture exactly; HexBattlefield's
## OWN positional data comes from separate domain Combatant instances built
## below, matched by combatant_id -- the same two-shapes-joined-by-id
## separation MainScene.gd itself already relies on).
func _combatant(p_name: String, p_is_enemy: bool, p_combatant_id: String, p_hp: int = 2000) -> Dictionary:
	return {
		"name":         p_name,
		"combatant_id": p_combatant_id,
		"hp_current":   p_hp,
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


func _view_model(combatant: Dictionary) -> Dictionary:
	return {
		"combatant_id":            combatant.get("combatant_id", ""),
		"name":                    combatant.get("name", ""),
		"hp_current":              combatant.get("hp_current", 0),
		"hp_max":                  2000,
		"stamina_current":         0,
		"stamina_max":             0,
		"action_budget_remaining": 1,
		"spent":                   false,
		"conditions":              [],
	}


## Builds a fully-wired, REAL RunRoundUseCase (+ its fake ports) exactly
## mirroring test_round_session_ai_turn.gd's "no phantom-method-on-a-spy" rig,
## always driven by the REAL core/combat/ai.gd module (never a stand-in).
func _make_use_case(entries: Array, random_number_port, event_sink_port) -> Dictionary:
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var round_history_port = FakeRoundHistoryPort.new()

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, AIClass.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	return {"use_case": run_round_use_case, "history": round_history_port}


## Instantiates HexBattlefield + its nested TurnOrderWidget + a standalone
## EventLogView and wires them all as `forward_to` subscribers of an
## EventSinkPort double, mirroring MainScene.gd's own
## _presentation_event_subscribers() fan-out list (ADR-003) — the exact set
## of Presentation surfaces a person running the project actually watches
## update live as an enemy turn resolves.
func _build_presentation_rig() -> Dictionary:
	var hex_battlefield = HexBattlefieldScene.instantiate()
	add_child_autofree(hex_battlefield)
	var turn_order_widget = hex_battlefield.get_turn_order_widget()
	var event_log_view = EventLogViewScene.instantiate()
	add_child_autofree(event_log_view)

	return {
		"hex_battlefield":   hex_battlefield,
		"turn_order_widget": turn_order_widget,
		"event_log_view":    event_log_view,
	}


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1, 2, 3, 4: two consecutive Enemy turns resolve through the REAL
# ai.gd + resolve_action_use_case pipeline, render on HexBattlefield/
# TurnOrderWidget/EventLogView in chronological order, and control returns to
# the next Player turn once both Enemy turns resolve.
# ══════════════════════════════════════════════════════════════════════════

func test_consecutive_enemy_turns_drive_real_ai_render_on_widgets_and_return_control_to_player() -> void:
	var goblin: Dictionary   = _combatant("Goblin", true, "goblin")
	var skeleton: Dictionary = _combatant("Skeleton", true, "skeleton")
	var titus: Dictionary    = _combatant("Titus", false, "titus")
	var entries: Array = [_entry(goblin), _entry(skeleton), _entry(titus)]

	var rig := _build_presentation_rig()
	var hex_battlefield = rig["hex_battlefield"]
	var turn_order_widget = rig["turn_order_widget"]
	var event_log_view = rig["event_log_view"]

	hex_battlefield.load_combatants(
		[
			CombatantClass.new("goblin", "Goblin", "Enemy", HexCoordClass.new(0, 0)),
			CombatantClass.new("skeleton", "Skeleton", "Enemy", HexCoordClass.new(1, 0)),
			CombatantClass.new("titus", "Titus", "Player", HexCoordClass.new(2, 0)),
		],
		[_view_model(goblin), _view_model(skeleton), _view_model(titus)]
	)
	turn_order_widget.load_combatants([
		{"combatant_id": "goblin",   "name": "Goblin",   "initiative_order": 20},
		{"combatant_id": "skeleton", "name": "Skeleton",  "initiative_order": 15},
		{"combatant_id": "titus",    "name": "Titus",     "initiative_order": 5},
	])

	var event_sink_port = FakeEventSinkPort.new()
	event_sink_port.forward_to = [hex_battlefield, turn_order_widget, event_log_view]

	# Each attack: raw=12 -> roll_total = 12 + strength(3) + proficiency(2) = 17
	# vs ac=10 -> hit (not a crit, margin 7 < 10); damage raw=4 -> 4 + 3 = 7.
	var random_number_port = ScriptedRandomNumberPort.new([12, 4, 12, 4])
	var rig_use_case: Dictionary = _make_use_case(entries, random_number_port, event_sink_port)
	var session = rig_use_case["use_case"].begin_round(1, [titus], [goblin, skeleton])

	assert_eq(session.current_actor().get("name", ""), "Goblin", "the first Enemy in initiative must be the current actor")
	assert_true(turn_order_widget.is_active("goblin"), "TurnOrderWidget must start with the first Enemy flagged active")

	# ── Drive every consecutive Enemy turn exactly the way
	# presentation/turn_controller.gd's auto-driver does (US-011) — while
	# the current actor is on the Enemy team, resolve via advance_ai_turn().
	# Bounded by entries.size() (a plain `for`, never a `while`) so a defect
	# that fails to advance the cursor away from an Enemy actor can never
	# hang this test indefinitely — the assertions below still catch it. ──
	var enemy_turns_driven: int = 0
	for _i in range(entries.size()):
		if not session.current_actor().get("_is_enemy", false):
			break
		var result: Dictionary = session.advance_ai_turn()
		assert_true(result.get("ok", false), "advance_ai_turn() must resolve every Enemy turn without stalling")
		enemy_turns_driven += 1
	assert_eq(enemy_turns_driven, 2, "both Goblin's and Skeleton's Enemy turns must have been driven")

	# ── Criterion 1: ai.gd selected and executed BOTH actions via the SAME
	# resolve_action_use_case pipeline (the one audit trail it appends to) —
	# never a bespoke enemy-only code path. ──
	assert_eq(rig_use_case["history"].entries.size(), 2, "both Enemy turns must resolve via resolve_action_use_case's own round history")
	assert_eq(rig_use_case["history"].entries[0]["attacker"].get("name", ""), "Goblin")
	assert_eq(rig_use_case["history"].entries[1]["attacker"].get("name", ""), "Skeleton")
	assert_eq(titus.get("hp_current", 0), 2000 - 7 - 7, "Titus must take damage from both AI-resolved Strikes")

	# ── Criterion 2: HexBattlefield's Titus readout and TurnOrderWidget both
	# reflect the resolved Enemy turns via the SAME EventSinkPort broadcast. ──
	assert_eq(
		hex_battlefield.get_readout("titus").get_status().get("hp_current"), 1986,
		"HexBattlefield's Titus readout must reflect both AI-resolved Strikes' damage"
	)
	assert_true(turn_order_widget.is_active("titus"), "TurnOrderWidget must flag Titus active once both Enemy turns resolve")
	assert_false(turn_order_widget.is_active("goblin"), "TurnOrderWidget must no longer flag Goblin active")
	assert_false(turn_order_widget.is_active("skeleton"), "TurnOrderWidget must no longer flag Skeleton active")

	# ── Criterion 3: EventLogView shows both Enemy actions, in chronological
	# (append) order — Goblin's Strike BEFORE Skeleton's. ──
	assert_eq(event_log_view.get_entry_count(), 2, "EventLogView must show exactly one entry per resolved Enemy Strike")
	assert_string_contains(event_log_view.get_entry_text(0), "Goblin")
	assert_string_contains(event_log_view.get_entry_text(0), "Titus")
	assert_string_contains(event_log_view.get_entry_text(1), "Skeleton")
	assert_string_contains(event_log_view.get_entry_text(1), "Titus")
	assert_true(
		event_log_view.get_sequence_numbers()[0] < event_log_view.get_sequence_numbers()[1],
		"Goblin's entry must be sequenced strictly before Skeleton's"
	)

	# ── Criterion 4: control returns to the next Player turn once every
	# consecutive Enemy turn has resolved. ──
	assert_eq(session.current_actor().get("name", ""), "Titus", "control must return to the Player once both Enemy turns resolve")
	assert_false(session.is_round_over(), "the round must remain open with the Player still due to act")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (alternate branch): when an Enemy's AI-resolved Strike decides
# the encounter outright, outcome evaluation fires INSTEAD of control
# returning to a next Player turn — the round ends via the SAME
# EncounterResultEvent broadcast every projection observes.
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_turn_that_decides_the_encounter_triggers_outcome_evaluation_instead_of_next_player_turn() -> void:
	var goblin: Dictionary = _combatant("Goblin", true, "goblin")
	var titus: Dictionary  = _combatant("Titus", false, "titus", 5)  # one guaranteed-hit Strike (7 dmg) defeats Titus
	var entries: Array = [_entry(goblin), _entry(titus)]

	var rig := _build_presentation_rig()
	var hex_battlefield = rig["hex_battlefield"]
	var turn_order_widget = rig["turn_order_widget"]
	var event_log_view = rig["event_log_view"]

	hex_battlefield.load_combatants(
		[
			CombatantClass.new("goblin", "Goblin", "Enemy", HexCoordClass.new(0, 0)),
			CombatantClass.new("titus", "Titus", "Player", HexCoordClass.new(1, 0)),
		],
		[_view_model(goblin), _view_model(titus)]
	)
	turn_order_widget.load_combatants([
		{"combatant_id": "goblin", "name": "Goblin", "initiative_order": 20},
		{"combatant_id": "titus",  "name": "Titus",  "initiative_order": 5},
	])

	var event_sink_port = FakeEventSinkPort.new()
	event_sink_port.forward_to = [hex_battlefield, turn_order_widget, event_log_view]

	var random_number_port = ScriptedRandomNumberPort.new([12, 4])
	var rig_use_case: Dictionary = _make_use_case(entries, random_number_port, event_sink_port)
	var session = rig_use_case["use_case"].begin_round(1, [titus], [goblin])

	assert_eq(session.current_actor().get("name", ""), "Goblin")
	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false))
	assert_true(result.get("round_over", false), "a decisive AI-resolved Strike must end the round instead of advancing to a next actor")
	assert_eq(result.get("outcome", ""), "lost")

	assert_true(session.is_round_over(), "the round must be over once outcome evaluation decides the encounter")
	assert_eq(session.current_actor(), {}, "no next Player turn is due once the encounter's outcome is decided")

	var result_events: Array = event_sink_port.events.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(result_events.size(), 1, "exactly one EncounterResultEvent must be emitted via the SAME EventSinkPort broadcast")
	assert_eq(result_events[0].outcome, "lost")

	assert_eq(
		hex_battlefield.get_readout("titus").get_status().get("hp_current"), 0,
		"HexBattlefield's Titus readout must reflect the defeat even though the round ended without a next-actor TurnAdvancedEvent"
	)
	assert_true(
		hex_battlefield.get_readout("titus").get_status().get("conditions").has("Defeated"),
		"HexBattlefield's Titus readout must show the Defeated condition from the CombatantDefeatedEvent"
	)

	assert_eq(
		event_log_view.get_entry_count(), 3,
		"EventLogView must show the AttackEvent, CombatantDefeatedEvent, and EncounterResultEvent, in that order"
	)
	assert_string_contains(event_log_view.get_entry_text(0), "Goblin")
	assert_string_contains(event_log_view.get_entry_text(1), "defeated")
	assert_string_contains(event_log_view.get_entry_text(2), "concluded")
