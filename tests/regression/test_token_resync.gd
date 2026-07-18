extends GutTest
## tests/regression/test_token_resync.gd — FEAT-166 (US-012 /
## FR-008,FR-009,FR-010,FR-012): regression verification of preserved
## behaviors on the KEPT single-stack MainScene composition root (post
## FEAT-001/FEAT-002 UI consolidation, iteration D).
##
## Re-runs combatant token resync against the KEPT presentation/hex_grid_view.gd
## HexGridView after BOTH Step and Stride, driven entirely through the real,
## shipped res://MainScene.tscn composition root (no stub/mock standing in
## for HexGridView/movement_input_controller/TurnController) -- mirroring
## tests/integration/test_movement_affordance_integration.gd's established
## "boot the real MainScene.tscn, execute the real verb registry" pattern.
##
## FEAT-007 (this iteration's US-007/FR-010): both scenarios below drive
## movement through `_verb_registry`'s STEP/STRIDE entries
## (VerbBarView.press(verb_id) -> execute(verb_id, destination)) rather than
## simulating a hex_grid_view.hex_clicked emission -- the legacy "click any
## highlighted hex to auto Step-or-Stride" affordance (which used to try
## step_to() first, falling back to stride_to()) has been deleted; Step and
## Stride are each driven through their own dedicated verb now, so there is
## no ambiguity about which branch resolves.
##
## tests/integration/test_movement_affordance_integration.gd's criterion 3
## (test_step_verb_execute_moves_the_combatant_and_resyncs_the_hex_grid_view_token)
## already exercises the Step path end-to-end. No existing suite specifically
## proves the Stride path resyncs the token too -- that gap is closed here by
## picking a destination hex present in the actor's Stride-legal set but
## ABSENT from its Step-legal set (distance > 1), then executing the STRIDE
## verb against it directly.
##
## test_criteria satisfied: "Token resync test confirms HexGridView token
## position matches Combatant.position after Step and after Stride."

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const HexGridViewClass = preload("res://presentation/hex_grid_view.gd")

const PINNED_SEED: int = 42


func _boot_main_scene(seed_value: int = PINNED_SEED):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


## _find_combatant_by_id(instance, combatant_id) -> Dictionary -- looks up a
## live combatant Dictionary (MainScene's own _party/_enemies fields, the SAME
## Dictionaries core/rules/movement.gd Movement.step()/stride() mutate in
## place), mirroring the identically-named helper already established by
## tests/integration/test_movement_affordance_integration.gd.
func _find_combatant_by_id(instance, combatant_id: String):
	for combatant in instance._party + instance._enemies:
		if combatant.combatant_id == combatant_id:
			return combatant
	return null


## _assert_token_matches_combatant_position(instance, actor_id, context) ->
## void -- the shared assertion this whole suite exists to prove: the
## KEPT HexGridView's token hex_coord/rendered pixel position both equal
## Combatant.position (the live combatant Dictionary's hex_coord).
func _assert_token_matches_combatant_position(instance, actor_id: String, context: String) -> void:
	var combatant = _find_combatant_by_id(instance, actor_id)
	assert_false(combatant == null, "%s: fixture assumption -- the moved actor must be one of MainScene's live combatant Dictionaries" % context)
	if combatant == null:
		return

	var token = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token, "%s: the kept HexGridView must still carry a token for the moved actor" % context)
	if token == null:
		return

	assert_true(
		token.hex_coord.equals(combatant.hex_coord),
		"%s: HexGridView token's hex_coord must match Combatant.position (the live combatant Dictionary's hex_coord)" % context
	)
	assert_eq(
		token.position, instance.hex_grid_view.axial_to_pixel_with_offset(combatant.hex_coord),
		(
			"%s: HexGridView token's rendered pixel position must match axial_to_pixel(Combatant.position), honoring the "
			+ "composition root's FEAT-002 viewport-centering origin offset"
		) % context
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion — token resync after Step.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_grid_view_token_resyncs_to_combatant_position_after_step() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var actor: Dictionary = instance.round_session.current_actor()
	var actor_id: String = actor.get("combatant_id", "")
	assert_ne(actor_id, "", "fixture assumption: the active actor carries a non-empty combatant_id")

	var step_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	assert_true(step_hexes.size() > 0, "fixture assumption: the active actor has at least one legal Step destination")
	var destination = step_hexes[0]

	var token_before = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_before, "the kept HexGridView must already carry a token for the active actor")
	assert_false(token_before.hex_coord.equals(destination), "sanity check: the chosen Step destination must differ from the actor's starting hex")

	# ── Execute the real STEP verb through `_verb_registry` -- the SOLE Step
	# entry point now that the legacy hex_grid_view.hex_clicked auto-resolve
	# handler has been deleted (FEAT-007). ───────────────────────────────────
	var step_result: Dictionary = instance._verb_registry.execute("STEP", destination)
	assert_true(step_result.get("ok", false), "executing STEP against the selected destination must resolve a real Step")

	var moved = _find_combatant_by_id(instance, actor_id)
	assert_true(
		moved.hex_coord.equals(destination),
		"Combatant.position must change to the selected legal Step hex via movement_input_controller.step_to()"
	)

	_assert_token_matches_combatant_position(instance, actor_id, "after Step")


