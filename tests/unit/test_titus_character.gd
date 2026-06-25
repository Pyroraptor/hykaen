extends GutTest
## tests/unit/test_titus_character.gd
##
## GUT test suite for FEAT-006: Titus Fighter Character .tres Resource.
## Validates all test criteria for US-006 — Titus character data and derived stats.
##
## Attribute spread (18 points — within 27-point budget):
##   STR=5 (cost 9), CON=4 (cost 6), DEX=2 (cost 2), WIL=2 (cost 2),
##   INT=1 (cost 1), Intuition=2 (cost 2), SOC=1 (cost 1) → total 23 points

const CharacterResource = preload("res://core/model/character_resource.gd")
const ClassResource     = preload("res://core/model/class_resource.gd")
const AttributesClass   = preload("res://core/rules/attributes.gd")
const RNGClass          = preload("res://core/rules/rng.gd")

## Load titus.tres once; reused across tests.
var _titus = null
## Load fighter.tres once; reused across derived-stat tests.
var _fighter_class = null

func before_all() -> void:
	_titus = ResourceLoader.load("res://data/characters/titus.tres")
	_fighter_class = ResourceLoader.load("res://data/classes/fighter.tres")


# ── ADR-003 text-format verification ─────────────────────────────────────────

func test_titus_tres_is_text_format() -> void:
	var file := FileAccess.open("res://data/characters/titus.tres", FileAccess.READ)
	assert_not_null(file, "data/characters/titus.tres must be readable")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.contains("[gd_resource"),
		"titus.tres first line must contain '[gd_resource' — text-format required (ADR-003)"
	)


# ── Resource loading ──────────────────────────────────────────────────────────

func test_titus_loads_non_null() -> void:
	assert_not_null(
		_titus,
		"ResourceLoader.load('data/characters/titus.tres') must return non-null"
	)


func test_titus_is_character_resource() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check type")
		return
	assert_is(_titus, CharacterResource, "titus.tres must be an instance of CharacterResource")


# ── Core identity fields ──────────────────────────────────────────────────────

func test_titus_name_is_Titus() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check name")
		return
	assert_eq(_titus.name, "Titus", "titus.name must be 'Titus'")


func test_titus_race_is_Human() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check race")
		return
	assert_eq(_titus.race, "Human", "titus.race must be 'Human'")


# ── Class reference — fighter.tres ───────────────────────────────────────────

func test_titus_class_ref_is_non_null() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check class_ref")
		return
	assert_not_null(_titus.class_ref, "titus.class_ref must not be null")


func test_titus_class_ref_is_class_resource() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check class_ref type")
		return
	if _titus.class_ref == null:
		fail_test("titus.class_ref is null — cannot check type")
		return
	assert_is(_titus.class_ref, ClassResource, "titus.class_ref must be an instance of ClassResource")


func test_titus_class_ref_has_fighter_class_hp() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check class_ref.class_hp")
		return
	if _titus.class_ref == null:
		fail_test("titus.class_ref is null — cannot check class_hp")
		return
	assert_eq(
		_titus.class_ref.class_hp, 6,
		"titus.class_ref.class_hp must be 6 (confirming fighter reference is intact)"
	)


func test_titus_class_ref_resource_path_loads_as_class_resource() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load")
		return
	if _titus.class_ref == null:
		fail_test("titus.class_ref is null")
		return
	var reloaded = ResourceLoader.load(_titus.class_ref.resource_path)
	assert_not_null(reloaded, "class_ref.resource_path must point to a loadable resource")
	if reloaded == null:
		return
	assert_is(reloaded, ClassResource, "reloaded class_ref resource must be a ClassResource")
	assert_eq(reloaded.class_hp, 6, "reloaded fighter must have class_hp == 6")


# ── Point-buy validation ──────────────────────────────────────────────────────

func test_titus_point_buy_validate_returns_valid() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot validate point buy")
		return
	var rng = RNGClass.new(0)
	var attrs = AttributesClass.new(rng)
	var result = attrs.point_buy_validate(_titus.attributes)
	assert_true(result["valid"], "point_buy_validate(titus.attributes) must return {valid: true}")


func test_titus_point_buy_cost_within_27() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check point buy cost")
		return
	var rng = RNGClass.new(0)
	var attrs = AttributesClass.new(rng)
	var result = attrs.point_buy_validate(_titus.attributes)
	assert_true(
		result["cost"] <= 27,
		"titus attribute point-buy cost must not exceed 27; got %d" % result["cost"]
	)


# ── Derived-stat computations using attributes.gd ────────────────────────────

## Criterion: compute_hp → 18 (8 + class_hp=6 + constitution=4)
func test_titus_compute_hp_equals_18() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot compute hp")
		return
	if _fighter_class == null:
		fail_test("fighter.tres failed to load — cannot compute hp")
		return
	var rng = RNGClass.new(0)
	var attrs = AttributesClass.new(rng)
	var hp: int = attrs.compute_hp(_titus.attributes, _fighter_class)
	assert_eq(hp, 18, "compute_hp(titus.attributes, fighter) must be 18 (8 + 6 + 4)")


