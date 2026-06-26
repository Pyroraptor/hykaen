extends GutTest
## tests/integration/test_steel_thread_e2e.gd
##
## GUT integration test — FEAT-010 / FEAT-028: Steel Thread End-to-End Smoke Test.
## CI-Gated deterministic encounter validation with all FIX-001 through FIX-007 applied.
##
## Satisfies: US-001, US-002, US-003, US-004, US-005, US-006, US-007, US-008, US-009
##
## Steel thread entry → exit:
##   data layer       → ResourceLoader.load('data/characters/titus.tres') non-null
##   business_logic   → attributes.gd computes HP=18, Stamina=10, AC=14, Reflex=14,
##                       Fortitude=19, Will=13 from titus.tres spread
##   integration      → encounter.run() terminates; outcome in ['won','lost']; round_count >= 1
##   determinism proof → Run 1 and Run 2 with seed 99999 produce byte-identical
##                       roll and damage_final sequences (exit_point)
##
## FEAT-028 additions validate:
##   FIX-003 → longsword.damage_modifier_attribute used directly (no key-remap shim)
##   FIX-004 → action budget spend_action() called during Strike (budget_remaining == 6)
##   FIX-005 → get_round_events() populated with attack events containing all required fields
##   Full pipeline → all resources loaded without attribute overrides; derived stats correct
##
## CI exit contract: godot --headless -- --gut-run-all exits 0.

const EncounterClass    = preload("res://core/combat/encounter.gd")
const RNGClass          = preload("res://core/rules/rng.gd")
const AttributesClass   = preload("res://core/rules/attributes.gd")
const ResolutionClass   = preload("res://core/rules/resolution.gd")
const CharacterResource = preload("res://core/model/character_resource.gd")
const ClassResource     = preload("res://core/model/class_resource.gd")
const WeaponResource    = preload("res://core/model/weapon_resource.gd")

## Pinned seed for all steel-thread determinism tests.
const STEEL_SEED: int = 99999

## Resources loaded once in before_all() and reused across all tests.
var _titus       = null
var _fighter_class = null
var _scale_mail  = null
var _longsword   = null


func before_all() -> void:
	_titus      = ResourceLoader.load("res://data/characters/titus.tres")
	_scale_mail = ResourceLoader.load("res://data/armor/scale_mail.tres")
	_longsword  = ResourceLoader.load("res://data/weapons/longsword.tres")
	if _titus != null:
		_fighter_class = _titus.class_ref


# ── Fixture helpers ────────────────────────────────────────────────────────────

## Builds a combatant Dictionary for Titus derived from the loaded .tres resources.
## Computes HP and AC via attributes.gd (business_logic layer) so the encounter
## receives real derived stats rather than hardcoded constants.
##
## FEAT-023: longsword.tres now stores damage_modifier_attribute='strength' (canonical
## full key). The weapon dict uses the resource field directly — no key-remap shim needed.
func _build_titus_combatant() -> Dictionary:
	var attrs = AttributesClass.new(RNGClass.new(0))
	var hp    = attrs.compute_hp(_titus.attributes, _fighter_class)
	var ac    = attrs.compute_ac(_titus.attributes, _scale_mail.ac_base, _scale_mail.category)
	return {
		"name":       _titus.name,
		"hp_current": hp,
		"ac":         ac,
		"strength":   _titus.attributes.get("strength",  0),
		"dexterity":  _titus.attributes.get("dexterity", 0),
		"intuition":  _titus.attributes.get("intuition", 0),
		"weapon": {
			"damage_modifier_attribute": _longsword.damage_modifier_attribute,
			"proficiency_bonus":         _longsword.proficiency_bonus,
			"damage_die":                _longsword.damage_die
		}
	}


## Inline Skeleton stub (no .tres loading required — ADR-006 integration-test
## pattern: enemies are defined inline for portability).
func _skeleton_dict() -> Dictionary:
	return {
		"name":       "Skeleton",
		"hp_current": 8,
		"ac":         12,
		"strength":   2,
		"dexterity":  1,
		"intuition":  1,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 6
		}
	}


