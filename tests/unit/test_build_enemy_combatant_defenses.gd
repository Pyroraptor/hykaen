extends GutTest
## tests/unit/test_build_enemy_combatant_defenses.gd
##
## GUT unit tests for FEAT-008 (US-008 / FR-008, ADR-106): MainScene.gd's
## _build_enemy_combatant() must read ac/fortitude/reflex/will DIRECTLY from
## the loaded EnemyResource, never a hard-coded fallback constant. Previously
## _build_enemy_combatant() always set "ac" to the module-level
## DEFAULT_ENEMY_AC constant (12), completely ignoring skeleton.tres' own
## authored ac=14 — this made every Strike against a Skeleton roll against
## the wrong AC. This feature removes DEFAULT_ENEMY_AC entirely and wires the
## resource's own ac/fortitude/reflex/will fields straight through.
##
## Mirrors tests/business_logic/test_highlight_legal_moves.gd's pattern:
## a freshly `.new()`-constructed (NOT scene-tree-booted) MainScene instance,
## so private helper methods can be exercised directly without needing the
## full composition-root _ready() wiring (child nodes, etc).
##
## Test criteria covered:
##   1. DEFAULT_ENEMY_AC no longer exists on MainScene.gd (grep/compile check).
##   2. _build_enemy_combatant(skeleton.tres) yields ac == 14, fortitude == 13,
##      reflex == 12, will == 12 — the values authored on data/enemies/
##      skeleton.tres (tests/unit/test_skeleton_resource_values.gd), not any
##      hard-coded constant.

const MainSceneClass = preload("res://MainScene.gd")
const SKELETON_TRES_PATH := "res://data/enemies/skeleton.tres"

var _instance = null


func before_each() -> void:
	_instance = MainSceneClass.new()


func after_each() -> void:
	if _instance != null:
		_instance.free()
	_instance = null


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: DEFAULT_ENEMY_AC constant no longer exists on MainScene.gd.
# ══════════════════════════════════════════════════════════════════════════

func test_default_enemy_ac_constant_is_removed() -> void:
	var file := FileAccess.open("res://MainScene.gd", FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	assert_false(
		content.contains("const DEFAULT_ENEMY_AC"),
		"MainScene.gd must no longer declare a DEFAULT_ENEMY_AC constant (FEAT-008 / ADR-106)"
	)
	assert_false(
		content.contains("DEFAULT_ENEMY_AC"),
		"MainScene.gd must contain no remaining code reference to DEFAULT_ENEMY_AC at all"
	)


func test_main_scene_gd_has_no_default_enemy_ac_field() -> void:
	assert_false(
		"DEFAULT_ENEMY_AC" in _instance,
		"a freshly constructed MainScene instance must not expose a DEFAULT_ENEMY_AC member"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: _build_enemy_combatant(skeleton.tres) yields ac/fortitude/
# reflex/will sourced from the EnemyResource itself (14/13/12/12).
# ══════════════════════════════════════════════════════════════════════════

func test_build_enemy_combatant_reads_ac_from_enemy_resource() -> void:
	var combatant: Dictionary = _instance._build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")

	assert_eq(
		combatant.get("ac", -1), 14,
		"Combatant.ac must be sourced from skeleton.tres' authored ac=14, not a hard-coded constant; got: %s" % str(combatant.get("ac", -1))
	)


func test_build_enemy_combatant_reads_fortitude_reflex_will_from_enemy_resource() -> void:
	var combatant: Dictionary = _instance._build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")

	assert_eq(combatant.get("fortitude", -1), 13, "Combatant.fortitude must equal skeleton.tres' authored fortitude=13")
	assert_eq(combatant.get("reflex", -1), 12, "Combatant.reflex must equal skeleton.tres' authored reflex=12")
	assert_eq(combatant.get("will", -1), 12, "Combatant.will must equal skeleton.tres' authored will=12")


func test_build_enemy_combatant_preserves_pre_existing_fields() -> void:
	var combatant: Dictionary = _instance._build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")

	assert_eq(combatant.get("name", ""), "Skeleton")
	assert_eq(combatant.get("hp_current", -1), 8)
	assert_eq(combatant.get("hp_max", -1), 8)
	assert_eq(combatant.get("strength", -1), 2)
	assert_eq(combatant.get("dexterity", -1), 1)
	assert_eq(combatant.get("combatant_id", ""), "skeleton_1")
