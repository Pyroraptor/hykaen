extends GutTest
## tests/boot/test_caster_loads_in_prologue.gd — FEAT-002 (Iteration M P0-0,
## US-001; FR-001, FR-002).
##
## Boot-real proof that the prologue encounter (data/encounters/
## prologue_encounter.tres) now includes a castable party member: boots the
## REAL res://MainScene.tscn composition root (never a hand-wired double) and
## asserts the Marigold combatant is present among the live party with a
## correctly-resolved spellcasting_attribute_score and
## known_spell_ids=[fire_bolt, channel] -- proving the caster is wired
## through the SAME real data-loading path every other party member uses
## (infrastructure/combatant_factory.gd's build_party_combatant()), not a
## bespoke caster construction path.
##
## test_criteria: "Boot-real smoke test confirms caster combatant loads in
## the prologue encounter with correct spellcasting_attribute_score and
## known_spell_ids=[fire_bolt, channel]."

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MARIGOLD_PATH: String = "res://data/characters/marigold.tres"

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/integration/test_combatant_factory_skills_boot_real.gd's
## identically-named/valued constant).
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _find_marigold(instance):
	for combatant in instance._party:
		if combatant.name == "Marigold":
			return combatant
	return null


func test_marigold_is_present_in_the_live_prologue_party() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_true(instance._party.size() >= 2, "the prologue encounter's live party must now include the caster alongside Titus")
	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "the real, booted MainScene party must include a 'Marigold' combatant")


func test_marigold_combatant_has_correct_spellcasting_attribute_score() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	if marigold == null:
		return

	var character = ResourceLoader.load(MARIGOLD_PATH)
	var expected_score: int = int(character.attributes.get("willpower", -1))
	assert_eq(
		marigold.spellcasting_attribute_score, expected_score,
		"the live, booted Marigold combatant's spellcasting_attribute_score must equal her authored willpower (%d), resolved via the REAL CombatantFactory construction path" % expected_score
	)
	assert_ne(marigold.spellcasting_attribute_score, 0, "the resolved score must be non-zero -- Marigold is a Divine Warrior caster")


func test_marigold_combatant_has_correct_known_spell_ids() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	if marigold == null:
		return

	assert_eq(
		marigold.known_spell_ids, ["fire_bolt", "channel"],
		"the live, booted Marigold combatant's known_spell_ids must be ['fire_bolt', 'channel']"
	)


func test_marigold_casting_state_is_empty_at_boot() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	if marigold == null:
		return

	assert_false(marigold.is_casting(), "a freshly-booted caster must not already be mid-cast")
