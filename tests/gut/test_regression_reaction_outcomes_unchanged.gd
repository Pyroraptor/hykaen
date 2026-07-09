extends GutTest
## tests/gut/test_regression_reaction_outcomes_unchanged.gd — FEAT-009
## (US-010, NFR-008: "Parry/Block/Pass mitigation outcomes are unchanged by
## the Dodge-Step/log wiring").
##
## This iteration (FEAT-001..FEAT-008) wired the Dodge-Step prompt/reposition
## seam and the rich combat-log rendering into LIVE play through
## core/application/round_session.gd and MainScene.gd. Neither of those
## features' files_to_create/files_to_modify ever touched
## core/rules/resolution.gd or core/application/apply_on_hit_defense_uc.gd —
## the two places OnHitMitigation math (Parry/Block/Pass) and the hp_current
## commit actually live (see resolution.gd's own `Resolution.
## apply_on_hit_defense()` and apply_on_hit_defense_uc.gd's `apply()`,
## "the ONLY hp_current mutation in this entire two-phase split"). This suite
## is the automated regression proof of that claim: it boots the REAL
## res://MainScene.tscn composition root (G2 — never a hand-wired double,
## mirroring tests/integration/test_mainscene_hit_reaction_apply.gd's
## established convention exactly) and pins the EXACT numeric hp/damage
## outcome of each of the three OnHitMitigation choices (Parry, Block, Pass)
## for the prologue fixture (seed=42, Titus vs the Skeleton) — not merely
## "damage went to zero" (which a coincidental compensating bug could still
## satisfy) but the literal roll/damage_final/hp_before/hp_after values
## captured directly from this exact commit, BEFORE any Dodge-Step/log wiring
## could plausibly perturb them.
##
## Two complementary scenario families are pinned:
##   A. REAL, unmodified longsword stats (parry_bonus=2, block_value=1, per
##      data/weapons/longsword.tres) against the Skeleton's real attack roll
##      — genuine dice-driven partial mitigation, never an artificially
##      forced full negation. This is the strongest regression oracle: any
##      drift in resolve_to_hit()/apply_on_hit_defense()'s formulas (attack
##      roll math, crit threshold, block-reduction formula, parry-success
##      comparison) changes one of these pinned numbers.
##   B. The OVERWHELMING_MITIGATION_STAT convention already established by
##      tests/integration/test_mainscene_hit_reaction_apply.gd (guaranteed
##      full suppression for Parry/Block), re-pinned here with the ABSOLUTE
##      hp values (not just "before == after") so a regression that
##      coincidentally preserves the before/after EQUALITY while drifting
##      the absolute starting HP (e.g. a max_hp/class_hp constant edit) would
##      still be caught.
##
## Fixture derivation note: every literal value below (roll=21, crit=true,
## damage_final=12/10/0, hp deltas) was captured by directly instrumenting
## this exact boot sequence at this commit and is therefore, by construction,
## the "pre-wiring baseline" this feature's test_criteria requires — the
## Dodge-Step/log wiring this suite guards against never executes on THIS
## codepath at all (Titus's Strike back is never reached; this suite only
## drives the Skeleton's incoming Strike against Titus, mirroring
## test_mainscene_hit_reaction_apply.gd).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass = preload("res://core/rules/round_events.gd")

const PROLOGUE_SEED: int = 42
const AC_GUARANTEED_HIT: int = -100
const OVERWHELMING_MITIGATION_STAT: int = 9999

## Pinned baseline — Section A (real, unmodified longsword stats).
const PINNED_ROLL: int = 21
const PINNED_CRIT: bool = true
const PINNED_HP_BEFORE: int = 18
const PINNED_DAMAGE_PARRY_FAILS: int = 12   # real parry_bonus(2) does not beat roll_total(21)
const PINNED_HP_AFTER_PARRY_FAILS: int = 6
const PINNED_DAMAGE_BLOCK_PARTIAL: int = 10  # 12 raw - (block roll + block_value(1))
const PINNED_HP_AFTER_BLOCK_PARTIAL: int = 8
const PINNED_DAMAGE_PASS: int = 12           # Pass ("none") leaves the raw hit unmitigated
const PINNED_HP_AFTER_PASS: int = 6


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


func _hp_of(instance, titus_id: String) -> int:
	return instance.status_panel_view.get_status(titus_id).get("hp_current", -1)


func _drive_incoming_strike_and_choose(instance, on_hit_choice: String) -> Array:
	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)
	instance.verb_bar_view.press("END_TURN")
	assert_true(instance.reaction_prompt_ui.is_open(), "the PreHitAvoidance pop-up must open for the incoming Strike")
	instance.reaction_prompt_ui.press_option("none")
	assert_true(instance.reaction_prompt_ui.is_open(), "the OnHitMitigation pop-up must open once the Strike is confirmed to hit")
	instance.reaction_prompt_ui.press_option(on_hit_choice)
	assert_false(instance.reaction_prompt_ui.is_open(), "no reaction window may remain open once OnHitMitigation has resolved")

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(attack_events.size(), 1, "exactly one Strike must have resolved")
	return attack_events


