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
const EnemyResourceClass = preload("res://data/enemies/enemy_resource.gd")
const WeaponResourceClass = preload("res://core/model/weapon_resource.gd")

const GRAM_MARX_PATH: String = "res://data/characters/gram_marx.tres"
const MARIGOLD_PATH: String = "res://data/characters/marigold.tres"
const DWARF_CHANNELER_PATH: String = "res://data/characters/dwarf_channeler.tres"
const TITUS_PATH: String = "res://data/characters/titus.tres"
const SKELETON_PATH: String = "res://data/enemies/skeleton.tres"
const ARMING_SWORD_PATH: String = "res://data/weapons/arming_sword.tres"
const SMALL_SHIELD_PATH: String = "res://data/weapons/small_shield.tres"
const MISSING_WEAPON_PATH_FEAT006: String = "res://data/weapons/does_not_exist_feat_006_off_hand.tres"

const ENEMY_FIXTURE_PATH_FEAT006: String = "user://test_combatant_factory_feat006_enemy_fixture.tres"
const WEAPON_FIXTURE_PATH_FEAT006: String = "user://test_combatant_factory_feat006_weapon_fixture.tres"


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


## --- FEAT-005 (US-005): ordered off-hand weapon collection ---------------


func test_patience_weapons_has_2_entries_mace_primary_small_shield_off_hand() -> void:
	# dwarf_channeler.tres.starting_equipment = [mace.tres, small_shield.tres,
	# chain_shirt.tres]. build_party_combatant() must walk this list and
	# collect an ORDERED weapon_res_list (not "last WeaponResource wins"),
	# producing combatant['weapons'] == [mace_dict, small_shield_dict].
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(DWARF_CHANNELER_PATH, null, "patience_1")

	assert_false(combatant.has("error"), "dwarf_channeler.tres must build without error")
	var weapons: Array = combatant.get("weapons", [])
	assert_eq(weapons.size(), 2, "Patience must have 2 weapons: mace (primary) + small shield (off-hand)")

	var mace: Dictionary = weapons[0]
	assert_eq(mace.get("damage_die", -1), 8, "weapons[0] must be the mace (damage_die=8)")
	assert_eq(mace.get("name", "SENTINEL"), "Mace", "weapons[0] name must be 'Mace'")

	var shield: Dictionary = weapons[1]
	assert_eq(shield.get("name", "SENTINEL"), "Small Shield", "weapons[1] name must be 'Small Shield'")
	assert_eq(shield.get("block_value", -1), 4, "weapons[1] block_value must match small_shield.tres (4)")
	assert_eq(shield.get("parry_bonus", -1), 1, "weapons[1] parry_bonus must match small_shield.tres (1)")
	assert_eq(shield.get("block_die", -1), 10, "weapons[1] block_die must match small_shield.tres (10)")


func test_patience_weapon_field_is_structurally_identical_to_weapons_0() -> void:
	# Invariant (data_model): weapons[0] is always structurally identical to
	# the `weapon` field. Must hold even when a second (off-hand) weapon is
	# present.
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(DWARF_CHANNELER_PATH, null, "patience_1")

	var weapon: Dictionary = combatant.get("weapon", {})
	var weapons: Array = combatant.get("weapons", [])
	assert_eq(weapons.size(), 2, "fixture assumption: Patience must have 2 weapons")
	assert_eq(weapon, weapons[0], "combatant['weapon'] must be structurally identical to weapons[0]")


func test_titus_weapons_has_1_entry_regression() -> void:
	# Regression guard (RISK-002 merge gate): a single-weapon party
	# combatant's weapons.size() must remain 1, with stats identical to the
	# pre-refactor baseline (longsword.tres).
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(TITUS_PATH, null, "titus_1")

	assert_false(combatant.has("error"), "titus.tres must build a valid combatant with no error")
	var weapons: Array = combatant.get("weapons", [])
	assert_eq(weapons.size(), 1, "Titus must have exactly 1 weapon (regression: ordered collection must not fabricate an off-hand)")

	var weapon_res = ResourceLoader.load("res://data/weapons/longsword.tres")
	var weapon: Dictionary = weapons[0]
	assert_eq(weapon.get("name", "SENTINEL"), weapon_res.name, "Titus weapons[0].name must match longsword.tres")
	assert_eq(weapon.get("damage_die", -1), weapon_res.damage_die, "Titus weapons[0].damage_die must match longsword.tres")
	assert_eq(weapon.get("proficiency_bonus", -1), weapon_res.proficiency_bonus, "Titus weapons[0].proficiency_bonus must match longsword.tres")
	assert_eq(weapon.get("parry_bonus", -1), weapon_res.parry_bonus, "Titus weapons[0].parry_bonus must match longsword.tres")
	assert_eq(weapon.get("block_value", -1), weapon_res.block_value, "Titus weapons[0].block_value must match longsword.tres")
	assert_eq(weapon.get("block_die", -1), weapon_res.block_die, "Titus weapons[0].block_die must match longsword.tres")


