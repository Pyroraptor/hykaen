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


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _titus(instance) -> Dictionary:
	return instance._party[0]


func _titus_id(instance) -> String:
	var titus: Dictionary = _titus(instance)
	return titus.get("combatant_id", titus.get("name", ""))


func _press_end_turn_and_drive_enemy_strike(instance) -> void:
	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)
	instance.verb_bar_view.press(END_TURN)


func _has_combatant_defeated_event(instance) -> bool:
	for event in instance.event_sink.log:
		if event is RoundEventsClass.CombatantDefeatedEvent:
			return true
	return false


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — hit + Parry: Titus's HP panel reflects ZERO damage taken.
# ══════════════════════════════════════════════════════════════════════════

func test_hit_then_parry_leaves_titus_hp_panel_unchanged() -> void:
	var instance = _boot_main_scene()
	var titus: Dictionary = _titus(instance)
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

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(attack_events.size(), 1, "exactly one Strike must have resolved")
	assert_true(attack_events[0].hit, "fixture assumption: the guaranteed-hit AC must actually produce a hit")
	assert_eq(attack_events[0].damage_final, 0, "the committed AttackEvent itself must carry the mitigated (zero) final damage")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — hit + Block: Titus's HP panel reflects damage per the
# mitigation formula (pinned here to full suppression, ZERO damage taken).
# ══════════════════════════════════════════════════════════════════════════

func test_hit_then_block_leaves_titus_hp_panel_reflecting_the_mitigation_formula() -> void:
	var instance = _boot_main_scene()
	var titus: Dictionary = _titus(instance)
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

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(attack_events.size(), 1)
	assert_true(attack_events[0].hit)
	assert_eq(attack_events[0].damage_final, 0, "block_value pinned to an overwhelming value must reduce committed damage per FR-001's formula: max(0, raw - reduction) = 0")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — hit + Pass: Titus's HP panel takes the FULL, unmitigated hit.
# ══════════════════════════════════════════════════════════════════════════

func test_hit_then_pass_leaves_titus_hp_panel_showing_full_unmitigated_damage() -> void:
	var instance = _boot_main_scene()
	var titus: Dictionary = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT

	var titus_id: String = _titus_id(instance)
	var hp_before: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)

	_press_end_turn_and_drive_enemy_strike(instance)

	instance.reaction_prompt_ui.press_option("none")

	assert_true(instance.reaction_prompt_ui.is_open(), "the OnHitMitigation pop-up must open once the Strike is confirmed to hit")
	instance.reaction_prompt_ui.press_option("none")

	assert_false(instance.reaction_prompt_ui.is_open())

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(attack_events.size(), 1)
	assert_true(attack_events[0].hit)
	assert_true(attack_events[0].damage_final > 0, "declining (Pass) must leave the Strike's real, unmitigated damage in place")

	var hp_after: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_eq(hp_before - hp_after, attack_events[0].damage_final, "Titus's HP panel must show damage taken EXACTLY matching the unmitigated (raw) committed damage -- Pass reproduces the unmitigated outcome byte-for-byte")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — lethal-but-parried: a hit that WOULD be lethal if unmitigated
# must never defeat Titus once genuinely Parried -- no CombatantDefeatedEvent,
# no loss state shown.
# ══════════════════════════════════════════════════════════════════════════

func test_lethal_but_parried_hit_never_defeats_titus_or_shows_a_loss_state() -> void:
	var instance = _boot_main_scene()
	var titus: Dictionary = _titus(instance)
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

	assert_eq(titus.get("hp_current", 0), 1, "a lethal-but-PARRIED hit must never reduce Titus's real hp_current")
	assert_false(_has_combatant_defeated_event(instance), "no CombatantDefeatedEvent may ever be emitted for a lethal-but-parried hit")
	assert_false(instance.result_screen_view.is_shown(), "no loss/result state may be shown once the lethal hit was genuinely negated by Parry")

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(attack_events.size(), 1)
	assert_true(attack_events[0].hit, "fixture assumption: the guaranteed-hit AC must actually produce a hit")
	assert_eq(attack_events[0].damage_final, 0, "the successful Parry must reduce the committed damage to 0, saving Titus from an otherwise-lethal hit")
