extends GutTest
## tests/gut/test_initiative_order_intuition_parity.gd
##
## GUT integration test for FEAT-202 (US-008): confirms the FEAT-201/FIX-001
## intuition-field-source fix actually closes the sim/game divergence risk at
## the point it matters — initiative rolling in core/combat/encounter.gd
## (initiative = d20 + intuition + dexterity, ADR-006).
##
## Prior to FIX-001, MainScene._build_enemy_combatant() and
## core/sim/simulator.gd's _build_skeleton_combatant() could read/hardcode
## DIFFERENT intuition values for the same skeleton.tres enemy. Even though
## tests/gut/test_intuition_defense_source_parity.gd already pins the raw
## `intuition` field each builder produces, this test proves the bug's actual
## DOWNSTREAM GAMEPLAY EFFECT — silently wrong turn order — is fixed, by
## feeding both builders' output through the real initiative calculation
## under an IDENTICAL pinned die roll and asserting identical resulting
## initiative scores.
##
## Test criteria covered:
##   1. Under a pinned die-roll seed, encounter.gd's initiative score for the
##      MainScene-built skeleton combatant equals the initiative score for
##      the Simulator-built skeleton combatant.
##   2. Fails if either build path reverts to a hardcoded intuition literal
##      (regression guard) — a reverted literal that diverges from
##      skeleton.tres' authored value desyncs the two initiative scores;
##      a source-level literal scan additionally guards the case where a
##      reintroduced literal happens to coincidentally match.
##   3. Computed initiative equals d20_roll + 1 (intuition) + dexterity for
##      skeleton.tres' authored values, confirming the formula consumes the
##      corrected field (not just that the two paths agree with each other).

const MainSceneClass = preload("res://MainScene.gd")
const SimulatorClass = preload("res://core/sim/simulator.gd")
const EncounterClass = preload("res://core/combat/encounter.gd")

const SKELETON_TRES_PATH := "res://data/enemies/skeleton.tres"

## Pinned d20 roll used for BOTH encounters below — any divergence in the
## resulting initiative score can only come from a difference in the
## combatants' intuition/dexterity fields, never from RNG variance.
const PINNED_D20_ROLL := 15

## Attribute name mapping mirrored from core/sim/simulator.gd's own
## SKELETON_ATTR_MAP local constant (EnemyResource uses compact keys).
const _SKELETON_ATTR_MAP: Dictionary = {"str": "strength", "dex": "dexterity"}


## FixedRollRng — a minimal duck-typed stand-in for core/rules/rng.gd (RNG).
## Encounter.initialize() calls `_rng.d20()` directly (not through a Port),
## so this fixture only needs to implement d20() to pin the initiative roll
## deterministically, independent of any real RandomNumberGenerator seed.
class FixedRollRng:
	var _value: int

	func _init(value: int) -> void:
		_value = value

	func d20() -> int:
		return _value


var _main_scene = null


func before_each() -> void:
	_main_scene = MainSceneClass.new()


func after_each() -> void:
	if _main_scene != null:
		_main_scene.free()
	_main_scene = null


func _skeleton_weapon_attribute(skeleton_res) -> String:
	var raw_attribute: String = skeleton_res.weapon.get("attribute", "strength")
	return _SKELETON_ATTR_MAP.get(raw_attribute, raw_attribute)


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1 & 3: pinned-seed initiative parity between the MainScene- and
# Simulator-built skeleton combatants, and equality against the explicit
# d20 + intuition + dexterity formula for skeleton.tres' authored values.
# ══════════════════════════════════════════════════════════════════════════

