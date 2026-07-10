extends GutTest
## tests/infrastructure/test_ai_reaction_policy.gd
##
## GUT test suite for FEAT-002 (US-002): infrastructure/ai_reaction_policy.gd's
## AIReactionPolicy — a new, independent ReactionChooserPort implementation
## (core/application/ports/reaction_chooser_port.gd) providing a
## deterministic, RNG-free enemy AI Dodge/Parry/Block reaction decision,
## distinct from infrastructure/auto_reaction_chooser.gd's headless
## pass/first-legal test double (ADR-001).
##
## Decision rules exercised (delegated to core/domain/mobility_dodge_rule.gd
## and core/domain/defense_mitigation_calculator.gd — this file never
## re-derives the math itself):
##   1. Dodge chosen when "dodge" is legal AND
##      10 + mobility > targeted_defense_value.
##   2. Else Parry chosen when "parry" is legal AND
##      (parry_attack_bonus + parry_bonus) >= roll_total - 9.
##   3. Else Block chosen when "block" is legal AND
##      damage_raw > hp_current / 4.
##   4. Else Pass (ReactionChooserPort.PASS).
##
## Verifies (this feature's test_criteria):
##   1. Dodge chosen when 10+mobility > targeted_defense_value, else Pass.
##   2. Parry chosen when parry_attack_bonus+parry_bonus >= roll_total-9,
##      else Block if damage_raw > hp_current/4, else Pass.
##   3. Determinism: two runs with identical seed/inputs produce identical
##      policy choices.
##   4. Static/code-inspection: ai_reaction_policy.gd does not import or
##      alias auto_reaction_chooser.gd.

const AIReactionPolicyClass = preload("res://infrastructure/ai_reaction_policy.gd")
const ReactionChooserPortClass = preload("res://core/application/ports/reaction_chooser_port.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")

const AI_REACTION_POLICY_PATH: String = "res://infrastructure/ai_reaction_policy.gd"
const AUTO_REACTION_CHOOSER_PATH: String = "res://infrastructure/auto_reaction_chooser.gd"


func _policy() -> AIReactionPolicyClass:
	return AIReactionPolicyClass.new()


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: Dodge chosen when 10+mobility > targeted_defense_value,
# else Pass
# ══════════════════════════════════════════════════════════════════════════

func test_dodge_chosen_when_10_plus_mobility_exceeds_targeted_defense() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {"mobility": 1, "targeted_defense_value": 10}

	var choice: String = policy.choose(["dodge"], context)

	assert_eq(choice, "dodge", "10+mobility(1)=11 > targeted_defense_value(10) -> Dodge")


func test_dodge_not_chosen_falls_back_to_pass_when_not_worthwhile() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {"mobility": 0, "targeted_defense_value": 15}

	var choice: String = policy.choose(["dodge"], context)

	assert_eq(choice, ReactionChooserPortClass.PASS,
		"10+mobility(0)=10 does not exceed targeted_defense_value(15) -> Pass")


func test_dodge_not_chosen_on_exact_tie_falls_back_to_pass() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {"mobility": 0, "targeted_defense_value": 10}

	var choice: String = policy.choose(["dodge"], context)

	assert_eq(choice, ReactionChooserPortClass.PASS,
		"an exact tie (10 == 10) is not a strict exceed -> Pass")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: Parry chosen when parry_attack_bonus+parry_bonus >=
# roll_total-9, else Block if damage_raw > hp_current/4, else Pass
# ══════════════════════════════════════════════════════════════════════════

func test_parry_chosen_when_at_or_above_threshold() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {
		"parry_attack_bonus": 4, "parry_bonus": 4, "roll_total": 17,
		"damage_raw": 0, "hp_current": 20,
	}

	var choice: String = policy.choose(["parry", "block"], context)

	assert_eq(choice, "parry", "B(8) >= roll_total-9(8) -> Parry, checked before Block")


func test_block_chosen_when_parry_below_threshold_and_damage_exceeds_quarter_hp() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {
		"parry_attack_bonus": 1, "parry_bonus": 1, "roll_total": 17,
		"damage_raw": 6, "hp_current": 20,
	}

	var choice: String = policy.choose(["parry", "block"], context)

	assert_eq(choice, "block",
		"B(2) < roll_total-9(8) rules out Parry; damage_raw(6) > hp_current/4(5) -> Block")


