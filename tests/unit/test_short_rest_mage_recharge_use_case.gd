extends GutTest
## tests/unit/test_short_rest_mage_recharge_use_case.gd — FEAT-005 (US-005;
## FR-006, NFR-001; iteration AB-0, rest mechanics steel thread).
##
## GUT suite for core/application/use_cases/short_rest_mage_recharge_use_case
## .gd's ShortRestMageRechargeUseCase. Mirrors tests/unit/test_long_rest_use_
## case.gd's / tests/unit/test_short_rest_heal_use_case.gd's established
## "real domain Combatant object + duck-typed FakeEquippedItem double, no
## adapter, no engine boot" convention — ShortRestMageRechargeUseCase itself
## is pure RefCounted orchestration over Combatant + item state (ADR-001).
##
## test_criteria covered:
##   1. item == null or item.is_charged == true returns
##      ERR_ITEM_ALREADY_CHARGED with no mutation
##   2. item.energy_cost <= 0 returns ERR_NOT_DISCHARGEABLE with no mutation
##   3. combatant.mage_recharge_budget_remaining < item.energy_cost returns
##      ERR_INSUFFICIENT_BUDGET with no mutation
##   4. Successful recharge sets item.is_charged = true and decrements
##      mage_recharge_budget_remaining by item.energy_cost
##   5. Successive recharges deplete budget to exactly 0 across multiple
##      items, with the next attempt returning ERR_INSUFFICIENT_BUDGET
##   6. Return shape on success is
##      {success: true, budget_spent: int, budget_remaining: int}
##   7. Static check: file contains no Node/Control/SceneTree references

const ShortRestMageRechargeUseCaseClass = preload("res://core/application/use_cases/short_rest_mage_recharge_use_case.gd")
const ErrorCodeClass                    = preload("res://core/application/ports/errors.gd")
const CombatantClass                    = preload("res://core/domain/combatant.gd")
const HexCoordClass                     = preload("res://core/geometry/hex_coord.gd")


## FakeEquippedItem — duck-typed equipped-item double exposing exactly the
## two fields ShortRestMageRechargeUseCase's _duck_get() walk reads:
## `is_charged` / `energy_cost`. Mirrors tests/unit/test_long_rest_use_case
## .gd's FakeEquippedItem convention (this codebase's established "fake,
## duck-typed... no adapter" pattern).
class FakeEquippedItem:
	extends RefCounted
	var is_charged: bool = false
	var energy_cost: int = 0

	func _init(p_is_charged: bool = false, p_energy_cost: int = 0) -> void:
		is_charged = p_is_charged
		energy_cost = p_energy_cost


func _combatant(mage_recharge_budget_remaining: int) -> Combatant:
	var c := CombatantClass.new("gram_marx_1", "Gram Marx", "Player", HexCoordClass.new(0, 0))
	c.mage_recharge_budget_remaining = mage_recharge_budget_remaining
	return c


# ══════════════════════════════════════════════════════════════════════════
# Validation order (a): item == null OR item.is_charged == true -> ERR_ITEM_ALREADY_CHARGED
# ══════════════════════════════════════════════════════════════════════════

func test_null_item_returns_item_already_charged_with_no_mutation() -> void:
	var gram := _combatant(5)
	var use_case := ShortRestMageRechargeUseCaseClass.new()

	var result: Dictionary = use_case.execute(gram, null)

	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_ITEM_ALREADY_CHARGED})
	assert_eq(gram.mage_recharge_budget_remaining, 5, "budget must be unchanged")


func test_already_charged_item_returns_item_already_charged_with_no_mutation() -> void:
	var item := FakeEquippedItem.new(true, 2)
	var gram := _combatant(5)
	var use_case := ShortRestMageRechargeUseCaseClass.new()

	var result: Dictionary = use_case.execute(gram, item)

	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_ITEM_ALREADY_CHARGED})
	assert_true(item.is_charged, "already-charged item must remain charged")
	assert_eq(gram.mage_recharge_budget_remaining, 5, "budget must be unchanged")


# ══════════════════════════════════════════════════════════════════════════
# Validation order (b): item.energy_cost <= 0 -> ERR_NOT_DISCHARGEABLE
# ══════════════════════════════════════════════════════════════════════════

func test_zero_energy_cost_item_returns_not_dischargeable_with_no_mutation() -> void:
	var item := FakeEquippedItem.new(false, 0)
	var gram := _combatant(5)
	var use_case := ShortRestMageRechargeUseCaseClass.new()

	var result: Dictionary = use_case.execute(gram, item)

	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_NOT_DISCHARGEABLE})
	assert_false(item.is_charged, "item must remain uncharged")
	assert_eq(gram.mage_recharge_budget_remaining, 5, "budget must be unchanged")


