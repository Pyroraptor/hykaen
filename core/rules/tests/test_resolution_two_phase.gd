extends GutTest
## core/rules/tests/test_resolution_two_phase.gd
##
## FEAT-001 (US-001 / FR-004, Iteration J Part A): GUT suite for the
## resolve_to_hit() + apply_on_hit_defense() two-phase split extracted out of
## core/rules/resolution.gd's resolve_weapon_attack().
##
## WHY this split exists: Iteration J's phased reaction windows (Dodge/Steel
## on-attacked, Block/Parry on-hit) need to learn the hit/miss result BEFORE
## deciding whether to open a post-hit Block/Parry window — the old
## single-call resolve_weapon_attack() committed to a whole active_defense
## choice up front. resolve_weapon_attack() itself becomes a THIN COMPOSING
## WRAPPER over these two functions and must keep producing byte-for-byte
## identical output on its default/"none" path (see
## tests/characterization/test_strike_characterization.gd, the pinned
## regression oracle this feature is forbidden from perturbing).
##
## Sections:
##   A. resolve_to_hit() pinned attack scenarios (hit/miss/crit/dodge/steel)
##   B. apply_on_hit_defense() pinned block/parry/none scenarios
##   C. apply_on_hit_defense() precondition guard (partial.hit == false)
##   D. resolve_weapon_attack() thin-wrapper equivalence (composition proves
##      byte-for-byte identical to calling the two phases manually)
##   E. resolve_weapon_attack() reproduces a known
##      tests/characterization/test_strike_characterization.gd pinned
##      scenario directly (cross-check, criterion 4)
##   F. No-duplicated-math static check (criterion 5)

const ResolutionClass = preload("res://core/rules/resolution.gd")
const FlankingClass    = preload("res://core/rules/flanking.gd")

const RESOLUTION_PATH: String = "res://core/rules/resolution.gd"


# ── Local test double: SequenceRNG ──────────────────────────────────────────
# Mirrors tests/unit/test_resolution.gd's SequenceRNG convention (each suite
# in this project owns its own doubles, per that file's header comment) —
# returns successive values from pre-set d20/roll sequences so every RNG
# consumption position is pinned and reproducible.
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


func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


# ── Shared fixtures ──────────────────────────────────────────────────────────

var _attacker: Dictionary = {
	"strength": 3
}

var _weapon: Dictionary = {
	"damage_modifier_attribute": "strength",
	"proficiency_bonus": 2,
	"damage_die": 6
}

## Target with real skills for Dodge (mobility) / Steel (determination)
## checks (FEAT-007 / US-007 / FR-008 / ADR-015).
var _ad_target: Dictionary = {
	"ac":        13,
	"reflex":    12,
	"fortitude": 14,
	"will":      11,
	"skills": {
		"mobility":      1,
		"determination": 1
	},
	"conscious": true
}

var _block_weapon: Dictionary = {
	"damage_die": 6,
	"block_value": 3
}

var _parry_weapon: Dictionary = {
	"parry_bonus": 4
}

func _make_res(d20_seq: Array, roll_seq: Array) -> ResolutionClass:
	var rng = SequenceRNG.new(d20_seq, roll_seq)
	return ResolutionClass.new(rng)


# ══════════════════════════════════════════════════════════════════════════
# Section A: resolve_to_hit() pinned attack scenarios
# ══════════════════════════════════════════════════════════════════════════

func test_resolve_to_hit_plain_hit_no_crit() -> void:
	## d20=11 -> roll_total=11+3+2=16 >= ac(13) -> hit; 16-13=3 < 10 -> no crit.
	## damage_raw = roll(6,1)=4 + strength(3) = 7.
	var res = _make_res([11], [4])
	var partial: Dictionary = res.resolve_to_hit(_attacker, _ad_target, _weapon, "ac", "none", {})

	assert_true(partial["hit"], "d20=11 -> roll_total=16 >= ac=13 -> must be a hit")
	assert_false(partial["crit"], "16-13=3 < 10 -> must not crit")
	assert_eq(partial["roll_total"], 16, "roll_total must be 11+3+2=16")
	assert_eq(partial["damage_raw"], 7, "damage_raw must be roll(4)+strength(3)=7")
	assert_false(partial["defender_stepped"], "no Dodge attempted -> defender_stepped must be false")


