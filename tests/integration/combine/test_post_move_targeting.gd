extends GutTest
## tests/integration/combine/test_post_move_targeting.gd
##
## Integration suite for FEAT-006 (Iteration O "Combine Selection UX";
## US-006; FR-005; ADR-006): "post-move-aware targeting for chained
## sub-actions" — drives core/application/combine/multi_phase_targeting_controller.gd's
## MultiPhaseTargetingController with the REAL
## core/controllers/stride_action_controller.gd StrideActionController AND
## core/controllers/strike_action_controller.gd StrikeActionController
## (never fakes for either verb), REAL core/domain/combatant.gd Combatant
## instances, and REAL core/geometry hex math -- proving the whole seam
## end-to-end: a resolved Stride destination genuinely changes what Strike
## offers, and no actor position is mutated along the way.
##
## test_criteria covered:
##   1. MultiPhaseTargetingController passes the accumulated dict
##      (containing the prior STRIDE result) into
##      StrikeActionController.enter_selection() -- proven by the SAME loop
##      that resolves both phases, not by hand-assembling a context.
##   2. Stride destination hex X yields a Strike candidate_targets set that
##      differs from the candidate_targets computed at the actor's original
##      hex (both are computed and diffed explicitly below).
##   3. Actor's real position is NOT mutated during enter_selection() calls
##      -- asserted after the full targeting loop completes.

const MultiPhaseTargetingControllerClass = preload("res://core/application/combine/multi_phase_targeting_controller.gd")
const StrideActionControllerClass = preload("res://core/controllers/stride_action_controller.gd")
const StrikeActionControllerClass = preload("res://core/controllers/strike_action_controller.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")


func _actor() -> CombatantClass:
	var c := CombatantClass.new("titus", "Titus", "Player", HexCoordClass.new(0, 0))
	c.weapon = {"name": "Sword"}
	c.hp_current = 10
	c.hp_max = 10
	return c


## _skeleton() -> Combatant -- positioned at (3,0): OUT of melee reach of the
## actor's real (0,0) start hex (distance 3), but ADJACENT (distance 1) to
## the Stride destination (2,0) this suite drives the actor to.
func _skeleton() -> CombatantClass:
	var c := CombatantClass.new("skeleton", "Skeleton", "Enemy", HexCoordClass.new(3, 0))
	c.weapon = {"name": "Claws"}
	c.hp_current = 8
	c.hp_max = 8
	return c


func _entries() -> Array:
	return [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]


func test_stride_destination_changes_strike_candidate_targets_versus_original_hex() -> void:
	var actor := _actor()
	var skeleton := _skeleton()
	var actor_start_hex := actor.hex_coord

	var stride_destination := HexCoordClass.new(2, 0)
	assert_eq(
		HexCoordClass.new(actor_start_hex.q, actor_start_hex.r).equals(HexCoordClass.new(0, 0)), true,
		"fixture assumption: the actor starts at (0,0)"
	)

	# ── Baseline: candidate_targets computed at the actor's ORIGINAL hex
	# (no chained Stride) -- the Skeleton is genuinely unreachable from here. ─
	var strike_controller := StrikeActionControllerClass.new({
		"candidate_targets_fn": func(): return [skeleton],
	})
	var baseline: Object = strike_controller.enter_selection({"actor_id": actor, "order_index": 0})
	assert_false(baseline.ok, "the Skeleton must be unreachable from the actor's ORIGINAL hex")

	# ── Drive the REAL MultiPhaseTargetingController loop -- STRIDE resolves
	# to `stride_destination` (the seam FEAT-006 adds to
	# MultiPhaseTargetingController.execute()'s own `resolved_selections`
	# param), then STRIKE's OWN enter_selection() call is made by the SAME
	# loop, receiving the accumulated STRIDE result. ───────────────────────
	var stride_controller := StrideActionControllerClass.new({
		"other_combatants_fn": func(): return [skeleton],
	})
	var targeting_controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride_controller, "STRIKE": strike_controller},
		"combine_action_controller": null,
	})

	var result: Dictionary = targeting_controller.execute(
		_entries(), actor, CombineQueueClass.Context.TURN, {"STRIDE": stride_destination}
	)

	assert_true(result.get("ok", false), "the full targeting loop must resolve ok:true (result: %s)" % [result])

	var accumulated: Dictionary = result.get("accumulated", {})
	assert_true(accumulated.has("STRIDE"), "accumulated must carry the resolved STRIDE phase")
	assert_true(accumulated.has("STRIKE"), "accumulated must carry the resolved STRIKE phase")
	assert_eq(accumulated["STRIDE"].meta.get("chosen_hex"), stride_destination, "the accumulated STRIDE entry must carry the resolved destination hex")

	# ── Criterion 2 — the Strike candidate_targets set computed VIA the
	# chained loop (post-move hex) must differ from the baseline (original
	# hex) set: the Skeleton is now offered. ────────────────────────────────
	var chained_targets: Array = accumulated["STRIKE"].candidate_targets
	assert_eq(chained_targets, ["skeleton"], "candidate_targets reachable from the Stride destination must include the now-adjacent Skeleton")
	assert_ne(chained_targets, baseline.candidate_targets, "the chained (post-move) candidate_targets set must differ from the original-hex baseline")

	# ── Criterion 3 — the actor's REAL position was never mutated by any
	# enter_selection() call across the whole targeting loop. ──────────────
	assert_eq(actor.hex_coord.q, 0, "the actor's real hex_coord.q must remain unchanged after targeting")
	assert_eq(actor.hex_coord.r, 0, "the actor's real hex_coord.r must remain unchanged after targeting")
	assert_same(actor.hex_coord, actor_start_hex, "the actor's hex_coord reference must be untouched (no positional mutation of any kind)")


func test_without_a_resolved_stride_selection_strike_falls_back_to_actors_real_hex() -> void:
	# Sanity/regression: when STRIDE's own phase does NOT resolve a
	# chosen_hex (no resolved_selections entry supplied), STRIKE must fall
	# back to the actor's real hex -- proving the substitution is additive,
	# not a hard requirement that breaks a queue lacking a resolved Stride.
	var actor := _actor()
	var adjacent := CombatantClass.new("adjacent_enemy", "Adjacent", "Enemy", HexCoordClass.new(1, 0))
	adjacent.weapon = {"name": "Claws"}
	adjacent.hp_current = 5
	adjacent.hp_max = 5

	var stride_controller := StrideActionControllerClass.new({
		"other_combatants_fn": func(): return [adjacent],
	})
	var strike_controller := StrikeActionControllerClass.new({
		"candidate_targets_fn": func(): return [adjacent],
	})
	var targeting_controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride_controller, "STRIKE": strike_controller},
		"combine_action_controller": null,
	})

	var result: Dictionary = targeting_controller.execute(_entries(), actor)

	assert_true(result.get("ok", false))
	var accumulated: Dictionary = result.get("accumulated", {})
	assert_eq(accumulated["STRIDE"].meta.get("chosen_hex"), null, "no resolved_selections supplied -- STRIDE's own descriptor must carry no chosen_hex")
	assert_eq(accumulated["STRIKE"].candidate_targets, ["adjacent_enemy"], "STRIKE must fall back to the actor's real hex when STRIDE resolved no chosen_hex")
