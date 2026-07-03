extends GutTest
## tests/unit/test_ranged_weapon_fixtures.gd
##
## GUT unit test suite for FEAT-152 (resolves FIND-144, critical):
## data/weapons/longbow.tres and data/weapons/shortbow.tres were referenced
## and asserted non-null by
## tests/unit/core/application/test_resolve_action_ranged_reach.gd but were
## never committed to the repository, breaking CI (scripts/test_command.sh
## stages 3 and 4) on a fresh/clean checkout — the fixtures existed only in
## a prior author's local working tree.
##
## This suite pins down BOTH ranged-weapon fixtures directly (independent
## of the reach-gating use-case test, which only happens to exercise
## shortbow.tres) so a future accidental deletion/un-commit of either file
## is caught immediately and explicitly, rather than surfacing only as an
## incidental failure deep inside an unrelated use-case suite.
##
## Test criteria (design notes / US-007):
##   - data/weapons/longbow.tres and data/weapons/shortbow.tres both load
##     via ResourceLoader.load() and are WeaponResource instances.
##   - range_hexes ordering matches the intended ranged-vs-melee reach
##     model consumed by core/application/resolve_action_use_case.gd's
##     _is_in_range(): longbow.range_hexes > shortbow.range_hexes >
##     WeaponResource's melee default of 1.

const WeaponResourceClass = preload("res://core/model/weapon_resource.gd")


func test_longbow_resource_loads_and_is_a_weapon_resource() -> void:
	var longbow = ResourceLoader.load("res://data/weapons/longbow.tres")
	assert_not_null(longbow, "ResourceLoader.load('res://data/weapons/longbow.tres') must return non-null")
	if longbow == null:
		return
	assert_is(longbow, WeaponResourceClass, "longbow.tres must be a WeaponResource")
	assert_eq(longbow.weapon_id, "longbow", "longbow weapon_id must be 'longbow'")


func test_shortbow_resource_loads_and_is_a_weapon_resource() -> void:
	var shortbow = ResourceLoader.load("res://data/weapons/shortbow.tres")
	assert_not_null(shortbow, "ResourceLoader.load('res://data/weapons/shortbow.tres') must return non-null")
	if shortbow == null:
		return
	assert_is(shortbow, WeaponResourceClass, "shortbow.tres must be a WeaponResource")
	assert_eq(shortbow.weapon_id, "shortbow", "shortbow weapon_id must be 'shortbow'")


func test_longbow_range_exceeds_shortbow_range_exceeds_melee_default() -> void:
	var longbow = ResourceLoader.load("res://data/weapons/longbow.tres")
	var shortbow = ResourceLoader.load("res://data/weapons/shortbow.tres")
	assert_not_null(longbow, "longbow.tres must load")
	assert_not_null(shortbow, "shortbow.tres must load")
	if longbow == null or shortbow == null:
		return

	var melee_default_range_hexes: int = WeaponResourceClass.new().range_hexes

	assert_true(
		longbow.range_hexes > shortbow.range_hexes,
		"longbow.range_hexes (%d) must exceed shortbow.range_hexes (%d)" % [longbow.range_hexes, shortbow.range_hexes]
	)
	assert_true(
		shortbow.range_hexes > melee_default_range_hexes,
		"shortbow.range_hexes (%d) must exceed the melee default range_hexes (%d)" % [shortbow.range_hexes, melee_default_range_hexes]
	)
