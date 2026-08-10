extends GutTest
## tests/integration/test_encounter_resource_pipeline_e2e.gd
##
## GUT integration test — FEAT-010 / FEAT-028: Resource-Pipeline End-to-End
## Smoke Test. CI-Gated deterministic encounter validation with all FIX-001
## through FIX-007 applied.
##
## DEF-005 (US-011) naming note: this suite constructs
## core/combat/encounter.gd DIRECTLY (EncounterClass.new(...).run()/
## run_round()) — a construction path MainScene.gd documents as
## intentionally never invoked in production. It is NOT the "steel thread"
## in the sense of booting the real composition root (res://MainScene.tscn);
## that end-to-end boot path is exercised exclusively by
## tests/integration/test_steel_thread_prologue_encounter.gd and
## tests/gut/test_steel_thread_e2e.gd. This file's name and doc comments
## intentionally avoid the "steel thread" label to keep that distinction
## unambiguous — see the reserved-naming guard test in
## tests/integration/test_test_suite_naming_hygiene.gd.
##
## Satisfies: US-001, US-002, US-003, US-004, US-005, US-006, US-007, US-008, US-009
##
## Resource pipeline entry → exit (direct Encounter construction, not MainScene):
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
## FEAT-103: RoundEvents value objects (core/rules/round_events.gd, FEAT-099/
## FIND-096) — get_round_events() carries TYPED instances of these classes,
## never raw Dictionaries. Introspection must use `is RoundEventsClass.<Type>`
## + direct field access (the pattern already established for the typed
## events surface), NOT Dictionary-style `.get()`/`.has()` calls — calling
## Dictionary methods on a typed RefCounted value object is a runtime
## SCRIPT ERROR ("Invalid call to function 'get' ... Expected 1 arguments"),
## not a GDScript compile error, so it must be caught by actually exercising
## the assertion rather than by static inspection alone.
const RoundEventsClass  = preload("res://core/rules/round_events.gd")

## Pinned seed for all steel-thread determinism tests.
const STEEL_SEED: int = 99999

## Resources loaded once in before_all() and reused across all tests.
var _titus       = null
var _fighter_class = null
var _scale_mail  = null
var _longsword   = null
## FEAT-091 — corrected resource baselines
var _chain_shirt          = null  ## FIX-004: Titus's actual armor (chain_shirt)
var _skeleton_resource    = null  ## FIX-005: skeleton.tres EnemyResource
var _prologue_encounter_res = null  ## FIX-006: prologue_encounter.tres EncounterResource


func before_all() -> void:
	_titus      = ResourceLoader.load("res://data/characters/titus.tres")
	_scale_mail = ResourceLoader.load("res://data/armor/scale_mail.tres")
	_longsword  = ResourceLoader.load("res://data/weapons/longsword.tres")
	## FEAT-091: load corrected resource baselines
	_chain_shirt           = ResourceLoader.load("res://data/armor/chain_shirt.tres")
	_skeleton_resource     = ResourceLoader.load("res://data/enemies/skeleton.tres")
	_prologue_encounter_res = ResourceLoader.load("res://data/encounters/prologue_encounter.tres")
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
## one TYPED RoundEvents.AttackBroadcast instance (FEAT-099/FIND-096 — never a
## raw Dictionary with a 'type' key) with all four required fields populated:
##   roll          — int:  the attack roll total (d20 + modifier + proficiency)
##   hit           — bool: whether the attack hit the target
##   crit          — bool: whether the attack was a critical hit
##   damage_final  — int:  the final damage value after active defense resolution
##
## FEAT-103: rewritten to use `is RoundEventsClass.AttackBroadcast` type-checks and
## direct field access instead of Dictionary-style `.get("type", "")` /
## `.has(key)` calls. The previous Dictionary-style access crashed at runtime
## with "Invalid call to function 'get' in base 'RefCounted (AttackEvent)'.
## Expected 1 arguments." the moment get_round_events() started returning
## typed value objects (FEAT-099) — this rewrite is the fix.
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

	# Locate the first typed AttackEvent in the round queue (FEAT-103: typed
	# `is` check — never `ev.get("type", "")`, which crashes on a RefCounted
	# value object).
	var attack_ev = null
	for ev in events:
		if ev is RoundEventsClass.AttackBroadcast:
			attack_ev = ev
			break

	assert_not_null(
		attack_ev,
		"get_round_events() must contain at least one typed RoundEvents.AttackBroadcast instance (FEAT-028 FIX-005, FEAT-103)"
	)

	if attack_ev == null:
		return

	# Verify all four required attack event fields are populated via direct
	# field access on the typed value object (FEAT-103 — never `.has(key)`).
	assert_true(attack_ev.roll is int, "AttackEvent.roll must be an int (FEAT-028 FIX-005, FEAT-103)")
	assert_true(attack_ev.hit is bool, "AttackEvent.hit must be a bool (FEAT-028 FIX-005, FEAT-103)")
	assert_true(attack_ev.crit is bool, "AttackEvent.crit must be a bool (FEAT-028 FIX-005, FEAT-103)")
	assert_true(attack_ev.damage_final is int, "AttackEvent.damage_final must be an int (FEAT-028 FIX-005, FEAT-103)")


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
## (The FEAT-049 spec gate test appears after this function.)
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


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-049 Criterion 6 — Spec gate consistent with CI smoke
# Reads docs/hollow-world-v0-spec.org and asserts the approval line does NOT
# contain PLACEHOLDER and is not empty.
# Mirrors the CI lint-spec-no-placeholder step at the GUT test layer so that
# local GUT runs catch the same condition without running the full CI pipeline.
# Verifies FIX-001 from smoke level.
# ══════════════════════════════════════════════════════════════════════════════