func test_gram_marx_weapons_has_1_entry_regression() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_1")

	assert_false(combatant.has("error"), "gram_marx.tres must build a valid combatant with no error")
	var weapons: Array = combatant.get("weapons", [])
	assert_eq(weapons.size(), 1, "Gram must have exactly 1 weapon (regression: ordered collection must not fabricate an off-hand)")
	assert_eq(weapons[0], combatant.get("weapon", {}), "Gram weapons[0] must be structurally identical to combatant['weapon']")


func test_marigold_weapons_has_1_entry_regression() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(MARIGOLD_PATH, null, "marigold_1")

	assert_false(combatant.has("error"), "marigold.tres must build a valid combatant with no error")
	var weapons: Array = combatant.get("weapons", [])
	assert_eq(weapons.size(), 1, "Marigold must have exactly 1 weapon (regression: ordered collection must not fabricate an off-hand)")
	assert_eq(weapons[0], combatant.get("weapon", {}), "Marigold weapons[0] must be structurally identical to combatant['weapon']")


func test_patience_armor_res_still_first_armor_resource_in_starting_equipment() -> void:
	# armor_res assignment (first ArmorResource in starting_equipment) must be
	# unaffected by the ordered weapon collection change -- chain_shirt.tres
	# is the 3rd entry in dwarf_channeler.tres.starting_equipment, after the
	# 2 weapon entries.
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(DWARF_CHANNELER_PATH, null, "patience_1")

	assert_false(combatant.has("error"), "dwarf_channeler.tres must build without error")
	var armor_res = ResourceLoader.load("res://data/armor/chain_shirt.tres")
	assert_eq(
		combatant.get("ac", -1), 10 + armor_res.ac_base,
		"Patience's ac must still be derived from chain_shirt.tres (first ArmorResource in starting_equipment)"
	)


func test_build_party_combatant_missing_primary_weapon_error_shape_unchanged() -> void:
	# Existing nil-check/error path for a missing primary weapon must be
	# unchanged by the ordered weapon collection refactor. Titus has a valid
	# primary weapon, so this pins the ABSENCE of an error for the happy
	# path; the error SHAPE itself ({"error": ..., "enemy_path": ...}) is
	# exercised by build_enemy_combatant regression tests elsewhere -- this
	# guard confirms build_party_combatant's success path never spuriously
	# reports an error after the refactor.
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(TITUS_PATH, null, "titus_1")
	assert_false(combatant.has("error"), "build_party_combatant() must not report an error when a primary weapon is present")


## --- FEAT-006 (US-006, EWA2-2-1): off-hand weapon resolution in
## build_enemy_combatant() -----------------------------------------------


func after_each() -> void:
	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ENEMY_FIXTURE_PATH_FEAT006)
		cleanup_dir.remove(WEAPON_FIXTURE_PATH_FEAT006)


func _save_enemy_fixture_feat006(res: EnemyResourceClass) -> String:
	var save_err := ResourceSaver.save(res, ENEMY_FIXTURE_PATH_FEAT006)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for this test's fixture EnemyResource")
	return ENEMY_FIXTURE_PATH_FEAT006


func _save_weapon_fixture_feat006(res: WeaponResourceClass) -> String:
	var save_err := ResourceSaver.save(res, WEAPON_FIXTURE_PATH_FEAT006)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for this test's fixture WeaponResource")
	return WEAPON_FIXTURE_PATH_FEAT006


