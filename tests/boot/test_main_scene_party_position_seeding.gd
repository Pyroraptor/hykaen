extends GutTest
## tests/boot/test_main_scene_party_position_seeding.gd — FEAT-005 (US-004;
## FR-004, ADR-003).
##
## Proves MainScene._ready()'s party-hex-position branching, added on top
## of FEAT-004's boot scenario/encounter resolution refactor:
##
##   - CurrentGameState.data.party_hex_positions EMPTY -> positions seeded
##     from the encounter-authored positions (new-game path, unchanged from
##     pre-refactor behaviour).
##   - CurrentGameState.data.party_hex_positions NON-EMPTY -> positions
##     seeded from CurrentGameState.data (loaded-save path).
##   - The Dripping Cave scenario boots through the SAME generic code path
##     (no scenario-specific branching in MainScene.gd).
##   - A party_hex_positions entry referencing a combatant_id absent from
##     the live encounter logs a push_warning() and is skipped rather than
##     crashing boot.
##
## Mirrors tests/boot/test_main_scene_boot_characterization.gd's established
## fixture-isolation convention (reset the REAL CurrentGameState autoload's
## `data` field in before_each()/after_each()) and its push_error/push_warning
## capture note: GUT's assert_push_warning_count()/assert_push_error_count()
## rely on OS.add_logger(), a Godot 4.4+ API that is a documented no-op on
## this project's pinned Godot 4.3 engine, so the push_warning "exactly
## fires, doesn't crash" contract is proven via source-inspection (the exact
## call site exists) plus the OBSERVABLE behavioural contract (boot
## completes, well-formed entries still apply, malformed entry skipped)
## rather than runtime signal capture.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_main_scene_boot_characterization.gd's identically
## -named/valued constant).
const PROLOGUE_SEED: int = 42

const PROLOGUE_SCENARIO_PATH: String = "res://data/scenarios/prologue_scenario.tres"
const DRIPPING_CAVE_SCENARIO_PATH: String = "res://data/scenarios/dripping_cave_scenario.tres"


# ══════════════════════════════════════════════════════════════════════════
# Fixture isolation — mirrors test_main_scene_boot_characterization.gd:
# every test starts (and ends) with the REAL CurrentGameState autoload's
# `data` reset to a fresh, never-initialized GameStateData.
# ══════════════════════════════════════════════════════════════════════════

