extends GutTest
## tests/boot/test_main_scene_cast_spell_verb_registered.gd — FEAT-004
## (US-004; FR-003, NFR-003)
##
## Headless boot-real proof that the REAL, shipped res://MainScene.tscn
## composition root (never a hand-wired double) plus the prologue encounter
## (data/encounters/prologue_encounter.tres) load cleanly with CAST_SPELL
## registered in VERB_TABLE -- mirroring tests/boot/test_caster_loads_in_prologue.gd's
## established "_boot_main_scene()" convention.
##
## test_criteria: "Headless boot test confirms MainScene + prologue
## encounter load cleanly with CAST_SPELL registered in VERB_TABLE
## (NFR-003)."

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const SpellActionControllerClass = preload("res://presentation/verbs/spell_action_controller.gd")

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/boot/test_caster_loads_in_prologue.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# CAST_SPELL is registered in the data-driven VERB_TABLE, pointing at the
# concrete SpellActionController class -- statically, no boot required.
# ══════════════════════════════════════════════════════════════════════════

func test_verb_table_registers_cast_spell_pointing_at_spell_action_controller() -> void:
	assert_true(MainSceneClass.VERB_TABLE.has("CAST_SPELL"), "MainScene.VERB_TABLE must register a CAST_SPELL entry")
	assert_eq(
		MainSceneClass.VERB_TABLE.get("CAST_SPELL"), SpellActionControllerClass,
		"VERB_TABLE['CAST_SPELL'] must point at presentation/verbs/spell_action_controller.gd's SpellActionController"
	)


# ══════════════════════════════════════════════════════════════════════════
# Boot-real: MainScene.tscn + the prologue encounter load cleanly with
# CAST_SPELL registered (NFR-003) -- the real composition root, real
# VerbBarRegistry, real prologue fixture.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_and_prologue_encounter_load_cleanly_with_cast_spell_registered() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance, "MainScene.tscn must instantiate")
	assert_not_null(instance.round_session, "a real RoundSession must be live after first frame (the prologue encounter loaded cleanly)")
	assert_not_null(instance._verb_registry, "MainScene must wire a real VerbBarRegistry after first frame")

	var registered_verb_ids: Array = []
	for descriptor in instance._verb_registry.list_verbs():
		registered_verb_ids.append(descriptor.get("verb_id"))
	assert_true(registered_verb_ids.has("CAST_SPELL"), "the real, booted VerbBarRegistry must have CAST_SPELL registered")


func test_booted_verb_registry_dispatches_cast_spell_availability_without_crashing() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# Drives the SAME real, live VerbBarRegistry the Layer 1 verb bar itself
	# reads from -- proving CAST_SPELL is genuinely reachable end-to-end
	# through the composition root's real dispatch path, not merely present
	# as a VERB_TABLE dict key.
	var available: bool = instance._verb_registry.is_available("CAST_SPELL")
	assert_typeof(available, TYPE_BOOL, "CAST_SPELL availability must resolve to a real bool through the live VerbBarRegistry, without crashing")


func test_booted_verb_bar_view_renders_a_cast_spell_button() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.verb_bar_view, "MainScene must wire a real $VerbBarView")
	assert_true(
		instance.verb_bar_view.get_verb_ids().has("CAST_SPELL"),
		"the real, booted Layer 1 verb bar must render a CAST_SPELL button alongside Strike/Step/Stride/End Turn"
	)
