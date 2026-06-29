extends GutTest
## tests/sim/test_determinism.gd
##
## FEAT-091: Steel Thread End-to-End Determinism Smoke Test with Corrected
##           Resource Baselines.
##
## Proves the complete pipeline determinism guarantee by running two independent
## encounter instances from scratch with seed 99999 and asserting byte-identical
## roll_sequence and damage_final_sequence arrays.
##
## Steel thread exit point:
##   "godot --headless GUT suite exits 0, proving Titus (Fighter) vs one stub
##    enemy resolves to a win/loss state with pinned-seed deterministic numeric
##    outcomes verifiable across two independent process runs."
##
## Architecture: all objects constructed locally — no global state, no shared
## RNG instances between Run 1 and Run 2.  Each call to _make_fresh_encounter()
## creates new RNG, new Encounter, and new ActionEconomy instances (ActionEconomy
## instances are internal to Encounter._init()).
##
## Corrected resource baselines used (FIX-003 through FIX-007):
##   titus.tres       — chain_shirt armor (FIX-004), longsword d12 (FIX-003)
##   longsword.tres   — damage_die=12, proficiency_bonus=2 (FIX-003)
##   chain_shirt.tres — ac_base=5, medium armor (FIX-004); AC=15 for Titus
##   skeleton.tres    — EnemyResource loaded via ResourceLoader (FIX-005)
##
## Satisfies: FEAT-091 test criteria 5–8.

const EncounterClass  = preload("res://core/combat/encounter.gd")
const RNGClass        = preload("res://core/rules/rng.gd")
const AttributesClass = preload("res://core/rules/attributes.gd")

## Pinned seed for all determinism tests (matches steel thread STEEL_SEED).
const STEEL_SEED: int = 99999


# ── Resource fixtures (loaded once per test file) ─────────────────────────────

var _titus            = null  ## CharacterResource
var _fighter_class    = null  ## ClassResource (titus.class_ref)
var _longsword        = null  ## WeaponResource
var _chain_shirt      = null  ## ArmorResource (FIX-004)
var _skeleton_res     = null  ## EnemyResource (FIX-005)


func before_all() -> void:
	## Load all resources once; each test constructs fresh combatant dicts.
	_titus       = ResourceLoader.load("res://data/characters/titus.tres")
	_longsword   = ResourceLoader.load("res://data/weapons/longsword.tres")
	_chain_shirt = ResourceLoader.load("res://data/armor/chain_shirt.tres")
	_skeleton_res = ResourceLoader.load("res://data/enemies/skeleton.tres")
	if _titus != null:
		_fighter_class = _titus.class_ref


# ── Combatant dict builders ───────────────────────────────────────────────────

## _build_titus_dict() — constructs a fresh Titus combatant dict from loaded resources.
##
## Uses chain_shirt (FIX-004) and longsword d12 (FIX-003).
## Each call produces an independent dict — no shared object references.
## The dict is mutable during encounter (hp, initiative tag); fresh per run.
func _build_titus_dict() -> Dictionary:
	var attrs = AttributesClass.new(RNGClass.new(0))
	var hp: int = attrs.compute_hp(_titus.attributes, _fighter_class)
	var ac: int = attrs.compute_ac(_titus.attributes, _chain_shirt.ac_base, _chain_shirt.category)
	return {
		"name":       _titus.name,
		"hp_current": hp,
		"ac":         ac,
		"strength":   _titus.attributes.get("strength",  0),
		"dexterity":  _titus.attributes.get("dexterity", 0),
		"intuition":  _titus.attributes.get("intuition", 0),
		"weapon": {
			"damage_modifier_attribute": _longsword.damage_modifier_attribute,
			"proficiency_bonus":         _longsword.proficiency_bonus,
			"damage_die":                _longsword.damage_die
		}
	}


## _build_skeleton_dict() — constructs a fresh skeleton combatant dict from
## skeleton.tres EnemyResource fields.
##
## FIX-005: skeleton.tres is loaded via ResourceLoader.
## EnemyResource fields are mapped to the encounter combatant dict format:
##   EnemyResource.str  → "strength" (canonical encounter attribute key)
##   EnemyResource.dex  → "dexterity"
##   weapon.attribute   → "damage_modifier_attribute" = "strength"
##   weapon.die         → "damage_die"
## ac and intuition are not in EnemyResource schema; defaults: ac=12, intuition=0.
func _build_skeleton_dict() -> Dictionary:
	return {
		"name":       _skeleton_res.name,
		"hp_current": _skeleton_res.hp,
		"ac":         12,
		"strength":   _skeleton_res.str,
		"dexterity":  _skeleton_res.dex,
		"intuition":  0,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus":         _skeleton_res.weapon.get("proficiency_bonus", 1),
			"damage_die":                _skeleton_res.weapon.get("die", 6)
		}
	}


## _make_fresh_encounter(seed_value) — constructs a fully independent Encounter.
##
## Creates new instances of:
##   - RNG (seeded with seed_value) — via RNGClass.new(seed_value)
##   - Encounter — via EncounterClass.new(party, enemies, rng)
##   - ActionEconomy — created internally by Encounter._init() per combatant
##
## Fresh combatant dicts from _build_titus_dict() and _build_skeleton_dict()
## guarantee no state leaks from prior encounter runs.
func _make_fresh_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_build_titus_dict()],
		[_build_skeleton_dict()],
		RNGClass.new(seed_value)
	)


# ── Guard helper ─────────────────────────────────────────────────────────────

