extends GutTest
## tests/integration/test_rest_mechanics_e2e.gd — FEAT-373 (US-011; FR-013,
## NFR-002; iteration AB-0, rest mechanics steel thread).
##
## Final integration checkpoint for the rest-mechanics steel thread
## (FEAT-003 LongRestUseCase, FEAT-004 ShortRestHealUseCase, FEAT-005
## ShortRestMageRechargeUseCase): an application-layer smoke test that
## boots a minimal party and drives ALL THREE new Combatant fields
## (stamina_max, intellect, mage_recharge_budget_remaining) and the two
## rest use cases this feature's scope covers (LongRestUseCase,
## ShortRestMageRechargeUseCase) through a single, chained end-to-end
## sequence.
##
## Naming note (DEF-005, tests/integration/test_test_suite_naming_hygiene
## .gd): this suite deliberately does NOT carry "steel_thread"/"steelthread"
## in its filename — per US-011/ADR-001 scope this is an APPLICATION-LAYER
## smoke test with NO res://MainScene.tscn dependency, mirroring
## tests/integration/test_frost_breath_cast_discharge_dazed_cold_log.gd's
## own identically-scoped precedent (see that file's own "Boot-real note").
##
## Party construction: Gram Marx + Titus are both built through
## infrastructure/combatant_factory.gd's CombatantFactory — the SAME
## production construction call MainScene.gd's own _build_party_combatant()
## delegates to — then lifted onto real core/domain/combatant.gd Combatant
## instances via Combatant.from_dict(). No Node/Control/SceneTree
## involvement anywhere in this file (LongRestUseCase/
## ShortRestMageRechargeUseCase are pure RefCounted orchestration, ADR-001).
##
## Item-recharge double: data/items/orb_gram.tres's real ItemResource does
## NOT yet declare an `energy_cost` field (see tests/unit/
## test_combatant_factory_rest_fields.gd's / tests/unit/
## test_long_rest_use_case.gd's own identical header notes — this is a
## documented, out-of-scope-for-this-feature gap in core/resources/
## item_resource.gd's authoring schema). This suite therefore represents
## Gram Marx's dischargeable Frost Breath focus with the SAME duck-typed
## FakeEquippedItem double (is_charged/energy_cost) every existing
## LongRestUseCase/ShortRestMageRechargeUseCase unit test already uses,
## appended onto the real, factory-built equipped_items array alongside the
## genuine orb_gram/staff_gram ItemResources — no production file
## (item_resource.gd, orb_gram.tres) is modified to make this suite pass,
## matching this feature's empty files_to_modify list.
##
## test_criteria satisfied:
##   1. Minimal party (Gram Marx + Titus) boots with no MainScene/
##      scene-tree dependency.
##   2. First LongRestUseCase call recharges the discharged focus item
##      (is_charged: false -> true) and sets
##      mage_recharge_budget_remaining == intellect (5).
##   3. A simulated Frost Breath discharge (is_charged=false, energy_cost=1)
##      followed by ShortRestMageRechargeUseCase spends exactly 1 budget
##      point and sets the item's is_charged back to true.
##   4. Five successive discharge+successful-recharge cycles exhaust the
##      budget from 5 to exactly 0.
##   5. A 6th recharge attempt after exhaustion returns
##      {success:false, error: ERR_INSUFFICIENT_BUDGET} with NO mutation
##      (item stays discharged, budget stays 0).
##   6. A subsequent LongRestUseCase call resets
##      mage_recharge_budget_remaining back to intellect (and recharges the
##      still-discharged focus item).

const CombatantFactoryClass             = preload("res://infrastructure/combatant_factory.gd")
const CombatantClass                    = preload("res://core/domain/combatant.gd")
const HexCoordClass                     = preload("res://core/geometry/hex_coord.gd")
const LongRestUseCaseClass              = preload("res://core/application/use_cases/long_rest_use_case.gd")
const ShortRestMageRechargeUseCaseClass = preload("res://core/application/use_cases/short_rest_mage_recharge_use_case.gd")
const ErrorCodeClass                    = preload("res://core/application/ports/errors.gd")

