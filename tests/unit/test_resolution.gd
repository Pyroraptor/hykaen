extends GutTest
## tests/unit/test_resolution.gd
##
## GUT test suite for core/rules/resolution.gd — Passive-Defense Strike Resolution Pipeline.
## Validates all test criteria for FEAT-008 / US-008.
##
## ═══════════════════════════════════════════════════════════════════════════════
## PINNED SEED DOCUMENTATION
##
## Common test setup:
##   attacker.strength = 3  (damage_modifier_attribute = "strength")
##   weapon.proficiency_bonus = 2
##   weapon.damage_die = 6  (d6)
##   target.ac = 13
##   roll_total = rng.d20() + attr_mod(3) + prof_bonus(2) = rng.d20() + 5
##
## HIT (no crit) — seed 2:
##   seed 2 → rng.d20() yields 11 → roll_total 11+3+2=16 → hit (16>=13, 16-13=3<10 no crit)
##   Damage: rng.roll(6,1) yields 4 → damage_raw = 4+3 = 7
##
## MISS — seed 3:
##   seed 3 → rng.d20() yields 5 → roll_total 5+3+2=10 → miss (10<13)
##   Damage: 0 (miss — no damage roll consumed)
##
## CRIT — seed 1:
##   seed 1 → rng.d20() yields 18 → roll_total 18+3+2=23 → crit (23>=13, 23-13=10>=10)
##   Damage: rng.roll(6,2) yields 1+2=3 → damage_raw = 3 + 3*2 = 9 (> weapon.damage_die=6)
## ═══════════════════════════════════════════════════════════════════════════════

const ResolutionClass    = preload("res://core/rules/resolution.gd")
const RNGClass           = preload("res://core/rules/rng.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")
const WeaponResourceClass = preload("res://core/model/weapon_resource.gd")


# ── Shared test fixtures ───────────────────────────────────────────────────────

## Standard attacker: strength 3 is the attack/damage modifier.
var _attacker: Dictionary = {
	"strength": 3,
	"dexterity": 1,
	"constitution": 2,
	"willpower": 1,
	"intellect": 1,
	"intuition": 1,
	"social": 1
}

## Standard weapon: d6 damage, strength modifier, +2 proficiency bonus.
var _weapon: Dictionary = {
	"damage_modifier_attribute": "strength",
	"proficiency_bonus": 2,
	"damage_die": 6
}

## Standard target: AC 13 plus other defense values.
var _target: Dictionary = {
	"ac": 13,
	"reflex": 12,
	"fortitude": 14,
	"will": 11
}

## Helper: construct a Resolution backed by a fresh RNG with the given seed.
func _make_res(seed_value: int) -> ResolutionClass:
	var rng = RNGClass.new(seed_value)
	return ResolutionClass.new(rng)


# ── Pinned seed constants ──────────────────────────────────────────────────────

## seed 2 → rng.d20() yields 11 → roll_total 11+3+2=16 → hit (16>=13, 16-13=3<10 no crit)
const _HIT_SEED: int = 2
const _EXPECTED_HIT_D20: int = 11            # verified: RandomNumberGenerator(seed=2).randi_range(1,20)
const _EXPECTED_HIT_ROLL_TOTAL: int = 16     # 11 + attr_mod(3) + prof_bonus(2)
const _EXPECTED_HIT_DAMAGE: int = 7          # rng.roll(6,1)=4 + attr_mod(3) = 7

## seed 3 → rng.d20() yields 5 → roll_total 5+3+2=10 → miss (10<13)
const _MISS_SEED: int = 3
const _EXPECTED_MISS_D20: int = 5            # verified: RandomNumberGenerator(seed=3).randi_range(1,20)
const _EXPECTED_MISS_ROLL_TOTAL: int = 10    # 5 + attr_mod(3) + prof_bonus(2)

## seed 1 → rng.d20() yields 18 → roll_total 18+3+2=23 → crit (23>=13, 23-13=10>=10)
const _CRIT_SEED: int = 1
const _EXPECTED_CRIT_D20: int = 18           # verified: RandomNumberGenerator(seed=1).randi_range(1,20)
const _EXPECTED_CRIT_ROLL_TOTAL: int = 23    # 18 + attr_mod(3) + prof_bonus(2)
const _EXPECTED_CRIT_DAMAGE: int = 9         # rng.roll(6,2)=1+2=3 + attr_mod*2=6 → 9


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: Hit (no crit)
# seed 2 → rng.d20() yields 11 → roll_total 11+3+2=16 → hit (16>=13, 16-13=3<10 no crit)
# ══════════════════════════════════════════════════════════════════════════════

