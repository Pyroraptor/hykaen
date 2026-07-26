extends GutTest
## tests/unit/presentation/test_hex_grid_view_hover.gd — FEAT-007 (US-007 /
## FR-009).
##
## GUT test suite for presentation/hex_grid_view.gd's hex_hovered(hex_coord)
## signal and its "mouse left this view" (`notify_mouse_exited()`) hook —
## the two new HexGridView surfaces this feature adds so
## presentation/exploration_mode_controller.gd's ExplorationModeController
## can drive a live path preview on hover (FR-009).
##
## Following this codebase's established convention for CanvasItem input
## routing (see tests/unit/presentation/test_hex_grid_view_mapping.gd's
## test_hex_clicked_signal_emits_the_hex_under_the_click(), which exercises
## hex_clicked directly rather than simulating a real OS click): this suite
## exercises hex_hovered directly (signal emission is observable regardless
## of how it was triggered) and _report_hovered_hex()/notify_mouse_exited()
## directly (the two entry points _unhandled_input()/_notification()
## delegate to) rather than depending on this view's real, headless-
## unreliable get_local_mouse_position()/window-focus state.
##
## Verifies (test_criteria):
##   1. hex_hovered can be emitted and observed like hex_clicked (mirrors
##      its contract/shape).
##   2. _report_hovered_hex() emits hex_hovered ONLY when the hovered hex
##      actually changes — a repeated call with the SAME hex is a silent
##      no-op (no duplicate emission).
##   3. _report_hovered_hex() with a DIFFERENT hex always re-emits.
##   4. notify_mouse_exited() emits hex_hovered(null) and resets the
##      de-duplication state, so the very next _report_hovered_hex() call —
##      even with the same hex as before the "exit" — re-emits.
##   5. notify_mouse_exited() is idempotent-safe (repeat calls never crash).

const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")

var _hex_grid_view = null


func before_each() -> void:
	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — hex_hovered mirrors hex_clicked's observable contract.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_hovered_signal_can_be_emitted_and_observed() -> void:
	watch_signals(_hex_grid_view)

	_hex_grid_view.hex_hovered.emit(HexCoordClass.new(2, -1))

	assert_signal_emitted(_hex_grid_view, "hex_hovered")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2/3 — _report_hovered_hex() de-duplicates by hovered-hex change.
# ══════════════════════════════════════════════════════════════════════════

func test_report_hovered_hex_emits_on_first_call() -> void:
	watch_signals(_hex_grid_view)

	_hex_grid_view._report_hovered_hex(HexCoordClass.new(1, 0))

	assert_signal_emit_count(_hex_grid_view, "hex_hovered", 1, "the first hover of a session must emit hex_hovered")
	assert_signal_emitted_with_parameters(
		_hex_grid_view, "hex_hovered", [HexCoordClass.new(1, 0)],
		"hex_hovered must carry the hovered HexCoord"
	)


func test_report_hovered_hex_does_not_re_emit_for_the_same_hex() -> void:
	_hex_grid_view._report_hovered_hex(HexCoordClass.new(1, 0))
	watch_signals(_hex_grid_view)

	_hex_grid_view._report_hovered_hex(HexCoordClass.new(1, 0))
	_hex_grid_view._report_hovered_hex(HexCoordClass.new(1, 0))

	assert_signal_emit_count(
		_hex_grid_view, "hex_hovered", 0,
		"repeated hovers over the SAME hex must not re-emit hex_hovered (no per-motion-event spam)"
	)


func test_report_hovered_hex_re_emits_when_the_hovered_hex_changes() -> void:
	_hex_grid_view._report_hovered_hex(HexCoordClass.new(1, 0))
	watch_signals(_hex_grid_view)

	_hex_grid_view._report_hovered_hex(HexCoordClass.new(2, -1))

	assert_signal_emit_count(_hex_grid_view, "hex_hovered", 1, "a genuinely different hovered hex must re-emit hex_hovered")
	assert_signal_emitted_with_parameters(
		_hex_grid_view, "hex_hovered", [HexCoordClass.new(2, -1)],
		"hex_hovered must carry the NEW hovered HexCoord"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4/5 — notify_mouse_exited() emits hex_hovered(null), resets
# de-duplication, and is idempotent-safe.
# ══════════════════════════════════════════════════════════════════════════

func test_notify_mouse_exited_emits_hex_hovered_with_null() -> void:
	_hex_grid_view._report_hovered_hex(HexCoordClass.new(1, 0))
	watch_signals(_hex_grid_view)

	_hex_grid_view.notify_mouse_exited()

	assert_signal_emit_count(_hex_grid_view, "hex_hovered", 1, "notify_mouse_exited() must emit hex_hovered exactly once")
	assert_signal_emitted_with_parameters(
		_hex_grid_view, "hex_hovered", [null],
		"notify_mouse_exited() must emit hex_hovered(null) -- the 'no longer hovering anything' case"
	)


func test_notify_mouse_exited_resets_deduplication_so_the_same_hex_re_emits_afterward() -> void:
	_hex_grid_view._report_hovered_hex(HexCoordClass.new(1, 0))
	_hex_grid_view.notify_mouse_exited()
	watch_signals(_hex_grid_view)

	# The SAME hex as before the "exit" must be treated as a genuine
	# hover-target change now that the mouse has left and come back.
	_hex_grid_view._report_hovered_hex(HexCoordClass.new(1, 0))

	assert_signal_emit_count(
		_hex_grid_view, "hex_hovered", 1,
		"after notify_mouse_exited(), the next _report_hovered_hex() call must re-emit even for a previously-seen hex"
	)


func test_notify_mouse_exited_is_idempotent_safe() -> void:
	_hex_grid_view.notify_mouse_exited()
	# no crash -- reaching this line is part of the assertion.
	_hex_grid_view.notify_mouse_exited()
	assert_true(true)


# ══════════════════════════════════════════════════════════════════════════
# Regression: the view remains fully functional after hover calls.
# ══════════════════════════════════════════════════════════════════════════

func test_view_remains_usable_after_hover_calls() -> void:
	const CombatantClass = preload("res://core/domain/combatant.gd")

	_hex_grid_view._report_hovered_hex(HexCoordClass.new(0, 0))
	_hex_grid_view.notify_mouse_exited()

	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(0, 0)),
	])
	assert_eq(_hex_grid_view.get_token_count(), 1, "HexGridView must remain fully functional after hover calls")
