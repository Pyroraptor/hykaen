extends GutTest
## tests/unit/core/application/test_resolve_cast_use_case.gd — FEAT-003
## (US-007; FR-010)
##
## GUT suite for core/application/use_cases/resolve_cast_use_case.gd's
## FEAT-003 extension: after _apply_damage_on_hit() runs for a target, if
## `spell.condition_on_hit == "dazed"` and the AttackResult ResolutionPort
## returned for that target was a hit, ResolveCastUseCase builds a
## core/domain/effects/condition_effect.gd ConditionEffect(target_id,
## "Dazed", true) and dispatches it through the SAME `_effects_applier.apply()`
## seam `_apply_damage_on_hit()` already uses (ADR-002 reuse of the existing
## dispatch seam — no new port introduced).
##
## Mirrors tests/unit/test_resolve_cast_effect_mapping.gd's established
## "fake, duck-typed ResolutionPort double + SpyEffectsApplier delegating to
## a REAL EffectsApplier" convention, so the suite proves BOTH that the
## right effect is dispatched to the seam AND that the live target
## Combatant's conditions[] genuinely mutate.
##
## test_criteria covered:
##   1. A seeded/forced hit against frost_breath: target ends with
##      has_condition('Dazed') == true.
##   2. A seeded/forced miss against frost_breath: target does NOT have
##      condition 'Dazed'.
##   3. Casting fire_bolt (condition_on_hit == '') never applies Dazed
##      regardless of hit/miss.
##   4. ConditionEffect is dispatched through the same
##      _effects_applier.apply() call path as DamageEffect (no new port
##      introduced) -- proven via the SpyEffectsApplier recording both a
##      DamageEffect AND a ConditionEffect from the SAME apply() seam.
##   5. Regression: CombineActionController's existing dazed-sync logic
##      still correctly reads has_condition('Dazed') after this change --
##      covered by exercising the REAL Combatant.has_condition() (the exact
##      method CombineActionController itself calls), not a double.

const ResolutionPortClass     = preload("res://core/application/ports/resolution_port.gd")
const ResolveCastUseCaseClass = preload("res://core/application/use_cases/resolve_cast_use_case.gd")
const CombatantClass          = preload("res://core/domain/combatant.gd")
const HexCoordClass           = preload("res://core/geometry/hex_coord.gd")
const SpellClass              = preload("res://core/domain/spell.gd")
const EffectsApplierClass     = preload("res://core/domain/effects_applier.gd")
const EffectKindClass         = preload("res://core/domain/effects/effect_kind.gd")
const DamageEffectClass       = preload("res://core/domain/effects/damage_effect.gd")
const ConditionEffectClass    = preload("res://core/domain/effects/condition_effect.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## SpyResolutionPort -- returns a scripted AttackResult regardless of the
## arguments handed in (mirrors test_resolve_cast_effect_mapping.gd's
## identically-named double).
class SpyResolutionPort:
	extends ResolutionPortClass
	var scripted_result: Dictionary = {}

	func resolve_spell_attack(_attacker, _target, _spell, _defense_type) -> Dictionary:
		return scripted_result


## SpyEffectsApplier -- records every apply() call's (effects, combatants)
## argument tuple, then delegates to a REAL EffectsApplier so the live
## target is genuinely mutated (mirrors test_resolve_cast_effect_mapping.gd's
## identically-named double).
class SpyEffectsApplier:
	extends RefCounted
	var calls: Array = []
	var _real := EffectsApplierClass.new()

	func apply(effects: Array, combatants: Dictionary) -> void:
		calls.append([effects, combatants])
		_real.apply(effects, combatants)


func _frost_breath() -> SpellClass:
	return SpellClass.new(
		"frost_breath", "Frost Breath", 2, 1, SpellClass.Defense.FORTITUDE, 30,
		"2d6+ATTR", "cold", ["Concentrate"], EffectKindClass.DAMAGE,
		{"formula": "2d6+ATTR", "type": "cold"}, "dazed"
	)


func _fire_bolt() -> SpellClass:
	return SpellClass.new("fire_bolt", "Fire Bolt", 2, 0, SpellClass.Defense.REFLEX, 50, "2d8+ATTR", "fire", [])


func _caster_at(hex_coord: HexCoordClass, spell_id: String = "frost_breath") -> CombatantClass:
	var c := CombatantClass.new("marigold_1", "Marigold", "Player", hex_coord)
	c.known_spell_ids = [spell_id]
	c.spellcasting_attribute_score = 4
	c.casting_state = {
		"spell_id": spell_id,
		"remaining_actions": 0,
		"committed_energy": 0,
		"caster_id": "marigold_1",
	}
	return c


func _enemy(id: String, hex_coord: HexCoordClass) -> CombatantClass:
	var e := CombatantClass.new(id, id, "Enemy", hex_coord)
	e.hp_current = 10
	e.hp_max = 10
	e.fortitude = 12
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
# test_criteria #1 -- a forced hit against frost_breath applies Dazed
# ══════════════════════════════════════════════════════════════════════════

func test_hit_against_frost_breath_applies_dazed_condition() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _frost_breath()
	assert_eq(spell.condition_on_hit, "dazed", "fixture assumption: Frost Breath's authored condition_on_hit is 'dazed'")

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _hit_result(7)

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target], resolution_spy)

	assert_true(result.get("success"))
	assert_true(target.has_condition("Dazed"), "a hit against a condition_on_hit=='dazed' spell must apply the Dazed condition to the target")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #2 -- a forced miss against frost_breath never applies Dazed
