extends GutTest
## tests/unit/combat/test_hex_scorer.gd
##
## GUT unit test suite for FEAT-004 (US-004 / FR-011 / ADR-005): the
## DOMAIN-layer core/combat/hex_scorer.gd pure scoring utility.
##
## Verifies (this feature's test_criteria):
##   1. score_hex(hex, actor, context) returns 0.0 for any input given no
##      cover/terrain systems wired (typical inputs, null hex/actor,
##      empty/missing context keys).
##   2. No push_error/exception raised for typical actor/context inputs —
##      calling score_hex() (and both hooks) for a range of shapes never
##      crashes/halts the test.
##   3. cover_bonus_hook() and terrain_bonus_hook() are individually
##      verified to contribute exactly 0.0 to the total (called directly,
##      not just observed indirectly via score_hex()'s sum).
##
## Satisfies: FEAT-004, US-004, FR-011.

const HexScorerClass = preload("res://core/combat/hex_scorer.gd")
const HexCoordClass  = preload("res://core/geometry/hex_coord.gd")


func _combatant(name: String, hex_coord, hp: int = 10) -> Dictionary:
	return {"name": name, "hp_current": hp, "hex_coord": hex_coord}


func _world_context(party: Array = [], enemies: Array = []) -> Dictionary:
	return {"party": party, "enemies": enemies, "action_economy": null}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: score_hex() returns 0.0 for any input (no cover/terrain wired)
# ══════════════════════════════════════════════════════════════════════════

func test_score_hex_returns_zero_for_typical_inputs() -> void:
	var hex := HexCoordClass.new(2, -1)
	var actor: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))
	var context: Dictionary = _world_context([_combatant("Titus", HexCoordClass.new(1, 0))])

	var score: float = HexScorerClass.score_hex(hex, actor, context)

	assert_eq(score, 0.0, "score_hex() must return 0.0 with no cover/terrain systems wired")


func test_score_hex_returns_zero_with_empty_context() -> void:
	var hex := HexCoordClass.new(0, 0)
	var actor: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))

	var score: float = HexScorerClass.score_hex(hex, actor, {})

	assert_eq(score, 0.0, "score_hex() must return 0.0 given an empty/bare context Dictionary")


func test_score_hex_returns_zero_with_all_null_inputs() -> void:
	var score: float = HexScorerClass.score_hex(null, null, null)

	assert_eq(score, 0.0, "score_hex() must return 0.0 (not crash) given entirely null inputs")


func test_score_hex_returns_zero_for_multiple_distinct_hexes() -> void:
	var actor: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))
	var context: Dictionary = _world_context()

	for coords in [[0, 0], [3, -2], [-4, 5], [10, 10]]:
		var hex := HexCoordClass.new(coords[0], coords[1])
		var score: float = HexScorerClass.score_hex(hex, actor, context)
		assert_eq(score, 0.0, "score_hex() must return 0.0 for hex (%d, %d)" % [coords[0], coords[1]])


func test_score_hex_return_type_is_float() -> void:
	var hex := HexCoordClass.new(1, 1)
	var actor: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))

	var score = HexScorerClass.score_hex(hex, actor, _world_context())

	assert_true(typeof(score) == TYPE_FLOAT, "score_hex() must return a float")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: no push_error/exception for typical actor/context inputs
# ══════════════════════════════════════════════════════════════════════════

func test_score_hex_does_not_raise_for_combatant_dictionary_actor() -> void:
	var hex := HexCoordClass.new(0, 0)
	var actor: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))
	var context: Dictionary = _world_context([_combatant("Titus", HexCoordClass.new(1, 0))], [actor])

	# Reachability of a well-formed float result is itself the proof this
	# call did not raise/crash/halt execution.
	var score: float = HexScorerClass.score_hex(hex, actor, context)
	assert_not_null(score, "score_hex() must return a value (not crash) for a typical Dictionary actor/context")


func test_score_hex_does_not_raise_for_missing_context_keys() -> void:
	var hex := HexCoordClass.new(0, 0)
	var actor: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))

	# A context missing the party/enemies/action_economy keys entirely must
	# still be handled gracefully -- score_hex() never dereferences context
	# in this feature's zero-weighted implementation.
	var score: float = HexScorerClass.score_hex(hex, actor, {"unexpected_key": "value"})
	assert_eq(score, 0.0, "score_hex() must tolerate a context Dictionary missing the usual party/enemies/action_economy keys")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: cover_bonus_hook() / terrain_bonus_hook() individually
# contribute exactly 0.0
# ══════════════════════════════════════════════════════════════════════════

func test_cover_bonus_hook_returns_zero_directly() -> void:
	var hex := HexCoordClass.new(2, -1)
	var actor: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))
	var context: Dictionary = _world_context()

	var bonus: float = HexScorerClass.cover_bonus_hook(hex, actor, context)

	assert_eq(bonus, 0.0, "cover_bonus_hook() must contribute exactly 0.0 (no cover system wired -- NFR-005)")


func test_terrain_bonus_hook_returns_zero_directly() -> void:
	var hex := HexCoordClass.new(2, -1)
	var actor: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))
	var context: Dictionary = _world_context()

	var bonus: float = HexScorerClass.terrain_bonus_hook(hex, actor, context)

	assert_eq(bonus, 0.0, "terrain_bonus_hook() must contribute exactly 0.0 (no terrain system wired -- NFR-005)")


func test_hooks_sum_matches_score_hex_total() -> void:
	var hex := HexCoordClass.new(4, -3)
	var actor: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))
	var context: Dictionary = _world_context([_combatant("Titus", HexCoordClass.new(1, 0))])

	var cover: float = HexScorerClass.cover_bonus_hook(hex, actor, context)
	var terrain: float = HexScorerClass.terrain_bonus_hook(hex, actor, context)
	var total: float = HexScorerClass.score_hex(hex, actor, context)

	assert_eq(cover, 0.0, "cover_bonus_hook() individual contribution must be 0.0")
	assert_eq(terrain, 0.0, "terrain_bonus_hook() individual contribution must be 0.0")
	assert_eq(total, cover + terrain, "score_hex()'s total must equal the sum of its individually-verified hook contributions")


func test_hooks_return_zero_for_null_inputs() -> void:
	assert_eq(HexScorerClass.cover_bonus_hook(null, null, null), 0.0, "cover_bonus_hook() must return 0.0 (not crash) given null inputs")
	assert_eq(HexScorerClass.terrain_bonus_hook(null, null, null), 0.0, "terrain_bonus_hook() must return 0.0 (not crash) given null inputs")