func test_resolve_to_hit_plain_miss() -> void:
	## d20=5 -> roll_total=5+3+2=10 < ac(13) -> miss; damage_raw must stay 0
	## (no damage roll consumed on a miss).
	var res = _make_res([5], [4])
	var partial: Dictionary = res.resolve_to_hit(_attacker, _ad_target, _weapon, "ac", "none", {})

	assert_false(partial["hit"], "d20=5 -> roll_total=10 < ac=13 -> must be a miss")
	assert_eq(partial["damage_raw"], 0, "miss must produce damage_raw=0")
	assert_false(partial["defender_stepped"], "no Dodge attempted -> defender_stepped must be false")


func test_resolve_to_hit_crit() -> void:
	## d20=18 -> roll_total=18+3+2=23 >= ac(13); excess=10 >= 10 -> crit.
	## Crit damage: roll(6,2) scripted as a single summed value (5) + strength(3)*2 = 11.
	var res = _make_res([18], [5])
	var partial: Dictionary = res.resolve_to_hit(_attacker, _ad_target, _weapon, "ac", "none", {})

	assert_true(partial["hit"], "d20=18 -> roll_total=23 >= ac=13 -> must be a hit")
	assert_true(partial["crit"], "excess=23-13=10 >= 10 -> must crit")
	assert_eq(partial["damage_raw"], 11, "crit damage_raw must be roll(5)+strength(3)*2=11")


func test_resolve_to_hit_dodge_success_avoids_attack_and_steps_defender() -> void:
	## mob_d20=16 -> mobility_check=16+mobility(1)=17. attack_d20=11 -> roll_total=16.
	## 16 < 17 -> miss (Dodge succeeded); defender_stepped must be true.
	var res = _make_res([16, 11], [])
	var partial: Dictionary = res.resolve_to_hit(_attacker, _ad_target, _weapon, "ac", "dodge", {})

	assert_false(partial["hit"], "Dodge succeeds: roll_total(16) < mobility_check(17) -> miss")
	assert_true(partial["defender_stepped"], "successful Dodge must set defender_stepped=true")
	assert_eq(partial["damage_raw"], 0, "a Dodge-avoided attack must produce damage_raw=0")


func test_resolve_to_hit_dodge_fail_still_hits_and_does_not_step() -> void:
	## mob_d20=9 -> mobility_check=9+1=10. attack_d20=11 -> roll_total=16.
	## 16 >= 10 -> hit (Dodge did not protect); defender_stepped must be false.
	var res = _make_res([9, 11], [4])
	var partial: Dictionary = res.resolve_to_hit(_attacker, _ad_target, _weapon, "ac", "dodge", {})

	assert_true(partial["hit"], "Dodge fails to protect: roll_total(16) >= mobility_check(10) -> hit")
	assert_false(partial["defender_stepped"], "a failed Dodge must not set defender_stepped")
	assert_eq(partial["damage_raw"], 7, "damage_raw must still be computed normally on a Dodge-fail hit")


func test_resolve_to_hit_steel_success_resists() -> void:
	## det_d20=16 -> determination_check=16+determination(1)=17. attack_d20=11(+3+2)=16.
	## 16 < 17 -> miss (Steel resisted).
	var res = _make_res([16, 11], [])
	var partial: Dictionary = res.resolve_to_hit(_attacker, _ad_target, _weapon, "fortitude", "steel", {})

	assert_false(partial["hit"], "Steel resists: roll_total(16) < determination_check(17) -> miss")


# ══════════════════════════════════════════════════════════════════════════
# Section B: apply_on_hit_defense() pinned block/parry/none scenarios
# ══════════════════════════════════════════════════════════════════════════

