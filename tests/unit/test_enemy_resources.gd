extends GutTest
## tests/unit/test_enemy_resources.gd
##
## GUT unit tests for data/enemies/enemy_resource.gd and data/enemies/skeleton.tres
## (FEAT-088 / US-009 / NFR-005).
##
## Test criteria covered:
##   1. ResourceLoader.load('res://data/enemies/skeleton.tres') returns non-null
##   2. skeleton.name == 'Skeleton'
##   3. skeleton.hp == 8
##   4. skeleton.str == 2
##   5. skeleton.dex == 1
##   6. skeleton.weapon.die == 6
##   7. skeleton.weapon.proficiency_bonus == 1
##   8. skeleton.weapon.attribute == 'str'
##   9. enemy_resource.gd contains no 'extends Node' or 'extends Control' (domain purity)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: ResourceLoader.load() returns non-null for skeleton.tres
# ══════════════════════════════════════════════════════════════════════════════

func test_skeleton_tres_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/enemies/skeleton.tres")
	assert_not_null(
		res,
		"ResourceLoader.load('res://data/enemies/skeleton.tres') must return non-null"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: skeleton.name == 'Skeleton'
# ══════════════════════════════════════════════════════════════════════════════

func test_skeleton_name_is_skeleton() -> void:
	var res = ResourceLoader.load("res://data/enemies/skeleton.tres")
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return
	assert_eq(
		res.name, "Skeleton",
		"skeleton.name must be 'Skeleton'; got: '%s'" % str(res.name)
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: skeleton.hp == 8
# ══════════════════════════════════════════════════════════════════════════════

func test_skeleton_hp_is_8() -> void:
	var res = ResourceLoader.load("res://data/enemies/skeleton.tres")
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return
	assert_eq(
		res.hp, 8,
		"skeleton.hp must be 8; got: %d" % res.hp
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: skeleton.str == 2
# ══════════════════════════════════════════════════════════════════════════════

func test_skeleton_str_is_2() -> void:
	var res = ResourceLoader.load("res://data/enemies/skeleton.tres")
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return
	assert_eq(
		res.str, 2,
		"skeleton.str must be 2; got: %d" % res.str
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5: skeleton.dex == 1
# ══════════════════════════════════════════════════════════════════════════════

func test_skeleton_dex_is_1() -> void:
	var res = ResourceLoader.load("res://data/enemies/skeleton.tres")
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return
	assert_eq(
		res.dex, 1,
		"skeleton.dex must be 1; got: %d" % res.dex
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 6–8: skeleton.weapon sub-resource fields
# ══════════════════════════════════════════════════════════════════════════════

func test_skeleton_weapon_die_is_6() -> void:
	var res = ResourceLoader.load("res://data/enemies/skeleton.tres")
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return
	assert_true(
		res.weapon is Dictionary,
		"skeleton.weapon must be a Dictionary; got type: %s" % typeof(res.weapon)
	)
	assert_eq(
		res.weapon.get("die", -1), 6,
		"skeleton.weapon.die must be 6; got: %d" % res.weapon.get("die", -1)
	)


func test_skeleton_weapon_proficiency_bonus_is_1() -> void:
	var res = ResourceLoader.load("res://data/enemies/skeleton.tres")
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return
	assert_eq(
		res.weapon.get("proficiency_bonus", -1), 1,
		"skeleton.weapon.proficiency_bonus must be 1; got: %d" % res.weapon.get("proficiency_bonus", -1)
	)


func test_skeleton_weapon_attribute_is_str() -> void:
	var res = ResourceLoader.load("res://data/enemies/skeleton.tres")
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return
	assert_eq(
		res.weapon.get("attribute", ""), "str",
		"skeleton.weapon.attribute must be 'str'; got: '%s'" % res.weapon.get("attribute", "")
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 9: Domain purity — enemy_resource.gd must not extend Node or Control
# ══════════════════════════════════════════════════════════════════════════════

func test_enemy_resource_gd_does_not_extend_node() -> void:
	var file := FileAccess.open("res://data/enemies/enemy_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/enemies/enemy_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"enemy_resource.gd must not contain 'extends Node' — domain purity (NFR-005)"
	)


func test_enemy_resource_gd_does_not_extend_control() -> void:
	var file := FileAccess.open("res://data/enemies/enemy_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/enemies/enemy_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Control"),
		"enemy_resource.gd must not contain 'extends Control' — domain purity (NFR-005)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Additional: skeleton.tres first line confirms text format
# ══════════════════════════════════════════════════════════════════════════════

func test_skeleton_tres_is_text_format() -> void:
	var file := FileAccess.open("res://data/enemies/skeleton.tres", FileAccess.READ)
	assert_not_null(file, "data/enemies/skeleton.tres must be readable")
	if file == null:
		return
	var first_line: String = file.get_line()
	file.close()
	assert_true(
		first_line.begins_with("[gd_resource"),
		"skeleton.tres first line must start with '[gd_resource' (text format); got: '%s'" % first_line
	)
