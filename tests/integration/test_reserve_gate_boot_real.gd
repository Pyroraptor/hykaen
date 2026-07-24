extends GutTest
## tests/integration/test_reserve_gate_boot_real.gd — FEAT-231 (US-003 /
## US-004, resolves DEF-004).
##
## DEF-004 named a coverage gap: every existing proof of the budget-aware
## RESERVE gate (tests/unit/test_action_economy_reserve_gate.gd's own
## ActionEconomy-only inequality pins; tests/infrastructure/
## test_ai_reaction_policy.gd's direct AIReactionPolicy.choose() calls;
## tests/application/test_resolve_action_use_case_resolve_reactive.gd's
## resolve_reactive() calls) exercises the gate with a hand-built context
## Dictionary or a drained ActionEconomy constructed in isolation — NEVER
## through the real, live player-Strike verb path (MainScene.gd's
## `_verb_bar_strike_execute()` -> core/application/resolve_action_use_case.gd's
## `resolve_reactive()`, wired at boot to the REAL
## infrastructure/ai_reaction_policy.gd AIReactionPolicy via
## res://MainScene.tscn's composition root). This is exactly the "green
## tests, dead in play" risk this iteration's guardrails (G2) target: a
## regression that broke the REAL wiring between resolve_action_use_case.gd
## and the Skeleton's REAL, live ActionEconomy (e.g. reading a stale/copied
## budget snapshot instead of the live instance) would sail through every
## pre-existing suite untouched.
##
## This suite closes that gap with two dedicated boot-real MainScene tests,
## mirroring tests/integration/test_mainscene_player_strike_enemy_reaction.gd's
## and tests/integration/test_enemy_dodge_step_relocation.gd's established
## conventions exactly: boots the REAL res://MainScene.tscn composition
## root (G2 — never a hand-wired double), drains the Skeleton's OWN real,
## live ActionEconomy (core/rules/action_economy.gd, obtained via
## MainScene.gd's `_action_economy_for()`) down to exactly 1 action (the
## RESERVE floor — reacting would leave 1-1=0 < RESERVE(1)), forces the
## Skeleton's own "ac" absurdly low (the SAME field
## core/application/_build_defense_context.gd's build_prehit_context() reads
## for BOTH the guaranteed-hit to-hit roll AND
## core/domain/mobility_dodge_rule.gd's MobilityDodgeRule.dodge_worthwhile()'s
## targeted_defense_value) and its weapon's parry_bonus/block_value to an
## overwhelming value (mirrors tests/integration/
## test_mainscene_player_strike_enemy_reaction.gd's own
## OVERWHELMING_MITIGATION_STAT), then drives ONE real player Strike
## (Titus -> Skeleton) through the SAME verb_bar_view.press("STRIKE") ->
## hex_grid_view.hex_clicked.emit() entry point production code fires from a
## live click.
##
## Rather than a second, costlier MainScene boot to prove Dodge/Parry/Block
## are "otherwise worthwhile" via a full counterfactual AI choice, this
## suite proves worthwhileness DIRECTLY against the exact real, live values
## this single Strike actually rolled (roll_total/damage_raw, read off the
## structured core/log/attack_event.gd AttackEvent — never re-derived/
## fabricated) by calling the SAME real, pure domain-layer predicates
## infrastructure/ai_reaction_policy.gd's AIReactionPolicy itself consults
## (core/domain/mobility_dodge_rule.gd's MobilityDodgeRule.dodge_worthwhile()
## and core/domain/defense_mitigation_calculator.gd's
## DefenseMitigationCalculator.parry_worthwhile()/block_worthwhile()) —
## genuine production formulas, never a hand-rolled reimplementation — and
## asserting all three return true for THIS Strike's own real numbers. This
## keeps the "would otherwise be worthwhile" proof entirely real while
## costing zero extra engine boots.
##
## Verifies (test_criteria):
##   1. test_skeleton_at_one_action_passes_reaction_on_real_boot passes.
##   2. test_no_action_budget_drop_and_unmitigated_hit_at_reserve_floor passes.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass = preload("res://core/rules/round_events.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")
const MobilityDodgeRuleClass = preload("res://core/domain/mobility_dodge_rule.gd")
const DefenseMitigationCalculatorClass = preload("res://core/domain/defense_mitigation_calculator.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed:
## Titus acts first and the sole enemy (Skeleton) starts adjacent to him
## (mirrors tests/integration/test_mainscene_hit_reaction_apply.gd's
## identically-named/valued constant).
const PROLOGUE_SEED: int = 42

## AC_GUARANTEED_HIT — mirrors tests/integration/
## test_mainscene_player_strike_enemy_reaction.gd's identically-named/valued
## constant: an absurdly low AC guarantees a hit AND makes
## MobilityDodgeRule.dodge_worthwhile() (10+mobility > targeted_defense_value)
## unconditionally true (targeted_defense_value == the SAME "ac" field),
## with no RNG/seed edits.
const AC_GUARANTEED_HIT: int = -1000

## OVERWHELMING_MITIGATION_STAT — mirrors tests/integration/
## test_mainscene_player_strike_enemy_reaction.gd's identically-named/valued
## constant: pinned onto the Skeleton's own weapon's parry_bonus/block_value
## fields so DefenseMitigationCalculator.parry_worthwhile()/
## block_worthwhile() are unconditionally true for any real, seeded roll.
const OVERWHELMING_MITIGATION_STAT: int = 9999

## SURVIVABLE_HP — mirrors tests/integration/
## test_mainscene_player_strike_enemy_reaction.gd's identically-named/valued
## constant: comfortably above any possible crit-damage roll so an
## unmitigated hit never coincidentally defeats the Skeleton, keeping this
## suite's hp/budget assertions free of CombatantDefeatedEvent/loss-state
## side effects.
const SURVIVABLE_HP: int = 40


## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): round_session/
## the Layer 1 verb bar/Layer 2 selection overlay/turn_controller signal
## wiring are no longer live unconditionally at boot -- they now stay
## dormant until a real combat trigger fires (see MainScene.gd's own
## FEAT-316 doc). This suite drives the STRIKE verb directly against the
## real composition root, so _boot_main_scene() now also drives the SAME
## real handoff tests/boot/test_exploration_to_combat_handoff_trigger.gd
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


func _id(combatant) -> String:
	return combatant.combatant_id


func _skeleton(instance):
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


## _force_guaranteed_hit_and_overwhelming_mitigation(combatant) -> void —
## forces the Skeleton's own "ac" absurdly low (guarantees BOTH a hit
## against it AND, via the SAME field, that
## MobilityDodgeRule.dodge_worthwhile() is unconditionally true against the
## Skeleton's real, un-forced Mobility skill) and its weapon's
## parry_bonus/block_value to an overwhelming value (guarantees
## DefenseMitigationCalculator.parry_worthwhile()/block_worthwhile() are
## unconditionally true for any real, seeded roll) -- the exact
## "Dodge/Parry/Block would otherwise be worthwhile" precondition this
## feature's test_criteria require, driven entirely off the Skeleton's own
## real production data (skills/weapon), never a fabricated Dictionary.
func _force_guaranteed_hit_and_overwhelming_mitigation(combatant) -> void:
	combatant["ac"] = AC_GUARANTEED_HIT
	combatant["hp_current"] = SURVIVABLE_HP
	combatant["weapon"]["parry_bonus"] = OVERWHELMING_MITIGATION_STAT
	combatant["weapon"]["block_value"] = OVERWHELMING_MITIGATION_STAT


## _drain_action_economy_to_reserve_floor(ae) -> void — spends reactions off
## the Skeleton's OWN real, live ActionEconomy (core/rules/action_economy.gd)
## one at a time (spend_reaction(), never a hand-constructed/fresh
## ActionEconomy) until exactly 1 action remains -- the RESERVE floor
## (RESERVE == 1; reacting would leave 1-1=0 < RESERVE). Uses
## spend_reaction() rather than spend_action() so no per-TURN
## action_used/movement_used flag is tripped, keeping the Skeleton's own
## Strike/Step availability on its NEXT turn irrelevant to this suite
## (only the shared per-round budget_remaining pool matters here).
func _drain_action_economy_to_reserve_floor(ae) -> void:
	while ae.get_remaining() > ActionEconomyClass.RESERVE:
		ae.spend_reaction()
	assert_eq(ae.get_remaining(), ActionEconomyClass.RESERVE, "fixture assumption: the Skeleton's own live ActionEconomy must be drained to exactly the RESERVE floor (1)")


## _resolve_one_real_player_strike_against(instance, target_id) -> void —
## mirrors tests/integration/test_mainscene_player_strike_enemy_reaction.gd's
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


## _latest_structured_attack_event(instance) -> AttackEvent or null — mirrors
## tests/integration/test_mainscene_hit_reaction_apply.gd's identically-named/
## purposed helper: reaches the structured, storage-shaped
## core/log/attack_event.gd AttackEvent (which carries BOTH damage_raw and
## damage_final, plus roll_total) for the just-resolved Strike's row, driven
## entirely through the REAL, live-booted event_log_view.
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


## _parry_attack_bonus(combatant) -> int — mirrors core/application/
## _build_defense_context.gd's build() computation byte-for-byte (an
## opposed ATTACK roll: the reactor's own attribute modifier + its weapon's
## proficiency_bonus), so this suite's own DefenseMitigationCalculator.
## parry_worthwhile() check below reads the exact same value
## infrastructure/ai_reaction_policy.gd's real AIReactionPolicy would have
## consulted for this SAME Strike.
func _parry_attack_bonus(combatant) -> int:
	var weapon: Dictionary = combatant.weapon
	var parry_attribute: String = weapon.get("damage_modifier_attribute", "")
	var attr_val = combatant.get(parry_attribute)
	return int(attr_val if attr_val != null else 0) + int(weapon.get("proficiency_bonus", 0))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — with the Skeleton's real ActionEconomy at the RESERVE floor
# (1 action), a real player Strike genuinely passes the reaction in BOTH
# windows (Dodge never fires; Parry/Block never fire), even though this
# SAME Strike's own real, rolled numbers make all three genuinely
# worthwhile per the REAL domain-layer predicates AIReactionPolicy itself
# consults -- proving the Pass is the RESERVE gate's doing, not an absence
# of otherwise-worthwhile reactions.
# ══════════════════════════════════════════════════════════════════════════

func test_skeleton_at_one_action_passes_reaction_on_real_boot() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var skeleton = _skeleton(instance)
	var skeleton_id: String = _id(skeleton)
	_force_guaranteed_hit_and_overwhelming_mitigation(skeleton)

	var mobility: int = int(skeleton.skills.get("mobility", 0))
	var targeted_defense_value: int = int(skeleton.ac)
	assert_true(
		MobilityDodgeRuleClass.dodge_worthwhile(mobility, targeted_defense_value),
		"fixture assumption: the Skeleton's own real Mobility skill against its forced-low ac must make Dodge genuinely worthwhile per the REAL MobilityDodgeRule"
	)

	var ae = instance._action_economy_for(skeleton)
	assert_not_null(ae, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")
	_drain_action_economy_to_reserve_floor(ae)

	_resolve_one_real_player_strike_against(instance, skeleton_id)

	var attack_event = _sole_attack_event(instance)
	assert_true(
		attack_event.hit,
		"at the RESERVE floor, the Strike must genuinely HIT -- a real, chosen Dodge would have produced a miss instead"
	)
	assert_true(attack_event.damage_final > 0, "at the RESERVE floor, the unmitigated hit must deal real, positive damage")

	var structured_attack_event = _latest_structured_attack_event(instance)
	assert_not_null(structured_attack_event, "fixture assumption: a structured AttackEvent must be recorded for this Strike")
	if structured_attack_event != null:
		var roll_total: int = structured_attack_event.roll_total
		var damage_raw: int = structured_attack_event.damage_raw
		var parry_attack_bonus: int = _parry_attack_bonus(skeleton)

		assert_true(
			DefenseMitigationCalculatorClass.parry_worthwhile(parry_attack_bonus, OVERWHELMING_MITIGATION_STAT, roll_total),
			"fixture assumption: the overwhelming parry_bonus against this Strike's own real, rolled roll_total must make Parry genuinely worthwhile per the REAL DefenseMitigationCalculator"
		)
		assert_true(
			DefenseMitigationCalculatorClass.block_worthwhile(damage_raw, SURVIVABLE_HP),
			"fixture assumption: this Strike's own real, rolled damage_raw against SURVIVABLE_HP must make Block genuinely worthwhile per the REAL DefenseMitigationCalculator"
		)

		# The criterion itself: despite Dodge/Parry/Block ALL being genuinely
		# worthwhile per the real domain rules above, the Strike's own real
		# outcome shows a Pass in BOTH windows -- an unmitigated hit
		# (final_damage == raw_damage), never a miss or a mitigated hit.
		assert_eq(
			attack_event.damage_final, damage_raw,
			"a genuine Pass at the RESERVE floor must leave final_damage EQUAL to raw_damage, even though Parry/Block were both genuinely worthwhile"
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — at the RESERVE floor, the Skeleton's own live ActionEconomy
# shows ZERO budget drop across the Strike, and the resulting hit is fully
# UNMITIGATED (final damage equals the real, rolled raw damage) -- the
# OnHitMitigation window's Pass, proven directly via the structured
# AttackEvent rather than merely inferred from hp movement.
# ══════════════════════════════════════════════════════════════════════════

func test_no_action_budget_drop_and_unmitigated_hit_at_reserve_floor() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var skeleton = _skeleton(instance)
	var skeleton_id: String = _id(skeleton)
	_force_guaranteed_hit_and_overwhelming_mitigation(skeleton)

	var ae = instance._action_economy_for(skeleton)
	assert_not_null(ae, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")
	_drain_action_economy_to_reserve_floor(ae)

	var budget_before: int = ae.get_remaining()
	assert_eq(budget_before, ActionEconomyClass.RESERVE, "fixture assumption: the Skeleton's own live ActionEconomy sits at the RESERVE floor before the Strike")

	var hp_before: int = skeleton.hp_current

	_resolve_one_real_player_strike_against(instance, skeleton_id)

	# Criterion: no budget drop -- a genuinely-CHOSEN Dodge/Parry/Block would
	# have spent exactly one reaction (spend_reaction()) from this SAME live
	# ActionEconomy instance; a Pass spends nothing.
	assert_eq(
		ae.get_remaining(), budget_before,
		"a genuine Pass at the RESERVE floor must leave the Skeleton's own live ActionEconomy budget UNCHANGED (no reaction spent)"
	)

	var attack_event = _sole_attack_event(instance)
	assert_true(attack_event.hit, "fixture assumption: the guaranteed-hit AC must actually produce a hit once Dodge is forced to Pass")
	assert_true(attack_event.damage_final > 0, "the unmitigated hit must deal real, positive damage")

	var hp_after: int = skeleton.hp_current
	assert_eq(hp_before - hp_after, attack_event.damage_final, "the Skeleton's hp_current must drop by EXACTLY the unmitigated final damage -- no Parry/Block silently applied")

	# Criterion: the hit is fully UNMITIGATED -- final damage equals the
	# real, rolled raw damage (Pass in the OnHitMitigation window), proven
	# directly on the structured AttackEvent rather than merely inferred.
	var structured_attack_event = _latest_structured_attack_event(instance)
	if structured_attack_event != null:
		assert_true(structured_attack_event.damage_raw > 0, "fixture assumption: a guaranteed hit must roll positive raw damage")
		assert_eq(
			structured_attack_event.damage_final, structured_attack_event.damage_raw,
			"a genuine Pass (RESERVE gate forced) must leave final_damage EQUAL to raw_damage -- no unintended Parry/Block mitigation ever applied at the reserve floor"
		)
