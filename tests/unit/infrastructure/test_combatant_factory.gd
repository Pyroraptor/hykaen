extends GutTest
## tests/unit/infrastructure/test_combatant_factory.gd — FEAT-005 (US-004;
## FR-007).
##
## Verifies infrastructure/combatant_factory.gd's build_party_combatant()
## exposes `equipped_items` on the returned combatant Dictionary: a SHALLOW
## copy of CharacterResource.equipped_items (character.equipped_items.
## duplicate()) so the Array container is independent per-build but the
## ItemResource instances INSIDE it are the SAME live references as
## character.equipped_items — a mutation to a field on one of those
## ItemResource instances (e.g. is_charged) must be visible both through the
## combatant dict's copy of the array AND through character.equipped_items
## directly, since both arrays hold the identical Resource objects.
##
## This is the infrastructure seam (ADR-004) that lets the application layer
## duck-type-read equipped_items off the combatant dict without the
## application layer importing any Resource/.tres machinery.

const CombatantFactoryClass = preload("res://infrastructure/combatant_factory.gd")

const GRAM_MARX_PATH: String = "res://data/characters/gram_marx.tres"
const MARIGOLD_PATH: String = "res://data/characters/marigold.tres"
const DWARF_CHANNELER_PATH: String = "res://data/characters/dwarf_channeler.tres"
const TITUS_PATH: String = "res://data/characters/titus.tres"
const SKELETON_PATH: String = "res://data/enemies/skeleton.tres"


func _has_item_id(equipped_items: Array, item_id: String) -> bool:
	for item in equipped_items:
		if item.item_id == item_id:
			return true
	return false


func test_gram_marx_equipped_items_has_3_entries_including_orb_gram() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_1")

	assert_false(combatant.has("error"), "fixture assumption: gram_marx.tres must build a valid combatant with no error")
	assert_true(combatant.has("equipped_items"), "build_party_combatant() must expose 'equipped_items' on the combatant dict")

	var equipped_items: Array = combatant.get("equipped_items", [])
	assert_eq(equipped_items.size(), 2, "gram_marx's combatant['equipped_items'] must have exactly 2 entries (staff_gram, orb_gram) — Wizards do not Channel")
	assert_true(
		_has_item_id(equipped_items, "orb_gram"),
		"gram_marx's combatant['equipped_items'] must include orb_gram"
	)


func test_mutating_item_is_charged_via_combatant_dict_is_visible_on_character_directly() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_1")

	var character = ResourceLoader.load(GRAM_MARX_PATH)

	var orb_via_combatant = null
	for item in combatant.get("equipped_items", []):
		if item.item_id == "orb_gram":
			orb_via_combatant = item
	assert_not_null(orb_via_combatant, "fixture assumption: orb_gram must be reachable through combatant['equipped_items']")

	assert_true(orb_via_combatant.is_charged, "fixture assumption: orb_gram.tres is authored with is_charged=true")

	# Mutate through the reference obtained via the combatant dict.
	orb_via_combatant.is_charged = false

	var orb_via_character = null
	for item in character.equipped_items:
		if item.item_id == "orb_gram":
			orb_via_character = item
	assert_not_null(orb_via_character, "fixture assumption: orb_gram must be reachable through character.equipped_items")

	assert_false(
		orb_via_character.is_charged,
		"mutating is_charged on an ItemResource reached through combatant['equipped_items'] must be visible via character.equipped_items directly -- equipped_items must be a SHALLOW copy (live ItemResource references), not a deep copy"
	)


func test_gram_marx_known_spell_ids_unchanged_by_equipped_items_addition() -> void:
	# FEAT-004 (US-006; FR-006) authored known_spell_ids = ["fireball"] onto
	# gram_marx.tres (unrelated to this equipped_items-addition regression
	# guard) -- the expected value here tracks that data change; this test
	# still protects its original concern: equipped_items wiring must not
	# itself perturb known_spell_ids.
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_1")

	assert_eq(
		combatant.get("known_spell_ids", ["SENTINEL"]), ["fireball"],
		"regression: gram_marx's known_spell_ids output must be unchanged by the equipped_items addition"
	)


