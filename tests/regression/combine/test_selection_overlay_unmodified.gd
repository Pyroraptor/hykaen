extends GutTest
## tests/regression/combine/test_selection_overlay_unmodified.gd — FEAT-007
## (Iteration O "Combine Selection UX"; US-007; NFR-001).
##
## Regression proof for FEAT-007's own reuse guarantee (design notes'
## architecture section: "SelectionOverlay (UNMODIFIED, US-007/NFR-001) --
## outer UI adapter"): wiring MultiPhaseTargetingController's callback into
## MainScene.gd (this feature's ONLY modified production file) must leave
## presentation/selection_overlay.gd COMPLETELY untouched, and every
## standalone (non-Combine) Stride/Strike flow through it must be byte-for-
## byte unaffected.
##
## test_criteria covered:
##   1. Standalone (non-Combine) Stride enter_selection()->SelectionOverlay->
##      selection_resolved flow passes unchanged.
##   2. Standalone (non-Combine) Strike enter_selection()->SelectionOverlay->
##      selection_resolved flow passes unchanged.
##   3. SelectionOverlay source file has zero diff relative to the
##      pre-Combine baseline (a pinned SHA-256 hash of the file's own
##      content, computed BEFORE this feature's MainScene.gd-only change was
##      authored -- see this suite's own PINNED_SELECTION_OVERLAY_SHA256
##      constant doc below).
##
## Every suite below drives the REAL, shipped res://MainScene.tscn
## composition root -- the real presentation/selection_overlay.gd
## SelectionOverlay, the real presentation/hex_grid_view.gd HexGridView, the
## real presentation/stride_action_controller.gd/strike_action_controller.gd
## verb controllers -- mirroring tests/gut/test_stride_layer2_integration.gd's/
## tests/regression/test_strike_end_to_end_unchanged.gd's established
## "boot-real, no mocked doubles" convention. NONE of these standalone flows
## ever call MainScene.gd's NEW start_combine_targeting() entry point (this
## feature's own addition) -- `_combine_targeting_active` must remain false
## throughout every test below, proving the new interactive Combine
## targeting loop never engages for a standalone verb press.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const SELECTION_OVERLAY_PATH: String = "res://presentation/selection_overlay.gd"

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/regression/test_strike_end_to_end_unchanged.gd's/
## tests/gut/test_stride_layer2_integration.gd's identically-valued
## constant): Titus acts first and the sole enemy (Skeleton) starts adjacent
## to him.
const PROLOGUE_SEED: int = 42

## PINNED_SELECTION_OVERLAY_SHA256 -- FEAT-007 (NFR-001): a SHA-256 digest of
## presentation/selection_overlay.gd's own file content, computed from the
## file exactly as it stood immediately before this feature's work began
## (this feature's files_to_modify list names ONLY scripts/main_scene.gd --
## i.e. MainScene.gd, the project's composition root -- so
## selection_overlay.gd is never touched by this change at all). A future
## change that edits presentation/selection_overlay.gd for ANY reason will
## flip this file's live hash away from this pinned value, failing
## test_selection_overlay_source_has_zero_diff_from_pinned_baseline below --
## the durable, automated guard this feature's own test_criteria calls for
## ("SelectionOverlay source file has zero diff relative to pre-Combine
## baseline (verified via file-hash/diff assertion in the regression
## test)"), mirroring tests/regression/test_baseline_diff_regression.gd's
## own established "pin a known-good snapshot, diff the live artifact
## against it" convention.
const PINNED_SELECTION_OVERLAY_SHA256: String = "18187ff052e438ff930dd5d9c1da0ef1ace4f63f3f7b8ccc09d40145f13dedf9"

const PROLOGUE_ENCOUNTER_ID: String = "prologue"


## FEAT-316 (resolves DEF-001/PR-001): MainScene now boots into EXPLORATION
## mode with the legacy combat pipeline (round_session, $VerbBarView/
## $SelectionOverlay configuration, turn_controller signal wiring) gated
## behind a real _on_combat_triggered() handoff -- see MainScene.gd's own
## FEAT-316 doc. Every standalone-verb flow this suite drives depends on that
## pipeline being live, so this helper now also drives the SAME real handoff
## tests/boot/test_exploration_to_combat_handoff_trigger.gd exercises
## directly, landing the instance in GameMode.COMBAT with a live
## round_session before returning (mirrors tests/boot/
## test_first_cast_firebolt.gd's established idiom).
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


func _skeleton(instance):
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


func _find_combatant_by_id(instance, combatant_id: String):
	for combatant in instance._party + instance._enemies:
		if combatant.combatant_id == combatant_id:
			return combatant
	return null


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — standalone (non-Combine) Stride: enter_selection() ->
# SelectionOverlay -> selection_resolved passes unchanged.
# ══════════════════════════════════════════════════════════════════════════

