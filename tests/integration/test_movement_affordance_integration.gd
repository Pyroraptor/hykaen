extends GutTest
## tests/integration/test_movement_affordance_integration.gd — FEAT-010
## (US-010 / FR-004, iteration D "UI Consolidation + Movement UX").
##
## Integration-test complement to tests/business_logic/
## test_highlight_legal_moves.gd and tests/business_logic/
## test_clear_highlight_triggers.gd: those two suites drive MainScene.gd's
## handlers directly against a freshly `.new()`-constructed MainScene with a
## SpyHexGridView collaborator standing in for presentation/hex_grid_view.gd
## (documented there as necessary because HexGridView's `_selectable_hexes`
## field has no dedicated public getter). This suite instead boots the REAL,
## shipped res://MainScene.tscn composition root headless (mirroring
## tests/integration/test_steel_thread_prologue_encounter.gd's and
## tests/infrastructure/test_presentation_stack_wiring.gd's
## `_boot_main_scene_with_seed()` fixture) with NO stub/mock standing in for
## HexGridView, movement_input_controller, or TurnController -- proving the
## movement affordance (US-006/US-007's highlight-then-move UX) works
## end-to-end through the exact objects a real player drives, not merely
## through MainScene.gd's handler methods in isolation.
##
## FEAT-007 (this iteration's US-007/FR-010): Criterion 3 was retargeted from
## simulating a hex_grid_view.hex_clicked emission (the legacy "click any
## highlighted hex to auto Step-or-Stride" affordance, now deleted) to
## executing the Layer 1 STEP verb (VerbBarView.press("STEP") ->
## `_verb_registry`'s enter_selection()/execute()) -- the SOLE way a Step can
## now be performed, mirroring tests/infrastructure/
## test_presentation_stack_wiring.gd's STRIKE verb-wiring test pattern.
##
## Because presentation/hex_grid_view.gd deliberately exposes no public
## getter for its highlighted-hex set (see the SpyHexGridView precedent
## above), and this suite must not modify any production file (FEAT-010's
## files_to_modify is empty -- only this test file is authored), this suite
## reads the real HexGridView's `_selectable_hexes` field directly. GDScript
## has no enforced privacy for underscore-prefixed members (it is a style
## convention only), so this is a legitimate, non-invasive way to observe the
## real, unmodified object's state -- it performs no injection, subclassing,
## or monkeypatching of HexGridView itself.
##
## test_criteria satisfied:
##   1. test_real_mainscene_boots_headlessly_with_the_real_movement_affordance_stack()
##   2. test_highlighted_hexes_on_turn_started_match_the_controllers_legal_step_stride_union()
##   3. test_step_verb_execute_moves_the_combatant_and_resyncs_the_hex_grid_view_token()
##   4. (whole-suite regression) -- enforced by test_command, not this file.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const HexGridViewClass             = preload("res://presentation/hex_grid_view.gd")
const MovementInputControllerClass = preload("res://presentation/movement_input_controller.gd")
const TurnControllerClass          = preload("res://presentation/turn_controller.gd")


# ══════════════════════════════════════════════════════════════════════════
# Shared fixture: boot the REAL res://MainScene.tscn composition root, pinned
# to seed=42 (the prologue fixture's known-good seed, matching this
# codebase's established convention -- see tests/integration/
# test_steel_thread_prologue_encounter.gd / tests/infrastructure/
# test_presentation_stack_wiring.gd) so this suite can rely on a
# deterministic first-actor/legal-move layout without asserting anything
# about which specific hexes are legal beyond what the real domain rules
# report at runtime.
# ══════════════════════════════════════════════════════════════════════════

## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): round_session/
## the Layer 1 verb bar/Layer 2 selection overlay/turn_controller signal
## wiring (including movement_input_controller's own turn_started-driven
## highlight refresh) are no longer live unconditionally at boot -- they now
## stay dormant until a real combat trigger fires (see MainScene.gd's own
## FEAT-316 doc). This suite drives the real movement affordance stack, so
## _boot_main_scene_with_seed() now also drives the SAME real handoff
## tests/boot/test_exploration_to_combat_handoff_trigger.gd exercises
## directly (mirrors tests/boot/test_first_cast_firebolt.gd's established
## convention), landing the instance in GameMode.COMBAT with a live
## round_session before returning.
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
## Dictionaries core/rules/movement.gd Movement.step()/stride() mutate in
## place), mirroring the identically-named helper already established by
## tests/integration/test_steel_thread_prologue_encounter.gd.
func _find_combatant_by_id(instance, combatant_id: String):
	for combatant in instance._party + instance._enemies:
		if combatant.combatant_id == combatant_id:
			return combatant
	return null


