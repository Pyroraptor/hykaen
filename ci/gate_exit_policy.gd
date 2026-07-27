## ci/gate_exit_policy.gd — FEAT-348 (DEF-003; US-006)
##
## Accepted-known-failures manifest + gate exit-policy.
##
## Problem (DEF-003): tests/runner/headless_runner.gd used to hand the
## process exit code entirely to GUT's built-in "any failure -> exit 1"
## rule (see addons/gut/gui/GutRunner.gd _handle_quit():
## `if(gut.get_fail_count() > 0): exit_code = EXIT_ERROR`). That makes
## FR-006's literal acceptance criteria -- "Failing Tests: N (baseline)"
## AND "exit code 0" -- mutually exclusive whenever N > 0. There was no way
## for a *known*, *accepted*, out-of-scope failure to coexist with a green
## gate other than re-pinning the baseline text in a fixture (the FEAT-344
## workaround the review rejected).
##
## Fix: this file is BOTH
##   1. a pure, Godot/GUT-object-free comparison function (`evaluate`) that
##      takes plain Arrays describing "which tests are currently failing"
##      and "which failures are accepted", and decides a match/mismatch
##      outcome + exit code. Fully unit-testable with hand-written
##      Arrays/Dictionaries -- no live GUT run required (see
##      tests/unit/test_gate_exit_policy.gd).
##   2. a GutHookScript (addons/gut/hook_script.gd) `run()` implementation
##      that headless_runner.gd wires in as GUT's `post_run_script` --
##      GUT's own officially-supported "override the exit code" extension
##      point (see GutRunner._handle_quit: "Overwrite the exit code with
##      the post_script's exit code if it is set"). This lets the pure
##      evaluate() logic actually decide the real headless-run exit code
##      instead of GUT's default "any failure -> 1" rule.
##
## The policy: exit 0 IFF the actual failing-test-id set returned by GUT
## exactly equals the ci/accepted_known_failures.json manifest set (no new
## failures, AND no manifest entry that has unexpectedly started passing).
## Any other outcome -- a regression, OR a stale manifest entry -- exits
## non-zero, per US-006 ("no partial-success interpretation is permitted").
class_name GateExitPolicy
extends GutHookScript

## Exit code returned when the actual failing-test set exactly matches the
## accepted manifest set.
const EXIT_OK: int = 0

## Exit code returned for ANY mismatch -- an unexpected new/regressed
## failure, OR a manifest entry that unexpectedly passed. Kept as its own
## named constant (rather than reusing GutRunner's EXIT_ERROR) so a
## non-zero exit is always attributable to THIS policy, not to GUT's
## built-in fail-count check.
const EXIT_MISMATCH: int = 1

const DEFAULT_MANIFEST_PATH: String = "res://ci/accepted_known_failures.json"


## evaluate(actual_failing_test_ids, accepted_known_failure_ids) -> Dictionary
##
## Pure set comparison. Both arguments are plain Arrays of String test
## identifiers (see `build_test_id` for the identifier shape) -- NOT live
## GUT objects -- so this function can be fed a hand-written "known-good"
## or "known-bad" GUT summary directly from a unit test, with zero Godot
## scene/Node or live-GUT-run dependency.
##
## Returns a Dictionary:
##   exit_code:            int             (EXIT_OK or EXIT_MISMATCH)
##   is_match:              bool
##   unexpected_failures:   Array[String]   actually failing, but NOT in the
##                          accepted manifest -- a new/regressed failure.
##   unexpectedly_passing:  Array[String]   in the accepted manifest, but NOT
##                          actually failing -- a stale manifest entry
##                          (the test started passing and was not removed).
static func evaluate(actual_failing_test_ids: Array, accepted_known_failure_ids: Array) -> Dictionary:
	var actual_set: Dictionary = {}
	for test_id in actual_failing_test_ids:
		actual_set[String(test_id)] = true

	var accepted_set: Dictionary = {}
	for test_id in accepted_known_failure_ids:
		accepted_set[String(test_id)] = true

	var unexpected_failures: Array = []
	for test_id in actual_set.keys():
		if not accepted_set.has(test_id):
			unexpected_failures.append(test_id)
	unexpected_failures.sort()

	var unexpectedly_passing: Array = []
	for test_id in accepted_set.keys():
		if not actual_set.has(test_id):
			unexpectedly_passing.append(test_id)
	unexpectedly_passing.sort()

	var is_match: bool = unexpected_failures.is_empty() and unexpectedly_passing.is_empty()

	return {
		"exit_code": EXIT_OK if is_match else EXIT_MISMATCH,
		"is_match": is_match,
		"unexpected_failures": unexpected_failures,
		"unexpectedly_passing": unexpectedly_passing,
	}


