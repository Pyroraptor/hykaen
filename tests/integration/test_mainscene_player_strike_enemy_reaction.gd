extends GutTest
## tests/integration/test_mainscene_player_strike_enemy_reaction.gd —
## FEAT-230 (US-004, resolves DEF-003).
##
## DEF-003 named a coverage gap on the player-strikes-enemy path
## (MainScene.gd's `_verb_bar_strike_execute()` -> core/application/
## resolve_action_use_case.gd's `resolve_reactive()`, wired to the REAL
## infrastructure/ai_reaction_policy.gd AIReactionPolicy at boot -- see
## tests/gut/test_player_strikes_enemy_pass_through.gd's own doc): only the
## Dodge branch (tests/integration/test_enemy_dodge_step_relocation.gd) is
## boot-real tested end to end on this path. Parry is only ever exercised
## via tests/application/test_resolve_action_use_case_resolve_reactive.gd's
## hand-built dictionaries + a ScriptedChooser that FORCES the choice
## directly -- it never proves the REAL AIReactionPolicy, wired through the
## REAL res://MainScene.tscn composition root, genuinely CHOOSES Parry off
## its own worthwhileness math. Block has no boot-real (or even
## resolve_reactive()-level) coverage AT ALL on this path.
##
## This suite closes that gap with two dedicated boot-real tests, mirroring
## tests/integration/test_mainscene_hit_reaction_apply.gd's established
## "player-defender" pattern (force deterministic mitigation via plain
## combatant-Dictionary field overrides a production call path already
## reads -- AC_GUARANTEED_HIT/OVERWHELMING_MITIGATION_STAT -- never a
## scripted/substitute ReactionChooserPort or RNG), applied here to the
## REVERSE direction (Titus -> Skeleton, the Skeleton as the genuine
## AI-driven defender):
##
##   1. test_forced_parry_success_yields_higher_skeleton_hp_current_vs_unmitigated
##      -- an overwhelming parry_bonus on the Skeleton's own weapon makes
##      DefenseMitigationCalculator.parry_worthwhile() true regardless of the
##      real, seeded roll_total, so the REAL AIReactionPolicy genuinely
##      CHOOSES "parry" (never injected), and the actual d20 parry roll
##      (also inflated by the same overwhelming parry_bonus) always
##      succeeds -- the Skeleton's hp_current is asserted strictly HIGHER
##      than an otherwise-identical, unmitigated Strike (parry_bonus/
##      block_value both zeroed so no reaction is even offered).
##   2. test_forced_block_yields_higher_skeleton_hp_current_vs_unmitigated
##      -- parry_bonus zeroed (so "parry" is never even a legal reaction --
##      is_parry_eligible() gates it out entirely) and an overwhelming
##      block_value makes DefenseMitigationCalculator.block_worthwhile()
##      true for any possible damage roll, so the REAL AIReactionPolicy
##      genuinely CHOOSES "block", and the actual block-reduction roll
##      always fully suppresses damage -- again asserted strictly HIGHER
##      than the identical unmitigated baseline.
##
## Both tests disable the Skeleton's PreHitAvoidance Dodge branch (already
## covered by test_enemy_dodge_step_relocation.gd) via the SAME
## "Immobilized" condition core/rules/resolution.gd's own is_dodge_eligible()
## reads (core/application/tests/test_reaction_window_prehit.gd's
## established technique) -- not a test double, a genuine domain condition,
## and NOT written via MainScene.gd's own `_refresh_off_guard_conditions()`
## (which only ever runs at boot and after a successful Step/Stride -- never
## during a Strike -- so this override safely survives untouched through the
## single Strike this suite drives) -- so the Strike reliably reaches the
## OnHitMitigation window under test regardless of the AC value forced for a
## guaranteed hit (an unnaturally low AC would otherwise ALSO make Dodge
## unconditionally "worthwhile", masking the OnHitMitigation branch this
## suite targets).
##
## Verifies (test_criteria):
##   1. test_forced_parry_success_yields_higher_skeleton_hp_current_vs_unmitigated passes.
##   2. test_forced_block_yields_higher_skeleton_hp_current_vs_unmitigated passes.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass = preload("res://core/rules/round_events.gd")

## PROLOGUE_SEED -- this project's established known-good fixture seed:
## Titus acts first and the sole enemy (Skeleton) starts adjacent to him
## (mirrors tests/integration/test_mainscene_hit_reaction_apply.gd's
## identically-named/valued constant).
const PROLOGUE_SEED: int = 42

## AC_GUARANTEED_HIT -- mirrors tests/e2e/test_reactions_fully_live.gd's
## identically-named/valued constant: an absurdly low AC guarantees a hit
## with no RNG/seed edits.
const AC_GUARANTEED_HIT: int = -1000

## OVERWHELMING_MITIGATION_STAT -- mirrors tests/integration/
## test_mainscene_hit_reaction_apply.gd's identically-named/valued constant:
## pinned onto the Skeleton's own weapon's parry_bonus/block_value fields so
## a chosen Parry's (d20 + parry_bonus) roll always strictly exceeds any
## possible attacker roll_total, and a chosen Block's (die_roll +
## block_value) reduction always meets or exceeds any possible raw damage --
## deterministic full suppression without touching RNG/seed math.
const OVERWHELMING_MITIGATION_STAT: int = 9999

