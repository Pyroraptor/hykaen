extends GutTest
## tests/integration/test_build_enemy_combatant_validation.gd
##
## GUT suite for FEAT-227 (US-001 / FR-001, resolves FIND-223): MainScene.gd's
## _build_enemy_combatant() previously called ResourceLoader.load(enemy_path)
## with NO null check, and read weapon fields (damage_die, proficiency_bonus,
## parry_bonus, block_value, block_die) with no range/sanity validation --
## contrary to this project's fail-fast-at-load design (see
## data/enemies/enemy_resource.gd's ADR-104 doc and
## core/application/reaction_window.gd's assert_reaction_budget_delta() for
## this project's established fail-fast idiom). A missing or malformed
## EnemyResource silently produced either a hard engine crash reaching into
## a null Resource's fields, or a "dead on arrival" combatant carrying
## phantom/negative weapon stats -- exactly the failure mode this feature
## closes.
##
## _build_enemy_combatant() now returns a typed error Dictionary
## ({"error": <ERR_ code>, "enemy_path": ...}) instead of a valid combatant
## shape whenever the EnemyResource fails to load or its weapon data is
## malformed, in addition to firing assert()+push_error() for defense in
## depth at the call site (this project's Godot 4.3 engine cannot reliably
## capture assert()/push_error() output from GUT, so this suite asserts on
## the returned "error" key directly, exactly the same convention already
## established by core/application/tests/test_reaction_budget_gate.gd's
## RoundSession.get_reaction_budget_violations() pattern).
##
## Malformed-resource fixtures are constructed at runtime via
## ResourceSaver.save() to a user:// path (mirrors
## tests/unit/test_enemy_resource_fields.gd's established round-trip
## fixture convention) since EnemyResource is only ever loaded from a
## Resource path, never handed to _build_enemy_combatant() as an in-memory
## instance.
##
## FEAT-002 (US-002, ADR-001/ADR-002): weapon data moved off EnemyResource
## (the removed inline `weapon: Dictionary` + parry_bonus/block_value/
## block_die fields) onto weapon_paths: Array, a list of res:// paths to a
## normalized WeaponResource. Malformed-weapon-data fixtures below now
## build a WeaponResource fixture (saved to its OWN user:// path via
## _save_weapon_fixture()) carrying the malformed field, and point the
## EnemyResource fixture's weapon_paths at it — rather than setting the
## (now-removed) fields directly on the EnemyResource.
##
## Test criteria covered:
##   1. test_missing_enemy_resource_path_raises_fail_fast_error
##   2. test_malformed_enemy_resource_missing_weapon_id_raises_error
##   3. test_negative_damage_die_raises_error
##   4. test_valid_skeleton_tres_still_loads_and_builds_combatant_unchanged
##      (regression)

const MainSceneClass = preload("res://MainScene.gd")
const EnemyResourceClass = preload("res://data/enemies/enemy_resource.gd")
const WeaponResourceClass = preload("res://core/model/weapon_resource.gd")

const SKELETON_TRES_PATH := "res://data/enemies/skeleton.tres"
const MISSING_TRES_PATH := "res://data/enemies/does_not_exist_feat_227.tres"
const FIXTURE_TRES_PATH := "user://test_build_enemy_combatant_validation_fixture.tres"
const WEAPON_FIXTURE_TRES_PATH := "user://test_build_enemy_combatant_validation_weapon_fixture.tres"

var _instance = null


func before_each() -> void:
	_instance = MainSceneClass.new()


func after_each() -> void:
	if _instance != null:
		_instance.free()
	_instance = null

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(FIXTURE_TRES_PATH)
		cleanup_dir.remove(WEAPON_FIXTURE_TRES_PATH)


