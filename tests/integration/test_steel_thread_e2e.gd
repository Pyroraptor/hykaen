extends GutTest
## tests/integration/test_steel_thread_e2e.gd
##
## GUT integration test — FEAT-010: Steel Thread End-to-End Smoke Test.
## CI-Gated deterministic encounter validation.
##
## Satisfies: US-002, US-003, US-009
##
## Steel thread entry → exit:
##   data layer       → ResourceLoader.load('data/characters/titus.tres') non-null
##   business_logic   → attributes.gd computes HP=18, Stamina=10, AC=14, Reflex=14,
##                       Fortitude=19, Will=13 from titus.tres spread
##   integration      → encounter.run() terminates; outcome in ['won','lost']; round_count >= 1
##   determinism proof → Run 1 and Run 2 with seed 99999 produce byte-identical
##                       roll and damage_final sequences (exit_point)
##
## CI exit contract: godot --headless -- --gut-run-all exits 0.

const EncounterClass    = preload("res://core/combat/encounter.gd")
const RNGClass          = preload("res://core/rules/rng.gd")
const AttributesClass   = preload("res://core/rules/attributes.gd")
const CharacterResource = preload("res://core/model/character_resource.gd")

## Pinned seed for all steel-thread determinism tests.
const STEEL_SEED: int = 99999

## Resources loaded once in before_all() and reused across all tests.
var _titus       = null
var _fighter_class = null
var _scale_mail  = null
var _longsword   = null


func before_all() -> void:
	_titus      = ResourceLoader.load("res://data/characters/titus.tres")
	_scale_mail = ResourceLoader.load("res://data/armor/scale_mail.tres")
	_longsword  = ResourceLoader.load("res://data/weapons/longsword.tres")
	if _titus != null:
		_fighter_class = _titus.class_ref


# ── Fixture helpers ────────────────────────────────────────────────────────────

## Builds a combatant Dictionary for Titus derived from the loaded .tres resources.
## Computes HP and AC via attributes.gd (business_logic layer) so the encounter
## receives real derived stats rather than hardcoded constants.
##
## Note: longsword.tres stores damage_modifier_attribute as "str" (abbreviated),
## but the combat system resolves attacker.get("strength"). The key is mapped
## here to match the combat dictionary convention shared by all encounter tests.
func _build_titus_combatant() -> Dictionary:
	var attrs = AttributesClass.new(RNGClass.new(0))
	var hp    = attrs.compute_hp(_titus.attributes, _fighter_class)
	var ac    = attrs.compute_ac(_titus.attributes, _scale_mail.ac_base, _scale_mail.category)
	return {
		"name":       _titus.name,
		"hp_current": hp,
		"ac":         ac,
		"strength":   _titus.attributes.get("strength",  0),
		"dexterity":  _titus.attributes.get("dexterity", 0),
		"intuition":  _titus.attributes.get("intuition", 0),
		"weapon": {
			## "str" resource key → "strength" combat key (encounter convention)
			"damage_modifier_attribute": "strength",
			"proficiency_bonus":         _longsword.proficiency_bonus,
			"damage_die":                _longsword.damage_die
		}
	}


## Inline Skeleton stub (no .tres loading required — ADR-006 integration-test
## pattern: enemies are defined inline for portability).
func _skeleton_dict() -> Dictionary:
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


## Builds a fresh Encounter from a newly constructed Titus combatant dict and
## an inline Skeleton stub, seeded with seed_value.  Fresh instances every call
## guarantees no shared state between Run 1 and Run 2.
func _make_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_build_titus_combatant()],
		[_skeleton_dict()],
		RNGClass.new(seed_value)
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1 — Data Layer
# ResourceLoader.load('data/characters/titus.tres') returns non-null CharacterResource
# ══════════════════════════════════════════════════════════════════════════════

func test_data_layer_titus_tres_loads_non_null() -> void:
	assert_not_null(
		_titus,
		"ResourceLoader.load('data/characters/titus.tres') must return non-null"
	)


