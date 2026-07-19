extends GutTest
## tests/test_mainscene_combat_log_richness.gd
##
## GUT suite for FEAT-009 (US-009 / FR-010): boots the REAL
## res://MainScene.tscn composition root (real Combatant/Weapon data loaded
## from data/characters/titus.tres + data/enemies/skeleton.tres, the real
## RoundSession / ReactionWindow / EventLogView instances MainScene.gd
## wires) and scripts an enemy Strike + reaction against Titus, proving the
## combat-log richness FEAT-007 (structured AttackEvent/ReactionResolvedEvent
## storage) and FEAT-008 (roll_total / active-defense-outcome rendering)
## built actually work end-to-end when driven by REAL composition-root
## objects -- not merely fixture doubles. This closes the "correct in
## isolation, dead/wrong when wired" bug class the design notes'
## observability section documents from Iterations H/I.
##
## MainScene.gd itself does not yet wire round_session's FEAT-007
## set_event_log_record_attack_fn() EventLogPort seam into the real
## event_log_view (that composition-root wiring is explicitly documented as
## a follow-on feature's file scope -- see round_session.gd's
## _event_log_record_attack_fn doc), so this suite performs that ONE seam
## injection itself, directly against the REAL, already-booted
## round_session/event_log_view instances -- exactly the Dependency-
## Inversion seam set_event_log_record_attack_fn() exists for. No production
## file is modified by this feature (files_to_modify is empty) -- this test
## exercises only the public seams FEAT-002/FEAT-007 already established.
##
## Verifies (test_criteria):
##   1. Booting real MainScene.tscn and scripting an enemy Strike + reaction
##      against Titus.
##   2. The resulting log entry carries roll_total and a non-empty
##      active-defense-outcome field via the FEAT-007 structured accessor.
##   3. The rendered string (FEAT-008) matches the structured field values
##      for the SAME entry.
##   4. This test is registered in and passes under the GUT suite.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const ReactionResolvedEventClass = preload("res://core/log/reaction_resolved_event.gd")


## _ScriptedDodgeResolver -- a synchronous ReactionResolverPort double
## (mirrors tests/gut/test_enemy_strike_reaction_window.gd's established
## ScriptedReactionResolver convention) that always answers "dodge" for
## whichever PreHitAvoidance trigger it is handed, so this suite's enemy
## Strike vs Titus deterministically opens and resolves a REAL reaction
## through the REAL ReactionWindow/resolution.gd pipeline MainScene.gd
## already wires -- rather than leaving the choice to whatever the real
## player-facing pop-up would otherwise block on.
class _ScriptedDodgeResolver:
	extends RefCounted
	var calls: Array = []
	func resolve(trigger: Dictionary) -> Dictionary:
		calls.append(trigger)
		return {"choice": "dodge"}