const GRAM_MARX_PATH: String = "res://data/characters/gram_marx.tres"
const TITUS_PATH: String     = "res://data/characters/titus.tres"


# ══════════════════════════════════════════════════════════════════════════
# Test-local seam: FakeEquippedItem (see file-level doc above)
# ══════════════════════════════════════════════════════════════════════════

## FakeEquippedItem — duck-typed equipped-item double exposing exactly the
## two fields LongRestUseCase/ShortRestMageRechargeUseCase's `_duck_get()`
## walk reads: `is_charged` / `energy_cost`. Mirrors tests/unit/
## test_long_rest_use_case.gd's / tests/unit/
## test_short_rest_mage_recharge_use_case.gd's identically-shaped
## FakeEquippedItem convention.
class FakeEquippedItem:
	extends RefCounted
	var is_charged: bool = false
	var energy_cost: int = 0

	func _init(p_is_charged: bool = false, p_energy_cost: int = 0) -> void:
		is_charged = p_is_charged
		energy_cost = p_energy_cost


## _build_combatant(character_path, combatant_id) -> Combatant — builds a
## party combatant through infrastructure/combatant_factory.gd's
## CombatantFactory (the SAME production construction call MainScene.gd's
## own _build_party_combatant() delegates to), then lifts the resulting
## Dictionary onto a REAL core/domain/combatant.gd Combatant via
## Combatant.from_dict() — no res://MainScene.tscn boot, no Node/Control/
## SceneTree involvement anywhere in this construction path.
func _build_combatant(character_path: String, combatant_id: String) -> Combatant:
	var factory := CombatantFactoryClass.new()
	var spec: Dictionary = factory.build_party_combatant(character_path, HexCoordClass.new(0, 0), combatant_id)
	assert_false(spec.has("error"), "fixture assumption: %s must build a valid combatant with no error" % character_path)
	return CombatantClass.from_dict(spec)


# ══════════════════════════════════════════════════════════════════════════
# The rest-mechanics smoke test
# ══════════════════════════════════════════════════════════════════════════

