extends GutTest
## tests/integration/test_panel_viewport_visibility.gd — FEAT-359 (US-009 /
## US-002, resolves DEF-VER-002 / FINDING-002).
##
## Replaces the manual/visual smoke-test step called out in the deployment
## checklist ("boot MainScene.tscn at default 1152x648 viewport and confirm
## StatusPanelView/EventLogView are fully visible on-screen") with an
## automated regression test, so this check is enforced by CI rather than a
## human eyeballing a screenshot. Boots the REAL res://MainScene.tscn scene
## tree (the same entry point project.godot's run/main_scene points at,
## ADR-002 pattern — mirrors tests/unit/test_main_scene_canvas_layer_panels.gd
## and tests/integration/test_steel_thread_camera_panel_e2e.gd's own
## established "instantiate the real scene, never a hand-wired double"
## convention) at the project's default 1152x648 viewport size and asserts:
##
##   1. StatusPanelView, InitiativeView, and EventLogView each render a
##      bounding rect (global_position .. global_position + size) that lies
##      ENTIRELY within [0, viewport.x] x [0, viewport.y] in their default
##      expanded state (post FIX-001/FIX-002).
##   2. Toggling toggle_collapsed() on each panel keeps its collapsed
##      bounding rect fully within the viewport, and leaves no gap at its
##      anchored edge (the anchored edge's screen-space coordinate is
##      unchanged by collapsing, mirroring
##      tests/unit/presentation/test_panel_anchor_collapse.gd's own
##      per-panel anchor-edge invariant, but asserted here against the real,
##      composed MainScene tree rather than a standalone-instantiated panel
##      scene).
##   3. Panning GameCamera to a non-zero position does not change any
##      panel's on-screen bounding rect — re-confirming CanvasLayer
##      screen-space isolation (US-002 / ADR-002) still holds after
##      FIX-001/FIX-002.
##
## All three panels are driven through their real, unmocked classes as
## reparented children of $UILayer (a CanvasLayer) in the real, instantiated
## MainScene tree — never a hand-wired or mocked StatusPanelView/
## InitiativeView/EventLogView double (test_criteria #4).
##
## InitiativeView is only made visible once combat begins (see
## MainScene.gd's _ready()/`initiative_view.visible = false` and
## _on_combat_triggered()'s `initiative_view.visible = true`), so this suite
## boots into combat -- mirroring
## tests/integration/test_steel_thread_camera_panel_e2e.gd's own
## _boot_main_scene_into_combat_with_seed() helper -- before asserting on
## InitiativeView's bounding rect. StatusPanelView and EventLogView are
## already visible at boot (exploration mode), so they are additionally
## checked pre-combat as well, to cover both game modes this steel thread
## cares about.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const PROLOGUE_ENCOUNTER_ID: String = "prologue"

## The project's default window/viewport size (project.godot has no
## [display] override, so this is Godot 4's own project default — the exact
## size the deployment checklist's manual smoke-test step named).
const DEFAULT_VIEWPORT_SIZE: Vector2 = Vector2(1152.0, 648.0)

const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")


func _boot_main_scene(seed_value: int = 42):
	# A headless GUT run's root Viewport does NOT inherit project.godot's
	# configured default resolution (it starts at a small, test-harness-
	# internal size) -- set explicitly here so this suite exercises the
	# EXACT 1152x648 resolution test_criteria calls out, mirroring
	# tests/unit/presentation/test_status_panel_anchor.gd's and
	# tests/unit/presentation/test_event_log_view_bounds.gd's own identical
	# `get_tree().root.size = DEFAULT_VIEWPORT_SIZE` convention.
	get_tree().root.size = Vector2i(DEFAULT_VIEWPORT_SIZE)

	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene entry point) must load as a PackedScene")
	if packed == null:
		return null
	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return null
	instance.seed_override = seed_value
	add_child_autofree(instance)
	await get_tree().process_frame
	return instance


## _boot_main_scene_into_combat(seed_value) -> Node — boots exactly as
## _boot_main_scene() above, then drives the REAL _on_combat_triggered()
## handoff so InitiativeView becomes visible, mirroring
## tests/integration/test_steel_thread_camera_panel_e2e.gd's identically
## purposed helper.
func _boot_main_scene_into_combat(seed_value: int = 42):
	var instance = await _boot_main_scene(seed_value)
	if instance == null:
		return null
	await instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	if instance.turn_controller != null and instance.reaction_window != null:
		instance.turn_controller.configure_reactions(instance.reaction_window, AutoReactionChooserClass.new("pass"))
	return instance


