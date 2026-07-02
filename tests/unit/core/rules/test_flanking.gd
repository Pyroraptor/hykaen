extends GutTest
## tests/unit/core/rules/test_flanking.gd
##
## GUT test suite for FEAT-015 (US-015 / FR-016): core/rules/flanking.gd's
## Flanking.is_off_guard() / Flanking.off_guard_conditions() — a target is
## Off-Guard iff two OTHER combatants occupy directly-OPPOSITE adjacent
## hexes relative to it.
##
## Verifies (test_criteria):
##   1. Attacker + ally on directly-opposite adjacent hexes flags the target
##      Off-Guard (positive case).
##   2. Non-opposite / non-adjacent positions do NOT flag Off-Guard
##      (negative cases).
##   3. Off-Guard is a BLANKET condition, not flankers-only (verified here
##      as "the detector never reports/depends on flanker identity" and in
##      tests/unit/test_resolution.gd as "the +2 bonus applies to any
##      attacker, not only the flanking pair").
##   4. Flankers-only tightening is NOT implemented (blanket v0 only) — the
##      public API surface exposes only a single target-level bool/condition
##      list, never a per-attacker/flanker-pair query.

const FlankingClass  = preload("res://core/rules/flanking.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass  = preload("res://core/geometry/hex_coord.gd")

## The 6 flat-top axial neighbor offsets of HexCoord(0,0), in
## core/geometry/hex_math.gd's fixed _DIRECTIONS order. Index i and index
## i+3 are directly opposite each other (used throughout this suite to pick
## guaranteed-opposite / guaranteed-non-opposite neighbor pairs without
## depending on hex_math.gd's private constant directly).
const _NEIGHBOR_OFFSETS: Array = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]]


func _neighbor_hex(index: int) -> HexCoordClass:
	var offset: Array = _NEIGHBOR_OFFSETS[index]
	return HexCoordClass.new(offset[0], offset[1])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: attacker + ally on directly-opposite adjacent hexes flags the
# target Off-Guard (positive case).
# ══════════════════════════════════════════════════════════════════════════

func test_two_combatants_on_opposite_adjacent_hexes_flags_off_guard() -> void:
	var target := CombatantClass.new("t1", "Target", "Enemy", HexCoordClass.new(0, 0))
	var attacker := CombatantClass.new("a1", "Attacker", "Player", _neighbor_hex(0))
	var ally := CombatantClass.new("a2", "Ally", "Player", _neighbor_hex(3))  # opposite of index 0

	assert_true(
		FlankingClass.is_off_guard(target, [attacker, ally]),
		"an attacker and an ally on directly-opposite adjacent hexes must flag the target Off-Guard"
	)


func test_off_guard_holds_for_every_opposite_neighbor_pair() -> void:
	# Every one of the 3 opposite-pair axes (0&3, 1&4, 2&5) must trigger
	# Off-Guard identically -- the rule is not special-cased to a single axis.
	for i in range(3):
		var target := CombatantClass.new("t1", "Target", "Enemy", HexCoordClass.new(0, 0))
		var flanker_a := CombatantClass.new("a1", "A", "Player", _neighbor_hex(i))
		var flanker_b := CombatantClass.new("a2", "B", "Player", _neighbor_hex(i + 3))

		assert_true(
			FlankingClass.is_off_guard(target, [flanker_a, flanker_b]),
			"opposite-neighbor axis (%d, %d) must flag Off-Guard" % [i, i + 3]
		)


func test_off_guard_condition_added_via_dictionary_shaped_combatants() -> void:
	# The interactive combat pipeline represents combatants as Dictionaries
	# carrying a "hex_coord" key -- Flanking must drive that SAME shape, not
	# only Combatant instances (mirrors core/rules/movement.gd's convention).
	var target: Dictionary = {"name": "Target", "hex_coord": HexCoordClass.new(0, 0)}
	var attacker: Dictionary = {"name": "Attacker", "hex_coord": _neighbor_hex(1)}
	var ally: Dictionary = {"name": "Ally", "hex_coord": _neighbor_hex(4)}

	assert_true(FlankingClass.is_off_guard(target, [attacker, ally]))


func test_off_guard_conditions_returns_off_guard_label_when_flanked() -> void:
	var target := CombatantClass.new("t1", "Target", "Enemy", HexCoordClass.new(0, 0))
	var attacker := CombatantClass.new("a1", "Attacker", "Player", _neighbor_hex(0))
	var ally := CombatantClass.new("a2", "Ally", "Player", _neighbor_hex(3))

	assert_eq(
		FlankingClass.off_guard_conditions(target, [attacker, ally]),
		[FlankingClass.OFF_GUARD_CONDITION]
	)


func test_third_unrelated_combatant_does_not_prevent_off_guard() -> void:
	# A bystander elsewhere on the field must not interfere with a genuine
	# opposite-adjacent flanking pair.
	var target := CombatantClass.new("t1", "Target", "Enemy", HexCoordClass.new(0, 0))
	var attacker := CombatantClass.new("a1", "Attacker", "Player", _neighbor_hex(0))
	var ally := CombatantClass.new("a2", "Ally", "Player", _neighbor_hex(3))
	var bystander := CombatantClass.new("b1", "Bystander", "Enemy", HexCoordClass.new(5, 5))

	assert_true(FlankingClass.is_off_guard(target, [attacker, ally, bystander]))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: non-opposite / non-adjacent positions do NOT flag Off-Guard
