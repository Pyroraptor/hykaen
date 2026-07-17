extends GutTest
## tests/unit/core/domain/test_opportunistic_strike_eligibility.gd
##
## GUT test suite for iteration K FEAT-006 (US-006): core/domain/
## opportunistic_strike_eligibility.gd's OpportunisticStrikeEligibility — the
## domain-pure "is this reactor eligible to be offered an OpportunisticStrike
## window against this Stride" predicate.
##
## Rule under test (design notes, "Opportunistic Strike eligibility"):
##   eligible = adjacent (to the mover's START hex) && hostile && !Spent &&
##              melee reach
##
## Verifies (this feature's test_criteria: "Unit test: OpportunisticStrikeEligibility
## correctly filters non-adjacent, non-hostile, Spent, and non-melee-reach
## candidates"):
##   1. A reactor that is adjacent, hostile, not Spent, and melee-armed is
##      eligible.
##   2. A non-adjacent reactor is filtered out.
##   3. A non-hostile (same-faction) reactor is filtered out.
##   4. A Spent reactor is filtered out.
##   5. A ranged-weapon reactor (no melee reach) is filtered out.
##   6. Static/code-inspection: the file is domain-pure (no engine imports,
##      no RNG, extends RefCounted only).

const OpportunisticStrikeEligibilityClass = preload("res://core/domain/opportunistic_strike_eligibility.gd")
const OPPORTUNISTIC_STRIKE_ELIGIBILITY_PATH: String = "res://core/domain/opportunistic_strike_eligibility.gd"
const HexCoord = preload("res://core/geometry/hex_coord.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")


## _mover() -- an enemy (Skeleton) about to Stride, starting at (0, 0).
func _mover():
	return CombatantClass.from_dict({
		"name":       "Skeleton",
		"hex_coord":  HexCoord.new(0, 0),
		"_is_enemy":  true,
		"weapon":     {"damage_die": 6},
	})


## _melee_reactor(hex_coord) -- a hostile (player) melee-armed reactor.
func _melee_reactor(hex_coord):
	return CombatantClass.from_dict({
		"name":       "Titus",
		"hex_coord":  hex_coord,
		"_is_enemy":  false,
		"weapon":     {"damage_die": 6},
	})


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: adjacent + hostile + not Spent + melee reach -> eligible
# ══════════════════════════════════════════════════════════════════════════

func test_eligible_when_adjacent_hostile_not_spent_and_melee_reach() -> void:
	var mover = _mover()
	var reactor = _melee_reactor(HexCoord.new(1, 0))  # a neighbor of (0,0)

	assert_true(
		OpportunisticStrikeEligibilityClass.eligible(reactor, mover, mover["hex_coord"], false),
		"an adjacent, hostile, not-Spent, melee-armed reactor must be eligible"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: non-adjacent reactor filtered out
# ══════════════════════════════════════════════════════════════════════════

func test_not_eligible_when_not_adjacent() -> void:
	var mover = _mover()
	var reactor = _melee_reactor(HexCoord.new(5, 5))  # far away

	assert_false(
		OpportunisticStrikeEligibilityClass.eligible(reactor, mover, mover["hex_coord"], false),
		"a non-adjacent reactor must never be eligible"
	)


func test_not_eligible_when_reactor_has_no_hex_coord() -> void:
	var mover = _mover()
	var reactor = CombatantClass.from_dict({"name": "Titus", "_is_enemy": false, "weapon": {"damage_die": 6}})

	assert_false(
		OpportunisticStrikeEligibilityClass.eligible(reactor, mover, mover["hex_coord"], false),
		"a reactor with no positional data can never be judged adjacent"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: non-hostile (same faction) reactor filtered out
# ══════════════════════════════════════════════════════════════════════════

func test_not_eligible_when_same_faction_as_mover() -> void:
	var mover = _mover()
	var ally = CombatantClass.from_dict({
		"name":       "Other Skeleton",
		"hex_coord":  HexCoord.new(1, 0),
		"_is_enemy":  true,  # SAME faction as mover
		"weapon":     {"damage_die": 6},
	})

	assert_false(
		OpportunisticStrikeEligibilityClass.eligible(ally, mover, mover["hex_coord"], false),
		"a same-faction (non-hostile) candidate must never be eligible"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: Spent reactor filtered out
# ══════════════════════════════════════════════════════════════════════════

func test_not_eligible_when_reactor_spent() -> void:
	var mover = _mover()
	var reactor = _melee_reactor(HexCoord.new(1, 0))

	assert_false(
		OpportunisticStrikeEligibilityClass.eligible(reactor, mover, mover["hex_coord"], true),
		"a Spent reactor has no reaction left to spend, and must never be eligible"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: ranged-weapon (no melee reach) reactor filtered out
# ══════════════════════════════════════════════════════════════════════════

func test_not_eligible_when_reactor_has_no_melee_reach() -> void:
	var mover = _mover()
	var reactor = CombatantClass.from_dict({
		"name":       "Archer",
		"hex_coord":  HexCoord.new(1, 0),
		"_is_enemy":  false,
		"weapon":     {"damage_die": 6, "range_hexes": 6},
	})

	assert_false(
		OpportunisticStrikeEligibilityClass.eligible(reactor, mover, mover["hex_coord"], false),
		"a ranged-weapon reactor has no opportunistic MELEE strike to make"
	)


func test_eligible_for_every_one_of_the_six_flat_top_neighbors() -> void:
	var mover = _mover()
	var mover_hex = mover["hex_coord"]
	for neighbor in _six_neighbors_of(mover_hex):
		var reactor = _melee_reactor(neighbor)
		assert_true(
			OpportunisticStrikeEligibilityClass.eligible(reactor, mover, mover_hex, false),
			"every one of the mover's 6 flat-top axial neighbors must count as adjacent"
		)


func _six_neighbors_of(origin) -> Array:
	# Mirrors core/geometry/hex_math.gd's own flat-top axial neighbor offsets
	# without importing it directly, so this suite independently proves the
	# domain function's adjacency behavior against a hand-authored fixture
	# set rather than reusing the SAME table under test.
	var offsets: Array = [
		HexCoord.new(1, 0), HexCoord.new(1, -1), HexCoord.new(0, -1),
		HexCoord.new(-1, 0), HexCoord.new(-1, 1), HexCoord.new(0, 1),
	]
	var result: Array = []
	for offset in offsets:
		result.append(HexCoord.new(origin.q + offset.q, origin.r + offset.r))
	return result


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6: domain purity — no engine imports, RefCounted only
# ══════════════════════════════════════════════════════════════════════════

func test_source_is_domain_pure() -> void:
	var f := FileAccess.open(OPPORTUNISTIC_STRIKE_ELIGIBILITY_PATH, FileAccess.READ)
	assert_not_null(f, "opportunistic_strike_eligibility.gd must be readable")
	if f == null:
		return
	var content: String = f.get_as_text()
	f.close()

	assert_true(content.contains("extends RefCounted"),
		"OpportunisticStrikeEligibility must extend RefCounted (domain purity, ADR-001)")
	assert_false(content.contains("extends Node"), "must not extend Node (ADR-001)")
	assert_false(content.contains("extends Control"), "must not extend Control (ADR-001)")
	assert_false(content.contains("RandomNumberGenerator"),
		"OpportunisticStrikeEligibility must consume zero RNG — it is a pure comparison")
	assert_false(content.contains("preload(\"res://core/rules/action_economy.gd\")"),
		"OpportunisticStrikeEligibility must stay free of an ActionEconomy import — the caller resolves 'spent' and passes a plain bool")
