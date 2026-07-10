extends GutTest
## tests/application/test_build_defense_context.gd
##
## GUT suite for iteration K FEAT-004 (US-004, ADR-004):
## core/application/_build_defense_context.gd's BuildDefenseContext —
## a static, side-effect-free helper computing the DefenseContext Dictionary
## core/rules/resolution.gd's resolve_to_hit()/apply_on_hit_defense() expect,
## GENERICALLY for any defender, plus the extra keys a ReactionChooserPort's
## choose() needs (mirrors core/application/round_session.gd's private
## _build_defense_context()'s own per-key rationale, byte-for-byte, for
## build()).
##
## Validates (test_criteria):
##   1. build() computes parry_attack_bonus from the defender's own
##      attribute + weapon proficiency, and threads action_economy/
##      parrying_weapon/blocking_weapon/open_space_available correctly.
##   2. build_prehit_context() extends build() with mobility/
##      targeted_defense_value (including the Off-Guard reduction)/
##      action_current.
##   3. build_onhit_context() extends build() with parry_bonus/roll_total/
##      damage_raw/hp_current/action_current.
##   4. action_current defaults to ActionEconomy.MAX_BUDGET when
##      target_action_economy is null (never crashes, never trips a
##      spurious RESERVE gate for an untracked reactor).

const BuildDefenseContextClass = preload("res://core/application/_build_defense_context.gd")
const ActionEconomyClass       = preload("res://core/rules/action_economy.gd")


func _fresh_action_economy():
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	return ae


func _target(overrides: Dictionary = {}) -> Dictionary:
	var target: Dictionary = {
		"name":      "Skeleton",
		"hp_current": 20,
		"ac":        12,
		"strength":  2,
		"skills":    {"mobility": 1},
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus":         2,
			"parry_bonus":               4,
			"block_value":               2,
		},
	}
	for key in overrides:
		target[key] = overrides[key]
	return target


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — build().
# ══════════════════════════════════════════════════════════════════════════

func test_build_computes_parry_attack_bonus_from_attribute_plus_proficiency() -> void:
	var target: Dictionary = _target()
	var ae = _fresh_action_economy()
	var ctx: Dictionary = BuildDefenseContextClass.build(target, ae)

	# strength(2) + proficiency_bonus(2) = 4.
	assert_eq(ctx["parry_attack_bonus"], 4)
	assert_same(ctx["action_economy"], ae, "action_economy must be the SAME injected instance, never a copy")
	assert_same(ctx["parrying_weapon"], target["weapon"])
	assert_same(ctx["blocking_weapon"], target["weapon"])
	assert_true(ctx["open_space_available"])


func test_build_defaults_parry_attack_bonus_to_zero_when_weapon_has_no_damage_modifier_attribute() -> void:
	var target: Dictionary = {"name": "Bare", "weapon": {}}
	var ctx: Dictionary = BuildDefenseContextClass.build(target, null)
	assert_eq(ctx["parry_attack_bonus"], 0)
	assert_null(ctx["action_economy"])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — build_prehit_context().
# ══════════════════════════════════════════════════════════════════════════

func test_build_prehit_context_carries_mobility_and_targeted_defense_value() -> void:
	var target: Dictionary = _target()
	var ae = _fresh_action_economy()
	var ctx: Dictionary = BuildDefenseContextClass.build_prehit_context(target, ae, "ac")

	assert_eq(ctx["mobility"], 1, "mobility must be read from target.skills.mobility")
	assert_eq(ctx["targeted_defense_value"], 12, "targeted_defense_value must equal the plain target.ac with no Off-Guard condition")
	assert_eq(ctx["action_current"], ActionEconomyClass.MAX_BUDGET)
	# The base DefenseContext keys must still be present (build()'s output is extended, not replaced).
	assert_eq(ctx["parry_attack_bonus"], 4)


func test_build_prehit_context_reduces_targeted_defense_value_when_off_guard() -> void:
	var target: Dictionary = _target({"conditions": ["Off-Guard"]})
	var ctx: Dictionary = BuildDefenseContextClass.build_prehit_context(target, null, "ac")

	assert_eq(ctx["targeted_defense_value"], 10, "Off-Guard must reduce targeted_defense_value by Flanking.OFF_GUARD_BONUS (2): 12-2=10")


func test_build_prehit_context_mobility_defaults_to_zero_with_no_skills_key() -> void:
	var target: Dictionary = {"name": "NoSkills", "ac": 10, "weapon": {}}
	var ctx: Dictionary = BuildDefenseContextClass.build_prehit_context(target, null, "ac")
	assert_eq(ctx["mobility"], 0)


func test_build_prehit_context_action_current_reflects_live_action_economy() -> void:
	var target: Dictionary = _target()
	var ae = _fresh_action_economy()
	ae.spend_reaction()
	var ctx: Dictionary = BuildDefenseContextClass.build_prehit_context(target, ae, "ac")
	assert_eq(ctx["action_current"], ActionEconomyClass.MAX_BUDGET - 1, "action_current must reflect a live, already-spent ActionEconomy")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — build_onhit_context().
# ══════════════════════════════════════════════════════════════════════════

func test_build_onhit_context_carries_parry_bonus_roll_total_damage_raw_hp_current() -> void:
	var target: Dictionary = _target({"hp_current": 15})
	var ae = _fresh_action_economy()
	var to_hit_partial: Dictionary = {"roll_total": 18, "damage_raw": 7}
	var ctx: Dictionary = BuildDefenseContextClass.build_onhit_context(target, ae, to_hit_partial)

	assert_eq(ctx["parry_bonus"], 4, "parry_bonus must be read from the defender's OWN weapon (distinct from parry_attack_bonus)")
	assert_eq(ctx["roll_total"], 18)
	assert_eq(ctx["damage_raw"], 7)
	assert_eq(ctx["hp_current"], 15)
	assert_eq(ctx["action_current"], ActionEconomyClass.MAX_BUDGET)


func test_build_onhit_context_hp_current_defaults_to_one_when_missing() -> void:
	var target: Dictionary = {"name": "NoHp", "weapon": {}}
	var ctx: Dictionary = BuildDefenseContextClass.build_onhit_context(target, null, {})
	assert_eq(ctx["hp_current"], 1)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — action_current defaults to MAX_BUDGET with a null economy.
# ══════════════════════════════════════════════════════════════════════════

func test_action_current_defaults_to_max_budget_for_a_null_action_economy() -> void:
	var target: Dictionary = _target()
	var prehit_ctx: Dictionary = BuildDefenseContextClass.build_prehit_context(target, null, "ac")
	var onhit_ctx: Dictionary = BuildDefenseContextClass.build_onhit_context(target, null, {})

	assert_eq(prehit_ctx["action_current"], ActionEconomyClass.MAX_BUDGET)
	assert_eq(onhit_ctx["action_current"], ActionEconomyClass.MAX_BUDGET)
