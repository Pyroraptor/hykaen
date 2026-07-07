extends GutTest
## tests/unit/test_action_economy_gate.gd
##
## GUT test suite for FEAT-003 (US-003 / FR-002 / ADR-103): the per-turn
## one-action gate on core/rules/action_economy.gd's ActionEconomy.
##
## ActionEconomy now tracks a NEW per-turn flag, _action_used, cleared by
## start_of_turn() and _reset_round_state() (the shared helper behind
## start_of_round()/end_of_round()), and checked by spend_action() BEFORE
## any budget mutation. This is the domain gate the steel thread's "exactly
## one action per turn" business rule depends on.
##
## Verifies (test_criteria):
##   1. spend_action() succeeds once, then rejects a second in-turn call
##      with reason ACTION_ALREADY_USED.
##   2. The rejected second spend_action() does NOT decrement
##      actions_remaining (gate checked before budget mutation).
##   3. Step (core/rules/movement.gd Movement.step()) remains callable and
##      free, unaffected by _action_used.
##   4. spend_reaction() succeeds regardless of _action_used state and only
##      fails once the round budget itself is exhausted.
##   5. start_of_turn() and _reset_round_state() (start_of_round() /
##      end_of_round()) clear _action_used back to false.

const ActionEconomyClass = preload("res://core/rules/action_economy.gd")
const MovementClass      = preload("res://core/rules/movement.gd")
const CombatantClass     = preload("res://core/domain/combatant.gd")
const HexCoordClass      = preload("res://core/geometry/hex_coord.gd")


# ── Criterion 1 & 2: second in-turn spend_action() is rejected with
# ACTION_ALREADY_USED and does NOT decrement actions_remaining. ────────────

func test_second_spend_action_same_turn_rejected_with_action_already_used() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	var first: Dictionary = ae.spend_action({})
	assert_true(first.get("success"), "first spend_action() this turn must succeed")

	var second: Dictionary = ae.spend_action({})
	assert_false(second.get("success"), "second spend_action() in the SAME turn must be rejected")
	assert_eq(
		second.get("reason"),
		"ACTION_ALREADY_USED",
		"rejected second spend_action() must report reason:'ACTION_ALREADY_USED'"
	)
	assert_false(second.get("ok"), "rejected second spend_action() must report ok:false")


func test_rejected_second_spend_action_does_not_decrement_budget() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	ae.spend_action({})
	var budget_after_first: int = ae.get_remaining()
	assert_eq(budget_after_first, ActionEconomyClass.MAX_BUDGET - 1, "sanity check: first spend must decrement budget by exactly 1")

	ae.spend_action({})
	assert_eq(
		ae.get_remaining(),
		budget_after_first,
		"a rejected (ACTION_ALREADY_USED) second spend_action() must NOT further decrement actions_remaining"
	)
	assert_false(ae.is_spent(), "a rejected second spend_action() must not have any budget side effects at all")


func test_gate_checked_before_movement_gate_still_reports_action_already_used() -> void:
	# Even when the second call also carries the Movement trait, the
	# ACTION_ALREADY_USED gate fires first (it is checked before ANY budget
	# mutation, and before the Movement-trait check).
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	ae.spend_action({})
	var result: Dictionary = ae.spend_action({"traits": ["Movement"]})
	assert_false(result.get("success"), "second spend_action() must be rejected regardless of traits")
	assert_eq(
		result.get("reason"),
		"ACTION_ALREADY_USED",
		"ACTION_ALREADY_USED must take priority over MOVEMENT_ALREADY_USED on the second in-turn call"
	)


# ── Criterion 3: Step remains callable and free, unaffected by _action_used. ─

func test_step_remains_callable_and_free_after_action_used() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	var spend_result: Dictionary = ae.spend_action({})
	assert_true(spend_result.get("success"), "fixture assumption: spend_action() must succeed and trip _action_used")

	var budget_before_step: int = ae.get_remaining()

	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var step_result: Dictionary = MovementClass.step(mover, HexCoordClass.new(1, 0), [], ae)

	assert_true(
		step_result.get("ok", false),
		"Step must remain callable after a spend_action() has already tripped _action_used this turn"
	)
	assert_eq(
		ae.get_remaining(),
		budget_before_step,
		"Step must remain free (no budget decrement) even when _action_used is already true"
	)


