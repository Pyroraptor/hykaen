extends GutTest
## tests/integration/test_test_suite_naming_hygiene.gd
##
## DEF-005 (US-011) regression guard: "steel thread" naming must be reserved
## EXCLUSIVELY for tests that boot the real res://MainScene.tscn composition
## root. Six suites previously self-described as exercising "the steel
## thread" while actually constructing core/combat/encounter.gd DIRECTLY
## and calling run()/run_round() — a construction path MainScene.gd
## documents as intentionally never invoked in production. Those suites were
## renamed to remove "steel_thread"/"steelthread" from their filenames
## (see the DEF-005 naming notes in each renamed file's header).
##
## This test locks the convention in place: it scans res://tests
## recursively for any filename containing "steel_thread" or "steelthread"
## (case-insensitive) and asserts the result set is EXACTLY the files
## that genuinely boot res://MainScene.tscn — no more, no fewer. A future
## test file that reintroduces the "steel thread" label without actually
## booting MainScene.tscn will fail this test.
##
## Mirrors the acceptance check: `find tests -iname '*steel_thread*' -o
## -iname '*steelthread*'`.
##
## FEAT-141 (DEF-005 continuation): tests/e2e/
## test_steel_thread_post_remediation_smoke.gd was added to this allow-list
## because it, too, genuinely instantiates/boots res://MainScene.tscn (the
## final post-remediation steel-thread smoke test) — see
## test_allowed_steel_thread_files_actually_reference_main_scene() below,
## which independently verifies every allow-listed file actually references
## MainScene.
##
## FEAT-159 (DEF-005 continuation): tests/unit/
## test_steel_thread_prologue_encounter.gd was added to this allow-list for
## the same reason — it is the final post-FIX-001..FIX-007 remediation
## steel-thread regression, and it, too, genuinely instantiates/boots
## res://MainScene.tscn.
##
## FEAT-167 (DEF-005 continuation): tests/e2e/test_full_steel_thread_e2e.gd
## was added to this allow-list for the same reason — it is the final,
## fully-consolidated-UI capstone E2E smoke test (turn start through
## post-resolution lock), and it, too, genuinely instantiates/boots
## res://MainScene.tscn.
##
## FEAT-001 (US-001, iteration D "UI Consolidation + Movement UX", P0-2):
## tests/gut/test_steel_thread_e2e.gd was deleted — it exclusively drove the
## duplicate scenes/battlefield/* UI stack (HexBattlefield/TurnOrderWidget/
## StrikeInputController/EndTurnController/ResultScreen) through MainScene,
## and that stack's wiring has been removed from MainScene.gd/.tscn
## entirely. Its own file-level doc already noted the newer presentation/*
## stack has independent, equivalent end-to-end coverage in
## tests/integration/test_steel_thread_prologue_encounter.gd and
## tests/e2e/test_prologue_encounter_e2e_smoke.gd, so no MainScene-booting
## coverage was lost by its removal.
##
## FEAT-180 (DEF-005 continuation): tests/gut/test_steel_thread_e2e.gd was
## added to this allow-list for the same reason — it is the mandatory
## steel-thread end-to-end integration suite consolidating Strike/Step/
## Stride/End Turn/verb-gating/cancel coverage in one file (US-015/FR-015),
## and it, too, genuinely instantiates/boots res://MainScene.tscn.
##
## FEAT-010 (Iteration F steel-thread capstone, DEF-005 continuation):
## tests/integration/test_steel_thread_e2e.gd was added to this allow-list —
## its named P0-1 tests genuinely instantiate/boot res://MainScene.tscn (via
## the SAME `_boot_main_scene_with_seed()` convention every other allow-listed
## suite uses); its P0-2/compliance/determinism tests drive a fully-wired
## real RunRoundUseCase/RoundSession + a real presentation/hex_grid_view.gd
## directly instead (mirroring tests/integration/test_ai_token_reposition.gd's
## established rig), never re-deriving the "steel thread" label without
## MainScene involvement anywhere in the file.
##
## FEAT-010 (iteration J's capstone, DEF-005 continuation):
## tests/test_steel_thread_full_e2e.gd was added to this allow-list for the
## same reason — every scenario it drives boots the real res://MainScene.tscn
## composition root (via the SAME `_boot_main_scene_with_seed()` convention)
## and resolves its scripted enemy Strike solely through
## round_session.advance_ai_turn().
##
## FEAT-220 (US-002..US-009, DEF-005 continuation): tests/gut/
## test_smoke_full_steel_thread.gd was added to this allow-list for the same
## reason — it is the CI-runnable release-gate smoke test (paired with
## scripts/smoke_test.sh) that genuinely instantiates/boots the real
## res://MainScene.tscn composition root (via the SAME
## ResourceLoader.load(MAIN_SCENE_PATH)/`instance.seed_override` convention
## every other allow-listed suite uses) and drives the full Dodge-Step
## steel thread end to end through it.
##
## FEAT-246 (US-015, DEF-005 continuation): tests/e2e/
## test_steel_thread_strike_full_flow.gd was added to this allow-list for
## the same reason — it is the steel thread's final end-to-end smoke test
## (boot-real player-Strike and enemy-reaction scenarios, the additive
## option-list/AREA-target-set selection pipeline, END_TURN regression, and
## pinned-seed determinism), and it, too, genuinely instantiates/boots
## res://MainScene.tscn (via the SAME `_boot_main_scene_with_seed()`
## convention every other allow-listed suite uses).
##
## FEAT-282 (US-018, DEF-005 continuation): tests/e2e/
## test_steel_thread_cast_a_spell.gd was added to this allow-list for the
## same reason — it is the Cast-a-Spell steel thread's end-to-end
## integration suite (entry point through Fire Bolt/Channel resolution and
## an Opportunistic Strike exposure window to exit point), and it, too,
## genuinely instantiates/boots res://MainScene.tscn (via the SAME
## `_boot_main_scene()` convention every other allow-listed suite uses).
##
## Satisfies: DEF-005, US-011, FEAT-141, FEAT-159, FEAT-001, FEAT-180, FEAT-010, FEAT-220, FEAT-246, FEAT-282.
##
## ══════════════════════════════════════════════════════════════════════════
## FEAT-171 (DEF-003): the guard above only ever inspected FILENAMES. That
## let a file like tests/unit/test_steel_thread_prologue_encounter.gd slip
## through naming hygiene entirely while its BODY still carried a stale
## `res://scenes/battlefield` / `hex_battlefield` reference (a property that
## no longer existed on MainScene once the duplicate battlefield stack was
## removed by FEAT-001) -- the same defect class FIX-001 (FEAT-170) fixed by
## retargeting that assertion to `hex_grid_view`. A filename-only check has
## no way to catch that: the filename never mentioned "battlefield" at all.
##
## This section extends the hygiene guard to scan file CONTENTS, not just
## paths, for the same removed-identifier family
## tests/infrastructure/test_mainscene_no_battlefield_refs.gd already checks
## against MainScene.gd/.tscn -- but applied here to the body of every file
## under res://tests, converting the defect class into a permanent,
## automated regression guard (ADR-002/ADR-006).
##
## Satisfies: DEF-003, FEAT-171.
## ══════════════════════════════════════════════════════════════════════════