# ══════════════════════════════════════════════════════════════════════════
# Criterion — token resync after Stride (the previously-unexercised path:
# a destination reachable only via Stride, never Step).
# ══════════════════════════════════════════════════════════════════════════

func test_hex_grid_view_token_resyncs_to_combatant_position_after_stride() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var actor: Dictionary = instance.round_session.current_actor()
	var actor_id: String = actor.get("combatant_id", "")
	assert_ne(actor_id, "", "fixture assumption: the active actor carries a non-empty combatant_id")

	var step_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	var stride_hexes: Array = instance.movement_input_controller.get_selectable_stride_hexes()

	var stride_only_destination = null
	for candidate in stride_hexes:
		var is_also_step_hex: bool = false
		for step_hex in step_hexes:
			if step_hex.equals(candidate):
				is_also_step_hex = true
				break
		if not is_also_step_hex:
			stride_only_destination = candidate
			break

	assert_not_null(
		stride_only_destination,
		"fixture assumption: the active actor has at least one Stride-only (distance > 1) legal destination -- Movement.DEFAULT_SPEED (4) " +
		"exceeds Step's 1-hex reach, so an open battlefield always yields at least one such hex"
	)
	if stride_only_destination == null:
		return

	var token_before = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_before, "the kept HexGridView must already carry a token for the active actor")
	assert_false(
		token_before.hex_coord.equals(stride_only_destination),
		"sanity check: the chosen Stride destination must differ from the actor's starting hex"
	)

	var action_budget_before: int = instance.round_session.current_action_economy().get_remaining()

	# ── Execute the real STRIDE verb through `_verb_registry` directly --
	# proving this scenario genuinely exercises the Stride branch, not Step
	# (FEAT-007: Step and Stride are each driven through their own dedicated
	# verb now, so there is no step-then-fallback-to-stride ambiguity). ─────
	var stride_result: Dictionary = instance._verb_registry.execute("STRIDE", stride_only_destination)
	assert_true(stride_result.get("ok", false), "executing STRIDE against the selected destination must resolve a real Stride")

	var moved = _find_combatant_by_id(instance, actor_id)
	assert_true(
		moved.hex_coord.equals(stride_only_destination),
		"Combatant.position must change to the selected legal Stride hex via movement_input_controller.stride_to()"
	)

	# Stride (unlike Step) spends exactly one action -- confirms this really
	# was resolved via Movement.stride(), not Movement.step() (which never
	# touches the action economy at all, per core/rules/movement.gd's
	# file-level doc).
	assert_eq(
		instance.round_session.current_action_economy().get_remaining(), action_budget_before - 1,
		"a successful Stride must spend exactly one action from the mover's action economy"
	)

	_assert_token_matches_combatant_position(instance, actor_id, "after Stride")
