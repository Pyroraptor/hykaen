## core/sim/simulator.gd — Balance Simulator
##
## Domain layer (ADR-001): pure GDScript class — no Node/Control/CanvasItem inheritance.
## Constructor accepts no parameters.  All configuration is passed to run().
##
## Satisfies: FEAT-048, US-009, DEF-004, FEAT-075
##
## run(n_battles, base_seed) drives n_battles independent Encounter instances,
## each seeded with (base_seed + i), and returns aggregate win/round/damage stats.
##
## RNG constraint (ADR-002): direct RNG calls are forbidden in this file.
## All randomness flows through the injected RNGClass instances
## created per-battle and passed into each Encounter.
##
## FEAT-075 (NFR-005 / DEF-002): Titus's weapon stats are now loaded from
## longsword.tres via titus.tres.starting_equipment[0] — no hardcoded weapon
## numeric values remain for the attacker.  The Skeleton is re-tuned to
## produce a seed-averaged win rate in [0.40, 0.80] against d12+5 Titus.

class_name Simulator

const EncounterClass  = preload("res://core/combat/encounter.gd")
const RNGClass        = preload("res://core/rules/rng.gd")
const AttributesClass = preload("res://core/rules/attributes.gd")


## _init() — no-parameter constructor; simulator holds no mutable state.
func _init() -> void:
	pass


## run(n_battles: int, base_seed: int) → Dictionary
##
## Runs n_battles encounter simulations.  Battle i uses seed (base_seed + i)
## so the entire simulation is fully deterministic from (n_battles, base_seed).
##
## Party: one Titus combatant derived from titus.tres / fighter class / equipment.
## Enemy: one Skeleton stub dict matching the fixture in test_encounter_integration.gd.
##
## Returns:
##   {
##     win_rate:           float  — fraction of battles the party won [0.0, 1.0]
##     avg_rounds:         float  — mean number of rounds per battle
##     total_damage_dealt: int    — sum of all damage_final values across all battles
##   }
func run(n_battles: int, base_seed: int) -> Dictionary:
	# ── Load Titus resources once ─────────────────────────────────────────────
	var titus_char    = ResourceLoader.load("res://data/characters/titus.tres")
	var fighter_class = titus_char.class_ref
	var scale_mail    = ResourceLoader.load(titus_char.starting_equipment[1])
	# FEAT-075: load weapon from titus.tres.starting_equipment[0] (longsword.tres)
	# instead of hardcoding damage_die, proficiency_bonus, damage_modifier_attribute.
	var weapon_res    = ResourceLoader.load(titus_char.starting_equipment[0])

	# Compute Titus's derived stats via attributes.gd (ADR-012 formulas).
	# RNGClass.new(0) is passed to satisfy the Attributes constructor;
	# roll_initiative() is never called here so the seed is irrelevant.
	var attrs         = AttributesClass.new(RNGClass.new(0))
	var scores        = titus_char.attributes
	var titus_hp: int  = attrs.compute_hp(scores, fighter_class)
	var titus_ac: int  = attrs.compute_ac(scores, scale_mail.ac_base, scale_mail.category)

	# ── Simulation accumulators ───────────────────────────────────────────────
	var wins:         int = 0
	var total_rounds: int = 0
	var total_damage: int = 0

	# ── Main simulation loop ──────────────────────────────────────────────────
	for i in range(n_battles):
		# Fresh seeded RNG for each battle — guarantees determinism (ADR-002).
		var battle_rng = RNGClass.new(base_seed + i)

		# Build a fresh Titus combatant dict for this battle (mutable hp_current).
		# HP and AC are derived from titus.tres via attributes.gd (ADR-012).
		# FEAT-075: weapon stats (damage_die, proficiency_bonus, damage_modifier_attribute)
		# are read from the longsword.tres resource loaded above — no hardcoded values.
		var titus: Dictionary = {
			"name":       titus_char.name,
			"hp_current": titus_hp,
			"ac":         titus_ac,
			"strength":   scores.get("strength",  0),
			"dexterity":  scores.get("dexterity", 0),
			"intuition":  scores.get("intuition", 0),
			"weapon": {
				"damage_modifier_attribute": weapon_res.damage_modifier_attribute,
				"proficiency_bonus":         weapon_res.proficiency_bonus,
				"damage_die":                weapon_res.damage_die
			}
		}

		# Skeleton stub — FEAT-075 balance calibration for d12+5 Titus.
		# Design rationale: d12+5 Titus averages ~11.5/hit vs hp=28 Skeleton
		# needing ~3 hits; Skeleton d8+2 avg ~6.5/hit vs Titus hp~18 needing
		# ~3 hits, producing ~55–65% win rate within the [0.40, 0.80] invariant.
		# Both combatants need ~3 hits to kill each other; Titus's +4 initiative
		# advantage (intuition 2 + dex 2 vs Skeleton's +2) yields ~57% initiative
		# win rate, which translates to a seed-averaged party win rate of ~60–65%.
		var skeleton: Dictionary = {
			"name":       "Skeleton",
			"hp_current": 28,
			"ac":         13,
			"strength":   2,
			"dexterity":  1,
			"intuition":  1,
			"weapon": {
				"damage_modifier_attribute": "strength",
				"proficiency_bonus":         1,
				"damage_die":               8
			}
		}

		# Run one encounter to completion.
		var enc = EncounterClass.new([titus], [skeleton], battle_rng)
		enc.run()

		# Accumulate results.
		if enc.get_outcome() == "won":
			wins += 1
		total_rounds += enc.get_round_count()
		for entry in enc.get_round_history():
			total_damage += entry.get("damage_final", 0)

	# ── Compute aggregate statistics ──────────────────────────────────────────
	var n:        float = float(n_battles) if n_battles > 0 else 1.0
	var win_rate: float = float(wins)         / n
	var avg_rounds: float = float(total_rounds) / n

	return {
		"win_rate":           win_rate,
		"avg_rounds":         avg_rounds,
		"total_damage_dealt": total_damage
	}
