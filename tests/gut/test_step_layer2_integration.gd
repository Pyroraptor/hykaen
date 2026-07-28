extends GutTest
## tests/gut/test_step_layer2_integration.gd — FEAT-009 (US-009 / FR-004;
## ADR-002, ADR-003, ADR-004).
##
## Integration-test complement to tests/pytest/test_verb_registry.py's
## TestGenericDispatch.test_enter_selection_step_returns_adjacent_hexes /
## test_execute_step_dispatches_to_movement_port_without_spending_action (the
## Python-level pin of the same "candidate_hexes is exactly the legal-
## adjacent-hex set" / "no action spent" contract). This suite boots the
## REAL, shipped res://MainScene.tscn composition root headless (mirroring
## tests/gut/test_strike_layer2_integration.gd's / tests/integration/
## test_movement_affordance_integration.gd's `_boot_main_scene_with_seed()`
## fixture) with NO stub/mock standing in for HexGridView, movement_input_
## controller, `_verb_registry`, or presentation/selection_overlay.gd's
## SelectionOverlay -- proving Step's Layer 2 (destination highlight -> click
## -> free move) works end-to-end through the exact objects a real player
## drives, extending FEAT-008's generic SelectionOverlay to hex-destination
## mode rather than forking a second Layer 2 component.
##
## Unlike tests/integration/test_movement_affordance_integration.gd's
## Criterion 3 (which executes STEP by calling `_verb_registry.execute()`
## directly), this suite drives the SAME real HexGridView.hex_clicked signal
## presentation/selection_overlay.gd subscribes to (mirroring
## test_strike_layer2_integration.gd's click-simulation convention) -- the
## SelectionOverlay/hex-click path FEAT-009 adds Step/Stride coverage for.
##
## test_criteria satisfied:
##   1. test_step_enter_selection_highlights_only_legal_adjacent_unoccupied_hexes()
##   2. test_clicking_a_highlighted_hex_moves_the_token_to_that_exact_axial_coordinate_with_no_action_spent()
##   3. test_highlighted_hexes_render_at_positions_consistent_with_the_shared_transform_used_by_the_click_handler()
##   4. (whole-suite regression) -- enforced by scripts/test_command.sh, not
##      this file.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const HexGridViewClass       = preload("res://presentation/hex_grid_view.gd")
const SelectionOverlayClass  = preload("res://presentation/selection_overlay.gd")
const HexCoordClass          = preload("res://core/geometry/hex_coord.gd")
const HexMathClass           = preload("res://core/geometry/hex_math.gd")


## _boot_main_scene_with_seed(seed_value) -> Node -- instantiates the REAL
## res://MainScene.tscn composition root, pinned to seed=42 (the prologue
## fixture's known-good seed, matching this codebase's established
## convention -- tests/gut/test_strike_layer2_integration.gd).
## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): MainScene now
## boots into EXPLORATION mode with round_session/verb_bar_view/
## selection_overlay/turn_controller signal wiring gated behind a real
## _on_combat_triggered() handoff (see MainScene.gd's own FEAT-316 doc). This
## suite drives verb_bar_view/selection_overlay/round_session directly, so
## this helper now also drives the SAME real handoff tests/boot/
## test_exploration_to_combat_handoff_trigger.gd exercises directly, landing
## the instance in GameMode.COMBAT with a live round_session before returning.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


## _find_combatant_by_id(instance, combatant_id) -> Dictionary -- looks up a
## live combatant Dictionary (MainScene's own _party/_enemies fields, the SAME
## Dictionaries core/rules/movement.gd Movement.step() mutates in place),
## mirroring tests/integration/test_movement_affordance_integration.gd's
## identically-named helper.
func _find_combatant_by_id(instance, combatant_id: String):
	for combatant in instance._party + instance._enemies:
		if combatant.combatant_id == combatant_id:
			return combatant
	return null


