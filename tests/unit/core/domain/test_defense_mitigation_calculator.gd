extends GutTest
## tests/unit/core/domain/test_defense_mitigation_calculator.gd
##
## GUT test suite for FEAT-002 (US-002):
## core/domain/defense_mitigation_calculator.gd's
## DefenseMitigationCalculator — the domain-pure "is Parry/Block worthwhile"
## predicates the enemy AI reaction policy
## (infrastructure/ai_reaction_policy.gd) consults for its ON-HIT mitigation
## decision.
##
## Rules under test (design notes, OnHitMitigation):
##   PARRY worthwhile when (parry_attack_bonus + parry_bonus) >=
##         roll_total - 9.
##   BLOCK worthwhile when damage_raw > hp_current / 4.
##
## Verifies:
##   1. parry_worthwhile() true when (parry_attack_bonus+parry_bonus) >=
##      roll_total-9, false otherwise.
##   2. block_worthwhile() true when damage_raw > hp_current/4, false
##      otherwise (else Pass, per the design notes' priority order — Block
##      is only ever consulted by the policy after Parry has already been
##      ruled out; this suite tests the predicate in isolation).
##   3. Static/code-inspection: the file is domain-pure (no engine imports,
##      no RNG, extends RefCounted only).

const DefenseMitigationCalculatorClass = preload("res://core/domain/defense_mitigation_calculator.gd")
const DEFENSE_MITIGATION_CALCULATOR_PATH: String = "res://core/domain/defense_mitigation_calculator.gd"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: Parry worthwhile when B >= roll_total - 9
# ══════════════════════════════════════════════════════════════════════════

func test_parry_worthwhile_true_when_at_threshold() -> void:
	# parry_attack_bonus(4)+parry_bonus(4)=8 >= roll_total(17)-9=8 -> true (equal counts)
	assert_true(
		DefenseMitigationCalculatorClass.parry_worthwhile(4, 4, 17),
		"B(8) >= roll_total-9(8) at the exact threshold must be worthwhile"
	)


func test_parry_worthwhile_true_when_above_threshold() -> void:
	# B = 5+4=9 >= 17-9=8 -> true
	assert_true(DefenseMitigationCalculatorClass.parry_worthwhile(5, 4, 17))


func test_parry_worthwhile_false_when_below_threshold() -> void:
	# B = 2+2=4 < 17-9=8 -> false
	assert_false(
		DefenseMitigationCalculatorClass.parry_worthwhile(2, 2, 17),
		"B(4) below roll_total-9(8) must not be worthwhile"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: Block worthwhile when damage_raw > hp_current/4
# ══════════════════════════════════════════════════════════════════════════

func test_block_worthwhile_true_when_damage_exceeds_quarter_hp() -> void:
	# damage_raw(6) > hp_current(20)/4=5 -> true
	assert_true(
		DefenseMitigationCalculatorClass.block_worthwhile(6, 20),
		"damage_raw(6) exceeding hp_current/4(5) must be worthwhile"
	)


func test_block_worthwhile_false_when_damage_at_quarter_hp() -> void:
	# damage_raw(5) == hp_current(20)/4=5 -> NOT a strict exceed -> false
	assert_false(
		DefenseMitigationCalculatorClass.block_worthwhile(5, 20),
		"damage_raw exactly at the quarter-hp threshold must not be worthwhile (strict exceed required)"
	)


func test_block_worthwhile_false_when_damage_below_quarter_hp() -> void:
	# damage_raw(2) < hp_current(20)/4=5 -> false
	assert_false(DefenseMitigationCalculatorClass.block_worthwhile(2, 20))


func test_block_worthwhile_handles_non_divisible_hp() -> void:
	# hp_current(21)/4 = 5.25; damage_raw(5) does not exceed -> false;
	# damage_raw(6) does -> true. Proves the threshold is not floored to an
	# integer 5 (which would incorrectly flip the damage_raw=6 case only).
	assert_false(DefenseMitigationCalculatorClass.block_worthwhile(5, 21))
	assert_true(DefenseMitigationCalculatorClass.block_worthwhile(6, 21))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: domain purity — no engine imports, RefCounted only
# ══════════════════════════════════════════════════════════════════════════

func test_source_is_domain_pure() -> void:
	var f := FileAccess.open(DEFENSE_MITIGATION_CALCULATOR_PATH, FileAccess.READ)
	assert_not_null(f, "defense_mitigation_calculator.gd must be readable")
	if f == null:
		return
	var content: String = f.get_as_text()
	f.close()

	assert_true(content.contains("extends RefCounted"),
		"DefenseMitigationCalculator must extend RefCounted (domain purity, ADR-001)")
	assert_false(content.contains("extends Node"), "must not extend Node (ADR-001)")
	assert_false(content.contains("extends Control"), "must not extend Control (ADR-001)")
	assert_false(content.contains("RandomNumberGenerator"),
		"DefenseMitigationCalculator must consume zero RNG — it is a pure comparison")
	assert_false(content.contains("_rng"),
		"DefenseMitigationCalculator must never touch an RNG instance")
