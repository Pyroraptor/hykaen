extends GutTest
## tests/unit/test_weapon_resource_data.gd
##
## GUT unit test suite for FEAT-001 (US-005 / FR-006): Populate weapon
## block_value and parry_bonus data.
##
## Data-layer foundation for the steel thread's reaction mechanics
## (docs/iterations/iteration-H-round-loop-fixes-and-reactions-first-pass.org,
## section B-1). Confirms the v0 CONFIRMED block/parry values are present on
## the three weapon fixtures used by the steel thread, and that
## core/rules/resolution.gd's Block reaction correctly falls back its
## block_die to the weapon's damage_die when no dedicated block_die is
## supplied (the "no shield weapon exists yet" case called out in B-1).
##
## Test criteria (per FEAT-001 spec):
##   - longsword.tres has block_value=1, parry_bonus=2
##   - mace.tres has block_value=2, parry_bonus=1
##   - longbow.tres has block_value=0, parry_bonus=0
##   - resolution logic falls back block_die to damage_die when block_die is unset

const ResolutionClass     = preload("res://core/rules/resolution.gd")
const WeaponResourceClass = preload("res://core/model/weapon_resource.gd")


# ══════════════════════════════════════════════════════════════════════════════
# Weapon fixture data (v0 CONFIRMED values, iteration-H B-1 / B-7)
# ══════════════════════════════════════════════════════════════════════════════

func test_longsword_block_value_is_1() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	assert_not_null(res, "ResourceLoader.load('res://data/weapons/longsword.tres') must return non-null")
	if res == null:
		return
	assert_eq(res.block_value, 1, "longsword.tres block_value must be 1 (iteration-H B-1 v0 value)")


func test_longsword_parry_bonus_is_2() -> void:
	var res = ResourceLoader.load("res://data/weapons/longsword.tres")
	assert_not_null(res, "ResourceLoader.load('res://data/weapons/longsword.tres') must return non-null")
	if res == null:
		return
	assert_eq(res.parry_bonus, 2, "longsword.tres parry_bonus must be 2 (iteration-H B-1 v0 value)")


func test_mace_block_value_is_2() -> void:
	var res = ResourceLoader.load("res://data/weapons/mace.tres")
	assert_not_null(res, "ResourceLoader.load('res://data/weapons/mace.tres') must return non-null")
	if res == null:
		return
	assert_eq(res.block_value, 2, "mace.tres block_value must be 2 (iteration-H B-1 v0 value)")


func test_mace_parry_bonus_is_1() -> void:
	var res = ResourceLoader.load("res://data/weapons/mace.tres")
	assert_not_null(res, "ResourceLoader.load('res://data/weapons/mace.tres') must return non-null")
	if res == null:
		return
	assert_eq(res.parry_bonus, 1, "mace.tres parry_bonus must be 1 (iteration-H B-1 v0 value)")


func test_longbow_block_value_is_0() -> void:
	var res = ResourceLoader.load("res://data/weapons/longbow.tres")
	assert_not_null(res, "ResourceLoader.load('res://data/weapons/longbow.tres') must return non-null")
	if res == null:
		return
	assert_eq(res.block_value, 0, "longbow.tres block_value must be 0 — ranged weapon, no block (iteration-H B-1)")


func test_longbow_parry_bonus_is_0() -> void:
	var res = ResourceLoader.load("res://data/weapons/longbow.tres")
	assert_not_null(res, "ResourceLoader.load('res://data/weapons/longbow.tres') must return non-null")
	if res == null:
		return
	assert_eq(res.parry_bonus, 0, "longbow.tres parry_bonus must be 0 — ranged weapon, no parry (iteration-H B-1)")


# ══════════════════════════════════════════════════════════════════════════════
# WeaponResource.block_die — nullable field, falls back to damage_die (B-1)
# ══════════════════════════════════════════════════════════════════════════════

