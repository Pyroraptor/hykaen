extends GutTest
## tests/boot/test_main_scene_combatant_snapshot_restoration.gd — FEAT-006
## (US-004; FR-004, ADR-003).
##
## Proves MainScene._ready()'s combatant_snapshots (hp_current/stamina/
## conditions) restoration branching, added alongside FEAT-005's
## party_hex_positions seeding:
##
##   - CurrentGameState.data.combatant_snapshots EMPTY -> combatants keep
##     their encounter-authored default hp_current/stamina/conditions
##     (new-game path, unchanged).
##   - CurrentGameState.data.combatant_snapshots NON-EMPTY with matching
##     combatant_ids -> hp_current/stamina/conditions restored EXACTLY from
##     the snapshot values (loaded-save path).
##   - A snapshot entry missing an optional key (e.g. "conditions")
##     restores the present fields and safe-defaults the missing one
##     without crashing.
##   - A snapshot entry referencing an unknown combatant_id logs a
##     push_warning() naming the combatant_id and is skipped.
##   - A snapshot entry with a malformed field type (e.g. hp_current as a
##     String) is rejected PER-ENTRY with a logged push_warning(); boot
##     continues using encounter-authored defaults for that combatant
##     (RISK-004 mitigation: logged, not silent, mismatch handling).
##
## Mirrors tests/boot/test_main_scene_party_position_seeding.gd's
## established fixture-isolation convention (reset the REAL
## CurrentGameState autoload's `data` field in before_each()/after_each())
## and its push_error/push_warning capture note: GUT's
## assert_push_warning_count()/assert_push_error_count() rely on
## OS.add_logger(), a Godot 4.4+ API that is a documented no-op on this
## project's pinned Godot 4.3 engine, so the push_warning "exactly fires,
## doesn't crash" contract is proven via source-inspection (the exact call
## site exists) plus the OBSERVABLE behavioural contract (boot completes,
## well-formed entries still apply, malformed/unknown entries skipped)
## rather than runtime signal capture.
##
## Conditions-restoration NOTE: MainScene._ready() later calls
## _refresh_off_guard_conditions() (unconditionally, for every party/enemy
## combatant, unchanged by this feature), which OVERWRITES `conditions`
## with the live Off-Guard flanking recomputation. That means a
## full-boot integration test cannot observe a restored `conditions` value
## surviving to the end of _ready() -- so exact conditions-restoration
## (and the "missing optional key" / "malformed type rejects whole entry"
## per-field behaviour) is proven at the finer-grained seam level, calling
## _seed_combatant_snapshots_from_current_game_state() directly against
## lightweight fake combatants -- mirroring
## test_main_scene_party_position_seeding.gd's own identical "Unit-level
## seam proof" section for the exact same reason (that file's seam also
## sits upstream of later _ready() mutation).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")

## PROLOGUE_SEED — mirrors this project's established known-good fixture
## seed (tests/boot/test_main_scene_boot_characterization.gd /
## test_main_scene_party_position_seeding.gd).
const PROLOGUE_SEED: int = 42

const PROLOGUE_SCENARIO_PATH: String = "res://data/scenarios/prologue_scenario.tres"


# ══════════════════════════════════════════════════════════════════════════
# Fixture isolation — mirrors test_main_scene_party_position_seeding.gd:
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
# Criterion 1 — combatant_snapshots EMPTY: combatants keep their
# encounter-authored default hp_current/stamina/conditions.
# ══════════════════════════════════════════════════════════════════════════

func test_empty_combatant_snapshots_keeps_encounter_authored_defaults() -> void:
	assert_true(
		CurrentGameState.data.combatant_snapshots.is_empty(),
		"fixture precondition: combatant_snapshots must start empty (before_each())"
	)

	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _find_party_member(instance, "player_0")
	assert_not_null(titus, "player_0 (Titus) must be present in _party")
	if titus != null:
		assert_eq(titus.hp_current, titus.hp_max, "empty combatant_snapshots must leave Titus at full (encounter-authored default) HP")
		assert_true(titus.stamina > 0, "empty combatant_snapshots must leave Titus at his encounter-authored (non-zero) stamina")

	assert_push_error_count(0, "the new-game (empty combatant_snapshots) boot path must not log any push_error()")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — combatant_snapshots NON-EMPTY with a matching combatant_id:
