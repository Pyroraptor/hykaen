extends GutTest
## tests/unit/test_action_economy.gd
##
## GUT test suite for core/rules/action_economy.gd — Seven-Action Round Economy
## State Machine.  Validates all test criteria for FEAT-007 / US-007.
##
## All test criteria verified here:
##   1. (CR-001 corrected) A fresh round established via start_of_round() →
##      get_remaining()==7, is_spent()==false; start_of_turn() alone must NOT
##      produce this state once budget has been spent within the round (the
##      original FEAT-007 criterion asserted start_of_turn() itself performed
##      this refill — that assumption was the per-turn budget-refill bug
##      CR-001 corrects; see test_fresh_round_has_budget_7_and_not_spent_via_start_of_round_not_start_of_turn()
##      below)
##   2. 7 successive spend_action({}) — 7th returns {success:true, remaining:0}
##      and is_spent()==true
##   3. spend_action({}) after is_spent==true → {success:false, error:'Spent'}
##   4. spend_reaction() after start_of_turn → {success:true, remaining:6}
##   5. end_of_round() after exhaustion → get_remaining()==7, is_spent()==false
##   6. use_step() then Movement action → {success:false, error:'Movement already used'}
##   7. First Movement action succeeds; subsequent Movement fails with same error
##   8. set_dazed(true) then combine_actions → error containing 'Dazed' or 'forbidden'
##   9. set_dazed(false) then combine_actions → error containing 'Not implemented'
##  10. action_economy.gd has no 'extends Node' or 'extends Control'

const ActionEconomyClass = preload("res://core/rules/action_economy.gd")


# ── Helper ─────────────────────────────────────────────────────────────────────

## Build a fresh ActionEconomy and call start_of_turn() to clear per-turn
## flags (TurnFlags) only. NOTE (CR-001 AC-1): budget_remaining==7 and
## is_spent()==false hold here because ActionEconomy.new() constructs that
## way, NOT because start_of_turn() refills anything — start_of_turn() must
## never be relied upon as a budget-refill point. See
## test_fresh_round_has_budget_7_and_not_spent_via_start_of_round_not_start_of_turn()
## for the explicit assertion of that contract.
func _make_ae() -> ActionEconomyClass:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	return ae


# ── Criterion 1 (CR-001 corrected): the per-ROUND budget is established by
# start_of_round() — never by start_of_turn(). The original FEAT-007 version
# of this test (pre-CR-001) asserted that start_of_turn() alone produced
# get_remaining()==7 / is_spent()==false, which encoded the old per-TURN
# budget-refill model that CR-001 (AC-1/AC-2) explicitly overturned: the
# 7-action budget is a per-ROUND resource shared across all of a combatant's
# turns within that round, and only start_of_round()/end_of_round() may
# reset it. This test is REWRITTEN (not deleted/weakened) to assert the
# corrected contract: (a) start_of_round() — not start_of_turn() — is what
# establishes budget=7/is_spent=false for a round, and (b) once budget has
# been spent within a round, start_of_turn() leaves it untouched.

func test_fresh_round_has_budget_7_and_not_spent_via_start_of_round_not_start_of_turn() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	assert_eq(
		ae.get_remaining(), 7,
		"CR-001 AC-2: start_of_round() (not start_of_turn()) establishes budget_remaining=MAX_BUDGET for the round"
	)
	assert_false(
		ae.is_spent(),
		"CR-001 AC-2: start_of_round() (not start_of_turn()) clears is_spent for the round"
	)

	# Spend the entire per-ROUND budget, then prove start_of_turn() within
	# the SAME round does NOT refill it — the corrected replacement for the
	# old (incorrect) assumption that every start_of_turn() call implied a
	# fresh budget.
	for _i in range(7):
		ae.spend_action({})
	assert_true(ae.is_spent(), "sanity check: budget must be exhausted mid-round before the start_of_turn() probe")

	ae.start_of_turn()
	assert_eq(
		ae.get_remaining(), 0,
		"CR-001 AC-1: start_of_turn() must NOT refill budget_remaining — refill happens only at the round boundary (start_of_round()/end_of_round())"
	)
	assert_true(
		ae.is_spent(),
		"CR-001 AC-1: start_of_turn() must NOT clear is_spent — a Spent combatant stays Spent until the round boundary"
	)


