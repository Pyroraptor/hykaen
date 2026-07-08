extends GutTest
## tests/unit/test_skills_dictionary.gd
##
## GUT unit tests for FEAT-002 (US-006 / FR-007): extensible skills
## dictionary on CharacterResource / EnemyResource.
##
## Adds a `skills: Dictionary` field — kept SEPARATE from `attributes`
## (3NF: skills and attributes are independent attribute sets of the same
## resource, not a repeating group within one dict). The missing-key-
## defaults-to-0 "accessor" is the standard `skills.get(key, 0)` pattern
## already used elsewhere in this codebase to read `attributes` (see
## test_titus_character.gd's `attributes.get("strength", -1)`), not a
## bespoke method — both CharacterResource and EnemyResource are meant to
## carry zero business logic (ADR-104's guard on enemy_resource.gd
## explicitly forbids adding functions there). This is the data-layer
## prerequisite for skill-based reaction/defense checks (Dodge/Steel,
## FEAT-007); no reaction/check logic is implemented here.
##
## Test criteria covered:
##   1. skills dictionary accessor (skills.get(key, 0)) returns 0 for
##      missing keys (both CharacterResource and EnemyResource).
##   2. Titus resource resolves skills.mobility=2, skills.determination=2.
##   3. skeleton.tres resolves skills.mobility=1, skills.determination=1.
##   4. attributes.gd REQUIRED_KEYS validation test still passes unaffected
##      (the skills dictionary must not interfere with point_buy_validate,
##      which only ever inspects `attributes`, never `skills`).

const CharacterResource = preload("res://core/model/character_resource.gd")
const EnemyResource      = preload("res://data/enemies/enemy_resource.gd")
const AttributesClass    = preload("res://core/rules/attributes.gd")
const RNGClass           = preload("res://core/rules/rng.gd")

const TITUS_TRES_PATH    := "res://data/characters/titus.tres"
const SKELETON_TRES_PATH := "res://data/enemies/skeleton.tres"


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: missing-key-defaults-to-0 accessor
# ══════════════════════════════════════════════════════════════════════════════

func test_character_resource_skills_get_returns_zero_for_missing_key() -> void:
	var res := CharacterResource.new()
	assert_eq(
		res.skills.get("mobility", 0), 0,
		"CharacterResource.skills.get(key, 0) must default a missing key to 0"
	)


func test_character_resource_skills_get_returns_set_value() -> void:
	var res := CharacterResource.new()
	res.skills = {"mobility": 3}
	assert_eq(
		res.skills.get("mobility", 0), 3,
		"CharacterResource.skills.get() must return the authored value when present"
	)


func test_enemy_resource_skills_get_returns_zero_for_missing_key() -> void:
	var res := EnemyResource.new()
	assert_eq(
		res.skills.get("determination", 0), 0,
		"EnemyResource.skills.get(key, 0) must default a missing key to 0"
	)


func test_enemy_resource_skills_get_returns_set_value() -> void:
	var res := EnemyResource.new()
	res.skills = {"determination": 5}
	assert_eq(
		res.skills.get("determination", 0), 5,
		"EnemyResource.skills.get() must return the authored value when present"
	)


func test_character_resource_skills_field_defaults_to_empty_dictionary() -> void:
	var res := CharacterResource.new()
	assert_eq(
		typeof(res.skills), TYPE_DICTIONARY,
		"CharacterResource.skills must be typed as a Dictionary"
	)
	assert_eq(res.skills.size(), 0, "CharacterResource.skills must default to an empty dictionary")


func test_enemy_resource_skills_field_defaults_to_empty_dictionary() -> void:
	var res := EnemyResource.new()
	assert_eq(
		typeof(res.skills), TYPE_DICTIONARY,
		"EnemyResource.skills must be typed as a Dictionary"
	)
	assert_eq(res.skills.size(), 0, "EnemyResource.skills must default to an empty dictionary")