# (negative cases).
# ══════════════════════════════════════════════════════════════════════════

func test_two_adjacent_but_non_opposite_combatants_do_not_flag_off_guard() -> void:
	var target := CombatantClass.new("t1", "Target", "Enemy", HexCoordClass.new(0, 0))
	var flanker_a := CombatantClass.new("a1", "A", "Player", _neighbor_hex(0))
	var flanker_b := CombatantClass.new("a2", "B", "Player", _neighbor_hex(1))  # adjacent to index 0, NOT opposite

	assert_false(
		FlankingClass.is_off_guard(target, [flanker_a, flanker_b]),
		"two adjacent-but-not-opposite neighbors must NOT flag Off-Guard"
	)


func test_single_adjacent_combatant_does_not_flag_off_guard() -> void:
	var target := CombatantClass.new("t1", "Target", "Enemy", HexCoordClass.new(0, 0))
	var attacker := CombatantClass.new("a1", "Attacker", "Player", _neighbor_hex(0))

	assert_false(
		FlankingClass.is_off_guard(target, [attacker]),
		"a single adjacent combatant with no opposite partner must NOT flag Off-Guard"
	)


func test_non_adjacent_combatants_do_not_flag_off_guard() -> void:
	var target := CombatantClass.new("t1", "Target", "Enemy", HexCoordClass.new(0, 0))
	var far_a := CombatantClass.new("a1", "A", "Player", HexCoordClass.new(5, 5))
	var far_b := CombatantClass.new("a2", "B", "Player", HexCoordClass.new(-5, -5))

	assert_false(FlankingClass.is_off_guard(target, [far_a, far_b]))


func test_one_adjacent_one_far_does_not_flag_off_guard() -> void:
	var target := CombatantClass.new("t1", "Target", "Enemy", HexCoordClass.new(0, 0))
	var attacker := CombatantClass.new("a1", "Attacker", "Player", _neighbor_hex(0))
	var far_ally := CombatantClass.new("a2", "Ally", "Player", HexCoordClass.new(9, 9))

	assert_false(
		FlankingClass.is_off_guard(target, [attacker, far_ally]),
		"an adjacent flanker with a non-adjacent 'ally' must NOT flag Off-Guard"
	)


func test_empty_other_combatants_does_not_flag_off_guard() -> void:
	var target := CombatantClass.new("t1", "Target", "Enemy", HexCoordClass.new(0, 0))
	assert_false(FlankingClass.is_off_guard(target, []))


func test_off_guard_conditions_returns_empty_array_when_not_flanked() -> void:
	var target := CombatantClass.new("t1", "Target", "Enemy", HexCoordClass.new(0, 0))
	var attacker := CombatantClass.new("a1", "Attacker", "Player", _neighbor_hex(0))

	assert_eq(FlankingClass.off_guard_conditions(target, [attacker]), [])


func test_target_with_no_positional_data_is_never_off_guard() -> void:
	var target: Dictionary = {"name": "Target"}  # no "hex_coord" key at all
	var attacker: Dictionary = {"name": "Attacker", "hex_coord": HexCoordClass.new(1, 0)}
	var ally: Dictionary = {"name": "Ally", "hex_coord": HexCoordClass.new(-1, 0)}

	assert_false(FlankingClass.is_off_guard(target, [attacker, ally]))


func test_flanker_with_no_positional_data_is_skipped_not_crashed_on() -> void:
	var target := CombatantClass.new("t1", "Target", "Enemy", HexCoordClass.new(0, 0))
	var attacker := CombatantClass.new("a1", "Attacker", "Player", _neighbor_hex(0))
	var no_position: Dictionary = {"name": "Ghost"}  # no "hex_coord" key

	assert_false(FlankingClass.is_off_guard(target, [attacker, no_position]))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3/4: blanket v0, not flankers-only — the public API exposes only
# a single target-level result (no per-attacker/flanker-identity query).
# ══════════════════════════════════════════════════════════════════════════

func test_public_api_exposes_no_flanker_identity_or_pair_query() -> void:
	# Source-inspection guard: flanking.gd must not grow a per-attacker
	# "is this specific combatant one of the flankers" API -- that would be
	# the (explicitly out-of-scope) flankers-only tightening rather than the
	# v0 blanket rule. Only is_off_guard()/off_guard_conditions() (target ->
	# bool/Array) may exist as public entry points.
	var file := FileAccess.open("res://core/rules/flanking.gd", FileAccess.READ)
	assert_not_null(file, "core/rules/flanking.gd must be readable to verify its source")
	if file == null:
		return
	var source: String = file.get_as_text()
	file.close()

	assert_eq(source.findn("is_flanker"), -1, "flanking.gd must not expose a per-attacker flanker-identity query")
	assert_eq(source.findn("flanking_pair"), -1, "flanking.gd must not expose a flanker-pair query (blanket v0 only)")


func test_off_guard_bonus_constant_is_two() -> void:
	assert_eq(FlankingClass.OFF_GUARD_BONUS, 2, "US-015/FR-016: Off-Guard grants a blanket +2 to all attacks")


func test_off_guard_condition_constant_label() -> void:
	assert_eq(FlankingClass.OFF_GUARD_CONDITION, "Off-Guard")
