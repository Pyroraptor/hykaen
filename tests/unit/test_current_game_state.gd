extends GutTest
## tests/unit/test_current_game_state.gd
##
## GUT unit tests for FEAT-003 (US-002 / FR-002, NFR-001, NFR-004):
## autoload/current_game_state.gd — CurrentGameState, the
## ADAPTER/INFRASTRUCTURE-layer autoload owning live session state and its
## JSON save-slot persistence.
##
## Tests instantiate the CurrentGameState SCRIPT directly (preload(...).new())
## rather than reaching for the registered autoload singleton, so each test
## gets a fresh `data` field in isolation — matching this feature's own
## "Fresh instance -> initialize_new_game(...) -> save_to_slot(0) ->
## load_from_slot(0)" acceptance-criterion wording. Persistence still goes
## to the SAME real user://saves/ directory the singleton would use (there
## is only one save-slot filesystem location, by design), so every test
## cleans up its own slot fixtures in before_each/after_each to stay
## order-independent.
##
## Test criteria covered (per FEAT-003 spec):
##   1. Fresh instance -> initialize_new_game(prologue_path) ->
##      save_to_slot(0) -> load_from_slot(0) round-trips scenario_path and
##      all fields exactly.
##   2. has_save(0) is false before save_to_slot(0) and true after.
##   3. Saved slot_0.json includes a schema_version field; load_from_slot()
##      handles a missing/mismatched schema_version without crashing.
##   4. Save uses write-to-temp-then-rename; a simulated
##      interrupted/corrupted JSON file causes load_from_slot() to return
##      false and leave existing data unchanged.
##   5. Negative or non-integer slot values are rejected before being
##      interpolated into the save file path.
##   6. Malformed JSON (missing required keys, wrong types) causes
##      load_from_slot() to return false with data left unchanged.
##   7. save_to_slot() emits save_failed(slot, reason) on a simulated IO
##      error.

const CurrentGameStateClass = preload("res://autoload/current_game_state.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")

const PROLOGUE_PATH: String = NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST

const SAVES_DIR: String = "user://saves"

## Every slot number any test in this suite touches — cleaned up before AND
## after every test so ordering never matters.
const USED_SLOTS: Array = [0, 1, 2, 3, 4, 5]


# ══════════════════════════════════════════════════════════════════════════
# Fixture isolation helpers
# ══════════════════════════════════════════════════════════════════════════

func _cleanup_fixtures() -> void:
	# The IO-error-simulation test (below) deliberately replaces
	# "user://saves" with a plain FILE to force directory creation to fail.
	# If a previous run left that blocking file behind, remove it so the
	# real directory can be used again.
	if FileAccess.file_exists(SAVES_DIR) and not DirAccess.dir_exists_absolute(SAVES_DIR):
		var root := DirAccess.open("user://")
		if root != null:
			root.remove("saves")

	if DirAccess.dir_exists_absolute(SAVES_DIR):
		var dir := DirAccess.open(SAVES_DIR)
		if dir != null:
			for slot in USED_SLOTS:
				var name: String = "slot_%d.json" % slot
				if dir.file_exists(name):
					dir.remove(name)
				var tmp_name: String = name + ".tmp"
				if dir.file_exists(tmp_name):
					dir.remove(tmp_name)


func before_each() -> void:
	_cleanup_fixtures()


func after_each() -> void:
	_cleanup_fixtures()


func _write_raw_slot_file(slot: int, contents: String) -> void:
	var dir := DirAccess.open("user://")
	if not dir.dir_exists("saves"):
		dir.make_dir("saves")
	var file := FileAccess.open("%s/slot_%d.json" % [SAVES_DIR, slot], FileAccess.WRITE)
	file.store_string(contents)
	file.close()


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: full round trip via a fresh instance
# ══════════════════════════════════════════════════════════════════════════

