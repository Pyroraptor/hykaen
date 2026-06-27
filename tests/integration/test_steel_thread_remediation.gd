extends GutTest
## tests/integration/test_steel_thread_remediation.gd
##
## FEAT-064: Steel Thread Remediation End-to-End Integration Smoke Test.
## Validates the KEPT remediation features end-to-end with pinned-seed determinism.
##
##   (a) FEAT-059 — Four active defenses (Dodge/Block/Parry/Steel) resolve correctly
##       through resolution.gd and each consumes one round action via ActionEconomy.
##       test_active_defenses_resolve_end_to_end()
##
##   (b) FEAT-058 — combine_actions() repeat-trait + reaction combinations with
##       stamina deduction, plus counter-strike resolution.
##       test_combination_riposte()
##
##   (c) FEAT-061 — The three non-Titus characters (gram_marx / marigold /
##       dwarf_channeler) load with non-empty starting_equipment and their equipped
##       weapons expose block_value / parry_bonus.
##       test_non_titus_characters_equipped()
##
##   (d) FEAT-057 — The spec-content CI gate (lint-spec-content-keywords) is present
##       and checks all required keyword categories in .github/workflows/test.yml.
##       test_spec_content_ci_gates_present_in_test_yml()
##
## Exit condition:
##   'godot --headless -- --gut-run-all' exits 0 across tests/unit,
##   tests/integration, tests/sim with zero FAIL lines.
##
## OUT OF SCOPE for this iteration (do NOT assert on):
##   - Enemy-AI module
##   - Real-d12 balance retune / N=1000
##   - primary_offensive_attribute schema field
##
## Satisfies: US-001 through US-009, FEAT-064 acceptance criteria.

const ResolutionClass    = preload("res://core/rules/resolution.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")
const CharacterResource  = preload("res://core/model/character_resource.gd")
const WeaponResource     = preload("res://core/model/weapon_resource.gd")


## ─────────────────────────────────────────────────────────────────────────────
## SequenceRNG — multi-step pinned RNG stub for active defense tests.
##
## Returns successive values from pre-loaded d20 and roll sequences.
## Each d20() call consumes the next element of d20_seq (wraps on exhaustion).
## Each roll() call consumes the next element of roll_seq (wraps on exhaustion).
##
## Matches the SequenceRNG used in tests/unit/test_resolution.gd — the same
## pinned sequences produce the same deterministic outcomes.
## Satisfies: ADR-002 RNG injection requirement.
## ─────────────────────────────────────────────────────────────────────────────
class SequenceRNG:
	var _d20_seq:  Array
	var _roll_seq: Array
	var _d20_idx:  int = 0
	var _roll_idx: int = 0

	func _init(d20_seq: Array, roll_seq: Array) -> void:
		_d20_seq  = d20_seq
		_roll_seq = roll_seq

	## Returns the next value from the d20 sequence (wraps around).
	func d20() -> int:
		var val: int = _d20_seq[_d20_idx % _d20_seq.size()]
		_d20_idx += 1
		return val

	## Returns the next value from the roll sequence (wraps around).
	func roll(_die_size: int, _count: int) -> int:
		var val: int = _roll_seq[_roll_idx % _roll_seq.size()]
		_roll_idx += 1
		return val


## ─────────────────────────────────────────────────────────────────────────────
## Shared test fixtures
##
## Attacker: strength=3, weapon.proficiency_bonus=2, weapon.damage_die=6
##   → attack modifier = 3 + 2 = 5 over the d20 result
##
## Pinned roll sequences (from tests/unit/test_resolution.gd FEAT-059 docs):
##
##   DODGE SUCCESS:  d20=[16,11] roll=[]   mob=16+dex(1)=17, attack=11+5=16; 16<17→miss
##   BLOCK HIT:      d20=[11]    roll=[4,2] attack=11+5=16>=ac(13)→hit; dmg=4+3=7; block=2+3=5; final=2
##   PARRY SUCCESS:  d20=[11,14] roll=[4]  attack=16→hit; dmg=7; parry=14+4=18>16→final=0
##   STEEL SUCCESS:  d20=[16,11] roll=[]   det=16+wil(1)=17, attack=16; 16<17→miss
## ─────────────────────────────────────────────────────────────────────────────

## Standard attacker with strength=3 (attack/damage modifier).
var _attacker: Dictionary = {
	"strength":     3,
	"dexterity":    1,
	"constitution": 2,
	"willpower":    1,
	"intellect":    1,
	"intuition":    1,
	"social":       1
}

