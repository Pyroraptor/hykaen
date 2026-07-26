extends GutTest
## tests/unit/test_current_game_state_nfr001_guard.gd
##
## Architecture fitness-function test for FEAT-003 (US-002 / NFR-001;
## mitigates RISK-008): autoload/current_game_state.gd must NEVER construct
## a ScenarioSession instance -- it only ever READS from a `session`
## parameter handed to it by a caller (see snapshot_from_session()'s own
## file-level doc). CurrentGameState owning/instantiating ScenarioSession
## itself would violate the Clean Architecture dependency direction this
## feature's design establishes (ADAPTER/INFRASTRUCTURE reading from, never
## owning, an APPLICATION-layer runtime object) and would make it
## impossible for a caller to snapshot an ALREADY-RUNNING session's exact
## live state.
##
## Mirrors tests/unit/test_core_purity_source_scan.gd's established
## methodology (RISK-003/RISK-007's word-boundary reasoning applies
## identically here): a blind substring search for "ScenarioSession" would
## both (a) false-positive on an unrelated identifier that merely CONTAINS
## the substring (e.g. a hypothetical "ScenarioSessionSnapshotBuilder")
## and (b) still miss the real question, which is whether the WHOLE
## identifier token "ScenarioSession" appears anywhere in the file at all
## -- not merely as a `.new()` call. This suite asserts the STRONGER,
## simpler invariant (current_game_state.gd never references the
## ScenarioSession identifier at all, in any form: preload(), type hint,
## comment, or `.new()` call) which trivially implies the narrower "never
## calls ScenarioSession.new()" requirement, while additionally proving
## the narrower claim directly too (so a future refactor that somehow
## reintroduces a `.new()` call under a differently-cased/aliased
## reference is still caught by the broader identifier scan).

const CURRENT_GAME_STATE_PATH: String = "res://autoload/current_game_state.gd"

## Word-boundary identifier-token match for the banned ScenarioSession
## reference -- matches the whole token wherever it appears, but never a
## longer identifier that merely starts with the same characters.
const _SCENARIO_SESSION_TOKEN_PATTERN: String = "\\bScenarioSession\\b"

## Specifically targets `ScenarioSession.new(` -- the narrower construction
## call this feature's own spec calls out by name. Kept as its own
## explicit assertion (in addition to the broader identifier scan above)
## so a failure message can call out the construction call specifically.
const _SCENARIO_SESSION_CONSTRUCTION_PATTERN: String = "\\bScenarioSession\\s*\\.\\s*new\\s*\\("

## The literal res:// path to scenario_session.gd -- current_game_state.gd
## must never preload/load it either (that would be an equally-forbidden
## way to obtain a constructible reference to the class, even without the
## bare "ScenarioSession" identifier appearing anywhere).
const _SCENARIO_SESSION_SCRIPT_PATH: String = "core/application/scenario_session.gd"


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable to run the NFR-001 guard test" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func _compiled(pattern: String) -> RegEx:
	var regex := RegEx.new()
	var compile_err := regex.compile(pattern)
	assert_eq(compile_err, OK, "pattern must compile: %s" % pattern)
	return regex


# ══════════════════════════════════════════════════════════════════════════
# current_game_state.gd never references the ScenarioSession identifier
# ══════════════════════════════════════════════════════════════════════════

func test_current_game_state_never_references_scenario_session_identifier() -> void:
	var content: String = _read_source(CURRENT_GAME_STATE_PATH)
	if content.is_empty():
		return

	var regex := _compiled(_SCENARIO_SESSION_TOKEN_PATTERN)
	var matches: Array = regex.search_all(content)

	assert_true(
		matches.is_empty(),
		(
			"autoload/current_game_state.gd must not reference the ScenarioSession identifier "
			+ "anywhere (NFR-001, RISK-008) -- it only ever reads from a `session` parameter "
			+ "handed to it by a caller; found %d occurrence(s)"
		) % matches.size()
	)


func test_current_game_state_never_calls_scenario_session_new() -> void:
	var content: String = _read_source(CURRENT_GAME_STATE_PATH)
	if content.is_empty():
		return

	var regex := _compiled(_SCENARIO_SESSION_CONSTRUCTION_PATTERN)
	var matches: Array = regex.search_all(content)

	assert_true(
		matches.is_empty(),
		"autoload/current_game_state.gd must never call ScenarioSession.new() (NFR-001)"
	)


func test_current_game_state_never_preloads_scenario_session_script_path() -> void:
	var content: String = _read_source(CURRENT_GAME_STATE_PATH)
	if content.is_empty():
		return

	assert_false(
		content.contains(_SCENARIO_SESSION_SCRIPT_PATH),
		(
			"autoload/current_game_state.gd must never preload/load "
			+ "res://core/application/scenario_session.gd -- it must obtain a session "
			+ "only as a caller-supplied parameter, never construct/own one itself (NFR-001)"
		)
	)


func test_snapshot_from_session_parameter_is_read_only_duck_typed() -> void:
	# Companion behavioural check (not just a source-scan): calling
	# snapshot_from_session() with a plain duck-typed stand-in (NOT a real
	# ScenarioSession) must work identically -- proving CurrentGameState
	# genuinely has no compile-time/runtime dependency on the concrete
	# ScenarioSession type, only on the shape it reads.
	var CurrentGameStateClass = preload("res://autoload/current_game_state.gd")

	var stand_in := RefCounted.new()
	# A bare RefCounted with no matching fields must degrade gracefully
	# (empty positions/ids), never crash and never require a real
	# ScenarioSession to be constructed anywhere along the way.
	var state = autofree(CurrentGameStateClass.new())
	state.snapshot_from_session("res://data/scenarios/prologue_scenario.tres", stand_in, [])

	assert_eq(state.data.scenario_path, "res://data/scenarios/prologue_scenario.tres")
	assert_true(state.data.party_hex_positions.is_empty())
	assert_true(state.data.completed_encounter_ids.is_empty())


# ══════════════════════════════════════════════════════════════════════════
# Sanity checks proving the word-boundary pattern actually discriminates a
# whole-token match from a longer identifier that merely shares a prefix
# (mirrors test_core_purity_source_scan.gd's own sanity-check convention).
# ══════════════════════════════════════════════════════════════════════════

func test_scenario_session_token_pattern_matches_bare_identifier_only() -> void:
	var regex := _compiled(_SCENARIO_SESSION_TOKEN_PATTERN)

	assert_not_null(regex.search("ScenarioSession.new()"), "must match a bare ScenarioSession identifier")
	assert_not_null(
		regex.search("var x = ScenarioSession"),
		"must match a bare ScenarioSession identifier at end-of-line"
	)
	assert_null(
		regex.search("ScenarioSessionSnapshotBuilder"),
		"must NOT match a longer identifier that merely starts with the same characters"
	)
	assert_null(
		regex.search("MyScenarioSessionHolder"),
		"must NOT match a longer identifier that merely contains the token as a non-boundary substring"
	)


func test_scenario_session_construction_pattern_matches_new_call_with_whitespace_variants() -> void:
	var regex := _compiled(_SCENARIO_SESSION_CONSTRUCTION_PATTERN)

	assert_not_null(regex.search("ScenarioSession.new()"))
	assert_not_null(regex.search("ScenarioSession . new (  )"))
	assert_null(regex.search("ScenarioSessionSnapshotBuilder.new()"))
