extends GutTest
## tests/unit/test_remaining_characters.gd
##
## GUT test suite for FEAT-045 / FEAT-076: Three Remaining Party Member Character .tres Resources.
## Validates all test criteria for US-006 — Gram Marx, Marigold, and Dwarf Channeler.
##
## Gram Marx (Tiefling Wizard, INT-primary, 22 points):
##   STR=1(1) + CON=2(2) + DEX=2(2) + WIL=2(2) + INT=5(9) + Intuition=3(4) + SOC=2(2) = 22
##
## Marigold (Elf Divine Champion, DEX-primary, 25 points):
##   STR=3(4) + CON=3(4) + DEX=3(4) + WIL=4(6) + INT=1(1) + Intuition=3(4) + SOC=2(2) = 25
##
## Dwarf Channeler (Dwarf Divine Channeler, SOC/CON dual-primary, 23 points):
##   STR=2(2) + CON=4(6) + DEX=1(1) + WIL=3(4) + INT=2(2) + Intuition=2(2) + SOC=4(6) = 23

const CharacterResource = preload("res://core/model/character_resource.gd")
const ClassResource     = preload("res://core/model/class_resource.gd")
const AttributesClass   = preload("res://core/rules/attributes.gd")
const RNGClass          = preload("res://core/rules/rng.gd")

## Resources loaded once and reused across derived-stat tests.
var _gram_marx = null
var _marigold = null
var _dwarf_channeler = null
var _titus = null
var _wizard_class = null
var _divine_warrior_class = null
var _divine_channeler_class = null


func before_all() -> void:
	_gram_marx = ResourceLoader.load("res://data/characters/gram_marx.tres")
	_marigold = ResourceLoader.load("res://data/characters/marigold.tres")
	_dwarf_channeler = ResourceLoader.load("res://data/characters/dwarf_channeler.tres")
	_titus = ResourceLoader.load("res://data/characters/titus.tres")
	_wizard_class = ResourceLoader.load("res://data/classes/wizard.tres")
	_divine_warrior_class = ResourceLoader.load("res://data/classes/divine_warrior.tres")
	_divine_channeler_class = ResourceLoader.load("res://data/classes/divine_channeler.tres")


## Helper: fresh Attributes instance with seed 0.
func _make_attrs() -> AttributesClass:
	var rng = RNGClass.new(0)
	return AttributesClass.new(rng)


# ════════════════════════════════════════════════════════════════════════════
# GRAM MARX — Tiefling Wizard
# ════════════════════════════════════════════════════════════════════════════

# ── ADR-003 text-format verification ─────────────────────────────────────────

func test_gram_marx_tres_is_text_format() -> void:
	var file := FileAccess.open("res://data/characters/gram_marx.tres", FileAccess.READ)
	assert_not_null(file, "data/characters/gram_marx.tres must be readable")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.contains("[gd_resource"),
		"gram_marx.tres first line must contain '[gd_resource' — text-format required (ADR-003)"
	)


# ── Resource loading ──────────────────────────────────────────────────────────

func test_gram_marx_loads_non_null() -> void:
	assert_not_null(
		_gram_marx,
		"ResourceLoader.load('data/characters/gram_marx.tres') must return non-null"
	)


func test_gram_marx_is_character_resource() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load — cannot check type")
		return
	assert_is(_gram_marx, CharacterResource, "gram_marx.tres must be an instance of CharacterResource")


# ── Core identity fields ──────────────────────────────────────────────────────

func test_gram_marx_name_is_Gram_Marx() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load — cannot check name")
		return
	assert_eq(_gram_marx.name, "Gram Marx", "gram_marx.name must be 'Gram Marx'")


func test_gram_marx_race_is_Tiefling() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load — cannot check race")
		return
	assert_eq(_gram_marx.race, "Tiefling", "gram_marx.race must be 'Tiefling'")


# ── Class reference — wizard.tres ─────────────────────────────────────────────

