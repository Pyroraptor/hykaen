extends GutTest
## tests/unit/test_attributes.gd
##
## GUT test suite for core/rules/attributes.gd — Attribute and Derived-Stat
## Computation Module.  Validates all test criteria for FEAT-005 / US-005.
##
## Pin: RandomNumberGenerator(seed=12345).randi_range(1,20) = 17
##   → roll_initiative({dexterity:2, intuition:2}) = 17 + 2 + 2 = 21

const AttributesClass = preload("res://core/rules/attributes.gd")
const RNGClass        = preload("res://core/rules/rng.gd")

## Load the fighter ClassResource once; reused across multiple tests.
var _fighter_class = null

func before_all() -> void:
	_fighter_class = ResourceLoader.load("res://data/classes/fighter.tres")


# ── Helpers ───────────────────────────────────────────────────────────────────

## Build a fresh Attributes instance backed by an RNG with the given seed.
func _make_attrs(seed_value: int = 0) -> AttributesClass:
	var rng = RNGClass.new(seed_value)
	return AttributesClass.new(rng)


# ── point_buy_validate — valid allocations ────────────────────────────────────

## Criterion: a 21-cost spread → {valid:true, cost:21}
## Scores: strength:5(9) + constitution:4(6) + dexterity:2(2) + willpower:1(1)
##         + intellect:1(1) + intuition:1(1) + social:1(1) = 21
func test_point_buy_validate_valid_21_cost() -> void:
	var attrs = _make_attrs()
	var scores := {
		"strength": 5,
		"constitution": 4,
		"dexterity": 2,
		"willpower": 1,
		"intellect": 1,
		"intuition": 1,
		"social": 1
	}
	var result = attrs.point_buy_validate(scores)
	assert_true(result["valid"], "21-cost allocation must be valid")
	assert_eq(result["cost"], 21, "cost must be 21")


## Criterion: allocation summing to exactly 27 → {valid:true}
## Scores: strength:6(12) + constitution:4(6) + dexterity:3(4) + willpower:2(2)
##         + intellect:1(1) + intuition:1(1) + social:1(1) = 27
func test_point_buy_validate_exactly_27_valid() -> void:
	var attrs = _make_attrs()
	var scores := {
		"strength": 6,
		"constitution": 4,
		"dexterity": 3,
		"willpower": 2,
		"intellect": 1,
		"intuition": 1,
		"social": 1
	}
	var result = attrs.point_buy_validate(scores)
	assert_true(result["valid"], "exactly-27-cost allocation must be valid")
	assert_eq(result["cost"], 27, "cost must be 27")


# ── point_buy_validate — over-budget ─────────────────────────────────────────

## Criterion: allocation summing to 28 → {valid:false, cost:28, error contains '27'}
## Scores: strength:6(12) + constitution:4(6) + dexterity:3(4) + willpower:2(2)
##         + intellect:1(1) + intuition:2(2) + social:1(1) = 28
func test_point_buy_validate_28_cost_invalid() -> void:
	var attrs = _make_attrs()
	var scores := {
		"strength": 6,
		"constitution": 4,
		"dexterity": 3,
		"willpower": 2,
		"intellect": 1,
		"intuition": 2,
		"social": 1
	}
	var result = attrs.point_buy_validate(scores)
	assert_false(result["valid"], "28-cost allocation must be invalid")
	assert_eq(result["cost"], 28, "cost must report 28")
	assert_true(
		result["error"].contains("27"),
		"error must mention the 27-point cap; got: '%s'" % result["error"]
	)


# ── point_buy_validate — range violations ─────────────────────────────────────

## Criterion: any score < 1 → {valid:false, error contains range message}
func test_point_buy_validate_score_below_1() -> void:
	var attrs = _make_attrs()
	var scores := {
		"strength": 0,
		"constitution": 3,
		"dexterity": 2,
		"willpower": 2,
		"intellect": 1,
		"intuition": 2,
		"social": 1
	}
	var result = attrs.point_buy_validate(scores)
	assert_false(result["valid"], "score 0 must produce invalid result")
	assert_true(
		result["error"].contains("range") or result["error"].contains("1"),
		"error must contain range information; got: '%s'" % result["error"]
	)


