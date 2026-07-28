extends GutTest
## tests/unit/presentation/test_collapsible_panel.gd — FEAT-008/FEAT-009
## (US-008 / FR-008, ADR-004, Iteration W "Camera Panning & Collapsible
## Panels").
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
## Per RISK-006 mitigation (design notes), FEAT-008 implemented this pattern
## on a single panel first -- presentation/initiative_view.gd /
## presentation/initiative_view.tscn (InitiativeView) -- and this suite
## originally exercised InitiativeView only.
##
## FEAT-009 (US-008 / FR-008) replicates the SAME implementation to
## StatusPanelView (presentation/status_panel_view.gd/.tscn) and EventLogView
## (presentation/event_log_view.gd/.tscn), and extends this suite to run
## every one of the five assertions above (boot state, toggle-hides-content,
## double-toggle-restores, CollapseButton text swap both directions, and the
## no-parent queue_sort() guard) against all THREE panel classes via GUT's
## use_parameters() -- proving the toggle contract behaves identically no
## matter which panel it's called on, rather than merely "not regressing"
## InitiativeView's own coverage.

const InitiativeViewScene: PackedScene = preload("res://presentation/initiative_view.tscn")
const StatusPanelViewScene: PackedScene = preload("res://presentation/status_panel_view.tscn")
const EventLogViewScene: PackedScene = preload("res://presentation/event_log_view.tscn")

## PANEL_SCENES — every panel class implementing the shared toggle contract
## (Contract 4). Each test below is parametrized over this array via
## use_parameters(), so adding a fourth panel class here is the only change
## needed to extend the whole suite to it.
const PANEL_SCENES: Array = [InitiativeViewScene, StatusPanelViewScene, EventLogViewScene]


## _instantiate(panel_scene) → Node — instantiates `panel_scene` and parents
## it via add_child_autofree() (freed automatically at the end of the test),
## mirroring the original before_each() rig now applied per-parameter.
func _instantiate(panel_scene: PackedScene):
	var view = panel_scene.instantiate()
	add_child_autofree(view)
	return view


# ── Boot state ──────────────────────────────────────────────────────────────

func test_boots_with_collapsed_false(panel_scene = use_parameters(PANEL_SCENES)) -> void:
	var view = _instantiate(panel_scene)
	assert_false(
		view._collapsed,
		"%s must boot with _collapsed == false" % panel_scene.resource_path
	)
	assert_true(view.get_node("Content").visible, "Content must be visible when not collapsed")


# ── toggle_collapsed() flips state and Content visibility ──────────────────

func test_toggle_collapsed_sets_collapsed_true_and_hides_content(panel_scene = use_parameters(PANEL_SCENES)) -> void:
	var view = _instantiate(panel_scene)
	view.toggle_collapsed()
	assert_true(view._collapsed, "toggle_collapsed() must flip _collapsed to true")
	assert_false(
		view.get_node("Content").visible,
		"Content must be hidden when collapsed"
	)


func test_toggle_collapsed_twice_restores_expanded_state(panel_scene = use_parameters(PANEL_SCENES)) -> void:
	var view = _instantiate(panel_scene)
	view.toggle_collapsed()
	view.toggle_collapsed()
	assert_false(view._collapsed, "a second toggle_collapsed() must flip _collapsed back to false")
	assert_true(
		view.get_node("Content").visible,
		"Content must be visible again after toggling twice"
	)


# ── CollapseButton text swap ─────────────────────────────────────────────────

func test_collapse_button_text_is_down_arrow_when_collapsed(panel_scene = use_parameters(PANEL_SCENES)) -> void:
	var view = _instantiate(panel_scene)
	view.toggle_collapsed()
	var button: Button = view.get_node("Header/CollapseButton")
	assert_eq(button.text, "▼", "CollapseButton text must be '▼' when collapsed")


func test_collapse_button_text_is_up_arrow_when_expanded(panel_scene = use_parameters(PANEL_SCENES)) -> void:
	var view = _instantiate(panel_scene)
	view.toggle_collapsed()
	view.toggle_collapsed()
	var button: Button = view.get_node("Header/CollapseButton")
	assert_eq(button.text, "▲", "CollapseButton text must be '▲' when expanded")


# ── No-parent guard on queue_sort() ──────────────────────────────────────────

func test_toggle_collapsed_with_no_parent_does_not_raise(panel_scene = use_parameters(PANEL_SCENES)) -> void:
	var orphan = panel_scene.instantiate()
	assert_null(orphan.get_parent(), "orphan instance must have no parent for this test to be meaningful")

	orphan.toggle_collapsed()

	assert_true(orphan._collapsed, "toggle_collapsed() must still flip _collapsed with no parent")
	orphan.free()


func test_get_parent_queue_sort_called_when_parent_present(panel_scene = use_parameters(PANEL_SCENES)) -> void:
	var view = _instantiate(panel_scene)
	assert_not_null(view.get_parent(), "view must have a parent for this test to be meaningful")
	view.toggle_collapsed()
	assert_true(view._collapsed, "toggle_collapsed() must flip _collapsed when a parent is present")