## build_test_id(script_full_name, test_name) -> String
##
## Canonical identifier shape shared by the manifest file,
## `extract_failing_test_ids` (when walking GUT's live test_collector), and
## this file's own unit tests: "<script full name>::<test method name>",
## e.g. "res://tests/unit/test_foo.gd::test_bar_does_the_thing".
static func build_test_id(script_full_name: String, test_name: String) -> String:
	return "%s::%s" % [script_full_name, test_name]


## load_accepted_known_failures(path) -> Array
##
## Reads and parses the manifest JSON file (default:
## res://ci/accepted_known_failures.json) and returns its
## "accepted_known_failures" array of test-id Strings. Returns an empty
## Array (fails toward "expect everything to pass") if the file is missing
## or malformed, so a corrupt manifest surfaces as an ordinary
## unexpected-failure mismatch rather than a silent crash.
static func load_accepted_known_failures(path: String = DEFAULT_MANIFEST_PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []

	var contents: String = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(contents)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	if not parsed.has("accepted_known_failures"):
		return []

	var raw_list = parsed["accepted_known_failures"]
	if typeof(raw_list) != TYPE_ARRAY:
		return []

	var result: Array = []
	for entry in raw_list:
		result.append(String(entry))
	return result


## extract_failing_test_ids(gut) -> Array
##
## Adapter-side helper: walks a LIVE GutMain instance's test_collector and
## returns the Array[String] of `build_test_id(...)`-shaped identifiers for
## every test GUT itself counts as FAILING -- i.e. `collected_test.
## is_failing()` (at least one failed assert), matching exactly the same
## per-test predicate addons/gut/collected_script.gd's
## get_failing_test_count() uses to produce the "Failing Tests: N" summary
## line this whole gate is reconciling against.
##
## Deliberately NOT `not is_passing()`: a "risky" test (ran, asserted
## nothing, `is_passing() == false`) is a DIFFERENT GUT category from a
## failing test (see collected_test.gd is_risky()/is_passing()/
## is_failing()) and must not be swept into this gate's failing-test set --
## doing so would make the manifest chase risky-test flakiness instead of
## real regressions.
##
## This is the ONLY function in this file that touches a real GUT object --
## kept separate from `evaluate()` so the comparison logic itself stays a
## pure function of plain data.
static func extract_failing_test_ids(gut) -> Array:
	var failing_ids: Array = []
	var collector = gut.get_test_collector()
	for collected_script in collector.scripts:
		for collected_test in collected_script.tests:
			if collected_test.was_run and collected_test.is_failing():
				failing_ids.append(build_test_id(collected_script.get_full_name(), collected_test.name))
	failing_ids.sort()
	return failing_ids


## run() -- GutHookScript override.
##
## Wired in as GUT's `post_run_script` by tests/runner/headless_runner.gd.
## GUT calls this automatically at the end of every run -- after setting
## `self.gut` to the GutMain instance that just finished, and BEFORE
## GutRunner reads get_exit_code() to decide the process exit code (see
## GutRunner._handle_quit). This computes the real accepted-known-failures
## gate decision and calls set_exit_code(...) so it -- not GUT's default
## any-failure-exits-1 rule -- determines the process exit code.
func run() -> void:
	var actual_failing_ids: Array = extract_failing_test_ids(gut)
	var accepted_ids: Array = load_accepted_known_failures()
	var result: Dictionary = evaluate(actual_failing_ids, accepted_ids)

	if not result.is_match:
		gut.logger.error(
			"GateExitPolicy: accepted-known-failures manifest mismatch -- unexpected_failures=%s unexpectedly_passing=%s (see ci/accepted_known_failures.json)" % [
				str(result.unexpected_failures),
				str(result.unexpectedly_passing),
			]
		)

	set_exit_code(result.exit_code)
