extends GutTest
## tests/integration/test_steel_thread_skeleton_weapon_e2e.gd
##
## FEAT-009 (US-009): the steel thread's own capstone end-to-end integration
## test, exercising the COMPLETE slice from entry_point to exit_point in one
## flow:
##   entry_point → data/enemies/skeleton.tres authors weapon_paths ->
##     [res://data/weapons/arming_sword.tres]
##   spawn        → an EncounterResource-driven spawn slot (mirroring
##     core/application/combat_session_factory.gd's own per-slot
##     weapon_path_overrides[j] lookup, FEAT-007) resolves that slot's
##     override string, WITH and WITHOUT an authored override
##   resolve      → infrastructure/combatant_factory.gd's REAL
##     CombatantFactory.build_enemy_combatant() (no mocked ResourceLoader)
##     loads the resolved WeaponResource and builds the combatant Dictionary
##   exit_point   → the resulting core/domain/combatant.gd Combatant's
##     weapon/weapons Dictionary values, and core/rules/resolution.gd's
##     is_parry_eligible()/is_block_eligible() reaction-eligibility
##     predicates, read correctly off the resolved weapon stats
##
## This is the user-facing demoable artifact proving the full slice works
## together: a real, live res://MainScene.tscn composition root is booted
## (mirrors tests/integration/test_mainscene_skeleton_defense_eligibility.gd's
## established `_boot_main_scene()` convention — PROLOGUE_SEED=42, Titus acts
## first, the Skeleton starts adjacent, seed_override set BEFORE
## add_child_autofree() triggers _ready() so no reaction-window pop-up can
## block boot), and the same live boot's already-spawned Skeleton combatant
## is cross-checked against a direct CombatantFactory build to prove the two
## paths agree — closing the loop between "the live game spawns this" and
## "the resolution contract this test pins produces this".
##
## Test criteria covered:
##   1. mainscene boots and spawns a skeleton combatant via
##      CombatantFactory.build_enemy_combatant with NO override -> weapon
##      dict has parry_bonus==4, block_value==2, block_die==0, damage_die==6,
##      damage_modifier_attribute=='strength' (the Arming Sword table).
##   2. The same flow with an EncounterResource weapon_path_overrides entry
##      set for the skeleton's slot resolves to the OVERRIDDEN
##      WeaponResource's stats (Mace) instead of arming_sword.tres.
##   3. The spawned combatant passes parry eligibility and block eligibility
##      reaction checks (core/rules/resolution.gd) driven by the resolved
##      weapon stats, in BOTH the no-override and override cases.
##   4. combatant.weapon and combatant.weapons[0] are consistent for the
##      spawned combatant, in BOTH cases.
##   5. Runs against the real mainscene/data files (no mocked ResourceLoader)
##      and passes as part of the GUT suite.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const ResolutionClass = preload("res://core/rules/resolution.gd")
const CombatantFactoryClass = preload("res://infrastructure/combatant_factory.gd")
const EncounterResourceClass = preload("res://data/encounters/encounter_resource.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")

const SKELETON_PATH: String = "res://data/enemies/skeleton.tres"
const MACE_PATH: String = "res://data/weapons/mace.tres"

## PROLOGUE_SEED — this project's established known-good fixture seed (see
## tests/integration/test_mainscene_skeleton_defense_eligibility.gd).
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


## _override_for_slot(encounter, slot_index) -> String — the EXACT same
## per-slot resolution core/application/combat_session_factory.gd's
## CombatSessionFactory.build() performs (FEAT-007 api_contract "Encounter
## spawn-slot override lookup"): weapon_path_overrides[slot_index] when
## slot_index < weapon_path_overrides.size(), else "" (no override -> the
## enemy's own weapon_paths[0] wins inside build_enemy_combatant()).
func _override_for_slot(encounter: EncounterResourceClass, slot_index: int) -> String:
	var weapon_path_override: String = ""
	if slot_index < encounter.weapon_path_overrides.size():
		weapon_path_override = encounter.weapon_path_overrides[slot_index]
	return weapon_path_override


