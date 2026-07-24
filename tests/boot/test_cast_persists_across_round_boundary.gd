extends GutTest
## tests/boot/test_cast_persists_across_round_boundary.gd — FEAT-007
## (US-007; FR-006, ADR-001/ADR-006)
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root (never a hand-wired double) keeps an in-progress Fire Bolt cast's
## casting_state genuinely intact across an END-OF-ROUND boundary --
## specifically that committed_energy survives round_session.finish()'s
## per-round EnergyPool.empty() sweep (core/application/round_session.gd's
## finish() doc: "every caster's EnergyPool ... is emptied ... under the
## SAME 'outcome still undecided' guard ... it never reaches, reads, or
## mutates a caster's committed_energy") -- mirroring
## tests/boot/test_first_cast_firebolt.gd's/tests/boot/
## test_continue_cast_firebolt.gd's established "_boot_main_scene()"
## convention, plus tests/gut/test_round_continuation_and_enemy_budget_display.gd's
## established "_force_all_spent() -> End Turn -> round rolls over" pattern
## for deterministically driving a round to completion without waiting on
## the full turn-order cycle.
##
## test_criteria satisfied:
##   "Boot-real test confirms a Fire Bolt cast spanning a round boundary
##   resolves correctly, with committed_energy intact despite the round's
##   energy_pools being emptied"

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/boot/test_first_cast_firebolt.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _find_marigold(instance):
	for combatant in instance._party:
		if combatant.name == "Marigold":
			return combatant
	return null


## _advance_to_marigolds_turn(instance) -> void -- Titus acts first in the
## prologue's turn order (seed=42); pass turns (EndTurnControl is ALWAYS
## available, regardless of whether an action was spent) until it is
## Marigold's live turn.
func _advance_to_marigolds_turn(instance) -> void:
	while not instance.round_session.is_round_over() and instance.round_session.current_actor_entity().name != "Marigold":
		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed while advancing to Marigold's turn")


## _force_all_spent(instance) -- drives every combatant's ActionEconomy to
## Spent via the public spend_reaction() path (mirrors
## tests/gut/test_round_continuation_and_enemy_budget_display.gd's
## identically-named, established helper exactly: deliberately NOT
## spend_action(), since reaction spends are gated ONLY by _is_spent, never
## the per-turn _action_used gate, so they can be applied in a tight loop
## from a test without staging start_of_turn() boundaries). These are the
## SAME economy instances RoundSession reads, since MainScene's
## _EncounterTurnOrderAdapter hands the session encounter.get_action_economy(i)
## directly. Deliberately does NOT touch casting_state -- ActionEconomy and
## CastingState are wholly separate fields.
func _force_all_spent(instance) -> void:
	var order: Array = instance.encounter.get_turn_order()
	for i in range(order.size()):
		var action_economy = instance.encounter.get_action_economy(i)
		while not action_economy.is_spent():
			action_economy.spend_reaction()


