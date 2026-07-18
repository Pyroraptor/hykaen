extends GutTest
## tests/unit/core/domain/test_effects_applier.gd
##
## GUT suite for FEAT-002 (US-002): the pure domain EffectsApplier service
## (core/domain/effects_applier.gd) that dispatches Effect value objects
## (core/domain/effects/*.gd, FEAT-001) to Combatant instance mutation
## methods (core/domain/combatant.gd) by reference against a live
## combatant set.
##
## Verifies (test_criteria):
##   1. apply([DamageEffect]) reduces target Combatant hp_current by the
##      exact amount.
##   2. apply([HealEffect]) increases hp_current, capped at hp_max.
##   3. apply([ConditionEffect add=true]) adds the tag; add=false removes
##      it.
##   4. apply([MoveEffect]) sets Combatant.hex_coord to the target hex.
##   5. The mutated Combatant is the SAME object instance passed in (by
##      reference — no copy/dict divergence).
##   6. A missing target_id in the combatants dict triggers a fail-soft
##      skip (never a partial-batch abort) -- the rest of the batch still
##      applies.
##   7. ci/check_no_duplicate_seams.sh confirms EffectsApplier is the sole
##      call site of take_damage/heal/add_condition/move_to (a real
##      subprocess invocation of the CI script, mirroring
##      tests/unit/domain/effects/test_effect_value_objects.gd's established
##      convention of exercising the actual ci/*.sh gate rather than
##      re-implementing its logic here).

const EffectsApplierClass = preload("res://core/domain/effects_applier.gd")
const CombatantClass       = preload("res://core/domain/combatant.gd")
const DamageEffectClass    = preload("res://core/domain/effects/damage_effect.gd")
const HealEffectClass      = preload("res://core/domain/effects/heal_effect.gd")
const ConditionEffectClass = preload("res://core/domain/effects/condition_effect.gd")
const MoveEffectClass      = preload("res://core/domain/effects/move_effect.gd")
const HexCoordClass        = preload("res://core/geometry/hex_coord.gd")

const NO_DUP_SEAMS_SCRIPT: String = "res://ci/check_no_duplicate_seams.sh"


func _make_combatant(id: String = "enemy_0", hp_current: int = 10, hp_max: int = 20) -> CombatantClass:
	var c := CombatantClass.new(id, "Fixture", "Enemy", HexCoordClass.new(0, 0))
	c.hp_current = hp_current
	c.hp_max = hp_max
	return c


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: apply([DamageEffect]) reduces hp_current by the exact amount
# ══════════════════════════════════════════════════════════════════════════

func test_apply_damage_effect_reduces_hp_current_by_exact_amount() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_combatant("enemy_0", 10, 20)
	var combatants := {"enemy_0": target}

	applier.apply([DamageEffectClass.new("enemy_0", 6)], combatants)

	assert_eq(target.hp_current, 4, "take_damage(6) must reduce hp_current from 10 to 4")


func test_apply_damage_effect_can_drive_hp_below_zero_unclamped() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_combatant("enemy_0", 5, 20)
	var combatants := {"enemy_0": target}

	applier.apply([DamageEffectClass.new("enemy_0", 12)], combatants)

	assert_eq(target.hp_current, -7, "damage must apply the exact amount, unclamped (parity with Combatant.take_damage())")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: apply([HealEffect]) increases hp_current, capped at hp_max
# ══════════════════════════════════════════════════════════════════════════

func test_apply_heal_effect_increases_hp_current() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_combatant("player_0", 4, 20)
	var combatants := {"player_0": target}

	applier.apply([HealEffectClass.new("player_0", 8)], combatants)

	assert_eq(target.hp_current, 12, "heal(8) must restore hp_current from 4 to 12")


func test_apply_heal_effect_caps_at_hp_max() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_combatant("player_0", 18, 20)
	var combatants := {"player_0": target}

	applier.apply([HealEffectClass.new("player_0", 100)], combatants)

	assert_eq(target.hp_current, 20, "heal() must cap at hp_max -- no overheal")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: apply([ConditionEffect]) add=true adds the tag, add=false
# removes it
# ══════════════════════════════════════════════════════════════════════════

func test_apply_condition_effect_add_true_adds_tag() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_combatant("enemy_0")
	var combatants := {"enemy_0": target}

	applier.apply([ConditionEffectClass.new("enemy_0", "Off-Guard", true)], combatants)

	assert_true(target.has_condition("Off-Guard"), "add=true must add the condition tag")


func test_apply_condition_effect_add_false_removes_tag() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_combatant("enemy_0")
	target.add_condition("Off-Guard")
	var combatants := {"enemy_0": target}

	applier.apply([ConditionEffectClass.new("enemy_0", "Off-Guard", false)], combatants)

	assert_false(target.has_condition("Off-Guard"), "add=false must remove the condition tag")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: apply([MoveEffect]) sets Combatant.hex_coord to the target hex
# ══════════════════════════════════════════════════════════════════════════

