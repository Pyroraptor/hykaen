extends GutTest
## tests/boot/test_continue_cast_firebolt.gd — FEAT-006 (US-006; FR-005)
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root (never a hand-wired double) genuinely CONTINUES an in-progress Fire
## Bolt cast for the prologue's caster (Marigold) through the SAME
## CAST_SPELL verb entry point production code drives
## (`_verb_bar_cast_spell_execute()`,
## presentation/verbs/spell_action_controller.gd's SpellActionController) --
## mirroring tests/boot/test_first_cast_firebolt.gd's established
## "_boot_main_scene()" convention exactly.
##
## Round 1's turn order is Titus, then Marigold, then the Skeleton (pinned by
## tests/integration/test_mainscene_r1_e2e.gd's own established fixture
## note) -- so this suite passes Titus's turn once (EndTurnControl.press(),
## "ALWAYS available" per that same file's doc) to reach Marigold's turn,
## begins a Fire Bolt cast (2 actions -- leaves remaining_actions == 1), ends
## Marigold's own turn, cycles the Skeleton's + Titus's turns back around to
## Marigold's NEXT turn, then drives a SECOND CAST_SPELL action with NO
## selection argument at all (US-006: the actor is already mid-cast, so no
## re-selection is possible/needed).
##
## test_criteria satisfied:
##   "Boot-real test: second Cast-a-Spell action on the same caster drives
##   remaining_actions to 0"

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
## Marigold's live turn again -- whether that is her FIRST turn this round
## or a LATER round's turn, after the Skeleton and Titus have each acted.
func _advance_to_marigolds_turn(instance) -> void:
	while not instance.round_session.is_round_over() and instance.round_session.current_actor_entity().name != "Marigold":
		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed while advancing to Marigold's turn")


func test_second_cast_spell_action_on_same_caster_drives_remaining_actions_to_zero() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")

	# ── Turn N: begin the cast (FEAT-005) ───────────────────────────────────
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast before this test's own cast begins")

	var begin_result: Dictionary = instance._verb_bar_cast_spell_execute("fire_bolt")
	assert_true(begin_result.get("success", false), "fixture assumption: the cast must begin successfully")
	assert_true(marigold.is_casting(), "fixture assumption: Marigold must now be mid-cast")
	assert_eq(marigold.casting_state.get("remaining_actions"), 1, "fixture assumption: Fire Bolt's 2-action cost must show exactly 1 remaining action immediately after being begun")
	var committed_energy_after_begin: int = int(marigold.casting_state.get("committed_energy", -1))

	var end_turn_n_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_n_result.get("ok", false), "EndTurnControl.press() must succeed for Marigold's own turn N")

	# ── Cycle the Skeleton's + Titus's turns back around to Marigold's NEXT
	# turn -- casting_state lives on the Combatant entity, not the
	# round-scoped session, so it must survive every intervening turn.
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "it must now be Marigold's NEXT live turn")
	assert_true(marigold.is_casting(), "the in-progress cast must survive every intervening turn up to Marigold's next turn")
	assert_eq(marigold.casting_state.get("remaining_actions"), 1, "remaining_actions must be unaffected by intervening turns that are not Marigold's own")

	# ── Turn N+k: continue the cast (FEAT-006, US-006) -- NO selection
	# argument at all, proving no re-selection occurs.
	var continue_result: Dictionary = instance._verb_bar_cast_spell_execute()

	assert_true(continue_result.get("success", false), "continuing an in-progress cast with no selection argument must succeed (US-006: no re-selection)")
	# The "casting_state" key on the ExecuteResult is ContinueCastUseCase's
	# OWN pre-resolution snapshot (SpellActionController._maybe_resolve_cast()
	# only ever ADDS a "resolve_spell_result" key alongside it -- it never
	# rewrites "casting_state" in place), so it still reads remaining_actions
	# == 0 / spell_id == "fire_bolt" / committed_energy unchanged regardless
	# of whether resolution subsequently ran.
	assert_eq(continue_result.get("casting_state", {}).get("remaining_actions"), 0, "a second Cast-a-Spell action on the same caster must drive remaining_actions to 0")
	assert_eq(continue_result.get("casting_state", {}).get("spell_id"), "fire_bolt", "spell_id must be unchanged by ContinueCastUseCase -- no re-selection")
	# No re-payment of energy: committed_energy is carried through unchanged,
	# and the round energy pool balance is untouched by this continue-cast
	# action.
	assert_eq(continue_result.get("casting_state", {}).get("committed_energy"), committed_energy_after_begin, "committed_energy must be unchanged by ContinueCastUseCase -- no re-payment of energy")

	# FEAT-285 (resolves PR-002/PR-004): MainScene.gd's `_verb_deps()` now
	# wires a real "targeting_candidates_fn" (the living-enemy pool), so the
	# in-range Skeleton is a genuine legal target -- reaching
	# remaining_actions == 0 immediately drives ResolveCastUseCase to
	# completion, which clears the LIVE Combatant's own casting_state field
	# (a separate mutation from the ExecuteResult snapshot asserted above).
	assert_false(marigold.is_casting(), "with a real in-range target now wired, remaining_actions reaching 0 must resolve the cast immediately")
	assert_true(marigold.casting_state.is_empty(), "the live Combatant's own casting_state must be cleared once resolution completes")
