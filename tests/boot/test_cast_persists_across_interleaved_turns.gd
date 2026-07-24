extends GutTest
## tests/boot/test_cast_persists_across_interleaved_turns.gd — FEAT-007
## (US-007; FR-006)
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root (never a hand-wired double) keeps an in-progress Fire Bolt cast's
## casting_state (spell_id, committed_energy) genuinely UNCHANGED while OTHER
## combatants' turns are interleaved in between the caster's own turns --
## aside from remaining_actions, which only ever decrements on the caster's
## OWN Cast-a-Spell action (never merely by the passage of another
## combatant's turn) -- mirroring tests/boot/test_first_cast_firebolt.gd's
## and tests/boot/test_continue_cast_firebolt.gd's established
## "_boot_main_scene()" convention exactly.
##
## Round 1's turn order is Titus, then Marigold, then the Skeleton (pinned by
## tests/integration/test_mainscene_r1_e2e.gd's own established fixture
## note) -- so once Marigold begins her cast and ends her own turn, the very
## next live actor is the Skeleton (an Enemy, auto-driven by
## RoundSession.advance_ai_turn() the instant control passes to it), then
## Titus again, before the cursor returns to Marigold for her SECOND turn of
## the round. Both of those intervening turns are asserted against directly
## below, proving persistence isn't merely "true at the very end" but holds
## at EVERY intermediate checkpoint too.
##
## test_criteria satisfied:
##   "Boot-real test confirms casting_state (spell_id, committed_energy)
##   unchanged aside from remaining_actions decrements across other
##   combatants' interleaved turns"

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
## Marigold's live turn again.
func _advance_to_marigolds_turn(instance) -> void:
	while not instance.round_session.is_round_over() and instance.round_session.current_actor_entity().name != "Marigold":
		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed while advancing to Marigold's turn")


## _assert_casting_state_unchanged(marigold, expected_spell_id,
##   expected_remaining_actions, expected_committed_energy, context) -- the
## shared assertion this test repeats at every interleaved-turn checkpoint,
## so a regression at ANY point in the interleave is caught precisely rather
## than only at the very end.
func _assert_casting_state_unchanged(
	marigold,
	expected_spell_id: String,
	expected_remaining_actions: int,
	expected_committed_energy: int,
	context: String
) -> void:
	assert_true(marigold.is_casting(), "%s: the in-progress cast must still be active" % context)
	assert_eq(marigold.casting_state.get("spell_id"), expected_spell_id, "%s: spell_id must be unchanged" % context)
	assert_eq(marigold.casting_state.get("committed_energy"), expected_committed_energy, "%s: committed_energy must be unchanged" % context)
	assert_eq(marigold.casting_state.get("remaining_actions"), expected_remaining_actions, "%s: remaining_actions must be unaffected by another combatant's interleaved turn" % context)


