extends GutTest
## tests/test_steel_thread_full_e2e.gd — FEAT-010 (US-010, iteration J's
## capstone; depends_on FEAT-006 "Wire reaction resolver into MainScene
## composition root, incl. round continuation" and FEAT-009 "Boot-real-
## MainScene test for combat log richness (Part D)").
##
## THE full steel-thread E2E test: boots the REAL res://MainScene.tscn
## composition root (project.godot's own run/main_scene target) and drives
## an enemy AI turn (round_session.advance_ai_turn() — the SOLE entry point
## for every scenario below; never resolve_action_use_case.resolve() or
## run_autonomous_to_completion() directly) targeting Titus with a weapon
## Strike, through the REAL, on-screen scenes/ui/reaction_prompt_ui.gd pop-up
## (wrapped by the REAL presentation/player_reaction_chooser.gd
## PlayerReactionChooser and core/application/reaction_window.gd
## ReactionWindow MainScene.gd's composition root already wires) — no
## test-local resolver/log double stands in for any of that machinery for
## the scenarios under test. This is the FR-011 human-sign-off automated
## evidence base for the whole reaction-timing-correction + richer-combat-
## log iteration (docs/iterations/iteration-J-reaction-timing-and-combat-
## log.org).
##
## Scenarios driven (each its own test function, its own fresh MainScene
## boot, fixture: seed=42, Titus at (0,0) adjacent to the sole enemy —
## Skeleton — at (1,0), so the Skeleton's Strike never needs a Stride first):
##   - dodge-success       — PreHitAvoidance: Dodge chosen and succeeds
##                            (short-circuits the Strike; no OnHitMitigation).
##   - miss                — PreHitAvoidance: Dodge declined; the underlying
##                            attack roll itself misses (no OnHitMitigation).
##   - dodge-fail+parry    — PreHitAvoidance: Dodge declined; the attack HITS
##                            (no reaction spent yet) → OnHitMitigation opens
##                            and Parry is chosen.
##   - dodge-fail+block    — same as above, Block chosen instead.
##   - dodge-fail+no-reaction-hit — same as above, but the OnHitMitigation
##                            window is itself declined (Pass).
## Hit/miss/Dodge-success are forced DETERMINISTICALLY by mutating the live
## Titus combatant Dictionary's own ac/skills fields BEFORE calling
## advance_ai_turn() (mirrors tests/e2e/test_full_steel_thread_e2e.gd's own
## "mutate the same live Dictionary a production call path already reads"
## convention) — never a scripted/substitute RNG port, so the REAL
## GodotRandomAdapter backing this boot's resolve_action_use_case keeps
## rolling real dice; only the THRESHOLD each roll is compared against is
## pinned to an extreme value so the outcome is deterministic regardless of
## the actual roll drawn.
##
## FEAT-003 (US-002 / FR-002, G3 remediation) update: the OnHitMitigation ask
## is now GENUINELY applied to the Strike it was asked about, rather than
## merely traced and discarded (the prior "KNOWN, DOCUMENTED INTERIM
## CHARACTERISTIC" this file used to pin here). round_session.gd's
## advance_ai_turn() now defers the commit — via
## resolve_to_hit_uc/apply_on_hit_defense_uc — until AFTER the OnHitMitigation
## choice is known, so the structured AttackEvent this suite observes is not
## recorded until the ENTIRE Strike (both reaction windows) has resolved, and
## a real Parry/Block choice genuinely changes damage_final vs. damage_raw.
## _run_dodge_declined_hit_scenario() below deterministically forces
## Parry/Block to fully succeed (mirrors this file's own established
## "mutate the live combatant Dictionary a production call path already
## reads" technique for ac/skills) by pinning Titus's own weapon's
## parry_bonus/block_value to an overwhelming value, so damage_final is
## pinned to 0 for those two scenarios regardless of the real dice drawn.
##
## The combat-log seam (core/application/round_session.gd's
## set_event_log_record_attack_fn()) is wired by THIS suite directly against
## the REAL, already-booted round_session/event_log_view instances — MainScene.gd
## itself does not yet perform this one composition-root wiring step (see
## round_session.gd's `_event_log_record_attack_fn` doc) — mirroring
## tests/test_mainscene_combat_log_richness.gd's (FEAT-009) own established,
## explicitly-endorsed convention for this exact interim gap, including its
## "manually correlate a structured ReactionResolvedEvent via record_reaction()"
## technique. No production file is modified by this feature (files_to_modify
## is empty) — this file exercises only public seams/accessors FEAT-002/
## FEAT-006/FEAT-007/FEAT-009 already established.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass = preload("res://core/rules/round_events.gd")
const ReactionResolvedEventClass = preload("res://core/log/reaction_resolved_event.gd")

