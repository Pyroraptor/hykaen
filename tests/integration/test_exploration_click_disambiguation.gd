extends GutTest
## tests/integration/test_exploration_click_disambiguation.gd — FEAT-006
## (US-006 / FR-004, mitigates RISK-001/RISK-007/RISK-010).
##
## Integration proof, against the REAL, booted res://MainScene.tscn
## composition root (mirrors tests/boot/test_exploration_pathfinding.gd's
## established `_boot_main_scene()` convention -- never a hand-wired
## double), that presentation/exploration_mode_controller.gd's
## `_on_exploration_hex_clicked()` now runs the DisambiguateHexClickUseCase
## guard clause (design notes' "queries get_combatant_id_at_hex before
## pathfinding; if the id is non-empty, present in scenario_session.
## party_hex_positions, and differs from current selection, calls
## _select_party_member(id) and returns early; otherwise falls through
## unchanged to existing move/pathfinding logic") BEFORE any pathfinding is
## attempted.
##
## test_criteria covered:
##   1. Clicking an adjacent hex occupied by a DIFFERENT party member calls
##      _select_party_member(id) and does NOT invoke pathfinding/move.
##   2. Clicking an empty hex falls through to the existing move/
##      pathfinding logic UNCHANGED (regression assertion against the
##      pre-existing click-to-navigate behavior).
##   3. Clicking a hex occupied by an ENEMY combatant falls through to
##      existing move/pathfinding logic unchanged (no selection change).
##   4. Clicking the currently-selected party member's OWN hex falls
##      through to move logic (no redundant re-selection).
##   5. (Verified separately, by running the full existing GUT suite after
##      this feature lands) all pre-existing exploration movement tests
##      continue to pass unmodified.
##
## Fixture facts (mirrors tests/boot/test_exploration_pathfinding.gd's own
## established fixture assumptions for data/scenarios/prologue_scenario.tres
## + data/parties/default_party.tres):
##   - player_0 (Titus) starts at (0, 0) and is the default hover/click
##     selection at boot.
##   - player_1 (Marigold) starts at (-1, 0) -- hex-distance 1 (adjacent)
##     from Titus.
##   - (2, 0) is unoccupied and is NOT one of the scenario's authored
##     proximity-trigger hexes, so a click-to-navigate walk there can never
##     also confound itself with a combat handoff (same target hex
##     test_exploration_pathfinding.gd's own click-to-navigate tests use).

const MAIN_SCENE_SCENE_PATH: String = "res://MainScene.tscn"
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_boot_exploration_mode.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


## _CallCountingExplorationControllerSpy — mirrors tests/boot/
## test_exploration_pathfinding.gd's own identically-named/shaped spy
## convention: wraps the REAL exploration_controller (state genuinely
## mutates when forwarded) while recording a plain call count for
## move_party_member(), so a test can prove "pathfinding/move was never
## invoked" directly rather than merely inferring it from an unmoved token.
class _CallCountingExplorationControllerSpy:
	var _real
	var move_party_member_call_count: int = 0

	func _init(real) -> void:
		_real = real

	func move_party_member(combatant_id: String, target_hex) -> bool:
		move_party_member_call_count += 1
		return _real.move_party_member(combatant_id, target_hex)


## _EnemyAtHexHexGridViewSpy — wraps the REAL, booted hex_grid_view
## (forwarding every call the controller issues against it, so state
## genuinely mutates), overriding ONLY get_combatant_id_at_hex() to report
## a synthetic enemy combatant id at one specific hex. Exploration mode
## never spawns enemy tokens onto hex_grid_view before a combat trigger
## fires (MainScene.gd only calls hex_grid_view.add_combatants(_enemies)
## from the combat-trigger handler), so this is the most direct way to
## exercise the "clicked hex is occupied by a non-party combatant" branch
## against a REAL booted controller without waiting for a live combat
## handoff.
class _EnemyAtHexHexGridViewSpy:
	var _real
	var _enemy_hex
	var _enemy_id: String

	func _init(real, enemy_hex, enemy_id: String) -> void:
		_real = real
		_enemy_hex = enemy_hex
		_enemy_id = enemy_id

	func get_combatant_id_at_hex(hex_coord) -> String:
		if hex_coord.equals(_enemy_hex):
			return _enemy_id
		return _real.get_combatant_id_at_hex(hex_coord)

	func clear_overlays() -> void:
		_real.clear_overlays()

	func set_selected_combatant(id: String) -> void:
		_real.set_selected_combatant(id)

	func get_selected_combatant() -> String:
		return _real.get_selected_combatant()

	func set_path_overlay(path: Array, color: Color) -> void:
		_real.set_path_overlay(path, color)

	func get_path_overlay() -> Array:
		return _real.get_path_overlay()

	func animate_token_to(combatant_id: String, target_hex) -> Signal:
		return _real.animate_token_to(combatant_id, target_hex)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — clicking an adjacent hex occupied by a DIFFERENT party
