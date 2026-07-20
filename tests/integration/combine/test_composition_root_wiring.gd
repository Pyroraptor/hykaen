extends GutTest
## tests/integration/combine/test_composition_root_wiring.gd — FEAT-007
## (Iteration O "Combine Selection UX"; US-007; NFR-001).
##
## Boot-real integration suite for FEAT-007's own scope: "Complete MainScene
## wiring of selection_overlay.selection_resolved to the
## MultiPhaseTargetingController callback, driving SelectionDescriptor
## display through the existing unmodified SelectionOverlay/choose_option()/
## _show_spell_picker() path per ADR-003." Drives the REAL, shipped
## res://MainScene.tscn composition root -- the real presentation/
## selection_overlay.gd SelectionOverlay, the real presentation/
## hex_grid_view.gd HexGridView, the real core/controllers/
## stride_action_controller.gd / core/controllers/strike_action_controller.gd
## verb controllers, and the real core/application/combine/
## multi_phase_targeting_controller.gd MultiPhaseTargetingController
## (UNCHANGED by this feature) -- via MainScene.gd's own new
## start_combine_targeting() entry point (this feature's OWN addition).
##
## test_criteria covered:
##   1. "selection_overlay.selection_resolved signal, when emitted during a
##      Combine targeting phase, routes the chosen_value into
##      MultiPhaseTargetingController's accumulated state for the correct
##      verb_id" -- proven both for a single-phase (STRIDE-only) queue and a
##      two-phase (STRIDE-then-STRIKE) queue, including a mid-flow assertion
##      that a resolved STRIDE value never leaks into the STRIKE verb_id's
##      own slot.
##
## Standalone (non-Combine) Stride/Strike regression coverage lives in the
## sibling tests/regression/combine/test_selection_overlay_unmodified.gd
## suite, not here (this file is scoped to the NEW Combine-targeting wiring
## itself).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const HexMathClass = preload("res://core/geometry/hex_math.gd")

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/regression/test_strike_end_to_end_unchanged.gd's/
## tests/gut/test_stride_layer2_integration.gd's identically-valued
## constant): Titus acts first and the sole enemy (Skeleton) starts adjacent
## to him.
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _titus(instance):
	return instance._party[0]


func _skeleton(instance):
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1a — a single-phase (STRIDE-only) Combine targeting queue: a
# real HexGridView click resolving through the UNCHANGED SelectionOverlay
# routes the chosen hex into MultiPhaseTargetingController's own accumulated
# state, keyed by "STRIDE".
# ══════════════════════════════════════════════════════════════════════════