## Criterion: any score > 6 → {valid:false, error contains range message}
func test_point_buy_validate_score_above_6() -> void:
	var attrs = _make_attrs()
	var scores := {
		"strength": 7,
		"constitution": 3,
		"dexterity": 2,
		"willpower": 2,
		"intellect": 1,
		"intuition": 2,
		"social": 1
	}
	var result = attrs.point_buy_validate(scores)
	assert_false(result["valid"], "score 7 must produce invalid result")
	assert_true(
		result["error"].contains("range") or result["error"].contains("6"),
		"error must contain range information; got: '%s'" % result["error"]
	)


# ── compute_hp ────────────────────────────────────────────────────────────────

## Criterion: compute_hp({constitution:4}, fighter) → 18 (8 + 6 + 4)
func test_compute_hp_fighter_constitution_4() -> void:
	if _fighter_class == null:
		fail_test("fighter.tres failed to load — cannot test compute_hp")
		return
	var attrs = _make_attrs()
	var scores := {"constitution": 4}
	var hp: int = attrs.compute_hp(scores, _fighter_class)
	assert_eq(hp, 18, "compute_hp with fighter(class_hp=6) and constitution=4 must be 18 (8+6+4)")


# ── compute_stamina ───────────────────────────────────────────────────────────

## Criterion: compute_stamina({willpower:2,constitution:4}, fighter) → 10 (4+2+4)
func test_compute_stamina_fighter_willpower2_constitution4() -> void:
	if _fighter_class == null:
		fail_test("fighter.tres failed to load — cannot test compute_stamina")
		return
	var attrs = _make_attrs()
	var scores := {"willpower": 2, "constitution": 4}
	var stamina: int = attrs.compute_stamina(scores, _fighter_class)
	assert_eq(stamina, 10, "compute_stamina with fighter(stamina_base=4) and wil=2,con=4 must be 10 (4+2+4)")


# ── compute_ac ────────────────────────────────────────────────────────────────

## Criterion: medium armor, armor_base=4, dex=3 → 14 (10+4, no DEX bonus)
func test_compute_ac_medium_no_dex_bonus() -> void:
	var attrs = _make_attrs()
	var scores := {"dexterity": 3}
	var ac: int = attrs.compute_ac(scores, 4, "medium")
	assert_eq(ac, 14, "compute_ac medium armor(base=4) dex=3 must be 14 (10+4+0)")


## Criterion: light armor, armor_base=2, dex=3 → 15 (10+2+3)
func test_compute_ac_light_dex_bonus_applies() -> void:
	var attrs = _make_attrs()
	var scores := {"dexterity": 3}
	var ac: int = attrs.compute_ac(scores, 2, "light")
	assert_eq(ac, 15, "compute_ac light armor(base=2) dex=3 must be 15 (10+2+3)")


## Criterion: none armor, armor_base=0, dex=3 → 13 (10+0+3)
func test_compute_ac_none_dex_bonus_applies() -> void:
	var attrs = _make_attrs()
	var scores := {"dexterity": 3}
	var ac: int = attrs.compute_ac(scores, 0, "none")
	assert_eq(ac, 13, "compute_ac none armor(base=0) dex=3 must be 13 (10+0+3)")


# ── compute_reflex ────────────────────────────────────────────────────────────

## Criterion: compute_reflex({dexterity:2, intuition:2}) → 14
func test_compute_reflex_dex2_intuition2() -> void:
	var attrs = _make_attrs()
	var scores := {"dexterity": 2, "intuition": 2}
	var reflex: int = attrs.compute_reflex(scores)
	assert_eq(reflex, 14, "compute_reflex with dex=2, intuition=2 must be 14 (10+2+2)")


# ── compute_fortitude ─────────────────────────────────────────────────────────

## Criterion: compute_fortitude({constitution:4, strength:5}) → 19
func test_compute_fortitude_con4_str5() -> void:
	var attrs = _make_attrs()
	var scores := {"constitution": 4, "strength": 5}
	var fort: int = attrs.compute_fortitude(scores)
	assert_eq(fort, 19, "compute_fortitude with con=4, str=5 must be 19 (10+4+5)")


# ── compute_will ──────────────────────────────────────────────────────────────