const SEED: int = 42

## _reaction_event_seq — monotonic id suffix for the structured
## ReactionResolvedEvent records this suite manually constructs (see
## _record_correlated_reaction() below) — harmless to share across this
## file's separate test functions/boots, since each carries a fresh
## event_log_view whose own record_reaction() pairing is keyed by
## (attack_event_id, window_id), never by this cosmetic id string.
var _reaction_event_seq: int = 0


# ══════════════════════════════════════════════════════════════════════════
# Shared fixture / helpers
# ══════════════════════════════════════════════════════════════════════════

func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	# This suite exercises reaction TIMING/logging, not the Dodge-Step follow-up.
	# A successful Dodge now fires the live Dodge-Step hex prompt inside
	# advance_ai_turn() (round_session.gd), which the REAL _UIHexChoiceResolver
	# would block on, awaiting a battlefield click no headless test can deliver.
	# Null the resolver so MainScene.resolve_hex_choice() returns null → the
	# Dodge-Step is a clean no-op here (the Dodge itself still negates the hit).
	instance.hex_choice_resolver = null
	return instance


## _find_action_economy_for(instance, combatant) -> ActionEconomy or null —
## looks up the live ActionEconomy paired with `combatant` in the real,
## booted RoundSession's own turn-order entries, matched by combatant_id
## (falling back to name) — mirrors this codebase's established
## non-invasive observation convention (e.g. tests/integration/
## test_steel_thread_e2e.gd's `_action_economy_by_id()`), never a mock/stub.
func _find_action_economy_for(instance, combatant):
	var combatant_id: String = combatant.combatant_id
	for entry in instance.round_session._entries:
		var candidate = entry["combatant"]
		if candidate.combatant_id == combatant_id:
			return entry["action_economy"]
	return null


## _wire_event_log_seam(instance) -> Array — wires round_session's FEAT-007
## set_event_log_record_attack_fn() EventLogPort seam into the REAL,
## already-booted event_log_view (see file-level doc: MainScene.gd itself
## does not yet perform this composition-root wiring step). Returns the
## Array every recorded structured AttackEvent is appended to, for direct
## test observation (mirrors tests/test_mainscene_combat_log_richness.gd's
## identical convention).
func _wire_event_log_seam(instance) -> Array:
	var recorded_attacks: Array = []
	instance.round_session.set_event_log_record_attack_fn(func(attack_event):
		recorded_attacks.append(attack_event)
		instance.event_log_view.record_attack(attack_event)
	)
	return recorded_attacks


## _advance_to_enemy_turn(instance) -> void — ends Titus's own turn via the
## real RoundSession.end_current_turn() (a FREE pass — US-002/ADR-010's
## documented contract: spends no action, leaves Titus's full ActionEconomy
## budget available for the reactions this suite is about to script), so the
## round cursor settles on the Skeleton (the prologue fixture's sole enemy) —
## the precondition every scenario below needs before calling
## advance_ai_turn() directly as the sole entry point for the Strike itself.
func _advance_to_enemy_turn(instance) -> void:
	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: Titus (the player) must act first at seed=42"
	)
	var end_result: Dictionary = instance.round_session.end_current_turn()
	assert_true(end_result.get("ok", false), "ending Titus's own turn (no action taken) must succeed")
	assert_true(
		instance.round_session.current_actor().get("_is_enemy", false),
		"the round cursor must now sit on the Skeleton enemy"
	)


