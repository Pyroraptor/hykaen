extends GutTest
## tests/unit/presentation/test_status_panel_view_selection.gd — FEAT-003
## (US-005 / FR-006): "Status panel selection highlight (presentation)" —
## StatusPanelView's StatusHighlightPort.
##
## Maps to the feature plan's files_to_create entry
## "tests/unit/test_status_panel_view_selection.gd" — this project's actual,
## established file layout (every prior StatusPanelView feature, e.g.
## tests/unit/presentation/test_status_panel_view.gd,
## tests/unit/presentation/test_status_panel_anchor.gd, and the sibling
## FEAT-001/FEAT-002 suite tests/unit/presentation/test_hex_grid_view_selection.gd)
## keeps StatusPanelView's own script under presentation/status_panel_view.gd
## and its tests under tests/unit/presentation/, so this suite lives here
## rather than directly under tests/unit/.
##
## StatusHighlightPort contract (design notes, api_contracts #4/#5):
##   set_selected_combatant(combatant_id: String) -> void
##     Success (known, non-empty id): matching row -> gold
##     Color(1.0, 0.9, 0.4); every other row -> white Color(1, 1, 1, 1).
##     Empty string (""): defined RESET behavior -- every row -> white,
##     get_selected_combatant_id() -> "".
##     Unknown id (non-empty, no matching row): a TRUE no-op -- row
##     modulate states and get_selected_combatant_id() are left EXACTLY as
##     they were before the call. No exception raised.
##   get_selected_combatant_id() -> String — pure accessor, round-trips the
##     last id passed to a successful set_selected_combatant() call.
##
## Verifies (test_criteria):
##   1. set_selected_combatant(id_a) then set_selected_combatant(id_b) swaps
##      the gold highlight from row A to row B and leaves other rows white.
##   2. set_selected_combatant('') resets all rows to white and
##      get_selected_combatant_id() returns ''.
##   3. set_selected_combatant('unknown_id') is a no-op: row modulate states
##      and get_selected_combatant_id() are unchanged from before the call.
##   4. get_selected_combatant_id() round-trips the last id passed to
##      set_selected_combatant().

const StatusPanelViewScene: PackedScene = preload("res://presentation/status_panel_view.tscn")

const GOLD: Color = Color(1.0, 0.9, 0.4)
const WHITE: Color = Color(1, 1, 1, 1)

var _panel = null


func before_each() -> void:
	_panel = StatusPanelViewScene.instantiate()
	add_child_autofree(_panel)


func _sample_view_models() -> Array:
	return [
		{
			"combatant_id": "player_0",
			"name": "Titus",
			"hp_current": 10,
			"hp_max": 10,
			"stamina_current": 6,
			"stamina_max": 6,
			"action_budget_remaining": 7,
			"spent": false,
			"conditions": [],
		},
		{
			"combatant_id": "enemy_0",
			"name": "Skeleton",
			"hp_current": 8,
			"hp_max": 8,
			"stamina_current": 0,
			"stamina_max": 0,
			"action_budget_remaining": 7,
			"spent": true,
			"conditions": [],
		},
	]


func _row_modulate(combatant_id: String) -> Color:
	return _panel.get_row_modulate(combatant_id)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — set_selected_combatant(id_a) then set_selected_combatant(id_b)
# swaps the gold highlight from row A to row B and leaves other rows white.
# ══════════════════════════════════════════════════════════════════════════

func test_set_selected_combatant_modulates_matching_row_gold_and_other_white() -> void:
	_panel.load_combatants(_sample_view_models())

	_panel.set_selected_combatant("player_0")

	assert_eq(
		_row_modulate("player_0"), GOLD,
		"the selected combatant's row must be modulated gold Color(1.0, 0.9, 0.4)"
	)
	assert_eq(
		_row_modulate("enemy_0"), WHITE,
		"a non-selected combatant's row must be modulated white Color(1, 1, 1, 1)"
	)


