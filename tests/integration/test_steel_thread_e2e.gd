extends GutTest
## tests/integration/test_steel_thread_e2e.gd — FEAT-010 (US-001..US-007;
## the current iteration's game-state/save-load steel-thread capstone).
##
## Exercises the COMPLETE steel thread against the real, running application
## stack, entry_point -> exit_point:
##
##   Title Screen "New Game" -> MainScene boots the seeded prologue
##   party/encounter from CurrentGameState.data -> combat is driven to a win
##   -> _on_combat_won() auto-saves to user://saves/slot_0.json -> the scene
##   tree is freed and a FRESH TitleScreen is instantiated (simulated
##   quit/relaunch) -> "Continue" -> MainScene reloads the EXACT saved state:
##   the party renders at its post-combat-win hex positions and the won
##   encounter is recorded complete, matching what was actually persisted to
##   disk.
##
## NO mocked persistence and NO mocked scene instantiation anywhere in this
## file: res://scenes/TitleScreen.tscn and res://MainScene.tscn are both
## loaded via ResourceLoader.load()/instantiate() exactly as the real engine
## would at runtime (mirrors this codebase's own established
## `_instantiate_title_screen()` / `_boot_main_scene()` conventions from
## tests/unit/test_title_screen_buttons.gd and
## tests/integration/test_auto_save_on_combat_won.gd), combat is won by
## directly zeroing the real, live enemy Combatants' hp_current then
## pressing the real $EndTurnControl (the SAME "force a deterministic win
## through the real round/turn flow" convention every other boot-real suite
## in this codebase already uses — never a stubbed CombatSession/RoundSession),
## and save/load IO goes to the real user://saves/slot_0.json file on disk.
##
## `transition_override` is TitleScreen's own documented test seam for
## observing/recording a requested scene transition WITHOUT tearing down the
## live GUT test tree (a real change_scene_to_file() call would destroy the
## running test runner's own scene) — using it here does not mock anything
## about persistence or MainScene itself; MainScene is still always a real,
## separately-instantiated res://MainScene.tscn PackedScene.
##
## Because CurrentGameState is a live, single, process-wide autoload
## singleton (not something a real quit/relaunch would preserve in memory,
## but persistent for the lifetime of THIS test process), "relaunch" is
## simulated by explicitly wiping CurrentGameState.data back to a fresh,
## empty GameStateData immediately before instantiating the second
## TitleScreen — so Continue's subsequent behavior can only be explained by
## a genuine load_from_slot(0) reading the just-written slot_0.json off
## disk, never leftover in-memory state (mirrors tests/integration/
## test_auto_save_on_combat_won.gd's own "simulate a fresh process" step).
##
## test_criteria satisfied by this file:
##   1. Real TitleScreen.tscn is instantiated, New Game is pressed, and a
##      real MainScene.tscn instance boots the seeded prologue
##      party/encounter rendered from CurrentGameState.data.
##   2. Combat is driven to a win condition through the real
##      CombatSession/MainScene flow (no combat mocks); _on_combat_won()
##      fires and user://saves/slot_0.json is written to the real
##      filesystem.
##   3. The scene tree is freed and a fresh TitleScreen.tscn is
##      instantiated (simulating quit/relaunch); Continue is enabled
##      because has_save(0) is true.
##   4. Continue is pressed; a fresh MainScene boots and renders the party
##      at the exact post-combat-win hex positions, with the encounter
##      marked complete — matching the values persisted in slot_0.json.
##   5. The full run touches real filesystem save IO, real scene-tree
##      instantiation, and a real GameStateData round-trip end to end.

