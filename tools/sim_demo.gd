## tools/sim_demo.gd — headless combat-simulation inspector (dev tool, not shipped).
##
## Drives core/sim/simulator.gd to print balance stats, and can replay a single
## encounter blow-by-blow. Pure observability — touches no game state, writes no files.
##
## USAGE (note the `--` before the tool's own flags):
##   godot --headless --path . -s tools/sim_demo.gd                       # default: N=1000, seed=12345
##   godot --headless --path . -s tools/sim_demo.gd -- --n=500 --seed=42  # custom aggregate run
##   godot --headless --path . -s tools/sim_demo.gd -- --trace --seed=7   # single-combat blow-by-blow
##   godot --headless --path . -s tools/sim_demo.gd -- --help
##
## Tip: append `2>/dev/null` to hide Godot's harmless "invalid UID" resource warnings.
##
## Flags:
##   --n=<int>     battle_count for the aggregate run (default 1000; ignored in --trace)
##   --seed=<int>  base_seed for the run / RNG seed for the traced combat (default 12345)
##   --trace       replay ONE Titus-vs-Skeleton encounter move-by-move instead of aggregating
##   --help, -h    print usage and exit

extends SceneTree

const SimulatorClass  = preload("res://core/sim/simulator.gd")
const EncounterClass  = preload("res://core/combat/encounter.gd")
const RNGClass        = preload("res://core/rules/rng.gd")
const AttributesClass = preload("res://core/rules/attributes.gd")


func _init() -> void:
	var opts := _parse_args()
	if opts.get("help", false):
		_print_usage()
		quit()
		return

	if opts["trace"]:
		_run_trace(int(opts["seed"]))
	else:
		_run_aggregate(int(opts["n"]), int(opts["seed"]))
	quit()


func _parse_args() -> Dictionary:
	var opts := {"n": 1000, "seed": 12345, "trace": false, "help": false}
	for a in OS.get_cmdline_user_args():
		if a == "--trace":
			opts["trace"] = true
		elif a == "--help" or a == "-h":
			opts["help"] = true
		elif a.begins_with("--n="):
			opts["n"] = int(a.substr(4))
		elif a.begins_with("--seed="):
			opts["seed"] = int(a.substr(7))
		else:
			print("WARNING: unrecognized argument '%s' (try --help)" % a)
	return opts


func _print_usage() -> void:
	print("sim_demo.gd — headless combat-simulation inspector")
	print("  godot --headless --path . -s tools/sim_demo.gd [-- --n=<int>] [--seed=<int>] [--trace]")
	print("  --n=<int>     battle_count for the aggregate run (default 1000)")
	print("  --seed=<int>  base_seed / traced-combat RNG seed (default 12345)")
	print("  --trace       replay one encounter move-by-move instead of aggregating")


## Aggregate mode: run battle_count battles and print the summary dict.
func _run_aggregate(battle_count: int, base_seed: int) -> void:
	var sim := SimulatorClass.new()
	var r := sim.run(battle_count, base_seed)
	print("=== Combat balance simulation: Titus (Fighter) vs Skeleton ===")
	print("  battles            : %d" % int(r["total_battles"]))
	print("  base_seed          : %d" % base_seed)
	print("  win_rate           : %.3f  (party wins / battles)" % float(r["win_rate"]))
	print("  avg_rounds         : %.2f  (mean rounds to resolve)" % float(r["avg_rounds"]))
	print("  total_damage_dealt : %d" % int(r["total_damage_dealt"]))
	print("  95%% CI (win_rate)  : +/-%.3f" % float(r["confidence_interval"]))
	var wr := float(r["win_rate"])
	var band_ok := wr >= 0.40 and wr <= 0.80
	print("  balance band [0.40, 0.80] : %s" % ("PASS" if band_ok else "OUT OF BAND"))