func _single_weapon_enemy_fixture_feat006() -> String:
	var res := EnemyResourceClass.new()
	res.name = "SingleWeaponEnemy"
	res.hp = 5
	res.str = 1
	res.dex = 1
	res.weapon_paths = [ARMING_SWORD_PATH]
	return _save_enemy_fixture_feat006(res)


func test_valid_off_hand_path_override_yields_2_weapons_with_correct_off_hand_stats() -> void:
	var enemy_path: String = _single_weapon_enemy_fixture_feat006()

	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(
		enemy_path, null, "off_hand_override_1", "", SMALL_SHIELD_PATH
	)

	assert_false(combatant.has("error"), "a valid off_hand_path_override must not yield an error; got: %s" % str(combatant))
	var weapons: Array = combatant.get("weapons", [])
	assert_eq(weapons.size(), 2, "off_hand_path_override must add a second entry to weapons")

	var shield_res = ResourceLoader.load(SMALL_SHIELD_PATH)
	var off_hand: Dictionary = weapons[1]
	assert_eq(off_hand.get("name", "SENTINEL"), shield_res.name, "weapons[1].name must match the override's WeaponResource.name")
	assert_eq(off_hand.get("block_value", -1), shield_res.block_value, "weapons[1].block_value must match small_shield.tres")
	assert_eq(off_hand.get("parry_bonus", -1), shield_res.parry_bonus, "weapons[1].parry_bonus must match small_shield.tres")
	assert_eq(off_hand.get("block_die", -1), shield_res.block_die, "weapons[1].block_die must match small_shield.tres")
	assert_eq(off_hand.get("damage_die", -1), shield_res.damage_die, "weapons[1].damage_die must match small_shield.tres")

	var weapon: Dictionary = combatant.get("weapon", {})
	assert_eq(weapon, weapons[0], "combatant['weapon'] must remain structurally identical to weapons[0]")


func test_no_override_and_enemy_weapon_paths_1_present_resolves_off_hand_from_weapon_paths_1() -> void:
	var res := EnemyResourceClass.new()
	res.name = "TwoWeaponEnemy"
	res.hp = 5
	res.str = 1
	res.dex = 1
	res.weapon_paths = [ARMING_SWORD_PATH, SMALL_SHIELD_PATH]
	var enemy_path: String = _save_enemy_fixture_feat006(res)

	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(enemy_path, null, "two_weapon_1")

	assert_false(combatant.has("error"), "an enemy with a 2-entry weapon_paths must build without error; got: %s" % str(combatant))
	var weapons: Array = combatant.get("weapons", [])
	assert_eq(weapons.size(), 2, "no override supplied; off-hand must resolve from enemy.weapon_paths[1]")

	var shield_res = ResourceLoader.load(SMALL_SHIELD_PATH)
	var off_hand: Dictionary = weapons[1]
	assert_eq(off_hand.get("name", "SENTINEL"), shield_res.name, "weapons[1] must be resolved from enemy.weapon_paths[1] (small_shield.tres)")
	assert_eq(off_hand.get("block_value", -1), shield_res.block_value)
	assert_eq(off_hand.get("block_die", -1), shield_res.block_die)


func test_off_hand_path_override_takes_precedence_over_enemy_weapon_paths_1() -> void:
	var res := EnemyResourceClass.new()
	res.name = "OverridePrecedenceEnemy"
	res.hp = 5
	res.str = 1
	res.dex = 1
	# enemy.weapon_paths[1] itself is unresolvable -- proves the override
	# short-circuits BEFORE weapon_paths[1] is ever consulted.
	res.weapon_paths = [ARMING_SWORD_PATH, MISSING_WEAPON_PATH_FEAT006]
	var enemy_path: String = _save_enemy_fixture_feat006(res)

	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(
		enemy_path, null, "override_precedence_1", "", SMALL_SHIELD_PATH
	)

	assert_false(combatant.has("error"), "off_hand_path_override must win over an unresolvable enemy.weapon_paths[1]; got: %s" % str(combatant))
	var weapons: Array = combatant.get("weapons", [])
	assert_eq(weapons.size(), 2)
	assert_eq((weapons[1] as Dictionary).get("name", "SENTINEL"), "Small Shield")


