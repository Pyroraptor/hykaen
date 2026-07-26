## autoload/current_game_state.gd — CurrentGameState autoload singleton
## (FEAT-003 / US-002, FR-002, NFR-001, NFR-004)
##
## ADAPTER/INFRASTRUCTURE layer (Clean Architecture / ADR-001): the ONLY
## place save-file IO happens in this project. Registered as a project
## autoload (see project.godot's [autoload] section) so exactly one
## instance owns the live in-memory session state (`data`) for the whole
## running game.
##
## Responsibilities:
##   - Hold the live `data: GameStateData` field (never null — mirrors
##     GameStateData.new()'s own FR-001 safe-empty-defaults guarantee).
##   - initialize_new_game(scenario_path) — delegate to the APPLICATION-
##     layer NewGameFactory (core/application/new_game_factory.gd) to seed a
##     fresh GameStateData for `scenario_path`.
##   - snapshot_from_session(scenario_path, session, combatants) — build a
##     fresh GameStateData snapshot by READING off a live runtime
##     exploration-session-shaped object (a caller-supplied `session`
##     parameter — see NFR-001 note below) and an Array of combatant-shaped
##     objects, entirely by duck-typing.
##   - save_to_slot(slot)/load_from_slot(slot)/has_save(slot) — JSON
##     persistence to user://saves/slot_<slot>.json.
##
## NFR-001 (mitigates RISK-008 alongside the schema_version field below):
## this file NEVER references the identifier of the APPLICATION-layer
## runtime-session class its own `session` parameter is shaped after —
## not in a preload(), not in a type hint, not in a `.new()` call — that
## identifier is deliberately never spelled out anywhere in this file, not
## even in a comment (mirroring core/application/new_game_factory.gd's own
## established convention for the SAME reason, in the opposite direction).
## snapshot_from_session() only ever READS from a `session` parameter
## passed in by a caller (untyped — Variant — so no static type dependency
## is created either); constructing that runtime object is exclusively the
## presentation/controller layer's job (a LATER feature). This is verified
## by this feature's own dedicated fitness-function test,
## tests/unit/test_current_game_state_nfr001_guard.gd.
##
## Persistence strategy (NFR-004 — engine-version resilience): plain JSON
## via JSON.stringify()/JSON.parse() (not ResourceSaver/ResourceLoader, so
## save files never depend on Godot's binary/text resource format or this
## project's registered class_name table). Every save embeds a
## `schema_version` field (RISK-008 mitigation); load_from_slot() tolerates
## a missing or mismatched schema_version without crashing — it still
## attempts to read the remaining known fields — but rejects (returns
## false, leaves `data` untouched) a payload missing any of the four
## required GameStateData fields or carrying a wrong-typed value for one of
## them.
##
## Atomicity: save_to_slot() writes the full payload to a `.tmp` sibling
## file first, then renames it into place with DirAccess.rename_absolute()
## — so a process interrupted mid-write never leaves a torn/partial
## slot_<slot>.json behind; the previous, still-intact save (if any)
## survives untouched.
##
## Error handling (fail-closed, matches the rest of this codebase's
## convention — see NewGameFactory's own file doc):
## save_to_slot()/load_from_slot() never throw; they return bool and, on
## failure, leave `data` unchanged. save_to_slot() additionally emits
## save_failed(slot, reason) on any IO error so a presentation-layer caller
## can react without polling.
##
## Slot validation: slot values are validated (must be a non-negative int)
## BEFORE being interpolated into the save file path — see _is_valid_slot()
## — closing off a path-traversal-style misuse even though Godot's user://
## sandbox already constrains the root.
##
## Usage:
##   CurrentGameState.initialize_new_game("res://data/scenarios/prologue_scenario.tres")
##   CurrentGameState.save_to_slot(0)
##   CurrentGameState.has_save(0)          # true
##   CurrentGameState.load_from_slot(0)    # true; CurrentGameState.data replaced

extends Node

const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")

