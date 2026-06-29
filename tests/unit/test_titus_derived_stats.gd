extends GutTest
## tests/unit/test_titus_derived_stats.gd
##
## GUT test suite for FEAT-087: Correct Titus Equipment Reference to Chain Shirt.
## Validates that Titus.tres references chain_shirt.tres and that derived stats
## are computed correctly with chain_shirt (medium armor, ac_base=5).
##
## Test criteria (FEAT-087):
##   1. data/armor/chain_shirt.tres loads non-null via ResourceLoader.load()
##   2. chain_shirt.category == 'medium'
##   3. chain_shirt.ac_base == 5  (v0 spec armor table: Chain Shirt +5)
##   4. titus.tres starting_equipment contains 'data/armor/chain_shirt.tres'
##   5. compute_ac(titus.attributes, chain_shirt.ac_base, 'medium') == 10 + chain_shirt.ac_base
##   6. category='medium' excludes DEX from AC (Titus dex=2 is NOT added)
##   7. HP, Stamina, Reflex, Fortitude, Will continue to pass unchanged
##
## Titus attribute spread (23 pts, all within 27-pt budget):
##   STR=5 (9), CON=4 (6), DEX=2 (2), WIL=2 (2), INT=1 (1), Intuition=2 (2), SOC=1 (1)
##
## Expected derived stats (Tier 1, Level 1 — v0 spec table):
##   HP = 18  (8 + Fighter class_hp=6 + CON=4)
##   Stamina = 10  (Fighter stamina_base=4 + WIL=2 + CON=4)
##   AC = 15  (10 + chain_shirt.ac_base=5; no DEX — medium armor)
##   Reflex = 14  (10 + DEX=2 + Intuition=2)
##   Fortitude = 19  (10 + CON=4 + STR=5)
##   Will = 13  (10 + WIL=2 + SOC=1)

const ArmorResource   = preload("res://core/model/armor_resource.gd")
const AttributesClass = preload("res://core/rules/attributes.gd")
const RNGClass        = preload("res://core/rules/rng.gd")

## V0 spec armor table value for Chain Shirt AC base.
const CHAIN_SHIRT_AC_BASE_SPEC: int = 5

## Resources loaded once and reused across tests.
var _chain_shirt = null
var _titus       = null
var _fighter     = null


func before_all() -> void:
	_chain_shirt = ResourceLoader.load("res://data/armor/chain_shirt.tres")
	_titus       = ResourceLoader.load("res://data/characters/titus.tres")
	_fighter     = ResourceLoader.load("res://data/classes/fighter.tres")


## Helper: fresh Attributes instance with a fixed seed so tests are deterministic.
func _make_attrs() -> AttributesClass:
	return AttributesClass.new(RNGClass.new(0))


# ── chain_shirt.tres — basic load and schema ──────────────────────────────────

## Criterion 1: data/armor/chain_shirt.tres loads as a non-null ArmorResource.
func test_chain_shirt_loads_non_null() -> void:
	assert_not_null(
		_chain_shirt,
		"ResourceLoader.load('res://data/armor/chain_shirt.tres') must return non-null (FEAT-087)"
	)


## Criterion 1 (continued): loaded resource is an ArmorResource instance.
func test_chain_shirt_is_armor_resource() -> void:
	assert_not_null(_chain_shirt, "chain_shirt.tres must load non-null (FEAT-087)")
	if _chain_shirt == null:
		return
	assert_is(
		_chain_shirt, ArmorResource,
		"chain_shirt.tres must be an ArmorResource instance (FEAT-087)"
	)


## Criterion 2: chain_shirt.category == 'medium' (DEX excluded from AC).
func test_chain_shirt_category_is_medium() -> void:
	assert_not_null(_chain_shirt, "chain_shirt.tres must load non-null (FEAT-087)")
	if _chain_shirt == null:
		return
	assert_eq(
		_chain_shirt.category, "medium",
		"chain_shirt.category must be 'medium' (v0 spec armor table; FEAT-087)"
	)


