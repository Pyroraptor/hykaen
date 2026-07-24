extends GutTest
## tests/integration/test_mainscene_hit_reaction_apply.gd
##
## GUT suite for FEAT-003 (US-002 / FR-002, G3 remediation): the
## "boot-real-MainScene" observable-acceptance suite proving round_session.gd's
## genuine two-phase on-hit commit (resolve_to_hit_uc -> await OnHitMitigation
## -> apply_on_hit_defense_uc) actually changes what a real player SEES,
## driven entirely through the REAL composition root (res://MainScene.tscn) --
## no self-wired seam/double stands in for round_session, resolve_action_use_case,
## the reaction window, or the status panel under test (G2 discipline).
##
## Mirrors tests/test_mainscene_reaction_timing.gd's established conventions
## exactly: boots the REAL scene at the prologue fixture seed (Titus acts
## first, the sole enemy -- Skeleton -- starts adjacent), presses the real
## END_TURN verb to auto-drive the Skeleton's Strike against Titus, and drives
## the REAL scenes/ui/reaction_prompt_ui.gd pop-up via press_option() exactly
## as a human's click would. Hit/miss determinism is achieved WITHOUT touching
## RNG/seed math by mutating Titus's live "ac" field directly (the same
## established technique); on-hit mitigation determinism is achieved the same
## way, by mutating Titus's live weapon's parry_bonus/block_value directly to
## an overwhelming value BEFORE the Strike ever resolves -- never a scripted/
## substitute RNG port.
##
## Verifies (test_criteria):
##   1. Boot real MainScene; script hit+Parry; assert Titus's HP panel
##      (StatusPanelView, the observable a real player sees) reflects FR-001's
##      mitigation formula -- ZERO damage taken.
##   2. Boot real MainScene; script hit+Block; assert damage taken matches
##      FR-001's formula -- ZERO damage taken (Titus's block_value is pinned
##      to an overwhelming value, guaranteeing full suppression regardless of
##      the real dice drawn for the block-reduction roll).
##   3. Boot real MainScene; script hit+Pass; assert damage taken is
##      UNCHANGED from the raw/unmitigated Strike (full damage lands).
##   4. Boot real MainScene; script a lethal-but-parried hit (Titus at 1 HP,
##      guaranteed-lethal-if-unmitigated raw damage, guaranteed-successful
##      Parry); assert no CombatantDefeatedEvent is ever emitted and no loss
##      state is shown (ResultScreenView.is_shown() stays false, Titus's own
##      HP panel never reaches 0).
##
## FEAT-219 (PR-002 remediation): DEF-001 ("on-hit mitigation cosmetic-only")
## could not be confirmed genuinely fixed by an automated, code-verifiable
## check alone, because RoundEvents.AttackBroadcast (the value object the
## assertions above read) only ever carries the FINAL, post-mitigation
## damage -- there was no live, observable field for the RAW (pre-mitigation)
## damage a successful Parry/Block was supposed to have reduced. This suite
## now additionally reads core/log/attack_event.gd's structured AttackEvent
## (retrieved from the REAL, live event_log_view via
## _latest_structured_attack_event() below -- record_attack()'s storage
## channel, never a re-derived/recomputed value) to assert the RELATIONSHIP
## between raw_damage and final_damage directly on the live combatant state,
## closing the code-verifiable portion of this finding:
##   5. Scripted successful Parry: final_damage < raw_damage by the
##      documented mitigation amount (Resolution.apply_on_hit_defense()'s
##      Parry formula: a success negates ALL raw damage -- final_damage ==
##      0, raw_damage > 0).
##   6. Scripted successful Block: final_damage < raw_damage by the
##      documented mitigation amount (Resolution.apply_on_hit_defense()'s
##      Block formula: max(0, raw_damage - block_reduction); pinned here, via
##      OVERWHELMING_MITIGATION_STAT, to full suppression -- final_damage ==
##      0, raw_damage > 0).
##   7. Scripted Pass/no-reaction: final_damage == raw_damage (no unintended
##      mitigation).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass = preload("res://core/rules/round_events.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed: Titus
## acts first and the sole enemy (Skeleton) starts adjacent to him (see
## tests/test_mainscene_reaction_timing.gd's identical fixture doc).
const PROLOGUE_SEED: int = 42

