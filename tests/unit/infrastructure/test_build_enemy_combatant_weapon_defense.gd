extends GutTest
## tests/unit/infrastructure/test_build_enemy_combatant_weapon_defense.gd
##
## GUT unit tests for FEAT-006 (US-005; ADR-005/ADR-006): infrastructure/
## combatant_factory.gd's build_enemy_combatant() resolves a weapon via
## path-based precedence -- weapon_path_override (4th arg) first, then
## enemy.weapon_paths[0] -- loads it via ResourceLoader, and populates BOTH
## combatant['weapon'] (legacy shape) and combatant['weapons'] (FEAT-005's
## Array-of-Dictionary representation) with NO attribute_map translation:
## WeaponResource.damage_modifier_attribute is copied verbatim.
##
## Exercises CombatantFactory directly (not through the MainScene test seam)
## since weapon_path_override is a new argument on
## CombatantFactory.build_enemy_combatant() itself.
##
## Test criteria covered:
##   1. weapon_path_override (non-empty) takes precedence over
##      enemy.weapon_paths[0].
##   2. Building the skeleton combatant (no override) yields
##      weapon/weapons with parry_bonus==4, block_value==2, block_die==0,
##      damage_die==6, damage_modifier_attribute=='strength' (the Arming
##      Sword table).
##   3. combatant['weapon'] matches the pre-refactor key shape and
##      combatant['weapons'] == [weapon.duplicate(true)].
##   4. No attribute_map translation code remains in
##      infrastructure/combatant_factory.gd.
##   5. (FEAT-389 merge, FEAT-001 iteration K origin) the built weapon dict
##      is genuinely Parry/Block-eligible per core/rules/resolution.gd's own
##      predicates, AND a block_die<=0 (skeleton's authored 0) falls back to
##      damage_die (6) as resolution.gd's actual Block reduction die --
##      proven end to end via a RecordingRNG capturing the die size rolled.
##      Merged from the now-deleted tests/unit/test_build_enemy_combatant_
##      weapon_defense.gd (which exercised the same underlying
##      CombatantFactory logic indirectly through the MainScene test seam --
##      MainScene._build_enemy_combatant() is a trivial delegate to
##      CombatantFactory.build_enemy_combatant(), so exercising the factory
##      directly here is equivalent, no MainScene-specific behavior lost).

const CombatantFactoryClass = preload("res://infrastructure/combatant_factory.gd")
const ResolutionClass = preload("res://core/rules/resolution.gd")

const SKELETON_TRES_PATH: String = "res://data/enemies/skeleton.tres"
const ARMING_SWORD_PATH: String = "res://data/weapons/arming_sword.tres"
const MACE_PATH: String = "res://data/weapons/mace.tres"


# ══════════════════════════════════════════════════════════════════════════
# Criterion: weapon_path_override takes precedence over enemy.weapon_paths[0].
# ══════════════════════════════════════════════════════════════════════════

func test_weapon_path_override_takes_precedence_over_enemy_weapon_paths() -> void:
	var factory := CombatantFactoryClass.new()

	# skeleton.tres' own weapon_paths[0] is arming_sword.tres (damage_die=6,
	# parry_bonus=4). Overriding with mace.tres (damage_die=8, parry_bonus=1,
	# block_value=2, block_die=0) must win.
	var combatant: Dictionary = factory.build_enemy_combatant(
		SKELETON_TRES_PATH, null, "skeleton_override_1", MACE_PATH
	)

	assert_false(combatant.has("error"), "override build must succeed; got: %s" % str(combatant))
	var weapon: Dictionary = combatant.get("weapon", {})
	assert_eq(weapon.get("damage_die", -1), 8, "override weapon dict must carry the Mace's damage_die (8), not the Skeleton's default Arming Sword (6)")
	assert_eq(weapon.get("proficiency_bonus", -1), 1, "override weapon dict must carry the Mace's proficiency_bonus (1)")
	assert_eq(weapon.get("parry_bonus", -1), 1, "override weapon dict must carry the Mace's parry_bonus (1), not the Arming Sword's (4)")
	assert_eq(weapon.get("block_value", -1), 2, "override weapon dict must carry the Mace's block_value (2)")
	assert_eq(weapon.get("block_die", -1), 0, "override weapon dict must carry the Mace's block_die (0, unset default)")
	assert_eq(weapon.get("damage_modifier_attribute", ""), "strength", "override weapon dict must carry the Mace's damage_modifier_attribute")


