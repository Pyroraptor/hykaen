extends GutTest
## tests/unit/test_main_scene_canvas_layer_panels.gd — FEAT-007 (US-002 /
## FR-002, ADR-002, Iteration W).
##
## GUT test suite proving StatusPanelView, InitiativeView, and EventLogView
## are wrapped in a CanvasLayer (layer >= 1) so they render in screen space,
## unaffected by GameCamera's world-space transform, per the real
## res://MainScene.tscn composition root (ADR-002 pattern: instantiate the
## real scene, never a hand-wired double).
##
## test_criteria satisfied:
##   1. A scene-tree test confirms StatusPanelView, InitiativeView, and
##      EventLogView are children of a CanvasLayer with layer >= 1.
##   2. Panning GameCamera to a non-zero position leaves each panel's
##      screen-space position/size unchanged (CanvasLayer isolates them
##      from the camera transform).
##   3. MainScene's @onready panel references (status_panel_view,
##      initiative_view, event_log_view) resolve to non-null nodes after
##      reparenting -- no null errors at boot.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return null
	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return null
	instance.seed_override = 42
	add_child_autofree(instance)
	await get_tree().process_frame
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — StatusPanelView, InitiativeView, and EventLogView are
# children of a CanvasLayer with layer >= 1.
# ══════════════════════════════════════════════════════════════════════════

func test_panels_are_children_of_a_canvas_layer_with_layer_gte_1() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	var status_panel_view: Node = instance.get_node_or_null("StatusPanelView")
	var initiative_view: Node = instance.get_node_or_null("InitiativeView")
	var event_log_view: Node = instance.get_node_or_null("EventLogView")

	assert_null(
		status_panel_view,
		"StatusPanelView must no longer be a direct child of MainScene -- it must be reparented "
		+ "under the CanvasLayer"
	)
	assert_null(
		initiative_view,
		"InitiativeView must no longer be a direct child of MainScene -- it must be reparented "
		+ "under the CanvasLayer"
	)
	assert_null(
		event_log_view,
		"EventLogView must no longer be a direct child of MainScene -- it must be reparented "
		+ "under the CanvasLayer"
	)

	status_panel_view = instance.status_panel_view
	initiative_view = instance.initiative_view
	event_log_view = instance.event_log_view

	assert_not_null(status_panel_view, "MainScene.status_panel_view must resolve to a non-null node")
	assert_not_null(initiative_view, "MainScene.initiative_view must resolve to a non-null node")
	assert_not_null(event_log_view, "MainScene.event_log_view must resolve to a non-null node")
	if status_panel_view == null or initiative_view == null or event_log_view == null:
		return

	for panel in [status_panel_view, initiative_view, event_log_view]:
		var parent: Node = panel.get_parent()
		assert_not_null(parent, "%s must have a parent node" % panel.name)
		if parent == null:
			continue
		assert_is(
			parent, CanvasLayer,
			"%s's parent must be a CanvasLayer, found %s" % [panel.name, parent.get_class()]
		)
		if parent is CanvasLayer:
			assert_true(
				parent.layer >= 1,
				"%s's CanvasLayer parent must have layer >= 1, found %d" % [panel.name, parent.layer]
			)

	# All three panels must share the SAME CanvasLayer wrapper.
	assert_eq(
		status_panel_view.get_parent(), initiative_view.get_parent(),
		"StatusPanelView and InitiativeView must share the same CanvasLayer parent"
	)
	assert_eq(
		initiative_view.get_parent(), event_log_view.get_parent(),
		"InitiativeView and EventLogView must share the same CanvasLayer parent"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — panning GameCamera to a non-zero position leaves each
# panel's screen-space position/size unchanged.
# ══════════════════════════════════════════════════════════════════════════

func test_panel_screen_space_transform_unchanged_after_panning_camera() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	var hex_grid_view: Node = instance.get_node_or_null("HexGridView")
	assert_not_null(hex_grid_view, "MainScene must expose a HexGridView child node")
	if hex_grid_view == null:
		return

	var game_camera: Camera2D = hex_grid_view.get_parent().get_node_or_null("GameCamera")
	assert_not_null(game_camera, "GameCamera must exist to pan it")
	if game_camera == null:
		return

	var panels: Array = [
		instance.status_panel_view,
		instance.initiative_view,
		instance.event_log_view,
	]
	for panel in panels:
		assert_not_null(panel, "panel must be non-null before capturing its pre-pan transform")
	if panels.any(func(p): return p == null):
		return

	var before_positions: Array = []
	var before_sizes: Array = []
	for panel in panels:
		before_positions.append(panel.position)
		before_sizes.append(panel.size)

	game_camera.position += Vector2(500, 500)
	await get_tree().process_frame

	for i in range(panels.size()):
		var panel = panels[i]
		assert_eq(
			panel.position, before_positions[i],
			"%s's screen-space position must be unchanged after panning GameCamera" % panel.name
		)
		assert_eq(
			panel.size, before_sizes[i],
			"%s's screen-space size must be unchanged after panning GameCamera" % panel.name
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — MainScene's @onready panel references resolve without
# null errors after reparenting.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_onready_panel_references_resolve_non_null() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	assert_not_null(instance.status_panel_view, "MainScene.status_panel_view must be non-null after reparenting")
	assert_not_null(instance.initiative_view, "MainScene.initiative_view must be non-null after reparenting")
	assert_not_null(instance.event_log_view, "MainScene.event_log_view must be non-null after reparenting")
