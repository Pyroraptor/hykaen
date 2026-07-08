extends GutTest
## tests/unit/test_dodge_steel_checks.gd
##
## GUT unit tests for FEAT-007 (US-007 / FR-008, ADR-015): rewires the
## Dodge and Steel active-defense checks in core/rules/resolution.gd to use
## the target's REAL skills — skills['mobility'] (Dodge/Mobility check) and
## skills['determination'] (Steel/Determination check) — replacing the
## former target.dexterity / target.willpower attribute proxies that stood
## in for those skills before FEAT-002 introduced the skills Dictionary.
##
## This is a prerequisite for the Dodge reaction (FEAT-010) that the steel
## thread's pop-up must be able to trigger: the reaction's math must read
## from the same skills source the pop-up will eventually let the player
## invoke against.
##
## Test criteria covered:
##   1. Dodge check uses skills['mobility'] instead of the dexterity proxy.
##   2. Steel check uses skills['determination'] instead of the willpower proxy.
##   3. Updated Dodge/Steel tests pass for Titus (2/2) and Skeleton (1/1)
##      loaded directly from their .tres resources.
##   4. The check formula is flat d20 + skill vs. the defender's effective
##      value (i.e., the check result substitutes for the passive defense
##      value compared against the attacker's roll_total) — no attribute
##      modifiers or other bonuses are folded into the check itself.

const ResolutionClass = preload("res://core/rules/resolution.gd")

const TITUS_TRES_PATH    := "res://data/characters/titus.tres"
const SKELETON_TRES_PATH := "res://data/enemies/skeleton.tres"


## SequenceRNG — multi-step RNG stub mirroring tests/unit/test_resolution.gd's
## own SequenceRNG: returns successive values from pre-set d20/roll sequences.
## Each d20() call consumes the next element of d20_seq (wraps if exhausted).
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


## Helper: build a Resolution backed by a SequenceRNG.
func _make_seq_res(d20_seq: Array, roll_seq: Array) -> ResolutionClass:
	var rng = SequenceRNG.new(d20_seq, roll_seq)
	return ResolutionClass.new(rng)


## Standard attacker: strength(3) + proficiency(2) → attack modifier +5.
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


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: Dodge check uses skills['mobility'], NOT the dexterity proxy
# ══════════════════════════════════════════════════════════════════════════════

func test_dodge_check_uses_skills_mobility_value() -> void:
	## Target carries a decoy "dexterity" (99, would never lose a Mobility
	## check) alongside the REAL skills['mobility'] (2). If resolution.gd
	## still read the old dexterity proxy, the check would be unbeatable
	## (mob_d20+99) and the attack would always miss. Reading skills['mobility']
	## instead produces a beatable check (mob_d20+2), so this attack must hit.
	##
	## mob_d20=10 → mobility_check = 10 + skills.mobility(2) = 12
	## attack_d20=11 → roll_total = 11 + strength(3) + prof(2) = 16
	## 16 >= 12 → hit=true (proves skills['mobility'] was used, not dexterity=99)
	var target: Dictionary = {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"dexterity": 99,
		"skills": {"mobility": 2},
		"conscious": true
	}
	var res = _make_seq_res([10, 11], [4])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, target, _weapon, "ac", "dodge", {}
	)
	assert_true(
		result["hit"],
		"Dodge must use skills['mobility']=2 (check=12), not dexterity=99 (check=101) — roll_total=16 must beat 12"
	)
	assert_eq(result["active_defense_applied"], "dodge",
		"Dodge trigger conditions were met → active_defense_applied must be 'dodge'")