## Standard weapon: d6, strength-based, +2 proficiency bonus.
var _weapon: Dictionary = {
	"damage_modifier_attribute": "strength",
	"proficiency_bonus":         2,
	"damage_die":                6
}

## Active-defense target: augmented with dexterity (Dodge/Mobility check)
## and willpower (Steel/Determination check), plus conscious flag.
var _ad_target: Dictionary = {
	"ac":        13,
	"reflex":    12,
	"fortitude": 14,
	"will":      11,
	"dexterity": 1,
	"willpower": 1,
	"conscious": true
}

## Blocking weapon: d6 die + block_value=3 (matches longsword block stat).
var _block_weapon: Dictionary = {
	"damage_die":  6,
	"block_value": 3
}

## Parrying weapon: parry_bonus=4 (matches longsword parry stat per Weapons.pdf).
var _parry_weapon: Dictionary = {
	"parry_bonus": 4
}


## Resources loaded once and reused across all tests (FEAT-061 characters).
var _gram_marx:       Resource = null
var _marigold:        Resource = null
var _dwarf_channeler: Resource = null


func before_all() -> void:
	_gram_marx       = ResourceLoader.load("res://data/characters/gram_marx.tres")
	_marigold        = ResourceLoader.load("res://data/characters/marigold.tres")
	_dwarf_channeler = ResourceLoader.load("res://data/characters/dwarf_channeler.tres")


# ── Helper factories ──────────────────────────────────────────────────────────

## Build a Resolution backed by a fresh SequenceRNG with the given sequences.
func _make_seq_res(d20_seq: Array, roll_seq: Array) -> ResolutionClass:
	var rng = SequenceRNG.new(d20_seq, roll_seq)
	return ResolutionClass.new(rng)


## Build a fresh ActionEconomy with start_of_turn() already called (budget=7).
func _make_full_ae() -> ActionEconomyClass:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	return ae


# ══════════════════════════════════════════════════════════════════════════════
# (a) FEAT-059 — test_active_defenses_resolve_end_to_end
#
# With pinned-seed SequenceRNG sequences, exercises each of the four active
# defenses (Dodge / Block / Parry / Steel) through the resolution.gd pipeline.
#
# For each defense, asserts:
#   • active_defense_applied matches the chosen defense type.
#   • damage outcome is correct (miss=0, block-reduction=2, parry-negate=0, steel-miss=0).
#   • ActionEconomy budget decrements from 7 → 6 after the reaction fires.
#
# Pinned RNG sequences are documented inline below.
# Satisfies: FEAT-059, FEAT-064 test criterion 1.
# ══════════════════════════════════════════════════════════════════════════════