## _press_next_deferred(instance, remaining) -> void — schedules pressing
## each expected reaction-prompt window in `remaining`, IN ORDER, via
## Godot's deferred-call queue (mirrors this codebase's established
## tests/integration/test_steel_thread_e2e.gd / tests/integration/
## test_reaction_prompt_ui.gd `call_deferred()` convention for driving the
## REAL, on-screen ReactionPromptUI without a human present). Each step's
## press is only SCHEDULED (call_deferred()) once the PRIOR step has itself
## already pressed its own option — by the time that happens,
## advance_ai_turn()'s coroutine has already synchronously continued
## (through resolve_action_use_case.resolve(), and opened the NEXT window
## when this Strike's flow calls for one) BEFORE this next step's deferred
## call even fires, so is_open()/get_displayed_options() are guaranteed
## accurate whenever each step's press actually executes.
##
## Each step Dictionary: {expected_options: Array, choice: String,
## assert_fn: Callable (optional, extra assertions run the instant this
## step's press fires — e.g. proving PreHitAvoidance fires BEFORE the roll /
## OnHitMitigation fires AFTER it, via the structured AttackEvent seam's own
## recorded-count at that exact moment)}.
func _press_next_deferred(instance, remaining: Array) -> void:
	if remaining.is_empty():
		return
	var step: Dictionary = remaining.pop_front()
	var press_fn := func():
		assert_true(
			instance.reaction_prompt_ui.is_open(),
			"expected the real, on-screen reaction prompt to be open for choice '%s'" % str(step.get("choice", ""))
		)
		assert_eq(instance.reaction_prompt_ui.get_displayed_options(), step.get("expected_options", []))
		var assert_fn: Callable = step.get("assert_fn", Callable())
		if assert_fn.is_valid():
			assert_fn.call()
		instance.reaction_prompt_ui.press_option(step.get("choice", "none"))
		_press_next_deferred(instance, remaining)
	press_fn.call_deferred()


## _record_correlated_reaction(instance, attack_event_id, window_id, choice,
## resolved_by, outcome) -> bool — manually constructs+records a structured
## core/log/reaction_resolved_event.gd ReactionResolvedEvent correlated to
## `attack_event_id` (mirrors tests/test_mainscene_combat_log_richness.gd's
## established convention for this exact interim gap — round_session.gd does
## not yet perform this pairing itself for either reaction window). Returns
## event_log_view.record_reaction()'s own acceptance result.
func _record_correlated_reaction(instance, attack_event_id, window_id: String, choice: String, resolved_by: String, outcome: String) -> bool:
	_reaction_event_seq += 1
	var reaction_event = ReactionResolvedEventClass.new(
		"RE-full-e2e-%d" % _reaction_event_seq, attack_event_id, window_id, choice, resolved_by, outcome
	)
	return instance.event_log_view.record_reaction(reaction_event, attack_event_id)


## _reaction_window_opened_events(instance) -> Array — every RoundEvents.
## ReactionWindowOpenedEvent this boot's real event_sink has recorded for
## Titus (the reactor), in emission order.
func _reaction_window_opened_events(instance) -> Array:
	return instance.event_sink.log.filter(
		func(e): return e is RoundEventsClass.ReactionWindowOpenedEvent and e.reactor_name == "player_0"
	)


func _fixture_titus_and_skeleton(instance) -> Dictionary:
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter has exactly one enemy")
	var titus = instance._party[0]
	var skeleton = instance._enemies[0]
	assert_eq(titus.name, "Titus")
	assert_eq(skeleton.name, "Skeleton")
	return {"titus": titus, "skeleton": skeleton}


# ══════════════════════════════════════════════════════════════════════════
# Scenario 1 — dodge-success: PreHitAvoidance offers Dodge, it is chosen and
# succeeds (defense_value substituted by an overwhelming Mobility check) —
# the Strike is avoided entirely; OnHitMitigation must never fire (the
# <=1-reaction-per-Strike budget).
# ══════════════════════════════════════════════════════════════════════════