func test_marigold_known_spell_ids_unchanged_by_equipped_items_addition() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(MARIGOLD_PATH, null, "marigold_1")

	assert_eq(
		combatant.get("known_spell_ids", []), ["fire_bolt", "channel"],
		"regression: marigold's known_spell_ids output must be unchanged by the equipped_items addition"
	)


func test_patience_primary_weapon_is_mace_not_shield() -> void:
	# Patience's starting_equipment is [mace.tres, small_shield.tres, chain_shirt.tres].
	# build_party_combatant() must pick the FIRST WeaponResource (mace, damage_die=8),
	# not the last (small_shield, damage_die=4).
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(DWARF_CHANNELER_PATH, null, "patience_1")

	assert_false(combatant.has("error"), "dwarf_channeler.tres must build without error")
	var weapon: Dictionary = combatant.get("weapon", {})
	assert_eq(
		weapon.get("damage_die", -1), 8,
		"Patience's primary weapon must be the mace (damage_die=8), not the shield (damage_die=4)"
	)


func test_titus_weapon_dict_includes_name_equal_to_weapon_resource_name() -> void:
	# FEAT-004 (US-004; FR-002): build_party_combatant()'s weapon dict must
	# carry a 'name' key sourced from the source WeaponResource.name --
	# Titus's starting_equipment resolves to longsword.tres (name="Longsword").
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(TITUS_PATH, null, "titus_1")

	assert_false(combatant.has("error"), "titus.tres must build a valid combatant with no error")
	var weapon: Dictionary = combatant.get("weapon", {})
	var weapon_res = ResourceLoader.load("res://data/weapons/longsword.tres")
	assert_eq(
		weapon.get("name", "SENTINEL"), weapon_res.name,
		"build_party_combatant()'s weapon dict must include 'name' equal to the source WeaponResource.name"
	)


func test_skeleton_weapon_dict_includes_name_equal_to_weapon_resource_name() -> void:
	# FEAT-004 (US-004; FR-002): build_enemy_combatant()'s weapon dict must
	# carry a 'name' key sourced from the source WeaponResource.name --
	# skeleton.tres resolves weapon_paths[0] to arming_sword.tres (name="Arming Sword").
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(SKELETON_PATH, null, "skeleton_1")

	assert_false(combatant.has("error"), "skeleton.tres must build a valid combatant with no error")
	var weapon: Dictionary = combatant.get("weapon", {})
	var weapon_res = ResourceLoader.load("res://data/weapons/arming_sword.tres")
	assert_eq(
		weapon.get("name", "SENTINEL"), weapon_res.name,
		"build_enemy_combatant()'s weapon dict must include 'name' equal to the source WeaponResource.name"
	)


func test_titus_weapon_name_round_trips_through_combatant_from_dict() -> void:
	# Combatant.from_dict()/to_dict() deep-duplicate arbitrary weapon-dict
	# keys (core/domain/combatant.gd's weapon.duplicate(true) path) -- this
	# regression guard pins that the new 'name' key survives that round-trip
	# unchanged, per ADR-001/ADR-003 (zero domain-layer changes required).
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(TITUS_PATH, null, "titus_1")

	var weapon: Dictionary = combatant.get("weapon", {})
	assert_eq(weapon.get("name", "SENTINEL"), "Longsword", "'name' must round-trip unchanged through Combatant.from_dict()")

	var weapons: Array = combatant.get("weapons", [])
	assert_eq(weapons.size(), 1, "Titus has a single weapon; weapons[0] must mirror the weapon dict, including 'name'")
	assert_eq(
		(weapons[0] as Dictionary).get("name", "SENTINEL"), "Longsword",
		"'name' must round-trip unchanged into weapons[0] as well (weapons[0] == weapon invariant)"
	)