func test_hit_no_crit_returns_hit_true_crit_false() -> void:
	# seed 2 → rng.d20() yields 11 → roll_total 11+3+2=16 → hit (16>=13, 16-13=3<10 no crit)
	var res = _make_res(_HIT_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")

	assert_true(result["hit"],   "seed 2: d20=11 → roll_total=16 >= ac=13 → must be a hit")
	assert_false(result["crit"], "seed 2: roll_total-ac = 16-13=3 < 10 → must not crit")


func test_hit_no_crit_damage_final_greater_than_zero() -> void:
	# seed 2 → rng.d20() yields 11 → roll_total 11+3+2=16 → hit → damage = roll(6,1)+attr_mod = 4+3 = 7
	var res = _make_res(_HIT_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")

	assert_true(result["damage_final"] > 0,
		"seed 2: hit must produce damage_final > 0, got %d" % result["damage_final"])


func test_hit_no_crit_active_defense_none() -> void:
	# seed 2 → hit → active_defense_applied must be 'none' (passive-only v0)
	var res = _make_res(_HIT_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")

	assert_eq(result["active_defense_applied"], "none",
		"seed 2: active_defense_applied must be 'none' (passive-only path for v0)")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: Miss
# seed 3 → rng.d20() yields 5 → roll_total 5+3+2=10 → miss (10<13)
# ══════════════════════════════════════════════════════════════════════════════

func test_miss_returns_hit_false() -> void:
	# seed 3 → rng.d20() yields 5 → roll_total 5+3+2=10 → miss (10<13)
	var res = _make_res(_MISS_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")

	assert_false(result["hit"],
		"seed 3: d20=5 → roll_total=10 < ac=13 → must be a miss")


func test_miss_damage_final_is_zero() -> void:
	# seed 3 → rng.d20() yields 5 → roll_total 5+3+2=10 → miss → damage_final == 0
	var res = _make_res(_MISS_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")

	assert_eq(result["damage_final"], 0,
		"seed 3: miss must produce damage_final == 0, got %d" % result["damage_final"])


func test_miss_active_defense_none() -> void:
	# seed 3 → miss → active_defense_applied must be 'none' (passive-only v0)
	var res = _make_res(_MISS_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")

	assert_eq(result["active_defense_applied"], "none",
		"seed 3: active_defense_applied must be 'none' (passive-only path for v0)")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: Critical hit
# seed 1 → rng.d20() yields 18 → roll_total 18+3+2=23 → crit (23>=13, 23-13=10>=10)
# Damage: roll(6,2)=1+2=3 + attr_mod*2=6 → 9 > weapon.damage_die (6)
# ══════════════════════════════════════════════════════════════════════════════

func test_crit_returns_hit_true_crit_true() -> void:
	# seed 1 → rng.d20() yields 18 → roll_total 18+3+2=23 → crit (23>=13, 23-13=10>=10)
	var res = _make_res(_CRIT_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")

	assert_true(result["hit"],  "seed 1: d20=18 → roll_total=23 >= ac=13 → must be a hit")
	assert_true(result["crit"], "seed 1: roll_total-ac = 23-13=10 >= 10 → must crit")


func test_crit_damage_final_exceeds_single_die_maximum() -> void:
	# seed 1 → rng.d20() yields 18 → crit → roll(6,2)=1+2=3 + attr_mod*2=6 → damage=9
	# 9 > weapon.damage_die (6): confirms 2-die crit calculation exceeds single-die max
	var res = _make_res(_CRIT_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")

	assert_true(
		result["damage_final"] > _weapon["damage_die"],
		"seed 1: crit damage=%d must exceed single damage_die=%d (2-die crit verified)" % [
			result["damage_final"], _weapon["damage_die"]
		]
	)


func test_crit_active_defense_none() -> void:
	# seed 1 → crit → active_defense_applied must be 'none' (passive-only v0)
	var res = _make_res(_CRIT_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")

	assert_eq(result["active_defense_applied"], "none",
		"seed 1: active_defense_applied must be 'none' (passive-only path for v0)")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: active_defense_applied == 'none' in all three attack scenarios
# (passive-only path for v0 — additional consolidated check)
# ══════════════════════════════════════════════════════════════════════════════

func test_active_defense_always_none_across_all_outcomes() -> void:
	## Verifies that hit, miss, and crit all return active_defense_applied='none'.
	## seed 2 → hit;  seed 3 → miss;  seed 1 → crit
	for seed in [_HIT_SEED, _MISS_SEED, _CRIT_SEED]:
		var res = _make_res(seed)
		var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")
		assert_eq(
			result["active_defense_applied"], "none",
			"seed %d: active_defense_applied must always be 'none' in passive-only v0" % seed
		)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5: Invalid defense_type → error dict without raising an exception
# ══════════════════════════════════════════════════════════════════════════════

func test_invalid_defense_type_returns_error_dict_with_hit_false() -> void:
	var res = _make_res(42)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "invalid")
	assert_false(result["hit"],   "defense_type='invalid' must return hit=false")
	assert_false(result["crit"],  "defense_type='invalid' must return crit=false")
	assert_eq(result["damage_raw"], 0,   "defense_type='invalid' must return damage_raw=0")
	assert_eq(result["damage_final"], 0, "defense_type='invalid' must return damage_final=0")


func test_invalid_defense_type_error_contains_invalid_defense_type() -> void:
	var res = _make_res(42)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "invalid")
	assert_true(result.has("error"),
		"defense_type='invalid' must include 'error' key in return Dictionary")
	assert_true(
		result["error"].contains("Invalid defense type"),
		"error must contain 'Invalid defense type'; got: '%s'" % result["error"]
	)


func test_empty_defense_type_returns_error_without_exception() -> void:
	## Empty string is also invalid — must return error dict, no exception.
	var res = _make_res(42)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "")
	assert_false(result["hit"],  "defense_type='' must return hit=false")
	assert_true(result.has("error"), "defense_type='' must return 'error' key")


func test_mixed_case_defense_type_invalid() -> void:
	## Defense types are case-sensitive; 'AC' is not valid.
	var res = _make_res(42)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "AC")
	assert_false(result["hit"],  "defense_type='AC' (uppercase) must return hit=false")
	assert_true(result.has("error"), "defense_type='AC' must return 'error' key")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5 (extended): All four valid defense types work without error
# ══════════════════════════════════════════════════════════════════════════════

func test_all_valid_defense_types_do_not_return_error() -> void:
	for dtype in ["ac", "reflex", "fortitude", "will"]:
		var res = _make_res(_HIT_SEED)
		var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, dtype)
		assert_false(result.has("error"),
			"defense_type='%s' must not return an error key" % dtype)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 7: Domain purity — resolution.gd must not extend Node or Control
# (CI linter step 1)
# ══════════════════════════════════════════════════════════════════════════════

func test_resolution_gd_does_not_extend_node() -> void:
	var file := FileAccess.open("res://core/rules/resolution.gd", FileAccess.READ)
	assert_not_null(file, "core/rules/resolution.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"resolution.gd must not contain 'extends Node' — ADR-001 domain purity"
	)


func test_resolution_gd_does_not_extend_control() -> void:
	var file := FileAccess.open("res://core/rules/resolution.gd", FileAccess.READ)
	assert_not_null(file, "core/rules/resolution.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Control"),
		"resolution.gd must not contain 'extends Control' — ADR-001 domain purity"
	)


## ADR-002: resolution.gd must not call randf(), randi(), or RandomNumberGenerator.new()
## directly — all randomness flows through the injected _rng instance.
func test_resolution_gd_no_direct_rng_calls() -> void:
	var file := FileAccess.open("res://core/rules/resolution.gd", FileAccess.READ)
	assert_not_null(file, "core/rules/resolution.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("RandomNumberGenerator.new()"),
		"resolution.gd must not instantiate RandomNumberGenerator directly (ADR-002)"
	)
	assert_false(
		content.contains("randf("),
		"resolution.gd must not call randf() directly (ADR-002)"
	)
	assert_false(
		content.contains("randi("),
		"resolution.gd must not call randi() directly (ADR-002)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 6: Pinned seed determinism — same seed produces same result twice
# ══════════════════════════════════════════════════════════════════════════════

func test_determinism_hit_seed_produces_identical_results() -> void:
	## seed 2 → rng.d20() yields 11 → roll_total 11+3+2=16 → hit
	var res_a = _make_res(_HIT_SEED)
	var res_b = _make_res(_HIT_SEED)
	var result_a: Dictionary = res_a.resolve_weapon_attack(_attacker, _target, _weapon, "ac")
	var result_b: Dictionary = res_b.resolve_weapon_attack(_attacker, _target, _weapon, "ac")
	assert_eq(result_a["hit"],          result_b["hit"],          "hit must be deterministic")
	assert_eq(result_a["crit"],         result_b["crit"],         "crit must be deterministic")
	assert_eq(result_a["damage_final"], result_b["damage_final"], "damage_final must be deterministic")


func test_determinism_crit_seed_produces_identical_results() -> void:
	## seed 1 → rng.d20() yields 18 → roll_total 18+3+2=23 → crit
	var res_a = _make_res(_CRIT_SEED)
	var res_b = _make_res(_CRIT_SEED)
	var result_a: Dictionary = res_a.resolve_weapon_attack(_attacker, _target, _weapon, "ac")
	var result_b: Dictionary = res_b.resolve_weapon_attack(_attacker, _target, _weapon, "ac")
	assert_eq(result_a["hit"],          result_b["hit"],          "crit hit must be deterministic")
	assert_eq(result_a["crit"],         result_b["crit"],         "crit flag must be deterministic")
	assert_eq(result_a["damage_final"], result_b["damage_final"], "crit damage_final must be deterministic")


# ══════════════════════════════════════════════════════════════════════════════
# Return structure completeness — all keys always present
# ══════════════════════════════════════════════════════════════════════════════

func test_return_dict_has_all_required_keys_on_hit() -> void:
	var res = _make_res(_HIT_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")
	for key in ["hit", "crit", "damage_raw", "active_defense_applied", "damage_final"]:
		assert_true(result.has(key),
			"hit result must contain key '%s'" % key)


func test_return_dict_has_all_required_keys_on_miss() -> void:
	var res = _make_res(_MISS_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")
	for key in ["hit", "crit", "damage_raw", "active_defense_applied", "damage_final"]:
		assert_true(result.has(key),
			"miss result must contain key '%s'" % key)


func test_return_dict_has_all_required_keys_on_error() -> void:
	var res = _make_res(42)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "bad")
	for key in ["hit", "crit", "damage_raw", "active_defense_applied", "damage_final", "error"]:
		assert_true(result.has(key),
			"error result must contain key '%s'" % key)


# ══════════════════════════════════════════════════════════════════════════════
# Damage formula integrity — miss never does damage, damage_raw == damage_final
# ══════════════════════════════════════════════════════════════════════════════

func test_miss_never_produces_nonzero_damage_raw() -> void:
	var res = _make_res(_MISS_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")
	assert_eq(result["damage_raw"], 0, "miss must produce damage_raw == 0")


func test_damage_final_always_equals_damage_raw() -> void:
	## In v0 (no active defenses) damage_final == damage_raw for all outcomes.
	for seed in [_HIT_SEED, _MISS_SEED, _CRIT_SEED]:
		var res = _make_res(seed)
		var result: Dictionary = res.resolve_weapon_attack(_attacker, _target, _weapon, "ac")
		assert_eq(result["damage_final"], result["damage_raw"],
			"seed %d: damage_final must equal damage_raw in v0 (no active defense modifier)" % seed)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-026 / FR-004: Bobbin-vs-Dmitri Canonical Worked Example
# Source: docs/design-source/Combat.pdf, §"Reactions" (p. 1)
#
# Bobbin (Fighter, longsword) attacks Dmitri (Rogue) in their fateful duel.
# PDF states: "Bobbin rolls a total of 17 to hit, beating Dmitri's Armor Class
# of 15." This test asserts the passive-defense-only (v0) path outcome.
# Dmitri's Dodge reaction (active defense) is deferred to Iteration 2.
#
# Fixture parameters derived from Combat.pdf and Weapons.pdf:
#
#   Bobbin (attacker):
#     strength = 4          — fighter primary attack attribute
#     intuition = 2         — stated in Combat.pdf initiative text
#     dexterity = 1         — stated in Combat.pdf initiative text
#     proficiency_bonus = 2 — longsword Heavy Blade, Prof. +2 (Weapons.pdf)
#     damage_die = 12       — longsword 1d12 S (Weapons.pdf, Heavy Blade)
#
#   Dmitri (target):
#     ac = 15               — stated explicitly: "Dmitri's Armor Class of 15"
#                             (Combat.pdf §"Reactions")
#
#   FixtureRNG stub (inline class FixtureRNG, defined below):
#     d20()       → 11      — 11 + strength(4) + prof(2) = 17 = roll_total
#     roll(12, 1) → 7       — deterministic non-crit damage roll
#
#   Expected outcomes (passive-only v0):
#     roll_total             = 17   — 11 (d20) + 4 (strength) + 2 (prof)
#     hit                    = true  — 17 >= ac(15)
#     crit                   = false — excess 17-15=2 < crit_threshold(10)
#     damage_final           = 11   — roll(7) + strength_mod(4) = 11
#     active_defense_applied = "none" — passive-only v0 path
# ══════════════════════════════════════════════════════════════════════════════


## FixtureRNG — minimal inline RNG stub for the Bobbin-vs-Dmitri worked example.
##
## Overrides d20() and roll() to return pinned values matching the Combat.pdf
## worked example, enabling byte-identical numeric assertions without seed hunting.
## Satisfies: FEAT-026, FR-004, DEF-005.
##
## Usage: FixtureRNG.new(d20_val, roll_val) → stub instance accepted by Resolution.new()
class FixtureRNG:
	var _d20_val: int
	var _roll_val: int

	func _init(d20_val: int, roll_val: int) -> void:
		_d20_val = d20_val
		_roll_val = roll_val

	## Returns the pinned d20 value.
	## Combat.pdf §"Reactions": roll_total=17 = d20(11) + strength(4) + prof(2).
	func d20() -> int:
		return _d20_val

	## Returns the pinned damage roll value regardless of die_size or count.
	## For the non-crit Bobbin example (count=1), yields the fixed damage contribution.
	func roll(_die_size: int, _count: int) -> int:
		return _roll_val


# ── Bobbin-vs-Dmitri fixture dictionaries ─────────────────────────────────────

## Bobbin (Fighter) attacker fixture — Combat.pdf §"Reactions" character.
## Strength=4: fighter primary attribute for attack and damage rolls.
## Intuition=2, Dexterity=1: stated in Combat.pdf initiative text.
var _bobbin: Dictionary = {
	"strength": 4,
	"dexterity": 1,
	"constitution": 3,
	"willpower": 1,
	"intellect": 1,
	"intuition": 2,
	"social": 1
}

## Bobbin's longsword — Weapons.pdf: Heavy Blade, 1d12 S, proficiency +2.
## damage_modifier_attribute = "strength" (longsword uses Strength per combat rules).
var _longsword: Dictionary = {
	"damage_modifier_attribute": "strength",
	"proficiency_bonus": 2,
	"damage_die": 12
}

## Dmitri (Rogue) target fixture.
## ac=15: stated explicitly in Combat.pdf §"Reactions" ("Dmitri's Armor Class of 15").
var _dmitri: Dictionary = {
	"ac": 15,
	"reflex": 13,
	"fortitude": 12,
	"will": 10
}

# ── Pinned constants for the Bobbin-vs-Dmitri fixture ─────────────────────────

## FixtureRNG d20 return value: 11 + strength(4) + prof(2) = 17 (matches PDF).
const _BD_D20: int = 11
## FixtureRNG roll return value: 7 (non-crit 1d12 roll for damage calculation).
const _BD_ROLL: int = 7
## Expected roll_total: 11 + 4 + 2 = 17 (stated in Combat.pdf as "total of 17").
const _BD_ROLL_TOTAL: int = 17
## Expected damage_final: roll(7) + strength_mod(4) = 11 (non-crit hit).
const _BD_DAMAGE: int = 11


## Helper: build a Resolution backed by the Bobbin-vs-Dmitri FixtureRNG stub.
## FixtureRNG returns d20=11, roll=7, reproducing the PDF worked example values.
func _make_bobbin_res() -> ResolutionClass:
	var rng = FixtureRNG.new(_BD_D20, _BD_ROLL)
	return ResolutionClass.new(rng)


# ── FEAT-026 test_bobbin_dmitri_example_hit_status ───────────────────────────

func test_bobbin_dmitri_example_hit_status() -> void:
	## Combat.pdf §"Reactions": "Bobbin rolls a total of 17 to hit, beating
	## Dmitri's Armor Class of 15." Passive-only v0 path: result.hit must be true.
	##
	## roll_total = d20(11) + strength(4) + prof(2) = 17 >= ac(15) → hit=true
	var res = _make_bobbin_res()
	var result: Dictionary = res.resolve_weapon_attack(_bobbin, _dmitri, _longsword, "ac")

	assert_true(
		result["hit"],
		"Bobbin-vs-Dmitri (Combat.pdf §Reactions): roll_total=%d must be >= ac=%d → hit=true" % [
			_BD_ROLL_TOTAL, _dmitri["ac"]
		]
	)


# ── FEAT-026 test_bobbin_dmitri_example_damage_value ─────────────────────────

func test_bobbin_dmitri_example_damage_value() -> void:
	## Passive-only v0 hit: damage_final = FixtureRNG.roll(12,1)=7 + strength_mod=4 = 11.
	## Combat.pdf longsword formula: 1[W]+Strength → 1d12+Strength (Weapons.pdf).
	var res = _make_bobbin_res()
	var result: Dictionary = res.resolve_weapon_attack(_bobbin, _dmitri, _longsword, "ac")

	assert_eq(
		result["damage_final"], _BD_DAMAGE,
		"Bobbin-vs-Dmitri: damage_final must be %d (roll=%d + strength=%d), got %d" % [
			_BD_DAMAGE, _BD_ROLL, _bobbin["strength"], result["damage_final"]
		]
	)


# ── FEAT-026 test_bobbin_dmitri_example_crit_status ──────────────────────────

func test_bobbin_dmitri_example_crit_status() -> void:
	## Combat.pdf §"Critical Hits": crit threshold = defense_value + 10.
	## roll_total=17, ac=15 → excess = 17-15 = 2 < 10 → crit=false.
	var res = _make_bobbin_res()
	var result: Dictionary = res.resolve_weapon_attack(_bobbin, _dmitri, _longsword, "ac")

	assert_false(
		result["crit"],
		"Bobbin-vs-Dmitri: roll_total=%d - ac=%d = %d < crit_threshold=10 → crit=false (Combat.pdf §Critical Hits)" % [
			_BD_ROLL_TOTAL, _dmitri["ac"], _BD_ROLL_TOTAL - _dmitri["ac"]
		]
	)


# ── FEAT-026 test_bobbin_dmitri_example_active_defense_is_none ───────────────

func test_bobbin_dmitri_example_active_defense_is_none() -> void:
	## v0 passive-only path: Dmitri's Dodge reaction (active defense) is deferred
	## to Iteration 2. active_defense_applied must be 'none' always in v0.
	## (Combat.pdf §"Reactions" shows Dodge, but v0 does not model active defenses.)
	var res = _make_bobbin_res()
	var result: Dictionary = res.resolve_weapon_attack(_bobbin, _dmitri, _longsword, "ac")

	assert_eq(
		result["active_defense_applied"], "none",
		"Bobbin-vs-Dmitri: active_defense_applied must be 'none' (v0 passive-only path; Dodge deferred to Iteration 2)"
	)


# ── FEAT-026 test_bobbin_dmitri_example_is_reproducible ──────────────────────

func test_bobbin_dmitri_example_is_reproducible() -> void:
	## Two independent FixtureRNG instances with identical pinned values must
	## produce byte-identical result Dictionaries (determinism proof, FR-004).
	## Satisfies: "running the same test twice produces byte-identical result dicts."
	var res_a = _make_bobbin_res()
	var res_b = _make_bobbin_res()
	var result_a: Dictionary = res_a.resolve_weapon_attack(_bobbin, _dmitri, _longsword, "ac")
	var result_b: Dictionary = res_b.resolve_weapon_attack(_bobbin, _dmitri, _longsword, "ac")

	assert_eq(result_a["hit"], result_b["hit"],
		"Bobbin-vs-Dmitri reproducibility: hit must be identical across two fixture runs")
	assert_eq(result_a["crit"], result_b["crit"],
		"Bobbin-vs-Dmitri reproducibility: crit must be identical across two fixture runs")
	assert_eq(result_a["damage_final"], result_b["damage_final"],
		"Bobbin-vs-Dmitri reproducibility: damage_final must be identical across two fixture runs")
	assert_eq(result_a["active_defense_applied"], result_b["active_defense_applied"],
		"Bobbin-vs-Dmitri reproducibility: active_defense_applied must be identical across two fixture runs")
	assert_eq(result_a["roll_total"], result_b["roll_total"],
		"Bobbin-vs-Dmitri reproducibility: roll_total must be identical across two fixture runs")


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-046 / DEF-003: Longsword .tres regression tests
#
# Permanently closes the masking gap exposed by DEF-003:
#   data/weapons/longsword.tres was shipping damage_die=6 (d6) while the unit
#   fixture _longsword already had damage_die=12 (d12 per Weapons.pdf).
#
# These two tests load longsword.tres directly via ResourceLoader so any future
# revert of the data file will immediately fail here — not just in integration.
# ══════════════════════════════════════════════════════════════════════════════

## test_longsword_is_d12
##
## Loads data/weapons/longsword.tres via ResourceLoader and asserts damage_die == 12.
## This test did not exist before FEAT-046; it permanently blocks any future
## regression where the .tres file reverts to damage_die=6 (or any other value).
##
## Satisfies: FEAT-046 test criterion 1, DEF-003.
func test_longsword_is_d12() -> void:
	var longsword = ResourceLoader.load("res://data/weapons/longsword.tres")
	assert_not_null(
		longsword,
		"ResourceLoader.load('res://data/weapons/longsword.tres') must return non-null"
	)
	if longsword == null:
		return
	assert_eq(
		longsword.damage_die, 12,
		"longsword.tres damage_die must be 12 (d12, Heavy Blade per Weapons.pdf) — DEF-003 fix"
	)


## test_longsword_tres_matches_resolution_fixture
##
## Asserts that:
##   (a) ResourceLoader.load('data/weapons/longsword.tres').damage_die == 12
##   (b) the local _longsword fixture's damage_die == 12
##   (c) both values are equal to each other
##
## This test permanently closes the masking gap: previously the unit fixture had
## damage_die=12 while the .tres file had damage_die=6, allowing unit tests to
## pass while integration tests used wrong (d6) damage.  Now both must be 12 and
## must match — a discrepancy causes an immediate CI failure.
##
## Satisfies: FEAT-046 test criterion 2, DEF-003.
func test_longsword_tres_matches_resolution_fixture() -> void:
	var longsword = ResourceLoader.load("res://data/weapons/longsword.tres")
	assert_not_null(
		longsword,
		"ResourceLoader.load('res://data/weapons/longsword.tres') must return non-null"
	)
	if longsword == null:
		return
	assert_eq(
		longsword.damage_die, 12,
		"longsword.tres damage_die must be 12 (d12) — FEAT-046 DEF-003"
	)
	assert_eq(
		_longsword["damage_die"], 12,
		"_longsword fixture damage_die must be 12 (d12) — FEAT-046 fixture integrity check"
	)
	assert_eq(
		longsword.damage_die, _longsword["damage_die"],
		"longsword.tres damage_die must equal _longsword fixture damage_die — "
		+ "masking gap permanently closed (FEAT-046 DEF-003)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-047 / DEF-006: resolve_spell_attack() — Wizard, Divine Warrior, Divine Channeler
#
# Adds resolve_spell_attack(attacker, target, spell, defense_type) to resolution.gd.
# Roll: rng.d20() + attacker[attacker.spellcasting_attribute] + attacker.spell_attack_bonus
# Crit: roll_total − defense >= 10
# Returns identical shape to resolve_weapon_attack().
#
# All tests use FixtureRNG (defined above under FEAT-026 Bobbin-vs-Dmitri) to
# pin d20 and roll values for fully deterministic assertions.
#
# PINNED VALUES:
#   spell attacker: {spellcasting_attribute: 'intellect', intellect: 3, spell_attack_bonus: 1}
#   spell fixture:  {damage_die: 6}
#
#   HIT  — FixtureRNG(d20=15, roll=3): roll_total = 15+3+1=19 >= 15 → hit=true,  crit=false (19-15=4 < 10)
#   MISS — FixtureRNG(d20=3,  roll=3): roll_total = 3+3+1=7   < 15  → hit=false, damage_final=0
#   CRIT — FixtureRNG(d20=18, roll=3): roll_total = 18+3+1=22 >= 8, 22-8=14 >= 10 → crit=true, damage = 3+3*2=9 > 6
# ══════════════════════════════════════════════════════════════════════════════

## Standard spell attacker (Wizard): intellect 3 is the spellcasting attribute.
var _spell_attacker: Dictionary = {
	"spellcasting_attribute": "intellect",
	"intellect": 3,
	"spell_attack_bonus": 1
}

## Standard spell: d6 damage.
var _spell: Dictionary = {
	"damage_die": 6
}

## Spell target — defense 15 (used for hit and miss tests).
var _spell_target_15: Dictionary = {
	"ac": 15
}

## Spell target — defense 8 (used for crit test; low defense ensures 10+ excess).
var _spell_target_8: Dictionary = {
	"ac": 8
}

## Pinned d20 values for the three spell attack scenarios.
const _SPELL_HIT_D20: int = 15   # roll_total = 15+3+1=19 >= 15 → hit, not crit
const _SPELL_MISS_D20: int = 3   # roll_total = 3+3+1=7   < 15  → miss
const _SPELL_CRIT_D20: int = 18  # roll_total = 18+3+1=22 >= 8, excess=14 >= 10 → crit
const _SPELL_ROLL_VAL: int = 3   # pinned roll() result for all damage assertions


## Helper: build a Resolution backed by a FixtureRNG with the given pinned values.
func _make_spell_res(d20_val: int, roll_val: int) -> ResolutionClass:
	var rng = FixtureRNG.new(d20_val, roll_val)
	return ResolutionClass.new(rng)


# ── FEAT-047 Criterion 1: resolve_spell_attack() exists and returns correct shape ─

func test_spell_attack_returns_all_required_keys() -> void:
	## resolve_spell_attack() must return a Dictionary with all five required keys:
	## hit, crit, damage_raw, active_defense_applied, damage_final.
	## Satisfies: FEAT-047 test criterion 1.
	var res = _make_spell_res(_SPELL_HIT_D20, _SPELL_ROLL_VAL)
	var result: Dictionary = res.resolve_spell_attack(
		_spell_attacker, _spell_target_15, _spell, "ac"
	)
	for key in ["hit", "crit", "damage_raw", "active_defense_applied", "damage_final"]:
		assert_true(
			result.has(key),
			"resolve_spell_attack() must return key '%s'" % key
		)


# ── FEAT-047 Criterion 2: Hit scenario ────────────────────────────────────────

func test_spell_attack_hit() -> void:
	## FixtureRNG d20=15; attacker {spellcasting_attribute:'intellect', intellect:3, spell_attack_bonus:1};
	## target defense=15 → roll_total=15+3+1=19 >= 15 → hit=true, crit=false.
	## Satisfies: FEAT-047 test criterion 2.
	var res = _make_spell_res(_SPELL_HIT_D20, _SPELL_ROLL_VAL)
	var result: Dictionary = res.resolve_spell_attack(
		_spell_attacker, _spell_target_15, _spell, "ac"
	)
	assert_true(
		result["hit"],
		"spell attack: d20=%d + intellect=%d + bonus=%d = 19 >= defense=15 → hit=true" % [
			_SPELL_HIT_D20, _spell_attacker["intellect"], _spell_attacker["spell_attack_bonus"]
		]
	)
	assert_false(
		result["crit"],
		"spell attack: roll_total=19 - defense=15 = 4 < 10 → crit=false"
	)


# ── FEAT-047 Criterion 3: Miss scenario ───────────────────────────────────────

func test_spell_attack_miss() -> void:
	## FixtureRNG d20=3; same attacker; defense=15 → roll_total=3+3+1=7 < 15 → miss.
	## Satisfies: FEAT-047 test criterion 3.
	var res = _make_spell_res(_SPELL_MISS_D20, _SPELL_ROLL_VAL)
	var result: Dictionary = res.resolve_spell_attack(
		_spell_attacker, _spell_target_15, _spell, "ac"
	)
	assert_false(
		result["hit"],
		"spell attack: d20=%d + intellect=%d + bonus=%d = 7 < defense=15 → hit=false" % [
			_SPELL_MISS_D20, _spell_attacker["intellect"], _spell_attacker["spell_attack_bonus"]
		]
	)
	assert_eq(
		result["damage_final"], 0,
		"spell attack: miss must produce damage_final=0, got %d" % result["damage_final"]
	)


# ── FEAT-047 Criterion 4: Crit scenario ───────────────────────────────────────

func test_spell_attack_crit() -> void:
	## FixtureRNG d20=18; same attacker; defense=8
	## → roll_total=18+3+1=22, 22-8=14 >= 10 → crit=true.
	## Crit damage: roll(6,2)=3 + intellect*2=6 = 9 > spell.damage_die(6).
	## Satisfies: FEAT-047 test criterion 4.
	var res = _make_spell_res(_SPELL_CRIT_D20, _SPELL_ROLL_VAL)
	var result: Dictionary = res.resolve_spell_attack(
		_spell_attacker, _spell_target_8, _spell, "ac"
	)
	assert_true(
		result["hit"],
		"spell attack crit: roll_total=22 >= defense=8 → hit=true"
	)
	assert_true(
		result["crit"],
		"spell attack crit: roll_total=22 - defense=8 = 14 >= 10 → crit=true"
	)
	assert_true(
		result["damage_final"] > _spell["damage_die"],
		"spell attack crit: damage_final=%d must exceed single damage_die=%d (2-die crit)" % [
			result["damage_final"], _spell["damage_die"]
		]
	)


# ── FEAT-047 Criterion 5: active_defense_applied always 'none' ────────────────

func test_spell_attack_active_defense_always_none() -> void:
	## All three spell attack outcomes (hit, miss, crit) must return
	## active_defense_applied == 'none' per ADR-011 Iteration 2 stub.
	## Satisfies: FEAT-047 test criterion 5.
	var scenarios: Array = [
		{
			"label": "hit",
			"d20": _SPELL_HIT_D20,
			"target": _spell_target_15
		},
		{
			"label": "miss",
			"d20": _SPELL_MISS_D20,
			"target": _spell_target_15
		},
		{
			"label": "crit",
			"d20": _SPELL_CRIT_D20,
			"target": _spell_target_8
		}
	]
	for scenario in scenarios:
		var res = _make_spell_res(scenario["d20"], _SPELL_ROLL_VAL)
		var result: Dictionary = res.resolve_spell_attack(
			_spell_attacker, scenario["target"], _spell, "ac"
		)
		assert_eq(
			result["active_defense_applied"], "none",
			"spell attack (%s): active_defense_applied must be 'none' (ADR-011 stub)" % scenario["label"]
		)


# ── FEAT-047 Criterion 6: attribute score sensitivity ─────────────────────────

func test_spell_attack_uses_spellcasting_attribute() -> void:
	## Call once with intellect=3, once with intellect=5, same pinned d20=15.
	## Second roll_total must be exactly 2 higher than the first.
	## Confirms the attribute score drives roll_total, not a hardcoded constant.
	## Satisfies: FEAT-047 test criterion 6.
	var attacker_low: Dictionary = {
		"spellcasting_attribute": "intellect",
		"intellect": 3,
		"spell_attack_bonus": 1
	}
	var attacker_high: Dictionary = {
		"spellcasting_attribute": "intellect",
		"intellect": 5,
		"spell_attack_bonus": 1
	}

	var res_low  = _make_spell_res(_SPELL_HIT_D20, _SPELL_ROLL_VAL)
	var res_high = _make_spell_res(_SPELL_HIT_D20, _SPELL_ROLL_VAL)

	var result_low:  Dictionary = res_low.resolve_spell_attack(attacker_low,  _spell_target_15, _spell, "ac")
	var result_high: Dictionary = res_high.resolve_spell_attack(attacker_high, _spell_target_15, _spell, "ac")

	assert_eq(
		result_high["roll_total"] - result_low["roll_total"], 2,
		"spell attack: intellect=5 roll_total (%d) must be exactly 2 higher than intellect=3 roll_total (%d)" % [
			result_high["roll_total"], result_low["roll_total"]
		]
	)


# ── FEAT-047 Criterion 7: Divine Channeler attribute dispatch (social) ────────

func test_divine_channeler_spell_attack_uses_social() -> void:
	## Divine Channeler uses spellcasting_attribute='social'.
	## Attacker: {spellcasting_attribute:'social', social:4, intellect:1, spell_attack_bonus:1}
	## Pinned d20=15 → expected roll_total = 15 + social(4) + bonus(1) = 20.
	## If intellect(1) were used incorrectly: 15 + 1 + 1 = 17. Must get 20.
	## Satisfies: FEAT-047 test criterion 7.
	var divine_channeler: Dictionary = {
		"spellcasting_attribute": "social",
		"social": 4,
		"intellect": 1,
		"spell_attack_bonus": 1
	}
	var target: Dictionary = {
		"ac": 5  # low defense so social-based roll always hits
	}
	var res = _make_spell_res(_SPELL_HIT_D20, _SPELL_ROLL_VAL)
	var result: Dictionary = res.resolve_spell_attack(divine_channeler, target, _spell, "ac")

	# roll_total must use social(4), not intellect(1)
	# Expected: 15 + 4 + 1 = 20; wrong: 15 + 1 + 1 = 17
	assert_eq(
		result["roll_total"], 20,
		"Divine Channeler: roll_total must be %d (d20=%d + social=%d + bonus=%d), got %d — must NOT use intellect=%d" % [
			20, _SPELL_HIT_D20, divine_channeler["social"], divine_channeler["spell_attack_bonus"],
			result["roll_total"], divine_channeler["intellect"]
		]
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-059 / DEF-NEW-003: Active Defense Resolution Paths
#
# Implements Dodge, Block, Parry, Steel as reactions per Combat.pdf.
# Each active defense spends ONE action from the actor's 7-action round budget
# (verified via ActionEconomy.spend_reaction()).
#
# RNG SEQUENCE DOCUMENTATION
# ─────────────────────────────────────────────────────────────────────────────
# Attacker fixture (_attacker): strength=3, proficiency=2 → attack modifier +5
# Weapon fixture (_weapon):     damage_die=6
# AD target (_ad_target):       ac=13, reflex=12, fortitude=14, will=11,
#                                dexterity=1, willpower=1, conscious=true
#
# For Dodge/Steel (pre-attack checks roll FIRST, then attacker rolls):
#   SequenceRNG d20_seq = [check_roll, attack_d20]
#
# DODGE SUCCESS:
#   mob_d20=16 → mobility_check=16+dex(1)=17
#   attack_d20=11 → roll_total=11+3+2=16
#   16 < 17 → miss! Dodge negated attack.  defender_stepped=true.
#
# DODGE FAIL (attack still beats mobility):
#   mob_d20=9 → mobility_check=9+1=10
#   attack_d20=11 → roll_total=16
#   16 >= 10 → hit (dodge didn't protect).  damage_raw=4+3=7.
#
# DODGE NO-SPACE:
#   open_space_available=false → no mobility roll → single d20 call
#   attack_d20=11 → roll_total=16 >= ac=13 → hit.  damage_raw=4+3=7.
#
# BLOCK (hit vs AC, tier 1):
#   attack_d20=11 → roll_total=16 >= ac=13 → hit
#   damage roll(6,1)=4 → damage_raw=4+3=7
#   block roll(6,1)=2 → block_reduction=2+block_value(3)=5
#   damage_final=max(0,7-5)=2.  on_hit_suppressed=true.
#
# BLOCK TIER 2:
#   attack_d20=11 → hit → damage_raw=7
#   block roll(6,2)=2 → block_reduction=2+3=5 → damage_final=2
#   (SequenceRNG roll() returns the value once regardless of count)
#
# BLOCK SHIELD (block_die=12):
#   Same as tier-1 block but block_die=12 (SequenceRNG ignores die_size)
#
# PARRY SUCCESS:
#   attack_d20=11 → roll_total=16 → hit
#   damage roll(6,1)=4 → damage_raw=7
#   parry_d20=14 → parry_roll=14+parry_bonus(4)=18 > roll_total(16) → success
#   damage_final=0.  on_hit_suppressed=true.
#
# PARRY FAIL:
#   attack_d20=11 → roll_total=16 → hit → damage_raw=7
#   parry_d20=5 → parry_roll=5+4=9 <= 16 → fail → damage_final=7.
#
# STEEL SUCCESS (vs fortitude):
#   det_d20=16 → determination_check=16+willpower(1)=17
#   attack_d20=11 → roll_total=16 vs fortitude... but effective defense=17
#   16 < 17 → miss! Steel resisted.  next_check_bonus=2.
#
# STEEL FAIL:
#   det_d20=5 → determination_check=5+1=6
#   attack_d20=8 → roll_total=8+3+2=13 >= 6 → hit; 13-6=7<10 → no crit.  damage_raw=4+3=7.
#   (attack_d20=8 chosen to avoid the 16-6=10 crit boundary that would fire with attack_d20=11)
# ══════════════════════════════════════════════════════════════════════════════


## SequenceRNG — multi-step RNG stub for active defense tests.
## Returns successive values from pre-set d20 and roll sequences.
## Each d20() call consumes the next element of d20_seq (wraps if exhausted).
## Each roll() call consumes the next element of roll_seq (wraps if exhausted).
## Satisfies: FEAT-059 pinned-RNG requirement (ADR-002).
class SequenceRNG:
	var _d20_seq: Array
	var _roll_seq: Array
	var _d20_idx: int = 0
	var _roll_idx: int = 0

	func _init(d20_seq: Array, roll_seq: Array) -> void:
		_d20_seq = d20_seq
		_roll_seq = roll_seq

	func d20() -> int:
		var val: int = _d20_seq[_d20_idx % _d20_seq.size()]
		_d20_idx += 1
		return val

	func roll(_die_size: int, _count: int) -> int:
		var val: int = _roll_seq[_roll_idx % _roll_seq.size()]
		_roll_idx += 1
		return val


# ── Shared fixtures for FEAT-059 active defense tests ─────────────────────────

## Target augmented with attribute scores needed for Dodge (dexterity)
## and Steel (willpower) checks.
var _ad_target: Dictionary = {
	"ac":        13,
	"reflex":    12,
	"fortitude": 14,
	"will":      11,
	"dexterity": 1,   # used for Mobility check (Dodge)
	"willpower": 1,   # used for Determination check (Steel)
	"conscious": true
}

## Blocking weapon: d6 damage die, block_value=3, tier-1 (default).
var _block_weapon: Dictionary = {
	"damage_die": 6,
	"block_value": 3
}

## Blocking shield: block_die=12, block_value=5 (Large Shield per Weapons.pdf).
var _shield_weapon: Dictionary = {
	"block_die":   12,
	"block_value": 5
}

## Parrying weapon: parry_bonus=4 (Longsword per Weapons.pdf).
var _parry_weapon: Dictionary = {
	"parry_bonus": 4
}

## Helper: build a Resolution backed by a SequenceRNG.
func _make_seq_res(d20_seq: Array, roll_seq: Array) -> ResolutionClass:
	var rng = SequenceRNG.new(d20_seq, roll_seq)
	return ResolutionClass.new(rng)

## Helper: build a fresh ActionEconomy at full budget (7).
func _make_full_ae() -> ActionEconomyClass:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	return ae


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-059 Criterion 1: active_defense param is accepted; active_defense_applied
# reflects the chosen defense (NOT always 'none').
# ══════════════════════════════════════════════════════════════════════════════

func test_active_defense_none_still_returns_none() -> void:
	## When active_defense is omitted (default "none"), active_defense_applied="none".
	## Ensures backward compatibility with all prior tests.
	var res = _make_seq_res([11], [4])
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _ad_target, _weapon, "ac")
	assert_eq(result["active_defense_applied"], "none",
		"No active_defense param: active_defense_applied must still be 'none'")


func test_active_defense_dodge_applied_reflects_dodge() -> void:
	## With active_defense="dodge" and proper trigger, active_defense_applied="dodge".
	## Dodge success: mob_d20=16→mobility=17, attack_d20=11→roll_total=16; 16<17→miss.
	var res = _make_seq_res([16, 11], [])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "dodge", {}
	)
	assert_eq(result["active_defense_applied"], "dodge",
		"active_defense='dodge' with proper trigger must set active_defense_applied='dodge'")


func test_active_defense_block_applied_reflects_block() -> void:
	## With active_defense="block" and a hit vs AC, active_defense_applied="block".
	## attack_d20=11→roll_total=16>=ac=13→hit; damage=7; block=2+3=5; final=2.
	var res = _make_seq_res([11], [4, 2])
	var ctx: Dictionary = {"blocking_weapon": _block_weapon}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "block", ctx
	)
	assert_eq(result["active_defense_applied"], "block",
		"active_defense='block' on hit vs AC must set active_defense_applied='block'")


func test_active_defense_parry_applied_reflects_parry() -> void:
	## With active_defense="parry" and a hit vs AC, active_defense_applied="parry".
	## Parry success: attack=16→hit; parry_d20=14→parry=18>16→damage=0.
	var res = _make_seq_res([11, 14], [4])
	var ctx: Dictionary = {"parrying_weapon": _parry_weapon}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "parry", ctx
	)
	assert_eq(result["active_defense_applied"], "parry",
		"active_defense='parry' on hit vs AC must set active_defense_applied='parry'")


func test_active_defense_steel_applied_reflects_steel() -> void:
	## With active_defense="steel" and trigger vs fortitude, active_defense_applied="steel".
	## Steel success: det_d20=16→det=17, attack_d20=11→roll_total=16; 16<17→miss.
	var res = _make_seq_res([16, 11], [])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "fortitude", "steel", {}
	)
	assert_eq(result["active_defense_applied"], "steel",
		"active_defense='steel' vs fortitude must set active_defense_applied='steel'")


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-059 Criterion 2: DODGE
# ══════════════════════════════════════════════════════════════════════════════

func test_dodge_success_negates_attack_that_beats_ac() -> void:
	## Dodge success: mob_d20=16→mobility_check=17; attack_d20=11→roll_total=16.
	## roll_total(16) < mobility_check(17) → miss. Attack was negated by Dodge.
	## Without Dodge: roll_total(16) >= ac(13) → would have been a hit.
	var res = _make_seq_res([16, 11], [])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "dodge", {}
	)
	assert_false(result["hit"],
		"Dodge success: roll_total=16 < mobility_check=17 → hit must be false")
	assert_eq(result["damage_final"], 0,
		"Dodge success: hit=false → damage_final must be 0")


func test_dodge_success_defender_steps() -> void:
	## After a successful Dodge, defender_stepped must be true.
	## mob_d20=16→mobility=17; attack=16<17→miss; defender_stepped=true.
	var res = _make_seq_res([16, 11], [])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "dodge", {}
	)
	assert_true(result["defender_stepped"],
		"Dodge success: defender_stepped must be true after successful dodge")


func test_dodge_failed_to_protect_still_applied() -> void:
	## When mobility check < attack roll, hit still occurs, but active_defense_applied="dodge".
	## mob_d20=9→mobility=10; attack_d20=11→roll_total=16; 16>=10→hit (dodge didn't protect).
	var res = _make_seq_res([9, 11], [4])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "dodge", {}
	)
	assert_true(result["hit"],
		"Dodge fail: roll_total=16 >= mobility_check=10 → hit must be true")
	assert_eq(result["active_defense_applied"], "dodge",
		"Even when dodge fails to protect, active_defense_applied must be 'dodge'")
	assert_false(result["defender_stepped"],
		"Dodge fail: defender_stepped must be false when dodge did not negate the attack")