func test_gram_marx_class_ref_is_non_null() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load — cannot check class_ref")
		return
	assert_not_null(_gram_marx.class_ref, "gram_marx.class_ref must not be null")


func test_gram_marx_class_ref_is_class_resource() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load — cannot check class_ref type")
		return
	if _gram_marx.class_ref == null:
		fail_test("gram_marx.class_ref is null — cannot check type")
		return
	assert_is(_gram_marx.class_ref, ClassResource, "gram_marx.class_ref must be a ClassResource")


func test_gram_marx_class_ref_resolves_to_wizard() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load")
		return
	if _gram_marx.class_ref == null:
		fail_test("gram_marx.class_ref is null")
		return
	assert_eq(
		_gram_marx.class_ref.class_id, "wizard",
		"gram_marx.class_ref.class_id must be 'wizard'"
	)


func test_gram_marx_class_ref_resource_path_ends_with_wizard_tres() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load")
		return
	if _gram_marx.class_ref == null:
		fail_test("gram_marx.class_ref is null")
		return
	assert_true(
		_gram_marx.class_ref.resource_path.ends_with("wizard.tres"),
		"gram_marx.class_ref.resource_path must end with 'wizard.tres'; got '%s'" % _gram_marx.class_ref.resource_path
	)


# ── Point-buy validation ──────────────────────────────────────────────────────

func test_gram_marx_point_buy_returns_valid_true() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load — cannot validate point buy")
		return
	var attrs = _make_attrs()
	var result = attrs.point_buy_validate(_gram_marx.attributes)
	assert_true(result["valid"], "point_buy_validate(gram_marx.attributes) must return {valid: true}")


func test_gram_marx_point_buy_cost_is_22() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load — cannot check point buy cost")
		return
	var attrs = _make_attrs()
	var result = attrs.point_buy_validate(_gram_marx.attributes)
	assert_eq(result["cost"], 22, "gram_marx point-buy cost must be 22; got %d" % result["cost"])


# ── Attribute score spot-checks ───────────────────────────────────────────────

func test_gram_marx_strength_is_1() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load")
		return
	assert_eq(_gram_marx.attributes.get("strength", -1), 1, "gram_marx strength must be 1")


func test_gram_marx_constitution_is_2() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load")
		return
	assert_eq(_gram_marx.attributes.get("constitution", -1), 2, "gram_marx constitution must be 2")


func test_gram_marx_dexterity_is_2() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load")
		return
	assert_eq(_gram_marx.attributes.get("dexterity", -1), 2, "gram_marx dexterity must be 2")


func test_gram_marx_willpower_is_2() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load")
		return
	assert_eq(_gram_marx.attributes.get("willpower", -1), 2, "gram_marx willpower must be 2")


func test_gram_marx_intellect_is_5() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load")
		return
	assert_eq(_gram_marx.attributes.get("intellect", -1), 5, "gram_marx intellect must be 5")


func test_gram_marx_intuition_is_3() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load")
		return
	assert_eq(_gram_marx.attributes.get("intuition", -1), 3, "gram_marx intuition must be 3")


func test_gram_marx_social_is_2() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load")
		return
	assert_eq(_gram_marx.attributes.get("social", -1), 2, "gram_marx social must be 2")


# ── Derived-stat computations using attributes.gd ────────────────────────────

## HP = 8 + class_hp(4) + constitution(2) = 14
func test_gram_marx_compute_hp_equals_14() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load — cannot compute hp")
		return
	if _wizard_class == null:
		fail_test("wizard.tres failed to load — cannot compute hp")
		return
	var attrs = _make_attrs()
	var hp: int = attrs.compute_hp(_gram_marx.attributes, _wizard_class)
	assert_eq(hp, 14, "compute_hp(gram_marx.attributes, wizard) must be 14 (8 + 4 + 2)")


