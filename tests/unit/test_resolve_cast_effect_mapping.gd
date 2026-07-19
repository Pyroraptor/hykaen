extends GutTest
## tests/unit/test_resolve_cast_effect_mapping.gd — FEAT-010 (US-010;
## FR-009)
##
## GUT suite for core/application/use_cases/resolve_cast_use_case.gd's
## FEAT-010 extension: on a hit, ResolveCastUseCase.execute() maps the
## AttackResult ResolutionPort returned into a DAMAGE Effect (core/domain/
## effects/damage_effect.gd DamageEffect) — amount = attack_result's own
## `damage_final` (already computed by ResolutionPort/core/rules/
## resolution.gd from the spell's damage_formula, e.g. Fire Bolt's
## "2d8+ATTR" fire damage, and the caster's spellcasting attribute; this
## use case performs no dice math of its own) — and dispatches it through
## the single domain EffectsApplier seam (core/domain/effects_applier.gd),
## mutating the live target Combatant BY REFERENCE. A miss never builds or
## applies a DAMAGE effect at all.
##
## Mirrors tests/unit/test_resolve_cast_use_case_resolution.gd's
## established "fake, duck-typed port doubles / real domain objects"
## convention (SpyResolutionPort, _fire_bolt()/_caster_at()/_enemy()
## fixture helpers) — this suite adds a SpyEffectsApplier double to observe
## exactly what is dispatched to the EffectsApplier seam, and otherwise
## drives the REAL core/domain/effects_applier.gd EffectsApplier (via
## ResolveCastUseCase's own default-constructed instance) to prove the
## live target's hp_current genuinely decrements.
##
## test_criteria covered:
##   1. Unit test confirms a hit builds a DAMAGE effect with formula
##      2d8+attribute and type fire, applied to the live target via
##      EffectsApplierPort.
##   2. Unit test confirms a miss applies no damage effect.
##   3. Unit test confirms target.hp decrements by the applied effect
##      amount.

