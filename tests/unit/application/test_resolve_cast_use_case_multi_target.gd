extends GutTest
## tests/unit/application/test_resolve_cast_use_case_multi_target.gd —
## US-003 (FR-005; ADR-003) — Multi-target processing in ResolveCastUseCase
## (AoE Fireball steel thread's exit-point use case).
##
## GUT suite for core/application/use_cases/resolve_cast_use_case.gd's
## multi-target fan-out: presentation/verbs/resolve_spell_controller.gd's
## AoE branch (US-005) filters the live combatant roster down to an
## Array[Combatant] and hands the WHOLE array to ResolveCastUseCase.execute()
## in one call — this suite proves that call genuinely processes EVERY
## target independently rather than only the first (the loop itself already
## existed from FEAT-009/FEAT-010; this feature's own change is that the LOG
## step now fans out to one CombatLogEntry PER target instead of FEAT-276's
## single aggregated entry — see resolve_cast_use_case.gd's own US-003 doc).
##
## This codebase has no standalone "RngPort" type — core/application/ports/
## resolution_port.gd's ResolutionPort is the seam ResolveCastUseCase
## actually rolls dice through (its concrete ResolutionRulesAdapter wraps a
## RandomNumberPort internally). `QueueResolutionPort` below plays the role
## test_criteria describes as "an injected RngPort stub returning distinct
## sequential values": a duck-typed ResolutionPort double that hands back a
## DIFFERENT scripted AttackResult on each successive resolve_spell_attack()
## call, in call order — proving each target's roll is independently
## resolved rather than the caster's own single roll being broadcast to
## every target. Mirrors tests/unit/test_resolve_cast_use_case_resolution.gd's
## SpyResolutionPort call-recording convention, extended with a per-call
## result queue.
##
## test_criteria covered:
##   1. 3 targets each receive independent rolls (QueueResolutionPort
##      returns 3 distinct scripted results, one per call, verified via
##      call-argument recording) and each produces exactly one
##      CombatLogEntry.
##   2. Damage and condition-on-hit are applied independently per target
##      (one hit+dazed, one hit+not-dazed-eligible-spell-variant covered
##      elsewhere, one miss) driven by the distinct per-target rolls.
##   3. Empty targets array -> {success:true}, results ("damage_events") ==
##      [], zero CombatLogEntries emitted, no target Combatant mutated.
##   4. Regression: the pre-existing insufficient-energy pre-flight gate
##      (BeginCastUseCase, upstream of ResolveCastUseCase in the Cast-a-Spell
##      pipeline — see rationale below) is unaffected by this refactor.