## Stamina = stamina_base(1) + willpower(2) + constitution(2) = 5
func test_gram_marx_compute_stamina_equals_5() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load — cannot compute stamina")
		return
	if _wizard_class == null:
		fail_test("wizard.tres failed to load — cannot compute stamina")
		return
	var attrs = _make_attrs()
	var stamina: int = attrs.compute_stamina(_gram_marx.attributes, _wizard_class)
	assert_eq(stamina, 5, "compute_stamina(gram_marx.attributes, wizard) must be 5 (1 + 2 + 2)")


## Reflex = 10 + dexterity(2) + intuition(3) = 15
func test_gram_marx_compute_reflex_equals_15() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load — cannot compute reflex")
		return
	var attrs = _make_attrs()
	var reflex: int = attrs.compute_reflex(_gram_marx.attributes)
	assert_eq(reflex, 15, "compute_reflex(gram_marx.attributes) must be 15 (10 + 2 + 3)")


## Will = 10 + willpower(2) + social(2) = 14
func test_gram_marx_compute_will_equals_14() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load — cannot compute will")
		return
	var attrs = _make_attrs()
	var will: int = attrs.compute_will(_gram_marx.attributes)
	assert_eq(will, 14, "compute_will(gram_marx.attributes) must be 14 (10 + 2 + 2)")


## Fortitude = 10 + constitution(2) + strength(1) = 13
func test_gram_marx_compute_fortitude_equals_13() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load — cannot compute fortitude")
		return
	var attrs = _make_attrs()
	var fortitude: int = attrs.compute_fortitude(_gram_marx.attributes)
	assert_eq(fortitude, 13, "compute_fortitude(gram_marx.attributes) must be 13 (10 + 2 + 1)")


# ── Talent selections ─────────────────────────────────────────────────────────

func test_gram_marx_talent_selections_is_array() -> void:
	if _gram_marx == null:
		fail_test("gram_marx.tres failed to load")
		return
	assert_not_null(_gram_marx.talent_selections, "gram_marx.talent_selections must not be null")


# ════════════════════════════════════════════════════════════════════════════
# MARIGOLD — Elven Divine Warrior with Divine Champion talent
# ════════════════════════════════════════════════════════════════════════════

# ── ADR-003 text-format verification ─────────────────────────────────────────

func test_marigold_tres_is_text_format() -> void:
	var file := FileAccess.open("res://data/characters/marigold.tres", FileAccess.READ)
	assert_not_null(file, "data/characters/marigold.tres must be readable")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.contains("[gd_resource"),
		"marigold.tres first line must contain '[gd_resource' — text-format required (ADR-003)"
	)


# ── Resource loading ──────────────────────────────────────────────────────────

func test_marigold_loads_non_null() -> void:
	assert_not_null(
		_marigold,
		"ResourceLoader.load('data/characters/marigold.tres') must return non-null"
	)


func test_marigold_is_character_resource() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot check type")
		return
	assert_is(_marigold, CharacterResource, "marigold.tres must be an instance of CharacterResource")


# ── Core identity fields ──────────────────────────────────────────────────────

func test_marigold_name_is_Marigold() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot check name")
		return
	assert_eq(_marigold.name, "Marigold", "marigold.name must be 'Marigold'")


func test_marigold_race_is_elf() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot check race")
		return
	assert_eq(_marigold.race, "Elf", "marigold.race must be 'Elf' (FR-010)")


# ── Class reference — divine_warrior.tres ────────────────────────────────────

func test_marigold_class_ref_is_non_null() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot check class_ref")
		return
	assert_not_null(_marigold.class_ref, "marigold.class_ref must not be null")


func test_marigold_class_ref_is_class_resource() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot check class_ref type")
		return
	if _marigold.class_ref == null:
		fail_test("marigold.class_ref is null — cannot check type")
		return
	assert_is(_marigold.class_ref, ClassResource, "marigold.class_ref must be a ClassResource")


