extends GutTest
## tests/unit/test_prologue_character_equipment_fixtures.gd
##
## GUT test suite for FEAT-008: Wire equipped_items/level into prologue
## character fixtures.
##
## Additively edits the four prologue party-member .tres fixtures
## (gram_marx, titus, marigold, dwarf_channeler) to reference the FEAT-007
## item resources via `level` and `equipped_items`, without touching any
## other existing field (ADR-004).
##
## Validates the US-008 test_criteria:
##   - gram_marx.tres loads with level==1 and equipped_items containing
##     staff_gram and orb_gram (NOT ring_channeling — Wizards do not Channel)
##
## FEAT-004 (US-003; FR-005/FR-006) additively extends this suite:
##   - gram_marx.tres equipped_items contains staff_gram (MAIN_HAND) and
##     orb_gram (ACCESSORY_1); ring_channeling is a Channeler item and is
##     NOT in a Wizard's loadout
##   - titus.tres loads with level==1 and equipped_items containing
##     longsword_titus only (two-handed; shield removed)
##   - marigold.tres loads with level==1 and equipped_items containing
##     shortsword_marigold
##   - dwarf_channeler.tres loads with level==1 and equipped_items
##     containing axe_dwarf
##   - Field-diff regression test confirms name/race/class_ref/attributes/
##     skills/starting_equipment/talent_selections/known_spell_ids/
##     primary_offensive_attribute are unchanged from their pre-edit values
##     on all four fixtures (RISK-004)
##
## `git status` clean-tree-after-commit criterion (CLAUDE.md / RISK-003)
## is a commit-hygiene process step enforced by the agent session and by
## scripts/verify_clean_tree.sh in the CI pipeline, not by a GUT assertion
## in this file.

const CharacterResourceClass = preload("res://core/model/character_resource.gd")


# ── Helpers ──────────────────────────────────────────────────────────────

## Returns true if `equipped_items` (Array of ItemResource) contains an
## item whose item_id matches `item_id`.
func _has_item_id(equipped_items: Array, item_id: String) -> bool:
	for item in equipped_items:
		if item != null and item.item_id == item_id:
			return true
	return false


# ── gram_marx.tres — level + equipped_items (staff_gram, ring_channeling) ──

func test_gram_marx_level_is_1() -> void:
	var character = ResourceLoader.load("res://data/characters/gram_marx.tres")
	assert_not_null(character, "gram_marx.tres must load non-null")
	if character == null:
		return
	assert_eq(character.level, 1, "gram_marx.level must be 1")


func test_gram_marx_equipped_items_contains_staff_gram() -> void:
	var character = ResourceLoader.load("res://data/characters/gram_marx.tres")
	assert_not_null(character, "gram_marx.tres must load non-null")
	if character == null:
		return
	assert_true(
		_has_item_id(character.equipped_items, "staff_gram"),
		"gram_marx.equipped_items must contain item_id 'staff_gram'"
	)


func test_gram_marx_equipped_items_does_not_contain_ring_channeling() -> void:
	# Wizards do not Channel — ring_channeling is a Channeler item and must
	# not appear in a Wizard's loadout.
	var character = ResourceLoader.load("res://data/characters/gram_marx.tres")
	assert_not_null(character, "gram_marx.tres must load non-null")
	if character == null:
		return
	assert_false(
		_has_item_id(character.equipped_items, "ring_channeling"),
		"gram_marx.equipped_items must NOT contain ring_channeling — Wizards do not Channel"
	)


# ── gram_marx.tres — orb_gram (FEAT-004; US-003/FR-005/FR-006) ─────────────

func test_gram_marx_equipped_items_contains_orb_gram() -> void:
	var character = ResourceLoader.load("res://data/characters/gram_marx.tres")
	assert_not_null(character, "gram_marx.tres must load non-null")
	if character == null:
		return
	assert_true(
		_has_item_id(character.equipped_items, "orb_gram"),
		"gram_marx.equipped_items must contain item_id 'orb_gram' (FEAT-004)"
	)


