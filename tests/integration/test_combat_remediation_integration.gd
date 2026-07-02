extends GutTest
## tests/integration/test_combat_remediation_integration.gd
##
## FEAT-064: CR-001 Combat Remediation End-to-End Integration Smoke Test.
## Validates the KEPT remediation features end-to-end with pinned-seed determinism.
##
## DEF-005 (US-011) naming note: the CR-001 sections of this suite construct
## core/combat/encounter.gd DIRECTLY (EncounterClass.new(...).run_round()) —
## a construction path MainScene.gd documents as intentionally never invoked
## in production. This file is NOT the "steel thread" in the sense of
## booting the real composition root (res://MainScene.tscn); that end-to-end
## boot path is exercised exclusively by
## tests/integration/test_steel_thread_prologue_encounter.gd and
## tests/gut/test_steel_thread_e2e.gd. This file's name intentionally avoids
## the "steel thread" label to keep that distinction unambiguous.
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
##
## ─────────────────────────────────────────────────────────────────────────────
## CR-001 / FEAT-104 (US-007) — peer-review BLOCKER fix:
##
## docs/change-requests/CR-001-action-economy.org § "Verification" names this
## file as one of FIVE GUT suites that MUST be rewritten (not weakened) to
## assert the corrected PER-ROUND action-economy model:
##   _budget is a per-ROUND resource shared across a combatant's turns AND
##   out-of-turn reactions (AC-3); only start_of_round()/end_of_round() may
##   reset it to MAX_BUDGET/clear is_spent (AC-2); start_of_turn() clears
##   ONLY the per-TURN _movement_used flag and must NEVER be relied upon to
##   "give back" a fresh budget (AC-1) — that was the original FEAT-007 bug
##   CR-001 corrects.
##
## A peer-review pass found this file had been left untouched: the
## _make_full_ae() helper below established its "budget=7" fixture via
## start_of_turn() — encoding the OLD (incorrect) per-turn mental model even
## though it happened to still pass (ActionEconomy.new() already defaults to
## budget=7, masking the misuse). This CR:
##   (1) corrects _make_full_ae() to call start_of_round() — the ONLY
##       contractually-correct way to establish a fresh per-round budget —
##       and documents why (see below);
##   (2) annotates every budget-bearing assertion block in
##       test_active_defenses_resolve_end_to_end() / test_combination_riposte()
##       with a CR-001 comment explaining the corrected rationale (AC-2/AC-3);
##   (3) adds NEW assertions (below, in the "CR-001 / FEAT-104" section at the
##       end of this file) proving (a) budget_remaining/is_spent persist
##       across a combatant's multiple turns within one round and reset
##       EXACTLY ONCE at the round boundary, and (b) a reaction spent
##       out-of-turn measurably reduces the budget available on that same
##       combatant's later turn in the SAME round — using TYPED
##       RoundEvents.* value-object access (core/rules/round_events.gd),
##       never raw Dictionary indexing, per FEAT-099/FIND-096.
##
## Satisfies: FR-001, FR-002, FR-003, ADR-001, ADR-002, CR-001 AC-1/AC-2/AC-3,
## CHECKLIST-2.
## ─────────────────────────────────────────────────────────────────────────────

const ResolutionClass    = preload("res://core/rules/resolution.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")
const CharacterResource  = preload("res://core/model/character_resource.gd")
const WeaponResource     = preload("res://core/model/weapon_resource.gd")
## CR-001/FEAT-104: EncounterClass/RNGClass/RoundEventsClass are required so
## the new round-boundary / typed-event assertions below can drive a real
## Encounter round loop and read its observability surface
## (get_round_events()/get_round_history()) via TYPED RoundEvents.* value
## objects — `is RoundEventsClass.X` + `.to_dict()` — rather than raw
## Dictionary indexing (FEAT-099/FIND-096 contract).
const EncounterClass     = preload("res://core/combat/encounter.gd")
const RNGClass            = preload("res://core/rules/rng.gd")
const RoundEventsClass    = preload("res://core/rules/round_events.gd")


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


