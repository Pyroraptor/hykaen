extends GutTest
## tests/unit/test_player_free_pass.gd
##
## GUT unit test suite for FEAT-004 (US-002 / FR-002, ADR-010): the player's
## "end turn with no action chosen" free-pass path.
##
## core/application/round_session.gd's end_current_turn() is the ONLY method
## the player-facing "end turn" control (presentation/end_turn_control.gd)
## calls to end the active PLAYER combatant's turn. Unlike
## advance_ai_turn()'s handling of core/combat/ai.gd's null-action sentinel
## (which resolves as an explicit WAIT via core/rules/actions.gd
## Actions.resolve_wait() -> ActionEconomy.spend_action(), spending one
## action from the shared per-round budget — see tests/unit/
## test_wait_action.gd), a PLAYER who ends their turn having chosen no
## action at all must NOT spend anything: end_current_turn() forwards
## straight to the shared cursor-advance/outcome-check tail
## (_after_action_resolved()) and never itself calls spend_action() or
## spend_reaction() on the free-passing combatant's ActionEconomy. This
## preserves the player's full action budget so it remains available for
## later reactions (Dodge/Parry/Block) this same round (US-002).
##
## Verifies (test_criteria):
##   1. A free-passing player's ActionEconomy.budget_remaining is unchanged
##      after the free-pass.
##   2. No ActionEconomy.spend_action() call occurs on the player free-pass
##      path.
##   3. A free-passed player can still be offered a later reaction —
##      is_spent() remains false, and spend_reaction() still succeeds
##      afterward.

const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")


# ── Test doubles ─────────────────────────────────────────────────────────

## SpyActionEconomy — a real ActionEconomy that additionally counts every
## spend_action() call it receives (mirrors tests/unit/test_wait_action.gd's
## identically-named double), so criterion 2 can assert the free-pass path
## makes EXACTLY ZERO such calls.
class SpyActionEconomy:
	extends "res://core/rules/action_economy.gd"

	var spend_action_call_count: int = 0

	func spend_action(action_metadata: Dictionary) -> Dictionary:
		spend_action_call_count += 1
		return super.spend_action(action_metadata)


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


## FakeAIDecisionPort — always PASSes (no target/action chosen). Only used
## here to let an Enemy entry exist in the turn order without exercising
## ResolveActionUseCase — this suite is exclusively about the PLAYER
## free-pass path.
class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant: Dictionary, _targets: Array) -> Dictionary:
		return {"action_type": "", "target": {}}


# ── Shared fixture helpers ─────────────────────────────────────────────────

func _player_combatant(p_name: String = "Titus") -> Dictionary:
	return {
		"name":        p_name,
		"combatant_id": p_name.to_lower(),
		"hp_current":  20,
		"ac":          14,
		"strength":    3,
		"_is_enemy":   false,
	}


func _enemy_combatant(p_name: String = "Goblin") -> Dictionary:
	return {
		"name":        p_name,
		"combatant_id": p_name.to_lower(),
		"hp_current":  20,
		"ac":          12,
		"strength":    2,
		"_is_enemy":   true,
	}


func _entry(combatant: Dictionary, action_economy = null) -> Dictionary:
	return {"combatant": combatant, "action_economy": action_economy if action_economy != null else ActionEconomyClass.new()}


func _begin_session(entries: Array, party: Array, enemies: Array):
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

	return run_round_use_case.begin_round(1, party, enemies)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: a free-passing player's ActionEconomy.budget_remaining is
# unchanged after the free-pass.
# ══════════════════════════════════════════════════════════════════════════

