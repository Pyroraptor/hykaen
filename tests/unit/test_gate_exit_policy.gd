extends GutTest
## tests/unit/test_gate_exit_policy.gd
##
## GUT test suite for FEAT-348 (DEF-003; US-006): the accepted-known-
## failures manifest + gate exit-policy mechanism.
##
## GateExitPolicy.evaluate() is a pure comparison function -- it takes
## plain Arrays of test-id Strings (a hand-fed "GUT summary": the set of
## currently-failing test ids) and the accepted-known-failures manifest
## set, with ZERO dependency on a live GUT run, Node, or scene tree. That
## is exactly what makes DEF-003's contradiction ("Failing Tests: N
## (baseline)" AND "exit code 0" must both hold) testable in isolation,
## rather than only observable end-to-end via a real `--gut-run-all` run.
##
## Verifies (test_criteria):
##   1. A known-good summary (actual failing set == manifest set) ->
##      exit code 0.
##   2. A known-bad/regressed summary (actual failing set contains an
##      entry NOT in the manifest) -> non-zero exit code.
##   3. A summary missing an expected manifest entry (i.e. an "unexpected
##      pass" -- the manifest expects a failure that did not occur) ->
##      the policy flags the mismatch (non-zero exit code) rather than
##      silently treating it as success.
##   4/5 (headless_runner.gd end-to-end + `python -m pytest` continuing to
##   exit 0) are exercised by actually running the real toolchain, not by
##   this GUT suite -- see ci/gate_exit_policy.gd's module doc comment and
##   tests/runner/headless_runner.gd for the wiring.

const GateExitPolicyClass = preload("res://ci/gate_exit_policy.gd")


# ── Criterion 1: known-good summary (failing set == manifest set) -> 0 ────────

func test_matching_failing_set_and_manifest_returns_exit_code_zero() -> void:
	var actual_failing := [
		"res://tests/unit/test_fixture_a.gd::test_known_pre_existing_failure",
	]
	var accepted := [
		"res://tests/unit/test_fixture_a.gd::test_known_pre_existing_failure",
	]

	var result: Dictionary = GateExitPolicyClass.evaluate(actual_failing, accepted)

	assert_eq(result.exit_code, GateExitPolicyClass.EXIT_OK, "exact match must exit 0")
	assert_true(result.is_match, "exact match must report is_match:true")
	assert_eq(result.unexpected_failures, [], "exact match must have no unexpected_failures")
	assert_eq(result.unexpectedly_passing, [], "exact match must have no unexpectedly_passing entries")


func test_empty_failing_set_and_empty_manifest_returns_exit_code_zero() -> void:
	# The degenerate "fully green suite, empty manifest" case -- must not be
	# treated as a mismatch just because both sides are empty.
	var result: Dictionary = GateExitPolicyClass.evaluate([], [])

	assert_eq(result.exit_code, GateExitPolicyClass.EXIT_OK, "empty vs empty must exit 0")
	assert_true(result.is_match, "empty vs empty must report is_match:true")


# ── Criterion 2: known-bad/regressed summary (extra unaccepted failure) ──────

func test_regressed_summary_with_unaccepted_new_failure_returns_non_zero_exit_code() -> void:
	var actual_failing := [
		"res://tests/unit/test_fixture_a.gd::test_known_pre_existing_failure",
		"res://tests/unit/test_fixture_b.gd::test_newly_broken_by_a_regression",
	]
	var accepted := [
		"res://tests/unit/test_fixture_a.gd::test_known_pre_existing_failure",
	]

	var result: Dictionary = GateExitPolicyClass.evaluate(actual_failing, accepted)

	assert_ne(result.exit_code, 0, "an unaccepted new failure must NOT exit 0")
	assert_eq(result.exit_code, GateExitPolicyClass.EXIT_MISMATCH, "regression must exit EXIT_MISMATCH")
	assert_false(result.is_match, "regression must report is_match:false")
	assert_eq(
		result.unexpected_failures,
		["res://tests/unit/test_fixture_b.gd::test_newly_broken_by_a_regression"],
		"the new/unaccepted failing test must be named in unexpected_failures"
	)
	assert_eq(result.unexpectedly_passing, [], "no manifest entry unexpectedly passed in this scenario")


