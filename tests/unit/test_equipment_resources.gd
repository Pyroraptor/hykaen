extends GutTest
## tests/unit/test_equipment_resources.gd
##
## GUT test suite for FEAT-004: WeaponResource, ArmorResource, CharacterResource
## schemas and starter equipment .tres data files.
## Validates all test criteria for US-006 (schema and equipment data portions).
##
## FEAT-023 additions: canonical attribute key convention ('strength' not 'str').

const WeaponResource = preload("res://core/model/weapon_resource.gd")
const ArmorResource  = preload("res://core/model/armor_resource.gd")
const CharacterResource = preload("res://core/model/character_resource.gd")
const ResolutionClass = preload("res://core/rules/resolution.gd")
const RNGClass = preload("res://core/rules/rng.gd")


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
		fail_test("longsword.tres failed to load — cannot check type")
		return
	assert_is(res, WeaponResource, "longsword.tres must be an instance of WeaponResource")


func test_longsword_damage_die() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	if res == null:
		fail_test("longsword.tres failed to load")
		return
	assert_eq(res.damage_die, 6, "longsword damage_die must be 6")


func test_longsword_damage_count() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	if res == null:
		fail_test("longsword.tres failed to load")
		return
	assert_eq(res.damage_count, 1, "longsword damage_count must be 1")


func test_longsword_damage_modifier_attribute() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	if res == null:
		fail_test("longsword.tres failed to load")
		return
	assert_eq(res.damage_modifier_attribute, "strength", "longsword damage_modifier_attribute must be 'strength' (FEAT-023: canonical full key)")


## FEAT-023: Canonical attribute key — explicit name mirrors the new test criterion.
func test_longsword_damage_modifier_attribute_is_strength() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	if res == null:
		fail_test("longsword.tres failed to load")
		return
	assert_eq(
		res.damage_modifier_attribute, "strength",
		"longsword.tres damage_modifier_attribute must be 'strength' — abbreviated 'str' is forbidden (FEAT-023)"
	)


func test_longsword_proficiency_bonus() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	if res == null:
		fail_test("longsword.tres failed to load")
		return
	assert_eq(res.proficiency_bonus, 1, "longsword proficiency_bonus must be 1")


# ── ArmorResource schema ──────────────────────────────────────────────────────

func test_scale_mail_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/armor/scale_mail.tres")
	assert_not_null(res, "ResourceLoader.load('data/armor/scale_mail.tres') must return non-null")


func test_scale_mail_is_armor_resource() -> void:
	var res = ResourceLoader.load("res://data/armor/scale_mail.tres")
	if res == null:
		fail_test("scale_mail.tres failed to load — cannot check type")
		return
	assert_is(res, ArmorResource, "scale_mail.tres must be an instance of ArmorResource")


func test_scale_mail_ac_base() -> void:
	var res = ResourceLoader.load("res://data/armor/scale_mail.tres")
	if res == null:
		fail_test("scale_mail.tres failed to load")
		return
	assert_eq(res.ac_base, 4, "scale_mail ac_base must be 4")


func test_scale_mail_category() -> void:
	var res = ResourceLoader.load("res://data/armor/scale_mail.tres")
	if res == null:
		fail_test("scale_mail.tres failed to load")
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


# ── FEAT-023: Canonical attribute key convention ──────────────────────────────

## test_all_weapon_tres_files_use_canonical_attribute_names
##
## Loops over every .tres file in data/weapons/, loads each as a WeaponResource,
## and asserts that damage_modifier_attribute is a full canonical name
## ('strength' or 'dexterity') — never an abbreviated form ('str', 'dex', etc.).
func test_all_weapon_tres_files_use_canonical_attribute_names() -> void:
	var CANONICAL: Array = ["strength", "dexterity"]
	var FORBIDDEN_PREFIXES: Array = ["str", "dex", "con", "wil", "int", "soc"]
	var violations: Array = []

	var dir := DirAccess.open("res://data/weapons")
	if dir == null:
		fail_test("Cannot open res://data/weapons — directory missing")
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".tres"):
			var path: String = "res://data/weapons/" + entry
			var res = ResourceLoader.load(path)
			if res == null:
				violations.append(path + ": failed to load")
			elif not res.get("damage_modifier_attribute") is String:
				violations.append(path + ": damage_modifier_attribute is not a String")
			else:
				var attr: String = res.damage_modifier_attribute
				if not (attr in CANONICAL):
					violations.append(
						"%s: damage_modifier_attribute='%s' is not canonical (must be one of %s)"
						% [path, attr, str(CANONICAL)]
					)
		entry = dir.get_next()
	dir.list_dir_end()

	assert_eq(
		violations.size(), 0,
		"All weapon .tres files must use canonical full attribute names:\n" + "\n".join(violations)
	)


## test_weapon_attribute_key_resolves_without_remap
##
## Loads longsword.tres and titus.tres, builds attacker/weapon dicts from the
## resources directly (no manual key remapping), calls resolve_weapon_attack()
## using longsword.damage_modifier_attribute — and asserts damage_final > 0.
##
## A non-zero damage_final proves the attribute key lookup found
## attacker['strength'] without any shim or override (FEAT-023 / DEF-003).
##
## Pinned seed: 2 → d20=11, roll_total = 11 + strength(5) + prof_bonus(1) = 17
## Target AC = 1 guarantees a hit regardless of roll.
func test_weapon_attribute_key_resolves_without_remap() -> void:
	var longsword = ResourceLoader.load("res://data/weapons/longsword.tres")
	var titus = ResourceLoader.load("res://data/characters/titus.tres")
	if longsword == null:
		fail_test("longsword.tres failed to load — cannot run remap test")
		return
	if titus == null:
		fail_test("titus.tres failed to load — cannot run remap test")
		return

	# Build attacker dict from titus.tres attributes directly — no hardcoding
	var attacker: Dictionary = {}
	for k in titus.attributes:
		attacker[k] = titus.attributes[k]

	# Build weapon dict using longsword resource fields directly (no manual remap)
	var weapon: Dictionary = {
		"damage_modifier_attribute": longsword.damage_modifier_attribute,
		"proficiency_bonus":         longsword.proficiency_bonus,
		"damage_die":                longsword.damage_die
	}

	# Target with minimal AC to guarantee a hit and confirm damage_final > 0
	var target: Dictionary = {"ac": 1, "reflex": 1, "fortitude": 1, "will": 1}

	# seed 2 → d20=11, guaranteed hit; damage > 0 proves key resolved correctly
	var rng = RNGClass.new(2)
	var resolution = ResolutionClass.new(rng)
	var result: Dictionary = resolution.resolve_weapon_attack(attacker, target, weapon, "ac")

	assert_true(
		result.get("damage_final", 0) > 0,
		(
			"resolve_weapon_attack using longsword.damage_modifier_attribute='%s' must produce "
			+ "damage_final > 0 — key lookup must succeed without any shim (FEAT-023)"
		) % longsword.damage_modifier_attribute
	)
