extends GutTest
## tests/unit/test_combatant_factory_real_item_recharge.gd — FEAT-377
## (US-001; US-005; resolves DEF-001, requirements-traceability gap).
##
## Prior to this feature, the Mage-recharge derivation
## (CombatantFactory.compute_mage_recharge_budget_remaining()'s ">0"
## branch, exercised by ShortRestMageRechargeUseCase / LongRestUseCase) was
## only provable end-to-end against FakeEquippedItem test doubles --
## data/items/orb_gram.tres and data/items/staff_gram.tres, Gram Marx's
## REAL equipped items, never authored a non-zero energy_cost, so
## FR-003/FR-006's acceptance criterion
## (mage_recharge_budget_remaining == 5 for Gram Marx) could never be
## verified against real production game data (see tests/unit/
## test_combatant_factory_rest_fields.gd's now-superseded
## "...zero_for_gram_marx_current_fixture" test, and tests/integration/
## test_rest_mechanics_e2e.gd's file-level doc, both of which formerly
## documented this exact gap).
##
## This suite closes that gap:
##   1. orb_gram.tres / staff_gram.tres load with energy_cost > 0 AND
##      is_charged == true by default (the authored data itself).
##   2. CombatantFactory.build_party_combatant(), given Gram Marx's real
##      CharacterResource fixture (res://data/characters/gram_marx.tres,
##      real equipped_items -- no FakeEquippedItem doubles anywhere in this
##      file), derives mage_recharge_budget_remaining == intellect (5).
##   3. CombatantFactory.build_enemy_combatant() still emits 0/0/0 for the
##      three rest fields -- these real, now-dischargeable items must not
##      leak into (or otherwise affect) the enemy construction path.

const CombatantFactoryClass = preload("res://infrastructure/combatant_factory.gd")

const GRAM_MARX_PATH: String = "res://data/characters/gram_marx.tres"
const SKELETON_PATH: String = "res://data/enemies/skeleton.tres"

const ORB_GRAM_PATH: String = "res://data/items/orb_gram.tres"
const STAFF_GRAM_PATH: String = "res://data/items/staff_gram.tres"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: orb_gram.tres / staff_gram.tres authored data
# ══════════════════════════════════════════════════════════════════════════

func test_orb_gram_loads_with_positive_energy_cost_and_is_charged_true() -> void:
	# CACHE_MODE_IGNORE forces a genuinely fresh read of the file ON DISK
	# (the AUTHORED default), rather than whatever mutable ItemResource
	# instance the engine's shared resource cache currently holds -- other
	# suites elsewhere in the full-project run legitimately mutate this
	# SAME real, aliased orb_gram.tres instance's is_charged field (e.g.
	# discharging it as part of a cast/discharge steel thread), so reading
	# through the default cache here would make this "authored default"
	# assertion order-dependent on the rest of the suite. Mirrors the
	# established round-trip pattern in tests/unit/
	# test_item_resource_energy_cost.gd.
	var orb = ResourceLoader.load(ORB_GRAM_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(orb, "fixture assumption: orb_gram.tres must load")
	assert_true(orb.energy_cost > 0, "orb_gram.tres must author energy_cost > 0 to be dischargeable")
	assert_eq(orb.is_charged, true, "orb_gram.tres must default is_charged to true")


func test_staff_gram_loads_with_positive_energy_cost_and_is_charged_true() -> void:
	# See test_orb_gram_loads_with_positive_energy_cost_and_is_charged_true()
	# above for why CACHE_MODE_IGNORE is used here.
	var staff = ResourceLoader.load(STAFF_GRAM_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(staff, "fixture assumption: staff_gram.tres must load")
	assert_true(staff.energy_cost > 0, "staff_gram.tres must author energy_cost > 0 to be dischargeable")
	assert_eq(staff.is_charged, true, "staff_gram.tres must default is_charged to true")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: CombatantFactory derivation against Gram Marx's REAL fixture
# (no FakeEquippedItem doubles anywhere in this file)
# ══════════════════════════════════════════════════════════════════════════

func test_gram_marx_real_fixture_mage_recharge_budget_remaining_equals_intellect() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_1")
	assert_false(combatant.has("error"), "fixture assumption: gram_marx.tres must build a valid combatant with no error")

	var character = ResourceLoader.load(GRAM_MARX_PATH)
	var expected_intellect: int = int(character.attributes.get("intellect", -1))
	assert_eq(expected_intellect, 5, "fixture assumption: gram_marx.tres's authored intellect must be 5")

	assert_eq(
		combatant.get("intellect", -1), expected_intellect,
		"build_party_combatant() must resolve intellect from character.attributes"
	)
	assert_eq(
		combatant.get("mage_recharge_budget_remaining", -1), 5,
		"Gram Marx's real equipped items (orb_gram.tres/staff_gram.tres, energy_cost > 0) must set mage_recharge_budget_remaining == intellect (5)"
	)


func test_gram_marx_real_equipped_items_include_at_least_one_dischargeable_item() -> void:
	# Direct proof that the ">0" precondition is satisfied by REAL, factory-
	# emitted equipped_items -- not merely inferred from the aggregate
	# mage_recharge_budget_remaining assertion above.
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_1")
	var equipped_items: Array = combatant.get("equipped_items", [])
	assert_true(equipped_items.size() > 0, "fixture assumption: Gram Marx must build with at least one equipped item")

	var has_dischargeable_item := false
	for item in equipped_items:
		if item != null and item.energy_cost > 0:
			has_dischargeable_item = true
			break
	assert_true(has_dischargeable_item, "at least one of Gram Marx's real equipped items must have energy_cost > 0")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: enemy path stays 0/0/0, unaffected by these real items
# ══════════════════════════════════════════════════════════════════════════

func test_build_enemy_combatant_still_emits_zero_rest_fields_with_real_items_unaffected() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(SKELETON_PATH, null, "skeleton_1")
	assert_false(combatant.has("error"), "fixture assumption: skeleton.tres must build a valid combatant with no error")

	assert_eq(combatant.get("stamina_max", -1), 0, "an enemy combatant must emit stamina_max == 0")
	assert_eq(combatant.get("intellect", -1), 0, "an enemy combatant must emit intellect == 0")
	assert_eq(
		combatant.get("mage_recharge_budget_remaining", -1), 0,
		"an enemy combatant must emit mage_recharge_budget_remaining == 0, regardless of orb_gram.tres/staff_gram.tres now authoring energy_cost > 0"
	)