func test_pass_chosen_when_neither_parry_nor_block_worthwhile() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {
		"parry_attack_bonus": 1, "parry_bonus": 1, "roll_total": 17,
		"damage_raw": 2, "hp_current": 20,
	}

	var choice: String = policy.choose(["parry", "block"], context)

	assert_eq(choice, ReactionChooserPortClass.PASS,
		"B(2) < 8 rules out Parry; damage_raw(2) does not exceed hp_current/4(5) -> Pass")


func test_block_chosen_alone_when_only_block_is_legal_and_worthwhile() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {"damage_raw": 10, "hp_current": 20}

	var choice: String = policy.choose(["block"], context)

	assert_eq(choice, "block")


func test_pass_chosen_when_block_alone_is_legal_but_not_worthwhile() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {"damage_raw": 4, "hp_current": 20}

	var choice: String = policy.choose(["block"], context)

	assert_eq(choice, ReactionChooserPortClass.PASS)


func test_pass_chosen_when_legal_reactions_is_empty() -> void:
	var policy: AIReactionPolicyClass = _policy()

	var choice: String = policy.choose([], {})

	assert_eq(choice, ReactionChooserPortClass.PASS)


## Dodge is checked before Parry/Block whenever it is legal AND worthwhile,
## even if a combined legal_reactions list also offers parry/block (mirrors
## reaction_window.gd's "WeaponAttack" composite trigger).
func test_dodge_takes_priority_over_parry_and_block_when_all_legal_and_worthwhile() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {
		"mobility": 5, "targeted_defense_value": 10,
		"parry_attack_bonus": 10, "parry_bonus": 10, "roll_total": 17,
		"damage_raw": 20, "hp_current": 20,
	}

	var choice: String = policy.choose(["dodge", "parry", "block"], context)

	assert_eq(choice, "dodge")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: determinism — two runs with identical inputs produce
# identical choices
# ══════════════════════════════════════════════════════════════════════════

func test_determinism_identical_inputs_produce_identical_choices_across_runs() -> void:
	var context: Dictionary = {
		"mobility": 1, "targeted_defense_value": 13,
		"parry_attack_bonus": 3, "parry_bonus": 2, "roll_total": 15,
		"damage_raw": 7, "hp_current": 20,
	}
	var legal_reactions: Array = ["dodge", "parry", "block"]

	var policy_a: AIReactionPolicyClass = _policy()
	var policy_b: AIReactionPolicyClass = _policy()

	var choice_a: String = policy_a.choose(legal_reactions, context)
	var choice_b: String = policy_b.choose(legal_reactions, context)

	assert_eq(choice_a, choice_b,
		"two independent AIReactionPolicy instances given identical inputs must agree")

	# Repeat the SAME policy instance twice more — proves no hidden mutable
	# state (e.g. an internal RNG/counter) drifts the answer across calls.
	var choice_repeat_1: String = policy_a.choose(legal_reactions, context)
	var choice_repeat_2: String = policy_a.choose(legal_reactions, context)
	assert_eq(choice_repeat_1, choice_a)
	assert_eq(choice_repeat_2, choice_a)


func test_determinism_across_many_repeated_calls_with_varied_worthwhile_inputs() -> void:
	# A Parry/Block boundary case, repeated many times, must never flap.
	var context: Dictionary = {
		"parry_attack_bonus": 2, "parry_bonus": 2, "roll_total": 17,
		"damage_raw": 6, "hp_current": 20,
	}
	var policy: AIReactionPolicyClass = _policy()

	var first_choice: String = policy.choose(["parry", "block"], context)
	for i in range(50):
		assert_eq(policy.choose(["parry", "block"], context), first_choice,
			"call #%d must reproduce the identical choice with no RNG involved" % i)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: static/code-inspection — no import/alias of
# auto_reaction_chooser.gd
# ══════════════════════════════════════════════════════════════════════════

func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % path)
	if f == null:
		return ""
	var content: String = f.get_as_text()
	f.close()
	return content


## Only CODE lines (preload/extends/`new`-style references) matter here —
## this feature's own file-level doc legitimately NAMES
## auto_reaction_chooser.gd in prose (contrasting the two implementations),
## which must not itself trip this check. Comment lines (leading `#`/`##`,
## ignoring indentation) are excluded before scanning for a real
## import/alias/subclass reference.
func _non_comment_lines(content: String) -> String:
	var kept: PackedStringArray = []
	for line in content.split("\n"):
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	return "\n".join(kept)


