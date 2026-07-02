extends GutTest
## tests/unit/presentation/test_movement_input_controller.gd
##
## GUT test suite for FEAT-013 (US-013): MovementInputController
## (presentation/movement_input_controller.gd) offers exactly the legal Step
## destinations (core/rules/movement.gd Movement.get_step_destinations()) and
## forwards a selected destination directly to the injected, REUSED
## Movement.step() (ADR-002 — no duplicate movement path), optionally
## repositioning the mover's token on a HexGridView collaborator.
##
## Verifies:
##   1. get_selectable_step_hexes() exactly matches
##      Movement.get_step_destinations() for the configured actor.
##   2. Selecting a legal destination invokes Movement.step() and updates the
##      actor's position; a non-adjacent/occupied/unknown destination is
##      rejected locally with no positional mutation.
##   3. Integration: a successful Step repositions the actor's token on a
##      configured HexGridView collaborator (via move_token()/reposition()).
##   4. After a successful Step, the selectable-destination set is
##      recomputed from the actor's NEW position (Strike reach re-gate
##      companion behavior — this controller's own cache must never go
##      stale either).

const MovementInputControllerClass = preload("res://presentation/movement_input_controller.gd")
const MovementClass                = preload("res://core/rules/movement.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: get_selectable_step_hexes() exactly matches
# Movement.get_step_destinations().
# ══════════════════════════════════════════════════════════════════════════

func test_selectable_step_hexes_excludes_occupied_neighbor() -> void:
	var actor: Dictionary = {"name": "Titus", "combatant_id": "p1", "hex_coord": HexCoordClass.new(0, 0)}
	var blocker: Dictionary = {"name": "Skeleton", "combatant_id": "e1", "hex_coord": HexCoordClass.new(1, 0)}

	var controller := MovementInputControllerClass.new()
	controller.configure(actor, [blocker])

	var selectable: Array = controller.get_selectable_step_hexes()
	assert_eq(selectable.size(), 5, "one of the 6 neighbors is occupied and must be excluded")
	assert_false(controller.is_hex_selectable(HexCoordClass.new(1, 0)), "the occupied neighbor must not be selectable")
	assert_true(controller.is_hex_selectable(HexCoordClass.new(0, 1)), "an unoccupied neighbor must be selectable")


func test_selectable_step_hexes_with_no_occupants_returns_all_six_neighbors() -> void:
	var actor: Dictionary = {"name": "Titus", "combatant_id": "p1", "hex_coord": HexCoordClass.new(0, 0)}

	var controller := MovementInputControllerClass.new()
	controller.configure(actor, [])

	assert_eq(controller.get_selectable_step_hexes().size(), 6)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: selecting a legal destination moves the actor; an illegal one
# is rejected locally with no mutation.
# ══════════════════════════════════════════════════════════════════════════

func test_step_to_selectable_destination_moves_actor_and_reports_ok() -> void:
	var actor: Dictionary = {"name": "Titus", "combatant_id": "p1", "hex_coord": HexCoordClass.new(0, 0)}

	var controller := MovementInputControllerClass.new()
	controller.configure(actor, [])

	watch_signals(controller)
	var result: Dictionary = controller.step_to(HexCoordClass.new(1, 0))

	assert_true(result.get("ok", false))
	assert_true(actor["hex_coord"].equals(HexCoordClass.new(1, 0)), "the actor Dictionary's hex_coord must be updated")
	assert_signal_emitted(controller, "step_resolved")
	assert_false(controller.has_error())


func test_step_to_non_adjacent_destination_is_rejected_without_calling_movement_step() -> void:
	var actor: Dictionary = {"name": "Titus", "combatant_id": "p1", "hex_coord": HexCoordClass.new(0, 0)}

	var controller := MovementInputControllerClass.new()
	controller.configure(actor, [])

	watch_signals(controller)
	var result: Dictionary = controller.step_to(HexCoordClass.new(3, 0))

	assert_false(result.get("ok", true))
	assert_eq(result.get("error", ""), MovementInputControllerClass.ERR_DESTINATION_NOT_SELECTABLE)
	assert_true(actor["hex_coord"].equals(HexCoordClass.new(0, 0)), "a rejected Step must not move the actor")
	assert_signal_emitted(controller, "step_rejected")
	assert_true(controller.has_error())


func test_step_to_occupied_destination_is_rejected() -> void:
	var actor: Dictionary = {"name": "Titus", "combatant_id": "p1", "hex_coord": HexCoordClass.new(0, 0)}
	var blocker: Dictionary = {"name": "Skeleton", "combatant_id": "e1", "hex_coord": HexCoordClass.new(1, 0)}

	var controller := MovementInputControllerClass.new()
	controller.configure(actor, [blocker])

	var result: Dictionary = controller.step_to(HexCoordClass.new(1, 0))

	assert_false(result.get("ok", true))
	assert_true(actor["hex_coord"].equals(HexCoordClass.new(0, 0)))


func test_step_to_supports_combatant_domain_instances() -> void:
	var actor := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))

	var controller := MovementInputControllerClass.new()
	controller.configure(actor, [])

	var result: Dictionary = controller.step_to(HexCoordClass.new(0, -1))

	assert_true(result.get("ok", false))
	assert_true(actor.hex_coord.equals(HexCoordClass.new(0, -1)))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: a successful Step repositions the actor's token on a
# configured HexGridView collaborator.
# ══════════════════════════════════════════════════════════════════════════

func test_successful_step_repositions_token_on_hex_grid_view() -> void:
	var actor := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var enemy := CombatantClass.new("e1", "Skeleton", "Enemy", HexCoordClass.new(-2, 0))

	var hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(hex_grid_view)
	hex_grid_view.load_combatants([actor, enemy])

	var controller := MovementInputControllerClass.new()
	controller.configure(actor, [enemy], hex_grid_view, "p1")

	var destination := HexCoordClass.new(1, 0)
	var result: Dictionary = controller.step_to(destination)
	assert_true(result.get("ok", false))

	var token = hex_grid_view.get_token("p1")
	assert_not_null(token)
	var expected_position: Vector2 = hex_grid_view.axial_to_pixel(destination)
	assert_almost_eq(
		token.position, expected_position, Vector2(0.01, 0.01),
		"the token must be repositioned to the new hex's mapped screen position"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: after a successful Step, the selectable-destination set is
# recomputed from the actor's NEW position.
# ══════════════════════════════════════════════════════════════════════════

func test_selectable_destinations_are_recomputed_after_a_successful_step() -> void:
	var actor: Dictionary = {"name": "Titus", "combatant_id": "p1", "hex_coord": HexCoordClass.new(0, 0)}

	var controller := MovementInputControllerClass.new()
	controller.configure(actor, [])

	var before: Array = controller.get_selectable_step_hexes()
	assert_true(_contains_hex(before, HexCoordClass.new(2, 0)) == false, "fixture assumption: (2,0) is not a neighbor of (0,0)")

	controller.step_to(HexCoordClass.new(1, 0))

	var after: Array = controller.get_selectable_step_hexes()
	assert_true(
		_contains_hex(after, HexCoordClass.new(2, 0)),
		"after stepping to (1,0), (2,0) must now be offered as a legal next Step destination"
	)
	assert_false(
		_contains_hex(after, HexCoordClass.new(1, 0)),
		"the actor's OWN current hex must never be offered as a Step destination"
	)


func _contains_hex(hexes: Array, target) -> bool:
	for hex_coord in hexes:
		if hex_coord.equals(target):
			return true
	return false
