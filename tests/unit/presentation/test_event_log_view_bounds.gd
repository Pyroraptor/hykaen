extends GutTest
## tests/unit/presentation/test_event_log_view_bounds.gd — FEAT-358
## (US-009 / FR-009, resolves DEF-VER-002/FINDING-002).
##
## NOTE on file location: FEAT-358's plan lists this file's path as
## "tests/panels/test_event_log_view_bounds.gd" and the scene under fix as
## "scenes/panels/EventLogView.tscn". This project's established, actual
## layout (every FEAT-008..010/353/357 commit; see e.g.
## tests/unit/presentation/test_status_panel_anchor.gd's own identical
## note) keeps every panel-scene GUT suite under tests/unit/presentation/
## and the scene itself at presentation/event_log_view.tscn rather than a
## scenes/panels/ or tests/panels/ tree that does not otherwise exist in
## this codebase. This suite follows that established convention.
##
## Regression context (DEF-VER-002/FINDING-002): a peer review found
## EventLogView.tscn anchored top-left with a fixed offset_bottom = 720,
## which exceeds the project's default 1152x648 viewport height -- pushing
## part of the panel (and, once collapsed, its own header) off-screen at
## the bottom, violating US-009/FR-009's "no gap / correctly anchored"
## acceptance criterion. This mirrors the exact defect class
## test_status_panel_anchor.gd (FEAT-357) already fixed on StatusPanelView,
## applied here to EventLogView specifically.

const EventLogViewScene: PackedScene = preload("res://presentation/event_log_view.tscn")

## DEFAULT_VIEWPORT_SIZE — the project's configured default resolution
## (project.godot has no display/window/size override, so Godot 4's engine
## default of 1152x648 applies at real runtime). A headless GUT run's root
## Viewport does NOT inherit this by default, so it's set explicitly here,
## mirroring test_status_panel_anchor.gd.
const DEFAULT_VIEWPORT_SIZE: Vector2i = Vector2i(1152, 648)


func _instantiate():
	get_tree().root.size = DEFAULT_VIEWPORT_SIZE
	var view = EventLogViewScene.instantiate()
	add_child_autofree(view)
	return view


# ── Anchor fields: bottom-left anchored ─────────────────────────────────────

func test_event_log_view_is_left_anchored() -> void:
	var view = _instantiate()
	assert_eq(view.anchor_left, 0.0, "EventLogView.anchor_left must be 0.0 (left-anchored)")


func test_event_log_view_is_bottom_anchored() -> void:
	var view = _instantiate()
	assert_eq(view.anchor_bottom, 1.0, "EventLogView.anchor_bottom must be 1.0 (bottom-anchored)")


func test_event_log_view_grows_upward_on_collapse() -> void:
	var view = _instantiate()
	assert_eq(
		view.grow_vertical,
		Control.GROW_DIRECTION_BEGIN,
		"EventLogView.grow_vertical must be GROW_DIRECTION_BEGIN (upward growth) "
		+ "so collapsing never opens a gap at the bottom-left anchor"
	)


# ── Computed rect: fully within the default 1152x648 viewport ──────────────

func test_event_log_view_bottom_fits_within_default_viewport_when_expanded() -> void:
	var view = _instantiate()
	var viewport_size: Vector2 = view.get_viewport().get_visible_rect().size
	assert_eq(
		viewport_size, Vector2(DEFAULT_VIEWPORT_SIZE),
		"this test exercises the project's default 1152x648 viewport size"
	)

	var computed_bottom: float = view.position.y + view.size.y
	assert_true(
		computed_bottom <= viewport_size.y,
		"EventLogView's expanded bottom edge (position.y + size.y = %s) must be <= "
		% [computed_bottom]
		+ "the default viewport height (%s), not rendered off-screen" % [viewport_size.y]
	)
	assert_almost_eq(
		computed_bottom, viewport_size.y, 0.5,
		"EventLogView must sit flush against the viewport's bottom edge, not float above/below it"
	)


func test_event_log_view_bottom_fits_within_default_viewport_when_collapsed() -> void:
	var view = _instantiate()
	view.toggle_collapsed()

	var viewport_size: Vector2 = view.get_viewport().get_visible_rect().size
	var computed_bottom: float = view.position.y + view.size.y
	assert_true(
		computed_bottom <= viewport_size.y,
		"EventLogView's collapsed bottom edge (position.y + size.y = %s) must be <= "
		% [computed_bottom]
		+ "the default viewport height (%s), not rendered off-screen" % [viewport_size.y]
	)


# ── Header/CollapseButton must remain fully visible (not clipped) ──────────

func test_event_log_view_header_fully_visible_when_expanded() -> void:
	var view = _instantiate()
	var viewport_size: Vector2 = view.get_viewport().get_visible_rect().size
	var header: Control = view.get_node("Header")
	var header_top: float = view.position.y + header.position.y
	var header_bottom: float = header_top + header.size.y

	assert_true(
		header_top >= 0.0 and header_bottom <= viewport_size.y,
		"EventLogView's Header (and CollapseButton within it) must be fully "
		+ "visible within the default viewport (top=%s, bottom=%s, viewport height=%s)"
		% [header_top, header_bottom, viewport_size.y]
	)


func test_event_log_view_header_fully_visible_when_collapsed() -> void:
	var view = _instantiate()
	view.toggle_collapsed()

	var viewport_size: Vector2 = view.get_viewport().get_visible_rect().size
	var header: Control = view.get_node("Header")
	var header_top: float = view.position.y + header.position.y
	var header_bottom: float = header_top + header.size.y

	assert_true(
		header_top >= 0.0 and header_bottom <= viewport_size.y,
		"EventLogView's collapsed Header (and CollapseButton within it) must be "
		+ "fully visible within the default viewport (top=%s, bottom=%s, viewport height=%s)"
		% [header_top, header_bottom, viewport_size.y]
	)
