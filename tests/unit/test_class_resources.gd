extends GutTest
## tests/unit/test_class_resources.gd
##
## GUT test suite for FEAT-003: ClassData Resource Schema and four class .tres files.
## Validates all test criteria for US-004 and ADR-003 (Content as Data Resources).

const ClassResource = preload("res://core/model/class_resource.gd")

# ── ADR-003 text-format verification ─────────────────────────────────────────
# Each .tres first line must start with '[gd_resource' confirming text format.

func test_fighter_tres_is_text_format() -> void:
	var file := FileAccess.open("res://data/classes/fighter.tres", FileAccess.READ)
	assert_not_null(file, "data/classes/fighter.tres must be readable")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.contains("[gd_resource"),
		"fighter.tres first line must contain '[gd_resource' — text-format required (ADR-003)"
	)


func test_wizard_tres_is_text_format() -> void:
	var file := FileAccess.open("res://data/classes/wizard.tres", FileAccess.READ)
	assert_not_null(file, "data/classes/wizard.tres must be readable")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.contains("[gd_resource"),
		"wizard.tres first line must contain '[gd_resource' — text-format required (ADR-003)"
	)


func test_divine_warrior_tres_is_text_format() -> void:
	var file := FileAccess.open("res://data/classes/divine_warrior.tres", FileAccess.READ)
	assert_not_null(file, "data/classes/divine_warrior.tres must be readable")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.contains("[gd_resource"),
		"divine_warrior.tres first line must contain '[gd_resource' — text-format required (ADR-003)"
	)


func test_divine_channeler_tres_is_text_format() -> void:
	var file := FileAccess.open("res://data/classes/divine_channeler.tres", FileAccess.READ)
	assert_not_null(file, "data/classes/divine_channeler.tres must be readable")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.contains("[gd_resource"),
		"divine_channeler.tres first line must contain '[gd_resource' — text-format required (ADR-003)"
	)


# ── Fighter (class_hp=6, stamina_base=4, skills_base=1, spellcasting='') ─────

func test_fighter_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/classes/fighter.tres")
	assert_not_null(res, "ResourceLoader.load('data/classes/fighter.tres') must return non-null")


func test_fighter_is_class_resource() -> void:
	var res = ResourceLoader.load("res://data/classes/fighter.tres")
	if res == null:
		fail_test("fighter.tres failed to load — cannot check type")
		return
	assert_is(res, ClassResource, "fighter.tres must be an instance of ClassResource")


func test_fighter_class_hp() -> void:
	var res = ResourceLoader.load("res://data/classes/fighter.tres")
	if res == null:
		fail_test("fighter.tres failed to load")
		return
	assert_eq(res.class_hp, 6, "fighter class_hp must be 6")


func test_fighter_stamina_base() -> void:
	var res = ResourceLoader.load("res://data/classes/fighter.tres")
	if res == null:
		fail_test("fighter.tres failed to load")
		return
	assert_eq(res.stamina_base, 4, "fighter stamina_base must be 4")


func test_fighter_skills_base() -> void:
	var res = ResourceLoader.load("res://data/classes/fighter.tres")
	if res == null:
		fail_test("fighter.tres failed to load")
		return
	assert_eq(res.skills_base, 1, "fighter skills_base must be 1")


func test_fighter_spellcasting_attribute() -> void:
	var res = ResourceLoader.load("res://data/classes/fighter.tres")
	if res == null:
		fail_test("fighter.tres failed to load")
		return
	assert_eq(res.spellcasting_attribute, "", "fighter spellcasting_attribute must be ''")


# ── Wizard (class_hp=4, stamina_base=1, skills_base=2, spellcasting='intellect') ──

func test_wizard_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/classes/wizard.tres")
	assert_not_null(res, "ResourceLoader.load('data/classes/wizard.tres') must return non-null")


func test_wizard_is_class_resource() -> void:
	var res = ResourceLoader.load("res://data/classes/wizard.tres")
	if res == null:
		fail_test("wizard.tres failed to load — cannot check type")
		return
	assert_is(res, ClassResource, "wizard.tres must be an instance of ClassResource")


func test_wizard_class_hp() -> void:
	var res = ResourceLoader.load("res://data/classes/wizard.tres")
	if res == null:
		fail_test("wizard.tres failed to load")
		return
	assert_eq(res.class_hp, 4, "wizard class_hp must be 4")


func test_wizard_stamina_base() -> void:
	var res = ResourceLoader.load("res://data/classes/wizard.tres")
	if res == null:
		fail_test("wizard.tres failed to load")
		return
	assert_eq(res.stamina_base, 1, "wizard stamina_base must be 1")