func test_active_defenses_resolve_end_to_end() -> void:
	# ── Dodge ─────────────────────────────────────────────────────────────────
	#
	# Sequence: d20=[16, 11], roll=[]
	#   Call 1 (Mobility check): mob_d20=16 → mobility_check = 16 + dex(1) = 17
	#   Call 2 (attack roll):    attack_d20=11 → roll_total = 11 + str(3) + prof(2) = 16
	#   16 < 17 → Dodge negates the attack → hit=false, damage_final=0
	#
	var ae_dodge = _make_full_ae()
	assert_eq(ae_dodge.get_remaining(), 7,
		"[DODGE] ActionEconomy must start at budget=7")

	var res_dodge = _make_seq_res([16, 11], [])
	var result_dodge: Dictionary = res_dodge.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac",
		"dodge", {"action_economy": ae_dodge}
	)

	assert_false(result_dodge["hit"],
		"[DODGE] roll_total=16 < mobility_check=17 → hit must be false (attack negated)")
	assert_eq(result_dodge["damage_final"], 0,
		"[DODGE] attack negated → damage_final must be 0")
	assert_eq(result_dodge["active_defense_applied"], "dodge",
		"[DODGE] active_defense_applied must be 'dodge'")
	assert_true(result_dodge["defender_stepped"],
		"[DODGE] defender_stepped must be true after successful Dodge (defender Steps away)")
	assert_eq(ae_dodge.get_remaining(), 6,
		"[DODGE] Dodge reaction consumes 1 action: budget must decrement 7 → 6")

	# ── Block ─────────────────────────────────────────────────────────────────
	#
	# Sequence: d20=[11], roll=[4, 2]
	#   Attack:       attack_d20=11 → roll_total = 11 + str(3) + prof(2) = 16 >= ac(13) → hit
	#   Damage roll:  roll(6,1) = 4  → damage_raw = 4 + str(3) = 7
	#   Block roll:   roll(6,1) = 2  → block_reduction = 2 + block_value(3) = 5
	#   damage_final  = max(0, 7 - 5) = 2
	#
	var ae_block = _make_full_ae()
	assert_eq(ae_block.get_remaining(), 7,
		"[BLOCK] ActionEconomy must start at budget=7")

	var res_block = _make_seq_res([11], [4, 2])
	var result_block: Dictionary = res_block.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac",
		"block", {"action_economy": ae_block, "blocking_weapon": _block_weapon}
	)

	assert_true(result_block["hit"],
		"[BLOCK] roll_total=16 >= ac=13 → hit must be true (Block fires post-hit)")
	assert_eq(result_block["damage_raw"], 7,
		"[BLOCK] damage_raw must be 4 + str(3) = 7 (before block reduction)")
	assert_eq(result_block["damage_final"], 2,
		"[BLOCK] damage_final must be max(0, 7 - 5) = 2 after 1[W](2) + block_value(3) = 5 reduction")
	assert_eq(result_block["active_defense_applied"], "block",
		"[BLOCK] active_defense_applied must be 'block'")
	assert_true(result_block["on_hit_suppressed"],
		"[BLOCK] on_hit_suppressed must be true (Combat.pdf: on-hit effects do not occur)")
	assert_eq(ae_block.get_remaining(), 6,
		"[BLOCK] Block reaction consumes 1 action: budget must decrement 7 → 6")

	# ── Parry ─────────────────────────────────────────────────────────────────
	#
	# Sequence: d20=[11, 14], roll=[4]
	#   Attack:      attack_d20=11 → roll_total = 16 >= ac(13) → hit
	#   Damage roll: roll(6,1) = 4  → damage_raw = 4 + str(3) = 7
	#   Parry roll:  parry_d20=14   → parry_roll = 14 + parry_bonus(4) = 18
	#   18 > roll_total(16) → Parry success → damage_final = 0, on_hit_suppressed = true
	#
	var ae_parry = _make_full_ae()
	assert_eq(ae_parry.get_remaining(), 7,
		"[PARRY] ActionEconomy must start at budget=7")

	var res_parry = _make_seq_res([11, 14], [4])
	var result_parry: Dictionary = res_parry.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac",
		"parry", {"action_economy": ae_parry, "parrying_weapon": _parry_weapon}
	)

	assert_true(result_parry["hit"],
		"[PARRY] roll_total=16 >= ac=13 → originally a hit (Parry fires post-hit)")
	assert_eq(result_parry["damage_final"], 0,
		"[PARRY] parry_roll=18 > roll_total=16 → Parry success → damage_final must be 0")
	assert_eq(result_parry["active_defense_applied"], "parry",
		"[PARRY] active_defense_applied must be 'parry'")
	assert_true(result_parry["on_hit_suppressed"],
		"[PARRY] on_hit_suppressed must be true (attack deflected)")
	assert_eq(ae_parry.get_remaining(), 6,
		"[PARRY] Parry reaction consumes 1 action: budget must decrement 7 → 6")

	# ── Steel ─────────────────────────────────────────────────────────────────
	#
	# Sequence: d20=[16, 11], roll=[]
	#   Call 1 (Determination check): det_d20=16 → det_check = 16 + willpower(1) = 17
	#   Call 2 (attack roll):         attack_d20=11 → roll_total = 16
	#   Effective defense = 17; 16 < 17 → Steel resists → hit=false, next_check_bonus=2
	#
	var ae_steel = _make_full_ae()
	assert_eq(ae_steel.get_remaining(), 7,
		"[STEEL] ActionEconomy must start at budget=7")

	var res_steel = _make_seq_res([16, 11], [])
	var result_steel: Dictionary = res_steel.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "fortitude",
		"steel", {"action_economy": ae_steel}
	)

	assert_false(result_steel["hit"],
		"[STEEL] roll_total=16 < determination=17 → hit must be false (attack resisted)")
	assert_eq(result_steel["damage_final"], 0,
		"[STEEL] attack resisted → damage_final must be 0")
	assert_eq(result_steel["active_defense_applied"], "steel",
		"[STEEL] active_defense_applied must be 'steel'")
	assert_eq(result_steel["next_check_bonus"], 2,
		"[STEEL] next_check_bonus must be +2 when the attack is resisted")
	assert_eq(ae_steel.get_remaining(), 6,
		"[STEEL] Steel reaction consumes 1 action: budget must decrement 7 → 6")