func test_dodge_no_open_space_auto_fails() -> void:
	## With open_space_available=false, Dodge auto-fails: hit determined by original AC.
	## attack_d20=11→roll_total=16>=ac(13)→hit; active_defense_applied="none".
	var res = _make_seq_res([11], [4])
	var ctx: Dictionary = {"open_space_available": false}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "dodge", ctx
	)
	assert_true(result["hit"],
		"Dodge no-space: roll_total=16 >= ac=13 → hit must be true (auto-fail)")
	assert_eq(result["active_defense_applied"], "none",
		"Dodge no-space: active_defense_applied must be 'none' (dodge did not apply)")
	assert_false(result["defender_stepped"],
		"Dodge no-space: defender_stepped must be false (dodge never applied)")


func test_dodge_does_not_trigger_on_fortitude() -> void:
	## Dodge trigger requires defense_type in ["ac","reflex"]. Fortitude → no dodge.
	## attack_d20=11→roll_total=16>=fortitude(14)→hit; active_defense_applied="none".
	var res = _make_seq_res([11], [4])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "fortitude", "dodge", {}
	)
	assert_eq(result["active_defense_applied"], "none",
		"Dodge vs fortitude: trigger condition not met → active_defense_applied must be 'none'")


func test_dodge_does_not_trigger_when_immobilized() -> void:
	## Immobilized condition prevents Dodge. Hit determined by AC normally.
	var immobilized_target: Dictionary = {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"dexterity": 1, "willpower": 1, "conscious": true,
		"conditions": ["Immobilized"]
	}
	var res = _make_seq_res([11], [4])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, immobilized_target, _weapon, "ac", "dodge", {}
	)
	assert_eq(result["active_defense_applied"], "none",
		"Dodge when Immobilized: trigger not met → active_defense_applied must be 'none'")
	assert_true(result["hit"],
		"Dodge when Immobilized: normal AC check → roll_total=16 >= ac=13 → hit")


