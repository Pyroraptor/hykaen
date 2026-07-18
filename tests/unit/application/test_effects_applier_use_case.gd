extends GutTest
## tests/unit/application/test_effects_applier_use_case.gd
##
## GUT suite for FEAT-002 (US-002): EffectsApplierUseCase
## (core/application/use_cases/effects_applier_use_case.gd) — the
## application-layer seam that validates an Effect batch and delegates
## dispatch to the single domain EffectsApplier (core/domain/
## effects_applier.gd), returning a structured, fail-soft
## AppliedEffectsResult (core/application/dto/applied_effects_result.gd)
## rather than throwing or silently no-op'ing.
##
## Verifies (test_criteria):
##   1. apply() with a DamageEffect calls target.take_damage(n) and mutates
##      hp_current on the SAME live instance passed in (object identity,
##      no copy divergence).
##   2. apply() with a HealEffect calls target.heal(n), capped at hp_max.
##   3. apply() with a ConditionEffect calls add_condition()/
##      remove_condition() per its op.
##   4. apply() with a MoveEffect calls target.move_to(hex).
##   5. An unknown/missing target_id yields EFFECT_TARGET_NOT_FOUND in
##      AppliedEffectsResult.errors, and the REMAINING effects in the same
##      batch still apply (fail-soft, no partial-batch abort).
##   6. A malformed/unrecognized effect kind yields EFFECT_UNKNOWN_KIND
##      (defensive; should be unreachable given typed Effect subtypes).
##   7. ci/check_no_duplicate_seams.sh (a real subprocess invocation of the
##      actual CI script, never a re-implementation of its logic here,
##      mirroring tests/unit/core/domain/test_effects_applier.gd's
##      established convention) confirms exactly one hp-mutation call
##      pattern exists across the repository even with this
##      application-layer wrapper present.

