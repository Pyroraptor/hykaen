extends GutTest
## tests/integration/test_encounter_integration.gd
##
## GUT integration test suite for core/combat/encounter.gd — Headless Encounter Loop.
## Validates all test criteria for FEAT-009 / US-009.
##
## Combatant dictionaries are stubbed inline — no .tres resource loading.
##
## Titus stats derived from titus.tres (FEAT-006):
##   hp_current=18, ac=14, strength=5, dexterity=2, intuition=2
##   weapon: {damage_die:6, proficiency_bonus:1, damage_modifier_attribute:'strength'}
##
## Skeleton stub (inline, ADR-006 integration test):
##   name='Skeleton', hp_current=8, ac=12, strength=2, dexterity=1, intuition=1
##   weapon: {damage_die:6, proficiency_bonus:1, damage_modifier_attribute:'strength'}

const EncounterClass = preload("res://core/combat/encounter.gd")
const RNGClass        = preload("res://core/rules/rng.gd")


# ── Shared fixture helpers ─────────────────────────────────────────────────────

## Returns a fresh Titus combatant dict (stats from titus.tres, FEAT-006).
func _titus_dict() -> Dictionary:
	return {
		"name": "Titus",
		"hp_current": 18,
		"ac": 14,
		"strength": 5,
		"dexterity": 2,
		"intuition": 2,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 6
		}
	}


## Returns a fresh Skeleton stub dict.
func _skeleton_dict() -> Dictionary:
	return {
		"name": "Skeleton",
		"hp_current": 8,
		"ac": 12,
		"strength": 2,
		"dexterity": 1,
		"intuition": 1,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 6
		}
	}


## Helper: build an Encounter from fresh combatant dicts and the given seed.
func _make_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_titus_dict()],
		[_skeleton_dict()],
		RNGClass.new(seed_value)
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: run() terminates with 'won' or 'lost' (seed 99999)
# ══════════════════════════════════════════════════════════════════════════════

