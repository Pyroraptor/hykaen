extends GutTest
## tests/unit/test_combatant_factory_rest_fields.gd — FEAT-001 (US-001;
## iteration AB-0, rest mechanics steel thread).
##
## Verifies infrastructure/combatant_factory.gd derives the three new
## Combatant rest-related fields (stamina_max, intellect,
## mage_recharge_budget_remaining):
##   - build_party_combatant(): stamina_max from Attributes.compute_stamina(),
##     intellect from character.attributes, mage_recharge_budget_remaining
##     from intellect ONLY when any equipped item has energy_cost > 0 (via
##     the same _duck_get() equipped-items walk BeginCastUseCase already
##     established), else 0.
##   - build_enemy_combatant(): 0/0/0 for all three fields.
##
## Originally, no currently-authored ItemResource fixture declared
## energy_cost, so the ">0" branch of mage_recharge_budget_remaining was
## exercised only against CombatantFactory's extracted, duck-typed helper
## with synthetic Dictionary-shaped items -- mirroring this codebase's
## established convention (see BeginCastUseCase._duck_get()) of duck-typing
## equipped items rather than depending on a concrete ItemResource shape.
## Both the duck-typed helper coverage below AND the ">0" branch are now
## ALSO covered against real production fixtures by FEAT-377 (DEF-001):
## data/items/orb_gram.tres/staff_gram.tres now author energy_cost=1, so
## Gram Marx's real equipped_items resolve mage_recharge_budget_remaining
## to his intellect (5) without any FakeEquippedItem double -- see
## tests/unit/test_combatant_factory_real_item_recharge.gd for the
## dedicated real-fixture suite, and
## test_build_party_combatant_mage_recharge_budget_remaining_for_gram_marx_real_fixture
## below for the updated in-file assertion (previously asserted 0, back
## when no real fixture authored energy_cost).

const CombatantFactoryClass = preload("res://infrastructure/combatant_factory.gd")
const AttributesClass = preload("res://core/rules/attributes.gd")
const RNGClass = preload("res://core/rules/rng.gd")

const TITUS_PATH: String = "res://data/characters/titus.tres"
const MARIGOLD_PATH: String = "res://data/characters/marigold.tres"
const GRAM_MARX_PATH: String = "res://data/characters/gram_marx.tres"

const SKELETON_PATH: String = "res://data/enemies/skeleton.tres"


# ── stamina_max ──────────────────────────────────────────────────────────────

func test_build_party_combatant_stamina_max_matches_compute_stamina() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(TITUS_PATH, null, "titus_1")
	assert_false(combatant.has("error"), "fixture assumption: titus.tres must build a valid combatant with no error")

	var character = ResourceLoader.load(TITUS_PATH)
	var attrs := AttributesClass.new(RNGClass.new(0))
	var expected_stamina: int = attrs.compute_stamina(character.attributes, character.class_ref)

	assert_eq(
		combatant.get("stamina_max", -1), expected_stamina,
		"build_party_combatant() must derive stamina_max from Attributes.compute_stamina()"
	)
	assert_true(combatant.get("stamina_max", 0) > 0, "fixture assumption: titus's derived stamina_max must be > 0")


func test_build_party_combatant_stamina_max_equals_stamina_at_construction() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_1")
	assert_eq(
		combatant.get("stamina_max", -1), combatant.get("stamina", -2),
		"a freshly-built combatant must start with stamina == stamina_max (full stamina)"
	)


# ── intellect ────────────────────────────────────────────────────────────────

func test_build_party_combatant_intellect_resolves_from_character_attributes() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_1")

	var character = ResourceLoader.load(GRAM_MARX_PATH)
	var expected_intellect: int = int(character.attributes.get("intellect", -1))
	assert_eq(expected_intellect, 5, "fixture assumption: gram_marx.tres's authored intellect must be 5")

	assert_eq(
		combatant.get("intellect", -1), expected_intellect,
		"build_party_combatant() must resolve intellect from character.attributes"
	)


func test_build_party_combatant_intellect_resolves_for_non_caster() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(TITUS_PATH, null, "titus_1")

	var character = ResourceLoader.load(TITUS_PATH)
	assert_eq(
		combatant.get("intellect", -1), int(character.attributes.get("intellect", -1)),
		"build_party_combatant() must resolve intellect from character.attributes for every party combatant, caster or not"
	)