# ── Criterion 2: 7 spend_action calls exhaust budget ──────────────────────────

func test_seven_spend_actions_exhaust_budget() -> void:
	var ae = _make_ae()
	var result: Dictionary
	for i in range(6):
		result = ae.spend_action({})
		assert_true(result["success"], "action %d of 7 must succeed" % (i + 1))
		assert_false(ae.is_spent(), "is_spent must be false after action %d of 7" % (i + 1))
	# 7th action — exhausts budget
	result = ae.spend_action({})
	assert_true(result["success"], "7th spend_action({}) must succeed")
	assert_eq(result["remaining"], 0, "remaining must be 0 after 7th action")
	assert_true(ae.is_spent(), "is_spent must be true after 7th action")


# ── Criterion 3: spend_action after is_spent → {success:false, error:'Spent'} ─

func test_spend_action_when_spent_returns_spent_error() -> void:
	var ae = _make_ae()
	for _i in range(7):
		ae.spend_action({})
	assert_true(ae.is_spent(), "is_spent must be true before over-spend test")
	var result: Dictionary = ae.spend_action({})
	assert_false(result["success"], "spend_action on spent combatant must fail")
	assert_eq(result["error"], "Spent", "error must be exactly 'Spent'")
	assert_eq(result["remaining"], 0, "remaining must report 0 when spent")


# ── Criterion 4: spend_reaction() decrements budget by 1 ──────────────────────

func test_spend_reaction_decrements_budget_to_6() -> void:
	var ae = _make_ae()
	var result: Dictionary = ae.spend_reaction()
	assert_true(result["success"], "spend_reaction() must succeed")
	assert_eq(result["remaining"], 6, "remaining must be 6 after spend_reaction()")
	assert_eq(ae.get_remaining(), 6, "get_remaining() must return 6 after spend_reaction()")


# ── Criterion 5: end_of_round() resets budget after exhaustion ────────────────

func test_end_of_round_resets_after_exhaustion() -> void:
	var ae = _make_ae()
	for _i in range(7):
		ae.spend_action({})
	assert_true(ae.is_spent(), "is_spent must be true before end_of_round()")
	ae.end_of_round()
	assert_eq(ae.get_remaining(), 7, "get_remaining() must be 7 after end_of_round()")
	assert_false(ae.is_spent(), "is_spent() must be false after end_of_round()")


# ── Criterion 6: use_step() then Movement action fails ────────────────────────

func test_use_step_then_movement_action_fails() -> void:
	var ae = _make_ae()
	ae.use_step()
	var result: Dictionary = ae.spend_action({"traits": ["Movement"]})
	assert_false(result["success"], "Movement spend_action after use_step() must fail")
	assert_eq(
		result["error"],
		"Movement already used",
		"error must be 'Movement already used'"
	)


# ── Criterion 7: First Movement succeeds; second Movement fails ───────────────

func test_first_movement_succeeds_second_movement_fails() -> void:
	var ae = _make_ae()
	# First Movement action — no prior use_step
	var first: Dictionary = ae.spend_action({"traits": ["Movement"]})
	assert_true(first["success"], "first Movement spend_action must succeed")
	# Second Movement action — _movement_used is now true
	var second: Dictionary = ae.spend_action({"traits": ["Movement"]})
	assert_false(second["success"], "second Movement spend_action must fail")
	assert_eq(
		second["error"],
		"Movement already used",
		"error must be 'Movement already used'"
	)


# ── Criterion 8: Dazed combatant — combine_actions forbidden ──────────────────

func test_combine_actions_dazed_returns_forbidden_error() -> void:
	var ae = _make_ae()
	ae.set_dazed(true)
	var result: Dictionary = ae.combine_actions({}, {}, {})
	assert_false(result["success"], "combine_actions when dazed must fail")
	assert_true(
		result["error"].contains("Dazed") or result["error"].contains("forbidden"),
		"error must contain 'Dazed' or 'forbidden'; got: '%s'" % result["error"]
	)