func _hit_partial(damage_raw: int, roll_total: int, defense_type: String = "ac", weapon: Dictionary = {}) -> Dictionary:
	return {
		"hit": true,
		"crit": false,
		"roll_total": roll_total,
		"damage_raw": damage_raw,
		"defender_stepped": false,
		"active_defense_applied": "none",
		"next_check_bonus": 0,
		"defense_value": 13,
		"defense_type": defense_type,
		"weapon": weapon
	}


func test_apply_on_hit_defense_none_passes_damage_through_unmodified() -> void:
	var res = _make_res([], [])
	var partial: Dictionary = _hit_partial(7, 16)
	var result: Dictionary = res.apply_on_hit_defense(partial, "none", {})

	assert_eq(result["damage_final"], 7, "on_hit_defense='none' must leave damage_final == damage_raw")
	assert_eq(result["active_defense_applied"], "none", "on_hit_defense='none' must not mark a defense as applied")
	assert_false(result["on_hit_suppressed"], "on_hit_defense='none' must never suppress")


func test_apply_on_hit_defense_block_reduces_damage() -> void:
	## damage_raw=7; block roll(6,1)=2 + block_value(3) = 5 -> damage_final = 7-5 = 2.
	var res = _make_res([], [2])
	var partial: Dictionary = _hit_partial(7, 16, "ac", _weapon)
	var result: Dictionary = res.apply_on_hit_defense(partial, "block", {"blocking_weapon": _block_weapon})

	assert_eq(result["damage_final"], 2, "block must reduce damage_final to 7-(2+3)=2")
	assert_eq(result["active_defense_applied"], "block")
	assert_true(result["on_hit_suppressed"], "block always sets on_hit_suppressed=true when it triggers")
	assert_true(result["damage_final"] >= 0, "damage_final must never go negative")


func test_apply_on_hit_defense_block_floors_damage_at_zero() -> void:
	## A block reduction larger than damage_raw must floor at 0, never negative.
	var res = _make_res([], [50])
	var partial: Dictionary = _hit_partial(7, 16, "ac", _weapon)
	var result: Dictionary = res.apply_on_hit_defense(partial, "block", {"blocking_weapon": _block_weapon})

	assert_eq(result["damage_final"], 0, "an oversized block reduction must floor damage_final at 0, not go negative")
	assert_true(result["damage_final"] >= 0, "damage_final must never go negative")


func test_apply_on_hit_defense_parry_success_negates_damage() -> void:
	## roll_total=16; parry_d20=14 + parry_bonus(4) = 18 > 16 -> success -> damage_final=0.
	var res = _make_res([14], [])
	var partial: Dictionary = _hit_partial(7, 16, "ac")
	var result: Dictionary = res.apply_on_hit_defense(partial, "parry", {"parrying_weapon": _parry_weapon})

	assert_eq(result["damage_final"], 0, "successful Parry must negate damage_final to 0")
	assert_eq(result["active_defense_applied"], "parry")
	assert_true(result["on_hit_suppressed"], "a successful Parry must set on_hit_suppressed=true")


func test_apply_on_hit_defense_parry_fail_leaves_damage_unmodified() -> void:
	## roll_total=16; parry_d20=5 + parry_bonus(4) = 9 <= 16 -> fail -> damage_final stays 7.
	var res = _make_res([5], [])
	var partial: Dictionary = _hit_partial(7, 16, "ac")
	var result: Dictionary = res.apply_on_hit_defense(partial, "parry", {"parrying_weapon": _parry_weapon})

	assert_eq(result["damage_final"], 7, "a failed Parry must leave damage_final unmodified")
	assert_eq(result["active_defense_applied"], "parry", "active_defense_applied is 'parry' whether or not it succeeded")
	assert_false(result["on_hit_suppressed"], "a failed Parry must not suppress the hit")