func test_committed_energy_and_spell_id_survive_end_of_round_pool_emptying() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_eq(instance.ROUND_NUMBER, 1, "fixture assumption: the encounter opens in round 1")

	# ── Round 1: begin the cast (FEAT-005) ──────────────────────────────────
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast before this test's own cast begins")

	var begin_result: Dictionary = instance.verb_dispatch_controller._verb_bar_cast_spell_execute("fire_bolt")
	assert_true(begin_result.get("success", false), "fixture assumption: the cast must begin successfully")
	assert_true(marigold.is_casting(), "fixture assumption: Marigold must now be mid-cast")

	var expected_spell_id: String = "fire_bolt"
	var expected_remaining_actions: int = 1
	var expected_committed_energy: int = int(marigold.casting_state.get("committed_energy", -1))
	assert_eq(marigold.casting_state.get("spell_id"), expected_spell_id)
	assert_eq(marigold.casting_state.get("remaining_actions"), expected_remaining_actions)

	# ── Force round 1 to its end -- draining every combatant's budget
	# (including the rest of Marigold's own, but never touching
	# casting_state) -- then pressing End Turn once more so RoundSession
	# genuinely reports is_round_over(), driving MainScene's automatic
	# round-over continuation (_on_round_over(): finish() -> ROUND_NUMBER++
	# -> rewire_session(), the SAME production path
	# tests/gut/test_round_continuation_and_enemy_budget_display.gd's
	# "ending turn with all actors spent begins the next round" regression
	# test already proves against this REAL composition root).
	_force_all_spent(instance)
	assert_false(instance.round_session.is_round_over(), "the round is not over until the cursor is actually advanced off the last actor")

	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "EndTurnControl.press() must succeed to end Marigold's turn and drive the round over")
	await get_tree().process_frame

	assert_eq(instance.ROUND_NUMBER, 2, "forcing every actor Spent and ending the turn must roll the encounter into round 2 (fixture assumption, mirrors the pinned round-continuation regression test)")
	assert_false(instance.round_session.is_round_over(), "the freshly begun round 2 must be a LIVE session, not left reporting round-over")

	# ── The round boundary crossed: round 1's RoundSession.finish() emptied
	# EVERY caster's EnergyPool (current -> 0) as part of the transition --
	# but casting_state (spell_id, remaining_actions, committed_energy) lives
	# on the Combatant entity itself, never on the round-scoped RoundSession,
	# so it must be entirely untouched by that sweep.
	assert_true(marigold.is_casting(), "an in-progress cast must survive an end-of-round boundary, not merely an end-of-turn one")
	assert_eq(marigold.casting_state.get("spell_id"), expected_spell_id, "spell_id must be unchanged by the round boundary")
	assert_eq(marigold.casting_state.get("remaining_actions"), expected_remaining_actions, "remaining_actions must be unaffected by the round boundary itself (only Marigold's own continue-cast action decrements it)")
	assert_eq(
		marigold.casting_state.get("committed_energy"), expected_committed_energy,
		"committed_energy must be INTACT across the round boundary despite round_session.finish() emptying every caster's EnergyPool -- committed_energy lives on casting_state, a field EnergyPool.empty() never reaches"
	)

	# Round 2's freshly-created energy pool for Marigold reflects the
	# post-finish() reset (current == 0, i.e. the pool starts empty again for
	# the new round) -- proving the round's pool really was reset, making the
	# committed_energy-is-untouched assertion above a genuine, non-vacuous
	# check rather than one where nothing actually changed.
	var round_2_pool = instance.round_session.get_energy_pool(marigold)
	assert_eq(round_2_pool.current, 0, "round 2's freshly-created energy pool must start empty, confirming round 1's pool was genuinely emptied/replaced -- not merely left alone")

	# ── The cast, still spanning into round 2, resolves correctly: Marigold's
	# NEXT Cast-a-Spell action (no re-selection, no re-payment) drives
	# remaining_actions to 0, with spell_id/committed_energy still intact.
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn in round 2")

	var continue_result: Dictionary = instance.verb_dispatch_controller._verb_bar_cast_spell_execute()
	assert_true(continue_result.get("success", false), "continuing a cast that spans a round boundary must still succeed, with no re-selection (US-006: no selection argument at all)")
	# The "casting_state" key on the ExecuteResult is ContinueCastUseCase's
	# OWN pre-resolution snapshot (SpellActionController._maybe_resolve_cast()
	# only ever ADDS a "resolve_spell_result" key alongside it, never
	# rewrites "casting_state" in place), so it still reads the state exactly
	# as continuing the cast left it, regardless of whether resolution
	# subsequently ran.
	assert_eq(continue_result.get("casting_state", {}).get("remaining_actions"), 0, "Marigold's continuing cast in round 2 must drive remaining_actions to 0, completing the Fire Bolt cast begun in round 1")
	assert_eq(continue_result.get("casting_state", {}).get("spell_id"), expected_spell_id, "spell_id must still be unchanged once the cast completes in round 2")
	assert_eq(
		continue_result.get("casting_state", {}).get("committed_energy"), expected_committed_energy,
		"committed_energy must remain exactly what was reserved back in round 1 -- no re-payment, no drift, even though it spanned a round boundary and an intervening pool reset"
	)

	# FEAT-285 (resolves PR-002/PR-004): MainScene.gd's `_verb_deps()` now
	# wires a real "targeting_candidates_fn" (the living-enemy pool), so the
	# in-range Skeleton is a genuine legal target -- reaching
	# remaining_actions == 0 immediately drives ResolveCastUseCase to
	# completion, which clears the LIVE Combatant's own casting_state field
	# (a separate mutation from the ExecuteResult snapshot asserted above).
	assert_false(marigold.is_casting(), "with a real in-range target now wired, remaining_actions reaching 0 must resolve the cast immediately, even spanning the round boundary")
	assert_true(marigold.casting_state.is_empty(), "the live Combatant's own casting_state must be cleared once the round-spanning cast resolves")
