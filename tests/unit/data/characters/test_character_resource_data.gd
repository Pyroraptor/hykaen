extends GutTest
## tests/unit/data/characters/test_character_resource_data.gd
##
## GUT unit tests for FEAT-002 (US-002 / FR-004): Patience's
## (data/characters/dwarf_channeler.tres) starting_equipment gains a
## small shield as her off-hand weapon, appended as the SECOND entry
## (after the mace, before the chain shirt) — the entry-point data
## prerequisite for the steel thread's Combatant build step
## (CombatantFactory.build_party_combatant() walking starting_equipment
## into an ordered weapons list).
##
## Architecture note (ADR-001/ADR-002): dwarf_channeler.tres is a data/
## Resource file consumed by DOMAIN/APPLICATION/INFRASTRUCTURE via plain
## ResourceLoader — this test loads it directly, exactly as
## infrastructure/combatant_factory.gd will, with zero core/ coupling.
##
## Test criteria covered (per FEAT-002 spec):
##   1. starting_equipment == ['res://data/weapons/mace.tres',
##      'res://data/weapons/small_shield.tres',
##      'res://data/armor/chain_shirt.tres'] (order preserved, mace first).
##   2. equipped_items is unchanged (still references shield_patience.tres
##      only for slot metadata, not the new small_shield.tres weapon).
##   3. The resource loads without error.

const DWARF_CHANNELER_PATH := "res://data/characters/dwarf_channeler.tres"

const EXPECTED_STARTING_EQUIPMENT := [
	"res://data/weapons/mace.tres",
	"res://data/weapons/small_shield.tres",
	"res://data/armor/chain_shirt.tres",
]


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: the resource loads without error
# ══════════════════════════════════════════════════════════════════════════════

func test_dwarf_channeler_loads_without_error() -> void:
	var res = ResourceLoader.load(DWARF_CHANNELER_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(res, "dwarf_channeler.tres must load non-null")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: starting_equipment gains small_shield.tres as the second
# entry, order preserved (mace first, chain shirt last)
# ══════════════════════════════════════════════════════════════════════════════

func test_starting_equipment_has_small_shield_as_second_entry_order_preserved() -> void:
	var res = ResourceLoader.load(DWARF_CHANNELER_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(res, "dwarf_channeler.tres must load non-null")
	if res == null:
		return

	assert_eq(
		res.starting_equipment, EXPECTED_STARTING_EQUIPMENT,
		"dwarf_channeler.starting_equipment must equal %s (mace first, shield second, chain shirt last); got: %s"
			% [EXPECTED_STARTING_EQUIPMENT, res.starting_equipment]
	)


func test_starting_equipment_first_entry_is_still_mace() -> void:
	var res = ResourceLoader.load(DWARF_CHANNELER_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(res, "dwarf_channeler.tres must load non-null")
	if res == null:
		return

	assert_eq(
		res.starting_equipment[0], "res://data/weapons/mace.tres",
		"dwarf_channeler.starting_equipment[0] must remain the mace (US-002: shield is appended AFTER the mace)"
	)


func test_small_shield_resource_referenced_in_starting_equipment_loads() -> void:
	var res = ResourceLoader.load(DWARF_CHANNELER_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(res, "dwarf_channeler.tres must load non-null")
	if res == null:
		return

	var shield_path: String = res.starting_equipment[1]
	var shield = ResourceLoader.load(shield_path)
	assert_not_null(shield, "small_shield.tres referenced from starting_equipment must load non-null")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: equipped_items is unchanged — still slot metadata only,
# NOT the source of the shield's combat stats
# ══════════════════════════════════════════════════════════════════════════════

func test_equipped_items_unchanged_still_references_shield_patience_for_slot_metadata() -> void:
	var res = ResourceLoader.load(DWARF_CHANNELER_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(res, "dwarf_channeler.tres must load non-null")
	if res == null:
		return

	assert_eq(
		res.equipped_items.size(), 2,
		"dwarf_channeler.equipped_items must remain unchanged at size 2 (mace_patience + shield_patience); got size %s"
			% res.equipped_items.size()
	)

	var found_shield_patience := false
	for item in res.equipped_items:
		if item != null and String(item.resource_path).ends_with("shield_patience.tres"):
			found_shield_patience = true
	assert_true(
		found_shield_patience,
		"dwarf_channeler.equipped_items must still reference shield_patience.tres (slot metadata only, untouched by US-002)"
	)