# ══════════════════════════════════════════════════════════════════════════════
# (b) FEAT-058 — test_combination_riposte
#
# Validates the combine_actions() Parry+Strike combination:
#   1. combine_actions(parry_with_Repeat, strike_with_Repeat, stamina=5) succeeds
#      and returns stamina_remaining = 4 (1 stamina spent).
#   2. The Parry resolves against an incoming attack → damage_final = 0.
#   3. The counter-Strike (riposte) resolves against a target → hit, damage_final > 0.
#
# This proves the full FEAT-058 path: Repeat-trait validation → stamina deduction
# → Parry defense resolves → counter-attack resolves.
#
# Satisfies: FEAT-058, FEAT-064 test criterion 2.
# ══════════════════════════════════════════════════════════════════════════════

func test_combination_riposte() -> void:
	var ae = _make_full_ae()

	# ── Step 1: validate the Parry+Strike combination ─────────────────────────
	# Both actions must carry the "Repeat" trait.
	# combine_actions() checks for Repeat, verifies stamina >= 1, and returns
	# stamina_remaining = stamina_pool - 1.
	var parry_action: Dictionary  = {"name": "Parry",  "traits": ["Repeat"]}
	var strike_action: Dictionary = {"name": "Strike", "traits": ["Repeat"]}
	const STAMINA_POOL: int = 5

	var combine_result: Dictionary = ae.combine_actions(
		parry_action, strike_action, STAMINA_POOL
	)
	assert_true(combine_result["success"],
		"combine_actions(Parry[Repeat]+Strike[Repeat], stamina=5) must succeed")
	assert_eq(combine_result["stamina_remaining"], STAMINA_POOL - 1,
		"combine_actions: stamina_remaining must be %d (pool %d − 1 spent)"
		% [STAMINA_POOL - 1, STAMINA_POOL])

	# ── Step 2: resolve the Parry defense (incoming attack triggers the reaction)
	# Sequence: d20=[11,14], roll=[4]
	#   attack_d20=11 → roll_total=16 → hit; damage_raw=4+str(3)=7
	#   parry_d20=14  → parry_roll=14+parry_bonus(4)=18 > roll_total(16)
	#   → Parry success → damage_final=0, on_hit_suppressed=true
	var res_parry = _make_seq_res([11, 14], [4])
	var parry_result: Dictionary = res_parry.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac",
		"parry", {"parrying_weapon": _parry_weapon}
	)
	assert_true(parry_result["hit"],
		"[Riposte Parry] roll_total=16 >= ac=13 → originally a hit (parry fires post-hit)")
	assert_eq(parry_result["damage_final"], 0,
		"[Riposte Parry] parry_roll=18 > roll_total=16 → damage_final must be 0 (attack deflected)")
	assert_eq(parry_result["active_defense_applied"], "parry",
		"[Riposte Parry] active_defense_applied must be 'parry'")
	assert_true(parry_result["on_hit_suppressed"],
		"[Riposte Parry] on_hit_suppressed must be true (attack deflected by parry)")

	# ── Step 3: resolve the counter-Strike (riposte attack) ──────────────────
	# Sequence: d20=[11], roll=[4]
	#   attack_d20=11 → roll_total=11+str(3)+prof(2)=16 >= ac(13) → hit
	#   damage = roll(6,1)=4 + str(3) = 7
	var counter_target: Dictionary = {
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"dexterity": 1, "willpower": 1, "conscious": true
	}
	var res_strike = _make_seq_res([11], [4])
	var strike_result: Dictionary = res_strike.resolve_weapon_attack(
		_attacker, counter_target, _weapon, "ac"
	)
	assert_true(strike_result["hit"],
		"[Riposte Strike] roll_total=16 >= ac=13 → counter-strike must hit")
	assert_true(strike_result["damage_final"] > 0,
		"[Riposte Strike] counter-strike hit must produce damage_final > 0; got %d"
		% strike_result["damage_final"])