## skills must be a dictionary distinct from attributes — setting one must
## never leak into or overwrite the other.
func test_skills_dictionary_is_distinct_from_attributes() -> void:
	var res := CharacterResource.new()
	res.attributes = {"strength": 5}
	res.skills = {"mobility": 2}
	assert_false(res.attributes.has("mobility"), "attributes must not contain skill keys")
	assert_false(res.skills.has("strength"), "skills must not contain attribute keys")


## enemy_resource.gd must remain pure @export data — this feature must not
## introduce any function (ADR-104 static guard, see
## test_enemy_resource_fields.gd's own copy of this assertion).
func test_enemy_resource_gd_still_has_no_functions() -> void:
	var file := FileAccess.open("res://data/enemies/enemy_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/enemies/enemy_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("func "),
		"enemy_resource.gd must still contain no functions after adding skills — pure data only (ADR-104)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: Titus resource resolves skills.mobility=2, skills.determination=2
# ══════════════════════════════════════════════════════════════════════════════

func test_titus_skills_mobility_is_2() -> void:
	var titus = ResourceLoader.load(TITUS_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(titus, "titus.tres must load")
	if titus == null:
		return
	assert_eq(titus.skills.get("mobility", 0), 2, "titus skills.mobility must be 2")


func test_titus_skills_determination_is_2() -> void:
	var titus = ResourceLoader.load(TITUS_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(titus, "titus.tres must load")
	if titus == null:
		return
	assert_eq(titus.skills.get("determination", 0), 2, "titus skills.determination must be 2")


func test_titus_skills_missing_key_defaults_to_zero() -> void:
	var titus = ResourceLoader.load(TITUS_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(titus, "titus.tres must load")
	if titus == null:
		return
	assert_eq(
		titus.skills.get("nonexistent_skill", 0), 0,
		"titus.skills.get() of an unauthored skill must default to 0"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: skeleton.tres resolves skills.mobility=1, skills.determination=1
# ══════════════════════════════════════════════════════════════════════════════

func test_skeleton_skills_mobility_is_1() -> void:
	var skeleton = ResourceLoader.load(SKELETON_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(skeleton, "skeleton.tres must load")
	if skeleton == null:
		return
	assert_eq(skeleton.skills.get("mobility", 0), 1, "skeleton skills.mobility must be 1")


func test_skeleton_skills_determination_is_1() -> void:
	var skeleton = ResourceLoader.load(SKELETON_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(skeleton, "skeleton.tres must load")
	if skeleton == null:
		return
	assert_eq(skeleton.skills.get("determination", 0), 1, "skeleton skills.determination must be 1")


func test_skeleton_skills_missing_key_defaults_to_zero() -> void:
	var skeleton = ResourceLoader.load(SKELETON_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(skeleton, "skeleton.tres must load")
	if skeleton == null:
		return
	assert_eq(
		skeleton.skills.get("nonexistent_skill", 0), 0,
		"skeleton.skills.get() of an unauthored skill must default to 0"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: attributes.gd REQUIRED_KEYS validation test still passes unaffected
# ══════════════════════════════════════════════════════════════════════════════

## Guards against a regression where adding `skills` to the .tres files or
## resource scripts accidentally perturbs the unrelated `attributes`
## Dictionary consumed by Attributes.point_buy_validate().
func test_titus_point_buy_validate_still_valid_after_skills_addition() -> void:
	var titus = ResourceLoader.load(TITUS_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(titus, "titus.tres must load")
	if titus == null:
		return
	var rng = RNGClass.new(0)
	var attrs = AttributesClass.new(rng)
	var result = attrs.point_buy_validate(titus.attributes)
	assert_true(
		result["valid"],
		"point_buy_validate(titus.attributes) must still return {valid: true} after adding skills"
	)


func test_attributes_required_keys_unchanged() -> void:
	assert_eq(
		AttributesClass.REQUIRED_KEYS,
		["strength", "constitution", "dexterity", "willpower", "intellect", "intuition", "social"],
		"Attributes.REQUIRED_KEYS must remain the seven canonical attribute keys — skills must not be merged into it"
	)
