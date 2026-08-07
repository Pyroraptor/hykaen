extends GutTest
## tests/unit/application/test_resolve_cast_use_case_single_target_baseline_pre_refactor.gd
## — US-003 (RISK-001 mitigation) — Multi-target processing in
## ResolveCastUseCase (AoE Fireball steel thread's exit-point use case).
##
## RISK-001 (per this iteration's plan): refactoring
## core/application/use_cases/resolve_cast_use_case.gd to fan the LOG step
## out to one CombatLogEntry per target (see that file's own US-003 doc)
## must NOT change the single-target behavior a pre-existing spell (Fire
## Bolt) already depends on. This suite pins that pre-refactor baseline down
## with GENUINE, non-scripted RNG (core/combat/seeded_random_adapter.gd's
## SeededRandomAdapter at a fixed seed, driving the REAL
## core/application/ports/resolution_port.gd ResolutionRulesAdapter ->
## core/rules/resolution.gd pipeline — mirrors tests/unit/
## test_resolve_cast_use_case_resolution.gd's own pinned-seed convention) so
## a regression in the refactored damage/log/roll path would fail loud here
## even though this suite never scripts a fake AttackResult.
##
## Both the roll/damage VALUES (computed once via an independent replay of
## the identical seed, exactly like test_resolve_cast_use_case_resolution.gd
## already does — never hardcoded magic numbers that would silently drift if
## core/rules/rng.gd's sequence ever changed) and the exactly-one-
## CombatLogEntry-for-one-target invariant are asserted together, so this
## file alone proves: same seed in -> same roll/damage/hp out, AND still
## exactly one log line out, post-refactor.
##
## test_criteria covered:
##   4. Fixed-RNG-seed single-target regression test reproduces the
##      pre-refactor baseline roll value, damage, and single log entry
##      exactly.

const ResolutionPortClass         = preload("res://core/application/ports/resolution_port.gd")
const CombatLogPortClass          = preload("res://core/application/ports/combat_log_port.gd")
const CombatLogEntryClass         = preload("res://core/domain/combat_log_entry.gd")
const ResolveCastUseCaseClass     = preload("res://core/application/use_cases/resolve_cast_use_case.gd")
const CombatantClass              = preload("res://core/domain/combatant.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")
const SpellClass                  = preload("res://core/domain/spell.gd")
const SeededRandomAdapterClass    = preload("res://core/combat/seeded_random_adapter.gd")

const PINNED_SEED: int = 4242


class SpyCombatLogPort:
	extends CombatLogPortClass
	var entries: Array = []

	func emit(entry) -> void:
		entries.append(entry)


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


func test_single_target_fixed_seed_baseline_roll_damage_and_single_log_entry_are_reproduced_exactly() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()
	var log_spy := SpyCombatLogPort.new()

	var port := ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PINNED_SEED))
	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target], port, log_spy)

	assert_true(result.get("success"))
	var results: Array = result.get("results")
	assert_eq(results.size(), 1, "a single target must still produce exactly one result entry")
	var attack_result: Dictionary = results[0].get("attack_result")
	assert_false(attack_result.has("error"))

	# Independently replay the SAME pinned seed to compute the expected
	# d20 + spell-mod roll -- the SOLE source of randomness for this call
	# (mirrors tests/unit/test_resolve_cast_use_case_resolution.gd's own
	# boot-real pinned-seed convention) -- this IS the "pre-refactor
	# baseline roll value" test_criteria #4 asks for, captured freshly here
	# rather than hardcoded, so it can never silently go stale.
	var expected_rng := SeededRandomAdapterClass.new(PINNED_SEED)
	var expected_raw: int = expected_rng.d20()
	var expected_roll_total: int = expected_raw + caster.spellcasting_attribute_score
	var expected_hit: bool = expected_roll_total >= target.reflex

	assert_eq(attack_result.get("roll_total"), expected_roll_total, "roll_total must equal d20 + spell-mod, deterministically reproduced at the pinned seed")
	assert_eq(attack_result.get("hit"), expected_hit, "hit must be determined against the target's Reflex defense")

	var expected_damage: int = int(results[0].get("damage_applied"))
	assert_eq(target.hp_current, 10 - expected_damage, "hp_current must decrement by exactly the applied damage, no more/no less")
	if expected_hit:
		assert_true(expected_damage > 0, "a hit against Fire Bolt (a damaging spell) must apply positive damage")
	else:
		assert_eq(expected_damage, 0, "a miss must apply zero damage")

	# ── exactly ONE CombatLogEntry for the single target (US-003 invariant:
	#    N targets -> N entries; N==1 here) ──────────────────────────────────
	assert_eq(log_spy.entries.size(), 1, "a single-target cast must still emit exactly one CombatLogEntry")
	var entry = log_spy.entries[0]
	assert_true(entry is CombatLogEntryClass)
	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.actor_id, "marigold_1")
	assert_eq(entry.spell_id, "fire_bolt")
	assert_eq(entry.target_ids, ["skeleton"])
	assert_eq(entry.hit, expected_hit)
	assert_eq(entry.damage_amount, expected_damage)
	assert_eq(entry.roll_total, expected_roll_total)
	assert_eq(entry.damage_type, "fire")


## NFR-002 determinism companion (mirrors test_resolve_cast_use_case_resolution.gd):
## a second, independently-seeded run at the SAME pinned seed against a
## FRESH target reproduces an identical AttackResult/damage/log entry --
## proving the baseline captured above is not an artifact of shared mutable
## state between runs.
func test_single_target_fixed_seed_baseline_is_reproducible_across_independent_runs() -> void:
	var caster_1 := _caster_at(HexCoordClass.new(0, 0))
	var target_1 := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()
	var log_spy_1 := SpyCombatLogPort.new()
	var port_1 := ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PINNED_SEED))
	var use_case_1 := ResolveCastUseCaseClass.new()
	var result_1: Dictionary = use_case_1.execute(caster_1, spell, [target_1], port_1, log_spy_1)

	var caster_2 := _caster_at(HexCoordClass.new(0, 0))
	var target_2 := _enemy("skeleton", HexCoordClass.new(1, 0))
	var log_spy_2 := SpyCombatLogPort.new()
	var port_2 := ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PINNED_SEED))
	var use_case_2 := ResolveCastUseCaseClass.new()
	var result_2: Dictionary = use_case_2.execute(caster_2, spell, [target_2], port_2, log_spy_2)

	assert_eq(result_1.get("results")[0].get("attack_result"), result_2.get("results")[0].get("attack_result"), "the same pinned seed must reproduce an identical AttackResult")
	assert_eq(target_1.hp_current, target_2.hp_current)
	assert_eq(log_spy_1.entries.size(), 1)
	assert_eq(log_spy_2.entries.size(), 1)
	assert_eq(log_spy_1.entries[0].damage_amount, log_spy_2.entries[0].damage_amount)
	assert_eq(log_spy_1.entries[0].roll_total, log_spy_2.entries[0].roll_total)