# ══════════════════════════════════════════════════════════════════════════
# Entry point → exit point, NO override: an EncounterResource spawn slot for
# the Skeleton with weapon_path_overrides == [] resolves through the REAL
# CombatantFactory.build_enemy_combatant() to the Skeleton's own
# weapon_paths[0] (arming_sword.tres), exercised inside a booted mainscene.
# ══════════════════════════════════════════════════════════════════════════

func test_no_override_skeleton_weapon_matches_arming_sword_table_inside_booted_mainscene() -> void:
	var instance = _boot_main_scene()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return

	var encounter := EncounterResourceClass.new()
	encounter.enemy_resource_paths = [SKELETON_PATH]
	var empty_overrides: Array[String] = []
	encounter.weapon_path_overrides = empty_overrides

	var override: String = _override_for_slot(encounter, 0)
	assert_eq(override, "", "no weapon_path_overrides authored -> slot 0 resolves to '' (no override)")

	var factory := CombatantFactoryClass.new()
	var built: Dictionary = factory.build_enemy_combatant(
		encounter.enemy_resource_paths[0], null, "skeleton_e2e_no_override", override
	)
	assert_false(built.has("error"), "no-override build must succeed inside a booted mainscene; got: %s" % str(built))
	if built.has("error"):
		return

	var combatant := CombatantClass.from_dict(built)

	# Criterion 1 — weapon dict matches the Arming Sword table exactly.
	assert_eq(combatant.weapon.get("parry_bonus", -1), 4, "no-override skeleton parry_bonus must be 4 (Arming Sword)")
	assert_eq(combatant.weapon.get("block_value", -1), 2, "no-override skeleton block_value must be 2 (Arming Sword)")
	assert_eq(combatant.weapon.get("block_die", -1), 0, "no-override skeleton block_die must be 0 (Arming Sword, unset)")
	assert_eq(combatant.weapon.get("damage_die", -1), 6, "no-override skeleton damage_die must be 6 (Arming Sword)")
	assert_eq(combatant.weapon.get("damage_modifier_attribute", ""), "strength", "no-override skeleton damage_modifier_attribute must be 'strength'")

	# Criterion 3 — parry/block reaction eligibility driven by the resolved weapon stats.
	assert_true(ResolutionClass.is_parry_eligible(combatant.weapon), "no-override skeleton weapon must be Parry-eligible")
	assert_true(ResolutionClass.is_block_eligible(combatant.weapon), "no-override skeleton weapon must be Block-eligible")

	# Criterion 4 — combatant.weapon and combatant.weapons[0] are consistent.
	assert_eq(combatant.weapons.size(), 1, "combatant.weapons must contain exactly one entry")
	assert_eq(combatant.weapons[0], combatant.weapon, "combatant.weapons[0] must equal combatant.weapon")


# ══════════════════════════════════════════════════════════════════════════
# Entry point → exit point, WITH override: the same EncounterResource-driven
# flow, but the skeleton's slot now authors a weapon_path_overrides entry
# (mace.tres, NOT arming_sword.tres) — the resolved combatant must carry the
# OVERRIDDEN weapon's stats, not the Skeleton's default.
# ══════════════════════════════════════════════════════════════════════════

