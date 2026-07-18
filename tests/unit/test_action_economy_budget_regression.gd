extends GutTest
## tests/unit/test_action_economy_budget_regression.gd
##
## GUT regression suite for FEAT-006 (US-006 / FR-009): confirms the
## existing CR-001 seven-action-per-round shared budget and reaction
## handling on core/rules/action_economy.gd's ActionEconomy remain correct,
## UNCHANGED, after the FEAT-003 (one-action-per-turn gate) and FEAT-004
## (RoundSession single cursor-advance start_of_turn() seam) changes.
##
## This file introduces NO production code changes (files_to_modify: [] —
## see the FEAT-006 spec) — it is a pure regression/characterization suite
## over the ALREADY-SHIPPED contract documented in
## core/rules/action_economy.gd and exercised piecemeal by
## tests/unit/test_action_economy.gd, tests/unit/test_action_economy_gate.gd,
## and tests/unit/test_round_session_turn_cursor.gd. Consolidates the
## specific CR-001/FEAT-003/FEAT-004 interaction scenarios called out by
## FEAT-006's test_criteria into one focused suite:
##
##   1. The full CR-001 budget regression (7 actions/round, shared across
##      MULTIPLE interleaved turns, for MULTIPLE independently-tracked
##      actors, including a mixed action/reaction spend sequence) still
##      passes unmodified.
##   2. A reaction spent mid-round, in the gap BETWEEN two other actors'
##      turns (i.e. out-of-turn for the reacting actor), correctly
##      decrements the reacting actor's shared per-round budget — and is
##      never blocked by that actor's OWN _action_used flag, regardless of
##      whether _action_used happens to be true or false at the moment the
##      reaction is spent.
##   3. Round exhaustion (actions_remaining==0) correctly sets is_spent()
##      true and blocks all further spend_action()/spend_reaction() calls
##      with the shipped budget-exhausted rejection.
##
## Section 4 drives the SAME reaction-independent-of-turn-ownership scenario
## through the REAL core/application/round_session.gd RoundSession
## cursor-advance machinery (FEAT-004), confirming the regression holds not
## just for ActionEconomy in isolation but for the actual turn-order
## orchestration seam that now owns every start_of_turn() call site.

const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")


# ══════════════════════════════════════════════════════════════════════════
# Section 1 (test_criteria #1): full CR-001 budget regression — 7 actions
# per round, shared across interleaved turns — unmodified after FEAT-003/
# FEAT-004.
# ══════════════════════════════════════════════════════════════════════════

func test_seven_actions_exhaust_a_single_actors_round_budget_across_interleaved_turns() -> void:
	# Mirrors tests/unit/test_action_economy.gd's CR-001 acceptance test —
	# reproduced here as an explicit FEAT-006 regression checkpoint.
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	for i in range(6):
		ae.start_of_turn()
		var result: Dictionary = ae.spend_action({})
		assert_true(result.get("success"), "action %d of 7 must succeed" % (i + 1))
		assert_false(ae.is_spent(), "is_spent must be false after action %d of 7" % (i + 1))

	ae.start_of_turn()
	var last: Dictionary = ae.spend_action({})
	assert_true(last.get("success"), "7th spend_action() must succeed")
	assert_eq(last.get("remaining"), 0, "remaining must be 0 after the 7th action")
	assert_true(ae.is_spent(), "is_spent must be true after the 7th action exhausts the round budget")


func test_two_actors_maintain_independent_seven_action_budgets_while_interleaving_turns() -> void:
	# AC-4 interleaving with TWO actors: actor turns alternate (A, B, A, B, ...)
	# within the same round. Each actor's OWN 7-action budget must be
	# unaffected by the other actor's spends.
	var actor_a := ActionEconomyClass.new()
	var actor_b := ActionEconomyClass.new()
	actor_a.start_of_round()
	actor_b.start_of_round()

	# Interleave: A spends 4 actions across 4 of its own turns, B spends 3
	# actions across 3 of its own turns, in strict alternation.
	for i in range(4):
		actor_a.start_of_turn()
		var a_result: Dictionary = actor_a.spend_action({})
		assert_true(a_result.get("success"), "actor A's spend %d must succeed" % (i + 1))

		if i < 3:
			actor_b.start_of_turn()
			var b_result: Dictionary = actor_b.spend_action({})
			assert_true(b_result.get("success"), "actor B's spend %d must succeed" % (i + 1))

	assert_eq(actor_a.get_remaining(), 3, "actor A must have spent exactly 4 of its own 7 actions")
	assert_eq(actor_b.get_remaining(), 4, "actor B must have spent exactly 3 of its own 7 actions, unaffected by A's spends")
	assert_false(actor_a.is_spent(), "actor A must not be Spent yet")
	assert_false(actor_b.is_spent(), "actor B must not be Spent yet")