func test_changing_selection_swaps_gold_highlight_from_row_a_to_row_b() -> void:
	_panel.load_combatants(_sample_view_models())

	_panel.set_selected_combatant("player_0")
	_panel.set_selected_combatant("enemy_0")

	assert_eq(
		_row_modulate("enemy_0"), GOLD,
		"the newly selected combatant's row must become gold"
	)
	assert_eq(
		_row_modulate("player_0"), WHITE,
		"the previously selected combatant's row must revert to white"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — set_selected_combatant('') resets all rows to white and
# get_selected_combatant_id() returns ''.
# ══════════════════════════════════════════════════════════════════════════

func test_set_selected_combatant_empty_string_resets_all_rows_to_white() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.set_selected_combatant("player_0")

	_panel.set_selected_combatant("")

	assert_eq(_row_modulate("player_0"), WHITE, "clearing selection must reset the selected row to white")
	assert_eq(_row_modulate("enemy_0"), WHITE, "clearing selection must leave the other row white")
	assert_eq(
		_panel.get_selected_combatant_id(), "",
		"get_selected_combatant_id() must return '' after set_selected_combatant('')"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — set_selected_combatant('unknown_id') is a no-op: row
# modulate states and get_selected_combatant_id() are unchanged from before
# the call.
# ══════════════════════════════════════════════════════════════════════════

func test_unknown_id_selection_is_a_full_noop_when_nothing_was_previously_selected() -> void:
	_panel.load_combatants(_sample_view_models())

	_panel.set_selected_combatant("does_not_exist")

	assert_eq(
		_row_modulate("player_0"), WHITE,
		"an unknown-id selection must not alter row modulate state (was already white)"
	)
	assert_eq(
		_row_modulate("enemy_0"), WHITE,
		"an unknown-id selection must not alter row modulate state (was already white)"
	)
	assert_eq(
		_panel.get_selected_combatant_id(), "",
		"an unknown-id selection must not alter get_selected_combatant_id() (was already '')"
	)


func test_unknown_id_selection_leaves_existing_gold_highlight_untouched() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.set_selected_combatant("player_0")

	_panel.set_selected_combatant("does_not_exist")

	assert_eq(
		_row_modulate("player_0"), GOLD,
		"an unknown-id selection must NOT reset the currently-selected row -- it is a true no-op, "
		+ "leaving row modulate state exactly as it was before the call"
	)
	assert_eq(
		_row_modulate("enemy_0"), WHITE,
		"an unknown-id selection must not alter a non-selected row's modulate state"
	)


func test_unknown_id_selection_does_not_overwrite_last_successful_selection_id() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.set_selected_combatant("player_0")

	_panel.set_selected_combatant("does_not_exist")

	assert_eq(
		_panel.get_selected_combatant_id(), "player_0",
		"an unknown-id call must be a guarded no-op -- it must not overwrite the last successful selection"
	)


func test_unknown_id_selection_raises_no_exception() -> void:
	_panel.load_combatants(_sample_view_models())
	# Reaching this line without a script error/crash IS the assertion --
	# set_selected_combatant() must never throw on an unknown id.
	_panel.set_selected_combatant("does_not_exist")
	assert_true(true, "set_selected_combatant() with an unknown id must not raise")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — get_selected_combatant_id() round-trips the last id passed
# to set_selected_combatant().
# ══════════════════════════════════════════════════════════════════════════

func test_get_selected_combatant_id_round_trips_through_set_selected_combatant() -> void:
	_panel.load_combatants(_sample_view_models())

	assert_eq(
		_panel.get_selected_combatant_id(), "",
		"sanity check: no selection at boot"
	)

	_panel.set_selected_combatant("player_0")
	assert_eq(_panel.get_selected_combatant_id(), "player_0")

	_panel.set_selected_combatant("enemy_0")
	assert_eq(
		_panel.get_selected_combatant_id(), "enemy_0",
		"get_selected_combatant_id() must reflect the most recently supplied valid id"
	)