func test_apply_on_hit_defense_damage_final_always_non_negative_across_all_paths() -> void:
	## Consolidated check across none/block/parry — damage_final must never be < 0.
	var scenarios: Array = [
		{"defense": "none",  "ctx": {}},
		{"defense": "block", "ctx": {"blocking_weapon": _block_weapon}},
		{"defense": "parry", "ctx": {"parrying_weapon": _parry_weapon}}
	]
	for scenario in scenarios:
		var res = _make_res([5], [2])
		var partial: Dictionary = _hit_partial(7, 16, "ac", _weapon)
		var result: Dictionary = res.apply_on_hit_defense(partial, scenario["defense"], scenario["ctx"])
		assert_true(
			result["damage_final"] >= 0,
			"on_hit_defense='%s': damage_final must be >= 0, got %d" % [scenario["defense"], result["damage_final"]]
		)


# ══════════════════════════════════════════════════════════════════════════
# Section C: apply_on_hit_defense() precondition guard
#
# US-004 task 5 / design-notes api_contracts: apply_on_hit_defense() must
# NEVER be invoked on a miss. This project's established pattern for a
# programmer-error guard (mirrors core/rules/action_economy.gd's
# null-combatant guards) is push_error() + a safe no-op return rather than a
# hard crash — GUT's push_error capture is unavailable on this project's
# Godot 4.3 engine (documented in tests/unit/test_action_economy.gd), so we
# assert the NO-OP CONTRACT here rather than the push_error() call site
# itself, exactly as that file's own note explains.
# ══════════════════════════════════════════════════════════════════════════

func test_apply_on_hit_defense_on_a_miss_is_a_safe_noop() -> void:
	var res = _make_res([], [])
	var miss_partial: Dictionary = {
		"hit": false,
		"crit": false,
		"roll_total": 10,
		"damage_raw": 0,
		"defender_stepped": false,
		"active_defense_applied": "none",
		"next_check_bonus": 0,
		"defense_value": 13,
		"defense_type": "ac",
		"weapon": _weapon
	}
	var result: Dictionary = res.apply_on_hit_defense(miss_partial, "block", {"blocking_weapon": _block_weapon})

	assert_eq(result["damage_final"], 0, "precondition violation (miss): damage_final must be the safe default 0")
	assert_false(result["on_hit_suppressed"], "precondition violation (miss): on_hit_suppressed must be the safe default false")


# ══════════════════════════════════════════════════════════════════════════
# Section D: resolve_weapon_attack() thin-wrapper equivalence
#
# Proves the single-call wrapper produces EXACTLY the same result as calling
# resolve_to_hit() then apply_on_hit_defense() manually with an identically-
# seeded RNG — i.e. the wrapper performs no math of its own, only dispatch.
# ══════════════════════════════════════════════════════════════════════════

func test_wrapper_equals_manual_two_phase_composition_on_hit_none() -> void:
	var wrapper_res = _make_res([11], [4])
	var wrapper_result: Dictionary = wrapper_res.resolve_weapon_attack(_attacker, _ad_target, _weapon, "ac", "none", {})

	var manual_res = _make_res([11], [4])
	var partial: Dictionary = manual_res.resolve_to_hit(_attacker, _ad_target, _weapon, "ac", "none", {})
	var post: Dictionary = manual_res.apply_on_hit_defense(partial, "none", {})

	assert_eq(wrapper_result["hit"], partial["hit"])
	assert_eq(wrapper_result["crit"], partial["crit"])
	assert_eq(wrapper_result["roll_total"], partial["roll_total"])
	assert_eq(wrapper_result["damage_raw"], partial["damage_raw"])
	assert_eq(wrapper_result["damage_final"], post["damage_final"])
	assert_eq(wrapper_result["active_defense_applied"], post["active_defense_applied"])
	assert_eq(wrapper_result["on_hit_suppressed"], post["on_hit_suppressed"])