## Criterion: compute_stamina → 10 (stamina_base=4 + willpower=2 + constitution=4)
func test_titus_compute_stamina_equals_10() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot compute stamina")
		return
	if _fighter_class == null:
		fail_test("fighter.tres failed to load — cannot compute stamina")
		return
	var rng = RNGClass.new(0)
	var attrs = AttributesClass.new(rng)
	var stamina: int = attrs.compute_stamina(_titus.attributes, _fighter_class)
	assert_eq(stamina, 10, "compute_stamina(titus.attributes, fighter) must be 10 (4 + 2 + 4)")


## Criterion: compute_ac(armor_base=4, category='medium') → 14 (10 + 4 + 0, no DEX bonus)
func test_titus_compute_ac_medium_armor_equals_14() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot compute AC")
		return
	var rng = RNGClass.new(0)
	var attrs = AttributesClass.new(rng)
	var ac: int = attrs.compute_ac(_titus.attributes, 4, "medium")
	assert_eq(ac, 14, "compute_ac(titus.attributes, armor_base=4, 'medium') must be 14 (10+4, no DEX)")


## Criterion: compute_reflex → 14 (10 + dexterity=2 + intuition=2)
func test_titus_compute_reflex_equals_14() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot compute reflex")
		return
	var rng = RNGClass.new(0)
	var attrs = AttributesClass.new(rng)
	var reflex: int = attrs.compute_reflex(_titus.attributes)
	assert_eq(reflex, 14, "compute_reflex(titus.attributes) must be 14 (10 + 2 + 2)")


## Criterion: compute_fortitude → 19 (10 + constitution=4 + strength=5)
func test_titus_compute_fortitude_equals_19() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot compute fortitude")
		return
	var rng = RNGClass.new(0)
	var attrs = AttributesClass.new(rng)
	var fortitude: int = attrs.compute_fortitude(_titus.attributes)
	assert_eq(fortitude, 19, "compute_fortitude(titus.attributes) must be 19 (10 + 4 + 5)")


## Criterion: compute_will → 13 (10 + willpower=2 + social=1)
func test_titus_compute_will_equals_13() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot compute will")
		return
	var rng = RNGClass.new(0)
	var attrs = AttributesClass.new(rng)
	var will: int = attrs.compute_will(_titus.attributes)
	assert_eq(will, 13, "compute_will(titus.attributes) must be 13 (10 + 2 + 1)")


# ── Starting equipment ────────────────────────────────────────────────────────

func test_titus_starting_equipment_has_at_least_two_items() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check starting_equipment")
		return
	assert_true(
		_titus.starting_equipment.size() >= 2,
		"titus.starting_equipment must have at least 2 items; got %d" % _titus.starting_equipment.size()
	)


func test_titus_starting_equipment_contains_longsword() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check starting_equipment")
		return
	var found: bool = false
	for item in _titus.starting_equipment:
		if str(item).ends_with("longsword.tres"):
			found = true
			break
	assert_true(
		found,
		"titus.starting_equipment must contain a path ending with 'longsword.tres'"
	)


func test_titus_starting_equipment_contains_scale_mail() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check starting_equipment")
		return
	var found: bool = false
	for item in _titus.starting_equipment:
		if str(item).ends_with("scale_mail.tres"):
			found = true
			break
	assert_true(
		found,
		"titus.starting_equipment must contain a path ending with 'scale_mail.tres'"
	)


# ── Talent selections (empty in v0) ──────────────────────────────────────────

func test_titus_talent_selections_is_empty() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check talent_selections")
		return
	assert_eq(
		_titus.talent_selections.size(), 0,
		"titus.talent_selections must be empty (v0 has no talent selections)"
	)


# ── Attribute score spot-checks ───────────────────────────────────────────────

func test_titus_strength_is_5() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check strength")
		return
	assert_eq(_titus.attributes.get("strength", -1), 5, "titus strength must be 5")


func test_titus_constitution_is_4() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check constitution")
		return
	assert_eq(_titus.attributes.get("constitution", -1), 4, "titus constitution must be 4")


func test_titus_dexterity_is_2() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check dexterity")
		return
	assert_eq(_titus.attributes.get("dexterity", -1), 2, "titus dexterity must be 2")


func test_titus_willpower_is_2() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check willpower")
		return
	assert_eq(_titus.attributes.get("willpower", -1), 2, "titus willpower must be 2")


func test_titus_intellect_is_1() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check intellect")
		return
	assert_eq(_titus.attributes.get("intellect", -1), 1, "titus intellect must be 1")


func test_titus_intuition_is_2() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check intuition")
		return
	assert_eq(_titus.attributes.get("intuition", -1), 2, "titus intuition must be 2")


func test_titus_social_is_1() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check social")
		return
	assert_eq(_titus.attributes.get("social", -1), 1, "titus social must be 1")