func test_run_terminates_with_valid_outcome_seed_99999() -> void:
	var enc = _make_encounter(99999)
	enc.run()
	var outcome: String = enc.get_outcome()
	assert_true(
		outcome == "won" or outcome == "lost",
		"run() must terminate with outcome 'won' or 'lost'; got '%s'" % outcome
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: get_round_count() >= 1 after run() completes
# ══════════════════════════════════════════════════════════════════════════════

func test_round_count_at_least_1_after_run() -> void:
	var enc = _make_encounter(99999)
	enc.run()
	assert_true(
		enc.get_round_count() >= 1,
		"get_round_count() must be >= 1 after run(); got %d" % enc.get_round_count()
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: get_turn_order() after initialize() returns Array of length 2
#              sorted descending by initiative roll value
# ══════════════════════════════════════════════════════════════════════════════

func test_turn_order_length_2_after_initialize() -> void:
	var enc = _make_encounter(99999)
	enc.initialize()
	assert_eq(
		enc.get_turn_order().size(), 2,
		"get_turn_order() must have exactly 2 entries after initialize()"
	)


func test_turn_order_sorted_descending_after_initialize() -> void:
	var enc = _make_encounter(99999)
	enc.initialize()
	var order: Array = enc.get_turn_order()
	if order.size() < 2:
		fail_test("Cannot check descending order — fewer than 2 combatants in turn order")
		return
	var first_roll: int  = order[0].get("_initiative_roll", -1)
	var second_roll: int = order[1].get("_initiative_roll", -1)
	assert_true(
		first_roll >= second_roll,
		"Turn order must be descending: order[0]._initiative_roll (%d) >= order[1]._initiative_roll (%d)"
		% [first_roll, second_roll]
	)


func test_turn_order_contains_both_combatants_after_initialize() -> void:
	var enc = _make_encounter(99999)
	enc.initialize()
	var order: Array = enc.get_turn_order()
	assert_eq(order.size(), 2, "Turn order must contain both combatants")
	# Both combatants must have _initiative_roll set (not -1)
	assert_true(order[0].get("_initiative_roll", -1) >= 0,
		"First combatant must have a valid _initiative_roll")
	assert_true(order[1].get("_initiative_roll", -1) >= 0,
		"Second combatant must have a valid _initiative_roll")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: When skeleton.hp_current <= 0, get_outcome() == 'won'
# ══════════════════════════════════════════════════════════════════════════════

func test_outcome_won_when_skeleton_hp_reaches_zero() -> void:
	## Skeleton has hp=1 and ac=1 (always hit, always die on first attack).
	## Titus has hp=18 so he survives even if skeleton strikes first
	## (skeleton max damage = d6+2 = 8 < 18).
	var titus: Dictionary = _titus_dict()
	var skeleton_fragile: Dictionary = {
		"name": "Skeleton",
		"hp_current": 1,
		"ac": 1,
		"strength": 2,
		"dexterity": 1,
		"intuition": 1,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 6
		}
	}
	var enc = EncounterClass.new([titus], [skeleton_fragile], RNGClass.new(42))
	enc.run()
	assert_true(
		skeleton_fragile.get("hp_current", 1) <= 0,
		"Skeleton must be dead (hp <= 0) after this setup"
	)
	assert_eq(enc.get_outcome(), "won",
		"get_outcome() must be 'won' when all enemies hp <= 0")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5: When titus.hp_current <= 0, get_outcome() == 'lost'
# ══════════════════════════════════════════════════════════════════════════════

func test_outcome_lost_when_titus_hp_reaches_zero() -> void:
	## Titus has hp=1 and ac=1 (skeleton always hits, killing him in one blow).
	## Skeleton has hp=100 so Titus (max damage = 2d6+10 = 22 on crit, but ac=20
	## so Titus can rarely hit) cannot kill the skeleton before being killed.
	## Regardless of initiative order: once skeleton attacks titus (ac=1, always
	## hit, damage >= 6), titus dies.
	var titus_fragile: Dictionary = {
		"name": "Titus",
		"hp_current": 1,
		"ac": 1,
		"strength": 5,
		"dexterity": 2,
		"intuition": 2,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 6
		}
	}
	var skeleton_strong: Dictionary = {
		"name": "Skeleton",
		"hp_current": 100,
		"ac": 20,
		"strength": 5,
		"dexterity": 5,
		"intuition": 5,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 6
		}
	}
	var enc = EncounterClass.new([titus_fragile], [skeleton_strong], RNGClass.new(42))
	enc.run()
	assert_true(
		titus_fragile.get("hp_current", 1) <= 0,
		"Titus must be dead (hp <= 0) after this setup"
	)
	assert_eq(enc.get_outcome(), "lost",
		"get_outcome() must be 'lost' when all party hp <= 0")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 6: _round_history contains entries with required keys
# ══════════════════════════════════════════════════════════════════════════════

func test_round_history_non_empty_after_run() -> void:
	var enc = _make_encounter(99999)
	enc.run()
	assert_true(
		enc.get_round_history().size() >= 1,
		"get_round_history() must have at least 1 entry after run()"
	)


func test_round_history_first_entry_has_all_required_keys() -> void:
	var enc = _make_encounter(99999)
	enc.run()
	var history: Array = enc.get_round_history()
	if history.is_empty():
		fail_test("round_history is empty — cannot check entry keys")
		return
	var entry: Dictionary = history[0]
	for key in ["attacker", "action", "target", "roll", "damage_final"]:
		assert_true(
			entry.has(key),
			"round_history[0] must contain key '%s'; got keys: %s" % [key, str(entry.keys())]
		)


func test_round_history_action_is_strike() -> void:
	var enc = _make_encounter(99999)
	enc.run()
	var history: Array = enc.get_round_history()
	if history.is_empty():
		fail_test("round_history is empty")
		return
	assert_eq(history[0].get("action", ""), "Strike",
		"round_history[0].action must be 'Strike'")