## Build a fresh ActionEconomy with a freshly-granted per-ROUND budget (budget=7).
##
## CR-001/FEAT-104 CORRECTION: the pre-remediation version of this helper
## called ONLY start_of_turn() to "fill" the budget. That encoded the OLD,
## incorrect per-turn model (it happened to still read budget=7 only because
## ActionEconomy.new() already defaults _budget=MAX_BUDGET — start_of_turn()
## itself contributes nothing to that value). Per CR-001 AC-1/AC-2,
## start_of_turn() clears ONLY the per-TURN _movement_used flag and must
## NEVER be relied upon as a budget-refill point — start_of_round() (or
## end_of_round()) is the SOLE operation permitted to (re)establish
## budget_remaining=MAX_BUDGET/is_spent=false for a round. This helper now
## calls start_of_round() explicitly so every test built on it exercises the
## contractually-correct round-start sequence, then start_of_turn() for the
## first turn's per-turn flag clear (mirrors real usage: start_of_round()
## once per round, start_of_turn() once per turn).
func _make_full_ae() -> ActionEconomyClass:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
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
	# CR-001/FEAT-104 (AC-2): budget=7 here must come from _make_full_ae()'s
	# start_of_round() call — the SOLE round-boundary operation permitted to
	# establish MAX_BUDGET — never from start_of_turn() alone (the pre-CR-001
	# bug). See _make_full_ae() doc comment above.
	var ae_dodge = _make_full_ae()
	assert_eq(ae_dodge.get_remaining(), 7,
		"[DODGE] ActionEconomy must start at budget=7 (CR-001 AC-2: via start_of_round(), not start_of_turn())")

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
	# CR-001 AC-3: a Dodge reaction draws from the SAME shared per-ROUND
	# budget that spend_action() draws from — there is no separate
	# "reaction pool". This is what makes the decrement observable here at all.
	assert_eq(ae_dodge.get_remaining(), 6,
		"[DODGE] Dodge reaction consumes 1 action: budget must decrement 7 → 6 (CR-001 AC-3: shared action/reaction pool)")

	# ── Block ─────────────────────────────────────────────────────────────────
	#
	# Sequence: d20=[11], roll=[4, 2]
	#   Attack:       attack_d20=11 → roll_total = 11 + str(3) + prof(2) = 16 >= ac(13) → hit
	#   Damage roll:  roll(6,1) = 4  → damage_raw = 4 + str(3) = 7
	#   Block roll:   roll(6,1) = 2  → block_reduction = 2 + block_value(3) = 5
	#   damage_final  = max(0, 7 - 5) = 2
	#
	# CR-001/FEAT-104 (AC-2): see DODGE block above — budget=7 is established
	# by start_of_round(), not start_of_turn().
	var ae_block = _make_full_ae()
	assert_eq(ae_block.get_remaining(), 7,
		"[BLOCK] ActionEconomy must start at budget=7 (CR-001 AC-2: via start_of_round(), not start_of_turn())")

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
	# CR-001 AC-3: Block (like Dodge) is a reaction drawing from the shared
	# per-ROUND budget — same pool spend_action() uses, not a separate
	# reaction allowance.
	assert_eq(ae_block.get_remaining(), 6,
		"[BLOCK] Block reaction consumes 1 action: budget must decrement 7 → 6 (CR-001 AC-3: shared action/reaction pool)")

	# ── Parry ─────────────────────────────────────────────────────────────────
	#
	# Sequence: d20=[11, 14], roll=[4]
	#   Attack:      attack_d20=11 → roll_total = 16 >= ac(13) → hit
	#   Damage roll: roll(6,1) = 4  → damage_raw = 4 + str(3) = 7
	#   Parry roll:  parry_d20=14   → parry_roll = 14 + parry_bonus(4) = 18
	#   18 > roll_total(16) → Parry success → damage_final = 0, on_hit_suppressed = true
	#
	# CR-001/FEAT-104 (AC-2): see DODGE block above — budget=7 is established
	# by start_of_round(), not start_of_turn().
	var ae_parry = _make_full_ae()
	assert_eq(ae_parry.get_remaining(), 7,
		"[PARRY] ActionEconomy must start at budget=7 (CR-001 AC-2: via start_of_round(), not start_of_turn())")

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
	# CR-001 AC-3: Parry is a reaction drawing from the shared per-ROUND
	# budget — same pool spend_action() uses.
	assert_eq(ae_parry.get_remaining(), 6,
		"[PARRY] Parry reaction consumes 1 action: budget must decrement 7 → 6 (CR-001 AC-3: shared action/reaction pool)")

	# ── Steel ─────────────────────────────────────────────────────────────────
	#
	# Sequence: d20=[16, 11], roll=[]
	#   Call 1 (Determination check): det_d20=16 → det_check = 16 + willpower(1) = 17
	#   Call 2 (attack roll):         attack_d20=11 → roll_total = 16
	#   Effective defense = 17; 16 < 17 → Steel resists → hit=false, next_check_bonus=2
	#
	# CR-001/FEAT-104 (AC-2): see DODGE block above — budget=7 is established
	# by start_of_round(), not start_of_turn().
	var ae_steel = _make_full_ae()
	assert_eq(ae_steel.get_remaining(), 7,
		"[STEEL] ActionEconomy must start at budget=7 (CR-001 AC-2: via start_of_round(), not start_of_turn())")

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
	# CR-001 AC-3: Steel is a reaction drawing from the shared per-ROUND
	# budget — same pool spend_action() uses.
	assert_eq(ae_steel.get_remaining(), 6,
		"[STEEL] Steel reaction consumes 1 action: budget must decrement 7 → 6 (CR-001 AC-3: shared action/reaction pool)")


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
	# CR-001/FEAT-104 (AC-2): budget=7 here comes from _make_full_ae()'s
	# start_of_round() call, not start_of_turn() (see helper doc comment).
	# combine_actions() itself never touches _budget (asserted separately in
	# tests/unit/test_action_economy.gd's
	# test_combine_actions_success_does_not_modify_budget()) — this fixture
	# only needs a contractually-valid fresh-round ActionEconomy to pass in.
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