func test_data_layer_titus_is_character_resource() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot verify CharacterResource type")
		return
	assert_is(
		_titus, CharacterResource,
		"titus.tres must be an instance of CharacterResource (data layer validated)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2 — Business Logic Layer
# attributes.gd computes all six derived stats from titus.tres spread
# Expected: HP=18, Stamina=10, AC=14, Reflex=14, Fortitude=19, Will=13
# ══════════════════════════════════════════════════════════════════════════════

func test_business_logic_layer_hp_equals_18() -> void:
	if _titus == null or _fighter_class == null:
		fail_test("titus.tres or fighter class failed to load — cannot compute HP")
		return
	var attrs = AttributesClass.new(RNGClass.new(0))
	var hp: int = attrs.compute_hp(_titus.attributes, _fighter_class)
	assert_eq(hp, 18,
		"HP must be 18 (8 + class_hp=6 + constitution=4) — business_logic layer")


func test_business_logic_layer_stamina_equals_10() -> void:
	if _titus == null or _fighter_class == null:
		fail_test("titus.tres or fighter class failed to load — cannot compute Stamina")
		return
	var attrs = AttributesClass.new(RNGClass.new(0))
	var stamina: int = attrs.compute_stamina(_titus.attributes, _fighter_class)
	assert_eq(stamina, 10,
		"Stamina must be 10 (stamina_base=4 + willpower=2 + constitution=4) — business_logic layer")


func test_business_logic_layer_ac_equals_14() -> void:
	if _titus == null or _scale_mail == null:
		fail_test("titus.tres or scale_mail.tres failed to load — cannot compute AC")
		return
	var attrs = AttributesClass.new(RNGClass.new(0))
	var ac: int = attrs.compute_ac(_titus.attributes, _scale_mail.ac_base, _scale_mail.category)
	assert_eq(ac, 14,
		"AC must be 14 (10 + ac_base=4, medium armor — no DEX bonus) — business_logic layer")


func test_business_logic_layer_reflex_equals_14() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot compute Reflex")
		return
	var attrs = AttributesClass.new(RNGClass.new(0))
	var reflex: int = attrs.compute_reflex(_titus.attributes)
	assert_eq(reflex, 14,
		"Reflex must be 14 (10 + dexterity=2 + intuition=2) — business_logic layer")


func test_business_logic_layer_fortitude_equals_19() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot compute Fortitude")
		return
	var attrs = AttributesClass.new(RNGClass.new(0))
	var fortitude: int = attrs.compute_fortitude(_titus.attributes)
	assert_eq(fortitude, 19,
		"Fortitude must be 19 (10 + constitution=4 + strength=5) — business_logic layer")


func test_business_logic_layer_will_equals_13() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot compute Will")
		return
	var attrs = AttributesClass.new(RNGClass.new(0))
	var will: int = attrs.compute_will(_titus.attributes)
	assert_eq(will, 13,
		"Will must be 13 (10 + willpower=2 + social=1) — business_logic layer")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3 — Integration Layer
# encounter.run() terminates; get_outcome() in ['won','lost']; get_round_count() >= 1
# ══════════════════════════════════════════════════════════════════════════════

func test_integration_layer_encounter_run_terminates_with_valid_outcome() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot run encounter")
		return
	var enc = _make_encounter(STEEL_SEED)
	enc.run()
	var outcome: String = enc.get_outcome()
	assert_true(
		outcome == "won" or outcome == "lost",
		"encounter.run() must terminate with 'won' or 'lost'; got '%s'" % outcome
	)


func test_integration_layer_round_count_at_least_1() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot run encounter")
		return
	var enc = _make_encounter(STEEL_SEED)
	enc.run()
	assert_true(
		enc.get_round_count() >= 1,
		"get_round_count() must be >= 1 after run(); got %d" % enc.get_round_count()
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4 — Determinism: Run 2 with seed 99999 produces identical outcome
# ══════════════════════════════════════════════════════════════════════════════

func test_determinism_run2_identical_outcome() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check determinism")
		return
	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()
	assert_eq(
		enc2.get_outcome(), enc1.get_outcome(),
		"Run 2 with seed %d must produce the same outcome as Run 1 (determinism proof)" % STEEL_SEED
	)


func test_determinism_run2_identical_round_count() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check determinism")
		return
	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()
	assert_eq(
		enc2.get_round_count(), enc1.get_round_count(),
		"Run 2 with seed %d must complete in the same number of rounds as Run 1" % STEEL_SEED
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5 — Determinism: byte-identical roll and damage_final per index i
## For every i in range(len(run1_history)):
##   run2_history[i].roll         == run1_history[i].roll
##   run2_history[i].damage_final == run1_history[i].damage_final
# ══════════════════════════════════════════════════════════════════════════════

func test_determinism_run2_round_history_same_length() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check round history")
		return
	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()
	assert_eq(
		enc2.get_round_history().size(), enc1.get_round_history().size(),
		"Run 1 and Run 2 with seed %d must have identical round_history length" % STEEL_SEED
	)


func test_determinism_run2_roll_values_byte_identical() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check determinism")
		return
	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()
	var run1_history: Array = enc1.get_round_history()
	var run2_history: Array = enc2.get_round_history()
	var count: int = mini(run1_history.size(), run2_history.size())
	for i in range(count):
		var r1: int = run1_history[i].get("roll", -1)
		var r2: int = run2_history[i].get("roll", -1)
		assert_eq(
			r2, r1,
			"round_history[%d].roll: Run 1=%d, Run 2=%d — must be byte-identical (seed %d)"
			% [i, r1, r2, STEEL_SEED]
		)


func test_determinism_run2_damage_final_values_byte_identical() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check determinism")
		return
	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()
	var run1_history: Array = enc1.get_round_history()
	var run2_history: Array = enc2.get_round_history()
	var count: int = mini(run1_history.size(), run2_history.size())
	for i in range(count):
		var d1: int = run1_history[i].get("damage_final", -1)
		var d2: int = run2_history[i].get("damage_final", -1)
		assert_eq(
			d2, d1,
			"round_history[%d].damage_final: Run 1=%d, Run 2=%d — must be byte-identical (seed %d)"
			% [i, d1, d2, STEEL_SEED]
		)


# ══════════════════════════════════════════════════════════════════════════════
# Steel Thread Validation Banner
# Prints the confirmation line visible in CI artifact log.
# ══════════════════════════════════════════════════════════════════════════════

func test_steel_thread_validated_banner() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — steel thread cannot be validated")
		return
	var enc = _make_encounter(STEEL_SEED)
	enc.run()
	var outcome: String  = enc.get_outcome()
	var rounds: int      = enc.get_round_count()
	gut.p("STEEL THREAD VALIDATED: seed %d, outcome %s, rounds %d"
		% [STEEL_SEED, outcome, rounds])
	assert_true(
		outcome == "won" or outcome == "lost",
		"Steel thread banner: encounter must complete with valid outcome"
	)
