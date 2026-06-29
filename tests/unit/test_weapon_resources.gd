extends GutTest
## tests/unit/test_weapon_resources.gd
##
## GUT unit test suite for FEAT-086: Reconcile Longsword Weapon Stats.
##
## Resolves DEF-003 (proficiency_bonus=1 vs spec's authoritative value of 2)
## and DEF-005 (split-brain between .tres resource and integration test fixture).
##
## Test criteria:
##   - longsword.tres proficiency_bonus == 2 (spec-authoritative)
##   - longsword.tres damage_die == 12 (Heavy Blade per Weapons.pdf)


# ── DEF-003: proficiency_bonus correction ─────────────────────────────────────

## Criterion: GUT unit test loads data/weapons/longsword.tres via
## ResourceLoader.load() and asserts proficiency_bonus == 2.
func test_longsword_proficiency_bonus_is_2() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	assert_not_null(
		res,
		"ResourceLoader.load('res://data/weapons/longsword.tres') must return non-null"
	)
	if res == null:
		return
	assert_eq(
		res.proficiency_bonus, 2,
		"longsword proficiency_bonus must be 2 — spec-authoritative value (DEF-003 / FEAT-086)"
	)


## Criterion: GUT unit test loads data/weapons/longsword.tres and asserts
## damage_die == 12 (Heavy Blade per Weapons.pdf).
func test_longsword_damage_die_is_12() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	assert_not_null(
		res,
		"ResourceLoader.load('res://data/weapons/longsword.tres') must return non-null"
	)
	if res == null:
		return
	assert_eq(
		res.damage_die, 12,
		"longsword damage_die must be 12 (d12, Heavy Blade per Weapons.pdf — FEAT-086)"
	)


# ── Confirming no regression on other longsword fields ───────────────────────

func test_longsword_weapon_id_is_longsword() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	if res == null:
		fail_test("longsword.tres failed to load")
		return
	assert_eq(res.weapon_id, "longsword", "longsword weapon_id must be 'longsword'")


func test_longsword_damage_modifier_attribute_is_strength() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	if res == null:
		fail_test("longsword.tres failed to load")
		return
	assert_eq(
		res.damage_modifier_attribute, "strength",
		"longsword damage_modifier_attribute must be 'strength' (canonical full key)"
	)