# ══════════════════════════════════════════════════════════════════════════════
# (e) CR-001 / FEAT-104 (US-007, CHECKLIST-2) — corrected per-ROUND budget /
#     Spent / dazed semantics, asserted via TYPED RoundEvents.* access.
#
# This section is the peer-review BLOCKER fix for this file: it adds the
# CR-001-mandated assertions that were previously ONLY covered by
# tests/unit/test_action_economy.gd, proving the corrected per-round model
# holds at BOTH the domain (ActionEconomy) layer and the integration
# (Encounter/RunRoundUseCase round-loop) layer:
#
#   test_budget_and_is_spent_persist_across_turns_then_reset_once_at_round_boundary()
#     — domain-level: budget_remaining/is_spent persist across a combatant's
#       MULTIPLE turns within ONE round (repeated start_of_turn() calls,
#       AC-4 interleaving) and reset EXACTLY ONCE at the round boundary
#       (a single end_of_round() call) — never mid-round.
#
#   test_parry_reaction_out_of_turn_reduces_budget_for_subsequent_own_turn_strike()
#     — integration-level (resolution.gd + action_economy.gd): a Parry
#       reaction spent OUT-OF-TURN (on an opponent's turn) measurably
#       reduces the budget available when this combatant's OWN turn comes
#       around later in the SAME round (AC-3 shared-pool contract).
#
#   test_titus_round_history_typed_entries_persist_budget_across_turns_and_reset_once_at_round_boundary()
#     — integration-level (core/combat/encounter.gd run_round() +
#       core/rules/round_events.gd RoundEvents.RoundHistoryEntry): drives a
#       REAL round loop and reads the typed history/event surface
#       (`is RoundEventsClass.X` / `.to_dict()`, never raw Dictionary
#       indexing) to prove the same persists/resets-once contract holds
#       end-to-end through RunRoundUseCase/ResolveActionUseCase.
#
#   test_round_events_are_typed_round_events_value_objects_not_raw_dictionaries()
#     — integration-level: confirms get_round_events() yields TYPED
#       RoundEvents.AttackEvent instances (FEAT-099/FIND-096), exercised via
#       `is` type-checks and `.to_dict()` snapshots.
#
# Satisfies: FR-001, FR-002, FR-003, ADR-001, ADR-002, CR-001 AC-1/AC-2/AC-3,
# CHECKLIST-2, FEAT-104 test criteria.
# ══════════════════════════════════════════════════════════════════════════════