func test_mixed_action_and_reaction_spends_across_interleaved_turns_share_one_round_budget() -> void:
	# CR-001 AC-3: actions and reactions draw from the SAME per-round pool,
	# regardless of turn ownership, across many interleaved turns.
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	ae.start_of_turn()
	ae.spend_action({})       # 1
	ae.spend_reaction()       # 2
	ae.start_of_turn()
	ae.spend_action({})       # 3
	ae.spend_reaction()       # 4
	ae.start_of_turn()
	ae.spend_action({})       # 5
	ae.spend_reaction()       # 6
	assert_eq(ae.get_remaining(), 1, "6 mixed spends must leave exactly 1 of 7 actions remaining")
	assert_false(ae.is_spent(), "is_spent must be false with 1 action remaining")

	ae.start_of_turn()
	var final_result: Dictionary = ae.spend_action({})
	assert_true(final_result.get("success"), "the 7th mixed spend must succeed")
	assert_eq(final_result.get("remaining"), 0, "remaining must be 0 after the 7th mixed spend")
	assert_true(ae.is_spent(), "is_spent must be true once all 7 mixed action/reaction spends are consumed")


# ══════════════════════════════════════════════════════════════════════════
# Section 2 (test_criteria #2): a reaction spent mid-round, between two
# other actors' turns, decrements the reacting actor's shared budget without
# being blocked by that actor's own _action_used flag.
# ══════════════════════════════════════════════════════════════════════════

func test_reaction_between_two_other_actors_turns_decrements_reacting_actors_budget() -> void:
	# The reacting actor (C) has NOT started a turn this round yet when it
	# reacts to something happening during another actor's turn.
	var actor_c := ActionEconomyClass.new()
	actor_c.start_of_round()

	# Simulated: it is some OTHER actor's turn; actor_c reacts out-of-turn.
	var reaction_result: Dictionary = actor_c.spend_reaction()
	assert_true(reaction_result.get("success"), "an out-of-turn reaction must succeed")
	assert_eq(actor_c.get_remaining(), 6, "the reaction must decrement actor_c's shared round budget to 6")

	# actor_c's own turn arrives later in the round — the earlier reaction's
	# deduction must have persisted.
	actor_c.start_of_turn()
	var action_result: Dictionary = actor_c.spend_action({})
	assert_true(action_result.get("success"), "actor_c's own-turn action must succeed")
	assert_eq(
		action_result.get("budget_remaining"), 5,
		"actor_c's own-turn action must spend from the pool already reduced by the earlier out-of-turn reaction"
	)


func test_reaction_spent_mid_round_is_not_blocked_by_reacting_actors_own_action_used_flag_when_true() -> void:
	# actor_c takes its own turn first (tripping _action_used=true), THEN,
	# during a DIFFERENT actor's subsequent turn later in the round, actor_c
	# spends a reaction. The reaction must succeed — spend_reaction() is
	# documented as completely unaffected by _action_used (FEAT-003).
	var actor_c := ActionEconomyClass.new()
	actor_c.start_of_round()

	actor_c.start_of_turn()
	var own_turn_action: Dictionary = actor_c.spend_action({})
	assert_true(own_turn_action.get("success"), "fixture assumption: actor_c's own action must succeed")
	assert_false(actor_c.can_take_action(), "fixture assumption: _action_used must now be true for actor_c")

	# -- another actor's turn happens here (not modeled; actor_c's own
	# ActionEconomy instance is untouched by other actors' economies) --

	var mid_round_reaction: Dictionary = actor_c.spend_reaction()
	assert_true(
		mid_round_reaction.get("success"),
		"a reaction spent mid-round, between two other actors' turns, must succeed even though actor_c's own _action_used flag is true"
	)
	assert_eq(
		mid_round_reaction.get("budget_remaining"), 5,
		"the mid-round reaction must decrement actor_c's shared budget normally (7 - 1 action - 1 reaction = 5)"
	)