## _assert_within_viewport(panel, viewport_size, context) — asserts panel's
## full on-screen bounding rect (position .. position + size, in the
## CanvasLayer's own screen-space coordinates — a plain Node, not a
## Container, so a Control child's position/size ARE its screen-space
## rect, unshifted by any camera/canvas transform per US-002/ADR-002) lies
## entirely within [0, viewport_size.x] x [0, viewport_size.y].
func _assert_within_viewport(panel: Control, viewport_size: Vector2, context: String) -> void:
	var rect: Rect2 = Rect2(panel.position, panel.size)
	assert_true(
		rect.position.x >= -0.01,
		"%s: left edge (%s) must not fall off-screen (< 0)" % [context, rect.position.x]
	)
	assert_true(
		rect.position.y >= -0.01,
		"%s: top edge (%s) must not fall off-screen (< 0)" % [context, rect.position.y]
	)
	assert_true(
		rect.position.x + rect.size.x <= viewport_size.x + 0.01,
		"%s: right edge (%s) must not exceed viewport width (%s)" % [context, rect.position.x + rect.size.x, viewport_size.x]
	)
	assert_true(
		rect.position.y + rect.size.y <= viewport_size.y + 0.01,
		"%s: bottom edge (%s) must not exceed viewport height (%s)" % [context, rect.position.y + rect.size.y, viewport_size.y]
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — all three panels fully within the default 1152x648 viewport
# in their default expanded state.
# ══════════════════════════════════════════════════════════════════════════

func test_all_three_panels_fully_within_default_viewport_in_expanded_state() -> void:
	var instance = await _boot_main_scene_into_combat(42)
	assert_not_null(instance, "MainScene.tscn must instantiate and boot into combat")
	if instance == null:
		return

	var viewport_size: Vector2 = instance.get_viewport().get_visible_rect().size
	assert_eq(
		viewport_size, DEFAULT_VIEWPORT_SIZE,
		"fixture assumption: this suite must run at the project's default 1152x648 viewport size"
	)

	var status_panel_view: Control = instance.status_panel_view
	var initiative_view: Control = instance.initiative_view
	var event_log_view: Control = instance.event_log_view

	assert_not_null(status_panel_view, "MainScene.status_panel_view must resolve to a non-null node")
	assert_not_null(initiative_view, "MainScene.initiative_view must resolve to a non-null node")
	assert_not_null(event_log_view, "MainScene.event_log_view must resolve to a non-null node")
	if status_panel_view == null or initiative_view == null or event_log_view == null:
		return

	assert_true(status_panel_view.visible, "StatusPanelView must be visible in exploration/combat")
	assert_true(initiative_view.visible, "InitiativeView must be visible once combat begins")
	assert_true(event_log_view.visible, "EventLogView must be visible in exploration/combat")

	_assert_within_viewport(status_panel_view, viewport_size, "StatusPanelView (expanded)")
	_assert_within_viewport(initiative_view, viewport_size, "InitiativeView (expanded)")
	_assert_within_viewport(event_log_view, viewport_size, "EventLogView (expanded)")


## Also covers exploration mode (pre-combat), where StatusPanelView and
## EventLogView are already visible but InitiativeView is not yet.
func test_status_panel_and_event_log_fully_within_default_viewport_before_combat() -> void:
	var instance = await _boot_main_scene(42)
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return

	var viewport_size: Vector2 = instance.get_viewport().get_visible_rect().size

	var status_panel_view: Control = instance.status_panel_view
	var event_log_view: Control = instance.event_log_view
	assert_not_null(status_panel_view, "MainScene.status_panel_view must resolve to a non-null node")
	assert_not_null(event_log_view, "MainScene.event_log_view must resolve to a non-null node")
	if status_panel_view == null or event_log_view == null:
		return

	assert_true(status_panel_view.visible, "StatusPanelView must be visible before combat begins (exploration mode)")
	assert_true(event_log_view.visible, "EventLogView must be visible before combat begins (exploration mode)")

	_assert_within_viewport(status_panel_view, viewport_size, "StatusPanelView (exploration, expanded)")
	_assert_within_viewport(event_log_view, viewport_size, "EventLogView (exploration, expanded)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — toggling toggle_collapsed() on each panel keeps its
# collapsed bounding rect fully within the viewport, with no gap at its
# anchored edge.
# ══════════════════════════════════════════════════════════════════════════

func test_status_panel_view_collapsed_stays_within_viewport_no_gap_at_anchor() -> void:
	var instance = await _boot_main_scene_into_combat(42)
	if instance == null:
		return
	var viewport_size: Vector2 = instance.get_viewport().get_visible_rect().size
	var panel: Control = instance.status_panel_view
	assert_not_null(panel)
	if panel == null:
		return

	# StatusPanelView is anchored bottom-right (upward collapse, bottom edge
	# fixed) -- see presentation/status_panel_view.tscn / tests/unit/
	# presentation/test_panel_anchor_collapse.gd.
	var original_bottom: float = panel.position.y + panel.size.y
	var original_right: float = panel.position.x + panel.size.x

	panel.toggle_collapsed()
	await get_tree().process_frame

	_assert_within_viewport(panel, viewport_size, "StatusPanelView (collapsed)")
	assert_almost_eq(
		panel.position.y + panel.size.y, original_bottom, 0.01,
		"StatusPanelView's bottom (anchored) edge must not move on collapse -- no gap at the anchor"
	)
	assert_almost_eq(
		panel.position.x + panel.size.x, original_right, 0.01,
		"StatusPanelView's right (anchored) edge must not move on collapse -- no gap at the anchor"
	)

	panel.toggle_collapsed()
	await get_tree().process_frame
	_assert_within_viewport(panel, viewport_size, "StatusPanelView (re-expanded)")


func test_initiative_view_collapsed_stays_within_viewport_no_gap_at_anchor() -> void:
	var instance = await _boot_main_scene_into_combat(42)
	if instance == null:
		return
	var viewport_size: Vector2 = instance.get_viewport().get_visible_rect().size
	var panel: Control = instance.initiative_view
	assert_not_null(panel)
	if panel == null:
		return

	# InitiativeView is anchored top-right (downward collapse, top edge
	# fixed).
	var original_top: float = panel.position.y
	var original_right: float = panel.position.x + panel.size.x

	panel.toggle_collapsed()
	await get_tree().process_frame

	_assert_within_viewport(panel, viewport_size, "InitiativeView (collapsed)")
	assert_almost_eq(
		panel.position.y, original_top, 0.01,
		"InitiativeView's top (anchored) edge must not move on collapse -- no gap at the anchor"
	)
	assert_almost_eq(
		panel.position.x + panel.size.x, original_right, 0.01,
		"InitiativeView's right (anchored) edge must not move on collapse -- no gap at the anchor"
	)

	panel.toggle_collapsed()
	await get_tree().process_frame
	_assert_within_viewport(panel, viewport_size, "InitiativeView (re-expanded)")


func test_event_log_view_collapsed_stays_within_viewport_no_gap_at_anchor() -> void:
	var instance = await _boot_main_scene_into_combat(42)
	if instance == null:
		return
	var viewport_size: Vector2 = instance.get_viewport().get_visible_rect().size
	var panel: Control = instance.event_log_view
	assert_not_null(panel)
	if panel == null:
		return

	# EventLogView is anchored bottom-left (upward collapse, bottom edge
	# fixed).
	var original_bottom: float = panel.position.y + panel.size.y
	var original_left: float = panel.position.x

	panel.toggle_collapsed()
	await get_tree().process_frame

	_assert_within_viewport(panel, viewport_size, "EventLogView (collapsed)")
	assert_almost_eq(
		panel.position.y + panel.size.y, original_bottom, 0.01,
		"EventLogView's bottom (anchored) edge must not move on collapse -- no gap at the anchor"
	)
	assert_almost_eq(
		panel.position.x, original_left, 0.01,
		"EventLogView's left (anchored) edge must not move on collapse -- no gap at the anchor"
	)

	panel.toggle_collapsed()
	await get_tree().process_frame
	_assert_within_viewport(panel, viewport_size, "EventLogView (re-expanded)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — panning GameCamera to a non-zero position does not change
# any panel's on-screen bounding rect (CanvasLayer isolation, US-002 /
# ADR-002), re-confirmed after FIX-001/FIX-002.
# ══════════════════════════════════════════════════════════════════════════

func test_camera_pan_does_not_move_any_panel_bounding_rect() -> void:
	var instance = await _boot_main_scene_into_combat(42)
	if instance == null:
		return
	var viewport_size: Vector2 = instance.get_viewport().get_visible_rect().size

	var game_camera: Camera2D = instance.get_node_or_null("GameCamera")
	assert_not_null(game_camera, "MainScene must expose the GameCamera node to pan it")
	if game_camera == null:
		return

	var panels: Array = [instance.status_panel_view, instance.initiative_view, instance.event_log_view]
	for panel in panels:
		assert_not_null(panel, "panel must be non-null before capturing its pre-pan bounding rect")
	if panels.any(func(p): return p == null):
		return

	var before_positions: Array = []
	var before_sizes: Array = []
	for panel in panels:
		_assert_within_viewport(panel, viewport_size, "%s (pre-pan)" % panel.name)
		before_positions.append(panel.position)
		before_sizes.append(panel.size)

	game_camera.position += Vector2(731.0, -419.0)
	await get_tree().process_frame

	for i in range(panels.size()):
		var panel: Control = panels[i]
		assert_eq(
			panel.position, before_positions[i],
			"%s's screen-space position must be unchanged after panning GameCamera (CanvasLayer isolation)" % panel.name
		)
		assert_eq(
			panel.size, before_sizes[i],
			"%s's screen-space size must be unchanged after panning GameCamera (CanvasLayer isolation)" % panel.name
		)
		_assert_within_viewport(panel, viewport_size, "%s (post-pan)" % panel.name)