func test_wizard_skills_base() -> void:
	var res = ResourceLoader.load("res://data/classes/wizard.tres")
	if res == null:
		fail_test("wizard.tres failed to load")
		return
	assert_eq(res.skills_base, 2, "wizard skills_base must be 2")


func test_wizard_spellcasting_attribute() -> void:
	var res = ResourceLoader.load("res://data/classes/wizard.tres")
	if res == null:
		fail_test("wizard.tres failed to load")
		return
	assert_eq(res.spellcasting_attribute, "intellect", "wizard spellcasting_attribute must be 'intellect'")


# ── Divine Warrior (class_hp=6, stamina_base=3, skills_base=1, spellcasting='willpower') ──

func test_divine_warrior_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/classes/divine_warrior.tres")
	assert_not_null(res, "ResourceLoader.load('data/classes/divine_warrior.tres') must return non-null")


func test_divine_warrior_is_class_resource() -> void:
	var res = ResourceLoader.load("res://data/classes/divine_warrior.tres")
	if res == null:
		fail_test("divine_warrior.tres failed to load — cannot check type")
		return
	assert_is(res, ClassResource, "divine_warrior.tres must be an instance of ClassResource")


func test_divine_warrior_class_hp() -> void:
	var res = ResourceLoader.load("res://data/classes/divine_warrior.tres")
	if res == null:
		fail_test("divine_warrior.tres failed to load")
		return
	assert_eq(res.class_hp, 6, "divine_warrior class_hp must be 6")


func test_divine_warrior_stamina_base() -> void:
	var res = ResourceLoader.load("res://data/classes/divine_warrior.tres")
	if res == null:
		fail_test("divine_warrior.tres failed to load")
		return
	assert_eq(res.stamina_base, 3, "divine_warrior stamina_base must be 3")


func test_divine_warrior_skills_base() -> void:
	var res = ResourceLoader.load("res://data/classes/divine_warrior.tres")
	if res == null:
		fail_test("divine_warrior.tres failed to load")
		return
	assert_eq(res.skills_base, 1, "divine_warrior skills_base must be 1")


func test_divine_warrior_spellcasting_attribute() -> void:
	var res = ResourceLoader.load("res://data/classes/divine_warrior.tres")
	if res == null:
		fail_test("divine_warrior.tres failed to load")
		return
	assert_eq(res.spellcasting_attribute, "willpower", "divine_warrior spellcasting_attribute must be 'willpower'")


# ── Divine Channeler (class_hp=5, stamina_base=2, skills_base=2, spellcasting='social') ──

func test_divine_channeler_loads_non_null() -> void:
	var res = ResourceLoader.load("res://data/classes/divine_channeler.tres")
	assert_not_null(res, "ResourceLoader.load('data/classes/divine_channeler.tres') must return non-null")


func test_divine_channeler_is_class_resource() -> void:
	var res = ResourceLoader.load("res://data/classes/divine_channeler.tres")
	if res == null:
		fail_test("divine_channeler.tres failed to load — cannot check type")
		return
	assert_is(res, ClassResource, "divine_channeler.tres must be an instance of ClassResource")


func test_divine_channeler_class_hp() -> void:
	var res = ResourceLoader.load("res://data/classes/divine_channeler.tres")
	if res == null:
		fail_test("divine_channeler.tres failed to load")
		return
	assert_eq(res.class_hp, 5, "divine_channeler class_hp must be 5")


func test_divine_channeler_stamina_base() -> void:
	var res = ResourceLoader.load("res://data/classes/divine_channeler.tres")
	if res == null:
		fail_test("divine_channeler.tres failed to load")
		return
	assert_eq(res.stamina_base, 2, "divine_channeler stamina_base must be 2")


func test_divine_channeler_skills_base() -> void:
	var res = ResourceLoader.load("res://data/classes/divine_channeler.tres")
	if res == null:
		fail_test("divine_channeler.tres failed to load")
		return
	assert_eq(res.skills_base, 2, "divine_channeler skills_base must be 2")


func test_divine_channeler_spellcasting_attribute() -> void:
	var res = ResourceLoader.load("res://data/classes/divine_channeler.tres")
	if res == null:
		fail_test("divine_channeler.tres failed to load")
		return
	assert_eq(res.spellcasting_attribute, "social", "divine_channeler spellcasting_attribute must be 'social'")


# ── Domain purity — class_resource.gd must not extend Node or Control ────────

func test_class_resource_gd_no_node_inheritance() -> void:
	var file := FileAccess.open("res://core/model/class_resource.gd", FileAccess.READ)
	assert_not_null(file, "core/model/class_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"class_resource.gd must not contain 'extends Node' — ADR-001 domain purity"
	)
	assert_false(
		content.contains("extends Control"),
		"class_resource.gd must not contain 'extends Control' — ADR-001 domain purity"
	)