# ── Criterion 9 (updated): Not dazed + missing Repeat trait → Repeat error ────

func test_combine_actions_missing_repeat_on_action_a_returns_repeat_error() -> void:
	var ae = _make_ae()
	ae.set_dazed(false)
	var action_a := {"name": "Strike", "traits": []}
	var action_b := {"name": "Strike", "traits": ["Repeat"]}
	var result: Dictionary = ae.combine_actions(action_a, action_b, 5)
	assert_false(result["success"], "combine_actions must fail when action_a lacks Repeat")
	assert_true(
		result["error"].contains("Repeat trait"),
		"error must contain 'Repeat trait' when action_a lacks Repeat; got: '%s'" % result["error"]
	)


# ── FEAT-058: Full combine_actions() implementation ───────────────────────────

func test_combine_actions_both_repeat_stamina_5_returns_success_stamina_4() -> void:
	var ae = _make_ae()
	var action_a := {"name": "Strike", "traits": ["Repeat"]}
	var action_b := {"name": "Strike", "traits": ["Repeat"]}
	var result: Dictionary = ae.combine_actions(action_a, action_b, 5)
	assert_true(result["success"], "combine_actions with both Repeat and stamina=5 must succeed")
	assert_eq(result["stamina_remaining"], 4, "stamina_remaining must be 4 after spending 1 from pool of 5")


func test_combine_actions_missing_repeat_on_action_b_returns_repeat_error() -> void:
	var ae = _make_ae()
	var action_a := {"name": "Strike", "traits": ["Repeat"]}
	var action_b := {"name": "Guard", "traits": []}
	var result: Dictionary = ae.combine_actions(action_a, action_b, 5)
	assert_false(result["success"], "combine_actions must fail when action_b lacks Repeat")
	assert_true(
		result["error"].contains("Repeat trait"),
		"error must contain 'Repeat trait' when action_b lacks Repeat; got: '%s'" % result["error"]
	)


func test_combine_actions_stamina_pool_zero_returns_stamina_error() -> void:
	var ae = _make_ae()
	var action_a := {"name": "Strike", "traits": ["Repeat"]}
	var action_b := {"name": "Strike", "traits": ["Repeat"]}
	var result: Dictionary = ae.combine_actions(action_a, action_b, 0)
	assert_false(result["success"], "combine_actions with stamina_pool=0 must fail")
	assert_true(
		result["error"].contains("Stamina"),
		"error must contain 'Stamina' when stamina_pool=0; got: '%s'" % result["error"]
	)


func test_combine_actions_success_does_not_modify_budget() -> void:
	var ae = _make_ae()
	var budget_before: int = ae.get_remaining()
	var action_a := {"name": "Strike", "traits": ["Repeat"]}
	var action_b := {"name": "Strike", "traits": ["Repeat"]}
	var result: Dictionary = ae.combine_actions(action_a, action_b, 3)
	assert_true(result["success"], "combine_actions must succeed")
	assert_eq(
		ae.get_remaining(),
		budget_before,
		"combine_actions must NOT modify _budget; get_remaining() must be unchanged"
	)


func test_combine_actions_stamina_pool_1_returns_stamina_remaining_0() -> void:
	var ae = _make_ae()
	var action_a := {"name": "Strike", "traits": ["Repeat"]}
	var action_b := {"name": "Strike", "traits": ["Repeat"]}
	var result: Dictionary = ae.combine_actions(action_a, action_b, 1)
	assert_true(result["success"], "combine_actions with stamina_pool=1 must succeed")
	assert_eq(result["stamina_remaining"], 0, "stamina_remaining must be 0 when pool was 1")


# ── Criterion 10: Domain purity — no Node/Control inheritance ─────────────────

func test_action_economy_gd_no_node_inheritance() -> void:
	var file := FileAccess.open("res://core/rules/action_economy.gd", FileAccess.READ)
	assert_not_null(file, "core/rules/action_economy.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"action_economy.gd must not contain 'extends Node' — ADR-001 domain purity"
	)
	assert_false(
		content.contains("extends Control"),
		"action_economy.gd must not contain 'extends Control' — ADR-001 domain purity"
	)