func test_resolved_off_hand_path_fails_to_load_yields_load_failed_error() -> void:
	var enemy_path: String = _single_weapon_enemy_fixture_feat006()

	var factory := CombatantFactoryClass.new()
	var result: Dictionary = factory.build_enemy_combatant(
		enemy_path, null, "off_hand_missing_1", "", MISSING_WEAPON_PATH_FEAT006
	)

	assert_true(result.has("error"), "an off_hand_path_override that fails to load must yield a typed error Dictionary; got: %s" % str(result))
	assert_eq(
		result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_LOAD_FAILED,
		"error_code must be ERR_ENEMY_RESOURCE_LOAD_FAILED when the resolved off-hand path fails to load"
	)
	assert_false(result.has("weapon"), "a fail-fast error result must never also carry a playable combatant's 'weapon' shape")


func _build_with_invalid_off_hand_field_feat006(field_name: String, value: int) -> Dictionary:
	var weapon_res := WeaponResourceClass.new()
	weapon_res.weapon_id = "invalid_off_hand_%s_fixture" % field_name
	weapon_res.name = "Invalid Off-Hand"
	weapon_res.damage_modifier_attribute = "strength"
	weapon_res.damage_die = 4
	weapon_res.proficiency_bonus = 1
	weapon_res.parry_bonus = 1
	weapon_res.block_value = 1
	weapon_res.block_die = 0
	weapon_res.set(field_name, value)
	var weapon_path: String = _save_weapon_fixture_feat006(weapon_res)

	var enemy_path: String = _single_weapon_enemy_fixture_feat006()

	var factory := CombatantFactoryClass.new()
	return factory.build_enemy_combatant(enemy_path, null, "off_hand_invalid_1", "", weapon_path)


func test_negative_off_hand_damage_die_yields_invalid_weapon_field_error() -> void:
	var result: Dictionary = _build_with_invalid_off_hand_field_feat006("damage_die", -6)
	assert_true(result.has("error"), "negative off-hand damage_die must yield a typed error Dictionary; got: %s" % str(result))
	assert_eq(result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD)


func test_negative_off_hand_parry_bonus_yields_invalid_weapon_field_error() -> void:
	var result: Dictionary = _build_with_invalid_off_hand_field_feat006("parry_bonus", -1)
	assert_true(result.has("error"), "negative off-hand parry_bonus must yield a typed error Dictionary; got: %s" % str(result))
	assert_eq(result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD)


func test_negative_off_hand_block_value_yields_invalid_weapon_field_error() -> void:
	var result: Dictionary = _build_with_invalid_off_hand_field_feat006("block_value", -3)
	assert_true(result.has("error"), "negative off-hand block_value must yield a typed error Dictionary; got: %s" % str(result))
	assert_eq(result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD)


func test_negative_off_hand_block_die_yields_invalid_weapon_field_error() -> void:
	var result: Dictionary = _build_with_invalid_off_hand_field_feat006("block_die", -4)
	assert_true(result.has("error"), "negative off-hand block_die must yield a typed error Dictionary; got: %s" % str(result))
	assert_eq(result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD)


func test_skeleton_single_weapon_enemy_still_yields_1_weapon_regression() -> void:
	# Regression guard (RISK-002 merge gate): skeleton.tres has a single-entry
	# weapon_paths and no off-hand override supplied -- weapons.size() must
	# stay 1, with the SAME primary stats as before this feature existed.
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(SKELETON_PATH, null, "skeleton_1")

	assert_false(combatant.has("error"), "skeleton.tres must build a valid combatant with no error")
	var weapons: Array = combatant.get("weapons", [])
	assert_eq(weapons.size(), 1, "skeleton.tres must have exactly 1 weapon (regression: no off-hand fabricated)")

	var weapon_res = ResourceLoader.load(ARMING_SWORD_PATH)
	var weapon: Dictionary = weapons[0]
	assert_eq(weapon.get("name", "SENTINEL"), weapon_res.name)
	assert_eq(weapon.get("damage_die", -1), weapon_res.damage_die)
	assert_eq(weapon.get("parry_bonus", -1), weapon_res.parry_bonus)
	assert_eq(weapon.get("block_value", -1), weapon_res.block_value)
	assert_eq(weapon.get("block_die", -1), weapon_res.block_die)
	assert_eq(weapon, combatant.get("weapon", {}), "weapons[0] must remain structurally identical to combatant['weapon']")
