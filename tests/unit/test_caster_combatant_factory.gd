extends GutTest
## tests/unit/test_caster_combatant_factory.gd — FEAT-002 (Iteration M P0-0,
## US-001; FR-001, FR-002).
##
## Verifies infrastructure/combatant_factory.gd's build_party_combatant()
## produces a caster combatant through the EXISTING, unmodified construction
## path (no bespoke caster branch) -- CombatantFactory just resolves
## Marigold's spellcasting_attribute_score from her class_ref
## (core/model/class_resource.gd's ClassResource.spellcasting_attribute,
## "willpower" for a Divine Warrior) + her own authored attributes, and
## carries known_spell_ids straight through from
## data/characters/marigold.tres.
##
## test_criteria: "Unit test confirms CombatantFactory produces the caster
## via the existing factory path with casting_state == null at
## construction."

const CombatantFactoryClass = preload("res://infrastructure/combatant_factory.gd")

const MARIGOLD_PATH: String = "res://data/characters/marigold.tres"


func test_marigold_spellcasting_attribute_score_resolves_from_willpower() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(MARIGOLD_PATH, null, "marigold_1")

	assert_false(combatant.has("error"), "fixture assumption: marigold.tres must build a valid combatant with no error")

	var character = ResourceLoader.load(MARIGOLD_PATH)
	var expected_score: int = int(character.attributes.get("willpower", -1))
	assert_eq(expected_score, 4, "fixture assumption: marigold.tres's authored willpower must be 4")
	assert_eq(character.class_ref.spellcasting_attribute, "willpower",
		"fixture assumption: marigold's class_ref (divine_warrior) spellcasting_attribute must be 'willpower'")

	assert_eq(
		combatant.get("spellcasting_attribute_score", -1), expected_score,
		"build_party_combatant() must resolve spellcasting_attribute_score from the character's OWN willpower attribute (%d) via class_ref.spellcasting_attribute, not a missing/zero-defaulted value" % expected_score
	)


func test_marigold_known_spell_ids_carried_through_from_resource() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(MARIGOLD_PATH, null, "marigold_1")

	assert_eq(
		combatant.get("known_spell_ids", []), ["fire_bolt", "channel"],
		"build_party_combatant() must carry known_spell_ids straight through from CharacterResource"
	)


func test_marigold_casting_state_is_null_at_construction() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(MARIGOLD_PATH, null, "marigold_1")

	assert_null(
		combatant.get("casting_state", null),
		"a freshly-constructed caster combatant must have NO casting_state -- reuse the existing construction path, no bespoke caster path that pre-populates it"
	)


func test_non_caster_titus_resolves_zero_score_and_empty_known_spells() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant("res://data/characters/titus.tres", null, "titus_1")

	assert_eq(
		combatant.get("spellcasting_attribute_score", -1), 0,
		"a non-caster (Fighter, spellcasting_attribute='') must resolve a spellcasting_attribute_score of 0"
	)
	assert_eq(
		combatant.get("known_spell_ids", ["SENTINEL"]), [],
		"a non-caster with no authored known_spell_ids must resolve an empty Array"
	)