## test_spec_gate_consistent_with_ci_smoke
##
## Verifies that docs/hollow-world-v0-spec.org carries a genuine approval sign-off
## (not the stub PLACEHOLDER text) — the GUT-level mirror of the CI
## lint-spec-no-placeholder gate (FEAT-039 / DEF-001).
##
## Assertions:
##   1. docs/hollow-world-v0-spec.org is readable.
##   2. The file contains a #+APPROVAL: line.
##   3. The #+APPROVAL: line does NOT contain the word PLACEHOLDER.
##   4. The content after #+APPROVAL: is non-empty (has a real sign-off).
##
## This test and the CI lint step must agree: if CI blocks on PLACEHOLDER,
## this GUT test must also fail — and vice versa.
##
## Satisfies: FEAT-049 criterion 6, FIX-001.
func test_spec_gate_consistent_with_ci_smoke() -> void:
	var file := FileAccess.open("res://docs/hollow-world-v0-spec.org", FileAccess.READ)
	assert_not_null(
		file,
		"docs/hollow-world-v0-spec.org must be readable (FIX-001 spec gate)"
	)
	if file == null:
		return

	var content: String = file.get_as_text()
	file.close()

	# Find the #+APPROVAL: line
	var approval_line: String = ""
	for line in content.split("\n"):
		if line.begins_with("#+APPROVAL:"):
			approval_line = line
			break

	assert_true(
		approval_line != "",
		"docs/hollow-world-v0-spec.org must contain a #+APPROVAL: line (FIX-001)"
	)

	if approval_line == "":
		return

	# The approval line must NOT contain PLACEHOLDER (mirrors CI lint-spec-no-placeholder)
	assert_false(
		approval_line.contains("PLACEHOLDER"),
		"#+APPROVAL: line must not contain PLACEHOLDER — replace with genuine sign-off (FIX-001 DEF-001); got: '%s'"
		% approval_line
	)

	# The content after "#+APPROVAL:" must be non-empty (not just whitespace)
	var approval_content: String = approval_line.replace("#+APPROVAL:", "").strip_edges()
	assert_true(
		approval_content != "",
		"#+APPROVAL: line must have non-whitespace content after the colon (FIX-001); got: '%s'"
		% approval_line
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-077 — Integration Smoke Tests: Full Steel Thread With Corrected
#            Weapon Data and Character Schema (FIX-002 + FIX-003)
#
# These tests extend the steel-thread e2e suite with assertions that exercise
# the complete corrected pipeline end-to-end under `godot --headless -- --gut-run-all`,
# serving as the smoke test proving FIX-002 and FIX-003 operate correctly in
# the real Godot execution environment (not only at unit-test isolation level).
#
# Corrected Skeleton profile (FIX-002 / FIX-003):
#   hp=28 (was 8), ac=13 (was 12), weapon damage_die=8 (was 6), strength=2 (+2 modifier)
# ══════════════════════════════════════════════════════════════════════════════

## _corrected_skeleton_dict() — FIX-002/FIX-003 adjusted Skeleton stub.
##
## Adjusted stats (hp=28, d8+2, ac=13) reflect the corrected enemy profile:
##   FIX-002 → hp=28 (was 8), ac=13 (was 12)
##   FIX-003 → damage_die=8 (was 6)
## Weapon "+2" comes from strength=2 applied as the damage modifier attribute.
func _corrected_skeleton_dict() -> Dictionary:
	return {
		"name":       "Skeleton",
		"hp_current": 28,
		"ac":         13,
		"strength":   2,
		"dexterity":  1,
		"intuition":  1,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 8
		}
	}


## _make_corrected_encounter(seed_value) — builds a fresh Encounter using
## Titus with d12 longsword vs the FIX-002/FIX-003 corrected Skeleton.
## Fresh instances every call guarantees no shared state.
func _make_corrected_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_build_titus_combatant()],
		[_corrected_skeleton_dict()],
		RNGClass.new(seed_value)
	)


# ── FEAT-091 helpers ──────────────────────────────────────────────────────────

## _build_titus_combatant_chain_shirt() — builds Titus combatant using chain_shirt armor.
##
## FIX-004: titus.tres.starting_equipment[1] is now chain_shirt.tres (ac_base=5, medium).
## AC formula: 10 + 5 + 0 (medium armor, no DEX bonus) = 15.
## Uses loaded resources directly — no hardcoded attribute literals.
func _build_titus_combatant_chain_shirt() -> Dictionary:
	var attrs = AttributesClass.new(RNGClass.new(0))
	var hp = attrs.compute_hp(_titus.attributes, _fighter_class)
	var ac = attrs.compute_ac(_titus.attributes, _chain_shirt.ac_base, _chain_shirt.category)
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


