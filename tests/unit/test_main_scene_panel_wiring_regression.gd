extends GutTest
## tests/unit/test_main_scene_panel_wiring_regression.gd — FEAT-352
## (US-010 / FR-010, RISK-006 mitigation).
##
## FEAT-007 introduced the $UILayer CanvasLayer and re-pointed MainScene.gd's
## @onready panel vars to resolve underneath it
## ($UILayer/StatusPanelView, $UILayer/InitiativeView, $UILayer/EventLogView).
## FEAT-009/FEAT-010 then replicated/finalized the shared collapsible-panel
## toggle contract onto all three panel classes. This suite is FEAT-352's own
## dedicated regression proof that:
##
##   1. MainScene's @onready panel references still resolve correctly under
##      the CanvasLayer for StatusPanelView, InitiativeView, and EventLogView
##      (using the panel classes as finalized by FEAT-009/FEAT-010).
##   2. The pre-existing exploration-mode panel show/hide behaviour
##      (InitiativeView hidden during EXPLORATION, shown during COMBAT, hidden
##      again on returning to EXPLORATION) still functions with the
##      CanvasLayer-relative paths -- driven through the REAL,
##      exploration-to-combat-to-exploration round trip against the real,
##      shipped res://MainScene.tscn (never a hand-wired double), mirroring
##      this project's established _boot_main_scene()/_click() conventions
##      (see tests/boot/test_exploration_to_combat_handoff.gd).
##   3. CollapseButton signal wiring is confirmed internal to each panel
##      scene -- MainScene.gd never references "CollapseButton" itself (a
##      source-inspection guard), and each panel's own
##      $Header/CollapseButton.pressed signal is connected to the panel
##      instance itself, never to the MainScene instance.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")

## Mirrors tests/boot/test_exploration_to_combat_handoff.gd's established
## fixture geometry constants exactly, so this suite drives the SAME genuine,
## stepwise player-facing path into combat rather than inventing a second
## fixture-geometry assumption.
const PROLOGUE_SEED: int = 42
const INTERMEDIATE_HEX := Vector2i(1, -1)
const TRIGGER_HEX := Vector2i(1, -2)


func before_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func after_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return null
	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return null
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _click(instance, hex: Vector2i) -> void:
	await instance._exploration._on_exploration_hex_clicked(HexCoordClass.new(hex.x, hex.y))


## Same genuine two-hop walk test_exploration_to_combat_handoff.gd uses to
## fire combat_triggered through the real ExplorationModeController path.
func _drive_into_combat(instance) -> void:
	await _click(instance, INTERMEDIATE_HEX)
	await get_tree().process_frame
	await _click(instance, TRIGGER_HEX)
	await get_tree().process_frame
	await get_tree().process_frame


func _force_win(instance) -> void:
	for enemy in instance._enemies:
		enemy.hp_current = 0
	instance.end_turn_control.press()


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — @onready panel references resolve correctly under the
# CanvasLayer for all three panel classes.
# ══════════════════════════════════════════════════════════════════════════

func test_onready_panel_refs_resolve_under_the_canvas_layer() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	var ui_layer: Node = instance.get_node_or_null("UILayer")
	assert_not_null(ui_layer, "MainScene must expose a UILayer CanvasLayer child node")
	assert_is(ui_layer, CanvasLayer, "UILayer must be a CanvasLayer")
	if ui_layer == null:
		return

	assert_eq(
		instance.status_panel_view, ui_layer.get_node_or_null("StatusPanelView"),
		"status_panel_view must resolve to $UILayer/StatusPanelView"
	)
	assert_eq(
		instance.initiative_view, ui_layer.get_node_or_null("InitiativeView"),
		"initiative_view must resolve to $UILayer/InitiativeView"
	)
	assert_eq(
		instance.event_log_view, ui_layer.get_node_or_null("EventLogView"),
		"event_log_view must resolve to $UILayer/EventLogView"
	)

	for panel in [instance.status_panel_view, instance.initiative_view, instance.event_log_view]:
		assert_not_null(panel, "panel @onready reference must be non-null")
		if panel == null:
			continue
		assert_eq(panel.get_parent(), ui_layer, "%s's parent must be the UILayer CanvasLayer" % panel.name)

	# FEAT-009/FEAT-010: confirm the panel classes finalized by those features
	# (each exposing toggle_collapsed()/_collapsed) are what MainScene wired.
	for panel in [instance.status_panel_view, instance.initiative_view, instance.event_log_view]:
		assert_true(panel.has_method("toggle_collapsed"), "%s must expose the FEAT-009/010 toggle_collapsed() contract" % panel.name)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — exploration-mode panel show/hide behaviour still functions
# with the CanvasLayer-relative @onready paths.
# ══════════════════════════════════════════════════════════════════════════

func test_initiative_view_hidden_on_boot_in_exploration_mode() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "fixture assumption: must boot into EXPLORATION")
	assert_false(instance.initiative_view.visible, "InitiativeView must be hidden while booting into EXPLORATION mode")
	assert_true(instance.status_panel_view.visible, "StatusPanelView must remain visible in EXPLORATION mode")
	assert_true(instance.event_log_view.visible, "EventLogView must remain visible in EXPLORATION mode")


func test_initiative_view_shown_after_entering_combat_then_hidden_again_after_resolution() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	assert_false(instance.initiative_view.visible, "fixture assumption: InitiativeView starts hidden in EXPLORATION")

	await _drive_into_combat(instance)
	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: the real handoff must have entered COMBAT")
	assert_true(instance.initiative_view.visible, "InitiativeView must become visible once COMBAT starts")

	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "fixture assumption: resolving the encounter returns to EXPLORATION")
	assert_false(instance.initiative_view.visible, "InitiativeView must be hidden again after returning to EXPLORATION")
	assert_true(instance.status_panel_view.visible, "StatusPanelView must remain visible throughout the exploration/combat round trip")
	assert_true(instance.event_log_view.visible, "EventLogView must remain visible throughout the exploration/combat round trip")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — CollapseButton signal wiring is confirmed internal to each
# panel scene; MainScene does not directly wire CollapseButton signals.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_source_never_references_collapse_button() -> void:
	var file := FileAccess.open("res://MainScene.gd", FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	assert_false(
		content.contains("CollapseButton"),
		"MainScene.gd must never reference CollapseButton -- that wiring is self-contained within each panel scene (US-010)"
	)


func test_collapse_button_pressed_signal_is_connected_to_its_own_panel_not_main_scene() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	for panel in [instance.status_panel_view, instance.initiative_view, instance.event_log_view]:
		var button: Button = panel.get_node_or_null("Header/CollapseButton")
		assert_not_null(button, "%s must expose a Header/CollapseButton" % panel.name)
		if button == null:
			continue

		assert_true(
			button.pressed.is_connected(Callable(panel, "toggle_collapsed")),
			"%s's CollapseButton.pressed must be connected to the panel's OWN toggle_collapsed()" % panel.name
		)
		assert_false(
			button.pressed.is_connected(Callable(instance, "toggle_collapsed")),
			"%s's CollapseButton.pressed must not be wired to MainScene directly" % panel.name
		)

		for connection in button.pressed.get_connections():
			var target = connection["callable"].get_object()
			assert_ne(
				target, instance,
				"%s's CollapseButton.pressed must not have any connection whose target is the MainScene instance" % panel.name
			)