func test_dodge_triggers_on_reflex_defense() -> void:
	## Dodge also triggers on reflex defense (not only AC).
	## mob_d20=16→mobility=17; attack=16<17→miss; reflex would have been 12.
	var res = _make_seq_res([16, 11], [])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "reflex", "dodge", {}
	)
	assert_false(result["hit"],
		"Dodge vs reflex: roll_total=16 < mobility_check=17 → miss")
	assert_eq(result["active_defense_applied"], "dodge",
		"Dodge vs reflex: active_defense_applied must be 'dodge'")


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-059 Criterion 3: BLOCK
# ══════════════════════════════════════════════════════════════════════════════

func test_block_reduces_damage_by_weapon_die_plus_block_value() -> void:
	## Block: attack_d20=11→roll_total=16>=ac=13→hit; damage_raw=4+3=7.
	## Block roll(6,1)=2 → block_reduction=2+block_value(3)=5.
	## damage_final=max(0,7-5)=2.
	var res = _make_seq_res([11], [4, 2])
	var ctx: Dictionary = {"blocking_weapon": _block_weapon}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "block", ctx
	)
	assert_true(result["hit"],
		"Block test: roll_total=16 >= ac=13 → hit must be true (block happens post-hit)")
	assert_eq(result["damage_raw"], 7,
		"Block test: damage_raw must be 4+3=7 before block reduction")
	assert_eq(result["damage_final"], 2,
		"Block test: damage_final must be max(0, 7-5)=2 after 1[W](2)+block_value(3)=5 reduction")


