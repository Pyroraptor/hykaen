extends GutTest
## tests/unit/test_no_hardcoded_scenario_constants.gd — FEAT-009 (US-007 /
## FR-007, ADR-007).
##
## Permanent source-scan regression guard: no *.gd file under tests/boot/,
## tests/gut/, or tests/integration/ (the boot/gut/integration suites this
## feature migrated off the former hardcoded MainScene.PROLOGUE_SCENARIO_PATH
## / PROLOGUE_ENCOUNTER_PATH constants, per FR-007) may reintroduce a bare
## reference to either identifier. Those two constants were removed from
## MainScene.gd by FEAT-004/ADR-005; every boot/gut/integration test that
## used to hardcode its own local copy of one of them now seeds
## CurrentGameState.data via core/application/new_game_factory.gd's
## NewGameFactory (create_prologue_state() / create_state_for_scenario())
## instead, so a future PR re-adding `const PROLOGUE_SCENARIO_PATH := "..."`
## (or the encounter-path equivalent) to a test file would be a silent
## regression back toward the ~130-test hard-coupling this iteration removed
## -- this suite is the executable guard against that regression.
##
## Scope note: this scan is deliberately restricted to tests/boot/, tests/gut/,
## and tests/integration/ -- the exact three suites FR-007 / this feature's
## own files_to_modify scope migrated. tests/unit/ is NOT scanned: several
## pre-existing, unrelated tests/unit/ suites (e.g. tests/unit/data/scenarios/
## test_prologue_scenario_fixture.gd, tests/unit/core/domain/
## test_combatant_hex_init.gd) legitimately declare their own
## PROLOGUE_ENCOUNTER_PATH/PROLOGUE_SCENARIO_PATH-named local constants purely
## as a concrete fixture path for testing LOWER-LEVEL resource/domain classes
## (EncounterResource, ScenarioResource, Combatant hex-init) directly --
## nothing to do with CurrentGameState/MainScene boot seeding, and out of this
## feature's file scope (files_to_modify) to touch.
##
## Matching rule: a WORD-BOUNDARY regex (`\bPROLOGUE_SCENARIO_PATH\b` /
## `\bPROLOGUE_ENCOUNTER_PATH\b`), mirroring tests/unit/
## test_core_purity_source_scan.gd's own established "whole identifier token,
## not a blind substring" convention -- so NewGameFactory's OWN
## `PROLOGUE_SCENARIO_PATH_CONST` (the legitimate, intended replacement every
## migrated test now reads instead) never false-positives: the trailing `_`
## before `CONST` is itself a word character, so `\bPROLOGUE_SCENARIO_PATH\b`
## does not match inside `PROLOGUE_SCENARIO_PATH_CONST`. Comment-only lines
## (a line whose trimmed text begins with "#") are excluded, so historical/
## explanatory doc comments narrating the pre-migration constants (e.g. this
## very file's own header above, or test_main_scene_boot_characterization.gd's
## FEAT-004 doc) are never flagged -- only living code (declarations, bare
## identifier uses, and string-literal content on a code line) is scanned.

const SCAN_ROOTS: Array[String] = [
	"res://tests/boot",
	"res://tests/gut",
	"res://tests/integration",
]

const _SCENARIO_PATH_PATTERN: String = "\\bPROLOGUE_SCENARIO_PATH\\b"
const _ENCOUNTER_PATH_PATTERN: String = "\\bPROLOGUE_ENCOUNTER_PATH\\b"


func _compiled(pattern: String) -> RegEx:
	var regex := RegEx.new()
	var compile_err := regex.compile(pattern)
	assert_eq(compile_err, OK, "pattern must compile: %s" % pattern)
	return regex