func test_scenario_dodge_success_short_circuits_the_strike_with_no_onhit_window() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var fixture: Dictionary = _fixture_titus_and_skeleton(instance)
	var titus = fixture["titus"]
	var skeleton = fixture["skeleton"]

	# Deterministic Dodge success regardless of the real RNG's next draws:
	# core/rules/resolution.gd's resolve_to_hit() dodge branch substitutes
	# defense_value with (d20 Mobility roll + skills.mobility) — an
	# overwhelmingly high mobility skill guarantees it exceeds any possible
	# Skeleton roll_total.
	titus["skills"] = {"mobility": 9999}

	var recorded_attacks: Array = _wire_event_log_seam(instance)
	_advance_to_enemy_turn(instance)

	var titus_action_economy = _find_action_economy_for(instance, titus)
	assert_not_null(titus_action_economy)
	var budget_before: int = titus_action_economy.get_remaining()

	_press_next_deferred(instance, [
		{
			"expected_options": ["dodge", "none"],
			"choice": "dodge",
			"assert_fn": func(): assert_eq(
				recorded_attacks.size(), 0,
				"PreHitAvoidance must fire BEFORE the attack roll -- no structured AttackEvent may exist yet"
			),
		},
	])

	var result: Dictionary = await instance.round_session.advance_ai_turn()
	await get_tree().process_frame

	assert_true(result.get("ok", false), "advance_ai_turn() must resolve the Skeleton's turn")
	assert_false(instance.reaction_prompt_ui.is_open(), "the pop-up must close once every reaction for this Strike has resolved")

	# ── Entry point + event counts (test_criteria #2/#4) ────────────────────
	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "advance_ai_turn() must resolve exactly one Strike")
	assert_eq(recorded_attacks.size(), 1, "exactly one structured AttackEvent must be recorded for this Strike")

	var prehit_opens: Array = _reaction_window_opened_events(instance).filter(func(e): return e.trigger_type == "PreHitAvoidance")
	var onhit_opens: Array = _reaction_window_opened_events(instance).filter(func(e): return e.trigger_type == "OnHitMitigation")
	assert_eq(prehit_opens.size(), 1, "PreHitAvoidance must fire exactly once for this Strike")
	assert_eq(onhit_opens.size(), 0, "OnHitMitigation must NOT fire once a reaction (Dodge) was already spent this Strike")

	# ── Budget (test_criteria #4: reactions_spent <= 1) ─────────────────────
	var reactions_spent: int = budget_before - titus_action_economy.get_remaining()
	assert_true(reactions_spent <= 1, "at most one reaction may be spent per Strike")
	assert_eq(reactions_spent, 1, "a chosen Dodge must spend exactly one reaction")

	# ── Resolution: a successful Dodge avoids the Strike entirely ───────────
	var attack_event = recorded_attacks[0]
	assert_eq(attack_event.attacker_id, skeleton.combatant_id)
	assert_eq(attack_event.target_id, titus.combatant_id)
	assert_false(attack_event.is_hit, "a successful Dodge must avoid the Strike -- a miss")
	assert_eq(attack_event.damage_final, 0)

	# ── Final combat log entry (test_criteria #5) ───────────────────────────
	# FEAT-008 (US-008 / FR-007, Iteration J-R2 Part D): MainScene's
	# composition root now wires RenderCombatLogUseCase into
	# round_session.advance_ai_turn() FOR REAL, so the PreHitAvoidance
	# ReactionResolvedEvent for this Strike is ALREADY correlated to the real
	# AttackEvent by production code -- a manual record_reaction() call here
	# would now be rejected as a duplicate pairing for the SAME
	# attack_event_id + window_id (see event_log_view.gd's documented dedup
	# contract). Assert the ALREADY-paired reaction directly instead.
	var paired_reaction = instance.event_log_view.get_paired_reaction(attack_event.id, "PreHitAvoidance")
	assert_not_null(
		paired_reaction,
		"production code (RenderCombatLogUseCase, wired via round_session.gd's advance_ai_turn()) must already have paired a ReactionResolvedEvent to this Strike's PreHitAvoidance window"
	)
	if paired_reaction != null:
		assert_eq(paired_reaction.choice, "dodge")
		assert_eq(paired_reaction.outcome, "dodge_succeeded")

	var defense_outcome: String = instance.event_log_view.get_active_defense_outcome_string(attack_event.id)
	assert_eq(defense_outcome, "dodge-succeeded")

	var rendered: String = instance.event_log_view.render_attack_entry(attack_event.id)
	assert_string_contains(rendered, str(attack_event.roll_total), "the log entry must show the real roll_total")
	assert_string_contains(rendered, "Miss")
	assert_string_contains(rendered, "Defense: dodge-succeeded")


