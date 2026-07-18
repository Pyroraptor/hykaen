extends GutTest
## tests/gut/test_stride_layer2_integration.gd — FEAT-010 (US-010 / FR-005;
## ADR-002, ADR-003, ADR-004).
##
## Integration-test complement to tests/pytest/test_verb_registry.py's
## TestGenericDispatch.test_enter_selection_stride_returns_stride_hexes /
## test_execute_stride_dispatches_to_movement_port_spending_action (the
## Python-level pin of the same "candidate_hexes is exactly the legal
## Speed-bounded, unoccupied hex set" / "one action spent" contract). This
## suite boots the REAL, shipped res://MainScene.tscn composition root
## headless (mirroring tests/gut/test_step_layer2_integration.gd's /
## tests/gut/test_strike_layer2_integration.gd's `_boot_main_scene_with_seed()`
## fixture) with NO stub/mock standing in for HexGridView,
## movement_input_controller, `_verb_registry`, or presentation/
## selection_overlay.gd's SelectionOverlay -- proving Stride's Layer 2
## (destination highlight -> click -> action-spending move) works end-to-end
## through the exact objects a real player drives, extending FEAT-009's
## generic SelectionOverlay to Stride's action-spending mode rather than
## forking a second Layer 2 component (presentation/selection_overlay.gd is
## driven purely by whichever candidate_hexes/candidate_targets the active
## verb's descriptor populates -- it required NO changes of its own for
## Stride, see that file's file-level doc).
##
## Unlike tests/integration/test_movement_affordance_integration.gd's
## Criterion 3 (which executes STRIDE by calling `_verb_registry.execute()`
## directly), this suite drives the SAME real HexGridView.hex_clicked signal
## presentation/selection_overlay.gd subscribes to (mirroring
## test_strike_layer2_integration.gd's / test_step_layer2_integration.gd's
## click-simulation convention) -- the SelectionOverlay/hex-click path
## FEAT-009 established for Step and this feature extends to Stride.
##
## test_criteria satisfied:
##   1. test_stride_enter_selection_highlights_only_legal_speed_bounded_unoccupied_hexes()
##      -- "Stride enter_selection() returns a SelectionDescriptor bounded by
##      Speed and excluding occupied hexes."
##   2. test_clicking_a_highlighted_destination_moves_the_token_and_spends_one_action()
##      -- "selecting Stride then clicking a highlighted destination moves the
##      token AND decrements actions_remaining/increments actions_spent."
##   3. test_a_hex_beyond_speed_is_never_offered_as_a_candidate_and_a_click_there_produces_no_resolution()
##      -- "attempting to select a hex beyond Speed is not offered as a
##      candidate."
##   4. (whole-suite regression) -- enforced by scripts/test_command.sh, not
##      this file.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const HexGridViewClass       = preload("res://presentation/hex_grid_view.gd")
const SelectionOverlayClass  = preload("res://presentation/selection_overlay.gd")
const HexCoordClass          = preload("res://core/geometry/hex_coord.gd")
const HexMathClass           = preload("res://core/geometry/hex_math.gd")
const MovementClass          = preload("res://core/rules/movement.gd")


## _boot_main_scene_with_seed(seed_value) -> Node -- instantiates the REAL
## res://MainScene.tscn composition root, pinned to seed=42 (the prologue
## fixture's known-good seed, matching this codebase's established
## convention -- tests/gut/test_strike_layer2_integration.gd /
## tests/gut/test_step_layer2_integration.gd).
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


## _find_combatant_by_id(instance, combatant_id) -> Dictionary -- looks up a
## live combatant Dictionary (MainScene's own _party/_enemies fields, the SAME
## Dictionaries core/rules/movement.gd Movement.stride() mutates in place),
## mirroring tests/gut/test_step_layer2_integration.gd's identically-named
## helper.
func _find_combatant_by_id(instance, combatant_id: String):
	for combatant in instance._party + instance._enemies:
		if combatant.combatant_id == combatant_id:
			return combatant
	return null


## _occupied_hexes(instance) -> Dictionary -- "q,r" -> true set of every
## LIVING combatant's currently occupied hex, used to prove no highlighted
## Stride destination is occupied.
func _occupied_hexes(instance) -> Dictionary:
	var occupied: Dictionary = {}
	for combatant in instance._party + instance._enemies:
		if combatant.hp_current <= 0:
			continue
		var hex_coord = combatant.hex_coord
		if hex_coord != null:
			occupied["%d,%d" % [hex_coord.q, hex_coord.r]] = true
	return occupied