# ══════════════════════════════════════════════════════════════════════════════
# (c) FEAT-061 — test_non_titus_characters_equipped
#
# Verifies that gram_marx / marigold / dwarf_channeler each:
#   (i)   Load as non-null CharacterResource instances.
#   (ii)  Have a non-empty starting_equipment Array.
#   (iii) Their first starting_equipment path loads as a WeaponResource.
#   (iv)  That WeaponResource exposes block_value and parry_bonus (both > 0).
#
# Expected weapons:
#   gram_marx       → quarterstaff.tres  (block_value=1, parry_bonus=2)
#   marigold        → shortsword.tres    (block_value=1, parry_bonus=4)
#   dwarf_channeler → mace.tres          (block_value=2, parry_bonus=1)
#
# Satisfies: FEAT-061, FEAT-064 test criterion 3.
# ══════════════════════════════════════════════════════════════════════════════

func test_non_titus_characters_equipped() -> void:
	# ── Gram Marx (Tiefling Wizard) ───────────────────────────────────────────
	# Expected: starting_equipment[0] = "res://data/weapons/quarterstaff.tres"
	#           quarterstaff: block_value=1, parry_bonus=2
	assert_not_null(_gram_marx,
		"gram_marx.tres must load non-null (FEAT-061)")
	if _gram_marx != null:
		assert_true(
			_gram_marx.starting_equipment.size() > 0,
			"gram_marx.starting_equipment must be non-empty (FEAT-061); got size=%d"
			% _gram_marx.starting_equipment.size()
		)
		if _gram_marx.starting_equipment.size() > 0:
			var gram_weapon_path: String = str(_gram_marx.starting_equipment[0])
			var gram_weapon = ResourceLoader.load(gram_weapon_path)
			assert_not_null(gram_weapon,
				"gram_marx starting_equipment[0] must load as non-null from '%s' (FEAT-061)"
				% gram_weapon_path)
			if gram_weapon != null:
				assert_true(
					gram_weapon is WeaponResource,
					"gram_marx starting_equipment[0] ('%s') must be a WeaponResource (FEAT-061)"
					% gram_weapon_path
				)
				if gram_weapon is WeaponResource:
					assert_true(
						gram_weapon.block_value > 0,
						"gram_marx weapon block_value must be > 0 (FEAT-061); got %d" % gram_weapon.block_value
					)
					assert_true(
						gram_weapon.parry_bonus > 0,
						"gram_marx weapon parry_bonus must be > 0 (FEAT-061); got %d" % gram_weapon.parry_bonus
					)

	# ── Marigold (Elven Divine Warrior) ──────────────────────────────────────
	# Expected: starting_equipment[0] = "res://data/weapons/shortsword.tres"
	#           shortsword: block_value=1, parry_bonus=4
	assert_not_null(_marigold,
		"marigold.tres must load non-null (FEAT-061)")
	if _marigold != null:
		assert_true(
			_marigold.starting_equipment.size() > 0,
			"marigold.starting_equipment must be non-empty (FEAT-061); got size=%d"
			% _marigold.starting_equipment.size()
		)
		if _marigold.starting_equipment.size() > 0:
			var marigold_weapon_path: String = str(_marigold.starting_equipment[0])
			var marigold_weapon = ResourceLoader.load(marigold_weapon_path)
			assert_not_null(marigold_weapon,
				"marigold starting_equipment[0] must load as non-null from '%s' (FEAT-061)"
				% marigold_weapon_path)
			if marigold_weapon != null:
				assert_true(
					marigold_weapon is WeaponResource,
					"marigold starting_equipment[0] ('%s') must be a WeaponResource (FEAT-061)"
					% marigold_weapon_path
				)
				if marigold_weapon is WeaponResource:
					assert_true(
						marigold_weapon.block_value > 0,
						"marigold weapon block_value must be > 0 (FEAT-061); got %d" % marigold_weapon.block_value
					)
					assert_true(
						marigold_weapon.parry_bonus > 0,
						"marigold weapon parry_bonus must be > 0 (FEAT-061); got %d" % marigold_weapon.parry_bonus
					)

	# ── Dwarf Channeler (Dwarf Divine Channeler) ──────────────────────────────
	# Expected: starting_equipment[0] = "res://data/weapons/mace.tres"
	#           mace: block_value=2, parry_bonus=1
	assert_not_null(_dwarf_channeler,
		"dwarf_channeler.tres must load non-null (FEAT-061)")
	if _dwarf_channeler != null:
		assert_true(
			_dwarf_channeler.starting_equipment.size() > 0,
			"dwarf_channeler.starting_equipment must be non-empty (FEAT-061); got size=%d"
			% _dwarf_channeler.starting_equipment.size()
		)
		if _dwarf_channeler.starting_equipment.size() > 0:
			var dwarf_weapon_path: String = str(_dwarf_channeler.starting_equipment[0])
			var dwarf_weapon = ResourceLoader.load(dwarf_weapon_path)
			assert_not_null(dwarf_weapon,
				"dwarf_channeler starting_equipment[0] must load as non-null from '%s' (FEAT-061)"
				% dwarf_weapon_path)
			if dwarf_weapon != null:
				assert_true(
					dwarf_weapon is WeaponResource,
					"dwarf_channeler starting_equipment[0] ('%s') must be a WeaponResource (FEAT-061)"
					% dwarf_weapon_path
				)
				if dwarf_weapon is WeaponResource:
					assert_true(
						dwarf_weapon.block_value > 0,
						"dwarf_channeler weapon block_value must be > 0 (FEAT-061); got %d" % dwarf_weapon.block_value
					)
					assert_true(
						dwarf_weapon.parry_bonus > 0,
						"dwarf_channeler weapon parry_bonus must be > 0 (FEAT-061); got %d" % dwarf_weapon.parry_bonus
					)