func test_apply_move_effect_sets_hex_coord() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_combatant("player_0")
	var combatants := {"player_0": target}
	var destination := HexCoordClass.new(2, -1)

	applier.apply([MoveEffectClass.new("player_0", destination)], combatants)

	assert_eq(target.hex_coord.q, 2, "move_to() must update hex_coord.q")
	assert_eq(target.hex_coord.r, -1, "move_to() must update hex_coord.r")
	assert_true(target.hex_coord.equals(destination), "hex_coord must equal the effect's destination hex")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: the mutated Combatant is the SAME object instance passed in
# (by reference, no copy/dict divergence)
# ══════════════════════════════════════════════════════════════════════════

func test_mutated_combatant_is_the_same_instance_by_reference() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_combatant("enemy_0", 10, 20)
	var combatants := {"enemy_0": target}

	applier.apply([DamageEffectClass.new("enemy_0", 3)], combatants)

	assert_same(
		combatants["enemy_0"], target,
		"EffectsApplier must mutate the SAME Combatant instance held in `combatants`, never a copy"
	)
	# A copy/dict-divergence bug would leave the original `target` reference
	# unmutated while some OTHER copy absorbed the damage -- assert the
	# ORIGINAL reference itself reflects the mutation too.
	assert_eq(target.hp_current, 7, "the original `target` reference (not just the dict entry) must reflect the mutation")


func test_apply_mutates_multiple_effects_against_the_same_target_in_order() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_combatant("enemy_0", 10, 20)
	var combatants := {"enemy_0": target}

	applier.apply([
		DamageEffectClass.new("enemy_0", 4),
		HealEffectClass.new("enemy_0", 1),
	], combatants)

	assert_eq(target.hp_current, 7, "effects must apply in list order against the same live instance: 10 -4 +1 = 7")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6: missing target_id triggers a fail-soft skip, never a
# partial-batch abort -- remaining effects in the batch still apply
# ══════════════════════════════════════════════════════════════════════════

func test_missing_target_id_is_skipped_without_aborting_the_batch() -> void:
	var applier := EffectsApplierClass.new()
	var known_target := _make_combatant("enemy_0", 10, 20)
	var combatants := {"enemy_0": known_target}

	applier.apply([
		DamageEffectClass.new("ghost_id", 5),   # missing target -- must be skipped, not abort
		DamageEffectClass.new("enemy_0", 3),    # must still apply despite the prior skip
	], combatants)

	assert_eq(
		known_target.hp_current, 7,
		"a missing target_id must be skipped fail-soft; the following valid effect must still apply (no partial-batch abort)"
	)


func test_missing_target_id_does_not_add_a_spurious_combatants_entry() -> void:
	var applier := EffectsApplierClass.new()
	var combatants := {}

	applier.apply([DamageEffectClass.new("ghost_id", 5)], combatants)

	assert_false(combatants.has("ghost_id"), "a missing target_id must never be auto-inserted into `combatants`")


func test_apply_empty_effects_array_is_a_no_op() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_combatant("enemy_0", 10, 20)
	var combatants := {"enemy_0": target}

	applier.apply([], combatants)

	assert_eq(target.hp_current, 10, "an empty effects batch must be a no-op")


func test_apply_skips_invalid_effect_without_aborting_the_batch() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_combatant("enemy_0", 10, 20)
	var combatants := {"enemy_0": target}

	applier.apply([
		DamageEffectClass.new("enemy_0", 0),   # invalid (amount<=0) -- rejected at construction, must be skipped
		DamageEffectClass.new("enemy_0", 4),   # must still apply
	], combatants)

	assert_eq(target.hp_current, 6, "an invalid effect must be skipped without aborting the remaining batch")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 7: ci/check_no_duplicate_seams.sh confirms EffectsApplier is the
# sole call site of take_damage/heal/add_condition/move_to -- a real
# subprocess invocation of the actual CI script (never a re-implementation
# of its logic), mirroring tests/unit/test_effect_value_objects.gd's
# test_domain_purity_check_passes_scoped_to_core_domain() convention.
# ══════════════════════════════════════════════════════════════════════════

func test_no_duplicate_seams_check_confirms_effects_applier_is_sole_seam() -> void:
	var absolute_script_path: String = ProjectSettings.globalize_path(NO_DUP_SEAMS_SCRIPT)
	var repo_root: String = ProjectSettings.globalize_path("res://")
	var out: Array = []
	var rc: int = OS.execute("bash", [absolute_script_path, repo_root], out, true)
	var combined_output: String = ""
	for line in out:
		combined_output += String(line)

	assert_eq(
		rc, 0,
		"ci/check_no_duplicate_seams.sh must exit 0 against the real repository now that EffectsApplier exists; output: %s" % combined_output
	)
	for method_name in ["take_damage", "heal", "add_condition", "move_to"]:
		assert_true(
			combined_output.contains(method_name),
			"check output must confirm the '%s' seam was scanned; got: %s" % [method_name, combined_output]
		)