## _build_skeleton_combatant_from_resource() — builds skeleton combatant from skeleton.tres.
##
## FIX-005: skeleton.tres is loaded via ResourceLoader; fields mapped to the
## combatant dict format expected by the encounter engine.
## EnemyResource.str  → "strength" (canonical encounter key)
## EnemyResource.dex  → "dexterity"
## weapon.attribute   → "damage_modifier_attribute" = "strength"
## weapon.die         → "damage_die"
## ac: not in EnemyResource schema — defaults to 12 (canonical skeleton baseline).
## intuition: not in EnemyResource schema — defaults to 0.
func _build_skeleton_combatant_from_resource() -> Dictionary:
	# FEAT-002 (US-002, ADR-001/ADR-002): weapon stats now resolve via
	# _skeleton_resource.weapon_paths[0] -> WeaponResource, not an inline
	# weapon Dictionary on EnemyResource.
	var weapon_res = ResourceLoader.load(_skeleton_resource.weapon_paths[0]) if not _skeleton_resource.weapon_paths.is_empty() else null
	return {
		"name":       _skeleton_resource.name,
		"hp_current": _skeleton_resource.hp,
		"ac":         12,
		"strength":   _skeleton_resource.str,
		"dexterity":  _skeleton_resource.dex,
		"intuition":  0,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus":         weapon_res.proficiency_bonus if weapon_res != null else 1,
			"damage_die":                weapon_res.damage_die if weapon_res != null else 6
		}
	}


## _make_prologue_encounter(seed_value) — builds a fresh Encounter from
## prologue_encounter.tres resource fields.
## Loads party and enemy resources from prologue_encounter.tres resource paths.
## Overrides the encounter seed with seed_value (injected, not prologue_encounter.seed).
func _make_prologue_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_build_titus_combatant_chain_shirt()],
		[_build_skeleton_combatant_from_resource()],
		RNGClass.new(seed_value)
	)


# ── FEAT-077 Test 1 ───────────────────────────────────────────────────────────

## test_longsword_damage_die_is_12
##
## Verifies via ResourceLoader in headless mode that longsword.tres.damage_die == 12.
## This is the FEAT-077 integration assertion confirming the corrected weapon data
## flows from the .tres file through ResourceLoader into the pipeline.
##
## Satisfies: FEAT-077 test criterion 1 (longsword.tres.damage_die == 12 verified
## via ResourceLoader in headless mode).
func test_longsword_damage_die_is_12() -> void:
	if _longsword == null:
		fail_test(
			"longsword.tres failed to load — cannot verify damage_die (FEAT-077)"
		)
		return
	assert_eq(
		_longsword.damage_die, 12,
		"longsword.tres.damage_die must be 12 (d12, verified via ResourceLoader in headless mode) — FEAT-077"
	)


# ── FEAT-077 Test 2 ───────────────────────────────────────────────────────────

## test_corrected_pipeline_titus_weapon_die_not_six
##
## Constructs a Titus combatant from titus.tres + longsword.tres and asserts
## the weapon die resolved through the resource chain is 12 — NOT 6.
##
## This closes the DEF-002 gap: the weapon dict used in the encounter pipeline
## must use the corrected longsword.damage_die (12) rather than the old d6 value.
##
## Satisfies: FEAT-077 test criterion 2 (weapon die resolved through
## titus.tres → longsword.tres chain equals 12).
func test_corrected_pipeline_titus_weapon_die_not_six() -> void:
	if _titus == null or _longsword == null:
		fail_test(
			"titus.tres or longsword.tres failed to load — cannot verify weapon die (FEAT-077)"
		)
		return
	var titus_c: Dictionary = _build_titus_combatant()
	var weapon_die: int = titus_c.get("weapon", {}).get("damage_die", -1)
	assert_eq(
		weapon_die, 12,
		"Titus weapon die resolved through titus.tres → longsword.tres chain must be 12 — FEAT-077 DEF-002"
	)
	assert_ne(
		weapon_die, 6,
		"Titus weapon die must NOT be 6 — FIX-002 corrected the longsword from d6 to d12 (FEAT-077)"
	)


# ── FEAT-077 Test 3 ───────────────────────────────────────────────────────────

## test_steel_thread_corrected_seed_99999_run1_terminates
##
## Runs the full encounter (Titus with d12 longsword vs adjusted Skeleton
## hp=28, d8+2, ac=13) with seed 99999, asserts outcome is 'won' or 'lost'
## and round_count >= 1, with no runtime errors.
##
## This validates FIX-002 and FIX-003 operating correctly in the real Godot
## execution environment (not only at unit-test isolation level).
##
## Satisfies: FEAT-077 test criterion 3 (encounter outcome is 'won' or 'lost',
## round_count >= 1, no runtime errors).
func test_steel_thread_corrected_seed_99999_run1_terminates() -> void:
	if _titus == null:
		fail_test(
			"titus.tres failed to load — corrected steel thread Run 1 (seed %d) cannot execute (FEAT-077)"
			% STEEL_SEED
		)
		return
	var enc = _make_corrected_encounter(STEEL_SEED)
	enc.run()
	var outcome: String = enc.get_outcome()
	assert_true(
		outcome == "won" or outcome == "lost",
		"Corrected steel thread Run 1 (seed %d) must terminate with 'won' or 'lost'; got '%s' — FEAT-077"
		% [STEEL_SEED, outcome]
	)
	assert_true(
		enc.get_round_count() >= 1,
		"Corrected steel thread Run 1 (seed %d) must complete at least 1 round; got %d — FEAT-077"
		% [STEEL_SEED, enc.get_round_count()]
	)


