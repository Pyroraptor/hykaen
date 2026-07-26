extends GutTest
## tests/integration/test_auto_save_on_combat_won.gd — FEAT-007 (US-005;
## FR-005).
##
## Proves MainScene.gd's `_on_combat_won()` hooks the auto-save steel thread:
## CurrentGameState.snapshot_from_session() followed by
## CurrentGameState.save_to_slot(0), and ONLY from that call site.
##
## Mirrors this project's established boot-real conventions:
##   - tests/boot/test_post_combat_return_to_exploration.gd's `_boot_main_scene()`
##     / `_force_win()` (real res://MainScene.tscn, never a hand-wired double;
##     zero every live enemy Combatant's hp_current then press $EndTurnControl
##     to force a "won" round-over deterministically, independent of any
##     seed-specific critical hit).
##   - tests/boot/test_main_scene_party_position_seeding.gd's fixture-isolation
##     convention (reset the REAL CurrentGameState autoload's `data` field in
##     before_each()/after_each(), reached directly as the bare `CurrentGameState`
##     identifier -- this is a normal (non `--check-only`) GUT test run, so
##     autoload global-identifier resolution works fine here).
##   - tests/unit/test_current_game_state.gd's user://saves/slot_N.json fixture
##     cleanup convention (remove slot_0.json/.tmp before AND after every test
##     so ordering never matters).
##
## Test criteria covered (per FEAT-007 spec):
##   1. _on_combat_won() calls CurrentGameState.snapshot_from_session()
##      followed by save_to_slot(0) -- proven by source-order inspection
##      (mirrors test_main_scene_party_position_seeding.gd's own
##      "read MainScene.gd source, assert on its contents" precedent, used
##      throughout this codebase whenever GUT's push_warning/signal capture
##      APIs can't directly observe an internal call sequence).
##   2. A spy on the real CurrentGameState singleton (watch_signals(), since
##      GDScript has no method-spy facility) confirms save_succeeded/
##      save_failed are NEVER emitted during any round prior to combat being
##      won -- driven through a REAL undecided round via the established
##      "pass every party member's turn, let TurnController auto-drive the
##      enemy, decline any reaction prompt" loop
##      (tests/boot/test_post_combat_return_to_exploration.gd's own
##      `test_undecided_round_continuation_is_unaffected_by_this_feature`
##      convention) -- then forcing the win in the SAME test proves the very
##      next _on_combat_won() call IS the first save.
##   3. Winning combat writes user://saves/slot_0.json to disk with the
##      correct scenario_path and the won encounter_id present in
##      completed_encounter_ids (read directly off disk, independent of
##      CurrentGameState's own in-memory `data`).
##   4. load_from_slot(0) after that save, then booting a FRESH MainScene
##      instance from the loaded data, renders the party at their
##      post-combat-win hex positions (deliberately moved away from their
##      pre-combat encounter-authored spawn hex mid-combat, so this proves
##      _on_combat_won()'s scenario_session.party_hex_positions sync fix,
##      not merely that boot-time seeding already worked) -- and the
##      just-won encounter is marked complete in the ORIGINAL instance's
##      ScenarioSession.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_post_combat_return_to_exploration.gd's
## identically-valued constant).
const PROLOGUE_SEED: int = 42

const PROLOGUE_ENCOUNTER_ID: String = "prologue"
const PROLOGUE_SCENARIO_PATH: String = "res://data/scenarios/prologue_scenario.tres"

const SAVES_DIR: String = "user://saves"
const SLOT_0_PATH: String = "user://saves/slot_0.json"


# ══════════════════════════════════════════════════════════════════════════
# Fixture isolation
# ══════════════════════════════════════════════════════════════════════════

func _cleanup_fixtures() -> void:
	CurrentGameState.data = GameStateDataClass.new()
	if DirAccess.dir_exists_absolute(SAVES_DIR):
		var dir := DirAccess.open(SAVES_DIR)
		if dir != null:
			for name in ["slot_0.json", "slot_0.json.tmp"]:
				if dir.file_exists(name):
					dir.remove(name)


func before_each() -> void:
	_cleanup_fixtures()