## Bumped whenever the persisted JSON shape changes in a way that matters
## to load_from_slot()'s field-by-field validation. load_from_slot() does
## NOT reject a save purely for carrying a different schema_version — it is
## informational/forward-compatible (RISK-008) — a missing or mismatched
## value never crashes the loader.
const SCHEMA_VERSION: int = 1

const SAVES_DIR: String = "user://saves"

## Emitted by save_to_slot() whenever it returns false due to an IO error
## (directory unavailable, temp file unopenable, rename failure, invalid
## slot, ...). `reason` is a short machine-readable tag, not a
## player-facing string.
signal save_failed(slot, reason)

## Emitted by save_to_slot() on a successful write. Optional extension
## point for a future toast/notification UI; no current caller depends on
## it, but it mirrors save_failed() for symmetry.
signal save_succeeded(slot)

## The live, in-memory session state. Never null — defaults to a fresh
## GameStateData (empty scenario_path, empty arrays), mirroring
## GameStateData.new()'s own FR-001 guarantee, so callers never need a
## null-check before initialize_new_game()/load_from_slot() populate it.
var data: GameStateDataClass = GameStateDataClass.new()


## initialize_new_game(scenario_path) -> void
##
## Resets `data` to a fresh GameStateData for `scenario_path`, delegating
## entirely to the APPLICATION-layer NewGameFactory (which itself never
## returns null — see its own file doc for the fail-loud contract on an
## unloadable scenario_path).
func initialize_new_game(scenario_path: String) -> void:
	data = NewGameFactoryClass.create_state_for_scenario(scenario_path)


## snapshot_from_session(scenario_path, session, combatants) -> void
##
## Builds a fresh GameStateData from a live `session` (duck-typed —
## expected to expose `party_hex_positions: Dictionary<String, HexCoord>`
## and `completed_encounter_ids: Array[String]`, matching the
## APPLICATION-layer runtime session object's own field shapes, WITHOUT
## this file ever referencing that class's identifier — see the NFR-001
## note at the top of this file) and `combatants` (an Array of duck-typed
## objects each exposing combatant_id/hp_current/stamina/conditions,
## matching the domain combatant entity's field shapes).
##
## Replaces `data` with the freshly-built snapshot. A null/malformed
## `session` degrades gracefully to empty party_hex_positions/
## completed_encounter_ids rather than crashing.
func snapshot_from_session(scenario_path: String, session, combatants: Array) -> void:
	var state := GameStateDataClass.new()
	state.scenario_path = scenario_path
	state.party_hex_positions = _snapshot_party_hex_positions(session)
	state.completed_encounter_ids = _snapshot_completed_encounter_ids(session)
	state.combatant_snapshots = _snapshot_combatants(combatants)
	data = state


func _snapshot_party_hex_positions(session) -> Array[Dictionary]:
	var positions: Array[Dictionary] = []
	if session == null:
		return positions
	if not ("party_hex_positions" in session):
		return positions
	var raw_positions = session.party_hex_positions
	if typeof(raw_positions) != TYPE_DICTIONARY:
		return positions
	for combatant_id in raw_positions.keys():
		var hex = raw_positions[combatant_id]
		positions.append({"combatant_id": combatant_id, "q": int(hex.q), "r": int(hex.r)})
	return positions


func _snapshot_completed_encounter_ids(session) -> Array[String]:
	var ids: Array[String] = []
	if session == null:
		return ids
	if not ("completed_encounter_ids" in session):
		return ids
	for encounter_id in session.completed_encounter_ids:
		ids.append(str(encounter_id))
	return ids


func _snapshot_combatants(combatants: Array) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for combatant in combatants:
		if combatant == null:
			continue
		snapshots.append({
			"combatant_id": combatant.combatant_id,
			"hp_current": combatant.hp_current,
			"stamina": combatant.stamina,
			"conditions": combatant.conditions.duplicate(),
		})
	return snapshots