# ══════════════════════════════════════════════════════════════════════════

func test_miss_against_frost_breath_does_not_apply_dazed_condition() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _frost_breath()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _miss_result()

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target], resolution_spy)

	assert_true(result.get("success"))
	assert_false(target.has_condition("Dazed"), "a miss must never apply the Dazed condition")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #3 -- fire_bolt (condition_on_hit == '') never applies
# Dazed regardless of hit/miss
# ══════════════════════════════════════════════════════════════════════════

func test_fire_bolt_hit_never_applies_dazed_condition() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0), "fire_bolt")
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()
	assert_eq(spell.condition_on_hit, "", "fixture assumption: Fire Bolt has no authored condition_on_hit")

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _hit_result(9)

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target], resolution_spy)

	assert_true(result.get("success"))
	assert_false(target.has_condition("Dazed"), "a spell with no condition_on_hit must never apply Dazed on a hit")


func test_fire_bolt_miss_never_applies_dazed_condition() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0), "fire_bolt")
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _miss_result()

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target], resolution_spy)

	assert_true(result.get("success"))
	assert_false(target.has_condition("Dazed"), "a spell with no condition_on_hit must never apply Dazed on a miss")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #4 -- ConditionEffect is dispatched through the SAME
# _effects_applier.apply() call path as DamageEffect (no new port
# introduced)
# ══════════════════════════════════════════════════════════════════════════

func test_hit_dispatches_both_damage_and_condition_effects_through_the_same_effects_applier_seam() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _frost_breath()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _hit_result(5)
	var effects_spy := SpyEffectsApplier.new()

	var use_case := ResolveCastUseCaseClass.new(effects_spy)
	var result: Dictionary = use_case.execute(caster, spell, [target], resolution_spy)

	assert_true(result.get("success"))
	assert_eq(effects_spy.calls.size(), 2, "a hit against a condition_on_hit spell must dispatch exactly two apply() calls -- one DAMAGE, one CONDITION -- both through the SAME seam")

	var damage_call: Array = effects_spy.calls[0]
	var damage_effects: Array = damage_call[0]
	assert_eq(damage_effects.size(), 1)
	assert_true(damage_effects[0] is DamageEffectClass, "the first dispatched effect must be the DamageEffect")
	assert_eq(damage_effects[0].amount, 5)

	var condition_call: Array = effects_spy.calls[1]
	var condition_effects: Array = condition_call[0]
	var condition_combatants: Dictionary = condition_call[1]
	assert_eq(condition_effects.size(), 1)
	var condition_effect = condition_effects[0]
	assert_true(condition_effect is ConditionEffectClass, "the second dispatched effect must genuinely be a ConditionEffect")
	assert_eq(condition_effect.kind, EffectKindClass.CONDITION)
	assert_eq(condition_effect.target_id, "skeleton")
	assert_eq(condition_effect.condition, "Dazed")
	assert_true(condition_effect.add, "the ConditionEffect must add the tag (active=true)")
	assert_true(condition_effect.is_valid())
	assert_true(condition_combatants.has("skeleton"))
	assert_same(condition_combatants["skeleton"], target, "the SAME target instance must be dispatched -- applied by reference, never a copy")

	assert_true(target.has_condition("Dazed"))
	assert_eq(target.hp_current, 5, "the DamageEffect must still be applied via the shared seam alongside the ConditionEffect")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #5 (regression) -- CombineActionController's existing
# dazed-sync logic reads Combatant.has_condition('Dazed') -- the exact
# method this feature's ConditionEffect dispatch mutates via
# add_condition(). Proven here against the REAL Combatant (no double) so a
# future change to has_condition()/add_condition()'s semantics would also
# break this assertion.
# ══════════════════════════════════════════════════════════════════════════

func test_dazed_condition_is_readable_via_has_condition_for_combine_action_controllers_sync_logic() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _frost_breath()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _hit_result(3)

	var use_case := ResolveCastUseCaseClass.new()
	use_case.execute(caster, spell, [target], resolution_spy)

	# CombineActionController's own dazed-sync call site is:
	#   economy.set_dazed(actor.has_condition("Dazed"))
	# (presentation/combine_action_controller.gd) -- this assertion exercises
	# the identical read against the target this feature just mutated.
	assert_true(target.has_condition("Dazed"), "CombineActionController's has_condition('Dazed') read must observe the condition this feature applies")
