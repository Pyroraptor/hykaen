extends GutTest
## tests/unit/test_build_enemy_combatant_weapon_defense.gd
##
## GUT unit tests for FEAT-001 (US-001, iteration K): MainScene.gd's
## _build_enemy_combatant() must thread the new parry_bonus/block_value/
## block_die fields (data/enemies/enemy_resource.gd) into the "weapon"
## Dictionary it builds, exactly mirroring _build_party_combatant()'s
## existing FEAT-006 fix. Without this, core/rules/resolution.gd's
## is_parry_eligible()/is_block_eligible() always read 0 for an enemy
## combatant and the reaction window could never offer the enemy (or a
## player reacting to the enemy's own Strike/Block) a real Parry/Block.
##
## Mirrors tests/unit/test_build_enemy_combatant_defenses.gd's established
## pattern: a freshly `.new()`-constructed (NOT scene-tree-booted) MainScene
## instance so the private _build_enemy_combatant() helper can be exercised
## directly.
##
## Test criteria covered:
##   1. _build_enemy_combatant(skeleton.tres)'s weapon dict carries
##      damage_die=6, proficiency_bonus=2, block_value=2, parry_bonus=4,
##      block_die=0, damage_modifier_attribute="strength" (the Arming Sword
##      table, translated through the existing str->strength attribute map).
##   2. ResolutionClass.is_parry_eligible()/is_block_eligible() are TRUE for
##      the built weapon dict (non-zero parry_bonus/block_value reach the
##      predicate).
##   3. block_die<=0 (skeleton's authored 0) falls back to damage_die (6)
##      when used as resolution.gd's Block reduction die — proven end to
##      end through a RecordingRNG capturing the die size actually rolled,
##      using the Skeleton's OWN _build_enemy_combatant()-built weapon dict
##      as both the attack weapon and the blocking weapon (mirrors
##      tests/unit/test_weapon_resource_data.gd's identical technique).

const MainSceneClass = preload("res://MainScene.gd")
const ResolutionClass = preload("res://core/rules/resolution.gd")
const SKELETON_TRES_PATH := "res://data/enemies/skeleton.tres"

var _instance = null


func before_each() -> void:
	_instance = MainSceneClass.new()


func after_each() -> void:
	if _instance != null:
		_instance.free()
	_instance = null


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: weapon dict carries the full Arming Sword table.
# ══════════════════════════════════════════════════════════════════════════

func test_build_enemy_combatant_weapon_dict_matches_arming_sword_table() -> void:
	var combatant: Dictionary = _instance._build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")
	var weapon: Dictionary = combatant.get("weapon", {})

	assert_eq(weapon.get("damage_die", -1), 6, "enemy weapon dict damage_die must be 6")
	assert_eq(weapon.get("proficiency_bonus", -1), 2, "enemy weapon dict proficiency_bonus must be 2")
	assert_eq(weapon.get("damage_modifier_attribute", ""), "strength", "enemy weapon dict damage_modifier_attribute must be 'strength'")
	assert_eq(weapon.get("block_value", -1), 2, "enemy weapon dict block_value must be 2")
	assert_eq(weapon.get("parry_bonus", -1), 4, "enemy weapon dict parry_bonus must be 4")
	assert_eq(weapon.get("block_die", -1), 0, "enemy weapon dict block_die must be 0 (unset)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: is_parry_eligible()/is_block_eligible() read non-zero.
# ══════════════════════════════════════════════════════════════════════════

func test_skeleton_weapon_dict_is_parry_and_block_eligible() -> void:
	var combatant: Dictionary = _instance._build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")
	var weapon: Dictionary = combatant.get("weapon", {})

	assert_true(
		ResolutionClass.is_parry_eligible(weapon),
		"Skeleton's built weapon dict must be Parry-eligible (parry_bonus=4 > 0)"
	)
	assert_true(
		ResolutionClass.is_block_eligible(weapon),
		"Skeleton's built weapon dict must be Block-eligible (block_value=2 > 0)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: block_die<=0 falls back to damage_die in the weapon dict,
# proven via the actual RNG call resolution.gd's Block branch makes.
# ══════════════════════════════════════════════════════════════════════════

class RecordingRNG:
	var _d20_seq: Array
	var _d20_idx: int = 0
	var last_roll_die_size: int = -1

	func _init(d20_seq: Array) -> void:
		_d20_seq = d20_seq

	func d20() -> int:
		var val: int = _d20_seq[_d20_idx % _d20_seq.size()]
		_d20_idx += 1
		return val

	func roll(die_size: int, count: int) -> int:
		last_roll_die_size = die_size
		return 2  # fixed low roll so damage arithmetic stays simple/deterministic


func test_block_falls_back_block_die_to_damage_die_for_skeleton_weapon() -> void:
	var combatant: Dictionary = _instance._build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")
	var weapon: Dictionary = combatant.get("weapon", {})

	assert_eq(weapon.get("block_die", -1), 0, "setup: skeleton weapon dict block_die must be 0 (unset)")

	var attacker: Dictionary = {"strength": combatant.get("strength", 0)}
	var target: Dictionary = {"ac": 1}  # guarantees a hit regardless of roll

	# d20_seq: [attack_d20=11] -> definitely hits target ac=1
	var rng = RecordingRNG.new([11])
	var resolution = ResolutionClass.new(rng)

	var ctx: Dictionary = {"blocking_weapon": weapon}
	var result: Dictionary = resolution.resolve_weapon_attack(
		attacker, target, weapon, "ac", "block", ctx
	)

	assert_true(result["hit"], "Setup must land a hit so the Block reaction triggers")
	assert_eq(
		rng.last_roll_die_size, weapon.get("damage_die", -1),
		"Block reduction roll must fall back the Skeleton's block_die to its damage_die (%d) when block_die<=0; got %d" % [
			weapon.get("damage_die", -1), rng.last_roll_die_size
		]
	)
	assert_eq(result["active_defense_applied"], "block", "Block must be recorded as the applied active defense")