## save_to_slot(slot) -> bool
##
## Success: writes `data` as JSON (with an embedded schema_version) to
## user://saves/slot_<slot>.json via write-to-temp-then-rename, returns
## true, and emits save_succeeded(slot).
##
## Failure (fail-closed, never throws): returns false and emits
## save_failed(slot, reason) — never touches the previously-saved file on
## disk — when:
##   - `slot` is not a non-negative int (rejected BEFORE path interpolation)
##   - the saves directory can't be created/accessed
##   - the temp file can't be opened for writing
##   - the temp-to-final rename fails
func save_to_slot(slot = 0) -> bool:
	if not _is_valid_slot(slot):
		push_error("CurrentGameState: invalid slot '%s' for save_to_slot" % [str(slot)])
		save_failed.emit(slot, "invalid_slot")
		return false

	if not _ensure_saves_dir():
		push_error("CurrentGameState: unable to create/access saves directory for slot %d" % slot)
		save_failed.emit(slot, "saves_dir_unavailable")
		return false

	var final_path := _slot_path(slot)
	var tmp_path := final_path + ".tmp"

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error(
			"CurrentGameState: failed to open temp save file for slot %d (error %d)"
			% [slot, FileAccess.get_open_error()]
		)
		save_failed.emit(slot, "open_temp_failed")
		return false

	file.store_string(JSON.stringify(_serialize(data), "\t"))
	file.close()

	var rename_err := DirAccess.rename_absolute(tmp_path, final_path)
	if rename_err != OK:
		push_error(
			"CurrentGameState: failed to rename temp save file into place for slot %d (error %d)"
			% [slot, rename_err]
		)
		save_failed.emit(slot, "rename_failed")
		return false

	save_succeeded.emit(slot)
	return true


## load_from_slot(slot) -> bool
##
## Success: replaces `data` with the deserialised GameStateData read from
## user://saves/slot_<slot>.json, returns true.
##
## Failure (fail-closed, `data` left COMPLETELY UNCHANGED, never throws):
## returns false when:
##   - `slot` is not a non-negative int (rejected BEFORE path interpolation)
##   - no save file exists at that slot
##   - the file can't be opened for reading
##   - the file contents are not valid JSON (e.g. truncated/corrupted by an
##     interrupted write)
##   - the parsed JSON is not an Object/Dictionary
##   - any of the four required GameStateData fields (scenario_path,
##     party_hex_positions, completed_encounter_ids, combatant_snapshots)
##     is missing or carries an unexpected type
##
## A missing or mismatched `schema_version` does NOT by itself cause a
## failure (RISK-008 forward/backward-compatibility mitigation) — only the
## structural checks above do.
func load_from_slot(slot = 0) -> bool:
	if not _is_valid_slot(slot):
		push_error("CurrentGameState: invalid slot '%s' for load_from_slot" % [str(slot)])
		return false

	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		push_warning("CurrentGameState: no save file at slot %d" % slot)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error(
			"CurrentGameState: failed to open save file for slot %d (error %d)"
			% [slot, FileAccess.get_open_error()]
		)
		return false

	var text: String = file.get_as_text()
	file.close()

	var parser := JSON.new()
	var parse_err: int = parser.parse(text)
	if parse_err != OK:
		push_error(
			"CurrentGameState: malformed JSON in slot %d (%s at line %d)"
			% [slot, parser.get_error_message(), parser.get_error_line()]
		)
		return false

	var parsed = parser.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CurrentGameState: slot %d JSON root is not an object" % slot)
		return false

	var candidate = _deserialize(parsed)
	if candidate == null:
		push_error("CurrentGameState: slot %d JSON failed shape validation" % slot)
		return false

	data = candidate
	return true


## has_save(slot) -> bool
##
## Pure boolean disk-stat check (FileAccess.file_exists) — no error path.
## Returns false (never crashes) for an invalid slot, without interpolating
## it into a path.
func has_save(slot = 0) -> bool:
	if not _is_valid_slot(slot):
		return false
	return FileAccess.file_exists(_slot_path(slot))


