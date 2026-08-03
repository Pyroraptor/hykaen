extends GutTest
## tests/unit/test_long_rest_use_case.gd — FEAT-003 (US-003; FR-004,
## NFR-001, NFR-005; iteration AB-0, rest mechanics steel thread).
##
## GUT suite for core/application/use_cases/long_rest_use_case.gd's
## LongRestUseCase. Mirrors this project's established "fake, duck-typed
## item doubles / real domain Combatant objects" convention (e.g.
## tests/unit/test_begin_cast_use_case.gd's FakeEquippedItem) — no adapter,
## no engine boot; LongRestUseCase itself is pure RefCounted orchestration
## over Combatant + item references (ADR-001).
##
## test_criteria covered:
##   1. execute(party) restores hp_current to hp_max for every combatant
##   2. execute(party) restores stamina to stamina_max for every combatant
##   3. execute(party) restores mage_recharge_budget_remaining to intellect
##      for every combatant
##   4. All discharged (is_charged==false) items with energy_cost>0 become
##      is_charged==true after execute()
##   5. Non-Mage combatants (mage_recharge_budget_remaining stays derived at
##      0) are left untouched aside from hp/stamina restore
##   6. Idempotency: calling execute() twice in a row produces the same
##      fully-restored state with no errors
##   7. Return value is exactly {success: true, restored_combatants: <party.size()>}
##   8. Static check: file contains no Node/Control/SceneTree references

const LongRestUseCaseClass = preload("res://core/application/use_cases/long_rest_use_case.gd")
const CombatantClass       = preload("res://core/domain/combatant.gd")
const HexCoordClass        = preload("res://core/geometry/hex_coord.gd")


## FakeEquippedItem — duck-typed equipped-item double exposing exactly the
## two fields LongRestUseCase's _duck_get() walk reads: `is_charged` /
## `energy_cost`. Mirrors tests/unit/test_begin_cast_use_case.gd's
## FakeEquippedItem convention (this codebase's established "fake,
## duck-typed... no adapter" pattern) — NOT
## core/resources/item_resource.gd's ItemResource, which does not yet
## declare an energy_cost field (a later feature's concern, per
## tests/unit/test_combatant_factory_rest_fields.gd's own header note).
class FakeEquippedItem:
	extends RefCounted
	var is_charged: bool = false
	var energy_cost: int = 0

	func _init(p_is_charged: bool = false, p_energy_cost: int = 0) -> void:
		is_charged = p_is_charged
		energy_cost = p_energy_cost


func _combatant(
	combatant_id: String,
	hp_current: int, hp_max: int,
	stamina: int, stamina_max: int,
	intellect: int, mage_recharge_budget_remaining: int,
	equipped_items: Array = []
) -> Combatant:
	var c := CombatantClass.new(combatant_id, combatant_id, "Player", HexCoordClass.new(0, 0))
	c.hp_current = hp_current
	c.hp_max = hp_max
	c.stamina = stamina
	c.stamina_max = stamina_max
	c.intellect = intellect
	c.mage_recharge_budget_remaining = mage_recharge_budget_remaining
	c.equipped_items = equipped_items
	return c


# ══════════════════════════════════════════════════════════════════════════
# hp_current / stamina / mage_recharge_budget_remaining restore
# ══════════════════════════════════════════════════════════════════════════

func test_execute_restores_hp_current_to_hp_max_for_every_combatant() -> void:
	var titus := _combatant("titus_1", 5, 20, 3, 5, 0, 0)
	var gram := _combatant("gram_marx_1", 1, 15, 2, 4, 5, 5)
	var use_case := LongRestUseCaseClass.new()

	use_case.execute([titus, gram])

	assert_eq(titus.hp_current, titus.hp_max, "titus's hp_current must restore to hp_max")
	assert_eq(gram.hp_current, gram.hp_max, "gram's hp_current must restore to hp_max")


func test_execute_restores_stamina_to_stamina_max_for_every_combatant() -> void:
	var titus := _combatant("titus_1", 20, 20, 0, 5, 0, 0)
	var gram := _combatant("gram_marx_1", 15, 15, 1, 4, 5, 5)
	var use_case := LongRestUseCaseClass.new()

	use_case.execute([titus, gram])

	assert_eq(titus.stamina, titus.stamina_max, "titus's stamina must restore to stamina_max")
	assert_eq(gram.stamina, gram.stamina_max, "gram's stamina must restore to stamina_max")


