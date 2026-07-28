extends GutTest
## tests/unit/presentation/test_collapsible_panel.gd — FEAT-008 (US-008 /
## FR-008, ADR-004, Iteration W "Camera Panning & Collapsible Panels").
##
## GUT test suite for the shared collapsible-panel toggle contract
## (Contract 4, design notes' api_contracts section):
##
##   Panel.toggle_collapsed() -> void
##     - flips _collapsed
##     - sets $Content.visible = not _collapsed
##     - sets $Header/CollapseButton.text to "▼" (collapsed) / "▲" (expanded)
##     - calls get_parent().queue_sort() only when get_parent() != null
##       (a no-parent call must not raise -- guarded no-op).
##
## Per RISK-006 mitigation (design notes), this steel thread implements the
## pattern on a single panel first -- presentation/initiative_view.gd /
## presentation/initiative_view.tscn (InitiativeView) -- before it is
## replicated to StatusPanelView and EventLogView in later features. This
## suite therefore exercises InitiativeView only.

const InitiativeViewScene: PackedScene = preload("res://presentation/initiative_view.tscn")


var _view = null


func before_each() -> void:
	_view = InitiativeViewScene.instantiate()
	add_child_autofree(_view)


# ── Boot state ──────────────────────────────────────────────────────────────

func test_boots_with_collapsed_false() -> void:
	assert_false(_view._collapsed, "InitiativeView must boot with _collapsed == false")
	assert_true(_view.get_node("Content").visible, "Content must be visible when not collapsed")


# ── toggle_collapsed() flips state and Content visibility ──────────────────

func test_toggle_collapsed_sets_collapsed_true_and_hides_content() -> void:
	_view.toggle_collapsed()
	assert_true(_view._collapsed, "toggle_collapsed() must flip _collapsed to true")
	assert_false(
		_view.get_node("Content").visible,
		"Content must be hidden when collapsed"
	)


func test_toggle_collapsed_twice_restores_expanded_state() -> void:
	_view.toggle_collapsed()
	_view.toggle_collapsed()
	assert_false(_view._collapsed, "a second toggle_collapsed() must flip _collapsed back to false")
	assert_true(
		_view.get_node("Content").visible,
		"Content must be visible again after toggling twice"
	)


# ── CollapseButton text swap ─────────────────────────────────────────────────

func test_collapse_button_text_is_down_arrow_when_collapsed() -> void:
	_view.toggle_collapsed()
	var button: Button = _view.get_node("Header/CollapseButton")
	assert_eq(button.text, "▼", "CollapseButton text must be '▼' when collapsed")


func test_collapse_button_text_is_up_arrow_when_expanded() -> void:
	_view.toggle_collapsed()
	_view.toggle_collapsed()
	var button: Button = _view.get_node("Header/CollapseButton")
	assert_eq(button.text, "▲", "CollapseButton text must be '▲' when expanded")


# ── No-parent guard on queue_sort() ──────────────────────────────────────────

func test_toggle_collapsed_with_no_parent_does_not_raise() -> void:
	var orphan = InitiativeViewScene.instantiate()
	assert_null(orphan.get_parent(), "orphan instance must have no parent for this test to be meaningful")

	orphan.toggle_collapsed()

	assert_true(orphan._collapsed, "toggle_collapsed() must still flip _collapsed with no parent")
	orphan.free()


func test_get_parent_queue_sort_called_when_parent_present() -> void:
	# _view is parented via add_child_autofree() in before_each(), so its
	# parent (the GUT test's scene root) receives queue_sort(). There is no
	# direct way to spy on Node.queue_sort() from GDScript, so this is
	# verified indirectly: toggling must not raise when a parent IS present
	# (the counterpart to the no-parent guard test above), and _collapsed
	# must reflect the toggle exactly as it does in the no-parent case.
	assert_not_null(_view.get_parent(), "_view must have a parent for this test to be meaningful")
	_view.toggle_collapsed()
	assert_true(_view._collapsed, "toggle_collapsed() must flip _collapsed when a parent is present")