## A durable combatant (hp=2000) that cannot die during a round — isolates
## the CR-001 budget-persistence/round-boundary-reset assertions below from
## win/loss early-termination (mirrors tests/test_encounter_round_loop.gd /
## tests/integration/test_encounter_integration.gd's identical pattern).
func _cr001_durable_titus() -> Dictionary:
	return {
		"name": "Titus",
		"hp_current": 2000,
		"ac": 14,
		"strength": 5,
		"dexterity": 2,
		"intuition": 2,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 12
		}
	}


## A durable enemy stub (hp=2000) — opposing side for _cr001_durable_titus().
func _cr001_durable_skeleton() -> Dictionary:
	return {
		"name": "Skeleton",
		"hp_current": 2000,
		"ac": 12,
		"strength": 2,
		"dexterity": 1,
		"intuition": 1,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 6
		}
	}


## CR-001 AC-1/AC-2 (domain-level): budget_remaining and is_spent must
## persist unchanged across a combatant's MULTIPLE turns within the SAME
## round (start_of_turn() is a documented no-op w.r.t. both, even called
## repeatedly — the AC-4 interleaving scenario), and must reset to
## MAX_BUDGET/false EXACTLY ONCE, only at the round boundary
## (end_of_round()/start_of_round()). This is the corrected replacement for
## the OLD per-turn assumption (that every start_of_turn() call implied a
## fresh budget) which CR-001 explicitly overturns — see
## docs/change-requests/CR-001-action-economy.org § "Defect".
func test_budget_and_is_spent_persist_across_turns_then_reset_once_at_round_boundary() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	assert_eq(ae.get_remaining(), 7,
		"CR-001 AC-2: start_of_round() establishes budget_remaining=MAX_BUDGET at the round boundary")
	assert_false(ae.is_spent(),
		"CR-001 AC-2: start_of_round() clears is_spent at the round boundary")

	# ── Turn 1 of the round ────────────────────────────────────────────────
	ae.start_of_turn()
	ae.spend_action({})
	ae.spend_action({})
	assert_eq(ae.get_remaining(), 5,
		"sanity check: 2 spends from budget=7 leaves 5")
	assert_false(ae.is_spent(), "is_spent must remain false with budget remaining")

	# ── Turn 2: this combatant's turn comes back around within the SAME
	# round (AC-4 interleaving) — start_of_turn() must NOT refill. ─────────
	ae.start_of_turn()
	assert_eq(ae.get_remaining(), 5,
		"CR-001 AC-1: budget_remaining must persist unchanged across the combatant's 2nd turn in the same round (start_of_turn() is a per-turn-flag-only no-op w.r.t. budget)")
	ae.spend_action({})
	ae.spend_action({})
	ae.spend_action({})
	assert_eq(ae.get_remaining(), 2,
		"sanity check: 3 more spends from 5 leaves 2")

	# ── Turn 3: a third pass through the round — budget keeps persisting. ──
	ae.start_of_turn()
	assert_eq(ae.get_remaining(), 2,
		"CR-001 AC-1: budget_remaining must persist unchanged across the combatant's 3rd turn in the same round")
	assert_false(ae.is_spent(), "is_spent must still be false with budget_remaining=2")
	ae.spend_action({})
	ae.spend_action({})
	assert_eq(ae.get_remaining(), 0,
		"sanity check: final 2 spends exhaust the 7-action round budget")
	assert_true(ae.is_spent(),
		"CR-001 AC-1: is_spent must become true exactly when budget_remaining reaches 0, while still within the same round (no round boundary has occurred yet)")

	# ── Round boundary — resets budget_remaining/is_spent EXACTLY ONCE. ────
	ae.end_of_round()
	assert_eq(ae.get_remaining(), 7,
		"CR-001 AC-2: end_of_round() resets budget_remaining to MAX_BUDGET at the round boundary")
	assert_false(ae.is_spent(),
		"CR-001 AC-2: end_of_round() clears is_spent at the round boundary")