func before_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func after_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _read_main_scene_source() -> String:
	var file := FileAccess.open("res://MainScene.gd", FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable")
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func _find_party_member(instance, combatant_id: String):
	for combatant in instance._party:
		if combatant.display_id() == combatant_id:
			return combatant
	return null


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — party_hex_positions EMPTY: encounter-authored positions,
# unchanged from pre-refactor behaviour (mirrors the prologue's authored
# Titus (0,0) / Marigold (-1,0) fixture positions, data/encounters/
# prologue_encounter.tres).
# ══════════════════════════════════════════════════════════════════════════

func test_empty_party_hex_positions_seeds_from_encounter_authored_positions() -> void:
	assert_true(
		CurrentGameState.data.party_hex_positions.is_empty(),
		"fixture precondition: party_hex_positions must start empty (before_each())"
	)

	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _find_party_member(instance, "player_0")
	assert_not_null(titus, "player_0 (Titus) must be present in _party")
	if titus != null:
		assert_eq(titus.hex_coord.q, 0, "Titus must be seeded at his authored start hex q=0 (encounter-authored, unchanged)")
		assert_eq(titus.hex_coord.r, 0, "Titus must be seeded at his authored start hex r=0 (encounter-authored, unchanged)")

	var marigold = _find_party_member(instance, "player_1")
	assert_not_null(marigold, "player_1 (Marigold) must be present in _party")
	if marigold != null:
		assert_eq(marigold.hex_coord.q, -1, "Marigold must be seeded at her authored start hex q=-1 (encounter-authored, unchanged)")
		assert_eq(marigold.hex_coord.r, 0, "Marigold must be seeded at her authored start hex r=0 (encounter-authored, unchanged)")

	assert_push_error_count(0, "the new-game (empty party_hex_positions) boot path must not log any push_error()")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — party_hex_positions NON-EMPTY: seeded from
# CurrentGameState.data (loaded-save path) rather than the encounter's own
# authored positions.
# ══════════════════════════════════════════════════════════════════════════

func test_non_empty_party_hex_positions_seeds_from_current_game_state() -> void:
	CurrentGameState.data.scenario_path = PROLOGUE_SCENARIO_PATH
	CurrentGameState.data.party_hex_positions = [
		{"combatant_id": "player_0", "q": 5, "r": -3},
		{"combatant_id": "player_1", "q": 2, "r": 2},
	]

	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _find_party_member(instance, "player_0")
	assert_not_null(titus, "player_0 (Titus) must be present in _party")
	if titus != null:
		assert_eq(titus.hex_coord.q, 5, "Titus' hex_coord.q must come from CurrentGameState.data, not the encounter-authored q=0")
		assert_eq(titus.hex_coord.r, -3, "Titus' hex_coord.r must come from CurrentGameState.data, not the encounter-authored r=0")

	var marigold = _find_party_member(instance, "player_1")
	assert_not_null(marigold, "player_1 (Marigold) must be present in _party")
	if marigold != null:
		assert_eq(marigold.hex_coord.q, 2, "Marigold's hex_coord.q must come from CurrentGameState.data, not the encounter-authored q=-1")
		assert_eq(marigold.hex_coord.r, 2, "Marigold's hex_coord.r must come from CurrentGameState.data, not the encounter-authored r=0")

	# The rendered HexGridView tokens must reflect the same loaded-save
	# positions (the seeding must happen BEFORE hex_grid_view.load_combatants()).
	assert_not_null(instance.hex_grid_view, "MainScene must wire a real $HexGridView")
	if instance.hex_grid_view != null:
		var titus_token = instance.hex_grid_view.get_token(titus.combatant_id) if titus != null else null
		assert_not_null(titus_token, "Titus' token must be rendered on HexGridView")

	assert_push_error_count(0, "the loaded-save (non-empty party_hex_positions) boot path must not log any push_error()")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — the Dripping Cave scenario boots through the SAME generic
# code path with no scenario-specific branching in MainScene.gd.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_source_contains_no_scenario_specific_branching() -> void:
	var content: String = _read_main_scene_source()
	assert_false(
		content.contains("dripping_cave"),
		"MainScene.gd must contain no scenario-specific branching for the Dripping Cave scenario (FEAT-005) -- " +
		"boot must reach cave content through the SAME generic CurrentGameState.data-driven code path as any other scenario"
	)
	assert_false(
		content.contains("if scenario_path ==") or content.contains("if scenario_id =="),
		"MainScene.gd's boot/party-position seeding must not branch on scenario_path/scenario_id at all"
	)


func test_dripping_cave_scenario_boots_via_generic_code_path_with_terrain_and_passability() -> void:
	CurrentGameState.data.scenario_path = DRIPPING_CAVE_SCENARIO_PATH
	# party_hex_positions left empty -- exercises the SAME "new game" branch
	# as the prologue, just against a different scenario_path, proving the
	# branching genuinely depends only on the SHAPE of CurrentGameState.data,
	# never on which scenario is booting.

	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.scenario_session, "MainScene must construct a real scenario_session for the Dripping Cave scenario")
	assert_not_null(instance.scenario_session.scenario, "scenario_session.scenario must be populated from the committed dripping_cave_scenario.tres")
	assert_eq(
		instance.scenario_session.scenario.scenario_id, "dripping_cave",
		"the booted scenario must be the committed dripping_cave scenario"
	)

	assert_not_null(instance.exploration_controller, "MainScene must construct a real exploration_controller")

	# Cave-specific terrain/passability is reached through the SAME generic
	# EncounterTileAdapter-backed pathfinding query wiring
	# (presentation/exploration_mode_controller.gd's boot(), exposed via its
	# own get_is_passable_fn()/get_move_cost_fn() test/inspection helpers --
	# MainScene's own `exploration_controller` property delegates to the
	# INNER domain ExplorationController, not this presentation-layer
	# controller, so this reaches the SAME `_exploration` field MainScene's
	# own _ready()/_on_combat_triggered() use throughout) as any other
	# scenario -- exercised here against data/encounters/dripping_cave.tres's
	# own authored tiles: (1,1) is rubble/difficult (passable, cost 2.0),
	# (0,5) is a wall (impassable).
	var is_passable_fn: Callable = instance._exploration.get_is_passable_fn()
	var move_cost_fn: Callable = instance._exploration.get_move_cost_fn()
	assert_true(is_passable_fn.is_valid(), "exploration_controller must have a real is_passable Callable wired from the cave encounter")
	assert_true(move_cost_fn.is_valid(), "exploration_controller must have a real move_cost Callable wired from the cave encounter")

	var rubble_hex := HexCoordClass.new(1, 1)
	assert_true(is_passable_fn.call(rubble_hex), "the cave's rubble tile (1,1) is authored passable=true")
	assert_eq(move_cost_fn.call(rubble_hex), 2.0, "the cave's rubble tile (1,1) is authored difficult=true -- move cost 2.0")

	var wall_hex := HexCoordClass.new(0, 5)
	assert_false(is_passable_fn.call(wall_hex), "the cave's wall tile (0,5) is authored passable=false")

	assert_push_error_count(0, "booting the Dripping Cave scenario must not log any push_error()")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — a party_hex_positions entry referencing a combatant_id
# absent from the live encounter logs a push_warning() and is skipped
# rather than crashing boot.
# ══════════════════════════════════════════════════════════════════════════

