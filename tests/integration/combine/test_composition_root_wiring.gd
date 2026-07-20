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
## FEAT-299 (resolves DEF-NEW-004): before this feature, both tests below
## stopped at `instance._combine_targeting_result.get("ok", false)` --
## proving the WIRING routed a resolved value into the right accumulated
## slot, but never proving the real, live-wired core/controllers/
## combine_action_controller.gd CombineActionController.execute()
## (`_core_combine_action_controller`, FEAT-297/298) this same real signal
## chain hands off to on loop exhaustion actually MOVED the actor, DAMAGED
## the target, or CHARGED the economy -- exactly the class of gap that let
## DEF-NEW-002/DEF-NEW-003 ship undetected despite this suite already
## driving the real signal chain. Both tests now additionally assert on
## `execution_result` (the real CombineActionController.execute() return
## Dictionary the same `_combine_targeting_result` already carries) and on
## `titus.hex_coord` / `skeleton.hp_current` / the live ActionEconomy --
## real actor/target/economy state, not merely `execution_result.ok`.
##
## Standalone (non-Combine) Stride/Strike regression coverage lives in the
## sibling tests/regression/combine/test_selection_overlay_unmodified.gd
## suite, not here (this file is scoped to the NEW Combine-targeting wiring
## itself).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const HexMathClass = preload("res://core/geometry/hex_math.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/regression/test_strike_end_to_end_unchanged.gd's/
## tests/gut/test_stride_layer2_integration.gd's identically-valued
## constant): Titus acts first and the sole enemy (Skeleton) starts adjacent
## to him.
const PROLOGUE_SEED: int = 42

## AC_GUARANTEED_HIT -- FEAT-299 (resolves DEF-NEW-004): mirrors this
## project's established convention (e.g. tests/integration/
## test_combine_execute_stride_then_strike.gd) for making the two-phase
## test's own final Strike damage assertion deterministic, independent of
## the real RNG stream, rather than relying on a real-but-unpinned hit
## chance at PROLOGUE_SEED.
const AC_GUARANTEED_HIT: int = -1000


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


## _drain_action_economy_to_reserve_floor(ae) -> void -- FEAT-299 (resolves
## DEF-NEW-004): mirrors tests/integration/test_combine_execute_stride_then_strike.gd's
## / tests/integration/test_reserve_gate_boot_real.gd's identically-named/
## purposed helper: spends reactions off the Skeleton's OWN real, live
## ActionEconomy one at a time (spend_reaction(), never a hand-constructed/
## fresh ActionEconomy) until exactly the RESERVE floor remains, so
## infrastructure/ai_reaction_policy.gd's real RESERVE gate forces every
## reaction (Dodge included) to Pass regardless of how "worthwhile"
## AC_GUARANTEED_HIT would otherwise make Dodge look -- making the final
## Strike damage assertion below deterministic.
func _drain_action_economy_to_reserve_floor(ae) -> void:
	while ae.get_remaining() > ActionEconomyClass.RESERVE:
		ae.spend_reaction()
	assert_eq(ae.get_remaining(), ActionEconomyClass.RESERVE, "fixture assumption: the Skeleton's own live ActionEconomy must be drained to exactly the RESERVE floor")


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

	var actor_start_hex = actor.hex_coord
	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var actions_before: int = economy.get_remaining()
	var stamina_before: int = actor.stamina
	assert_true(stamina_before > 0, "fixture assumption: Titus starts with positive Stamina")

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

	# ── FEAT-299 (resolves DEF-NEW-004) -- real actor/economy state, not
	# merely execution_result.ok: the real, live-wired core CombineActionController
	# this same real signal chain hands off to on loop exhaustion actually
	# moved Titus to the clicked hex and charged exactly 1 action + 1 Stamina. ──
	var execution_result: Dictionary = instance._combine_targeting_result.get("execution_result", {})
	assert_true(execution_result.get("ok", false), "the real, live-wired CombineActionController.execute() must resolve ok=true (result: %s)" % [execution_result])
	assert_true(actor.hex_coord.equals(chosen_hex), "actor.hex_coord must equal the EXACT hex the player clicked via the real SelectionOverlay UI")
	assert_false(actor.hex_coord.equals(actor_start_hex), "actor.hex_coord must have actually changed from its pre-Combine start hex")
	assert_eq(actions_before - economy.get_remaining(), 1, "the live ActionEconomy must show exactly 1 action spent")
	assert_eq(stamina_before - actor.stamina, 1, "the live actor's Stamina must show exactly 1 Stamina spent")


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

	var actor_start_hex = actor.hex_coord
	var skeleton_hp_before: int = skeleton.hp_current
	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var actions_before: int = economy.get_remaining()
	var stamina_before: int = actor.stamina
	assert_true(stamina_before > 0, "fixture assumption: Titus starts with positive Stamina")

	# ── FEAT-299 (resolves DEF-NEW-004): make the eventual Strike damage
	# assertion below deterministic, independent of the real RNG stream,
	# mirroring this project's established AC_GUARANTEED_HIT convention. ────
	skeleton.ac = AC_GUARANTEED_HIT
	var skeleton_action_economy = instance._action_economy_for(skeleton)
	assert_not_null(skeleton_action_economy, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")
	_drain_action_economy_to_reserve_floor(skeleton_action_economy)

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

	# ── FEAT-299 (resolves DEF-NEW-004) -- real actor/target/economy state,
	# not merely execution_result.ok: the real, live-wired core
	# CombineActionController this same real signal chain hands off to on
	# loop exhaustion actually moved Titus to the clicked hex, dealt real
	# Strike damage to the Skeleton from that post-move position, and charged
	# exactly 1 action + 1 Stamina for the WHOLE Combine (never a
	# double-charge from the two dispatched sub-actions). ────────────────────
	var execution_result: Dictionary = instance._combine_targeting_result.get("execution_result", {})
	assert_true(execution_result.get("ok", false), "the real, live-wired CombineActionController.execute() must resolve ok=true (result: %s)" % [execution_result])

	var resolution_log: Array = execution_result.get("resolution_log", [])
	assert_eq(resolution_log.size(), 2, "resolution_log must carry exactly one entry per dispatched sub-action")
	assert_eq(resolution_log[0].get("verb_id"), "STRIDE", "the resolution log must record STRIDE resolving before STRIKE")
	assert_eq(resolution_log[1].get("verb_id"), "STRIKE")

	assert_true(actor.hex_coord.equals(chosen_hex), "actor.hex_coord must equal the EXACT Stride hex the player clicked via the real SelectionOverlay UI")
	assert_false(actor.hex_coord.equals(actor_start_hex), "actor.hex_coord must have actually changed from its pre-Combine start hex")
	assert_true(skeleton.hp_current < skeleton_hp_before, "the Skeleton must have taken real Strike damage from the post-move position")
	assert_eq(actions_before - economy.get_remaining(), 1, "the live ActionEconomy must show exactly 1 action spent for the WHOLE Combine")
	assert_eq(stamina_before - actor.stamina, 1, "the live actor's Stamina must show exactly 1 Stamina spent for the WHOLE Combine")


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