## CR-001 AC-3 (integration-level): spend_action() and a reaction
## (Parry, resolved through core/rules/resolution.gd exactly as the DODGE/
## BLOCK/PARRY/STEEL blocks above exercise it) draw down the SAME per-ROUND
## budget regardless of turn ownership — a reaction spent OUT-OF-TURN (i.e.
## on what would be an opponent's turn) measurably reduces the budget
## available when this combatant's OWN turn comes around later in the SAME
## round. This is the corrected replacement for the old per-turn model,
## where an out-of-turn reaction's cost would have been silently wiped by
## the next start_of_turn() refill.
func test_parry_reaction_out_of_turn_reduces_budget_for_subsequent_own_turn_strike() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	assert_eq(ae.get_remaining(), 7,
		"CR-001 AC-2: start_of_round() establishes the fresh per-round budget")

	# ── Out-of-turn reaction: this combatant Parries an incoming attack on
	# what is, narratively, an opponent's turn — no start_of_turn() call for
	# this combatant has happened yet this round. ──────────────────────────
	# Sequence: d20=[11, 14], roll=[4]
	#   attack_d20=11 → roll_total=16 >= ac(13) → hit; damage_raw=4+str(3)=7
	#   parry_d20=14  → parry_roll=14+parry_bonus(4)=18 > roll_total(16)
	#   → Parry success → damage_final=0, on_hit_suppressed=true
	var res_parry = _make_seq_res([11, 14], [4])
	var parry_result: Dictionary = res_parry.resolve_weapon_attack(
		_attacker, _ad_target, _weapon, "ac",
		"parry", {"action_economy": ae, "parrying_weapon": _parry_weapon}
	)
	assert_true(parry_result["hit"],
		"[OUT-OF-TURN PARRY] roll_total=16 >= ac=13 → originally a hit (parry fires post-hit)")
	assert_eq(parry_result["damage_final"], 0,
		"[OUT-OF-TURN PARRY] parry_roll=18 > roll_total=16 → damage_final must be 0 (attack deflected)")
	# CR-001 AC-3: the out-of-turn reaction draws from the SAME shared
	# per-round budget — observable immediately as a decrement to 6.
	assert_eq(ae.get_remaining(), 6,
		"CR-001 AC-3: an out-of-turn Parry reaction must decrement the shared per-round budget (7 → 6), with no turn of this combatant's own having occurred yet")

	# ── This combatant's own turn now arrives, within the SAME round. ──────
	ae.start_of_turn()
	assert_eq(ae.get_remaining(), 6,
		"CR-001 AC-1/AC-3: start_of_turn() must NOT refill — the budget spent via the prior out-of-turn reaction persists into this combatant's own turn")

	var own_action_result: Dictionary = ae.spend_action({})
	assert_true(own_action_result.get("ok"),
		"own-turn spend_action() must succeed (budget remained available)")
	assert_eq(own_action_result.get("budget_remaining"), 5,
		"CR-001 AC-3: the own-turn action spends from the SAME pool already reduced by the out-of-turn reaction (6 → 5) — proves actions/reactions are unified against one ActionBudget, not separate per-turn/per-reaction allowances")


