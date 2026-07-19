extends GutTest
## tests/boot/test_first_cast_firebolt.gd — FEAT-005 (US-005; FR-004)
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root (never a hand-wired double) genuinely begins a Fire Bolt cast for the
## prologue's caster (Marigold) through the SAME CAST_SPELL verb entry point
## production code drives (`_verb_bar_cast_spell_execute()`,
## presentation/verbs/spell_action_controller.gd's SpellActionController) --
## mirroring tests/boot/test_caster_loads_in_prologue.gd's and
## tests/integration/test_reserve_gate_boot_real.gd's established
## "_boot_main_scene()" convention exactly.
##
## Round 1's turn order is Titus, then Marigold, then the Skeleton (pinned by
## tests/integration/test_mainscene_r1_e2e.gd's own established fixture
## note) -- so this suite passes Titus's turn once (EndTurnControl.press(),
## "ALWAYS available" per that same file's doc) to reach Marigold's turn
## before driving the cast.
##
## test_criteria satisfied:
##   2. Fire Bolt (2 actions) begun on turn N shows remaining_actions=1
##      after turn N, and committed_energy is deducted immediately from the
##      round pool.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/boot/test_caster_loads_in_prologue.gd's identically-named/
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
## prologue's turn order (seed=42); pass his turn (EndTurnControl is ALWAYS
## available, regardless of whether an action was spent) so Marigold becomes
## the live current actor.
func _advance_to_marigolds_turn(instance) -> void:
	while not instance.round_session.is_round_over() and instance.round_session.current_actor_entity().name != "Marigold":
		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed while advancing to Marigold's turn")


func test_fire_bolt_begun_reserves_energy_and_leaves_one_remaining_action() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast before this test's own cast begins")

	var pool_before = instance.round_session.get_energy_pool(marigold)
	var balance_before: int = pool_before.current
	var capacity: int = pool_before.capacity
	assert_eq(capacity, marigold.spellcasting_attribute_score, "fixture assumption: the round pool's capacity must be resolved from Marigold's own spellcasting_attribute_score")

	var result: Dictionary = instance._verb_bar_cast_spell_execute("fire_bolt")

	assert_true(result.get("success", false), "casting Fire Bolt on turn N with sufficient/affordable energy must succeed")
	assert_true(marigold.is_casting(), "Marigold must now be mid-cast")

	# Criterion: Fire Bolt (2 actions) begun on turn N shows remaining_actions=1
	# after turn N -- the first action is spent immediately at begin-cast time.
	assert_eq(marigold.casting_state.get("spell_id"), "fire_bolt")
	assert_eq(marigold.casting_state.get("remaining_actions"), 1, "Fire Bolt's 2-action cost must show exactly 1 remaining action immediately after being begun")

	# Criterion: committed_energy deducted immediately from the round pool.
	var committed_energy: int = int(marigold.casting_state.get("committed_energy", -1))
	assert_eq(committed_energy, result.get("casting_state", {}).get("committed_energy"), "the ExecuteResult's casting_state must mirror the live Combatant's own casting_state")

	var pool_after = instance.round_session.get_energy_pool(marigold)
	assert_eq(
		balance_before - pool_after.current, committed_energy,
		"the round energy pool's balance must drop by EXACTLY the spell's committed_energy immediately upon casting"
	)
	assert_same(pool_before, pool_after, "get_energy_pool() must return the SAME live pool instance across calls, never a fresh/reset one")


func test_casting_state_persists_across_a_turn_boundary() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	_advance_to_marigolds_turn(instance)

	var result: Dictionary = instance._verb_bar_cast_spell_execute("fire_bolt")
	assert_true(result.get("success", false), "fixture assumption: the cast must begin successfully")

	# End Marigold's own turn -- casting_state lives on the Combatant entity,
	# not the round-scoped session, so it must survive the turn boundary.
	var press_result: Dictionary = instance.end_turn_control.press()
	assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed for Marigold's own turn")

	assert_true(marigold.is_casting(), "an in-progress cast must survive ending its own caster's turn")
	assert_eq(marigold.casting_state.get("remaining_actions"), 1, "remaining_actions must be unaffected by ending the turn")