# ── combining_forbidden() property reflects dazed state ───────────────────────

func test_combining_forbidden_reflects_dazed_state() -> void:
	var ae = _make_ae()
	ae.set_dazed(true)
	assert_true(ae.combining_forbidden(), "combining_forbidden() must be true when dazed")
	ae.set_dazed(false)
	assert_false(ae.combining_forbidden(), "combining_forbidden() must be false when not dazed")


# ── end_of_round dazed persists ────────────────────────────────────────────────

func test_dazed_persists_across_end_of_round() -> void:
	var ae = _make_ae()
	ae.set_dazed(true)
	ae.end_of_round()
	assert_true(ae.combining_forbidden(), "_dazed must persist across end_of_round()")


# ── spend_reaction exhausts budget at 0 ───────────────────────────────────────

func test_spend_reaction_exhausting_sets_is_spent() -> void:
	var ae = _make_ae()
	# Spend 6 actions first
	for _i in range(6):
		ae.spend_action({})
	# Spend the last one via reaction
	var result: Dictionary = ae.spend_reaction()
	assert_true(result["success"], "7th spend (via reaction) must succeed")
	assert_eq(result["remaining"], 0, "remaining must be 0")
	assert_true(ae.is_spent(), "is_spent must be true after 7th deduction via reaction")


# ── FEAT-001 (CR-001 AC-1): start_of_turn() limited to per-turn flag clearing ──
#
# AC-1: start_of_turn() clears ONLY the per-TURN flag(s) (_movement_used). It
# must NOT refill _budget, must NOT clear _is_spent, and must NOT touch
# _dazed. A combatant who became Spent earlier in the round stays Spent until
# the round boundary (end_of_round() / start_of_round()).

func test_start_of_turn_clears_movement_used() -> void:
	var ae = ActionEconomyClass.new()
	ae.use_step()
	var blocked: Dictionary = ae.spend_action({"traits": ["Movement"]})
	assert_false(
		blocked["success"],
		"sanity check: Movement must be blocked while movement_used is set"
	)
	ae.start_of_turn()
	var result: Dictionary = ae.spend_action({"traits": ["Movement"]})
	assert_true(
		result["success"],
		"start_of_turn() must clear movement_used (TurnFlags) so Movement can be taken again"
	)


func test_start_of_turn_does_not_modify_budget_remaining() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	ae.spend_action({})
	ae.spend_action({})
	var budget_before: int = ae.get_remaining()
	ae.start_of_turn()
	assert_eq(
		ae.get_remaining(),
		budget_before,
		"start_of_turn() must NOT modify budget_remaining (AC-1)"
	)


func test_start_of_turn_does_not_modify_is_spent() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	for _i in range(7):
		ae.spend_action({})
	assert_true(ae.is_spent(), "sanity check: is_spent must be true after exhausting the budget")
	ae.start_of_turn()
	assert_true(
		ae.is_spent(),
		"start_of_turn() must NOT clear is_spent — a Spent combatant stays Spent until round end (AC-1)"
	)
	assert_eq(
		ae.get_remaining(),
		0,
		"start_of_turn() must NOT refill budget_remaining for an already-Spent combatant (AC-1)"
	)


func test_start_of_turn_does_not_modify_is_dazed() -> void:
	var dazed_ae = ActionEconomyClass.new()
	dazed_ae.set_dazed(true)
	dazed_ae.start_of_turn()
	assert_true(
		dazed_ae.combining_forbidden(),
		"start_of_turn() must NOT clear _dazed when it was true"
	)

	var not_dazed_ae = ActionEconomyClass.new()
	not_dazed_ae.set_dazed(false)
	not_dazed_ae.start_of_turn()
	assert_false(
		not_dazed_ae.combining_forbidden(),
		"start_of_turn() must NOT set _dazed when it was false"
	)


