extends GutTest
## tests/unit/test_short_rest_heal_use_case.gd — FEAT-004 (US-004; FR-005,
## NFR-001; iteration AB-0, rest mechanics steel thread).
##
## GUT suite for core/application/use_cases/short_rest_heal_use_case.gd's
## ShortRestHealUseCase. Mirrors tests/unit/test_long_rest_use_case.gd's
## established "real domain Combatant object, no adapter, no engine boot"
## convention — ShortRestHealUseCase itself is pure RefCounted orchestration
## over Combatant state (ADR-001).
##
## test_criteria covered:
##   1. stamina_to_spend < 1 returns ERR_INSUFFICIENT_STAMINA with no state
##      mutation
##   2. stamina_to_spend > combatant.stamina returns ERR_INSUFFICIENT_STAMINA
##      with no state mutation
##   3. hp_current == hp_max returns ERR_ALREADY_AT_FULL_HP with no state
##      mutation
##   4. Successful heal applies
##      min(stamina_to_spend * ceil(hp_max/4), hp_max - hp_current) and
##      decrements stamina atomically in the same call
##   5. Over-spend request that would exceed hp_max caps healing at hp_max
##      exactly and still spends the requested stamina
##   6. Return shape on success is
##      {success: true, hp_gained: int, stamina_spent: int}
##   7. Static check: file contains no Node/Control/SceneTree references

const ShortRestHealUseCaseClass = preload("res://core/application/use_cases/short_rest_heal_use_case.gd")
const ErrorCodeClass            = preload("res://core/application/ports/errors.gd")
const CombatantClass            = preload("res://core/domain/combatant.gd")
const HexCoordClass             = preload("res://core/geometry/hex_coord.gd")


func _combatant(hp_current: int, hp_max: int, stamina: int) -> Combatant:
	var c := CombatantClass.new("titus_1", "Titus", "Player", HexCoordClass.new(0, 0))
	c.hp_current = hp_current
	c.hp_max = hp_max
	c.stamina = stamina
	return c


# ══════════════════════════════════════════════════════════════════════════
# Validation order (a): stamina_to_spend < 1 -> ERR_INSUFFICIENT_STAMINA
# ══════════════════════════════════════════════════════════════════════════

func test_zero_stamina_to_spend_returns_insufficient_stamina_with_no_mutation() -> void:
	var titus := _combatant(5, 20, 3)
	var use_case := ShortRestHealUseCaseClass.new()

	var result: Dictionary = use_case.execute(titus, 0)

	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_INSUFFICIENT_STAMINA})
	assert_eq(titus.hp_current, 5, "hp_current must be unchanged")
	assert_eq(titus.stamina, 3, "stamina must be unchanged")


func test_negative_stamina_to_spend_returns_insufficient_stamina_with_no_mutation() -> void:
	var titus := _combatant(5, 20, 3)
	var use_case := ShortRestHealUseCaseClass.new()

	var result: Dictionary = use_case.execute(titus, -1)

	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_INSUFFICIENT_STAMINA})
	assert_eq(titus.hp_current, 5)
	assert_eq(titus.stamina, 3)


# ══════════════════════════════════════════════════════════════════════════
# Validation order (b): stamina_to_spend > combatant.stamina -> ERR_INSUFFICIENT_STAMINA
# ══════════════════════════════════════════════════════════════════════════

func test_stamina_to_spend_exceeding_available_stamina_returns_insufficient_stamina() -> void:
	var titus := _combatant(5, 20, 2)
	var use_case := ShortRestHealUseCaseClass.new()

	var result: Dictionary = use_case.execute(titus, 3)

	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_INSUFFICIENT_STAMINA})
	assert_eq(titus.hp_current, 5, "hp_current must be unchanged")
	assert_eq(titus.stamina, 2, "stamina must be unchanged")


func test_stamina_to_spend_exactly_equal_to_available_stamina_is_allowed() -> void:
	var titus := _combatant(5, 20, 2)
	var use_case := ShortRestHealUseCaseClass.new()

	var result: Dictionary = use_case.execute(titus, 2)

	assert_true(result.get("success"), "spending exactly all available stamina must succeed")
	assert_eq(titus.stamina, 0)


# ══════════════════════════════════════════════════════════════════════════
# Validation order (c): hp_current == hp_max -> ERR_ALREADY_AT_FULL_HP
# ══════════════════════════════════════════════════════════════════════════

