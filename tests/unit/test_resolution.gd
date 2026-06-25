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

const ResolutionClass = preload("res://core/rules/resolution.gd")
const RNGClass        = preload("res://core/rules/rng.gd")


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