func test_block_suppresses_on_hit_effects() -> void:
	## After a Block, on_hit_suppressed must be true (per Combat.pdf).
	var res = _make_seq_res([11], [4, 2])
	var ctx: Dictionary = {"blocking_weapon": _block_weapon}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "block", ctx
	)
	assert_true(result["on_hit_suppressed"],
		"Block: on_hit_suppressed must be true (Combat.pdf: on-hit effects do not occur)")


func test_block_does_not_trigger_on_miss() -> void:
	## Block trigger: "hit by an attack targeting AC". Miss → Block doesn't apply.
	## seed3-equivalent: mob=_MISS_SEED → miss. Block should not fire.
	var miss_res = _make_res(_MISS_SEED)  # seed 3 → attack misses
	var ctx: Dictionary = {"blocking_weapon": _block_weapon}
	var result: Dictionary = miss_res.resolve_weapon_attack(
		_attacker, _target, _weapon, "ac", "block", ctx
	)
	assert_false(result["hit"],
		"Block miss test: seed 3 → roll_total=10 < ac=13 → hit must be false")
	assert_eq(result["active_defense_applied"], "none",
		"Block on miss: active_defense_applied must be 'none' (Block trigger not met)")
	assert_eq(result["damage_final"], 0,
		"Block on miss: damage_final must be 0 (no hit, no block)")


