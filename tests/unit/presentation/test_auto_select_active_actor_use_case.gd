extends GutTest
## tests/unit/presentation/test_auto_select_active_actor_use_case.gd —
## FEAT-008 (US-008 / FR-008, ADR-005).
##
## Unit-level GUT suite for the new
## presentation/auto_select_active_actor_use_case.gd -- AutoSelectActiveActorUseCase
## -- in isolation, against hand-written fakes standing in for
## hex_grid_view/status_panel_view (mirroring tests/unit/
## test_exploration_mode_controller_select.gd's own _FakeHexGridView
## convention). The REAL, booted res://MainScene.tscn end-to-end scenarios
## (boot-time player active, enemy-turn no-op, subsequent-player-turn
## shift) are covered separately by tests/integration/
## test_active_actor_selection.gd; this suite instead pins the use case's
## own unit-level contract so a future refactor of MainScene.gd's wiring
## can't silently break it without a fast, non-headless-boot signal.
##
## test_criteria covered (unit-level restatement of FEAT-008's own):
##   1. A party-member actor's combatant_id is pushed to BOTH
##      hex_grid_view.set_selected_combatant() and
##      status_panel_view.set_selected_combatant().
##   2. An enemy actor is a no-op: neither collaborator is called.
##   3. A null actor is a no-op: neither collaborator is called.
##   4. Selection consistency invariant: after a party-member call, both
##      fakes report the same selected id.

const AutoSelectActiveActorUseCaseClass = preload("res://presentation/auto_select_active_actor_use_case.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## _FakeSelectionView — stands in for BOTH hex_grid_view and
## status_panel_view (their relevant surface here -- set_selected_combatant()
## / get_selected_combatant()-shaped accessor -- is identical), with a
## call-count list so "exactly once, with the right id" is provable.
class _FakeSelectionView:
	extends RefCounted
	var _selected_combatant_id: String = ""
	var set_selected_combatant_calls: Array = []

	func set_selected_combatant(id: String) -> void:
		set_selected_combatant_calls.append(id)
		_selected_combatant_id = id

	func get_selected_combatant() -> String:
		return _selected_combatant_id

	func get_selected_combatant_id() -> String:
		return _selected_combatant_id


## _FakeCombatant — the minimal shape execute() reads: combatant_id only.
class _FakeCombatant:
	extends RefCounted
	var combatant_id: String

	func _init(id: String) -> void:
		combatant_id = id


var _hex_grid_view
var _status_panel_view
var _party: Array
var _use_case


func before_each() -> void:
	_hex_grid_view = _FakeSelectionView.new()
	_status_panel_view = _FakeSelectionView.new()
	_party = [_FakeCombatant.new("player_0"), _FakeCombatant.new("player_1")]
	_use_case = AutoSelectActiveActorUseCaseClass.new(
		_hex_grid_view, _status_panel_view, Callable(self, "_current_party")
	)


func _current_party() -> Array:
	return _party


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — a party-member actor updates BOTH collaborators.
# ══════════════════════════════════════════════════════════════════════════

func test_party_member_actor_updates_both_hex_grid_view_and_status_panel_view() -> void:
	_use_case.execute(_FakeCombatant.new("player_1"))

	assert_eq(_hex_grid_view.get_selected_combatant(), "player_1")
	assert_eq(_status_panel_view.get_selected_combatant_id(), "player_1")
	assert_eq(_hex_grid_view.set_selected_combatant_calls, ["player_1"])
	assert_eq(_status_panel_view.set_selected_combatant_calls, ["player_1"])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — an enemy actor (not present in the party roster) is a no-op.
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_actor_leaves_both_selections_unchanged() -> void:
	_hex_grid_view.set_selected_combatant("player_0")
	_status_panel_view.set_selected_combatant("player_0")
	_hex_grid_view.set_selected_combatant_calls.clear()
	_status_panel_view.set_selected_combatant_calls.clear()

	_use_case.execute(_FakeCombatant.new("enemy_0"))

	assert_eq(_hex_grid_view.get_selected_combatant(), "player_0")
	assert_eq(_status_panel_view.get_selected_combatant_id(), "player_0")
	assert_eq(_hex_grid_view.set_selected_combatant_calls, [], "an enemy actor must never invoke hex_grid_view.set_selected_combatant")
	assert_eq(_status_panel_view.set_selected_combatant_calls, [], "an enemy actor must never invoke status_panel_view.set_selected_combatant")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — a null actor is a safe no-op.
# ══════════════════════════════════════════════════════════════════════════

func test_null_actor_is_a_safe_no_op() -> void:
	_use_case.execute(null)

	assert_eq(_hex_grid_view.set_selected_combatant_calls, [])
	assert_eq(_status_panel_view.set_selected_combatant_calls, [])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — selection consistency invariant holds after a change.
# ══════════════════════════════════════════════════════════════════════════

func test_selection_consistency_invariant_holds_after_party_member_change() -> void:
	_use_case.execute(_FakeCombatant.new("player_0"))
	assert_eq(_hex_grid_view.get_selected_combatant(), _status_panel_view.get_selected_combatant_id())

	_use_case.execute(_FakeCombatant.new("player_1"))
	assert_eq(_hex_grid_view.get_selected_combatant(), _status_panel_view.get_selected_combatant_id())
