extends GutTest
## tests/regression/test_single_hex_choice_seam.gd
##
## GUT suite for FEAT-001 (US-001, Dodge-Step steel thread; ADR-001/ADR-002/
## ADR-006 "no duplicate seam"): a live-path grep artifact, encoded as an
## automated regression test, proving that extending the sprint-12
## hex-choice injection seam for Dodge-Step scripting did NOT introduce a
## second, parallel, self-wired hex-choice resolver anywhere in production
## code. Mirrors this project's existing static-grep regression-guard
## convention (ci/check_no_duplicate_seams.sh /
## tests/ci/test_static_checks.gd): a real, executable `grep` invocation
## (via OS.execute) over the actual source tree — never a hand-waved
## "should be fine" assertion.
##
## Verifies (this feature's test_criteria):
##   1. Static grep over core/ source confirms exactly one production
##      hex-choice seam CONTRACT (class_name HexChoiceResolverPort) and
##      exactly TWO production CONCRETE implementations of it (see the
##      FEAT-005 update below) — MainScene.gd's `_UIHexChoiceResolver` (the
##      composition root's own player-facing adapter) and infrastructure/
##      ai_hex_choice_resolver.gd's AIHexChoiceResolver (the enemy AI's
##      adapter) — no THIRD/parallel/rogue seam introduced.
##   2. The check actually has teeth: fails (detects an extra,
##      unaccounted-for implementation) if a rogue, self-wired hex-choice
##      resolver is injected anywhere outside those two known files,
##      proven against a disposable fixture repo (never by mutating the
##      real tree).
##
## FEAT-005 (US-005, Iteration K — "Synchronous AI hex chooser for enemy
## Dodge-Step", ADR-004) update: this seam now legitimately has TWO
## production concrete implementations behind the ONE
## HexChoiceResolverPort contract — MainScene.gd's `_UIHexChoiceResolver`
## (the real, blocking, pop-up-driven resolver for the PLAYER's own
## Dodge-Step) and infrastructure/ai_hex_choice_resolver.gd's
## AIHexChoiceResolver (the synchronous, no-pop-up resolver for the ENEMY's
## own Dodge-Step) — mirroring core/application/ports/reaction_chooser_port.gd's
## OWN established "one port, multiple concrete adapters" precedent
## (presentation/player_reaction_chooser.gd / infrastructure/
## ai_reaction_policy.gd / infrastructure/auto_reaction_chooser.gd all
## extend that SAME port with no analogous singularity guard). This is
## intentional, not a regression: the "no duplicate seam" guarantee this
## suite protects is about a THIRD, rogue implementation ever appearing
## outside these two known, composition-root-selected adapters — never
## about capping the count at exactly one.
##
## Implementation note: the EXTENDS_PATTERN below matches `extends` followed
## by a single wildcard character (`.`) standing in for the opening quote,
## rather than a literal embedded `"` — Godot's OS.execute silently strips
## embedded double-quote characters from spawned-process arguments on this
## engine version, which would otherwise make a literal
## `extends "res://...gd"` pattern silently never match anything via
## OS.execute (verified directly: passing `"he said \"hi\""` through
## OS.execute arrives at the child process as `he said hi`). Using `.` as a
## single-any-character wildcard sidesteps that stripping entirely while
## still anchoring on the real `extends "res://...` source shape.
##
## The port CONTRACT file itself (hex_choice_resolver_port.gd) is excluded
## by name from the "concrete implementation" count/list — mirroring this
## project's own established ci/check_no_duplicate_seams.sh convention of
## excluding an abstract contract/stub file by name (there: `-v --
## '/ai_decision_port\.gd$'`) — because the contract file's own file-level
## doc comment documents the exact adapter shape
## (`` `extends "res://core/application/ports/hex_choice_resolver_port.gd"` ``)
## as prose, which would otherwise textually self-match and produce a false
## "duplicate" positive despite containing zero actual resolver logic.

const PORT_CONTRACT_PATH: String = "res://core/application/ports/hex_choice_resolver_port.gd"
const PORT_CONTRACT_BASENAME: String = "hex_choice_resolver_port.gd"
const EXTENDS_PATTERN: String = "extends .res://core/application/ports/hex_choice_resolver_port.gd"
const CLASS_NAME_PATTERN: String = "class_name HexChoiceResolverPort"

var _temp_dirs: Array = []


func after_each() -> void:
	for dir_path in _temp_dirs:
		OS.execute("rm", ["-rf", dir_path], [], true)
	_temp_dirs = []


func _make_temp_dir() -> String:
	var out: Array = []
	var rc: int = OS.execute("mktemp", ["-d"], out, true)
	if rc != 0 or out.is_empty():
		return ""
	var path: String = String(out[0]).strip_edges()
	_temp_dirs.append(path)
	return path