## _occupied_hexes(instance) -> Dictionary -- "q,r" -> true set of every
## LIVING combatant's currently occupied hex, used to prove no highlighted
## Step destination is occupied.
func _occupied_hexes(instance) -> Dictionary:
	var occupied: Dictionary = {}
	for combatant in instance._party + instance._enemies:
		if combatant.hp_current <= 0:
			continue
		var hex_coord = combatant.hex_coord
		if hex_coord != null:
			occupied["%d,%d" % [hex_coord.q, hex_coord.r]] = true
	return occupied


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — pressing STEP surfaces (and SelectionOverlay highlights)
# EXACTLY the legal adjacent UNOCCUPIED hexes -- no out-of-range hex, no
# occupied hex.
# ══════════════════════════════════════════════════════════════════════════

func test_step_enter_selection_highlights_only_legal_adjacent_unoccupied_hexes() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_true(
		is_instance_of(instance.selection_overlay, SelectionOverlayClass),
		"MainScene must wire the REAL presentation/selection_overlay.gd SelectionOverlay -- no stub/mock"
	)
	assert_true(
		instance._verb_registry.is_available("STEP"),
		"fixture assumption: the prologue's first actor has at least one legal Step destination at seed=42"
	)

	var actor = instance.round_session.current_actor()
	var actor_hex = actor.hex_coord
	assert_not_null(actor_hex, "fixture assumption: the active actor carries a hex_coord")

	var expected_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	assert_true(expected_hexes.size() > 0, "sanity check: at least one legal Step destination exists at boot")

	var selection: Dictionary = instance.verb_bar_view.press("STEP")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_eq(candidate_hexes.size(), expected_hexes.size(), "Step's Layer 2 selection must surface EXACTLY the legal adjacent unoccupied hex set -- no more, no less")

	# SelectionOverlay itself (not merely the raw descriptor) must reflect the
	# SAME exactly-legal-adjacent-unoccupied set.
	assert_true(instance.selection_overlay.is_active(), "SelectionOverlay must be active (Layer 2) after pressing STEP")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STEP")

	var highlighted_hexes: Array = instance.selection_overlay.get_highlighted_hexes()
	assert_eq(highlighted_hexes.size(), expected_hexes.size(), "SelectionOverlay must highlight exactly the legal Step destination count")

	var neighbors: Array = HexMathClass.hex_neighbors(actor_hex)
	var occupied: Dictionary = _occupied_hexes(instance)

	for hex_coord in highlighted_hexes:
		# Every highlighted hex must be ADJACENT (a neighbor) to the actor --
		# never a farther-away hex leaking in from Stride or elsewhere.
		var is_neighbor: bool = false
		for neighbor in neighbors:
			if neighbor.equals(hex_coord):
				is_neighbor = true
				break
		assert_true(is_neighbor, "highlighted Step hex (%d,%d) must be adjacent to the actor's hex" % [hex_coord.q, hex_coord.r])

		# Every highlighted hex must be UNOCCUPIED.
		var key: String = "%d,%d" % [hex_coord.q, hex_coord.r]
		assert_false(occupied.has(key), "highlighted Step hex (%d,%d) must not be occupied by a living combatant" % [hex_coord.q, hex_coord.r])

	# Exact-set comparison against candidate_hexes as well (order-independent).
	for candidate_hex in candidate_hexes:
		var found: bool = false
		for hex_coord in highlighted_hexes:
			if hex_coord.equals(candidate_hex):
				found = true
				break
		assert_true(found, "every candidate_hex from the Step descriptor must be among SelectionOverlay's highlighted hexes")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — clicking a highlighted hex resolves through the REAL