const ResolutionPortClass     = preload("res://core/application/ports/resolution_port.gd")
const CombatLogPortClass      = preload("res://core/application/ports/combat_log_port.gd")
const CombatLogEntryClass     = preload("res://core/domain/combat_log_entry.gd")
const ResolveCastUseCaseClass = preload("res://core/application/use_cases/resolve_cast_use_case.gd")
const CombatantClass          = preload("res://core/domain/combatant.gd")
const HexCoordClass           = preload("res://core/geometry/hex_coord.gd")
const SpellClass              = preload("res://core/domain/spell.gd")
const ErrorCodeClass          = preload("res://core/application/ports/errors.gd")
const BeginCastUseCaseClass   = preload("res://core/application/use_cases/begin_cast_use_case.gd")
const EffectKindClass         = preload("res://core/domain/effects/effect_kind.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## QueueResolutionPort -- a duck-typed ResolutionPort double that returns a
## DIFFERENT scripted AttackResult on each successive resolve_spell_attack()
## call (FIFO), and records every (attacker, target, spell, defense_type)
## call tuple -- this suite's stand-in for "an injected RngPort stub
## returning distinct sequential values" (see file-level doc).
class QueueResolutionPort:
	extends ResolutionPortClass
	var scripted_results: Array = []
	var calls: Array = []

	func resolve_spell_attack(attacker, target, spell, defense_type) -> Dictionary:
		calls.append([attacker, target, spell, defense_type])
		if scripted_results.is_empty():
			return {"hit": false, "crit": false, "roll_total": 0, "damage_raw": 0, "active_defense_applied": "none", "damage_final": 0}
		return scripted_results.pop_front()


## SpyCombatLogPort -- records every emit() call's entry argument.
class SpyCombatLogPort:
	extends CombatLogPortClass
	var entries: Array = []

	func emit(entry) -> void:
		entries.append(entry)


## FakeSpellCatalogPort / FakeRoundEnergyPoolPort / FakeActionEconomy --
## mirrors tests/unit/test_begin_cast_use_case.gd's identically-named
## doubles, reused here (independently, GDScript inner classes are not
## importable across files) purely to prove criterion 4 below: this
## feature's ResolveCastUseCase refactor does not regress the pre-flight
## insufficient-energy gate that already lives, and is already tested, one
## step UPSTREAM of ResolveCastUseCase in the Cast-a-Spell pipeline.
class FakeSpellCatalogPort:
	extends RefCounted
	var spells: Dictionary = {}

	func get_spell(spell_id: String):
		return spells.get(spell_id, null)


class FakeRoundEnergyPoolPort:
	extends RefCounted
	var _balance: int
	var reserve_calls: Array = []

	func _init(starting_balance: int) -> void:
		_balance = starting_balance

	func reserve(caster_id: String, amount: int) -> bool:
		reserve_calls.append([caster_id, amount])
		if _balance < amount:
			return false
		_balance -= amount
		return true

	func balance(_caster_id: String) -> int:
		return _balance


class FakeActionEconomy:
	extends RefCounted
	var spend_calls: Array = []

	func spend_action(action_metadata: Dictionary) -> Dictionary:
		spend_calls.append(action_metadata)
		return {"success": true, "ok": true}


# ══════════════════════════════════════════════════════════════════════════
# Fixtures
# ══════════════════════════════════════════════════════════════════════════

func _fireball() -> SpellClass:
	return SpellClass.new(
		"fireball", "Fireball", 2, 2, SpellClass.Defense.REFLEX, 60,
		"4d6+ATTR", "fire", ["Concentrate"], EffectKindClass.DAMAGE,
		{"formula": "4d6+ATTR", "type": "fire"}, "dazed", 10
	)


func _caster_at(hex_coord: HexCoordClass) -> CombatantClass:
	var c := CombatantClass.new("marigold_1", "Marigold", "Player", hex_coord)
	c.known_spell_ids = ["fireball"]
	c.spellcasting_attribute_score = 4
	c.casting_state = {
		"spell_id": "fireball",
		"remaining_actions": 0,
		"committed_energy": 0,
		"caster_id": "marigold_1",
	}
	return c


func _enemy(id: String, hex_coord: HexCoordClass) -> CombatantClass:
	var e := CombatantClass.new(id, id, "Enemy", hex_coord)
	e.hp_current = 20
	e.hp_max = 20
	e.reflex = 12
	return e


func _hit_result(roll_total: int, damage_final: int) -> Dictionary:
	return {
		"hit": true,
		"crit": false,
		"roll_total": roll_total,
		"damage_raw": damage_final,
		"active_defense_applied": "none",
		"damage_final": damage_final,
	}


func _miss_result(roll_total: int) -> Dictionary:
	return {
		"hit": false,
		"crit": false,
		"roll_total": roll_total,
		"damage_raw": 0,
		"active_defense_applied": "none",
		"damage_final": 0,
	}


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #1/#2 -- 3 targets, independent rolls, independent
# damage/condition-on-hit, one CombatLogEntry per target
# ══════════════════════════════════════════════════════════════════════════

func test_three_targets_each_get_independent_rolls_and_exactly_one_log_entry_each() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target_a := _enemy("skeleton_a", HexCoordClass.new(1, 0))
	var target_b := _enemy("skeleton_b", HexCoordClass.new(1, 1))
	var target_c := _enemy("skeleton_c", HexCoordClass.new(1, -1))
	var spell := _fireball()

	# Three DISTINCT sequential scripted results -- a hit, a miss, and a
	# second (different-magnitude) hit -- proving no two targets observe the
	# same roll/outcome.
	var port := QueueResolutionPort.new()
	port.scripted_results = [
		_hit_result(19, 8),
		_miss_result(3),
		_hit_result(22, 5),
	]
	var log_spy := SpyCombatLogPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target_a, target_b, target_c], port, log_spy)

	assert_true(result.get("success"))

	# ── independent rolls: resolve_spell_attack called once per target ─────
	assert_eq(port.calls.size(), 3, "resolve_spell_attack must be called exactly once per target")
	assert_same(port.calls[0][1], target_a)
	assert_same(port.calls[1][1], target_b)
	assert_same(port.calls[2][1], target_c)

	# ── independent damage application ──────────────────────────────────────
	assert_eq(target_a.hp_current, 12, "target_a took the FIRST scripted hit's damage (8)")
	assert_eq(target_b.hp_current, 20, "target_b's scripted MISS must apply zero damage")
	assert_eq(target_c.hp_current, 15, "target_c took the THIRD scripted hit's own damage (5), independent of target_a's")

	# ── independent condition-on-hit application ────────────────────────────
	assert_true(target_a.has_condition("Dazed"), "a hit against fireball's condition_on_hit=='dazed' must dazes the hit target")
	assert_false(target_b.has_condition("Dazed"), "a miss must never apply Dazed")
	assert_true(target_c.has_condition("Dazed"), "the second, independently-rolled hit must also daze ITS target")

	# ── exactly one CombatLogEntry per target ───────────────────────────────
	assert_eq(log_spy.entries.size(), 3, "exactly one CombatLogEntry must be emitted per target")

	var entry_a = log_spy.entries[0]
	assert_true(entry_a is CombatLogEntryClass)
	assert_eq(entry_a.target_ids, ["skeleton_a"], "each entry must carry ONLY its own target's id")
	assert_true(entry_a.hit)
	assert_eq(entry_a.damage_amount, 8)
	assert_eq(entry_a.roll_total, 19)

	var entry_b = log_spy.entries[1]
	assert_eq(entry_b.target_ids, ["skeleton_b"])
	assert_false(entry_b.hit)
	assert_eq(entry_b.damage_amount, 0)
	assert_eq(entry_b.roll_total, 3)

	var entry_c = log_spy.entries[2]
	assert_eq(entry_c.target_ids, ["skeleton_c"])
	assert_true(entry_c.hit)
	assert_eq(entry_c.damage_amount, 5)
	assert_eq(entry_c.roll_total, 22)

	# Every entry shares the SAME actor/spell (only the per-target fields
	# differ), and carries the spell's damage_type (FEAT-001, NFR-001).
	for entry in log_spy.entries:
		assert_eq(entry.actor_id, "marigold_1")
		assert_eq(entry.spell_id, "fireball")
		assert_eq(entry.damage_type, "fire")
		assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)


