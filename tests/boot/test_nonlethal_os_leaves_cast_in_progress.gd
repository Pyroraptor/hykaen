extends GutTest
## tests/boot/test_nonlethal_os_leaves_cast_in_progress.gd — FEAT-281
## (US-016; FR-018)
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root (never a hand-wired double) leaves a caster's in-progress
## casting_state COMPLETELY UNCHANGED when a provoked Opportunistic Strike
## is genuinely NON-lethal — closing the sibling gap tests/boot/
## test_lethal_os_cancels_cast.gd (FEAT-280) deliberately left open (that
## suite pins the caster's hp BELOW the reactor's minimum possible damage
## roll so the reaction always cancels the cast; this suite instead pins a
## comfortably-survivable hp, mirroring tests/boot/
## test_cast_provokes_opportunistic_strike.gd's (FEAT-279) own
## AC_GUARANTEED_HIT/SURVIVABLE_HP technique, so the SAME reaction window
## resolves a real, positive-damage Strike that never downs the caster).
##
## Drives the SAME real, composition-root-bound CAST_SPELL entry point a
## live player click resolves through (`_verb_bar_cast_spell_execute()`),
## routed through presentation/verbs/spell_action_controller.gd's
## `_maybe_cancel_cast()` (FEAT-280's helper) -- proving its "stride_should_
## commit == true -> return result UNCHANGED" branch (the mirror image of
## FEAT-280's own cancel branch) leaves casting_state's THREE tracked
## fields (spell_id, remaining_actions, committed_energy) byte-for-byte
## identical to whatever BeginCastUseCase/ContinueCastUseCase alone would
## have produced, and that the cast goes on to resolve NORMALLY on its
## following action -- through the SAME real ResolveSpellController wiring
## tests/boot/test_fire_bolt_full_cast_e2e_log.gd (FEAT-276) already
## establishes.
##
## Verifies (test_criteria):
##   1. "Boot-real test confirms a non-lethal OS during a casting action
##      leaves casting_state (spell_id, remaining_actions, committed_energy)
##      unchanged."
##   2. "Boot-real test confirms the cast resolves normally on the
##      subsequent action after a non-lethal OS."

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass            = preload("res://core/rules/round_events.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")
const CombatLogEntryClass         = preload("res://core/domain/combat_log_entry.gd")
const SpellActionControllerClass  = preload("res://presentation/verbs/spell_action_controller.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const TargetingPortClass          = preload("res://core/application/ports/targeting_port.gd")
const ResolutionPortClass         = preload("res://core/application/ports/resolution_port.gd")
const SeededRandomAdapterClass    = preload("res://core/combat/seeded_random_adapter.gd")
const CombatLogPanelAdapterClass  = preload("res://presentation/ui/combat_log_panel_adapter.gd")
const ErrorCodeClass              = preload("res://core/application/ports/errors.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_cast_provokes_opportunistic_strike.gd's own
## identically-named/valued constant).
const PROLOGUE_SEED: int = 42

## AC_GUARANTEED_HIT / SURVIVABLE_HP — mirror tests/boot/
## test_cast_provokes_opportunistic_strike.gd's identically-named/valued
## constants: an absurdly low AC guarantees the Skeleton's resolved
## Opportunistic Strike hits with no RNG/seed edits, and a comfortably-high
## hp keeps Marigold alive well past every Strike this suite drives against
## her, so the reaction is genuinely NON-lethal -- never a fabricated
## "mover_downed" flag.
const AC_GUARANTEED_HIT: int = -1000
const SURVIVABLE_HP: int = 500


## ScriptedTargetingPort -- always returns the same pre-picked target,
## mirroring tests/boot/test_fire_bolt_full_cast_e2e_log.gd's identically-
## shaped test double.
class ScriptedTargetingPort:
	extends TargetingPortClass
	var scripted_target = null

	func request_single_target(_legal_targets: Array):
		return scripted_target


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
## Marigold's live turn (mirrors every other Cast-a-Spell boot-real suite's
## identically-named helper).
func _advance_to_marigolds_turn(instance) -> void:
	while not instance.round_session.is_round_over() and instance.round_session.current_actor_entity().name != "Marigold":
		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed while advancing to Marigold's turn")


## _reposition_marigold_adjacent_to_skeleton(marigold, skeleton) -> void --
## mirrors tests/boot/test_cast_provokes_opportunistic_strike.gd's own
## identically-named helper exactly: forces Marigold's OWN live hex_coord
## adjacent to the Skeleton's, since the prologue fixture's own boot
## positions leave her two hexes away.
func _reposition_marigold_adjacent_to_skeleton(marigold, skeleton) -> void:
	marigold.hex_coord = HexCoordClass.new(skeleton.hex_coord.q + 1, skeleton.hex_coord.r)


func _attack_events(instance) -> Array:
	return instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)


## _wire_real_cast_spell_controller(instance, skeleton) -> CombatLogPanelAdapter
## -- mirrors tests/boot/test_fire_bolt_full_cast_e2e_log.gd's identically-
## named helper: swaps a REAL SpellActionController (built from the booted
## composition root's OWN `_verb_deps()` dict, byte-for-byte unchanged)
## carrying a resolve_spell_controller wired with a REAL
## ResolutionPort.ResolutionRulesAdapter + CombatLogPanelAdapter into
## `instance._controllers["CAST_SPELL"]`, the SAME memoized slot
## MainScene.gd's own `_controller("CAST_SPELL")` reads -- so this suite's
## second criterion (the cast resolves NORMALLY on the action after a
## non-lethal OS) can be asserted through the SAME production
## `_verb_bar_cast_spell_execute()` shim every other boot-real Cast-a-Spell
## suite drives, never a bespoke resolution path this test invents on its
## own.
func _wire_real_cast_spell_controller(instance, skeleton):
	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = skeleton

	var combat_log_panel := CombatLogPanelAdapterClass.new()
	var resolution_port = ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PROLOGUE_SEED))

	var deps: Dictionary = instance._verb_deps().duplicate()
	deps["resolve_spell_controller"] = ResolveSpellControllerClass.new({
		"targeting_port": targeting,
		"candidates_fn": func(): return [skeleton],
		"resolution_port": resolution_port,
		"combat_log_port": combat_log_panel,
	})
	instance._controllers["CAST_SPELL"] = SpellActionControllerClass.new(deps)
	return combat_log_panel


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — a non-lethal Opportunistic Strike provoked mid-cast leaves
# casting_state (spell_id, remaining_actions, committed_energy) unchanged.
# ══════════════════════════════════════════════════════════════════════════