func test_reaction_spent_mid_round_before_reacting_actors_first_turn_never_trips_action_used() -> void:
	# Symmetric case: _action_used is false (actor_c hasn't acted yet this
	# round at all) when the mid-round reaction fires — the reaction must
	# succeed, AND must never itself trip _action_used, so actor_c's own
	# upcoming first turn still gets its full one-action allowance.
	var actor_c := ActionEconomyClass.new()
	actor_c.start_of_round()

	var reaction_result: Dictionary = actor_c.spend_reaction()
	assert_true(reaction_result.get("success"), "reaction before actor_c's first turn must succeed")

	actor_c.start_of_turn()
	assert_true(
		actor_c.can_take_action(),
		"a reaction must never trip _action_used — can_take_action() must still be true at the start of actor_c's own first turn"
	)
	var own_action: Dictionary = actor_c.spend_action({})
	assert_true(own_action.get("success"), "actor_c's own first spend_action() must still succeed after an earlier out-of-turn reaction")


func test_multiple_reactions_spent_across_several_other_actors_turns_all_decrement_shared_budget() -> void:
	# actor_c reacts THREE separate times, each simulating a different other
	# actor's turn happening in between, before actor_c's own turn ever
	# arrives.
	var actor_c := ActionEconomyClass.new()
	actor_c.start_of_round()

	for i in range(3):
		var result: Dictionary = actor_c.spend_reaction()
		assert_true(result.get("success"), "reaction %d (out-of-turn) must succeed" % (i + 1))

	assert_eq(actor_c.get_remaining(), 4, "3 out-of-turn reactions must leave 4 of 7 actions remaining")

	actor_c.start_of_turn()
	assert_true(actor_c.can_take_action(), "can_take_action() must be true — none of the reactions touched _action_used")
	var action_result: Dictionary = actor_c.spend_action({})
	assert_true(action_result.get("success"), "actor_c's own action must still succeed after 3 out-of-turn reactions")
	assert_eq(action_result.get("budget_remaining"), 3, "budget must reflect all 3 reactions plus this action (7 - 3 - 1 = 3)")


# ══════════════════════════════════════════════════════════════════════════
# Section 3 (test_criteria #3): round exhaustion (actions_remaining==0)
# correctly sets is_spent() true and blocks further spend_action()/
# spend_reaction() calls.
# ══════════════════════════════════════════════════════════════════════════

func test_round_exhaustion_sets_is_spent_true() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	for _i in range(ActionEconomyClass.MAX_BUDGET):
		ae.start_of_turn()
		ae.spend_action({})
	assert_eq(ae.get_remaining(), 0, "budget must be fully exhausted")
	assert_true(ae.is_spent(), "is_spent() must be true once actions_remaining reaches 0")


func test_round_exhaustion_blocks_further_spend_action() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	for _i in range(ActionEconomyClass.MAX_BUDGET):
		ae.start_of_turn()
		ae.spend_action({})
	assert_true(ae.is_spent(), "sanity check: round budget must be exhausted")

	ae.start_of_turn()
	var blocked: Dictionary = ae.spend_action({})
	assert_false(blocked.get("success"), "spend_action() must be blocked once the round budget is exhausted")
	assert_false(blocked.get("ok"), "blocked spend_action() must report ok:false")
	assert_eq(blocked.get("remaining"), 0, "blocked spend_action() must report remaining:0")
	# NOTE: core/rules/action_economy.gd's shipped Result-style reason code
	# for round-budget-exhaustion is "ALREADY_SPENT" (see
	# _already_spent_result()) — this regression suite asserts against the
	# ACTUAL shipped contract, not the aspirational "ROUND_BUDGET_EXHAUSTED"
	# label used in prose elsewhere, since FEAT-006 makes no production code
	# changes.
	assert_eq(
		blocked.get("reason"), "ALREADY_SPENT",
		"blocked spend_action() must report the shipped round-budget-exhausted reason code"
	)
	assert_eq(ae.get_remaining(), 0, "a blocked spend_action() must not further decrement the exhausted budget")