func test_start_of_turn_repeated_calls_within_round_preserve_budget_and_spent() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	ae.spend_action({})
	ae.spend_action({})
	ae.spend_action({})
	var budget_after_three_spends: int = ae.get_remaining()

	# Simulate AC-4 interleaving: this combatant's turn comes around again
	# within the SAME round (no intervening end_of_round()/start_of_round()).
	ae.start_of_turn()
	assert_eq(
		ae.get_remaining(),
		budget_after_three_spends,
		"repeated start_of_turn() calls within the same round must not change budget_remaining"
	)
	assert_false(
		ae.is_spent(),
		"repeated start_of_turn() calls must not change is_spent while budget remains"
	)

	ae.start_of_turn()
	ae.start_of_turn()
	assert_eq(
		ae.get_remaining(),
		budget_after_three_spends,
		"budget_remaining must remain stable across many repeated start_of_turn() calls in one round"
	)


# ── FEAT-002 (CR-001 AC-2 / ADR-001): start_of_round()/end_of_round() are the
# SOLE operations permitted to reset budget_remaining/is_spent at the round
# boundary. Neither may ever touch is_dazed — is_dazed only changes via the
# explicit set_dazed() call.

func test_start_of_round_sets_budget_to_max_and_clears_is_spent() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	for _i in range(7):
		ae.spend_action({})
	assert_true(ae.is_spent(), "sanity check: is_spent must be true before start_of_round()")
	ae.start_of_round()
	assert_eq(ae.get_remaining(), 7, "start_of_round() must set budget_remaining to MAX_BUDGET")
	assert_false(ae.is_spent(), "start_of_round() must clear is_spent to false")


func test_end_of_round_sets_budget_to_max_and_clears_is_spent() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	for _i in range(7):
		ae.spend_action({})
	assert_true(ae.is_spent(), "sanity check: is_spent must be true before end_of_round()")
	ae.end_of_round()
	assert_eq(ae.get_remaining(), 7, "end_of_round() must set budget_remaining to MAX_BUDGET")
	assert_false(ae.is_spent(), "end_of_round() must clear is_spent to false")


func test_start_of_round_does_not_modify_is_dazed() -> void:
	var dazed_ae = ActionEconomyClass.new()
	dazed_ae.set_dazed(true)
	dazed_ae.start_of_round()
	assert_true(
		dazed_ae.combining_forbidden(),
		"start_of_round() must NOT clear _dazed when it was true"
	)

	var not_dazed_ae = ActionEconomyClass.new()
	not_dazed_ae.set_dazed(false)
	not_dazed_ae.start_of_round()
	assert_false(
		not_dazed_ae.combining_forbidden(),
		"start_of_round() must NOT set _dazed when it was false"
	)


func test_end_of_round_does_not_modify_is_dazed() -> void:
	var dazed_ae = ActionEconomyClass.new()
	dazed_ae.set_dazed(true)
	dazed_ae.end_of_round()
	assert_true(
		dazed_ae.combining_forbidden(),
		"end_of_round() must NOT clear _dazed when it was true"
	)

	var not_dazed_ae = ActionEconomyClass.new()
	not_dazed_ae.set_dazed(false)
	not_dazed_ae.end_of_round()
	assert_false(
		not_dazed_ae.combining_forbidden(),
		"end_of_round() must NOT set _dazed when it was false"
	)


func test_is_dazed_only_changes_via_set_dazed() -> void:
	var ae = ActionEconomyClass.new()
	ae.set_dazed(true)
	# A whole round's worth of lifecycle calls must never flip _dazed.
	ae.start_of_round()
	ae.start_of_turn()
	ae.spend_action({})
	ae.spend_reaction()
	ae.end_of_round()
	assert_true(
		ae.combining_forbidden(),
		"is_dazed must remain true across a full round lifecycle until set_dazed(false) is called"
	)
	ae.set_dazed(false)
	assert_false(
		ae.combining_forbidden(),
		"is_dazed must only change via explicit set_dazed(false)"
	)


