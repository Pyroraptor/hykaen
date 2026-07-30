extends GutTest
## tests/unit/presentation/test_combat_camera_follow_use_case.gd — FEAT-007
## (US-005, mitigates RISK-009).
##
## Unit-level GUT suite for the new presentation/
## combat_camera_follow_use_case.gd -- CombatCameraFollowUseCase -- in
## isolation, against hand-written fakes standing in for hex_grid_view/
## game_camera (mirroring tests/unit/presentation/
## test_auto_select_active_actor_use_case.gd's own fake-collaborator
## convention). The REAL, booted res://MainScene.tscn end-to-end scenarios
## (resolvable hex, unresolved hex, End-Turn-press E2E) are covered
## separately by tests/integration/test_main_scene_combat_camera_follow.gd;
## this suite instead pins the use case's own unit-level contract so a
## future refactor of MainScene.gd's wiring can't silently break it
## without a fast, non-headless-boot signal.
##
## test_criteria covered (unit-level restatement of FEAT-007's own):
##   1. A combatant_id resolvable via scenario_session.party_hex_positions
##      results in game_camera.move_to() being called with
##      hex_grid_view.axial_to_pixel_with_offset(hex_coord).
##   2. A combatant_id resolvable only via the live party/enemies roster
##      Callables (not present in party_hex_positions) still resolves.
##   3. An unresolved combatant_id (absent from party_hex_positions AND the
##      roster) results in no move_to() call and no exception.
##   4. A null combatant is a safe no-op.
##   5. An invalid/unbound camera_follow_fn Callable, or a null
##      hex_grid_view, is a safe no-op (defensive guard).

const CombatCameraFollowUseCaseClass = preload("res://presentation/combat_camera_follow_use_case.gd")
const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

class _FakeHexGridView:
	extends RefCounted
	var axial_to_pixel_calls: Array = []

	func axial_to_pixel_with_offset(hex_coord) -> Vector2:
		axial_to_pixel_calls.append(hex_coord)
		# Deterministic, distinguishable mapping for assertion purposes.
		return Vector2(hex_coord.q * 10.0, hex_coord.r * 10.0)


class _FakeGameCamera:
	extends RefCounted
	var move_to_calls: Array = []

	func move_to(world_pos: Vector2) -> void:
		move_to_calls.append(world_pos)


class _FakeCombatant:
	extends RefCounted
	var combatant_id: String
	var hex_coord

	func _init(id: String, p_hex_coord = null) -> void:
		combatant_id = id
		hex_coord = p_hex_coord


var _hex_grid_view
var _game_camera
var _scenario_session
var _party: Array
var _enemies: Array


func before_each() -> void:
	_hex_grid_view = _FakeHexGridView.new()
	_game_camera = _FakeGameCamera.new()
	_scenario_session = ScenarioSessionClass.new()
	_party = []
	_enemies = []


func _current_party() -> Array:
	return _party


func _current_enemies() -> Array:
	return _enemies


func _make_use_case():
	return CombatCameraFollowUseCaseClass.new(
		_hex_grid_view,
		Callable(_game_camera, "move_to"),
		_scenario_session,
		Callable(self, "_current_party"),
		Callable(self, "_current_enemies")
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — resolvable via scenario_session.party_hex_positions.
# ══════════════════════════════════════════════════════════════════════════

func test_resolvable_via_party_hex_positions_calls_move_to_with_correct_world_pos() -> void:
	var hex_coord = HexCoordClass.new(2, -1)
	_scenario_session.party_hex_positions["player_0"] = hex_coord

	_make_use_case().execute(_FakeCombatant.new("player_0"))

	assert_eq(_game_camera.move_to_calls.size(), 1, "move_to() must be called exactly once")
	if _game_camera.move_to_calls.size() > 0:
		assert_eq(
			_game_camera.move_to_calls[0], _hex_grid_view.axial_to_pixel_with_offset(hex_coord),
			"move_to() must receive axial_to_pixel_with_offset(hex_coord) for the resolved hex"
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — resolvable only via the live party/enemies roster.
# ══════════════════════════════════════════════════════════════════════════

func test_resolvable_via_live_roster_when_absent_from_party_hex_positions() -> void:
	var hex_coord = HexCoordClass.new(3, 3)
	_party.append(_FakeCombatant.new("player_1", hex_coord))

	_make_use_case().execute(_FakeCombatant.new("player_1"))

	assert_eq(_game_camera.move_to_calls.size(), 1, "move_to() must be called once, resolved via the live party roster fallback")
	if _game_camera.move_to_calls.size() > 0:
		assert_eq(_game_camera.move_to_calls[0], Vector2(30.0, 30.0))


func test_resolvable_via_live_enemies_roster() -> void:
	var hex_coord = HexCoordClass.new(-1, -1)
	_enemies.append(_FakeCombatant.new("enemy_0", hex_coord))

	_make_use_case().execute(_FakeCombatant.new("enemy_0"))

	assert_eq(_game_camera.move_to_calls.size(), 1, "move_to() must be called once, resolved via the live enemies roster fallback")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — an unresolved combatant_id is a silent no-op (RISK-009).
# ══════════════════════════════════════════════════════════════════════════

func test_unresolved_combatant_id_is_a_safe_no_op() -> void:
	_make_use_case().execute(_FakeCombatant.new("ghost_actor"))

	assert_eq(_game_camera.move_to_calls, [], "move_to() must never be called when the hex cannot be resolved")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — a null combatant is a safe no-op.
# ══════════════════════════════════════════════════════════════════════════

func test_null_combatant_is_a_safe_no_op() -> void:
	_make_use_case().execute(null)

	assert_eq(_game_camera.move_to_calls, [])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — null/invalid collaborators are a safe no-op.
# ══════════════════════════════════════════════════════════════════════════

func test_invalid_camera_follow_fn_is_a_safe_no_op() -> void:
	var hex_coord = HexCoordClass.new(0, 0)
	_scenario_session.party_hex_positions["player_0"] = hex_coord
	var use_case = CombatCameraFollowUseCaseClass.new(
		_hex_grid_view, Callable(), _scenario_session, Callable(self, "_current_party"), Callable(self, "_current_enemies")
	)

	use_case.execute(_FakeCombatant.new("player_0"))
	# No exception raised is the primary assertion here; nothing else to
	# observe since the camera_follow_fn Callable is invalid/unbound.
	assert_true(true)


func test_null_hex_grid_view_is_a_safe_no_op() -> void:
	var hex_coord = HexCoordClass.new(0, 0)
	_scenario_session.party_hex_positions["player_0"] = hex_coord
	var use_case = CombatCameraFollowUseCaseClass.new(
		null, Callable(_game_camera, "move_to"), _scenario_session, Callable(self, "_current_party"), Callable(self, "_current_enemies")
	)

	use_case.execute(_FakeCombatant.new("player_0"))

	assert_eq(_game_camera.move_to_calls, [], "move_to() must never be called when hex_grid_view is null")