func test_step_does_not_trip_or_read_action_used_gate() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	var mover := CombatantClass.new("p1", "Titus", "Player", HexCoordClass.new(0, 0))
	var step_result: Dictionary = MovementClass.step(mover, HexCoordClass.new(1, 0), [], ae)
	assert_true(step_result.get("ok", false), "fixture assumption: Step must succeed on a fresh turn")

	# Step trips the SEPARATE _movement_used gate (pre-existing behaviour),
	# never _action_used -- spend_action() (a non-Movement action) must still
	# be free to succeed afterwards.
	var spend_result: Dictionary = ae.spend_action({})
	assert_true(
		spend_result.get("success"),
		"spend_action() (non-Movement) must still succeed after a Step -- Step must not touch _action_used"
	)


# ── Criterion 4: spend_reaction() succeeds regardless of _action_used state,
# only fails once the round budget is exhausted. ────────────────────────────

func test_spend_reaction_succeeds_after_action_used_is_true() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	var spend_result: Dictionary = ae.spend_action({})
	assert_true(spend_result.get("success"), "fixture assumption: spend_action() must succeed and trip _action_used")

	var reaction_result: Dictionary = ae.spend_reaction()
	assert_true(
		reaction_result.get("success"),
		"spend_reaction() must succeed regardless of _action_used state"
	)
	assert_eq(
		ae.get_remaining(),
		ActionEconomyClass.MAX_BUDGET - 2,
		"spend_reaction() must decrement the shared per-round budget normally"
	)


func test_spend_reaction_only_fails_once_round_budget_exhausted() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	# _action_used is true after one spend_action(), yet spend_reaction()
	# keeps succeeding -- it is gated ONLY by the shared round budget, never
	# by _action_used.
	ae.spend_action({})
	for _i in range(ActionEconomyClass.MAX_BUDGET - 1):
		var result: Dictionary = ae.spend_reaction()
		assert_true(result.get("success"), "spend_reaction() must keep succeeding while round budget remains, independent of _action_used")

	assert_true(ae.is_spent(), "sanity check: round budget must now be exhausted")

	var exhausted_result: Dictionary = ae.spend_reaction()
	assert_false(exhausted_result.get("success"), "spend_reaction() must fail once the round budget is exhausted")
	assert_eq(
		exhausted_result.get("reason"),
		"ALREADY_SPENT",
		"spend_reaction() failure once budget-exhausted must report the round-budget-exhausted reason"
	)


# ── Criterion 5: start_of_turn() and _reset_round_state()
# (start_of_round()/end_of_round()) clear _action_used to false. ────────────

func test_start_of_turn_clears_action_used_for_next_turn() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	ae.spend_action({})
	var blocked: Dictionary = ae.spend_action({})
	assert_false(blocked.get("success"), "sanity check: second spend_action() must be blocked before the next start_of_turn()")

	ae.start_of_turn()
	var result: Dictionary = ae.spend_action({})
	assert_true(
		result.get("success"),
		"start_of_turn() must clear _action_used so a new turn's spend_action() can succeed again"
	)


func test_start_of_round_clears_action_used() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()
	ae.spend_action({})

	ae.start_of_round()
	var result: Dictionary = ae.spend_action({})
	assert_true(
		result.get("success"),
		"start_of_round() (_reset_round_state()) must clear _action_used"
	)


func test_end_of_round_clears_action_used() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()
	ae.spend_action({})

	ae.end_of_round()
	var result: Dictionary = ae.spend_action({})
	assert_true(
		result.get("success"),
		"end_of_round() (_reset_round_state()) must clear _action_used"
	)


func test_start_of_turn_does_not_affect_budget_or_is_spent_when_clearing_action_used() -> void:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()
	ae.spend_action({})
	var budget_before: int = ae.get_remaining()

	ae.start_of_turn()
	assert_eq(
		ae.get_remaining(),
		budget_before,
		"start_of_turn() clearing _action_used must not also refill actions_remaining (AC-1 unchanged)"
	)