const EffectsApplierUseCaseClass = preload("res://core/application/use_cases/effects_applier_use_case.gd")
const AppliedEffectsResultClass = preload("res://core/application/dto/applied_effects_result.gd")
const EffectApplicationErrorClass = preload("res://core/application/dto/effect_application_error.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const EffectBaseClass = preload("res://core/domain/effects/effect_base.gd")
const DamageEffectClass = preload("res://core/domain/effects/damage_effect.gd")
const HealEffectClass = preload("res://core/domain/effects/heal_effect.gd")
const ConditionEffectClass = preload("res://core/domain/effects/condition_effect.gd")
const MoveEffectClass = preload("res://core/domain/effects/move_effect.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const NO_DUP_SEAMS_SCRIPT: String = "res://ci/check_no_duplicate_seams.sh"


func _make_combatant(id: String = "enemy_0", hp_current: int = 10, hp_max: int = 20) -> CombatantClass:
	var c := CombatantClass.new(id, "Fixture", "Enemy", HexCoordClass.new(0, 0))
	c.hp_current = hp_current
	c.hp_max = hp_max
	return c


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: DamageEffect -> take_damage(n), same live instance mutated
# ══════════════════════════════════════════════════════════════════════════

func test_apply_damage_effect_reduces_hp_current_and_mutates_same_instance() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("enemy_0", 10, 20)
	var combatants := {"enemy_0": target}

	var result := use_case.apply([DamageEffectClass.new("enemy_0", 6)], combatants)

	assert_eq(target.hp_current, 4, "take_damage(6) must reduce hp_current from 10 to 4")
	assert_same(
		combatants["enemy_0"], target,
		"EffectsApplierUseCase must mutate the SAME Combatant instance held in `combatants`, never a copy"
	)
	assert_eq(result.applied_count, 1, "one successfully-dispatched effect must be counted")
	assert_false(result.has_errors(), "a clean single-effect batch must produce no errors")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: HealEffect -> heal(n), capped at hp_max
# ══════════════════════════════════════════════════════════════════════════

func test_apply_heal_effect_increases_hp_current() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("player_0", 4, 20)
	var combatants := {"player_0": target}

	var result := use_case.apply([HealEffectClass.new("player_0", 8)], combatants)

	assert_eq(target.hp_current, 12, "heal(8) must restore hp_current from 4 to 12")
	assert_eq(result.applied_count, 1, "one successfully-dispatched effect must be counted")


func test_apply_heal_effect_caps_at_hp_max() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("player_0", 18, 20)
	var combatants := {"player_0": target}

	use_case.apply([HealEffectClass.new("player_0", 100)], combatants)

	assert_eq(target.hp_current, 20, "heal() must cap at hp_max -- no overheal")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: ConditionEffect -> add_condition()/remove_condition() per op
# ══════════════════════════════════════════════════════════════════════════

func test_apply_condition_effect_add_true_adds_tag() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("enemy_0")
	var combatants := {"enemy_0": target}

	use_case.apply([ConditionEffectClass.new("enemy_0", "Off-Guard", true)], combatants)

	assert_true(target.has_condition("Off-Guard"), "add=true must add the condition tag")


func test_apply_condition_effect_add_false_removes_tag() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("enemy_0")
	target.add_condition("Off-Guard")
	var combatants := {"enemy_0": target}

	use_case.apply([ConditionEffectClass.new("enemy_0", "Off-Guard", false)], combatants)

	assert_false(target.has_condition("Off-Guard"), "add=false must remove the condition tag")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: MoveEffect -> move_to(hex)
# ══════════════════════════════════════════════════════════════════════════

func test_apply_move_effect_sets_hex_coord() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("player_0")
	var combatants := {"player_0": target}
	var destination := HexCoordClass.new(2, -1)

	use_case.apply([MoveEffectClass.new("player_0", destination)], combatants)

	assert_true(target.hex_coord.equals(destination), "move_to() must relocate hex_coord to the effect's destination hex")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: unknown/missing target_id -> EFFECT_TARGET_NOT_FOUND,
# fail-soft (remaining effects in the batch still apply)
# ══════════════════════════════════════════════════════════════════════════

func test_missing_target_id_yields_effect_target_not_found_error() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var combatants := {}

	var result := use_case.apply([DamageEffectClass.new("ghost_id", 5)], combatants)

	assert_eq(result.applied_count, 0, "an effect with a missing target must not be counted as applied")
	assert_eq(result.errors.size(), 1, "exactly one error must be recorded")
	assert_eq(
		result.errors[0].code_name(), "EFFECT_TARGET_NOT_FOUND",
		"a missing target_id must yield EFFECT_TARGET_NOT_FOUND"
	)
	assert_eq(result.errors[0].target_id, "ghost_id", "the error must record the offending target_id")


func test_missing_target_id_does_not_abort_remaining_effects_in_the_batch() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var known_target := _make_combatant("enemy_0", 10, 20)
	var combatants := {"enemy_0": known_target}

	var result := use_case.apply([
		DamageEffectClass.new("ghost_id", 5),   # missing target -- fail-soft skip
		DamageEffectClass.new("enemy_0", 3),    # must still apply
	], combatants)

	assert_eq(
		known_target.hp_current, 7,
		"a missing target_id must be skipped fail-soft; the following valid effect must still apply"
	)
	assert_eq(result.applied_count, 1, "exactly one of the two effects was actually applied")
	assert_eq(result.errors.size(), 1, "exactly one error was recorded for the missing target")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6: an unrecognized effect kind -> EFFECT_UNKNOWN_KIND
# (defensive; should be unreachable given typed Effect subtypes)
# ══════════════════════════════════════════════════════════════════════════

func test_unrecognized_effect_kind_yields_effect_unknown_kind_error() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("enemy_0")
	var combatants := {"enemy_0": target}

	# A bare EffectBase (never constructed by production code) carries the
	# sentinel kind=-1, matching no recognized EffectKind member.
	var malformed_effect := EffectBaseClass.new(-1, "enemy_0")

	var result := use_case.apply([malformed_effect], combatants)

	assert_eq(result.applied_count, 0, "an unrecognized-kind effect must not be counted as applied")
	assert_eq(result.errors.size(), 1, "exactly one error must be recorded")
	assert_eq(
		result.errors[0].code_name(), "EFFECT_UNKNOWN_KIND",
		"an unrecognized effect kind must yield EFFECT_UNKNOWN_KIND"
	)


func test_apply_empty_effects_array_is_a_no_op() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("enemy_0", 10, 20)
	var combatants := {"enemy_0": target}

	var result := use_case.apply([], combatants)

	assert_eq(target.hp_current, 10, "an empty effects batch must be a no-op")
	assert_eq(result.applied_count, 0, "an empty batch applies nothing")
	assert_false(result.has_errors(), "an empty batch records no errors")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 7: ci/check_no_duplicate_seams.sh confirms exactly one
# hp-mutation call pattern exists -- a real subprocess invocation of the
# actual CI script (never a re-implementation of its logic here).
# ══════════════════════════════════════════════════════════════════════════

func test_no_duplicate_seams_check_passes_with_the_use_case_wrapper_present() -> void:
	var absolute_script_path: String = ProjectSettings.globalize_path(NO_DUP_SEAMS_SCRIPT)
	var repo_root: String = ProjectSettings.globalize_path("res://")
	var out: Array = []
	var rc: int = OS.execute("bash", [absolute_script_path, repo_root], out, true)
	var combined_output: String = ""
	for line in out:
		combined_output += String(line)

	assert_eq(
		rc, 0,
		"ci/check_no_duplicate_seams.sh must exit 0 with EffectsApplierUseCase present (it must delegate, never re-dispatch); output: %s" % combined_output
	)
	for method_name in ["take_damage", "heal", "add_condition", "move_to"]:
		assert_true(
			combined_output.contains(method_name),
			"check output must confirm the '%s' seam was scanned; got: %s" % [method_name, combined_output]
		)