# ══════════════════════════════════════════════════════════════════════════
# Scenario 2 — miss: PreHitAvoidance offers Dodge, it is DECLINED, and the
# underlying attack roll itself misses -- OnHitMitigation must never fire
# (Block/Parry are ON-HIT-only reactions).
# ══════════════════════════════════════════════════════════════════════════

func test_scenario_miss_never_opens_the_onhit_mitigation_window() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var fixture: Dictionary = _fixture_titus_and_skeleton(instance)
	var titus = fixture["titus"]
	var skeleton = fixture["skeleton"]

	# Deterministic miss regardless of the real RNG's next draw: an
	# overwhelmingly high passive ac guarantees roll_total never meets it.
	titus["ac"] = 1000

	var recorded_attacks: Array = _wire_event_log_seam(instance)
	_advance_to_enemy_turn(instance)

	var titus_action_economy = _find_action_economy_for(instance, titus)
	var budget_before: int = titus_action_economy.get_remaining()

	_press_next_deferred(instance, [
		{
			"expected_options": ["dodge", "none"],
			"choice": "none",
			"assert_fn": func(): assert_eq(recorded_attacks.size(), 0, "PreHitAvoidance must fire BEFORE the attack roll"),
		},
	])

	var result: Dictionary = await instance.round_session.advance_ai_turn()
	await get_tree().process_frame

	assert_true(result.get("ok", false))
	assert_false(instance.reaction_prompt_ui.is_open())

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1)
	assert_eq(recorded_attacks.size(), 1)

	var prehit_opens: Array = _reaction_window_opened_events(instance).filter(func(e): return e.trigger_type == "PreHitAvoidance")
	var onhit_opens: Array = _reaction_window_opened_events(instance).filter(func(e): return e.trigger_type == "OnHitMitigation")
	assert_eq(prehit_opens.size(), 1)
	assert_eq(onhit_opens.size(), 0, "a miss must never open the OnHitMitigation window")

	var reactions_spent: int = budget_before - titus_action_economy.get_remaining()
	assert_true(reactions_spent <= 1)
	assert_eq(reactions_spent, 0, "declining Dodge must spend no reaction")

	var attack_event = recorded_attacks[0]
	assert_eq(attack_event.attacker_id, skeleton.combatant_id)
	assert_eq(attack_event.target_id, titus.combatant_id)
	assert_false(attack_event.is_hit)
	assert_eq(attack_event.damage_final, 0)

	var paired: bool = _record_correlated_reaction(instance, attack_event.id, "PreHitAvoidance", "none", "player", "none")
	assert_true(paired)

	var defense_outcome: String = instance.event_log_view.get_active_defense_outcome_string(attack_event.id)
	assert_eq(defense_outcome, "none")

	var rendered: String = instance.event_log_view.render_attack_entry(attack_event.id)
	assert_string_contains(rendered, str(attack_event.roll_total))
	assert_string_contains(rendered, "Miss")
	assert_string_contains(rendered, "Defense: none")


# ══════════════════════════════════════════════════════════════════════════
# Scenarios 3-5 — dodge-fail+parry / dodge-fail+block / dodge-fail+no-
# reaction-hit: PreHitAvoidance's Dodge is DECLINED, the attack HITS (no
# reaction spent yet, so the <=1-reaction budget still permits an on-hit
# ask), and OnHitMitigation opens offering Parry+Block -- each scenario
# presses a different option.
# ══════════════════════════════════════════════════════════════════════════