func test_empty_weapon_path_override_falls_back_to_enemy_weapon_paths() -> void:
	var factory := CombatantFactoryClass.new()

	# An explicit empty-string override (the default) must NOT be treated as
	# "override present" -- it must fall through to enemy.weapon_paths[0]
	# (arming_sword.tres).
	var combatant: Dictionary = factory.build_enemy_combatant(
		SKELETON_TRES_PATH, null, "skeleton_no_override_1", ""
	)

	assert_false(combatant.has("error"), "no-override build must succeed; got: %s" % str(combatant))
	var weapon: Dictionary = combatant.get("weapon", {})
	assert_eq(weapon.get("damage_die", -1), 6, "empty override must fall back to the Skeleton's own weapon_paths[0] (Arming Sword, damage_die=6)")
	assert_eq(weapon.get("parry_bonus", -1), 4, "empty override must fall back to the Arming Sword's parry_bonus (4)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion: skeleton combatant (no override) yields the full Arming Sword
# table on both `weapon` and `weapons`.
# ══════════════════════════════════════════════════════════════════════════

func test_skeleton_weapon_dict_matches_arming_sword_table() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")

	assert_false(combatant.has("error"), "fixture assumption: skeleton.tres must build a valid combatant with no error")

	var weapon: Dictionary = combatant.get("weapon", {})
	assert_eq(weapon.get("damage_die", -1), 6, "skeleton weapon dict damage_die must be 6")
	assert_eq(weapon.get("proficiency_bonus", -1), 2, "skeleton weapon dict proficiency_bonus must be 2")
	assert_eq(weapon.get("damage_modifier_attribute", ""), "strength", "skeleton weapon dict damage_modifier_attribute must be 'strength'")
	assert_eq(weapon.get("parry_bonus", -1), 4, "skeleton weapon dict parry_bonus must be 4")
	assert_eq(weapon.get("block_value", -1), 2, "skeleton weapon dict block_value must be 2")
	assert_eq(weapon.get("block_die", -1), 0, "skeleton weapon dict block_die must be 0 (unset)")


func test_skeleton_weapons_array_matches_weapon_dict() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")

	assert_true(combatant.has("weapons"), "build_enemy_combatant() must populate combatant['weapons']")
	var weapon: Dictionary = combatant.get("weapon", {})
	var weapons: Array = combatant.get("weapons", [])

	assert_eq(weapons.size(), 1, "combatant['weapons'] must contain exactly one entry for a single-weapon enemy")
	assert_eq(weapons[0], weapon, "combatant['weapons'][0] must equal combatant['weapon'] (weapon.duplicate(true))")

	# Non-aliasing: mutating the weapons[0] entry must not perturb `weapon`.
	weapons[0]["damage_die"] = 999
	assert_eq(weapon.get("damage_die", -1), 6, "combatant['weapons'][0] must be a non-aliasing duplicate of combatant['weapon']")


# ══════════════════════════════════════════════════════════════════════════
# Criterion: no attribute_map translation code remains.
# ══════════════════════════════════════════════════════════════════════════

func test_no_attribute_map_translation_code_remains() -> void:
	var file := FileAccess.open("res://infrastructure/combatant_factory.gd", FileAccess.READ)
	assert_not_null(file, "infrastructure/combatant_factory.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	# Checks for actual TRANSLATION CODE constructs (a lookup table/dict and
	# its usage), not mere prose -- this file's own doc comments legitimately
	# reference the historical "attribute_map" name when explaining WHY it
	# was removed (e.g. "the old str/dex -> strength/dexterity attribute_map
	# translation is no longer needed"), which must not itself trip this
	# regression guard.
	assert_false(
		content.contains("var attribute_map") or content.contains("const attribute_map") or content.contains("const ATTRIBUTE_MAP"),
		"infrastructure/combatant_factory.gd must declare no attribute_map lookup table (FEAT-006 / ADR-005/ADR-006) -- damage_modifier_attribute must be copied verbatim from WeaponResource"
	)
	assert_false(
		content.contains("attribute_map[") or content.contains("attribute_map.get(") or content.contains("ATTRIBUTE_MAP["),
		"infrastructure/combatant_factory.gd must perform no attribute_map dictionary lookup (FEAT-006 / ADR-005/ADR-006) -- damage_modifier_attribute must be copied verbatim from WeaponResource"
	)
	assert_true(
		content.contains("weapon_res.damage_modifier_attribute"),
		"infrastructure/combatant_factory.gd must read damage_modifier_attribute VERBATIM off the loaded WeaponResource"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 (FEAT-389 merge): the built weapon dict is genuinely
# Parry/Block-eligible, and block_die<=0 falls back to damage_die as the
# ACTUAL Block reduction die resolution.gd rolls.
# ══════════════════════════════════════════════════════════════════════════

func test_skeleton_weapon_dict_is_parry_and_block_eligible() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")
	var weapon: Dictionary = combatant.get("weapon", {})

	assert_true(
		ResolutionClass.is_parry_eligible(weapon),
		"Skeleton's built weapon dict must be Parry-eligible (parry_bonus=4 > 0)"
	)
	assert_true(
		ResolutionClass.is_block_eligible(weapon),
		"Skeleton's built weapon dict must be Block-eligible (block_value=2 > 0)"
	)


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
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")
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