# ── mage_recharge_budget_remaining: real fixtures (no dischargeable items) ──

func test_build_party_combatant_mage_recharge_budget_remaining_zero_for_titus() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(TITUS_PATH, null, "titus_1")
	assert_eq(
		combatant.get("mage_recharge_budget_remaining", -1), 0,
		"Titus has no dischargeable (energy_cost > 0) equipped items -- mage_recharge_budget_remaining must be 0"
	)


func test_build_party_combatant_mage_recharge_budget_remaining_zero_for_marigold() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(MARIGOLD_PATH, null, "marigold_1")
	assert_eq(
		combatant.get("mage_recharge_budget_remaining", -1), 0,
		"Marigold has no dischargeable (energy_cost > 0) equipped items -- mage_recharge_budget_remaining must be 0"
	)


func test_build_party_combatant_mage_recharge_budget_remaining_for_gram_marx_real_fixture() -> void:
	# FEAT-377 (DEF-001): data/items/orb_gram.tres and data/items/
	# staff_gram.tres now author energy_cost=1, so Gram Marx's REAL
	# equipped_items (no FakeEquippedItem double) make him a dischargeable
	# Mage-paradigm combatant -- mage_recharge_budget_remaining must resolve
	# to his intellect (5), not 0. See tests/unit/
	# test_combatant_factory_real_item_recharge.gd for the dedicated
	# real-fixture suite this criterion is drawn from.
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_1")
	assert_eq(
		combatant.get("mage_recharge_budget_remaining", -1), 5,
		"Gram Marx's real equipped items (orb_gram.tres/staff_gram.tres) now author energy_cost > 0 -- mage_recharge_budget_remaining must equal his intellect (5)"
	)


# ── mage_recharge_budget_remaining: duck-typed helper, synthetic items ──────

func test_mage_recharge_budget_remaining_helper_returns_intellect_when_item_dischargeable() -> void:
	var factory := CombatantFactoryClass.new()
	var equipped_items: Array = [{"energy_cost": 1, "is_charged": true}]
	assert_eq(
		factory.compute_mage_recharge_budget_remaining(5, equipped_items), 5,
		"any equipped item with energy_cost > 0 must set the budget to intellect"
	)


func test_mage_recharge_budget_remaining_helper_returns_zero_when_no_item_dischargeable() -> void:
	var factory := CombatantFactoryClass.new()
	var equipped_items: Array = [{"energy_cost": 0, "is_charged": true}]
	assert_eq(
		factory.compute_mage_recharge_budget_remaining(5, equipped_items), 0,
		"no equipped item with energy_cost > 0 must leave the budget at 0"
	)


func test_mage_recharge_budget_remaining_helper_returns_zero_for_empty_equipped_items() -> void:
	var factory := CombatantFactoryClass.new()
	assert_eq(
		factory.compute_mage_recharge_budget_remaining(5, []), 0,
		"no equipped items at all must leave the budget at 0"
	)


func test_mage_recharge_budget_remaining_helper_tolerates_null_items_in_array() -> void:
	var factory := CombatantFactoryClass.new()
	var equipped_items: Array = [null, {"energy_cost": 2, "is_charged": false}]
	assert_eq(
		factory.compute_mage_recharge_budget_remaining(3, equipped_items), 3,
		"a null entry in equipped_items must not crash the walk; a later dischargeable item still sets the budget"
	)


# ── enemy path: 0/0/0 ────────────────────────────────────────────────────────

func test_build_enemy_combatant_emits_zero_stamina_max_intellect_and_budget() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(SKELETON_PATH, null, "skeleton_1")
	assert_false(combatant.has("error"), "fixture assumption: skeleton.tres must build a valid combatant with no error")

	assert_eq(combatant.get("stamina_max", -1), 0, "an enemy combatant must emit stamina_max == 0")
	assert_eq(combatant.get("intellect", -1), 0, "an enemy combatant must emit intellect == 0")
	assert_eq(combatant.get("mage_recharge_budget_remaining", -1), 0, "an enemy combatant must emit mage_recharge_budget_remaining == 0")