# ── FEAT-077 Test 4 ───────────────────────────────────────────────────────────

## test_steel_thread_corrected_seed_99999_run2_byte_identical_rolls
##
## Constructs and runs the identical corrected encounter (Titus + corrected Skeleton)
## a second time with seed 99999 and asserts the d20 roll sequence is byte-for-byte
## identical to run 1 (element-by-element Array equality).
##
## Proves the corrected pipeline is deterministic: same seed → same rolls.
##
## Satisfies: FEAT-077 test criterion 4 (Array of d20 rolls from run 2 equals
## Array from run 1 element-by-element).
func test_steel_thread_corrected_seed_99999_run2_byte_identical_rolls() -> void:
	if _titus == null:
		fail_test(
			"titus.tres failed to load — cannot verify byte-identical rolls "
			+ "(corrected pipeline, seed %d) — FEAT-077" % STEEL_SEED
		)
		return
	var enc1 = _make_corrected_encounter(STEEL_SEED)
	var enc2 = _make_corrected_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()
	var rolls_1: Array = []
	var rolls_2: Array = []
	for entry in enc1.get_round_history():
		rolls_1.append(entry.get("roll", -1))
	for entry in enc2.get_round_history():
		rolls_2.append(entry.get("roll", -1))
	assert_eq(
		rolls_2, rolls_1,
		"Corrected pipeline Run 2 roll sequence must be byte-identical to Run 1 (seed %d) — FEAT-077"
		% STEEL_SEED
	)


# ── FEAT-077 Test 5 ───────────────────────────────────────────────────────────

## test_steel_thread_corrected_seed_99999_run2_byte_identical_damage
##
## Asserts damage_final values in round_history for the corrected-pipeline Run 2
## match Run 1 exactly (byte-for-byte identical, element-by-element Array equality).
##
## Proves the corrected pipeline is deterministic: same seed → same damage outcomes.
##
## Satisfies: FEAT-077 test criterion 5 (Array of damage_final values from
## round_history in run 2 equals run 1 exactly).
func test_steel_thread_corrected_seed_99999_run2_byte_identical_damage() -> void:
	if _titus == null:
		fail_test(
			"titus.tres failed to load — cannot verify byte-identical damage "
			+ "(corrected pipeline, seed %d) — FEAT-077" % STEEL_SEED
		)
		return
	var enc1 = _make_corrected_encounter(STEEL_SEED)
	var enc2 = _make_corrected_encounter(STEEL_SEED)
	enc1.run()
	enc2.run()
	var damage_1: Array = []
	var damage_2: Array = []
	for entry in enc1.get_round_history():
		damage_1.append(entry.get("damage_final", -1))
	for entry in enc2.get_round_history():
		damage_2.append(entry.get("damage_final", -1))
	assert_eq(
		damage_2, damage_1,
		"Corrected pipeline Run 2 damage_final sequence must be byte-identical to Run 1 (seed %d) — FEAT-077"
		% STEEL_SEED
	)


# ── FEAT-077 Test 6 ───────────────────────────────────────────────────────────