## SURVIVABLE_HP -- the Skeleton's hp_current is pinned to this before every
## Strike this suite drives. AC_GUARANTEED_HIT is so far below any possible
## defense_value that every Strike in this suite is ALSO a guaranteed
## CRITICAL hit (core/rules/resolution.gd: crit = hit AND (roll_total -
## defense_value) >= 10), which rolls 2 damage dice plus DOUBLE the
## attribute modifier: for Titus's longsword (1d12, strength 5) that is
## 2d12 + 10, range [12, 34]. SURVIVABLE_HP is comfortably above that
## maximum (34) so the UNMITIGATED baseline run never coincidentally
## defeats the Skeleton (which would complicate the hp_current comparison
## with CombatantDefeatedEvent/loss-state side effects), while staying low
## enough that DefenseMitigationCalculator.block_worthwhile(damage_raw,
## hp_current) (damage_raw > hp_current / 4 == 10) is true for EVERY
## possible crit damage roll (minimum 12 > 10).
const SURVIVABLE_HP: int = 40


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _id(combatant: Dictionary) -> String:
	return combatant.get("combatant_id", combatant.get("name", ""))


func _skeleton(instance) -> Dictionary:
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton: Dictionary = instance._enemies[0]
	assert_eq(skeleton.get("name", ""), "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


## _force_guaranteed_hit_no_dodge(combatant) -> void -- forces a guaranteed
## hit (AC_GUARANTEED_HIT) AND disables the PreHitAvoidance Dodge branch
## entirely via the genuine "Immobilized" domain condition
## core/rules/resolution.gd's is_dodge_eligible() reads -- without this, an
## AC this low would ALSO make MobilityDodgeRule.dodge_worthwhile() (10 +
## mobility > targeted_defense_value) unconditionally true, routing every
## Strike into the (already boot-real-tested) Dodge branch instead of the
## OnHitMitigation (Parry/Block) branch this suite targets.
func _force_guaranteed_hit_no_dodge(combatant: Dictionary) -> void:
	combatant["ac"] = AC_GUARANTEED_HIT
	combatant["conditions"] = ["Immobilized"]


## _resolve_one_real_player_strike_against(instance, target_id) -> void --
## mirrors tests/integration/test_enemy_dodge_step_relocation.gd's own
## identically-named/purposed helper: drives the REAL
## verb_bar_view.press("STRIKE") -> hex_grid_view.hex_clicked.emit() entry
## point (the SAME MainScene._verb_bar_strike_execute() call site production
## code fires from a live player click) against a specific, caller-chosen
## target_id.
func _resolve_one_real_player_strike_against(instance, target_id: String) -> void:
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.has(target_id), "fixture assumption: the Skeleton must be an in-reach Strike target at boot")
	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the Skeleton has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)


func _sole_attack_event(instance):
	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one Strike must have resolved")
	return attack_events[0]


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 -- a genuinely AI-CHOSEN, successful Parry leaves the
# Skeleton's hp_current strictly HIGHER than an otherwise-identical,
# unmitigated Strike.
# ══════════════════════════════════════════════════════════════════════════

