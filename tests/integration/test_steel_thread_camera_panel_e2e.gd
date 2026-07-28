extends GutTest
## tests/integration/test_steel_thread_camera_panel_e2e.gd — FEAT-354 (US-011 /
## FR-011, Iteration W "Camera Panning & Collapsible Panels").
##
## The FINAL end-to-end steel-thread smoke test for this iteration's whole
## camera-panning / collapsible-panel feature set (FEAT-005 through FEAT-012:
## GameCamera introduction, HexGridView world-coordinate draw refactor,
## set_origin_offset()'s camera re-implementation, the camera-aware hit-test
## refactor, middle-mouse drag-to-pan, keyboard WASD/arrow-key pan, and the
## shared collapsible-panel contract on InitiativeView/StatusPanelView/
## EventLogView). Exercises the iteration's own "Steel Thread" narrative
## (docs/iterations/iteration-W-panning-party-selection-panels.org, "* Steel
## Thread" section) verbatim, entry point to exit point, against the REAL,
## unmocked res://MainScene.tscn composition root — the same entry point
## project.godot's run/main_scene points at (ADR-002 pattern, mirroring
## tests/integration/test_steel_thread_prologue_encounter.gd's/
## test_steel_thread_scenario_boot_e2e.gd's own established "boot the real
## scene, never a hand-wired double" convention):
##
##   "A player opens the prologue. The hex map is centred as before. They
##   hold W and the map scrolls upward; they release and it stops. They
##   middle-mouse-drag and the map follows the cursor; releasing the mouse
##   button does not trigger a spurious hex-click. They enter combat, click
##   the InitiativeView collapse arrow, and the initiative list folds to a
##   title bar, expanding the visible battlefield. Clicking the arrow again
##   restores it."
##
## ...followed by one final left-click hex-select (not itself narrated in the
## iteration doc's steel thread, but required by this feature's own
## test_criteria as the "exit point assertion, no hex-click regression") to
## prove the pre-existing hex_clicked contract (FEAT-013/US-013, predating
## this iteration entirely) still fires correctly after every pan/drag/
## collapse interaction above has run against it.
##
## Following this codebase's established "call the handler directly"
## convention for headless-unreliable real engine input dispatch (see
## tests/hex_grid/test_hex_grid_view_pan.gd's own file-level doc, which this
## suite's input-simulation helpers below are copied from verbatim): keyboard
## pan is driven via the real, global Input singleton (GutInputSender, i.e.
## the `InputSender` class exposed on every GutTest) with HexGridView._process()
## called directly with an explicit delta, and middle-mouse-drag/left-click
## are driven via hand-built InputEvent instances passed directly to
## HexGridView._unhandled_input() — the SAME method the real engine's actual
## _unhandled_input() dispatch would call, fully deterministic in headless CI.
##
## No production code is modified for this feature (files_to_modify is empty
## in the feature spec) — every object driven below is the exact, unmodified,
## already-shipped production class this iteration's other features already
## cover with their own focused unit suites (test_hex_grid_view_pan.gd,
## test_main_scene_game_camera.gd, test_panel_anchor_collapse.gd,
## test_collapsible_panel.gd, etc.); this file's job is proving they compose
## correctly end-to-end through the ONE real, shipped MainScene.tscn entry
## point, in the real instantiated scene tree — no mocked/stubbed
## HexGridView, InitiativeView, or GameCamera anywhere on the path.
##
## test_criteria satisfied:
##   1. test_entry_point_prologue_hex_map_renders_centered_exactly_as_before_camera_refactor()
##   2. test_w_key_hold_pans_map_upward_per_frame_and_camera_stops_immediately_on_release()
##   3. test_middle_mouse_drag_pans_map_and_emits_no_hex_clicked()
##   4. test_initiative_view_collapse_toggle_folds_and_restores_panel_expanding_battlefield_during_combat()
##   5. test_full_steel_thread_pan_and_collapse_in_live_session_no_regression()
##      — the composite smoke test driving ALL of the above, in the SAME
##      narrated order, through ONE continuous live MainScene session,
##      culminating in the exit-point left-click regression check.
##   6. (implicit throughout) every assertion above drives the real,
##      instantiated res://MainScene.tscn scene tree — never a hand-wired or
##      mocked HexGridView/InitiativeView/GameCamera double.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")