## Criterion 3: chain_shirt.ac_base == 5 (v0 spec armor table: Chain Shirt +5).
func test_chain_shirt_ac_base_equals_5() -> void:
	assert_not_null(_chain_shirt, "chain_shirt.tres must load non-null (FEAT-087)")
	if _chain_shirt == null:
		return
	assert_eq(
		_chain_shirt.ac_base, CHAIN_SHIRT_AC_BASE_SPEC,
		"chain_shirt.ac_base must be %d — matching v0 spec armor table (FEAT-087); got %d"
		% [CHAIN_SHIRT_AC_BASE_SPEC, _chain_shirt.ac_base]
	)


# ── chain_shirt.tres — text-format gate ──────────────────────────────────────

## ADR-003: chain_shirt.tres must be a text-format resource (first line contains '[gd_resource').
func test_chain_shirt_tres_is_text_format() -> void:
	var file := FileAccess.open("res://data/armor/chain_shirt.tres", FileAccess.READ)
	assert_not_null(file, "data/armor/chain_shirt.tres must be readable (FEAT-087)")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.begins_with("[gd_resource"),
		"data/armor/chain_shirt.tres first line must start with '[gd_resource' — text-format required (ADR-003 / FEAT-087); got: '%s'" % first_line
	)


# ── titus.tres — equipment reference ─────────────────────────────────────────

## Criterion 4: titus.tres starting_equipment contains 'data/armor/chain_shirt.tres'.
func test_titus_starting_equipment_contains_chain_shirt_path() -> void:
	assert_not_null(_titus, "titus.tres must load non-null (FEAT-087)")
	if _titus == null:
		return
	var found: bool = false
	for item in _titus.starting_equipment:
		if str(item).contains("chain_shirt.tres"):
			found = true
			break
	assert_true(
		found,
		"titus.starting_equipment must contain a path with 'chain_shirt.tres' (FEAT-087)"
	)


## Criterion 4 (no scale_mail): titus.tres starting_equipment must NOT reference scale_mail.
func test_titus_starting_equipment_does_not_contain_scale_mail() -> void:
	assert_not_null(_titus, "titus.tres must load non-null (FEAT-087)")
	if _titus == null:
		return
	var found_scale_mail: bool = false
	for item in _titus.starting_equipment:
		if str(item).contains("scale_mail.tres"):
			found_scale_mail = true
			break
	assert_false(
		found_scale_mail,
		"titus.starting_equipment must NOT reference scale_mail.tres — chain_shirt replaces it (FEAT-087)"
	)


# ── Titus AC with chain_shirt ─────────────────────────────────────────────────

## Criterion 5: compute_ac(titus.attributes, chain_shirt.ac_base, 'medium') == 10 + chain_shirt.ac_base
## Titus DEX=2, chain_shirt.ac_base=5, medium → AC = 10 + 5 = 15 (no DEX added).
func test_titus_compute_ac_with_chain_shirt_equals_15() -> void:
	assert_not_null(_titus, "titus.tres must load non-null (FEAT-087)")
	assert_not_null(_chain_shirt, "chain_shirt.tres must load non-null (FEAT-087)")
	if _titus == null or _chain_shirt == null:
		return
	var attrs = _make_attrs()
	var ac: int = attrs.compute_ac(_titus.attributes, _chain_shirt.ac_base, _chain_shirt.category)
	var expected: int = 10 + _chain_shirt.ac_base  # 10 + 5 = 15; no DEX for medium armor
	assert_eq(
		ac, expected,
		"compute_ac(titus.attributes, chain_shirt.ac_base=%d, 'medium') must be %d (no DEX; FEAT-087); got %d"
		% [_chain_shirt.ac_base, expected, ac]
	)