const ResolutionPortClass     = preload("res://core/application/ports/resolution_port.gd")
const ResolveCastUseCaseClass = preload("res://core/application/use_cases/resolve_cast_use_case.gd")
const CombatantClass          = preload("res://core/domain/combatant.gd")
const HexCoordClass           = preload("res://core/geometry/hex_coord.gd")
const SpellClass              = preload("res://core/domain/spell.gd")
const ErrorCodeClass          = preload("res://core/application/ports/errors.gd")
const EffectsApplierClass     = preload("res://core/domain/effects_applier.gd")
const EffectKindClass         = preload("res://core/domain/effects/effect_kind.gd")
const DamageEffectClass       = preload("res://core/domain/effects/damage_effect.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## SpyResolutionPort -- returns a scripted AttackResult regardless of the
## arguments handed in (mirrors test_resolve_cast_use_case_resolution.gd's
## identically-named double).
class SpyResolutionPort:
	extends ResolutionPortClass
	var scripted_result: Dictionary = {}

	func resolve_spell_attack(_attacker, _target, _spell, _defense_type) -> Dictionary:
		return scripted_result


## SpyEffectsApplier -- records every apply() call's (effects, combatants)
## argument tuple, then delegates to a REAL EffectsApplier so the live
## target is genuinely mutated (proving this use case dispatches through
## the actual domain seam, not a bespoke mutation path of its own).
class SpyEffectsApplier:
	extends RefCounted
	var calls: Array = []
	var _real := EffectsApplierClass.new()

	func apply(effects: Array, combatants: Dictionary) -> void:
		calls.append([effects, combatants])
		_real.apply(effects, combatants)


func _fire_bolt() -> SpellClass:
	return SpellClass.new("fire_bolt", "Fire Bolt", 2, 0, SpellClass.Defense.REFLEX, 50, "2d8+ATTR", "fire", [])


func _caster_at(hex_coord: HexCoordClass) -> CombatantClass:
	var c := CombatantClass.new("marigold_1", "Marigold", "Player", hex_coord)
	c.known_spell_ids = ["fire_bolt"]
	c.spellcasting_attribute_score = 4
	c.casting_state = {
		"spell_id": "fire_bolt",
		"remaining_actions": 0,
		"committed_energy": 0,
		"caster_id": "marigold_1",
	}
	return c


func _enemy(id: String, hex_coord: HexCoordClass) -> CombatantClass:
	var e := CombatantClass.new(id, id, "Enemy", hex_coord)
	e.hp_current = 10
	e.hp_max = 10
	e.reflex = 12
	return e


func _hit_result(damage_final: int) -> Dictionary:
	return {
		"hit": true,
		"crit": false,
		"roll_total": 18,
		"damage_raw": damage_final,
		"active_defense_applied": "none",
		"damage_final": damage_final,
	}


func _miss_result() -> Dictionary:
	return {
		"hit": false,
		"crit": false,
		"roll_total": 4,
		"damage_raw": 0,
		"active_defense_applied": "none",
		"damage_final": 0,
	}


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #1 -- a hit builds a DAMAGE effect (from Fire Bolt's
# 2d8+attribute fire formula's already-resolved damage_final) and applies
# it to the live target via the EffectsApplier seam
# ══════════════════════════════════════════════════════════════════════════

func test_hit_builds_damage_effect_from_fire_bolt_formula_and_applies_via_effects_applier() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()
	assert_eq(spell.damage_formula, "2d8+ATTR", "fixture assumption: Fire Bolt's authored formula is 2d8+ATTR")
	assert_eq(spell.damage_type, "fire", "fixture assumption: Fire Bolt's authored damage type is fire")

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _hit_result(9)
	var effects_spy := SpyEffectsApplier.new()

	var use_case := ResolveCastUseCaseClass.new(effects_spy)
	var result: Dictionary = use_case.execute(caster, spell, [target], resolution_spy)

	assert_true(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.NONE)

	assert_eq(effects_spy.calls.size(), 1, "a hit must dispatch exactly one apply() call to the EffectsApplier seam")
	var call: Array = effects_spy.calls[0]
	var applied_effects: Array = call[0]
	var applied_combatants: Dictionary = call[1]

	assert_eq(applied_effects.size(), 1, "exactly one DAMAGE effect must be built for a single-target hit")
	var effect = applied_effects[0]
	assert_true(effect is DamageEffectClass, "the built effect must genuinely be a DamageEffect")
	assert_eq(effect.kind, EffectKindClass.DAMAGE)
	assert_eq(effect.target_id, "skeleton")
	assert_eq(effect.amount, 9, "the DamageEffect amount must equal the AttackResult's damage_final (Fire Bolt's 2d8+attribute formula, already resolved)")
	assert_true(effect.is_valid())

	assert_true(applied_combatants.has("skeleton"), "the live target Combatant must be handed to the EffectsApplier seam by its own id")
	assert_same(applied_combatants["skeleton"], target, "the SAME target instance must be dispatched -- applied by reference, never a copy")

	assert_eq(result.get("results")[0].get("damage_applied"), 9)


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #2 -- a miss applies no damage effect
# ══════════════════════════════════════════════════════════════════════════

func test_miss_applies_no_damage_effect() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _miss_result()
	var effects_spy := SpyEffectsApplier.new()

	var use_case := ResolveCastUseCaseClass.new(effects_spy)
	var result: Dictionary = use_case.execute(caster, spell, [target], resolution_spy)

	assert_true(result.get("success"))
	assert_true(effects_spy.calls.is_empty(), "a miss must never dispatch a DAMAGE effect to the EffectsApplier seam")
	assert_eq(result.get("results")[0].get("damage_applied"), 0)
	assert_eq(target.hp_current, 10, "a miss must leave the target's hp untouched")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #3 -- target.hp decrements by the applied effect amount
# ══════════════════════════════════════════════════════════════════════════

func test_hit_decrements_target_hp_by_the_applied_effect_amount() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _hit_result(6)

	# Default-constructed ResolveCastUseCase (no injected effects applier) --
	# proves the REAL production EffectsApplier is used when the caller
	# does not substitute a double, mirroring resolve_action_use_case.gd's
	# own "own an EffectsApplier by default" convention.
	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target], resolution_spy)

	assert_true(result.get("success"))
	assert_eq(target.hp_current, 4, "hp_current must decrement from 10 by the applied DamageEffect's amount (6)")
	assert_eq(result.get("results")[0].get("damage_applied"), 6)

	assert_true(use_case.get_effects_applier() is EffectsApplierClass, "the default-constructed EffectsApplier must genuinely be core/domain/effects_applier.gd's EffectsApplier")


func test_hit_decrements_target_hp_across_multiple_targets_independently() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target_a := _enemy("skeleton_a", HexCoordClass.new(1, 0))
	var target_b := _enemy("skeleton_b", HexCoordClass.new(2, 0))
	var spell := _fire_bolt()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _hit_result(3)

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target_a, target_b], resolution_spy)

	assert_true(result.get("success"))
	assert_eq(target_a.hp_current, 7)
	assert_eq(target_b.hp_current, 7)
	assert_eq(result.get("results").size(), 2)
	assert_eq(result.get("results")[0].get("damage_applied"), 3)
	assert_eq(result.get("results")[1].get("damage_applied"), 3)


# ══════════════════════════════════════════════════════════════════════════
# Defensive: a hit with a non-positive damage_final never constructs an
# invalid DamageEffect (DamageEffect rejects amount<=0 at construction)
# ══════════════════════════════════════════════════════════════════════════

func test_hit_with_zero_damage_final_applies_no_effect() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _hit_result(0)
	var effects_spy := SpyEffectsApplier.new()

	var use_case := ResolveCastUseCaseClass.new(effects_spy)
	var result: Dictionary = use_case.execute(caster, spell, [target], resolution_spy)

	assert_true(result.get("success"))
	assert_true(effects_spy.calls.is_empty(), "a zero damage_final on a hit must never construct/apply an (invalid) DamageEffect")
	assert_eq(target.hp_current, 10)