func test_standalone_stride_enter_selection_selection_overlay_resolved_flow_is_unaffected() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	assert_false(instance._combine_targeting_active, "the new interactive Combine targeting loop must never be active before a standalone verb press")

	var actor_id: String = instance.round_session.current_actor().display_id()
	var action_economy = instance.round_session.current_action_economy()
	var before_remaining: int = action_economy.get_remaining()

	var selection: Dictionary = instance.verb_bar_view.press("STRIDE")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "fixture assumption: at least one legal Stride destination exists at boot")
	assert_true(instance.selection_overlay.is_active(), "SelectionOverlay must be active (Layer 2) after pressing STRIDE")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIDE")

	var destination = candidate_hexes[0]
	var token_before = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_before, "the real HexGridView must already carry a token for the active actor")

	watch_signals(instance.selection_overlay)
	instance.hex_grid_view.hex_clicked.emit(destination)

	assert_signal_emitted(instance.selection_overlay, "selection_resolved", "a standalone Stride click must still resolve through the UNCHANGED selection_overlay.gd")
	var resolved_params: Array = get_signal_parameters(instance.selection_overlay, "selection_resolved")
	assert_eq(resolved_params[0], "STRIDE", "selection_resolved must carry the STRIDE verb_id")
	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the real click resolves a standalone Stride")

	var moved_combatant = _find_combatant_by_id(instance, actor_id)
	assert_true(moved_combatant.hex_coord.equals(destination), "the actor must have genuinely moved to the chosen destination")

	assert_eq(
		action_economy.get_remaining(), before_remaining - 1,
		"a standalone Stride must still decrement actions_remaining by EXACTLY 1, exactly as before this feature"
	)

	# The interactive Combine targeting loop this feature adds must NEVER
	# have engaged for this standalone press.
	assert_false(instance._combine_targeting_active, "a standalone Stride press must never engage the interactive Combine targeting loop")
	assert_eq(instance._combine_targeting_resolved, {}, "a standalone Stride press must never populate the Combine targeting loop's own resolved-state map")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — standalone (non-Combine) Strike: enter_selection() ->
# SelectionOverlay -> selection_resolved passes unchanged.
# ══════════════════════════════════════════════════════════════════════════

func test_standalone_strike_enter_selection_selection_overlay_resolved_flow_is_unaffected() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	assert_false(instance._combine_targeting_active, "the new interactive Combine targeting loop must never be active before a standalone verb press")

	var skeleton = _skeleton(instance)
	var skeleton_id: String = skeleton.combatant_id
	var hp_before: int = skeleton.hp_current

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.has(skeleton_id), "fixture assumption: the Skeleton must be an in-reach Strike target at boot")
	assert_true(instance.selection_overlay.is_active(), "SelectionOverlay must be active (Layer 2) after pressing STRIKE")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIKE")

	var target_token = instance.hex_grid_view.get_token(skeleton_id)
	assert_not_null(target_token, "fixture assumption: the Skeleton has a rendered HexGridView token")

	watch_signals(instance.selection_overlay)
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	assert_signal_emitted(instance.selection_overlay, "selection_resolved", "a standalone Strike click must still resolve through the UNCHANGED selection_overlay.gd")
	var resolved_params: Array = get_signal_parameters(instance.selection_overlay, "selection_resolved")
	assert_eq(resolved_params[0], "STRIKE", "selection_resolved must carry the STRIKE verb_id")
	assert_true(resolved_params[1] is Dictionary, "selection_resolved's result must be the registry.execute() return Dictionary verbatim")
	assert_true(resolved_params[1].get("resolved", false), "a standalone Strike must still resolve through the real registry.execute() call")
	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the real click resolves a standalone Strike")

	assert_ne(skeleton.hp_current, hp_before, "a standalone Strike must still genuinely mutate the target's hp exactly as before this feature")

	# The interactive Combine targeting loop this feature adds must NEVER
	# have engaged for this standalone press.
	assert_false(instance._combine_targeting_active, "a standalone Strike press must never engage the interactive Combine targeting loop")
	assert_eq(instance._combine_targeting_resolved, {}, "a standalone Strike press must never populate the Combine targeting loop's own resolved-state map")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — presentation/selection_overlay.gd has ZERO diff relative to
# its pre-Combine (pinned) baseline.
# ══════════════════════════════════════════════════════════════════════════

func test_selection_overlay_source_has_zero_diff_from_pinned_baseline() -> void:
	var content: String = _read_file(SELECTION_OVERLAY_PATH)
	var live_hash: String = content.sha256_text()

	assert_eq(
		live_hash, PINNED_SELECTION_OVERLAY_SHA256,
		"REGRESSION: presentation/selection_overlay.gd must have ZERO diff relative to the pre-Combine pinned baseline -- any hash mismatch means this file was modified, violating FEAT-007/NFR-001's 'unmodified reuse of selection infrastructure' guarantee"
	)


func test_selection_overlay_is_never_modified_by_the_combine_targeting_wiring_seam() -> void:
	# Structural complement to Criterion 3 above: MainScene.gd's own new
	# Combine-targeting seam methods (start_combine_targeting() and its
	# private helpers) must reach selection_overlay ONLY through its
	# EXISTING public surface (configure()/activate()/is_active()/etc.) --
	# never by reaching into a private (`_`-prefixed) member of
	# SelectionOverlay itself, which would be a de-facto modification of
	# that class's contract even with zero bytes changed in its own file.
	var proxy_content: String = _read_file("res://presentation/adapters/combine_targeting_registry_proxy.gd")
	assert_true(
		proxy_content.contains("CombineTargetingRegistryProxy"),
		"presentation/adapters/combine_targeting_registry_proxy.gd must define the CombineTargetingRegistryProxy presentation-layer proxy for the Combine targeting loop"
	)