func after_each() -> void:
	_cleanup_fixtures()


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _enter_combat(instance) -> void:
	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)


## _force_win(instance) -> void — mirrors
## tests/boot/test_post_combat_return_to_exploration.gd's identically-named
## helper: zeroes every live enemy Combatant's hp_current then ends the
## current actor's turn, deterministically resolving the round as "won"
## regardless of seed-specific attack-roll outcomes.
func _force_win(instance) -> void:
	for enemy in instance._enemies:
		enemy.hp_current = 0
	instance.end_turn_control.press()


func _read_main_scene_source() -> String:
	var file := FileAccess.open("res://MainScene.gd", FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable")
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


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
# Criterion 1 — source-order proof: snapshot_from_session() is called
# BEFORE save_to_slot() inside _on_combat_won()'s own body.
# ══════════════════════════════════════════════════════════════════════════

func test_on_combat_won_calls_snapshot_from_session_then_save_to_slot_in_order() -> void:
	var content: String = _read_main_scene_source()

	var body_start: int = content.find("func _on_combat_won()")
	assert_true(body_start >= 0, "MainScene.gd must define _on_combat_won()")
	var next_func: int = content.find("\nfunc ", body_start + 1)
	if next_func < 0:
		next_func = content.length()
	var body: String = content.substr(body_start, next_func - body_start)

	var snapshot_index: int = body.find("snapshot_from_session(")
	var save_index: int = body.find("save_to_slot(")

	assert_true(snapshot_index >= 0, "_on_combat_won() must call CurrentGameState.snapshot_from_session()")
	assert_true(save_index >= 0, "_on_combat_won() must call CurrentGameState.save_to_slot(0)")
	assert_true(
		snapshot_index < save_index,
		"_on_combat_won() must call snapshot_from_session() BEFORE save_to_slot() (this feature's own ordering contract)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — guard: no save fires during any round prior to combat won;
# winning combat is the first and only save.
# ══════════════════════════════════════════════════════════════════════════

func test_no_save_occurs_before_combat_is_won_then_winning_saves_exactly_once() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	_enter_combat(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: the handoff into combat must have succeeded")

	watch_signals(CurrentGameState)

	# Drive one full undecided round to conclusion (mirrors
	# tests/boot/test_post_combat_return_to_exploration.gd's
	# test_undecided_round_continuation_is_unaffected_by_this_feature loop):
	# every living party member passes their turn, TurnController auto-drives
	# the enemy's own turn, and any reaction prompt is declined (Pass).
	var round_number_before: int = instance.ROUND_NUMBER
	var guard: int = 0
	while instance.ROUND_NUMBER == round_number_before and not instance.round_session.is_round_over() and guard < 60:
		var actor = instance.round_session.current_actor()
		if actor != null and not actor.is_enemy:
			instance.end_turn_control.press()
		await get_tree().process_frame
		await get_tree().process_frame

		var reaction_guard: int = 0
		while instance.reaction_prompt_ui != null and instance.reaction_prompt_ui.is_open() and reaction_guard < 5:
			instance.reaction_prompt_ui.press_option("none")
			await get_tree().process_frame
			await get_tree().process_frame
			reaction_guard += 1

		guard += 1

	assert_eq(
		instance.ROUND_NUMBER, round_number_before + 1,
		"fixture assumption: driving the round to its natural conclusion must increment ROUND_NUMBER before the encounter is otherwise decided"
	)
	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: an undecided round-over must never leave COMBAT")

	assert_signal_emit_count(
		CurrentGameState, "save_succeeded", 0,
		"no save may occur during any round prior to combat being won"
	)
	assert_signal_emit_count(
		CurrentGameState, "save_failed", 0,
		"no save attempt (successful or failed) may occur during any round prior to combat being won"
	)
	assert_false(
		FileAccess.file_exists(SLOT_0_PATH),
		"user://saves/slot_0.json must not exist before combat has been won"
	)

	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "fixture assumption: the win must have returned to EXPLORATION")
	assert_signal_emit_count(
		CurrentGameState, "save_succeeded", 1,
		"winning combat must trigger exactly one successful auto-save"
	)
	assert_true(FileAccess.file_exists(SLOT_0_PATH), "winning combat must write user://saves/slot_0.json")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — winning combat writes a slot_0.json with the correct
# scenario_path and the won encounter_id present in completed_encounter_ids.
# ══════════════════════════════════════════════════════════════════════════

func test_winning_combat_writes_slot_0_json_with_correct_scenario_and_completed_encounter() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	_enter_combat(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(FileAccess.file_exists(SLOT_0_PATH), "fixture precondition: no save file before winning")

	_force_win(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(FileAccess.file_exists(SLOT_0_PATH), "winning combat must write user://saves/slot_0.json")

	var parsed: Dictionary = _read_slot_0_json()
	assert_eq(parsed.get("scenario_path", ""), PROLOGUE_SCENARIO_PATH, "the saved slot must carry the booted scenario_path")

	var completed_ids: Array = parsed.get("completed_encounter_ids", [])
	assert_true(
		completed_ids.has(PROLOGUE_ENCOUNTER_ID),
		"the saved slot's completed_encounter_ids must include the just-won encounter_id"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — load_from_slot(0) after the save, then boot MainScene from
# that data: party renders at post-combat-win hex positions (deliberately
# moved mid-combat, distinct from the pre-combat encounter-authored spawn),
# and the just-won encounter is marked complete in ScenarioSession.
# ══════════════════════════════════════════════════════════════════════════

func test_load_after_save_boots_party_at_post_combat_win_positions_and_marks_encounter_complete() -> void:
	var instance_a = _boot_main_scene()
	await get_tree().process_frame

	_enter_combat(instance_a)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(instance_a._party.size() > 0, "fixture assumption: the prologue encounter has at least one party member")
	var moved_member = instance_a._party[0]
	var pre_combat_hex: HexCoordClass = HexCoordClass.new(moved_member.hex_coord.q, moved_member.hex_coord.r)

	# Simulate this party member having moved during combat (e.g. via a real
	# Stride action) to a hex distinct from their pre-combat encounter-
	# authored spawn -- directly mutating hex_coord mirrors _force_win()'s
	# own "directly manipulate live Combatant fields to force a deterministic
	# fixture state" convention, isolating this test from any seed-specific
	# movement-action outcome.
	var post_combat_hex := HexCoordClass.new(pre_combat_hex.q + 3, pre_combat_hex.r - 2)
	moved_member.move_to(post_combat_hex)
	var moved_member_id: String = moved_member.combatant_id

	_force_win(instance_a)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(
		instance_a.scenario_session.completed_encounter_ids.has(PROLOGUE_ENCOUNTER_ID),
		"the original instance's ScenarioSession must mark the just-won encounter complete"
	)

	# Simulate a fresh process: wipe in-memory state, then load the just-saved slot.
	CurrentGameState.data = GameStateDataClass.new()
	assert_true(CurrentGameState.load_from_slot(0), "load_from_slot(0) must succeed after the auto-save")
	assert_eq(CurrentGameState.data.scenario_path, PROLOGUE_SCENARIO_PATH)

	var instance_b = _boot_main_scene()
	await get_tree().process_frame

	var reloaded_member = null
	for combatant in instance_b._party:
		if combatant.display_id() == moved_member_id:
			reloaded_member = combatant
			break

	assert_not_null(reloaded_member, "the moved party member must still be present in the freshly booted instance")
	if reloaded_member != null:
		assert_eq(
			reloaded_member.hex_coord.q, post_combat_hex.q,
			"the freshly booted party member must render at the post-combat-win hex.q, not the pre-combat spawn"
		)
		assert_eq(
			reloaded_member.hex_coord.r, post_combat_hex.r,
			"the freshly booted party member must render at the post-combat-win hex.r, not the pre-combat spawn"
		)
		assert_false(
			reloaded_member.hex_coord.q == pre_combat_hex.q and reloaded_member.hex_coord.r == pre_combat_hex.r,
			"fixture sanity: the reloaded hex must differ from the pre-combat spawn hex, proving the sync actually mattered"
		)
