extends GutTest
## tests/unit/test_combatant_rest_fields.gd — FEAT-001 (US-001; iteration
## AB-0, rest mechanics steel thread).
##
## Covers the three new Combatant domain fields this feature adds:
## stamina_max, intellect, mage_recharge_budget_remaining. Verifies
## from_dict()/to_dict() round-trip them without loss and that they default
## to 0 when absent from the input spec — mirroring the existing
## tests/unit/core/domain/test_combatant_combat_state.gd round-trip
## convention for the pre-existing fields.

const CombatantClass = preload("res://core/domain/combatant.gd")


func _full_spec() -> Dictionary:
	return {
		"combatant_id":     "gram_marx_1",
		"name":             "Gram Marx",
		"team":             "Player",
		"hp_current":       10,
		"hp_max":           10,
		"stamina":          6,
		"stamina_max":      9,
		"conscious":        true,
		"ac":               12,
		"fortitude":        10,
		"reflex":           10,
		"will":             10,
		"strength":         1,
		"dexterity":        2,
		"intuition":        3,
		"intellect":        5,
		"mage_recharge_budget_remaining": 4,
		"weapon":           {},
		"skills":           {},
		"conditions":       [],
		"spellcasting_attribute_score": 0,
		"known_spell_ids":  [],
	}


# ── from_dict() reads the new fields ────────────────────────────────────────

func test_from_dict_reads_stamina_max() -> void:
	var c := CombatantClass.from_dict(_full_spec())
	assert_eq(c.stamina_max, 9, "from_dict() must read stamina_max from the spec")


func test_from_dict_reads_intellect() -> void:
	var c := CombatantClass.from_dict(_full_spec())
	assert_eq(c.intellect, 5, "from_dict() must read intellect from the spec")


func test_from_dict_reads_mage_recharge_budget_remaining() -> void:
	var c := CombatantClass.from_dict(_full_spec())
	assert_eq(c.mage_recharge_budget_remaining, 4, "from_dict() must read mage_recharge_budget_remaining from the spec")


# ── defaults when absent ────────────────────────────────────────────────────

func test_from_dict_defaults_stamina_max_to_zero_when_absent() -> void:
	var c := CombatantClass.from_dict({})
	assert_eq(c.stamina_max, 0, "stamina_max must default to 0 when absent from the input dict")


func test_from_dict_defaults_intellect_to_zero_when_absent() -> void:
	var c := CombatantClass.from_dict({})
	assert_eq(c.intellect, 0, "intellect must default to 0 when absent from the input dict")


func test_from_dict_defaults_mage_recharge_budget_remaining_to_zero_when_absent() -> void:
	var c := CombatantClass.from_dict({})
	assert_eq(c.mage_recharge_budget_remaining, 0, "mage_recharge_budget_remaining must default to 0 when absent from the input dict")


func test_new_combatant_defaults_new_fields_to_zero() -> void:
	var c := CombatantClass.new()
	assert_eq(c.stamina_max, 0, "a freshly-constructed Combatant.new() must default stamina_max to 0")
	assert_eq(c.intellect, 0, "a freshly-constructed Combatant.new() must default intellect to 0")
	assert_eq(c.mage_recharge_budget_remaining, 0, "a freshly-constructed Combatant.new() must default mage_recharge_budget_remaining to 0")


# ── to_dict() emits the new fields ───────────────────────────────────────────

func test_to_dict_emits_stamina_max() -> void:
	var c := CombatantClass.from_dict(_full_spec())
	assert_eq(c.to_dict().get("stamina_max", -1), 9, "to_dict() must emit stamina_max")


func test_to_dict_emits_intellect() -> void:
	var c := CombatantClass.from_dict(_full_spec())
	assert_eq(c.to_dict().get("intellect", -1), 5, "to_dict() must emit intellect")


func test_to_dict_emits_mage_recharge_budget_remaining() -> void:
	var c := CombatantClass.from_dict(_full_spec())
	assert_eq(c.to_dict().get("mage_recharge_budget_remaining", -1), 4, "to_dict() must emit mage_recharge_budget_remaining")


# ── round-trip ────────────────────────────────────────────────────────────────

func test_round_trip_preserves_new_fields_without_loss() -> void:
	var spec := _full_spec()
	var round_tripped := CombatantClass.from_dict(spec).to_dict()
	assert_eq(round_tripped.get("stamina_max"), spec["stamina_max"], "round-trip must preserve stamina_max")
	assert_eq(round_tripped.get("intellect"), spec["intellect"], "round-trip must preserve intellect")
	assert_eq(round_tripped.get("mage_recharge_budget_remaining"), spec["mage_recharge_budget_remaining"], "round-trip must preserve mage_recharge_budget_remaining")


func test_round_trip_via_second_from_dict_pass_is_stable() -> void:
	# from_dict(spec).to_dict() fed back into from_dict() again must be a fixed
	# point -- guards against any asymmetry between the read and emit sides.
	var spec := _full_spec()
	var once := CombatantClass.from_dict(spec).to_dict()
	var twice := CombatantClass.from_dict(once).to_dict()
	assert_eq(twice.get("stamina_max"), once.get("stamina_max"))
	assert_eq(twice.get("intellect"), once.get("intellect"))
	assert_eq(twice.get("mage_recharge_budget_remaining"), once.get("mage_recharge_budget_remaining"))


# ── attribute() accessor picks up intellect (Combatant.attribute() reads via
#    get(attr_name), which resolves automatically once a field is declared) ──

func test_attribute_accessor_resolves_intellect() -> void:
	var c := CombatantClass.from_dict(_full_spec())
	assert_eq(c.attribute("intellect"), 5, "attribute('intellect') must resolve the same value as c.intellect")
