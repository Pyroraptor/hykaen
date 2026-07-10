extends GutTest
## tests/unit/presentation/test_hex_grid_view_move_token.gd
##
## GUT test suite for FEAT-226 (US-005, FR-004, resolves FIND-222): guards
## the "silent token-move no-op" gap in presentation/hex_grid_view.gd's
## HexGridView.move_token() — previously a completely silent no-op on an
## unknown `combatant_id`, which let a caller (e.g. core/application/
## resolve_dodge_step_use_case.gd) mutate Combatant.hex_coord even though the
## on-screen token never actually moved, desyncing the two with no error
## signal at all.
##
## Verifies (test_criteria):
##   1. move_token() on a KNOWN combatant_id still repositions the token and
##      now returns `true` (regression — the pre-existing, working path must
##      remain byte-for-byte functional).
##   2. move_token() on an UNKNOWN combatant_id returns `false`
##      (TOKEN_NOT_FOUND) rather than silently doing nothing observable.
##   3. move_token() on an UNKNOWN combatant_id emits the new
##      `token_move_failed(combatant_id)` signal, carrying the offending id —
##      so a caller wired only via signal (rather than checking the return
##      value) can still observe the failure.
##   4. move_token() on a KNOWN combatant_id never emits
##      `token_move_failed` — the signal is reserved for the failure path
##      only.

const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")

const EPSILON: float = 0.01

var _hex_grid_view = null


func before_each() -> void:
	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(0, 0)),
	])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (regression): a KNOWN combatant_id still repositions the token
# and now reports success via a `true` return value.
# ══════════════════════════════════════════════════════════════════════════

func test_move_token_known_combatant_id_repositions_token_and_returns_true() -> void:
	var new_hex := HexCoordClass.new(2, -1)

	var result = _hex_grid_view.move_token("defender-1", new_hex)

	assert_true(result, "move_token() must return true when the token was found and repositioned")
	var token = _hex_grid_view.get_token("defender-1")
	var expected_position: Vector2 = _hex_grid_view.axial_to_pixel_with_offset(new_hex)
	assert_almost_eq(
		token.position, expected_position, Vector2(EPSILON, EPSILON),
		"the known combatant's token must still visibly reposition to new_hex_coord"
	)


func test_move_token_known_combatant_id_never_emits_token_move_failed() -> void:
	watch_signals(_hex_grid_view)

	_hex_grid_view.move_token("defender-1", HexCoordClass.new(1, 1))

	assert_signal_not_emitted(_hex_grid_view, "token_move_failed", "token_move_failed must never fire for a successful reposition")


# ══════════════════════════════════════════════════════════════════════════
# Criteria 2 + 3: an UNKNOWN combatant_id returns false (TOKEN_NOT_FOUND)
# AND emits token_move_failed(combatant_id).
# ══════════════════════════════════════════════════════════════════════════

func test_move_token_unknown_combatant_id_returns_false() -> void:
	var result = _hex_grid_view.move_token("no_such_combatant", HexCoordClass.new(1, 1))

	assert_false(result, "move_token() must return false (TOKEN_NOT_FOUND) for an unknown combatant_id -- never a silent no-op")


func test_move_token_unknown_combatant_id_emits_token_move_failed_signal() -> void:
	watch_signals(_hex_grid_view)

	_hex_grid_view.move_token("no_such_combatant", HexCoordClass.new(1, 1))

	assert_signal_emitted(_hex_grid_view, "token_move_failed", "an unknown combatant_id must emit token_move_failed so callers watching the signal can also observe the failure")
	assert_eq(
		get_signal_parameters(_hex_grid_view, "token_move_failed", 0)[0], "no_such_combatant",
		"token_move_failed must carry the offending combatant_id"
	)


## test_move_token_unknown_combatant_id_returns_false_or_emits_signal --
## literal test_criteria name: combines criteria 2 + 3 into a single
## assertion pinning BOTH halves of the TOKEN_NOT_FOUND contract together
## (an unknown combatant_id must be observable via EITHER channel a caller
## might use -- the return value or the signal -- not just one of them).
func test_move_token_unknown_combatant_id_returns_false_or_emits_signal() -> void:
	watch_signals(_hex_grid_view)

	var result = _hex_grid_view.move_token("no_such_combatant", HexCoordClass.new(1, 1))

	var returned_false: bool = (result == false)
	var signal_emitted: bool = get_signal_emit_count(_hex_grid_view, "token_move_failed") > 0
	assert_true(
		returned_false or signal_emitted,
		"an unknown combatant_id must be surfaced via a false return value and/or a token_move_failed signal -- never a fully silent no-op"
	)
	# This implementation provides BOTH channels.
	assert_true(returned_false, "this implementation's move_token() returns false for TOKEN_NOT_FOUND")
	assert_true(signal_emitted, "this implementation's move_token() also emits token_move_failed for TOKEN_NOT_FOUND")


func test_move_token_unknown_combatant_id_does_not_crash_and_leaves_existing_tokens_untouched() -> void:
	var original_position: Vector2 = _hex_grid_view.get_token("defender-1").position

	_hex_grid_view.move_token("no_such_combatant", HexCoordClass.new(4, -2))

	# no crash -- reaching this line is part of the assertion.
	assert_eq(
		_hex_grid_view.get_token("defender-1").position, original_position,
		"an unknown combatant_id's failed move must never affect an unrelated, already-tracked token"
	)
