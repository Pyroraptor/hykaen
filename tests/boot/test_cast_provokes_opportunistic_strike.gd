extends GutTest
## tests/boot/test_cast_provokes_opportunistic_strike.gd — FEAT-279 (US-014;
## FR-016, ADR-005)
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root (never a hand-wired double) genuinely opens the SAME OpportunisticStrike
## reaction window a player Stride opens (tests/integration/
## test_player_stride_provokes_enemy_opportunistic_strike.gd's own established
## convention, mirrored here for Cast-a-Spell) when the prologue's caster
## (Marigold) takes a Cast-a-Spell action — both the FIRST-cast action
## (BeginCastUseCase) and a CONTINUING-cast action (ContinueCastUseCase) —
## through the SAME CAST_SPELL verb entry point production code drives
## (`_verb_bar_cast_spell_execute()`,
## presentation/verbs/spell_action_controller.gd's SpellActionController,
## routed through core/application/use_cases/
## provoke_reaction_on_cast_use_case.gd's ProvokeReactionOnCastUseCase, per
## this feature's own file-level doc). No new reaction infrastructure is
## exercised here (ADR-005) — this suite drives the IDENTICAL `reaction`
## ReactionController collaborator (presentation/reaction_controller.gd)
## MainScene.gd's own `_verb_deps()` already wires for Strike/Stride, with
## no composition-root change required for this feature.
##
## The prologue fixture's own boot positions (Titus (0,0), Marigold (-1,0),
## Skeleton (1,0) — data/encounters/prologue_encounter.tres) leave Marigold
## two hexes from the Skeleton, so — mirroring tests/integration/
## test_player_stride_provokes_enemy_opportunistic_strike.gd's own
## AC_GUARANTEED_HIT/SURVIVABLE_HP direct-field-override technique for
## forcing a deterministic outcome without touching RNG/seed math — this
## suite forces Marigold's OWN live hex_coord to a hex adjacent to the
## Skeleton's (Combatant.hex_coord is a plain public field, the SAME
## direct-assignment convention core/rules/tests already use) before
## driving each cast action. Casting never relocates the caster (this
## feature's own design notes: "casting a spell ... never relocates the
## caster the way a Stride does"), so the forced position stays valid for
## every action driven against it.
##
## test_criteria satisfied:
##   "Boot-real test confirms an in-range enemy's Opportunistic Strike is
##   provoked by a first-cast Concentrate action"
##   "Boot-real test confirms a continuing-cast action also provokes the
##   same reaction window"

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass = preload("res://core/rules/round_events.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_first_cast_firebolt.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42

## AC_GUARANTEED_HIT / SURVIVABLE_HP — mirror tests/integration/
## test_player_stride_provokes_enemy_opportunistic_strike.gd's identically-
## named/valued constants: an absurdly low AC guarantees the Skeleton's
## resolved Opportunistic Strike hits with no RNG/seed edits, and a
## comfortably-high hp keeps Marigold alive so this suite can assert on the
## post-strike state without the caster's own defeat complicating either
## criterion.
const AC_GUARANTEED_HIT: int = -1000
const SURVIVABLE_HP: int = 500


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
## forces Marigold's OWN live hex_coord to (skeleton.hex_coord.q + 1,
## skeleton.hex_coord.r) -- one of core/geometry/hex_math.gd's own 6
## flat-top axial neighbor offsets ([1, 0]) -- which is NOT Titus's own
## fixture-boot hex (0,0) (that offset is the [-1, 0] neighbor, the
## opposite direction), so this repositioning never collides with another
## live combatant's hex.
func _reposition_marigold_adjacent_to_skeleton(marigold, skeleton) -> void:
	var HexCoordClass = preload("res://core/geometry/hex_coord.gd")
	marigold.hex_coord = HexCoordClass.new(skeleton.hex_coord.q + 1, skeleton.hex_coord.r)


func _attack_events(instance) -> Array:
	return instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)


# ══════════════════════════════════════════════════════════════════════════
# Criterion: a first-cast Concentrate action provokes an in-range enemy's
# Opportunistic Strike.
# ══════════════════════════════════════════════════════════════════════════