const END_TURN: String = "END_TURN"

## AC_GUARANTEED_HIT — see tests/test_mainscene_reaction_timing.gd's identical
## "mutate the live combatant Dictionary a production call path already
## reads" doc -- an absurdly low AC guarantees a hit with no RNG/seed edits.
const AC_GUARANTEED_HIT: int = -100

## OVERWHELMING_MITIGATION_STAT — pinned onto Titus's own weapon's
## parry_bonus/block_value fields (data/weapons/longsword.tres normally
## carries small positive values for both) so a chosen Parry's
## (d20 + parry_bonus) roll always strictly exceeds any possible attacker
## roll_total, and a chosen Block's (die_roll + block_value) reduction always
## meets or exceeds any possible raw damage -- deterministic full suppression
## without touching RNG/seed math (mirrors the AC trick above).
const OVERWHELMING_MITIGATION_STAT: int = 9999


## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): round_session/
## the Layer 1 verb bar/Layer 2 selection overlay/turn_controller signal
## wiring are no longer live unconditionally at boot -- they now stay
## dormant until a real combat trigger fires (see MainScene.gd's own
## FEAT-316 doc). This suite drives Strike/reaction-window verbs directly
## against the real composition root, so _boot_main_scene() now also drives
## the SAME real handoff tests/boot/test_exploration_to_combat_handoff_trigger.gd
## exercises directly (mirrors tests/boot/test_first_cast_firebolt.gd's
## established convention), landing the instance in GameMode.COMBAT with a
## live round_session before returning.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


func _titus(instance):
	return instance._party[0]


func _titus_id(instance) -> String:
	var titus = _titus(instance)
	return titus.combatant_id


func _press_end_turn_and_drive_enemy_strike(instance) -> void:
	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)
	instance.verb_bar_view.press(END_TURN)
	# Marigold (the second, player-controlled party member added alongside
	# Titus) now holds the cursor -- RoundSession/TurnController only
	# auto-drives AI (enemy) turns, never a second living player combatant --
	# so an explicit manual End Turn is required here too before the
	# Skeleton's turn (and its Strike) is ever reached.
	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Marigold (the second party member) acts second, before the enemy, at seed=%d" % PROLOGUE_SEED
	)
	instance.verb_bar_view.press(END_TURN)


func _has_combatant_defeated_event(instance) -> bool:
	for event in instance.event_sink.log:
		if event is RoundEventsClass.CombatantDefeatedEvent:
			return true
	return false


## _latest_structured_attack_event(instance) -> AttackEvent or null
##
## FEAT-219 (PR-002 remediation): the accessor this suite adds to reach the
## structured, storage-shaped core/log/attack_event.gd AttackEvent (which
## carries BOTH damage_raw and damage_final -- unlike
## core/rules/round_events.gd's RoundEvents.AttackBroadcast above, which only
## ever carries damage_final) for the JUST-resolved Strike's row, driven
## entirely through the REAL, live-booted event_log_view (never a
## re-derived/recomputed value) -- exactly the same accessor
## tests/gut/test_rich_log_enemy_attack.gd already established
## (get_entry()'s attack_event_id -> get_structured_attack()). Returns null
## if no row has been appended yet.
func _latest_structured_attack_event(instance):
	var count: int = instance.event_log_view.get_entry_count()
	assert_true(count > 0, "at least one row must exist in the real event_log_view after a resolved Strike")
	if count == 0:
		return null
	var attack_event_id = instance.event_log_view.get_entry(count - 1).get("attack_event_id", "")
	assert_true(str(attack_event_id) != "", "the latest row must carry a non-empty attack_event_id")
	var structured = instance.event_log_view.get_structured_attack(attack_event_id)
	assert_not_null(structured, "the structured AttackEvent recorded via record_attack() must be retrievable for the just-resolved Strike")
	return structured


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — hit + Parry: Titus's HP panel reflects ZERO damage taken.
# ══════════════════════════════════════════════════════════════════════════