## The ONLY filenames permitted to carry "steel_thread"/"steelthread" — all
## genuinely instantiate/boot res://MainScene.tscn.
const ALLOWED_STEEL_THREAD_PATHS: Array = [
	"res://tests/integration/test_steel_thread_prologue_encounter.gd",
	"res://tests/e2e/test_steel_thread_post_remediation_smoke.gd",
	"res://tests/unit/test_steel_thread_prologue_encounter.gd",
	"res://tests/e2e/test_full_steel_thread_e2e.gd",
	"res://tests/gut/test_steel_thread_e2e.gd",
	"res://tests/integration/test_steel_thread_e2e.gd",
	"res://tests/test_steel_thread_full_e2e.gd",
	"res://tests/gut/test_smoke_full_steel_thread.gd",
	"res://tests/e2e/test_steel_thread_strike_full_flow.gd",
	"res://tests/e2e/test_steel_thread_cast_a_spell.gd",
]

## Path-fragment/identifier substrings from the removed duplicate
## scenes/battlefield/* UI stack (FEAT-001). Each has no overlap against any
## KEPT presentation/* identifier, so a plain `.contains()` is unambiguous —
## mirrors tests/infrastructure/test_mainscene_no_battlefield_refs.gd's
## `_UNAMBIGUOUS_BANNED_TERMS`, extended here to every file under res://tests
## instead of just MainScene.gd/.tscn.
const _UNAMBIGUOUS_BANNED_CONTENT_TERMS: Array = [
	"res://scenes/battlefield",
	"HexBattlefield",
	"hex_battlefield",
	"CombatantReadout",
	"TurnOrderWidget",
	"turn_order_widget",
	"StrikeInputController",
	"strike_input_controller",
	"EndTurnController",
	"end_turn_controller",
]