## CR-001 AC-1/AC-2/AC-4 (integration-level, TYPED access): drives a real
## Encounter round loop (core/combat/encounter.gd → RunRoundUseCase →
## ResolveActionUseCase) with a durable (hp=2000) Titus so he never dies and
## therefore takes all 7 of his per-round turns. Reads the typed
## RoundEvents.RoundHistoryEntry value objects carried in each
## get_round_history() entry's "entry" key (FEAT-099/FIND-096) — never raw
## Dictionary indexing of event/history data — to prove budget_remaining
## persists/decrements monotonically across Titus's repeated turns
## (cycle_index 0..6) WITHIN round 1, then resets to MAX_BUDGET-1 (i.e. the
## round boundary reset to MAX_BUDGET happened exactly once, between round 1
## and round 2) at the start of round 2.
func test_titus_round_history_typed_entries_persist_budget_across_turns_and_reset_once_at_round_boundary() -> void:
	var enc = EncounterClass.new(
		[_cr001_durable_titus()], [_cr001_durable_skeleton()], RNGClass.new(42)
	)
	enc.initialize()
	enc.run_round()  # Round 1

	var titus_r1: Array = []
	for hist_entry in enc.get_round_history():
		var typed_entry = hist_entry.get("entry")
		if typed_entry is RoundEventsClass.RoundHistoryEntry \
				and typed_entry.combatant_id == "Titus" \
				and typed_entry.round_number == 1:
			titus_r1.append(typed_entry)
	titus_r1.sort_custom(func(a, b): return a.cycle_index < b.cycle_index)

	assert_eq(titus_r1.size(), 7,
		"CR-001 AC-4: a durable (never-dying) combatant must take exactly 7 turns in round 1 (MAX_BUDGET), one per interleave cycle; got %d"
		% titus_r1.size())

	for i in range(titus_r1.size()):
		var expected_budget: int = 6 - i
		assert_eq(
			titus_r1[i].budget_remaining, expected_budget,
			"CR-001 AC-1/AC-4: RoundEvents.RoundHistoryEntry.budget_remaining must persist/decrement monotonically across Titus's repeated turns (cycle_index=%d) WITHIN round 1 — never reset mid-round; expected %d, got %d"
			% [titus_r1[i].cycle_index, expected_budget, titus_r1[i].budget_remaining]
		)
		# Typed .to_dict() snapshot must agree with the typed field — both
		# are "typed access", neither is raw Dictionary indexing of the
		# underlying event/history data.
		assert_eq(
			titus_r1[i].to_dict()["budget_remaining"], expected_budget,
			"RoundEvents.RoundHistoryEntry.to_dict() snapshot must agree with the typed budget_remaining field at cycle_index=%d"
			% titus_r1[i].cycle_index
		)

	enc.run_round()  # Round 2 — crosses the round boundary exactly once

	var titus_r2: Array = []
	for hist_entry in enc.get_round_history():
		var typed_entry = hist_entry.get("entry")
		if typed_entry is RoundEventsClass.RoundHistoryEntry \
				and typed_entry.combatant_id == "Titus" \
				and typed_entry.round_number == 2:
			titus_r2.append(typed_entry)
	titus_r2.sort_custom(func(a, b): return a.cycle_index < b.cycle_index)

	assert_true(titus_r2.size() >= 1,
		"Round 2 must have at least one Titus RoundHistoryEntry")
	if titus_r2.size() >= 1:
		assert_eq(
			titus_r2[0].budget_remaining, 6,
			"CR-001 AC-2: the round boundary (end_of_round() after round 1 / start_of_round() at round 2) must reset budget to MAX_BUDGET EXACTLY ONCE — round 2's first Titus turn shows budget_remaining=6 (7 − 1 spend), identical in shape to round 1's first turn, never carrying over round 1's exhausted (budget_remaining=0) state"
		)


## FEAT-099/FIND-096 (typed-access regression guard for THIS file): confirms
## get_round_events() yields TYPED RoundEvents.AttackEvent value objects —
## never raw Dictionaries — exercised via `is RoundEventsClass.AttackEvent`
## and `.to_dict()`, the same idiom required throughout this CR-001 section
## (and already established in tests/integration/test_encounter_integration.gd
## / tests/test_encounter_round_loop.gd).
func test_round_events_are_typed_round_events_value_objects_not_raw_dictionaries() -> void:
	var enc = EncounterClass.new(
		[_cr001_durable_titus()], [_cr001_durable_skeleton()], RNGClass.new(42)
	)
	enc.initialize()
	enc.run_round()

	var events: Array = enc.get_round_events()
	assert_true(events.size() > 0,
		"get_round_events() must be non-empty after run_round()")

	var attack_ev = null
	for ev in events:
		if ev is RoundEventsClass.AttackEvent:
			attack_ev = ev
			break

	assert_not_null(attack_ev,
		"get_round_events() must contain at least one typed RoundEvents.AttackEvent instance")
	if attack_ev == null:
		return

	assert_eq(attack_ev.round, 1,
		"RoundEvents.AttackEvent.round must be read as a typed field (round 1)")
	assert_true(
		attack_ev.attacker_name == "Titus" or attack_ev.attacker_name == "Skeleton",
		"RoundEvents.AttackEvent.attacker_name must be read as a typed field naming a known combatant; got '%s'"
		% attack_ev.attacker_name
	)

	var snapshot: Dictionary = attack_ev.to_dict()
	for field in ["round", "attacker_name", "target_name", "roll", "defense_type", "defense_value", "hit", "crit", "damage_final"]:
		assert_true(
			snapshot.has(field),
			"AttackEvent.to_dict() snapshot must contain field '%s'" % field
		)