func test_marigold_class_ref_resolves_to_divine_warrior() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load")
		return
	if _marigold.class_ref == null:
		fail_test("marigold.class_ref is null")
		return
	assert_eq(
		_marigold.class_ref.class_id, "divine_warrior",
		"marigold.class_ref.class_id must be 'divine_warrior'"
	)


func test_marigold_class_ref_resource_path_ends_with_divine_warrior_tres() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load")
		return
	if _marigold.class_ref == null:
		fail_test("marigold.class_ref is null")
		return
	assert_true(
		_marigold.class_ref.resource_path.ends_with("divine_warrior.tres"),
		"marigold.class_ref.resource_path must end with 'divine_warrior.tres'; got '%s'" % _marigold.class_ref.resource_path
	)


# ── Point-buy validation ──────────────────────────────────────────────────────

func test_marigold_point_buy_returns_valid_true() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot validate point buy")
		return
	var attrs = _make_attrs()
	var result = attrs.point_buy_validate(_marigold.attributes)
	assert_true(result["valid"], "point_buy_validate(marigold.attributes) must return {valid: true}")


func test_marigold_point_buy_cost_is_25() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot check point buy cost")
		return
	var attrs = _make_attrs()
	var result = attrs.point_buy_validate(_marigold.attributes)
	assert_eq(result["cost"], 25, "marigold point-buy cost must be 25; got %d" % result["cost"])


# ── Attribute score spot-checks ───────────────────────────────────────────────

func test_marigold_strength_is_3() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load")
		return
	assert_eq(_marigold.attributes.get("strength", -1), 3, "marigold strength must be 3")


func test_marigold_constitution_is_3() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load")
		return
	assert_eq(_marigold.attributes.get("constitution", -1), 3, "marigold constitution must be 3")


func test_marigold_dexterity_is_3() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load")
		return
	assert_eq(_marigold.attributes.get("dexterity", -1), 3, "marigold dexterity must be 3")


func test_marigold_willpower_is_4() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load")
		return
	assert_eq(_marigold.attributes.get("willpower", -1), 4, "marigold willpower must be 4")


func test_marigold_intellect_is_1() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load")
		return
	assert_eq(_marigold.attributes.get("intellect", -1), 1, "marigold intellect must be 1")


func test_marigold_intuition_is_3() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load")
		return
	assert_eq(_marigold.attributes.get("intuition", -1), 3, "marigold intuition must be 3")


func test_marigold_social_is_2() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load")
		return
	assert_eq(_marigold.attributes.get("social", -1), 2, "marigold social must be 2")


# ── Derived-stat computations using attributes.gd ────────────────────────────

## HP = 8 + class_hp(6) + constitution(3) = 17
func test_marigold_compute_hp_equals_17() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot compute hp")
		return
	if _divine_warrior_class == null:
		fail_test("divine_warrior.tres failed to load — cannot compute hp")
		return
	var attrs = _make_attrs()
	var hp: int = attrs.compute_hp(_marigold.attributes, _divine_warrior_class)
	assert_eq(hp, 17, "compute_hp(marigold.attributes, divine_warrior) must be 17 (8 + 6 + 3)")


## Stamina = stamina_base(3) + willpower(4) + constitution(3) = 10
func test_marigold_compute_stamina_equals_10() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot compute stamina")
		return
	if _divine_warrior_class == null:
		fail_test("divine_warrior.tres failed to load — cannot compute stamina")
		return
	var attrs = _make_attrs()
	var stamina: int = attrs.compute_stamina(_marigold.attributes, _divine_warrior_class)
	assert_eq(stamina, 10, "compute_stamina(marigold.attributes, divine_warrior) must be 10 (3 + 4 + 3)")


