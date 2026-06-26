extends GutTest
## tests/integration/test_steel_thread_smoke.gd
##
## FEAT-043 / FEAT-049: Steel Thread End-to-End Smoke Test — Full Resource Pipeline
## with Determinism Proof and Post-Remediation Cross-Cutting Validation.
##
## Original four test functions (FEAT-043):
##   (1) test_all_resources_load
##   (2) test_titus_derived_stats_from_resources
##   (3) test_encounter_resolves_to_terminal_state
##   (4) test_determinism_two_independent_runs
##
## FEAT-049 additions — cross-cutting tests spanning all remediated subsystems:
##   (5) test_full_party_all_four_characters_load
##       Loads all four .tres character files and asserts each is non-null
##       CharacterResource with non-empty name — verifies FIX-002 integration.
##   (6) test_spell_attacker_in_pipeline
##       Constructs Gram Marx combatant from gram_marx.tres with
##       spellcasting_attribute='intellect', calls resolve_spell_attack() with
##       pinned RNG, asserts hit/crit/damage_final keys present — verifies FIX-004.
##   (7) test_titus_vs_skeleton_d12_longsword_pinned_seed
##       Asserts encounter terminates with outcome in ['won','lost'] and at least
##       one round_history entry has damage_final > 0 proving d12 weapon data
##       flows end-to-end — verifies FIX-003.
##   (8) test_simulator_balance_invariant_from_smoke
##       Instantiates Simulator and asserts the SEED-AVERAGED mean win_rate
##       (averaged across at least 3 distinct base seeds) is in [0.40, 0.80]
##       — verifies FIX-005.
##
## CI exit contract: godot --headless -- --gut-run-all exits 0 with all smoke
## test functions green — the steel-thread exit point proof.
##
## Satisfies: US-001 through US-009, FEAT-043 and FEAT-049 acceptance criteria.

const EncounterClass    = preload("res://core/combat/encounter.gd")
const RNGClass          = preload("res://core/rules/rng.gd")
const AttributesClass   = preload("res://core/rules/attributes.gd")
const ResolutionClass   = preload("res://core/rules/resolution.gd")
const SimulatorClass    = preload("res://core/sim/simulator.gd")
const CharacterResource = preload("res://core/model/character_resource.gd")

## Pinned seed used for both encounter and determinism tests.
const STEEL_SEED: int = 99999

## Formula constants — rule-system base values, NOT derived stats.
## Using named constants documents intent without embedding stat literals.
const _HP_BASE: int  = 8   # Tier 1 / Level 1 base HP (before class + attribute bonuses)
const _DEF_BASE: int = 10  # Defense formula base (before attribute bonuses)

## Resources loaded once in before_all() and reused across all tests.
var _fighter          = null  ## data/classes/fighter.tres
var _wizard           = null  ## data/classes/wizard.tres
var _divine_warrior   = null  ## data/classes/divine_warrior.tres
var _divine_channeler = null  ## data/classes/divine_channeler.tres
var _titus            = null  ## data/characters/titus.tres (CharacterResource)
var _longsword        = null  ## data/weapons/longsword.tres
var _scale_mail       = null  ## data/armor/scale_mail.tres
## FEAT-049: additional character resources for full-party smoke test
var _gram_marx        = null  ## data/characters/gram_marx.tres (CharacterResource)
var _marigold         = null  ## data/characters/marigold.tres (CharacterResource)
var _dwarf_char       = null  ## data/characters/dwarf_channeler.tres (CharacterResource)


func before_all() -> void:
	_fighter          = ResourceLoader.load("res://data/classes/fighter.tres")
	_wizard           = ResourceLoader.load("res://data/classes/wizard.tres")
	_divine_warrior   = ResourceLoader.load("res://data/classes/divine_warrior.tres")
	_divine_channeler = ResourceLoader.load("res://data/classes/divine_channeler.tres")
	_titus            = ResourceLoader.load("res://data/characters/titus.tres")
	_longsword        = ResourceLoader.load("res://data/weapons/longsword.tres")
	_scale_mail       = ResourceLoader.load("res://data/armor/scale_mail.tres")
	## FEAT-049: load the remaining three character resources for full-party validation
	_gram_marx        = ResourceLoader.load("res://data/characters/gram_marx.tres")
	_marigold         = ResourceLoader.load("res://data/characters/marigold.tres")
	_dwarf_char       = ResourceLoader.load("res://data/characters/dwarf_channeler.tres")


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


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-049 (5) — test_full_party_all_four_characters_load
# Loads all four .tres character files and asserts each is non-null with a
# non-empty name.  Verifies FIX-002 integration: the CharacterResource schema
# is applied correctly to all party members, not just Titus.
# ══════════════════════════════════════════════════════════════════════════════

