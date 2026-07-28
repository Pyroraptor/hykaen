extends GutTest
## tests/unit/presentation/test_panel_anchor_collapse.gd — FEAT-010 (US-009 /
## FR-009, ADR-004 AnchorConfig, Iteration W "Camera Panning & Collapsible
## Panels").
##
## GUT test suite for FEAT-010's per-panel anchored collapse direction:
## each panel's root Control is configured with a `grow_vertical` value
## (static AnchorConfig data, per the design notes' data_model section) that
## decides which vertical edge stays fixed while the panel's height changes
## in toggle_collapsed() -> _apply_collapsed_state() ->
## _apply_anchored_collapse_size():
##
##   GROW_DIRECTION_END   ("downward collapse") -- the TOP edge stays fixed;
##       collapsing shrinks the panel by moving its BOTTOM edge up toward
##       the header. Used by InitiativeView (anchored top-right): the panel
##       is pinned near the top of the screen, so the top edge must never
##       move or a gap would open between the panel and the top-right
##       corner it's anchored to.
##   GROW_DIRECTION_BEGIN ("upward collapse") -- the BOTTOM edge stays
##       fixed; collapsing shrinks the panel by moving its TOP edge down
##       toward the header. Used by StatusPanelView (anchored bottom-right)
##       and EventLogView (anchored bottom-left): both are pinned near the
##       bottom of the screen, so the bottom edge must never move.
##
## Width/horizontal position is never touched by collapse (only Content's
## visibility, hence only height, changes), so the panel's left/right edges
## are trivially unchanged across a toggle -- no separate horizontal-gap
## assertion is needed beyond confirming position.x/size.x are untouched.

const InitiativeViewScene: PackedScene = preload("res://presentation/initiative_view.tscn")
const StatusPanelViewScene: PackedScene = preload("res://presentation/status_panel_view.tscn")
const EventLogViewScene: PackedScene = preload("res://presentation/event_log_view.tscn")


func _instantiate(panel_scene: PackedScene):
	var view = panel_scene.instantiate()
	add_child_autofree(view)
	return view


# ── InitiativeView: top-right anchor, downward collapse (top fixed) ────────

func test_initiative_view_configured_for_downward_collapse() -> void:
	var view = _instantiate(InitiativeViewScene)
	assert_eq(
		view.grow_vertical,
		Control.GROW_DIRECTION_END,
		"InitiativeView must grow/collapse downward (top edge fixed)"
	)
	assert_eq(
		view.grow_horizontal,
		Control.GROW_DIRECTION_BEGIN,
		"InitiativeView is right-anchored: it must grow/collapse leftward from its right edge"
	)


func test_initiative_view_collapse_keeps_top_edge_fixed_no_gap() -> void:
	var view = _instantiate(InitiativeViewScene)
	var original_position: Vector2 = view.position
	var original_size: Vector2 = view.size
	var header_height: float = view.get_node("Header").size.y

	view.toggle_collapsed()

	assert_eq(
		view.position.y, original_position.y,
		"InitiativeView's top edge must not move on collapse -- no gap at the top-right anchor"
	)
	assert_eq(
		view.size.y, header_height,
		"InitiativeView must shrink to exactly its header height when collapsed"
	)
	assert_lt(
		view.size.y, original_size.y,
		"InitiativeView must actually be smaller once collapsed"
	)
	assert_eq(view.position.x, original_position.x, "collapse must never move the panel horizontally")
	assert_eq(view.size.x, original_size.x, "collapse must never resize the panel horizontally")

	view.toggle_collapsed()
	assert_eq(view.position, original_position, "re-expanding must restore the original position exactly")
	assert_eq(view.size, original_size, "re-expanding must restore the original size exactly")


# ── StatusPanelView: bottom-right anchor, upward collapse (bottom fixed) ───

func test_status_panel_view_configured_for_upward_collapse() -> void:
	var view = _instantiate(StatusPanelViewScene)
	assert_eq(
		view.grow_vertical,
		Control.GROW_DIRECTION_BEGIN,
		"StatusPanelView must grow/collapse upward (bottom edge fixed)"
	)
	assert_eq(
		view.grow_horizontal,
		Control.GROW_DIRECTION_BEGIN,
		"StatusPanelView is right-anchored: it must grow/collapse leftward from its right edge"
	)


func test_status_panel_view_collapse_keeps_bottom_edge_fixed_no_gap() -> void:
	var view = _instantiate(StatusPanelViewScene)
	var original_position: Vector2 = view.position
	var original_size: Vector2 = view.size
	var original_bottom: float = original_position.y + original_size.y
	var header_height: float = view.get_node("Header").size.y

	view.toggle_collapsed()

	var collapsed_bottom: float = view.position.y + view.size.y
	assert_eq(
		collapsed_bottom, original_bottom,
		"StatusPanelView's bottom edge must not move on collapse -- no gap at the bottom anchor"
	)
	assert_eq(
		view.size.y, header_height,
		"StatusPanelView must shrink to exactly its header height when collapsed"
	)
	assert_gt(
		view.position.y, original_position.y,
		"StatusPanelView's top edge must move DOWN (toward the fixed bottom) when collapsing"
	)
	assert_eq(view.position.x, original_position.x, "collapse must never move the panel horizontally")
	assert_eq(view.size.x, original_size.x, "collapse must never resize the panel horizontally")

	view.toggle_collapsed()
	assert_eq(view.position, original_position, "re-expanding must restore the original position exactly")
	assert_eq(view.size, original_size, "re-expanding must restore the original size exactly")


# ── EventLogView: bottom-left anchor, upward collapse (bottom fixed) ───────

func test_event_log_view_configured_for_upward_collapse() -> void:
	var view = _instantiate(EventLogViewScene)
	assert_eq(
		view.grow_vertical,
		Control.GROW_DIRECTION_BEGIN,
		"EventLogView must grow/collapse upward (bottom edge fixed)"
	)
	assert_eq(
		view.grow_horizontal,
		Control.GROW_DIRECTION_END,
		"EventLogView is left-anchored: it must grow/collapse rightward from its left edge"
	)


func test_event_log_view_collapse_keeps_bottom_edge_fixed_no_gap() -> void:
	var view = _instantiate(EventLogViewScene)
	var original_position: Vector2 = view.position
	var original_size: Vector2 = view.size
	var original_bottom: float = original_position.y + original_size.y
	var header_height: float = view.get_node("Header").size.y

	view.toggle_collapsed()

	var collapsed_bottom: float = view.position.y + view.size.y
	assert_eq(
		collapsed_bottom, original_bottom,
		"EventLogView's bottom edge must not move on collapse -- no gap at the bottom-left anchor"
	)
	assert_eq(
		view.size.y, header_height,
		"EventLogView must shrink to exactly its header height when collapsed"
	)
	assert_gt(
		view.position.y, original_position.y,
		"EventLogView's top edge must move DOWN (toward the fixed bottom) when collapsing"
	)
	assert_eq(view.position.x, original_position.x, "collapse must never move the panel horizontally")
	assert_eq(view.size.x, original_size.x, "collapse must never resize the panel horizontally")

	view.toggle_collapsed()
	assert_eq(view.position, original_position, "re-expanding must restore the original position exactly")
	assert_eq(view.size, original_size, "re-expanding must restore the original size exactly")