func test_free_pass_leaves_budget_remaining_unchanged() -> void:
	var titus: Dictionary = _player_combatant()
	var goblin: Dictionary = _enemy_combatant()
	var titus_ae = ActionEconomyClass.new()
	var entries: Array = [_entry(titus, titus_ae), _entry(goblin)]

	var session = _begin_session(entries, [titus], [goblin])
	assert_eq(session.current_actor().get("name", ""), "Titus", "fixture assumption: the player must be current actor")

	var budget_before: int = titus_ae.get_remaining()
	assert_eq(budget_before, ActionEconomyClass.MAX_BUDGET, "fixture assumption: a fresh combatant starts with the full budget")

	var result: Dictionary = session.end_current_turn()

	assert_true(result.get("ok", false), "the player's free-pass must succeed")
	assert_eq(
		titus_ae.get_remaining(), budget_before,
		"a free-passing player's budget_remaining must be unchanged by the free-pass"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: no ActionEconomy.spend_action() call occurs on the player
# free-pass path.
# ══════════════════════════════════════════════════════════════════════════

func test_free_pass_never_calls_spend_action() -> void:
	var titus: Dictionary = _player_combatant()
	var goblin: Dictionary = _enemy_combatant()
	var titus_ae = SpyActionEconomy.new()
	var entries: Array = [_entry(titus, titus_ae), _entry(goblin)]

	var session = _begin_session(entries, [titus], [goblin])
	assert_eq(session.current_actor().get("name", ""), "Titus", "fixture assumption: the player must be current actor")

	session.end_current_turn()

	assert_eq(
		titus_ae.spend_action_call_count, 0,
		"the player's free-pass path must never call ActionEconomy.spend_action()"
	)


func test_free_pass_never_calls_spend_action_across_repeated_turns() -> void:
	# The player free-passes several of their OWN turns in a row (the enemy
	# also free-passing / WAITing in between via FakeAIDecisionPort's
	# null-action sentinel resolving through advance_ai_turn()'s WAIT path --
	# out of scope here, this suite only inspects the PLAYER's economy). No
	# matter how many times the player free-passes, spend_action() must never
	# be invoked on their ActionEconomy.
	var titus: Dictionary = _player_combatant()
	var goblin: Dictionary = _enemy_combatant()
	var titus_ae = SpyActionEconomy.new()
	var entries: Array = [_entry(titus, titus_ae), _entry(goblin)]

	var session = _begin_session(entries, [titus], [goblin])

	for _i in range(3):
		if session.current_actor().get("_is_enemy", false):
			session.advance_ai_turn()
		else:
			session.end_current_turn()

	assert_eq(
		titus_ae.spend_action_call_count, 0,
		"repeated player free-passes must never call ActionEconomy.spend_action()"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: a free-passed player can still be offered a later reaction --
# is_spent() remains false, and spend_reaction() still succeeds afterward.
# ══════════════════════════════════════════════════════════════════════════

func test_free_passed_player_is_not_spent_and_can_still_react() -> void:
	var titus: Dictionary = _player_combatant()
	var goblin: Dictionary = _enemy_combatant()
	var titus_ae = ActionEconomyClass.new()
	var entries: Array = [_entry(titus, titus_ae), _entry(goblin)]

	var session = _begin_session(entries, [titus], [goblin])
	session.end_current_turn()

	assert_false(
		titus_ae.is_spent(),
		"a free-passed player must not be marked Spent -- their budget was never touched"
	)

	var reaction_result: Dictionary = titus_ae.spend_reaction()
	assert_true(
		reaction_result.get("success", false),
		"a free-passed player must still be able to spend a later reaction (e.g. Dodge/Parry/Block) this round"
	)
	assert_eq(
		reaction_result.get("remaining", -1), ActionEconomyClass.MAX_BUDGET - 1,
		"the reaction must draw from the player's still-full budget, undiminished by the earlier free-pass"
	)


func test_free_passed_player_retains_full_budget_for_multiple_later_reactions() -> void:
	var titus: Dictionary = _player_combatant()
	var goblin: Dictionary = _enemy_combatant()
	var titus_ae = ActionEconomyClass.new()
	var entries: Array = [_entry(titus, titus_ae), _entry(goblin)]

	var session = _begin_session(entries, [titus], [goblin])
	session.end_current_turn()

	# The free-pass spent nothing, so the player's full MAX_BUDGET is
	# available for reactions -- exercise a few to demonstrate the budget
	# was genuinely preserved, not merely reported unchanged.
	for i in range(ActionEconomyClass.MAX_BUDGET):
		var result: Dictionary = titus_ae.spend_reaction()
		assert_true(result.get("success", false), "reaction %d must succeed against the preserved budget" % (i + 1))

	assert_true(titus_ae.is_spent(), "after MAX_BUDGET reactions the budget is legitimately exhausted")
