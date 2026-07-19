extends GutTest
## tests/unit/test_round_session_energy_pools.gd
##
## GUT test suite for FEAT-003 (US-003; FR-012, FR-015): the
## `energy_pools: Dictionary[caster_id -> EnergyPool]` collection
## core/application/round_session.gd's RoundSession now holds, exercised
## against a REAL RunRoundUseCase/RoundSession (mirrors
## tests/unit/test_round_session_turn_cursor.gd's isolation strategy — only
## the ports are fakes/doubles, never RoundSession itself).
##
## Verifies (test_criteria):
##   1. get_energy_pool(caster) resolves capacity from the caster's
##      spellcasting_attribute_score, and repeated calls for the SAME caster
##      return the SAME pool instance (never silently reset mid-round).
##   2. finish() (the end_of_round hook) empties every energy pool to 0.
##   3. finish() does NOT touch a caster's committed_energy, simulated here
##      via a separate CastingState-shaped field
##      (Combatant.casting_state["committed_energy"]).

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")


# ── Fake/double port implementations (mirrors test_round_session_turn_cursor.gd) ──

class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant, targets: Array) -> Dictionary:
		for t in targets:
			if t.hp_current > 0:
				return {"action_type": "Strike", "target": t}
		return {"action_type": "", "target": null}


# ── Shared fixture helpers ─────────────────────────────────────────────────

func _caster_combatant(p_name: String, p_score: int, p_combatant_id: String = ""):
	return CombatantClass.from_dict({
		"name":                         p_name,
		"combatant_id":                 p_combatant_id,
		"hp_current":                   20,
		"ac":                           10,
		"strength":                     1,
		"dexterity":                    1,
		"intuition":                    1,
		"_is_enemy":                    false,
		"spellcasting_attribute_score": p_score,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 4
		}
	})


func _entry(combatant) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


func _make_session(entries: Array):
	var turn_order_port     = FakeTurnOrderPort.new(entries)
	var event_sink_port     = FakeEventSinkPort.new()
	var round_history_port  = FakeRoundHistoryPort.new()
	var random_number_port  = SeededRandomAdapterClass.new(1)

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, FakeAIDecisionPort.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	var combatants: Array = []
	for e in entries:
		combatants.append(e["combatant"])

	return run_round_use_case.begin_round(1, combatants, [])


# ══════════════════════════════════════════════════════════════════════════
# Criterion: capacity resolves from spellcasting_attribute_score; clamp-on-add.
# ══════════════════════════════════════════════════════════════════════════

func test_get_energy_pool_resolves_capacity_from_spellcasting_attribute_score() -> void:
	var marigold = _caster_combatant("Marigold", 3, "marigold")
	var entries: Array = [_entry(marigold)]
	var session = _make_session(entries)

	var pool = session.get_energy_pool(marigold)

	assert_eq(pool.capacity, 3, "EnergyPool.capacity must equal the caster's spellcasting_attribute_score")
	assert_eq(pool.current, 0, "a freshly-created pool must start empty")


func test_pool_current_never_exceeds_capacity_via_the_session_seam() -> void:
	var marigold = _caster_combatant("Marigold", 2, "marigold")
	var entries: Array = [_entry(marigold)]
	var session = _make_session(entries)

	var pool = session.get_energy_pool(marigold)
	pool.add(10)

	assert_eq(pool.current, 2, "current must clamp at capacity even when accessed through RoundSession's get_energy_pool() seam")


func test_repeated_get_energy_pool_calls_return_the_same_instance() -> void:
	var marigold = _caster_combatant("Marigold", 3, "marigold")
	var entries: Array = [_entry(marigold)]
	var session = _make_session(entries)

	var pool_a = session.get_energy_pool(marigold)
	pool_a.add(2)
	var pool_b = session.get_energy_pool(marigold)

	assert_eq(pool_b.current, 2, "a second get_energy_pool() call for the SAME caster must return the SAME pool instance, not a freshly-reset one")


# ══════════════════════════════════════════════════════════════════════════
# Criterion: finish() (end_of_round hook) empties every energy pool to 0.
# ══════════════════════════════════════════════════════════════════════════

func test_finish_empties_every_energy_pool_to_zero() -> void:
	var marigold = _caster_combatant("Marigold", 3, "marigold")
	var patience = _caster_combatant("Patience", 2, "patience")
	var entries: Array = [_entry(marigold), _entry(patience)]
	var session = _make_session(entries)

	session.get_energy_pool(marigold).add(3)
	session.get_energy_pool(patience).add(2)

	assert_eq(session.get_energy_pool(marigold).current, 3, "fixture assumption: Marigold's pool is full before finish()")
	assert_eq(session.get_energy_pool(patience).current, 2, "fixture assumption: Patience's pool is full before finish()")

	session.finish()

	assert_eq(session.get_energy_pool(marigold).current, 0, "finish() must empty Marigold's energy pool to 0")
	assert_eq(session.get_energy_pool(patience).current, 0, "finish() must empty Patience's energy pool to 0")


func test_finish_empties_pool_capacity_unchanged() -> void:
	var marigold = _caster_combatant("Marigold", 3, "marigold")
	var entries: Array = [_entry(marigold)]
	var session = _make_session(entries)

	session.get_energy_pool(marigold).add(3)
	session.finish()

	assert_eq(session.get_energy_pool(marigold).capacity, 3, "finish() must never change a pool's capacity, only its current energy")


# ══════════════════════════════════════════════════════════════════════════
# Criterion: finish() must NOT touch a caster's committed_energy
# (simulated on a separate CastingState-shaped field).
# ══════════════════════════════════════════════════════════════════════════

func test_finish_does_not_touch_committed_energy_on_casting_state() -> void:
	var marigold = _caster_combatant("Marigold", 3, "marigold")
	# Simulate an in-progress cast's committed_energy on a SEPARATE
	# CastingState-shaped field (Combatant.casting_state), entirely distinct
	# from the round-scoped EnergyPool this feature adds.
	marigold.casting_state = {"spell_id": "fire_bolt", "remaining_actions": 1, "committed_energy": 2}

	var entries: Array = [_entry(marigold)]
	var session = _make_session(entries)

	session.get_energy_pool(marigold).add(3)
	session.finish()

	assert_eq(
		marigold.casting_state.get("committed_energy", -1), 2,
		"finish()'s pool-emptying must never touch a caster's already-committed energy on casting_state"
	)
	assert_eq(
		marigold.casting_state.get("spell_id", ""), "fire_bolt",
		"finish() must leave the rest of casting_state untouched too"
	)