## "ResultScreen"/"result_screen" is ALSO a removed identifier
## (scenes/battlefield/ResultScreen.gd), but it is a literal PREFIX of the
## KEPT "ResultScreenView"/"result_screen_view" identifiers AND of the kept
## "test_result_screen_lock.gd" regression-suite family, so it cannot be
## banned via a bare substring search without false-positiving on those. It
## is checked separately via a negative-lookahead regex that excludes both
## kept suffixes — extends
## tests/infrastructure/test_mainscene_no_battlefield_refs.gd's
## `_RESULT_SCREEN_NOT_VIEW_PATTERN` to also exclude "_lock".
const _RESULT_SCREEN_NOT_VIEW_OR_LOCK_PATTERN: String = "[Rr]esult_?[Ss]creen(?!_?[Vv]iew|_?[Ll]ock)"

## Files legitimately allowed to reference the removed battlefield-stack
## identifiers/path in their BODY — exclusively as historical documentation
## (doc-comment narration of what was removed, why, and when) or as the
## literal string constants a hygiene/regression guard must itself contain
## in order to check for them (e.g. this very file, and
## test_mainscene_no_battlefield_refs.gd). Every entry was manually audited
## when added: none references a removed identifier in a LIVE, executable
## assertion against production state — each such reference was either
## retargeted (FIX-001/FEAT-170) or was never live to begin with.
##
## This list intentionally does NOT include the FEAT-171 fixture at
## res://tests/fixtures/naming_hygiene/test_fixture_with_stale_reference.gd —
## that file exists specifically to prove this guard fails when it should;
## see test_content_scan_detects_stale_reference_hidden_in_an_innocuously_named_file().
const ALLOWED_CONTENT_REFERENCE_PATHS: Array = [
	"res://tests/business_logic/test_result_screen_lock.gd",
	"res://tests/e2e/test_steel_thread_post_remediation_smoke.gd",
	"res://tests/gut/test_movement_input_controller_lock.gd",
	"res://tests/gut/test_presentation_controls_sticky_lock.gd",
	"res://tests/infrastructure/test_mainscene_headless_boot.gd",
	"res://tests/infrastructure/test_mainscene_no_battlefield_refs.gd",
	"res://tests/integration/test_steel_thread_prologue_encounter.gd",
	"res://tests/integration/test_test_suite_naming_hygiene.gd",
	"res://tests/unit/presentation/test_hex_grid_view_retargeted.gd",
	"res://tests/unit/presentation/test_result_screen_view_retargeted.gd",
	"res://tests/unit/presentation/test_status_panel_view_retargeted.gd",
]

## Directory prefix whose contents are test FIXTURES/DATA, not test suites —
## excluded from the suite-wide content scan below (a dedicated test scans
## the fixture directly instead; see
## test_content_scan_detects_stale_reference_hidden_in_an_innocuously_named_file()).
const _FIXTURE_DIR_PREFIX: String = "res://tests/fixtures/"


## Recursively collects every file path under dir_path (res:// virtual FS).
func _collect_files_recursive(dir_path: String) -> Array:
	var results: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return results
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				results.append_array(_collect_files_recursive(full_path))
			else:
				results.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return results


func test_only_mainscene_booting_suites_carry_steel_thread_naming() -> void:
	var all_files: Array = _collect_files_recursive("res://tests")
	var matches: Array = []
	for path in all_files:
		var lower: String = path.to_lower()
		if lower.contains("steel_thread") or lower.contains("steelthread"):
			matches.append(path)
	matches.sort()

	var expected: Array = ALLOWED_STEEL_THREAD_PATHS.duplicate()
	expected.sort()

	assert_eq(
		matches, expected,
		("Only files that boot res://MainScene.tscn may carry "
			+ "'steel_thread'/'steelthread' in their filename (DEF-005); "
			+ "expected exactly %s, got %s") % [str(expected), str(matches)]
	)


## Sanity: each allowed path must actually exist and reference MainScene.tscn
## somewhere in its own source, so this guard cannot be satisfied by simply
## deleting the legitimate steel-thread suites.
func test_allowed_steel_thread_files_actually_reference_main_scene() -> void:
	for path in ALLOWED_STEEL_THREAD_PATHS:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "%s must exist and be readable" % path)
		if file == null:
			continue
		var content: String = file.get_as_text()
		file.close()
		assert_true(
			content.contains("MainScene"),
			"%s carries the reserved 'steel thread' naming but does not reference MainScene — DEF-005 violation" % path
		)


