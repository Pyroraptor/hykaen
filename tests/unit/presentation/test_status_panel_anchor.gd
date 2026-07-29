extends GutTest
## tests/unit/presentation/test_status_panel_anchor.gd — FEAT-357
## (US-009 / FR-009, ADR-004 AnchorConfig).
##
## NOTE on file location: FEAT-357's plan lists this file's path as
## "tests/panels/test_status_panel_anchor.gd". This project's established,
## actual layout (every FEAT-008..010/353 commit; see
## tests/unit/test_ci_gut_presentation_consolidation_feat353.py's own note)
## keeps every panel-scene GUT suite under tests/unit/presentation/ rather
## than a tests/panels/ tree that does not otherwise exist in this codebase.
## This suite follows that established convention.
##
## Regression context (DEF-VER-002 / FINDING-002): a prior peer review found
## StatusPanelView.tscn anchored to the TOP of the viewport (anchors_preset
## = 0, i.e. anchor_top/anchor_bottom/anchor_right all 0.0) instead of
## bottom-right, as US-009/FR-009 and ADR-004's per-panel anchored collapse
## direction require -- the same pattern already exercised on InitiativeView
## (top-right anchor). tests/unit/presentation/test_panel_anchor_collapse.gd
## (FEAT-010) already pins StatusPanelView's grow_vertical ==
## GROW_DIRECTION_BEGIN (upward collapse, bottom edge fixed) and the
## *relative* geometry deltas across a toggle_collapsed() call, but never
## asserted the panel's actual anchor_top/anchor_bottom/anchor_right fields
## nor that its resting position is flush against the viewport's bottom
## edge -- which is exactly how a top-anchored-but-otherwise-plausible
## configuration slipped through. This suite closes that gap.

const StatusPanelViewScene: PackedScene = preload("res://presentation/status_panel_view.tscn")

## DEFAULT_VIEWPORT_SIZE — the project's configured default resolution
## (project.godot has no display/window/size override, so Godot 4's engine
## default of 1152x648 applies at real runtime). A headless GUT run's root
## Viewport does NOT inherit this by default (it starts at a small,
## test-harness-internal size), so it's set explicitly here for every test
## in this suite -- letting each test exercise the exact resolution
## test_criteria calls out, rather than an incidental headless-runner size.
const DEFAULT_VIEWPORT_SIZE: Vector2i = Vector2i(1152, 648)


func _instantiate():
	get_tree().root.size = DEFAULT_VIEWPORT_SIZE
	var view = StatusPanelViewScene.instantiate()
	add_child_autofree(view)
	return view


# ── Anchor fields: bottom-right anchored ────────────────────────────────────

func test_status_panel_view_is_bottom_anchored() -> void:
	var view = _instantiate()
	assert_eq(view.anchor_top, 1.0, "StatusPanelView.anchor_top must be 1.0 (bottom-anchored)")
	assert_eq(view.anchor_bottom, 1.0, "StatusPanelView.anchor_bottom must be 1.0 (bottom-anchored)")


func test_status_panel_view_is_right_anchored() -> void:
	var view = _instantiate()
	assert_eq(view.anchor_right, 1.0, "StatusPanelView.anchor_right must be 1.0 (right-anchored)")


# ── grow_vertical: upward growth on collapse (no gap at the bottom edge) ───

func test_status_panel_view_grows_upward_on_collapse() -> void:
	var view = _instantiate()
	assert_eq(
		view.grow_vertical,
		Control.GROW_DIRECTION_BEGIN,
		"StatusPanelView.grow_vertical must be GROW_DIRECTION_BEGIN (upward growth) "
		+ "so collapsing never opens a gap at the bottom edge"
	)


# ── Computed rect: flush against the viewport's bottom edge ────────────────

func test_status_panel_view_bottom_edge_is_flush_with_viewport_bottom() -> void:
	var view = _instantiate()
	var viewport_size: Vector2 = view.get_viewport().get_visible_rect().size
	assert_eq(
		viewport_size, Vector2(DEFAULT_VIEWPORT_SIZE),
		"this test exercises the project's default 1152x648 viewport size"
	)

	var computed_bottom: float = view.global_position.y + view.size.y
	assert_eq(
		computed_bottom, viewport_size.y,
		"StatusPanelView's bottom edge (global_position.y + size.y) must equal the "
		+ "viewport height at the default 1152x648 resolution -- the panel sits "
		+ "flush against the bottom, not the top"
	)


func test_status_panel_view_docks_to_bottom_right_not_top_left() -> void:
	var view = _instantiate()
	var viewport_size: Vector2 = view.get_viewport().get_visible_rect().size
	var computed_bottom: float = view.global_position.y + view.size.y
	var computed_right: float = view.global_position.x + view.size.x

	# A top-anchored panel (the pre-fix bug: anchors_preset = 0, offset_top =
	# 8) would rest with its bottom edge at y = 400 regardless of viewport
	# size -- nowhere near the viewport's actual bottom edge at any
	# non-trivial resolution. The fixed, bottom-right-anchored panel's
	# bottom/right edges must instead track the viewport's own bottom/right
	# edges (within its fixed 8px margin from the right).
	assert_almost_eq(
		computed_bottom, viewport_size.y, 0.01,
		"StatusPanelView's bottom edge must track the viewport's bottom edge, not rest at a fixed offset from the top"
	)
	assert_almost_eq(
		computed_right, viewport_size.x - 8.0, 0.01,
		"StatusPanelView's right edge must track the viewport's right edge (8px margin), not rest at a fixed offset from the left"
	)