func test_initiative_score_matches_between_mainscene_and_simulator_skeleton_builds() -> void:
	var skeleton_res = ResourceLoader.load(SKELETON_TRES_PATH)
	var sim = SimulatorClass.new()

	var game_combatant: Dictionary = _main_scene._build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")
	var sim_combatant: Dictionary = sim._build_skeleton_combatant(skeleton_res, _skeleton_weapon_attribute(skeleton_res))

	var game_encounter = EncounterClass.new([game_combatant], [], FixedRollRng.new(PINNED_D20_ROLL))
	var sim_encounter = EncounterClass.new([sim_combatant], [], FixedRollRng.new(PINNED_D20_ROLL))

	game_encounter.initialize()
	sim_encounter.initialize()

	var game_turn_order: Array = game_encounter.get_turn_order()
	var sim_turn_order: Array = sim_encounter.get_turn_order()

	assert_eq(game_turn_order.size(), 1, "sanity: single-combatant MainScene turn order")
	assert_eq(sim_turn_order.size(), 1, "sanity: single-combatant Simulator turn order")
	if game_turn_order.size() != 1 or sim_turn_order.size() != 1:
		return

	var game_initiative: int = game_turn_order[0].get("_initiative_roll", -1)
	var sim_initiative: int = sim_turn_order[0].get("_initiative_roll", -2)

	assert_eq(
		game_initiative, sim_initiative,
		"encounter.gd initiative score must be IDENTICAL for MainScene- and Simulator-built skeleton combatants under the same pinned d20 roll; game=%s sim=%s" % [str(game_initiative), str(sim_initiative)]
	)

	# Criterion 3: the formula must actually consume the corrected intuition
	# field — d20_roll + intuition(1) + dexterity, per skeleton.tres.
	var expected_initiative: int = PINNED_D20_ROLL + skeleton_res.intuition + skeleton_res.dex
	assert_eq(skeleton_res.intuition, 1, "sanity: skeleton.tres authors intuition=1")

	assert_eq(
		game_initiative, expected_initiative,
		"MainScene-path initiative must equal d20_roll + intuition + dexterity for skeleton.tres' authored values"
	)
	assert_eq(
		sim_initiative, expected_initiative,
		"Simulator-path initiative must equal d20_roll + intuition + dexterity for skeleton.tres' authored values"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (regression guard): even a reintroduced hardcoded intuition
# literal that happens to numerically match skeleton.tres' authored value
# would defeat the parity assertions above by coincidence — so also assert,
# at the source level, that neither builder contains a hardcoded
# `"intuition": <int>` literal. Mirrors
# tests/gut/test_intuition_defense_source_parity.gd's scan exactly, scoped
# to this initiative-propagation test file so this file's own regression
# guarantee does not implicitly depend on another test file continuing to
# exist.
# ══════════════════════════════════════════════════════════════════════════

func test_no_hardcoded_intuition_literal_remains_in_either_builder() -> void:
	# CombatantFactory de-bloat (2026-07-10): _build_enemy_combatant()'s body was
	# extracted from MainScene.gd into infrastructure/combatant_factory.gd
	# (MainScene now delegates via a shim). This source-level guard follows the
	# code to its new home; the behavioral parity criteria above still exercise
	# the real MainScene._build_enemy_combatant() call path unchanged.
	var enemy_builder_src := FileAccess.get_file_as_string("res://infrastructure/combatant_factory.gd")
	var simulator_src := FileAccess.get_file_as_string("res://core/sim/simulator.gd")

	var enemy_builder_body := _extract_function_body(enemy_builder_src, "func build_enemy_combatant(")
	var simulator_body := _extract_function_body(simulator_src, "func _build_skeleton_combatant(")

	assert_false(
		_has_literal_intuition_assignment(enemy_builder_body),
		"CombatantFactory.build_enemy_combatant() must not contain a hardcoded \"intuition\": <int> literal"
	)
	assert_false(
		_has_literal_intuition_assignment(simulator_body),
		"Simulator._build_skeleton_combatant() must not contain a hardcoded \"intuition\": <int> literal"
	)

	assert_true(enemy_builder_body.find("intuition") != -1, "sanity: CombatantFactory.build_enemy_combatant() must still set intuition somehow")
	assert_true(simulator_body.find("intuition") != -1, "sanity: _build_skeleton_combatant() must still set intuition somehow")


## _extract_function_body(source, func_signature_prefix) -> String — grabs the
## text from the given `func ...(` declaration up to (but not including) the
## next top-level `func ` declaration, so the grep-level literal check below
## is scoped to just that one function, not the whole file.
func _extract_function_body(source: String, func_signature_prefix: String) -> String:
	var start: int = source.find(func_signature_prefix)
	if start == -1:
		return ""
	var next_func: int = source.find("\nfunc ", start + func_signature_prefix.length())
	if next_func == -1:
		return source.substr(start)
	return source.substr(start, next_func - start)


## _has_literal_intuition_assignment(body) -> bool — true if `body` contains a
## `"intuition":` key immediately followed by an integer literal (optionally
## whitespace-padded), e.g. `"intuition":  0,` or `"intuition": 1`. A
## field-read expression like `enemy.intuition` or `skeleton_res.intuition`
## does NOT match this pattern.
func _has_literal_intuition_assignment(body: String) -> bool:
	var regex := RegEx.new()
	regex.compile("\"intuition\"\\s*:\\s*-?\\d+")
	return regex.search(body) != null