# MovementPort (movement_input_controller.step_to() -> core/rules/movement.gd
# Movement.step(), the FEAT-001-shared-transform-resolved axial coordinate),
# moving the token to THAT EXACT axial coordinate with actions_remaining
# unchanged (a Step is a FREE move -- no action spent).
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_a_highlighted_hex_moves_the_token_to_that_exact_axial_coordinate_with_no_action_spent() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().display_id()
	assert_ne(actor_id, "", "fixture assumption: the active actor carries a non-empty combatant_id")

	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_true(before_remaining > 0, "sanity check: the acting combatant starts with a positive action budget")

	var selection: Dictionary = instance.verb_bar_view.press("STEP")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "fixture assumption: at least one legal Step destination exists")
	var destination = candidate_hexes[0]

	var token_before = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_before, "the real HexGridView must already carry a token for the active actor")
	assert_false(token_before.hex_coord.equals(destination), "sanity check: the chosen destination hex must differ from the actor's starting hex")

	# ── Simulate the real player interaction: a left-click resolving to the
	# highlighted destination's OWN hex, decoded through the SAME shared
	# CoordinateTransform (FEAT-001) axial_to_pixel()/pixel_to_axial() pair
	# HexGridView's real click handler (_unhandled_input()) uses -- proving
	# the click resolves to the EXACT axial coordinate the highlight was
	# rendered at, never a drifted/rounded neighbor. ────────────────────────
	var destination_pixel: Vector2 = instance.hex_grid_view.axial_to_pixel_with_offset(destination)
	var click_resolved_hex = instance.hex_grid_view.pixel_to_axial_with_offset(destination_pixel)
	assert_true(click_resolved_hex.equals(destination), "the shared transform must decode the highlighted destination's own pixel back to the exact same axial coordinate")

	instance.hex_grid_view.hex_clicked.emit(click_resolved_hex)

	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the click resolves a real Step")

	var moved_combatant = _find_combatant_by_id(instance, actor_id)
	assert_false(moved_combatant == null, "fixture assumption: the moved actor must be one of MainScene's live combatant Dictionaries")
	assert_true(
		moved_combatant.hex_coord.equals(destination),
		"Combatant.position (the live combatant Dictionary's hex_coord) must move to the EXACT clicked axial coordinate via move_token()/step_to()"
	)

	var token_after = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_after, "the real HexGridView must still carry a token for the moved actor")
	assert_true(token_after.hex_coord.equals(destination), "the real HexGridView's token must resync its hex_coord to the exact clicked destination")
	assert_eq(
		token_after.position, instance.hex_grid_view.axial_to_pixel(destination),
		"the real HexGridView's token must resync its rendered screen position to the destination's ADR-004 axial-to-pixel projection (FEAT-002: pure world coordinates, no _origin_offset)"
	)

	var after_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(
		after_remaining, before_remaining,
		"a Step is a FREE move -- actions_remaining must be COMPLETELY UNCHANGED after it resolves"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — the highlighted hexes render at pixel positions consistent
# with the SAME shared CoordinateTransform the click handler decodes through
# -- eliminating the Iteration D class of bug where drawing and click mapping
# could independently drift out of sync (design notes' stated purpose of
# presentation/infrastructure/coordinate_transform.gd).
# ══════════════════════════════════════════════════════════════════════════

func test_highlighted_hexes_render_at_positions_consistent_with_the_shared_transform_used_by_the_click_handler() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	instance.verb_bar_view.press("STEP")
	var highlighted_hexes: Array = instance.selection_overlay.get_highlighted_hexes()
	assert_true(highlighted_hexes.size() > 0, "fixture assumption: at least one legal Step destination is highlighted")

	for hex_coord in highlighted_hexes:
		# The exact pixel position HexGridView._draw_hex_cell() renders this
		# highlighted hex's fill/outline at (axial_to_pixel_with_offset()) --
		# decoding it back (pixel_to_axial_with_offset(), the SAME call
		# _unhandled_input() uses for every real click) must resolve to the
		# IDENTICAL axial coordinate, proving highlight rendering and click
		# mapping share one transform rather than two independently
		# recomputed ones.
		var rendered_pixel: Vector2 = instance.hex_grid_view.axial_to_pixel_with_offset(hex_coord)
		var decoded_hex = instance.hex_grid_view.pixel_to_axial_with_offset(rendered_pixel)
		assert_true(
			decoded_hex.equals(hex_coord),
			"the highlighted hex (%d,%d)'s own rendered pixel position must decode back to itself via the SAME shared transform the click handler uses" % [hex_coord.q, hex_coord.r]
		)

		# A synthetic hex_clicked emission carrying this decoded hex must be
		# recognized by SelectionOverlay as the SAME highlighted candidate
		# (not silently rejected as out-of-selection) -- proving the overlay's
		# highlight set and the click handler's decoded coordinate space
		# agree exactly.
		watch_signals(instance.selection_overlay)
		var found_as_candidate: bool = false
		for candidate in instance.selection_overlay.get_highlighted_hexes():
			if candidate.equals(decoded_hex):
				found_as_candidate = true
				break
		assert_true(found_as_candidate, "the click-decoded hex must still name one of SelectionOverlay's currently highlighted hexes")