func test_round_exhaustion_blocks_further_spend_reaction() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	for _i in range(ActionEconomyClass.MAX_BUDGET):
		ae.start_of_turn()
		ae.spend_action({})
	assert_true(ae.is_spent(), "sanity check: round budget must be exhausted")

	var blocked: Dictionary = ae.spend_reaction()
	assert_false(blocked.get("success"), "spend_reaction() must be blocked once the round budget is exhausted")
	assert_false(blocked.get("ok"), "blocked spend_reaction() must report ok:false")
	assert_eq(blocked.get("remaining"), 0, "blocked spend_reaction() must report remaining:0")
	assert_eq(
		blocked.get("reason"), "ALREADY_SPENT",
		"blocked spend_reaction() must report the shipped round-budget-exhausted reason code"
	)
	assert_eq(ae.get_remaining(), 0, "a blocked spend_reaction() must not further decrement the exhausted budget")


func test_round_exhaustion_blocking_is_consistent_regardless_of_action_reaction_mix() -> void:
	# Exhaust via a MIX of actions and reactions (not pure actions), then
	# confirm both spend paths are blocked identically afterward.
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()
	ae.spend_action({})     # 1
	ae.spend_reaction()     # 2
	ae.start_of_turn()
	ae.spend_action({})     # 3
	ae.spend_reaction()     # 4
	ae.start_of_turn()
	ae.spend_action({})     # 5
	ae.spend_reaction()     # 6
	ae.start_of_turn()
	ae.spend_action({})     # 7 -- exhausts
	assert_true(ae.is_spent(), "sanity check: mixed spends must exhaust the round budget at 7")

	var blocked_action: Dictionary = ae.spend_action({})
	var blocked_reaction: Dictionary = ae.spend_reaction()
	assert_false(blocked_action.get("success"), "spend_action() must be blocked after mixed-spend exhaustion")
	assert_false(blocked_reaction.get("success"), "spend_reaction() must be blocked after mixed-spend exhaustion")
	assert_eq(ae.get_remaining(), 0, "budget must remain at 0 after both blocked attempts")


func test_round_boundary_reset_lifts_the_exhaustion_block() -> void:
	# Confirms the block from is_spent() is a per-ROUND condition only —
	# end_of_round()/start_of_round() (never start_of_turn()) is what lifts
	# it, matching CR-001 AC-2 (already covered elsewhere, reasserted here as
	# part of this consolidated regression suite).
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	for _i in range(ActionEconomyClass.MAX_BUDGET):
		ae.start_of_turn()
		ae.spend_action({})
	assert_true(ae.is_spent(), "sanity check: round budget must be exhausted")

	ae.start_of_turn()
	var still_blocked: Dictionary = ae.spend_action({})
	assert_false(still_blocked.get("success"), "start_of_turn() alone must NOT lift the round-exhaustion block")

	ae.end_of_round()
	assert_false(ae.is_spent(), "end_of_round() must lift the round-exhaustion block")
	var after_reset: Dictionary = ae.spend_action({})
	assert_true(after_reset.get("success"), "spend_action() must succeed again once the round boundary resets the budget")


# ══════════════════════════════════════════════════════════════════════════
# Section 4: the reaction-independent-of-turn-ownership regression (Section
# 2) reproduced through the REAL RoundSession cursor-advance orchestration
# (FEAT-004), confirming start_of_turn()'s single authoritative call site
# (RoundSession._init / _advance_cursor()) never interferes with an
# out-of-turn spend_reaction() on a DIFFERENT actor's ActionEconomy.
# ══════════════════════════════════════════════════════════════════════════

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


## FakeAIDecisionPort — always PASSes (no target/action chosen). Used here
## purely to let advance_ai_turn() progress the cursor deterministically
## without exercising ResolveActionUseCase (out of scope for this
## budget-focused regression suite — combat resolution is covered
## elsewhere, e.g. tests/unit/core/application/test_round_session.gd).
class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant, _targets: Array) -> Dictionary:
		return {"action_type": "", "target": null}


