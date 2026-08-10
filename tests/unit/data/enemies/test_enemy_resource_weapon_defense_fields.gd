extends GutTest
## tests/unit/data/enemies/test_enemy_resource_weapon_defense_fields.gd
##
## GUT unit tests for FEAT-002 (US-002, ADR-001/ADR-002): restructures
## data/enemies/enemy_resource.gd's weapon representation from the legacy
## inline `weapon: Dictionary` + top-level parry_bonus/block_value/
## block_die fields to a single `weapon_paths: Array = []` of res:// paths,
## each referencing a normalized WeaponResource (data/weapons/*.tres).
##
## This SUPERSEDES the old tests/unit/test_enemy_resource_weapon_defense_fields.gd
## (FEAT-001), which asserted the pre-refactor schema (parry_bonus/
## block_value/block_die living directly on EnemyResource) — that file has
## been removed as part of this feature since it exercised fields this
## feature deletes.
##
## Test criteria covered:
##   1. enemy_resource.gd contains zero 'func ' definitions (ADR-104 static
##      scan passes) — it remains pure @export data.
##   2. weapon_paths defaults to [] on a freshly instantiated EnemyResource.
##   3. An EnemyResource with weapon_paths[0] set to a valid WeaponResource
##      path (data/weapons/arming_sword.tres) resolves via ResourceLoader
##      to a WeaponResource with parry_bonus == 4 and block_value == 2.
##   4. The legacy weapon/parry_bonus/block_value/block_die fields no
##      longer exist on EnemyResource.

const EnemyResource = preload("res://data/enemies/enemy_resource.gd")
const WeaponResourceClass = preload("res://core/model/weapon_resource.gd")

const ARMING_SWORD_PATH := "res://data/weapons/arming_sword.tres"
const ENEMY_RESOURCE_SCRIPT_PATH := "res://data/enemies/enemy_resource.gd"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (ADR-104): enemy_resource.gd remains pure @export data — zero
# 'func ' definitions.
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_resource_gd_has_zero_func_definitions() -> void:
	var file := FileAccess.open(ENEMY_RESOURCE_SCRIPT_PATH, FileAccess.READ)
	assert_not_null(file, "data/enemies/enemy_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("func "),
		"enemy_resource.gd must contain no functions — weapon_paths is authored data, not computed (ADR-104)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: weapon_paths defaults to [] on a freshly instantiated
# EnemyResource.
# ══════════════════════════════════════════════════════════════════════════

func test_weapon_paths_defaults_to_empty_array() -> void:
	var res := EnemyResource.new()
	assert_true(
		"weapon_paths" in res,
		"EnemyResource must expose a 'weapon_paths' field (FEAT-002)"
	)
	assert_true(
		res.weapon_paths is Array,
		"EnemyResource.weapon_paths must be an Array; got type: %s" % typeof(res.weapon_paths)
	)
	assert_eq(
		res.weapon_paths.size(), 0,
		"EnemyResource.weapon_paths must default to an empty Array; got: %s" % str(res.weapon_paths)
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: weapon_paths[0] set to a valid WeaponResource path resolves
# via ResourceLoader to a WeaponResource with parry_bonus == 4 and
# block_value == 2 (Arming Sword table).
# ══════════════════════════════════════════════════════════════════════════

func test_weapon_paths_first_entry_resolves_to_weapon_resource_with_expected_defense_stats() -> void:
	var res := EnemyResource.new()
	res.weapon_paths = [ARMING_SWORD_PATH]

	assert_eq(
		res.weapon_paths[0], ARMING_SWORD_PATH,
		"weapon_paths[0] must round-trip the assigned path unchanged"
	)

	var weapon = ResourceLoader.load(res.weapon_paths[0])
	assert_not_null(weapon, "ResourceLoader.load(weapon_paths[0]) must return non-null")
	if weapon == null:
		return

	assert_true(
		weapon is WeaponResourceClass,
		"weapon_paths[0] must resolve to a WeaponResource instance"
	)
	assert_eq(weapon.parry_bonus, 4, "resolved WeaponResource.parry_bonus must be 4 (Arming Sword table)")
	assert_eq(weapon.block_value, 2, "resolved WeaponResource.block_value must be 2 (Arming Sword table)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: the legacy weapon Dictionary and top-level parry_bonus/
# block_value/block_die fields no longer exist on EnemyResource (ADR-001/
# ADR-002 — this feature's deletion is the point of the change).
# ══════════════════════════════════════════════════════════════════════════

func test_legacy_weapon_and_defense_fields_are_removed() -> void:
	var res := EnemyResource.new()
	for field_name in ["weapon", "parry_bonus", "block_value", "block_die"]:
		assert_false(
			field_name in res,
			"EnemyResource must NOT expose legacy field '%s' — replaced by weapon_paths (FEAT-002)" % field_name
		)
