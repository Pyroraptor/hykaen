extends GutTest
## tests/unit/test_equipment_resources.gd
##
## GUT test suite for FEAT-004: WeaponResource, ArmorResource, CharacterResource
## schemas and starter equipment .tres data files.
## Validates all test criteria for US-006 (schema and equipment data portions).

const WeaponResource = preload("res://core/model/weapon_resource.gd")
const ArmorResource  = preload("res://core/model/armor_resource.gd")
const CharacterResource = preload("res://core/model/character_resource.gd")


# ── ADR-003 text-format verification ─────────────────────────────────────────

func test_longsword_tres_is_text_format() -> void:
	var file := FileAccess.open("res://data/weapons/longsword.tres", FileAccess.READ)
	assert_not_null(file, "data/weapons/longsword.tres must be readable")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.contains("[gd_resource"),
		"longsword.tres first line must contain '[gd_resource' — text-format required (ADR-003)"
	)


func test_scale_mail_tres_is_text_format() -> void:
	var file := FileAccess.open("res://data/armor/scale_mail.tres", FileAccess.READ)
	assert_not_null(file, "data/armor/scale_mail.tres must be readable")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.contains("[gd_resource"),
		"scale_mail.tres first line must contain '[gd_resource' — text-format required (ADR-003)"
	)


# ── WeaponResource schema ─────────────────────────────────────────────────────

func test_longsword_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	assert_not_null(res, "ResourceLoader.load('data/weapons/longsword.tres') must return non-null")


func test_longsword_is_weapon_resource() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	if res == null:
		fail("longsword.tres failed to load — cannot check type")
		return
	assert_is(res, WeaponResource, "longsword.tres must be an instance of WeaponResource")


func test_longsword_damage_die() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	if res == null:
		fail("longsword.tres failed to load")
		return
	assert_eq(res.damage_die, 6, "longsword damage_die must be 6")


func test_longsword_damage_count() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	if res == null:
		fail("longsword.tres failed to load")
		return
	assert_eq(res.damage_count, 1, "longsword damage_count must be 1")


func test_longsword_damage_modifier_attribute() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	if res == null:
		fail("longsword.tres failed to load")
		return
	assert_eq(res.damage_modifier_attribute, "str", "longsword damage_modifier_attribute must be 'str'")


func test_longsword_proficiency_bonus() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	if res == null:
		fail("longsword.tres failed to load")
		return
	assert_eq(res.proficiency_bonus, 1, "longsword proficiency_bonus must be 1")


# ── ArmorResource schema ──────────────────────────────────────────────────────

func test_scale_mail_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/armor/scale_mail.tres")
	assert_not_null(res, "ResourceLoader.load('data/armor/scale_mail.tres') must return non-null")


func test_scale_mail_is_armor_resource() -> void:
	var res = ResourceLoader.load("res://data/armor/scale_mail.tres")
	if res == null:
		fail("scale_mail.tres failed to load — cannot check type")
		return
	assert_is(res, ArmorResource, "scale_mail.tres must be an instance of ArmorResource")


func test_scale_mail_ac_base() -> void:
	var res = ResourceLoader.load("res://data/armor/scale_mail.tres")
	if res == null:
		fail("scale_mail.tres failed to load")
		return
	assert_eq(res.ac_base, 4, "scale_mail ac_base must be 4")


func test_scale_mail_category() -> void:
	var res = ResourceLoader.load("res://data/armor/scale_mail.tres")
	if res == null:
		fail("scale_mail.tres failed to load")
		return
	assert_eq(res.category, "medium", "scale_mail category must be 'medium'")


# ── CharacterResource schema ──────────────────────────────────────────────────

func test_character_resource_default_name() -> void:
	var res = CharacterResource.new()
	assert_eq(res.name, "", "CharacterResource default name must be ''")


func test_character_resource_default_race() -> void:
	var res = CharacterResource.new()
	assert_eq(res.race, "", "CharacterResource default race must be ''")


func test_character_resource_default_attributes() -> void:
	var res = CharacterResource.new()
	assert_eq(res.attributes, {}, "CharacterResource default attributes must be {}")


func test_character_resource_default_starting_equipment() -> void:
	var res = CharacterResource.new()
	assert_eq(res.starting_equipment, [], "CharacterResource default starting_equipment must be []")


func test_character_resource_default_talent_selections() -> void:
	var res = CharacterResource.new()
	assert_eq(res.talent_selections, [], "CharacterResource default talent_selections must be []")


# ── Domain purity — no Node/Control inheritance ───────────────────────────────

func test_weapon_resource_gd_no_node_inheritance() -> void:
	var file := FileAccess.open("res://core/model/weapon_resource.gd", FileAccess.READ)
	assert_not_null(file, "core/model/weapon_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"weapon_resource.gd must not contain 'extends Node' — ADR-001 domain purity"
	)
	assert_false(
		content.contains("extends Control"),
		"weapon_resource.gd must not contain 'extends Control' — ADR-001 domain purity"
	)


func test_armor_resource_gd_no_node_inheritance() -> void:
	var file := FileAccess.open("res://core/model/armor_resource.gd", FileAccess.READ)
	assert_not_null(file, "core/model/armor_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"armor_resource.gd must not contain 'extends Node' — ADR-001 domain purity"
	)
	assert_false(
		content.contains("extends Control"),
		"armor_resource.gd must not contain 'extends Control' — ADR-001 domain purity"
	)


func test_character_resource_gd_no_node_inheritance() -> void:
	var file := FileAccess.open("res://core/model/character_resource.gd", FileAccess.READ)
	assert_not_null(file, "core/model/character_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"character_resource.gd must not contain 'extends Node' — ADR-001 domain purity"
	)
	assert_false(
		content.contains("extends Control"),
		"character_resource.gd must not contain 'extends Control' — ADR-001 domain purity"
	)


# ── CI linter step 2 — no binary .res files in data/ ─────────────────────────

func test_no_binary_res_files_in_data() -> void:
	var violations: Array = []
	_scan_for_binary_res("res://data", violations)
	assert_eq(
		violations.size(), 0,
		"CI linter step 2: no .res binary files allowed in data/:\n" + "\n".join(violations)
	)


func _scan_for_binary_res(dir_path: String, violations: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			_scan_for_binary_res(dir_path + "/" + entry, violations)
		elif entry.ends_with(".res"):
			violations.append(dir_path + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()