func test_dodge_check_ignores_dexterity_proxy_entirely() -> void:
	## Same scenario as above, but flipped: dexterity is now LOW (0) while
	## skills.mobility is HIGH (10). If the old dexterity proxy were still
	## consulted, this attack would hit (mob_d20+dex(0)=10 < roll_total=16
	## is false... rather 10<16 -> hit true). We need a scenario where using
	## dexterity gives a DIFFERENT outcome than using skills.mobility.
	##
	## mob_d20=10, skills.mobility=10 → mobility_check = 20 (skills path)
	## mob_d20=10, dexterity=0        → mobility_check = 10 (old proxy path)
	## attack_d20=11 → roll_total = 16
	## Skills path:  16 >= 20 is false → miss (Dodge succeeds, defender steps).
	## Old-proxy path: 16 >= 10 is true → hit (Dodge fails to protect).
	## These two outcomes are mutually exclusive, so asserting "miss" proves
	## the implementation reads skills['mobility'], not target.dexterity.
	var target: Dictionary = {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"dexterity": 0,
		"skills": {"mobility": 10},
		"conscious": true
	}
	var res = _make_seq_res([10, 11], [])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, target, _weapon, "ac", "dodge", {}
	)
	assert_false(
		result["hit"],
		"Dodge must use skills['mobility']=10 (check=20 > roll_total=16 → miss), " +
		"NOT dexterity=0 (check=10 < 16 → would incorrectly hit)"
	)
	assert_true(result["defender_stepped"],
		"Dodge check=20 beats roll_total=16 → defender must Step (successful Dodge)")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: Steel check uses skills['determination'], NOT the willpower proxy
# ══════════════════════════════════════════════════════════════════════════════

func test_steel_check_uses_skills_determination_value() -> void:
	## Target carries a decoy "willpower" (99) alongside the REAL
	## skills['determination'] (2). If resolution.gd still read the old
	## willpower proxy, the check would be unbeatable and the attack would
	## always be resisted (miss). Reading skills['determination'] instead
	## produces a beatable check, so this attack must hit.
	##
	## det_d20=10 → determination_check = 10 + skills.determination(2) = 12
	## attack_d20=11 → roll_total = 11 + strength(3) + prof(2) = 16
	## 16 >= 12 → hit=true (proves skills['determination'] was used, not willpower=99)
	var target: Dictionary = {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"willpower": 99,
		"skills": {"determination": 2},
		"conscious": true
	}
	var res = _make_seq_res([10, 11], [4])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, target, _weapon, "fortitude", "steel", {}
	)
	assert_true(
		result["hit"],
		"Steel must use skills['determination']=2 (check=12), not willpower=99 (check=101) — roll_total=16 must beat 12"
	)
	assert_eq(result["active_defense_applied"], "steel",
		"Steel trigger conditions were met → active_defense_applied must be 'steel'")


func test_steel_check_ignores_willpower_proxy_entirely() -> void:
	## Flipped scenario: willpower is LOW (0) while skills.determination is
	## HIGH (10) — the two paths produce mutually exclusive hit/miss outcomes.
	##
	## det_d20=10, skills.determination=10 → determination_check = 20 (skills path)
	## det_d20=10, willpower=0              → determination_check = 10 (old proxy path)
	## attack_d20=11 → roll_total = 16
	## Skills path:    16 >= 20 is false → miss (Steel resists, next_check_bonus=2).
	## Old-proxy path: 16 >= 10 is true  → hit (Steel fails to resist).
	var target: Dictionary = {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"willpower": 0,
		"skills": {"determination": 10},
		"conscious": true
	}
	var res = _make_seq_res([10, 11], [])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, target, _weapon, "will", "steel", {}
	)
	assert_false(
		result["hit"],
		"Steel must use skills['determination']=10 (check=20 > roll_total=16 → miss), " +
		"NOT willpower=0 (check=10 < 16 → would incorrectly hit)"
	)
	assert_eq(result["next_check_bonus"], 2,
		"Steel check=20 beats roll_total=16 → attack resisted, next_check_bonus must be +2")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: flat d20 + skill vs defender's effective value formula
#
# Isolates that the check is EXACTLY d20 + skill (no attribute modifiers,
# no proficiency, no other bonuses folded in) by holding the pinned d20
# fixed and varying only the skill score, observing the hit/miss boundary
# shift by precisely the skill delta.
# ══════════════════════════════════════════════════════════════════════════════

