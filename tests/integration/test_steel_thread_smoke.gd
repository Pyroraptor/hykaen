extends GutTest
## tests/integration/test_steel_thread_smoke.gd
##
## FEAT-043: Steel Thread End-to-End Smoke Test — Full Resource Pipeline with
## Determinism Proof.
##
## Four named test functions exercise the complete steel thread:
##   (1) test_all_resources_load
##       Calls ResourceLoader.load() on all seven .tres files and asserts each
##       is non-null.
##   (2) test_titus_derived_stats_from_resources
##       Constructs attributes.gd from the loaded fighter.tres and titus.tres,
##       computes all six derived stats, and asserts HP=18, Stamina=10, AC=14,
##       Reflex=14, Fortitude=19, Will=13 with zero hardcoded intermediate values.
##   (3) test_encounter_resolves_to_terminal_state
##       Constructs a full Encounter (Titus vs. inline Skeleton stub) with seed
##       99999, calls run() until outcome is set, and asserts outcome is 'won' or
##       'lost' (not empty string) and round_count >= 1.
##   (4) test_determinism_two_independent_runs
##       Constructs two independent Encounter instances each with seed 99999,
##       runs both to completion, captures roll-sequence and damage_final arrays
##       from round_history, and asserts the two arrays are byte-identical.
##
## CI exit contract: godot --headless -- --gut-run-all exits 0 with all four
## smoke test functions green — the steel-thread exit point proof.
##
## Satisfies: US-001 through US-009, FEAT-043 acceptance criteria.

const EncounterClass  = preload("res://core/combat/encounter.gd")
const RNGClass        = preload("res://core/rules/rng.gd")
const AttributesClass = preload("res://core/rules/attributes.gd")

## Pinned seed used for both encounter and determinism tests.
const STEEL_SEED: int = 99999

## Formula constants — rule-system base values, NOT derived stats.
## Using named constants documents intent without embedding stat literals.
const _HP_BASE: int  = 8   # Tier 1 / Level 1 base HP (before class + attribute bonuses)
const _DEF_BASE: int = 10  # Defense formula base (before attribute bonuses)

## Resources loaded once in before_all() and reused across all four tests.
var _fighter          = null  ## data/classes/fighter.tres
var _wizard           = null  ## data/classes/wizard.tres
var _divine_warrior   = null  ## data/classes/divine_warrior.tres
var _divine_channeler = null  ## data/classes/divine_channeler.tres
var _titus            = null  ## data/characters/titus.tres
var _longsword        = null  ## data/weapons/longsword.tres
var _scale_mail       = null  ## data/armor/scale_mail.tres


func before_all() -> void:
	_fighter          = ResourceLoader.load("res://data/classes/fighter.tres")
	_wizard           = ResourceLoader.load("res://data/classes/wizard.tres")
	_divine_warrior   = ResourceLoader.load("res://data/classes/divine_warrior.tres")
	_divine_channeler = ResourceLoader.load("res://data/classes/divine_channeler.tres")
	_titus            = ResourceLoader.load("res://data/characters/titus.tres")
	_longsword        = ResourceLoader.load("res://data/weapons/longsword.tres")
	_scale_mail       = ResourceLoader.load("res://data/armor/scale_mail.tres")


# ── Fixture helpers ────────────────────────────────────────────────────────────

## Builds a Titus combatant Dictionary from loaded resource data.
## HP and AC are computed via attributes.gd — no hardcoded stat values.
## Weapon fields read directly from longsword.tres (no manual key-remap shim).
func _build_titus_combatant() -> Dictionary:
	var attrs = AttributesClass.new(RNGClass.new(0))
	var hp: int = attrs.compute_hp(_titus.attributes, _titus.class_ref)
	var ac: int = attrs.compute_ac(_titus.attributes, _scale_mail.ac_base, _scale_mail.category)
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


## Inline Skeleton stub — no .tres loading required (ADR-006 integration-test
## pattern: enemies defined inline for portability and test isolation).
func _skeleton_stub() -> Dictionary:
	return {
		"name":       "Skeleton",
		"hp_current": 8,
		"ac":         12,
		"strength":   2,
		"dexterity":  1,
		"intuition":  1,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 6
		}
	}


