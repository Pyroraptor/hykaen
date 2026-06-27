extends GutTest
## tests/unit/test_character_resources.gd
##
## GUT test suite for FEAT-045: All Party Member Character Resources.
## Validates that all four pre-generated party member character .tres files
## can be loaded, are non-null, and have non-empty name fields.
##
## FEAT-045 adds test_all_four_party_members_load() to iterate all four
## character resource paths and assert basic loadability.
##
## FEAT-061 additions: validates starting_equipment arrays for Gram Marx,
## Marigold, and Dwarf Channeler; validates new weapon/armor .tres stats;
## asserts that all non-Titus characters have equipped weapons with
## block_value/parry_bonus (required by FEAT-059 active defenses).
##
## Characters:
##   - Titus         (Human Fighter)
##   - Gram Marx     (Tiefling Wizard)          — quarterstaff + robes
##   - Marigold      (Elven Divine Warrior)     — shortsword + leather_armor
##   - Dwarf Channeler (Dwarf Divine Channeler) — mace + chain_shirt

const CharacterResource = preload("res://core/model/character_resource.gd")
const WeaponResource    = preload("res://core/model/weapon_resource.gd")
const ArmorResource     = preload("res://core/model/armor_resource.gd")


# ── All four party members — batch load test ──────────────────────────────────

## Criterion: all four character paths load as non-null CharacterResource instances
## with non-empty name fields.
func test_all_four_party_members_load() -> void:
	var paths: Array = [
		"res://data/characters/titus.tres",
		"res://data/characters/gram_marx.tres",
		"res://data/characters/marigold.tres",
		"res://data/characters/dwarf_channeler.tres",
	]
	for path in paths:
		var res = ResourceLoader.load(path)
		assert_not_null(
			res,
			"ResourceLoader.load('%s') must return non-null" % path
		)
		if res == null:
			continue
		assert_is(
			res, CharacterResource,
			"'%s' must be a CharacterResource instance" % path
		)
		assert_true(
			res.name.length() > 0,
			"'%s' must have a non-empty name field; got '%s'" % [path, res.name]
		)


# ── Text-format gate for all four character .tres files ───────────────────────

## Criterion: all four character .tres files must be in text format (first line
## contains '[gd_resource') as required by ADR-003.
func test_all_four_character_tres_are_text_format() -> void:
	var paths: Array = [
		"res://data/characters/titus.tres",
		"res://data/characters/gram_marx.tres",
		"res://data/characters/marigold.tres",
		"res://data/characters/dwarf_channeler.tres",
	]
	for path in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "%s must be readable" % path)
		if file == null:
			continue
		var first_line := file.get_line()
		file.close()
		assert_true(
			first_line.contains("[gd_resource"),
			"%s first line must contain '[gd_resource' — text-format required (ADR-003)" % path
		)


# ── Individual load checks ────────────────────────────────────────────────────

func test_titus_loads() -> void:
	var res = ResourceLoader.load("res://data/characters/titus.tres")
	assert_not_null(res, "titus.tres must load non-null")
	if res == null:
		return
	assert_eq(res.name, "Titus", "titus.name must be 'Titus'")


func test_gram_marx_loads() -> void:
	var res = ResourceLoader.load("res://data/characters/gram_marx.tres")
	assert_not_null(res, "gram_marx.tres must load non-null")
	if res == null:
		return
	assert_eq(res.name, "Gram Marx", "gram_marx.name must be 'Gram Marx'")


func test_marigold_loads() -> void:
	var res = ResourceLoader.load("res://data/characters/marigold.tres")
	assert_not_null(res, "marigold.tres must load non-null")
	if res == null:
		return
	assert_eq(res.name, "Marigold", "marigold.name must be 'Marigold'")


func test_dwarf_channeler_loads() -> void:
	var res = ResourceLoader.load("res://data/characters/dwarf_channeler.tres")
	assert_not_null(res, "dwarf_channeler.tres must load non-null")
	if res == null:
		return
	assert_eq(res.race, "Dwarf", "dwarf_channeler.race must be 'Dwarf'")


# ── FEAT-061: Starting equipment — non-empty arrays ───────────────────────────

## Criterion: gram_marx.tres has a non-empty starting_equipment array.
func test_gram_marx_starting_equipment_is_non_empty() -> void:
	var res = ResourceLoader.load("res://data/characters/gram_marx.tres")
	assert_not_null(res, "gram_marx.tres must load non-null")
	if res == null:
		return
	assert_true(
		res.starting_equipment.size() > 0,
		"gram_marx.starting_equipment must be non-empty (FEAT-061)"
	)


## Criterion: marigold.tres has a non-empty starting_equipment array.
func test_marigold_starting_equipment_is_non_empty() -> void:
	var res = ResourceLoader.load("res://data/characters/marigold.tres")
	assert_not_null(res, "marigold.tres must load non-null")
	if res == null:
		return
	assert_true(
		res.starting_equipment.size() > 0,
		"marigold.starting_equipment must be non-empty (FEAT-061)"
	)


