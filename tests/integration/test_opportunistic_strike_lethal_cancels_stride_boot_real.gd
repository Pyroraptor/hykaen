extends GutTest
## tests/integration/test_opportunistic_strike_lethal_cancels_stride_boot_real.gd
## — FEAT-238 (US-007 / US-008, resolves PR-003).
##
## PR-003 named a review gap: FR-007's lethal-Opportunistic-Strike-cancels-
## Stride branch (core/application/use_cases/resolve_stride_use_case.gd's
## "mover_downed" -> "stride_should_commit: false" contract, and both real
## call sites that must honor it — core/combat/ai.gd's
## `_stride_toward_target()` and presentation/stride_action_controller.gd's
## `execute()`) was ONLY ever proven by fake-double tests
## (tests/unit/core/application/use_cases/test_resolve_stride_use_case.gd's
## `test_lethal_opportunistic_strike_cancels_stride()` /
## `test_first_lethal_reactor_in_initiative_order_stops_the_second_reactor()`,
## both driving `execute()` directly with a hand-rolled `strike_use_case`
## fake that unconditionally reports `target_defeated`). No suite anywhere in
## this codebase had ever driven a GENUINELY LETHAL Opportunistic Strike
## through the REAL, composition-root-wired path
## (core/combat/ai.gd::decide_action() -> ResolveStrideUseCase ->
## ResolveActionUseCase, and separately MainScene's real player-Stride verb)
## — every existing boot-real suite exercising this seam
## (tests/integration/test_ai_decide_action_opportunistic_strike_trigger.gd,
## tests/integration/test_player_stride_provokes_enemy_opportunistic_strike.gd,
## tests/e2e/test_reactions_fully_live.gd) deliberately pins the mover's hp to
## an OVERWHELMING/SURVIVABLE value specifically so the Opportunistic Strike
## does NOT down the mover, so `mover_downed`/`stride_should_commit`'s FALSE
## branch is exhaustively covered, but the TRUE (cancel) branch never was
## through real production wiring — exactly the "green tests, dead in play"
## risk this remediation pass targets.
##
## This suite closes that gap with TWO boot-real tests, both against the
## REAL res://MainScene.tscn composition root (G2 — no injected
## ReactionChooserPort/HexChoiceResolverPort double stands in for the
## reactor's own path):
##
##   1. test_enemy_mover_lethal_opportunistic_strike_cancels_stride_via_real_ai_decide_action
##      — mirrors tests/integration/
##      test_ai_decide_action_opportunistic_strike_trigger.gd's and
##      tests/e2e/test_reactions_fully_live.gd's own established technique
##      (a fresh, real, unmodified core/combat/ai.gd AI instance, its
##      `set_stride_reaction_resolver_fn()` bound to the EXACT SAME
##      production Callable MainScene.gd's own composition root binds onto
##      its own `ai_decision_port` in _ready() —
##      `Callable(instance, "_resolve_enemy_stride_opportunistic_window")` —
##      so every reaction-path collaborator underneath it, ResolveStrideUseCase/
##      ResolveActionUseCase/ReactionWindow/TurnController/
##      PlayerReactionChooser/ReactionPromptUI, is the live, composition-root-
##      wired production instance, never a double). The Skeleton (the mover)
##      is driven out of reach of a synthetic decoy target (so
##      decide_action() organically issues a Stride) while the REAL, live
##      Titus stands adjacent to its start hex as the sole eligible
##      Opportunistic Strike reactor, routed through the REAL, blocking
##      scenes/ui/reaction_prompt_ui.gd pop-up. The Skeleton's own hp_current
##      is forced down to a value BELOW Titus's real, minimum possible
##      Longsword damage roll (die-minimum + strength modifier), so the
##      resolved Opportunistic Strike is GENUINELY lethal — never a fabricated
##      target_defeated flag.
##
##   2. test_player_mover_lethal_opportunistic_strike_cancels_stride_via_real_mainscene_player_path
##      — mirrors tests/integration/
##      test_player_stride_provokes_enemy_opportunistic_strike.gd's own
##      established technique: drives the REAL, composition-root-bound
##      Stride entry point (`instance._verb_bar_stride_execute()` — "the SOLE
##      Stride entry point", per that method's own doc) against the prologue
##      fixture's own real adjacency (Titus and the Skeleton start adjacent —
##      no fixture repositioning required for eligibility). Titus's own
##      hp_current is forced down to a value BELOW the Skeleton's real,
##      minimum possible Arming Sword damage roll, so the Skeleton's real,
##      unforced AIReactionPolicy's resolved "opportunistic_strike" choice
##      GENUINELY defeats Titus before his own Stride can ever commit.
##
## Both tests assert the SAME three-part contract this feature's
## test_criteria require: (a) the mover's hex_coord/on-screen token is
## UNCHANGED from its start hex (Movement.stride() is never reached), (b) the
## mover's hp_current already reflects the lethal Opportunistic Strike's real
## damage BEFORE any position mutation could have occurred, and (c) the
## real, composition-root-wired call site's own "may this Stride commit?"
## signal (ai.gd's decide_action() no-action sentinel /
## ResolveStrideUseCase's own "stride_should_commit": false /
## StrideActionController's own rejected result) genuinely reports the
## Stride did NOT complete.
##
## No change was required to core/combat/ai.gd or core/application/
## use_cases/resolve_stride_use_case.gd to make these tests pass — both
## already read `mover_downed`/`stride_should_commit` and cancel the Stride
## (iteration K FEAT-008); this suite exists to PROVE that real-path
## behavior directly, closing PR-003's coverage gap without requiring a
## production change.
##
## Verifies (test_criteria):
##   1. Both tests boot the real res://MainScene.tscn composition root with
##      zero test-double reaction chooser/hex resolver substituted for the
##      reactor path.
##   2. Both tests force a lethal Opportunistic Strike (reactor's Strike
##      reduces mover hp_current to <= 0) and assert the mover's
##      hex_coord/token position is unchanged from its start hex.
##   3. Both tests assert the mover's hp_current reflects the lethal
##      damage before any position mutation could have occurred.
##   4. Test 1 drives core/combat/ai.gd::decide_action() for an enemy mover;
##      Test 2 drives MainScene's real player Stride path for a player mover.
##   5. Existing US-008 fake-based tests
##      (tests/unit/core/application/use_cases/test_resolve_stride_use_case.gd)
##      remain untouched by this suite.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass = preload("res://core/rules/round_events.gd")
const AIClass           = preload("res://core/combat/ai.gd")
const HexCoordClass     = preload("res://core/geometry/hex_coord.gd")
const HexMathClass      = preload("res://core/geometry/hex_math.gd")
const CombatantClass    = preload("res://core/domain/combatant.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed:
## Titus acts first and the sole enemy (Skeleton) starts adjacent to him
## (mirrors tests/integration/test_reserve_gate_boot_real.gd's identically-
## named/valued constant).
const PROLOGUE_SEED: int = 42

## AC_GUARANTEED_HIT — mirrors this project's established
## AC_GUARANTEED_HIT convention: an absurdly low AC guarantees a hit with
## no RNG/seed edits.
const AC_GUARANTEED_HIT: int = -1000

## LETHAL_HP — pinned BELOW the lowest possible real damage roll either
## attacker in this fixture can ever produce:
##   - Titus's real Longsword: damage_die=12 (min roll 1) + strength(5) = 6.
##   - the Skeleton's real Arming Sword: damage_die=6 (min roll 1) +
##     strength(2) = 3.
## 1 is strictly below both floors, so ANY real, seeded hit-and-damage roll
## against a combatant pinned to LETHAL_HP is genuinely lethal — never a
## fabricated/forced target_defeated flag.
const LETHAL_HP: int = 1

## DECOY_TARGET_DISTANCE — mirrors tests/e2e/test_reactions_fully_live.gd's
## identically-named/valued constant: far enough (> 1) to fail the
## Skeleton's own melee reach check, forcing decide_action() to choose
## "Stride" over "Strike" toward the decoy.
const DECOY_TARGET_DISTANCE: int = 3


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _id(combatant) -> String:
	return combatant.combatant_id


func _hex_tuple(hex_coord) -> Array:
	return [hex_coord.q, hex_coord.r]


# ══════════════════════════════════════════════════════════════════════════
# Test 1 — enemy mover (the Skeleton), driven through core/combat/ai.gd's
# real decide_action(), suffers a GENUINELY lethal Opportunistic Strike from
# Titus (routed through the REAL, blocking reaction_prompt_ui pop-up) BEFORE
# its Stride can ever commit.
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_mover_lethal_opportunistic_strike_cancels_stride_via_real_ai_decide_action() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)

	var titus = instance._party[0]
	var skeleton = instance._enemies[0]
	var titus_id: String = _id(titus)
	var skeleton_id: String = _id(skeleton)

	var mover_start_hex = skeleton.hex_coord
	assert_not_null(mover_start_hex, "fixture assumption: the Skeleton carries a hex_coord before its Stride")

	var is_titus_adjacent_at_boot: bool = false
	for neighbor in HexMathClass.hex_neighbors(mover_start_hex):
		if neighbor.equals(titus.hex_coord):
			is_titus_adjacent_at_boot = true
			break
	assert_true(is_titus_adjacent_at_boot, "fixture assumption: Titus starts adjacent to the Skeleton's own hex at the PROLOGUE_SEED fixture's boot position -- no repositioning is needed for eligibility")

	# Force the Skeleton (the mover) down to a hp floor that ANY real,
	# minimum-possible Longsword roll from Titus (the reactor) will defeat --
	# see LETHAL_HP's own doc for the arithmetic. No AC/weapon field is
	# forced on Titus's own attack -- only his target's AC is forced low
	# (mirrors every other boot-real suite's AC_GUARANTEED_HIT usage) so the
	# hit itself is deterministic without touching RNG/seed math.
	skeleton["ac"] = AC_GUARANTEED_HIT
	skeleton["hp_current"] = LETHAL_HP
	skeleton["hp_max"] = LETHAL_HP

	var titus_ae = instance._action_economy_for(titus)
	assert_not_null(titus_ae, "fixture assumption: Titus must have a live ActionEconomy wired at boot")
	var titus_budget_before: int = titus_ae.get_remaining()

	var skeleton_ae = instance._action_economy_for(skeleton)
	assert_not_null(skeleton_ae, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")

	# `decoy_target` -- a synthetic, out-of-reach, hostile-to-the-Skeleton
	# combatant, NEVER Titus himself: this is what lets decide_action()
	# genuinely, organically compute "the chosen target is out of reach" and
	# issue a real Stride, while the REAL, live Titus (still at his true,
	# adjacent boot position) is supplied separately via `other_combatants`
	# as the sole genuinely eligible OpportunisticStrike reactor -- the SAME
	# reading of decide_action()'s own contract
	# tests/integration/test_ai_decide_action_opportunistic_strike_trigger.gd
	# (FEAT-233) and tests/e2e/test_reactions_fully_live.gd (FEAT-234)
	# already establish and justify at length in their own header docs.
	var decoy_target = CombatantClass.from_dict({
		"name": "Lethal Test Decoy Target",
		"combatant_id": "lethal_test_decoy_target",
		"hp_current": 20, "hp_max": 20, "ac": 14,
		"hex_coord": HexCoordClass.new(mover_start_hex.q + DECOY_TARGET_DISTANCE, mover_start_hex.r),
		"_is_enemy": false,
	})

	var displayed_options_when_opened: Array = []
	var press_opportunistic_strike := func():
		assert_true(instance.reaction_prompt_ui.is_open(), "the REAL OpportunisticStrike pop-up must genuinely be open before this deferred press fires")
		displayed_options_when_opened.append_array(instance.reaction_prompt_ui.get_displayed_options())
		instance.reaction_prompt_ui.press_option("opportunistic_strike")
	press_opportunistic_strike.call_deferred()

	# `observed_stride_resolver` wraps -- never replaces -- the EXACT SAME
	# production Callable MainScene.gd's own composition root binds onto its
	# `ai_decision_port` in _ready() (`Callable(instance,
	# "_resolve_enemy_stride_opportunistic_window")`). It only OBSERVES,
	# capturing the use case's own returned Dictionary (never otherwise
	# reachable from outside decide_action() itself) at the one instant that
	# call guarantees is BOTH "after the reaction fully resolved" AND
	# "before core/rules/movement.gd's Movement.stride() (called by ai.gd
	# immediately after this Callable returns) could ever mutate `mover`'s
	# hex_coord".
	var real_stride_resolver := Callable(instance, "_resolve_enemy_stride_opportunistic_window")
	var _capture: Dictionary = {"result": {}, "mover_hex_immediately_after_reaction": [], "mover_hp_immediately_after_reaction": -1}

	var observed_stride_resolver := func(mover, mover_start, candidate_reactors: Array):
		var result: Dictionary = await real_stride_resolver.call(mover, mover_start, candidate_reactors)
		_capture["result"] = result
		_capture["mover_hex_immediately_after_reaction"] = _hex_tuple(mover.hex_coord)
		_capture["mover_hp_immediately_after_reaction"] = mover.hp_current
		return result

	var ai_instance = AIClass.new()
	ai_instance.set_stride_reaction_resolver_fn(observed_stride_resolver)

	# ── The organic entry point itself: a real, unmodified core/combat/ai.gd
	# AI instance's decide_action() -- never
	# instance._resolve_enemy_stride_opportunistic_window() called directly. ──
	var decision: Dictionary = await ai_instance.decide_action(skeleton, [decoy_target], skeleton_ae, [titus])

	# NOTE: unlike the non-lethal sibling suites (tests/integration/
	# test_ai_decide_action_opportunistic_strike_trigger.gd, tests/e2e/
	# test_reactions_fully_live.gd), decide_action() here does NOT report
	# "Stride" -- the whole point of this criterion is that the lethal
	# Opportunistic Strike cancels the Stride BEFORE it ever commits, so
	# decide_action() reports the SAME no-action sentinel it uses for "no
	# legal Stride destination" (asserted explicitly below).

	assert_true(instance.reaction_prompt_ui.is_open() == false, "the REAL OpportunisticStrike pop-up must have already closed once the deferred press resolved it")
	assert_true(displayed_options_when_opened.has("opportunistic_strike"), "the REAL OpportunisticStrike pop-up must offer 'opportunistic_strike' as a legal option")

	var stride_reaction_result: Dictionary = _capture["result"]
	var reactions: Array = stride_reaction_result.get("reactions", [])
	assert_eq(reactions.size(), 1, "fixture assumption: exactly one reactor (Titus) must have been offered the OpportunisticStrike window")
	assert_eq(reactions[0].get("choice", ""), "opportunistic_strike", "the real, blocking pop-up press must be reported back verbatim as the resolved choice")

	var strike_result: Dictionary = reactions[0].get("strike_result", {})
	assert_true(strike_result.get("resolved", false), "the reactor's opportunistic_strike choice must FULLY resolve a real Strike")
	assert_true(strike_result.get("ok", false), "the resolved Strike must succeed")
	assert_true(strike_result.get("target_defeated", false), "the Skeleton's forced LETHAL_HP floor must be genuinely defeated by Titus's real, minimum-possible damage roll")

	# ── Criterion: the mover's hp_current reflects the lethal damage BEFORE
	# any position mutation could have occurred -- captured at the one
	# instant the resolver guarantees is still before Movement.stride() could
	# ever run. ────────────────────────────────────────────────────────────
	assert_true(_capture["mover_hp_immediately_after_reaction"] <= 0, "the Skeleton's hp_current must already show <= 0 (the lethal Opportunistic Strike's real damage) at the instant the reaction resolver returns, strictly before any Stride commit could occur")
	assert_eq(_capture["mover_hex_immediately_after_reaction"], _hex_tuple(mover_start_hex), "the Skeleton's hex_coord must be UNCHANGED immediately after the lethal reaction resolves")

	# ── Criterion: the real, composition-root-wired ResolveStrideUseCase
	# genuinely reports the cancel signal. ────────────────────────────────
	assert_true(stride_reaction_result.get("mover_downed", false), "a lethal Opportunistic Strike must set mover_downed true on the REAL, composition-root-wired ResolveStrideUseCase result")
	assert_false(stride_reaction_result.get("stride_should_commit", true), "a lethal Opportunistic Strike must set stride_should_commit false -- the real caller must cancel the Stride")

	# ── Criterion: decide_action() itself genuinely CANCELS the Stride --
	# the SAME no-action sentinel it reports for "no legal Stride
	# destination", never a committed Stride. ─────────────────────────────
	assert_eq(decision.get("action_type", ""), "", "core/combat/ai.gd's decide_action() must cancel the Stride (report the no-action sentinel) once its own _stride_reaction_resolver_fn reports mover_downed=true")
	assert_null(decision.get("destination", null), "a cancelled Stride must carry a null destination")
	assert_false(decision.get("will_strike", true), "a cancelled Stride must never also report will_strike true")

	# ── Criterion: the mover's real hex_coord/on-screen token are UNCHANGED
	# from its start hex -- core/rules/movement.gd's Movement.stride() was
	# never reached. ───────────────────────────────────────────────────────
	assert_true(skeleton.hex_coord.equals(mover_start_hex), "the Skeleton's live hex_coord must remain at its start hex -- Movement.stride() must never have been called once the mover was downed")
	var skeleton_token = instance.hex_grid_view.get_token(skeleton_id)
	assert_not_null(skeleton_token, "the real HexGridView must still carry a token for the Skeleton after the cancelled Stride")
	assert_true(skeleton_token.hex_coord.equals(mover_start_hex), "the Skeleton's on-screen token must remain at its start hex -- no token reposition was ever driven for a cancelled Stride")

	# ── The mover's hp_current still reflects the lethal damage at the end
	# of the whole choreography, not merely transiently. ──────────────────
	assert_true(skeleton.hp_current <= 0, "the Skeleton's hp_current must still reflect the lethal Opportunistic Strike's real damage")

	# ── Titus (the reactor) paid via spend_reaction(), never a second
	# spend_action() -- the SAME live ActionEconomy instance every other
	# boot-real suite's identical assertion reads from. ────────────────────
	assert_eq(
		titus_ae.get_remaining(), titus_budget_before - 1,
		"Titus's own live ActionEconomy budget must drop by EXACTLY 1 -- paid via spend_reaction(), never spend_action()"
	)

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one Strike (Titus's lethal Opportunistic Strike) must have resolved")
	var attack_event = attack_events[0]
	assert_eq(attack_event.attacker_name, "Titus", "the resolved Strike must be attributed to Titus (the reactor), not the Skeleton (the mover)")
	assert_eq(attack_event.target_name, "Skeleton", "the resolved Strike's target must be the Skeleton (the mover)")
	assert_true(attack_event.hit, "the guaranteed-hit AC must actually produce a hit")
	assert_true(attack_event.damage_final > 0, "the resolved, lethal Opportunistic Strike must apply real, positive damage")


# ══════════════════════════════════════════════════════════════════════════
# Test 2 — player mover (Titus), driven through MainScene's real player
# Stride verb path, suffers a GENUINELY lethal Opportunistic Strike from the
# Skeleton (routed synchronously through the REAL, unforced AIReactionPolicy
# -- never a pop-up) BEFORE his Stride can ever commit.
# ══════════════════════════════════════════════════════════════════════════

func test_player_mover_lethal_opportunistic_strike_cancels_stride_via_real_mainscene_player_path() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)

	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var titus = instance._party[0]
	var skeleton = instance._enemies[0]
	var titus_id: String = _id(titus)

	var titus_start_hex = titus.hex_coord
	var skeleton_hex = skeleton.hex_coord
	assert_not_null(titus_start_hex, "fixture assumption: Titus carries a hex_coord before Striding")
	assert_not_null(skeleton_hex, "fixture assumption: the Skeleton carries a hex_coord")

	var is_adjacent_at_boot: bool = false
	for neighbor in HexMathClass.hex_neighbors(titus_start_hex):
		if neighbor.equals(skeleton_hex):
			is_adjacent_at_boot = true
			break
	assert_true(is_adjacent_at_boot, "fixture assumption: the Skeleton starts adjacent to Titus's own hex at the PROLOGUE_SEED fixture's boot position -- no repositioning is needed for eligibility")

	assert_true(
		skeleton.has("weapon") and not skeleton["weapon"].has("range_hexes"),
		"fixture assumption: the Skeleton's real weapon carries melee reach (no 'range_hexes' key)"
	)

	# Force a guaranteed hit against TITUS (the mover), and pin his hp to a
	# floor strictly below the Skeleton's real, minimum-possible Arming
	# Sword damage roll -- see LETHAL_HP's own doc for the arithmetic. No
	# field on the Skeleton's own weapon/attack is forced -- the lethal
	# outcome is produced entirely by the Skeleton's real, seeded roll
	# against Titus's forced-low AC and forced-low hp floor.
	titus["ac"] = AC_GUARANTEED_HIT
	titus["hp_current"] = LETHAL_HP
	titus["hp_max"] = LETHAL_HP

	var skeleton_ae = instance._action_economy_for(skeleton)
	assert_not_null(skeleton_ae, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")
	var skeleton_budget_before: int = skeleton_ae.get_remaining()

	assert_true(instance._verb_registry.is_available("STRIDE"), "fixture assumption: Titus has a legal Stride available at boot")
	var selection: Dictionary = instance.verb_bar_view.press("STRIDE")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "fixture assumption: at least one legal Stride destination exists")
	var destination = candidate_hexes[0]

	assert_false(instance.reaction_prompt_ui.is_open(), "fixture assumption: no pop-up is open before this Stride is driven")

	# ── Drive the SAME real, composition-root-bound Stride entry point a
	# live player click resolves through -- "the SOLE Stride entry point"
	# (MainScene.gd's own _verb_bar_stride_execute() doc). ─────────────────
	var stride_result: Dictionary = await instance._verb_bar_stride_execute(destination)

	# The enemy reactor's own OpportunisticStrike decision routes
	# synchronously through the REAL AIReactionPolicy -- never a pop-up.
	assert_false(instance.reaction_prompt_ui.is_open(), "the enemy reactor's own OpportunisticStrike decision is resolved synchronously via AIReactionPolicy -- no pop-up may ever open for it")

	# ── Criterion: the real, composition-root-wired Stride verb path
	# genuinely reports the Stride did NOT complete. ───────────────────────
	assert_false(stride_result.get("ok", true), "Titus's own Stride must be rejected once the Skeleton's lethal Opportunistic Strike defeats him")
	assert_false(stride_result.get("resolved", true), "a cancelled Stride must never report itself as resolved")
	assert_eq(stride_result.get("error", ""), "ERR_MOVER_DOWNED_BY_OPPORTUNISTIC_STRIKE", "the real StrideActionController must report the lethal-opportunistic-strike cancellation error code")

	# ── Criterion: the mover's real hex_coord/on-screen token are UNCHANGED
	# from its start hex -- movement_input_controller.stride_to() was never
	# reached (StrideActionController's own execute() returns early). ──────
	assert_true(titus.hex_coord.equals(titus_start_hex), "Titus's live hex_coord must remain at his start hex -- movement_input_controller.stride_to() must never have been called once he was downed")
	var titus_token = instance.hex_grid_view.get_token(titus_id)
	assert_not_null(titus_token, "the real HexGridView must still carry a token for Titus after the cancelled Stride")
	assert_true(titus_token.hex_coord.equals(titus_start_hex), "Titus's on-screen token must remain at his start hex -- no token reposition was ever driven for a cancelled Stride")

	# ── Criterion: the mover's hp_current reflects the lethal damage. ─────
	assert_true(titus.hp_current <= 0, "Titus's hp_current must reflect the Skeleton's real, lethal Opportunistic Strike damage")

	# ── The Skeleton (the reactor) paid via spend_reaction(), never a
	# second spend_action(). ───────────────────────────────────────────────
	assert_eq(
		skeleton_ae.get_remaining(), skeleton_budget_before - 1,
		"the Skeleton's own live ActionEconomy budget must drop by EXACTLY 1 -- paid via spend_reaction(), never spend_action()"
	)

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one Strike (the Skeleton's lethal Opportunistic Strike) must have resolved")
	var attack_event = attack_events[0]
	assert_eq(attack_event.attacker_name, "Skeleton", "the resolved Strike must be attributed to the Skeleton (the reactor), not Titus (the mover)")
	assert_eq(attack_event.target_name, "Titus", "the resolved Strike's target must be Titus (the mover)")
	assert_true(attack_event.hit, "the guaranteed-hit AC must actually produce a hit")
	assert_true(attack_event.damage_final > 0, "the resolved, lethal Opportunistic Strike must apply real, positive damage")

	# Sanity check: the Skeleton (the reactor) never moved -- only Titus (the
	# mover) attempted to Stride in this scenario, and that Stride was
	# cancelled.
	assert_true(skeleton.hex_coord.equals(skeleton_hex), "the Skeleton (the reactor) must remain at its own hex")