func test_wrapper_equals_manual_two_phase_composition_on_block() -> void:
	var wrapper_res = _make_res([11], [4, 2])
	var wrapper_result: Dictionary = wrapper_res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "block", {"blocking_weapon": _block_weapon}
	)

	var manual_res = _make_res([11], [4, 2])
	var partial: Dictionary = manual_res.resolve_to_hit(_attacker, _ad_target, _weapon, "ac", "none", {})
	var post: Dictionary = manual_res.apply_on_hit_defense(partial, "block", {"blocking_weapon": _block_weapon})

	assert_eq(wrapper_result["damage_final"], post["damage_final"])
	assert_eq(wrapper_result["damage_final"], 2, "sanity: block scenario must still reduce damage_final to 2")
	assert_eq(wrapper_result["active_defense_applied"], "block")
	assert_true(wrapper_result["on_hit_suppressed"])


func test_wrapper_equals_manual_two_phase_composition_on_dodge_success() -> void:
	var wrapper_res = _make_res([16, 11], [])
	var wrapper_result: Dictionary = wrapper_res.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac", "dodge", {}
	)

	var manual_res = _make_res([16, 11], [])
	var partial: Dictionary = manual_res.resolve_to_hit(_attacker, _ad_target, _weapon, "ac", "dodge", {})
	# hit is false -> apply_on_hit_defense must not be invoked (US-004 task 5); wrapper enforces this itself.

	assert_eq(wrapper_result["hit"], partial["hit"])
	assert_false(wrapper_result["hit"], "sanity: this scenario is a successful Dodge (miss)")
	assert_eq(wrapper_result["defender_stepped"], partial["defender_stepped"])
	assert_true(wrapper_result["defender_stepped"])
	assert_eq(wrapper_result["damage_final"], 0, "a Dodge-avoided attack must produce damage_final=0")
	assert_eq(wrapper_result["active_defense_applied"], "dodge")


# ══════════════════════════════════════════════════════════════════════════
# Section E: resolve_weapon_attack() reproduces a known
# tests/characterization/test_strike_characterization.gd pinned scenario
# (Section A, Off-Guard +2) directly against resolution.gd -- a direct
# cross-check that the post-split wrapper has not drifted from the pinned
# regression oracle for the default/"none" path (test_criteria #4).
# ══════════════════════════════════════════════════════════════════════════

func test_wrapper_reproduces_characterization_off_guard_baseline_miss() -> void:
	## Mirrors test_pin_baseline_defense_value_equals_plain_ac: attacker
	## strength=0/prof=0/d6; target ac=12; scripted raw=10 -> roll_total=10
	## -> baseline (no Off-Guard) defense_value=12 -> 10 < 12 -> miss.
	var attacker: Dictionary = {"strength": 0}
	var weapon: Dictionary = {"damage_modifier_attribute": "strength", "proficiency_bonus": 0, "damage_die": 6}
	var target: Dictionary = {"ac": 12, "conditions": []}

	var res = _make_res([10], [4])
	var result: Dictionary = res.resolve_weapon_attack(attacker, target, weapon, "ac", "none", {})

	assert_eq(result["defense_value"], 12, "PINNED (cross-check vs characterization Section A): baseline defense_value must equal plain ac(12)")
	assert_false(result["hit"], "PINNED: roll_total(10) < ac(12) -> miss")


func test_wrapper_reproduces_characterization_off_guard_flips_boundary() -> void:
	## Mirrors test_pin_off_guard_flips_boundary_miss_into_hit: same fixture,
	## Off-Guard condition present -> defense_value=10 -> 10 >= 10 -> hit,
	## damage_final = damage_roll(4) + strength_mod(0) = 4.
	var attacker: Dictionary = {"strength": 0}
	var weapon: Dictionary = {"damage_modifier_attribute": "strength", "proficiency_bonus": 0, "damage_die": 6}
	var target: Dictionary = {"ac": 12, "conditions": [FlankingClass.OFF_GUARD_CONDITION]}

	var res = _make_res([10], [4])
	var result: Dictionary = res.resolve_weapon_attack(attacker, target, weapon, "ac", "none", {})

	assert_eq(result["defense_value"], 10, "PINNED (cross-check vs characterization Section A): Off-Guard defense_value must be ac(12)-2=10")
	assert_true(result["hit"], "PINNED: roll_total(10) >= off-guard defense_value(10) -> hit")
	assert_eq(result["damage_final"], 4, "PINNED: damage_final = damage_roll(4) + strength_mod(0) = 4")