# ══════════════════════════════════════════════════════════════════════════════
# (d) FEAT-057 — test_spec_content_ci_gates_present_in_test_yml
#
# Reads .github/workflows/test.yml and asserts that the lint-spec-content-keywords
# CI step is present and verifies all required keyword categories:
#   1. 'lint-spec-content-keywords' step name present.
#   2. All seven attribute names (strength, constitution, dexterity, willpower,
#      intellect, intuition, social) are checked by the gate.
#   3. HP formula marker 'HP =' is checked.
#   4. All four defense keywords (AC, Reflex, Fortitude, Will) are checked.
#   5. Action set keywords (Strike, Stride) are checked.
#   6. Armor table marker ('ac_base' or '| Armor') is checked.
#   7. Talent tree marker 'talent' is checked.
#
# Mirrors the lint-spec-content-keywords CI gate at the GUT-test layer so that
# local GUT runs catch the same condition without running the CI pipeline first.
#
# Satisfies: FEAT-057, FEAT-064 test criterion 4.
# ══════════════════════════════════════════════════════════════════════════════

func test_spec_content_ci_gates_present_in_test_yml() -> void:
	var file := FileAccess.open("res://.github/workflows/test.yml", FileAccess.READ)
	assert_not_null(file,
		".github/workflows/test.yml must be readable — CI gate must be present (FEAT-057)")
	if file == null:
		return

	var content: String = file.get_as_text()
	file.close()

	# (1) The lint-spec-content-keywords step must be present
	assert_true(
		content.contains("lint-spec-content-keywords"),
		"test.yml must contain the 'lint-spec-content-keywords' CI step (FEAT-057 DEF-NEW-001)"
	)

	# (2) All seven attribute names must be checked by the gate
	var required_attributes: Array = [
		"strength", "constitution", "dexterity",
		"willpower", "intellect", "intuition", "social"
	]
	for attr in required_attributes:
		assert_true(
			content.contains(attr),
			("test.yml lint-spec-content-keywords must check for attribute keyword '%s' (FEAT-057)")
			% attr
		)

	# (3) HP formula marker 'HP =' must be checked
	assert_true(
		content.contains("HP ="),
		"test.yml lint-spec-content-keywords must check for 'HP =' formula marker (FEAT-057)"
	)

	# (4) All four defense keywords must be checked
	var required_defenses: Array = ["AC", "Reflex", "Fortitude", "Will"]
	for kw in required_defenses:
		assert_true(
			content.contains(kw),
			("test.yml lint-spec-content-keywords must check for defense keyword '%s' (FEAT-057)")
			% kw
		)

	# (5) Action set keywords (Strike, Stride) must be checked
	var required_actions: Array = ["Strike", "Stride"]
	for kw in required_actions:
		assert_true(
			content.contains(kw),
			("test.yml lint-spec-content-keywords must check for action keyword '%s' (FEAT-057)")
			% kw
		)

	# (6) Armor table marker must be checked ('ac_base' or '| Armor')
	assert_true(
		content.contains("ac_base") or content.contains("| Armor"),
		"test.yml lint-spec-content-keywords must check for armor table marker 'ac_base' or '| Armor' (FEAT-057)"
	)

	# (7) Talent tree marker 'talent' must be checked
	assert_true(
		content.contains("talent"),
		"test.yml lint-spec-content-keywords must check for 'talent' tree marker (FEAT-057)"
	)