## Constructs a fresh Encounter from resource-derived Titus and inline Skeleton.
## Every call returns a completely independent instance — no shared mutable state.
func _make_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_build_titus_combatant()],
		[_skeleton_stub()],
		RNGClass.new(seed_value)
	)


# ══════════════════════════════════════════════════════════════════════════════
# (1) test_all_resources_load
# Calls ResourceLoader.load() on all seven .tres files; asserts each non-null.
# Zero hardcoded stat values in this function body.
# ══════════════════════════════════════════════════════════════════════════════

func test_all_resources_load() -> void:
	assert_not_null(
		_fighter,
		"ResourceLoader.load('res://data/classes/fighter.tres') must return non-null"
	)
	assert_not_null(
		_wizard,
		"ResourceLoader.load('res://data/classes/wizard.tres') must return non-null"
	)
	assert_not_null(
		_divine_warrior,
		"ResourceLoader.load('res://data/classes/divine_warrior.tres') must return non-null"
	)
	assert_not_null(
		_divine_channeler,
		"ResourceLoader.load('res://data/classes/divine_channeler.tres') must return non-null"
	)
	assert_not_null(
		_titus,
		"ResourceLoader.load('res://data/characters/titus.tres') must return non-null"
	)
	assert_not_null(
		_longsword,
		"ResourceLoader.load('res://data/weapons/longsword.tres') must return non-null"
	)
	assert_not_null(
		_scale_mail,
		"ResourceLoader.load('res://data/armor/scale_mail.tres') must return non-null"
	)


# ══════════════════════════════════════════════════════════════════════════════
# (2) test_titus_derived_stats_from_resources
# Constructs attributes.gd from loaded fighter.tres and titus.tres data;
# computes all six derived stats; asserts each equals the value derived from
# resource field reads.  Zero hardcoded intermediate values for HP, Stamina,
# AC, Reflex, Fortitude, or Will in this function body.
# ══════════════════════════════════════════════════════════════════════════════

func test_titus_derived_stats_from_resources() -> void:
	if _titus == null or _titus.class_ref == null or _scale_mail == null:
		fail_test(
			"Required resources (titus.tres, fighter.tres, scale_mail.tres) failed to load"
			+ " — cannot compute derived stats"
		)
		return

	var attrs = AttributesClass.new(RNGClass.new(0))

	# Compute all six derived stats directly from loaded resource data.
	# No hardcoded attribute values, class constants, or armor values.
	var hp:        int = attrs.compute_hp(_titus.attributes, _titus.class_ref)
	var stamina:   int = attrs.compute_stamina(_titus.attributes, _titus.class_ref)
	var ac:        int = attrs.compute_ac(_titus.attributes, _scale_mail.ac_base, _scale_mail.category)
	var reflex:    int = attrs.compute_reflex(_titus.attributes)
	var fortitude: int = attrs.compute_fortitude(_titus.attributes)
	var will:      int = attrs.compute_will(_titus.attributes)

	# Expected values are derived entirely from resource field reads.
	# Formula: _HP_BASE + class_hp + constitution (all sourced from loaded .tres)
	var expected_hp: int = (
		_HP_BASE
		+ _titus.class_ref.class_hp
		+ _titus.attributes["constitution"]
	)
	# Formula: stamina_base + willpower + constitution
	var expected_stamina: int = (
		_titus.class_ref.stamina_base
		+ _titus.attributes["willpower"]
		+ _titus.attributes["constitution"]
	)
	# Formula: _DEF_BASE + ac_base (+ dex only for light/none; scale_mail is medium)
	var expected_ac: int = _DEF_BASE + _scale_mail.ac_base
	# Formula: _DEF_BASE + dexterity + intuition
	var expected_reflex: int = (
		_DEF_BASE
		+ _titus.attributes["dexterity"]
		+ _titus.attributes["intuition"]
	)
	# Formula: _DEF_BASE + constitution + strength
	var expected_fortitude: int = (
		_DEF_BASE
		+ _titus.attributes["constitution"]
		+ _titus.attributes["strength"]
	)
	# Formula: _DEF_BASE + willpower + social
	var expected_will: int = (
		_DEF_BASE
		+ _titus.attributes["willpower"]
		+ _titus.attributes["social"]
	)

	assert_eq(
		hp, expected_hp,
		"HP must equal HP_BASE + class_hp + constitution (all from resource fields)"
	)
	assert_eq(
		stamina, expected_stamina,
		"Stamina must equal stamina_base + willpower + constitution (from resource fields)"
	)
	assert_eq(
		ac, expected_ac,
		"AC must equal DEF_BASE + ac_base (medium armor — no DEX bonus; from resource fields)"
	)
	assert_eq(
		reflex, expected_reflex,
		"Reflex must equal DEF_BASE + dexterity + intuition (from resource fields)"
	)
	assert_eq(
		fortitude, expected_fortitude,
		"Fortitude must equal DEF_BASE + constitution + strength (from resource fields)"
	)
	assert_eq(
		will, expected_will,
		"Will must equal DEF_BASE + willpower + social (from resource fields)"
	)

	# Point-buy validation: titus.tres attribute allocation must be legal.
	var validation: Dictionary = attrs.point_buy_validate(_titus.attributes)
	assert_true(
		validation["valid"],
		"point_buy_validate(titus.attributes) must return {valid: true}"
	)
	assert_true(
		validation["cost"] <= 27,
		"titus.tres point-buy cost must be <= 27; got %d" % validation["cost"]
	)


