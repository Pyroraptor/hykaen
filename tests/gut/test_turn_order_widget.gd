extends GutTest
## tests/gut/test_turn_order_widget.gd — FEAT-006 (US-006 / FR-005)
##
## GUT test suite for scenes/battlefield/TurnOrderWidget.gd — the turn-order
## list rendered alongside scenes/battlefield/HexBattlefield.gd, completing
## the steel thread's "turn order" surface.
##
## Verifies (test_criteria):
##   1. Rendered order matches InitiativeOrder derived from
##      Combatant.initiative_score descending (realized here via each view
##      model's `initiative_order` field, the same convention already used
##      by MainScene.gd/presentation/initiative_view.gd).
##   2. The active combatant entry is visually flagged and updates after
##      run_round_use_case (core/application/run_round_use_case.gd) advances
##      initiative — exercised against the REAL RunRoundUseCase/RoundSession
##      (not a spy standing in for them), mirroring
##      tests/unit/core/application/test_round_session.gd's isolation
##      strategy: only TurnOrderPort/EventSinkPort/RoundHistoryPort/
##      AIDecisionPort are fakes.
##   3. The widget renders correctly across multiple simulated rounds without
##      duplicate or stale entries.

const TurnOrderWidgetScene: PackedScene = preload("res://scenes/battlefield/TurnOrderWidget.tscn")

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const RoundEventsClass             = preload("res://core/rules/round_events.gd")

const TURN_ORDER_WIDGET_SOURCE_PATH: String = "res://scenes/battlefield/TurnOrderWidget.gd"


# ── Fake/double port implementations (mirrors test_round_session.gd) ───────

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


var _widget = null


func before_each() -> void:
	_widget = TurnOrderWidgetScene.instantiate()
	add_child_autofree(_widget)


func _sample_view_models() -> Array:
	# Deliberately NOT pre-sorted — load_combatants() must sort by
	# initiative_order (descending) itself.
	return [
		{"combatant_id": "enemy_0", "name": "Skeleton", "initiative_order": 9},
		{"combatant_id": "player_0", "name": "Titus", "initiative_order": 17},
		{"combatant_id": "player_1", "name": "Marigold", "initiative_order": 12},
	]


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: rendered order matches InitiativeOrder derived from
# Combatant.initiative_score descending.
# ══════════════════════════════════════════════════════════════════════════

func test_load_combatants_creates_one_row_per_combatant() -> void:
	_widget.load_combatants(_sample_view_models())
	assert_eq(_widget.get_row_count(), 3, "TurnOrderWidget must have one row per loaded combatant")


func test_load_combatants_orders_descending_by_initiative_score() -> void:
	_widget.load_combatants(_sample_view_models())
	assert_eq(
		_widget.get_ordered_combatant_ids(),
		["player_0", "player_1", "enemy_0"],
		"turn order must be descending by initiative score (17, 12, 9)"
	)


func test_entry_reflects_name_and_initiative_score() -> void:
	_widget.load_combatants(_sample_view_models())
	var entry: Dictionary = _widget.get_entry("player_0")
	assert_eq(entry.get("name"), "Titus")
	assert_eq(entry.get("initiative_order"), 17)


func test_row_text_displays_name_and_position() -> void:
	_widget.load_combatants(_sample_view_models())
	var text: String = _widget.get_row_text("player_1")
	assert_string_contains(text, "Marigold", "row text must show the combatant's name")
	assert_string_contains(text, "2.", "row text must show Marigold's position (2nd) in turn order")


func test_unknown_combatant_id_returns_empty_entry() -> void:
	_widget.load_combatants(_sample_view_models())
	assert_eq(_widget.get_entry("does_not_exist"), {})


func test_first_entry_in_turn_order_is_active_by_default_after_load() -> void:
	_widget.load_combatants(_sample_view_models())
	assert_eq(
		_widget.get_active_combatant_id(), "player_0",
		"the first combatant in initiative order must be active immediately after load"
	)
	assert_true(_widget.is_active("player_0"))
	assert_false(_widget.is_active("player_1"))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: the active combatant entry is visually flagged and updates
# after run_round_use_case advances initiative (real RunRoundUseCase/
# RoundSession — only the ports are fakes).
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


func test_active_entry_updates_after_run_round_use_case_advances_initiative() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var bravo: Dictionary = _durable_combatant("Bravo", true, "bravo")
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var event_sink := FakeEventSinkPort.new()
	event_sink.forward_to = _widget

	_widget.load_combatants([
		{"combatant_id": "alpha", "name": "Alpha", "initiative_order": 20},
		{"combatant_id": "bravo", "name": "Bravo", "initiative_order": 5},
	])
	assert_true(_widget.is_active("alpha"), "Alpha (higher initiative) must be active before any turn advances")

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1, event_sink)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])
	assert_eq(session.current_actor().get("name", ""), "Alpha")

	session.end_current_turn()  # run_round_use_case's RoundSession advances initiative: Alpha -> Bravo

	assert_eq(session.current_actor().get("name", ""), "Bravo")
	assert_true(
		_widget.is_active("bravo"),
		"TurnOrderWidget must flag Bravo active once RoundSession's cursor advances to it"
	)
	assert_false(_widget.is_active("alpha"), "Alpha must no longer be flagged active once the turn advances")
	assert_string_contains(_widget.get_row_text("bravo"), "->", "the active row's text must carry a visual marker")
	assert_true(_widget.get_row_text("alpha").find("->") == -1, "a non-active row must not carry the active marker")


