extends GutTest
## tests/unit/presentation/test_initiative_view.gd
##
## GUT test suite for FEAT-009 / US-007 — InitiativeView renders the
## domain-determined turn order and highlights the active combatant,
## updating on TurnAdvancedEvent and CombatantDefeatedEvent signals
## (satisfies the steel thread's "sees ... initiative" criterion).
##
## Verifies:
##   1. InitiativeView lists combatants ordered by initiative_order at boot
##      (load_combatants()).
##   2. The active-combatant highlight moves to the correct entry on a
##      simulated TurnAdvancedEvent SIGNAL (connected via a real Godot
##      Signal, exercising on_turn_advanced_event() as a signal-handler
##      entry point, mirroring test_status_panel_view.gd's pattern).
##   3. A defeated combatant is visually marked on a simulated
##      CombatantDefeatedEvent signal.
##   4. Code-review assertion (source-inspection): initiative_view.gd
##      contains no direct reference to resolve_action_use_case or
##      run_round_use_case — InitiativeView must never call into a use case
##      (read-only projection).

const InitiativeViewScene: PackedScene = preload("res://presentation/initiative_view.tscn")

const INITIATIVE_VIEW_PATH: String = "res://presentation/initiative_view.gd"


## _FakeEventEmitter — a minimal Node exposing custom Signals, used to
## simulate a "TurnAdvancedEvent"/"CombatantDefeatedEvent signal" arriving
## at InitiativeView the way a future SignalEventSinkAdapter (design notes,
## ADR-003) would broadcast one — WITHOUT depending on that adapter (out of
## scope for this feature).
class _FakeEventEmitter:
	extends Node
	signal turn_advanced_event(event)
	signal combatant_defeated_event(event)


var _view = null


func before_each() -> void:
	_view = InitiativeViewScene.instantiate()
	add_child_autofree(_view)


func _sample_view_models() -> Array:
	# Deliberately NOT pre-sorted — load_combatants() must sort by
	# initiative_order (descending) itself.
	return [
		{"combatant_id": "enemy_0", "name": "Skeleton", "initiative_order": 9},
		{"combatant_id": "player_0", "name": "Titus", "initiative_order": 17},
		{"combatant_id": "player_1", "name": "Marigold", "initiative_order": 12},
	]


# ── Criterion 1: combatants listed ordered by initiative_order at boot ─────

func test_load_combatants_creates_one_row_per_combatant() -> void:
	_view.load_combatants(_sample_view_models())
	assert_eq(_view.get_row_count(), 3, "InitiativeView must have one row per loaded combatant")


func test_load_combatants_orders_descending_by_initiative_order() -> void:
	_view.load_combatants(_sample_view_models())
	assert_eq(
		_view.get_ordered_combatant_ids(),
		["player_0", "player_1", "enemy_0"],
		"turn order must be descending by initiative_order (17, 12, 9)"
	)


func test_entry_reflects_name_and_initiative_order() -> void:
	_view.load_combatants(_sample_view_models())
	var entry: Dictionary = _view.get_entry("player_0")
	assert_eq(entry.get("name"), "Titus")
	assert_eq(entry.get("initiative_order"), 17)


func test_row_text_displays_name_and_position() -> void:
	_view.load_combatants(_sample_view_models())
	var text: String = _view.get_row_text("player_1")
	assert_string_contains(text, "Marigold", "row text must show the combatant's name")
	assert_string_contains(text, "2.", "row text must show Marigold's position (2nd) in turn order")


func test_load_combatants_reload_does_not_leak_duplicate_rows() -> void:
	_view.load_combatants(_sample_view_models())
	_view.load_combatants(_sample_view_models())
	assert_eq(_view.get_row_count(), 3, "a second load_combatants() call must not leak duplicate rows")


func test_unknown_combatant_id_returns_empty_entry() -> void:
	_view.load_combatants(_sample_view_models())
	assert_eq(_view.get_entry("does_not_exist"), {})


func test_first_entry_in_turn_order_is_active_by_default_after_boot() -> void:
	_view.load_combatants(_sample_view_models())
	assert_eq(
		_view.get_active_combatant_id(), "player_0",
		"the first combatant in initiative order must be active immediately after boot"
	)
	assert_true(_view.is_active("player_0"))
	assert_false(_view.is_active("player_1"))


# ── Criterion 2: active highlight moves on a simulated TurnAdvancedEvent ───

func test_active_highlight_moves_to_correct_entry_on_turn_advanced_signal_by_id() -> void:
	_view.load_combatants(_sample_view_models())

	var emitter := _FakeEventEmitter.new()
	add_child_autofree(emitter)
	emitter.turn_advanced_event.connect(_view.on_turn_advanced_event)

	emitter.emit_signal("turn_advanced_event", {"active_combatant_id": "player_1"})

	assert_eq(_view.get_active_combatant_id(), "player_1")
	assert_true(_view.is_active("player_1"))
	assert_false(_view.is_active("player_0"), "the previously active entry must no longer be highlighted")


