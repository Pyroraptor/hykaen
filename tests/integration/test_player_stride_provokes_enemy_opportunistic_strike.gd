extends GutTest
## tests/integration/test_player_stride_provokes_enemy_opportunistic_strike.gd
## — FEAT-233 (US-006, resolves DEF-001's remaining coverage gap, depends on
## FIX-001).
##
## FR-005's exit criterion ("a Stride by either side" can trigger an
## OpportunisticStrike window) has TWO legs. The PLAYER-mover leg —
## MainScene.gd's `_verb_bar_stride_execute()` opening an OpportunisticStrike
## window for a live, adjacent ENEMY reactor (routed synchronously through
## `_resolve_enemy_opportunistic_strike_reaction()` ->
## infrastructure/ai_reaction_policy.gd's real AIReactionPolicy, per this
## iteration's design notes) — has NO dedicated test coverage anywhere in
## this codebase: tests/gut/test_stride_layer2_integration.gd's own Stride
## tests incidentally exercise this exact seam (Titus starts adjacent to the
## Skeleton at the PROLOGUE_SEED fixture's boot position, so ANY Stride he
## takes organically offers the Skeleton a window) but never assert anything
## about the Skeleton's own reaction outcome — they only assert Titus's own
## action-budget spend and token position. tests/integration/
## test_reserve_gate_boot_real.gd and tests/integration/
## test_mainscene_player_strike_enemy_reaction.gd cover the Skeleton's
## reaction on the STRIKE path, never the STRIDE path.
##
## This suite closes that gap with ONE dedicated boot-real MainScene test,
## mirroring tests/integration/test_reserve_gate_boot_real.gd's and
## tests/e2e/test_reactions_fully_live.gd's established conventions exactly:
## boots the REAL res://MainScene.tscn composition root (G2 — never a
## hand-wired double), then drives the SAME real, composition-root-bound
## STRIDE entry point (`instance._verb_bar_stride_execute()` — "the SOLE
## Stride entry point", per that method's own doc) a live player click
## resolves through, against the prologue fixture's OWN real adjacency
## (Titus and the Skeleton start adjacent — no fixture repositioning
## required for eligibility). Titus's own "ac"/hp_current are forced (the
## SAME plain-Dictionary-field-override technique this project's other
## boot-real suites already use — never a scripted RNG/ReactionChooserPort)
## so the Skeleton's real, unforced AIReactionPolicy deterministically
## CHOOSES "opportunistic_strike" (melee_reach true, RESERVE gate open on a
## fresh-turn budget) and the resulting guaranteed-hit Strike survives
## without downing Titus — proving the window is genuinely OFFERED, the
## REAL AIReactionPolicy genuinely CHOOSES the strike, and the effect is
## FULLY RESOLVED (real damage + real spend_reaction()) strictly BEFORE
## Titus's own Stride ever commits his hex_coord/token.
##
## Verifies (test_criteria):
##   test_player_stride_past_live_adjacent_skeleton_provokes_and_resolves_opportunistic_strike
##   passes.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass = preload("res://core/rules/round_events.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed:
## Titus acts first and the sole enemy (Skeleton) starts adjacent to him
## (mirrors tests/integration/test_mainscene_hit_reaction_apply.gd's
## identically-named/valued constant).
const PROLOGUE_SEED: int = 42

## AC_GUARANTEED_HIT — mirrors tests/e2e/test_reactions_fully_live.gd's
## identically-named/valued constant: an absurdly low AC guarantees a hit
## with no RNG/seed edits. Forced on TITUS here (he is the mover the
## Skeleton's opportunistic Strike targets), the mirror image of every other
## boot-real suite's Skeleton-as-defender usage.
const AC_GUARANTEED_HIT: int = -1000

## SURVIVABLE_HP — comfortably above any possible single-weapon damage roll,
## so the resolved Opportunistic Strike never coincidentally defeats Titus —
## keeping "mover_downed"/"stride_should_commit" on the ordinary "the Stride
## still commits" branch so this suite can also observe the real
## Movement.stride()/token-resync commit that follows.
const SURVIVABLE_HP: int = 500


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _id(combatant: Dictionary) -> String:
	return combatant.get("combatant_id", combatant.get("name", ""))


# ══════════════════════════════════════════════════════════════════════════
# The criterion: a real player Stride past a live, adjacent Skeleton
# genuinely provokes AND fully resolves an OpportunisticStrike, strictly
# before Titus's own Stride commits.
# ══════════════════════════════════════════════════════════════════════════