func test_regression_alongside_empty_manifest_returns_non_zero_exit_code() -> void:
	var result: Dictionary = GateExitPolicyClass.evaluate(
		["res://tests/unit/test_fixture_c.gd::test_totally_unaccepted_failure"],
		[]
	)

	assert_ne(result.exit_code, 0, "any failing test not present in an empty manifest must NOT exit 0")
	assert_eq(
		result.unexpected_failures,
		["res://tests/unit/test_fixture_c.gd::test_totally_unaccepted_failure"]
	)


# ── Criterion 3: manifest entry missing from the actual failing set ──────────
# (i.e. an accepted known failure unexpectedly started passing) ──────────────

func test_manifest_entry_missing_from_actual_failures_is_flagged_as_mismatch() -> void:
	var actual_failing: Array = []  # nothing is actually failing any more
	var accepted := [
		"res://tests/unit/test_fixture_a.gd::test_known_pre_existing_failure",
	]

	var result: Dictionary = GateExitPolicyClass.evaluate(actual_failing, accepted)

	assert_ne(
		result.exit_code, 0,
		"a manifest entry that unexpectedly stopped failing must NOT be silently treated as success"
	)
	assert_eq(result.exit_code, GateExitPolicyClass.EXIT_MISMATCH)
	assert_false(result.is_match)
	assert_eq(
		result.unexpectedly_passing,
		["res://tests/unit/test_fixture_a.gd::test_known_pre_existing_failure"],
		"the stale manifest entry must be named in unexpectedly_passing"
	)
	assert_eq(result.unexpected_failures, [], "no new failures exist in this scenario")


func test_mismatch_can_have_both_unexpected_and_unexpectedly_passing_entries_simultaneously() -> void:
	var actual_failing := ["res://tests/unit/test_fixture_new.gd::test_new_regression"]
	var accepted := ["res://tests/unit/test_fixture_old.gd::test_stale_accepted_failure"]

	var result: Dictionary = GateExitPolicyClass.evaluate(actual_failing, accepted)

	assert_false(result.is_match)
	assert_eq(result.exit_code, GateExitPolicyClass.EXIT_MISMATCH)
	assert_eq(result.unexpected_failures, ["res://tests/unit/test_fixture_new.gd::test_new_regression"])
	assert_eq(result.unexpectedly_passing, ["res://tests/unit/test_fixture_old.gd::test_stale_accepted_failure"])


# ── build_test_id() identifier shape ──────────────────────────────────────────

func test_build_test_id_joins_script_full_name_and_test_name_with_double_colon() -> void:
	var id: String = GateExitPolicyClass.build_test_id("res://tests/unit/test_foo.gd", "test_bar")
	assert_eq(id, "res://tests/unit/test_foo.gd::test_bar")


# ── load_accepted_known_failures() manifest parsing ───────────────────────────

func test_load_accepted_known_failures_reads_the_real_manifest_as_an_array() -> void:
	var accepted: Array = GateExitPolicyClass.load_accepted_known_failures()
	assert_true(accepted is Array, "the real ci/accepted_known_failures.json must parse to an Array")


func test_load_accepted_known_failures_returns_empty_array_for_missing_file() -> void:
	var accepted: Array = GateExitPolicyClass.load_accepted_known_failures("res://ci/does_not_exist.json")
	assert_eq(accepted, [], "a missing manifest file must fail toward an empty accepted set, not a crash")


func test_load_accepted_known_failures_returns_empty_array_for_malformed_json() -> void:
	var tmp_path := "user://feat348_malformed_manifest_test.json"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	f.store_string("{ not valid json ][")
	f.close()

	var accepted: Array = GateExitPolicyClass.load_accepted_known_failures(tmp_path)
	assert_eq(accepted, [], "malformed manifest JSON must fail toward an empty accepted set, not a crash")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))


# ── GateExitPolicy is wired as a valid GUT post_run_script hook ──────────────

func test_gate_exit_policy_extends_gut_hook_script_and_is_instantiable() -> void:
	var instance = GateExitPolicyClass.new()
	assert_true(instance is GutHookScript, "GateExitPolicy must extend GutHookScript to be usable as post_run_script")
	assert_true(instance.has_method("run"), "GateExitPolicy must implement run() per the GutHookScript contract")