## Reflex = 10 + dexterity(3) + intuition(3) = 16
func test_marigold_compute_reflex_equals_16() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot compute reflex")
		return
	var attrs = _make_attrs()
	var reflex: int = attrs.compute_reflex(_marigold.attributes)
	assert_eq(reflex, 16, "compute_reflex(marigold.attributes) must be 16 (10 + 3 + 3)")


## Fortitude = 10 + constitution(3) + strength(3) = 16
func test_marigold_compute_fortitude_equals_16() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot compute fortitude")
		return
	var attrs = _make_attrs()
	var fortitude: int = attrs.compute_fortitude(_marigold.attributes)
	assert_eq(fortitude, 16, "compute_fortitude(marigold.attributes) must be 16 (10 + 3 + 3)")


# ── Talent selections — Divine Champion stealth ───────────────────────────────

func test_marigold_talent_selections_is_non_empty() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot check talent_selections")
		return
	assert_true(
		_marigold.talent_selections.size() > 0,
		"marigold.talent_selections must have at least one entry; got %d" % _marigold.talent_selections.size()
	)


func test_marigold_talent_selections_contains_stealth_capable_talent() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot check talent_selections")
		return
	if _marigold.talent_selections.size() == 0:
		fail_test("marigold.talent_selections is empty — cannot check talent ID")
		return
	var first_talent: String = str(_marigold.talent_selections[0])
	assert_true(
		first_talent.length() > 0,
		"marigold.talent_selections[0] must be a non-empty string (stealth-capable Divine Champion talent ID)"
	)
	assert_true(
		first_talent.contains("stealth") or first_talent.contains("divine_champion"),
		"marigold.talent_selections[0] must reference a stealth-capable Divine Champion talent; got '%s'" % first_talent
	)


# ════════════════════════════════════════════════════════════════════════════
# DWARF CHANNELER — Dwarf Divine Channeler
# ════════════════════════════════════════════════════════════════════════════

# ── ADR-003 text-format verification ─────────────────────────────────────────

func test_dwarf_channeler_tres_is_text_format() -> void:
	var file := FileAccess.open("res://data/characters/dwarf_channeler.tres", FileAccess.READ)
	assert_not_null(file, "data/characters/dwarf_channeler.tres must be readable")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.contains("[gd_resource"),
		"dwarf_channeler.tres first line must contain '[gd_resource' — text-format required (ADR-003)"
	)


# ── Resource loading ──────────────────────────────────────────────────────────

func test_dwarf_channeler_loads_non_null() -> void:
	assert_not_null(
		_dwarf_channeler,
		"ResourceLoader.load('data/characters/dwarf_channeler.tres') must return non-null"
	)


func test_dwarf_channeler_is_character_resource() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load — cannot check type")
		return
	assert_is(_dwarf_channeler, CharacterResource, "dwarf_channeler.tres must be an instance of CharacterResource")


# ── Core identity fields ──────────────────────────────────────────────────────

func test_dwarf_channeler_race_is_Dwarf() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load — cannot check race")
		return
	assert_eq(_dwarf_channeler.race, "Dwarf", "dwarf_channeler.race must be 'Dwarf'")


func test_dwarf_channeler_name_is_non_empty() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load — cannot check name")
		return
	assert_true(
		_dwarf_channeler.name.length() > 0,
		"dwarf_channeler.name must be non-empty"
	)


# ── Class reference — divine_channeler.tres ───────────────────────────────────

func test_dwarf_channeler_class_ref_is_non_null() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load — cannot check class_ref")
		return
	assert_not_null(_dwarf_channeler.class_ref, "dwarf_channeler.class_ref must not be null")


func test_dwarf_channeler_class_ref_is_class_resource() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load — cannot check class_ref type")
		return
	if _dwarf_channeler.class_ref == null:
		fail_test("dwarf_channeler.class_ref is null — cannot check type")
		return
	assert_is(_dwarf_channeler.class_ref, ClassResource, "dwarf_channeler.class_ref must be a ClassResource")