const PROLOGUE_ENCOUNTER_ID: String = "prologue"

## Tolerance for floating-point pixel/position comparisons.
const EPSILON: float = 0.5

var _key_sender = null


## FEAT-009 (FR-007/ADR-002): seed CurrentGameState.data via
## NewGameFactory.create_prologue_state() before every boot -- explicit,
## rather than relying on MainScene's own never-initialized fallback -- and
## reset it afterward so this suite never leaks state into another test file
## sharing the same autoload singleton across the one GUT process. Mirrors
## tests/integration/test_steel_thread_scenario_boot_e2e.gd's own
## before_each()/after_each() exactly.
##
## Also sets up the InputSender used by the keyboard-pan (W-hold) assertions
## below, mirroring tests/hex_grid/test_hex_grid_view_pan.gd's own
## before_each()/after_each() pair -- released every test so no pressed key
## state leaks across tests (Input singleton state is process-global, not
## per-test).
func before_each() -> void:
	CurrentGameState.data = NewGameFactoryClass.create_prologue_state()
	_key_sender = InputSender.new(Input)
	_key_sender.set_auto_flush_input(true)


func after_each() -> void:
	if _key_sender != null:
		_key_sender.release_all()
		_key_sender = null
	CurrentGameState.data = GameStateDataClass.new()


## _boot_main_scene_with_seed(seed_value) -> Node -- boots the REAL
## res://MainScene.tscn composition root (the same entry point project.godot's
## run/main_scene points at) with a pinned `seed_override` so this suite's
## "Titus acts first" fixture assumption (prologue_encounter.tres' seed=42
## roll) is reproducible. Mirrors tests/integration/
## test_steel_thread_prologue_encounter.gd's/test_steel_thread_scenario_boot_e2e.gd's
## identically-named helper. Leaves MainScene in EXPLORATION mode (the
## "player opens the prologue" entry point) -- the pan/drag steps of the
## steel thread narrative happen BEFORE combat is ever entered.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene entry point) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	await get_tree().process_frame
	return instance


## _boot_main_scene_into_combat_with_seed(seed_value) -> Node -- boots exactly
## as _boot_main_scene_with_seed() above, then drives the REAL
## _on_combat_triggered() handoff (the same production entry point the real
## exploration-to-combat trigger uses) so InitiativeView becomes visible, per
## the steel thread narrative's "They enter combat" step. Mirrors
## tests/integration/test_steel_thread_prologue_encounter.gd's own
## _boot_main_scene() AutoReactionChooser swap as a defensive guard against a
## real, un-clickable reaction pop-up blocking this suite -- harmless/unused
## for this suite's own assertions, which never advance a turn.
func _boot_main_scene_into_combat_with_seed(seed_value: int):
	var instance = await _boot_main_scene_with_seed(seed_value)
	await instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	if instance.turn_controller != null and instance.reaction_window != null:
		instance.turn_controller.configure_reactions(instance.reaction_window, AutoReactionChooserClass.new("pass"))
	return instance


