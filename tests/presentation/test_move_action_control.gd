extends GutTest
## tests/presentation/test_move_action_control.gd — FEAT-007 (US-007 / FR-002)
##
## GUT test suite for MoveActionControl (presentation/MoveActionControl.gd):
## a visible Move affordance, sibling to StrikeActionControl, whose
## visibility is bound to whether HexGridView (via
## presentation/movement_input_controller.gd's union(Step, Stride) hex set,
## see MainScene.gd's _highlight_legal_moves()) currently reports ANY
## selectable hex. MoveActionControl never re-derives movement legality
## itself (ADR-001) — configure() is simply handed the already-computed
## selectable-hex Array and reflects its emptiness in `visible`.
##
## Verifies (test_criteria):
##   1. MoveActionControl.visible == true when configure() is handed a
##      non-empty selectable-hex set.
##   2. MoveActionControl.visible == false when configure() is handed an
##      empty selectable-hex set.
##   3. MoveActionControl exposes the same enabled/disabled semantics as
##      StrikeActionControl (lock()/is_locked() sticky guard, mirroring
##      tests/gut/test_presentation_controls_sticky_lock.gd exactly) for
##      consistency across the player-facing action controls.

const MoveActionControlScene: PackedScene = preload("res://presentation/MoveActionControl.tscn")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


var _control = null


func before_each() -> void:
	_control = MoveActionControlScene.instantiate()
	add_child_autofree(_control)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1/2: visibility is bound to whether the selectable-hex set is
# non-empty.
# ══════════════════════════════════════════════════════════════════════════

func test_visible_true_when_selectable_hexes_non_empty() -> void:
	_control.configure([HexCoordClass.new(1, 0), HexCoordClass.new(0, 1)])

	assert_true(_control.visible, "MoveActionControl must be visible when a non-empty selectable-hex set is configured")


func test_visible_false_when_selectable_hexes_empty() -> void:
	_control.configure([])

	assert_false(_control.visible, "MoveActionControl must be hidden when the selectable-hex set is empty")


func test_visibility_toggles_across_repeated_configure_calls() -> void:
	_control.configure([HexCoordClass.new(1, 0)])
	assert_true(_control.visible, "sanity check: visible after a non-empty configure()")

	_control.configure([])
	assert_false(_control.visible, "must become hidden once a subsequent configure() reports no selectable hexes")

	_control.configure([HexCoordClass.new(0, -1)])
	assert_true(_control.visible, "must become visible again once a later configure() reports selectable hexes")


func test_visible_false_before_any_configure_call() -> void:
	assert_false(_control.visible, "MoveActionControl must start hidden before configure() is ever called (no highlight before a turn has started)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: MoveActionControl exposes the same enabled/disabled semantics
# as StrikeActionControl (lock()/is_locked() sticky guard).
# ══════════════════════════════════════════════════════════════════════════

func test_is_enabled_mirrors_strike_action_control_semantics_before_lock() -> void:
	assert_false(_control.is_locked(), "sanity check: not locked before lock() is ever called")
	assert_false(_control.is_enabled(), "disabled before any configure() call, mirroring StrikeActionControl having no selectable targets yet")

	_control.configure([HexCoordClass.new(1, 0)])
	assert_true(_control.is_enabled(), "enabled once a non-empty selectable-hex set is configured")


func test_lock_hides_control_and_reports_is_locked_true() -> void:
	_control.configure([HexCoordClass.new(1, 0)])
	assert_true(_control.visible, "sanity check: visible before lock()")

	_control.lock()

	assert_true(_control.is_locked(), "MoveActionControl must report is_locked() == true once lock() is engaged")
	assert_false(_control.is_enabled(), "MoveActionControl must be disabled once locked")
	assert_false(_control.visible, "MoveActionControl must be hidden once locked (mirrors ResultScreenView's uniform lock across Strike/EndTurn/Move)")


func test_locked_control_stays_locked_and_hidden_even_after_a_stray_reconfigure() -> void:
	_control.configure([HexCoordClass.new(1, 0)])
	_control.lock()

	assert_true(_control.is_locked())
	assert_false(_control.visible)

	# The DEF-004-style regression this mirrors (see
	# tests/gut/test_presentation_controls_sticky_lock.gd): a stray
	# reconfigure() call after lock() must NOT re-enable/re-show the control.
	_control.configure([HexCoordClass.new(1, 0), HexCoordClass.new(0, 1)])

	assert_true(_control.is_locked(), "is_locked() must stay true through a later configure() call")
	assert_false(_control.is_enabled(), "a stray reconfigure() must not re-enable the control once locked")
	assert_false(_control.visible, "a stray reconfigure() must not re-show the control once locked")
