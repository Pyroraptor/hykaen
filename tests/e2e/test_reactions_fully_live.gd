extends GutTest
## tests/e2e/test_reactions_fully_live.gd — FEAT-010 (US-010): the G6
## CAPSTONE end-to-end steel-thread test for "Reactions Are Fully Live".
##
## Boots the REAL res://MainScene.tscn composition root (G2 — never a
## hand-wired double for ANY reaction-path component) and, in a SINGLE run,
## drives the complete entry-to-exit steel thread this iteration's design
## notes describe:
##
##   entry  — a real player Strike (Titus -> Skeleton) that makes the REAL
##            enemy AI (infrastructure/ai_reaction_policy.gd's
##            AIReactionPolicy, wired at MainScene.gd's `enemy_reaction_chooser`
##            field — never infrastructure/auto_reaction_chooser.gd's headless
##            test double) genuinely choose a reaction (Dodge/Parry/Block),
##            producing a visible Miss/hp change AND a visible action-budget
##            drop for the Skeleton;
##   exit   — a real Stride that opens a genuine OpportunisticStrike reaction
##            window for Titus (the REAL, blocking scenes/ui/reaction_prompt_ui.gd
##            pop-up, driven via its own production press_option() entry point
##            — never a scripted ReactionChooserPort/HexChoiceResolverPort
##            double standing in for the player), whose resolved Strike lands
##            (hp change + reaction spend) BEFORE the mover's (the Skeleton's)
##            hex_coord/on-screen token ever changes — repeated twice at the
##            SAME fixed seed to prove the entire decision-log stream (not
##            merely the final state) replays byte-for-byte identically.
##
## ── FEAT-234 (resolves DEF-001, depends on FIX-001/FIX-004/FIX-009) ────────
##
## Prior to this feature, the exit leg above drove the Skeleton's Stride by
## calling `MainScene._resolve_enemy_stride_opportunistic_window()` DIRECTLY
## — the very composition-root SEAM core/combat/ai.gd's own decide_action()
## awaits, bypassed rather than exercised. That bypass existed because, in
## this project's single-enemy/single-party prologue fixture, Titus is BOTH
## the Skeleton's only possible target AND the only possible OpportunisticStrike
## reactor — and those two conditions are mutually exclusive for one and the
## same combatant (decide_action() only ever Strides toward a target that is
## OUT of reach, while OpportunisticStrikeEligibility requires the reactor be
## ADJACENT to the mover's START hex; see tests/integration/
## test_ai_decide_action_opportunistic_strike_trigger.gd's own header doc,
## FEAT-233, for the exhaustive proof). FIX-001 (AIReactionPolicy's
## opportunistic_strike branch), FIX-004 (initiative-ordered candidate
## reactors) and FIX-009 (FEAT-233's dedicated boot-real coverage for both
## Stride directions, in isolation) landed the surrounding machinery, but
## left THIS capstone as the one remaining live-play call site still
## invoking the seam directly instead of going through decide_action()
## itself — exactly the "green tests, dead in play" pattern this
## remediation pass exists to close.
##
## This feature closes that gap using FEAT-233's OWN sanctioned technique
## (see that suite's header doc, restated here): decide_action()'s
## documented `targets`/`other_combatants` parameters are populated so the
## Skeleton's chosen Stride TARGET is a synthetic, out-of-reach decoy
## combatant (never Titus — so `_select_target()`/`_is_in_reach()` genuinely
## compute "out of reach" and decide_action() genuinely issues a Stride),
## while the REAL, live Titus (`instance._party[0]`, at his true boot
## position) is supplied via `other_combatants` as the sole eligible
## OpportunisticStrike reactor. A fresh, real, unmodified `core/combat/ai.gd`
## AI instance's `set_stride_reaction_resolver_fn()` is bound to
## `Callable(instance, "_resolve_enemy_stride_opportunistic_window")` — the
## EXACT SAME production Callable MainScene.gd's own composition root binds
## onto its OWN `ai_decision_port` in _ready() — so every reaction-path
## collaborator underneath it (ResolveStrideUseCase, OpenReactionWindowUseCase,
## ReactionWindow, TurnController, PlayerReactionChooser, ReactionPromptUI,
## ResolveActionUseCase) is still the exact, live, unmodified,
## composition-root-wired production instance
## (test_zero_test_double_wiring_for_reaction_path_components below proves
## this by identity, unchanged by this feature). The Stride itself — the
## `core/rules/movement.gd` Movement.stride() domain mutation — now happens
## INSIDE decide_action() (core/combat/ai.gd's own `_stride_toward_target()`),
## never re-invoked or re-implemented by this test; this test only mirrors
## core/application/round_session.gd's own post-decide_action() convention of
## syncing the on-screen token via `hex_grid_view.move_token(actor_id,
## decision.destination)` (see round_session.gd's `_reposition_mover_token()`)
## — the ONE step decide_action() itself never performs (ai.gd is domain/
## application-adjacent and never touches Presentation).
##
## Only ONE Stride direction (enemy-mover Skeleton Strides, player-reactor
## Titus responds via the real pop-up) is driven inside this SAME choreography:
## Titus's shared per-round ActionEconomy enforces "exactly one Action-type
## spend per turn" (core/rules/action_economy.gd's `_action_used` flag —
## FR-002), and Titus's entry-leg Strike ALREADY consumes his one action this
## turn, so he cannot ALSO organically Stride (via
## MainScene._verb_bar_stride_execute(), the real Stride verb) within this
## SAME turn without ending it and cycling a full extra round — a much larger
## change than "update this test's Stride leg" calls for. FR-005's OTHER
## direction ("a Stride by either side" — the player-mover/enemy-reactor
## half) is exhaustively covered, organically, at boot-real MainScene
## granularity, by the dedicated sibling suite tests/integration/
## test_player_stride_provokes_enemy_opportunistic_strike.gd (FEAT-233),
## which this feature leaves untouched and still passing — so FR-005's
## "either side" exit criterion is satisfied, organically, across the full
## test suite; this capstone's own job is solely to stop being the one
## remaining direct-seam-invocation call site for the leg it DOES drive.
##
## Determinism (fixture data, not RNG rigging): outcomes are pinned by
## mutating plain combatant Dictionary fields (mobility skill, ac, hp) that
## production call paths already read — the SAME established technique
## tests/gut/test_e2e_dodge_step_capstone.gd's `_force_guaranteed_dodge_success()`
## and tests/integration/test_mainscene_hit_reaction_apply.gd's
## `AC_GUARANTEED_HIT`/`OVERWHELMING_MITIGATION_STAT` already use — never a
## scripted/substitute RandomPort or a re-derived hit/damage computation of
## this test's own. The underlying seeded RNG (GodotRandomAdapter, seed=42)
## is exercised for real on every roll; test_criteria #4 (repeated-run
## determinism) proves that seeded math — and every reaction decision
## downstream of it — replays byte-for-byte identically.
##
## Verifies (test_criteria):
##   1. Boots the real MainScene.tscn with zero test-double wiring for any
##      reaction-path component (see test_zero_test_double_wiring_for_reaction_path_components()).
##   2. A real player Strike vs the Skeleton produces an AI-CHOSEN Dodge/
##      Parry/Block, visible as an hp/miss change PLUS an action-budget drop
##      for the Skeleton.
##   3. A real Stride, driven organically through core/combat/ai.gd's
##      decide_action() (never the composition-root seam directly), triggers
##      and FULLY resolves an Opportunistic Strike (hp change + reaction
##      spend) BEFORE the mover's hex_coord/token ever changes.
##   4. The identical outcome and decision-log stream (not merely final
##      state) is reproduced across two independent runs at the same fixed
##      seed.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const AIReactionPolicyClass       = preload("res://infrastructure/ai_reaction_policy.gd")
const AutoReactionChooserClass    = preload("res://infrastructure/auto_reaction_chooser.gd")
const PlayerReactionChooserClass  = preload("res://presentation/player_reaction_chooser.gd")
const ReactionWindowClass         = preload("res://core/application/reaction_window.gd")
const AIClass                      = preload("res://core/combat/ai.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed:
## Titus acts first and the sole enemy (Skeleton) starts adjacent to him
## (mirrors tests/integration/test_mainscene_hit_reaction_apply.gd's
## identically-valued/documented PROLOGUE_SEED).
const PROLOGUE_SEED: int = 42

## FORCED_DODGE_MOBILITY — mirrors tests/gut/test_e2e_dodge_step_capstone.gd's
## `_force_guaranteed_dodge_success()` exactly: an absurdly high Mobility
## skill guarantees MobilityDodgeRule.dodge_worthwhile() (and therefore
## infrastructure/ai_reaction_policy.gd's real AIReactionPolicy.choose())
## picks "dodge" for the Skeleton's PreHitAvoidance window regardless of
## which d20 faces the real, seeded RNG actually rolls.
const FORCED_DODGE_MOBILITY: int = 500

## AC_GUARANTEED_HIT — mirrors tests/integration/test_mainscene_hit_reaction_apply.gd's
## identically-named/valued constant: an absurdly low AC guarantees a hit
## with no RNG/seed edits.
const AC_GUARANTEED_HIT: int = -1000

## SURVIVABLE_HP — the Skeleton's hp is pinned to this (an overwhelming
## value versus any single weapon roll) immediately before the
## Opportunistic Strike leg, so the resolved Strike's damage is genuinely
## applied and observable (hp decreases) without ever coincidentally
## defeating the Skeleton -- keeping `mover_downed`/`stride_should_commit`
## on their ordinary, "the Stride still commits" branch so this test can
## also observe the SAME Movement.stride() commit `ai.gd`'s own
## `_stride_toward_target()` performs internally, before ever returning.
const SURVIVABLE_HP: int = 500

## DECOY_TARGET_DISTANCE — how far (in hexes, along the q-axis) the
## synthetic Stride-forcing decoy target is placed from the Skeleton's own
## start hex: far enough (> 1) to fail the Skeleton's own melee reach check
## (forcing decide_action() to choose "Stride" over "Strike"), matching
## core/combat/ai.gd's own `_is_adjacent()` melee-reach contract.
const DECOY_TARGET_DISTANCE: int = 3


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _id(combatant: Dictionary) -> String:
	return combatant.get("combatant_id", combatant.get("name", ""))


func _hex_tuple(hex_coord) -> Array:
	return [hex_coord.q, hex_coord.r]


## _decision_log_stream(instance) -> Array[String] — a byte-comparable
## snapshot of EVERY round event this run has emitted so far, in emission
## order, read straight off the REAL ConsoleEventSinkAdapter's `log`
## (never a re-derived/recomputed trace of this test's own) — the
## "decision-log stream" test_criteria #4 requires be reproduced
## byte-for-byte across two independent runs, not merely the final state.
func _decision_log_stream(instance) -> Array:
	var stream: Array = []
	for event in instance.event_sink.log:
		if event.has_method("to_dict"):
			stream.append(str(event.to_dict()))
		else:
			stream.append(str(event))
	return stream


# ══════════════════════════════════════════════════════════════════════════
# _drive_full_steel_thread(instance) -> Dictionary — the ONE choreography
# both the primary capstone test and the repeated-run determinism test
# below share (never duplicated), so a fixture/wiring change only ever
# needs updating in one place. Performs ONLY fixture-sanity assertions
# (never outcome assertions -- those belong to each calling test) and
# returns a snapshot Dictionary of plain, byte-comparable primitives.
# ══════════════════════════════════════════════════════════════════════════
func _drive_full_steel_thread(instance) -> Dictionary:
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)

	var titus: Dictionary = instance._party[0]
	var skeleton: Dictionary = instance._enemies[0]
	var skeleton_id: String = _id(skeleton)
	var titus_id: String = _id(titus)

	# ── LEG A (entry_point): a real player Strike vs the Skeleton, forced
	# to a genuine, real AIReactionPolicy-chosen Dodge. ─────────────────────
	skeleton["skills"] = {"mobility": FORCED_DODGE_MOBILITY}

	var skeleton_ae = instance._action_economy_for(skeleton)
	var titus_ae = instance._action_economy_for(titus)
	var skeleton_budget_before_leg_a: int = skeleton_ae.get_remaining()
	var skeleton_hp_before_leg_a: int = skeleton.get("hp_current", -1)

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: the Skeleton is in reach at boot")
	var target_token = instance.hex_grid_view.get_token(target_ids[0])
	assert_not_null(target_token, "fixture assumption: the Skeleton has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	assert_eq(instance.event_log_view.get_entry_count(), 1, "fixture assumption: exactly one row exists after the ONE resolved Strike")
	var strike_attack_event_id = instance.event_log_view.get_entry(0).get("attack_event_id", "")
	var strike_paired_reaction = instance.event_log_view.get_paired_reaction(strike_attack_event_id, "PreHitAvoidance")
	assert_not_null(strike_paired_reaction, "fixture assumption: record_reaction() must have paired a ReactionResolvedEvent to this Strike's PreHitAvoidance window")

	var strike_structured_attack = instance.event_log_view.get_structured_attack(strike_attack_event_id)
	assert_not_null(strike_structured_attack, "fixture assumption: the structured AttackEvent must be retrievable for the resolved Strike")

	# Point-in-time captures (NEVER re-read later, since `skeleton`'s own
	# hp_current/ac fields are deliberately overwritten for LEG B below, and
	# `skeleton_ae`'s own remaining budget keeps changing across this whole
	# choreography) — this is exactly the bug class this comment guards
	# against: reading a live Dictionary/ActionEconomy field lazily at
	# snapshot-construction time would silently capture LEG B's (or the
	# final Stride commit's) value instead of LEG A's own.
	var skeleton_budget_after_leg_a: int = skeleton_ae.get_remaining()
	var skeleton_hp_after_leg_a: int = skeleton.get("hp_current", -1)

	# ── LEG B (exit_point): a real Stride — driven ORGANICALLY through
	# core/combat/ai.gd's own decide_action() public entry point (FEAT-234;
	# never the composition-root seam directly) — that opens and FULLY
	# resolves a genuine Opportunistic Strike for Titus (the reactor) BEFORE
	# the Skeleton's own hex_coord/token ever changes. ──────────────────────
	skeleton["ac"] = AC_GUARANTEED_HIT
	skeleton["hp_current"] = SURVIVABLE_HP
	skeleton["hp_max"] = SURVIVABLE_HP

	var titus_budget_before_leg_b: int = titus_ae.get_remaining()

	var mover_start_hex = skeleton.get("hex_coord", null)
	assert_not_null(mover_start_hex, "fixture assumption: the Skeleton carries a hex_coord before its Stride")
	var mover_hex_before_leg_b: Array = _hex_tuple(mover_start_hex)

	# `decoy_target` — a synthetic, out-of-reach, hostile-to-the-Skeleton
	# combatant, NEVER Titus himself: this is what lets decide_action()
	# genuinely, organically compute "the chosen target is out of reach" and
	# issue a real Stride, while the REAL, live Titus (still at his true,
	# adjacent boot position) is supplied separately via `other_combatants`
	# as the sole genuinely eligible OpportunisticStrike reactor — the SAME
	# reading of decide_action()'s own contract
	# tests/integration/test_ai_decide_action_opportunistic_strike_trigger.gd
	# (FEAT-233) already establishes and justifies at length in its own
	# header doc. `decoy_target` never reacts (it fails
	# OpportunisticStrikeEligibility's adjacency check against
	# `mover_start_hex`), so only Titus's window is ever offered.
	var decoy_target: Dictionary = {
		"name": "Steel Thread Decoy Target",
		"combatant_id": "steel_thread_decoy_target",
		"hp_current": 20, "hp_max": 20, "ac": 14,
		"hex_coord": HexCoordClass.new(mover_start_hex.q + DECOY_TARGET_DISTANCE, mover_start_hex.r),
		"_is_enemy": false,
	}

	var displayed_options_when_opened: Array = []
	var press_opportunistic_strike := func():
		assert_true(instance.reaction_prompt_ui.is_open(), "the REAL OpportunisticStrike pop-up must genuinely be open before this deferred press fires")
		displayed_options_when_opened.append_array(instance.reaction_prompt_ui.get_displayed_options())
		instance.reaction_prompt_ui.press_option("opportunistic_strike")
	press_opportunistic_strike.call_deferred()

	# `observed_stride_resolver` wraps -- never replaces -- the EXACT SAME
	# production Callable MainScene.gd's own composition root binds onto its
	# `ai_decision_port` in _ready() (`Callable(instance,
	# "_resolve_enemy_stride_opportunistic_window")`, itself a thin shim over
	# presentation/reaction_controller.gd's real
	# resolve_enemy_stride_opportunistic_window()). The wrapper only
	# OBSERVES -- it awaits the real call through to completion and snapshots
	# plain primitives at the one instant that call guarantees is BOTH
	# "after the reaction fully resolved" AND "before core/rules/movement.gd's
	# Movement.stride() (called by ai.gd immediately after this Callable
	# returns, still inside the SAME decide_action() invocation) ever mutates
	# `mover`'s hex_coord" -- this is what test_criteria #3's ordering proof
	# rests on, since decide_action() itself does not suspend a second time
	# between resolving the reaction and committing the Stride.
	# NOTE: GDScript lambdas capture outer locals BY VALUE at creation time —
	# a plain `x = ...` reassignment inside the lambda below would never
	# propagate back to this function's own scope. `_leg_b_capture` is a
	# single Dictionary "box" instead: lambdas capture Dictionaries/Arrays by
	# REFERENCE, so mutating its KEYS in place (never rebinding the
	# Dictionary itself) is what actually lets this function observe values
	# written inside `observed_stride_resolver` below.
	var real_stride_resolver := Callable(instance, "_resolve_enemy_stride_opportunistic_window")
	var _leg_b_capture: Dictionary = {
		"result": {},
		"mover_hex_immediately_after_reaction": [],
		"skeleton_hp_immediately_after_reaction": -1,
		"titus_budget_after_leg_b": -1,
	}

	var observed_stride_resolver := func(mover: Dictionary, mover_start, candidate_reactors: Array):
		var result: Dictionary = await real_stride_resolver.call(mover, mover_start, candidate_reactors)
		_leg_b_capture["result"] = result
		_leg_b_capture["mover_hex_immediately_after_reaction"] = _hex_tuple(mover.get("hex_coord", mover_start))
		_leg_b_capture["skeleton_hp_immediately_after_reaction"] = mover.get("hp_current", -1)
		_leg_b_capture["titus_budget_after_leg_b"] = titus_ae.get_remaining()
		return result

	var ai_instance = AIClass.new()
	ai_instance.set_stride_reaction_resolver_fn(observed_stride_resolver)

	# ── The organic entry point itself (FEAT-234): a real, unmodified
	# core/combat/ai.gd AI instance's decide_action() -- never
	# `instance._resolve_enemy_stride_opportunistic_window()` called directly. ──
	var decision: Dictionary = await ai_instance.decide_action(skeleton, [decoy_target], skeleton_ae, [titus])

	assert_eq(decision.get("action_type", ""), "Stride", "fixture assumption: decide_action() must organically issue a Stride once its chosen (decoy) target is genuinely out of melee reach")
	var chosen_destination = decision.get("destination", null)
	assert_not_null(chosen_destination, "fixture assumption: an organic Stride decision must carry a destination hex")

	# Sync the on-screen token exactly the way core/application/round_session.gd's
	# own post-decide_action() convention does (`_token_reposition_fn.call(actor_id,
	# destination)`) -- decide_action()/Movement.stride() themselves never touch
	# Presentation, so this is the caller's (this test's, standing in for
	# round_session's own real call site) responsibility, not a re-implementation
	# of the Stride's own domain commit (already performed, for real, inside
	# decide_action() above).
	instance.hex_grid_view.move_token(skeleton_id, chosen_destination)

	# Extract only PRIMITIVE, byte-comparable fields from the Opportunistic
	# Strike's own resolution -- never the raw `reactions` Array itself,
	# which embeds a live `reactor` Dictionary (carrying a HexCoord, which
	# has no `==` override) and a raw RefCounted AttackEvent (`event`,
	# compared by IDENTITY, not value) -- both would spuriously mismatch
	# across two independently-constructed runs even when every underlying
	# VALUE is identical.
	var stride_reaction_result: Dictionary = _leg_b_capture["result"]
	var mover_hex_immediately_after_reaction: Array = _leg_b_capture["mover_hex_immediately_after_reaction"]
	var skeleton_hp_immediately_after_reaction: int = _leg_b_capture["skeleton_hp_immediately_after_reaction"]
	var titus_budget_after_leg_b: int = _leg_b_capture["titus_budget_after_leg_b"]

	var reactions: Array = stride_reaction_result.get("reactions", [])
	assert_eq(reactions.size(), 1, "fixture assumption: exactly one reactor (Titus) must have been offered the OpportunisticStrike window")
	var ostrike_choice: String = reactions[0].get("choice", "")
	var ostrike_strike_result: Dictionary = reactions[0].get("strike_result", {})

	return {
		"strike_row_text":                       instance.event_log_view.get_row_text(0),
		"strike_choice":                          strike_paired_reaction.choice,
		"strike_outcome":                         strike_paired_reaction.outcome,
		"strike_hit":                             strike_structured_attack.is_hit,
		"strike_damage_final":                    strike_structured_attack.damage_final,
		"skeleton_budget_before_leg_a":           skeleton_budget_before_leg_a,
		"skeleton_budget_after_leg_a":            skeleton_budget_after_leg_a,
		"skeleton_hp_before_leg_a":               skeleton_hp_before_leg_a,
		"skeleton_hp_after_leg_a":                skeleton_hp_after_leg_a,
		"ostrike_choice":                         ostrike_choice,
		"ostrike_resolved":                       ostrike_strike_result.get("resolved", false),
		"ostrike_ok":                             ostrike_strike_result.get("ok", false),
		"ostrike_damage_final":                   ostrike_strike_result.get("damage_final", -1),
		"ostrike_target_defeated":                ostrike_strike_result.get("target_defeated", true),
		"mover_downed":                           stride_reaction_result.get("mover_downed", true),
		"stride_should_commit":                   stride_reaction_result.get("stride_should_commit", false),
		"mover_hex_before_leg_b":                 mover_hex_before_leg_b,
		"mover_hex_immediately_after_reaction":   mover_hex_immediately_after_reaction,
		"skeleton_hp_immediately_after_reaction": skeleton_hp_immediately_after_reaction,
		"displayed_options_when_opened":          displayed_options_when_opened,
		"titus_budget_before_leg_b":              titus_budget_before_leg_b,
		"titus_budget_after_leg_b":               titus_budget_after_leg_b,
		"chosen_destination":                     _hex_tuple(chosen_destination),
		"skeleton_hex_after_stride_commit":       _hex_tuple(skeleton.get("hex_coord")),
		"skeleton_budget_after_stride_commit":    skeleton_ae.get_remaining(),
		"token_hex_after_move":                   _hex_tuple(instance.hex_grid_view.get_token(skeleton_id).hex_coord),
		"decision_log_stream":                    _decision_log_stream(instance),
	}


# ══════════════════════════════════════════════════════════════════════════
# THE capstone: entry point (real player Strike, real AI-chosen reaction) to
# exit point (real Stride, driven organically through core/combat/ai.gd's
# decide_action(), real fully-resolved Opportunistic Strike landing before
# the mover moves) in ONE run, against the live, booted MainScene
# composition root.
# ══════════════════════════════════════════════════════════════════════════

func test_full_steel_thread_strike_reaction_then_stride_opportunistic_strike() -> void:
	var instance = _boot_main_scene()
	var snapshot: Dictionary = await _drive_full_steel_thread(instance)

	# ── test_criteria #2: a real player Strike vs the Skeleton produces an
	# AI-CHOSEN Dodge/Parry/Block, visible as an hp/miss change PLUS an
	# action-budget drop. ────────────────────────────────────────────────
	assert_eq(snapshot["strike_choice"], "dodge", "the REAL AIReactionPolicy must genuinely choose 'dodge' once the Skeleton's Mobility is forced overwhelmingly high")
	assert_string_contains(snapshot["strike_outcome"], "dodge", "the paired reaction's own outcome must be a dodge-family outcome")
	assert_false(snapshot["strike_hit"], "the Skeleton's chosen reaction must resolve this Strike as a Miss (hp/miss change)")
	assert_eq(snapshot["strike_damage_final"], 0, "a Miss must apply zero damage")
	assert_eq(snapshot["skeleton_hp_after_leg_a"], snapshot["skeleton_hp_before_leg_a"], "the Skeleton's hp must be UNCHANGED by a Miss")
	assert_string_contains(snapshot["strike_row_text"], "Miss", "the visible log row must render the Miss outcome")
	assert_string_contains(snapshot["strike_row_text"], "Defense: dodge", "the visible log row must attribute the outcome to the Skeleton's own chosen Dodge reaction")
	assert_eq(
		snapshot["skeleton_budget_after_leg_a"], snapshot["skeleton_budget_before_leg_a"] - 1,
		"the Skeleton's OWN action-budget must visibly drop by exactly 1 (the reaction spend) once it genuinely reacts"
	)

	# ── test_criteria #3: a real Stride, driven organically through
	# core/combat/ai.gd's decide_action() (never the composition-root seam
	# directly), triggers and FULLY resolves an Opportunistic Strike (hp
	# change + reaction spend) BEFORE the mover's hex_coord/token ever
	# changes. ────────────────────────────────────────────────────────────
	assert_true(snapshot["displayed_options_when_opened"].has("opportunistic_strike"), "the REAL OpportunisticStrike pop-up must offer 'opportunistic_strike' as a legal option")

	assert_eq(snapshot["ostrike_choice"], "opportunistic_strike", "the real, blocking pop-up press must be reported back verbatim as the resolved choice")
	assert_true(snapshot["ostrike_resolved"], "an 'opportunistic_strike' choice must FULLY resolve a real Strike (never merely record the choice with no effect)")
	assert_true(snapshot["ostrike_ok"], "the Opportunistic Strike's own Strike must resolve ok")
	assert_false(snapshot["ostrike_target_defeated"], "fixture assumption: the Skeleton's overwhelming hp must survive the Opportunistic Strike")
	assert_true(snapshot["ostrike_damage_final"] > 0, "the Opportunistic Strike's guaranteed hit must apply positive damage")

	assert_false(snapshot["mover_downed"], "the Skeleton must not be downed by its own survivable-hp fixture")
	assert_true(snapshot["stride_should_commit"], "a non-lethal Opportunistic Strike must leave the Stride free to commit")

	# Ordering proof: the resolved Strike's hp change is observable while the
	# mover's own hex_coord is STILL exactly where it started -- captured by
	# `observed_stride_resolver`'s own wrapper at the one instant this is
	# guaranteed true (see that Callable's own doc in _drive_full_steel_thread()).
	assert_eq(snapshot["mover_hex_immediately_after_reaction"], snapshot["mover_hex_before_leg_b"], "the mover's hex_coord must be UNCHANGED immediately after the Opportunistic Strike resolves")
	assert_true(
		snapshot["skeleton_hp_immediately_after_reaction"] < SURVIVABLE_HP,
		"the Opportunistic Strike's damage must already be visible on the Skeleton's hp BEFORE its Stride ever commits"
	)
	assert_eq(
		snapshot["titus_budget_after_leg_b"], snapshot["titus_budget_before_leg_b"] - 1,
		"Titus's OWN action-budget must drop by exactly 1 -- the Opportunistic Strike is paid via spend_reaction(), never a second spend_action()"
	)

	# Only AFTER all of the above had already resolved (inside decide_action()
	# itself) does core/rules/movement.gd's Movement.stride() commit relocate
	# the mover -- proving the "before" half of the ordering guarantee against
	# a real, subsequent position change, not merely against a hex_coord that
	# coincidentally never moves at all.
	assert_ne(snapshot["skeleton_hex_after_stride_commit"], snapshot["mover_hex_before_leg_b"], "the Skeleton's Stride, once decide_action() commits it, must actually relocate it")
	assert_eq(snapshot["skeleton_hex_after_stride_commit"], snapshot["chosen_destination"], "the committed hex_coord must equal decide_action()'s own real Movement.stride() destination")
	assert_eq(snapshot["token_hex_after_move"], snapshot["chosen_destination"], "the on-screen token must visibly relocate to the SAME destination")
	assert_eq(
		snapshot["skeleton_budget_after_stride_commit"], snapshot["skeleton_budget_after_leg_a"] - 1,
		"committing the Stride must spend exactly one of the Skeleton's OWN actions (distinct from the reaction Titus spent)"
	)


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #1: zero test-double wiring for ANY reaction-path component
# — every ReactionChooserPort/ReactionWindow/prompt-UI seam this capstone's
# assertions rest on is the REAL, composition-root-bound production adapter,
# never infrastructure/auto_reaction_chooser.gd's headless test double or a
# locally re-wired stand-in.
# ══════════════════════════════════════════════════════════════════════════

func test_zero_test_double_wiring_for_reaction_path_components() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.enemy_reaction_chooser, "MainScene must wire a real enemy_reaction_chooser at boot")
	assert_true(is_instance_of(instance.enemy_reaction_chooser, AIReactionPolicyClass), "the enemy's reaction chooser must be a REAL AIReactionPolicy instance")
	assert_false(is_instance_of(instance.enemy_reaction_chooser, AutoReactionChooserClass), "the enemy's reaction chooser must NEVER be the headless AutoReactionChooser test double")

	assert_not_null(instance.player_reaction_chooser, "MainScene must wire a real player_reaction_chooser at boot")
	assert_true(is_instance_of(instance.player_reaction_chooser, PlayerReactionChooserClass), "the player's reaction chooser must be a REAL PlayerReactionChooser instance")
	assert_false(is_instance_of(instance.player_reaction_chooser, AutoReactionChooserClass), "the player's reaction chooser must NEVER be the headless AutoReactionChooser test double")
	assert_same(instance.player_reaction_chooser._prompt_ui, instance.reaction_prompt_ui, "PlayerReactionChooser must wrap the REAL, live, booted reaction_prompt_ui -- never a stand-in prompt")

	assert_same(
		instance.turn_controller._reaction_chooser, instance.player_reaction_chooser,
		"TurnController must still be configured with the SAME real player_reaction_chooser MainScene wired at boot -- never re-wired to a local double"
	)
	assert_not_null(instance.turn_controller._reaction_window, "TurnController must carry a real, configured ReactionWindow")
	assert_true(is_instance_of(instance.turn_controller._reaction_window, ReactionWindowClass), "TurnController's reaction window must be a REAL ReactionWindow instance")
	assert_same(instance.turn_controller._reaction_window, instance.reaction_window, "TurnController's reaction window must be the SAME instance MainScene's composition root constructed -- never a second, parallel window")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #4: repeated runs at the SAME fixed seed reproduce the
# identical outcome AND the identical decision-log stream (not merely final
# state).
# ══════════════════════════════════════════════════════════════════════════

func test_repeated_runs_at_fixed_seed_reproduce_identical_outcome_and_decision_log() -> void:
	var instance_run_1 = _boot_main_scene()
	var snapshot_run_1: Dictionary = await _drive_full_steel_thread(instance_run_1)

	var instance_run_2 = _boot_main_scene()
	var snapshot_run_2: Dictionary = await _drive_full_steel_thread(instance_run_2)

	assert_true(snapshot_run_1["decision_log_stream"].size() > 0, "fixture assumption: at least one round event must have been emitted")
	assert_eq(
		snapshot_run_1["decision_log_stream"], snapshot_run_2["decision_log_stream"],
		"the FULL decision-log stream (every emitted round event, in order) must replay byte-for-byte identically across two independent runs at the same fixed seed"
	)

	# Belt-and-braces: every individual outcome field the capstone test above
	# asserts on must also match exactly, not merely the aggregate log.
	for key in snapshot_run_1.keys():
		assert_eq(snapshot_run_2.get(key), snapshot_run_1[key], "snapshot field '%s' must be identical across repeated runs at the same fixed seed" % key)
