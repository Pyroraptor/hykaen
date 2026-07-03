extends GutTest

## Integration test for FEAT-162 / DEF-001: the real ResultScreen composition
## wiring must lock the MovementInputController once an EncounterResultEvent
## fires -- exactly as it already locks StrikeInputController/EndTurnController
## -- so Step/Stride are rejected post-resolution. Exercises the real
## ResultScreen.on_round_event() path (the same entry MainScene's EventSinkPort
## subscriber drives), NOT lock() in isolation.

const ResultScreenScene: PackedScene = preload("res://scenes/battlefield/ResultScreen.tscn")
const MovementInputControllerClass = preload("res://presentation/movement_input_controller.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")

var _view
var _movement
var _actor
var _enemy


func before_each() -> void:
	_view = ResultScreenScene.instantiate()
	add_child_autofree(_view)
	_actor = CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	_enemy = CombatantClass.new("e1", "Skeleton", "Enemy", HexCoordClass.new(-3, 0))
	_movement = MovementInputControllerClass.new()
	# Configure with an action economy so a Stride would otherwise be legal --
	# isolating the post-resolution lock as the sole reason it is rejected.
	_movement.configure(_actor, [_enemy], null, "p1", ActionEconomyClass.new())


# Wire exactly as MainScene does: movement_input_controller as the 4th configure() arg.
func test_result_screen_locks_movement_controller_on_encounter_result() -> void:
	_view.configure([], null, null, _movement)
	assert_false(_movement.is_locked(), "fixture: movement controller starts unlocked")

	_view.on_round_event({"round": 1, "outcome": "won"})

	assert_true(
		_movement.is_locked(),
		"MovementInputController must be locked once the ResultScreen is shown (FEAT-162/DEF-001)"
	)


func test_step_and_stride_rejected_after_encounter_result() -> void:
	_view.configure([], null, null, _movement)
	_view.on_round_event({"round": 1, "outcome": "lost"})

	var step_result: Dictionary = _movement.step_to(HexCoordClass.new(1, 0))
	assert_false(step_result.get("ok", true), "Step must be rejected after the encounter is resolved")
	assert_eq(step_result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED", "Step rejection uses the post-resolution lock code")

	var stride_result: Dictionary = _movement.stride_to(HexCoordClass.new(3, 0))
	assert_false(stride_result.get("ok", true), "Stride must be rejected after the encounter is resolved")
	assert_eq(stride_result.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED", "Stride rejection uses the post-resolution lock code")


func test_movement_lock_wiring_is_optional_no_crash_when_omitted() -> void:
	# Backward compat: the 4th arg is optional; omitting it (older wiring) must
	# not crash when the result event fires -- it simply doesn't lock movement.
	_view.configure([], null, null)
	_view.on_round_event({"round": 1, "outcome": "won"})
	assert_false(_movement.is_locked(), "an unwired movement controller is simply never locked (no crash)")