func test_forced_parry_success_yields_higher_skeleton_hp_current_vs_unmitigated() -> void:
	# ── Run A: forced-successful Parry ──────────────────────────────────────
	var mitigated_instance = _boot_main_scene()
	await get_tree().process_frame

	var mitigated_skeleton: Dictionary = _skeleton(mitigated_instance)
	var mitigated_skeleton_id: String = _id(mitigated_skeleton)
	_force_guaranteed_hit_no_dodge(mitigated_skeleton)
	mitigated_skeleton["hp_current"] = SURVIVABLE_HP
	mitigated_skeleton["weapon"]["parry_bonus"] = OVERWHELMING_MITIGATION_STAT

	var mitigated_ae = mitigated_instance._action_economy_for(mitigated_skeleton)
	var mitigated_budget_before: int = mitigated_ae.get_remaining()

	_resolve_one_real_player_strike_against(mitigated_instance, mitigated_skeleton_id)

	var mitigated_attack_event = _sole_attack_event(mitigated_instance)
	assert_true(mitigated_attack_event.hit, "fixture assumption: the guaranteed-hit AC must actually produce a hit")
	assert_eq(mitigated_attack_event.damage_final, 0, "a genuinely-chosen, successful Parry must negate ALL raw damage")

	var mitigated_hp_after: int = mitigated_skeleton.get("hp_current", -1)
	assert_eq(mitigated_hp_after, SURVIVABLE_HP, "a successful Parry must leave the Skeleton's hp_current byte-for-byte unchanged")
	assert_eq(
		mitigated_ae.get_remaining(), mitigated_budget_before - 1,
		"a genuinely-CHOSEN Parry must spend exactly one reaction from the Skeleton's own action budget (visibly drops)"
	)

	# ── Run B: an otherwise-identical, unmitigated baseline (parry_bonus AND
	# block_value both zeroed, so is_parry_eligible()/is_block_eligible()
	# gate BOTH reactions out entirely -- no reaction is even offered). ─────
	var baseline_instance = _boot_main_scene()
	await get_tree().process_frame

	var baseline_skeleton: Dictionary = _skeleton(baseline_instance)
	var baseline_skeleton_id: String = _id(baseline_skeleton)
	_force_guaranteed_hit_no_dodge(baseline_skeleton)
	baseline_skeleton["hp_current"] = SURVIVABLE_HP
	baseline_skeleton["weapon"]["parry_bonus"] = 0
	baseline_skeleton["weapon"]["block_value"] = 0

	_resolve_one_real_player_strike_against(baseline_instance, baseline_skeleton_id)

	var baseline_attack_event = _sole_attack_event(baseline_instance)
	assert_true(baseline_attack_event.hit, "fixture assumption: the guaranteed-hit AC must actually produce a hit")
	assert_true(baseline_attack_event.damage_final > 0, "the unmitigated baseline must take real, unmitigated damage")

	var baseline_hp_after: int = baseline_skeleton.get("hp_current", -1)
	assert_lt(baseline_hp_after, SURVIVABLE_HP, "fixture assumption: the unmitigated baseline must actually lose hp")

	# ── The criterion itself ────────────────────────────────────────────────
	assert_true(
		mitigated_hp_after > baseline_hp_after,
		"a genuinely AI-chosen, successful Parry must leave the Skeleton's hp_current strictly higher than an identical unmitigated Strike (%d vs %d)" % [mitigated_hp_after, baseline_hp_after]
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 -- a genuinely AI-CHOSEN, successful Block leaves the
# Skeleton's hp_current strictly HIGHER than an otherwise-identical,
# unmitigated Strike.
# ══════════════════════════════════════════════════════════════════════════

func test_forced_block_yields_higher_skeleton_hp_current_vs_unmitigated() -> void:
	# ── Run A: forced-successful Block (Parry gated out entirely) ──────────
	var mitigated_instance = _boot_main_scene()
	await get_tree().process_frame

	var mitigated_skeleton: Dictionary = _skeleton(mitigated_instance)
	var mitigated_skeleton_id: String = _id(mitigated_skeleton)
	_force_guaranteed_hit_no_dodge(mitigated_skeleton)
	mitigated_skeleton["hp_current"] = SURVIVABLE_HP
	mitigated_skeleton["weapon"]["parry_bonus"] = 0
	mitigated_skeleton["weapon"]["block_value"] = OVERWHELMING_MITIGATION_STAT

	var mitigated_ae = mitigated_instance._action_economy_for(mitigated_skeleton)
	var mitigated_budget_before: int = mitigated_ae.get_remaining()

	_resolve_one_real_player_strike_against(mitigated_instance, mitigated_skeleton_id)

	var mitigated_attack_event = _sole_attack_event(mitigated_instance)
	assert_true(mitigated_attack_event.hit, "fixture assumption: the guaranteed-hit AC must actually produce a hit")
	assert_eq(mitigated_attack_event.damage_final, 0, "a genuinely-chosen, successful Block must fully suppress damage (overwhelming block_value)")

	var mitigated_hp_after: int = mitigated_skeleton.get("hp_current", -1)
	assert_eq(mitigated_hp_after, SURVIVABLE_HP, "a successful Block must leave the Skeleton's hp_current byte-for-byte unchanged")
	assert_eq(
		mitigated_ae.get_remaining(), mitigated_budget_before - 1,
		"a genuinely-CHOSEN Block must spend exactly one reaction from the Skeleton's own action budget (visibly drops)"
	)

	# ── Run B: an otherwise-identical, unmitigated baseline ─────────────────
	var baseline_instance = _boot_main_scene()
	await get_tree().process_frame

	var baseline_skeleton: Dictionary = _skeleton(baseline_instance)
	var baseline_skeleton_id: String = _id(baseline_skeleton)
	_force_guaranteed_hit_no_dodge(baseline_skeleton)
	baseline_skeleton["hp_current"] = SURVIVABLE_HP
	baseline_skeleton["weapon"]["parry_bonus"] = 0
	baseline_skeleton["weapon"]["block_value"] = 0

	_resolve_one_real_player_strike_against(baseline_instance, baseline_skeleton_id)

	var baseline_attack_event = _sole_attack_event(baseline_instance)
	assert_true(baseline_attack_event.hit, "fixture assumption: the guaranteed-hit AC must actually produce a hit")
	assert_true(baseline_attack_event.damage_final > 0, "the unmitigated baseline must take real, unmitigated damage")

	var baseline_hp_after: int = baseline_skeleton.get("hp_current", -1)
	assert_lt(baseline_hp_after, SURVIVABLE_HP, "fixture assumption: the unmitigated baseline must actually lose hp")

	# ── The criterion itself ────────────────────────────────────────────────
	assert_true(
		mitigated_hp_after > baseline_hp_after,
		"a genuinely AI-chosen, successful Block must leave the Skeleton's hp_current strictly higher than an identical unmitigated Strike (%d vs %d)" % [mitigated_hp_after, baseline_hp_after]
	)