func test_casting_state_unchanged_across_other_combatants_interleaved_turns() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")

	# ── Turn N: begin the cast (FEAT-005) ───────────────────────────────────
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast before this test's own cast begins")

	var begin_result: Dictionary = instance.verb_dispatch_controller._verb_bar_cast_spell_execute("fire_bolt")
	assert_true(begin_result.get("success", false), "fixture assumption: the cast must begin successfully")

	var expected_spell_id: String = "fire_bolt"
	var expected_remaining_actions: int = 1
	var expected_committed_energy: int = int(marigold.casting_state.get("committed_energy", -1))
	_assert_casting_state_unchanged(marigold, expected_spell_id, expected_remaining_actions, expected_committed_energy, "immediately after begin-cast")

	# End Marigold's own turn N -- the cast is left in-progress (a "free
	# pass" turn end never counts as her continue-cast action).
	var end_turn_n_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_n_result.get("ok", false), "EndTurnControl.press() must succeed for Marigold's own turn N")

	# ── Interleaved turn 1: whichever OTHER combatant now holds the cursor
	# (the Skeleton, an Enemy auto-driven by advance_ai_turn(), per the
	# pinned Titus/Marigold/Skeleton turn order) -- casting_state must be
	# completely unaffected by this turn resolving, whatever it does.
	assert_ne(instance.round_session.current_actor_entity(), marigold, "fixture assumption: control must have passed to a different combatant after Marigold's own turn ended")
	_assert_casting_state_unchanged(marigold, expected_spell_id, expected_remaining_actions, expected_committed_energy, "during the first interleaved (non-Marigold) turn")

	var interleaved_press_1: Dictionary = instance.end_turn_control.press()
	assert_true(interleaved_press_1.get("ok", false), "EndTurnControl.press() must succeed for the first interleaved combatant's turn")
	_assert_casting_state_unchanged(marigold, expected_spell_id, expected_remaining_actions, expected_committed_energy, "immediately after the first interleaved (non-Marigold) turn ended")

	# ── Interleaved turn 2: the SECOND other combatant (Titus, back around)
	# -- casting_state must remain unaffected across this turn too, proving
	# persistence holds across EVERY intervening turn, not merely the first.
	if not instance.round_session.is_round_over() and instance.round_session.current_actor_entity() != marigold:
		_assert_casting_state_unchanged(marigold, expected_spell_id, expected_remaining_actions, expected_committed_energy, "during the second interleaved (non-Marigold) turn")

		var interleaved_press_2: Dictionary = instance.end_turn_control.press()
		assert_true(interleaved_press_2.get("ok", false), "EndTurnControl.press() must succeed for the second interleaved combatant's turn")
		_assert_casting_state_unchanged(marigold, expected_spell_id, expected_remaining_actions, expected_committed_energy, "immediately after the second interleaved (non-Marigold) turn ended")

	# ── Back to Marigold's NEXT turn -- casting_state must have survived
	# every intervening turn intact.
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "it must now be Marigold's NEXT live turn")
	_assert_casting_state_unchanged(marigold, expected_spell_id, expected_remaining_actions, expected_committed_energy, "once control returns to Marigold's own next turn")

	# ── Only NOW, on Marigold's OWN action, does remaining_actions decrement
	# -- proving the earlier interleaved turns genuinely never touched it.
	var continue_result: Dictionary = instance.verb_dispatch_controller._verb_bar_cast_spell_execute()
	assert_true(continue_result.get("success", false), "continuing an in-progress cast with no selection argument must succeed (US-006: no re-selection)")
	# The "casting_state" key on the ExecuteResult is ContinueCastUseCase's
	# OWN pre-resolution snapshot (SpellActionController._maybe_resolve_cast()
	# only ever ADDS a "resolve_spell_result" key alongside it, never
	# rewrites "casting_state" in place), so it still reads the state exactly
	# as continuing the cast left it, regardless of whether resolution
	# subsequently ran.
	assert_eq(continue_result.get("casting_state", {}).get("remaining_actions"), 0, "Marigold's OWN Cast-a-Spell action -- and ONLY that -- must drive remaining_actions to 0")
	assert_eq(continue_result.get("casting_state", {}).get("spell_id"), expected_spell_id, "spell_id must still be unchanged after the continuing cast")
	assert_eq(continue_result.get("casting_state", {}).get("committed_energy"), expected_committed_energy, "committed_energy must still be unchanged after the continuing cast -- no re-payment")

	# FEAT-285 (resolves PR-002/PR-004): MainScene.gd's `_verb_deps()` now
	# wires a real "targeting_candidates_fn" (the living-enemy pool), so the
	# in-range Skeleton is a genuine legal target -- reaching
	# remaining_actions == 0 immediately drives ResolveCastUseCase to
	# completion, which clears the LIVE Combatant's own casting_state field
	# (a separate mutation from the ExecuteResult snapshot asserted above).
	assert_false(marigold.is_casting(), "with a real in-range target now wired, remaining_actions reaching 0 must resolve the cast immediately, even across interleaved turns")
	assert_true(marigold.casting_state.is_empty(), "the live Combatant's own casting_state must be cleared once the interleaved-turn-spanning cast resolves")