## _far_beyond_speed_hex(instance, actor_hex) -> HexCoord -- a hex strictly
## FARTHER than Movement.DEFAULT_SPEED from `actor_hex`, and not occupied by
## any living combatant -- used to prove a beyond-Speed hex is never offered
## as a candidate and a click there resolves nothing.
func _far_beyond_speed_hex(instance, actor_hex):
	var occupied: Dictionary = _occupied_hexes(instance)
	var far_q: int = actor_hex.q + MovementClass.DEFAULT_SPEED + 5
	var far_r: int = actor_hex.r + MovementClass.DEFAULT_SPEED + 5
	var candidate = HexCoordClass.new(far_q, far_r)
	if occupied.has("%d,%d" % [candidate.q, candidate.r]):
		candidate = HexCoordClass.new(far_q + 1, far_r + 1)
	assert_true(
		HexMathClass.hex_distance(actor_hex, candidate) > MovementClass.DEFAULT_SPEED,
		"test setup: the constructed far hex must actually exceed Speed"
	)
	return candidate


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — pressing STRIDE surfaces (and SelectionOverlay highlights)
# EXACTLY the legal, Speed-bounded, UNOCCUPIED hexes -- no out-of-Speed hex,
# no occupied hex.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_enter_selection_highlights_only_legal_speed_bounded_unoccupied_hexes() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_true(
		is_instance_of(instance.selection_overlay, SelectionOverlayClass),
		"MainScene must wire the REAL presentation/selection_overlay.gd SelectionOverlay -- no stub/mock"
	)
	assert_true(
		instance._verb_registry.is_available("STRIDE"),
		"fixture assumption: the prologue's first actor has at least one legal Stride destination and a positive action budget at seed=42"
	)

	var actor: Dictionary = instance.round_session.current_actor()
	var actor_hex = actor.get("hex_coord", null)
	assert_not_null(actor_hex, "fixture assumption: the active actor carries a hex_coord")

	var expected_hexes: Array = instance.movement_input_controller.get_selectable_stride_hexes()
	assert_true(expected_hexes.size() > 0, "sanity check: at least one legal Stride destination exists at boot")

	var selection: Dictionary = instance.verb_bar_view.press("STRIDE")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_eq(candidate_hexes.size(), expected_hexes.size(), "Stride's Layer 2 selection must surface EXACTLY the legal Speed-bounded unoccupied hex set -- no more, no less")

	# SelectionOverlay itself (not merely the raw descriptor) must reflect the
	# SAME exactly-legal-Speed-bounded-unoccupied set.
	assert_true(instance.selection_overlay.is_active(), "SelectionOverlay must be active (Layer 2) after pressing STRIDE")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIDE")

	var highlighted_hexes: Array = instance.selection_overlay.get_highlighted_hexes()
	assert_eq(highlighted_hexes.size(), expected_hexes.size(), "SelectionOverlay must highlight exactly the legal Stride destination count")

	var occupied: Dictionary = _occupied_hexes(instance)

	for hex_coord in highlighted_hexes:
		# Every highlighted hex must be within Speed of the actor -- never a
		# farther-away hex.
		assert_true(
			HexMathClass.hex_distance(actor_hex, hex_coord) <= MovementClass.DEFAULT_SPEED,
			"highlighted Stride hex (%d,%d) must be within Speed (%d) of the actor's hex" % [hex_coord.q, hex_coord.r, MovementClass.DEFAULT_SPEED]
		)

		# Every highlighted hex must be UNOCCUPIED.
		var key: String = "%d,%d" % [hex_coord.q, hex_coord.r]
		assert_false(occupied.has(key), "highlighted Stride hex (%d,%d) must not be occupied by a living combatant" % [hex_coord.q, hex_coord.r])

	# Exact-set comparison against candidate_hexes as well (order-independent).
	for candidate_hex in candidate_hexes:
		var found: bool = false
		for hex_coord in highlighted_hexes:
			if hex_coord.equals(candidate_hex):
				found = true
				break
		assert_true(found, "every candidate_hex from the Stride descriptor must be among SelectionOverlay's highlighted hexes")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — clicking a highlighted hex resolves through the REAL
