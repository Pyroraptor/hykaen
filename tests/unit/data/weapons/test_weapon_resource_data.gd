extends GutTest
## tests/unit/data/weapons/test_weapon_resource_data.gd
##
## GUT unit test suite for FEAT-001 (US-001 / FR-001, EWA-0-0 of
## docs/refactors/enemy-weapon-architecture-phase1.org): author
## data/weapons/arming_sword.tres as a normalized, standalone
## WeaponResource populated from the Weapons.pdf Heavy Blade row.
##
## Architecture note (Clean Architecture / ADR-001):
##   arming_sword.tres is a data/ Resource file — declarative data only,
##   zero behavior (ADR-104). It is consumed exclusively by infrastructure
##   (a future CombatantFactory change, out of scope for this feature) —
##   this test suite loads it directly via ResourceLoader, exactly as
##   infrastructure will, with no core/domain or core/application coupling.
##
## Test criteria (values are GROUND TRUTH from docs/design-source/
## Weapons.pdf's Heavy Blade row, reconciled in
## docs/refactors/enemy-weapon-architecture-phase1.org EWA-0-0):
##   - ResourceLoader.load('res://data/weapons/arming_sword.tres') returns
##     a non-null WeaponResource.
##   - weapon_id, name, damage_die, damage_type, damage_count,
##     damage_modifier_attribute, proficiency_bonus, block_value,
##     parry_bonus, block_die, range_hexes all match the Heavy Blade row.
##   - The assigned res:// UID does not collide with any other UID
##     assigned to a .tres file under data/weapons/ (RISK-010).

const WeaponResourceClass = preload("res://core/model/weapon_resource.gd")

const ARMING_SWORD_PATH := "res://data/weapons/arming_sword.tres"
const WEAPONS_DIR := "res://data/weapons"


# ══════════════════════════════════════════════════════════════════════════════
# Load + type criteria
# ══════════════════════════════════════════════════════════════════════════════