## Criterion 6: medium armor excludes DEX from AC.
## Titus dexterity=2; medium armor; compute_ac returns 10 + armor_base, NOT 10 + armor_base + dex.
func test_compute_ac_medium_excludes_dex_for_titus() -> void:
	assert_not_null(_titus, "titus.tres must load non-null (FEAT-087)")
	assert_not_null(_chain_shirt, "chain_shirt.tres must load non-null (FEAT-087)")
	if _titus == null or _chain_shirt == null:
		return
	var attrs = _make_attrs()
	var dex: int = _titus.attributes.get("dexterity", 0)
	var ac: int = attrs.compute_ac(_titus.attributes, _chain_shirt.ac_base, "medium")
	# DEX is excluded: result should NOT include the dexterity score
	var ac_without_dex: int = 10 + _chain_shirt.ac_base
	var ac_with_dex: int    = 10 + _chain_shirt.ac_base + dex
	assert_eq(
		ac, ac_without_dex,
		"Medium armor: compute_ac must return %d (10 + %d, no DEX=%d); got %d (FEAT-087)"
		% [ac_without_dex, _chain_shirt.ac_base, dex, ac]
	)
	assert_ne(
		ac, ac_with_dex,
		"Medium armor: compute_ac must NOT include DEX=%d in result (FEAT-087)" % dex
	)


# ── Titus derived stats — unchanged after armor swap (Criterion 7) ────────────

## Criterion 7: HP = 18 (8 + Fighter class_hp=6 + CON=4). Unchanged by armor swap.
func test_titus_compute_hp_equals_18_after_armor_swap() -> void:
	assert_not_null(_titus, "titus.tres must load non-null (FEAT-087)")
	assert_not_null(_fighter, "fighter.tres must load non-null (FEAT-087)")
	if _titus == null or _fighter == null:
		return
	var attrs = _make_attrs()
	var hp: int = attrs.compute_hp(_titus.attributes, _fighter)
	assert_eq(
		hp, 18,
		"compute_hp(titus.attributes, fighter) must be 18 (8 + 6 + 4); unchanged after armor swap (FEAT-087)"
	)


## Criterion 7: Stamina = 10 (Fighter stamina_base=4 + WIL=2 + CON=4). Unchanged by armor swap.
func test_titus_compute_stamina_equals_10_after_armor_swap() -> void:
	assert_not_null(_titus, "titus.tres must load non-null (FEAT-087)")
	assert_not_null(_fighter, "fighter.tres must load non-null (FEAT-087)")
	if _titus == null or _fighter == null:
		return
	var attrs = _make_attrs()
	var stamina: int = attrs.compute_stamina(_titus.attributes, _fighter)
	assert_eq(
		stamina, 10,
		"compute_stamina(titus.attributes, fighter) must be 10 (4 + 2 + 4); unchanged after armor swap (FEAT-087)"
	)


## Criterion 7: Reflex = 14 (10 + DEX=2 + Intuition=2). Unchanged by armor swap.
func test_titus_compute_reflex_equals_14_after_armor_swap() -> void:
	assert_not_null(_titus, "titus.tres must load non-null (FEAT-087)")
	if _titus == null:
		return
	var attrs = _make_attrs()
	var reflex: int = attrs.compute_reflex(_titus.attributes)
	assert_eq(
		reflex, 14,
		"compute_reflex(titus.attributes) must be 14 (10 + 2 + 2); unchanged after armor swap (FEAT-087)"
	)


## Criterion 7: Fortitude = 19 (10 + CON=4 + STR=5). Unchanged by armor swap.
func test_titus_compute_fortitude_equals_19_after_armor_swap() -> void:
	assert_not_null(_titus, "titus.tres must load non-null (FEAT-087)")
	if _titus == null:
		return
	var attrs = _make_attrs()
	var fortitude: int = attrs.compute_fortitude(_titus.attributes)
	assert_eq(
		fortitude, 19,
		"compute_fortitude(titus.attributes) must be 19 (10 + 4 + 5); unchanged after armor swap (FEAT-087)"
	)


## Criterion 7: Will = 13 (10 + WIL=2 + SOC=1). Unchanged by armor swap.
func test_titus_compute_will_equals_13_after_armor_swap() -> void:
	assert_not_null(_titus, "titus.tres must load non-null (FEAT-087)")
	if _titus == null:
		return
	var attrs = _make_attrs()
	var will: int = attrs.compute_will(_titus.attributes)
	assert_eq(
		will, 13,
		"compute_will(titus.attributes) must be 13 (10 + 2 + 1); unchanged after armor swap (FEAT-087)"
	)