func test_turn_advanced_event_for_unknown_combatant_is_a_silent_noop() -> void:
	_widget.load_combatants(_sample_view_models())
	_widget.on_turn_advanced_event({"active_combatant_id": "does_not_exist"})
	assert_eq(
		_widget.get_active_combatant_id(), "player_0",
		"an event for an unknown combatant must leave the current highlight unchanged"
	)


func test_on_round_event_with_production_turn_advanced_event_value_object() -> void:
	# Exercises the ACTUAL core/rules/round_events.gd shape, not only the
	# Dictionary test double above.
	_widget.load_combatants(_sample_view_models())

	var event = RoundEventsClass.TurnAdvancedEvent.new(1, "Marigold", "player_1")
	_widget.on_round_event(event)

	assert_true(
		_widget.is_active("player_1"),
		"a real RoundEvents.TurnAdvancedEvent must move the highlight to Marigold"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: renders correctly across multiple simulated rounds without
# duplicate or stale entries.
# ══════════════════════════════════════════════════════════════════════════

func test_reload_for_a_subsequent_round_does_not_leak_duplicate_rows() -> void:
	_widget.load_combatants(_sample_view_models())
	_widget.load_combatants(_sample_view_models())  # simulates round 2 reload
	assert_eq(_widget.get_row_count(), 3, "a second load_combatants() call must not leak duplicate rows")

	var row_label_children: int = 0
	for child in _widget.get_node("RowsContainer").get_children():
		if child is Label:
			row_label_children += 1
	assert_eq(row_label_children, 3, "the scene tree must never accumulate stale Label rows across reloads")


func test_multiple_full_cycles_of_turn_advanced_events_leave_no_stale_labels() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var bravo: Dictionary = _durable_combatant("Bravo", true, "bravo")
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var event_sink := FakeEventSinkPort.new()
	event_sink.forward_to = _widget

	_widget.load_combatants([
		{"combatant_id": "alpha", "name": "Alpha", "initiative_order": 20},
		{"combatant_id": "bravo", "name": "Bravo", "initiative_order": 5},
	])

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 7, event_sink)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	# Drive several turn advances (wrapping the two-entry cycle multiple
	# times) — no dead/Spent combatants here, so the cursor keeps cycling.
	for i in range(6):
		if session.current_actor().get("_is_enemy", false):
			session.advance_ai_turn()
		else:
			session.end_current_turn()

		assert_eq(_widget.get_row_count(), 2, "row count must stay exactly 2 across every simulated turn advance")
		var row_label_children: int = 0
		for child in _widget.get_node("RowsContainer").get_children():
			if child is Label:
				row_label_children += 1
		assert_eq(row_label_children, 2, "no stale/duplicate Label rows may accumulate across repeated turn advances")

	# Simulate round 2 beginning: reload from a fresh view-model snapshot.
	_widget.load_combatants([
		{"combatant_id": "alpha", "name": "Alpha", "initiative_order": 20},
		{"combatant_id": "bravo", "name": "Bravo", "initiative_order": 5},
	])
	assert_eq(_widget.get_row_count(), 2, "reloading for a new round must not leave stale entries from the prior round")
	assert_true(_widget.is_active("alpha"), "a fresh round's reload must reset the active highlight to the first entry")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (code-review guardrail, mirrors initiative_view.gd's
# equivalent regression test): read-only projection — no direct use-case
# calls.
# ══════════════════════════════════════════════════════════════════════════

func _read_source() -> String:
	var file := FileAccess.open(TURN_ORDER_WIDGET_SOURCE_PATH, FileAccess.READ)
	assert_not_null(file, "scenes/battlefield/TurnOrderWidget.gd must be readable to verify its source")
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_contains_no_direct_resolve_action_use_case_reference() -> void:
	var source: String = _read_source()
	assert_eq(
		source.findn("resolve_action_use_case"), -1,
		"TurnOrderWidget.gd must never reference resolve_action_use_case (read-only projection)"
	)


func test_source_contains_no_direct_run_round_use_case_reference() -> void:
	var source: String = _read_source()
	assert_eq(
		source.findn("run_round_use_case"), -1,
		"TurnOrderWidget.gd must never reference run_round_use_case (read-only projection)"
	)


func test_source_declares_no_polling_process_callbacks() -> void:
	var source: String = _read_source()
	assert_eq(source.find("_process("), -1, "TurnOrderWidget.gd must not poll domain state via _process()")
	assert_eq(source.find("_physics_process("), -1, "TurnOrderWidget.gd must not poll domain state via _physics_process()")