# ══════════════════════════════════════════════════════════════════════════
# FEAT-171 (DEF-003): content-scanning guard. Reads the BODY of every test
# file (not merely its path/filename) and fails if a removed
# scenes/battlefield/* path or identifier is found outside the explicit
# allow-list above.
# ══════════════════════════════════════════════════════════════════════════

func _read_file_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


## Scans a single file's BODY text (not its path) for banned
## battlefield-stack references, returning the list of distinct terms
## found. Empty array means the content is clean.
func _find_battlefield_content_violations(content: String) -> Array:
	var violations: Array = []
	for term in _UNAMBIGUOUS_BANNED_CONTENT_TERMS:
		if content.contains(term):
			violations.append(term)

	var regex := RegEx.new()
	var compile_err := regex.compile(_RESULT_SCREEN_NOT_VIEW_OR_LOCK_PATTERN)
	if compile_err == OK and not regex.search_all(content).is_empty():
		violations.append("ResultScreen (not ResultScreenView/result_screen_lock)")

	return violations


## The core DEF-003 regression guard: every test file's CONTENT (body text),
## not just its filename, must be free of removed scenes/battlefield/*
## references outside the explicit allow-list. This is what would have
## caught the FIX-001 (FEAT-170) defect — a stale `instance.hex_battlefield`
## assertion sitting inside tests/unit/test_steel_thread_prologue_encounter.gd
## whose FILENAME never mentioned "battlefield" at all.
func test_no_test_file_body_references_removed_battlefield_stack_outside_allow_list() -> void:
	var all_files: Array = _collect_files_recursive("res://tests")
	var offenders: Dictionary = {}

	for path in all_files:
		if not path.ends_with(".gd"):
			continue
		if path.begins_with(_FIXTURE_DIR_PREFIX):
			continue
		if ALLOWED_CONTENT_REFERENCE_PATHS.has(path):
			continue

		var content: String = _read_file_text(path)
		if content.is_empty():
			continue

		var violations: Array = _find_battlefield_content_violations(content)
		if not violations.is_empty():
			offenders[path] = violations

	assert_true(
		offenders.is_empty(),
		("DEF-003: the following test file(s) reference removed "
			+ "scenes/battlefield/* stack identifiers (HexBattlefield, "
			+ "CombatantReadout, TurnOrderWidget, ResultScreen, "
			+ "StrikeInputController, end_turn_controller) or the "
			+ "res://scenes/battlefield path IN THEIR BODY, outside the "
			+ "explicit allow-list: %s") % [str(offenders)]
	)


## Proves the guard above genuinely performs CONTENT scanning, not merely
## filename/path scanning: res://tests/fixtures/naming_hygiene/
## test_fixture_with_stale_reference.gd has an entirely innocuous FILENAME
## (no "steel_thread"/"steelthread"/"battlefield" substring anywhere in its
## path) yet its BODY deliberately contains a stale
## `res://scenes/battlefield` reference. The content scan MUST detect it.
func test_content_scan_detects_stale_reference_hidden_in_an_innocuously_named_file() -> void:
	var fixture_path: String = "res://tests/fixtures/naming_hygiene/test_fixture_with_stale_reference.gd"

	var lower_path: String = fixture_path.to_lower()
	assert_false(
		lower_path.contains("steel_thread") or lower_path.contains("steelthread") or lower_path.contains("battlefield"),
		"fixture path must itself be innocuous, proving any detection below can only come from scanning its BODY text, not its path/name"
	)

	var content: String = _read_file_text(fixture_path)
	assert_false(
		content.is_empty(),
		"%s fixture must exist and be readable" % fixture_path
	)

	var violations: Array = _find_battlefield_content_violations(content)
	assert_false(
		violations.is_empty(),
		("content-scanning must detect the stale res://scenes/battlefield "
			+ "reference inside %s's body even though its filename/path is "
			+ "entirely clean — proves this guard reads file BODIES, not "
			+ "just paths (DEF-003)") % fixture_path
	)
	assert_true(
		violations.has("res://scenes/battlefield"),
		"the fixture's specific stale reference (res://scenes/battlefield) must be among the detected violations, got: %s" % [violations]
	)