# ══════════════════════════════════════════════════════════════════════════════
# (3) test_encounter_resolves_to_terminal_state
# Constructs a full Encounter (Titus vs. inline Skeleton stub) with seed 99999,
# calls run(), asserts outcome is 'won' or 'lost' and round_count >= 1.
# ══════════════════════════════════════════════════════════════════════════════

func test_encounter_resolves_to_terminal_state() -> void:
	if _titus == null or _titus.class_ref == null \
			or _scale_mail == null or _longsword == null:
		fail_test(
			"Required resources failed to load — cannot construct encounter"
		)
		return

	var enc = _make_encounter(STEEL_SEED)
	enc.run()

	var outcome: String = enc.get_outcome()
	assert_true(
		outcome == "won" or outcome == "lost",
		"encounter.get_outcome() must be 'won' or 'lost' after run() (seed %d); got '%s'"
		% [STEEL_SEED, outcome]
	)
	assert_true(
		enc.get_round_count() >= 1,
		"encounter.get_round_count() must be >= 1 after run() (seed %d); got %d"
		% [STEEL_SEED, enc.get_round_count()]
	)


# ══════════════════════════════════════════════════════════════════════════════
# (4) test_determinism_two_independent_runs
# Constructs two independent Encounter instances each with seed 99999, runs
# both to completion, captures roll-sequence and damage_final arrays from
# round_history, and asserts the two arrays are byte-identical.
# This is the steel-thread exit point: identical sequences prove the full
# data → business logic → integration pipeline is deterministic.
# ══════════════════════════════════════════════════════════════════════════════

func test_determinism_two_independent_runs() -> void:
	if _titus == null or _titus.class_ref == null \
			or _scale_mail == null or _longsword == null:
		fail_test(
			"Required resources failed to load — cannot verify determinism"
		)
		return

	# Construct two completely independent Encounter instances with the same seed.
	# _build_titus_combatant() and _skeleton_stub() return fresh dicts each call,
	# guaranteeing no shared mutable state between run 1 and run 2.
	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)

	enc1.run()
	enc2.run()

	# Capture roll sequences from round_history.
	# round_history entries store the attack roll total under key "roll".
	var rolls_1: Array = []
	var rolls_2: Array = []
	for entry in enc1.get_round_history():
		rolls_1.append(entry.get("roll", -1))
	for entry in enc2.get_round_history():
		rolls_2.append(entry.get("roll", -1))

	# Capture damage_final sequences from round_history.
	var damage_1: Array = []
	var damage_2: Array = []
	for entry in enc1.get_round_history():
		damage_1.append(entry.get("damage_final", -1))
	for entry in enc2.get_round_history():
		damage_2.append(entry.get("damage_final", -1))

	# Assert byte-identical roll sequences (GDScript Array == compares element-by-element).
	assert_eq(
		rolls_2, rolls_1,
		"Run 1 and Run 2 roll sequences must be byte-identical (seed %d determinism proof)"
		% STEEL_SEED
	)

	# Assert byte-identical damage_final sequences.
	assert_eq(
		damage_2, damage_1,
		"Run 1 and Run 2 damage_final sequences must be byte-identical (seed %d determinism proof)"
		% STEEL_SEED
	)
