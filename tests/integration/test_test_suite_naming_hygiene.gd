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
## Satisfies: DEF-005, US-011, FEAT-141, FEAT-159, FEAT-001.

## The ONLY filenames permitted to carry "steel_thread"/"steelthread" — all
## genuinely instantiate/boot res://MainScene.tscn.
const ALLOWED_STEEL_THREAD_PATHS: Array = [
	"res://tests/integration/test_steel_thread_prologue_encounter.gd",
	"res://tests/e2e/test_steel_thread_post_remediation_smoke.gd",
	"res://tests/unit/test_steel_thread_prologue_encounter.gd",
	"res://tests/e2e/test_full_steel_thread_e2e.gd",
]


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