func test_unknown_combatant_id_entry_is_skipped_with_push_warning_not_a_crash() -> void:
	CurrentGameState.data.scenario_path = PROLOGUE_SCENARIO_PATH
	CurrentGameState.data.party_hex_positions = [
		{"combatant_id": "player_0", "q": 5, "r": -3},
		{"combatant_id": "ghost_combatant_not_in_encounter", "q": 9, "r": 9},
	]

	var instance = _boot_main_scene()
	await get_tree().process_frame

	# Boot must not crash: MainScene must still reach EXPLORATION with the
	# full, correct party.
	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"boot must reach GameMode.EXPLORATION even when a party_hex_positions entry references an unknown combatant_id"
	)
	assert_eq(instance._party.size(), 2, "the known-good party members must still be built despite the unknown-combatant_id entry")

	# The well-formed entry must still have applied.
	var titus = _find_party_member(instance, "player_0")
	assert_not_null(titus, "player_0 (Titus) must still be present in _party")
	if titus != null:
		assert_eq(titus.hex_coord.q, 5, "the well-formed player_0 entry must still apply despite the OTHER entry being unknown")
		assert_eq(titus.hex_coord.r, -3, "the well-formed player_0 entry must still apply despite the OTHER entry being unknown")

	# No combatant named after the unknown id was fabricated.
	var ghost = _find_party_member(instance, "ghost_combatant_not_in_encounter")
	assert_null(ghost, "an unknown combatant_id must never fabricate a phantom party member")


func test_main_scene_source_contains_unknown_combatant_id_push_warning() -> void:
	var content: String = _read_main_scene_source()
	assert_true(
		content.contains("push_warning(") and content.contains("not present in the live encounter"),
		"MainScene.gd must push_warning() when a party_hex_positions entry references a combatant_id absent from the live encounter (FEAT-005, fail-closed)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Unit-level seam proof: _seed_party_hex_positions_from_current_game_state()
# in isolation (finer-grained than the full-boot tests above, so a failure
# here points directly at the seam rather than anywhere else in _ready()).
# ══════════════════════════════════════════════════════════════════════════

class _FakeHexCombatant:
	extends RefCounted
	var combatant_id: String
	var hex_coord

	func _init(p_combatant_id: String, p_hex_coord) -> void:
		combatant_id = p_combatant_id
		hex_coord = p_hex_coord

	func move_to(new_hex_coord) -> void:
		hex_coord = new_hex_coord


func test_seed_seam_is_a_noop_when_current_game_state_party_hex_positions_is_empty() -> void:
	CurrentGameState.data = GameStateDataClass.new()

	var hex_combatants: Array = [_FakeHexCombatant.new("player_0", HexCoordClass.new(0, 0))]

	var instance := MainSceneClass.new()
	instance._seed_party_hex_positions_from_current_game_state(hex_combatants)
	autofree(instance)

	assert_eq(hex_combatants[0].hex_coord.q, 0, "empty party_hex_positions must leave the encounter-authored hex_coord untouched")
	assert_eq(hex_combatants[0].hex_coord.r, 0, "empty party_hex_positions must leave the encounter-authored hex_coord untouched")


func test_seed_seam_overrides_hex_combatants_from_current_game_state() -> void:
	CurrentGameState.data = GameStateDataClass.new()
	CurrentGameState.data.party_hex_positions = [{"combatant_id": "player_0", "q": 7, "r": -2}]

	var hex_combatants: Array = [_FakeHexCombatant.new("player_0", HexCoordClass.new(0, 0))]

	var instance := MainSceneClass.new()
	instance._seed_party_hex_positions_from_current_game_state(hex_combatants)
	autofree(instance)

	assert_eq(hex_combatants[0].hex_coord.q, 7, "non-empty party_hex_positions must override the encounter-authored hex_coord.q")
	assert_eq(hex_combatants[0].hex_coord.r, -2, "non-empty party_hex_positions must override the encounter-authored hex_coord.r")


func test_seed_seam_skips_unknown_combatant_id_without_crashing() -> void:
	CurrentGameState.data = GameStateDataClass.new()
	CurrentGameState.data.party_hex_positions = [{"combatant_id": "unknown_ghost", "q": 3, "r": 3}]

	var hex_combatants: Array = [_FakeHexCombatant.new("player_0", HexCoordClass.new(0, 0))]

	var instance := MainSceneClass.new()
	instance._seed_party_hex_positions_from_current_game_state(hex_combatants)
	autofree(instance)

	assert_eq(hex_combatants[0].hex_coord.q, 0, "an entry referencing an unknown combatant_id must never mutate an unrelated combatant's hex_coord")
	assert_eq(hex_combatants[0].hex_coord.r, 0, "an entry referencing an unknown combatant_id must never mutate an unrelated combatant's hex_coord")