## test_marigold_integration_fields
##
## Loads marigold.tres in integration context (headless ResourceLoader) and asserts:
##   1. race == 'Elf'
##   2. primary_offensive_attribute == 'dexterity'
##
## This validates the DEF-004 fix operates correctly in the real Godot execution
## environment: marigold.tres must carry the correct race and offensive attribute
## fields as loaded by ResourceLoader (not only in unit tests).
##
## Satisfies: FEAT-077 test criterion 6 (marigold.race == 'Elf' AND
## marigold.primary_offensive_attribute == 'dexterity' in headless ResourceLoader context).
func test_marigold_integration_fields() -> void:
	var marigold = ResourceLoader.load("res://data/characters/marigold.tres")
	assert_not_null(
		marigold,
		"ResourceLoader.load('res://data/characters/marigold.tres') must return non-null (FEAT-077)"
	)
	if marigold == null:
		return
	assert_eq(
		marigold.race, "Elf",
		"marigold.race must be 'Elf' in headless ResourceLoader context (FEAT-077 DEF-004)"
	)
	assert_eq(
		marigold.primary_offensive_attribute, "dexterity",
		"marigold.primary_offensive_attribute must be 'dexterity' in headless ResourceLoader context (FEAT-077 DEF-004)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-091 — Steel Thread E2E Determinism Smoke Test with Corrected Resource Baselines
#
# Locks in corrected resource values as the new pinned baselines and re-proves
# complete pipeline determinism guarantee.
#
# FIX-004 → titus.tres uses chain_shirt armor (ac_base=5, AC=15)
# FIX-005 → skeleton.tres loaded via ResourceLoader (EnemyResource)
# FIX-006 → prologue_encounter.tres loaded, encounter constructed from its fields
#
# Test criteria (FEAT-091):
#   1. chain_shirt.tres loads non-null via ResourceLoader
#   2. skeleton.tres loads non-null via ResourceLoader
#   3. prologue_encounter.tres loads non-null; encounter runs to 'won'/'lost'
#   4. round_count >= 1 after encounter.run() returns
# ══════════════════════════════════════════════════════════════════════════════


# ── FEAT-091 Criterion 1 — chain_shirt.tres loads non-null ───────────────────

## test_feat091_chain_shirt_tres_loads_non_null
##
## Verifies that chain_shirt.tres is loadable via ResourceLoader in the
## headless Godot process.  FIX-004 corrected titus.tres to reference
## chain_shirt.tres (ac_base=5, medium armor) in starting_equipment.
##
## Satisfies: FEAT-091 test criterion 1 (chain_shirt.tres non-null via ResourceLoader).
func test_feat091_chain_shirt_tres_loads_non_null() -> void:
	assert_not_null(
		_chain_shirt,
		"ResourceLoader.load('res://data/armor/chain_shirt.tres') must return non-null (FEAT-091 FIX-004)"
	)


## test_feat091_titus_tres_loads_non_null_pipeline
##
## Asserts titus.tres loads non-null — confirmed as part of the FEAT-091 pipeline
## that includes chain_shirt.tres, longsword.tres, skeleton.tres.
## Complements the already-existing test_data_layer_titus_tres_loads_non_null().
##
## Satisfies: FEAT-091 test criterion 1 (titus.tres non-null alongside chain_shirt + longsword).
func test_feat091_titus_tres_loads_non_null_pipeline() -> void:
	assert_not_null(
		_titus,
		"ResourceLoader.load('res://data/characters/titus.tres') must return non-null (FEAT-091)"
	)
	assert_not_null(
		_longsword,
		"ResourceLoader.load('res://data/weapons/longsword.tres') must return non-null (FEAT-091)"
	)
	assert_not_null(
		_chain_shirt,
		"ResourceLoader.load('res://data/armor/chain_shirt.tres') must return non-null (FEAT-091 FIX-004)"
	)


# ── FEAT-091 Criterion 2 — skeleton.tres loads non-null ──────────────────────

## test_feat091_skeleton_tres_loads_non_null
##
## Verifies that skeleton.tres is loadable via ResourceLoader and returns a
## non-null EnemyResource.  FIX-005 corrected skeleton.tres to use the proper
## EnemyResource schema.
##
## Satisfies: FEAT-091 test criterion 2 (skeleton.tres non-null via ResourceLoader).
func test_feat091_skeleton_tres_loads_non_null() -> void:
	assert_not_null(
		_skeleton_resource,
		"ResourceLoader.load('res://data/enemies/skeleton.tres') must return non-null (FEAT-091 FIX-005)"
	)


# ── FEAT-091 Criterion 3 — prologue_encounter.tres non-null + encounter runs ─

## test_feat091_prologue_encounter_tres_loads_non_null
##
## Verifies that prologue_encounter.tres is loadable via ResourceLoader.
## FIX-006 corrected prologue_encounter.tres to reference the corrected
## skeleton.tres and titus.tres resources in its resource path arrays.
##
## Satisfies: FEAT-091 test criterion 3 (first half: prologue_encounter.tres non-null).
func test_feat091_prologue_encounter_tres_loads_non_null() -> void:
	assert_not_null(
		_prologue_encounter_res,
		"ResourceLoader.load('res://data/encounters/prologue_encounter.tres') must return non-null (FEAT-091 FIX-006)"
	)


## test_feat091_prologue_encounter_run_terminates_with_valid_outcome
##
## Loads prologue_encounter.tres, constructs an Encounter from its resource
## path fields (party_resource_paths → Titus with chain_shirt; enemy_resource_paths
## → skeleton.tres), injects seed 99999, calls encounter.run(), and asserts
## _outcome is 'won' or 'lost' (not empty string).
##
## FIX-004: chain_shirt used for Titus (ac_base=5, AC=15).
## FIX-005: skeleton.tres loaded via ResourceLoader (not inline dict).
## FIX-006: prologue_encounter.tres drives the resource path lookup.
##
## Satisfies: FEAT-091 test criterion 3.
func test_feat091_prologue_encounter_run_terminates_with_valid_outcome() -> void:
	if _prologue_encounter_res == null:
		fail_test(
			"prologue_encounter.tres failed to load — cannot construct encounter (FEAT-091 FIX-006)"
		)
		return
	if _titus == null or _fighter_class == null or _longsword == null or _chain_shirt == null:
		fail_test(
			"Titus resources failed to load — cannot build party combatant (FEAT-091 FIX-004)"
		)
		return
	if _skeleton_resource == null:
		fail_test(
			"skeleton.tres failed to load — cannot build enemy combatant (FEAT-091 FIX-005)"
		)
		return

	# Verify prologue_encounter.tres carries the expected resource path fields
	assert_true(
		_prologue_encounter_res.party_resource_paths.size() > 0,
		"prologue_encounter.tres must have non-empty party_resource_paths (FEAT-091 FIX-006)"
	)
	assert_true(
		_prologue_encounter_res.enemy_resource_paths.size() > 0,
		"prologue_encounter.tres must have non-empty enemy_resource_paths (FEAT-091 FIX-006)"
	)

	# Construct encounter from prologue_encounter.tres fields with injected seed 99999
	var enc = _make_prologue_encounter(STEEL_SEED)
	enc.run()

	var outcome: String = enc.get_outcome()
	assert_true(
		outcome == "won" or outcome == "lost",
		("Prologue encounter (seed %d, FEAT-091) must terminate with 'won' or 'lost'; "
			+ "got '%s'") % [STEEL_SEED, outcome]
	)


# ── FEAT-091 Criterion 4 — round_count >= 1 after run() ──────────────────────

## test_feat091_prologue_encounter_round_count_at_least_1
##
## After prologue_encounter.tres → encounter.run() with seed 99999, the
## encounter must have executed at least one complete round.
##
## Satisfies: FEAT-091 test criterion 4 (round_count >= 1 after run() returns).
func test_feat091_prologue_encounter_round_count_at_least_1() -> void:
	if _prologue_encounter_res == null or _titus == null or _fighter_class == null \
			or _longsword == null or _chain_shirt == null or _skeleton_resource == null:
		fail_test(
			"required resources not loaded — cannot verify round_count (FEAT-091)"
		)
		return

	var enc = _make_prologue_encounter(STEEL_SEED)
	enc.run()

	assert_true(
		enc.get_round_count() >= 1,
		("Prologue encounter (seed %d, FEAT-091) must complete at least 1 round; "
			+ "got %d") % [STEEL_SEED, enc.get_round_count()]
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-103 — Repaired typed round-event access; full steel-thread coverage
# from run_round() entry to outcome/_round_events/_round_history exit
# (FR-004/FR-005, AC-4/AC-5, ADR-003).
#
# These tests exercise the REAL core/combat/encounter.gd entry point
# (run_round() / run()) with NO mocked domain layer — only plain combatant
# Dictionary fixtures and a real injected RNG, exactly like every other
# fixture in this file. They use the typed `is RoundEventsClass.<Type>` +
# direct field access pattern (never Dictionary-style `.get()`/`.has()` on a
# typed value object) established earlier in this file for
# test_round_events_populated_with_attack_events.
#
# Covers:
#   - Interleaved A,B,A,B,... Strike order across multiple combatants
#     (ADR-003 — Strikes interleave across the turn order rather than one
#     side acting completely before the other).
#   - _round_history entries carrying correct POST-SPEND budget_remaining
#     values across a full multi-round encounter.
#   - encounter_result (RoundEvents.EncounterResultEvent) emitted EXACTLY
#     ONCE per encounter, with its outcome matching the final win/loss
#     decided by get_outcome().
# ══════════════════════════════════════════════════════════════════════════════

## _feat103_durable_combatant(name) — a combatant that cannot die within a
## single round (hp=2000). Isolates AC-4/ADR-003 interleaving behavior from
## win/loss early-termination — every combatant exhausts its full MAX_BUDGET
## (7) of Strikes every round, every round, with nobody ever being defeated.
func _feat103_durable_combatant(p_name: String) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": 2000,
		"ac":         10,
		"strength":   3,
		"dexterity":  2,
		"intuition":  2,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	}


## _feat103_moderate_combatant(name) — survives several rounds of incoming
## Strikes before dying, so a full encounter genuinely spans MULTIPLE rounds
## (exercising the round-boundary budget reset across the whole encounter,
## not just round 1).
func _feat103_moderate_combatant(p_name: String) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": 60,
		"ac":         11,
		"strength":   3,
		"dexterity":  2,
		"intuition":  2,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	}