# hp_current/stamina restored EXACTLY from the snapshot values.
# ══════════════════════════════════════════════════════════════════════════

func test_non_empty_combatant_snapshots_restores_hp_and_stamina_exactly() -> void:
	CurrentGameState.data.scenario_path = PROLOGUE_SCENARIO_PATH
	CurrentGameState.data.combatant_snapshots = [
		{"combatant_id": "player_0", "hp_current": 3, "stamina": 1, "conditions": []},
		{"combatant_id": "player_1", "hp_current": 5, "stamina": 2, "conditions": []},
	]

	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _find_party_member(instance, "player_0")
	assert_not_null(titus, "player_0 (Titus) must be present in _party")
	if titus != null:
		assert_eq(titus.hp_current, 3, "Titus' hp_current must come from CurrentGameState.data, not the encounter-authored full HP")
		assert_eq(titus.stamina, 1, "Titus' stamina must come from CurrentGameState.data, not the encounter-authored default")

	var marigold = _find_party_member(instance, "player_1")
	assert_not_null(marigold, "player_1 (Marigold) must be present in _party")
	if marigold != null:
		assert_eq(marigold.hp_current, 5, "Marigold's hp_current must come from CurrentGameState.data")
		assert_eq(marigold.stamina, 2, "Marigold's stamina must come from CurrentGameState.data")

	assert_push_error_count(0, "the loaded-save (non-empty combatant_snapshots) boot path must not log any push_error()")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — a snapshot entry referencing an unknown combatant_id logs a
# push_warning() naming the combatant_id and is skipped (boot continues).
# ══════════════════════════════════════════════════════════════════════════

func test_unknown_combatant_id_entry_is_skipped_with_push_warning_not_a_crash() -> void:
	CurrentGameState.data.scenario_path = PROLOGUE_SCENARIO_PATH
	CurrentGameState.data.combatant_snapshots = [
		{"combatant_id": "player_0", "hp_current": 3, "stamina": 1},
		{"combatant_id": "ghost_combatant_not_in_encounter", "hp_current": 99, "stamina": 99},
	]

	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"boot must reach GameMode.EXPLORATION even when a combatant_snapshots entry references an unknown combatant_id"
	)
	assert_eq(instance._party.size(), 2, "the known-good party members must still be built despite the unknown-combatant_id entry")

	var titus = _find_party_member(instance, "player_0")
	assert_not_null(titus, "player_0 (Titus) must still be present in _party")
	if titus != null:
		assert_eq(titus.hp_current, 3, "the well-formed player_0 entry must still apply despite the OTHER entry being unknown")
		assert_eq(titus.stamina, 1, "the well-formed player_0 entry must still apply despite the OTHER entry being unknown")

	var ghost = _find_party_member(instance, "ghost_combatant_not_in_encounter")
	assert_null(ghost, "an unknown combatant_id must never fabricate a phantom party member")