## _run_dodge_declined_hit_scenario(instance, onhit_choice) -> Dictionary —
## the SHARED drive/assert body for scenarios 3-5 (identical setup/timing/
## budget/log-richness assertions; only the OnHitMitigation choice differs),
## returning {attack_event, titus, skeleton} for each caller's own
## scenario-specific final assertions.
func _run_dodge_declined_hit_scenario(instance, onhit_choice: String) -> Dictionary:
	var fixture: Dictionary = _fixture_titus_and_skeleton(instance)
	var titus = fixture["titus"]
	var skeleton = fixture["skeleton"]

	# Deterministic hit regardless of the real RNG's next draw: an
	# overwhelmingly low passive ac guarantees roll_total always meets it.
	titus["ac"] = -1000

	# FEAT-003 (G3 remediation): deterministic on-hit mitigation, mirroring
	# the ac/skills mutation technique above -- an overwhelming parry_bonus
	# guarantees a chosen Parry's (d20 + parry_bonus) roll always strictly
	# exceeds the attacker's roll_total, and an overwhelming block_value
	# guarantees a chosen Block's reduction always meets or exceeds any
	# possible damage_raw -- so damage_final is deterministically 0 for BOTH
	# the "parry" and "block" scenarios below, regardless of the real dice
	# the RNG actually draws for the mitigation roll itself.
	titus["weapon"]["parry_bonus"] = 9999
	titus["weapon"]["block_value"] = 9999

	var recorded_attacks: Array = _wire_event_log_seam(instance)
	_advance_to_enemy_turn(instance)

	var titus_action_economy = _find_action_economy_for(instance, titus)
	var budget_before: int = titus_action_economy.get_remaining()

	_press_next_deferred(instance, [
		{
			"expected_options": ["dodge", "none"],
			"choice": "none",
			"assert_fn": func(): assert_eq(recorded_attacks.size(), 0, "PreHitAvoidance must fire BEFORE the attack roll"),
		},
		{
			# Titus's real longsword (data/weapons/longsword.tres) carries both
			# parry_bonus=4 and block_value=3 -- both Parry and Block are
			# legally offered regardless of which this scenario ultimately
			# presses.
			"expected_options": ["parry", "block", "none"],
			"choice": onhit_choice,
			# FEAT-003 (G3 remediation): the structured AttackEvent is now
			# recorded only AFTER the ENTIRE Strike (both reaction windows,
			# including this OnHitMitigation choice) has resolved -- the
			# genuine two-phase deferred commit this feature wires in. At the
			# moment this window OPENS (before its choice is pressed), the
			# Strike's damage has NOT yet been committed/recorded.
			"assert_fn": func(): assert_eq(
				recorded_attacks.size(), 0,
				"OnHitMitigation must fire BEFORE the structured AttackEvent is recorded -- the commit is deferred until this choice is known"
			),
		},
	])

	var result: Dictionary = await instance.round_session.advance_ai_turn()
	await get_tree().process_frame

	assert_true(result.get("ok", false))
	assert_false(instance.reaction_prompt_ui.is_open())

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1)
	assert_eq(recorded_attacks.size(), 1)

	var prehit_opens: Array = _reaction_window_opened_events(instance).filter(func(e): return e.trigger_type == "PreHitAvoidance")
	var onhit_opens: Array = _reaction_window_opened_events(instance).filter(func(e): return e.trigger_type == "OnHitMitigation")
	assert_eq(prehit_opens.size(), 1)
	assert_eq(onhit_opens.size(), 1, "a hit with no prior reaction spend must open exactly one OnHitMitigation window")

	# ── Budget (test_criteria #4) ────────────────────────────────────────────
	# FEAT-003 (G3 remediation): a real, non-Pass OnHitMitigation choice
	# (parry/block) now GENUINELY spends one reaction from Titus's live
	# ActionEconomy via Resolution.apply_on_hit_defense()'s own
	# _try_spend_reaction() gate; declining (onhit_choice == "none") spends
	# none -- PreHitAvoidance was declined in every scenario this helper
	# drives, so this IS the entire Strike's reaction spend.
	var reactions_spent: int = budget_before - titus_action_economy.get_remaining()
	assert_true(reactions_spent <= 1, "at most one reaction may be spent per Strike")
	var expected_reactions_spent: int = 0 if onhit_choice == "none" else 1
	assert_eq(reactions_spent, expected_reactions_spent, "a real Parry/Block choice must spend exactly one reaction; Pass must spend none")

	var attack_event = recorded_attacks[0]
	assert_eq(attack_event.attacker_id, skeleton.combatant_id)
	assert_eq(attack_event.target_id, titus.combatant_id)
	assert_true(attack_event.is_hit)
	# FEAT-003 (G3 remediation): the OnHitMitigation choice is now GENUINELY
	# applied to this Strike's committed damage (never merely traced). Titus's
	# weapon parry_bonus/block_value were pinned to an overwhelming value
	# above, so both "parry" and "block" deterministically reduce the
	# COMMITTED final damage to 0, while "none" (declined) leaves the full,
	# unmitigated damage committed (> 0). NOTE: this structured log event
	# (core/log/attack_event.gd, built by round_session.gd's
	# _record_structured_attack()) mirrors its own "raw_damage" field from the
	# SAME already-final resolve_result -- it was never a second, independent
	# pre-mitigation snapshot (unrelated to this feature; see
	# core/application/tests/test_round_session_reaction_window.gd for a
	# direct application-layer proof that damage_final differs from the TRUE
	# pre-mitigation raw damage), so damage_raw == damage_final always holds
	# here regardless of mitigation and is not itself an interesting
	# assertion -- only damage_final (the genuinely committed amount) is.
	if onhit_choice == "none":
		assert_true(attack_event.damage_final > 0, "declining (Pass) must leave the Strike's full, unmitigated damage committed")
	else:
		assert_eq(attack_event.damage_final, 0, "a chosen Parry/Block, pinned to overwhelmingly succeed, must reduce committed damage to 0 (FR-001 mitigation formula)")

	return {"attack_event": attack_event, "titus": titus, "skeleton": skeleton}