## _is_valid_slot(slot) -> bool
##
## Non-negative int only. Rejects negative ints, floats (even
## whole-numbered ones, e.g. 1.0), Strings, null, etc. — anything that
## isn't already exactly an int — BEFORE it is ever interpolated into a
## save file path.
func _is_valid_slot(slot) -> bool:
	return typeof(slot) == TYPE_INT and slot >= 0


func _slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVES_DIR, slot]


## _ensure_saves_dir() -> bool — true iff user://saves exists (or was just
## successfully created).
func _ensure_saves_dir() -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.dir_exists("saves"):
		return true
	return dir.make_dir("saves") == OK


## _serialize(state) -> Dictionary — the flat, JSON-friendly shape written
## to disk (NFR-004), with the schema_version field prepended (RISK-008).
func _serialize(state: GameStateDataClass) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"scenario_path": state.scenario_path,
		"party_hex_positions": state.party_hex_positions,
		"completed_encounter_ids": state.completed_encounter_ids,
		"combatant_snapshots": state.combatant_snapshots,
	}


## _deserialize(raw) -> GameStateData or null
##
## Validates that all four required fields are present and correctly
## typed, rebuilding each nested Array[Dictionary]/Array[String] entry by
## entry (never trusting the parsed JSON's nested shapes blindly). Returns
## null (never partially-populated) the moment any required field/entry
## fails validation — schema_version is read but never itself a rejection
## reason.
func _deserialize(raw: Dictionary):
	if not (raw.has("scenario_path") and typeof(raw["scenario_path"]) == TYPE_STRING):
		return null
	if not (raw.has("party_hex_positions") and typeof(raw["party_hex_positions"]) == TYPE_ARRAY):
		return null
	if not (raw.has("completed_encounter_ids") and typeof(raw["completed_encounter_ids"]) == TYPE_ARRAY):
		return null
	if not (raw.has("combatant_snapshots") and typeof(raw["combatant_snapshots"]) == TYPE_ARRAY):
		return null

	var party_positions: Array[Dictionary] = []
	for entry in raw["party_hex_positions"]:
		if typeof(entry) != TYPE_DICTIONARY:
			return null
		if not (entry.has("combatant_id") and entry.has("q") and entry.has("r")):
			return null
		if typeof(entry["combatant_id"]) != TYPE_STRING:
			return null
		if not (typeof(entry["q"]) in [TYPE_INT, TYPE_FLOAT]):
			return null
		if not (typeof(entry["r"]) in [TYPE_INT, TYPE_FLOAT]):
			return null
		party_positions.append({
			"combatant_id": entry["combatant_id"],
			"q": int(entry["q"]),
			"r": int(entry["r"]),
		})

	var completed_ids: Array[String] = []
	for encounter_id in raw["completed_encounter_ids"]:
		if typeof(encounter_id) != TYPE_STRING:
			return null
		completed_ids.append(encounter_id)

	var snapshots: Array[Dictionary] = []
	for entry in raw["combatant_snapshots"]:
		if typeof(entry) != TYPE_DICTIONARY:
			return null
		if not (
			entry.has("combatant_id")
			and entry.has("hp_current")
			and entry.has("stamina")
			and entry.has("conditions")
		):
			return null
		if typeof(entry["combatant_id"]) != TYPE_STRING:
			return null
		if not (typeof(entry["hp_current"]) in [TYPE_INT, TYPE_FLOAT]):
			return null
		if not (typeof(entry["stamina"]) in [TYPE_INT, TYPE_FLOAT]):
			return null
		if typeof(entry["conditions"]) != TYPE_ARRAY:
			return null
		snapshots.append({
			"combatant_id": entry["combatant_id"],
			"hp_current": int(entry["hp_current"]),
			"stamina": int(entry["stamina"]),
			"conditions": entry["conditions"].duplicate(),
		})

	var state := GameStateDataClass.new()
	state.scenario_path = raw["scenario_path"]
	state.party_hex_positions = party_positions
	state.completed_encounter_ids = completed_ids
	state.combatant_snapshots = snapshots
	return state