## Saves `res` to FIXTURE_TRES_PATH and returns that path, forcing a
## fresh-from-disk load path so _build_enemy_combatant() genuinely exercises
## ResourceLoader.load() (mirrors tests/unit/test_enemy_resource_fields.gd's
## round-trip fixture convention).
func _save_fixture(res: EnemyResourceClass) -> String:
	var save_err := ResourceSaver.save(res, FIXTURE_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for this test's fixture EnemyResource")
	return FIXTURE_TRES_PATH


## Saves `res` (a WeaponResource) to WEAPON_FIXTURE_TRES_PATH and returns
## that path, so a malformed-weapon-field fixture is genuinely resolved
## through ResourceLoader.load() from disk, exactly like a real weapon_paths
## entry (mirrors _save_fixture() above).
func _save_weapon_fixture(res: WeaponResourceClass) -> String:
	var save_err := ResourceSaver.save(res, WEAPON_FIXTURE_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for this test's fixture WeaponResource")
	return WEAPON_FIXTURE_TRES_PATH


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: a missing/unresolvable enemy_path must fail fast, never
# crash on a null Resource.
# ══════════════════════════════════════════════════════════════════════════

func test_missing_enemy_resource_path_raises_fail_fast_error() -> void:
	var result: Dictionary = _instance._build_enemy_combatant(MISSING_TRES_PATH, null, "ghost_1")

	assert_true(
		result.has("error"),
		"a missing EnemyResource path must yield a typed error Dictionary, not a crash or a bogus combatant; got: %s" % str(result)
	)
	assert_false(
		result.has("weapon"),
		"a fail-fast error result must never also carry a playable combatant's 'weapon' shape"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: a malformed EnemyResource with no resolvable weapon data
# (an empty weapon_paths Array -- no weapon ever authored/resolved) must
# fail fast rather than silently defaulting to a phantom weapon.
# ══════════════════════════════════════════════════════════════════════════

func test_malformed_enemy_resource_missing_weapon_id_raises_error() -> void:
	var res := EnemyResourceClass.new()
	res.name = "Malformed"
	res.hp = 5
	res.str = 1
	res.dex = 1
	res.weapon_paths = []
	var path: String = _save_fixture(res)

	var result: Dictionary = _instance._build_enemy_combatant(path, null, "malformed_1")

	assert_true(
		result.has("error"),
		"an EnemyResource with no resolvable weapon data must yield a typed error Dictionary; got: %s" % str(result)
	)
	assert_false(
		result.has("weapon"),
		"a fail-fast error result must never also carry a playable combatant's 'weapon' shape"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: a negative damage_die is a genuine data error and must fail
# fast rather than being threaded silently into a Strike's damage roll.
# ══════════════════════════════════════════════════════════════════════════

func test_negative_damage_die_raises_error() -> void:
	var weapon_res := WeaponResourceClass.new()
	weapon_res.weapon_id = "negative_die_fixture"
	weapon_res.damage_modifier_attribute = "strength"
	weapon_res.damage_die = -6
	weapon_res.proficiency_bonus = 2
	weapon_res.parry_bonus = 1
	weapon_res.block_value = 1
	weapon_res.block_die = 0
	var weapon_path: String = _save_weapon_fixture(weapon_res)

	var res := EnemyResourceClass.new()
	res.name = "NegativeDie"
	res.hp = 5
	res.str = 1
	res.dex = 1
	res.weapon_paths = [weapon_path]
	var path: String = _save_fixture(res)

	var result: Dictionary = _instance._build_enemy_combatant(path, null, "negative_die_1")

	assert_true(
		result.has("error"),
		"a negative damage_die must yield a typed error Dictionary; got: %s" % str(result)
	)


func test_negative_proficiency_bonus_raises_error() -> void:
	var weapon_res := WeaponResourceClass.new()
	weapon_res.weapon_id = "negative_proficiency_fixture"
	weapon_res.damage_modifier_attribute = "strength"
	weapon_res.damage_die = 6
	weapon_res.proficiency_bonus = -2
	var weapon_path: String = _save_weapon_fixture(weapon_res)

	var res := EnemyResourceClass.new()
	res.name = "NegativeProficiency"
	res.hp = 5
	res.str = 1
	res.dex = 1
	res.weapon_paths = [weapon_path]
	var path: String = _save_fixture(res)

	var result: Dictionary = _instance._build_enemy_combatant(path, null, "negative_prof_1")

	assert_true(
		result.has("error"),
		"a negative proficiency_bonus must yield a typed error Dictionary; got: %s" % str(result)
	)


func test_negative_block_value_raises_error() -> void:
	var weapon_res := WeaponResourceClass.new()
	weapon_res.weapon_id = "negative_block_fixture"
	weapon_res.damage_modifier_attribute = "strength"
	weapon_res.damage_die = 6
	weapon_res.proficiency_bonus = 1
	weapon_res.block_value = -3
	var weapon_path: String = _save_weapon_fixture(weapon_res)

	var res := EnemyResourceClass.new()
	res.name = "NegativeBlock"
	res.hp = 5
	res.str = 1
	res.dex = 1
	res.weapon_paths = [weapon_path]
	var path: String = _save_fixture(res)

	var result: Dictionary = _instance._build_enemy_combatant(path, null, "negative_block_1")

	assert_true(
		result.has("error"),
		"a negative block_value must yield a typed error Dictionary; got: %s" % str(result)
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (regression): the real skeleton.tres fixture must still load
# and build a combatant unchanged -- fail-fast validation must never
# false-positive on genuinely well-formed data.
# ══════════════════════════════════════════════════════════════════════════

func test_valid_skeleton_tres_still_loads_and_builds_combatant_unchanged() -> void:
	var combatant: Dictionary = _instance._build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")

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
