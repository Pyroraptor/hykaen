extends GutTest
## tests/gut/test_intuition_defense_source_parity.gd
##
## GUT unit tests for FEAT-201 (US-008, ADR-106): MainScene's
## _build_enemy_combatant() and core/sim/simulator.gd's
## _build_skeleton_combatant() must both read the `intuition` attribute from
## the SAME EnemyResource source (data/enemies/skeleton.tres) — never an
## independently hard-coded literal. Prior to this fix, MainScene hardcoded
## intuition:0 and Simulator hardcoded intuition:1 (which happened to match
## skeleton.tres' authored value by coincidence, masking the bug). Since
## core/combat/encounter.gd computes initiative as d20+intuition+dexterity,
## an undetected divergence here would silently desync sim-validated balance
## from live-game initiative order — the exact class of defect ADR-106 was
## meant to close (previously only closed for ac/fortitude/reflex/will).
##
## Mirrors tests/unit/test_simulator_defense_source_parity.gd's fixture/
## pattern exactly, scoped to the `intuition` field.
##
## Test criteria covered:
##   1. MainScene._build_enemy_combatant() yields intuition == 1 for
##      skeleton.tres (not the old hardcoded 0).
##   2. Simulator._build_skeleton_combatant() yields intuition == 1 for
##      skeleton.tres (not the old hardcoded-but-coincidentally-correct 1).
##   3. Both consumers' intuition values are equal to each other AND to
##      skeleton_res.intuition directly (no divergence, no re-hardcoding).

const MainSceneClass = preload("res://MainScene.gd")
const SimulatorClass = preload("res://core/sim/simulator.gd")

const SKELETON_TRES_PATH := "res://data/enemies/skeleton.tres"

## Attribute name mapping mirrored from core/sim/simulator.gd's own
## SKELETON_ATTR_MAP local constant (EnemyResource uses compact keys).
const _SKELETON_ATTR_MAP: Dictionary = {"str": "strength", "dex": "dexterity"}

var _main_scene = null


func before_each() -> void:
	_main_scene = MainSceneClass.new()


func after_each() -> void:
	if _main_scene != null:
		_main_scene.free()
	_main_scene = null


func _skeleton_weapon_attribute(skeleton_res) -> String:
	## FEAT-002 (US-002, ADR-001/ADR-002): resolve via weapon_paths[0] ->
	## WeaponResource; damage_modifier_attribute is already canonical
	## long-form (e.g. "strength"), so no attribute-map translation remains.
	if skeleton_res.weapon_paths.is_empty():
		return "strength"
	var weapon_res = ResourceLoader.load(skeleton_res.weapon_paths[0])
	if weapon_res == null:
		return "strength"
	return weapon_res.damage_modifier_attribute


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: MainScene._build_enemy_combatant() reads intuition from the
# EnemyResource (skeleton.tres authors intuition=1), not a hardcoded 0.
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_build_enemy_combatant_intuition_matches_resource() -> void:
	var skeleton_res = ResourceLoader.load(SKELETON_TRES_PATH)
	var game_combatant: Dictionary = _main_scene._build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")

	assert_eq(
		game_combatant.get("intuition", -1), 1,
		"MainScene._build_enemy_combatant() must read intuition=1 off skeleton.tres, not a hardcoded 0"
	)
	assert_eq(
		game_combatant.get("intuition", -1), skeleton_res.intuition,
		"MainScene's intuition must equal skeleton_res.intuition directly (single source of truth)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: Simulator._build_skeleton_combatant() reads intuition from the
# EnemyResource (skeleton.tres authors intuition=1), not a hardcoded 1.
# ══════════════════════════════════════════════════════════════════════════

func test_simulator_build_skeleton_combatant_intuition_matches_resource() -> void:
	var skeleton_res = ResourceLoader.load(SKELETON_TRES_PATH)
	var sim = SimulatorClass.new()
	var sim_combatant: Dictionary = sim._build_skeleton_combatant(skeleton_res, _skeleton_weapon_attribute(skeleton_res))

	assert_eq(
		sim_combatant.get("intuition", -1), 1,
		"Simulator._build_skeleton_combatant() must read intuition=1 off skeleton.tres, not a hardcoded literal"
	)
	assert_eq(
		sim_combatant.get("intuition", -1), skeleton_res.intuition,
		"Simulator's intuition must equal skeleton_res.intuition directly (single source of truth)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: no divergence — MainScene and Simulator agree with each other
# AND with skeleton_res.intuition (sim/game parity, ADR-106).
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_and_simulator_agree_on_skeleton_intuition() -> void:
	var skeleton_res = ResourceLoader.load(SKELETON_TRES_PATH)
	var sim = SimulatorClass.new()
	var sim_combatant: Dictionary = sim._build_skeleton_combatant(skeleton_res, _skeleton_weapon_attribute(skeleton_res))
	var game_combatant: Dictionary = _main_scene._build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")

	assert_eq(
		sim_combatant.get("intuition", -1), game_combatant.get("intuition", -2),
		"Simulator and MainScene must agree on skeleton intuition; sim=%s game=%s" % [str(sim_combatant.get("intuition")), str(game_combatant.get("intuition"))]
	)
	assert_eq(sim_combatant.get("intuition", -1), skeleton_res.intuition)
	assert_eq(game_combatant.get("intuition", -1), skeleton_res.intuition)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (static/grep-level): no remaining literal `"intuition": <int>`
# assignment survives in either _build_enemy_combatant() or
# _build_skeleton_combatant() — guards against re-introducing the hardcoded
# literal even if it happens to match the resource's authored value.
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
