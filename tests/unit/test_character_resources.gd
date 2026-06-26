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
## Characters:
##   - Titus         (Human Fighter)
##   - Gram Marx     (Tiefling Wizard)
##   - Marigold      (Elven Divine Warrior)
##   - Dwarf Channeler (Dwarf Divine Channeler)

const CharacterResource = preload("res://core/model/character_resource.gd")


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