func test_player_stride_past_live_adjacent_skeleton_provokes_and_resolves_opportunistic_strike() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)

	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var titus: Dictionary = instance._party[0]
	var skeleton: Dictionary = instance._enemies[0]
	var titus_id: String = _id(titus)
	var skeleton_id: String = _id(skeleton)

	var titus_start_hex = titus.get("hex_coord", null)
	var skeleton_hex = skeleton.get("hex_coord", null)
	assert_not_null(titus_start_hex, "fixture assumption: Titus carries a hex_coord before Striding")
	assert_not_null(skeleton_hex, "fixture assumption: the Skeleton carries a hex_coord")

	var HexMathClass = preload("res://core/geometry/hex_math.gd")
	var is_adjacent_at_boot: bool = false
	for neighbor in HexMathClass.hex_neighbors(titus_start_hex):
		if neighbor.equals(skeleton_hex):
			is_adjacent_at_boot = true
			break
	assert_true(is_adjacent_at_boot, "fixture assumption: the Skeleton starts adjacent to Titus's own hex at the PROLOGUE_SEED fixture's boot position — no repositioning is needed for eligibility")

	assert_true(
		skeleton.has("weapon") and not skeleton["weapon"].has("range_hexes"),
		"fixture assumption: the Skeleton's real weapon carries melee reach (no 'range_hexes' key)"
	)

	# Force a guaranteed hit against TITUS (the mover) -- the mirror image of
	# every other boot-real suite's Skeleton-as-defender AC_GUARANTEED_HIT
	# usage -- so this suite's assertions are deterministic without touching
	# RNG/seed math. Titus's own hp is pinned comfortably above any possible
	# single-weapon roll so he survives the Opportunistic Strike and his own
	# Stride is free to commit afterward.
	titus["ac"] = AC_GUARANTEED_HIT
	titus["hp_current"] = SURVIVABLE_HP
	titus["hp_max"] = SURVIVABLE_HP

	var skeleton_ae = instance._action_economy_for(skeleton)
	assert_not_null(skeleton_ae, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")
	var skeleton_budget_before: int = skeleton_ae.get_remaining()

	assert_true(instance._verb_registry.is_available("STRIDE"), "fixture assumption: Titus has a legal Stride available at boot")
	var selection: Dictionary = instance.verb_bar_view.press("STRIDE")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "fixture assumption: at least one legal Stride destination exists")
	var destination = candidate_hexes[0]

	assert_false(instance.reaction_prompt_ui.is_open(), "fixture assumption: no pop-up is open before this Stride is driven")
	var titus_hp_before: int = titus.get("hp_current", -1)

	# ── Drive the SAME real, composition-root-bound Stride entry point a
	# live player click resolves through -- "the SOLE Stride entry point"
	# (MainScene.gd's own _verb_bar_stride_execute() doc). ──────────────────
	var stride_result: Dictionary = await instance._verb_bar_stride_execute(destination)

	# The criterion itself: the window was genuinely OFFERED, the REAL
	# AIReactionPolicy genuinely CHOSE opportunistic_strike, and the effect
	# FULLY RESOLVED (real damage + real spend_reaction()) -- never a pop-up
	# (the enemy reactor's own decision routes synchronously through
	# AIReactionPolicy, never turn_controller's blocking prompt).
	assert_false(instance.reaction_prompt_ui.is_open(), "the enemy reactor's own OpportunisticStrike decision is resolved synchronously via AIReactionPolicy -- no pop-up may ever open for it")

	assert_eq(
		skeleton_ae.get_remaining(), skeleton_budget_before - 1,
		"the Skeleton's own live ActionEconomy budget must drop by EXACTLY 1 -- paid via spend_reaction(), never spend_action()"
	)

	var titus_hp_after: int = titus.get("hp_current", -1)
	assert_true(titus_hp_after < titus_hp_before, "Titus (the mover) must show real, positive damage from the Skeleton's resolved Opportunistic Strike")

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one Strike (the Skeleton's Opportunistic Strike) must have resolved")
	var attack_event = attack_events[0]
	assert_eq(attack_event.attacker_name, "Skeleton", "the resolved Strike must be attributed to the Skeleton (the reactor), not Titus (the mover)")
	assert_eq(attack_event.target_name, "Titus", "the resolved Strike's target must be Titus (the mover)")
	assert_true(attack_event.hit, "the guaranteed-hit AC must actually produce a hit")
	assert_true(attack_event.damage_final > 0, "the resolved Opportunistic Strike must apply real, positive damage")
	assert_eq(titus_hp_before - titus_hp_after, attack_event.damage_final, "Titus's hp_current must drop by EXACTLY the resolved Strike's damage_final")

	# ── The mover survived, so the Stride is free to commit -- proven AFTER
	# the above (the reaction has already fully resolved by this point in the
	# real, composition-root-bound call chain: ResolveStrideUseCase.execute()
	# is awaited to completion strictly BEFORE
	# movement_input_controller.stride_to() ever runs, per this project's
	# established "opens a resolved reaction window before position changes"
	# contract). ──────────────────────────────────────────────────────────────
	assert_true(stride_result.get("ok", false), "Titus's own Stride must genuinely resolve once the Skeleton's non-lethal Opportunistic Strike leaves him alive")

	assert_true(
		titus.get("hex_coord").equals(destination),
		"Titus's own live hex_coord must relocate to the chosen Stride destination once the Opportunistic Strike resolved without downing him"
	)
	var token_after = instance.hex_grid_view.get_token(titus_id)
	assert_not_null(token_after, "the real HexGridView must still carry a token for Titus after his Stride")
	assert_true(token_after.hex_coord.equals(destination), "Titus's own on-screen token must visibly relocate to the Stride destination")

	# Sanity check: the Skeleton (the reactor) never moved -- only Titus (the
	# mover) Strides in this scenario.
	assert_true(skeleton.get("hex_coord").equals(skeleton_hex), "the Skeleton (the reactor) must remain at its own hex -- only the mover (Titus) relocates on a Stride")