func test_override_skeleton_weapon_resolves_to_overridden_weapon_inside_booted_mainscene() -> void:
	var instance = _boot_main_scene()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return

	var encounter := EncounterResourceClass.new()
	encounter.enemy_resource_paths = [SKELETON_PATH]
	var overrides: Array[String] = [MACE_PATH]
	encounter.weapon_path_overrides = overrides

	var override: String = _override_for_slot(encounter, 0)
	assert_eq(override, MACE_PATH, "slot 0's authored weapon_path_overrides entry must resolve verbatim")

	var factory := CombatantFactoryClass.new()
	var built: Dictionary = factory.build_enemy_combatant(
		encounter.enemy_resource_paths[0], null, "skeleton_e2e_override", override
	)
	assert_false(built.has("error"), "override build must succeed inside a booted mainscene; got: %s" % str(built))
	if built.has("error"):
		return

	var combatant := CombatantClass.from_dict(built)

	# Criterion 2 — resolves to the Mace's stats, NOT the Arming Sword's.
	assert_eq(combatant.weapon.get("damage_die", -1), 8, "override skeleton damage_die must be 8 (Mace), not 6 (Arming Sword)")
	assert_eq(combatant.weapon.get("proficiency_bonus", -1), 1, "override skeleton proficiency_bonus must be 1 (Mace)")
	assert_eq(combatant.weapon.get("parry_bonus", -1), 1, "override skeleton parry_bonus must be 1 (Mace), not 4 (Arming Sword)")
	assert_eq(combatant.weapon.get("block_value", -1), 2, "override skeleton block_value must be 2 (Mace)")
	assert_eq(combatant.weapon.get("block_die", -1), 0, "override skeleton block_die must be 0 (Mace, unset)")
	assert_eq(combatant.weapon.get("damage_modifier_attribute", ""), "strength", "override skeleton damage_modifier_attribute must be 'strength' (Mace)")
	assert_ne(combatant.weapon.get("damage_die", -1), 6, "override must NOT fall back to arming_sword.tres's damage_die (6)")

	# Criterion 3 — parry/block reaction eligibility driven by the OVERRIDDEN weapon stats.
	assert_true(ResolutionClass.is_parry_eligible(combatant.weapon), "override skeleton weapon (Mace, parry_bonus=1) must be Parry-eligible")
	assert_true(ResolutionClass.is_block_eligible(combatant.weapon), "override skeleton weapon (Mace, block_value=2) must be Block-eligible")

	# Criterion 4 — combatant.weapon and combatant.weapons[0] are consistent.
	assert_eq(combatant.weapons.size(), 1, "combatant.weapons must contain exactly one entry")
	assert_eq(combatant.weapons[0], combatant.weapon, "combatant.weapons[0] must equal combatant.weapon for the overridden build")


# ══════════════════════════════════════════════════════════════════════════
# Live-boot cross-check: the REAL, live Skeleton enemy MainScene's own
# _ready() composition already spawned (instance._enemies[0], a real
# core/domain/combatant.gd Combatant instance — see
## core/application/combat_session_factory.gd's `CombatantClass.from_dict()`
## population of `enemies`) carries the SAME Arming Sword table and passes
## the SAME parry/block eligibility checks this suite's direct
## CombatantFactory calls above assert — proving the two paths agree and
## this suite is not diverging from what the live game actually spawns.
# ══════════════════════════════════════════════════════════════════════════

func test_live_booted_skeleton_matches_direct_factory_build_no_override() -> void:
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
	assert_eq(weapon.get("parry_bonus", -1), 4, "live-booted skeleton parry_bonus must be 4 (Arming Sword)")
	assert_eq(weapon.get("block_value", -1), 2, "live-booted skeleton block_value must be 2 (Arming Sword)")
	assert_eq(weapon.get("block_die", -1), 0, "live-booted skeleton block_die must be 0 (Arming Sword, unset)")
	assert_eq(weapon.get("damage_die", -1), 6, "live-booted skeleton damage_die must be 6 (Arming Sword)")
	assert_eq(weapon.get("damage_modifier_attribute", ""), "strength", "live-booted skeleton damage_modifier_attribute must be 'strength'")

	assert_true(ResolutionClass.is_parry_eligible(weapon), "live-booted skeleton weapon must be Parry-eligible")
	assert_true(ResolutionClass.is_block_eligible(weapon), "live-booted skeleton weapon must be Block-eligible")

	var weapons: Array = skeleton.weapons
	assert_eq(weapons.size(), 1, "live-booted skeleton.weapons must contain exactly one entry")
	assert_eq(weapons[0], weapon, "live-booted skeleton.weapons[0] must equal skeleton.weapon")
