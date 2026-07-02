extends GutTest

## Integration test for FEAT-138: the REAL movement input path
## (presentation/movement_input_controller.gd, configured EXACTLY as
## MainScene.gd wires it) must resync BOTH of MainScene's token renderers --
## HexGridView AND HexBattlefield -- after a Step or Stride.
##
## Regression guarded: previously the controller only resynced HexGridView, so
## the $HexBattlefield renderer kept showing the stale pre-move position. This
## suite drives step_to()/stride_to() through the controller (NOT direct
## move_token() calls) against real HexBattlefield + HexGridView instances,
## proving the production wiring resyncs the battlefield.

const MovementInputControllerClass = preload("res://presentation/movement_input_controller.gd")
const HexBattlefieldScene: PackedScene = preload("res://scenes/battlefield/HexBattlefield.tscn")
const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")

var _controller
var _battlefield
var _grid_view
var _actor
var _enemy


func before_each() -> void:
	_actor = CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	_enemy = CombatantClass.new("e1", "Skeleton", "Enemy", HexCoordClass.new(-3, 0))

	_battlefield = HexBattlefieldScene.instantiate()
	add_child_autofree(_battlefield)
	_battlefield.load_combatants([_actor, _enemy])

	_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_grid_view)
	_grid_view.load_combatants([_actor, _enemy])

	_controller = MovementInputControllerClass.new()


## Configure the controller exactly as MainScene.gd does (hex_grid_view,
## actor_id, action_economy, hex_battlefield) -- the real production wiring.
func _configure_like_mainscene(action_economy = null) -> void:
	_controller.configure(_actor, [_enemy], _grid_view, "p1", action_economy, _battlefield)


func test_step_resyncs_hex_battlefield_through_real_controller_path() -> void:
	_configure_like_mainscene()
	var result: Dictionary = _controller.step_to(HexCoordClass.new(1, 0))
	assert_true(result.get("ok", false), "fixture: a 1-hex Step to an adjacent empty hex must succeed")

	var pos: Dictionary = _battlefield.get_hex_position("p1")
	assert_eq(pos.get("q", null), 1, "HexBattlefield must resync q after a Step via the real controller path (FEAT-138)")
	assert_eq(pos.get("r", null), 0, "HexBattlefield must resync r after a Step via the real controller path (FEAT-138)")


func test_stride_resyncs_hex_battlefield_through_real_controller_path() -> void:
	_configure_like_mainscene(ActionEconomyClass.new())
	var result: Dictionary = _controller.stride_to(HexCoordClass.new(3, 0))
	assert_true(result.get("ok", false), "fixture: a Stride within Speed to an empty hex must succeed")

	var pos: Dictionary = _battlefield.get_hex_position("p1")
	assert_eq(pos.get("q", null), 3, "HexBattlefield must resync q after a Stride via the real controller path (FEAT-138)")
	assert_eq(pos.get("r", null), 0, "HexBattlefield must resync r after a Stride via the real controller path (FEAT-138)")


func test_step_still_resyncs_hex_grid_view_no_regression() -> void:
	_configure_like_mainscene()
	var before = _grid_view.get_token("p1")
	assert_not_null(before, "fixture: HexGridView must have the actor's token")
	var before_pos: Vector2 = before.position

	var result: Dictionary = _controller.step_to(HexCoordClass.new(1, 0))
	assert_true(result.get("ok", false), "fixture: Step must succeed")

	var after = _grid_view.get_token("p1")
	assert_true(after.position != before_pos, "HexGridView must STILL resync after a Step -- no regression from the FEAT-138 battlefield resync")


func test_movement_still_works_when_no_battlefield_configured() -> void:
	# Backward compatibility: hex_battlefield is an OPTIONAL trailing arg; a
	# caller that omits it (pre-FEAT-138 wiring) still Steps successfully and
	# simply resyncs HexGridView alone.
	_controller.configure(_actor, [_enemy], _grid_view, "p1")
	var result: Dictionary = _controller.step_to(HexCoordClass.new(1, 0))
	assert_true(result.get("ok", false), "Step must succeed even with no HexBattlefield collaborator configured")


func test_battlefield_move_token_null_coord_is_noop_not_crash() -> void:
	# HexBattlefield.move_token() guards against a null/malformed coord (FEAT-138):
	# a no-op rather than a crash, so a stray resync call can never throw.
	_battlefield.move_token("p1", null)
	var pos: Dictionary = _battlefield.get_hex_position("p1")
	assert_eq(pos.get("q", null), 0, "a null coord must be a no-op -- position unchanged")
	assert_eq(pos.get("r", null), 0, "a null coord must be a no-op -- position unchanged")