# ══════════════════════════════════════════════════════════════════════════
# Section F: No-duplicated-resolution-math static check (test_criteria #5)
#
# Manual/static verification, documented here rather than hand-waved:
# resolve_weapon_attack()'s own function body (as opposed to resolve_to_hit()
# and apply_on_hit_defense(), which it calls) must contain ZERO direct RNG
# consumption and must NOT restate the crit-threshold formula -- proving it
# is a pure dispatcher over the two extracted phases with no re-derived math.
# ══════════════════════════════════════════════════════════════════════════

func _extract_function_body(content: String, func_signature_prefix: String) -> String:
	var start: int = content.find(func_signature_prefix)
	assert_true(start >= 0, "expected to find '%s' in resolution.gd" % func_signature_prefix)
	if start < 0:
		return ""
	# Find the next top-level "\nfunc " after this function's own signature line.
	var after_signature: int = content.find("\n", start) + 1
	var next_func: int = content.find("\nfunc ", after_signature)
	if next_func < 0:
		next_func = content.length()
	return content.substr(after_signature, next_func - after_signature)


func test_resolve_weapon_attack_body_contains_no_direct_rng_calls() -> void:
	var content: String = _read_file(RESOLUTION_PATH)
	var body: String = _extract_function_body(content, "func resolve_weapon_attack(")

	assert_false(
		body.contains("_rng.d20()"),
		"CR-001/FEAT-001: resolve_weapon_attack()'s own body must not call _rng.d20() directly -- all dice rolls must live in resolve_to_hit()/apply_on_hit_defense(), never duplicated in the thin wrapper"
	)
	assert_false(
		body.contains("_rng.roll("),
		"CR-001/FEAT-001: resolve_weapon_attack()'s own body must not call _rng.roll() directly -- all dice rolls must live in resolve_to_hit()/apply_on_hit_defense(), never duplicated in the thin wrapper"
	)


func test_resolve_weapon_attack_body_does_not_restate_crit_formula() -> void:
	var content: String = _read_file(RESOLUTION_PATH)
	var body: String = _extract_function_body(content, "func resolve_weapon_attack(")

	# NOTE: the needle is built via concatenation (rather than one contiguous
	# string literal) so THIS test file itself does not trip
	# tests/characterization/test_strike_characterization.gd's repo-wide
	# static scan for the same formula (which recursively scans res://core,
	# including this file's own directory).
	var crit_formula_needle: String = "roll_total - defense_value" + ") >= 10"
	assert_false(
		body.contains(crit_formula_needle),
		"CR-001/FEAT-001: the crit-threshold formula must live ONLY in resolve_to_hit(), not be restated inside resolve_weapon_attack()'s thin-wrapper body"
	)


func test_resolve_to_hit_and_apply_on_hit_defense_each_appear_exactly_once() -> void:
	## Sanity that the extraction produced exactly one definition of each new
	## function (no accidental duplicate/leftover copy).
	var content: String = _read_file(RESOLUTION_PATH)

	assert_eq(
		content.count("func resolve_to_hit("), 1,
		"resolution.gd must define resolve_to_hit() exactly once"
	)
	assert_eq(
		content.count("func apply_on_hit_defense("), 1,
		"resolution.gd must define apply_on_hit_defense() exactly once"
	)


func test_resolve_weapon_attack_delegates_to_both_phase_functions() -> void:
	var content: String = _read_file(RESOLUTION_PATH)
	var body: String = _extract_function_body(content, "func resolve_weapon_attack(")

	assert_true(
		body.contains("resolve_to_hit("),
		"resolve_weapon_attack() must delegate to resolve_to_hit() rather than re-implementing pre-hit math"
	)
	assert_true(
		body.contains("apply_on_hit_defense("),
		"resolve_weapon_attack() must delegate to apply_on_hit_defense() rather than re-implementing post-hit math"
	)
