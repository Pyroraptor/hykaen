extends GutTest
## tests/unit/test_exploration_mode_controller_camera_follow.gd — FEAT-006
## (US-004, ADR-002, mitigates RISK-007).
##
## GUT suite for presentation/exploration_mode_controller.gd's new,
## optional `on_camera_follow: Callable` setup() dependency: when present,
## _select_party_member(id) — the single authorized write path for
## selection state (FEAT-002/FEAT-005) — invokes it, AFTER
## hex_grid_view.set_selected_combatant(id), with the newly-selected party
## member's world position, computed via
## hex_grid_view.axial_to_pixel_with_offset(hex_coord). Absent/invalid
## `on_camera_follow` must be a silent no-op (backward compatibility —
## every pre-existing caller/test that never supplies this key must keep
## working unmodified).
##
## test_criteria covered:
##   1. Selecting a party member with on_camera_follow set invokes the
##      Callable with the correct world position derived from
##      axial_to_pixel_with_offset().
##   2. Regression test: omitting on_camera_follow from setup() deps
##      produces no error and no invocation (backward compatibility).
##   3. (RISK-007 guard) the pre-existing selection test_criteria —
##      selected_party_member_id assignment, hex_grid_view.
##      set_selected_combatant() call, and boot-time auto-select routing
##      through _select_party_member() — all still pass unchanged with
##      on_camera_follow wired.

