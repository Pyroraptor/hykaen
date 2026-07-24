extends GutTest
## tests/unit/test_exploration_controller.gd
##
## GUT test suite for FEAT-005 (US-004 / FR-002): core/application/
## exploration_controller.gd's ExplorationController use-case orchestrator
## for party movement + proximity-trigger evaluation.
##
## Verifies (this feature's test_criteria):
##   1. move_party_member() to an adjacent hex succeeds, updates
##      session.party_hex_positions, returns true.
##   2. move_party_member() to a non-adjacent hex fails closed — returns
##      false, no state mutation.
##   3. move_party_member() with unknown combatant_id fails closed —
##      returns false, no state mutation.
##   4. moving into an active trigger hex emits combat_triggered(encounter_id)
##      exactly once.
##   5. moving into a trigger hex whose entry is already in
##      completed_encounter_ids does NOT emit combat_triggered.
##   6. moving into a non-trigger hex emits no signal.
##   7. with two overlapping active trigger entries, only the first (per
##      get_active_encounter_entries() order) fires — single-fire-per-move
##      (ADR-005).
##   8. Static source-inspection check: exploration_controller.gd contains
##      no 'extends Node' / no HexGridView or presentation imports
##      (RISK-002 mitigation).

const ExplorationControllerClass = preload("res://core/application/exploration_controller.gd")
const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")
const ScenarioEncounterEntryResourceClass = preload("res://data/scenarios/scenario_encounter_entry_resource.gd")
const ProximityTriggerResourceClass = preload("res://data/triggers/proximity_trigger_resource.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const EXPLORATION_CONTROLLER_PATH: String = "res://core/application/exploration_controller.gd"


func _make_entry(encounter_id: String, trigger_hexes: Array):
	var entry = ScenarioEncounterEntryResourceClass.new()
	entry.encounter_id = encounter_id
	if trigger_hexes.size() > 0:
		var trigger = ProximityTriggerResourceClass.new()
		trigger.trigger_hexes = trigger_hexes
		entry.trigger = trigger
	return entry


func _make_scenario(entries: Array):
	var scenario = ScenarioResourceClass.new()
	scenario.scenario_id = "test_scenario"
	var typed_entries: Array[ScenarioEncounterEntryResource] = []
	for entry in entries:
		typed_entries.append(entry)
	scenario.encounter_entries = typed_entries
	return scenario


func _make_session(entries: Array, party_hex: Dictionary = {"hero": {"q": 0, "r": 0}}):
	var session = ScenarioSessionClass.new()
	session.scenario = _make_scenario(entries)
	var positions: Dictionary = {}
	for combatant_id in party_hex:
		var pos: Dictionary = party_hex[combatant_id]
		positions[combatant_id] = HexCoordClass.new(pos["q"], pos["r"])
	session.party_hex_positions = positions
	return session


# ── Criterion 1: adjacent move succeeds ─────────────────────────────────────

func test_move_party_member_to_adjacent_hex_succeeds_and_updates_position() -> void:
	var session = _make_session([])
	var controller = ExplorationControllerClass.new(session)

	var target = HexCoordClass.new(1, 0)
	var result: bool = controller.move_party_member("hero", target)

	assert_true(result, "move_party_member() to an adjacent hex must return true")
	assert_true(
		session.party_hex_positions["hero"].equals(target),
		"session.party_hex_positions['hero'] must be updated to the target hex"
	)


# ── Criterion 2: non-adjacent move fails closed ─────────────────────────────

func test_move_party_member_to_non_adjacent_hex_fails_closed() -> void:
	var session = _make_session([])
	var controller = ExplorationControllerClass.new(session)

	var original = HexCoordClass.new(0, 0)
	var target = HexCoordClass.new(5, 5)
	var result: bool = controller.move_party_member("hero", target)

	assert_false(result, "move_party_member() to a non-adjacent hex must return false")
	assert_true(
		session.party_hex_positions["hero"].equals(original),
		"a non-adjacent move must not mutate session.party_hex_positions"
	)


# ── Criterion 3: unknown combatant fails closed ─────────────────────────────

func test_move_party_member_unknown_combatant_id_fails_closed() -> void:
	var session = _make_session([])
	var controller = ExplorationControllerClass.new(session)

	var target = HexCoordClass.new(1, 0)
	var result: bool = controller.move_party_member("no_such_combatant", target)

	assert_false(result, "move_party_member() with an unknown combatant_id must return false")
	assert_false(
		session.party_hex_positions.has("no_such_combatant"),
		"an unknown combatant_id must never be added to session.party_hex_positions"
	)
	assert_true(
		session.party_hex_positions["hero"].equals(HexCoordClass.new(0, 0)),
		"an unknown combatant_id's failed move must not disturb other party members' positions"
	)


# ── Criterion 4: active trigger hex emits combat_triggered exactly once ────

func test_move_into_active_trigger_hex_emits_combat_triggered_once() -> void:
	var target = HexCoordClass.new(1, 0)
	var entry = _make_entry("prologue_fight", [{"q": 1, "r": 0}])
	var session = _make_session([entry])
	var controller = ExplorationControllerClass.new(session)

	watch_signals(controller)
	var result: bool = controller.move_party_member("hero", target)

	assert_true(result, "the move itself must still succeed")
	assert_signal_emit_count(
		controller, "combat_triggered", 1,
		"moving into an active trigger hex must emit combat_triggered exactly once"
	)
	assert_eq(
		get_signal_parameters(controller, "combat_triggered", 0)[0], "prologue_fight",
		"combat_triggered must carry the triggering entry's encounter_id"
	)


# ── Criterion 5: completed entries never (re-)fire ──────────────────────────

func test_move_into_trigger_hex_of_completed_entry_does_not_emit() -> void:
	var target = HexCoordClass.new(1, 0)
	var entry = _make_entry("prologue_fight", [{"q": 1, "r": 0}])
	var session = _make_session([entry])
	session.mark_encounter_complete("prologue_fight")
	var controller = ExplorationControllerClass.new(session)

	watch_signals(controller)
	var result: bool = controller.move_party_member("hero", target)

	assert_true(result, "the move itself must still succeed even when the trigger is already completed")
	assert_signal_emit_count(
		controller, "combat_triggered", 0,
		"a completed encounter's trigger hex must never re-emit combat_triggered"
	)


# ── Criterion 6: non-trigger hex emits nothing ──────────────────────────────

func test_move_into_non_trigger_hex_emits_no_signal() -> void:
	var target = HexCoordClass.new(1, 0)
	var entry = _make_entry("prologue_fight", [{"q": 9, "r": 9}])
	var session = _make_session([entry])
	var controller = ExplorationControllerClass.new(session)

	watch_signals(controller)
	controller.move_party_member("hero", target)

	assert_signal_emit_count(
		controller, "combat_triggered", 0,
		"moving into a hex that is not part of any active trigger must emit no signal"
	)


# ── Criterion 7: overlapping active triggers — first-match-wins (ADR-005) ──

func test_overlapping_active_triggers_only_first_fires() -> void:
	var target = HexCoordClass.new(1, 0)
	var first_entry = _make_entry("first_fight", [{"q": 1, "r": 0}])
	var second_entry = _make_entry("second_fight", [{"q": 1, "r": 0}])
	var session = _make_session([first_entry, second_entry])
	var controller = ExplorationControllerClass.new(session)

	watch_signals(controller)
	controller.move_party_member("hero", target)

	assert_signal_emit_count(
		controller, "combat_triggered", 1,
		"only ONE combat_triggered emission is allowed per move, even with overlapping active triggers"
	)
	assert_eq(
		get_signal_parameters(controller, "combat_triggered", 0)[0], "first_fight",
		"the FIRST active entry (per get_active_encounter_entries() order) must be the one that fires"
	)


# ── Criterion 8: static check — application/domain purity (RISK-002) ───────

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable to run the RISK-002 static check" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_has_no_node_or_control_inheritance() -> void:
	var content: String = _read_source(EXPLORATION_CONTROLLER_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("extends Node"), "exploration_controller.gd must not extend Node (ADR-001/RISK-002)")
	assert_false(content.contains("extends Control"), "exploration_controller.gd must not extend Control (ADR-001/RISK-002)")
	assert_false(content.contains("extends CanvasItem"), "exploration_controller.gd must not extend CanvasItem (ADR-001/RISK-002)")
	assert_true(content.contains("extends RefCounted"), "exploration_controller.gd must extend RefCounted (ADR-001/RISK-002)")


func test_source_has_no_presentation_layer_imports() -> void:
	var content: String = _read_source(EXPLORATION_CONTROLLER_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("res://presentation/"), "exploration_controller.gd must not import presentation/ (RISK-002)")
	assert_false(content.contains("preload(\"res://MainScene"), "exploration_controller.gd must not import MainScene (RISK-002)")
	assert_false(content.contains("HexGridView"), "exploration_controller.gd must not reference HexGridView (RISK-002)")


func test_source_has_no_engine_lifecycle_callbacks() -> void:
	var content: String = _read_source(EXPLORATION_CONTROLLER_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("func _ready("), "exploration_controller.gd must not define _ready() (ADR-001)")
	assert_false(content.contains("func _process("), "exploration_controller.gd must not define _process() (ADR-001)")
	assert_false(
		content.contains("func _physics_process("),
		"exploration_controller.gd must not define _physics_process() (ADR-001)"
	)