func test_gram_marx_equipped_items_has_exactly_3_entries() -> void:
	var character = ResourceLoader.load("res://data/characters/gram_marx.tres")
	assert_not_null(character, "gram_marx.tres must load non-null")
	if character == null:
		return
	assert_eq(
		character.equipped_items.size(), 2,
		"gram_marx.equipped_items must have exactly 2 items (staff_gram, orb_gram) — Wizards do not Channel"
	)


# ── titus.tres — level + equipped_items (longsword_titus only; two-handed) ──

func test_titus_level_is_1() -> void:
	var character = ResourceLoader.load("res://data/characters/titus.tres")
	assert_not_null(character, "titus.tres must load non-null")
	if character == null:
		return
	assert_eq(character.level, 1, "titus.level must be 1")


func test_titus_equipped_items_contains_longsword_titus() -> void:
	var character = ResourceLoader.load("res://data/characters/titus.tres")
	assert_not_null(character, "titus.tres must load non-null")
	if character == null:
		return
	assert_true(
		_has_item_id(character.equipped_items, "longsword_titus"),
		"titus.equipped_items must contain item_id 'longsword_titus'"
	)


func test_titus_equipped_items_has_only_longsword() -> void:
	var character = ResourceLoader.load("res://data/characters/titus.tres")
	assert_not_null(character, "titus.tres must load non-null")
	if character == null:
		return
	assert_eq(
		character.equipped_items.size(), 1,
		"titus.equipped_items must have exactly 1 item (longsword; two-handed blocks OFF_HAND)"
	)


# ── marigold.tres — level + equipped_items (shortsword_marigold) ──────────

func test_marigold_level_is_1() -> void:
	var character = ResourceLoader.load("res://data/characters/marigold.tres")
	assert_not_null(character, "marigold.tres must load non-null")
	if character == null:
		return
	assert_eq(character.level, 1, "marigold.level must be 1")


func test_marigold_equipped_items_contains_shortsword_marigold() -> void:
	var character = ResourceLoader.load("res://data/characters/marigold.tres")
	assert_not_null(character, "marigold.tres must load non-null")
	if character == null:
		return
	assert_true(
		_has_item_id(character.equipped_items, "shortsword_marigold"),
		"marigold.equipped_items must contain item_id 'shortsword_marigold'"
	)


# ── dwarf_channeler.tres — level + equipped_items (mace_patience, shield_patience) ──

func test_dwarf_channeler_level_is_1() -> void:
	var character = ResourceLoader.load("res://data/characters/dwarf_channeler.tres")
	assert_not_null(character, "dwarf_channeler.tres must load non-null")
	if character == null:
		return
	assert_eq(character.level, 1, "dwarf_channeler.level must be 1")


func test_dwarf_channeler_equipped_items_contains_mace_patience() -> void:
	var character = ResourceLoader.load("res://data/characters/dwarf_channeler.tres")
	assert_not_null(character, "dwarf_channeler.tres must load non-null")
	if character == null:
		return
	assert_true(
		_has_item_id(character.equipped_items, "mace_patience"),
		"dwarf_channeler.equipped_items must contain item_id 'mace_patience' (Patience's Mace)"
	)


func test_dwarf_channeler_equipped_items_contains_shield_patience() -> void:
	var character = ResourceLoader.load("res://data/characters/dwarf_channeler.tres")
	assert_not_null(character, "dwarf_channeler.tres must load non-null")
	if character == null:
		return
	assert_true(
		_has_item_id(character.equipped_items, "shield_patience"),
		"dwarf_channeler.equipped_items must contain item_id 'shield_patience' (Patience's Shield)"
	)


# ── Field-diff regression test (RISK-004) ──────────────────────────────────
##
## Confirms name/race/class_ref/attributes/skills/starting_equipment/
## talent_selections/known_spell_ids/primary_offensive_attribute are
## UNCHANGED from their pre-FEAT-008-edit values on all four fixtures.
## Expected values below are the exact pre-edit field values captured from
## the fixtures before this feature's additive level/equipped_items edit.

