extends GutTest
## tests/unit/test_enemy_resource_fields.gd
##
## GUT unit tests for FEAT-001 (ADR-104 / FR-006): defense and attribute
## fields on data/enemies/enemy_resource.gd.
##
## Adds @export int fields — ac, fortitude, reflex, will, constitution,
## intuition, willpower, social, intellect — to EnemyResource. These are
## AUTHORED values (set directly on the .tres), never derived/recomputed
## from other fields at load time.
##
## Test criteria covered:
##   1. All nine new @export int fields exist and default sanely (0).
##   2. Round-trip save/load: setting each field and reloading the
##      resource preserves the values exactly.
##   3. No formula recomputation of ac/fortitude/reflex/will occurs on
##      resource load — values are static reads, not computed from
##      attributes.

const EnemyResource = preload("res://data/enemies/enemy_resource.gd")

const NEW_FIELDS := [
	"ac", "fortitude", "reflex", "will",
	"constitution", "intuition", "willpower", "social", "intellect",
]

const ROUND_TRIP_TRES_PATH := "user://test_enemy_resource_fields_round_trip.tres"


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: all nine new @export int fields exist and default sanely
# ══════════════════════════════════════════════════════════════════════════════

func test_all_nine_new_fields_exist_with_zero_default() -> void:
	var res := EnemyResource.new()
	for field_name in NEW_FIELDS:
		assert_true(
			field_name in res,
			"EnemyResource must expose a '%s' field" % field_name
		)
		assert_eq(
			res.get(field_name), 0,
			"EnemyResource.%s must default sanely to 0; got: %s" % [field_name, str(res.get(field_name))]
		)


func test_new_fields_are_typed_as_int() -> void:
	var res := EnemyResource.new()
	for field_name in NEW_FIELDS:
		res.set(field_name, 5)
		assert_eq(
			typeof(res.get(field_name)), TYPE_INT,
			"EnemyResource.%s must be typed as int" % field_name
		)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: round-trip save/load preserves every field exactly
# ══════════════════════════════════════════════════════════════════════════════

func test_round_trip_save_load_preserves_all_nine_fields() -> void:
	var res := EnemyResource.new()
	res.name = "RoundTripFixture"
	res.hp = 11
	res.str = 3
	res.dex = 2
	res.ac = 14
	res.fortitude = 5
	res.reflex = 3
	res.will = 4
	res.constitution = 2
	res.intuition = 1
	res.willpower = 0
	res.social = -1
	res.intellect = 1

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for round-trip fixture")

	# Force a fresh load from disk rather than returning a cached instance.
	ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)

	assert_not_null(reloaded, "Round-trip fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.ac, 14, "ac must round-trip exactly; got: %d" % reloaded.ac)
	assert_eq(reloaded.fortitude, 5, "fortitude must round-trip exactly; got: %d" % reloaded.fortitude)
	assert_eq(reloaded.reflex, 3, "reflex must round-trip exactly; got: %d" % reloaded.reflex)
	assert_eq(reloaded.will, 4, "will must round-trip exactly; got: %d" % reloaded.will)
	assert_eq(reloaded.constitution, 2, "constitution must round-trip exactly; got: %d" % reloaded.constitution)
	assert_eq(reloaded.intuition, 1, "intuition must round-trip exactly; got: %d" % reloaded.intuition)
	assert_eq(reloaded.willpower, 0, "willpower must round-trip exactly; got: %d" % reloaded.willpower)
	assert_eq(reloaded.social, -1, "social must round-trip exactly; got: %d" % reloaded.social)
	assert_eq(reloaded.intellect, 1, "intellect must round-trip exactly; got: %d" % reloaded.intellect)

	# Pre-existing fields must be untouched by this feature.
	assert_eq(reloaded.name, "RoundTripFixture")
	assert_eq(reloaded.hp, 11)
	assert_eq(reloaded.str, 3)
	assert_eq(reloaded.dex, 2)

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: no formula recomputation — defenses are static authored reads
# ══════════════════════════════════════════════════════════════════════════════

func test_defenses_are_not_recomputed_from_attributes_on_load() -> void:
	# Author defense values that deliberately do NOT match any plausible
	# derivation from the attribute fields, save, reload, and confirm the
	# authored defense values survive untouched — proving load performs a
	# static read, not a formula recomputation.
	var res := EnemyResource.new()
	res.constitution = 20
	res.intuition = 20
	res.willpower = 20
	res.ac = 1
	res.fortitude = 1
	res.reflex = 1
	res.will = 1

	var save_err := ResourceSaver.save(res, ROUND_TRIP_TRES_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for formula-independence fixture")

	var reloaded = ResourceLoader.load(ROUND_TRIP_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(reloaded, "Formula-independence fixture must reload from disk")
	if reloaded == null:
		return

	assert_eq(reloaded.ac, 1, "ac must remain the authored value regardless of high attributes")
	assert_eq(reloaded.fortitude, 1, "fortitude must remain the authored value regardless of high attributes")
	assert_eq(reloaded.reflex, 1, "reflex must remain the authored value regardless of high attributes")
	assert_eq(reloaded.will, 1, "will must remain the authored value regardless of high attributes")

	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ROUND_TRIP_TRES_PATH)


func test_enemy_resource_gd_has_no_defense_formula_logic() -> void:
	# Static guard: enemy_resource.gd must contain no functions (which would
	# indicate derived/computed defenses) — it is pure @export data.
	var file := FileAccess.open("res://data/enemies/enemy_resource.gd", FileAccess.READ)
	assert_not_null(file, "data/enemies/enemy_resource.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("func "),
		"enemy_resource.gd must contain no functions — defenses/attributes are authored data, not computed (ADR-104)"
	)
