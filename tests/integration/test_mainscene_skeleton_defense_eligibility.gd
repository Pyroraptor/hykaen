extends GutTest
## tests/integration/test_mainscene_skeleton_defense_eligibility.gd
##
## Boot-real test for FEAT-001 (US-001, iteration K): boots the REAL
## composition root (res://MainScene.tscn) at the established prologue
## fixture seed and asserts core/rules/resolution.gd's
## is_parry_eligible()/is_block_eligible() predicates read NON-ZERO for the
## live Skeleton combatant's own weapon Dictionary -- proving, through the
## genuine composition-root wiring (not a hand-built fixture Dictionary),
## that the Skeleton now carries real defensive weapon stats. This is the
## steel-thread entry precondition this feature exists to satisfy: no
## reaction (Parry/Block) can ever be legally offered to/against the
## Skeleton until this predicate reads true.
##
## Mirrors tests/integration/test_mainscene_hit_reaction_apply.gd's
## established "boot-real-MainScene" conventions: PROLOGUE_SEED=42 (Titus
## acts first, the Skeleton starts adjacent), instantiated via
## add_child_autofree() with seed_override set BEFORE add_child() triggers
## _ready() (so no reaction-window pop-up can block this boot indefinitely).
##
## Test criteria covered:
##   1. The real, live Skeleton combatant (instance._enemies[0]) built by
##      MainScene.gd's _build_enemy_combatant() carries a "weapon"
##      Dictionary for which ResolutionClass.is_parry_eligible() is TRUE.
##   2. The same live Skeleton weapon Dictionary is ResolutionClass.
##      is_block_eligible() TRUE.
##   3. The underlying parry_bonus/block_value values driving that
##      eligibility match the Arming Sword table (4 and 2 respectively).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const ResolutionClass = preload("res://core/rules/resolution.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed: Titus
## acts first and the sole enemy (Skeleton) starts adjacent to him (see
## tests/test_mainscene_reaction_timing.gd / test_mainscene_hit_reaction_apply.gd).
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return null
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func test_skeleton_is_parry_eligible_on_real_boot() -> void:
	var instance = _boot_main_scene()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return

	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	if instance._enemies.size() == 0:
		return

	var skeleton: Dictionary = instance._enemies[0]
	assert_eq(skeleton.get("name", ""), "Skeleton", "fixture assumption: the sole enemy is the Skeleton")

	var weapon: Dictionary = skeleton.get("weapon", {})
	assert_true(
		ResolutionClass.is_parry_eligible(weapon),
		"the REAL, live Skeleton combatant's weapon dict must be Parry-eligible after boot (FEAT-001) -- got weapon: %s" % [weapon]
	)


func test_skeleton_is_block_eligible_on_real_boot() -> void:
	var instance = _boot_main_scene()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return

	if instance._enemies.size() == 0:
		fail_test("fixture assumption failed: no enemies present")
		return

	var skeleton: Dictionary = instance._enemies[0]
	var weapon: Dictionary = skeleton.get("weapon", {})
	assert_true(
		ResolutionClass.is_block_eligible(weapon),
		"the REAL, live Skeleton combatant's weapon dict must be Block-eligible after boot (FEAT-001) -- got weapon: %s" % [weapon]
	)


func test_skeleton_defense_values_match_arming_sword_table_on_real_boot() -> void:
	var instance = _boot_main_scene()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return

	if instance._enemies.size() == 0:
		fail_test("fixture assumption failed: no enemies present")
		return

	var skeleton: Dictionary = instance._enemies[0]
	var weapon: Dictionary = skeleton.get("weapon", {})
	assert_eq(weapon.get("parry_bonus", 0), 4, "the live Skeleton's parry_bonus must be 4 (Arming Sword table)")
	assert_eq(weapon.get("block_value", 0), 2, "the live Skeleton's block_value must be 2 (Arming Sword table)")
	assert_eq(weapon.get("block_die", -1), 0, "the live Skeleton's block_die must be 0 (unset, falls back to damage_die)")
