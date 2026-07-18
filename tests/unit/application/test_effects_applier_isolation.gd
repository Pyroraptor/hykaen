extends GutTest
## tests/unit/application/test_effects_applier_isolation.gd
##
## NAMING NOTE: the feature spec's files_to_create entry spells this file
## "effects_applier_isolation_test.gd" (suffix convention). This project's
## actual GUT discovery is PREFIX-based, not suffix-based: both
## .gutconfig.json and tests/.gutconfig.json set "prefix": "test_",
## "suffix": ".gd", and addons/gut/gut.gd's _get_files() only collects a
## script when `fs_item.begins_with(prefix)` (see gut.gd:980). A file named
## "effects_applier_isolation_test.gd" does NOT begin with "test_" and
## would be silently skipped by every dir-scanned GUT stage in
## scripts/test_command.sh (stage 7's tests/.gutconfig.json and stage 8's
## root .gutconfig.json both scan res://tests/... with include_subdirs) --
## i.e. it would never actually run. This file is therefore named
## test_effects_applier_isolation.gd, matching the prefix convention every
## other suite in tests/unit/ already follows (e.g. tests/unit/application/
## test_effects_applier_use_case.gd), so it is a real, executing part of
## the regression gate rather than dead code that merely LOOKS like
## coverage.
##
## GUT suite for FEAT-003 (US-003, FR-006): isolated per-Effect-kind
## coverage of EffectsApplierUseCase (core/application/use_cases/
## effects_applier_use_case.gd) — the application-layer "Applier" seam
## every future ResolveActionUseCase/ApplyOnHitDefenseUseCase call site is
## meant to route through (design notes' architecture section, US-004/
## US-005, not yet wired by this feature).
##
## WHY THIS FILE EXISTS ALONGSIDE tests/unit/core/domain/
## test_effects_applier.gd and tests/unit/application/
## test_effects_applier_use_case.gd: those suites exercise the domain
## EffectsApplier / application EffectsApplierUseCase as part of their own
## feature's broader coverage (batching, fail-soft error collection,
## instance-identity, no-duplicate-seams). FEAT-003 (FR-006) asks for a
## SEPARATE, narrowly-scoped suite whose only job is: does each Effect
## KIND, taken completely on its own (one effect, one target, one
## assertion), drive the correct domain business rule end to end through
## the Applier? Every test below constructs exactly ONE Effect and applies
## it in its own batch — no Strike, no ApplyOnHitDefenseUseCase, no
## reaction machinery, no multi-effect batches anywhere in this file, so a
## regression here can only mean the Applier's per-kind dispatch (or the
## domain business rule it triggers) broke, never a call-site-specific
## wiring bug.
##
## Verifies (test_criteria):
##   1. DAMAGE effect reduces hp by exactly the expected amount.
##   2. HEAL effect increases hp and clamps at hp_max (overheal amount).
##   3. CONDITION effect adds the specified tag on op=ADD and removes it on
##      op=REMOVE.
##   4. MOVE effect relocates Combatant.position (hex_coord) to the target
##      hex exactly.

const EffectsApplierUseCaseClass = preload("res://core/application/use_cases/effects_applier_use_case.gd")
const CombatantClass             = preload("res://core/domain/combatant.gd")
const DamageEffectClass          = preload("res://core/domain/effects/damage_effect.gd")
const HealEffectClass            = preload("res://core/domain/effects/heal_effect.gd")
const ConditionEffectClass       = preload("res://core/domain/effects/condition_effect.gd")
const MoveEffectClass            = preload("res://core/domain/effects/move_effect.gd")
const HexCoordClass              = preload("res://core/geometry/hex_coord.gd")


func _make_combatant(id: String = "isolation_target", hp_current: int = 10, hp_max: int = 20) -> CombatantClass:
	var c := CombatantClass.new(id, "Isolation Fixture", "Enemy", HexCoordClass.new(0, 0))
	c.hp_current = hp_current
	c.hp_max = hp_max
	return c


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: DAMAGE effect reduces hp by exactly the expected amount
# ══════════════════════════════════════════════════════════════════════════

func test_damage_effect_in_isolation_reduces_hp_by_exact_amount() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("isolation_target", 10, 20)
	var combatants := {"isolation_target": target}

	var result := use_case.apply([DamageEffectClass.new("isolation_target", 7)], combatants)

	assert_eq(target.hp_current, 3, "a lone DAMAGE effect of 7 must reduce hp_current from 10 to exactly 3")
	assert_eq(result.applied_count, 1, "the lone DAMAGE effect must be recorded as applied")
	assert_false(result.has_errors(), "a single valid DAMAGE effect must not produce any errors")