func test_budget_persists_across_turns_then_resets_once_at_round_boundary() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	ae.spend_action({})
	ae.spend_action({})
	var budget_after_two_spends: int = ae.get_remaining()

	# AC-4 interleaving: this combatant's turn comes around again within the
	# SAME round — budget must persist unchanged across repeated
	# start_of_turn() calls.
	ae.start_of_turn()
	assert_eq(
		ae.get_remaining(),
		budget_after_two_spends,
		"budget_remaining must persist unchanged across start_of_turn() within the round"
	)
	ae.spend_action({})
	ae.start_of_turn()
	ae.start_of_turn()
	assert_eq(
		ae.get_remaining(),
		budget_after_two_spends - 1,
		"budget_remaining must persist (minus further spends) across repeated start_of_turn() calls"
	)

	# Round boundary — resets exactly once back to MAX_BUDGET.
	ae.start_of_round()
	assert_eq(
		ae.get_remaining(),
		ActionEconomyClass.MAX_BUDGET,
		"start_of_round() must reset budget_remaining to MAX_BUDGET exactly once at the round boundary"
	)
	assert_false(ae.is_spent(), "start_of_round() must clear is_spent at the round boundary")


func test_start_of_round_null_combatant_guard_no_ops() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	for _i in range(7):
		ae.spend_action({})
	assert_true(ae.is_spent(), "sanity check: is_spent must be true before null-guard call")

	ae.start_of_round(null)

	assert_eq(
		ae.get_remaining(),
		0,
		"start_of_round(null) must no-op and not modify budget_remaining"
	)
	assert_true(
		ae.is_spent(),
		"start_of_round(null) must no-op and not clear is_spent"
	)


func test_end_of_round_null_combatant_guard_no_ops() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	for _i in range(7):
		ae.spend_action({})
	assert_true(ae.is_spent(), "sanity check: is_spent must be true before null-guard call")

	ae.end_of_round(null)

	assert_eq(
		ae.get_remaining(),
		0,
		"end_of_round(null) must no-op and not modify budget_remaining"
	)
	assert_true(
		ae.is_spent(),
		"end_of_round(null) must no-op and not clear is_spent"
	)


# ── FEAT-003 (CR-001 AC-3): spend_action()/spend_reaction() share the same
# ActionBudget.budget_remaining counter regardless of action/reaction mix or
# turn ownership, and expose a Result-style {ok, reason:'ALREADY_SPENT'}
# contract for the already-Spent case, plus {ok:true, budget_remaining:<n>}
# on success.

func test_spend_action_success_returns_ok_true_and_budget_remaining() -> void:
	var ae = _make_ae()
	var result: Dictionary = ae.spend_action({})
	assert_true(result.get("ok"), "spend_action() success must set ok:true")
	assert_eq(
		result.get("budget_remaining"),
		6,
		"spend_action() success must report budget_remaining:6 after first spend"
	)


func test_spend_reaction_success_returns_ok_true_and_budget_remaining() -> void:
	var ae = _make_ae()
	var result: Dictionary = ae.spend_reaction()
	assert_true(result.get("ok"), "spend_reaction() success must set ok:true")
	assert_eq(
		result.get("budget_remaining"),
		6,
		"spend_reaction() success must report budget_remaining:6 after first spend"
	)


func test_spend_action_already_spent_returns_ok_false_reason_already_spent() -> void:
	var ae = _make_ae()
	for _i in range(7):
		ae.spend_action({})
	assert_true(ae.is_spent(), "sanity check: combatant must be Spent before over-spend")
	var result: Dictionary = ae.spend_action({})
	assert_false(result.get("ok"), "spend_action() on Spent combatant must set ok:false")
	assert_eq(
		result.get("reason"),
		"ALREADY_SPENT",
		"spend_action() on Spent combatant must set reason:'ALREADY_SPENT'"
	)


func test_spend_reaction_already_spent_returns_ok_false_reason_already_spent() -> void:
	var ae = _make_ae()
	for _i in range(7):
		ae.spend_action({})
	assert_true(ae.is_spent(), "sanity check: combatant must be Spent before over-spend")
	var result: Dictionary = ae.spend_reaction()
	assert_false(result.get("ok"), "spend_reaction() on Spent combatant must set ok:false")
	assert_eq(
		result.get("reason"),
		"ALREADY_SPENT",
		"spend_reaction() on Spent combatant must set reason:'ALREADY_SPENT'"
	)