func test_round_history_attacker_and_target_are_dicts() -> void:
	var enc = _make_encounter(99999)
	enc.run()
	var history: Array = enc.get_round_history()
	if history.is_empty():
		fail_test("round_history is empty")
		return
	var entry: Dictionary = history[0]
	assert_true(
		entry.get("attacker") is Dictionary,
		"round_history[0].attacker must be a Dictionary"
	)
	assert_true(
		entry.get("target") is Dictionary,
		"round_history[0].target must be a Dictionary"
	)


func test_round_history_damage_final_is_int() -> void:
	var enc = _make_encounter(99999)
	enc.run()
	var history: Array = enc.get_round_history()
	if history.is_empty():
		fail_test("round_history is empty")
		return
	assert_true(
		entry_damage_final_is_non_negative(history[0]),
		"round_history[0].damage_final must be >= 0"
	)


func entry_damage_final_is_non_negative(entry: Dictionary) -> bool:
	var df = entry.get("damage_final", -1)
	return df is int and df >= 0


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 7: encounter.gd does not contain 'extends Node' or 'extends Control'
#              (CI linter step 1 — ADR-001 domain purity)
# ══════════════════════════════════════════════════════════════════════════════

func test_encounter_gd_does_not_extend_node() -> void:
	var file := FileAccess.open("res://core/combat/encounter.gd", FileAccess.READ)
	assert_not_null(file, "core/combat/encounter.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"encounter.gd must not contain 'extends Node' — ADR-001 domain purity"
	)


func test_encounter_gd_does_not_extend_control() -> void:
	var file := FileAccess.open("res://core/combat/encounter.gd", FileAccess.READ)
	assert_not_null(file, "core/combat/encounter.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Control"),
		"encounter.gd must not contain 'extends Control' — ADR-001 domain purity"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 8: No direct randf/randi/RandomNumberGenerator.new() in core/combat/
#              (CI linter step 3 — ADR-002 RNG injection)
# ══════════════════════════════════════════════════════════════════════════════

func test_no_direct_rng_calls_in_core_combat() -> void:
	var dir := DirAccess.open("res://core/combat")
	if dir == null:
		fail_test("res://core/combat directory must exist")
		return
	var violations: Array = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.ends_with(".gd") and entry != "rng.gd":
			var full_path: String = "res://core/combat/" + entry
			var f := FileAccess.open(full_path, FileAccess.READ)
			if f != null:
				var content: String = f.get_as_text()
				f.close()
				if content.contains("randf(") or content.contains("randi(") \
						or content.contains("RandomNumberGenerator.new()"):
					violations.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
	assert_eq(
		violations.size(), 0,
		"ADR-002: core/combat/ must not contain direct RNG calls (excluding rng.gd):\n%s"
		% "\n".join(violations)
	)


# ══════════════════════════════════════════════════════════════════════════════
# Additional: outcome is immutable once set (idempotent get_outcome())
# ══════════════════════════════════════════════════════════════════════════════

func test_outcome_is_non_empty_string_after_run() -> void:
	var enc = _make_encounter(99999)
	enc.run()
	assert_true(
		enc.get_outcome() != "",
		"get_outcome() must return non-empty string after run() completes"
	)


func test_get_round_count_returns_int() -> void:
	var enc = _make_encounter(99999)
	enc.run()
	assert_true(
		enc.get_round_count() is int,
		"get_round_count() must return an int"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Determinism: same seed produces same outcome
# ══════════════════════════════════════════════════════════════════════════════

func test_same_seed_produces_same_outcome() -> void:
	var enc_a = _make_encounter(99999)
	var enc_b = _make_encounter(99999)
	enc_a.run()
	enc_b.run()
	assert_eq(
		enc_a.get_outcome(), enc_b.get_outcome(),
		"Same seed must produce identical outcome (determinism)"
	)


func test_same_seed_produces_same_round_count() -> void:
	var enc_a = _make_encounter(99999)
	var enc_b = _make_encounter(99999)
	enc_a.run()
	enc_b.run()
	assert_eq(
		enc_a.get_round_count(), enc_b.get_round_count(),
		"Same seed must produce identical round_count (determinism)"
	)
