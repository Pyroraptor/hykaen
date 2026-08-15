extends GutTest
## tests/unit/data/enemies/test_skeleton_ai_tier_stamina.gd
##
## GUT unit tests for FEAT-002 (US-002 / FR-002-FR-005 / ADR-004): extends
## data/enemies/enemy_resource.gd with two new authored @export fields —
## ai_tier: String (default 'mindless') and stamina_max: int (default 0) —
## and wires data/enemies/skeleton.tres to ai_tier='mindless',
## stamina_max=0. This is the steel thread's entry point: an authored
## .tres value that later features (AITierRegistry, CombatantFactory) read
## to select and configure an enemy's AI planner.
##
## Test criteria covered:
##   1. skeleton.tres loads with ai_tier == 'mindless'
##   2. skeleton.tres loads with stamina_max == 0
##   3. enemy_resource.gd exposes both fields with correct defaults for any
##      unauthored .tres (fresh EnemyResource.new())
##   4. enemy_resource.gd remains pure @export data — zero 'func '
##      definitions (ADR-104 static scan, matching sibling tests in this
##      directory)

const SKELETON_TRES_PATH := "res://data/enemies/skeleton.tres"
const ENEMY_RESOURCE_SCRIPT_PATH := "res://data/enemies/enemy_resource.gd"

const EnemyResource = preload("res://data/enemies/enemy_resource.gd")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: skeleton.tres loads with ai_tier == 'mindless'
# ══════════════════════════════════════════════════════════════════════════

func test_skeleton_ai_tier_is_mindless() -> void:
	var res = ResourceLoader.load(SKELETON_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return
	assert_eq(
		res.ai_tier, "mindless",
		"skeleton.ai_tier must be 'mindless'; got: '%s'" % str(res.ai_tier)
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: skeleton.tres loads with stamina_max == 0
# ══════════════════════════════════════════════════════════════════════════

func test_skeleton_stamina_max_is_zero() -> void:
	var res = ResourceLoader.load(SKELETON_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return
	assert_eq(
		res.stamina_max, 0,
		"skeleton.stamina_max must be 0; got: %s" % str(res.stamina_max)
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: enemy_resource.gd exposes both fields with correct defaults
# for any unauthored .tres (fresh EnemyResource.new()).
# ══════════════════════════════════════════════════════════════════════════

func test_fresh_enemy_resource_defaults_ai_tier_to_mindless() -> void:
	var res := EnemyResource.new()
	assert_true(
		"ai_tier" in res,
		"EnemyResource must expose an 'ai_tier' field (FEAT-002 / US-002)"
	)
	assert_eq(
		res.ai_tier, "mindless",
		"EnemyResource.ai_tier must default to 'mindless'; got: '%s'" % str(res.ai_tier)
	)


func test_fresh_enemy_resource_defaults_stamina_max_to_zero() -> void:
	var res := EnemyResource.new()
	assert_true(
		"stamina_max" in res,
		"EnemyResource must expose a 'stamina_max' field (FEAT-002 / US-002)"
	)
	assert_eq(
		res.stamina_max, 0,
		"EnemyResource.stamina_max must default to 0; got: %s" % str(res.stamina_max)
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (ADR-104): enemy_resource.gd remains pure @export data — zero
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
		"enemy_resource.gd must contain no functions — ai_tier/stamina_max are authored data, not computed (ADR-104)"
	)