## test_full_party_all_four_characters_load
##
## Asserts that ResourceLoader successfully loads all four character .tres files
## as non-null CharacterResource instances each with a non-empty name field.
##
## Characters verified:
##   titus.tres          → name="Titus"   (Human Fighter)
##   gram_marx.tres      → name="Gram Marx" (Tiefling Wizard)
##   marigold.tres       → name="Marigold" (Elven Divine Warrior)
##   dwarf_channeler.tres → name="Dwarf Channeler" (Dwarf Divine Channeler)
##
## Satisfies: FEAT-049 criterion 1, FIX-002 integration.
func test_full_party_all_four_characters_load() -> void:
	## Verify Titus
	assert_not_null(
		_titus,
		"ResourceLoader.load('res://data/characters/titus.tres') must return non-null (FEAT-049 FIX-002)"
	)
	if _titus != null:
		assert_is(
			_titus, CharacterResource,
			"titus.tres must be a CharacterResource instance (FEAT-049 FIX-002)"
		)
		assert_true(
			_titus.name != "",
			"titus.tres must have non-empty name; got '%s' (FEAT-049 FIX-002)" % _titus.name
		)

	## Verify Gram Marx
	assert_not_null(
		_gram_marx,
		"ResourceLoader.load('res://data/characters/gram_marx.tres') must return non-null (FEAT-049 FIX-002)"
	)
	if _gram_marx != null:
		assert_is(
			_gram_marx, CharacterResource,
			"gram_marx.tres must be a CharacterResource instance (FEAT-049 FIX-002)"
		)
		assert_true(
			_gram_marx.name != "",
			"gram_marx.tres must have non-empty name; got '%s' (FEAT-049 FIX-002)" % _gram_marx.name
		)

	## Verify Marigold
	assert_not_null(
		_marigold,
		"ResourceLoader.load('res://data/characters/marigold.tres') must return non-null (FEAT-049 FIX-002)"
	)
	if _marigold != null:
		assert_is(
			_marigold, CharacterResource,
			"marigold.tres must be a CharacterResource instance (FEAT-049 FIX-002)"
		)
		assert_true(
			_marigold.name != "",
			"marigold.tres must have non-empty name; got '%s' (FEAT-049 FIX-002)" % _marigold.name
		)

	## Verify Dwarf Channeler
	assert_not_null(
		_dwarf_char,
		"ResourceLoader.load('res://data/characters/dwarf_channeler.tres') must return non-null (FEAT-049 FIX-002)"
	)
	if _dwarf_char != null:
		assert_is(
			_dwarf_char, CharacterResource,
			"dwarf_channeler.tres must be a CharacterResource instance (FEAT-049 FIX-002)"
		)
		assert_true(
			_dwarf_char.name != "",
			"dwarf_channeler.tres must have non-empty name; got '%s' (FEAT-049 FIX-002)" % _dwarf_char.name
		)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-049 (6) — test_spell_attacker_in_pipeline
# Constructs a Gram Marx combatant from gram_marx.tres with
# spellcasting_attribute read from the wizard class_ref (value='intellect').
# Calls resolve_spell_attack() through the live Resolution pipeline with a
# pinned RNG.  Asserts that hit, crit, and damage_final keys are present and
# have correct GDScript types.  Verifies FIX-004.
# ══════════════════════════════════════════════════════════════════════════════