func test_does_not_import_or_alias_auto_reaction_chooser() -> void:
	var content: String = _read_source(AI_REACTION_POLICY_PATH)
	if content.is_empty():
		return
	var code_only: String = _non_comment_lines(content)
	assert_false(
		code_only.contains("auto_reaction_chooser"),
		"ai_reaction_policy.gd must never import/reference auto_reaction_chooser.gd in code (ADR-001, distinct implementations)"
	)
	assert_false(
		code_only.contains("AutoReactionChooser"),
		"ai_reaction_policy.gd must never alias/subclass AutoReactionChooser in code"
	)


func test_extends_reaction_chooser_port_directly_not_via_auto_reaction_chooser() -> void:
	var content: String = _read_source(AI_REACTION_POLICY_PATH)
	if content.is_empty():
		return
	assert_true(
		content.contains("extends \"res://core/application/ports/reaction_chooser_port.gd\""),
		"AIReactionPolicy must extend ReactionChooserPort directly"
	)


func test_ai_reaction_policy_and_auto_reaction_chooser_are_distinct_files() -> void:
	assert_ne(AI_REACTION_POLICY_PATH, AUTO_REACTION_CHOOSER_PATH)
	assert_true(FileAccess.file_exists(AI_REACTION_POLICY_PATH))
	assert_true(FileAccess.file_exists(AUTO_REACTION_CHOOSER_PATH))


func test_ai_reaction_policy_is_a_reaction_chooser_port_instance() -> void:
	var policy: AIReactionPolicyClass = _policy()
	assert_true(policy is ReactionChooserPortClass,
		"AIReactionPolicy must satisfy the ReactionChooserPort contract")


# ══════════════════════════════════════════════════════════════════════════
# iteration K FEAT-003 (US-003, ADR-003): budget-aware RESERVE gate.
#
# RESERVE gate: reacting always costs exactly one action; choose() must
# force Pass whenever action_current - 1 < ActionEconomyClass.RESERVE,
# checked BEFORE any Dodge/Parry/Block rule is evaluated, for BOTH the
# PreHitAvoidance (Dodge) and OnHitMitigation (Parry/Block) windows.
# ══════════════════════════════════════════════════════════════════════════

func test_reserve_gate_forces_pass_at_action_current_one_even_though_dodge_worthwhile() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {
		"mobility": 5, "targeted_defense_value": 10,  # 10+5=15 > 10 -> Dodge would fire
		"action_current": 1,
	}

	var choice: String = policy.choose(["dodge"], context)

	assert_eq(choice, ReactionChooserPortClass.PASS,
		"action_current=1: reacting would leave 0 actions (< RESERVE=1) for the reactor's next turn -> Pass, even though Dodge's own rule is worthwhile")


func test_reserve_gate_forces_pass_at_action_current_one_even_though_parry_worthwhile() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {
		"parry_attack_bonus": 4, "parry_bonus": 4, "roll_total": 17,  # Parry would fire
		"damage_raw": 0, "hp_current": 20,
		"action_current": 1,
	}

	var choice: String = policy.choose(["parry", "block"], context)

	assert_eq(choice, ReactionChooserPortClass.PASS,
		"action_current=1 must force Pass on the OnHitMitigation window even though Parry's own rule is worthwhile")


func test_reserve_gate_forces_pass_at_action_current_one_even_though_block_worthwhile() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {
		"damage_raw": 10, "hp_current": 20,  # Block would fire
		"action_current": 1,
	}

	var choice: String = policy.choose(["block"], context)

	assert_eq(choice, ReactionChooserPortClass.PASS,
		"action_current=1 must force Pass on the OnHitMitigation window even though Block's own rule is worthwhile")


func test_reserve_gate_forces_pass_at_action_current_zero() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {
		"mobility": 5, "targeted_defense_value": 10,
		"action_current": 0,
	}

	var choice: String = policy.choose(["dodge"], context)

	assert_eq(choice, ReactionChooserPortClass.PASS,
		"action_current=0 must also force Pass (reacting would go negative)")


func test_reserve_gate_allows_dodge_at_action_current_two() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {
		"mobility": 5, "targeted_defense_value": 10,
		"action_current": 2,
	}

	var choice: String = policy.choose(["dodge"], context)

	assert_eq(choice, "dodge",
		"action_current=2: reacting leaves exactly 1 action (== RESERVE) -> the reserve is preserved, Dodge proceeds")