# ══════════════════════════════════════════════════════════════════════════
# Section A — real, unmodified longsword stats: genuine dice-driven
# partial/failed/absent mitigation, pinned to this commit's exact numbers.
# ══════════════════════════════════════════════════════════════════════════

func test_real_stats_parry_outcome_matches_pinned_pre_wiring_baseline() -> void:
	var instance = _boot_main_scene()
	var titus: Dictionary = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT
	var titus_id: String = _titus_id(instance)

	assert_eq(_hp_of(instance, titus_id), PINNED_HP_BEFORE, "fixture assumption: Titus's starting HP must match the pinned baseline")

	var attack_events: Array = _drive_incoming_strike_and_choose(instance, "parry")
	var event = attack_events[0]

	assert_eq(event.roll, PINNED_ROLL, "REGRESSION: the Skeleton's attack roll must be unchanged from the pinned pre-wiring baseline")
	assert_eq(event.crit, PINNED_CRIT, "REGRESSION: crit determination must be unchanged from the pinned pre-wiring baseline")
	assert_eq(event.damage_final, PINNED_DAMAGE_PARRY_FAILS, "REGRESSION: Parry (real parry_bonus=2, insufficient to beat roll_total) must still fail identically and leave damage_final unchanged")
	assert_eq(_hp_of(instance, titus_id), PINNED_HP_AFTER_PARRY_FAILS, "REGRESSION: Titus's post-Parry HP must be unchanged from the pinned pre-wiring baseline")


func test_real_stats_block_outcome_matches_pinned_pre_wiring_baseline() -> void:
	var instance = _boot_main_scene()
	var titus: Dictionary = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT
	var titus_id: String = _titus_id(instance)

	var attack_events: Array = _drive_incoming_strike_and_choose(instance, "block")
	var event = attack_events[0]

	assert_eq(event.roll, PINNED_ROLL, "REGRESSION: the Skeleton's attack roll must be unchanged from the pinned pre-wiring baseline")
	assert_eq(event.damage_final, PINNED_DAMAGE_BLOCK_PARTIAL, "REGRESSION: Block's partial-reduction formula (raw - (roll + block_value)) must be unchanged from the pinned pre-wiring baseline")
	assert_eq(_hp_of(instance, titus_id), PINNED_HP_AFTER_BLOCK_PARTIAL, "REGRESSION: Titus's post-Block HP must be unchanged from the pinned pre-wiring baseline")


func test_real_stats_pass_outcome_matches_pinned_pre_wiring_baseline() -> void:
	var instance = _boot_main_scene()
	var titus: Dictionary = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT
	var titus_id: String = _titus_id(instance)

	var attack_events: Array = _drive_incoming_strike_and_choose(instance, "none")
	var event = attack_events[0]

	assert_eq(event.roll, PINNED_ROLL, "REGRESSION: the Skeleton's attack roll must be unchanged from the pinned pre-wiring baseline")
	assert_eq(event.damage_final, PINNED_DAMAGE_PASS, "REGRESSION: Pass must leave the raw, unmitigated damage unchanged from the pinned pre-wiring baseline")
	assert_eq(_hp_of(instance, titus_id), PINNED_HP_AFTER_PASS, "REGRESSION: Titus's post-Pass HP must be unchanged from the pinned pre-wiring baseline")


# ══════════════════════════════════════════════════════════════════════════
# Section B — OVERWHELMING_MITIGATION_STAT convention (guaranteed full
# suppression), re-pinned with ABSOLUTE hp values.
# ══════════════════════════════════════════════════════════════════════════

func test_overwhelming_parry_still_fully_suppresses_damage_to_the_pinned_absolute_hp() -> void:
	var instance = _boot_main_scene()
	var titus: Dictionary = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT
	titus["weapon"]["parry_bonus"] = OVERWHELMING_MITIGATION_STAT
	var titus_id: String = _titus_id(instance)

	assert_eq(_hp_of(instance, titus_id), PINNED_HP_BEFORE, "fixture assumption: Titus's starting HP must match the pinned baseline")

	var attack_events: Array = _drive_incoming_strike_and_choose(instance, "parry")

	assert_eq(attack_events[0].damage_final, 0, "REGRESSION: an overwhelming Parry must still fully suppress damage_final to 0")
	assert_eq(_hp_of(instance, titus_id), PINNED_HP_BEFORE, "REGRESSION: Titus's HP must remain at the pinned absolute baseline value, not merely 'unchanged from itself'")


func test_overwhelming_block_still_fully_suppresses_damage_to_the_pinned_absolute_hp() -> void:
	var instance = _boot_main_scene()
	var titus: Dictionary = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT
	titus["weapon"]["block_value"] = OVERWHELMING_MITIGATION_STAT
	var titus_id: String = _titus_id(instance)

	var attack_events: Array = _drive_incoming_strike_and_choose(instance, "block")

	assert_eq(attack_events[0].damage_final, 0, "REGRESSION: an overwhelming Block must still fully suppress damage_final to 0")
	assert_eq(_hp_of(instance, titus_id), PINNED_HP_BEFORE, "REGRESSION: Titus's HP must remain at the pinned absolute baseline value, not merely 'unchanged from itself'")