func test_arming_sword_loads_as_non_null_weapon_resource() -> void:
	var res = ResourceLoader.load(ARMING_SWORD_PATH)
	assert_not_null(res, "ResourceLoader.load('%s') must return non-null" % ARMING_SWORD_PATH)
	if res == null:
		return
	assert_true(
		res is WeaponResourceClass,
		"arming_sword.tres must load as a WeaponResource instance"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Field criteria — Heavy Blade row, docs/design-source/Weapons.pdf
# (values reconciled in enemy-weapon-architecture-phase1.org EWA-0-0)
# ══════════════════════════════════════════════════════════════════════════════

func test_arming_sword_weapon_id_is_arming_sword() -> void:
	var res = ResourceLoader.load(ARMING_SWORD_PATH)
	assert_not_null(res, "arming_sword.tres must load")
	if res == null:
		return
	assert_eq(res.weapon_id, "arming_sword", "weapon_id must be 'arming_sword'")


func test_arming_sword_name_is_arming_sword() -> void:
	var res = ResourceLoader.load(ARMING_SWORD_PATH)
	assert_not_null(res, "arming_sword.tres must load")
	if res == null:
		return
	assert_eq(res.name, "Arming Sword", "name must be 'Arming Sword'")


func test_arming_sword_damage_die_is_6() -> void:
	var res = ResourceLoader.load(ARMING_SWORD_PATH)
	assert_not_null(res, "arming_sword.tres must load")
	if res == null:
		return
	assert_eq(res.damage_die, 6, "damage_die must be 6 (d6, Heavy Blade row)")


func test_arming_sword_damage_type_is_s() -> void:
	var res = ResourceLoader.load(ARMING_SWORD_PATH)
	assert_not_null(res, "arming_sword.tres must load")
	if res == null:
		return
	assert_eq(res.damage_type, "S", "damage_type must be 'S' (slashing, Heavy Blade row)")


func test_arming_sword_damage_count_is_1() -> void:
	var res = ResourceLoader.load(ARMING_SWORD_PATH)
	assert_not_null(res, "arming_sword.tres must load")
	if res == null:
		return
	assert_eq(res.damage_count, 1, "damage_count must be 1")


func test_arming_sword_damage_modifier_attribute_is_strength() -> void:
	var res = ResourceLoader.load(ARMING_SWORD_PATH)
	assert_not_null(res, "arming_sword.tres must load")
	if res == null:
		return
	assert_eq(
		res.damage_modifier_attribute, "strength",
		"damage_modifier_attribute must be the canonical long-form 'strength'"
	)


func test_arming_sword_proficiency_bonus_is_2() -> void:
	var res = ResourceLoader.load(ARMING_SWORD_PATH)
	assert_not_null(res, "arming_sword.tres must load")
	if res == null:
		return
	assert_eq(res.proficiency_bonus, 2, "proficiency_bonus must be 2 (Heavy Blade row)")


func test_arming_sword_block_value_is_2() -> void:
	var res = ResourceLoader.load(ARMING_SWORD_PATH)
	assert_not_null(res, "arming_sword.tres must load")
	if res == null:
		return
	assert_eq(res.block_value, 2, "block_value must be 2 (Heavy Blade row, Block column)")


func test_arming_sword_parry_bonus_is_4() -> void:
	var res = ResourceLoader.load(ARMING_SWORD_PATH)
	assert_not_null(res, "arming_sword.tres must load")
	if res == null:
		return
	assert_eq(res.parry_bonus, 4, "parry_bonus must be 4 (Heavy Blade row, Parry column)")


func test_arming_sword_block_die_is_0() -> void:
	var res = ResourceLoader.load(ARMING_SWORD_PATH)
	assert_not_null(res, "arming_sword.tres must load")
	if res == null:
		return
	assert_eq(
		res.block_die, 0,
		"block_die must be 0 (unset) — no dedicated block die for arming_sword; falls back to damage_die"
	)


func test_arming_sword_range_hexes_is_1() -> void:
	var res = ResourceLoader.load(ARMING_SWORD_PATH)
	assert_not_null(res, "arming_sword.tres must load")
	if res == null:
		return
	assert_eq(res.range_hexes, 1, "range_hexes must be 1 — melee weapon, adjacency-only reach")


# ══════════════════════════════════════════════════════════════════════════════
# RISK-010: assigned res:// UID must not collide with any existing UID
# under data/weapons/
# ══════════════════════════════════════════════════════════════════════════════

func test_arming_sword_uid_does_not_collide_with_other_weapon_files() -> void:
	## Scans every .tres file directly under data/weapons/ (excluding
	## arming_sword.tres itself), extracts its top-level resource `uid=`
	## value, and asserts none of them equal arming_sword.tres's own uid.
	var arming_sword_text := FileAccess.get_file_as_string(
		"res://data/weapons/arming_sword.tres"
	)
	var arming_sword_uid := _extract_resource_uid(arming_sword_text)
	assert_ne(arming_sword_uid, "", "arming_sword.tres must declare a top-level resource uid")

	var dir := DirAccess.open(WEAPONS_DIR)
	assert_not_null(dir, "data/weapons/ directory must be readable")
	if dir == null:
		return

	dir.list_dir_begin()
	var seen_uids: Dictionary = {}
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres") and file_name != "arming_sword.tres":
			var other_path := "%s/%s" % [WEAPONS_DIR, file_name]
			var other_text := FileAccess.get_file_as_string(other_path)
			var other_uid := _extract_resource_uid(other_text)
			if other_uid != "":
				assert_ne(
					other_uid, arming_sword_uid,
					"arming_sword.tres uid (%s) must not collide with %s's uid (%s)" % [
						arming_sword_uid, file_name, other_uid
					]
				)
				seen_uids[other_uid] = file_name
		file_name = dir.get_next()
	dir.list_dir_end()

	assert_false(
		seen_uids.has(arming_sword_uid),
		"arming_sword.tres uid must be unique among data/weapons/*.tres files"
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-001 (US-001 / FR-001): shield WeaponResource data files
#
# Values are GROUND TRUTH from docs/design-source/Weapons.pdf's shield
# rows. RISK-004 mitigation: every stat is asserted to its EXACT value
# (not merely field presence), so a transcription error trips a test.
# All three shields share damage_die=4, damage_type='B', damage_count=1,
# damage_modifier_attribute='strength', range_hexes=1 (Weapons.pdf shield
# rows all use the same shield-bash damage line).
# ══════════════════════════════════════════════════════════════════════════════

const SMALL_SHIELD_PATH := "res://data/weapons/small_shield.tres"
const LARGE_SHIELD_PATH := "res://data/weapons/large_shield.tres"
const BUCKLER_PATH := "res://data/weapons/buckler.tres"


# ── small_shield.tres ─────────────────────────────────────────────────────────

func test_small_shield_loads_as_non_null_weapon_resource() -> void:
	var res = ResourceLoader.load(SMALL_SHIELD_PATH)
	assert_not_null(res, "ResourceLoader.load('%s') must return non-null" % SMALL_SHIELD_PATH)
	if res == null:
		return
	assert_true(
		res is WeaponResourceClass,
		"small_shield.tres must load as a WeaponResource instance"
	)


func test_small_shield_weapon_id_is_small_shield() -> void:
	var res = ResourceLoader.load(SMALL_SHIELD_PATH)
	assert_not_null(res, "small_shield.tres must load")
	if res == null:
		return
	assert_eq(res.weapon_id, "small_shield", "weapon_id must be 'small_shield'")


func test_small_shield_stats() -> void:
	var res = ResourceLoader.load(SMALL_SHIELD_PATH)
	assert_not_null(res, "small_shield.tres must load")
	if res == null:
		return
	assert_eq(res.block_value, 4, "small_shield block_value must be 4")
	assert_eq(res.parry_bonus, 1, "small_shield parry_bonus must be 1")
	assert_eq(res.block_die, 10, "small_shield block_die must be 10 (1d10)")
	assert_eq(res.damage_die, 4, "small_shield damage_die must be 4 (1d4)")
	assert_eq(res.damage_type, "B", "small_shield damage_type must be 'B' (bludgeoning)")
	assert_eq(res.damage_count, 1, "small_shield damage_count must be 1")
	assert_eq(
		res.damage_modifier_attribute, "strength",
		"small_shield damage_modifier_attribute must be 'strength'"
	)
	assert_eq(res.range_hexes, 1, "small_shield range_hexes must be 1 — melee, adjacency-only")


# ── large_shield.tres ─────────────────────────────────────────────────────────

func test_large_shield_loads_as_non_null_weapon_resource() -> void:
	var res = ResourceLoader.load(LARGE_SHIELD_PATH)
	assert_not_null(res, "ResourceLoader.load('%s') must return non-null" % LARGE_SHIELD_PATH)
	if res == null:
		return
	assert_true(
		res is WeaponResourceClass,
		"large_shield.tres must load as a WeaponResource instance"
	)


func test_large_shield_weapon_id_is_large_shield() -> void:
	var res = ResourceLoader.load(LARGE_SHIELD_PATH)
	assert_not_null(res, "large_shield.tres must load")
	if res == null:
		return
	assert_eq(res.weapon_id, "large_shield", "weapon_id must be 'large_shield'")


func test_large_shield_stats() -> void:
	var res = ResourceLoader.load(LARGE_SHIELD_PATH)
	assert_not_null(res, "large_shield.tres must load")
	if res == null:
		return
	assert_eq(res.block_value, 5, "large_shield block_value must be 5")
	assert_eq(res.parry_bonus, 2, "large_shield parry_bonus must be 2")
	assert_eq(res.block_die, 12, "large_shield block_die must be 12 (1d12)")
	assert_eq(res.damage_die, 4, "large_shield damage_die must be 4 (1d4)")
	assert_eq(res.damage_type, "B", "large_shield damage_type must be 'B' (bludgeoning)")
	assert_eq(res.damage_count, 1, "large_shield damage_count must be 1")
	assert_eq(
		res.damage_modifier_attribute, "strength",
		"large_shield damage_modifier_attribute must be 'strength'"
	)
	assert_eq(res.range_hexes, 1, "large_shield range_hexes must be 1 — melee, adjacency-only")


# ── buckler.tres ──────────────────────────────────────────────────────────────

func test_buckler_loads_as_non_null_weapon_resource() -> void:
	var res = ResourceLoader.load(BUCKLER_PATH)
	assert_not_null(res, "ResourceLoader.load('%s') must return non-null" % BUCKLER_PATH)
	if res == null:
		return
	assert_true(
		res is WeaponResourceClass,
		"buckler.tres must load as a WeaponResource instance"
	)


func test_buckler_weapon_id_is_buckler() -> void:
	var res = ResourceLoader.load(BUCKLER_PATH)
	assert_not_null(res, "buckler.tres must load")
	if res == null:
		return
	assert_eq(res.weapon_id, "buckler", "weapon_id must be 'buckler'")


func test_buckler_stats() -> void:
	var res = ResourceLoader.load(BUCKLER_PATH)
	assert_not_null(res, "buckler.tres must load")
	if res == null:
		return
	assert_eq(res.block_value, 3, "buckler block_value must be 3")
	assert_eq(res.parry_bonus, 3, "buckler parry_bonus must be 3")
	assert_eq(res.block_die, 8, "buckler block_die must be 8 (1d8)")
	assert_eq(res.damage_die, 4, "buckler damage_die must be 4 (1d4)")
	assert_eq(res.damage_type, "B", "buckler damage_type must be 'B' (bludgeoning)")
	assert_eq(res.damage_count, 1, "buckler damage_count must be 1")
	assert_eq(
		res.damage_modifier_attribute, "strength",
		"buckler damage_modifier_attribute must be 'strength'"
	)
	assert_eq(res.range_hexes, 1, "buckler range_hexes must be 1 — melee, adjacency-only")


# ── RISK-010: shield UIDs must not collide with each other or existing files ──

func test_shield_uids_do_not_collide_with_other_weapon_files() -> void:
	var shield_files := [SMALL_SHIELD_PATH, LARGE_SHIELD_PATH, BUCKLER_PATH]

	var dir := DirAccess.open(WEAPONS_DIR)
	assert_not_null(dir, "data/weapons/ directory must be readable")
	if dir == null:
		return

	var uid_by_file: Dictionary = {}
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path := "%s/%s" % [WEAPONS_DIR, file_name]
			var text := FileAccess.get_file_as_string(path)
			var uid := _extract_resource_uid(text)
			assert_ne(uid, "", "%s must declare a top-level resource uid" % file_name)
			uid_by_file[path] = uid
		file_name = dir.get_next()
	dir.list_dir_end()

	for shield_path in shield_files:
		assert_true(uid_by_file.has(shield_path), "%s must exist under data/weapons/" % shield_path)

	var seen: Dictionary = {}
	for path in uid_by_file.keys():
		var uid = uid_by_file[path]
		assert_false(
			seen.has(uid),
			"UID collision: %s and %s share uid %s" % [path, seen.get(uid, ""), uid]
		)
		seen[uid] = path


func _extract_resource_uid(tres_text: String) -> String:
	## Extracts the top-level `[gd_resource ... uid="uid://..."]` value from
	## raw .tres file text using a plain string scan (no regex dependency).
	var marker := "uid=\""
	var marker_idx := tres_text.find(marker)
	if marker_idx == -1:
		return ""
	var start := marker_idx + marker.length()
	var end := tres_text.find("\"", start)
	if end == -1:
		return ""
	return tres_text.substr(start, end - start)