func test_dwarf_channeler_class_ref_resolves_to_divine_channeler() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load")
		return
	if _dwarf_channeler.class_ref == null:
		fail_test("dwarf_channeler.class_ref is null")
		return
	assert_eq(
		_dwarf_channeler.class_ref.class_id, "divine_channeler",
		"dwarf_channeler.class_ref.class_id must be 'divine_channeler'"
	)


func test_dwarf_channeler_class_ref_resource_path_ends_with_divine_channeler_tres() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load")
		return
	if _dwarf_channeler.class_ref == null:
		fail_test("dwarf_channeler.class_ref is null")
		return
	assert_true(
		_dwarf_channeler.class_ref.resource_path.ends_with("divine_channeler.tres"),
		"dwarf_channeler.class_ref.resource_path must end with 'divine_channeler.tres'; got '%s'" % _dwarf_channeler.class_ref.resource_path
	)


# ── Point-buy validation ──────────────────────────────────────────────────────

func test_dwarf_channeler_point_buy_returns_valid_true() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load — cannot validate point buy")
		return
	var attrs = _make_attrs()
	var result = attrs.point_buy_validate(_dwarf_channeler.attributes)
	assert_true(result["valid"], "point_buy_validate(dwarf_channeler.attributes) must return {valid: true}")


func test_dwarf_channeler_point_buy_cost_is_23() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load — cannot check point buy cost")
		return
	var attrs = _make_attrs()
	var result = attrs.point_buy_validate(_dwarf_channeler.attributes)
	assert_eq(result["cost"], 23, "dwarf_channeler point-buy cost must be 23; got %d" % result["cost"])


# ── Attribute score spot-checks ───────────────────────────────────────────────

func test_dwarf_channeler_strength_is_2() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load")
		return
	assert_eq(_dwarf_channeler.attributes.get("strength", -1), 2, "dwarf_channeler strength must be 2")


func test_dwarf_channeler_constitution_is_4() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load")
		return
	assert_eq(_dwarf_channeler.attributes.get("constitution", -1), 4, "dwarf_channeler constitution must be 4")


func test_dwarf_channeler_dexterity_is_1() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load")
		return
	assert_eq(_dwarf_channeler.attributes.get("dexterity", -1), 1, "dwarf_channeler dexterity must be 1")


func test_dwarf_channeler_willpower_is_3() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load")
		return
	assert_eq(_dwarf_channeler.attributes.get("willpower", -1), 3, "dwarf_channeler willpower must be 3")


func test_dwarf_channeler_intellect_is_2() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load")
		return
	assert_eq(_dwarf_channeler.attributes.get("intellect", -1), 2, "dwarf_channeler intellect must be 2")


func test_dwarf_channeler_intuition_is_2() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load")
		return
	assert_eq(_dwarf_channeler.attributes.get("intuition", -1), 2, "dwarf_channeler intuition must be 2")


func test_dwarf_channeler_social_is_4() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load")
		return
	assert_eq(_dwarf_channeler.attributes.get("social", -1), 4, "dwarf_channeler social must be 4")


# ── Derived-stat computations using attributes.gd ────────────────────────────

## HP = 8 + class_hp(5) + constitution(4) = 17
func test_dwarf_channeler_compute_hp_equals_17() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load — cannot compute hp")
		return
	if _divine_channeler_class == null:
		fail_test("divine_channeler.tres failed to load — cannot compute hp")
		return
	var attrs = _make_attrs()
	var hp: int = attrs.compute_hp(_dwarf_channeler.attributes, _divine_channeler_class)
	assert_eq(hp, 17, "compute_hp(dwarf_channeler.attributes, divine_channeler) must be 17 (8 + 5 + 4)")