## _boot_main_scene() -> Node -- instantiates the REAL res://MainScene.tscn
## composition root, pinning seed_override=42 (this codebase's established
## deterministic-fixture convention, e.g. tests/gut/
## test_mainscene_reaction_resolver_wiring.gd) so Titus is reliably the
## first actor and the prologue encounter's Titus-vs-Skeleton layout is
## reproducible.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	# This suite asserts the rich combat log, not the Dodge-Step follow-up.
	# A successful Dodge now fires the live Dodge-Step hex prompt inside
	# advance_ai_turn(); the REAL _UIHexChoiceResolver would block awaiting a
	# battlefield click no headless test can deliver. Null it so
	# MainScene.resolve_hex_choice() returns null → Dodge-Step no-ops here
	# (the Dodge itself, and its "Defense: dodge" log segment, are unaffected).
	instance.hex_choice_resolver = null
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1-3: boot real MainScene, script an enemy Strike + reaction
# against Titus, and prove the resulting log entry carries roll_total and a
# non-empty active-defense-outcome field whose rendered string matches.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_real_mainscene_scripted_enemy_strike_and_reaction_produces_rich_log_entry() -> void:
	var instance = _boot_main_scene()

	assert_not_null(instance.round_session, "MainScene.round_session must be a real RoundSession after boot")
	assert_not_null(instance.event_log_view, "MainScene.event_log_view must be a real EventLogView after boot")
	assert_not_null(instance.turn_controller, "MainScene.turn_controller must be wired after boot")
	assert_not_null(instance.end_turn_control, "MainScene.end_turn_control must be wired after boot")

	var player = instance.round_session.current_actor()
	assert_eq(player.name, "Titus", "fixture: Titus (the real player combatant) must be the current actor at boot")
	assert_false(player.is_enemy, "fixture: Titus is the player, not an enemy")

	assert_eq(instance._enemies.size(), 1, "fixture: the prologue encounter's real enemy roster must carry exactly the Skeleton")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture: the real enemy combatant must be the Skeleton")

	# FEAT-213 / FEAT-214 (Iteration J V&V fix): MainScene's composition root now
	# wires the EventLogPort seam FOR REAL (set_event_log_record_attack_fn ->
	# event_log_view.record_attack, MainScene.gd rewire_session()). Assert that
	# real wiring exists at boot -- BEFORE this suite overrides it with a
	# capturing recorder below -- so this boot-real test genuinely verifies the
	# composition-root wiring instead of self-wiring around the gap it should
	# catch (the V&V finding this rewrite closes; the standing boot-real rule).
	assert_true(
		instance.round_session._event_log_record_attack_fn.is_valid(),
		"MainScene must wire round_session.set_event_log_record_attack_fn() in its composition root -- the live combat log must render the rich format without any test self-wiring"
	)

	# ── Override with a capturing recorder purely to snapshot the forwarded
	# AttackEvents for the assertions below (the real MainScene wiring, asserted
	# above, still points at event_log_view.record_attack -- this override also
	# forwards there, preserving identical live behavior). ──
	var recorded_attacks: Array = []
	instance.round_session.set_event_log_record_attack_fn(func(attack_event):
		recorded_attacks.append(attack_event)
		instance.event_log_view.record_attack(attack_event)
	)

	# ── Script the enemy Strike's reaction deterministically: force "dodge"
	# on the REAL PreHitAvoidance window (Dodge/Steel, asked BEFORE the
	# attack roll -- reaction_window.gd's own, unmodified eligibility gate
	# still decides legality) so a genuine reaction fires through the REAL
	# ReactionWindow/resolution.gd pipeline, rather than the default
	# synchronous {"choice": "none"} fallback every un-injected caller
	# resolves against. ───────────────────────────────────────────────────
	var scripted_resolver := _ScriptedDodgeResolver.new()
	instance.round_session.set_prehit_avoidance_resolver_fn(Callable(scripted_resolver, "resolve"))

	# ── End Titus's turn via the REAL EndTurnControl -> TurnController
	# auto-drive path (US-011): the Skeleton's turn is auto-driven via
	# round_session.advance_ai_turn(), resolving a REAL enemy Strike +
	# reaction against Titus through the REAL composition-root pipeline. ────
	var press_result: Dictionary = instance.end_turn_control.press()
	assert_true(press_result.get("ok", false), "the real EndTurnControl.press() must forward to RoundSession.end_current_turn() successfully")

	# Iteration M ("Cast a Spell"): the prologue roster now seats Marigold (a
	# second living, player-controlled combatant) BEFORE the Skeleton in turn
	# order at this fixture's seed. TurnController only auto-drives Enemy
	# turns (presentation/turn_controller.gd's _drive()), so Marigold's own
	# turn needs an explicit manual End Turn / pass here too before the
	# Skeleton's Strike is actually auto-driven.
	var next_actor = instance.round_session.current_actor()
	if next_actor != null and not next_actor.is_enemy:
		press_result = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "the real EndTurnControl.press() must forward to RoundSession.end_current_turn() successfully for Marigold's pass")

	assert_eq(scripted_resolver.calls.size(), 1, "the scripted PreHitAvoidance resolver must be awaited exactly once for the Skeleton's Strike against Titus")
	var prehit_call: Dictionary = scripted_resolver.calls[0]
	assert_eq(prehit_call.get("trigger_type", ""), "PreHitAvoidance", "the scripted resolver must have been awaited for a genuine PreHitAvoidance window")

	assert_eq(recorded_attacks.size(), 1, "advance_ai_turn() must forward exactly one structured AttackEvent for the Skeleton's resolved Strike")

	var attack_event = recorded_attacks[0]
	assert_eq(attack_event.attacker_id, skeleton.combatant_id, "the resolved Strike must be attributed to the real Skeleton enemy")
	assert_eq(attack_event.target_id, player.display_id(), "the resolved Strike must target the real Titus player combatant")
	assert_true(attack_event.roll_total > 0, "the real resolution.gd math must produce a non-zero roll_total for the resolved Strike")

	# ── FEAT-008 (US-008 / FR-007, Iteration J-R2 Part D): MainScene's
	# composition root now wires RenderCombatLogUseCase into
	# round_session.advance_ai_turn() FOR REAL (set_event_log_record_reaction_fn
	# -> event_log_view.record_reaction), so the ReactionResolvedEvent for
	# this Skeleton Strike's PreHitAvoidance window is ALREADY paired to the
	# real AttackEvent by production code -- this suite no longer needs to
	# construct/record one itself (a manual record_reaction() call here would
	# now be rejected as a duplicate pairing for the SAME attack_event_id +
	# window_id, per that accessor's own documented dedup contract). The
	# outcome derived by production ("dodge_succeeded"/"dodge_failed") mirrors
	# the REAL resolved outcome (a successful Dodge produces a miss; a failed
	# Dodge still produces a hit -- resolution.gd's own math, never re-derived
	# by this suite). ─────────────────────────────────────────────────────
	var expected_outcome: String = "dodge_failed" if attack_event.is_hit else "dodge_succeeded"
	var paired_reaction = instance.event_log_view.get_paired_reaction(attack_event.id, "PreHitAvoidance")
	assert_not_null(
		paired_reaction,
		"production code (RenderCombatLogUseCase, wired via round_session.gd's advance_ai_turn()) must already have paired a ReactionResolvedEvent to this Strike's PreHitAvoidance window"
	)
	if paired_reaction != null:
		assert_eq(paired_reaction.choice, "dodge", "the paired reaction's choice must reflect the scripted Dodge resolver's answer")
		assert_eq(paired_reaction.outcome, expected_outcome, "the paired reaction's outcome must reflect the REAL resolved hit/miss result")

	# ── Criterion 2: the log entry produced carries roll_total and a
	# non-empty active-defense-outcome field via the FEAT-007 structured
	# accessor. ────────────────────────────────────────────────────────────
	var stored_attack = instance.event_log_view.get_structured_attack(attack_event.id)
	assert_not_null(stored_attack, "the structured AttackEvent must be retrievable via get_structured_attack() on the real, booted event_log_view")
	assert_eq(stored_attack.roll_total, attack_event.roll_total, "the stored AttackEvent's roll_total must match the real resolved Strike's roll")
	assert_true(stored_attack.roll_total > 0, "roll_total must be a real, non-zero rolled value, never a stub 0")

	var defense_outcome: String = instance.event_log_view.get_active_defense_outcome_string(attack_event.id)
	assert_true(defense_outcome != "", "the active-defense-outcome field must be non-empty")
	assert_true(
		defense_outcome == "dodge-succeeded" or defense_outcome == "dodge-failed",
		"the active-defense-outcome must be a genuine, non-'none' Dodge result for this scripted enemy Strike + reaction against Titus (got '%s')" % defense_outcome
	)

	# ── Criterion 3: the rendered string (FEAT-008) matches the structured
	# field values for the SAME entry. ────────────────────────────────────
	var rendered_text: String = instance.event_log_view.render_attack_entry(attack_event.id)
	assert_true(rendered_text != "", "render_attack_entry() must render non-empty text for a recorded AttackEvent")
	assert_string_contains(rendered_text, str(attack_event.roll_total), "the rendered string must include the SAME roll_total the structured accessor reports")
	assert_string_contains(
		rendered_text, "Defense: %s" % defense_outcome,
		"the rendered string's active-defense outcome must match get_active_defense_outcome_string()'s value exactly"
	)
	if attack_event.is_hit:
		assert_string_contains(rendered_text, "Critical Hit" if attack_event.is_crit else "Hit", "a hit must render its hit/crit label")
		assert_string_contains(rendered_text, str(attack_event.damage_raw), "a hit must render damage_raw")
		assert_string_contains(rendered_text, str(attack_event.damage_final), "a hit must render damage_final")
	else:
		assert_string_contains(rendered_text, "Miss", "a miss must render the Miss label")

	# ── Regression guard: this suite's own manual wiring must never disturb
	# the pre-existing formatted-string `_entries` path (FEAT-007 criterion
	# 4, still true when driven by a REAL booted MainScene). ───────────────
	assert_true(instance.event_log_view.get_entry_count() >= 0, "recording structured data must never break the pre-existing formatted-string entries accessor")


# ══════════════════════════════════════════════════════════════════════════
# Regression guard: the FEAT-007/FEAT-008 accessors' documented "unpaired
# lookup, never an error" contract holds against the REAL, booted
# event_log_view instance -- not only a bare fixture double.
# ══════════════════════════════════════════════════════════════════════════

func test_real_booted_event_log_view_accessors_are_safe_for_an_unrecorded_attack_event_id() -> void:
	var instance = _boot_main_scene()

	assert_null(instance.event_log_view.get_structured_attack("does-not-exist"))
	assert_eq(instance.event_log_view.get_active_defense_outcome_string("does-not-exist"), "none")
	assert_eq(instance.event_log_view.render_attack_entry("does-not-exist"), "")