func test_first_cast_action_provokes_in_range_enemys_opportunistic_strike() -> void:
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
	marigold.ac = AC_GUARANTEED_HIT
	marigold.hp_current = SURVIVABLE_HP
	marigold.hp_max = SURVIVABLE_HP

	var skeleton_ae = instance._action_economy_for(skeleton)
	assert_not_null(skeleton_ae, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")
	var skeleton_budget_before: int = skeleton_ae.get_remaining()
	var marigold_hp_before: int = marigold.hp_current

	# ── Drive the SAME real, composition-root-bound CAST_SPELL entry point a
	# live player click resolves through. ────────────────────────────────────
	var begin_result: Dictionary = instance._verb_bar_cast_spell_execute("fire_bolt")

	assert_true(begin_result.get("success", false), "the first-cast Fire Bolt action must succeed")
	assert_true(marigold.is_casting(), "Marigold must now be mid-cast (Fire Bolt costs 2 actions)")

	# The criterion itself: the window was genuinely OFFERED to the Skeleton
	# (the SAME adjacent/hostile/not-Spent/melee-reach eligibility a Stride
	# provokes), the REAL AIReactionPolicy genuinely CHOSE
	# opportunistic_strike (melee_reach true, RESERVE gate open on a
	# fresh-turn budget — see infrastructure/ai_reaction_policy.gd), and the
	# effect FULLY RESOLVED (real damage + real spend_reaction()) -- never a
	# pop-up (the enemy reactor's own decision routes synchronously through
	# AIReactionPolicy).
	assert_false(instance.reaction_prompt_ui.is_open(), "the enemy reactor's own OpportunisticStrike decision is resolved synchronously via AIReactionPolicy -- no pop-up may ever open for it")

	var reaction_result: Dictionary = begin_result.get("reaction_result", {})
	assert_eq(reaction_result.get("reactions", []).size(), 1, "exactly one reactor (the adjacent Skeleton) must have been offered a window")
	assert_eq(reaction_result.get("reactions")[0].get("choice"), "opportunistic_strike", "the REAL AIReactionPolicy must genuinely choose opportunistic_strike when melee-legal and the RESERVE gate is open")

	assert_eq(
		skeleton_ae.get_remaining(), skeleton_budget_before - 1,
		"the Skeleton's own live ActionEconomy budget must drop by EXACTLY 1 -- paid via spend_reaction(), never spend_action()"
	)

	var marigold_hp_after: int = marigold.hp_current
	assert_true(marigold_hp_after < marigold_hp_before, "Marigold (the caster) must show real, positive damage from the Skeleton's resolved Opportunistic Strike")

	var attack_events: Array = _attack_events(instance)
	assert_eq(attack_events.size(), 1, "exactly one Strike (the Skeleton's Opportunistic Strike) must have resolved")
	var attack_event = attack_events[0]
	assert_eq(attack_event.attacker_name, "Skeleton", "the resolved Strike must be attributed to the Skeleton (the reactor), not Marigold (the caster)")
	assert_eq(attack_event.target_name, "Marigold", "the resolved Strike's target must be Marigold (the caster)")
	assert_true(attack_event.hit, "the guaranteed-hit AC must actually produce a hit")
	assert_eq(marigold_hp_before - marigold_hp_after, attack_event.damage_final, "Marigold's hp_current must drop by EXACTLY the resolved Strike's damage_final")


# ══════════════════════════════════════════════════════════════════════════
# Criterion: a continuing-cast action ALSO provokes the same reaction
# window.
# ══════════════════════════════════════════════════════════════════════════

func test_continuing_cast_action_also_provokes_the_same_reaction_window() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")

	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")

	_reposition_marigold_adjacent_to_skeleton(marigold, skeleton)
	marigold.ac = AC_GUARANTEED_HIT
	marigold.hp_current = SURVIVABLE_HP
	marigold.hp_max = SURVIVABLE_HP

	# Drive Marigold directly into an ALREADY-mid-cast state (spell_id
	# "fire_bolt", 1 action remaining) WITHOUT actually spending a
	# BeginCastUseCase action of her own here -- so the Skeleton's own
	# reaction budget is still completely fresh/unspent when the CONTINUING
	# action below drives its own window, isolating this test's criterion
	# ("a continuing-cast action also provokes the SAME reaction window")
	# from the first-cast criterion the sibling test above already covers on
	# its own. casting_state is a plain public Dictionary field on the
	# Combatant entity (core/domain/combatant.gd) -- the SAME
	# direct-assignment convention this project's other boot-real suites
	# already use for forcing deterministic fixture state (e.g.
	# titus["ac"]/marigold.ac above).
	marigold.casting_state = {"spell_id": "fire_bolt", "remaining_actions": 1, "committed_energy": 0, "caster_id": marigold.display_id()}
	assert_true(marigold.is_casting(), "fixture assumption: Marigold must now be mid-cast (forced casting_state)")

	var skeleton_ae = instance._action_economy_for(skeleton)
	assert_not_null(skeleton_ae, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")
	var skeleton_budget_before: int = skeleton_ae.get_remaining()
	var marigold_hp_before: int = marigold.hp_current

	# ── Drive the SAME real, composition-root-bound CAST_SPELL entry point
	# with NO selection argument at all (US-006: the actor is already
	# mid-cast, so no re-selection is possible/needed) -- this is the
	# CONTINUING-cast branch (ContinueCastUseCase), not BeginCastUseCase. ──
	# Fire-and-forget: remaining_actions→0 triggers resolution + targeting,
	# which awaits a hex click from the real PlayerTargetingPort.
	var _cap := {"done": false, "result": null}
	var _run := func():
		var r = await instance._verb_bar_cast_spell_execute()
		_cap["done"] = true
		_cap["result"] = r
	_run.call()
	instance.hex_grid_view.hex_clicked.emit(skeleton.hex_coord)
	await get_tree().process_frame
	var continue_result: Dictionary = _cap["result"]

	assert_true(continue_result.get("success", false), "continuing an in-progress cast with no selection argument must succeed (US-006: no re-selection)")
	assert_eq(continue_result.get("casting_state", {}).get("remaining_actions"), 0, "the continuing-cast action must drive remaining_actions to 0 (Fire Bolt's 2-action cost)")

	# The criterion itself: the SAME reaction window (ReactionWindowPort,
	# routed through the IDENTICAL ProvokeReactionOnCastUseCase ->
	# ReactionController -> AIReactionPolicy path the first-cast branch
	# exercises above) is ALSO opened for the continuing-cast action.
	assert_false(instance.reaction_prompt_ui.is_open(), "the enemy reactor's own OpportunisticStrike decision is resolved synchronously via AIReactionPolicy -- no pop-up may ever open for it")

	var reaction_result: Dictionary = continue_result.get("reaction_result", {})
	assert_eq(reaction_result.get("reactions", []).size(), 1, "exactly one reactor (the adjacent Skeleton, its reaction still fresh) must have been offered a window by the continuing-cast action")
	assert_eq(reaction_result.get("reactions")[0].get("choice"), "opportunistic_strike", "the REAL AIReactionPolicy must genuinely choose opportunistic_strike when melee-legal and the RESERVE gate is open")

	assert_eq(
		skeleton_ae.get_remaining(), skeleton_budget_before - 1,
		"the Skeleton's own live ActionEconomy budget must drop by EXACTLY 1 -- paid via spend_reaction(), never spend_action()"
	)

	var marigold_hp_after: int = marigold.hp_current
	assert_true(marigold_hp_after < marigold_hp_before, "Marigold (the caster) must show real, positive damage from the Skeleton's resolved Opportunistic Strike, provoked by the CONTINUING-cast action")

	var attack_events: Array = _attack_events(instance)
	assert_eq(attack_events.size(), 1, "exactly one Strike (the Skeleton's Opportunistic Strike, provoked by the continuing-cast action) must have resolved")
	var attack_event = attack_events[0]
	assert_eq(attack_event.attacker_name, "Skeleton", "the resolved Strike must be attributed to the Skeleton (the reactor), not Marigold (the caster)")
	assert_eq(attack_event.target_name, "Marigold", "the resolved Strike's target must be Marigold (the caster)")
	assert_true(attack_event.hit, "the guaranteed-hit AC must actually produce a hit")