func test_fresh_instance_round_trips_all_fields_exactly() -> void:
	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	state.initialize_new_game(PROLOGUE_PATH)

	# Enrich beyond what NewGameFactory alone seeds, so every field on
	# GameStateData is actually exercised by the round trip.
	state.data.completed_encounter_ids = ["prologue_ambush"]
	state.data.combatant_snapshots = [
		{"combatant_id": "player_0", "hp_current": 14, "stamina": 3, "conditions": ["prone"]},
		{"combatant_id": "player_1", "hp_current": 8, "stamina": 1, "conditions": []},
	]

	var expected_scenario_path: String = state.data.scenario_path
	var expected_positions: Array = state.data.party_hex_positions.duplicate(true)
	var expected_completed: Array = state.data.completed_encounter_ids.duplicate(true)
	var expected_snapshots: Array = state.data.combatant_snapshots.duplicate(true)

	assert_true(state.save_to_slot(0), "save_to_slot(0) must succeed for a valid state")

	# Wipe in-memory data first so a passing assertion below can only be
	# explained by load_from_slot() actually re-reading the file.
	state.data = GameStateDataClass.new()

	assert_true(state.load_from_slot(0), "load_from_slot(0) must succeed after a prior save_to_slot(0)")
	assert_eq(state.data.scenario_path, expected_scenario_path, "scenario_path must round-trip exactly")
	assert_eq(state.data.party_hex_positions, expected_positions, "party_hex_positions must round-trip exactly")
	assert_eq(
		state.data.completed_encounter_ids, expected_completed,
		"completed_encounter_ids must round-trip exactly"
	)
	assert_eq(state.data.combatant_snapshots, expected_snapshots, "combatant_snapshots must round-trip exactly")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: has_save() before/after
# ══════════════════════════════════════════════════════════════════════════

func test_has_save_false_before_save_true_after() -> void:
	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	assert_false(state.has_save(0), "has_save(0) must be false before any save_to_slot(0) call")

	state.initialize_new_game(PROLOGUE_PATH)
	state.save_to_slot(0)

	assert_true(state.has_save(0), "has_save(0) must be true after save_to_slot(0) succeeds")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: schema_version field + graceful missing/mismatched handling
# ══════════════════════════════════════════════════════════════════════════

func test_saved_file_includes_schema_version_field() -> void:
	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	state.initialize_new_game(PROLOGUE_PATH)
	assert_true(state.save_to_slot(0))

	var file := FileAccess.open("%s/slot_0.json" % SAVES_DIR, FileAccess.READ)
	assert_not_null(file, "slot_0.json must exist and be readable after save_to_slot(0)")
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()

	var parser := JSON.new()
	assert_eq(parser.parse(text), OK, "saved slot_0.json must be valid JSON")
	var parsed = parser.get_data()
	assert_true(typeof(parsed) == TYPE_DICTIONARY, "saved slot_0.json root must be an object")
	assert_true(parsed.has("schema_version"), "saved slot_0.json must include a schema_version field")


func test_load_handles_missing_schema_version_without_crashing() -> void:
	var payload := {
		"scenario_path": PROLOGUE_PATH,
		"party_hex_positions": [{"combatant_id": "player_0", "q": 0, "r": 0}],
		"completed_encounter_ids": [],
		"combatant_snapshots": [],
	}
	_write_raw_slot_file(1, JSON.stringify(payload))

	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	var ok := state.load_from_slot(1)

	assert_true(ok, "load_from_slot() must not crash and must still load a payload missing schema_version")
	assert_eq(state.data.scenario_path, PROLOGUE_PATH)


func test_load_handles_mismatched_schema_version_without_crashing() -> void:
	var payload := {
		"schema_version": 999999,
		"scenario_path": PROLOGUE_PATH,
		"party_hex_positions": [],
		"completed_encounter_ids": [],
		"combatant_snapshots": [],
	}
	_write_raw_slot_file(1, JSON.stringify(payload))

	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	var ok := state.load_from_slot(1)

	assert_true(ok, "load_from_slot() must not crash on a mismatched schema_version")
	assert_eq(state.data.scenario_path, PROLOGUE_PATH)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: atomic write + corrupted-file safety
# ══════════════════════════════════════════════════════════════════════════

func test_atomic_save_leaves_no_leftover_tmp_file() -> void:
	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	state.initialize_new_game(PROLOGUE_PATH)
	assert_true(state.save_to_slot(2))

	assert_false(
		FileAccess.file_exists("%s/slot_2.json.tmp" % SAVES_DIR),
		"save_to_slot() must rename its temp file into place, leaving no .tmp behind"
	)
	assert_true(FileAccess.file_exists("%s/slot_2.json" % SAVES_DIR), "the final slot_2.json must exist")


