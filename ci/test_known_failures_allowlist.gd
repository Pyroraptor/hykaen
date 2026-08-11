extends GutTest
## ci/test_known_failures_allowlist.gd
##
## FEAT-006 (US-006; FR-007) -- RISK-007 mitigation: an automated
## allowlist-diff check.
##
## ci/accepted_known_failures.json is the CI gate's allowlist (see
## ci/gate_exit_policy.gd): GateExitPolicy.run() exits the process with 0
## IFF the live GUT run's actual failing-test-id set exactly equals this
## manifest's "accepted_known_failures" array. That makes the manifest a
## security-relevant control file in its own right -- silently adding an
## entry to it to paper over a genuine regression is functionally
## equivalent to disabling part of the quality gate, and would otherwise
## only ever be caught by a human noticing it in code review.
##
## This suite asserts the manifest parses to the literal empty JSON array
## [] -- i.e. this project currently has zero accepted, out-of-scope,
## pre-existing failures -- and fails LOUDLY (an ordinary GUT assertion
## failure, exactly like any other regression) the moment a single entry
## is added, so any future attempt to bypass the gate that way trips an
## automated test rather than relying solely on manual review to catch it.
## Co-located under ci/ (rather than tests/) alongside the
## ci/accepted_known_failures.json manifest and ci/gate_exit_policy.gd
## policy it exercises, per this feature's own file placement; wired into
## the project-wide GUT suite via .gutconfig.json's "res://ci" scan dir.

const MANIFEST_PATH: String = "res://ci/accepted_known_failures.json"

var _temp_dirs: Array = []


func after_each() -> void:
	for dir_path in _temp_dirs:
		OS.execute("rm", ["-rf", dir_path], [], true)
	_temp_dirs = []


## _make_temp_dir() -> String -- creates a fresh, empty filesystem temp
## directory (via `mktemp -d`) and registers it for cleanup in
## after_each(). Returns "" if `mktemp` is unavailable in this sandbox
## (tests using it should skip/no-op rather than fail hard), mirroring
## tests/ci/test_static_checks.gd's identical convention.
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


## _read_manifest_text(path) -> String -- raw file contents, "" if the file
## is missing or unreadable.
func _read_manifest_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


## _parse_accepted_known_failures(path) -> Variant
##
## Parses `path` as JSON and returns whatever its "accepted_known_failures"
## key holds, RAW -- null if the file is missing/unreadable, not valid
## JSON, not a JSON object, or lacks the key entirely. Deliberately NOT
## fail-open the way ci/gate_exit_policy.gd's own
## load_accepted_known_failures() is (that function defaults to [] on any
## parse error, by design, so the live gate degrades to "expect everything
## to pass" rather than crashing). This test suite wants the opposite:
## a malformed or missing manifest must surface as ITS OWN distinct
## assertion failure, not be silently conflated with "empty and fine".
func _parse_accepted_known_failures(path: String):
	var contents: String = _read_manifest_text(path)
	if contents == "":
		return null
	var parsed = JSON.parse_string(contents)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	if not parsed.has("accepted_known_failures"):
		return null
	return parsed["accepted_known_failures"]


# ══════════════════════════════════════════════════════════════════════════
# Real manifest: exists, is valid JSON, and remains the empty allowlist
# (test_criteria #1)
# ══════════════════════════════════════════════════════════════════════════

func test_manifest_file_exists() -> void:
	assert_true(
		FileAccess.file_exists(MANIFEST_PATH),
		"ci/accepted_known_failures.json must exist"
	)


func test_manifest_is_valid_json_object_with_accepted_known_failures_key() -> void:
	var contents: String = _read_manifest_text(MANIFEST_PATH)
	assert_false(
		contents.is_empty(),
		"ci/accepted_known_failures.json must be readable and non-empty"
	)

	var parsed = JSON.parse_string(contents)
	assert_eq(
		typeof(parsed), TYPE_DICTIONARY,
		"ci/accepted_known_failures.json must parse to a JSON object"
	)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	assert_true(
		parsed.has("accepted_known_failures"),
		"ci/accepted_known_failures.json must have an 'accepted_known_failures' key"
	)


## The core policy assertion (test_criteria #1): the manifest's
## accepted_known_failures value must equal the literal empty array [].
func test_accepted_known_failures_equals_the_literal_empty_array() -> void:
	var actual = _parse_accepted_known_failures(MANIFEST_PATH)
	assert_eq(
		actual, [],
		(
			"ci/accepted_known_failures.json's accepted_known_failures must " +
			"remain the literal empty array []; found: %s -- adding entries " +
			"to bypass a genuine test failure is forbidden (US-006); fix the " +
			"underlying failure instead of allowlisting it"
		) % str(actual)
	)


func test_accepted_known_failures_is_an_array_type() -> void:
	var actual = _parse_accepted_known_failures(MANIFEST_PATH)
	assert_eq(
		typeof(actual), TYPE_ARRAY,
		"accepted_known_failures must be a JSON array; got Variant.Type %s" % typeof(actual)
	)


## test_criteria #2 (against the REAL manifest): loudly fails, rather than
## silently passing, the instant any entry exists.
func test_accepted_known_failures_has_zero_entries() -> void:
	var actual = _parse_accepted_known_failures(MANIFEST_PATH)
	assert_eq(typeof(actual), TYPE_ARRAY, "accepted_known_failures must be a JSON array")
	if typeof(actual) != TYPE_ARRAY:
		return
	assert_eq(
		actual.size(), 0,
		"ci/accepted_known_failures.json must contain zero accepted known failures; found %d entrie(s): %s" % [actual.size(), str(actual)]
	)


# ══════════════════════════════════════════════════════════════════════════
# Proof the check actually distinguishes pass/fail -- exercised against a
# disposable fixture copy (never by mutating the real manifest), mirroring
# tests/ci/test_static_checks.gd / tests/ci/test_mainscene_gate.gd's
# fixture-injection convention. Demonstrates test_criteria #2's "fails
# loudly if any entry is present" is a real, working assertion path, not
# merely true-by-construction of the current empty file.
# ══════════════════════════════════════════════════════════════════════════

func test_parse_helper_flags_injected_non_empty_entry_as_a_violation() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	var fixture_path: String = tmp_dir + "/accepted_known_failures.json"
	_write_file(
		fixture_path,
		'{"accepted_known_failures": ["res://tests/unit/test_something.gd::test_should_never_be_allowlisted"]}'
	)

	var actual = _parse_accepted_known_failures(fixture_path)
	assert_eq(typeof(actual), TYPE_ARRAY, "fixture must parse as a JSON array")
	assert_ne(
		actual, [],
		(
			"a fixture manifest with an injected entry must NOT equal the " +
			"empty array -- proves this suite's core assertion would " +
			"actually fail (not vacuously pass) were a real entry ever added"
		)
	)
	assert_true(
		actual.size() > 0,
		"the injected entry must be visible in the parsed result"
	)


func test_parse_helper_accepts_clean_empty_fixture() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	var fixture_path: String = tmp_dir + "/accepted_known_failures.json"
	_write_file(fixture_path, '{"accepted_known_failures": []}')

	var actual = _parse_accepted_known_failures(fixture_path)
	assert_eq(
		actual, [],
		"control case: a clean empty-allowlist fixture must parse to []"
	)


func test_parse_helper_returns_null_for_missing_file() -> void:
	var actual = _parse_accepted_known_failures("res://ci/does_not_exist_%s.json" % str(Time.get_ticks_usec()))
	assert_null(
		actual,
		"a missing manifest file must be its own distinct (null) outcome, not silently treated as an empty allowlist"
	)