func test_damage_effect_in_isolation_applies_exact_amount_unclamped() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("isolation_target", 5, 20)
	var combatants := {"isolation_target": target}

	use_case.apply([DamageEffectClass.new("isolation_target", 5)], combatants)

	assert_eq(target.hp_current, 0, "a DAMAGE effect exactly equal to remaining hp must reduce hp_current to exactly 0")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: HEAL effect increases hp and clamps at hp_max (overheal)
# ══════════════════════════════════════════════════════════════════════════

func test_heal_effect_in_isolation_increases_hp_by_exact_amount() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("isolation_target", 4, 20)
	var combatants := {"isolation_target": target}

	var result := use_case.apply([HealEffectClass.new("isolation_target", 9)], combatants)

	assert_eq(target.hp_current, 13, "a lone HEAL effect of 9 must restore hp_current from 4 to exactly 13")
	assert_eq(result.applied_count, 1, "the lone HEAL effect must be recorded as applied")


func test_heal_effect_in_isolation_clamps_at_hp_max_on_overheal() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("isolation_target", 18, 20)
	var combatants := {"isolation_target": target}

	var result := use_case.apply([HealEffectClass.new("isolation_target", 500)], combatants)

	assert_eq(target.hp_current, 20, "an overheal HEAL amount (500) must clamp hp_current at hp_max (20), never exceed it")
	assert_eq(result.applied_count, 1, "the clamped HEAL effect is still counted as applied")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: CONDITION effect adds the tag on op=ADD, removes it on
# op=REMOVE
# ══════════════════════════════════════════════════════════════════════════

func test_condition_effect_in_isolation_op_add_adds_the_specified_tag() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("isolation_target")
	var combatants := {"isolation_target": target}
	var effect := ConditionEffectClass.new("isolation_target", "Off-Guard", true)

	assert_eq(effect.op, ConditionEffectClass.Op.ADD, "add=true must set op=ADD on the effect itself")
	assert_false(target.has_condition("Off-Guard"), "fixture must not already carry the tag before applying")

	var result := use_case.apply([effect], combatants)

	assert_true(target.has_condition("Off-Guard"), "op=ADD must add the specified 'Off-Guard' tag")
	assert_eq(result.applied_count, 1, "the lone CONDITION effect must be recorded as applied")


func test_condition_effect_in_isolation_op_remove_removes_the_specified_tag() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("isolation_target")
	target.add_condition("Immobilized")
	var combatants := {"isolation_target": target}
	var effect := ConditionEffectClass.new("isolation_target", "Immobilized", false)

	assert_eq(effect.op, ConditionEffectClass.Op.REMOVE, "add=false must set op=REMOVE on the effect itself")
	assert_true(target.has_condition("Immobilized"), "fixture must carry the tag before applying the REMOVE effect")

	var result := use_case.apply([effect], combatants)

	assert_false(target.has_condition("Immobilized"), "op=REMOVE must remove the specified 'Immobilized' tag")
	assert_eq(result.applied_count, 1, "the lone CONDITION effect must be recorded as applied")


func test_condition_effect_in_isolation_op_add_does_not_duplicate_an_existing_tag() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("isolation_target")
	target.add_condition("Off-Guard")
	var combatants := {"isolation_target": target}

	use_case.apply([ConditionEffectClass.new("isolation_target", "Off-Guard", true)], combatants)

	assert_eq(target.conditions.count("Off-Guard"), 1, "op=ADD on an already-present tag must not duplicate it")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: MOVE effect relocates Combatant.position to the target hex
# exactly
# ══════════════════════════════════════════════════════════════════════════

func test_move_effect_in_isolation_relocates_position_to_target_hex_exactly() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("isolation_target")
	var combatants := {"isolation_target": target}
	var destination := HexCoordClass.new(3, -2)

	assert_false(target.hex_coord.equals(destination), "fixture must not already occupy the destination hex")

	var result := use_case.apply([MoveEffectClass.new("isolation_target", destination)], combatants)

	assert_eq(target.hex_coord.q, 3, "MOVE must relocate hex_coord.q to the effect's destination hex exactly")
	assert_eq(target.hex_coord.r, -2, "MOVE must relocate hex_coord.r to the effect's destination hex exactly")
	assert_true(target.hex_coord.equals(destination), "position must equal the target hex exactly after MOVE")
	assert_eq(result.applied_count, 1, "the lone MOVE effect must be recorded as applied")


func test_move_effect_in_isolation_relocates_to_origin_hex_exactly() -> void:
	var use_case := EffectsApplierUseCaseClass.new()
	var target := _make_combatant("isolation_target")
	target.hex_coord = HexCoordClass.new(4, 1)
	var combatants := {"isolation_target": target}
	var destination := HexCoordClass.new(0, 0)

	use_case.apply([MoveEffectClass.new("isolation_target", destination)], combatants)

	assert_true(target.hex_coord.equals(destination), "MOVE must relocate position to the origin hex exactly when that is the target")
