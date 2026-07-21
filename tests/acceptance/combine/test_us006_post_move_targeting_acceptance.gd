extends GutTest
## tests/acceptance/combine/test_us006_post_move_targeting_acceptance.gd —
## FEAT-303 (Iteration O "Combine Selection UX"; CHECKLIST-3).
##
## Scripted acceptance-test evidence for US-006 ("As a player who Combines
## Stride into Strike, the Strike phase's candidate targets must be computed
## from where Stride WOULD move me, not from where I'm currently standing --
## so a target that is only in reach AFTER the move is genuinely offered").
##
## Exercises the REAL, already-shipped
## core/application/combine/multi_phase_targeting_controller.gd
## MultiPhaseTargetingController driving the REAL
## core/controllers/stride_action_controller.gd StrideActionController and
## core/controllers/strike_action_controller.gd StrikeActionController
## (never fakes for either verb) -- mirrors
## tests/integration/combine/test_post_move_targeting.gd's own "boot-real
## controllers" convention -- this suite exists to give the
## deployment-readiness checklist an explicit, individually-named,
## CI-verifiable trace back to US-006's own acceptance behavior.
##
## test_criteria (feature spec, verbatim): "test_us006 asserts Strike
## candidate_targets are computed from the accumulated Stride destination
## hex, not the original hex."

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


## Skeleton at (2,0): distance 2 from the actor's ORIGINAL (0,0) hex (out of
## melee reach), but distance 1 (adjacent, in reach) from the Stride
## destination (1,0) this suite drives the actor to.
func _skeleton() -> CombatantClass:
	var c := CombatantClass.new("skeleton", "Skeleton", "Enemy", HexCoordClass.new(2, 0))
	c.weapon = {"name": "Claws"}
	c.hp_current = 8
	c.hp_max = 8
	return c


func _entries() -> Array:
	return [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 1, "STRIKE"),
	]


func test_us006_strike_candidate_targets_computed_from_accumulated_stride_destination_not_original_hex() -> void:
	var actor := _actor()
	var skeleton := _skeleton()
	var stride_destination := HexCoordClass.new(1, 0)

	# Baseline: candidate_targets computed at the actor's ORIGINAL hex, with
	# no chained Stride -- the Skeleton must be unreachable from here.
	var baseline_strike_controller := StrikeActionControllerClass.new({
		"candidate_targets_fn": func(): return [skeleton],
	})
	var baseline: Object = baseline_strike_controller.enter_selection({"actor_id": actor, "order_index": 0})
	assert_false(baseline.ok, "US-006 fixture assumption: the Skeleton must be unreachable from the actor's original (0,0) hex")

	# The REAL MultiPhaseTargetingController loop: STRIDE resolves to
	# `stride_destination`, and STRIKE's own enter_selection() -- called by
	# the SAME loop -- must receive that accumulated STRIDE result.
	var stride_controller := StrideActionControllerClass.new({
		"other_combatants_fn": func(): return [skeleton],
	})
	var strike_controller := StrikeActionControllerClass.new({
		"candidate_targets_fn": func(): return [skeleton],
	})
	var targeting_controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride_controller, "STRIKE": strike_controller},
		"combine_action_controller": null,
	})

	var result: Dictionary = targeting_controller.execute(
		_entries(), actor, CombineQueueClass.Context.TURN, {"STRIDE": stride_destination}
	)

	assert_true(result.get("ok", false), "US-006: the chained Stride-then-Strike targeting loop must resolve ok=true (result: %s)" % [result])
	var accumulated: Dictionary = result.get("accumulated", {})
	assert_eq(accumulated["STRIDE"].meta.get("chosen_hex"), stride_destination, "US-006: the accumulated STRIDE entry must carry the resolved destination hex")

	var chained_targets: Array = accumulated["STRIKE"].candidate_targets
	assert_eq(chained_targets, ["skeleton"], "US-006: Strike's candidate_targets must be computed from the accumulated Stride DESTINATION hex, now placing the Skeleton in reach")
	assert_ne(chained_targets, baseline.candidate_targets, "US-006: the post-move candidate_targets set must differ from the original-hex baseline")

	# The actor's REAL position must never be mutated by any of this.
	assert_eq(actor.hex_coord.q, 0, "US-006: the actor's real hex_coord must remain unmutated by enter_selection() calls")
	assert_eq(actor.hex_coord.r, 0, "US-006: the actor's real hex_coord must remain unmutated by enter_selection() calls")