const MainSceneClass = preload("res://MainScene.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const TITLE_SCREEN_PATH: String = "res://scenes/TitleScreen.tscn"
const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/integration/test_auto_save_on_combat_won.gd's identically-
## valued constant).
const PROLOGUE_SEED: int = 42

const PROLOGUE_ENCOUNTER_ID: String = "prologue"

const SAVES_DIR: String = "user://saves"
const SLOT_0_PATH: String = "user://saves/slot_0.json"


# ══════════════════════════════════════════════════════════════════════════
# Fixture isolation — mirrors tests/integration/test_auto_save_on_combat_won.gd
# / tests/unit/test_title_screen_buttons.gd's established cleanup convention.
# ══════════════════════════════════════════════════════════════════════════

func _cleanup_fixtures() -> void:
	CurrentGameState.data = GameStateDataClass.new()
	if DirAccess.dir_exists_absolute(SAVES_DIR):
		var dir := DirAccess.open(SAVES_DIR)
		if dir != null:
			for entry_name in ["slot_0.json", "slot_0.json.tmp"]:
				if dir.file_exists(entry_name):
					dir.remove(entry_name)


func before_each() -> void:
	_cleanup_fixtures()


func after_each() -> void:
	_cleanup_fixtures()


func _instantiate_title_screen():
	var packed: PackedScene = ResourceLoader.load(TITLE_SCREEN_PATH)
	assert_not_null(packed, "res://scenes/TitleScreen.tscn (the project's real title/entry scene) must load as a PackedScene")
	var instance = packed.instantiate()
	add_child_autofree(instance)
	return instance


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "res://MainScene.tscn (the project's real composition root) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


## _force_win(instance) -> void — mirrors tests/integration/
## test_auto_save_on_combat_won.gd's identically-named helper: zeroes every
## live enemy Combatant's hp_current then ends the current actor's turn,
## deterministically resolving the round as "won" through the REAL
## RoundSession/TurnController flow, regardless of seed-specific attack-roll
## outcomes. This is not a combat mock — every collaborator driven here
## (round_session, turn_controller, end_turn_control) is the real,
## production instance MainScene.gd's own composition root wires.
func _force_win(instance) -> void:
	for enemy in instance._enemies:
		enemy.hp_current = 0
	instance.end_turn_control.press()


func _read_slot_0_json() -> Dictionary:
	var file := FileAccess.open(SLOT_0_PATH, FileAccess.READ)
	assert_not_null(file, "user://saves/slot_0.json must exist and be readable")
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parser := JSON.new()
	assert_eq(parser.parse(text), OK, "slot_0.json must be valid JSON")
	var parsed = parser.get_data()
	assert_true(typeof(parsed) == TYPE_DICTIONARY, "slot_0.json root must be an object")
	return parsed


# ══════════════════════════════════════════════════════════════════════════
# The full steel thread, entry_point -> exit_point, in one continuous,
# real-application-stack run.
# ══════════════════════════════════════════════════════════════════════════

func test_title_screen_new_game_win_combat_relaunch_continue_reloads_exact_saved_state() -> void:
	# ── Criterion 1: Title Screen -> New Game -> MainScene boots seeded
	# prologue party/encounter from CurrentGameState.data. ───────────────────
	var title_a = _instantiate_title_screen()
	var transitions_a: Array = []
	title_a.transition_override = func(path): transitions_a.append(path)

	title_a.press_new_game()

	assert_eq(
		transitions_a, [MAIN_SCENE_PATH],
		"New Game must request exactly one transition, to the real MainScene.tscn"
	)
	assert_eq(
		CurrentGameState.data.scenario_path, NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
		"New Game must seed CurrentGameState.data via NewGameFactory.create_prologue_state()"
	)
	assert_false(
		CurrentGameState.data.party_hex_positions.is_empty(),
		"New Game's seeded state must carry a non-empty prologue party_hex_positions"
	)

	# Simulate the requested scene transition: a real MainScene.tscn instance
	# boots directly from the CurrentGameState.data New Game just seeded.
	var main_a = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(main_a.scenario_session, "MainScene must resolve a live scenario_session at boot")
	assert_not_null(main_a.encounter, "MainScene must resolve a live encounter at boot")
	assert_eq(
		main_a.scenario_session.scenario.scenario_id, "prologue",
		"MainScene must boot the prologue scenario seeded by New Game (entry_point)"
	)
	assert_true(main_a._party.size() > 0, "MainScene must render a non-empty seeded prologue party")

	var seeded_ids: Dictionary = {}
	for entry in CurrentGameState.data.party_hex_positions:
		seeded_ids[String(entry.get("combatant_id", ""))] = true
	for combatant in main_a._party:
		assert_true(
			seeded_ids.has(combatant.display_id()),
			"every rendered party member must correspond to a combatant_id seeded from CurrentGameState.data (%s missing)" % combatant.display_id()
		)

	# ── Criterion 2: combat is driven to a win through the real
	# CombatSession/MainScene flow; _on_combat_won() fires and
	# user://saves/slot_0.json is written to the real filesystem. ───────────
	assert_false(FileAccess.file_exists(SLOT_0_PATH), "fixture precondition: no save file must exist before winning combat")

	main_a._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(main_a._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: the real exploration->combat handoff must succeed")
	assert_true(main_a._enemies.size() > 0, "fixture assumption: the prologue encounter must seed at least one live enemy")

	# Move a party member to a hex distinct from their pre-combat spawn (as if
	# by a real Stride mid-combat), so the reload assertions below can prove
	# the reload genuinely reflects post-combat-win state rather than
	# coincidentally matching the encounter-authored spawn position.
	assert_true(main_a._party.size() > 0, "fixture assumption: the prologue encounter has at least one party member")
	var moved_member = main_a._party[0]
	var pre_combat_hex := HexCoordClass.new(moved_member.hex_coord.q, moved_member.hex_coord.r)
	var post_combat_hex := HexCoordClass.new(pre_combat_hex.q + 3, pre_combat_hex.r - 2)
	moved_member.move_to(post_combat_hex)
	var moved_member_id: String = moved_member.combatant_id

	watch_signals(CurrentGameState)
	_force_win(main_a)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(main_a._game_mode, MainSceneClass.GameMode.EXPLORATION, "winning combat must return MainScene to EXPLORATION (_on_combat_won fired)")
	assert_signal_emit_count(CurrentGameState, "save_succeeded", 1, "winning combat must trigger exactly one successful auto-save")
	assert_true(FileAccess.file_exists(SLOT_0_PATH), "winning combat must write user://saves/slot_0.json to the real filesystem")
	assert_true(
		main_a.scenario_session.completed_encounter_ids.has(PROLOGUE_ENCOUNTER_ID),
		"the original instance's ScenarioSession must mark the just-won encounter complete"
	)

	var persisted: Dictionary = _read_slot_0_json()
	assert_eq(
		persisted.get("scenario_path", ""), NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
		"the saved slot must carry the booted scenario_path"
	)
	assert_true(
		(persisted.get("completed_encounter_ids", []) as Array).has(PROLOGUE_ENCOUNTER_ID),
		"the saved slot's completed_encounter_ids must include the just-won encounter_id"
	)
	var persisted_moved_position = null
	for pos_entry in persisted.get("party_hex_positions", []):
		if String(pos_entry.get("combatant_id", "")) == moved_member_id:
			persisted_moved_position = pos_entry
			break
	assert_not_null(persisted_moved_position, "slot_0.json's party_hex_positions must include the moved party member")
	if persisted_moved_position != null:
		assert_eq(int(persisted_moved_position["q"]), post_combat_hex.q, "slot_0.json must persist the post-combat-win hex.q, not the pre-combat spawn")
		assert_eq(int(persisted_moved_position["r"]), post_combat_hex.r, "slot_0.json must persist the post-combat-win hex.r, not the pre-combat spawn")

	# ── Criterion 3: the scene tree is freed and a fresh TitleScreen.tscn is
	# instantiated (simulating quit/relaunch); Continue is enabled because
	# has_save(0) is true. ────────────────────────────────────────────────────
	main_a.free()
	title_a.free()

	# Simulate a fresh process: only the real, on-disk slot_0.json written
	# above may explain anything observed from this point on.
	CurrentGameState.data = GameStateDataClass.new()

	var title_b = _instantiate_title_screen()

	assert_true(CurrentGameState.has_save(0), "has_save(0) must be true after the real on-disk save")
	assert_true(title_b.is_continue_enabled(), "the freshly-instantiated TitleScreen's Continue button must be enabled because has_save(0) is true")

	# ── Criterion 4: Continue is pressed; MainScene boots and renders the
	# party at the exact post-combat-win hex positions with the encounter
	# marked complete, matching the values persisted in slot_0.json. ────────
	var transitions_b: Array = []
	title_b.transition_override = func(path): transitions_b.append(path)

	title_b.press_continue()

	assert_eq(
		CurrentGameState.data.scenario_path, NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
		"Continue must call load_from_slot(0), restoring the saved scenario_path"
	)
	assert_true(
		CurrentGameState.data.completed_encounter_ids.has(PROLOGUE_ENCOUNTER_ID),
		"Continue's reloaded CurrentGameState.data must mark the encounter complete, matching slot_0.json"
	)
	assert_eq(
		transitions_b, [MAIN_SCENE_PATH],
		"Continue must request exactly one transition, to the real MainScene.tscn, after a successful load"
	)

	title_b.free()

	var main_b = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(
		main_b.scenario_session.scenario.scenario_id, "prologue",
		"the relaunched-and-continued MainScene must resolve the SAME saved prologue scenario (exit_point)"
	)

	var reloaded_member = null
	for combatant in main_b._party:
		if combatant.display_id() == moved_member_id:
			reloaded_member = combatant
			break

	assert_not_null(reloaded_member, "the moved party member must still be present in the freshly relaunched-and-continued MainScene")
	if reloaded_member != null:
		assert_eq(
			reloaded_member.hex_coord.q, post_combat_hex.q,
			"the relaunched-and-continued party member must render at the post-combat-win hex.q, not the pre-combat spawn (exit_point)"
		)
		assert_eq(
			reloaded_member.hex_coord.r, post_combat_hex.r,
			"the relaunched-and-continued party member must render at the post-combat-win hex.r, not the pre-combat spawn (exit_point)"
		)
		assert_false(
			reloaded_member.hex_coord.q == pre_combat_hex.q and reloaded_member.hex_coord.r == pre_combat_hex.r,
			"fixture sanity: the reloaded hex must differ from the pre-combat spawn hex, proving the round-trip actually mattered"
		)

	# ── Criterion 5 (whole-file proof): real filesystem save IO, real
	# scene-tree instantiation, and a real GameStateData round-trip were used
	# throughout — re-asserted here as a single, explicit closing statement. ─
	assert_true(FileAccess.file_exists(SLOT_0_PATH), "the real save file must still exist on the real filesystem at the end of this run")
	assert_is(CurrentGameState.data, GameStateDataClass, "the final, reloaded live state must be a real GameStateData instance (no mocked persistence)")
