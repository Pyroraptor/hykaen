extends GutTest
## tests/gut/test_hex_battlefield_movement_resync.gd — FEAT-138 (US-013 /
## US-014, DEF-006)
##
## DEF-006 (minor, FR-004): scenes/battlefield/HexBattlefield.gd seeded
## combatant token positions ONCE in load_combatants() and never repositioned
## them after a Step or Stride, while presentation/hex_grid_view.gd already
## correctly re-synced via move_token(). Since MainScene renders both
## battlefields simultaneously, the two renderers could disagree about a
## combatant's hex position after any movement.
##
## This suite proves HexBattlefield now exposes move_token(combatant_id,
## new_hex_coord) -- the SAME method name/signature contract
## presentation/hex_grid_view.gd's move_token() already offers -- and that
## after a Step then a Stride:
##   1. HexBattlefield's CombatantReadout position matches the combatant's
##      CURRENT domain hex_position (core/domain/combatant.gd) after each
##      move (test_criteria #1).
##   2. HexBattlefield's rendered screen position for that combatant matches
##      HexGridView's rendered screen position for the SAME combatant/round --
##      no cross-renderer disagreement (test_criteria #2).
##
## Movement itself is driven directly through the existing, REUSED domain
## rule (core/rules/movement.gd Movement.step()/stride(), ADR-002) -- this
## suite introduces no duplicate movement path. HexBattlefield/HexGridView
## are then each told about the SAME resolved move via their own
## move_token() call, exactly mirroring how a caller (e.g.
## presentation/movement_input_controller.gd, or a future composition-root
## wiring) would resync every renderer subscribed to the same
## movement-completion, without either renderer computing the move itself
## (ADR-001: read-and-render only).

const HexBattlefieldScene: PackedScene = preload("res://scenes/battlefield/HexBattlefield.tscn")
const HexBattlefieldClass: GDScript = preload("res://scenes/battlefield/HexBattlefield.gd")
const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const MovementClass = preload("res://core/rules/movement.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")

var _battlefield = null
var _grid_view = null
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


# ══════════════════════════════════════════════════════════════════════════
# HexBattlefield now offers the same move_token() contract HexGridView does.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_battlefield_exposes_move_token() -> void:
	assert_true(
		_battlefield.has_method("move_token"),
		"HexBattlefield must expose move_token(), mirroring HexGridView's existing resync contract (DEF-006)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: after a Step, HexBattlefield's CombatantReadout position
# matches the combatant's current domain hex_position.
# ══════════════════════════════════════════════════════════════════════════

func test_step_resyncs_combatant_readout_position_to_new_domain_hex_position() -> void:
	var step_destination := HexCoordClass.new(1, 0)
	var step_result: Dictionary = MovementClass.step(_actor, step_destination, [_enemy])
	assert_true(step_result.get("ok", false), "fixture assumption: Step must succeed")
	assert_true(_actor.hex_coord.equals(step_destination), "fixture assumption: domain hex_position updated by Step")

	_battlefield.move_token("p1", step_destination)
	_grid_view.move_token("p1", step_destination)

	var rendered: Dictionary = _battlefield.get_hex_position("p1")
	assert_eq(rendered.get("q", null), _actor.hex_coord.q, "HexBattlefield must resync q after a Step")
	assert_eq(rendered.get("r", null), _actor.hex_coord.r, "HexBattlefield must resync r after a Step")

	var readout = _battlefield.get_readout("p1")
	assert_not_null(readout, "get_readout() must still return the same CombatantReadout after a Step")
	var expected_position: Vector2 = HexBattlefieldClass.axial_to_pixel(_actor.hex_coord)
	assert_almost_eq(
		readout.position, expected_position, Vector2(0.01, 0.01),
		"HexBattlefield's CombatantReadout must be repositioned to the combatant's new hex after a Step"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (continued): after a subsequent Stride, HexBattlefield's
# CombatantReadout position matches the combatant's current domain
# hex_position.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_resyncs_combatant_readout_position_to_new_domain_hex_position() -> void:
	var step_destination := HexCoordClass.new(1, 0)
	MovementClass.step(_actor, step_destination, [_enemy])
	_battlefield.move_token("p1", step_destination)
	_grid_view.move_token("p1", step_destination)

	var action_economy := ActionEconomyClass.new()
	var stride_destination := HexCoordClass.new(4, 0)
	var stride_result: Dictionary = MovementClass.stride(_actor, stride_destination, action_economy, [_enemy])
	assert_true(stride_result.get("ok", false), "fixture assumption: Stride must succeed: %s" % stride_result)
	assert_true(_actor.hex_coord.equals(stride_destination), "fixture assumption: domain hex_position updated by Stride")

	_battlefield.move_token("p1", stride_destination)
	_grid_view.move_token("p1", stride_destination)

	var rendered: Dictionary = _battlefield.get_hex_position("p1")
	assert_eq(rendered.get("q", null), _actor.hex_coord.q, "HexBattlefield must resync q after a Stride")
	assert_eq(rendered.get("r", null), _actor.hex_coord.r, "HexBattlefield must resync r after a Stride")

	var readout = _battlefield.get_readout("p1")
	assert_not_null(readout, "get_readout() must still return the same CombatantReadout after a Stride")
	var expected_position: Vector2 = HexBattlefieldClass.axial_to_pixel(_actor.hex_coord)
	assert_almost_eq(
		readout.position, expected_position, Vector2(0.01, 0.01),
		"HexBattlefield's CombatantReadout must be repositioned to the combatant's new hex after a Stride"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: no cross-renderer disagreement -- HexBattlefield and
# HexGridView agree on the combatant's rendered position after each move.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_battlefield_and_hex_grid_view_agree_after_a_step_then_a_stride() -> void:
	var step_destination := HexCoordClass.new(1, 0)
	MovementClass.step(_actor, step_destination, [_enemy])
	_battlefield.move_token("p1", step_destination)
	_grid_view.move_token("p1", step_destination)

	var battlefield_readout = _battlefield.get_readout("p1")
	var grid_token_after_step = _grid_view.get_token("p1")
	assert_almost_eq(
		battlefield_readout.position, grid_token_after_step.position, Vector2(0.01, 0.01),
		"HexBattlefield and HexGridView must agree on the combatant's rendered position after a Step"
	)

	var action_economy := ActionEconomyClass.new()
	var stride_destination := HexCoordClass.new(4, 0)
	var stride_result: Dictionary = MovementClass.stride(_actor, stride_destination, action_economy, [_enemy])
	assert_true(stride_result.get("ok", false), "fixture assumption: Stride must succeed: %s" % stride_result)

	_battlefield.move_token("p1", stride_destination)
	_grid_view.move_token("p1", stride_destination)

	var grid_token_after_stride = _grid_view.get_token("p1")
	assert_almost_eq(
		battlefield_readout.position, grid_token_after_stride.position, Vector2(0.01, 0.01),
		"HexBattlefield and HexGridView must agree on the combatant's rendered position after a Stride"
	)


# ══════════════════════════════════════════════════════════════════════════
# move_token() is a defensive no-op for an unknown combatant_id.
# ══════════════════════════════════════════════════════════════════════════

func test_move_token_is_a_noop_for_unknown_combatant_id() -> void:
	_battlefield.move_token("does_not_exist", HexCoordClass.new(2, 2))
	assert_eq(_battlefield.get_hex_position("does_not_exist"), {})