## Returns true if all required resources loaded successfully.
func _all_resources_loaded() -> bool:
	return _titus != null and _fighter_class != null \
		and _longsword != null and _chain_shirt != null and _skeleton_res != null


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-091 Criteria 5–6 — Dual-Run Determinism Proof
#
# Run #1: construct full encounter stack from scratch with seed 99999.
#          Capture roll_sequence_1 (Array[int]) and damage_final_sequence_1 (Array[int])
#          from get_round_history().
#
# Run #2: in the SAME test function, re-construct ALL objects from scratch
#          with seed 99999 (new RNG instance, new Encounter instance, new
#          ActionEconomy instances created by Encounter._init()).
#          Capture roll_sequence_2 and damage_final_sequence_2.
#
# Both sequences are extracted from round_history entries:
#   roll_sequence   ← entry.get("roll", -1)
#   damage_sequence ← entry.get("damage_final", -1)
# ══════════════════════════════════════════════════════════════════════════════

## test_determinism_seed_99999_roll_sequences_byte_identical
##
## Proves: two independent Encounter constructions with seed 99999 produce
## byte-identical d20 attack roll sequences.
##
## Run 1 and Run 2 each get a fresh RNG(99999), fresh Encounter, fresh
## ActionEconomy instances.  No shared state between runs.
##
## Satisfies: FEAT-091 test criteria 5, 6, 7.
func test_determinism_seed_99999_roll_sequences_byte_identical() -> void:
	if not _all_resources_loaded():
		fail_test(
			"one or more required resources failed to load — "
			+ "cannot prove roll determinism (FEAT-091)"
		)
		return

	# ── Run #1: fresh encounter stack ───────────────────────────────────────
	var enc1 = _make_fresh_encounter(STEEL_SEED)
	enc1.run()

	var roll_sequence_1: Array = []
	var damage_final_sequence_1: Array = []
	for entry in enc1.get_round_history():
		roll_sequence_1.append(entry.get("roll", -1))
		damage_final_sequence_1.append(entry.get("damage_final", -1))

	# ── Run #2: completely fresh instances — new RNG, Encounter, ActionEconomy ──
	var enc2 = _make_fresh_encounter(STEEL_SEED)
	enc2.run()

	var roll_sequence_2: Array = []
	var damage_final_sequence_2: Array = []
	for entry in enc2.get_round_history():
		roll_sequence_2.append(entry.get("roll", -1))
		damage_final_sequence_2.append(entry.get("damage_final", -1))

	# ── Criterion 7: roll sequences must be byte-identical ───────────────────
	assert_eq(
		roll_sequence_1, roll_sequence_2,
		"Roll sequences must be byte-identical across two independent constructions with same seed"
	)

	# ── Criterion 8: damage sequences must be byte-identical ─────────────────
	assert_eq(
		damage_final_sequence_1, damage_final_sequence_2,
		"Damage sequences must be byte-identical across two independent constructions with same seed"
	)


## test_determinism_seed_99999_encounter_terminates
##
## Verifies that the fresh-stack encounter (seed 99999, chain_shirt Titus vs
## skeleton.tres enemy) actually terminates with a valid outcome.
## This is the baseline sanity check for the determinism tests above.
##
## A non-terminating encounter would make all determinism assertions vacuously
## true (empty sequences always equal each other) — this test catches that.
##
## Satisfies: FEAT-091 test criteria 5–6 (encounters terminate with valid outcome).
func test_determinism_seed_99999_encounter_terminates() -> void:
	if not _all_resources_loaded():
		fail_test(
			"one or more required resources failed to load — "
			+ "cannot verify encounter termination (FEAT-091)"
		)
		return

	var enc = _make_fresh_encounter(STEEL_SEED)
	enc.run()

	var outcome: String = enc.get_outcome()
	assert_true(
		outcome == "won" or outcome == "lost",
		("Determinism test encounter (seed %d) must terminate with 'won' or 'lost'; "
			+ "got '%s' — FEAT-091") % [STEEL_SEED, outcome]
	)
	assert_true(
		enc.get_round_count() >= 1,
		("Determinism test encounter (seed %d) must complete at least 1 round; "
			+ "got %d — FEAT-091") % [STEEL_SEED, enc.get_round_count()]
	)
	assert_true(
		enc.get_round_history().size() >= 1,
		("Determinism test encounter (seed %d) round_history must be non-empty; "
			+ "got size %d — empty sequences would trivially satisfy byte-identical test")
			% [STEEL_SEED, enc.get_round_history().size()]
	)


## test_determinism_seed_99999_round_histories_same_length
##
## Verifies that Run 1 and Run 2 with seed 99999 produce round histories of
## the same length — a prerequisite for the element-by-element byte-identity
## assertions in test_determinism_seed_99999_roll_sequences_byte_identical.
##
## Satisfies: FEAT-091 (determinism precondition gate).
func test_determinism_seed_99999_round_histories_same_length() -> void:
	if not _all_resources_loaded():
		fail_test(
			"one or more required resources failed to load — "
			+ "cannot verify round history length (FEAT-091)"
		)
		return

	var enc1 = _make_fresh_encounter(STEEL_SEED)
	var enc2 = _make_fresh_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()

	assert_eq(
		enc1.get_round_history().size(),
		enc2.get_round_history().size(),
		("Run 1 and Run 2 (seed %d) must produce round histories of equal length "
			+ "— FEAT-091 determinism precondition") % STEEL_SEED
	)