func test_main_scene_source_contains_unknown_combatant_id_push_warning_for_snapshots() -> void:
	var content: String = _read_main_scene_source()
	assert_true(
		content.contains("combatant_snapshots entry references combatant_id") and content.contains("push_warning("),
		"MainScene.gd must push_warning() when a combatant_snapshots entry references a combatant_id absent from the live encounter (FEAT-006, fail-closed)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — a snapshot entry with a malformed field type (hp_current as
# a String) is rejected PER-ENTRY with a logged push_warning(); boot
# continues using encounter-authored defaults for that combatant.
# ══════════════════════════════════════════════════════════════════════════

func test_malformed_hp_current_type_rejects_entry_and_boot_continues_with_defaults() -> void:
	CurrentGameState.data.scenario_path = PROLOGUE_SCENARIO_PATH
	CurrentGameState.data.combatant_snapshots = [
		{"combatant_id": "player_0", "hp_current": "not-a-number", "stamina": 1},
	]

	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(
		instance._game_mode, MainSceneClass.GameMode.EXPLORATION,
		"boot must reach GameMode.EXPLORATION even when a combatant_snapshots entry has a malformed hp_current"
	)

	var titus = _find_party_member(instance, "player_0")
	assert_not_null(titus, "player_0 (Titus) must still be present in _party")
	if titus != null:
		assert_eq(titus.hp_current, titus.hp_max, "a malformed hp_current must reject the WHOLE entry -- Titus keeps his encounter-authored default HP")
		assert_true(titus.stamina > 0, "a malformed hp_current must reject the WHOLE entry -- the entry's OTHER (well-typed) stamina field must NOT be partially applied either")

	assert_push_error_count(0, "a malformed combatant_snapshots entry must be handled with push_warning(), never push_error()/a crash")


func test_main_scene_source_contains_malformed_field_push_warning_for_snapshots() -> void:
	var content: String = _read_main_scene_source()
	assert_true(
		content.contains("malformed hp_current") and content.contains("push_warning("),
		"MainScene.gd must push_warning() when a combatant_snapshots entry carries a malformed hp_current type (FEAT-006, RISK-004 mitigation)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Unit-level seam proof: _seed_combatant_snapshots_from_current_game_state()
# in isolation (finer-grained than the full-boot tests above, so a failure
# here points directly at the seam rather than anywhere else in _ready() —
# and, per the file-level NOTE above, this is the ONLY place `conditions`
# restoration and the "missing optional key" / "malformed type rejects
# the WHOLE entry" per-field contracts can be observed, since a full boot
# overwrites `conditions` afterward via _refresh_off_guard_conditions()).
# ══════════════════════════════════════════════════════════════════════════

class _FakeCombatant:
	extends RefCounted
	var combatant_id: String
	var hp_current: int
	var hp_max: int
	var stamina: int
	var conditions: Array

	func _init(p_combatant_id: String, p_hp_current: int, p_stamina: int, p_conditions: Array) -> void:
		combatant_id = p_combatant_id
		hp_current = p_hp_current
		hp_max = p_hp_current
		stamina = p_stamina
		conditions = p_conditions

	func display_id() -> String:
		return combatant_id


func test_seed_seam_is_a_noop_when_current_game_state_combatant_snapshots_is_empty() -> void:
	CurrentGameState.data = GameStateDataClass.new()

	var hex_combatants: Array = [_FakeCombatant.new("player_0", 20, 4, [])]

	var instance := MainSceneClass.new()
	instance._seed_combatant_snapshots_from_current_game_state(hex_combatants)
	autofree(instance)

	assert_eq(hex_combatants[0].hp_current, 20, "empty combatant_snapshots must leave hp_current untouched")
	assert_eq(hex_combatants[0].stamina, 4, "empty combatant_snapshots must leave stamina untouched")
	assert_eq(hex_combatants[0].conditions, [], "empty combatant_snapshots must leave conditions untouched")


func test_seed_seam_restores_hp_stamina_and_conditions_exactly() -> void:
	CurrentGameState.data = GameStateDataClass.new()
	CurrentGameState.data.combatant_snapshots = [
		{"combatant_id": "player_0", "hp_current": 7, "stamina": 1, "conditions": ["Poisoned"]},
	]

	var hex_combatants: Array = [_FakeCombatant.new("player_0", 20, 4, [])]

	var instance := MainSceneClass.new()
	instance._seed_combatant_snapshots_from_current_game_state(hex_combatants)
	autofree(instance)

	assert_eq(hex_combatants[0].hp_current, 7, "non-empty combatant_snapshots must override hp_current")
	assert_eq(hex_combatants[0].stamina, 1, "non-empty combatant_snapshots must override stamina")
	assert_eq(hex_combatants[0].conditions, ["Poisoned"], "non-empty combatant_snapshots must override conditions")


func test_seed_seam_missing_optional_conditions_key_restores_present_fields_and_safe_defaults_missing_one() -> void:
	CurrentGameState.data = GameStateDataClass.new()
	CurrentGameState.data.combatant_snapshots = [
		{"combatant_id": "player_0", "hp_current": 9, "stamina": 2},
	]

	var hex_combatants: Array = [_FakeCombatant.new("player_0", 20, 4, ["Dazed"])]

	var instance := MainSceneClass.new()
	instance._seed_combatant_snapshots_from_current_game_state(hex_combatants)
	autofree(instance)

	assert_eq(hex_combatants[0].hp_current, 9, "the present hp_current field must still be restored")
	assert_eq(hex_combatants[0].stamina, 2, "the present stamina field must still be restored")
	assert_eq(hex_combatants[0].conditions, ["Dazed"], "a missing optional 'conditions' key must safe-default (leave the existing value untouched), never crash")


func test_seed_seam_skips_unknown_combatant_id_without_crashing() -> void:
	CurrentGameState.data = GameStateDataClass.new()
	CurrentGameState.data.combatant_snapshots = [
		{"combatant_id": "unknown_ghost", "hp_current": 1, "stamina": 1, "conditions": ["Stunned"]},
	]

	var hex_combatants: Array = [_FakeCombatant.new("player_0", 20, 4, [])]

	var instance := MainSceneClass.new()
	instance._seed_combatant_snapshots_from_current_game_state(hex_combatants)
	autofree(instance)

	assert_eq(hex_combatants[0].hp_current, 20, "an entry referencing an unknown combatant_id must never mutate an unrelated combatant's hp_current")
	assert_eq(hex_combatants[0].stamina, 4, "an entry referencing an unknown combatant_id must never mutate an unrelated combatant's stamina")
	assert_eq(hex_combatants[0].conditions, [], "an entry referencing an unknown combatant_id must never mutate an unrelated combatant's conditions")


func test_seed_seam_malformed_hp_current_type_rejects_whole_entry() -> void:
	CurrentGameState.data = GameStateDataClass.new()
	CurrentGameState.data.combatant_snapshots = [
		{"combatant_id": "player_0", "hp_current": "not-a-number", "stamina": 1, "conditions": ["Poisoned"]},
	]

	var hex_combatants: Array = [_FakeCombatant.new("player_0", 20, 4, [])]

	var instance := MainSceneClass.new()
	instance._seed_combatant_snapshots_from_current_game_state(hex_combatants)
	autofree(instance)

	assert_eq(hex_combatants[0].hp_current, 20, "a malformed hp_current must reject the WHOLE entry -- hp_current stays at its default")
	assert_eq(hex_combatants[0].stamina, 4, "a malformed hp_current must reject the WHOLE entry -- the OTHER well-typed field (stamina) must NOT be partially applied")
	assert_eq(hex_combatants[0].conditions, [], "a malformed hp_current must reject the WHOLE entry -- conditions must NOT be partially applied either")


func test_seed_seam_malformed_stamina_type_rejects_whole_entry() -> void:
	CurrentGameState.data = GameStateDataClass.new()
	CurrentGameState.data.combatant_snapshots = [
		{"combatant_id": "player_0", "hp_current": 5, "stamina": [1, 2, 3]},
	]

	var hex_combatants: Array = [_FakeCombatant.new("player_0", 20, 4, [])]

	var instance := MainSceneClass.new()
	instance._seed_combatant_snapshots_from_current_game_state(hex_combatants)
	autofree(instance)

	assert_eq(hex_combatants[0].hp_current, 20, "a malformed stamina must reject the WHOLE entry -- hp_current must NOT be partially applied")
	assert_eq(hex_combatants[0].stamina, 4, "a malformed stamina must reject the WHOLE entry -- stamina stays at its default")


func test_seed_seam_malformed_conditions_type_rejects_whole_entry() -> void:
	CurrentGameState.data = GameStateDataClass.new()
	CurrentGameState.data.combatant_snapshots = [
		{"combatant_id": "player_0", "hp_current": 5, "stamina": 1, "conditions": "Poisoned"},
	]

	var hex_combatants: Array = [_FakeCombatant.new("player_0", 20, 4, [])]

	var instance := MainSceneClass.new()
	instance._seed_combatant_snapshots_from_current_game_state(hex_combatants)
	autofree(instance)

	assert_eq(hex_combatants[0].hp_current, 20, "a malformed conditions (non-Array) must reject the WHOLE entry -- hp_current must NOT be partially applied")
	assert_eq(hex_combatants[0].stamina, 4, "a malformed conditions (non-Array) must reject the WHOLE entry -- stamina must NOT be partially applied")
	assert_eq(hex_combatants[0].conditions, [], "a malformed conditions (non-Array) must reject the WHOLE entry -- conditions stays at its default")
