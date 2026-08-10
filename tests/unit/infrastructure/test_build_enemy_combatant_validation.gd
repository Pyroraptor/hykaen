extends GutTest
## tests/unit/infrastructure/test_build_enemy_combatant_validation.gd
##
## GUT unit tests for FEAT-006 (US-005; ADR-005/ADR-006): infrastructure/
## combatant_factory.gd's build_enemy_combatant() resolves a weapon via
## path-based precedence (weapon_path_override -> enemy.weapon_paths[0] ->
## ERR_ENEMY_RESOURCE_WEAPON_UNRESOLVABLE), loads it via ResourceLoader, and
## validates its numeric fields are non-negative -- each distinct failure
## mode returns its OWN typed error code, per this project's established
## "typed Dictionary result, no exceptions" convention (see
## infrastructure/combatant_factory.gd's _fail_enemy_resource_load() doc).
##
## Exercises CombatantFactory directly (not through the MainScene test seam)
## since weapon_path_override is a new argument on
## CombatantFactory.build_enemy_combatant() itself.
##
## Malformed-resource fixtures are constructed at runtime via
## ResourceSaver.save() to a user:// path (mirrors the now-deleted
## tests/integration/test_build_enemy_combatant_validation.gd's established
## fixture convention, merged into this file by FEAT-389) since
## EnemyResource/WeaponResource are only ever loaded from a Resource path,
## never handed to build_enemy_combatant() as an in-memory instance.
##
## Test criteria covered:
##   1. override == "" AND enemy.weapon_paths == [] -> {success: false,
##      error_code: ERR_ENEMY_RESOURCE_WEAPON_UNRESOLVABLE, ...}
##   2. resolved path fails to load (ResourceLoader.load() returns null) ->
##      {success: false, error_code: ERR_ENEMY_RESOURCE_LOAD_FAILED, ...}
##   3. any of damage_die/proficiency_bonus/parry_bonus/block_value/
##      block_die is negative on the loaded WeaponResource ->
##      {success: false, error_code: ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD,
##      ...}
##   4. (FEAT-389 merge, FEAT-227 origin) a missing/unresolvable ENEMY
##      resource path itself (as opposed to an unresolvable WEAPON path,
##      already covered by criterion 2 above) also fails fast with
##      ERR_ENEMY_RESOURCE_LOAD_FAILED. Merged from the now-deleted
##      tests/integration/test_build_enemy_combatant_validation.gd (which
##      exercised the same underlying CombatantFactory logic indirectly
##      through the MainScene test seam -- MainScene._build_enemy_combatant()
##      is a trivial delegate to CombatantFactory.build_enemy_combatant(), so
##      exercising the factory directly here is equivalent, no
##      MainScene-specific behavior lost).
##   5. (FEAT-389 merge) the regression fixture (skeleton.tres) also
##      round-trips fortitude/reflex/will/strength/dexterity/combatant_id and
##      the FULL weapon dict shape unchanged -- widened from the narrower
##      name/hp_current/ac check this suite previously carried, so no
##      assertion coverage is lost relative to the deleted duplicate above.

const CombatantFactoryClass = preload("res://infrastructure/combatant_factory.gd")
const EnemyResourceClass = preload("res://data/enemies/enemy_resource.gd")
const WeaponResourceClass = preload("res://core/model/weapon_resource.gd")

const SKELETON_TRES_PATH: String = "res://data/enemies/skeleton.tres"
const MISSING_ENEMY_PATH: String = "res://data/enemies/does_not_exist_feat_227.tres"
const MISSING_WEAPON_PATH: String = "res://data/weapons/does_not_exist_feat_006.tres"
const ENEMY_FIXTURE_PATH: String = "user://test_build_enemy_combatant_validation_enemy_fixture.tres"
const WEAPON_FIXTURE_PATH: String = "user://test_build_enemy_combatant_validation_weapon_fixture.tres"


func after_each() -> void:
	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ENEMY_FIXTURE_PATH)
		cleanup_dir.remove(WEAPON_FIXTURE_PATH)