func _write_file(path: String, contents: String) -> bool:
	var parent_dir: String = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(parent_dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(contents)
	f.close()
	return true


func _copy_real_file_into_fixture(res_source_path: String, dest_path: String) -> void:
	var f := FileAccess.open(res_source_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_source_path)
	if f == null:
		return
	var contents: String = f.get_as_text()
	f.close()
	_write_file(dest_path, contents)


## _grep_files(repo_root, pattern) -> Array — runs a real `grep -rl` over
## `repo_root` for `pattern` (a grep BRE regex — see EXTENDS_PATTERN's own
## doc for why literal embedded quote chars must never appear here), scoped
## to *.gd files, EXCLUDING any "tests" or "addons" directory at any depth
## (test doubles/fixtures legitimately declare their own scripted resolvers
## and must never be counted as a production duplicate — mirrors
## ci/check_no_duplicate_seams.sh's own SCAN_DIRS/exclusion convention
## exactly). Returns the list of matching absolute file paths (empty if
## none).
func _grep_files(repo_root: String, pattern: String) -> Array:
	var out: Array = []
	var args: Array = [
		"-rl",
		"--include=*.gd",
		"--exclude-dir=tests",
		"--exclude-dir=addons",
		"--exclude-dir=.git",
		"-e", pattern,
		repo_root,
	]
	var rc: int = OS.execute("grep", args, out, true)
	# grep exits 1 when no matches are found (not an error condition here).
	assert_true(rc == 0 or rc == 1, "grep invocation must succeed (exit 0 or 1-for-no-matches); got rc=%d" % rc)

	# OS.execute's `output` array is NOT guaranteed to be split one-line-per-
	# element (a multi-line `grep -l` result can arrive as a single element
	# containing embedded "\n" characters) -- join everything first, then
	# split on "\n" ourselves to recover one path per entry.
	var combined: String = ""
	for element in out:
		combined += String(element)

	var files: Array = []
	for line in combined.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped != "":
			files.append(stripped)
	return files


## _concrete_implementation_files(repo_root) -> Array — every production
## file matching EXTENDS_PATTERN, EXCLUDING the port contract file itself by
## name (see file-level doc above).
func _concrete_implementation_files(repo_root: String) -> Array:
	var matches: Array = _grep_files(repo_root, EXTENDS_PATTERN)
	var filtered: Array = []
	for path in matches:
		if path.get_file() != PORT_CONTRACT_BASENAME:
			filtered.append(path)
	return filtered


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — exactly one production hex-choice seam implementation,
# referenced from MainScene.gd (the composition root).
# ══════════════════════════════════════════════════════════════════════════

func test_hex_choice_resolver_port_contract_file_exists() -> void:
	assert_true(FileAccess.file_exists(PORT_CONTRACT_PATH), "the FEAT-001 hex-choice seam contract file must still exist")


func test_exactly_one_hex_choice_resolver_port_contract_definition_in_real_repo() -> void:
	var repo_root: String = ProjectSettings.globalize_path("res://")
	var files: Array = _grep_files(repo_root, CLASS_NAME_PATTERN)

	assert_eq(
		files.size(), 1,
		"expected exactly one '%s' declaration (the single seam contract), found %d: %s" % [CLASS_NAME_PATTERN, files.size(), str(files)]
	)


## FEAT-005 update: exactly the TWO known, composition-root-selected
## implementations (infrastructure/ui_hex_choice_resolver.gd's UIHexChoiceResolver
## for the player — extracted 2026-07-10 from MainScene's former inner class —
## and infrastructure/ai_hex_choice_resolver.gd's AIHexChoiceResolver for the
## enemy AI) — no THIRD/rogue implementation anywhere else.
func test_exactly_two_concrete_hex_choice_resolver_implementations_in_real_repo() -> void:
	var repo_root: String = ProjectSettings.globalize_path("res://")
	var files: Array = _concrete_implementation_files(repo_root)

	assert_eq(
		files.size(), 2,
		"expected exactly two production hex-choice seam implementations (the player's and the enemy AI's — no THIRD/parallel/duplicate seam), found %d: %s" % [files.size(), str(files)]
	)

	var basenames: Array = []
	for path in files:
		basenames.append(path.get_file())

	assert_true(
		"ui_hex_choice_resolver.gd" in basenames,
		"the player's production hex-choice seam implementation must be infrastructure/ui_hex_choice_resolver.gd (UIHexChoiceResolver — extracted 2026-07-10 from MainScene's former `_UIHexChoiceResolver` inner class during the composition-root de-bloat; still wired ONLY by MainScene, now co-located with the enemy AI's adapter), found: %s" % str(basenames)
	)
	assert_true(
		"ai_hex_choice_resolver.gd" in basenames,
		"the other production hex-choice seam implementation must be infrastructure/ai_hex_choice_resolver.gd (the enemy AI's adapter, FEAT-005), found: %s" % str(basenames)
	)


func test_mainscene_is_the_composition_root_wiring_the_hex_choice_seam() -> void:
	var f := FileAccess.open("res://MainScene.gd", FileAccess.READ)
	assert_not_null(f, "res://MainScene.gd must be readable")
	if f == null:
		return
	var source: String = f.get_as_text()
	f.close()

	assert_true(
		source.contains("core/application/ports/hex_choice_resolver_port.gd"),
		"MainScene.gd (the composition root) must reference the hex-choice seam's contract file"
	)
	assert_true(
		source.contains("hex_choice_resolver"),
		"MainScene.gd must wire the hex_choice_resolver field, per FEAT-001's existing composition-root convention"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — the check has teeth: it fails (detects an unaccounted-for
# extra) when a rogue, self-wired hex-choice resolver is injected outside
# the two known, composition-root-selected adapters.
# ══════════════════════════════════════════════════════════════════════════

func _build_clean_fixture_repo(tmp_dir: String) -> void:
	_copy_real_file_into_fixture(PORT_CONTRACT_PATH, tmp_dir + "/core/application/ports/hex_choice_resolver_port.gd")
	# A composition-root stand-in: a single concrete adapter, exactly
	# mirroring MainScene.gd's real `_UIHexChoiceResolver` inner class.
	_write_file(
		tmp_dir + "/MainScene.gd",
		"class_name FixtureMainScene\nextends Node\n\nclass _UIHexChoiceResolver:\n\textends \"res://core/application/ports/hex_choice_resolver_port.gd\"\n\tfunc resolve(legal_hexes: Array):\n\t\treturn null\n"
	)


func test_check_passes_on_clean_single_seam_fixture_repo() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_build_clean_fixture_repo(tmp_dir)
	var files: Array = _concrete_implementation_files(tmp_dir)

	assert_eq(
		files.size(), 1,
		"control case: a clean single-seam fixture repo must report exactly one implementation; found: %s" % str(files)
	)


## _build_two_seam_fixture_repo(tmp_dir) -> void — FEAT-005: a fixture
## mirroring the REAL repo's now-legitimate two-adapter shape (MainScene.gd's
## `_UIHexChoiceResolver` PLUS a dedicated infrastructure/ adapter file for
## the enemy AI), so the "the check has teeth" tests below exercise the
## SAME baseline the real repo actually has, rather than a stale
## single-implementation baseline.
func _build_two_seam_fixture_repo(tmp_dir: String) -> void:
	_build_clean_fixture_repo(tmp_dir)
	_write_file(
		tmp_dir + "/infrastructure/ai_hex_choice_resolver.gd",
		"class_name FixtureAIHexChoiceResolver\nextends \"res://core/application/ports/hex_choice_resolver_port.gd\"\nfunc resolve(legal_hexes: Array):\n\treturn null\n"
	)


func test_check_passes_on_the_real_repos_known_two_seam_fixture() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_build_two_seam_fixture_repo(tmp_dir)
	var files: Array = _concrete_implementation_files(tmp_dir)

	assert_eq(
		files.size(), 2,
		"control case: the real repo's known two-adapter fixture must report exactly two implementations; found: %s" % str(files)
	)


func test_check_detects_injected_duplicate_hex_choice_resolver_outside_composition_root() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_build_two_seam_fixture_repo(tmp_dir)

	# Deliberately inject a THIRD, self-wired concrete hex-choice resolver
	# living outside the two known adapters (e.g. a rogue helper under
	# core/rules/) — exactly the class of regression this test guards
	# against.
	_write_file(
		tmp_dir + "/core/rules/rogue_hex_choice_resolver.gd",
		"class_name RogueHexChoiceResolver\nextends \"res://core/application/ports/hex_choice_resolver_port.gd\"\nfunc resolve(legal_hexes: Array):\n\treturn null\n"
	)

	var files: Array = _concrete_implementation_files(tmp_dir)

	assert_ne(
		files.size(), 2,
		"the check must detect the injected rogue hex-choice resolver (expected != 2 known implementations); got: %s" % str(files)
	)
	assert_eq(files.size(), 3, "expected exactly 3 implementations once the rogue resolver is injected; got: %s" % str(files))

	var basenames: Array = []
	for path in files:
		basenames.append(path.get_file())
	assert_true("rogue_hex_choice_resolver.gd" in basenames, "failure diagnostic must name the offending rogue fixture file; got: %s" % str(basenames))


func test_check_ignores_a_scripted_test_double_extending_the_seam_inside_a_tests_directory() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_build_clean_fixture_repo(tmp_dir)

	# A test double is EXPECTED to extend the same contract (that's the
	# whole point of the seam) — it must never count as a production
	# duplicate as long as it lives under a `tests/` directory.
	_write_file(
		tmp_dir + "/tests/gut/test_double_hex_choice_resolver.gd",
		"class_name TestDoubleHexChoiceResolver\nextends \"res://core/application/ports/hex_choice_resolver_port.gd\"\nfunc resolve(legal_hexes: Array):\n\treturn null\n"
	)

	var files: Array = _concrete_implementation_files(tmp_dir)

	assert_eq(
		files.size(), 1,
		"a scripted test double under tests/ must NOT be counted as a second production implementation; found: %s" % str(files)
	)
