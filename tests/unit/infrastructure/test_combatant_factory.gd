extends GutTest
## tests/unit/infrastructure/test_combatant_factory.gd — FEAT-005 (US-004;
## FR-007).
##
## Verifies infrastructure/combatant_factory.gd's build_party_combatant()
## exposes `equipped_items` on the returned combatant Dictionary: a SHALLOW
## copy of CharacterResource.equipped_items (character.equipped_items.
## duplicate()) so the Array container is independent per-build but the
## ItemResource instances INSIDE it are the SAME live references as
## character.equipped_items — a mutation to a field on one of those
## ItemResource instances (e.g. is_charged) must be visible both through the
## combatant dict's copy of the array AND through character.equipped_items
## directly, since both arrays hold the identical Resource objects.
##
## This is the infrastructure seam (ADR-004) that lets the application layer
## duck-type-read equipped_items off the combatant dict without the
## application layer importing any Resource/.tres machinery.

const CombatantFactoryClass = preload("res://infrastructure/combatant_factory.gd")

const GRAM_MARX_PATH: String = "res://data/characters/gram_marx.tres"
const MARIGOLD_PATH: String = "res://data/characters/marigold.tres"


func _has_item_id(equipped_items: Array, item_id: String) -> bool:
	for item in equipped_items:
		if item.item_id == item_id:
			return true
	return false


func test_gram_marx_equipped_items_has_3_entries_including_orb_gram() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_1")

	assert_false(combatant.has("error"), "fixture assumption: gram_marx.tres must build a valid combatant with no error")
	assert_true(combatant.has("equipped_items"), "build_party_combatant() must expose 'equipped_items' on the combatant dict")

	var equipped_items: Array = combatant.get("equipped_items", [])
	assert_eq(equipped_items.size(), 2, "gram_marx's combatant['equipped_items'] must have exactly 2 entries (staff_gram, orb_gram) — Wizards do not Channel")
	assert_true(
		_has_item_id(equipped_items, "orb_gram"),
		"gram_marx's combatant['equipped_items'] must include orb_gram"
	)


func test_mutating_item_is_charged_via_combatant_dict_is_visible_on_character_directly() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_1")

	var character = ResourceLoader.load(GRAM_MARX_PATH)

	var orb_via_combatant = null
	for item in combatant.get("equipped_items", []):
		if item.item_id == "orb_gram":
			orb_via_combatant = item
	assert_not_null(orb_via_combatant, "fixture assumption: orb_gram must be reachable through combatant['equipped_items']")

	assert_true(orb_via_combatant.is_charged, "fixture assumption: orb_gram.tres is authored with is_charged=true")

	# Mutate through the reference obtained via the combatant dict.
	orb_via_combatant.is_charged = false

	var orb_via_character = null
	for item in character.equipped_items:
		if item.item_id == "orb_gram":
			orb_via_character = item
	assert_not_null(orb_via_character, "fixture assumption: orb_gram must be reachable through character.equipped_items")

	assert_false(
		orb_via_character.is_charged,
		"mutating is_charged on an ItemResource reached through combatant['equipped_items'] must be visible via character.equipped_items directly -- equipped_items must be a SHALLOW copy (live ItemResource references), not a deep copy"
	)


func test_gram_marx_known_spell_ids_unchanged_by_equipped_items_addition() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, null, "gram_marx_1")

	assert_eq(
		combatant.get("known_spell_ids", ["SENTINEL"]), [],
		"regression: gram_marx's known_spell_ids output must be unchanged by the equipped_items addition"
	)


func test_marigold_known_spell_ids_unchanged_by_equipped_items_addition() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(MARIGOLD_PATH, null, "marigold_1")

	assert_eq(
		combatant.get("known_spell_ids", []), ["fire_bolt", "channel"],
		"regression: marigold's known_spell_ids output must be unchanged by the equipped_items addition"
	)
