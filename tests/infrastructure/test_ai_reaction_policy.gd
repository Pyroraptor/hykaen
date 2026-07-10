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