func test_scenario_dodge_declined_hit_then_parry_chosen_at_onhit_window() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var outcome: Dictionary = await _run_dodge_declined_hit_scenario(instance, "parry")
	var attack_event = outcome["attack_event"]

	# FEAT-008 (US-008 / FR-007, Iteration J-R2 Part D): MainScene's
	# composition root now wires RenderCombatLogUseCase into
	# round_session.advance_ai_turn() FOR REAL, so the OnHitMitigation
	# ReactionResolvedEvent for this Strike is ALREADY correlated to the real
	# AttackEvent by production code (a manual record_reaction() call for the
	# SAME attack_event_id + window_id would now be rejected as a duplicate
	# pairing). Assert the ALREADY-paired reaction directly instead -- and,
	# since parry_bonus was pinned to overwhelmingly succeed above, the
	# derived outcome is genuinely "parry_succeeded", not the pre-FEAT-008
	# "no reaction ever recorded" default of "none".
	var paired_onhit = instance.event_log_view.get_paired_reaction(attack_event.id, "OnHitMitigation")
	assert_not_null(
		paired_onhit,
		"production code (RenderCombatLogUseCase, wired via round_session.gd's advance_ai_turn()) must already have paired a ReactionResolvedEvent to this Strike's OnHitMitigation window"
	)
	if paired_onhit != null:
		assert_eq(paired_onhit.choice, "parry")
		assert_eq(paired_onhit.outcome, "parry_succeeded")

	var defense_outcome: String = instance.event_log_view.get_active_defense_outcome_string(attack_event.id)
	assert_eq(defense_outcome, "parry-succeeded")

	var hit_label: String = "Critical Hit" if attack_event.is_crit else "Hit"
	var rendered: String = instance.event_log_view.render_attack_entry(attack_event.id)
	assert_string_contains(rendered, str(attack_event.roll_total))
	assert_string_contains(rendered, hit_label)
	assert_string_contains(rendered, str(attack_event.damage_raw))
	assert_string_contains(rendered, str(attack_event.damage_final))
	assert_string_contains(rendered, "Defense: parry-succeeded")