# member selects it and never invokes pathfinding/move.
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_a_different_party_members_hex_selects_them_without_moving() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._exploration.selected_party_member_id, "player_0", "fixture assumption: Titus (player_0) is the default selection at boot")
	assert_eq(instance.scenario_session.party_hex_positions["player_1"].q, -1, "fixture assumption: Marigold (player_1) starts at (-1, 0)")
	assert_eq(instance.scenario_session.party_hex_positions["player_1"].r, 0, "fixture assumption: Marigold (player_1) starts at (-1, 0)")

	var spy := _CallCountingExplorationControllerSpy.new(instance._exploration.exploration_controller)
	instance._exploration.exploration_controller = spy

	var target := HexCoordClass.new(-1, 0)
	await instance._exploration._on_exploration_hex_clicked(target)

	assert_eq(
		instance._exploration.selected_party_member_id, "player_1",
		"clicking a hex occupied by a different party member must select that member"
	)
	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), "player_1",
		"the disambiguation select branch must route through _select_party_member(), updating hex_grid_view's own selection cache too"
	)
	assert_eq(
		spy.move_party_member_call_count, 0,
		"the disambiguation select branch must never invoke pathfinding/move (exploration_controller.move_party_member())"
	)
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].q, 0, "Titus must not have moved")
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "Titus must not have moved")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — clicking an empty hex falls through to the existing move/
# pathfinding logic UNCHANGED (regression assertion).
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_an_empty_hex_still_walks_the_full_path_unchanged() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._exploration.selected_party_member_id, "player_0", "fixture assumption: Titus (player_0) is the default selection at boot")

	var target := HexCoordClass.new(2, 0)
	assert_eq(instance.hex_grid_view.get_combatant_id_at_hex(target), "", "fixture assumption: (2, 0) must be unoccupied")

	await instance._exploration._on_exploration_hex_clicked(target)

	assert_eq(
		instance.scenario_session.party_hex_positions["player_0"].q, 2,
		"clicking an empty, reachable hex must still walk the full path to the destination (pre-existing behavior unchanged)"
	)
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "clicking an empty, reachable hex must still walk to the destination")

	var token = instance.hex_grid_view.get_token("player_0")
	assert_eq(
		token.position, instance.hex_grid_view.axial_to_pixel(target),
		"the rendered token's pixel position must end at the destination hex's pixel center, exactly as before this feature"
	)
	assert_eq(
		instance._exploration.selected_party_member_id, "player_0",
		"clicking an empty hex must never change the current selection"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — clicking a hex occupied by an ENEMY combatant falls through
# to existing move/pathfinding logic unchanged (no selection change).
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_an_enemy_occupied_hex_falls_through_to_move_with_no_selection_change() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._exploration.selected_party_member_id, "player_0", "fixture assumption: Titus (player_0) is the default selection at boot")

	var target := HexCoordClass.new(2, 0)
	var enemy_spy := _EnemyAtHexHexGridViewSpy.new(instance._exploration._hex_grid_view, target, "enemy_1")
	instance._exploration._hex_grid_view = enemy_spy

	await instance._exploration._on_exploration_hex_clicked(target)

	assert_eq(
		instance._exploration.selected_party_member_id, "player_0",
		"a click on a non-party (enemy) combatant's hex must never change the current selection"
	)
	assert_eq(
		instance.scenario_session.party_hex_positions["player_0"].q, 2,
		"a click on an enemy-occupied hex must still fall through and walk the full path there, exactly like an empty hex"
	)
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "a click on an enemy-occupied hex must still walk to the destination")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — clicking the currently-selected party member's OWN hex
# falls through to move logic (no redundant re-selection).
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_own_hex_falls_through_to_move_logic_not_reselection() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._exploration.selected_party_member_id, "player_0", "fixture assumption: Titus (player_0) is the default selection at boot")

	var own_hex := HexCoordClass.new(0, 0)
	assert_eq(
		instance.hex_grid_view.get_combatant_id_at_hex(own_hex), "player_0",
		"fixture assumption: Titus' own token must be found at his own current hex"
	)

	# Establish a non-empty overlay first (via the genuine hover path). Only
	# the MOVE branch reaches hex_grid_view.clear_overlays() -- the
	# disambiguation select-and-return-early branch never touches the
	# overlay at all -- so observing the overlay go empty after the click
	# below is direct proof this click fell through to the move branch
	# rather than short-circuiting into a (redundant) re-selection.
	instance.hex_grid_view.hex_hovered.emit(HexCoordClass.new(1, 0))
	assert_false(instance.hex_grid_view.get_path_overlay().is_empty(), "fixture assumption: a hover-preview overlay must be visible before the click below")

	await instance._exploration._on_exploration_hex_clicked(own_hex)

	assert_eq(
		instance.hex_grid_view.get_path_overlay(), [],
		"clicking one's own hex must fall through to the move branch, which clears the pre-existing overlay -- the disambiguation select branch would have left it untouched"
	)
	assert_eq(
		instance._exploration.selected_party_member_id, "player_0",
		"clicking one's own hex must never change the current selection (it was already player_0)"
	)
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].q, 0, "clicking one's own hex must produce zero movement (start == goal)")
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "clicking one's own hex must produce zero movement (start == goal)")


# ══════════════════════════════════════════════════════════════════════════
# Edge case sanity: a controller with no hex_grid_view wired (RISK-010
# defensive-guard convention) must fall straight through to move -- the
# disambiguation lookup itself must never be attempted, never crash.
# ══════════════════════════════════════════════════════════════════════════

func test_disambiguation_is_a_safe_no_op_when_hex_grid_view_is_null() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._exploration._hex_grid_view = null

	var target := HexCoordClass.new(2, 0)
	await instance._exploration._on_exploration_hex_clicked(target)

	assert_eq(
		instance.scenario_session.party_hex_positions["player_0"].q, 2,
		"with no hex_grid_view wired, a click must still fall through to move/pathfinding logic without crashing"
	)
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "with no hex_grid_view wired, a click must still walk to the destination")
