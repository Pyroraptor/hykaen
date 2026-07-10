extends GutTest
## tests/unit/test_ai.gd
##
## GUT unit test suite for core/combat/ai.gd — Enemy AI Module (FEAT-089 / FR-012).
##
## Test criteria covered (FEAT-089):
##   1. decide_action(enemy_dict, targets_array) returns a dict with keys
##      'action_type' and 'target'
##   2. decide_action() for an enemy with hp > 0 and at least one valid target
##      returns action_type == 'Strike'
##   3. core/combat/ai.gd contains no 'extends Node' or 'extends Control'
##      (domain-purity CI linter)
##   4. decide_action() with no living targets returns action_type == ''
##   5. decide_action() with a dead target and a living target picks the living one

const AIClass = preload("res://core/combat/ai.gd")


# ── Fixture helpers ───────────────────────────────────────────────────────────

func _make_enemy() -> Dictionary:
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


func _make_target(name: String, hp: int) -> Dictionary:
	return {
		"name": name,
		"hp_current": hp,
		"ac": 14,
		"strength": 5
	}


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: decide_action() returns a Dictionary with keys 'action_type'
#              and 'target'
# ══════════════════════════════════════════════════════════════════════════════

func test_decide_action_returns_dict_with_action_type_key() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _make_enemy()
	var targets: Array = [_make_target("Titus", 18)]

	var result: Dictionary = await ai.decide_action(combatant, targets)

	assert_true(
		result is Dictionary,
		"decide_action() must return a Dictionary"
	)
	assert_true(
		result.has("action_type"),
		"decide_action() result must contain key 'action_type'; got keys: %s" % str(result.keys())
	)


func test_decide_action_returns_dict_with_target_key() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _make_enemy()
	var targets: Array = [_make_target("Titus", 18)]

	var result: Dictionary = await ai.decide_action(combatant, targets)

	assert_true(
		result.has("target"),
		"decide_action() result must contain key 'target'; got keys: %s" % str(result.keys())
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: decide_action() for an enemy with hp > 0 and at least one valid
#              target returns action_type == 'Strike'
# ══════════════════════════════════════════════════════════════════════════════

func test_decide_action_returns_strike_for_living_enemy_with_valid_target() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _make_enemy()
	var targets: Array = [_make_target("Titus", 18)]

	var result: Dictionary = await ai.decide_action(combatant, targets)

	assert_eq(
		result.get("action_type", ""),
		"Strike",
		"decide_action() must return action_type == 'Strike' for a living enemy with a valid target"
	)


func test_decide_action_target_matches_first_living_target() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _make_enemy()
	var titus: Dictionary = _make_target("Titus", 18)
	var targets: Array = [titus]

	var result: Dictionary = await ai.decide_action(combatant, targets)

	var chosen: Dictionary = result.get("target", {})
	assert_eq(
		chosen.get("name", ""),
		"Titus",
		"decide_action() must choose 'Titus' as the first valid target"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: Domain purity — ai.gd must not extend Node or Control
# ══════════════════════════════════════════════════════════════════════════════

func test_ai_gd_does_not_extend_node() -> void:
	var file := FileAccess.open("res://core/combat/ai.gd", FileAccess.READ)
	assert_not_null(file, "core/combat/ai.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"ai.gd must not contain 'extends Node' — domain purity (ADR-001)"
	)


func test_ai_gd_does_not_extend_control() -> void:
	var file := FileAccess.open("res://core/combat/ai.gd", FileAccess.READ)
	assert_not_null(file, "core/combat/ai.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Control"),
		"ai.gd must not contain 'extends Control' — domain purity (ADR-001)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: decide_action() with no living targets returns action_type == ''
# ══════════════════════════════════════════════════════════════════════════════

func test_decide_action_no_living_targets_returns_empty_action_type() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _make_enemy()
	var dead_target: Dictionary = _make_target("Corpse", 0)
	var targets: Array = [dead_target]

	var result: Dictionary = await ai.decide_action(combatant, targets)

	assert_eq(
		result.get("action_type", "MISSING"),
		"",
		"decide_action() with no living targets must return action_type == ''"
	)


func test_decide_action_empty_targets_array_returns_empty_action_type() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _make_enemy()

	var result: Dictionary = await ai.decide_action(combatant, [])

	assert_eq(
		result.get("action_type", "MISSING"),
		"",
		"decide_action() with an empty targets array must return action_type == ''"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5: decide_action() with dead and living targets picks the living one
# ══════════════════════════════════════════════════════════════════════════════

func test_decide_action_skips_dead_targets() -> void:
	var ai = AIClass.new()
	var combatant: Dictionary = _make_enemy()
	var dead_target: Dictionary = _make_target("Corpse", 0)
	var living_target: Dictionary = _make_target("Titus", 18)
	var targets: Array = [dead_target, living_target]

	var result: Dictionary = await ai.decide_action(combatant, targets)

	assert_eq(
		result.get("action_type", ""),
		"Strike",
		"decide_action() must choose Strike against the living target"
	)
	var chosen: Dictionary = result.get("target", {})
	assert_eq(
		chosen.get("name", ""),
		"Titus",
		"decide_action() must skip dead targets and pick the living one"
	)