## test_spell_attacker_in_pipeline
##
## Verifies the spell attack resolution pipeline end-to-end using Gram Marx
## (Tiefling Wizard) built from gram_marx.tres.
##
## Gram Marx spellcasting profile:
##   spellcasting_attribute = 'intellect' (read from wizard.tres class_ref)
##   intellect score        = 5           (from gram_marx.tres attributes)
##   spell_attack_bonus     = 0           (v0; no bonus beyond attribute)
##
## Pinned seed 42 is used for deterministic roll consumption.
##
## Satisfies: FEAT-049 criterion 3, FIX-004.
func test_spell_attacker_in_pipeline() -> void:
	if _gram_marx == null:
		fail_test(
			"gram_marx.tres failed to load — cannot verify spell attacker pipeline (FEAT-049 FIX-004)"
		)
		return

	if _gram_marx.class_ref == null:
		fail_test(
			"gram_marx.tres class_ref is null — wizard.tres dependency must load (FEAT-049 FIX-004)"
		)
		return

	# Verify the class resource has the expected spellcasting attribute
	var spell_attr: String = _gram_marx.class_ref.spellcasting_attribute
	assert_eq(
		spell_attr, "intellect",
		"gram_marx.class_ref.spellcasting_attribute must be 'intellect' (wizard class — FEAT-049 FIX-004)"
	)

	# Build Gram Marx attacker dict from resource fields
	var attacker: Dictionary = {}
	for k in _gram_marx.attributes:
		attacker[k] = _gram_marx.attributes[k]
	attacker["spellcasting_attribute"] = spell_attr
	attacker["spell_attack_bonus"] = 0  # v0: no extra bonus beyond attribute score

	# Inline target for testing
	var target: Dictionary = {"ac": 12, "reflex": 12, "fortitude": 14, "will": 11}

	# Minimal spell dict — only damage_die required by resolve_spell_attack()
	var spell: Dictionary = {"damage_die": 6}

	# Resolve spell attack with pinned seed (FEAT-049: pinned RNG for determinism)
	const SPELL_SEED: int = 42
	var resolution = ResolutionClass.new(RNGClass.new(SPELL_SEED))
	var result: Dictionary = resolution.resolve_spell_attack(attacker, target, spell, "ac")

	# Assert all three required keys are present
	assert_true(
		result.has("hit"),
		"resolve_spell_attack() result must contain 'hit' key (FEAT-049 FIX-004)"
	)
	assert_true(
		result.has("crit"),
		"resolve_spell_attack() result must contain 'crit' key (FEAT-049 FIX-004)"
	)
	assert_true(
		result.has("damage_final"),
		"resolve_spell_attack() result must contain 'damage_final' key (FEAT-049 FIX-004)"
	)

	# Assert correct GDScript types
	if result.has("hit"):
		assert_true(
			result["hit"] is bool,
			"result['hit'] must be bool; got type %s (FEAT-049 FIX-004)" % typeof(result["hit"])
		)
	if result.has("crit"):
		assert_true(
			result["crit"] is bool,
			"result['crit'] must be bool; got type %s (FEAT-049 FIX-004)" % typeof(result["crit"])
		)
	if result.has("damage_final"):
		assert_true(
			result["damage_final"] is int,
			"result['damage_final'] must be int; got type %s (FEAT-049 FIX-004)" % typeof(result["damage_final"])
		)
		assert_true(
			result["damage_final"] >= 0,
			"result['damage_final'] must be >= 0; got %d (FEAT-049 FIX-004)" % result["damage_final"]
		)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-049 (7) — test_titus_vs_skeleton_d12_longsword_pinned_seed
# Runs a Titus vs Skeleton encounter where Titus's weapon is longsword.tres
# (damage_die=12 after FIX-003).  Asserts: outcome in ['won','lost'],
# round_count >= 1, and at least one round_history entry has damage_final > 0
# proving the d12 weapon data flows through the full pipeline.
# Verifies FIX-003 end-to-end.
# ══════════════════════════════════════════════════════════════════════════════