func _assert_starting_equipment_matches(character, expected_suffixes: Array, path: String) -> void:
	assert_eq(
		character.starting_equipment.size(), expected_suffixes.size(),
		"%s starting_equipment size must be unchanged; got %d, expected %d" % [
			path, character.starting_equipment.size(), expected_suffixes.size()
		]
	)
	for i in range(min(character.starting_equipment.size(), expected_suffixes.size())):
		assert_true(
			str(character.starting_equipment[i]).ends_with(expected_suffixes[i]),
			"%s starting_equipment[%d] must be unchanged; got '%s', expected suffix '%s'" % [
				path, i, str(character.starting_equipment[i]), expected_suffixes[i]
			]
		)


func test_gram_marx_field_diff_unchanged() -> void:
	var character = ResourceLoader.load("res://data/characters/gram_marx.tres")
	assert_not_null(character, "gram_marx.tres must load non-null")
	if character == null:
		return
	assert_eq(character.name, "Gram Marx", "gram_marx.name must be unchanged")
	assert_eq(character.race, "Tiefling", "gram_marx.race must be unchanged")
	assert_not_null(character.class_ref, "gram_marx.class_ref must be unchanged (non-null)")
	if character.class_ref != null:
		assert_true(
			character.class_ref.resource_path.ends_with("wizard.tres"),
			"gram_marx.class_ref must be unchanged (still wizard.tres)"
		)
	assert_eq(
		character.attributes,
		{"constitution": 2, "dexterity": 2, "intellect": 5, "intuition": 3, "social": 2, "strength": 1, "willpower": 2},
		"gram_marx.attributes must be unchanged"
	)
	assert_eq(character.skills, {}, "gram_marx.skills must be unchanged (default {})")
	_assert_starting_equipment_matches(
		character, ["weapons/quarterstaff.tres", "armor/robes.tres"], "gram_marx.tres"
	)
	assert_eq(character.talent_selections, [], "gram_marx.talent_selections must be unchanged")
	# FEAT-004 (US-006; FR-006) grants Gram Marx "fireball" via
	# known_spell_ids -- this field-diff baseline (originally pinned by
	# FEAT-008's equipped_items change) is updated in lockstep with that
	# intentional data change; every OTHER field on this fixture stays
	# byte-for-byte unchanged, which is what this test still guards.
	assert_eq(character.known_spell_ids, ["fireball"], "gram_marx.known_spell_ids must reflect the FEAT-004 fireball grant")
	assert_eq(
		character.primary_offensive_attribute, "",
		"gram_marx.primary_offensive_attribute must be unchanged (default '')"
	)


func test_titus_field_diff_unchanged() -> void:
	var character = ResourceLoader.load("res://data/characters/titus.tres")
	assert_not_null(character, "titus.tres must load non-null")
	if character == null:
		return
	assert_eq(character.name, "Titus", "titus.name must be unchanged")
	assert_eq(character.race, "Human", "titus.race must be unchanged")
	assert_not_null(character.class_ref, "titus.class_ref must be unchanged (non-null)")
	if character.class_ref != null:
		assert_true(
			character.class_ref.resource_path.ends_with("fighter.tres"),
			"titus.class_ref must be unchanged (still fighter.tres)"
		)
	assert_eq(
		character.attributes,
		{"constitution": 4, "dexterity": 2, "intellect": 1, "intuition": 2, "social": 1, "strength": 5, "willpower": 2},
		"titus.attributes must be unchanged"
	)
	assert_eq(
		character.skills, {"determination": 2, "mobility": 2},
		"titus.skills must be unchanged"
	)
	_assert_starting_equipment_matches(
		character, ["weapons/longsword.tres", "armor/chain_shirt.tres"], "titus.tres"
	)
	assert_eq(character.talent_selections, [], "titus.talent_selections must be unchanged")
	assert_eq(character.known_spell_ids, [], "titus.known_spell_ids must be unchanged (default [])")
	assert_eq(
		character.primary_offensive_attribute, "",
		"titus.primary_offensive_attribute must be unchanged (default '')"
	)