func test_scenario_dodge_declined_hit_then_block_chosen_at_onhit_window() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var outcome: Dictionary = await _run_dodge_declined_hit_scenario(instance, "block")
	var attack_event = outcome["attack_event"]

	# FEAT-008 (US-008 / FR-007): see the parry scenario's identical doc
	# above -- production already pairs this Strike's OnHitMitigation
	# ReactionResolvedEvent; Block's outcome is always "block_reduced_by_n"
	# once attempted (never succeeded/failed), with reduced_by equal to the
	# actual damage-reduction amount (the TRUE pre-mitigation damage_raw --
	# resolve_to_hit_uc's own `partial.damage_raw` -- minus the committed
	# damage_final; block_value was pinned to overwhelmingly succeed above,
	# so damage_final is 0 and reduced_by equals the full pre-mitigation
	# damage). NOTE: this structured AttackEvent's OWN damage_raw field is
	# NOT that true pre-mitigation value -- core/application/round_session.gd's
	# _record_structured_attack() convention mirrors it from the
	# already-final resolve_result (damage_raw == damage_final always holds
	# on THIS structured record, per _run_dodge_declined_hit_scenario()'s own
	# doc above) -- so reduced_by is asserted here only as a non-negative
	# int, never pinned against attack_event.damage_raw.
	var paired_onhit = instance.event_log_view.get_paired_reaction(attack_event.id, "OnHitMitigation")
	assert_not_null(
		paired_onhit,
		"production code (RenderCombatLogUseCase, wired via round_session.gd's advance_ai_turn()) must already have paired a ReactionResolvedEvent to this Strike's OnHitMitigation window"
	)
	if paired_onhit != null:
		assert_eq(paired_onhit.choice, "block")
		assert_eq(paired_onhit.outcome, "block_reduced_by_n")
		assert_true(int(paired_onhit.reduced_by) >= 0, "reduced_by must be a non-negative int")

	var defense_outcome: String = instance.event_log_view.get_active_defense_outcome_string(attack_event.id)
	assert_true(defense_outcome.begins_with("block reduced-by-"), "defense_outcome must render Block's 'block reduced-by-N' shape (got '%s')" % defense_outcome)

	var hit_label: String = "Critical Hit" if attack_event.is_crit else "Hit"
	var rendered: String = instance.event_log_view.render_attack_entry(attack_event.id)
	assert_string_contains(rendered, str(attack_event.roll_total))
	assert_string_contains(rendered, hit_label)
	assert_string_contains(rendered, str(attack_event.damage_raw))
	assert_string_contains(rendered, str(attack_event.damage_final))
	assert_string_contains(rendered, "Defense: block reduced-by-")


func test_scenario_dodge_declined_hit_then_no_reaction_chosen_at_onhit_window() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var outcome: Dictionary = await _run_dodge_declined_hit_scenario(instance, "none")
	var attack_event = outcome["attack_event"]

	# FEAT-008 (US-008 / FR-007): see the parry scenario's identical doc
	# above -- production already pairs this Strike's OnHitMitigation
	# ReactionResolvedEvent, recorded with choice/outcome "none" since
	# OnHitMitigation was declined (Pass).
	var paired_onhit = instance.event_log_view.get_paired_reaction(attack_event.id, "OnHitMitigation")
	assert_not_null(
		paired_onhit,
		"production code (RenderCombatLogUseCase, wired via round_session.gd's advance_ai_turn()) must already have paired a ReactionResolvedEvent to this Strike's OnHitMitigation window"
	)
	if paired_onhit != null:
		assert_eq(paired_onhit.choice, "none")
		assert_eq(paired_onhit.outcome, "none")

	var defense_outcome: String = instance.event_log_view.get_active_defense_outcome_string(attack_event.id)
	assert_eq(defense_outcome, "none")

	var hit_label: String = "Critical Hit" if attack_event.is_crit else "Hit"
	var rendered: String = instance.event_log_view.render_attack_entry(attack_event.id)
	assert_string_contains(rendered, str(attack_event.roll_total))
	assert_string_contains(rendered, hit_label)
	assert_string_contains(rendered, str(attack_event.damage_raw))
	assert_string_contains(rendered, str(attack_event.damage_final))
	assert_string_contains(rendered, "Defense: none")