## _as_key_set(hexes) -> Dictionary -- a "q,r" -> true set built from an Array
## of core/geometry/hex_coord.gd HexCoords, mirroring tests/business_logic/
## test_highlight_legal_moves.gd's identically-named helper: HexCoord is a
## value object with no custom `==`/hash, so comparing Arrays of HexCoord
## instances directly (assert_eq on the Arrays themselves) would compare
## object identity, not value equality -- this key-set comparison is the
## established, correct way to compare two hex sets for exact value equality
## regardless of instance identity or ordering.
func _as_key_set(hexes: Array) -> Dictionary:
	var set: Dictionary = {}
	for hex_coord in hexes:
		set["%d,%d" % [hex_coord.q, hex_coord.r]] = true
	return set


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — the REAL MainScene.tscn boots headlessly with zero compile/
# runtime errors, and the movement affordance is wired through the REAL
# HexGridView / MovementInputController / TurnController classes -- never a
# stub/mock standing in for any of the three.
# ══════════════════════════════════════════════════════════════════════════

func test_real_mainscene_boots_headlessly_with_the_real_movement_affordance_stack() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_not_null(instance.round_session, "MainScene must obtain a real RoundSession via RunRoundUseCase.begin_round()")
	assert_false(instance.round_session.is_round_over(), "the freshly-begun RoundSession must not already be over with no player input")

	assert_not_null(instance.hex_grid_view, "MainScene must expose a non-null hex_grid_view")
	assert_true(
		is_instance_of(instance.hex_grid_view, HexGridViewClass),
		"MainScene must wire the REAL presentation/hex_grid_view.gd HexGridView -- no stub/mock"
	)

	assert_not_null(instance.movement_input_controller, "MainScene must expose a non-null movement_input_controller")
	assert_true(
		is_instance_of(instance.movement_input_controller, MovementInputControllerClass),
		"MainScene must wire the REAL presentation/movement_input_controller.gd MovementInputController -- no stub/mock"
	)

	assert_not_null(instance.turn_controller, "MainScene must expose a non-null turn_controller")
	assert_true(
		is_instance_of(instance.turn_controller, TurnControllerClass),
		"MainScene must wire the REAL presentation/turn_controller.gd TurnController -- no stub/mock"
	)

	# Sanity check: the hex battlefield rendered one token per prologue
	# combatant (Titus + Marigold + Skeleton, Iteration M "Cast a Spell"
	# roster) via the real HexGridView.
	assert_eq(instance.hex_grid_view.get_token_count(), 3, "the real HexGridView must render one token per prologue combatant")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — the highlighted hex set on turn_started (realized in this
# codebase as TurnController.active_actor_changed, driven here entirely
# through the real _ready() wiring, not a directly-invoked handler) exactly
# matches union(movement_input_controller.get_selectable_step_hexes(),
# get_selectable_stride_hexes()) for the active player's turn.
# ══════════════════════════════════════════════════════════════════════════

func test_highlighted_hexes_on_turn_started_match_the_controllers_legal_step_stride_union() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: the first actor must be the living player combatant (Titus) per prologue_encounter.tres' hex layout at seed=42"
	)

	var step_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	var stride_hexes: Array = instance.movement_input_controller.get_selectable_stride_hexes()

	assert_true(step_hexes.size() > 0, "sanity check: the active player actor has at least one legal Step destination")
	assert_true(
		stride_hexes.size() >= step_hexes.size(),
		"sanity check: Stride (up to Speed hexes) must legally reach at least as many hexes as Step (1 hex)"
	)

	var expected_keys: Dictionary = _as_key_set(step_hexes)
	for key in _as_key_set(stride_hexes).keys():
		expected_keys[key] = true

	# Read the REAL HexGridView's highlighted set directly -- see this file's
	# header doc for why this is the correct, non-invasive way to observe it
	# without a stub/mock standing in for HexGridView.
	var highlighted: Array = instance.hex_grid_view._selectable_hexes
	var highlighted_keys: Dictionary = _as_key_set(highlighted)

	assert_eq(
		highlighted_keys.keys().size(), expected_keys.keys().size(),
		"the real HexGridView's highlighted hex count must exactly equal the union(Step, Stride) hex count -- no extra hexes, no missing hexes"
	)
	for key in expected_keys.keys():
		assert_true(highlighted_keys.has(key), "expected union hex %s to be highlighted on the real HexGridView" % key)
	for key in highlighted_keys.keys():
		assert_true(expected_keys.has(key), "highlighted hex %s must be present in union(Step, Stride) -- no extra/filtered hex" % key)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — executing the Layer 1 STEP verb (VerbBarView.press("STEP") ->
# `_verb_registry`'s enter_selection()/execute(), the SOLE Step entry point
# since FEAT-007, this iteration's US-007/FR-010, deleted the legacy
# hex_grid_view.hex_clicked auto-resolve handler) against a legal destination
# (drawn straight from the real movement_input_controller's own legal-Step
# set) moves the active combatant (Combatant.position, observed on
# MainScene's own live combatant Dictionary) via step_to(), and the real
# HexGridView's token resyncs to the new hex.
# ══════════════════════════════════════════════════════════════════════════

func test_step_verb_execute_moves_the_combatant_and_resyncs_the_hex_grid_view_token() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var actor: Dictionary = instance.round_session.current_actor()
	var actor_id: String = actor.get("combatant_id", "")
	assert_true(actor_id != "", "fixture assumption: the active actor carries a non-empty combatant_id")

	assert_true(
		instance._verb_registry.is_available("STEP"),
		"fixture assumption: the active actor has at least one legal Step destination"
	)
	var step_selection: Dictionary = instance.verb_bar_view.press("STEP")
	var step_hexes: Array = step_selection.get("candidate_hexes", [])
	assert_true(step_hexes.size() > 0, "sanity check: entering STEP's Layer 2 selection surfaces at least one legal destination hex")
	var destination = step_hexes[0]

	var token_before = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_before, "the real HexGridView must already carry a token for the active actor")
	assert_false(
		token_before.hex_coord.equals(destination),
		"sanity check: the chosen destination hex must differ from the actor's starting hex"
	)
	# ── Execute STEP through the real verb registry -- the SOLE Step entry
	# point now that the legacy hex_grid_view.hex_clicked auto-resolve handler
	# has been deleted (FEAT-007). ───────────────────────────────────────────
	var step_result: Dictionary = instance._verb_registry.execute("STEP", destination)
	assert_true(step_result.get("ok", false), "executing STEP against the selected destination must resolve a real Step")

	var moved_combatant = _find_combatant_by_id(instance, actor_id)
	assert_false(moved_combatant == null, "fixture assumption: the moved actor must be one of MainScene's live combatant Dictionaries")
	assert_true(
		moved_combatant.hex_coord.equals(destination),
		"Combatant.position (the live combatant Dictionary's hex_coord) must change to the clicked legal hex via step_to()"
	)

	var token_after = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_after, "the real HexGridView must still carry a token for the moved actor")
	assert_true(
		token_after.hex_coord.equals(destination),
		"the real HexGridView's token must resync its hex_coord to the new hex after a successful step_to()"
	)
	assert_eq(
		token_after.position, instance.hex_grid_view.axial_to_pixel_with_offset(destination),
		"the real HexGridView's token must resync its rendered screen position to the new hex's ADR-004 axial-to-pixel "
		+ "projection, honoring the composition root's FEAT-002 viewport-centering origin offset"
	)

	# US-008 (design notes' API contract #4): the highlight is cleared
	# immediately after a successful move, then re-derived from the mover's
	# NEW position -- proven here the same way criterion 2 above proves the
	# turn_started highlight: it must exactly equal
	# union(get_selectable_step_hexes(), get_selectable_stride_hexes())
	# computed AFTER the move, from the mover's new position (the vacated
	# starting hex is no longer occupied by the mover, so it MAY legitimately
	# reappear in that fresh union -- e.g. a legal Stride back the way it
	# came -- so this suite asserts freshness by exact-equality with the real
	# post-move domain query, never by asserting the vacated hex is absent).
	var step_hexes_after: Array = instance.movement_input_controller.get_selectable_step_hexes()
	var stride_hexes_after: Array = instance.movement_input_controller.get_selectable_stride_hexes()
	var expected_keys_after: Dictionary = _as_key_set(step_hexes_after)
	for key in _as_key_set(stride_hexes_after).keys():
		expected_keys_after[key] = true

	var highlighted_after: Array = instance.hex_grid_view._selectable_hexes
	var highlighted_after_keys: Dictionary = _as_key_set(highlighted_after)

	assert_eq(
		highlighted_after_keys.keys().size(), expected_keys_after.keys().size(),
		"the highlight re-derived after a successful move must exactly equal union(Step, Stride) computed from the mover's NEW position -- no extra hexes, no missing hexes"
	)
	for key in expected_keys_after.keys():
		assert_true(highlighted_after_keys.has(key), "expected post-move union hex %s to be highlighted" % key)
	for key in highlighted_after_keys.keys():
		assert_true(expected_keys_after.has(key), "post-move highlighted hex %s must be present in the post-move union(Step, Stride)" % key)
