extends GutTest
## tests/unit/test_enemy_resource_weapon_defense_fields.gd
##
## GUT unit tests for FEAT-001 (US-001, iteration K): defensive weapon data
## on data/enemies/enemy_resource.gd — parry_bonus, block_value, block_die
## fields mirroring core/model/weapon_resource.gd's own fields of the same
## name, plus the Arming Sword table now authored onto skeleton.tres.
##
## Steel-thread entry precondition: the Skeleton must carry real, non-zero
## defensive weapon stats before any Parry/Block reaction can occur (see
## core/rules/resolution.gd's is_parry_eligible()/is_block_eligible(),
## which read weapon.get("parry_bonus", 0) > 0 / weapon.get("block_value", 0)
## > 0). Previously EnemyResource had no such fields at all, so every enemy
## weapon Dictionary built by MainScene.gd's _build_enemy_combatant()
## silently read 0 for both — this feature closes that gap at the data
## layer.
##
## Test criteria covered:
##   1. EnemyResource exposes parry_bonus, block_value, block_die fields,
##      each defaulting to 0 and typed as int.
##   2. skeleton.tres is authored to the Arming Sword table: damage_die=6
##      (enemy.weapon.die), proficiency_bonus=2 (enemy.weapon.
##      proficiency_bonus), block_value=2, parry_bonus=4, block_die=0,
##      damage_modifier_attribute=strength (enemy.weapon.attribute=="str").
##   3. enemy_resource.gd remains pure @export data — no functions (ADR-104).

const EnemyResource = preload("res://data/enemies/enemy_resource.gd")
const SKELETON_TRES_PATH := "res://data/enemies/skeleton.tres"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: EnemyResource exposes parry_bonus/block_value/block_die,
# each int-typed and defaulting to 0.
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_resource_exposes_parry_bonus_block_value_block_die() -> void:
	var res := EnemyResource.new()
	for field_name in ["parry_bonus", "block_value", "block_die"]:
		assert_true(
			field_name in res,
			"EnemyResource must expose a '%s' field (FEAT-001, mirrors WeaponResource)" % field_name
		)
		assert_eq(
			res.get(field_name), 0,
			"EnemyResource.%s must default to 0; got: %s" % [field_name, str(res.get(field_name))]
		)


func test_enemy_resource_defense_fields_are_typed_int() -> void:
	var res := EnemyResource.new()
	for field_name in ["parry_bonus", "block_value", "block_die"]:
		res.set(field_name, 7)
		assert_eq(
			typeof(res.get(field_name)), TYPE_INT,
			"EnemyResource.%s must be typed as int" % field_name
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: skeleton.tres is authored to the Arming Sword table.
# ══════════════════════════════════════════════════════════════════════════

func test_skeleton_tres_matches_arming_sword_table() -> void:
	var res = ResourceLoader.load(SKELETON_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return

	assert_eq(res.weapon.get("die", -1), 6, "skeleton damage_die must be 6 (Arming Sword)")
	assert_eq(res.weapon.get("proficiency_bonus", -1), 2, "skeleton proficiency_bonus must be 2 (Arming Sword)")
	assert_eq(res.weapon.get("attribute", ""), "str", "skeleton damage_modifier_attribute source must be 'str' (maps to 'strength')")
	assert_eq(res.block_value, 2, "skeleton.block_value must be 2 (Arming Sword)")
	assert_eq(res.parry_bonus, 4, "skeleton.parry_bonus must be 4 (Arming Sword)")
	assert_eq(res.block_die, 0, "skeleton.block_die must be 0 — unset, falls back to damage_die (Arming Sword)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: enemy_resource.gd remains pure @export data (ADR-104).
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_resource_gd_still_has_no_defense_formula_logic() -> void:
	var file := FileAccess.open("res://data/enemies/enemy_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/enemies/enemy_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("func "),
		"enemy_resource.gd must contain no functions — parry_bonus/block_value/block_die are authored data, not computed (ADR-104)"
	)