## Stamina = stamina_base(2) + willpower(3) + constitution(4) = 9
func test_dwarf_channeler_compute_stamina_equals_9() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load — cannot compute stamina")
		return
	if _divine_channeler_class == null:
		fail_test("divine_channeler.tres failed to load — cannot compute stamina")
		return
	var attrs = _make_attrs()
	var stamina: int = attrs.compute_stamina(_dwarf_channeler.attributes, _divine_channeler_class)
	assert_eq(stamina, 9, "compute_stamina(dwarf_channeler.attributes, divine_channeler) must be 9 (2 + 3 + 4)")


## Will = 10 + willpower(3) + social(4) = 17
func test_dwarf_channeler_compute_will_equals_17() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load — cannot compute will")
		return
	var attrs = _make_attrs()
	var will: int = attrs.compute_will(_dwarf_channeler.attributes)
	assert_eq(will, 17, "compute_will(dwarf_channeler.attributes) must be 17 (10 + 3 + 4)")


## Fortitude = 10 + constitution(4) + strength(2) = 16
func test_dwarf_channeler_compute_fortitude_equals_16() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load — cannot compute fortitude")
		return
	var attrs = _make_attrs()
	var fortitude: int = attrs.compute_fortitude(_dwarf_channeler.attributes)
	assert_eq(fortitude, 16, "compute_fortitude(dwarf_channeler.attributes) must be 16 (10 + 4 + 2)")


# ── Talent selections ─────────────────────────────────────────────────────────

func test_dwarf_channeler_talent_selections_is_array() -> void:
	if _dwarf_channeler == null:
		fail_test("dwarf_channeler.tres failed to load")
		return
	assert_not_null(_dwarf_channeler.talent_selections, "dwarf_channeler.talent_selections must not be null")


# ════════════════════════════════════════════════════════════════════════════
# FEAT-076 — primary_offensive_attribute field and Marigold race fix
# ════════════════════════════════════════════════════════════════════════════

## Test that CharacterResource.new() exposes the primary_offensive_attribute property.
## This is a schema-level check: the field must exist with a default value.
func test_character_resource_has_primary_offensive_attribute_field() -> void:
	var cr = CharacterResource.new()
	assert_true(
		"primary_offensive_attribute" in cr,
		"CharacterResource must have a primary_offensive_attribute property (FEAT-076)"
	)


## Marigold's race must be "Elf" per FR-010 (DEF-004: was incorrectly 'Elven').
func test_marigold_race_is_elf_feat076() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot check race")
		return
	assert_eq(
		_marigold.race, "Elf",
		"marigold.race must be 'Elf' per FR-010 (DEF-004 fix)"
	)


## Marigold's primary_offensive_attribute must be "dexterity" (Divine Champion build).
func test_marigold_primary_offensive_attribute_is_dexterity() -> void:
	if _marigold == null:
		fail_test("marigold.tres failed to load — cannot check primary_offensive_attribute")
		return
	assert_eq(
		_marigold.primary_offensive_attribute, "dexterity",
		"marigold.primary_offensive_attribute must be 'dexterity' (FEAT-076)"
	)


## Titus (existing .tres, no primary_offensive_attribute set) must default to "".
## This confirms backward compatibility: adding the field does not break existing files.
func test_titus_primary_offensive_attribute_defaults_empty() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check primary_offensive_attribute")
		return
	assert_eq(
		_titus.primary_offensive_attribute, "",
		"titus.primary_offensive_attribute must default to '' when not set in .tres (FEAT-076 backward compat)"
	)


## gram_marx.tres must still load non-null after the schema change.
func test_gram_marx_loads_without_error_feat076() -> void:
	assert_not_null(
		_gram_marx,
		"gram_marx.tres must load non-null after primary_offensive_attribute schema addition (FEAT-076)"
	)


## dwarf_channeler.tres must still load non-null after the schema change.
func test_dwarf_channeler_loads_without_error_feat076() -> void:
	assert_not_null(
		_dwarf_channeler,
		"dwarf_channeler.tres must load non-null after primary_offensive_attribute schema addition (FEAT-076)"
	)