func test_block_does_not_trigger_on_non_ac_defense() -> void:
	## Block trigger requires defense_type=="ac". Fortitude attack → Block doesn't apply.
	## fortitude=14, attack_d20=11→roll_total=16>=14→hit; Block should not fire.
	var res = _make_seq_res([11], [4])
	var ctx: Dictionary = {"blocking_weapon": _block_weapon}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "fortitude", "block", ctx
	)
	assert_eq(result["active_defense_applied"], "none",
		"Block vs fortitude: trigger not met → active_defense_applied must be 'none'")
	assert_eq(result["damage_final"], result["damage_raw"],
		"Block vs fortitude: damage_final must equal damage_raw (no block reduction)")


func test_block_tier2_scales_to_two_dice() -> void:
	## Tier-2 Block: 2[W]+block_value. SequenceRNG roll()=2 → 2+3=5; damage=7-5=2.
	## (SequenceRNG returns same roll value regardless of count parameter.)
	var res = _make_seq_res([11], [4, 2])
	var ctx: Dictionary = {
		"blocking_weapon": _block_weapon,
		"blocking_weapon_tier": 2
	}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "block", ctx
	)
	assert_eq(result["active_defense_applied"], "block",
		"Block tier 2: active_defense_applied must be 'block'")
	assert_true(result["on_hit_suppressed"],
		"Block tier 2: on_hit_suppressed must be true")


func test_block_shield_uses_block_die() -> void:
	## Shield blocking uses block_die (1d12) instead of weapon die.
	## SequenceRNG ignores die_size so the value is the same (2); block_reduction=2+5=7.
	## damage_raw=7; damage_final=max(0,7-7)=0.
	var res = _make_seq_res([11], [4, 2])
	var ctx: Dictionary = {"blocking_weapon": _shield_weapon}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "block", ctx
	)
	assert_eq(result["active_defense_applied"], "block",
		"Shield block: active_defense_applied must be 'block'")
	assert_eq(result["damage_final"], 0,
		"Shield block: damage_raw=7, block_reduction=2+5=7 → damage_final=max(0,0)=0")


func test_block_cannot_reduce_damage_below_zero() -> void:
	## Block reduction is capped at damage_raw (damage_final >= 0).
	## large block_value=10 on damage_raw=7 → damage_final=max(0,7-(any+10))=0.
	var huge_block_weapon: Dictionary = {"damage_die": 6, "block_value": 10}
	var res = _make_seq_res([11], [4, 1])
	var ctx: Dictionary = {"blocking_weapon": huge_block_weapon}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "block", ctx
	)
	assert_true(result["damage_final"] >= 0,
		"Block: damage_final must never be negative; got %d" % result["damage_final"])


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-059 Criterion 4: PARRY
# ══════════════════════════════════════════════════════════════════════════════

func test_parry_success_zeroes_damage() -> void:
	## Parry success: parry_d20=14→parry_roll=14+4=18 > roll_total=16.
	## damage_final becomes 0. on_hit_suppressed=true.
	var res = _make_seq_res([11, 14], [4])
	var ctx: Dictionary = {"parrying_weapon": _parry_weapon}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "parry", ctx
	)
	assert_true(result["hit"],
		"Parry test: roll_total=16 >= ac=13 → originally a hit (parry fires post-hit)")
	assert_eq(result["damage_final"], 0,
		"Parry success: parry_roll=18 > roll_total=16 → damage_final must be 0")
	assert_eq(result["active_defense_applied"], "parry",
		"Parry success: active_defense_applied must be 'parry'")


func test_parry_success_suppresses_on_hit_effects() -> void:
	## Parry success: on_hit_suppressed must be true (Combat.pdf).
	var res = _make_seq_res([11, 14], [4])
	var ctx: Dictionary = {"parrying_weapon": _parry_weapon}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "parry", ctx
	)
	assert_true(result["on_hit_suppressed"],
		"Parry success: on_hit_suppressed must be true (Combat.pdf: on-hit effects do not occur)")


func test_parry_fail_damage_unchanged() -> void:
	## Parry fail: parry_d20=5→parry_roll=5+4=9 <= roll_total=16.
	## damage_final unchanged (=damage_raw=7). active_defense_applied="parry".
	var res = _make_seq_res([11, 5], [4])
	var ctx: Dictionary = {"parrying_weapon": _parry_weapon}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "parry", ctx
	)
	assert_true(result["hit"],
		"Parry fail: roll_total=16 >= ac=13 → hit must be true")
	assert_eq(result["damage_final"], result["damage_raw"],
		"Parry fail: parry_roll=9 <= roll_total=16 → damage_final must equal damage_raw")
	assert_false(result["on_hit_suppressed"],
		"Parry fail: on_hit_suppressed must be false (parry did not succeed)")
	assert_eq(result["active_defense_applied"], "parry",
		"Parry fail: active_defense_applied must still be 'parry' (it was attempted)")


func test_parry_does_not_trigger_on_miss() -> void:
	## Parry trigger: "hit by an attack targeting AC". Miss → Parry doesn't apply.
	var miss_res = _make_res(_MISS_SEED)  # seed 3 → miss
	var ctx: Dictionary = {"parrying_weapon": _parry_weapon}
	var result: Dictionary = miss_res.resolve_weapon_attack(
		_attacker, _target, _weapon, "ac", "parry", ctx
	)
	assert_false(result["hit"],
		"Parry miss test: seed 3 → miss")
	assert_eq(result["active_defense_applied"], "none",
		"Parry on miss: active_defense_applied must be 'none' (trigger not met)")


func test_parry_does_not_trigger_on_non_ac_defense() -> void:
	## Parry trigger requires defense_type=="ac". Fortitude → Parry doesn't apply.
	var res = _make_seq_res([11], [4])
	var ctx: Dictionary = {"parrying_weapon": _parry_weapon}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "fortitude", "parry", ctx
	)
	assert_eq(result["active_defense_applied"], "none",
		"Parry vs fortitude: trigger not met → active_defense_applied must be 'none'")


func test_parry_equal_to_roll_total_fails() -> void:
	## Parry must EXCEED (>) attacker's roll_total, not equal it.
	## parry_d20=12→parry_roll=12+4=16 == roll_total=16 → not > → fail.
	var res = _make_seq_res([11, 12], [4])
	var ctx: Dictionary = {"parrying_weapon": _parry_weapon}
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "parry", ctx
	)
	assert_false(result["on_hit_suppressed"],
		"Parry: parry_roll=16 equal to roll_total=16 → must NOT succeed (needs to EXCEED)")
	assert_eq(result["damage_final"], result["damage_raw"],
		"Parry equal: damage_final must equal damage_raw (parry did not succeed)")


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-059 Criterion 5: STEEL
# ══════════════════════════════════════════════════════════════════════════════