func test_negative_energy_cost_item_returns_not_dischargeable_with_no_mutation() -> void:
	var item := FakeEquippedItem.new(false, -1)
	var gram := _combatant(5)
	var use_case := ShortRestMageRechargeUseCaseClass.new()

	var result: Dictionary = use_case.execute(gram, item)

	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_NOT_DISCHARGEABLE})
	assert_eq(gram.mage_recharge_budget_remaining, 5)


# ══════════════════════════════════════════════════════════════════════════
# Validation order (c): mage_recharge_budget_remaining < energy_cost -> ERR_INSUFFICIENT_BUDGET
# ══════════════════════════════════════════════════════════════════════════

func test_insufficient_budget_returns_insufficient_budget_with_no_mutation() -> void:
	var item := FakeEquippedItem.new(false, 3)
	var gram := _combatant(2)
	var use_case := ShortRestMageRechargeUseCaseClass.new()

	var result: Dictionary = use_case.execute(gram, item)

	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_INSUFFICIENT_BUDGET})
	assert_false(item.is_charged, "item must remain uncharged")
	assert_eq(gram.mage_recharge_budget_remaining, 2, "budget must be unchanged")


func test_budget_exactly_equal_to_energy_cost_is_allowed() -> void:
	var item := FakeEquippedItem.new(false, 3)
	var gram := _combatant(3)
	var use_case := ShortRestMageRechargeUseCaseClass.new()

	var result: Dictionary = use_case.execute(gram, item)

	assert_true(result.get("success"), "spending exactly all available budget must succeed")
	assert_eq(gram.mage_recharge_budget_remaining, 0)


# ══════════════════════════════════════════════════════════════════════════
# Successful recharge — atomic is_charged flip + budget decrement
# ══════════════════════════════════════════════════════════════════════════

func test_successful_recharge_sets_is_charged_and_decrements_budget() -> void:
	var item := FakeEquippedItem.new(false, 2)
	var gram := _combatant(5)
	var use_case := ShortRestMageRechargeUseCaseClass.new()

	var result: Dictionary = use_case.execute(gram, item)

	assert_eq(result, {"success": true, "budget_spent": 2, "budget_remaining": 3})
	assert_true(item.is_charged, "item must become charged")
	assert_eq(gram.mage_recharge_budget_remaining, 3, "budget must decrement by energy_cost")


# ══════════════════════════════════════════════════════════════════════════
# Successive recharges — budget depletes to exactly 0, next attempt fails
# ══════════════════════════════════════════════════════════════════════════

func test_successive_recharges_deplete_budget_to_zero_then_next_attempt_fails() -> void:
	var item_a := FakeEquippedItem.new(false, 2)
	var item_b := FakeEquippedItem.new(false, 3)
	var item_c := FakeEquippedItem.new(false, 1)
	var gram := _combatant(5)
	var use_case := ShortRestMageRechargeUseCaseClass.new()

	var result_a: Dictionary = use_case.execute(gram, item_a)
	assert_eq(result_a, {"success": true, "budget_spent": 2, "budget_remaining": 3})

	var result_b: Dictionary = use_case.execute(gram, item_b)
	assert_eq(result_b, {"success": true, "budget_spent": 3, "budget_remaining": 0})

	assert_true(item_a.is_charged)
	assert_true(item_b.is_charged)
	assert_eq(gram.mage_recharge_budget_remaining, 0)

	var result_c: Dictionary = use_case.execute(gram, item_c)
	assert_eq(result_c, {"success": false, "error": ErrorCodeClass.ERR_INSUFFICIENT_BUDGET})
	assert_false(item_c.is_charged, "item_c must remain uncharged after the failed attempt")
	assert_eq(gram.mage_recharge_budget_remaining, 0, "budget must stay at 0 after the failed attempt")


# ══════════════════════════════════════════════════════════════════════════
# Static check: no Node/Control/SceneTree references in production source
# ══════════════════════════════════════════════════════════════════════════

func test_source_file_has_no_node_control_scenetree_references() -> void:
	# Mirrors tests/static/test_no_godot_types_in_core.py's real scan: only
	# an actual `extends <Banned>` clause or a banned type used as a type
	# hint/instantiation is a violation -- a doc-comment merely MENTIONING
	# "SceneTree" in prose is not.
	var source := FileAccess.get_file_as_string("res://core/application/use_cases/short_rest_mage_recharge_use_case.gd")
	for banned in ["extends Node", "extends Control", "extends CanvasItem", "extends SceneTree"]:
		assert_false(source.contains(banned), "must not extend '%s'" % banned)
	for banned_hint in [": Node", ": Control", "Node.new(", "Control.new(", "SceneTree.new("]:
		assert_false(source.contains(banned_hint), "must not reference '%s'" % banned_hint)