## Criterion: compute_will({willpower:2, social:1}) → 13
func test_compute_will_willpower2_social1() -> void:
	var attrs = _make_attrs()
	var scores := {"willpower": 2, "social": 1}
	var will: int = attrs.compute_will(scores)
	assert_eq(will, 13, "compute_will with wil=2, soc=1 must be 13 (10+2+1)")


# ── compute_skills_known ──────────────────────────────────────────────────────

## Criterion: compute_skills_known({intellect:1}, fighter) → 2 (1+1)
func test_compute_skills_known_fighter_intellect1() -> void:
	if _fighter_class == null:
		fail_test("fighter.tres failed to load — cannot test compute_skills_known")
		return
	var attrs = _make_attrs()
	var scores := {"intellect": 1}
	var skills: int = attrs.compute_skills_known(scores, _fighter_class)
	assert_eq(skills, 2, "compute_skills_known with fighter(skills_base=1) and intellect=1 must be 2 (1+1)")


# ── roll_initiative ───────────────────────────────────────────────────────────

## Criterion: roll_initiative({dexterity:2, intuition:2}) with seed 12345 →
##   deterministic pinned value.
##
## Manually computed:
##   RandomNumberGenerator(seed=12345).randi_range(1,20) = 17
##   initiative = 17 + intuition(2) + dexterity(2) = 21
##
## The RNG used in Attributes is the injected instance; first d20() call
## consumes the first draw from the sequence, giving the pinned result.
const _EXPECTED_INITIATIVE_SEED_12345: int = 21

func test_roll_initiative_deterministic_seed_12345() -> void:
	var rng = RNGClass.new(12345)
	var attrs = AttributesClass.new(rng)
	var scores := {"dexterity": 2, "intuition": 2}
	var initiative: int = attrs.roll_initiative(scores)
	assert_eq(
		initiative,
		_EXPECTED_INITIATIVE_SEED_12345,
		"roll_initiative(dex=2, intuition=2) with seed 12345 must be %d (d20=17 + 2 + 2)" % _EXPECTED_INITIATIVE_SEED_12345
	)


## Additional determinism check: two instances with the same seed produce
## the same initiative roll.
func test_roll_initiative_reproducible_across_same_seed() -> void:
	var rng_a = RNGClass.new(42)
	var attrs_a = AttributesClass.new(rng_a)
	var rng_b = RNGClass.new(42)
	var attrs_b = AttributesClass.new(rng_b)
	var scores := {"dexterity": 3, "intuition": 3}
	var roll_a: int = attrs_a.roll_initiative(scores)
	var roll_b: int = attrs_b.roll_initiative(scores)
	assert_eq(roll_a, roll_b, "Same seed must produce identical initiative rolls")


# ── Domain purity — no Node/Control inheritance ───────────────────────────────

## Criterion (CI linter step 1): attributes.gd must not extend Node or Control.
func test_attributes_gd_no_node_inheritance() -> void:
	var file := FileAccess.open("res://core/rules/attributes.gd", FileAccess.READ)
	assert_not_null(file, "core/rules/attributes.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"attributes.gd must not contain 'extends Node' — ADR-001 domain purity"
	)
	assert_false(
		content.contains("extends Control"),
		"attributes.gd must not contain 'extends Control' — ADR-001 domain purity"
	)


# ── point_buy_validate — key validation (FEAT-022 / DEF-004) ─────────────────

## Criterion: {strength: 5} alone → {valid:false, error contains 'Missing required attributes'}
func test_point_buy_validate_single_key_returns_invalid() -> void:
	var attrs = _make_attrs()
	var scores := {"strength": 5}
	var result = attrs.point_buy_validate(scores)
	assert_false(result["valid"], "single-key dict must be invalid")
	assert_true(
		result["error"].contains("Missing required attributes"),
		"error must mention 'Missing required attributes'; got: '%s'" % result["error"]
	)
	assert_eq(result["cost"], 0, "cost must be 0 when keys are invalid")