func test_reserve_gate_boundary_action_current_equal_to_reserve_forces_pass() -> void:
	# Directly pins the exact inequality this feature's test_criteria names:
	# RESERVE enforces action_current-1>=1 (i.e. action_current>=RESERVE+1)
	# before evaluating Dodge/Parry/Block.
	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {
		"damage_raw": 10, "hp_current": 20,
		"action_current": ActionEconomyClass.RESERVE,
	}

	var choice: String = policy.choose(["block"], context)

	assert_eq(choice, ReactionChooserPortClass.PASS,
		"action_current == RESERVE must still force Pass: action_current-1 (0) < RESERVE (1)")


## "Boot-real" style: drains a REAL core/rules/action_economy.gd ActionEconomy
## instance down to a budget of 1 via its own spend_reaction() calls (never a
## bare int literal fixture), then feeds its real get_remaining() straight
## into the policy's context -- proving the gate reacts correctly to the
## actual domain object the composition root will eventually wire in, not
## merely to a hand-authored integer.
func test_reserve_gate_forces_pass_using_real_action_economy_drained_to_one() -> void:
	var ae: ActionEconomyClass = ActionEconomyClass.new()
	ae.start_of_round()
	for _i in range(ActionEconomyClass.MAX_BUDGET - 1):
		ae.spend_reaction()
	assert_eq(ae.get_remaining(), 1, "fixture assumption: real ActionEconomy must be drained to exactly 1")

	var policy: AIReactionPolicyClass = _policy()
	var context: Dictionary = {
		"mobility": 5, "targeted_defense_value": 10,
		"parry_attack_bonus": 10, "parry_bonus": 10, "roll_total": 17,
		"damage_raw": 20, "hp_current": 20,
		"action_current": ae.get_remaining(),
	}

	var choice: String = policy.choose(["dodge", "parry", "block"], context)

	assert_eq(choice, ReactionChooserPortClass.PASS,
		"a real ActionEconomy drained to budget=1 must force Pass regardless of how worthwhile every reaction rule looks")


## Regression (test_criteria #3): FEAT-002's own Dodge/Parry/Block outcomes
## must be byte-for-byte unchanged when the budget is sufficient -- whether
## action_current is entirely omitted (pre-FEAT-003 caller shape) or
## explicitly supplied at a healthy value, the RESERVE gate must be a
## complete no-op.
func test_regression_dodge_outcome_unchanged_when_action_current_omitted_or_healthy() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var context_no_key: Dictionary = {"mobility": 1, "targeted_defense_value": 10}
	var context_healthy: Dictionary = {
		"mobility": 1, "targeted_defense_value": 10,
		"action_current": ActionEconomyClass.MAX_BUDGET,
	}

	assert_eq(policy.choose(["dodge"], context_no_key), "dodge",
		"omitting action_current must default to a healthy budget and preserve FEAT-002's Dodge outcome")
	assert_eq(policy.choose(["dodge"], context_healthy), "dodge",
		"an explicit healthy action_current must preserve FEAT-002's Dodge outcome")


func test_regression_parry_and_block_outcomes_unchanged_when_budget_sufficient() -> void:
	var policy: AIReactionPolicyClass = _policy()
	var parry_context: Dictionary = {
		"parry_attack_bonus": 4, "parry_bonus": 4, "roll_total": 17,
		"damage_raw": 0, "hp_current": 20, "action_current": 7,
	}
	var block_context: Dictionary = {
		"parry_attack_bonus": 1, "parry_bonus": 1, "roll_total": 17,
		"damage_raw": 6, "hp_current": 20, "action_current": 7,
	}
	var pass_context: Dictionary = {
		"parry_attack_bonus": 1, "parry_bonus": 1, "roll_total": 17,
		"damage_raw": 2, "hp_current": 20, "action_current": 7,
	}

	assert_eq(policy.choose(["parry", "block"], parry_context), "parry",
		"FEAT-002's Parry outcome must be unchanged when the budget is sufficient")
	assert_eq(policy.choose(["parry", "block"], block_context), "block",
		"FEAT-002's Block outcome must be unchanged when the budget is sufficient")
	assert_eq(policy.choose(["parry", "block"], pass_context), ReactionChooserPortClass.PASS,
		"FEAT-002's Pass outcome must be unchanged when the budget is sufficient")