## Criterion: dwarf_channeler.tres has a non-empty starting_equipment array.
func test_dwarf_channeler_starting_equipment_is_non_empty() -> void:
	var res = ResourceLoader.load("res://data/characters/dwarf_channeler.tres")
	assert_not_null(res, "dwarf_channeler.tres must load non-null")
	if res == null:
		return
	assert_true(
		res.starting_equipment.size() > 0,
		"dwarf_channeler.starting_equipment must be non-empty (FEAT-061)"
	)


## Criterion: all starting_equipment paths in gram_marx, marigold, dwarf_channeler load non-null.
func test_non_titus_starting_equipment_paths_all_load_non_null() -> void:
	var char_paths: Array = [
		"res://data/characters/gram_marx.tres",
		"res://data/characters/marigold.tres",
		"res://data/characters/dwarf_channeler.tres",
	]
	for char_path in char_paths:
		var char_res = ResourceLoader.load(char_path)
		assert_not_null(char_res, "%s must load non-null" % char_path)
		if char_res == null:
			continue
		for equip_path in char_res.starting_equipment:
			var equip_res = ResourceLoader.load(str(equip_path))
			assert_not_null(
				equip_res,
				"Equipment path '%s' from '%s' must load non-null (FEAT-061)" % [equip_path, char_path]
			)


# ── FEAT-061: New weapon .tres — stat validation ──────────────────────────────

## Criterion: quarterstaff.tres loads non-null as a WeaponResource.
func test_quarterstaff_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/weapons/quarterstaff.tres")
	assert_not_null(res, "quarterstaff.tres must load non-null (FEAT-061)")
	if res == null:
		return
	assert_is(res, WeaponResource, "quarterstaff.tres must be a WeaponResource")


## Criterion: quarterstaff has damage_die, damage_type, proficiency_bonus, block_value, parry_bonus.
func test_quarterstaff_stats() -> void:
	var res = ResourceLoader.load("res://data/weapons/quarterstaff.tres")
	if res == null:
		fail_test("quarterstaff.tres failed to load")
		return
	assert_eq(res.damage_die, 6, "quarterstaff damage_die must be 6 (FEAT-061)")
	assert_eq(res.damage_type, "B", "quarterstaff damage_type must be 'B' bludgeoning (FEAT-061)")
	assert_eq(res.proficiency_bonus, 1, "quarterstaff proficiency_bonus must be 1 (simple weapon, FEAT-061)")
	assert_true(res.block_value >= 0, "quarterstaff block_value must be present (FEAT-061)")
	assert_true(res.parry_bonus >= 0, "quarterstaff parry_bonus must be present (FEAT-061)")


## Criterion: shortsword.tres loads non-null; damage 1d6P, prof +3, block 1, parry 4.
func test_shortsword_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/weapons/shortsword.tres")
	assert_not_null(res, "shortsword.tres must load non-null (FEAT-061)")
	if res == null:
		return
	assert_is(res, WeaponResource, "shortsword.tres must be a WeaponResource")


## Criterion: shortsword canonical stats from Weapons.pdf: 1d6 P, +3 prof, block 1, parry 4.
func test_shortsword_stats_match_weapons_pdf() -> void:
	var res = ResourceLoader.load("res://data/weapons/shortsword.tres")
	if res == null:
		fail_test("shortsword.tres failed to load")
		return
	assert_eq(res.damage_die, 6, "shortsword damage_die must be 6 (Weapons.pdf: 1d6 P, FEAT-061)")
	assert_eq(res.damage_type, "P", "shortsword damage_type must be 'P' piercing (Weapons.pdf, FEAT-061)")
	assert_eq(res.proficiency_bonus, 3, "shortsword proficiency_bonus must be +3 (Weapons.pdf, FEAT-061)")
	assert_eq(res.block_value, 1, "shortsword block_value must be 1 (Weapons.pdf, FEAT-061)")
	assert_eq(res.parry_bonus, 4, "shortsword parry_bonus must be 4 (Weapons.pdf, FEAT-061)")


## Criterion: mace.tres loads non-null; damage 1d8B, prof +1, block 2, parry 1.
func test_mace_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/weapons/mace.tres")
	assert_not_null(res, "mace.tres must load non-null (FEAT-061)")
	if res == null:
		return
	assert_is(res, WeaponResource, "mace.tres must be a WeaponResource")