## test_titus_vs_skeleton_d12_longsword_pinned_seed
##
## Smoke test confirming the d12 longsword data flows end-to-end through the
## full combat pipeline: data layer (longsword.tres.damage_die=12) →
## business logic (_build_titus_combatant builds weapon dict from resource) →
## encounter loop (Resolution uses damage_die for damage rolls) →
## round_history (damage_final reflects d12-range values).
##
## Assertions:
##   1. Encounter terminates with _outcome in ['won', 'lost'] (not empty).
##   2. At least one complete round executed (_round_count >= 1).
##   3. At least one round_history entry has damage_final > 0, confirming
##      the weapon damage calculation produced non-zero output.
##      (A d12 weapon can produce values up to 17 on a normal hit with
##       Titus's strength=5, exceeding the old d6 maximum of 11.)
##
## Satisfies: FEAT-049 criterion 4, FIX-003.
func test_titus_vs_skeleton_d12_longsword_pinned_seed() -> void:
	if _titus == null or _titus.class_ref == null \
			or _scale_mail == null or _longsword == null:
		fail_test(
			"Required resources failed to load — cannot verify d12 longsword pipeline (FEAT-049 FIX-003)"
		)
		return

	# Confirm longsword resource carries the corrected d12 value
	assert_eq(
		_longsword.damage_die, 12,
		"longsword.tres must have damage_die=12 — prerequisite for d12 pipeline test (FEAT-049 FIX-003)"
	)

	# Run the full encounter with the pinned steel-thread seed
	var enc = _make_encounter(STEEL_SEED)
	enc.run()

	# (1) Outcome must be terminal
	var outcome: String = enc.get_outcome()
	assert_true(
		outcome == "won" or outcome == "lost",
		"d12 longsword encounter must terminate with 'won' or 'lost' (seed %d); got '%s' (FEAT-049 FIX-003)"
		% [STEEL_SEED, outcome]
	)

	# (2) At least one complete round must have executed
	assert_true(
		enc.get_round_count() >= 1,
		"d12 longsword encounter must execute at least 1 round (seed %d); got %d (FEAT-049 FIX-003)"
		% [STEEL_SEED, enc.get_round_count()]
	)

	# (3) At least one history entry must show damage_final > 0
	var found_nonzero_damage: bool = false
	for entry in enc.get_round_history():
		if entry.get("damage_final", 0) > 0:
			found_nonzero_damage = true
			break

	assert_true(
		found_nonzero_damage,
		"At least one round_history entry must have damage_final > 0 — d12 damage flowing end-to-end (FEAT-049 FIX-003)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-049 (8) — test_simulator_balance_invariant_from_smoke
# Instantiates Simulator and asserts the SEED-AVERAGED mean win_rate
# (averaged across at least 3 distinct base seeds, consistent with FEAT-048's
# balance test) is in [0.40, 0.80].  Verifies FIX-005.
# ══════════════════════════════════════════════════════════════════════════════

## test_simulator_balance_invariant_from_smoke
##
## Cross-cutting smoke test that verifies Simulator produces balanced encounter
## outcomes from the integration test layer.  Uses the same seed configuration
## as FEAT-048's test_balance_invariant_seed_averaged:
##   Seeds: [42, 12345, 99999]  — widely spaced to sample different RNG regions
##   Battles per seed: 30       — 90 total encounters
##
## The SEED-AVERAGED mean win_rate must be in [0.40, 0.80] — the v0 balance gate.
## This test runs from the smoke layer (tests/integration/) to confirm the full
## stack from ResourceLoader → simulator loop produces balanced results.
##
## Satisfies: FEAT-049 criterion 5, FIX-005.
func test_simulator_balance_invariant_from_smoke() -> void:
	var sim = SimulatorClass.new()
	var seeds: Array = [42, 12345, 99999]
	var battles_per_seed: int = 30
	var total_win_rate: float = 0.0

	for seed in seeds:
		var result: Dictionary = sim.run(battles_per_seed, seed)
		assert_true(
			result.has("win_rate"),
			"sim.run(%d, %d) must return a dict with 'win_rate' key (FEAT-049 FIX-005)" % [battles_per_seed, seed]
		)
		total_win_rate += result.get("win_rate", 0.0)

	var mean_win_rate: float = total_win_rate / float(seeds.size())

	assert_true(
		mean_win_rate >= 0.40 and mean_win_rate <= 0.80,
		"SEED-AVERAGED mean win_rate must be in [0.40, 0.80]; got %.4f (FEAT-049 FIX-005)" % mean_win_rate
	)