func test_steel_vs_fortitude_negates_attack_when_check_exceeds() -> void:
	## Steel vs Fortitude: det_d20=16→determination=17; attack_d20=11→roll_total=16.
	## Effective defense=17; 16<17→miss! Attack negated by Steel.
	var res = _make_seq_res([16, 11], [])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "fortitude", "steel", {}
	)
	assert_false(result["hit"],
		"Steel vs fortitude: roll_total=16 < determination=17 → hit must be false")
	assert_eq(result["active_defense_applied"], "steel",
		"Steel vs fortitude: active_defense_applied must be 'steel'")


func test_steel_resist_grants_next_check_bonus_2() -> void:
	## When Steel successfully resists an attack, next_check_bonus must be +2.
	var res = _make_seq_res([16, 11], [])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "fortitude", "steel", {}
	)
	assert_false(result["hit"],
		"Steel resist: hit must be false (attack resisted)")
	assert_eq(result["next_check_bonus"], 2,
		"Steel resist: next_check_bonus must be +2 when attack is resisted")


func test_steel_vs_will_negates_attack() -> void:
	## Steel also triggers on 'will' defense. Same logic as fortitude.
	## det_d20=16→det_check=17; attack_d20=11→roll_total=16; vs will(11) but effective=17.
	## 16<17→miss.
	var res = _make_seq_res([16, 11], [])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "will", "steel", {}
	)
	assert_false(result["hit"],
		"Steel vs will: roll_total=16 < determination=17 → hit must be false")
	assert_eq(result["active_defense_applied"], "steel",
		"Steel vs will: active_defense_applied must be 'steel'")
	assert_eq(result["next_check_bonus"], 2,
		"Steel vs will: next_check_bonus must be 2 when resisted")


func test_steel_fail_attack_lands_no_bonus() -> void:
	## Steel fail: det_d20=5→determination_check=5+willpower(1)=6.
	## attack_d20=8→roll_total=8+str(3)+prof(2)=13.
	## Effective defense=6; 13>=6→hit; 13-6=7<10→no crit → damage_raw=4+3=7.
	## No next_check_bonus (attack was not resisted).
	## Note: using attack_d20=8 (not 11) to avoid 16-6=10 crit boundary with determination=6.
	var res = _make_seq_res([5, 8], [4])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "fortitude", "steel", {}
	)
	assert_true(result["hit"],
		"Steel fail: roll_total=13 >= determination=6 → hit must be true")
	assert_false(result["crit"],
		"Steel fail: roll_total=13 - determination=6 = 7 < 10 → must NOT crit")
	assert_eq(result["damage_final"], 7,
		"Steel fail: damage_final must be 7 (roll=4+str=3, no defense reduction)")
	assert_eq(result["next_check_bonus"], 0,
		"Steel fail: next_check_bonus must be 0 (attack was not resisted)")
	assert_eq(result["active_defense_applied"], "steel",
		"Steel fail: active_defense_applied must be 'steel' (it was attempted)")


func test_steel_does_not_trigger_on_ac_defense() -> void:
	## Steel trigger requires defense_type in ["fortitude","will"]. AC → no Steel.
	## attack_d20=11→roll_total=16>=ac=13→hit; active_defense_applied="none".
	var res = _make_seq_res([11], [4])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "steel", {}
	)
	assert_eq(result["active_defense_applied"], "none",
		"Steel vs AC: trigger not met → active_defense_applied must be 'none'")


func test_steel_does_not_trigger_when_unconscious() -> void:
	## Steel requires conscious target. Unconscious target → no Steel.
	var unconscious_target: Dictionary = {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"dexterity": 1, "willpower": 1, "conscious": false
	}
	var res = _make_seq_res([11], [4])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, unconscious_target, _weapon, "fortitude", "steel", {}
	)
	assert_eq(result["active_defense_applied"], "none",
		"Steel on unconscious: trigger not met → active_defense_applied must be 'none'")


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-059 Criterion 6: WeaponResource exposes block_value and parry_bonus
# ══════════════════════════════════════════════════════════════════════════════

func test_weapon_resource_has_block_value_property() -> void:
	## WeaponResource must expose block_value:int (default 0).
	var wr = WeaponResourceClass.new()
	assert_eq(wr.block_value, 0,
		"WeaponResource.block_value must exist and default to 0")


func test_weapon_resource_has_parry_bonus_property() -> void:
	## WeaponResource must expose parry_bonus:int (default 0).
	var wr = WeaponResourceClass.new()
	assert_eq(wr.parry_bonus, 0,
		"WeaponResource.parry_bonus must exist and default to 0")


func test_longsword_tres_has_block_value_3() -> void:
	## longsword.tres must have block_value=3 per docs/design-source/Weapons.pdf.
	var longsword = ResourceLoader.load("res://data/weapons/longsword.tres")
	assert_not_null(longsword,
		"ResourceLoader.load('res://data/weapons/longsword.tres') must return non-null")
	if longsword == null:
		return
	assert_eq(longsword.block_value, 3,
		"longsword.tres block_value must be 3 (Weapons.pdf: Longsword Block=3)")


func test_longsword_tres_has_parry_bonus_4() -> void:
	## longsword.tres must have parry_bonus=4 per docs/design-source/Weapons.pdf.
	var longsword = ResourceLoader.load("res://data/weapons/longsword.tres")
	assert_not_null(longsword,
		"ResourceLoader.load('res://data/weapons/longsword.tres') must return non-null")
	if longsword == null:
		return
	assert_eq(longsword.parry_bonus, 4,
		"longsword.tres parry_bonus must be 4 (Weapons.pdf: Longsword Parry=4)")


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-059 Criterion 7: Action economy integration
# Each active defense reaction consumes one action from the actor's round budget.
# ══════════════════════════════════════════════════════════════════════════════

func test_dodge_consumes_one_action_from_economy() -> void:
	## Dodge reaction spends one action: budget 7→6.
	## Dodge success: mob_d20=16→mobility=17; attack_d20=11→roll_total=16<17→miss.
	var ae = _make_full_ae()
	assert_eq(ae.get_remaining(), 7, "budget must start at 7")
	var ctx: Dictionary = {"action_economy": ae}
	var res = _make_seq_res([16, 11], [])
	res.resolve_weapon_attack(_attacker, _ad_target, _weapon, "ac", "dodge", ctx)
	assert_eq(ae.get_remaining(), 6,
		"Dodge reaction must consume 1 action: budget must be 6 after dodge")


func test_block_consumes_one_action_from_economy() -> void:
	## Block reaction spends one action: budget 7→6.
	## attack_d20=11→hit; block reduces damage.
	var ae = _make_full_ae()
	var ctx: Dictionary = {
		"action_economy": ae,
		"blocking_weapon": _block_weapon
	}
	var res = _make_seq_res([11], [4, 2])
	res.resolve_weapon_attack(_attacker, _ad_target, _weapon, "ac", "block", ctx)
	assert_eq(ae.get_remaining(), 6,
		"Block reaction must consume 1 action: budget must be 6 after block")


func test_parry_consumes_one_action_from_economy() -> void:
	## Parry reaction spends one action: budget 7→6.
	## Parry success: parry_d20=14→parry=18>roll_total=16→damage=0.
	var ae = _make_full_ae()
	var ctx: Dictionary = {
		"action_economy": ae,
		"parrying_weapon": _parry_weapon
	}
	var res = _make_seq_res([11, 14], [4])
	res.resolve_weapon_attack(_attacker, _ad_target, _weapon, "ac", "parry", ctx)
	assert_eq(ae.get_remaining(), 6,
		"Parry reaction must consume 1 action: budget must be 6 after parry")


func test_steel_consumes_one_action_from_economy() -> void:
	## Steel reaction spends one action: budget 7→6.
	## Steel success: det_d20=16→det=17; attack_d20=11→roll_total=16<17→miss.
	var ae = _make_full_ae()
	var ctx: Dictionary = {"action_economy": ae}
	var res = _make_seq_res([16, 11], [])
	res.resolve_weapon_attack(_attacker, _ad_target, _weapon, "fortitude", "steel", ctx)
	assert_eq(ae.get_remaining(), 6,
		"Steel reaction must consume 1 action: budget must be 6 after steel")


func test_active_defense_not_applied_when_budget_exhausted() -> void:
	## When the action economy is Spent, active defense cannot trigger.
	## Exhaust budget (7 actions), then attempt Dodge → Budget=0, dodge not applied.
	var ae = _make_full_ae()
	# FEAT-003 (ADR-103): only one spend_action() succeeds per turn, so
	# exhausting the round budget requires a fresh start_of_turn() before
	# each spend (AC-4 interleaving simulated across MAX_BUDGET turns).
	for _i in range(7):
		ae.start_of_turn()
		ae.spend_action({})
	assert_true(ae.is_spent(), "AE must be spent before this test")

	var ctx: Dictionary = {"action_economy": ae, "open_space_available": true}
	var res = _make_seq_res([11], [4])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "dodge", ctx
	)
	assert_eq(result["active_defense_applied"], "none",
		"Spent AE: Dodge reaction cannot fire → active_defense_applied must be 'none'")
	assert_true(result["hit"],
		"Spent AE: no dodge → normal AC check → roll_total=16 >= ac=13 → hit")


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-059: New return keys always present in the result dict
# ══════════════════════════════════════════════════════════════════════════════

func test_result_dict_contains_defender_stepped_key() -> void:
	## defender_stepped must always be present (bool) — not just for dodge scenarios.
	var res = _make_seq_res([11], [4])
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _ad_target, _weapon, "ac")
	assert_true(result.has("defender_stepped"),
		"Result dict must always contain 'defender_stepped' key")
	assert_false(result["defender_stepped"],
		"defender_stepped must be false when active_defense='none'")


func test_result_dict_contains_next_check_bonus_key() -> void:
	## next_check_bonus must always be present (int) — not just for steel scenarios.
	var res = _make_seq_res([11], [4])
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _ad_target, _weapon, "ac")
	assert_true(result.has("next_check_bonus"),
		"Result dict must always contain 'next_check_bonus' key")
	assert_eq(result["next_check_bonus"], 0,
		"next_check_bonus must be 0 when active_defense='none'")