# MovementPort (movement_input_controller.stride_to() -> core/rules/
# movement.gd Movement.stride(), the FEAT-001-shared-transform-resolved axial
# coordinate), moving the token to THAT EXACT axial coordinate AND spending
# exactly one action from the acting combatant's LIVE ActionEconomy (a
# Stride is NOT a free move -- unlike Step).
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_a_highlighted_destination_moves_the_token_and_spends_one_action() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	assert_ne(actor_id, "", "fixture assumption: the active actor carries a non-empty combatant_id")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the acting combatant carries a live ActionEconomy")

	var before_remaining: int = action_economy.get_remaining()
	assert_true(before_remaining > 0, "sanity check: the acting combatant starts with a positive action budget")
	var before_spent: bool = action_economy.is_spent()

	var selection: Dictionary = instance.verb_bar_view.press("STRIDE")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "fixture assumption: at least one legal Stride destination exists")
	var destination = candidate_hexes[0]

	var token_before = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_before, "the real HexGridView must already carry a token for the active actor")
	assert_false(token_before.hex_coord.equals(destination), "sanity check: the chosen destination hex must differ from the actor's starting hex")

	# Simulate the real player interaction: a left-click resolving to the
	# highlighted destination's OWN hex, decoded through the SAME shared
	# CoordinateTransform (FEAT-001) axial_to_pixel()/pixel_to_axial() pair
	# HexGridView's real click handler (_unhandled_input()) uses -- proving
	# the click resolves to the EXACT axial coordinate the highlight was
	# rendered at, never a drifted/rounded neighbor. ────────────────────────
	var destination_pixel: Vector2 = instance.hex_grid_view.axial_to_pixel_with_offset(destination)
	var click_resolved_hex = instance.hex_grid_view.pixel_to_axial_with_offset(destination_pixel)
	assert_true(click_resolved_hex.equals(destination), "the shared transform must decode the highlighted destination's own pixel back to the exact same axial coordinate")

	instance.hex_grid_view.hex_clicked.emit(click_resolved_hex)

	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the click resolves a real Stride")

	var moved_combatant = _find_combatant_by_id(instance, actor_id)
	assert_false(moved_combatant == null, "fixture assumption: the moved actor must be one of MainScene's live combatant Dictionaries")
	assert_true(
		moved_combatant.hex_coord.equals(destination),
		"Combatant.position (the live combatant Dictionary's hex_coord) must move to the EXACT clicked axial coordinate via move_token()/stride_to()"
	)

	var token_after = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_after, "the real HexGridView must still carry a token for the moved actor")
	assert_true(token_after.hex_coord.equals(destination), "the real HexGridView's token must resync its hex_coord to the exact clicked destination")
	assert_eq(
		token_after.position, instance.hex_grid_view.axial_to_pixel_with_offset(destination),
		"the real HexGridView's token must resync its rendered screen position to the destination's ADR-004 axial-to-pixel projection"
	)

	# A Stride SPENDS exactly one action from the SAME live ActionEconomy
	# instance movement_input_controller.stride_to() was configured with --
	# unlike a Step, which is completely free.
	assert_eq(
		action_economy.get_remaining(), before_remaining - 1,
		"a Stride must decrement actions_remaining by EXACTLY 1 -- it is not a free move like Step"
	)
	if before_remaining - 1 <= 0:
		assert_true(action_economy.is_spent(), "the acting combatant's action budget must report spent once it reaches zero after the Stride")
	else:
		assert_eq(action_economy.is_spent(), before_spent, "the acting combatant's action budget must not be reported spent while actions remain")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — a hex beyond Speed is NEVER offered as a Stride candidate,
# and a synthetic click there produces NO resolution at all: no token move,
# no action-budget spend.
# ══════════════════════════════════════════════════════════════════════════

func test_a_hex_beyond_speed_is_never_offered_as_a_candidate_and_a_click_there_produces_no_resolution() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var actor: Dictionary = instance.round_session.current_actor()
	var actor_id: String = actor.get("combatant_id", "")
	var actor_hex = actor.get("hex_coord", null)
	assert_not_null(actor_hex, "fixture assumption: the active actor carries a hex_coord")

	var action_economy = instance.round_session.current_action_economy()
	var before_remaining: int = action_economy.get_remaining()

	var selection: Dictionary = instance.verb_bar_view.press("STRIDE")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "fixture assumption: at least one legal Stride destination exists")

	var beyond_speed_hex = _far_beyond_speed_hex(instance, actor_hex)

	for candidate_hex in candidate_hexes:
		assert_false(
			candidate_hex.equals(beyond_speed_hex),
			"a hex strictly beyond Speed must never appear among Stride's candidate_hexes"
		)
	for hex_coord in instance.selection_overlay.get_highlighted_hexes():
		assert_false(
			hex_coord.equals(beyond_speed_hex),
			"a hex strictly beyond Speed must never be highlighted by SelectionOverlay"
		)

	watch_signals(instance.selection_overlay)
	instance.hex_grid_view.hex_clicked.emit(beyond_speed_hex)

	assert_signal_emitted(instance.selection_overlay, "selection_rejected", "a beyond-Speed click must emit selection_rejected, never selection_resolved")
	assert_signal_not_emitted(instance.selection_overlay, "selection_resolved", "a beyond-Speed click must NEVER resolve through the verb registry")

	assert_true(instance.selection_overlay.is_active(), "Stride's Layer 2 selection must remain active after a rejected, beyond-Speed click (no accidental cancel)")

	var unmoved_combatant = _find_combatant_by_id(instance, actor_id)
	assert_true(unmoved_combatant.hex_coord.equals(actor_hex), "a beyond-Speed click must not move the actor at all")

	assert_eq(
		action_economy.get_remaining(), before_remaining,
		"a beyond-Speed click must spend no action -- no resolution may occur"
	)