func test_dodge_formula_is_flat_d20_plus_mobility_skill() -> void:
	## Fixed mob_d20=10, attack_d20=11 → roll_total=16 in both cases.
	## mobility=1 → check=11 → 16>=11 → hit=true (Dodge fails to protect).
	## mobility=10 → check=20 → 16<20 → hit=false (Dodge succeeds).
	## The boundary crossing exactly at the point where 10+skill exceeds 16
	## confirms the formula is flat d20 + skill, with no hidden modifier.
	var low_target: Dictionary = {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"skills": {"mobility": 1}, "conscious": true
	}
	var high_target: Dictionary = {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"skills": {"mobility": 10}, "conscious": true
	}

	var res_low = _make_seq_res([10, 11], [4])
	var result_low: Dictionary = res_low.resolve_weapon_attack(
		_attacker, low_target, _weapon, "ac", "dodge", {}
	)
	var res_high = _make_seq_res([10, 11], [])
	var result_high: Dictionary = res_high.resolve_weapon_attack(
		_attacker, high_target, _weapon, "ac", "dodge", {}
	)

	assert_true(result_low["hit"],
		"mobility=1: check=10+1=11 <= roll_total=16 → hit must be true")
	assert_false(result_high["hit"],
		"mobility=10: check=10+10=20 > roll_total=16 → hit must be false")


func test_steel_formula_is_flat_d20_plus_determination_skill() -> void:
	## Same boundary-crossing proof, for Steel/determination.
	## Fixed det_d20=10, attack_d20=11 → roll_total=16 in both cases.
	## determination=1 → check=11 → 16>=11 → hit=true (Steel fails to resist).
	## determination=10 → check=20 → 16<20 → hit=false (Steel resists).
	var low_target: Dictionary = {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"skills": {"determination": 1}, "conscious": true
	}
	var high_target: Dictionary = {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"skills": {"determination": 10}, "conscious": true
	}

	var res_low = _make_seq_res([10, 11], [4])
	var result_low: Dictionary = res_low.resolve_weapon_attack(
		_attacker, low_target, _weapon, "fortitude", "steel", {}
	)
	var res_high = _make_seq_res([10, 11], [])
	var result_high: Dictionary = res_high.resolve_weapon_attack(
		_attacker, high_target, _weapon, "fortitude", "steel", {}
	)

	assert_true(result_low["hit"],
		"determination=1: check=10+1=11 <= roll_total=16 → hit must be true")
	assert_false(result_high["hit"],
		"determination=10: check=10+10=20 > roll_total=16 → hit must be false")


func test_dodge_check_defaults_to_zero_when_skills_key_absent() -> void:
	## Missing-key-defaults-to-0: a target with no "skills" Dictionary at
	## all must resolve the Mobility check as d20 + 0, matching the
	## accessor pattern used everywhere else skills are read.
	## mob_d20=10 → mobility_check=10+0=10; attack_d20=11 → roll_total=16.
	## 16 >= 10 → hit=true.
	var target: Dictionary = {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"conscious": true
	}
	var res = _make_seq_res([10, 11], [4])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, target, _weapon, "ac", "dodge", {}
	)
	assert_true(result["hit"],
		"No 'skills' key on target: mobility check must default to d20+0=10 <= roll_total=16 → hit=true")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: Updated Dodge/Steel tests pass for Titus (2/2) and Skeleton (1/1)
#
# Loads titus.tres (skills.mobility=2, skills.determination=2) and
# skeleton.tres (skills.mobility=1, skills.determination=1) directly via
# ResourceLoader, builds an active-defense target Dictionary from each
# resource's real skills Dictionary, and drives both checks through
# resolve_weapon_attack() with pinned RNG sequences.
# ══════════════════════════════════════════════════════════════════════════════

func _build_ad_target_from_resource(resource) -> Dictionary:
	return {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"skills": resource.skills,
		"conscious": true
	}