func test_weapon_resource_has_block_die_property_defaulting_unset() -> void:
	## WeaponResource must expose block_die:int, defaulting to 0 ("unset" —
	## no shield weapon exists yet per iteration-H B-1; every current weapon
	## fixture leaves this unset so resolution.gd falls back to damage_die).
	var wr = WeaponResourceClass.new()
	assert_eq(wr.block_die, 0, "WeaponResource.block_die must exist and default to 0 (unset)")


func test_no_weapon_fixture_sets_block_die() -> void:
	## None of the three steel-thread weapon fixtures define a dedicated
	## block_die yet (B-1: "no shield weapon exists yet") — each must fall
	## back to its own damage_die inside resolution.gd's Block reaction.
	for weapon_id in ["longsword", "mace", "longbow"]:
		var res = ResourceLoader.load("res://data/weapons/%s.tres" % weapon_id)
		assert_not_null(res, "%s.tres must load" % weapon_id)
		if res == null:
			continue
		assert_eq(res.block_die, 0, "%s.tres block_die must be unset (0) — falls back to damage_die" % weapon_id)


# ══════════════════════════════════════════════════════════════════════════════
# RecordingRNG — captures the block_die_size passed to roll() by the Block
# reaction in resolution.gd, so the fallback-to-damage_die path is directly
# observable (rather than merely inferred from damage_final arithmetic).
# ══════════════════════════════════════════════════════════════════════════════
class RecordingRNG:
	var _d20_seq: Array
	var _d20_idx: int = 0
	var last_roll_die_size: int = -1
	var last_roll_count: int = -1

	func _init(d20_seq: Array) -> void:
		_d20_seq = d20_seq

	func d20() -> int:
		var val: int = _d20_seq[_d20_idx % _d20_seq.size()]
		_d20_idx += 1
		return val

	func roll(die_size: int, count: int) -> int:
		last_roll_die_size = die_size
		last_roll_count = count
		return 2  # fixed low roll so damage arithmetic stays simple/deterministic


## Attacker/target fixtures mirroring tests/unit/test_resolution.gd's
## FEAT-059 Block scenario (hit vs AC, no crit).
var _attacker: Dictionary = {"strength": 3}
var _target: Dictionary = {"ac": 13}


func test_block_falls_back_block_die_to_damage_die_when_unset() -> void:
	## Uses the real longsword.tres WeaponResource (block_die unset) as both
	## the attack weapon and the blocking weapon. Per resolution.gd's Block
	## reaction: block_die_size = blocking_weapon.block_die ?? blocking_weapon.
	## damage_die ?? weapon.damage_die. With block_die absent from the
	## blocking_weapon dict, the roll() call must receive longsword's
	## damage_die (12), never a default/zero value.
	var longsword = ResourceLoader.load("res://data/weapons/longsword.tres")
	assert_not_null(longsword, "longsword.tres must load")
	if longsword == null:
		return

	var weapon_dict: Dictionary = {
		"damage_modifier_attribute": longsword.damage_modifier_attribute,
		"proficiency_bonus": longsword.proficiency_bonus,
		"damage_die": longsword.damage_die
	}
	# blocking_weapon deliberately omits "block_die" — this is the "unset" case.
	var blocking_weapon: Dictionary = {
		"damage_die": longsword.damage_die,
		"block_value": longsword.block_value
	}

	# d20_seq: [attack_d20=11] -> roll_total = 11+3(str)+2(prof)=16 >= ac(13) -> hit, no crit
	var rng = RecordingRNG.new([11])
	var resolution = ResolutionClass.new(rng)

	var ctx: Dictionary = {"blocking_weapon": blocking_weapon}
	var result: Dictionary = resolution.resolve_weapon_attack(
		_attacker, _target, weapon_dict, "ac", "block", ctx
	)

	assert_true(result["hit"], "Setup must land a hit so the Block reaction triggers")
	assert_eq(
		rng.last_roll_die_size, longsword.damage_die,
		"Block reduction roll must fall back block_die to weapon.damage_die (%d) when block_die is unset; got %d" % [
			longsword.damage_die, rng.last_roll_die_size
		]
	)
	assert_eq(result["active_defense_applied"], "block", "Block must be recorded as the applied active defense")
