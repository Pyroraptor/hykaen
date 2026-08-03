extends GutTest
## tests/unit/test_rest_action_guard.gd — FEAT-006 (US-010; FR-012,
## ADR-005; iteration AB-0, rest mechanics steel thread).
##
## GUT suite for core/api/rest_action_guard.gd's RestActionGuard and
## core/api/game_mode_reader.gd's GameModeReader. Mirrors
## tests/unit/test_short_rest_heal_use_case.gd's established "real domain
## Combatant object, no adapter, no engine boot" convention — both
## production files under test are pure RefCounted orchestration (ADR-001).
##
## test_criteria covered:
##   1. invoke() in EXPLORATION mode forwards to the bound use-case
##      Callable and passes through its return Dictionary unchanged.
##   2. invoke() in COMBAT mode does NOT call the bound use-case and
##      returns {success:false, error: ErrorCode.ERR_OUT_OF_COMBAT_ONLY}.
##   3. No side effects occur on the combatant/item passed to a blocked
##      call (verified via before/after state comparison against a real
##      Combatant + ShortRestHealUseCase pairing).
##   4. game_mode_reader helper returns the same value/type consumed
##      identically by a unit test simulating both a HUD-style caller (a
##      duck-typed source object exposing a `game_mode` property) and a
##      guard-style caller (an already-resolved int).
##   5. Static check: no Node/Control/SceneTree references in either
##      production source file.

const RestActionGuardClass    = preload("res://core/api/rest_action_guard.gd")
const GameModeReaderClass     = preload("res://core/api/game_mode_reader.gd")
const ErrorCodeClass          = preload("res://core/application/ports/errors.gd")
const ShortRestHealUseCaseClass = preload("res://core/application/use_cases/short_rest_heal_use_case.gd")
const CombatantClass          = preload("res://core/domain/combatant.gd")
const HexCoordClass           = preload("res://core/geometry/hex_coord.gd")


func _combatant(hp_current: int, hp_max: int, stamina: int) -> Combatant:
	var c := CombatantClass.new("titus_1", "Titus", "Player", HexCoordClass.new(0, 0))
	c.hp_current = hp_current
	c.hp_max = hp_max
	c.stamina = stamina
	return c


## _HudStyleModeSource — a hand-written duck-typed double simulating the
## kind of object a future HUD visibility caller (FEAT-007) would hand to
## GameModeReader.read(): NOT an int, but an Object exposing `game_mode`
## as a real property. Mirrors this codebase's established "small real
## fake, not a Mock-everything spy" convention.
class _HudStyleModeSource:
	extends RefCounted
	var game_mode: int = 0


# ══════════════════════════════════════════════════════════════════════════
# invoke() in EXPLORATION mode forwards to the bound Callable
# ══════════════════════════════════════════════════════════════════════════

func test_invoke_in_exploration_mode_forwards_to_use_case_callable() -> void:
	var guard := RestActionGuardClass.new()
	# `call_count` is an Array (reference type) rather than a plain bool/int
	# local: GDScript lambdas capture local variables BY VALUE, so a
	# reassignment to a captured `bool`/`int` inside the lambda body would
	# never be observed by this outer scope -- mutating a shared Array's
	# element is the established way to observe "was this Callable
	# actually invoked" from outside the closure.
	var call_count := [0]
	var use_case_call := func():
		call_count[0] += 1
		return {"success": true, "hp_gained": 5, "stamina_spent": 1}

	var result: Dictionary = guard.invoke(GameModeReaderClass.EXPLORATION, use_case_call)

	assert_eq(call_count[0], 1, "the bound use-case Callable must be invoked exactly once in EXPLORATION mode")
	assert_eq(result, {"success": true, "hp_gained": 5, "stamina_spent": 1},
		"invoke() must pass through the wrapped use case's return Dictionary unchanged")


func test_invoke_in_exploration_mode_passes_through_a_failure_dictionary_unchanged() -> void:
	# Passthrough must be unconditional -- invoke() does not inspect or
	# alter the wrapped use case's own success/failure shape.
	var guard := RestActionGuardClass.new()
	var use_case_call := func():
		return {"success": false, "error": ErrorCodeClass.ERR_ALREADY_AT_FULL_HP}

	var result: Dictionary = guard.invoke(GameModeReaderClass.EXPLORATION, use_case_call)

	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_ALREADY_AT_FULL_HP})


# ══════════════════════════════════════════════════════════════════════════
# invoke() in COMBAT mode short-circuits without calling the use case
# ══════════════════════════════════════════════════════════════════════════