func _save_enemy_fixture(res: EnemyResourceClass) -> String:
	var save_err := ResourceSaver.save(res, ENEMY_FIXTURE_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for this test's fixture EnemyResource")
	return ENEMY_FIXTURE_PATH


func _save_weapon_fixture(res: WeaponResourceClass) -> String:
	var save_err := ResourceSaver.save(res, WEAPON_FIXTURE_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for this test's fixture WeaponResource")
	return WEAPON_FIXTURE_PATH


func _valid_weapon_fixture(weapon_id: String) -> WeaponResourceClass:
	var weapon_res := WeaponResourceClass.new()
	weapon_res.weapon_id = weapon_id
	weapon_res.damage_modifier_attribute = "strength"
	weapon_res.damage_die = 6
	weapon_res.proficiency_bonus = 2
	weapon_res.parry_bonus = 1
	weapon_res.block_value = 1
	weapon_res.block_die = 0
	return weapon_res


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: override == "" AND enemy.weapon_paths == [] is unresolvable.
# ══════════════════════════════════════════════════════════════════════════

func test_empty_override_and_empty_weapon_paths_yields_unresolvable_error() -> void:
	var res := EnemyResourceClass.new()
	res.name = "NoWeapon"
	res.hp = 5
	res.str = 1
	res.dex = 1
	res.weapon_paths = []
	var enemy_path: String = _save_enemy_fixture(res)

	var factory := CombatantFactoryClass.new()
	var result: Dictionary = factory.build_enemy_combatant(enemy_path, null, "no_weapon_1", "")

	assert_true(
		result.has("error"),
		"empty override + empty enemy.weapon_paths must yield a typed error Dictionary; got: %s" % str(result)
	)
	assert_eq(
		result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_WEAPON_UNRESOLVABLE,
		"error_code must be ERR_ENEMY_RESOURCE_WEAPON_UNRESOLVABLE when no weapon can be resolved"
	)
	assert_false(result.has("weapon"), "a fail-fast error result must never also carry a playable combatant's 'weapon' shape")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: a resolved path that fails to load (ResourceLoader.load()
# returns null) must fail with ERR_ENEMY_RESOURCE_LOAD_FAILED -- proven via
# BOTH the override branch and the enemy.weapon_paths[0] branch.
# ══════════════════════════════════════════════════════════════════════════

func test_unresolvable_override_path_yields_load_failed_error() -> void:
	var factory := CombatantFactoryClass.new()
	var result: Dictionary = factory.build_enemy_combatant(
		SKELETON_TRES_PATH, null, "bad_override_1", MISSING_WEAPON_PATH
	)

	assert_true(
		result.has("error"),
		"a weapon_path_override that fails to load must yield a typed error Dictionary; got: %s" % str(result)
	)
	assert_eq(
		result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_LOAD_FAILED,
		"error_code must be ERR_ENEMY_RESOURCE_LOAD_FAILED when the resolved weapon path fails to load"
	)
	assert_false(result.has("weapon"), "a fail-fast error result must never also carry a playable combatant's 'weapon' shape")


func test_unresolvable_enemy_weapon_paths_entry_yields_load_failed_error() -> void:
	var res := EnemyResourceClass.new()
	res.name = "BadWeaponPath"
	res.hp = 5
	res.str = 1
	res.dex = 1
	res.weapon_paths = [MISSING_WEAPON_PATH]
	var enemy_path: String = _save_enemy_fixture(res)

	var factory := CombatantFactoryClass.new()
	var result: Dictionary = factory.build_enemy_combatant(enemy_path, null, "bad_weapon_path_1", "")

	assert_true(
		result.has("error"),
		"an enemy.weapon_paths[0] that fails to load must yield a typed error Dictionary; got: %s" % str(result)
	)
	assert_eq(
		result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_LOAD_FAILED,
		"error_code must be ERR_ENEMY_RESOURCE_LOAD_FAILED when enemy.weapon_paths[0] fails to load"
	)


func test_missing_enemy_resource_path_yields_load_failed_error() -> void:
	var factory := CombatantFactoryClass.new()
	var result: Dictionary = factory.build_enemy_combatant(MISSING_ENEMY_PATH, null, "ghost_1")

	assert_true(
		result.has("error"),
		"a missing/unresolvable EnemyResource path must yield a typed error Dictionary, not a crash or a bogus combatant; got: %s" % str(result)
	)
	assert_eq(
		result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_LOAD_FAILED,
		"error_code must be ERR_ENEMY_RESOURCE_LOAD_FAILED when the EnemyResource itself fails to load"
	)
	assert_false(result.has("weapon"), "a fail-fast error result must never also carry a playable combatant's 'weapon' shape")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: negative numeric fields on the loaded WeaponResource each
# yield ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD.
# ══════════════════════════════════════════════════════════════════════════

func _build_with_weapon_field(field_name: String, value: int) -> Dictionary:
	var weapon_res := _valid_weapon_fixture("invalid_%s_fixture" % field_name)
	weapon_res.set(field_name, value)
	var weapon_path: String = _save_weapon_fixture(weapon_res)

	var res := EnemyResourceClass.new()
	res.name = "Invalid%s" % field_name.capitalize()
	res.hp = 5
	res.str = 1
	res.dex = 1
	res.weapon_paths = [weapon_path]
	var enemy_path: String = _save_enemy_fixture(res)

	var factory := CombatantFactoryClass.new()
	return factory.build_enemy_combatant(enemy_path, null, "invalid_field_1", "")


func test_negative_damage_die_yields_invalid_weapon_field_error() -> void:
	var result: Dictionary = _build_with_weapon_field("damage_die", -6)
	assert_true(result.has("error"), "negative damage_die must yield a typed error Dictionary; got: %s" % str(result))
	assert_eq(result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD)


func test_negative_proficiency_bonus_yields_invalid_weapon_field_error() -> void:
	var result: Dictionary = _build_with_weapon_field("proficiency_bonus", -2)
	assert_true(result.has("error"), "negative proficiency_bonus must yield a typed error Dictionary; got: %s" % str(result))
	assert_eq(result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD)


func test_negative_parry_bonus_yields_invalid_weapon_field_error() -> void:
	var result: Dictionary = _build_with_weapon_field("parry_bonus", -1)
	assert_true(result.has("error"), "negative parry_bonus must yield a typed error Dictionary; got: %s" % str(result))
	assert_eq(result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD)


func test_negative_block_value_yields_invalid_weapon_field_error() -> void:
	var result: Dictionary = _build_with_weapon_field("block_value", -3)
	assert_true(result.has("error"), "negative block_value must yield a typed error Dictionary; got: %s" % str(result))
	assert_eq(result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD)


func test_negative_block_die_yields_invalid_weapon_field_error() -> void:
	var result: Dictionary = _build_with_weapon_field("block_die", -4)
	assert_true(result.has("error"), "negative block_die must yield a typed error Dictionary; got: %s" % str(result))
	assert_eq(result.get("error", ""), CombatantFactoryClass.ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD)


# ══════════════════════════════════════════════════════════════════════════
# Regression: the real skeleton.tres fixture must still build a valid
# combatant with no error.
# ══════════════════════════════════════════════════════════════════════════

func test_valid_skeleton_tres_still_builds_combatant_with_no_error() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")

	assert_false(combatant.has("error"), "a well-formed EnemyResource must never yield an error Dictionary; got: %s" % str(combatant))
	assert_eq(combatant.get("name", ""), "Skeleton")
	assert_eq(combatant.get("hp_current", -1), 8)
	assert_eq(combatant.get("hp_max", -1), 8)
	assert_eq(combatant.get("ac", -1), 14)
	assert_eq(combatant.get("fortitude", -1), 13)
	assert_eq(combatant.get("reflex", -1), 12)
	assert_eq(combatant.get("will", -1), 12)
	assert_eq(combatant.get("strength", -1), 2)
	assert_eq(combatant.get("dexterity", -1), 1)
	assert_eq(combatant.get("combatant_id", ""), "skeleton_1")

	var weapon: Dictionary = combatant.get("weapon", {})
	assert_eq(weapon.get("damage_modifier_attribute", ""), "strength")
	assert_eq(weapon.get("proficiency_bonus", -1), 2)
	assert_eq(weapon.get("damage_die", -1), 6)
	assert_eq(weapon.get("parry_bonus", -1), 4)
	assert_eq(weapon.get("block_value", -1), 2)
	assert_eq(weapon.get("block_die", -1), 0)