## Trace mode: build one Titus + one Skeleton (mirroring core/sim/simulator.gd's
## setup) and replay a single encounter, printing each attack from round history.
func _run_trace(seed_value: int) -> void:
	var combatants := _build_combatants()
	var titus: Dictionary = combatants[0]
	var skeleton: Dictionary = combatants[1]

	print("=== Single-combat trace (seed %d) ===" % seed_value)
	print("  %s: HP %d, AC %d, d%d longsword" % [
		titus["name"], int(titus["hp_current"]), int(titus["ac"]), int(titus["weapon"]["damage_die"])])
	print("  %s: HP %d, AC %d" % [skeleton["name"], int(skeleton["hp_current"]), int(skeleton["ac"])])
	print("  --")

	var enc := EncounterClass.new([titus], [skeleton], RNGClass.new(seed_value))
	enc.run()

	for e in enc.get_round_history():
		var atk: String = e["attacker"].get("name", "?")
		var tgt: String = e["target"].get("name", "?")
		var hit: bool = int(e["damage_final"]) > 0
		print("  R%d  %-8s --%s--> %-8s  roll=%-3d  %s  (actions left: %d)" % [
			int(e["round"]), atk, e["action"], tgt, int(e["roll"]),
			("dmg=%d" % int(e["damage_final"])) if hit else "miss   ",
			int(e["budget_remaining"])])

	print("  --")
	print("  outcome: %s in %d round(s)   |   final HP — %s: %d, %s: %d" % [
		enc.get_outcome().to_upper(), enc.get_round_count(),
		titus["name"], int(titus["hp_current"]),
		skeleton["name"], int(skeleton["hp_current"])])


## Build [titus, skeleton] combatant dicts exactly as core/sim/simulator.gd does,
## so a traced combat matches what the aggregate run produces for the same seed.
func _build_combatants() -> Array:
	var titus_char = ResourceLoader.load("res://data/characters/titus.tres")
	var fighter_class = titus_char.class_ref
	var armor_res = ResourceLoader.load(titus_char.starting_equipment[1])
	var weapon_res = ResourceLoader.load(titus_char.starting_equipment[0])
	var skeleton_res = ResourceLoader.load("res://data/enemies/skeleton.tres")

	# FEAT-002 (US-002, ADR-001/ADR-002): resolve the Skeleton's weapon via
	# weapon_paths[0] -> WeaponResource, matching core/sim/simulator.gd.
	var skel_weapon_res = ResourceLoader.load(skeleton_res.weapon_paths[0]) if not skeleton_res.weapon_paths.is_empty() else null
	var skel_weapon_attr: String = skel_weapon_res.damage_modifier_attribute if skel_weapon_res != null else "strength"

	var attrs = AttributesClass.new(RNGClass.new(0))
	var scores = titus_char.attributes

	var titus := {
		"name":       titus_char.name,
		"hp_current": attrs.compute_hp(scores, fighter_class),
		"ac":         attrs.compute_ac(scores, armor_res.ac_base, armor_res.category),
		"strength":   scores.get("strength", 0),
		"dexterity":  scores.get("dexterity", 0),
		"intuition":  scores.get("intuition", 0),
		"weapon": {
			"damage_modifier_attribute": weapon_res.damage_modifier_attribute,
			"proficiency_bonus":         weapon_res.proficiency_bonus,
			"damage_die":                weapon_res.damage_die,
		},
	}

	# hp_current=50 and ac=14 are balance-tuned simulation parameters (see simulator.gd).
	var skeleton := {
		"name":       skeleton_res.name,
		"hp_current": 50,
		"ac":         14,
		"strength":   skeleton_res.str,
		"dexterity":  skeleton_res.dex,
		"intuition":  1,
		"weapon": {
			"damage_modifier_attribute": skel_weapon_attr,
			"proficiency_bonus":         skel_weapon_res.proficiency_bonus if skel_weapon_res != null else 1,
			"damage_die":                skel_weapon_res.damage_die if skel_weapon_res != null else 8,
		},
	}

	return [titus, skeleton]