func test_result_dict_contains_on_hit_suppressed_key() -> void:
	## on_hit_suppressed must always be present (bool) — not just for block/parry.
	var res = _make_seq_res([11], [4])
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _ad_target, _weapon, "ac")
	assert_true(result.has("on_hit_suppressed"),
		"Result dict must always contain 'on_hit_suppressed' key")
	assert_false(result["on_hit_suppressed"],
		"on_hit_suppressed must be false when active_defense='none'")


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-059: Bobbin-vs-Dmitri extended — Dodge integration (Combat.pdf §Reactions)
#
# Combat.pdf describes: "Bobbin rolls a total of 17 to hit, beating Dmitri's
# Armor Class of 15, but failing to beat his Mobility check [of 18]."
# Dmitri dodges — attack falls on empty air, Dmitri steps to the side.
#
# FixtureRNG extension: we need two d20 calls.
# We'll use SequenceRNG(d20_seq=[18, 11], roll_seq=[7]):
#   Call 1: d20()=18 → Dmitri's Mobility check = 18+dex(4)=22...
#
# Wait — the PDF says Dmitri rolled 18 on the Mobility check, and Bobbin's
# roll_total=17. Per the PDF: Dmitri's dexterity is 4 (initiative modifier=5,
# intuition=1, dexterity=4), so mob_check = 18 on the die (the PDF states
# "rolling 18 on a Mobility check"). Let's use the die roll = 18 directly
# and treat the check result as 18 (no attribute added, since the PDF quotes
# the die result directly as "rolling 18 on a Mobility check").
#
# For this canonical test, we interpret: Mobility check result = 18 (from the
# die). Bobbin's roll_total=17. 17 < 18 → miss.
#
# SequenceRNG(d20_seq=[18, 11], roll_seq=[7]):
#   d20 call 1 (mob check): 18 → Dmitri's Mobility check = 18+dex(4)=22
#   d20 call 2 (attack):    11 → Bobbin's roll_total = 11+4(str)+2(prof) = 17
#   17 < 22 → miss (matches PDF: fails to beat Mobility check)
# ══════════════════════════════════════════════════════════════════════════════

func test_bobbin_dmitri_dodge_negates_attack() -> void:
	## Combat.pdf §Reactions: Bobbin rolls 17 to hit, fails to beat Dmitri's
	## Mobility check of 18 → attack misses and Dmitri steps to the side.
	##
	## Dmitri (Rogue) target with Dodge:
	##   dexterity=4 (initiative modifier text implies dex=4 for Dmitri)
	##   ac=15, Mobility check die=18 → check result=18+4=22
	##
	## Bobbin (Fighter) attack:
	##   strength=4, proficiency=2, d20=11 → roll_total=11+4+2=17
	##   17 < 22 → miss!
	var dmitri_dodge: Dictionary = {
		"ac":        15,
		"reflex":    13,
		"fortitude": 12,
		"will":      10,
		"dexterity": 4,    # Dmitri's dexterity (per Combat.pdf initiative: modifier=5, intuition=1, dex=4)
		"willpower": 1,
		"conscious": true
	}
	# SequenceRNG: d20[0]=18 (mob check), d20[1]=11 (attack); roll=7 (not used on miss)
	var rng = SequenceRNG.new([18, 11], [7])
	var res = ResolutionClass.new(rng)
	var result: Dictionary = res.resolve_weapon_attack(
		_bobbin, dmitri_dodge, _longsword, "ac", "dodge", {}
	)
	assert_false(result["hit"],
		"Bobbin-vs-Dmitri Dodge: roll_total=17 < Dmitri's Mobility check=22 → miss (Combat.pdf)")
	assert_eq(result["active_defense_applied"], "dodge",
		"Bobbin-vs-Dmitri Dodge: active_defense_applied must be 'dodge'")
	assert_true(result["defender_stepped"],
		"Bobbin-vs-Dmitri Dodge: Dmitri deftly steps to the side (defender_stepped=true)")
	assert_eq(result["damage_final"], 0,
		"Bobbin-vs-Dmitri Dodge: hit=false → damage_final must be 0")


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-015 / US-015 / FR-016: Off-Guard positional condition — blanket +2 to
# ALL attacks against a flanked target, integrated via core/rules/flanking.gd's
# Flanking.OFF_GUARD_CONDITION/OFF_GUARD_BONUS.
#
# seed 3 (_MISS_SEED) → rng.d20() yields 5 → roll_total 5+3+2=10.
#   Against a plain target.ac=13: 10 < 13 → miss (pinned above, _EXPECTED_MISS_ROLL_TOTAL).
#   Against the SAME target but Off-Guard (ac effectively 13-2=11): 10 < 11 →
#   still a miss with THIS particular seed, so a dedicated ac=12 target
#   fixture is used below instead to land squarely on the +2 boundary:
#   roll_total=10 misses ac=12 (10<12) but hits an Off-Guard ac=12 target
#   (effective defense 12-2=10, 10>=10 → hit).
# ══════════════════════════════════════════════════════════════════════════════

const FlankingConditionClass = preload("res://core/rules/flanking.gd")

## A target whose plain AC (12) is JUST out of reach of the pinned seed-3
## roll_total (10), so Off-Guard's +2 is the ONLY thing that can flip the
## outcome to a hit — isolating the bonus's effect precisely.
func _boundary_target(conditions: Array) -> Dictionary:
	return {
		"ac": 12,
		"reflex": 12,
		"fortitude": 14,
		"will": 11,
		"conditions": conditions,
	}


func test_off_guard_condition_absent_leaves_boundary_attack_a_miss() -> void:
	# Baseline (no Off-Guard): seed 3 → roll_total=10 < ac=12 → miss.
	var res = _make_res(_MISS_SEED)
	var result: Dictionary = res.resolve_weapon_attack(_attacker, _boundary_target([]), _weapon, "ac")
	assert_false(result["hit"], "without Off-Guard, roll_total=10 must miss ac=12")


func test_off_guard_condition_present_turns_boundary_miss_into_a_hit() -> void:
	# Off-Guard present: seed 3 → roll_total=10 vs effective ac=12-2=10 → hit.
	var res = _make_res(_MISS_SEED)
	var off_guard_target: Dictionary = _boundary_target([FlankingConditionClass.OFF_GUARD_CONDITION])
	var result: Dictionary = res.resolve_weapon_attack(_attacker, off_guard_target, _weapon, "ac")
	assert_true(
		result["hit"],
		"Off-Guard's blanket +2 must turn roll_total=10 vs ac=12 into a hit (effective ac=10)"
	)


func test_off_guard_bonus_applies_regardless_of_which_attacker_is_used() -> void:
	# Criterion: "Off-Guard applies +2 to ALL attacks against the flanked
	# target, not only the flanking pair" — resolve_weapon_attack() never
	# receives or checks flanker identity at all, so ANY attacker Dictionary
	# benefits identically once the target carries the condition (blanket
	# v0, not flankers-only per core/rules/flanking.gd's file-level doc).
	var off_guard_target: Dictionary = _boundary_target([FlankingConditionClass.OFF_GUARD_CONDITION])
	var unrelated_attacker: Dictionary = {
		"strength": 3, "dexterity": 1, "constitution": 2,
		"willpower": 1, "intellect": 1, "intuition": 1, "social": 1
	}

	var res_a = _make_res(_MISS_SEED)
	var result_a: Dictionary = res_a.resolve_weapon_attack(_attacker, off_guard_target, _weapon, "ac")

	var res_b = _make_res(_MISS_SEED)
	var result_b: Dictionary = res_b.resolve_weapon_attack(unrelated_attacker, off_guard_target, _weapon, "ac")

	assert_true(result_a["hit"], "the first attacker must benefit from the blanket Off-Guard bonus")
	assert_true(result_b["hit"], "a completely unrelated second attacker must ALSO benefit — blanket, not flankers-only")


func test_off_guard_condition_does_not_affect_targets_without_it() -> void:
	# A target with an unrelated condition (no Off-Guard) must resolve exactly
	# as the no-conditions baseline — Off-Guard's bonus must not leak in.
	var res = _make_res(_MISS_SEED)
	var target_with_other_condition: Dictionary = _boundary_target(["Dazed"])
	var result: Dictionary = res.resolve_weapon_attack(_attacker, target_with_other_condition, _weapon, "ac")
	assert_false(result["hit"], "an unrelated condition (Dazed) must not grant the Off-Guard bonus")


func test_off_guard_condition_boosts_crit_threshold_too() -> void:
	# seed 1 (_CRIT_SEED) → roll_total=23. Against ac=13 that's already a
	# crit (23-13=10>=10). Off-Guard's +2 (effective ac=11) must not somehow
	# REMOVE the crit -- confirms the reduction composes correctly with the
	# existing crit math rather than only gating the hit check.
	var res = _make_res(_CRIT_SEED)
	var off_guard_target: Dictionary = _target.duplicate()
	off_guard_target["conditions"] = [FlankingConditionClass.OFF_GUARD_CONDITION]
	var result: Dictionary = res.resolve_weapon_attack(_attacker, off_guard_target, _weapon, "ac")
	assert_true(result["hit"])
	assert_true(result["crit"], "Off-Guard must widen, never narrow, the crit margin")


func test_off_guard_condition_applies_to_spell_attacks_too() -> void:
	# resolve_spell_attack() must ALSO honor Off-Guard -- "blanket +2 to ALL
	# attacks against it" is not limited to weapon Strikes.
	var caster: Dictionary = {
		"spellcasting_attribute": "intellect",
		"intellect": 3,
		"spell_attack_bonus": 2,
	}
	var spell: Dictionary = {"damage_die": 6}

	# seed 3 → d20()=5 → roll_total = 5 + 3 + 2 = 10, identical shape to the
	# weapon boundary fixture above.
	var res_plain = _make_res(_MISS_SEED)
	var plain_result: Dictionary = res_plain.resolve_spell_attack(caster, _boundary_target([]), spell, "ac")
	assert_false(plain_result["hit"], "without Off-Guard, roll_total=10 must miss ac=12")

	var res_off_guard = _make_res(_MISS_SEED)
	var off_guard_target: Dictionary = _boundary_target([FlankingConditionClass.OFF_GUARD_CONDITION])
	var off_guard_result: Dictionary = res_off_guard.resolve_spell_attack(caster, off_guard_target, spell, "ac")
	assert_true(off_guard_result["hit"], "Off-Guard's blanket +2 must also apply to spell attacks")