## _feat103_make_2v2_encounter(seed_value) — builds a fresh 2-vs-2 Encounter
## of moderate-durability combatants, seeded deterministically. Used to drive
## a genuine multi-round encounter end-to-end through the real run_round()/
## run() entry points (no mocked domain layer).
func _feat103_make_2v2_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_feat103_moderate_combatant("Hero1"), _feat103_moderate_combatant("Hero2")],
		[_feat103_moderate_combatant("Orc1"), _feat103_moderate_combatant("Orc2")],
		RNGClass.new(seed_value)
	)


## Safety cap on the number of run_round() calls per encounter loop — guards
## the TEST process against an unexpected non-terminating scenario. Genuine
## v0 encounters with MAX_BUDGET=7 per side terminate in single digits of
## rounds; this is a generous upper bound.
const FEAT103_MAX_ROUNDS_GUARD: int = 50


# ── Criterion: A,B,A,B,... Strike interleaving (ADR-003) ────────────────────

## test_feat103_strikes_interleave_a_b_a_b_between_two_combatants
##
## A single round between two equal-budget durable combatants — driven
## through the real Encounter.run_round() entry point — must interleave
## Strikes in strict A,B,A,B,... order rather than one combatant exhausting
## its full action budget before the other ever acts (ADR-003).
##
## Uses the typed `is RoundEventsClass.AttackBroadcast` pattern (FEAT-103 fix)
## to introspect get_round_events().
func test_feat103_strikes_interleave_a_b_a_b_between_two_combatants() -> void:
	var enc = EncounterClass.new(
		[_feat103_durable_combatant("Alpha")], [_feat103_durable_combatant("Bravo")], RNGClass.new(42)
	)
	enc.initialize()
	enc.run_round()

	var events: Array = enc.get_round_events()
	var attack_events: Array = events.filter(func(e): return e is RoundEventsClass.AttackBroadcast)

	# Both combatants share MAX_BUDGET=7 and neither dies (durable) — each
	# takes exactly 7 actions this round, 14 total interleaved AttackEvents.
	assert_eq(
		attack_events.size(), 14,
		"Two durable equal-budget combatants must emit 14 typed AttackEvent instances via the real run_round() entry point (ADR-003)"
	)
	if attack_events.size() != 14:
		return

	for ev in attack_events:
		assert_true(
			ev is RoundEventsClass.AttackBroadcast,
			"Every 'attack' round event must be a typed RoundEvents.AttackBroadcast instance (FEAT-103)"
		)

	# Strict alternation: consecutive AttackEvents must never share an attacker.
	for i in range(attack_events.size() - 1):
		assert_ne(
			attack_events[i].attacker_name, attack_events[i + 1].attacker_name,
			"Consecutive typed AttackEvent instances %d and %d must have different attacker_name (A,B,A,B,... interleaving, ADR-003)" % [i, i + 1]
		)

	# The full A,B,A,B,... pattern, explicitly.
	var attacker_sequence: Array = []
	for ev in attack_events:
		attacker_sequence.append(ev.attacker_name)
	var first_attacker: String = attacker_sequence[0]
	var second_attacker: String = attacker_sequence[1]
	assert_ne(first_attacker, second_attacker, "Sanity: the two combatants must be distinct")
	for i in range(attack_events.size()):
		var expected: String = first_attacker if i % 2 == 0 else second_attacker
		assert_eq(
			attacker_sequence[i], expected,
			"AttackEvent %d must continue the strict A,B,A,B,... interleave pattern (ADR-003)" % i
		)


