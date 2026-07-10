extends GutTest
## tests/unit/core/domain/test_mobility_dodge_rule.gd
##
## GUT test suite for FEAT-002 (US-002): core/domain/mobility_dodge_rule.gd's
## MobilityDodgeRule — the domain-pure "is Dodge worthwhile" predicate the
## enemy AI reaction policy (infrastructure/ai_reaction_policy.gd) consults.
##
## Rule under test (design notes, PreHitAvoidance Dodge):
##   DODGE if 10 + mobility_skill > targeted_defense_value, else Pass.
##
## Verifies:
##   1. dodge_worthwhile() returns true when 10+mobility STRICTLY exceeds
##      targeted_defense_value.
##   2. dodge_worthwhile() returns false when 10+mobility does not exceed
##      (less than OR equal to) targeted_defense_value.
##   3. Static/code-inspection: the file is domain-pure (no engine imports,
##      no RNG, extends RefCounted only).

const MobilityDodgeRuleClass = preload("res://core/domain/mobility_dodge_rule.gd")
const MOBILITY_DODGE_RULE_PATH: String = "res://core/domain/mobility_dodge_rule.gd"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: Dodge worthwhile when 10+mobility > targeted_defense_value
# ══════════════════════════════════════════════════════════════════════════

func test_dodge_worthwhile_true_when_strictly_exceeds() -> void:
	# 10 + 1 = 11 > 10 -> true
	assert_true(
		MobilityDodgeRuleClass.dodge_worthwhile(1, 10),
		"10+mobility(1)=11 strictly exceeds targeted_defense_value(10) -> worthwhile"
	)


func test_dodge_worthwhile_true_with_higher_mobility() -> void:
	# 10 + 5 = 15 > 12 -> true
	assert_true(MobilityDodgeRuleClass.dodge_worthwhile(5, 12))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: Dodge NOT worthwhile (else Pass) when 10+mobility does not
# strictly exceed targeted_defense_value (equal or less)
# ══════════════════════════════════════════════════════════════════════════

func test_dodge_worthwhile_false_when_equal() -> void:
	# 10 + 0 = 10 == 10 -> NOT a strict exceed -> false
	assert_false(
		MobilityDodgeRuleClass.dodge_worthwhile(0, 10),
		"an exact tie must not count as 'worthwhile' (strict exceed required)"
	)


func test_dodge_worthwhile_false_when_less() -> void:
	# 10 + 1 = 11 < 15 -> false
	assert_false(MobilityDodgeRuleClass.dodge_worthwhile(1, 15))


func test_dodge_worthwhile_handles_negative_mobility() -> void:
	# 10 + (-2) = 8 < 9 -> false
	assert_false(MobilityDodgeRuleClass.dodge_worthwhile(-2, 9))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: domain purity — no engine imports, RefCounted only
# ══════════════════════════════════════════════════════════════════════════

func test_source_is_domain_pure() -> void:
	var f := FileAccess.open(MOBILITY_DODGE_RULE_PATH, FileAccess.READ)
	assert_not_null(f, "mobility_dodge_rule.gd must be readable")
	if f == null:
		return
	var content: String = f.get_as_text()
	f.close()

	assert_true(content.contains("extends RefCounted"),
		"MobilityDodgeRule must extend RefCounted (domain purity, ADR-001)")
	assert_false(content.contains("extends Node"), "must not extend Node (ADR-001)")
	assert_false(content.contains("extends Control"), "must not extend Control (ADR-001)")
	assert_false(content.contains("RandomNumberGenerator"),
		"MobilityDodgeRule must consume zero RNG — it is a pure comparison")
	assert_false(content.contains("_rng"), "MobilityDodgeRule must never touch an RNG instance")
