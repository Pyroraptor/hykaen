extends GutTest
## tests/unit/presentation/test_hex_grid_view_token_animation.gd
##
## GUT suite for FEAT-006 (US-006 / FR-011, ADR-005): HexGridView's
## animate_token_to(combatant_id, target_hex) tweens the named combatant's
## CombatantTokenView to axial_to_pixel(target_hex) over TOKEN_MOVE_DURATION
## seconds, returns the tween's `finished` Signal, and finalizes domain-side
## state via move_token() ONLY once the tween genuinely completes -- never
## eagerly/synchronously -- so pixel state and hex-space state never
## observably diverge for a caller that awaits the returned Signal
## (ADR-005, mitigates RISK-002).
##
## Verifies (test_criteria):
##   1. TOKEN_MOVE_DURATION is the single source of animation duration used
##      by animate_token_to (grep/reflection check, NFR-005) -- the literal
##      0.12 appears exactly once in hex_grid_view.gd (the const's own
##      declaration) and animate_token_to's body references the constant by
##      name, never a second/duplicate hardcoded literal.
##   2. animate_token_to returns the tween's finished Signal.
##   3. awaiting the returned signal yields a token pixel position equal to
##      axial_to_pixel(target_hex).
##   4. domain-side move_token() is invoked exactly once, only after the
##      tween completes -- proven by swapping a spy token (a minimal Node2D
##      double recording every reposition() call, the sole method
##      move_token() calls on a token) into HexGridView's token registry,
##      then asserting its call count is zero immediately after the
##      animate_token_to() call (not eager/synchronous) and exactly one
##      after awaiting the returned signal.
##   5. Completion is asserted via the real `finished` Signal (a genuine
##      `await` on Godot's own Tween completion signal), never a fixed
##      sleep/frame-count wait (RISK-008 test-flakiness mitigation) -- no
##      wait_seconds()/wait_frames() call appears anywhere in this suite.

const HexGridViewClass: GDScript = preload("res://presentation/hex_grid_view.gd")
const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")
const CombatantClass: GDScript = preload("res://core/domain/combatant.gd")

const HEX_GRID_VIEW_SOURCE_PATH: String = "res://presentation/hex_grid_view.gd"
const EPSILON: float = 0.01

var _hex_grid_view = null


func before_each() -> void:
	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)
	_hex_grid_view.load_combatants([
		CombatantClass.new("mover-1", "Titus", "Player", HexCoordClass.new(0, 0)),
	])


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func _count_occurrences(haystack: String, needle: String) -> int:
	var count := 0
	var idx := 0
	while true:
		idx = haystack.find(needle, idx)
		if idx == -1:
			break
		count += 1
		idx += needle.length()
	return count


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: TOKEN_MOVE_DURATION is the SINGLE source of animation
# duration used by animate_token_to (NFR-005).
# ══════════════════════════════════════════════════════════════════════════

func test_token_move_duration_constant_is_point_one_two_seconds() -> void:
	assert_eq(
		HexGridViewClass.TOKEN_MOVE_DURATION, 0.12,
		"TOKEN_MOVE_DURATION must be 0.12 seconds per NFR-005"
	)


func test_token_move_duration_literal_appears_exactly_once_in_source() -> void:
	var source: String = _read_source(HEX_GRID_VIEW_SOURCE_PATH)
	assert_eq(
		_count_occurrences(source, "0.12"), 1,
		"the 0.12 literal must appear exactly once in hex_grid_view.gd (TOKEN_MOVE_DURATION's own declaration) -- animate_token_to must never hardcode a second/duplicate duration literal (NFR-005)"
	)