func test_corrupted_save_file_load_fails_and_leaves_data_unchanged() -> void:
	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	state.initialize_new_game(PROLOGUE_PATH)
	assert_true(state.save_to_slot(2), "baseline save must succeed")

	var baseline_scenario_path: String = state.data.scenario_path
	var baseline_positions: Array = state.data.party_hex_positions.duplicate(true)

	# Simulate a write interrupted mid-flight: truncated/invalid JSON
	# overwriting the previously-good slot_2.json directly (bypassing the
	# atomic temp-then-rename path entirely, exactly as an external crash
	# mid-write would leave the file).
	_write_raw_slot_file(2, "{\"scenario_path\": \"res://something\", \"party_hex_pos")

	var ok := state.load_from_slot(2)

	assert_false(ok, "load_from_slot() must return false for a corrupted/truncated JSON file")
	assert_eq(
		state.data.scenario_path, baseline_scenario_path,
		"data.scenario_path must be left unchanged after a failed load"
	)
	assert_eq(
		state.data.party_hex_positions, baseline_positions,
		"data.party_hex_positions must be left unchanged after a failed load"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: slot validation before path interpolation
# ══════════════════════════════════════════════════════════════════════════

func test_negative_slot_rejected_by_save_and_load_and_has_save() -> void:
	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	state.initialize_new_game(PROLOGUE_PATH)

	assert_false(state.save_to_slot(-1), "save_to_slot(-1) must be rejected")
	assert_false(state.load_from_slot(-1), "load_from_slot(-1) must be rejected")
	assert_false(state.has_save(-1), "has_save(-1) must be rejected")
	assert_false(
		FileAccess.file_exists("%s/slot_-1.json" % SAVES_DIR),
		"a negative slot must never be interpolated into an actual save file path"
	)


func test_non_integer_slot_rejected_by_save_and_load_and_has_save() -> void:
	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	state.initialize_new_game(PROLOGUE_PATH)

	assert_false(state.save_to_slot("0"), "save_to_slot(String) must be rejected")
	assert_false(state.save_to_slot(1.5), "save_to_slot(float) must be rejected")
	assert_false(state.load_from_slot("0"), "load_from_slot(String) must be rejected")
	assert_false(state.load_from_slot(1.5), "load_from_slot(float) must be rejected")
	assert_false(state.has_save("0"), "has_save(String) must be rejected")
	assert_false(state.has_save(1.5), "has_save(float) must be rejected")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6: malformed JSON (missing keys / wrong types)
# ══════════════════════════════════════════════════════════════════════════

func test_missing_required_key_causes_load_failure_and_leaves_data_unchanged() -> void:
	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	state.data.scenario_path = "res://sentinel_unchanged.tres"

	var payload := {
		"schema_version": 1,
		# scenario_path deliberately omitted
		"party_hex_positions": [],
		"completed_encounter_ids": [],
		"combatant_snapshots": [],
	}
	_write_raw_slot_file(3, JSON.stringify(payload))

	var ok := state.load_from_slot(3)

	assert_false(ok, "load_from_slot() must fail when a required key is missing")
	assert_eq(
		state.data.scenario_path, "res://sentinel_unchanged.tres",
		"data must be left completely unchanged when the payload is missing a required key"
	)


func test_wrong_type_field_causes_load_failure_and_leaves_data_unchanged() -> void:
	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	state.data.scenario_path = "res://sentinel_unchanged.tres"

	var payload := {
		"schema_version": 1,
		"scenario_path": PROLOGUE_PATH,
		"party_hex_positions": "this should be an array, not a string",
		"completed_encounter_ids": [],
		"combatant_snapshots": [],
	}
	_write_raw_slot_file(3, JSON.stringify(payload))

	var ok := state.load_from_slot(3)

	assert_false(ok, "load_from_slot() must fail when a required field has the wrong type")
	assert_eq(
		state.data.scenario_path, "res://sentinel_unchanged.tres",
		"data must be left completely unchanged when a required field has the wrong type"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 7: save_failed(slot, reason) signal on a simulated IO error
# ══════════════════════════════════════════════════════════════════════════

func test_save_to_slot_emits_save_failed_on_simulated_io_error() -> void:
	# Simulate an IO error by replacing the saves directory with a plain
	# FILE, so directory creation inside save_to_slot() is forced to fail.
	var root := DirAccess.open("user://")
	if root.dir_exists("saves"):
		root.remove("saves")
	var blocker := FileAccess.open(SAVES_DIR, FileAccess.WRITE)
	assert_not_null(blocker, "test setup: must be able to create the blocking 'saves' file")
	blocker.store_string("blocking file, not a directory")
	blocker.close()

	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	state.initialize_new_game(PROLOGUE_PATH)

	watch_signals(state)
	var ok := state.save_to_slot(4)

	assert_false(ok, "save_to_slot() must return false on a simulated IO error")
	assert_signal_emitted_with_parameters(state, "save_failed", [4, "saves_dir_unavailable"])

	# Restore a real directory so subsequent tests/after_each cleanup work.
	root.remove("saves")


func test_save_to_slot_emits_save_succeeded_on_success() -> void:
	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	state.initialize_new_game(PROLOGUE_PATH)

	watch_signals(state)
	var ok := state.save_to_slot(0)

	assert_true(ok)
	assert_signal_emitted_with_parameters(state, "save_succeeded", [0])


# ══════════════════════════════════════════════════════════════════════════
# snapshot_from_session() — basic behaviour (duck-typed session/combatants)
# ══════════════════════════════════════════════════════════════════════════

func test_snapshot_from_session_builds_state_from_duck_typed_session_and_combatants() -> void:
	var HexCoordClass = preload("res://core/geometry/hex_coord.gd")

	var session := _make_fake_session({"hero_1": HexCoordClass.new(2, -1)}, ["prologue_ambush"])
	var combatant := _make_fake_combatant("hero_1", 14, 3, ["prone"])

	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	state.snapshot_from_session("res://data/scenarios/prologue_scenario.tres", session, [combatant])

	assert_eq(state.data.scenario_path, "res://data/scenarios/prologue_scenario.tres")
	assert_eq(state.data.party_hex_positions, [{"combatant_id": "hero_1", "q": 2, "r": -1}])
	assert_eq(state.data.completed_encounter_ids, ["prologue_ambush"])
	assert_eq(
		state.data.combatant_snapshots,
		[{"combatant_id": "hero_1", "hp_current": 14, "stamina": 3, "conditions": ["prone"]}]
	)


func test_snapshot_from_session_handles_null_session_gracefully() -> void:
	var state: CurrentGameStateClass = autofree(CurrentGameStateClass.new())
	state.snapshot_from_session("res://data/scenarios/prologue_scenario.tres", null, [])

	assert_eq(state.data.scenario_path, "res://data/scenarios/prologue_scenario.tres")
	assert_true(state.data.party_hex_positions.is_empty())
	assert_true(state.data.completed_encounter_ids.is_empty())
	assert_true(state.data.combatant_snapshots.is_empty())


## Minimal RefCounted-based stand-ins exposing exactly the fields
## CurrentGameState.snapshot_from_session() reads via duck typing --
## deliberately NOT ScenarioSession/Combatant themselves, so this suite
## never has to construct one (only autoload/current_game_state.gd's own
## behaviour is under test here; the NFR-001 guard about
## current_game_state.gd's SOURCE is separately verified in
## tests/unit/test_current_game_state_nfr001_guard.gd).
func _make_fake_session(positions: Dictionary, completed_ids: Array) -> RefCounted:
	var session := _FakeSession.new()
	session.party_hex_positions = positions
	session.completed_encounter_ids = completed_ids
	return session


func _make_fake_combatant(combatant_id: String, hp_current: int, stamina: int, conditions: Array) -> RefCounted:
	var combatant := _FakeCombatant.new()
	combatant.combatant_id = combatant_id
	combatant.hp_current = hp_current
	combatant.stamina = stamina
	combatant.conditions = conditions
	return combatant


class _FakeSession:
	extends RefCounted
	var party_hex_positions: Dictionary = {}
	var completed_encounter_ids: Array = []


class _FakeCombatant:
	extends RefCounted
	var combatant_id: String = ""
	var hp_current: int = 0
	var stamina: int = 0
	var conditions: Array = []
