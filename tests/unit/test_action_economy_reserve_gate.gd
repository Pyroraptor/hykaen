extends GutTest
## tests/unit/test_action_economy_reserve_gate.gd
##
## GUT test suite for iteration K FEAT-003 (US-003, ADR-003): the RESERVE
## constant on core/rules/action_economy.gd's ActionEconomy -- the domain
## half of the budget-aware reaction reserve gate whose GATING BEHAVIOR
## lives in infrastructure/ai_reaction_policy.gd's choose() (see
## tests/infrastructure/test_ai_reaction_policy.gd for the full
## Dodge/Parry/Block-suppression coverage). This suite pins RESERVE's own
## value/identity as the single authoritative source the policy reads,
## independent of any policy-level test double.
##
## Verifies (test_criteria):
##   1. RESERVE == 1 (>=1 action retained for the reactor's own next turn,
##      per ADR-003 / this iteration's governing constants).
##   2. RESERVE is a distinct constant from MAX_BUDGET -- never accidentally
##      coupled/aliased.
##   3. A fresh (full-budget) ActionEconomy satisfies the reserve inequality
##      (get_remaining() - 1 >= RESERVE); an ActionEconomy drained to exactly
##      1 violates it (get_remaining() - 1 < RESERVE) -- the exact real-object
##      shape ai_reaction_policy.gd's gate is evaluated against.
##   4. action_economy.gd remains domain-pure (no Node/Control inheritance) —
##      RESERVE introduces no framework dependency.

const ActionEconomyClass = preload("res://core/rules/action_economy.gd")


func test_reserve_constant_equals_one() -> void:
	assert_eq(
		ActionEconomyClass.RESERVE, 1,
		"RESERVE must equal 1 -- keep >=1 action for the reactor's own next turn (ADR-003)"
	)


func test_reserve_is_distinct_from_max_budget() -> void:
	assert_ne(
		ActionEconomyClass.RESERVE, ActionEconomyClass.MAX_BUDGET,
		"RESERVE must be its own constant, never accidentally aliased to MAX_BUDGET"
	)


func test_fresh_action_economy_satisfies_reserve_inequality() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	assert_true(
		ae.get_remaining() - 1 >= ActionEconomyClass.RESERVE,
		"a fresh, full-budget ActionEconomy must satisfy the reserve inequality (safe to react)"
	)


func test_action_economy_drained_to_one_violates_reserve_inequality() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	for _i in range(ActionEconomyClass.MAX_BUDGET - 1):
		ae.spend_reaction()
	assert_eq(ae.get_remaining(), 1, "fixture assumption: budget must be drained to exactly 1")

	assert_false(
		ae.get_remaining() - 1 >= ActionEconomyClass.RESERVE,
		"an ActionEconomy drained to budget=1 must violate the reserve inequality (unsafe to react)"
	)


func test_action_economy_drained_to_two_satisfies_reserve_inequality() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	for _i in range(ActionEconomyClass.MAX_BUDGET - 2):
		ae.spend_reaction()
	assert_eq(ae.get_remaining(), 2, "fixture assumption: budget must be drained to exactly 2")

	assert_true(
		ae.get_remaining() - 1 >= ActionEconomyClass.RESERVE,
		"an ActionEconomy at budget=2 satisfies the reserve inequality: reacting leaves exactly RESERVE (1)"
	)


func test_action_economy_gd_no_node_inheritance_still_holds_with_reserve_added() -> void:
	var file := FileAccess.open("res://core/rules/action_economy.gd", FileAccess.READ)
	assert_not_null(file, "core/rules/action_economy.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"action_economy.gd must not contain 'extends Node' after adding RESERVE -- ADR-001 domain purity"
	)
	assert_false(
		content.contains("extends Control"),
		"action_economy.gd must not contain 'extends Control' after adding RESERVE -- ADR-001 domain purity"
	)
