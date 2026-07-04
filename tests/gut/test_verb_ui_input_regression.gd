extends GutTest

## REPRO for the reported bug: "Stride only lets you pick melee-range hexes."
## test_stride_layer2_integration.gd asserts the SelectionOverlay's INTERNAL
## get_highlighted_hexes() is the full Speed-bounded set (and passes) -- but it
## never checks what HexGridView ACTUALLY displays (== what the player sees and
## can click). This asserts the real displayed grid set spans the full Speed
## range after entering Stride Layer 2.

const MAIN_SCENE_PATH := "res://MainScene.tscn"
const HexMathClass = preload("res://core/geometry/hex_math.gd")
const MovementClass = preload("res://core/rules/movement.gd")


func _boot(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


func test_stride_mode_displays_full_speed_range_on_the_grid() -> void:
	var instance = _boot(42)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available("STRIDE"), "fixture: STRIDE available at boot")
	var actor: Dictionary = instance.round_session.current_actor()
	var actor_hex = actor.get("hex_coord", null)
	assert_not_null(actor_hex, "fixture: active actor carries a hex_coord")

	# The overlay's OWN computed set (what the passing test checks):
	var overlay_expected: Array = instance.movement_input_controller.get_selectable_stride_hexes()
	var overlay_max := 0
	for h in overlay_expected:
		overlay_max = max(overlay_max, HexMathClass.hex_distance(actor_hex, h))
	gut.p("overlay stride set: %d hexes, max distance %d" % [overlay_expected.size(), overlay_max])

	instance.verb_bar_view.press("STRIDE")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIDE", "should be in STRIDE Layer 2")

	# What HexGridView ACTUALLY displays == what the player sees & can click:
	var displayed: Array = instance.hex_grid_view._selectable_hexes
	var displayed_max := 0
	for h in displayed:
		displayed_max = max(displayed_max, HexMathClass.hex_distance(actor_hex, h))
	gut.p("DISPLAYED grid set: %d hexes, max distance %d" % [displayed.size(), displayed_max])

	assert_gt(
		displayed_max, 1,
		"Stride must DISPLAY hexes beyond melee range (distance > 1) on the grid; got max distance %d among %d displayed hexes" % [displayed_max, displayed.size()]
	)
	assert_eq(
		displayed.size(), overlay_expected.size(),
		"the grid must display EXACTLY the overlay's Stride set (%d), not a melee-only subset (%d)" % [overlay_expected.size(), displayed.size()]
	)


## Does clicking a FAR (distance>1) highlighted Stride hex actually resolve a
## move? Emits hex_grid_view.hex_clicked (the SAME signal the overlay subscribes
## to) with a far candidate and asserts the token repositions there.
func test_clicking_a_far_stride_hex_resolves_the_move() -> void:
	var instance = _boot(42)
	await get_tree().process_frame
	var actor: Dictionary = instance.round_session.current_actor()
	var actor_id: String = actor.get("combatant_id", "")
	var actor_hex = actor.get("hex_coord", null)

	instance.verb_bar_view.press("STRIDE")
	var candidates: Array = instance.selection_overlay.get_highlighted_hexes()

	# pick the FARTHEST candidate (distance>1 = beyond melee)
	var far = null
	var far_d := 1
	for h in candidates:
		var d = HexMathClass.hex_distance(actor_hex, h)
		if d > far_d:
			far_d = d
			far = h
	assert_not_null(far, "fixture: at least one Stride candidate beyond melee range exists")
	gut.p("clicking far stride hex (%d,%d) at distance %d" % [far.q, far.r, far_d])

	var token_before = instance.hex_grid_view.get_token(actor_id)
	var pos_before = token_before.hex_coord if token_before != null else null

	# Simulate the click landing on that far hex (same signal the overlay listens to)
	instance.hex_grid_view.hex_clicked.emit(far)
	await get_tree().process_frame

	var token_after = instance.hex_grid_view.get_token(actor_id)
	var pos_after = token_after.hex_coord if token_after != null else null
	assert_not_null(pos_after, "actor token must still exist after the Stride")
	assert_true(pos_after.equals(far), "clicking a far highlighted Stride hex must MOVE the token to it (expected %d,%d, got %d,%d)" % [far.q, far.r, pos_after.q, pos_after.r])


## BUG 1 fix: the read-only display panels overlap the battlefield, so they must
## be transparent to mouse input (MOUSE_FILTER_IGNORE) or they swallow clicks on
## hexes drawn beneath them (only the clear-center hexes were selectable before).
func test_display_panels_are_mouse_transparent() -> void:
	var instance = _boot(42)
	await get_tree().process_frame
	for panel_name in ["status_panel_view", "event_log_view", "initiative_view"]:
		var panel = instance.get(panel_name)
		assert_not_null(panel, "MainScene must wire %s" % panel_name)
		assert_eq(
			panel.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"%s overlaps the battlefield and must NOT consume mouse clicks (MOUSE_FILTER_IGNORE)" % panel_name
		)


## BUG 2 fix: End Turn is a single verb-bar button labelled "End Turn"; the old
## standalone EndTurnControl button is hidden (kept only as the logic delegate).
func test_single_labelled_end_turn() -> void:
	var instance = _boot(42)
	await get_tree().process_frame
	assert_false(instance.end_turn_control.visible, "the legacy EndTurnControl button must be hidden (End Turn is now a verb)")
	# The verb-bar button for END_TURN must read "End Turn", not the raw id.
	var verb_bar = instance.verb_bar_view
	var btn = verb_bar.get_node_or_null("ButtonsContainer/Verb_END_TURN")
	assert_not_null(btn, "verb bar must render an END_TURN button")
	assert_eq(btn.text, "End Turn", "the End Turn verb button must show a human-readable label, not 'END_TURN'")