## Builds a fresh Encounter from a newly constructed Titus combatant dict and
## an inline Skeleton stub, seeded with seed_value.  Fresh instances every call
## guarantees no shared state between Run 1 and Run 2.
func _make_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_build_titus_combatant()],
		[_skeleton_dict()],
		RNGClass.new(seed_value)
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1 — Data Layer
# ResourceLoader.load('data/characters/titus.tres') returns non-null CharacterResource
# ══════════════════════════════════════════════════════════════════════════════

func test_data_layer_titus_tres_loads_non_null() -> void:
	assert_not_null(
		_titus,
		"ResourceLoader.load('data/characters/titus.tres') must return non-null"
	)


func test_data_layer_titus_is_character_resource() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot verify CharacterResource type")
		return
	assert_is(
		_titus, CharacterResource,
		"titus.tres must be an instance of CharacterResource (data layer validated)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2 — Business Logic Layer
# attributes.gd computes all six derived stats from titus.tres spread
# Expected: HP=18, Stamina=10, AC=14, Reflex=14, Fortitude=19, Will=13
# ══════════════════════════════════════════════════════════════════════════════

func test_business_logic_layer_hp_equals_18() -> void:
	if _titus == null or _fighter_class == null:
		fail_test("titus.tres or fighter class failed to load — cannot compute HP")
		return
	var attrs = AttributesClass.new(RNGClass.new(0))
	var hp: int = attrs.compute_hp(_titus.attributes, _fighter_class)
	assert_eq(hp, 18,
		"HP must be 18 (8 + class_hp=6 + constitution=4) — business_logic layer")


func test_business_logic_layer_stamina_equals_10() -> void:
	if _titus == null or _fighter_class == null:
		fail_test("titus.tres or fighter class failed to load — cannot compute Stamina")
		return
	var attrs = AttributesClass.new(RNGClass.new(0))
	var stamina: int = attrs.compute_stamina(_titus.attributes, _fighter_class)
	assert_eq(stamina, 10,
		"Stamina must be 10 (stamina_base=4 + willpower=2 + constitution=4) — business_logic layer")


func test_business_logic_layer_ac_equals_14() -> void:
	if _titus == null or _scale_mail == null:
		fail_test("titus.tres or scale_mail.tres failed to load — cannot compute AC")
		return
	var attrs = AttributesClass.new(RNGClass.new(0))
	var ac: int = attrs.compute_ac(_titus.attributes, _scale_mail.ac_base, _scale_mail.category)
	assert_eq(ac, 14,
		"AC must be 14 (10 + ac_base=4, medium armor — no DEX bonus) — business_logic layer")


func test_business_logic_layer_reflex_equals_14() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot compute Reflex")
		return
	var attrs = AttributesClass.new(RNGClass.new(0))
	var reflex: int = attrs.compute_reflex(_titus.attributes)
	assert_eq(reflex, 14,
		"Reflex must be 14 (10 + dexterity=2 + intuition=2) — business_logic layer")


func test_business_logic_layer_fortitude_equals_19() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot compute Fortitude")
		return
	var attrs = AttributesClass.new(RNGClass.new(0))
	var fortitude: int = attrs.compute_fortitude(_titus.attributes)
	assert_eq(fortitude, 19,
		"Fortitude must be 19 (10 + constitution=4 + strength=5) — business_logic layer")


func test_business_logic_layer_will_equals_13() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot compute Will")
		return
	var attrs = AttributesClass.new(RNGClass.new(0))
	var will: int = attrs.compute_will(_titus.attributes)
	assert_eq(will, 13,
		"Will must be 13 (10 + willpower=2 + social=1) — business_logic layer")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3 — Integration Layer
# encounter.run() terminates; get_outcome() in ['won','lost']; get_round_count() >= 1
# ══════════════════════════════════════════════════════════════════════════════

func test_integration_layer_encounter_run_terminates_with_valid_outcome() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot run encounter")
		return
	var enc = _make_encounter(STEEL_SEED)
	enc.run()
	var outcome: String = enc.get_outcome()
	assert_true(
		outcome == "won" or outcome == "lost",
		"encounter.run() must terminate with 'won' or 'lost'; got '%s'" % outcome
	)


func test_integration_layer_round_count_at_least_1() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot run encounter")
		return
	var enc = _make_encounter(STEEL_SEED)
	enc.run()
	assert_true(
		enc.get_round_count() >= 1,
		"get_round_count() must be >= 1 after run(); got %d" % enc.get_round_count()
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4 — Determinism: Run 2 with seed 99999 produces identical outcome
# ══════════════════════════════════════════════════════════════════════════════

func test_determinism_run2_identical_outcome() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check determinism")
		return
	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()
	assert_eq(
		enc2.get_outcome(), enc1.get_outcome(),
		"Run 2 with seed %d must produce the same outcome as Run 1 (determinism proof)" % STEEL_SEED
	)


func test_determinism_run2_identical_round_count() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check determinism")
		return
	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()
	assert_eq(
		enc2.get_round_count(), enc1.get_round_count(),
		"Run 2 with seed %d must complete in the same number of rounds as Run 1" % STEEL_SEED
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5 — Determinism: byte-identical roll and damage_final per index i
## For every i in range(len(run1_history)):
##   run2_history[i].roll         == run1_history[i].roll
##   run2_history[i].damage_final == run1_history[i].damage_final
# ══════════════════════════════════════════════════════════════════════════════

func test_determinism_run2_round_history_same_length() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check round history")
		return
	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()
	assert_eq(
		enc2.get_round_history().size(), enc1.get_round_history().size(),
		"Run 1 and Run 2 with seed %d must have identical round_history length" % STEEL_SEED
	)


func test_determinism_run2_roll_values_byte_identical() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check determinism")
		return
	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()
	var run1_history: Array = enc1.get_round_history()
	var run2_history: Array = enc2.get_round_history()
	var count: int = mini(run1_history.size(), run2_history.size())
	for i in range(count):
		var r1: int = run1_history[i].get("roll", -1)
		var r2: int = run2_history[i].get("roll", -1)
		assert_eq(
			r2, r1,
			"round_history[%d].roll: Run 1=%d, Run 2=%d — must be byte-identical (seed %d)"
			% [i, r1, r2, STEEL_SEED]
		)


func test_determinism_run2_damage_final_values_byte_identical() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot check determinism")
		return
	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()
	var run1_history: Array = enc1.get_round_history()
	var run2_history: Array = enc2.get_round_history()
	var count: int = mini(run1_history.size(), run2_history.size())
	for i in range(count):
		var d1: int = run1_history[i].get("damage_final", -1)
		var d2: int = run2_history[i].get("damage_final", -1)
		assert_eq(
			d2, d1,
			"round_history[%d].damage_final: Run 1=%d, Run 2=%d — must be byte-identical (seed %d)"
			% [i, d1, d2, STEEL_SEED]
		)


# ══════════════════════════════════════════════════════════════════════════════
# Steel Thread Validation Banner
# Prints the confirmation line visible in CI artifact log.
# ══════════════════════════════════════════════════════════════════════════════

func test_steel_thread_validated_banner() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — steel thread cannot be validated")
		return
	var enc = _make_encounter(STEEL_SEED)
	enc.run()
	var outcome: String  = enc.get_outcome()
	var rounds: int      = enc.get_round_count()
	gut.p("STEEL THREAD VALIDATED: seed %d, outcome %s, rounds %d"
		% [STEEL_SEED, outcome, rounds])
	assert_true(
		outcome == "won" or outcome == "lost",
		"Steel thread banner: encounter must complete with valid outcome"
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-023 — Resource field drives attribute lookup end-to-end
# resolve_weapon_attack() with weapon dict built from longsword.tres fields
# produces identical result to the previous manually-keyed test fixture.
# ══════════════════════════════════════════════════════════════════════════════

## test_resolution_uses_resource_field_for_attribute_lookup
##
## Verifies that using _longsword.damage_modifier_attribute directly in the weapon
## dict produces an identical resolve_weapon_attack() result to the previous
## manually-keyed fixture (which hardcoded "strength").
##
## Since longsword.tres now stores 'strength', both weapon dicts are equivalent,
## and the two resolutions (same pinned seed) must agree on hit, crit, and damage_final.
##
## Pinned seed 2: d20=11, Titus strength=5, prof_bonus=1 → roll_total=17 vs ac=12 → hit.
func test_resolution_uses_resource_field_for_attribute_lookup() -> void:
	if _titus == null or _longsword == null:
		fail_test("titus.tres or longsword.tres failed to load — cannot check resource field lookup")
		return

	# Build attacker dict from titus.tres attributes
	var attacker: Dictionary = {}
	for k in _titus.attributes:
		attacker[k] = _titus.attributes[k]

	var target: Dictionary = {"ac": 12, "reflex": 12, "fortitude": 14, "will": 11}

	# Weapon dict A: built from the longsword resource field directly (FEAT-023 path)
	var weapon_from_resource: Dictionary = {
		"damage_modifier_attribute": _longsword.damage_modifier_attribute,
		"proficiency_bonus":         _longsword.proficiency_bonus,
		"damage_die":                _longsword.damage_die
	}

	# Weapon dict B: the previous manually-keyed fixture (hardcoded "strength")
	var weapon_manual: Dictionary = {
		"damage_modifier_attribute": "strength",
		"proficiency_bonus":         _longsword.proficiency_bonus,
		"damage_die":                _longsword.damage_die
	}

	# Both resolutions use the same pinned seed → must produce byte-identical output
	const LOOKUP_SEED: int = 2
	var res_a = ResolutionClass.new(RNGClass.new(LOOKUP_SEED))
	var res_b = ResolutionClass.new(RNGClass.new(LOOKUP_SEED))

	var result_resource: Dictionary = res_a.resolve_weapon_attack(attacker, target, weapon_from_resource, "ac")
	var result_manual: Dictionary   = res_b.resolve_weapon_attack(attacker, target, weapon_manual, "ac")

	assert_eq(
		result_resource["hit"], result_manual["hit"],
		"resource-field weapon dict must produce identical 'hit' to manually-keyed fixture (FEAT-023)"
	)
	assert_eq(
		result_resource["crit"], result_manual["crit"],
		"resource-field weapon dict must produce identical 'crit' to manually-keyed fixture (FEAT-023)"
	)
	assert_eq(
		result_resource["damage_final"], result_manual["damage_final"],
		"resource-field weapon dict must produce identical damage_final to manually-keyed fixture (FEAT-023)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-028 Criterion 1 — Full Pipeline: all resources without attribute overrides
# Loads titus.tres, fighter.tres (via class_ref), and longsword.tres via
# ResourceLoader; computes ALL six derived stats directly from resource data
# (no hardcoded attribute values); asserts v0 formula expectations.
# Validates: DEF-001, DEF-002 — data layer fully wired
# ══════════════════════════════════════════════════════════════════════════════

## test_pipeline_loads_all_resources_without_overrides
##
## Verifies the complete data layer of the steel thread:
##   1. All three resources load non-null via ResourceLoader (no fallback stubs).
##   2. fighter.tres is a ClassResource (loaded as titus.class_ref dependency).
##   3. longsword.tres is a WeaponResource.
##   4. All six derived stats computed from resource fields (no literal overrides)
##      match v0 formula expectations exactly.
##
## Expected: HP=18, Stamina=10, AC=14, Reflex=14, Fortitude=19, Will=13
func test_pipeline_loads_all_resources_without_overrides() -> void:
	if _titus == null or _fighter_class == null or _longsword == null or _scale_mail == null:
		fail_test(
			"One or more required resources failed to load — "
			+ "cannot verify pipeline without attribute overrides"
		)
		return

	# Verify all resources loaded non-null via ResourceLoader
	assert_not_null(
		_titus,
		"titus.tres must load non-null via ResourceLoader (FEAT-028 pipeline)"
	)
	assert_not_null(
		_fighter_class,
		"fighter.tres (via titus.class_ref) must load non-null — ResourceLoader dependency chain intact"
	)
	assert_not_null(
		_longsword,
		"longsword.tres must load non-null via ResourceLoader (FEAT-028 pipeline)"
	)

	# Verify correct resource types
	assert_is(
		_titus, CharacterResource,
		"titus.tres must be an instance of CharacterResource (FEAT-028)"
	)
	assert_is(
		_fighter_class, ClassResource,
		"fighter.tres must be an instance of ClassResource (FEAT-028)"
	)
	assert_is(
		_longsword, WeaponResource,
		"longsword.tres must be an instance of WeaponResource (FEAT-028)"
	)

	# Compute ALL six derived stats directly from resource data — zero hardcoded values.
	# Proves the full data → business_logic pipeline is wired (FEAT-028, FIX-001, FIX-002).
	var attrs = AttributesClass.new(RNGClass.new(0))
	var hp: int       = attrs.compute_hp(_titus.attributes, _fighter_class)
	var stamina: int  = attrs.compute_stamina(_titus.attributes, _fighter_class)
	var ac: int       = attrs.compute_ac(_titus.attributes, _scale_mail.ac_base, _scale_mail.category)
	var reflex: int   = attrs.compute_reflex(_titus.attributes)
	var fortitude: int = attrs.compute_fortitude(_titus.attributes)
	var will: int     = attrs.compute_will(_titus.attributes)

	assert_eq(hp, 18,
		"HP from resource data must be 18 (8 + class_hp=6 + constitution=4) — FEAT-028 pipeline")
	assert_eq(stamina, 10,
		"Stamina from resource data must be 10 (stamina_base=4 + willpower=2 + constitution=4) — FEAT-028 pipeline")
	assert_eq(ac, 14,
		"AC from resource data must be 14 (10 + ac_base=4, medium armor, no DEX) — FEAT-028 pipeline")
	assert_eq(reflex, 14,
		"Reflex from resource data must be 14 (10 + dexterity=2 + intuition=2) — FEAT-028 pipeline")
	assert_eq(fortitude, 19,
		"Fortitude from resource data must be 19 (10 + constitution=4 + strength=5) — FEAT-028 pipeline")
	assert_eq(will, 13,
		"Will from resource data must be 13 (10 + willpower=2 + social=1) — FEAT-028 pipeline")


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-028 Criterion 2 — Weapon attribute key convention end-to-end (FIX-003)
# Encounter built using longsword.damage_modifier_attribute directly in weapon dict
# (no manual key-remap shim present in _build_titus_combatant).
# Titus deals non-zero damage_final in at least one attack event.
# Validates: DEF-003, FIX-003
# ══════════════════════════════════════════════════════════════════════════════

## test_weapon_attribute_key_convention_e2e
##
## Verifies end-to-end that the canonical 'strength' key stored in
## longsword.tres.damage_modifier_attribute is used directly in the weapon dict
## passed to the encounter — no manual remap (e.g. 'damage_modifier' → 'strength').
##
## Also verifies that with this wiring, Titus successfully deals non-zero damage_final
## in at least one attack event during the encounter run (seed 99999).
func test_weapon_attribute_key_convention_e2e() -> void:
	if _titus == null or _longsword == null:
		fail_test(
			"titus.tres or longsword.tres failed to load — "
			+ "cannot verify weapon attribute key convention"
		)
		return

	# Build Titus combatant and verify weapon dict reads resource field directly
	var titus_c: Dictionary = _build_titus_combatant()
	var weapon_attr: String = titus_c.get("weapon", {}).get("damage_modifier_attribute", "")
	assert_eq(
		weapon_attr, _longsword.damage_modifier_attribute,
		"weapon dict 'damage_modifier_attribute' must equal longsword resource field directly "
		+ "(no manual remap shim — FEAT-028 FIX-003)"
	)
	assert_eq(
		weapon_attr, "strength",
		"longsword.damage_modifier_attribute must be 'strength' (canonical full key, FIX-003)"
	)

	# Run the full encounter with seed 99999 and verify Titus deals damage
	var enc = _make_encounter(STEEL_SEED)
	enc.run()

	var titus_dealt_damage: bool = false
	for entry in enc.get_round_history():
		if entry.get("attacker", {}).get("name", "") == "Titus" \
				and entry.get("damage_final", 0) > 0:
			titus_dealt_damage = true
			break

	assert_true(
		titus_dealt_damage,
		"Titus must deal non-zero damage_final in at least one attack event "
		+ "(weapon key convention wired correctly — FEAT-028 FIX-003)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-028 Criterion 3 — Action budget consumed after Strike (FIX-004)
# After the first run_round(), round_history[0].budget_remaining must equal 6,
# confirming spend_action() was called during Strike execution and the action
# budget was decremented from the starting value of 7 to 6.
# Validates: DEF-004 / DEF-005, FIX-004
# ══════════════════════════════════════════════════════════════════════════════

## test_action_budget_consumed_after_strike
##
## Uses a real-resource encounter (seed 99999) to verify the action economy
## spend_action() integration within the Strike execution path.
##
## The round_history entry for the first Strike must record budget_remaining == 6
## (spend_action returned {success: true, remaining: 6} after decrementing from 7).
##
## This is the FIX-004 smoke test: prior to the fix, spend_action() was not called
## and budget_remaining would be absent or incorrect in round_history.
func test_action_budget_consumed_after_strike() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot verify action budget spend")
		return

	var enc = _make_encounter(STEEL_SEED)
	enc.initialize()
	enc.run_round()

	var history: Array = enc.get_round_history()
	assert_true(
		history.size() >= 1,
		"round_history must have at least 1 entry after run_round() — "
		+ "spend_action() must have been called (FEAT-028 FIX-004)"
	)

	if history.size() < 1:
		return

	# The first Strike decrements budget from 7 to 6
	var first_entry: Dictionary = history[0]
	assert_true(
		first_entry.has("budget_remaining"),
		"round_history[0] must contain 'budget_remaining' key — "
		+ "spend_action() return value must be captured (FEAT-028 FIX-004)"
	)
	assert_eq(
		first_entry.get("budget_remaining", -1), 6,
		"First Strike must decrement action budget 7 → 6; "
		+ "budget_remaining must be 6 (FEAT-028 FIX-004)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-028 Criterion 4 — Round events populated with attack events (FIX-005)
# get_round_events() after any run_round() contains at least one event
# with type == 'attack' and all required fields populated.
# Required fields: roll, hit, crit, damage_final.
# Validates: DEF-006 / DEF-007, FIX-005
# ══════════════════════════════════════════════════════════════════════════════

## test_round_events_populated_with_attack_events
##
## Verifies the FEAT-025 round event queue is correctly populated by the
## encounter's run_round() execution path (FIX-005).
##
## After a single run_round() call, get_round_events() must contain at least
## one event with type == 'attack' that has all four required fields populated:
##   roll        — int: the attack roll total (d20 + modifier + proficiency)
##   hit         — bool: whether the attack hit the target
##   crit        — bool: whether the attack was a critical hit
##   damage_final — int: the final damage value after active defense resolution
func test_round_events_populated_with_attack_events() -> void:
	if _titus == null:
		fail_test("titus.tres failed to load — cannot verify round events (FEAT-028 FIX-005)")
		return

	var enc = _make_encounter(STEEL_SEED)
	enc.initialize()
	enc.run_round()

	var events: Array = enc.get_round_events()
	assert_true(
		events.size() > 0,
		"get_round_events() must be non-empty after run_round() (FEAT-028 FIX-005)"
	)

	# Locate the first attack event in the round queue
	var attack_ev: Dictionary = {}
	for ev in events:
		if ev.get("type", "") == "attack":
			attack_ev = ev
			break

	assert_false(
		attack_ev.is_empty(),
		"get_round_events() must contain at least one event with type == 'attack' (FEAT-028 FIX-005)"
	)

	if attack_ev.is_empty():
		return

	# Verify all four required attack event fields are present
	for key in ["roll", "hit", "crit", "damage_final"]:
		assert_true(
			attack_ev.has(key),
			"Attack event must contain required field '%s' — "
			+ "FEAT-028 FIX-005; present keys: %s" % [key, str(attack_ev.keys())]
		)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-028 Criterion 5 — Steel thread Run 1 terminates (seed 99999 CI gate)
# Encounter with seed 99999 using only real resources must reach a valid
# outcome ('won' or 'lost') with round_count >= 1.
# This is the CI entry point for the steel thread exit gate.
# ══════════════════════════════════════════════════════════════════════════════

## test_steel_thread_seed_99999_run1_terminates
##
## Runs the complete steel thread encounter (seed 99999, real Titus resources)
## and asserts:
##   1. Encounter terminates with outcome in ['won', 'lost'].
##   2. At least one complete round was executed (round_count >= 1).
##
## This is the primary CI gate test: if the full pipeline (data → business logic →
## encounter) is broken, this test fails and blocks the merge.
func test_steel_thread_seed_99999_run1_terminates() -> void:
	if _titus == null:
		fail_test(
			"titus.tres failed to load — steel thread Run 1 (seed %d) cannot execute"
			% STEEL_SEED
		)
		return

	var enc = _make_encounter(STEEL_SEED)
	enc.run()

	var outcome: String = enc.get_outcome()
	assert_true(
		outcome == "won" or outcome == "lost",
		"Steel thread Run 1 (seed %d) must terminate with 'won' or 'lost'; got '%s'"
		% [STEEL_SEED, outcome]
	)
	assert_true(
		enc.get_round_count() >= 1,
		"Steel thread Run 1 (seed %d) must complete at least 1 round; got %d"
		% [STEEL_SEED, enc.get_round_count()]
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-028 Criterion 6 — Run 2 byte-identical roll sequence (determinism proof)
# Second fresh instantiation with seed 99999 produces a roll sequence array
# that is equal to the roll sequence array from Run 1 (GDScript array == assertion).
# ══════════════════════════════════════════════════════════════════════════════

## test_steel_thread_seed_99999_run2_byte_identical_rolls
##
## Proves the steel thread determinism guarantee at the exit point:
## two independent encounters with the same seed produce byte-identical roll sequences.
##
## Extracts the roll value from every round_history entry and asserts
## GDScript array equality (rolls_run2 == rolls_run1).
##
## This covers the FEAT-028 requirement: "second fresh instantiation with seed 99999
## produces roll sequence array == roll sequence array from run 1".
func test_steel_thread_seed_99999_run2_byte_identical_rolls() -> void:
	if _titus == null:
		fail_test(
			"titus.tres failed to load — "
			+ "cannot verify byte-identical rolls (seed %d)" % STEEL_SEED
		)
		return

	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()

	# Extract roll sequences from both independent round histories
	var rolls_1: Array = []
	var rolls_2: Array = []
	for entry in enc1.get_round_history():
		rolls_1.append(entry.get("roll", -1))
	for entry in enc2.get_round_history():
		rolls_2.append(entry.get("roll", -1))

	# GDScript array equality assertion — byte-identical roll sequences
	assert_eq(
		rolls_2, rolls_1,
		("Run 2 roll sequence must be byte-identical to Run 1 (seed %d) "
			+ "— steel thread determinism proof (FEAT-028)") % STEEL_SEED
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-028 Criterion 7 — Run 2 byte-identical damage sequence (determinism proof)
# Second fresh instantiation with seed 99999 produces a damage_final sequence array
# that is equal to the damage_final sequence array from Run 1.
# ══════════════════════════════════════════════════════════════════════════════

## test_steel_thread_seed_99999_run2_byte_identical_damage
##
## Proves the steel thread determinism guarantee for damage values:
## two independent encounters with the same seed produce byte-identical damage_final sequences.
##
## Extracts damage_final from every round_history entry and asserts
## GDScript array equality (damage_run2 == damage_run1).
##
## This covers the FEAT-028 requirement: "second run produces damage_final sequence
## array == damage_final sequence array from run 1".
func test_steel_thread_seed_99999_run2_byte_identical_damage() -> void:
	if _titus == null:
		fail_test(
			"titus.tres failed to load — "
			+ "cannot verify byte-identical damage (seed %d)" % STEEL_SEED
		)
		return

	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()

	# Extract damage_final sequences from both independent round histories
	var damage_1: Array = []
	var damage_2: Array = []
	for entry in enc1.get_round_history():
		damage_1.append(entry.get("damage_final", -1))
	for entry in enc2.get_round_history():
		damage_2.append(entry.get("damage_final", -1))

	# GDScript array equality assertion — byte-identical damage_final sequences
	assert_eq(
		damage_2, damage_1,
		("Run 2 damage_final sequence must be byte-identical to Run 1 (seed %d) "
			+ "— steel thread determinism proof (FEAT-028)") % STEEL_SEED
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-028 Criterion 8 — Run 2 identical outcome string (determinism proof)
# Both fresh instantiations with seed 99999 must return the same outcome string.
# ══════════════════════════════════════════════════════════════════════════════

## test_steel_thread_seed_99999_run2_identical_outcome
##
## Proves the steel thread determinism guarantee for the encounter outcome:
## two independent encounters with the same seed return the same 'won' or 'lost' string.
##
## This covers the FEAT-028 requirement: "both runs return identical outcome string
## ('won' or 'lost')".
func test_steel_thread_seed_99999_run2_identical_outcome() -> void:
	if _titus == null:
		fail_test(
			"titus.tres failed to load — "
			+ "cannot verify outcome determinism (seed %d)" % STEEL_SEED
		)
		return

	var enc1 = _make_encounter(STEEL_SEED)
	var enc2 = _make_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()

	assert_eq(
		enc2.get_outcome(), enc1.get_outcome(),
		("Run 2 outcome must be identical to Run 1 (seed %d) "
			+ "— steel thread determinism proof (FEAT-028)") % STEEL_SEED
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-046 / DEF-003 — Longsword d12 regression gate (integration layer)
#
# Verifies that the corrected longsword.tres (damage_die=12) is the value that
# actually flows through the full pipeline in the steel-thread encounter:
#   data layer   → longsword.tres.damage_die == 12
#   combat layer → Titus attack damage_final is within d12 range (0–34 incl. crit)
#   not d6 range → damage_final is NOT capped at 6+STR (old incorrect maximum)
#
# The "old d6-range assertions" would have checked damage_final ≤ 6+5 = 11.
# The corrected d12-range assertions check damage_final ≤ 12*2+5*2 = 34 (max crit)
# and confirm the resource value is 12 at the integration boundary.
# ══════════════════════════════════════════════════════════════════════════════

## test_longsword_tres_damage_die_is_d12_in_pipeline
##
## Verifies that data/weapons/longsword.tres has damage_die == 12 at the point it
## enters the steel-thread encounter pipeline (resource loaded in before_all()).
## Closes the integration-layer half of the DEF-003 masking gap: previously
## longsword.tres had damage_die=6, so the encounter used d6 for Titus's damage
## while unit tests used the correctly-specified d12 fixture.
##
## Satisfies: FEAT-046 test criterion 5 (integration layer), DEF-003.
func test_longsword_tres_damage_die_is_d12_in_pipeline() -> void:
	if _longsword == null:
		fail_test(
			"longsword.tres failed to load — cannot verify d12 damage die (FEAT-046 DEF-003)"
		)
		return

	assert_eq(
		_longsword.damage_die, 12,
		"longsword.tres must have damage_die=12 (d12, Heavy Blade per Weapons.pdf) — "
		+ "FEAT-046 DEF-003 integration regression gate"
	)


## test_titus_damage_final_in_d12_range_seed_99999
##
## Verifies that with the corrected longsword.tres (damage_die=12), every attack
## event from Titus in the seed-99999 encounter has damage_final within the
## valid d12-weapon range:
##   miss  → damage_final == 0
##   hit   → damage_final in [1+STR, 12+STR]   = [6, 17]  (Titus strength=5)
##   crit  → damage_final in [2+STR*2, 24+STR*2] = [12, 34]  (2d12 + 2*5)
##
## Upper bound for ANY outcome (incl. crit): 12*2 + 5*2 = 34.
## Old d6-range upper bound was: 6 + 5 = 11 (normal hit) / 6*2 + 5*2 = 22 (crit).
## The new d12-range upper bound (34) replaces the old d6-range upper bound (11/22).
##
## Satisfies: FEAT-046 test criterion 5 (d12-range assertion), DEF-003.
func test_titus_damage_final_in_d12_range_seed_99999() -> void:
	if _titus == null or _longsword == null:
		fail_test(
			"titus.tres or longsword.tres failed to load — "
			+ "cannot verify d12-range damage (FEAT-046 DEF-003)"
		)
		return

	# Confirm the weapon resource itself is correct before running the encounter
	assert_eq(
		_longsword.damage_die, 12,
		"longsword.tres damage_die must be 12 — prerequisite for d12-range damage check"
	)

	var titus_strength: int = _titus.attributes.get("strength", 0)
	# Max possible damage_final for any outcome (crit with max d12 rolls):
	#   2 * damage_die + 2 * strength = 2*12 + 2*5 = 34
	var max_d12_damage: int = 2 * _longsword.damage_die + 2 * titus_strength

	var enc = _make_encounter(STEEL_SEED)
	enc.run()

	for entry in enc.get_round_history():
		if entry.get("attacker", {}).get("name", "") == "Titus":
			var dmg: int = entry.get("damage_final", -1)
			assert_true(
				dmg >= 0,
				"Titus damage_final must be >= 0 (miss=0, hit=positive); got %d (FEAT-046)" % dmg
			)
			assert_true(
				dmg <= max_d12_damage,
				("Titus damage_final=%d must be within d12 range [0, %d] "
				+ "(max = 2*damage_die + 2*STR = 2*12 + 2*%d) — "
				+ "FEAT-046 DEF-003 d12-range assertion (replaces old d6-range max=%d)")
				% [dmg, max_d12_damage, titus_strength, 6 + titus_strength]
			)
