extends GutTest
## tests/unit/application/test_round_session_ai_world_context.gd
##
## FEAT-008 (US-008 / FR-015) — GUT suite for the new APPLICATION-layer
## private helper core/application/round_session.gd
## RoundSession._build_ai_world_context(combatant, action_economy).
##
## This helper assembles the AIWorldContext DTO { party, enemies,
## action_economy } handed to a DOMAIN planner's plan_turn() call, isolating
## planners from RoundSession's own internal `_party`/`_enemies` state shape
## (design notes' mutation-safety requirement).
##
## Verifies (this feature's test_criteria):
##   1. Dead (hp_current <= 0) party members are excluded from the returned
##      "party" list.
##   2. The returned "enemies" list is a distinct duplicate — mutating it
##      (e.g. appending/removing elements) does not affect RoundSession's
##      own internal `_enemies` collection.
##   3. The "action_economy" key is present and references (is_same as) the
##      passed-in ActionEconomy instance verbatim.
##
## Mirrors tests/unit/core/application/test_round_session.gd's established
## "build a REAL RunRoundUseCase/RoundSession, fake only the outer ports"
## rig convention (no phantom-method-on-a-spy risk), and its established
## "call a private-by-convention helper directly on the session" pattern
## (e.g. that suite's `session._safe_weapons(...)` calls).

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")


# ── Fake/double port implementations (mirrors test_round_session.gd) ───────

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


## FakeAIDecisionPort — never actually invoked by this suite (every test
## calls the private _build_ai_world_context() helper directly rather than
## driving a full advance_ai_turn() cycle), but RunRoundUseCase's
## constructor requires an AIDecisionPort-shaped collaborator regardless.
class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant, _targets: Array) -> Dictionary:
		return {"action_type": "", "target": null}


# ── Shared fixture helpers ─────────────────────────────────────────────────

func _living_combatant(p_name: String, p_is_enemy: bool):
	return CombatantClass.from_dict({
		"name":       p_name,
		"hp_current": 10,
		"ac":         10,
		"strength":   1,
		"dexterity":  1,
		"intuition":  1,
		"_is_enemy":  p_is_enemy,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 4
		}
	})


func _dead_combatant(p_name: String, p_is_enemy: bool):
	var combatant = _living_combatant(p_name, p_is_enemy)
	combatant.hp_current = 0
	return combatant


## Builds a fully-wired, REAL RunRoundUseCase/RoundSession (mirroring
## test_round_session.gd's explicit "no phantom-method-on-a-spy" convention)
## plus its fake outer ports.
func _make_use_case(entries: Array, seed: int) -> Dictionary:
	var turn_order_port     = FakeTurnOrderPort.new(entries)
	var event_sink_port     = FakeEventSinkPort.new()
	var round_history_port  = FakeRoundHistoryPort.new()
	var random_number_port  = SeededRandomAdapterClass.new(seed)
	var ai_decision_port    = FakeAIDecisionPort.new()

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, ai_decision_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	return {"use_case": run_round_use_case}


# ══════════════════════════════════════════════════════════════════════════
# 1. Dead party members excluded from the returned "party" list
# ══════════════════════════════════════════════════════════════════════════

func test_dead_party_members_are_excluded_from_context_party() -> void:
	var alive_ally = _living_combatant("Alive Ally", false)
	var dead_ally  = _dead_combatant("Dead Ally", false)
	var enemy      = _living_combatant("Goblin", true)

	var rig = _make_use_case([], 1)
	var session = rig["use_case"].begin_round(1, [alive_ally, dead_ally], [enemy])

	var action_economy := ActionEconomyClass.new()
	var context: Dictionary = session._build_ai_world_context(enemy, action_economy)

	assert_true(context.has("party"), "AIWorldContext must carry a 'party' key")
	assert_true(context["party"].has(alive_ally), "a living (hp_current > 0) party member must be included")
	assert_false(context["party"].has(dead_ally), "a dead (hp_current <= 0) party member must be excluded")
	assert_eq(context["party"].size(), 1, "only the single living party member should be present")


func test_all_party_members_included_when_none_are_dead() -> void:
	var alpha = _living_combatant("Alpha", false)
	var bravo = _living_combatant("Bravo", false)
	var enemy = _living_combatant("Goblin", true)

	var rig = _make_use_case([], 2)
	var session = rig["use_case"].begin_round(1, [alpha, bravo], [enemy])

	var action_economy := ActionEconomyClass.new()
	var context: Dictionary = session._build_ai_world_context(enemy, action_economy)

	assert_eq(context["party"].size(), 2, "every living party member must be present when none are dead")
	assert_true(context["party"].has(alpha))
	assert_true(context["party"].has(bravo))


# ══════════════════════════════════════════════════════════════════════════
# 2. Returned "enemies" list is a distinct duplicate (mutation-safety)
# ══════════════════════════════════════════════════════════════════════════

func test_context_enemies_is_a_distinct_array_not_the_internal_reference() -> void:
	var ally     = _living_combatant("Ally", false)
	var goblin_a = _living_combatant("Goblin A", true)
	var goblin_b = _living_combatant("Goblin B", true)

	var rig = _make_use_case([], 3)
	var session = rig["use_case"].begin_round(1, [ally], [goblin_a, goblin_b])

	var action_economy := ActionEconomyClass.new()
	var context: Dictionary = session._build_ai_world_context(goblin_a, action_economy)

	assert_true(context.has("enemies"), "AIWorldContext must carry an 'enemies' key")
	assert_eq(context["enemies"], session._enemies, "returned enemies content must match RoundSession's internal _enemies")
	assert_not_same(context["enemies"], session._enemies, "returned enemies Array must be a distinct object, not an alias of _enemies")


func test_mutating_context_enemies_does_not_affect_internal_enemies() -> void:
	var ally     = _living_combatant("Ally", false)
	var goblin_a = _living_combatant("Goblin A", true)

	var rig = _make_use_case([], 4)
	var session = rig["use_case"].begin_round(1, [ally], [goblin_a])

	var action_economy := ActionEconomyClass.new()
	var context: Dictionary = session._build_ai_world_context(goblin_a, action_economy)
	var original_internal_size: int = session._enemies.size()

	# Mutate the DTO's enemies array (append + remove) exactly as a careless
	# DOMAIN planner might.
	context["enemies"].append(_living_combatant("Intruder", true))
	context["enemies"].pop_front()

	assert_eq(session._enemies.size(), original_internal_size, "mutating the returned enemies Array must never resize RoundSession's internal _enemies")
	assert_true(session._enemies.has(goblin_a), "RoundSession's internal _enemies must still contain the original enemy after the DTO copy was mutated")


# ══════════════════════════════════════════════════════════════════════════
# 3. "action_economy" key present and references the passed-in ActionEconomy
# ══════════════════════════════════════════════════════════════════════════

func test_context_action_economy_is_the_same_instance_passed_in() -> void:
	var ally  = _living_combatant("Ally", false)
	var enemy = _living_combatant("Goblin", true)

	var rig = _make_use_case([], 5)
	var session = rig["use_case"].begin_round(1, [ally], [enemy])

	var action_economy := ActionEconomyClass.new()
	var context: Dictionary = session._build_ai_world_context(enemy, action_economy)

	assert_true(context.has("action_economy"), "AIWorldContext must carry an 'action_economy' key")
	assert_same(context["action_economy"], action_economy, "context's action_economy must be the SAME ActionEconomy instance passed in, not a copy")
