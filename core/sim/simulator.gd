## core/sim/simulator.gd — Balance Simulator
##
## Domain layer (ADR-001): pure GDScript class — no Node/Control/CanvasItem inheritance.
## Constructor accepts no parameters.  All configuration is passed to run().
##
## Satisfies: FEAT-048, US-009, DEF-004, FEAT-075, FEAT-088
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
## FEAT-087: Titus's armor corrected to chain_shirt (AC=15); Skeleton rebalanced
## (hp=36, ac=14) to maintain the [0.40, 0.80] invariant at the correct AC.
## FEAT-088 (NFR-005 / ADR-003): Skeleton enemy is now loaded from
## data/enemies/skeleton.tres via ResourceLoader — no inline hardcoded dict literal.
## The skeleton resource provides name, str, dex, and weapon stats; hp_current and
## ac remain balance-tuned simulation parameters not stored in the base resource.

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

	# ── Load Skeleton resource once (FEAT-088 / ADR-003 / NFR-005) ────────────
	# The EnemyResource provides name, str, dex, and weapon base stats.
	# hp_current=50 and ac=14 remain balance-tuned simulation parameters (FEAT-087).
	var skeleton_res  = ResourceLoader.load("res://data/enemies/skeleton.tres")

	# Attribute name mapping: EnemyResource uses compact keys ('str', 'dex') while
	# the combat system uses full attribute names matching combatant dict keys.
	const SKELETON_ATTR_MAP: Dictionary = {"str": "strength", "dex": "dexterity"}
	var raw_skel_attr: String = skeleton_res.weapon.get("attribute", "strength")
	var skel_weapon_attr: String = SKELETON_ATTR_MAP.get(raw_skel_attr, raw_skel_attr)

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

		# Skeleton combatant — FEAT-088: built from skeleton.tres resource (loaded above).
		# The EnemyResource provides name, str, dex, and weapon base stats.
		# hp_current=50 and ac=14 are balance-tuned simulation parameters (FEAT-087).
		var skeleton: Dictionary = {
			"name":       skeleton_res.name,
			"hp_current": 50,
			"ac":         14,
			"strength":   skeleton_res.str,
			"dexterity":  skeleton_res.dex,
			"intuition":  1,
			"weapon": {
				"damage_modifier_attribute": skel_weapon_attr,
				"proficiency_bonus":         skeleton_res.weapon.get("proficiency_bonus", 1),
				"damage_die":               skeleton_res.weapon.get("die", 8)
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
