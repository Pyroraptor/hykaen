extends GutTest
## tests/unit/test_action_economy_can_take_action.gd
##
## GUT test suite for FEAT-005 (US-005 / FR-003): can_take_action() on
## core/rules/action_economy.gd's ActionEconomy.
##
## can_take_action() is a pure query, no side effects:
##   can_take_action() == (NOT _action_used) AND (NOT is_spent())
##
## This is the single source of truth presentation (verb-bar greying) and
## AI decision logic will both consume as the sole availability check.
##
## Verifies (test_criteria):
##   1. can_take_action() returns true at start_of_turn() before any spend.
##   2. can_take_action() returns false immediately after a successful
##      spend_action() in the same turn.
##   3. can_take_action() returns true again after the next start_of_turn()
##      for that actor.
##   4. can_take_action() returns false when is_spent() is true regardless
##      of _action_used, at round exhaustion.

const ActionEconomyClass = preload("res://core/rules/action_economy.gd")


func test_can_take_action_true_at_start_of_turn_before_any_spend() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	assert_true(
		ae.can_take_action(),
		"can_take_action() must return true at start_of_turn() before any spend"
	)


func test_can_take_action_false_immediately_after_successful_spend_action() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	var result: Dictionary = ae.spend_action({})
	assert_true(result.get("success"), "fixture assumption: spend_action() must succeed")

	assert_false(
		ae.can_take_action(),
		"can_take_action() must return false immediately after a successful spend_action() in the same turn"
	)


func test_can_take_action_true_again_after_next_start_of_turn() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	ae.spend_action({})
	assert_false(ae.can_take_action(), "sanity check: must be false right after spend")

	ae.start_of_turn()
	assert_true(
		ae.can_take_action(),
		"can_take_action() must return true again after the next start_of_turn() for that actor"
	)


func test_can_take_action_false_when_is_spent_regardless_of_action_used() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	# Exhaust the round budget via spend_reaction() (never touches
	# _action_used), so _action_used stays false while is_spent() becomes
	# true -- can_take_action() must still report false.
	for _i in range(ActionEconomyClass.MAX_BUDGET):
		ae.spend_reaction()

	assert_true(ae.is_spent(), "sanity check: round budget must now be exhausted")
	assert_false(
		ae.can_take_action(),
		"can_take_action() must return false when is_spent() is true, even though _action_used was never tripped"
	)