func test_rest_mechanics_full_smoke() -> void:
	# ── Boot a minimal party: Gram Marx (Mage-paradigm, item-caster) + Titus
	# (non-caster Fighter) -- no MainScene/scene-tree dependency. ───────────
	var gram := _build_combatant(GRAM_MARX_PATH, "gram_marx_1")
	var titus := _build_combatant(TITUS_PATH, "titus_1")

	assert_eq(gram.intellect, 5, "fixture assumption: gram_marx.tres's authored intellect must be 5")
	assert_true(gram.hp_max > 0 and gram.stamina_max > 0, "fixture assumption: gram_marx.tres must build with positive hp_max/stamina_max")
	assert_true(titus.hp_max > 0 and titus.stamina_max > 0, "fixture assumption: titus.tres must build with positive hp_max/stamina_max")

	# Gram's dischargeable Frost Breath focus -- see file-level doc for why
	# this is a duck-typed double rather than the real orb_gram.tres
	# ItemResource. Starts DISCHARGED (is_charged=false), simulating a Frost
	# Breath cast from a prior encounter, energy_cost=1 mirroring Frost
	# Breath's own authored energy_cost (data/spells/frost_breath.tres).
	var focus_item := FakeEquippedItem.new(false, 1)
	gram.equipped_items.append(focus_item)

	# Simulate battle wear-and-tear before the first Long Rest, so restoring
	# to full is an observable, non-trivial state change.
	gram.hp_current = maxi(0, gram.hp_max - 2)
	gram.stamina = maxi(0, gram.stamina_max - 1)
	titus.hp_current = maxi(0, titus.hp_max - 2)
	titus.stamina = maxi(0, titus.stamina_max - 1)

	var party: Array = [gram, titus]
	var long_rest := LongRestUseCaseClass.new()
	var mage_recharge := ShortRestMageRechargeUseCaseClass.new()

	# ── (1) First Long Rest: recharges the discharged focus item and sets
	# mage_recharge_budget_remaining == intellect for both party members. ──
	var first_long_rest_result: Dictionary = long_rest.execute(party)
	assert_eq(first_long_rest_result, {"success": true, "restored_combatants": 2})

	assert_eq(gram.hp_current, gram.hp_max, "Long Rest must restore gram's hp_current to hp_max")
	assert_eq(gram.stamina, gram.stamina_max, "Long Rest must restore gram's stamina to stamina_max")
	assert_eq(gram.mage_recharge_budget_remaining, gram.intellect, "Long Rest must set gram's mage_recharge_budget_remaining to intellect")
	assert_eq(gram.mage_recharge_budget_remaining, 5)
	assert_true(focus_item.is_charged, "Long Rest must recharge the discharged, dischargeable focus item (is_charged=true)")

	assert_eq(titus.hp_current, titus.hp_max, "Long Rest must restore titus's hp_current to hp_max")
	assert_eq(titus.stamina, titus.stamina_max, "Long Rest must restore titus's stamina to stamina_max")

	# ── (2) A Frost Breath discharge followed by ShortRestMageRechargeUseCase
	# spends exactly 1 budget point and recharges the item. ────────────────
	focus_item.is_charged = false  # simulated Frost Breath discharge
	var first_recharge_result: Dictionary = mage_recharge.execute(gram, focus_item)
	assert_eq(first_recharge_result, {"success": true, "budget_spent": 1, "budget_remaining": 4})
	assert_true(focus_item.is_charged, "the recharge must set the focus item back to charged")
	assert_eq(gram.mage_recharge_budget_remaining, 4)

	# ── (3) Four more discharge+recharge cycles -- five successive
	# successful recharges total -- exhaust the budget to exactly 0. ───────
	var expected_remaining: Array = [3, 2, 1, 0]
	for expected in expected_remaining:
		focus_item.is_charged = false
		var result: Dictionary = mage_recharge.execute(gram, focus_item)
		assert_eq(result, {"success": true, "budget_spent": 1, "budget_remaining": expected})
		assert_true(focus_item.is_charged, "each successful recharge must re-charge the focus item")

	assert_eq(gram.mage_recharge_budget_remaining, 0, "five successive successful recharges must exhaust the budget to exactly 0")

	# ── (4) A 6th recharge attempt after exhaustion returns
	# ERR_INSUFFICIENT_BUDGET with NO mutation. ─────────────────────────────
	focus_item.is_charged = false  # another simulated discharge
	var sixth_result: Dictionary = mage_recharge.execute(gram, focus_item)
	assert_eq(sixth_result, {"success": false, "error": ErrorCodeClass.ERR_INSUFFICIENT_BUDGET})
	assert_false(focus_item.is_charged, "a failed recharge must leave the item discharged (no mutation)")
	assert_eq(gram.mage_recharge_budget_remaining, 0, "a failed recharge must leave the budget unchanged at 0")

	# ── (5) A subsequent LongRestUseCase call resets
	# mage_recharge_budget_remaining back to intellect (and recharges the
	# still-discharged focus item). ─────────────────────────────────────────
	var second_long_rest_result: Dictionary = long_rest.execute(party)
	assert_eq(second_long_rest_result, {"success": true, "restored_combatants": 2})
	assert_eq(gram.mage_recharge_budget_remaining, gram.intellect, "a subsequent Long Rest must reset mage_recharge_budget_remaining back to intellect")
	assert_eq(gram.mage_recharge_budget_remaining, 5)
	assert_true(focus_item.is_charged, "a subsequent Long Rest must recharge the still-discharged focus item")