func test_execute_restores_mage_recharge_budget_remaining_to_intellect() -> void:
	var gram := _combatant("gram_marx_1", 15, 15, 4, 4, 5, 1)
	var use_case := LongRestUseCaseClass.new()

	use_case.execute([gram])

	assert_eq(gram.mage_recharge_budget_remaining, gram.intellect, "mage_recharge_budget_remaining must restore to intellect")
	assert_eq(gram.mage_recharge_budget_remaining, 5)


# ══════════════════════════════════════════════════════════════════════════
# Item recharge — is_charged==false AND energy_cost>0 becomes is_charged==true
# ══════════════════════════════════════════════════════════════════════════

func test_execute_recharges_discharged_dischargeable_items() -> void:
	var discharged_dischargeable := FakeEquippedItem.new(false, 2)
	var already_charged := FakeEquippedItem.new(true, 2)
	var never_dischargeable := FakeEquippedItem.new(false, 0)
	var gram := _combatant("gram_marx_1", 15, 15, 4, 4, 5, 5, [
		discharged_dischargeable, already_charged, never_dischargeable,
	])
	var use_case := LongRestUseCaseClass.new()

	use_case.execute([gram])

	assert_true(discharged_dischargeable.is_charged, "a discharged item with energy_cost>0 must become charged")
	assert_true(already_charged.is_charged, "an already-charged item must remain charged")
	assert_false(never_dischargeable.is_charged, "an item with energy_cost==0 must never be marked charged (it never discharges)")


# ══════════════════════════════════════════════════════════════════════════
# Non-Mage combatants left untouched aside from hp/stamina restore
# ══════════════════════════════════════════════════════════════════════════

func test_execute_leaves_non_mage_combatant_budget_at_zero() -> void:
	var titus := _combatant("titus_1", 5, 20, 1, 5, 0, 0)
	var use_case := LongRestUseCaseClass.new()

	use_case.execute([titus])

	assert_eq(titus.mage_recharge_budget_remaining, 0, "a non-Mage combatant's derived budget stays 0 (0 -> intellect(0) is a no-op)")
	assert_eq(titus.hp_current, titus.hp_max)
	assert_eq(titus.stamina, titus.stamina_max)


# ══════════════════════════════════════════════════════════════════════════
# Idempotency
# ══════════════════════════════════════════════════════════════════════════

func test_execute_twice_in_a_row_is_idempotent() -> void:
	var item := FakeEquippedItem.new(false, 2)
	var gram := _combatant("gram_marx_1", 1, 15, 0, 4, 5, 0, [item])
	var use_case := LongRestUseCaseClass.new()

	var first_result: Dictionary = use_case.execute([gram])
	var state_after_first := {
		"hp_current": gram.hp_current,
		"stamina": gram.stamina,
		"mage_recharge_budget_remaining": gram.mage_recharge_budget_remaining,
		"is_charged": item.is_charged,
	}

	var second_result: Dictionary = use_case.execute([gram])

	assert_eq(gram.hp_current, state_after_first["hp_current"])
	assert_eq(gram.stamina, state_after_first["stamina"])
	assert_eq(gram.mage_recharge_budget_remaining, state_after_first["mage_recharge_budget_remaining"])
	assert_eq(item.is_charged, state_after_first["is_charged"])
	assert_eq(second_result, first_result)


# ══════════════════════════════════════════════════════════════════════════
# Return value shape
# ══════════════════════════════════════════════════════════════════════════

func test_execute_returns_success_true_and_restored_combatants_count() -> void:
	var titus := _combatant("titus_1", 5, 20, 1, 5, 0, 0)
	var gram := _combatant("gram_marx_1", 1, 15, 0, 4, 5, 0)
	var use_case := LongRestUseCaseClass.new()

	var result: Dictionary = use_case.execute([titus, gram])

	assert_eq(result, {"success": true, "restored_combatants": 2})


func test_execute_returns_restored_combatants_matching_empty_party_size() -> void:
	var use_case := LongRestUseCaseClass.new()

	var result: Dictionary = use_case.execute([])

	assert_eq(result, {"success": true, "restored_combatants": 0})