func test_nonlethal_opportunistic_strike_during_first_cast_leaves_casting_state_unchanged() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_true(marigold.known_spell_ids.has("fire_bolt"), "fixture assumption: Marigold must know Fire Bolt")

	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_true(
		not skeleton.weapon.has("range_hexes"),
		"fixture assumption: the Skeleton's real weapon carries melee reach (no 'range_hexes' key)"
	)

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast before this test's own cast begins")

	_reposition_marigold_adjacent_to_skeleton(marigold, skeleton)

	# Force a GENUINELY non-lethal Opportunistic Strike against Marigold (the
	# caster) -- guaranteed hit, hp comfortably survivable -- never a
	# fabricated "mover_downed" flag.
	marigold.ac = AC_GUARANTEED_HIT
	marigold.hp_current = SURVIVABLE_HP
	marigold.hp_max = SURVIVABLE_HP
	var marigold_hp_before: int = marigold.hp_current

	var skeleton_ae = instance._action_economy_for(skeleton)
	assert_not_null(skeleton_ae, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")
	var skeleton_budget_before: int = skeleton_ae.get_remaining()

	# ── Drive the SAME real, composition-root-bound CAST_SPELL entry point a
	# live player click resolves through -- a FIRST-cast action (Fire Bolt's
	# 2-action cost leaves the cast genuinely "in progress" -- remaining_
	# actions == 1 -- immediately after BeginCastUseCase runs, followed by
	# the non-lethal reaction). ─────────────────────────────────────────────
	assert_false(instance.reaction_prompt_ui.is_open(), "fixture assumption: no pop-up is open before this cast is driven")
	var begin_result: Dictionary = instance._verb_bar_cast_spell_execute("fire_bolt")

	# The enemy reactor's own OpportunisticStrike decision routes
	# synchronously through the REAL AIReactionPolicy -- never a pop-up.
	assert_false(instance.reaction_prompt_ui.is_open(), "the enemy reactor's own OpportunisticStrike decision is resolved synchronously via AIReactionPolicy -- no pop-up may ever open for it")

	# ── Criterion: the reaction itself genuinely, NON-lethally resolved. ───
	var reaction_result: Dictionary = begin_result.get("reaction_result", {})
	var reactions: Array = reaction_result.get("reactions", [])
	assert_eq(reactions.size(), 1, "exactly one reactor (the adjacent Skeleton) must have been offered a window")
	assert_eq(reactions[0].get("choice", ""), "opportunistic_strike", "the REAL AIReactionPolicy must genuinely choose opportunistic_strike when melee-legal and the RESERVE gate is open")
	var strike_result: Dictionary = reactions[0].get("strike_result", {})
	assert_true(strike_result.get("resolved", false), "the reactor's opportunistic_strike choice must FULLY resolve a real Strike")
	assert_true(strike_result.get("ok", false), "the resolved Strike must succeed")
	assert_false(strike_result.get("target_defeated", true), "Marigold's SURVIVABLE_HP floor must NOT be defeated by the Skeleton's real damage roll -- the reaction must be genuinely non-lethal")
	assert_false(reaction_result.get("mover_downed", true), "a non-lethal Opportunistic Strike must leave mover_downed false")
	assert_true(reaction_result.get("stride_should_commit", false), "a non-lethal Opportunistic Strike must leave stride_should_commit true -- the cast is never cancelled")

	var marigold_hp_after: int = marigold.hp_current
	assert_true(marigold_hp_after < marigold_hp_before, "Marigold (the caster) must show real, positive damage from the Skeleton's resolved Opportunistic Strike")
	assert_true(marigold_hp_after > 0, "Marigold must still be alive -- the reaction must be genuinely non-lethal, never a fabricated survival")

	# ── The criterion itself: casting_state's three tracked fields are
	# EXACTLY what BeginCastUseCase alone (Fire Bolt: actions_cost=2,
	# energy_cost=0) would have produced -- byte-for-byte unaffected by the
	# non-lethal reaction that fired in between. ───────────────────────────
	assert_true(begin_result.get("success", false), "the first-cast Fire Bolt action must still report success")
	assert_true(marigold.is_casting(), "Marigold must still be mid-cast -- a non-lethal Opportunistic Strike must never cancel the cast")
	assert_eq(begin_result.get("error"), ErrorCodeClass.NONE, "no cancellation error must be reported for a non-lethal Opportunistic Strike")

	var casting_state: Dictionary = begin_result.get("casting_state", {})
	assert_eq(casting_state.get("spell_id"), "fire_bolt", "casting_state.spell_id must be unchanged by the non-lethal Opportunistic Strike")
	assert_eq(casting_state.get("remaining_actions"), 1, "casting_state.remaining_actions must be unchanged by the non-lethal Opportunistic Strike (Fire Bolt's 2-action cost, first action already spent)")
	assert_eq(casting_state.get("committed_energy"), 0, "casting_state.committed_energy must be unchanged by the non-lethal Opportunistic Strike (Fire Bolt costs 0 energy)")

	# The live Combatant's own casting_state field mirrors the ExecuteResult
	# exactly -- no divergence between what the caller observes and what is
	# actually persisted on the entity.
	assert_eq(marigold.casting_state.get("spell_id"), "fire_bolt", "the live Combatant's own casting_state.spell_id must be unchanged")
	assert_eq(marigold.casting_state.get("remaining_actions"), 1, "the live Combatant's own casting_state.remaining_actions must be unchanged")
	assert_eq(marigold.casting_state.get("committed_energy"), 0, "the live Combatant's own casting_state.committed_energy must be unchanged")

	assert_eq(
		skeleton_ae.get_remaining(), skeleton_budget_before - 1,
		"the Skeleton's own live ActionEconomy budget must drop by EXACTLY 1 -- paid via spend_reaction(), never spend_action()"
	)

	var attack_events: Array = _attack_events(instance)
	assert_eq(attack_events.size(), 1, "exactly one Strike (the Skeleton's non-lethal Opportunistic Strike) must have resolved")
	var attack_event = attack_events[0]
	assert_eq(attack_event.attacker_name, "Skeleton", "the resolved Strike must be attributed to the Skeleton (the reactor), not Marigold (the caster)")
	assert_eq(attack_event.target_name, "Marigold", "the resolved Strike's target must be Marigold (the caster)")
	assert_true(attack_event.hit, "the guaranteed-hit AC must actually produce a hit")
	assert_eq(marigold_hp_before - marigold_hp_after, attack_event.damage_final, "Marigold's hp_current must drop by EXACTLY the resolved Strike's damage_final")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — the cast resolves NORMALLY on the subsequent action after a
# non-lethal Opportunistic Strike.
# ══════════════════════════════════════════════════════════════════════════

func test_cast_resolves_normally_on_subsequent_action_after_nonlethal_opportunistic_strike() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter's real enemy roster carries exactly the Skeleton")
	var skeleton = instance._enemies[0]
	var skeleton_hp_before: int = skeleton.hp_current

	var combat_log_panel = _wire_real_cast_spell_controller(instance, skeleton)

	# ── Turn N: begin the cast (Fire Bolt's 2-action cost leaves
	# remaining_actions == 1), provoking a first non-lethal Opportunistic
	# Strike. ───────────────────────────────────────────────────────────────
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast before this test's own cast begins")

	_reposition_marigold_adjacent_to_skeleton(marigold, skeleton)
	marigold.ac = AC_GUARANTEED_HIT
	marigold.hp_current = SURVIVABLE_HP
	marigold.hp_max = SURVIVABLE_HP

	var begin_result: Dictionary = instance._verb_bar_cast_spell_execute("fire_bolt")
	assert_true(begin_result.get("success", false), "the first-cast Fire Bolt action must succeed")
	assert_true(marigold.is_casting(), "Marigold must now be mid-cast")
	assert_eq(marigold.casting_state.get("remaining_actions"), 1)
	assert_eq(combat_log_panel.get_entry_count(), 0, "no CAST_RESOLVE entry yet -- the cast has not reached resolution")

	var first_reaction_result: Dictionary = begin_result.get("reaction_result", {})
	assert_eq(first_reaction_result.get("reactions", []).size(), 1, "the first-cast action must provoke the adjacent Skeleton's Opportunistic Strike")
	assert_false(first_reaction_result.get("mover_downed", true), "the first Opportunistic Strike must be non-lethal")
	assert_true(marigold.hp_current > 0, "Marigold must still be alive after the first non-lethal Opportunistic Strike")

	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "EndTurnControl.press() must succeed for Marigold's own turn")

	# ── Cycle the Skeleton's + Titus's turns back around to Marigold's NEXT
	# turn (mirrors tests/boot/test_fire_bolt_full_cast_e2e_log.gd) -- the
	# in-progress cast must survive every intervening turn. ────────────────
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "it must now be Marigold's NEXT live turn")
	assert_true(marigold.is_casting(), "the in-progress cast must survive every intervening turn")
	assert_eq(marigold.casting_state.get("remaining_actions"), 1)

	# ── Turn N+k: the SUBSEQUENT action after the non-lethal Opportunistic
	# Strike, driven with NO selection argument (US-006: no re-selection).
	# This drives remaining_actions to 0, which triggers ResolveCastUseCase
	# through the SAME production _verb_bar_cast_spell_execute() shim. ──────
	var continue_result: Dictionary = instance._verb_bar_cast_spell_execute()
	assert_true(continue_result.get("success", false), "the continuing CAST_SPELL action must succeed")

	# The continuing action may ALSO provoke a (fresh-round) Opportunistic
	# Strike from the still-adjacent Skeleton -- also genuinely non-lethal,
	# since Marigold's hp remains comfortably survivable throughout.
	var second_reaction_result: Dictionary = continue_result.get("reaction_result", {})
	assert_false(second_reaction_result.get("mover_downed", true), "any Opportunistic Strike provoked by the continuing action must also be non-lethal")

	# ── The criterion itself: the cast resolves NORMALLY -- casting_state is
	# cleared, and a CAST_RESOLVE combat-log entry is emitted, exactly as it
	# would with no Opportunistic Strike ever having fired. ────────────────
	assert_false(marigold.is_casting(), "casting_state must be cleared once the cast reaches resolution")
	assert_true(marigold.casting_state.is_empty(), "the live Combatant's own casting_state Dictionary must be empty after normal resolution")

	assert_eq(combat_log_panel.get_entry_count(), 1, "exactly one CAST_RESOLVE entry must be emitted for this normally-resolved cast")
	var entry = combat_log_panel.get_entry(0)
	assert_true(entry is CombatLogEntryClass)
	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.spell_id, "fire_bolt")
	assert_eq(entry.actor_id, marigold.display_id())
	assert_eq(entry.target_ids, [skeleton.display_id()])
	assert_typeof(entry.hit, TYPE_BOOL, "hit must resolve to a real bool once a genuine target was resolved against")

	if entry.hit:
		assert_gt(entry.damage_amount, 0, "a hit must carry a positive damage_amount")
		assert_lt(skeleton.hp_current, skeleton_hp_before, "a hit must have genuinely reduced the Skeleton's hp through the live EffectsApplier seam")
	else:
		assert_eq(entry.damage_amount, 0, "a miss must carry zero damage_amount")
		assert_eq(skeleton.hp_current, skeleton_hp_before, "a miss must leave the Skeleton's hp untouched")

	assert_true(marigold.hp_current > 0, "Marigold must still be alive at the end of this normally-resolved cast -- every Opportunistic Strike provoked along the way was genuinely non-lethal")