func test_hit_then_parry_leaves_titus_hp_panel_unchanged() -> void:
	var instance = await _boot_main_scene()
	var titus = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT
	titus["weapon"]["parry_bonus"] = OVERWHELMING_MITIGATION_STAT

	var titus_id: String = _titus_id(instance)
	var hp_before: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_true(hp_before > 0, "fixture assumption: Titus starts with positive HP")

	_press_end_turn_and_drive_enemy_strike(instance)

	assert_true(instance.reaction_prompt_ui.is_open(), "the PreHitAvoidance pop-up must open for the incoming Strike")
	instance.reaction_prompt_ui.press_option("none")

	assert_true(instance.reaction_prompt_ui.is_open(), "the OnHitMitigation pop-up must open once the Strike is confirmed to hit")
	assert_true(instance.reaction_prompt_ui.get_displayed_options().has("parry"), "Parry must be offered for Titus's real longsword")
	instance.reaction_prompt_ui.press_option("parry")

	assert_false(instance.reaction_prompt_ui.is_open(), "no further reaction window may remain open once this Strike's OnHitMitigation choice has resolved")

	var hp_after: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_eq(hp_after, hp_before, "Titus's own HP panel must show ZERO damage taken once a successful Parry is GENUINELY applied (FR-001 mitigation formula)")

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one Strike must have resolved")
	assert_true(attack_events[0].hit, "fixture assumption: the guaranteed-hit AC must actually produce a hit")
	assert_eq(attack_events[0].damage_final, 0, "the committed AttackEvent itself must carry the mitigated (zero) final damage")

	# FEAT-219 (PR-002 remediation, criterion 5): assert the RELATIONSHIP
	# between raw and final damage directly on the live combatant state --
	# not merely that final_damage happens to be zero (which, in isolation,
	# is indistinguishable from a bug that always reports zero damage) but
	# that it is STRICTLY LESS than the real raw_damage the to-hit phase
	# actually rolled, matching Resolution.apply_on_hit_defense()'s
	# documented Parry formula (a success negates ALL raw damage).
	var structured_attack_event = _latest_structured_attack_event(instance)
	if structured_attack_event != null:
		assert_true(structured_attack_event.damage_raw > 0, "fixture assumption: a guaranteed hit must roll positive raw damage")
		assert_true(
			structured_attack_event.damage_final < structured_attack_event.damage_raw,
			"a successful Parry must genuinely reduce final_damage below raw_damage -- not merely report a coincidental zero"
		)
		assert_eq(structured_attack_event.damage_final, 0, "Parry's documented mitigation amount is full negation: final_damage == 0")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — hit + Block: Titus's HP panel reflects damage per the
# mitigation formula (pinned here to full suppression, ZERO damage taken).
# ══════════════════════════════════════════════════════════════════════════