## Titus test 1/2 — Dodge check uses titus.tres skills.mobility=2.
func test_titus_dodge_check_uses_titus_tres_mobility_skill() -> void:
	var titus = ResourceLoader.load(TITUS_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(titus, "titus.tres must load")
	if titus == null:
		return
	assert_eq(titus.skills.get("mobility", 0), 2, "titus.tres skills.mobility must be 2 (FEAT-002 fixture)")

	var target: Dictionary = _build_ad_target_from_resource(titus)
	# mob_d20=14 → mobility_check = 14 + titus mobility(2) = 16
	# attack_d20=11 → roll_total = 11 + strength(3) + prof(2) = 16
	# 16 >= 16 → hit=true (boundary tie goes to the attacker per >= semantics)
	var res = _make_seq_res([14, 11], [4])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, target, _weapon, "ac", "dodge", {}
	)
	assert_true(result["hit"],
		"Titus Dodge: mobility_check=14+2=16 <= roll_total=16 → hit must be true")
	assert_eq(result["active_defense_applied"], "dodge",
		"Titus Dodge: active_defense_applied must be 'dodge'")


## Titus test 2/2 — Steel check uses titus.tres skills.determination=2.
func test_titus_steel_check_uses_titus_tres_determination_skill() -> void:
	var titus = ResourceLoader.load(TITUS_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(titus, "titus.tres must load")
	if titus == null:
		return
	assert_eq(titus.skills.get("determination", 0), 2, "titus.tres skills.determination must be 2 (FEAT-002 fixture)")

	var target: Dictionary = _build_ad_target_from_resource(titus)
	# det_d20=8 → determination_check = 8 + titus determination(2) = 10
	# attack_d20=11 → roll_total = 16
	# 16 >= 10 → hit=true; excess=6 < 10 → no crit; Steel failed to resist.
	var res = _make_seq_res([8, 11], [4])
	var result: Dictionary = res.resolve_weapon_attack(
		_attacker, target, _weapon, "fortitude", "steel", {}
	)
	assert_true(result["hit"],
		"Titus Steel: determination_check=8+2=10 <= roll_total=16 → hit must be true (Steel failed to resist)")
	assert_eq(result["active_defense_applied"], "steel",
		"Titus Steel: active_defense_applied must be 'steel'")
	assert_eq(result["next_check_bonus"], 0,
		"Titus Steel: attack was NOT resisted → next_check_bonus must be 0")


## Skeleton test 1/1 — a single combined test exercising BOTH the Dodge and
## Steel checks against skeleton.tres' skills (mobility=1, determination=1),
## demonstrating both checks read the same loaded EnemyResource skills
## Dictionary correctly.
func test_skeleton_dodge_and_steel_checks_use_skeleton_tres_skills() -> void:
	var skeleton = ResourceLoader.load(SKELETON_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(skeleton, "skeleton.tres must load")
	if skeleton == null:
		return
	assert_eq(skeleton.skills.get("mobility", 0), 1, "skeleton.tres skills.mobility must be 1 (FEAT-002 fixture)")
	assert_eq(skeleton.skills.get("determination", 0), 1, "skeleton.tres skills.determination must be 1 (FEAT-002 fixture)")

	var target: Dictionary = _build_ad_target_from_resource(skeleton)

	# Dodge: mob_d20=16 → mobility_check=16+1=17; attack_d20=11 → roll_total=16.
	# 16 < 17 → miss (Dodge succeeds, defender steps).
	var res_dodge = _make_seq_res([16, 11], [])
	var result_dodge: Dictionary = res_dodge.resolve_weapon_attack(
		_attacker, target, _weapon, "ac", "dodge", {}
	)
	assert_false(result_dodge["hit"],
		"Skeleton Dodge: mobility_check=16+1=17 > roll_total=16 → hit must be false")
	assert_true(result_dodge["defender_stepped"],
		"Skeleton Dodge: successful Dodge → defender_stepped must be true")

	# Steel: det_d20=16 → determination_check=16+1=17; attack_d20=11 → roll_total=16.
	# 16 < 17 → miss (Steel resists, next_check_bonus=2).
	var res_steel = _make_seq_res([16, 11], [])
	var result_steel: Dictionary = res_steel.resolve_weapon_attack(
		_attacker, target, _weapon, "will", "steel", {}
	)
	assert_false(result_steel["hit"],
		"Skeleton Steel: determination_check=16+1=17 > roll_total=16 → hit must be false")
	assert_eq(result_steel["next_check_bonus"], 2,
		"Skeleton Steel: attack resisted → next_check_bonus must be +2")