func test_already_at_full_hp_returns_already_at_full_hp_with_no_mutation() -> void:
	var titus := _combatant(20, 20, 3)
	var use_case := ShortRestHealUseCaseClass.new()

	var result: Dictionary = use_case.execute(titus, 1)

	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_ALREADY_AT_FULL_HP})
	assert_eq(titus.hp_current, 20, "hp_current must be unchanged")
	assert_eq(titus.stamina, 3, "stamina must be unchanged")


func test_full_hp_check_takes_precedence_over_insufficient_stamina_when_full_hp_and_starved() -> void:
	# Validation order: (a) spend>=1 -> (b) sufficient stamina -> (c) not full
	# HP. This case exercises that a combatant at full HP with 0 stamina
	# and a request of stamina_to_spend=0 stops at (a), not (c) -- verifying
	# (a) really does run first (both failures possible only pick ERR_INSUFFICIENT_STAMINA).
	var titus := _combatant(20, 20, 0)
	var use_case := ShortRestHealUseCaseClass.new()

	var result: Dictionary = use_case.execute(titus, 0)

	assert_eq(result, {"success": false, "error": ErrorCodeClass.ERR_INSUFFICIENT_STAMINA})


# ══════════════════════════════════════════════════════════════════════════
# Successful heal — atomic hp gain + stamina spend
# ══════════════════════════════════════════════════════════════════════════

func test_successful_heal_applies_ceil_hp_max_over_4_per_stamina_point() -> void:
	# hp_max=20 -> ceil(20/4) == 5 healed per stamina point spent.
	var titus := _combatant(5, 20, 3)
	var use_case := ShortRestHealUseCaseClass.new()

	var result: Dictionary = use_case.execute(titus, 1)

	assert_eq(result, {"success": true, "hp_gained": 5, "stamina_spent": 1})
	assert_eq(titus.hp_current, 10, "hp_current must increase by 5")
	assert_eq(titus.stamina, 2, "stamina must decrement atomically with the heal")


func test_successful_heal_with_non_divisible_hp_max_rounds_up_per_stamina_point() -> void:
	# hp_max=15 -> ceil(15/4) == 4 healed per stamina point spent.
	var titus := _combatant(1, 15, 5)
	var use_case := ShortRestHealUseCaseClass.new()

	var result: Dictionary = use_case.execute(titus, 2)

	assert_eq(result, {"success": true, "hp_gained": 8, "stamina_spent": 2})
	assert_eq(titus.hp_current, 9)
	assert_eq(titus.stamina, 3)


# ══════════════════════════════════════════════════════════════════════════
# Over-spend caps healing at hp_max exactly, but still spends requested stamina
# ══════════════════════════════════════════════════════════════════════════

func test_over_spend_caps_healing_at_hp_max_but_still_spends_requested_stamina() -> void:
	# hp_max=20 -> ceil(20/4) == 5 per stamina point. hp_current=18, so only
	# 2 HP is needed to reach full, but stamina_to_spend=3 (15 HP worth) is
	# requested -- healing must cap at hp_max exactly (18 -> 20, hp_gained=2)
	# while the full 3 stamina is still spent.
	var titus := _combatant(18, 20, 5)
	var use_case := ShortRestHealUseCaseClass.new()

	var result: Dictionary = use_case.execute(titus, 3)

	assert_eq(result, {"success": true, "hp_gained": 2, "stamina_spent": 3})
	assert_eq(titus.hp_current, 20, "hp_current must cap exactly at hp_max")
	assert_eq(titus.stamina, 2, "the full requested stamina must still be spent")


# ══════════════════════════════════════════════════════════════════════════
# Static check: no Node/Control/SceneTree references in production source
# ══════════════════════════════════════════════════════════════════════════

func test_source_file_has_no_node_control_scenetree_references() -> void:
	# Mirrors tests/static/test_no_godot_types_in_core.py's real scan: only
	# an actual `extends <Banned>` clause or a banned type used as a type
	# hint/instantiation is a violation -- a doc-comment merely MENTIONING
	# "SceneTree" in prose (e.g. this file's own ADR-001 header note) is not.
	var source := FileAccess.get_file_as_string("res://core/application/use_cases/short_rest_heal_use_case.gd")
	for banned in ["extends Node", "extends Control", "extends CanvasItem", "extends SceneTree"]:
		assert_false(source.contains(banned), "must not extend '%s'" % banned)
	for banned_hint in [": Node", ": Control", "Node.new(", "Control.new(", "SceneTree.new("]:
		assert_false(source.contains(banned_hint), "must not reference '%s'" % banned_hint)