func test_animate_token_to_body_references_token_move_duration_constant() -> void:
	var source: String = _read_source(HEX_GRID_VIEW_SOURCE_PATH)
	var fn_start: int = source.find("func animate_token_to")
	assert_true(fn_start != -1, "animate_token_to must be defined in hex_grid_view.gd")
	var fn_body: String = source.substr(fn_start)
	assert_true(
		fn_body.find("TOKEN_MOVE_DURATION") != -1,
		"animate_token_to's body must drive its tween duration via the TOKEN_MOVE_DURATION constant (NFR-005), not an inline literal"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: animate_token_to returns the tween's finished Signal.
# ══════════════════════════════════════════════════════════════════════════

func test_animate_token_to_returns_a_signal() -> void:
	var result = _hex_grid_view.animate_token_to("mover-1", HexCoordClass.new(1, 0))

	assert_eq(
		typeof(result), TYPE_SIGNAL,
		"animate_token_to must return the tween's finished Signal"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: awaiting the returned signal yields a token pixel position
# equal to axial_to_pixel(target_hex).
# ══════════════════════════════════════════════════════════════════════════

func test_awaiting_animate_token_to_moves_token_to_target_hex_pixel_position() -> void:
	var target_hex := HexCoordClass.new(2, -1)
	var expected_position: Vector2 = _hex_grid_view.axial_to_pixel_with_offset(target_hex)

	var finished_signal: Signal = _hex_grid_view.animate_token_to("mover-1", target_hex)
	await finished_signal

	var token = _hex_grid_view.get_token("mover-1")
	assert_almost_eq(
		token.position, expected_position, Vector2(EPSILON, EPSILON),
		"after the returned signal fires, the token's pixel position must equal axial_to_pixel(target_hex)"
	)


func test_awaiting_animate_token_to_updates_domain_side_hex_coord_to_target_hex() -> void:
	var target_hex := HexCoordClass.new(-1, 1)

	var finished_signal: Signal = _hex_grid_view.animate_token_to("mover-1", target_hex)
	await finished_signal

	var token = _hex_grid_view.get_token("mover-1")
	assert_true(
		token.hex_coord.equals(target_hex),
		"after the returned signal fires, the token's hex_coord (set only by move_token()/reposition()) must equal target_hex"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: domain-side move_token() is invoked exactly once, only after
# the tween completes.
# ══════════════════════════════════════════════════════════════════════════

## _SpyTokenView -- a minimal Node2D double standing in for a
## CombatantTokenView. move_token() only ever touches a token through its
## `position` property (via the Tween, tweened directly by animate_token_to)
## and its reposition() method (called exactly once by move_token() itself)
## -- so recording reposition() calls is a direct, unambiguous proxy for
## "was move_token() invoked", without needing to double/spy on HexGridView
## itself (this codebase has no existing precedent for GUT doubling, and
## this Node2D-based double is simpler and avoids that machinery entirely).
class _SpyTokenView:
	extends Node2D
	var reposition_calls: Array = []
	var hex_coord = null

	func reposition(new_hex_coord, _offset: Vector2 = Vector2.ZERO) -> void:
		reposition_calls.append(new_hex_coord)
		hex_coord = new_hex_coord


func test_move_token_is_invoked_exactly_once_only_after_the_tween_completes() -> void:
	var spy_token := _SpyTokenView.new()
	add_child_autofree(spy_token)
	# Swap the spy in for the real, already-instantiated token so
	# animate_token_to()'s eventual move_token() call reposition()s THIS
	# object instead of the real CombatantTokenView.
	_hex_grid_view._tokens["mover-1"] = spy_token
	var target_hex := HexCoordClass.new(1, 0)

	var finished_signal: Signal = _hex_grid_view.animate_token_to("mover-1", target_hex)

	# Immediately after the call -- before any frame has advanced the tween --
	# move_token() must NOT have fired yet: it is gated strictly on tween
	# completion, never invoked eagerly/synchronously inside animate_token_to
	# itself.
	assert_eq(
		spy_token.reposition_calls.size(), 0,
		"move_token() must not fire before the tween's finished Signal has been emitted"
	)

	await finished_signal

	# Exactly once, only once the (real) finished Signal has fired.
	assert_eq(
		spy_token.reposition_calls.size(), 1,
		"move_token() must be invoked exactly once, only after the tween completes"
	)
	assert_true(
		spy_token.reposition_calls[0].equals(target_hex),
		"move_token()'s single invocation must finalize the token to target_hex"
	)