func test_single_phase_stride_selection_resolved_routes_chosen_hex_into_accumulated_state() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var actor = _titus(instance)
	var entries: Array = [VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	instance.start_combine_targeting(entries, actor, CombineQueueClass.Context.TURN)

	assert_true(instance._combine_targeting_active, "the interactive targeting loop must be active after start_combine_targeting()")
	assert_true(instance.selection_overlay.is_active(), "the STRIDE phase must activate the UNCHANGED selection_overlay")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIDE")

	var candidate_hexes: Array = instance.selection_overlay.get_highlighted_hexes()
	assert_true(candidate_hexes.size() > 0, "fixture assumption: Titus has at least one legal Stride destination at boot")
	var chosen_hex = candidate_hexes[0]

	watch_signals(instance.selection_overlay)
	instance.hex_grid_view.hex_clicked.emit(chosen_hex)

	assert_signal_emitted(instance.selection_overlay, "selection_resolved", "the STRIDE phase's hex click must resolve through the UNCHANGED selection_overlay.gd")
	var resolved_params: Array = get_signal_parameters(instance.selection_overlay, "selection_resolved")
	assert_eq(resolved_params[0], "STRIDE", "selection_resolved must carry the STRIDE verb_id")

	# ── The criterion itself: the chosen hex is now inside
	# MultiPhaseTargetingController's own accumulated state, keyed by the
	# CORRECT verb_id ("STRIDE") -- driven purely by the selection_overlay
	# signal wiring, never by this test hand-assembling resolved_selections. ──
	assert_true(instance._combine_targeting_result.get("ok", false), "a 1-entry queue's only phase resolving must report ok:true")
	var accumulated: Dictionary = instance._combine_targeting_result.get("accumulated", {})
	assert_true(accumulated.has("STRIDE"), "accumulated must carry the resolved STRIDE phase")
	assert_eq(
		accumulated["STRIDE"].meta.get("chosen_hex"), chosen_hex,
		"the accumulated STRIDE entry must carry the EXACT hex the player clicked via the real SelectionOverlay UI"
	)

	assert_false(instance.selection_overlay.is_active(), "selection_overlay must return to Layer 1 once Combine targeting completes")
	assert_false(instance._combine_targeting_active, "the interactive loop must have finished")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1b — a two-phase (STRIDE-then-STRIKE) queue: EACH phase's own
# selection_resolved routes its OWN chosen_value into the accumulated state
# keyed by ITS OWN verb_id -- never cross-contaminated between phases.
# ══════════════════════════════════════════════════════════════════════════

func test_two_phase_stride_then_strike_routes_each_phases_chosen_value_to_the_correct_verb_id() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var actor = _titus(instance)
	var skeleton = _skeleton(instance)
	var entries: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]

	instance.start_combine_targeting(entries, actor, CombineQueueClass.Context.TURN)
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIDE")

	# Pick a Stride destination that keeps the actor adjacent to the
	# Skeleton, so STRIKE's own phase genuinely has a reachable target
	# afterward (post-move-aware targeting, FEAT-006, unchanged).
	var candidate_hexes: Array = instance.selection_overlay.get_highlighted_hexes()
	var skeleton_neighbors: Array = HexMathClass.hex_neighbors(skeleton.hex_coord)
	var chosen_hex = null
	for h in candidate_hexes:
		for n in skeleton_neighbors:
			if h.equals(n):
				chosen_hex = h
				break
		if chosen_hex != null:
			break
	assert_not_null(chosen_hex, "fixture assumption: at least one Stride destination keeps the actor adjacent to the Skeleton")

	instance.hex_grid_view.hex_clicked.emit(chosen_hex)

	# ── Mid-flow check: the STRIDE phase's chosen value must be routed into
	# the resolved-state map keyed by "STRIDE" -- and must NOT leak into a
	# "STRIKE" slot before STRIKE's own phase has even resolved anything. ──
	assert_eq(
		instance._combine_targeting_resolved.get("STRIDE"), chosen_hex,
		"the STRIDE phase's chosen_value must be routed into resolved state keyed by verb_id 'STRIDE'"
	)
	assert_false(
		instance._combine_targeting_resolved.has("STRIKE"),
		"the STRIDE phase's resolution must never leak into the STRIKE verb_id's own slot"
	)

	# The loop must have auto-advanced into the STRIKE phase, not terminated.
	assert_true(instance._combine_targeting_active, "the loop must still be active -- STRIKE's own phase has not resolved yet")
	assert_true(instance.selection_overlay.is_active(), "the loop must advance into the STRIKE phase, not terminate")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIKE")
	var strike_target_ids: Array = instance.selection_overlay.get_highlighted_target_ids()
	assert_true(
		strike_target_ids.has(skeleton.combatant_id),
		"STRIKE's own phase must offer the Skeleton as reachable from the chosen post-move hex"
	)

	var skeleton_token = instance.hex_grid_view.get_token(skeleton.combatant_id)
	assert_not_null(skeleton_token, "fixture assumption: the Skeleton has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(skeleton_token.hex_coord)

	assert_false(instance.selection_overlay.is_active(), "selection_overlay must return to Layer 1 once both phases resolve")
	assert_false(instance._combine_targeting_active, "the interactive loop must have finished")
	assert_true(instance._combine_targeting_result.get("ok", false), "both phases resolving must report ok:true")

	var accumulated: Dictionary = instance._combine_targeting_result.get("accumulated", {})
	assert_true(accumulated.has("STRIDE") and accumulated.has("STRIKE"), "accumulated must carry BOTH resolved phases")
	assert_eq(
		accumulated["STRIDE"].meta.get("chosen_hex"), chosen_hex,
		"STRIDE's own accumulated entry must carry the STRIDE phase's own chosen hex, never the STRIKE phase's chosen target"
	)
	assert_eq(
		accumulated["STRIKE"].candidate_targets, [skeleton.combatant_id],
		"STRIKE's own accumulated entry must carry ITS OWN phase's candidate_targets, computed from the post-move hex"
	)


# ══════════════════════════════════════════════════════════════════════════
# Structural sanity — the interactive loop reuses the EXACT SAME
# verb_id -> controller registry multi_phase_targeting_controller was
# constructed with, never a second/forked lookup path (ADR-002).
# ══════════════════════════════════════════════════════════════════════════

func test_combine_controller_registry_is_reused_not_forked() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_true(instance._combine_controller_registry.has("STRIDE"))
	assert_true(instance._combine_controller_registry.has("STRIKE"))
	assert_eq(
		instance._combine_controller_registry, instance.multi_phase_targeting_controller._controller_registry,
		"the interactive targeting loop must reuse the EXACT SAME verb_id -> controller registry multi_phase_targeting_controller was constructed with"
	)


func test_empty_queue_is_a_no_op() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance.start_combine_targeting([], _titus(instance), CombineQueueClass.Context.TURN)

	assert_false(instance._combine_targeting_active, "an empty queue must never engage the interactive targeting loop")
	assert_false(instance.selection_overlay.is_active(), "an empty queue must never activate selection_overlay")