func test_results_array_carries_each_targets_own_damage_applied_independently() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target_a := _enemy("skeleton_a", HexCoordClass.new(1, 0))
	var target_b := _enemy("skeleton_b", HexCoordClass.new(1, 1))
	var spell := _fireball()

	var port := QueueResolutionPort.new()
	port.scripted_results = [_hit_result(20, 11), _hit_result(15, 2)]

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target_a, target_b], port)

	var results: Array = result.get("results")
	assert_eq(results.size(), 2)
	assert_eq(results[0].get("target_id"), "skeleton_a")
	assert_eq(results[0].get("damage_applied"), 11)
	assert_eq(results[1].get("target_id"), "skeleton_b")
	assert_eq(results[1].get("damage_applied"), 2)


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #3 -- empty targets: success, no damage_events, no
# CombatLogEntry, no Combatant mutation
# ══════════════════════════════════════════════════════════════════════════

func test_empty_targets_returns_success_with_no_damage_events_no_log_entries_and_no_mutation() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _fireball()

	var port := QueueResolutionPort.new()
	var log_spy := SpyCombatLogPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [], port, log_spy)

	assert_true(result.get("success"), "an empty targets Array is explicitly NOT an error (US-003 AC-3)")
	assert_eq(result.get("results"), [], "damage_events (this codebase's 'results' key) must be empty")
	assert_true(log_spy.entries.is_empty(), "zero CombatLogEntries must be emitted for an empty targets Array")
	assert_true(port.calls.is_empty(), "resolve_spell_attack must never be called when there are no targets")


func test_empty_targets_never_mutates_any_target_combatant() -> void:
	# There ARE no target Combatants in this scenario by construction -- this
	# test documents/pins that fact: an unrelated bystander Combatant, never
	# passed into `targets`, must be provably untouched by the call.
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var bystander := _enemy("bystander", HexCoordClass.new(5, 5))
	var spell := _fireball()

	var use_case := ResolveCastUseCaseClass.new()
	use_case.execute(caster, spell, [], QueueResolutionPort.new())

	assert_eq(bystander.hp_current, 20, "a Combatant never passed as a target must never be mutated")
	assert_false(bystander.has_condition("Dazed"))


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #5 -- insufficient-energy pre-flight error path regression
#
# ResolveCastUseCase itself never checks caster energy (its own file-level
# doc: "assume affordability already validated") -- that pre-flight gate is
# core/application/use_cases/begin_cast_use_case.gd's BeginCastUseCase,
# ONE STEP UPSTREAM of ResolveCastUseCase in the Cast-a-Spell pipeline
# (BeginCastUseCase -> ContinueCastUseCase -> ResolveCastUseCase). This test
# proves that gate -- ErrorCode.ERR_INSUFFICIENT_ENERGY, no casting_state
# set, no action spent, no pool mutation -- is genuinely unaffected by this
# feature's ResolveCastUseCase multi-target/log refactor (RISK-001):
# BeginCastUseCase never even reaches ResolveCastUseCase on this path.
# ══════════════════════════════════════════════════════════════════════════

func test_insufficient_energy_preflight_gate_upstream_of_resolve_cast_is_unaffected_by_this_refactor() -> void:
	var actor := _caster_at(HexCoordClass.new(0, 0))
	actor.casting_state = {}  # not yet casting -- BeginCastUseCase is the entry point here
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fireball"] = _fireball()
	var pool := FakeRoundEnergyPoolPort.new(1)  # fireball costs 2 -- insufficient
	var action_economy := FakeActionEconomy.new()

	var begin_use_case := BeginCastUseCaseClass.new()
	var result: Dictionary = begin_use_case.execute(actor, "fireball", catalog, pool, action_economy)

	assert_false(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_INSUFFICIENT_ENERGY)
	assert_null(result.get("casting_state"))
	assert_false(actor.is_casting(), "no casting_state must be set on a failed reservation")
	assert_eq(action_economy.spend_calls.size(), 0, "no action may be spent when the energy reservation fails")
	assert_eq(pool.balance("marigold_1"), 1, "a failed reservation must leave the pool balance untouched")

	# ResolveCastUseCase is never reached at all on this path -- proven by
	# never having been constructed/called above; this feature's refactor of
	# _emit_combat_log_entries()/the per-target loop has no bearing on it.
