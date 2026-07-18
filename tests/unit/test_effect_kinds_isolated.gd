extends GutTest
## tests/unit/test_effect_kinds_isolated.gd
##
## GUT suite for FEAT-003 (US-003): a dedicated, ISOLATED unit-test suite
## for each Effect kind's behaviour through EffectsApplier
## (core/domain/effects_applier.gd, FEAT-002), independent of combat
## orchestration (resolution.gd, encounter.gd, round_session.gd, AI, or
## any presentation/engine scaffolding).
##
## "Isolated" here means: every test in this file constructs its own bare
## Combatant fixture (core/domain/combatant.gd) directly via `.new()`,
## constructs the Effect value object(s) under test directly, and drives
## them through a bare EffectsApplier instance -- with NO Node/Control/
## CanvasItem scene tree, NO MainScene boot, NO ResolveActionUseCase, and
## NO EventSinkPort/CombatantSetPort involved. This is a pure-domain test:
## Combatant + Effect + EffectsApplier only (core/domain/**), matching the
## project's domain-purity convention (zero engine I/O beyond RefCounted).
##
## This suite deliberately covers ONLY the four Effect kinds US-003 calls
## out by name (test_criteria) -- DAMAGE, HEAL, CONDITION, MOVE -- one
## focused test-per-behaviour file, distinct from (and narrower than)
## tests/unit/core/domain/test_effects_applier.gd's broader FEAT-002
## applier-contract suite (fail-soft skip semantics, batch ordering,
## same-instance-by-reference, the no-duplicate-seams CI gate, etc.),
## which remains the authority for those cross-cutting applier concerns.
## ADD_ENERGY is intentionally out of scope here (reserved for Iteration M,
## per the design notes; not named in US-003's acceptance criteria).
##
## Verifies (test_criteria):
##   1. DAMAGE reduces hp by the expected amount on an isolated Combatant
##      fixture.
##   2. HEAL increases hp and caps at hp_max on an isolated Combatant
##      fixture.
##   3. CONDITION adds and then removes the specified tag on an isolated
##      Combatant fixture.
##   4. MOVE relocates a Combatant to the target hex on an isolated
##      Combatant fixture.
##   5. All tests run without any engine/UI scaffolding (pure domain
##      test) -- enforced structurally by this file only preloading
##      core/domain/** and core/geometry/** scripts (no presentation/**,
##      no Node-derived scene, no MainScene boot).

const EffectsApplierClass = preload("res://core/domain/effects_applier.gd")
const CombatantClass       = preload("res://core/domain/combatant.gd")
const DamageEffectClass    = preload("res://core/domain/effects/damage_effect.gd")
const HealEffectClass      = preload("res://core/domain/effects/heal_effect.gd")
const ConditionEffectClass = preload("res://core/domain/effects/condition_effect.gd")
const MoveEffectClass      = preload("res://core/domain/effects/move_effect.gd")
const HexCoordClass        = preload("res://core/geometry/hex_coord.gd")


## _make_isolated_combatant(...) -> Combatant -- a bare fixture built
## directly via Combatant.new(), with no factory, no encounter, no
## resolution pipeline involved. This is the ONLY way this suite ever
## obtains a Combatant.
func _make_isolated_combatant(
	id: String = "fixture_0",
	hp_current: int = 10,
	hp_max: int = 20
) -> CombatantClass:
	var c := CombatantClass.new(id, "Isolated Fixture", "Enemy", HexCoordClass.new(0, 0))
	c.hp_current = hp_current
	c.hp_max = hp_max
	return c


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: DAMAGE reduces hp by the expected amount on an isolated
# Combatant fixture
# ══════════════════════════════════════════════════════════════════════════

func test_damage_effect_reduces_hp_by_expected_amount() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_isolated_combatant("fixture_0", 10, 20)
	var combatants := {"fixture_0": target}

	applier.apply([DamageEffectClass.new("fixture_0", 7)], combatants)

	assert_eq(target.hp_current, 3, "DAMAGE(7) must reduce hp_current from 10 to 3 on an isolated Combatant fixture")


func test_damage_effect_of_zero_amount_is_invalid_and_leaves_hp_unchanged() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_isolated_combatant("fixture_0", 10, 20)
	var combatants := {"fixture_0": target}

	applier.apply([DamageEffectClass.new("fixture_0", 0)], combatants)

	assert_eq(target.hp_current, 10, "a zero-amount DamageEffect is invalid at construction and must never mutate hp")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: HEAL increases hp and caps at hp_max on an isolated