func test_invoke_in_combat_mode_does_not_call_use_case_and_returns_out_of_combat_error() -> void:
	var guard := RestActionGuardClass.new()
	# See test_invoke_in_exploration_mode_forwards_to_use_case_callable()'s
	# comment: an Array is used here (not a plain bool) because GDScript
	# lambdas capture local variables by value.
	var call_count := [0]
	var use_case_call := func():
		call_count[0] += 1
		return {"success": true}

	var result: Dictionary = guard.invoke(GameModeReaderClass.COMBAT, use_case_call)

	assert_eq(call_count[0], 0, "the bound use-case Callable must NOT be invoked in COMBAT mode")
	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_OUT_OF_COMBAT_ONLY})


# ══════════════════════════════════════════════════════════════════════════
# No side effects on a blocked call -- before/after state comparison
# ══════════════════════════════════════════════════════════════════════════

func test_blocked_call_in_combat_mode_leaves_combatant_state_completely_unchanged() -> void:
	var titus := _combatant(5, 20, 3)
	var use_case := ShortRestHealUseCaseClass.new()
	var guard := RestActionGuardClass.new()
	var use_case_call := func(): return use_case.execute(titus, 1)

	var result: Dictionary = guard.invoke(GameModeReaderClass.COMBAT, use_case_call)

	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_OUT_OF_COMBAT_ONLY})
	assert_eq(titus.hp_current, 5, "hp_current must be byte-for-byte unchanged when blocked")
	assert_eq(titus.stamina, 3, "stamina must be byte-for-byte unchanged when blocked")


# ══════════════════════════════════════════════════════════════════════════
# GameModeReader — shared helper consumed identically by both caller styles
# ══════════════════════════════════════════════════════════════════════════

func test_game_mode_reader_returns_same_value_and_type_for_guard_style_int_input() -> void:
	# Guard-style caller: RestActionGuard.invoke() already has a resolved
	# int (its own `game_mode` parameter) and passes it straight through.
	var reader := GameModeReaderClass.new()

	var exploration_result = reader.read(GameModeReaderClass.EXPLORATION)
	var combat_result = reader.read(GameModeReaderClass.COMBAT)

	assert_eq(typeof(exploration_result), TYPE_INT)
	assert_eq(typeof(combat_result), TYPE_INT)
	assert_eq(exploration_result, GameModeReaderClass.EXPLORATION)
	assert_eq(combat_result, GameModeReaderClass.COMBAT)


func test_game_mode_reader_returns_same_value_and_type_for_hud_style_object_input() -> void:
	# HUD-style caller (simulating FEAT-007's future visibility scan):
	# hands the reader a duck-typed source object exposing `game_mode`
	# rather than an already-resolved int.
	var reader := GameModeReaderClass.new()
	var exploration_source := _HudStyleModeSource.new()
	exploration_source.game_mode = GameModeReaderClass.EXPLORATION
	var combat_source := _HudStyleModeSource.new()
	combat_source.game_mode = GameModeReaderClass.COMBAT

	var exploration_result = reader.read(exploration_source)
	var combat_result = reader.read(combat_source)

	assert_eq(typeof(exploration_result), TYPE_INT)
	assert_eq(typeof(combat_result), TYPE_INT)
	assert_eq(exploration_result, GameModeReaderClass.EXPLORATION,
		"HUD-style and guard-style callers must resolve the same EXPLORATION value")
	assert_eq(combat_result, GameModeReaderClass.COMBAT,
		"HUD-style and guard-style callers must resolve the same COMBAT value")


func test_game_mode_reader_returns_same_value_and_type_for_dictionary_source() -> void:
	var reader := GameModeReaderClass.new()

	var result = reader.read({"game_mode": GameModeReaderClass.COMBAT})

	assert_eq(typeof(result), TYPE_INT)
	assert_eq(result, GameModeReaderClass.COMBAT)


func test_game_mode_reader_defaults_to_exploration_for_null_source() -> void:
	var reader := GameModeReaderClass.new()

	var result = reader.read(null)

	assert_eq(result, GameModeReaderClass.EXPLORATION)


# ══════════════════════════════════════════════════════════════════════════
# Static check: no Node/Control/SceneTree references in production source
# ══════════════════════════════════════════════════════════════════════════

func test_source_files_have_no_node_control_scenetree_references() -> void:
	var paths := [
		"res://core/api/rest_action_guard.gd",
		"res://core/api/game_mode_reader.gd",
	]
	for path in paths:
		var source := FileAccess.get_file_as_string(path)
		for banned in ["extends Node", "extends Control", "extends CanvasItem", "extends SceneTree"]:
			assert_false(source.contains(banned), "%s must not extend '%s'" % [path, banned])
		for banned_hint in [": Node", ": Control", "Node.new(", "Control.new(", "SceneTree.new("]:
			assert_false(source.contains(banned_hint), "%s must not reference '%s'" % [path, banned_hint])
