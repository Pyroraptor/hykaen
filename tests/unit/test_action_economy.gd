extends GutTest
## tests/unit/test_action_economy.gd
##
## GUT test suite for core/rules/action_economy.gd — Seven-Action Round Economy
## State Machine.  Validates all test criteria for FEAT-007 / US-007.
##
## All test criteria verified here:
##   1. start_of_turn() → get_remaining()==7, is_spent()==false
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

## Build a fresh ActionEconomy and call start_of_turn().
func _make_ae() -> ActionEconomyClass:
	var ae = ActionEconomyClass.new()
	ae.start_of_turn()
	return ae


# ── Criterion 1: start_of_turn() sets budget=7 and is_spent=false ─────────────

func test_start_of_turn_sets_budget_7_and_not_spent() -> void:
	var ae = _make_ae()
	assert_eq(ae.get_remaining(), 7, "budget must be 7 after start_of_turn()")
	assert_false(ae.is_spent(), "is_spent() must be false after start_of_turn()")


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


# ── Criterion 9: Not dazed — combine_actions not yet implemented ──────────────

func test_combine_actions_not_dazed_returns_not_implemented() -> void:
	var ae = _make_ae()
	ae.set_dazed(false)
	var result: Dictionary = ae.combine_actions({}, {}, {})
	assert_false(result["success"], "combine_actions must fail")
	assert_true(
		result["error"].contains("Not implemented"),
		"error must contain 'Not implemented'; got: '%s'" % result["error"]
	)


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