func test_active_highlight_moves_via_active_combatant_name() -> void:
	_view.load_combatants(_sample_view_models())
	_view.on_round_event({"active_combatant_name": "Skeleton"})
	assert_eq(_view.get_active_combatant_id(), "enemy_0")
	assert_true(_view.is_active("enemy_0"))


func test_row_text_shows_active_marker_for_the_active_entry_only() -> void:
	_view.load_combatants(_sample_view_models())
	_view.on_turn_advanced_event({"active_combatant_id": "player_1"})

	assert_string_contains(_view.get_row_text("player_1"), "->")
	assert_true(_view.get_row_text("player_0").find("->") == -1)


func test_turn_advanced_event_for_unknown_combatant_is_a_silent_noop() -> void:
	_view.load_combatants(_sample_view_models())
	_view.on_turn_advanced_event({"active_combatant_id": "does_not_exist"})
	assert_eq(
		_view.get_active_combatant_id(), "player_0",
		"an event for an unknown combatant must leave the current highlight unchanged"
	)


# ── Criterion 3: a defeated combatant is visually marked on a simulated ────
# ── CombatantDefeatedEvent signal ──────────────────────────────────────────

func test_defeated_combatant_is_marked_on_combatant_defeated_signal() -> void:
	_view.load_combatants(_sample_view_models())

	var emitter := _FakeEventEmitter.new()
	add_child_autofree(emitter)
	emitter.combatant_defeated_event.connect(_view.on_combatant_defeated_event)

	emitter.emit_signal("combatant_defeated_event", {"name": "Skeleton", "defeated_by": "Titus"})

	assert_true(_view.is_defeated("enemy_0"))
	assert_string_contains(_view.get_row_text("enemy_0"), "Defeated")


func test_defeated_marking_leaves_other_combatants_unaffected() -> void:
	_view.load_combatants(_sample_view_models())
	_view.on_combatant_defeated_event({"name": "Skeleton", "defeated_by": "Titus"})
	assert_false(_view.is_defeated("player_0"))
	assert_false(_view.is_defeated("player_1"))


func test_defeated_active_combatant_clears_the_highlight() -> void:
	_view.load_combatants(_sample_view_models())
	assert_eq(_view.get_active_combatant_id(), "player_0")

	_view.on_combatant_defeated_event({"name": "Titus", "defeated_by": "Skeleton"})

	assert_true(_view.is_defeated("player_0"))
	assert_eq(
		_view.get_active_combatant_id(), "",
		"the highlight must clear when the active combatant is defeated (no TurnAdvancedEvent yet)"
	)


func test_combatant_defeated_event_for_unknown_combatant_is_a_silent_noop() -> void:
	_view.load_combatants(_sample_view_models())
	_view.on_combatant_defeated_event({"name": "Nobody", "defeated_by": "Titus"})
	assert_eq(_view.get_row_count(), 3, "an event for an unknown combatant must not create/remove rows")


func test_round_event_with_production_combatant_defeated_event_value_object() -> void:
	# Exercises the ACTUAL core/rules/round_events.gd shape (name,
	# defeated_by) — confirms InitiativeView works against the real
	# production event type, not only the Dictionary test double above.
	const RoundEventsClass = preload("res://core/rules/round_events.gd")
	_view.load_combatants(_sample_view_models())

	var defeated_event = RoundEventsClass.CombatantDefeatedEvent.new(1, "Skeleton", "Titus")
	_view.on_round_event(defeated_event)

	assert_true(
		_view.is_defeated("enemy_0"),
		"a real RoundEvents.CombatantDefeatedEvent must mark the Skeleton row defeated"
	)


# ── Criterion 4: code-review assertion — no direct use-case calls ──────────

func _read_source() -> String:
	var file := FileAccess.open(INITIATIVE_VIEW_PATH, FileAccess.READ)
	assert_not_null(file, "presentation/initiative_view.gd must be readable to verify its source")
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_contains_no_direct_resolve_action_use_case_reference() -> void:
	var source: String = _read_source()
	assert_eq(
		source.findn("resolve_action_use_case"), -1,
		"initiative_view.gd must never reference resolve_action_use_case (read-only projection)"
	)


func test_source_contains_no_direct_run_round_use_case_reference() -> void:
	var source: String = _read_source()
	assert_eq(
		source.findn("run_round_use_case"), -1,
		"initiative_view.gd must never reference run_round_use_case (read-only projection)"
	)