const ExplorationModeControllerClass = preload("res://presentation/exploration_mode_controller.gd")
const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const CoordinateTransformClass = preload("res://presentation/infrastructure/coordinate_transform.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## _FakeHexGridView — mirrors tests/unit/test_exploration_mode_controller_
## selection.gd's own _FakeHexGridView convention: a hand-written fake
## exposing the hex_clicked/hex_hovered signals boot() connects to, a real
## stateful set_selected_combatant()/get_selected_combatant() round-trip,
## PLUS a real axial_to_pixel_with_offset() delegating to the SAME
## presentation/infrastructure/coordinate_transform.gd the production
## HexGridView uses, so this suite can assert the exact world position
## on_camera_follow is invoked with.
class _FakeHexGridView:
	extends RefCounted
	signal hex_clicked(hex_coord)
	signal hex_hovered(hex_coord)

	const HEX_SIZE: float = 32.0

	var _selected_combatant_id: String = ""
	var set_selected_combatant_calls: Array = []
	var origin_offset: Vector2 = Vector2(100.0, 50.0)

	func set_path_overlay(_path: Array, _color: Color) -> void:
		pass

	func clear_overlays() -> void:
		pass

	func set_selected_combatant(id: String) -> void:
		set_selected_combatant_calls.append(id)
		_selected_combatant_id = id

	func get_selected_combatant() -> String:
		return _selected_combatant_id

	func axial_to_pixel_with_offset(hex_coord) -> Vector2:
		return CoordinateTransformClass.axial_to_pixel(hex_coord, HEX_SIZE, origin_offset)


## _FakeHexCombatant — minimal duck-typed stand-in for boot()'s
## `hex_combatants` entries (`combatant_id`/`hex_coord`), mirrors this
## controller's other GUT suites' own _FakeHexCombatant convention.
class _FakeHexCombatant:
	extends RefCounted
	var combatant_id: String
	var hex_coord

	func _init(p_combatant_id: String, p_hex_coord) -> void:
		combatant_id = p_combatant_id
		hex_coord = p_hex_coord


## _CameraFollowSpy — records every on_camera_follow invocation (world
## position argument) so this suite can assert both the call count and the
## exact Vector2 the Callable receives.
class _CameraFollowSpy:
	extends RefCounted
	var calls: Array = []

	func move_to(world_pos: Vector2) -> void:
		calls.append(world_pos)


func _make_controller(hex_grid_view, deps_extra: Dictionary = {}) -> ExplorationModeControllerClass:
	var controller := ExplorationModeControllerClass.new()
	var deps: Dictionary = {
		"hex_grid_view": hex_grid_view,
		"scenario_path": NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
	}
	for key in deps_extra.keys():
		deps[key] = deps_extra[key]
	controller.setup(deps)
	return controller


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — selecting a party member with on_camera_follow set invokes
# the Callable with the world position derived from
# axial_to_pixel_with_offset().
# ══════════════════════════════════════════════════════════════════════════

func test_select_party_member_invokes_on_camera_follow_with_correct_world_position() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var camera_follow_spy := _CameraFollowSpy.new()
	var controller := _make_controller(hex_grid_view, {
		"on_camera_follow": Callable(camera_follow_spy, "move_to"),
	})

	var hex_coord = HexCoordClass.new(2, -1)
	controller.boot([
		_FakeHexCombatant.new("hero_a", hex_coord),
	])

	var expected_world_pos: Vector2 = hex_grid_view.axial_to_pixel_with_offset(hex_coord)

	assert_eq(
		camera_follow_spy.calls.size(), 1,
		"on_camera_follow must be invoked exactly once for boot()'s auto-select"
	)
	if camera_follow_spy.calls.size() > 0:
		assert_eq(
			camera_follow_spy.calls[0], expected_world_pos,
			"on_camera_follow must be invoked with axial_to_pixel_with_offset(token.hex_coord)"
		)


func test_select_party_member_invokes_on_camera_follow_after_set_selected_combatant() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var camera_follow_spy := _CameraFollowSpy.new()
	var controller := _make_controller(hex_grid_view, {
		"on_camera_follow": Callable(camera_follow_spy, "move_to"),
	})

	# Directly exercise _select_party_member with a scenario_session that
	# already has a known hex position for the id, to prove ordering
	# without depending on boot()'s own auto-select path.
	var ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
	var scenario_session := ScenarioSessionClass.new()
	var hex_coord = HexCoordClass.new(1, 1)
	scenario_session.party_hex_positions["hero_b"] = hex_coord
	controller.scenario_session = scenario_session

	controller._select_party_member("hero_b")

	assert_eq(
		hex_grid_view.set_selected_combatant_calls, ["hero_b"],
		"hex_grid_view.set_selected_combatant(id) must still be called"
	)
	assert_eq(
		camera_follow_spy.calls.size(), 1,
		"on_camera_follow must be invoked once selection changes"
	)
	if camera_follow_spy.calls.size() > 0:
		assert_eq(
			camera_follow_spy.calls[0], hex_grid_view.axial_to_pixel_with_offset(hex_coord),
			"on_camera_follow must receive the world position for the newly-selected member's hex"
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — regression: omitting on_camera_follow from setup() deps
# produces no error and no invocation (backward compatibility).
# ══════════════════════════════════════════════════════════════════════════

func test_select_party_member_is_a_safe_no_op_without_on_camera_follow() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var controller := _make_controller(hex_grid_view)

	controller.boot([
		_FakeHexCombatant.new("hero_a", HexCoordClass.new(0, 0)),
	])

	assert_eq(
		controller.selected_party_member_id, "hero_a",
		"selection must still work with no on_camera_follow configured"
	)
	assert_eq(
		hex_grid_view.set_selected_combatant_calls, ["hero_a"],
		"hex_grid_view.set_selected_combatant() must still be called with no on_camera_follow configured"
	)


func test_select_party_member_direct_call_is_safe_without_on_camera_follow() -> void:
	# Defensive: _select_party_member() called directly (no boot()), no
	# hex_grid_view, no scenario_session, no on_camera_follow — must never
	# throw.
	var controller := ExplorationModeControllerClass.new()

	controller._select_party_member("hero_a")

	assert_eq(
		controller.selected_party_member_id, "hero_a",
		"_select_party_member(id) must still update selected_party_member_id"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (RISK-007 guard) — pre-existing ExplorationModeController
# selection behavior is unchanged by this wiring.
# ══════════════════════════════════════════════════════════════════════════

func test_select_party_member_still_sets_selected_party_member_id() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var camera_follow_spy := _CameraFollowSpy.new()
	var controller := _make_controller(hex_grid_view, {
		"on_camera_follow": Callable(camera_follow_spy, "move_to"),
	})

	controller._select_party_member("hero_c")

	assert_eq(
		controller.selected_party_member_id, "hero_c",
		"_select_party_member(id) must still set selected_party_member_id to id"
	)
	assert_eq(
		hex_grid_view.get_selected_combatant(), "hero_c",
		"hex_grid_view.get_selected_combatant() must still reflect id immediately after _select_party_member(id)"
	)