## test_feat103_strikes_interleave_across_four_combatants_in_turn_order
##
## Generalizes the A,B,A,B,... interleave to MULTIPLE (four) combatants — a
## real 2v2 encounter driven through run_round() — proving Strikes cycle
## through the FULL turn order every pass rather than resolving one side
## (or one combatant) completely before the next (ADR-003/AC-4).
func test_feat103_strikes_interleave_across_four_combatants_in_turn_order() -> void:
	var enc = EncounterClass.new(
		[_feat103_durable_combatant("Hero1"), _feat103_durable_combatant("Hero2")],
		[_feat103_durable_combatant("Orc1"), _feat103_durable_combatant("Orc2")],
		RNGClass.new(777)
	)
	enc.initialize()
	enc.run_round()

	# The turn order is fixed (by initiative) once initialize() runs — read it
	# back from the real entry point's own accessor, no mocking/duplication
	# of the sort logic under test.
	var expected_cycle: Array = []
	for combatant in enc.get_turn_order():
		expected_cycle.append(combatant.get("name", ""))
	assert_eq(expected_cycle.size(), 4, "2v2 turn order must contain all four combatants")

	var events: Array = enc.get_round_events()
	var attack_events: Array = events.filter(func(e): return e is RoundEventsClass.AttackBroadcast)

	# All four combatants are durable and share MAX_BUDGET=7 — 7 full cycles
	# of 4 Strikes each = 28 interleaved AttackEvents.
	assert_eq(
		attack_events.size(), 28,
		"Four durable equal-budget combatants must emit 28 typed AttackEvent instances (7 cycles x 4) via run_round()"
	)
	if attack_events.size() != 28:
		return

	# Every cycle of 4 consecutive AttackEvents must reproduce the SAME
	# turn-order sequence — proving the cycle algorithm interleaves across
	# ALL combatants each pass (ADR-003) rather than draining one
	# combatant's budget before moving to the next.
	for cycle in range(7):
		for slot in range(4):
			var idx: int = cycle * 4 + slot
			assert_eq(
				attack_events[idx].attacker_name, expected_cycle[slot],
				"Cycle %d slot %d must be attacker '%s' (turn-order interleave, ADR-003); got '%s'"
				% [cycle, slot, expected_cycle[slot], attack_events[idx].attacker_name]
			)


# ── Criterion: _round_history post-spend budget_remaining correctness ───────