## Criterion: mace canonical stats from Weapons.pdf: 1d8 B, +1 prof, block 2, parry 1.
func test_mace_stats_match_weapons_pdf() -> void:
	var res = ResourceLoader.load("res://data/weapons/mace.tres")
	if res == null:
		fail_test("mace.tres failed to load")
		return
	assert_eq(res.damage_die, 8, "mace damage_die must be 8 (Weapons.pdf: 1d8 B, FEAT-061)")
	assert_eq(res.damage_type, "B", "mace damage_type must be 'B' bludgeoning (Weapons.pdf, FEAT-061)")
	assert_eq(res.proficiency_bonus, 1, "mace proficiency_bonus must be +1 (Weapons.pdf, FEAT-061)")
	assert_eq(res.block_value, 2, "mace block_value must be 2 (Weapons.pdf, FEAT-061)")
	assert_eq(res.parry_bonus, 1, "mace parry_bonus must be 1 (Weapons.pdf, FEAT-061)")


# ── FEAT-061: New armor .tres — stat validation ───────────────────────────────

## Criterion: robes.tres loads non-null as an ArmorResource with ac_base and category.
func test_robes_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/armor/robes.tres")
	assert_not_null(res, "robes.tres must load non-null (FEAT-061)")
	if res == null:
		return
	assert_is(res, ArmorResource, "robes.tres must be an ArmorResource")


func test_robes_stats() -> void:
	var res = ResourceLoader.load("res://data/armor/robes.tres")
	if res == null:
		fail_test("robes.tres failed to load")
		return
	assert_true(res.ac_base >= 0, "robes ac_base must be present and >= 0 (FEAT-061)")
	assert_eq(res.category, "none", "robes category must be 'none' (no armor, FEAT-061)")


## Criterion: leather_armor.tres loads non-null as an ArmorResource with ac_base and category.
func test_leather_armor_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/armor/leather_armor.tres")
	assert_not_null(res, "leather_armor.tres must load non-null (FEAT-061)")
	if res == null:
		return
	assert_is(res, ArmorResource, "leather_armor.tres must be an ArmorResource")


func test_leather_armor_stats() -> void:
	var res = ResourceLoader.load("res://data/armor/leather_armor.tres")
	if res == null:
		fail_test("leather_armor.tres failed to load")
		return
	assert_true(res.ac_base > 0, "leather_armor ac_base must be > 0 (FEAT-061)")
	assert_eq(res.category, "light", "leather_armor category must be 'light' (FEAT-061)")


## Criterion: chain_shirt.tres loads non-null as an ArmorResource with ac_base and category.
func test_chain_shirt_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/armor/chain_shirt.tres")
	assert_not_null(res, "chain_shirt.tres must load non-null (FEAT-061)")
	if res == null:
		return
	assert_is(res, ArmorResource, "chain_shirt.tres must be an ArmorResource")


func test_chain_shirt_stats() -> void:
	var res = ResourceLoader.load("res://data/armor/chain_shirt.tres")
	if res == null:
		fail_test("chain_shirt.tres failed to load")
		return
	assert_true(res.ac_base > 0, "chain_shirt ac_base must be > 0 (FEAT-061)")
	assert_eq(res.category, "medium", "chain_shirt category must be 'medium' (FEAT-061)")


# ── FEAT-061: Non-Titus characters each have a weapon with block_value/parry_bonus ──

## Criterion: each non-Titus character's first starting_equipment weapon has
## block_value and parry_bonus fields present (required by FEAT-059 active defenses).
func test_non_titus_equipped_weapon_has_block_and_parry_fields() -> void:
	var char_paths: Array = [
		"res://data/characters/gram_marx.tres",
		"res://data/characters/marigold.tres",
		"res://data/characters/dwarf_channeler.tres",
	]
	for char_path in char_paths:
		var char_res = ResourceLoader.load(char_path)
		if char_res == null:
			fail_test("'%s' failed to load — cannot check weapon fields" % char_path)
			continue
		assert_true(
			char_res.starting_equipment.size() > 0,
			"'%s' must have non-empty starting_equipment for this check (FEAT-061)" % char_path
		)
		if char_res.starting_equipment.size() == 0:
			continue
		# First item is the weapon
		var weapon_path: String = str(char_res.starting_equipment[0])
		var weapon_res = ResourceLoader.load(weapon_path)
		assert_not_null(
			weapon_res,
			"Weapon '%s' from '%s' must load non-null (FEAT-061)" % [weapon_path, char_path]
		)
		if weapon_res == null:
			continue
		assert_is(weapon_res, WeaponResource,
			"'%s' first starting_equipment item must be a WeaponResource (FEAT-061)" % char_path)
		# Verify block_value and parry_bonus are accessible (FEAT-059 active defenses)
		var bv = weapon_res.get("block_value")
		var pb = weapon_res.get("parry_bonus")
		assert_not_null(bv,
			"'%s' equipped weapon must have block_value field (FEAT-059 / FEAT-061)" % weapon_path)
		assert_not_null(pb,
			"'%s' equipped weapon must have parry_bonus field (FEAT-059 / FEAT-061)" % weapon_path)