# Combatant fixture
# ══════════════════════════════════════════════════════════════════════════

func test_heal_effect_increases_hp_by_expected_amount() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_isolated_combatant("fixture_0", 5, 20)
	var combatants := {"fixture_0": target}

	applier.apply([HealEffectClass.new("fixture_0", 6)], combatants)

	assert_eq(target.hp_current, 11, "HEAL(6) must restore hp_current from 5 to 11 on an isolated Combatant fixture")


func test_heal_effect_caps_at_hp_max_no_overheal() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_isolated_combatant("fixture_0", 18, 20)
	var combatants := {"fixture_0": target}

	applier.apply([HealEffectClass.new("fixture_0", 50)], combatants)

	assert_eq(target.hp_current, 20, "HEAL must cap hp_current at hp_max -- no overheal, even for a large heal amount")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: CONDITION adds and then removes the specified tag on an
# isolated Combatant fixture
# ══════════════════════════════════════════════════════════════════════════

func test_condition_effect_adds_the_specified_tag() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_isolated_combatant("fixture_0")
	var combatants := {"fixture_0": target}

	assert_false(target.has_condition("Off-Guard"), "fixture must start without the tag")

	applier.apply([ConditionEffectClass.new("fixture_0", "Off-Guard", true)], combatants)

	assert_true(target.has_condition("Off-Guard"), "CONDITION(add=true) must add the specified tag on an isolated Combatant fixture")


func test_condition_effect_then_removes_the_specified_tag() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_isolated_combatant("fixture_0")
	var combatants := {"fixture_0": target}

	applier.apply([ConditionEffectClass.new("fixture_0", "Off-Guard", true)], combatants)
	assert_true(target.has_condition("Off-Guard"), "precondition: tag must be present before it can be removed")

	applier.apply([ConditionEffectClass.new("fixture_0", "Off-Guard", false)], combatants)

	assert_false(target.has_condition("Off-Guard"), "CONDITION(add=false) must remove the specified tag on an isolated Combatant fixture")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: MOVE relocates Combatant to target hex on an isolated
# Combatant fixture
# ══════════════════════════════════════════════════════════════════════════

func test_move_effect_relocates_combatant_to_target_hex() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_isolated_combatant("fixture_0")
	var combatants := {"fixture_0": target}
	var destination := HexCoordClass.new(3, -2)

	assert_false(target.hex_coord.equals(destination), "fixture must start away from the destination hex")

	applier.apply([MoveEffectClass.new("fixture_0", destination)], combatants)

	assert_eq(target.hex_coord.q, 3, "MOVE must relocate hex_coord.q to the target hex on an isolated Combatant fixture")
	assert_eq(target.hex_coord.r, -2, "MOVE must relocate hex_coord.r to the target hex on an isolated Combatant fixture")
	assert_true(target.hex_coord.equals(destination), "MOVE must relocate the Combatant's hex_coord to exactly the target hex")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: all tests run without any engine/UI scaffolding (pure
# domain test) -- a structural self-check that the fixtures this suite
# drives are plain RefCounted domain objects (Combatant, Effect,
# EffectsApplier), never a Node/Control/CanvasItem scene-tree type. GDScript
# statically PROVES `is Node` false for a RefCounted-typed expression at
# compile time (a parse error, not a runtime false), so this is asserted via
# get_class() string comparison instead -- still a real runtime check, not a
# grep, but one the static type checker will not reject.
# ══════════════════════════════════════════════════════════════════════════

func test_isolated_fixtures_are_plain_refcounted_not_engine_nodes() -> void:
	var applier := EffectsApplierClass.new()
	var target := _make_isolated_combatant("fixture_0")
	var damage_effect := DamageEffectClass.new("fixture_0", 1)

	assert_true(applier is RefCounted, "EffectsApplier must extend RefCounted")
	assert_true(target is RefCounted, "Combatant must extend RefCounted")
	assert_true(damage_effect is RefCounted, "DamageEffect must extend RefCounted")
	assert_false(applier.get_class() == "Node", "EffectsApplier must be a plain RefCounted domain service, never a Node")
	assert_false(target.get_class() == "Node", "Combatant must be a plain RefCounted domain entity, never a Node")
	assert_false(damage_effect.get_class() == "Node", "DamageEffect must be a plain RefCounted value object, never a Node")