## Criterion: abbreviated keys → {valid:false, error contains 'unknown keys'}
func test_point_buy_validate_wrong_key_name_returns_invalid() -> void:
	var attrs = _make_attrs()
	# abbreviated/misspelled keys: str, con, dex, wil, int are NOT the canonical names
	var scores := {
		"str": 5,
		"con": 4,
		"dex": 2,
		"wil": 2,
		"int": 1,
		"intuition": 2,
		"social": 1
	}
	var result = attrs.point_buy_validate(scores)
	assert_false(result["valid"], "abbreviated keys must be invalid")
	assert_true(
		result["error"].to_lower().contains("unknown keys"),
		"error must mention 'unknown keys'; got: '%s'" % result["error"]
	)


## Criterion: empty dict → {valid:false, error lists all 7 missing keys}
func test_point_buy_validate_empty_dict_returns_invalid() -> void:
	var attrs = _make_attrs()
	var scores := {}
	var result = attrs.point_buy_validate(scores)
	assert_false(result["valid"], "empty dict must be invalid")
	assert_true(
		result["error"].contains("Missing required attributes"),
		"error must mention 'Missing required attributes'; got: '%s'" % result["error"]
	)
	# All 7 required keys should be listed
	assert_true(result["error"].contains("strength"), "error must list 'strength'")
	assert_true(result["error"].contains("constitution"), "error must list 'constitution'")
	assert_true(result["error"].contains("dexterity"), "error must list 'dexterity'")
	assert_true(result["error"].contains("willpower"), "error must list 'willpower'")
	assert_true(result["error"].contains("intellect"), "error must list 'intellect'")
	assert_true(result["error"].contains("intuition"), "error must list 'intuition'")
	assert_true(result["error"].contains("social"), "error must list 'social'")
	assert_eq(result["cost"], 0, "cost must be 0 for empty dict")


## Criterion: six keys, missing 'willpower' → {valid:false, error contains 'willpower'}
func test_point_buy_validate_six_keys_missing_one_returns_invalid() -> void:
	var attrs = _make_attrs()
	var scores := {
		"strength": 5,
		"constitution": 4,
		"dexterity": 2,
		"intellect": 1,
		"intuition": 1,
		"social": 1
		# willpower is intentionally missing
	}
	var result = attrs.point_buy_validate(scores)
	assert_false(result["valid"], "six keys (missing willpower) must be invalid")
	assert_true(
		result["error"].contains("willpower"),
		"error must mention missing key 'willpower'; got: '%s'" % result["error"]
	)
	assert_eq(result["cost"], 0, "cost must be 0 when key missing")


## Criterion: all 7 correct keys + extra 'charisma' → {valid:false, error contains 'unknown keys: charisma'}
func test_point_buy_validate_extra_key_returns_invalid() -> void:
	var attrs = _make_attrs()
	var scores := {
		"strength": 5,
		"constitution": 4,
		"dexterity": 2,
		"willpower": 1,
		"intellect": 1,
		"intuition": 1,
		"social": 1,
		"charisma": 3  # extra, unknown key
	}
	var result = attrs.point_buy_validate(scores)
	assert_false(result["valid"], "extra key 'charisma' must make result invalid")
	assert_true(
		result["error"].to_lower().contains("unknown keys"),
		"error must mention 'unknown keys'; got: '%s'" % result["error"]
	)
	assert_true(
		result["error"].contains("charisma"),
		"error must mention the unknown key 'charisma'; got: '%s'" % result["error"]
	)
	assert_eq(result["cost"], 0, "cost must be 0 when unknown keys present")


# ── Domain purity — no Node/Control inheritance ───────────────────────────────

## The CI RNG-linter (ADR-002) must not flag attributes.gd.
## Ensures attributes.gd contains no direct RandomNumberGenerator.new(),
## randf(), or randi() calls — all randomness flows through the injected RNG.
func test_attributes_gd_no_direct_rng_calls() -> void:
	var file := FileAccess.open("res://core/rules/attributes.gd", FileAccess.READ)
	assert_not_null(file, "core/rules/attributes.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("RandomNumberGenerator.new()"),
		"attributes.gd must not instantiate RandomNumberGenerator directly (ADR-002)"
	)
	assert_false(
		content.contains("randf("),
		"attributes.gd must not call randf() directly (ADR-002)"
	)
	assert_false(
		content.contains("randi("),
		"attributes.gd must not call randi() directly (ADR-002)"
	)