func _middle_mouse_button_event(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = pressed
	return event


func _left_mouse_button_event() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func _mouse_motion_event(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — entry point: prologue scene loads and the hex map renders
# centered exactly as before the camera refactor.
# ══════════════════════════════════════════════════════════════════════════

func test_entry_point_prologue_hex_map_renders_centered_exactly_as_before_camera_refactor() -> void:
	var instance = await _boot_main_scene_with_seed(42)

	var hex_grid_view = instance.hex_grid_view
	assert_not_null(hex_grid_view, "MainScene must expose a non-null hex_grid_view")
	if hex_grid_view == null:
		return

	# Mirrors tests/gut/test_viewport_centering.gd's own established
	# "no regression" invariant for the camera refactor: a non-zero centering
	# offset is still configured, and every token still renders at its pure
	# world-space pixel position (unshifted) -- exactly the pre-refactor
	# centered-rendering contract this iteration's design notes require be
	# preserved (the "centering seam").
	assert_ne(
		hex_grid_view.get_origin_offset(), Vector2.ZERO,
		"MainScene must still configure a non-zero centering offset on hex_grid_view at boot -- the hex map must render centered exactly as before the camera refactor"
	)

	var camera: Camera2D = instance.get_node_or_null("GameCamera")
	assert_not_null(camera, "MainScene must expose the GameCamera sibling of hex_grid_view (FEAT-005/US-001)")
	if camera != null:
		assert_true(camera.current, "GameCamera must be the active camera at boot")
		assert_false(camera.position_smoothing_enabled, "GameCamera must have position_smoothing_enabled == false")

	var boot_combatants: Array = instance._party + instance._enemies
	assert_true(boot_combatants.size() > 0, "fixture assumption: the prologue encounter must supply at least one combatant to check")
	for combatant in boot_combatants:
		var token = hex_grid_view.get_token(combatant.combatant_id)
		assert_not_null(token, "hex_grid_view must render a token for combatant_id=%s" % combatant.combatant_id)
		if token == null:
			continue
		var expected_position: Vector2 = hex_grid_view.axial_to_pixel(combatant.hex_coord)
		assert_almost_eq(
			token.position, expected_position, Vector2(EPSILON, EPSILON),
			"token %s must render at its pure world-space pixel position, unshifted -- the centered-rendering contract must be unchanged by the camera refactor" % combatant.combatant_id
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — holding W pans the map upward per-frame; _camera.position
# stops changing immediately on key release.
# ══════════════════════════════════════════════════════════════════════════

func test_w_key_hold_pans_map_upward_per_frame_and_camera_stops_immediately_on_release() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	var hex_grid_view = instance.hex_grid_view
	var camera: Camera2D = instance.get_node("GameCamera")

	var initial_position: Vector2 = camera.position

	_key_sender.key_down(KEY_W)
	hex_grid_view._process(0.1)
	var after_first_frame: Vector2 = camera.position
	assert_lt(
		after_first_frame.y, initial_position.y,
		"holding W must pan the camera UPWARD (decrease world-space y) on the very first frame it is held"
	)

	hex_grid_view._process(0.1)
	var after_second_frame: Vector2 = camera.position
	assert_lt(
		after_second_frame.y, after_first_frame.y,
		"W held across multiple frames must keep panning upward PER-FRAME, not just once"
	)

	_key_sender.key_up(KEY_W)
	hex_grid_view._process(0.1)
	var after_release: Vector2 = camera.position
	assert_eq(
		after_release, after_second_frame,
		"_camera.position must stop changing IMMEDIATELY on the very next frame after W is released"
	)

	# A further frame after release must still leave the camera untouched --
	# "stops" means stays stopped, not merely one quiet frame.
	hex_grid_view._process(0.1)
	assert_eq(
		camera.position, after_release,
		"_camera.position must remain stopped on subsequent frames after W release, not resume drifting"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — a middle-mouse drag pans the map and does not emit
# hex_clicked on release.
# ══════════════════════════════════════════════════════════════════════════

func test_middle_mouse_drag_pans_map_and_emits_no_hex_clicked() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	var hex_grid_view = instance.hex_grid_view
	var camera: Camera2D = instance.get_node("GameCamera")
	var initial_position: Vector2 = camera.position

	watch_signals(hex_grid_view)

	hex_grid_view._unhandled_input(_middle_mouse_button_event(true))
	assert_true(hex_grid_view._drag_panning, "a middle-mouse press must begin a drag-pan gesture")

	var relative := Vector2(42.0, -17.0)
	hex_grid_view._unhandled_input(_mouse_motion_event(relative))

	assert_almost_eq(
		camera.position, initial_position - relative, Vector2(EPSILON, EPSILON),
		"a middle-mouse drag motion must pan the camera opposite the drag direction (the map 'follows the cursor')"
	)

	hex_grid_view._unhandled_input(_middle_mouse_button_event(false))
	assert_false(hex_grid_view._drag_panning, "releasing the middle mouse button must end the drag-pan gesture")

	assert_signal_not_emitted(
		hex_grid_view, "hex_clicked",
		"no hex_clicked may be emitted for a middle-mouse drag gesture (press, motion, release) -- releasing the mouse button must not trigger a spurious hex-click"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — toggling InitiativeView's collapse arrow during a simulated
# combat state folds/restores the panel and correspondingly expands/
# contracts the battlefield viewport area.
# ══════════════════════════════════════════════════════════════════════════

func test_initiative_view_collapse_toggle_folds_and_restores_panel_expanding_battlefield_during_combat() -> void:
	var instance = await _boot_main_scene_into_combat_with_seed(42)

	var initiative_view = instance.initiative_view
	assert_not_null(initiative_view, "MainScene must expose a non-null initiative_view")
	if initiative_view == null:
		return
	assert_true(initiative_view.visible, "InitiativeView must become visible once combat begins (US-011's 'they enter combat' step)")
	assert_true(
		initiative_view.get_node("Content").visible,
		"InitiativeView must boot expanded (Content visible) -- collapsed state is never persisted, per the design notes"
	)

	var viewport_size: Vector2 = instance.get_viewport().get_visible_rect().size
	var original_position: Vector2 = initiative_view.position
	var original_size: Vector2 = initiative_view.size
	# The "battlefield viewport area" reclaimed from the panel: since
	# HexGridView itself is always full-screen (the panels are a CanvasLayer
	# overlay, ADR-002), the visible/unobstructed battlefield area a panel's
	# footprint currently occupies is exactly (viewport height - panel
	# height) -- this grows precisely as the panel's own height shrinks.
	var battlefield_area_before: float = viewport_size.y - original_size.y

	initiative_view.toggle_collapsed()

	assert_false(
		initiative_view.get_node("Content").visible,
		"toggling collapse must hide $Content, folding InitiativeView down to just its title bar"
	)
	assert_lt(initiative_view.size.y, original_size.y, "collapsing InitiativeView must shrink its on-screen footprint")
	assert_eq(initiative_view.position.x, original_position.x, "collapse must never move the panel horizontally")

	var battlefield_area_after_collapse: float = viewport_size.y - initiative_view.size.y
	assert_gt(
		battlefield_area_after_collapse, battlefield_area_before,
		"folding InitiativeView to its header must EXPAND the reclaimed battlefield viewport area"
	)

	initiative_view.toggle_collapsed()

	assert_true(
		initiative_view.get_node("Content").visible,
		"toggling collapse a second time must restore $Content visibility"
	)
	assert_eq(initiative_view.position, original_position, "restoring InitiativeView must return it to its exact original position")
	assert_eq(initiative_view.size, original_size, "restoring InitiativeView must return it to its exact original size")

	var battlefield_area_after_restore: float = viewport_size.y - initiative_view.size.y
	assert_almost_eq(
		battlefield_area_after_restore, battlefield_area_before, 0.01,
		"restoring InitiativeView must CONTRACT the battlefield viewport area back to its exact pre-collapse value"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 & 6 — the composite steel-thread smoke test: entry point to
# exit point, one continuous live MainScene session, no mocked collaborator
# anywhere on the path.
# ══════════════════════════════════════════════════════════════════════════

func test_full_steel_thread_pan_and_collapse_in_live_session_no_regression() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	var hex_grid_view = instance.hex_grid_view
	var camera: Camera2D = instance.get_node("GameCamera")

	# ── Entry point: "A player opens the prologue. The hex map is centred as
	# before." ──────────────────────────────────────────────────────────────
	assert_ne(
		hex_grid_view.get_origin_offset(), Vector2.ZERO,
		"entry point: the hex map must still be configured centered exactly as before the camera refactor"
	)
	var boot_combatants: Array = instance._party + instance._enemies
	assert_true(boot_combatants.size() > 0, "fixture assumption: the prologue encounter must supply at least one combatant")
	for combatant in boot_combatants:
		var token = hex_grid_view.get_token(combatant.combatant_id)
		assert_not_null(token, "entry point: hex_grid_view must render a token for every prologue combatant")

	# ── "They hold W and the map scrolls upward; they release and it
	# stops." ────────────────────────────────────────────────────────────────
	var pre_pan_position: Vector2 = camera.position
	_key_sender.key_down(KEY_W)
	hex_grid_view._process(0.1)
	var mid_pan_position: Vector2 = camera.position
	assert_lt(mid_pan_position.y, pre_pan_position.y, "holding W must pan the map upward")

	_key_sender.key_up(KEY_W)
	hex_grid_view._process(0.1)
	assert_eq(camera.position, mid_pan_position, "releasing W must stop the pan immediately")

	# ── "They middle-mouse-drag and the map follows the cursor; releasing
	# the mouse button does not trigger a spurious hex-click." ─────────────
	watch_signals(hex_grid_view)
	var pre_drag_position: Vector2 = camera.position
	hex_grid_view._unhandled_input(_middle_mouse_button_event(true))
	var drag_relative := Vector2(30.0, 15.0)
	hex_grid_view._unhandled_input(_mouse_motion_event(drag_relative))
	assert_almost_eq(
		camera.position, pre_drag_position - drag_relative, Vector2(EPSILON, EPSILON),
		"middle-mouse drag motion must pan the camera opposite the drag direction"
	)
	hex_grid_view._unhandled_input(_middle_mouse_button_event(false))
	assert_false(hex_grid_view._drag_panning, "drag-pan gesture must have fully ended before combat begins")
	assert_signal_not_emitted(
		hex_grid_view, "hex_clicked",
		"releasing the middle-mouse drag must not have triggered a spurious hex_clicked"
	)

	# ── "They enter combat, click the InitiativeView collapse arrow, and the
	# initiative list folds to a title bar, expanding the visible
	# battlefield. Clicking the arrow again restores it." ───────────────────
	await instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	if instance.turn_controller != null and instance.reaction_window != null:
		instance.turn_controller.configure_reactions(instance.reaction_window, AutoReactionChooserClass.new("pass"))

	var initiative_view = instance.initiative_view
	assert_not_null(initiative_view, "MainScene must expose a non-null initiative_view once combat begins")
	assert_true(initiative_view.visible, "InitiativeView must become visible once combat begins")

	var viewport_size: Vector2 = instance.get_viewport().get_visible_rect().size
	var original_panel_size: Vector2 = initiative_view.size

	initiative_view.toggle_collapsed()
	assert_false(initiative_view.get_node("Content").visible, "the collapse arrow must fold the initiative list to just its title bar")
	assert_lt(initiative_view.size.y, original_panel_size.y, "folding the panel must shrink its footprint")
	assert_gt(
		viewport_size.y - initiative_view.size.y, viewport_size.y - original_panel_size.y,
		"folding InitiativeView must expand the visible battlefield viewport area"
	)

	initiative_view.toggle_collapsed()
	assert_true(initiative_view.get_node("Content").visible, "clicking the arrow again must restore the initiative list")
	assert_eq(initiative_view.size, original_panel_size, "restoring the panel must return it to its exact original size")

	# ── Exit point (no regression): a left-click hex-select still emits
	# hex_clicked with the correct HexCoord after every interaction above. ──
	# Explicitly resets the camera to a known baseline (the SAME public
	# set_origin_offset() contract every other consumer/test in this codebase
	# already relies on, ADR-003) so this final assertion pins a concrete,
	# reproducible expected HexCoord rather than depending on the exact
	# cumulative pixel drift from the pan/drag steps above -- mirrors
	# tests/hex_grid/test_hex_grid_view_pan.gd's own established
	# "default camera position resolves world (0, 0)" sanity convention.
	hex_grid_view.set_origin_offset(Vector2.ZERO)
	watch_signals(hex_grid_view)
	hex_grid_view._unhandled_input(_left_mouse_button_event())

	assert_signal_emitted_with_parameters(
		hex_grid_view, "hex_clicked", [HexCoordClass.new(0, 0)],
		"exit point: a left-click hex-select after all pan/drag/collapse interactions must still emit hex_clicked with the correct HexCoord -- no regression"
	)