func test_hit_then_block_leaves_titus_hp_panel_reflecting_the_mitigation_formula() -> void:
	var instance = await _boot_main_scene()
	var titus = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT
	titus["weapon"]["block_value"] = OVERWHELMING_MITIGATION_STAT

	var titus_id: String = _titus_id(instance)
	var hp_before: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)

	_press_end_turn_and_drive_enemy_strike(instance)

	instance.reaction_prompt_ui.press_option("none")

	assert_true(instance.reaction_prompt_ui.is_open(), "the OnHitMitigation pop-up must open once the Strike is confirmed to hit")
	assert_true(instance.reaction_prompt_ui.get_displayed_options().has("block"), "Block must be offered for Titus's real longsword")
	instance.reaction_prompt_ui.press_option("block")

	assert_false(instance.reaction_prompt_ui.is_open())

	var hp_after: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_eq(hp_after, hp_before, "Titus's own HP panel must show the mitigated (here: zero) damage taken once a genuinely-applied Block reduces the committed damage per FR-001's formula")

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1)
	assert_true(attack_events[0].hit)
	assert_eq(attack_events[0].damage_final, 0, "block_value pinned to an overwhelming value must reduce committed damage per FR-001's formula: max(0, raw - reduction) = 0")

	# FEAT-219 (PR-002 remediation, criterion 6): as with Parry above, assert
	# the RELATIONSHIP between raw and final damage on the live combatant
	# state -- final_damage must be strictly less than the real raw_damage
	# rolled, matching Resolution.apply_on_hit_defense()'s documented Block
	# formula: max(0, raw_damage - block_reduction).
	var structured_attack_event = _latest_structured_attack_event(instance)
	if structured_attack_event != null:
		assert_true(structured_attack_event.damage_raw > 0, "fixture assumption: a guaranteed hit must roll positive raw damage")
		assert_true(
			structured_attack_event.damage_final < structured_attack_event.damage_raw,
			"a successful Block must genuinely reduce final_damage below raw_damage -- not merely report a coincidental zero"
		)
		assert_eq(structured_attack_event.damage_final, 0, "block_value pinned to an overwhelming value must reduce final_damage to 0 per max(0, raw - reduction)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — hit + Pass: Titus's HP panel takes the FULL, unmitigated hit.
# ══════════════════════════════════════════════════════════════════════════

func test_hit_then_pass_leaves_titus_hp_panel_showing_full_unmitigated_damage() -> void:
	var instance = await _boot_main_scene()
	var titus = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT

	var titus_id: String = _titus_id(instance)
	var hp_before: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)

	_press_end_turn_and_drive_enemy_strike(instance)

	instance.reaction_prompt_ui.press_option("none")

	assert_true(instance.reaction_prompt_ui.is_open(), "the OnHitMitigation pop-up must open once the Strike is confirmed to hit")
	instance.reaction_prompt_ui.press_option("none")

	assert_false(instance.reaction_prompt_ui.is_open())

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1)
	assert_true(attack_events[0].hit)
	assert_true(attack_events[0].damage_final > 0, "declining (Pass) must leave the Strike's real, unmitigated damage in place")

	var hp_after: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_eq(hp_before - hp_after, attack_events[0].damage_final, "Titus's HP panel must show damage taken EXACTLY matching the unmitigated (raw) committed damage -- Pass reproduces the unmitigated outcome byte-for-byte")

	# FEAT-219 (PR-002 remediation, criterion 7): declining every reaction
	# (Pass) must leave final_damage EQUAL to raw_damage -- no unintended
	# mitigation is ever silently applied when the player chose none.
	var structured_attack_event = _latest_structured_attack_event(instance)
	if structured_attack_event != null:
		assert_true(structured_attack_event.damage_raw > 0, "fixture assumption: a guaranteed hit must roll positive raw damage")
		assert_eq(
			structured_attack_event.damage_final, structured_attack_event.damage_raw,
			"Pass/no-reaction must leave final_damage EQUAL to raw_damage -- no unintended mitigation"
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — lethal-but-parried: a hit that WOULD be lethal if unmitigated
# must never defeat Titus once genuinely Parried -- no CombatantDefeatedEvent,
# no loss state shown.
# ══════════════════════════════════════════════════════════════════════════

func test_lethal_but_parried_hit_never_defeats_titus_or_shows_a_loss_state() -> void:
	var instance = await _boot_main_scene()
	var titus = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT
	titus["weapon"]["parry_bonus"] = OVERWHELMING_MITIGATION_STAT
	# Any unmitigated hit is lethal at 1 HP -- the die alone (>=1) already
	# guarantees this without needing to touch the Skeleton's own stats.
	titus["hp_current"] = 1

	_press_end_turn_and_drive_enemy_strike(instance)

	instance.reaction_prompt_ui.press_option("none")
	assert_true(instance.reaction_prompt_ui.is_open(), "the OnHitMitigation pop-up must open once the Strike is confirmed to hit")
	instance.reaction_prompt_ui.press_option("parry")
	assert_false(instance.reaction_prompt_ui.is_open())

	assert_eq(titus.hp_current, 1, "a lethal-but-PARRIED hit must never reduce Titus's real hp_current")
	assert_false(_has_combatant_defeated_event(instance), "no CombatantDefeatedEvent may ever be emitted for a lethal-but-parried hit")
	assert_false(instance.result_screen_view.is_shown(), "no loss/result state may be shown once the lethal hit was genuinely negated by Parry")

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1)
	assert_true(attack_events[0].hit, "fixture assumption: the guaranteed-hit AC must actually produce a hit")
	assert_eq(attack_events[0].damage_final, 0, "the successful Parry must reduce the committed damage to 0, saving Titus from an otherwise-lethal hit")