func test_marigold_field_diff_unchanged() -> void:
	var character = ResourceLoader.load("res://data/characters/marigold.tres")
	assert_not_null(character, "marigold.tres must load non-null")
	if character == null:
		return
	assert_eq(character.name, "Marigold", "marigold.name must be unchanged")
	assert_eq(character.race, "Elf", "marigold.race must be unchanged")
	assert_not_null(character.class_ref, "marigold.class_ref must be unchanged (non-null)")
	if character.class_ref != null:
		assert_true(
			character.class_ref.resource_path.ends_with("divine_warrior.tres"),
			"marigold.class_ref must be unchanged (still divine_warrior.tres)"
		)
	assert_eq(
		character.attributes,
		{"constitution": 3, "dexterity": 3, "intellect": 1, "intuition": 3, "social": 2, "strength": 3, "willpower": 4},
		"marigold.attributes must be unchanged"
	)
	assert_eq(character.skills, {}, "marigold.skills must be unchanged (default {})")
	_assert_starting_equipment_matches(
		character, ["weapons/shortsword.tres", "armor/leather_armor.tres"], "marigold.tres"
	)
	assert_eq(
		character.talent_selections, ["divine_champion_stealth"],
		"marigold.talent_selections must be unchanged"
	)
	assert_eq(
		character.known_spell_ids, ["fire_bolt", "channel"],
		"marigold.known_spell_ids must be unchanged"
	)
	assert_eq(
		character.primary_offensive_attribute, "dexterity",
		"marigold.primary_offensive_attribute must be unchanged"
	)


func test_dwarf_channeler_field_diff_unchanged() -> void:
	var character = ResourceLoader.load("res://data/characters/dwarf_channeler.tres")
	assert_not_null(character, "dwarf_channeler.tres must load non-null")
	if character == null:
		return
	assert_eq(character.name, "Patience Stoneshield", "dwarf_channeler.name must be unchanged")
	assert_eq(character.race, "Dwarf", "dwarf_channeler.race must be unchanged")
	assert_not_null(character.class_ref, "dwarf_channeler.class_ref must be unchanged (non-null)")
	if character.class_ref != null:
		assert_true(
			character.class_ref.resource_path.ends_with("divine_channeler.tres"),
			"dwarf_channeler.class_ref must be unchanged (still divine_channeler.tres)"
		)
	assert_eq(
		character.attributes,
		{"constitution": 4, "dexterity": 1, "intellect": 2, "intuition": 2, "social": 4, "strength": 2, "willpower": 3},
		"dwarf_channeler.attributes must be unchanged"
	)
	assert_eq(character.skills, {}, "dwarf_channeler.skills must be unchanged (default {})")
	# FEAT-002 (US-002 / FR-004): starting_equipment intentionally gains
	# 'res://data/weapons/small_shield.tres' as the second entry (mace
	# first, chain shirt last) — this pin is updated to match the new,
	# intended field value rather than the pre-FEAT-002 2-item list.
	_assert_starting_equipment_matches(
		character, ["weapons/mace.tres", "weapons/small_shield.tres", "armor/chain_shirt.tres"], "dwarf_channeler.tres"
	)
	assert_eq(character.talent_selections, [], "dwarf_channeler.talent_selections must be unchanged")
	assert_eq(character.known_spell_ids, [], "dwarf_channeler.known_spell_ids must be unchanged (default [])")
	assert_eq(
		character.primary_offensive_attribute, "",
		"dwarf_channeler.primary_offensive_attribute must be unchanged (default '')"
	)


# ── ADR-003 text-format gate for all four fixtures ─────────────────────────

func test_all_four_fixtures_remain_text_format() -> void:
	var paths: Array = [
		"res://data/characters/gram_marx.tres",
		"res://data/characters/titus.tres",
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


# ── Type sanity — all four still deserialize as CharacterResource ─────────

func test_all_four_fixtures_still_deserialize_as_character_resource() -> void:
	var paths: Array = [
		"res://data/characters/gram_marx.tres",
		"res://data/characters/titus.tres",
		"res://data/characters/marigold.tres",
		"res://data/characters/dwarf_channeler.tres",
	]
	for path in paths:
		var character = ResourceLoader.load(path)
		assert_not_null(character, "%s must load non-null" % path)
		if character == null:
			continue
		assert_is(character, CharacterResourceClass, "%s must be a CharacterResource instance" % path)