## Recursively collects every *.gd file path under `dir_path` (res://-style),
## mirroring tests/unit/test_core_purity_source_scan.gd's own
## _collect_gd_files() traversal.
func _collect_gd_files(dir_path: String, out_paths: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				_collect_gd_files(full_path, out_paths)
			elif entry.ends_with(".gd"):
				out_paths.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable to run the source-scan fitness test" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


## _non_comment_source(content) -> String — strips every line whose trimmed
## text begins with "#" (this project's only comment syntax; GDScript has no
## block comments), preserving every other line VERBATIM (including any
## trailing/inline text after code on that line) so a code-line's own string
## literals are still scanned. Lines are rejoined with "\n" so the returned
## text's line numbers no longer matter -- only membership of the two banned
## tokens is asserted below.
func _non_comment_source(content: String) -> String:
	var kept_lines: Array = []
	for line in content.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept_lines.append(line)
	return "\n".join(kept_lines)


func _scan_for_violations(pattern_string: String) -> Array:
	var regex := _compiled(pattern_string)
	var violations: Array = []

	var gd_files: Array = []
	for root in SCAN_ROOTS:
		_collect_gd_files(root, gd_files)
	assert_false(gd_files.is_empty(), "the scanned tests/boot|gut|integration roots must contain at least one *.gd file for this scan to be meaningful")

	for file_path in gd_files:
		var content: String = _read_source(file_path)
		if content.is_empty():
			continue
		var scanned_content: String = _non_comment_source(content)
		var matches: Array = regex.search_all(scanned_content)
		if not matches.is_empty():
			violations.append("%s (%d occurrence(s))" % [file_path, matches.size()])

	return violations


# ══════════════════════════════════════════════════════════════════════════
# The regression guard itself.
# ══════════════════════════════════════════════════════════════════════════

func test_no_boot_gut_or_integration_test_declares_or_references_prologue_scenario_path() -> void:
	var violations: Array = _scan_for_violations(_SCENARIO_PATH_PATTERN)
	assert_true(
		violations.is_empty(),
		(
			"no test under tests/boot|gut|integration may reference the removed PROLOGUE_SCENARIO_PATH "
			+ "identifier (FR-007/ADR-007) -- seed CurrentGameState.data via NewGameFactory."
			+ "create_prologue_state()/create_state_for_scenario() instead; offending files: %s"
		) % [violations]
	)


func test_no_boot_gut_or_integration_test_declares_or_references_prologue_encounter_path() -> void:
	var violations: Array = _scan_for_violations(_ENCOUNTER_PATH_PATTERN)
	assert_true(
		violations.is_empty(),
		(
			"no test under tests/boot|gut|integration may reference the removed PROLOGUE_ENCOUNTER_PATH "
			+ "identifier (FR-007/ADR-007) -- the boot encounter is derived from "
			+ "scenario.encounter_entries[0].encounter, never a hardcoded encounter-path constant; "
			+ "offending files: %s"
		) % [violations]
	)


# ══════════════════════════════════════════════════════════════════════════
# Sanity checks proving the word-boundary pattern discriminates the exact
# banned identifier from NewGameFactory's own, legitimately-referenced
# PROLOGUE_SCENARIO_PATH_CONST -- guards against this suite's own regex
# silently degrading into a blind substring match that would false-positive
# on every migrated test (RISK parity with test_core_purity_source_scan.gd's
# own identical sanity-check convention).
# ══════════════════════════════════════════════════════════════════════════

func test_scenario_path_pattern_does_not_match_new_game_factory_const_suffix() -> void:
	var regex := _compiled(_SCENARIO_PATH_PATTERN)

	assert_not_null(regex.search("const PROLOGUE_SCENARIO_PATH := \"res://data/scenarios/prologue_scenario.tres\""), "must match a bare local re-declaration")
	assert_not_null(regex.search("CurrentGameState.data.scenario_path = PROLOGUE_SCENARIO_PATH"), "must match a bare identifier use")
	assert_null(
		regex.search("NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST"),
		"must NOT match the legitimate NewGameFactory.PROLOGUE_SCENARIO_PATH_CONST identifier (RISK: false positive on the intended replacement)"
	)


func test_encounter_path_pattern_does_not_match_a_differently_named_longer_identifier() -> void:
	var regex := _compiled(_ENCOUNTER_PATH_PATTERN)

	assert_not_null(regex.search("const PROLOGUE_ENCOUNTER_PATH := \"res://data/encounters/prologue_encounter.tres\""), "must match a bare local re-declaration")
	assert_null(
		regex.search("const PROLOGUE_ENCOUNTER_RESOURCE_PATH := \"res://data/encounters/prologue_encounter.tres\""),
		"must NOT match a differently-named longer identifier that merely shares the same prefix"
	)


func test_non_comment_source_strips_full_comment_lines_but_keeps_code_lines_verbatim() -> void:
	var sample: String = (
		"## PROLOGUE_SCENARIO_PATH mentioned only in a doc comment, must be stripped\n"
		+ "\t# PROLOGUE_SCENARIO_PATH mentioned only in an indented comment, must be stripped\n"
		+ "var x = 1 # PROLOGUE_SCENARIO_PATH trailing comment text is kept verbatim on a code line\n"
	)
	var scanned: String = _non_comment_source(sample)

	assert_eq(scanned.count("PROLOGUE_SCENARIO_PATH"), 1, "only the code line's own text survives comment-stripping")
	assert_true(scanned.contains("var x = 1"), "non-comment code lines must be preserved verbatim")