func test_already_spent_combatant_does_not_decrement_further_via_action_or_reaction() -> void:
	var ae = _make_ae()
	for _i in range(7):
		ae.spend_action({})
	assert_eq(ae.get_remaining(), 0, "sanity check: budget must be 0 before over-spend attempts")

	ae.spend_action({})
	assert_eq(ae.get_remaining(), 0, "over-spend via spend_action() must not decrement below 0")

	ae.spend_reaction()
	assert_eq(ae.get_remaining(), 0, "over-spend via spend_reaction() must not decrement below 0")

	assert_true(ae.is_spent(), "is_spent must remain true after over-spend attempts")


func test_spend_action_and_spend_reaction_share_same_budget_counter() -> void:
	var ae = _make_ae()
	ae.spend_action({})
	ae.spend_reaction()
	ae.spend_action({})
	assert_eq(
		ae.get_remaining(),
		4,
		"spend_action()/spend_reaction() must decrement the SAME budget_remaining counter"
	)


func test_budget_reaching_zero_via_mixed_action_reaction_calls_sets_is_spent() -> void:
	var ae = _make_ae()
	# Mix of 4 actions and 3 reactions = 7 total spends, in interleaved order.
	ae.spend_action({})
	ae.spend_reaction()
	ae.spend_action({})
	ae.spend_reaction()
	ae.spend_action({})
	ae.spend_reaction()
	assert_false(ae.is_spent(), "is_spent must be false with budget_remaining==1")
	var result: Dictionary = ae.spend_action({})
	assert_true(result.get("ok"), "final mixed spend must succeed")
	assert_eq(result.get("budget_remaining"), 0, "budget_remaining must be 0 after 7 mixed spends")
	assert_true(ae.is_spent(), "is_spent must be true regardless of action/reaction mix at 0")


func test_reaction_spent_out_of_turn_reduces_budget_on_own_subsequent_turn() -> void:
	# Simulates AC-3: a reaction spent on the opponent's turn (out-of-turn)
	# must measurably reduce the budget available when this combatant's own
	# turn comes around later in the SAME round.
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	# Opponent's turn happens elsewhere; this combatant reacts out-of-turn.
	var reaction_result: Dictionary = ae.spend_reaction()
	assert_true(reaction_result.get("ok"), "out-of-turn reaction must succeed")
	assert_eq(ae.get_remaining(), 6, "out-of-turn reaction must decrement shared budget to 6")

	# Now it's this combatant's own turn within the same round.
	ae.start_of_turn()
	assert_eq(
		ae.get_remaining(),
		6,
		"budget spent via out-of-turn reaction must persist into the combatant's own turn"
	)
	var action_result: Dictionary = ae.spend_action({})
	assert_true(action_result.get("ok"), "own-turn action must succeed")
	assert_eq(
		action_result.get("budget_remaining"),
		5,
		"own-turn action must spend from the SAME pool already reduced by the out-of-turn reaction"
	)


func test_start_of_turn_null_combatant_guard_no_ops_and_logs_error() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	ae.spend_action({})
	var budget_before: int = ae.get_remaining()
	ae.use_step()

	# NOTE: GUT's push_error capture (assert_push_error) relies on
	# OS.add_logger, which is Godot 4.4+ only and is a documented no-op on
	# this project's Godot 4.3 engine (see addons/gut/error_tracker.gd).
	# We therefore assert the no-op CONTRACT (no state mutated) rather than
	# the push_error() call site itself, which start_of_turn()'s null guard
	# still performs (see core/rules/action_economy.gd).
	ae.start_of_turn(null)

	assert_eq(
		ae.get_remaining(),
		budget_before,
		"start_of_turn(null) must no-op and not modify budget_remaining"
	)
	var movement_result: Dictionary = ae.spend_action({"traits": ["Movement"]})
	assert_false(
		movement_result["success"],
		"start_of_turn(null) must no-op — movement_used must remain set"
	)