func _regression_combatant(p_name: String, p_is_enemy: bool, p_combatant_id: String):
	return CombatantClass.from_dict({
		"name":         p_name,
		"combatant_id": p_combatant_id,
		"hp_current":   2000,
		"ac":           10,
		"_is_enemy":    p_is_enemy,
	})


func _regression_entry(combatant) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


func _begin_regression_round(entries: Array, party: Array, enemies: Array):
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var event_sink_port    = FakeEventSinkPort.new()
	var round_history_port = FakeRoundHistoryPort.new()
	var random_number_port = SeededRandomAdapterClass.new(1)

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, FakeAIDecisionPort.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	return run_round_use_case.begin_round(1, party, enemies)


func test_round_session_reaction_between_two_other_actors_turns_is_unaffected_by_cursor_advance() -> void:
	var alpha   = _regression_combatant("Alpha",   false, "alpha")
	var bravo   = _regression_combatant("Bravo",   true,  "bravo")
	var charlie = _regression_combatant("Charlie", false, "charlie")

	var alpha_entry:   Dictionary = _regression_entry(alpha)
	var bravo_entry:   Dictionary = _regression_entry(bravo)
	var charlie_entry: Dictionary = _regression_entry(charlie)
	var entries: Array = [alpha_entry, bravo_entry, charlie_entry]

	var session = _begin_regression_round(entries, [alpha, charlie], [bravo])

	# Cursor order: Alpha -> Bravo -> Charlie. Alpha is the initial current
	# actor; start_of_turn() has been called exactly once for Alpha only
	# (ADR-101/ADR-102 — the single authoritative seam), Charlie's turn has
	# NOT started yet.
	assert_eq(session.current_actor().name, "Alpha", "fixture assumption: Alpha is the initial current actor")

	# While it is Alpha's turn, Charlie reacts out-of-turn (e.g. an
	# opportunity attack against Alpha's action). This must succeed and
	# decrement CHARLIE's own shared round budget, completely independent of
	# whose turn the RoundSession cursor currently points to.
	var charlie_ae = charlie_entry["action_economy"]
	var reaction_result: Dictionary = charlie_ae.spend_reaction()
	assert_true(reaction_result.get("success"), "Charlie's out-of-turn reaction during Alpha's turn must succeed")
	assert_eq(charlie_ae.get_remaining(), 6, "Charlie's reaction must decrement Charlie's own shared round budget to 6")

	# Advance the cursor: Alpha ends turn -> Bravo (Enemy, auto-PASSes via
	# FakeAIDecisionPort) -> Charlie.
	session.end_current_turn()
	assert_eq(session.current_actor().name, "Bravo", "cursor must advance from Alpha to Bravo")

	session.advance_ai_turn()
	assert_eq(session.current_actor().name, "Charlie", "cursor must advance from Bravo to Charlie")

	# Charlie's own turn has now started (RoundSession._advance_cursor()
	# called start_of_turn() on Charlie exactly once, per-turn flags only) —
	# the earlier out-of-turn reaction's budget deduction must have
	# persisted, and Charlie must not be blocked from acting by anything the
	# reaction did.
	var charlie_ae_now = session.current_action_economy()
	assert_true(charlie_ae_now == charlie_ae, "fixture assumption: current_action_economy() must be the SAME ActionEconomy instance Charlie reacted with")
	assert_eq(
		charlie_ae_now.get_remaining(), 6,
		"Charlie's shared budget must still reflect the earlier out-of-turn reaction once Charlie's own turn arrives"
	)
	assert_true(
		charlie_ae_now.can_take_action(),
		"Charlie's start_of_turn() (via RoundSession._advance_cursor()) must leave can_take_action() true — the earlier reaction never touched _action_used"
	)

	var own_turn_action: Dictionary = charlie_ae_now.spend_action({})
	assert_true(own_turn_action.get("success"), "Charlie's own-turn action must succeed after the earlier out-of-turn reaction")
	assert_eq(
		own_turn_action.get("budget_remaining"), 5,
		"Charlie's own-turn action must spend from the SAME pool already reduced by the earlier out-of-turn reaction (7 - 1 reaction - 1 action = 5)"
	)