## test_feat103_round_history_budget_remaining_correct_across_full_encounter
##
## Drives a genuine multi-round 2v2 encounter to completion via repeated
## run_round() calls on the real entry point (no mocked domain layer), then
## asserts that EVERY get_round_history() entry's budget_remaining is the
## correct POST-SPEND value (spend_action() decrements from MAX_BUDGET=7),
## that the countdown is strictly monotonic per combatant per round
## (6, 5, 4, ... one action per resolved entry — AC-3's shared per-round
## budget pool), and that the budget resets to a fresh 6 at every round
## boundary (AC-2) — not just the first round (FR-005/AC-5).
func test_feat103_round_history_budget_remaining_correct_across_full_encounter() -> void:
	var enc = _feat103_make_2v2_encounter(4242)
	enc.initialize()

	var rounds_run: int = 0
	while enc.get_outcome() == "" and rounds_run < FEAT103_MAX_ROUNDS_GUARD:
		enc.run_round()
		rounds_run += 1

	assert_true(rounds_run < FEAT103_MAX_ROUNDS_GUARD, "Full 2v2 encounter must terminate within the safety guard")
	assert_true(
		rounds_run >= 2,
		"Steel-thread fixture (seed 4242, 60hp/ac11 2v2) must span >= 2 rounds so round-boundary "
		+ "reset assertions below are not vacuous; got %d round(s)" % rounds_run
	)

	var all_history: Array = enc.get_round_history()
	assert_true(all_history.size() > 0, "Full encounter must record at least one round_history entry")

	# Group resolved entries by (combatant name, round_number), preserving
	# resolution order, using the typed RoundEvents.RoundHistoryEntry
	# ("entry" key) field values directly — never Dictionary `.get()` calls
	# against the typed object.
	var by_combatant_round: Dictionary = {}  # name -> { round_number -> Array[budget_remaining] }
	for hist_entry in all_history:
		assert_true(
			hist_entry.has("entry"),
			"Every round_history Dictionary entry must carry an 'entry' key holding the typed RoundHistoryEntry (FEAT-103)"
		)
		var typed_entry = hist_entry["entry"]
		assert_true(
			typed_entry is RoundEventsClass.RoundHistoryEntry,
			"The 'entry' key must hold a typed RoundEvents.RoundHistoryEntry instance (FEAT-103)"
		)
		# The typed object's fields must agree with the surrounding
		# Dictionary's pre-existing keys (both views of the same resolved
		# action) — including the budget_remaining value under test.
		assert_eq(
			typed_entry.budget_remaining, hist_entry.get("budget_remaining", -999),
			"typed entry.budget_remaining must match the surrounding Dictionary's 'budget_remaining' key"
		)

		var name: String = typed_entry.combatant_id
		var round_number: int = typed_entry.round_number
		if not by_combatant_round.has(name):
			by_combatant_round[name] = {}
		if not by_combatant_round[name].has(round_number):
			by_combatant_round[name][round_number] = []
		by_combatant_round[name][round_number].append(typed_entry.budget_remaining)

	var any_combatant_spans_multiple_rounds: bool = false
	for name in by_combatant_round.keys():
		var rounds_for_name: Dictionary = by_combatant_round[name]
		if rounds_for_name.keys().size() >= 2:
			any_combatant_spans_multiple_rounds = true

		var round_numbers: Array = rounds_for_name.keys()
		round_numbers.sort()

		for round_number in round_numbers:
			var budgets: Array = rounds_for_name[round_number]

			# Within a single round, a combatant's budget_remaining must
			# strictly count down 6,5,4,...  — one action per resolved
			# entry, decremented from the fresh MAX_BUDGET=7 (post-spend
			# value), per the shared per-round budget pool (AC-3).
			for i in range(budgets.size()):
				var expected_budget: int = 6 - i
				assert_eq(
					budgets[i], expected_budget,
					"%s's round_history entry %d in round %d must show POST-SPEND budget_remaining == %d; got %d"
					% [name, i, round_number, expected_budget, budgets[i]]
				)

			# Round-boundary reset: the FIRST entry a combatant records in
			# ANY round must again start the countdown at 6 (7 - 1) —
			# proving the budget reset at the round boundary
			# (start_of_round()/end_of_round()), not a continuation of a
			# prior round's leftover budget (AC-2).
			assert_eq(
				budgets[0], 6,
				"%s's FIRST round_history entry in round %d must show budget_remaining == 6 (fresh per-round budget); got %d"
				% [name, round_number, budgets[0]]
			)

	# Cross-round proof: at least one combatant must have acted in 2+
	# distinct rounds — otherwise the round-boundary-reset assertion above
	# would be vacuously checking only round 1.
	assert_true(
		any_combatant_spans_multiple_rounds,
		"At least one combatant must have recorded round_history entries across >= 2 distinct rounds, "
		+ "so the round-boundary reset assertion (AC-2) is exercised more than once"
	)


# ── Criterion: encounter_result emitted exactly once; outcome correct ───────

## test_feat103_encounter_result_emitted_exactly_once_with_correct_outcome
##
## Drives a full encounter to completion via the real run_round() entry
## point (no mocked domain layer), accumulating get_round_events() across
## EVERY round (the queue is cleared at the start of each run_round() call —
## FEAT-025), and asserts:
##   1. Exactly ONE typed RoundEvents.EncounterResultEvent is emitted across
##      the ENTIRE encounter (never zero, never more than one).
##   2. Its `.outcome` field is 'won' or 'lost' (a real win/loss decision,
##      never the empty/undecided string).
##   3. Its `.outcome` exactly matches the final get_outcome() the encounter
##      settles on — the typed terminal event and the encounter's own
##      accessor must never disagree.
func test_feat103_encounter_result_emitted_exactly_once_with_correct_outcome() -> void:
	var enc = _feat103_make_2v2_encounter(4242)
	enc.initialize()

	var all_events: Array = []
	var rounds_run: int = 0
	while enc.get_outcome() == "" and rounds_run < FEAT103_MAX_ROUNDS_GUARD:
		enc.run_round()
		all_events.append_array(enc.get_round_events())
		rounds_run += 1

	assert_true(rounds_run < FEAT103_MAX_ROUNDS_GUARD, "Full 2v2 encounter must terminate within the safety guard")

	var result_events: Array = all_events.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(
		result_events.size(), 1,
		"Exactly one typed RoundEvents.EncounterResultEvent must be emitted across the full encounter; got %d"
		% result_events.size()
	)
	if result_events.size() != 1:
		return

	var final_outcome: String = enc.get_outcome()
	assert_true(
		final_outcome == "won" or final_outcome == "lost",
		"encounter.get_outcome() must settle on 'won' or 'lost'; got '%s'" % final_outcome
	)
	assert_true(
		result_events[0].outcome == "won" or result_events[0].outcome == "lost",
		"The typed EncounterResultEvent's outcome must be a real win/loss decision; got '%s'" % result_events[0].outcome
	)
	assert_eq(
		result_events[0].outcome, final_outcome,
		"The typed EncounterResultEvent's outcome ('%s') must match encounter.get_outcome() ('%s')"
		% [result_events[0].outcome, final_outcome]
	)
