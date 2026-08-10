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
##   3. The underlying parry_bonus/block_value/block_die/damage_die/
##      damage_modifier_attribute values driving that eligibility match the
##      Arming Sword table (parry_bonus==4, block_value==2, block_die==0,
##      damage_die==6, damage_modifier_attribute=='strength').
##
## FEAT-390 (root-cause fix for the pre-remediation 11-test GUT full-suite
## regression, NFR-002/PR-003): the design notes for that iteration
## hypothesized this suite's production seam (infrastructure/
## combatant_factory.gd's weapon-resolution precedence) as a LIKELY fault
## location for the 11 unexpected failures captured in
## .test-output/full_gut_run.log and .test-output/def001_gate_captured_
## output.log. Triage of those two artifacts found the 11 failing tests
## were actually test_encounter_round_loop.gd, test_round_events.gd,
## test_encounter_multiround_balance_smoke.gd,
## test_encounter_no_hang_typed_events_smoke.gd, tests/sim/test_determinism.gd,
## and tests/integration/test_encounter_resource_pipeline_e2e.gd
## (round_history budget_remaining off-by-one, DRAW-instead-of-won/lost
## outcomes, missing combatant_defeated/terminal encounter_result events, and
## a missing combatant_id key in EncounterResultEvent.to_dict()) -- NONE of
## which touch weapon resolution, the weapon/weapons alias, or per-slot
## override wiring. The actual root cause was a GUT test-discovery basename
## collision (tests/unit/test_weapon_resource_data.gd vs
## tests/unit/data/weapons/test_weapon_resource_data.gd) that corrupted
## unrelated cross-test state during a full `--gut-run-all` pass; it was
## fixed by renaming the colliding file (FEAT-388, DEF-002) with no
## production-code changes anywhere. This suite (and
## infrastructure/combatant_factory.gd / core/domain/combatant.gd) were
## re-verified defect-free and required NO changes for FEAT-390 -- the two
## assertions added to test_skeleton_defense_values_match_arming_sword_table_
## on_real_boot() below (damage_die/damage_modifier_attribute) close the
## small residual gap so this file alone now proves ALL FIVE Arming Sword
## values FEAT-390's acceptance criteria name, end to end through the real
## boot path.

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

	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")

	var weapon: Dictionary = skeleton.weapon
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

	var skeleton = instance._enemies[0]
	var weapon: Dictionary = skeleton.weapon
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

	var skeleton = instance._enemies[0]
	var weapon: Dictionary = skeleton.weapon
	assert_eq(weapon.get("parry_bonus", 0), 4, "the live Skeleton's parry_bonus must be 4 (Arming Sword table)")
	assert_eq(weapon.get("block_value", 0), 2, "the live Skeleton's block_value must be 2 (Arming Sword table)")
	assert_eq(weapon.get("block_die", -1), 0, "the live Skeleton's block_die must be 0 (unset, falls back to damage_die)")
	# FEAT-390: close the residual gap flagged by that iteration's exit-point
	# criteria -- damage_die/damage_modifier_attribute were already proven via
	# CombatantFactory directly (tests/unit/infrastructure/
	# test_build_enemy_combatant_weapon_defense.gd) but not through this
	# boot-real MainScene seam. Asserted here too so this single file proves
	# all five Arming Sword values end to end.
	assert_eq(weapon.get("damage_die", -1), 6, "the live Skeleton's damage_die must be 6 (Arming Sword table)")
	assert_eq(weapon.get("damage_modifier_attribute", ""), "strength", "the live Skeleton's damage_modifier_attribute must be 'strength' (Arming Sword table)")
