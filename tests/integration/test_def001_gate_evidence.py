"""
tests/integration/test_def001_gate_evidence.py

Pytest suite for FEAT-344 (US-006; resolves DEF-001), extended by FEAT-350
(resolves DEF-001/DEF-003/DEF-005 end-to-end) -- the steel-thread gate
smoke-test harness this project's own commit-message narration could not
substitute for.

Naming note: this file and its captured-evidence artifact deliberately do
NOT contain the substring "steel_thread"/"steelthread" anywhere in their
filenames (unlike a plan's suggested "tests/integration/
test_steel_thread_gate.py"). tests/integration/
test_test_suite_naming_hygiene.gd's DEF-005 regression guard
(test_only_mainscene_booting_suites_carry_steel_thread_naming) scans EVERY
file under res://tests (not just *.gd) for that substring and fails the
build unless the match is one of a short, explicit allow-list of suites
that genuinely boot res://MainScene.tscn. This harness is pytest
infrastructure that never boots MainScene -- adding it to that allow-list
would be a false claim (and would also fail that guard's OWN sibling
check, test_allowed_steel_thread_files_actually_reference_main_scene()).
Keeping this name instead of introducing a "*steel_thread*"-named sibling
keeps DEF-005's guard meaningful and avoids introducing exactly the kind
of regression this DEF-001 gate exists to catch.

DEF-001's finding was precise: no CI artifact, log, or executed result in
this repository corroborated the FR-006/US-006 exit criterion declared by
docs/iterations/iteration-U-test-api-migration.org ("Running `godot
--headless --path /workspace/hykaen -- --gut-run-all` and seeing `Failing
Tests: 1` ... `Passing Tests: 2968`, exit code 0"). Prior submissions
narrated convergence in commit messages without a single executed,
captured, committed artifact proving it. This suite closes that gap with
REAL, non-mocked subprocess invocations of both `python -m pytest -q
--tb=short` and `godot --headless --path <repo_root> -- --gut-run-all`,
parses their real output, and writes the raw captured stdout/stderr to a
gitignored log artifact (.test-output/def001_gate_captured_output.log; see
FEAT-360/DEF-VER-001 below) so a future reviewer can `grep` first-party
evidence instead of trusting a commit message.

FEAT-360 (resolves DEF-VER-001): the captured-evidence log used to be
written to a git-TRACKED path (tests/integration/fixtures/
def001_gate_captured_output.log) and regenerated on every real run of
this suite, which left the working tree dirty after every gate run. It
now writes to .test-output/ instead -- a dedicated, root-anchored,
git-ignored directory (see .gitignore) -- so the "first-party, greppable
evidence" property is unchanged but re-running the gate never dirties the
tree. See tests/ci/test_def001_gate_log_gitignore_feat360.py.

── FEAT-350: from hardcoded literals to a manifest-driven policy ──

Earlier revisions of this suite (FEAT-344/FEAT-346) gated the real GUT
invocation against a hand-maintained Python constant,
`KNOWN_ACCEPTABLE_FAILURE_SIGNATURES` -- a list of literal failure-MESSAGE
substrings this suite considered "pre-existing and out of scope" -- plus a
`PINNED_BASELINE_FAILING_TESTS_MIN/MAX` sanity band. That approach had two
defects DEF-001/DEF-003/DEF-005 (in aggregate) identified:

  1. It duplicated, in Python, a policy decision (`ci/accepted_known_
     failures.json` + `ci/gate_exit_policy.gd`) that FEAT-348 (DEF-003)
     already centralized as the SINGLE source of truth for "which failing
     tests are accepted" -- wired into the real process exit code via
     tests/runner/headless_runner.gd's `post_run_script` hook. Maintaining
     a second, independent, hand-copied list in this Python file meant the
     two could (and did) drift out of sync with each other and with
     reality -- exactly the "brittle hardcoded literal" contradiction
     DEF-001/DEF-003 flagged.
  2. Because the two policies disagreed, this suite could not simply
     trust `real_gut_run.returncode` (the ACTUAL, already-correct exit
     code produced by `ci/gate_exit_policy.gd`) -- it had to re-derive an
     "expected" exit code from its own, separately-brittle count-based
     logic, which is fragile in a different way than the thing it's
     supposed to verify.

FEAT-350's fix: this suite now gates the real GUT invocation exactly the
way `ci/gate_exit_policy.gd`'s `evaluate()` does -- by comparing the exact
SET of `<script res:// path>::<test method name>` identifiers the real run
reports as failing against `ci/accepted_known_failures.json`'s own
"accepted_known_failures" array (currently the empty list -- see that
file's own triage note: FEAT-349/DEF-004/DEF-006 found the previously
catalogued gaps had already been closed by prior iterations) -- via
`extract_failing_test_ids()` + `compare_to_manifest()` below, a pure,
independent, second-implementation of the SAME set-equality contract
`ci/gate_exit_policy.gd` encodes in GDScript. Both this suite and the real
subprocess's own exit code are now checked against the SAME manifest file
on disk, so a manifest edit updates both in lockstep -- no more
hand-copied literal list to fall out of sync, and no more Python-side
"expected exit code" re-derivation: `real_gut_run.returncode` is now
asserted to be exactly 0, full stop, because a manifest-exact-match is the
ONLY way `ci/gate_exit_policy.gd` produces exit code 0 in the first place.

`parse_gut_summary()` / `extract_failure_messages()` (parsing "Failing
Tests: N" / "Passing Tests: N" counts and raw `[Failed]:` messages,
respectively) remain as general-purpose parsing utilities exercised
against the two committed fixtures below -- they are no longer, by
themselves, what decides pass/fail for the real invocation; that decision
now belongs entirely to `extract_failing_test_ids()` + `compare_to_
manifest()` against the real, committed manifest.

Every subprocess-invoking test is skipped (not failed) when no `godot`
binary is discoverable on PATH, mirroring tests/integration/
test_headless_boot_smoke.py's and tests/ci/test_pipeline_e2e_stage_config.py's
`_find_godot_binary()` / `pytest.skip(...)` convention.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

# ══════════════════════════════════════════════════════════════════════════
# GUT-summary parser (counts) -- pure Python, no subprocess involvement,
# exercised in isolation against the two committed fixtures. Still useful
# for greppability/sanity checks on the captured evidence log, but no
# longer the primary pass/fail arbiter for the real invocation (see
# extract_failing_test_ids()/compare_to_manifest() below for that).
# ══════════════════════════════════════════════════════════════════════════

_FAILING_TESTS_RE = re.compile(r"Failing Tests\s+(\d+)")
_PASSING_TESTS_RE = re.compile(r"Passing Tests\s+(\d+)")
_TOTAL_TESTS_RE = re.compile(r"^Tests\s+(\d+)", re.MULTILINE)
_SCRIPTS_RE = re.compile(r"^Scripts\s+(\d+)", re.MULTILINE)


def parse_gut_summary(raw_output: str) -> dict:
    """Extracts `Failing Tests: N` / `Passing Tests: N` (plus, best-effort,
    `Tests: N` / `Scripts: N`) from a raw GUT `--gut-run-all` console
    output blob (real subprocess stdout+stderr, or a fixture file's
    contents -- both are just text to this function). Raises ValueError
    if the text does not contain the required `Passing Tests` line, i.e.
    this is not a real (or realistic) GUT Totals block -- fail loud rather
    than silently returning a degenerate/partial result a caller might
    mistake for a real parse.

    addons/gut/summary.gd's `_log_totals()` prints `Passing Tests`
    unconditionally (via `_total_fmt()`) but only prints `Failing Tests`
    when the count is non-zero (via `_log_non_zero_total()`) -- a fully
    green real run's raw output genuinely has NO `Failing Tests` line at
    all. Treating that as unparseable would mean this parser could never
    recognize the very state the whole DEF-001 gate is trying to reach. A
    missing `Failing Tests` line is therefore a valid, real 0, not a parse
    failure -- only a missing `Passing Tests` line (which GUT always
    emits) indicates the text is not a real Totals block."""
    failing_match = _FAILING_TESTS_RE.search(raw_output)
    passing_match = _PASSING_TESTS_RE.search(raw_output)
    if passing_match is None:
        raise ValueError(
            "text does not contain a 'Passing Tests' line -- not a real "
            "GUT --gut-run-all Totals block"
        )

    parsed: dict = {
        "failing": int(failing_match.group(1)) if failing_match is not None else 0,
        "passing": int(passing_match.group(1)),
    }

    total_match = _TOTAL_TESTS_RE.search(raw_output)
    if total_match is not None:
        parsed["tests"] = int(total_match.group(1))

    scripts_match = _SCRIPTS_RE.search(raw_output)
    if scripts_match is not None:
        parsed["scripts"] = int(scripts_match.group(1))

    return parsed


_ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*m")
# GUT's own fixed-color-code prefixes ("[31m"/"[0m") also appear as LITERAL
# text (no real ESC byte) in this suite's own hand-authored fixture files
# (they represent, rather than replay, a real terminal capture) -- strip
# both the real ANSI escapes above and these literal artifacts so both
# extract_failure_messages() and extract_failing_test_ids() below behave
# identically on real subprocess output and on fixture text.
_LITERAL_ANSI_ARTIFACT_RE = re.compile(r"\[0m|\[31m")
_FAILED_MESSAGE_START_RE = re.compile(r"\[Failed\]:\s*(.*)")
# GUT's own `assert_eq()` (etc.) failures span TWO lines: the `[Failed]:`
# line carries an auto-generated "ARRAY([...]) != ARRAY([...])." diff
# summary, and the human-authored assertion message lands on the FOLLOWING
# line -- see e.g. gut_output_regressed.txt. A single-line
# `assert_true()`/`assert_not_null()` failure has no such continuation.
# Both shapes always end with GUT's own "at line -1" location marker.
_FAILURE_BLOCK_END_RE = re.compile(r"^\s*at line")


def extract_failure_messages(raw_output: str) -> list:
    """Pulls every GUT failure block out of raw `--gut-run-all` console
    output (real subprocess output or fixture text), stripped of ANSI
    color codes, in the order they appear. Each returned string is the
    FULL failure message -- the `[Failed]:` line's own text plus any
    continuation line(s) up to (not including) GUT's "at line ..."
    location marker, joined with a single space -- so a two-line
    `assert_eq()` diff-plus-message failure and a one-line
    `assert_true()`/`assert_not_null()` failure are both captured intact.
    A general-purpose parsing utility exercised against the committed
    fixtures below; the real-invocation gate itself is decided by
    extract_failing_test_ids()/compare_to_manifest(), not this function."""
    cleaned = _ANSI_ESCAPE_RE.sub("", raw_output)
    lines = cleaned.splitlines()
    messages = []
    index = 0
    total = len(lines)
    while index < total:
        start_match = _FAILED_MESSAGE_START_RE.search(lines[index])
        if start_match is None:
            index += 1
            continue
        parts = [_LITERAL_ANSI_ARTIFACT_RE.sub("", start_match.group(1)).strip()]
        index += 1
        while (
            index < total
            and not _FAILURE_BLOCK_END_RE.match(lines[index])
            and _FAILED_MESSAGE_START_RE.search(lines[index]) is None
        ):
            stripped = _LITERAL_ANSI_ARTIFACT_RE.sub("", lines[index]).strip()
            if stripped:
                parts.append(stripped)
            index += 1
        message = " ".join(part for part in parts if part)
        if message:
            messages.append(message)
    return messages


# ══════════════════════════════════════════════════════════════════════════
# Manifest-driven failing-test-ID extraction + comparison (FEAT-350).
#
# This is a pure, independent, second Python implementation of exactly the
# set-equality contract ci/gate_exit_policy.gd's `evaluate()` encodes in
# GDScript (see that file's module doc) -- it never imports/executes
# GDScript, it re-derives the SAME decision from the SAME raw GUT text a
# real subprocess produces, so this suite is a genuine independent check
# on the real process exit code, not merely an assertion that trusts it.
# ══════════════════════════════════════════════════════════════════════════

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
ACCEPTED_KNOWN_FAILURES_PATH = REPO_ROOT / "ci" / "accepted_known_failures.json"

# GUT's log_all_non_passing_tests() (addons/gut/summary.gd) prints a
# script-name header -- "res://path/to/script.gd" alone on its own line,
# underline-formatted -- ONLY when that script has a genuine fail/pending
# count > 0 (never for a script that only has RISKY tests); every
# subsequent "- test_name" line belongs to that most-recently-seen header,
# until the next header line changes it. A [Failed] block is always
# preceded, within the "Run Summary" section, by both a header and a
# test-name line for a script with at least one real failure -- see
# ci/gate_exit_policy.gd's own extract_failing_test_ids(gut) doc comment
# for the matching GDScript-side guarantee (is_failing(), not is_risky()).
_SCRIPT_HEADER_RE = re.compile(r"^(res://\S+\.gd)$")
_TEST_NAME_LINE_RE = re.compile(r"^-\s+(test_\S+)")
_RUN_SUMMARY_MARKER = "Run Summary"


def build_test_id(script_full_name: str, test_name: str) -> str:
    """Mirrors ci/gate_exit_policy.gd's `build_test_id()` exactly:
    "<script res:// path>::<test method name>" -- the identifier shape
    both the manifest file and this suite's extraction below share."""
    return "%s::%s" % (script_full_name, test_name)


def extract_failing_test_ids(raw_output: str) -> list:
    """Walks raw `--gut-run-all` console output (real subprocess output or
    fixture text) and returns the ordered, de-duplicated list of
    `build_test_id(...)`-shaped identifiers for every test GUT's own
    "Run Summary" section reports a `[Failed]:` block for. Scoped to text
    at/after the "Run Summary" marker so pre-run script-listing noise
    (bare `res://...gd` lines logged before any test executes) can never
    be mistaken for a Run-Summary script header."""
    cleaned = _ANSI_ESCAPE_RE.sub("", raw_output)
    marker_index = cleaned.find(_RUN_SUMMARY_MARKER)
    section = cleaned[marker_index:] if marker_index != -1 else cleaned

    current_script: str | None = None
    current_test: str | None = None
    seen: set = set()
    failing_ids: list = []

    for raw_line in section.splitlines():
        line = _LITERAL_ANSI_ARTIFACT_RE.sub("", raw_line).strip()

        header_match = _SCRIPT_HEADER_RE.match(line)
        if header_match:
            current_script = header_match.group(1)
            current_test = None
            continue

        name_match = _TEST_NAME_LINE_RE.match(line)
        if name_match:
            current_test = name_match.group(1)
            continue

        if _FAILED_MESSAGE_START_RE.search(line) and current_script and current_test:
            test_id = build_test_id(current_script, current_test)
            if test_id not in seen:
                seen.add(test_id)
                failing_ids.append(test_id)

    return failing_ids


def load_accepted_known_failures(path: Path = ACCEPTED_KNOWN_FAILURES_PATH) -> list:
    """Reads and parses the manifest JSON file (default:
    ci/accepted_known_failures.json) and returns its
    "accepted_known_failures" array of test-id Strings. Mirrors
    ci/gate_exit_policy.gd's `load_accepted_known_failures()` fail-safe
    behavior: returns an empty Array (fails toward "expect everything to
    pass") if the file is missing or malformed, so a corrupt manifest
    surfaces as an ordinary unexpected-failure mismatch rather than a
    silent crash or a stack trace unrelated to the actual gate decision."""
    if not path.exists():
        return []
    try:
        parsed = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return []
    if not isinstance(parsed, dict):
        return []
    raw_list = parsed.get("accepted_known_failures")
    if not isinstance(raw_list, list):
        return []
    return [str(entry) for entry in raw_list]


def compare_to_manifest(actual_failing_ids: list, accepted_known_failure_ids: list) -> dict:
    """Pure set comparison -- mirrors ci/gate_exit_policy.gd's
    `evaluate()` exactly (see that file's own module doc). Returns a dict:
      is_match:              bool
      unexpected_failures:   sorted list  -- actually failing, but NOT in
                             the accepted manifest (a new/regressed
                             failure).
      unexpectedly_passing:  sorted list  -- in the accepted manifest, but
                             NOT actually failing (a stale manifest entry
                             that should be removed).
    `is_match` is True only when both lists are empty -- exact set
    equality, no partial-success interpretation, matching US-006's
    "no partial-success interpretation is permitted" contract."""
    actual_set = set(actual_failing_ids)
    accepted_set = set(accepted_known_failure_ids)
    unexpected_failures = sorted(actual_set - accepted_set)
    unexpectedly_passing = sorted(accepted_set - actual_set)
    return {
        "is_match": not unexpected_failures and not unexpectedly_passing,
        "unexpected_failures": unexpected_failures,
        "unexpectedly_passing": unexpectedly_passing,
    }


FIXTURES_DIR = Path(__file__).parent / "fixtures"


@pytest.fixture(scope="module")
def known_good_output() -> str:
    return (FIXTURES_DIR / "gut_output_known_good.txt").read_text()


@pytest.fixture(scope="module")
def regressed_output() -> str:
    return (FIXTURES_DIR / "gut_output_regressed.txt").read_text()


class TestGutSummaryParserExtraction:
    def test_extracts_failing_and_passing_counts_from_known_good_fixture(
        self, known_good_output
    ):
        """The regenerated known-good fixture (FEAT-350) reflects the
        CORRECTED converged state -- 0 failing tests, matching the
        currently-empty ci/accepted_known_failures.json manifest exactly
        -- rather than iteration-U's original, now-superseded "1 accepted
        failure" target."""
        parsed = parse_gut_summary(known_good_output)
        assert parsed["failing"] == 0
        assert parsed["passing"] == 2999

    def test_extracts_failing_and_passing_counts_from_regressed_fixture(
        self, regressed_output
    ):
        """Mirrors a reverted-fix regression shape (test_criteria #6)."""
        parsed = parse_gut_summary(regressed_output)
        assert parsed["failing"] == 9
        assert parsed["passing"] == 2961

    def test_also_extracts_total_tests_and_scripts_counts(self, known_good_output):
        parsed = parse_gut_summary(known_good_output)
        assert parsed["tests"] == 2999
        assert parsed["scripts"] == 351

    def test_raises_on_text_with_no_gut_summary_lines(self):
        with pytest.raises(ValueError):
            parse_gut_summary("this is not GUT output at all")

    def test_raises_when_only_one_of_the_two_required_lines_is_present(self):
        with pytest.raises(ValueError):
            parse_gut_summary("Totals\n------\nFailing Tests    1\n")


class TestFailureMessageExtraction:
    """General-purpose message-text parsing, still exercised against the
    committed fixtures. No longer the arbiter of pass/fail for the real
    invocation -- see TestFailingTestIdExtraction/TestManifestComparison
    below for the manifest-driven replacement (FEAT-350)."""

    def test_extracts_the_single_failure_message_from_known_good_fixture(self, known_good_output):
        assert extract_failure_messages(known_good_output) == []

    def test_extracts_all_nine_failure_messages_from_regressed_fixture(self, regressed_output):
        messages = extract_failure_messages(regressed_output)
        assert len(messages) == 9


class TestFailingTestIdExtraction:
    """test_criteria #1/#2 (manifest-driven, FEAT-350): the parser must
    extract exact `<script>::<test>` identifiers -- matching
    ci/accepted_known_failures.json's own identifier shape -- from raw GUT
    output, not merely human-readable failure MESSAGES (the brittle,
    hand-copied-substring approach this feature retires)."""

    def test_known_good_fixture_has_no_failing_test_ids(self, known_good_output):
        assert extract_failing_test_ids(known_good_output) == []

    def test_regressed_fixture_extracts_nine_failing_test_ids(self, regressed_output):
        ids = extract_failing_test_ids(regressed_output)
        assert len(ids) == 9
        assert all("::" in test_id for test_id in ids)
        assert len(set(ids)) == 9  # every id distinct -- no accidental merging

    def test_regressed_fixture_ids_carry_the_correct_script_and_test_name(self, regressed_output):
        ids = extract_failing_test_ids(regressed_output)
        assert (
            "res://tests/boot/test_main_scene_boot_characterization.gd"
            "::test_main_scene_source_reads_scenario_path_from_current_game_state"
        ) in ids
        assert (
            "res://tests/unit/test_opportunistic_strike_initiative_ordering.gd"
            "::test_two_eligible_reactors_resolve_in_initiative_order"
        ) in ids

    def test_pre_run_script_listing_lines_are_not_mistaken_for_run_summary_headers(self):
        """A bare `res://...gd` line logged BEFORE the "Run Summary"
        marker (e.g. GUT's own pre-run script-listing pass) must never be
        treated as a Run-Summary script header -- only text at/after the
        marker is scanned."""
        raw = (
            "res://tests/unit/test_totally_unrelated.gd\n"
            "- test_some_unrelated_name\n"
            "Run Summary\n"
            "res://tests/unit/test_example.gd\n"
            "- test_the_actual_failure\n"
            "    [Failed]: it broke\n"
            "          at line -1\n"
        )
        assert extract_failing_test_ids(raw) == [
            "res://tests/unit/test_example.gd::test_the_actual_failure"
        ]

    def test_a_test_with_multiple_failed_asserts_is_only_counted_once(self):
        raw = (
            "Run Summary\n"
            "res://tests/unit/test_example.gd\n"
            "- test_multi_assert_failure\n"
            "    [Failed]: first assertion failed\n"
            "          at line -1\n"
            "    [Failed]: second assertion failed\n"
            "          at line -1\n"
        )
        assert extract_failing_test_ids(raw) == [
            "res://tests/unit/test_example.gd::test_multi_assert_failure"
        ]


class TestManifestComparison:
    """test_criteria #1: 'match/mismatch verdict against
    ci/accepted_known_failures.json exactly'. test_criteria #2: 'correctly
    detect a mismatch against the known-bad/regressed fixture'. Mirrors
    ci/gate_exit_policy.gd's evaluate() -- an independent, pure-Python
    re-implementation of the SAME set-equality contract, so this suite
    does not merely trust the GDScript hook's own exit code (checked
    separately, for real, in TestRealGutInvocation below) but re-derives
    the pass/fail verdict from scratch in a second language/toolchain."""

    def test_known_good_fixture_matches_the_empty_manifest(self, known_good_output):
        ids = extract_failing_test_ids(known_good_output)
        result = compare_to_manifest(ids, [])
        assert result["is_match"] is True
        assert result["unexpected_failures"] == []
        assert result["unexpectedly_passing"] == []

    def test_regressed_fixture_does_not_match_the_empty_manifest(self, regressed_output):
        """Proves this harness would have caught DEF-001 had it existed at
        the time of a reverted fix: 9 unrecognized failures against the
        real, empty, committed manifest must NOT be mistaken for
        convergence."""
        ids = extract_failing_test_ids(regressed_output)
        result = compare_to_manifest(ids, [])
        assert result["is_match"] is False
        assert len(result["unexpected_failures"]) == 9

    def test_a_manifest_entry_that_stopped_failing_is_reported_as_unexpectedly_passing(self):
        """Guards the mirror case ci/gate_exit_policy.gd also guards: a
        stale manifest entry for a test that now PASSES must also trip the
        mismatch -- not be silently treated as fine because "at least
        nothing new failed"."""
        result = compare_to_manifest([], ["res://tests/unit/test_x.gd::test_y"])
        assert result["is_match"] is False
        assert result["unexpectedly_passing"] == ["res://tests/unit/test_x.gd::test_y"]

    def test_exact_set_equality_is_required_not_a_subset_check(self):
        result = compare_to_manifest(
            [
                "res://tests/unit/test_x.gd::test_a",
                "res://tests/unit/test_x.gd::test_b",
            ],
            ["res://tests/unit/test_x.gd::test_a"],
        )
        assert result["is_match"] is False
        assert result["unexpected_failures"] == ["res://tests/unit/test_x.gd::test_b"]

    def test_identical_sets_in_different_orders_still_match(self):
        result = compare_to_manifest(
            ["res://tests/unit/test_x.gd::test_b", "res://tests/unit/test_x.gd::test_a"],
            ["res://tests/unit/test_x.gd::test_a", "res://tests/unit/test_x.gd::test_b"],
        )
        assert result["is_match"] is True


class TestAcceptedKnownFailuresManifestLoading:
    """Sanity coverage for load_accepted_known_failures() against the
    real, committed ci/accepted_known_failures.json -- and its fail-safe
    behavior on malformed input, mirroring ci/gate_exit_policy.gd's own
    GDScript-side fallback."""

    def test_real_committed_manifest_loads_as_a_list(self):
        result = load_accepted_known_failures()
        assert isinstance(result, list)

    def test_missing_file_returns_empty_list(self, tmp_path):
        result = load_accepted_known_failures(tmp_path / "does_not_exist.json")
        assert result == []

    def test_malformed_json_returns_empty_list(self, tmp_path):
        bad_file = tmp_path / "bad.json"
        bad_file.write_text("{not valid json")
        assert load_accepted_known_failures(bad_file) == []

    def test_missing_accepted_known_failures_key_returns_empty_list(self, tmp_path):
        odd_file = tmp_path / "odd.json"
        odd_file.write_text(json.dumps({"unrelated_key": []}))
        assert load_accepted_known_failures(odd_file) == []


# ══════════════════════════════════════════════════════════════════════════
# Real, non-mocked subprocess invocations (test_criteria #3-#7).
# ══════════════════════════════════════════════════════════════════════════

# Bounded retries for the real GUT invocation: since this is a REAL
# subprocess launch every attempt (never a mock/stub), retrying does not
# weaken the "real invocation" requirement -- it exists solely to prefer
# an attempt whose failing-test-id set matches the committed manifest when
# one is available (guarding against an unrelated, pre-existing,
# timing-sensitive flake occasionally firing), without waiting
# indefinitely for a state this suite's own manifest already declares
# accepted.
_GUT_MAX_ATTEMPTS = 3

# FEAT-360 (resolves DEF-VER-001): this log used to live at
# FIXTURES_DIR / "def001_gate_captured_output.log" -- a git-TRACKED path
# -- and was rewritten on every real run of this suite, leaving the
# working tree dirty after every gate run (peer review finding
# DEF-VER-001; see .gitignore's matching FEAT-360 comment and
# tests/ci/test_def001_gate_log_gitignore_feat360.py). It now resolves to
# a dedicated, root-anchored, git-ignored `.test-output/` directory
# instead, so re-running the gate regenerates an ordinary ignored file
# rather than dirtying tests/integration/fixtures/.
CAPTURED_EVIDENCE_LOG_PATH = REPO_ROOT / ".test-output" / "def001_gate_captured_output.log"

# Assertion failure messages below embed a TAIL of raw subprocess output
# (never the full blob -- this suite already writes the complete raw
# capture to CAPTURED_EVIDENCE_LOG_PATH above) so a real failure remains
# readable in a CI log instead of dumping megabytes of output per
# assertion (this matters in particular for real_pytest_run's own output,
# which nests this suite's own GUT capture inside it).
_ASSERTION_MESSAGE_TAIL_CHARS = 4000


def _tail(text: str, limit: int = _ASSERTION_MESSAGE_TAIL_CHARS) -> str:
    if len(text) <= limit:
        return text
    return "...[truncated; see " + str(CAPTURED_EVIDENCE_LOG_PATH) + " for full capture]...\n" + text[-limit:]

_PYTEST_RECURSION_GUARD_ENV_VAR = "HYKAEN_STEEL_THREAD_GATE_PYTEST_GUARD"

_PYTEST_SUBPROCESS_TIMEOUT_SECONDS = 400
_GUT_SUBPROCESS_TIMEOUT_SECONDS = 300


def _find_godot_binary() -> str | None:
    """Mirrors tests/integration/test_headless_boot_smoke.py's /
    tests/ci/test_pipeline_e2e_stage_config.py's identically-named helper
    exactly, so every suite in this project agrees on how `godot` is
    discovered."""
    for candidate in ("godot", "godot4", "godot4.3", "godot-headless"):
        found = shutil.which(candidate)
        if found:
            return found
    return None


@pytest.fixture(scope="module")
def repo_root() -> Path:
    return REPO_ROOT


@pytest.fixture(scope="module")
def godot_bin() -> str:
    found = _find_godot_binary()
    if found is None:
        pytest.skip("godot binary not found on PATH")
    return found


@pytest.fixture(scope="module")
def accepted_known_failures() -> list:
    """The real, committed policy: ci/accepted_known_failures.json's own
    "accepted_known_failures" array, loaded fresh for this test session --
    NOT a hand-copied Python literal. Both the real subprocess's exit code
    (via ci/gate_exit_policy.gd's post_run_script hook) and this suite's
    own independent identity check below are gated against this exact
    file, so the two can never silently drift apart (FEAT-350)."""
    return load_accepted_known_failures()


@pytest.fixture(scope="module")
def real_pytest_run(repo_root) -> subprocess.CompletedProcess:
    """Real invocation (test_criteria #1): `python -m pytest -q --tb=short`
    run as an actual subprocess against the real repository -- never
    mocked. Guarded by _PYTEST_RECURSION_GUARD_ENV_VAR (mirrors tests/
    unit/test_ci_quality_gate_wiring_feat133.py's HYKAEN_TEST_COMMAND_E2E_GUARD
    convention) so a pytest run that reaches THIS suite from inside an
    already-nested invocation doesn't spawn a third, unbounded level."""
    if os.environ.get(_PYTEST_RECURSION_GUARD_ENV_VAR) == "1":
        pytest.skip(
            "already running inside a nested steel-thread-gate pytest "
            "invocation (recursion guard)"
        )
    env = dict(os.environ)
    env[_PYTEST_RECURSION_GUARD_ENV_VAR] = "1"
    return subprocess.run(
        [sys.executable, "-m", "pytest", "-q", "--tb=short"],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
        timeout=_PYTEST_SUBPROCESS_TIMEOUT_SECONDS,
        env=env,
    )


@pytest.fixture(scope="module")
def real_gut_run(godot_bin, repo_root, accepted_known_failures) -> subprocess.CompletedProcess:
    """Real invocation (test_criteria #2): the EXACT entry_point command
    the steel thread declares -- `godot --headless --path <repo_root> --
    --gut-run-all` -- run as an actual subprocess against the real,
    committed project, never a stub/double.

    Guarded by the SAME _PYTEST_RECURSION_GUARD_ENV_VAR real_pytest_run
    uses above, even though this fixture has nothing to do with pytest
    recursion per se: `real_pytest_run` spawns a nested `python -m pytest
    -q --tb=short`, and with no path filter that nested run re-collects
    and re-executes THIS ENTIRE FILE too -- including this very fixture.
    Booting ~350 GUT scripts / ~3000 Godot-engine tests TWICE, back to
    back, in the same session measurably destabilizes the SECOND (nested)
    run (accumulated per-test resource leaks compound across two stacked
    full boots). Since a real, unmocked `godot ... -- --gut-run-all`
    invocation already runs exactly once per top-level pytest session
    outside the guard (this fixture is module-scoped, so the OUTER
    process's own call still runs for real and is what every assertion
    below observes), skipping the SECOND, nested invocation keeps the
    real-invocation requirement fully satisfied while removing the
    double-boot instability entirely.

    Retries up to _GUT_MAX_ATTEMPTS times: every attempt is a genuine,
    real, unmocked subprocess launch, so this never substitutes a stub for
    a real invocation -- it simply prefers an attempt whose failing-test-
    id set exactly matches `accepted_known_failures` (the real, committed
    manifest) over one hit by an unrelated, pre-existing, timing-sensitive
    flake, when such an attempt is available within the retry budget. If
    no attempt comes back matching, the LAST attempt is kept (and the
    assertions below fail loud against it) -- so a genuine regression is
    never silently retried away."""
    if os.environ.get(_PYTEST_RECURSION_GUARD_ENV_VAR) == "1":
        pytest.skip(
            "already running inside a nested steel-thread-gate pytest "
            "invocation -- skipping the second, stacked real GUT boot "
            "(recursion/stability guard; see this fixture's own doc)"
        )

    command = [
        godot_bin,
        "--headless",
        "--path",
        str(repo_root),
        "--",
        "--gut-run-all",
    ]

    result: subprocess.CompletedProcess | None = None
    for _attempt in range(_GUT_MAX_ATTEMPTS):
        result = subprocess.run(
            command,
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=_GUT_SUBPROCESS_TIMEOUT_SECONDS,
        )
        combined = result.stdout + result.stderr
        try:
            actual_ids = extract_failing_test_ids(combined)
        except Exception:
            actual_ids = []
        if compare_to_manifest(actual_ids, accepted_known_failures)["is_match"]:
            break
    return result


@pytest.fixture(scope="module")
def captured_evidence_log(real_pytest_run, real_gut_run) -> Path:
    """Writes the RAW captured stdout+stderr of both real subprocess
    invocations above to a gitignored log artifact (test_criteria #4;
    FEAT-360/DEF-VER-001: no longer a committed path, see
    CAPTURED_EVIDENCE_LOG_PATH's own doc comment above) -- first-party,
    greppable evidence a future reviewer can inspect directly, rather than
    relying on commit-message narration (the exact DEF-001
    audit gap this feature closes)."""
    sections = [
        "=" * 78,
        "tests/integration/test_def001_gate_evidence.py -- captured raw evidence",
        "Regenerated on every real run of this suite; see git history for prior captures.",
        "=" * 78,
        "",
        "---- `python -m pytest -q --tb=short` ----",
        f"exit code: {real_pytest_run.returncode}",
        "---- combined stdout+stderr ----",
        real_pytest_run.stdout + real_pytest_run.stderr,
        "",
        "---- `godot --headless --path <repo_root> -- --gut-run-all` ----",
        f"exit code: {real_gut_run.returncode}",
        "---- combined stdout+stderr ----",
        real_gut_run.stdout + real_gut_run.stderr,
        "",
    ]
    CAPTURED_EVIDENCE_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CAPTURED_EVIDENCE_LOG_PATH.write_text("\n".join(sections))
    return CAPTURED_EVIDENCE_LOG_PATH


class TestRealPytestInvocation:
    """Real invocation: `python -m pytest -q --tb=short` from within the
    harness completes and its exit code is captured and asserted to be 0."""

    def test_pytest_subprocess_actually_completed(self, real_pytest_run):
        assert real_pytest_run.returncode is not None

    def test_pytest_exit_code_is_zero(self, real_pytest_run):
        assert real_pytest_run.returncode == 0, (
            "the real `python -m pytest -q --tb=short` subprocess must exit 0.\n"
            f"STDOUT:\n{_tail(real_pytest_run.stdout)}\nSTDERR:\n{_tail(real_pytest_run.stderr)}"
        )

    def test_pytest_output_reports_a_real_completed_run(self, real_pytest_run):
        combined = real_pytest_run.stdout + real_pytest_run.stderr
        assert re.search(r"\d+ passed", combined), (
            "expected the real pytest subprocess's own summary line "
            f"(e.g. '410 passed...') in its output; found none.\n{_tail(combined)}"
        )


class TestRealGutInvocation:
    """Real `godot --headless --path <repo_root> -- --gut-run-all`
    invocation, exit code captured, and stdout's failing-test-id set
    asserted to exactly match ci/accepted_known_failures.json (FEAT-350;
    resolves DEF-001/DEF-003/DEF-005's hardcoded-literal contradiction --
    see module doc's design note)."""

    def test_gut_subprocess_actually_completed(self, real_gut_run):
        assert real_gut_run.returncode is not None

    def test_gut_output_is_a_real_parseable_summary(self, real_gut_run):
        combined = real_gut_run.stdout + real_gut_run.stderr
        parsed = parse_gut_summary(combined)  # raises loudly if unparseable
        assert "failing" in parsed
        assert "passing" in parsed

    def test_gut_failing_test_ids_exactly_match_the_accepted_manifest(
        self, real_gut_run, accepted_known_failures
    ):
        """The PRIMARY real-invocation gate (test_criteria #2/#6): the
        exact SET of failing test identities the real run produced must
        equal ci/accepted_known_failures.json exactly -- no unexpected new
        failure, and no manifest entry that has unexpectedly started
        passing. A reverted FIX-001..FIX-004 fix, or any other regression,
        always produces an identifier absent from the manifest, so it
        always surfaces here regardless of the exact total count -- this
        is what makes the gate real and non-tautological (test_criteria
        #6), not a hand-copied literal list that could quietly drift out
        of sync with the actual policy."""
        combined = real_gut_run.stdout + real_gut_run.stderr
        actual_ids = extract_failing_test_ids(combined)
        result = compare_to_manifest(actual_ids, accepted_known_failures)
        assert result["is_match"], (
            "the real GUT run's failing-test-id set does not exactly match "
            "ci/accepted_known_failures.json (this is either a genuine "
            "regression, or a legitimately new pre-existing failure that "
            "needs to be triaged and added to the manifest).\n"
            f"Unexpected failures (failing now, not in the manifest): {result['unexpected_failures']}\n"
            f"Unexpectedly passing (in the manifest, but not actually failing): {result['unexpectedly_passing']}\n"
            f"{_tail(combined)}"
        )

    def test_gut_exit_code_is_zero(self, real_gut_run):
        """test_criteria #2: real invocation completes with exit code 0.
        tests/runner/headless_runner.gd wires ci/gate_exit_policy.gd in as
        GUT's post_run_script hook (FEAT-348/DEF-003), so the real process
        exit code is decided by the SAME manifest-equality policy the test
        above independently re-derives in pure Python. Asserting a plain
        `== 0` here (rather than deriving an "expected" exit code from a
        separately-brittle count) is only correct BECAUSE a manifest-exact
        match is the ONLY way ci/gate_exit_policy.gd ever produces exit
        code 0 -- when this assertion and the one above both pass, that is
        first-party, dual-implementation proof the gate is wired
        end-to-end correctly, not merely a Python-side parsing exercise."""
        assert real_gut_run.returncode == 0, (
            "expected exit code 0 (accepted-known-failures manifest match, "
            "per ci/gate_exit_policy.gd's post_run_script hook); got "
            f"{real_gut_run.returncode}.\n"
            f"STDOUT:\n{_tail(real_gut_run.stdout)}\nSTDERR:\n{_tail(real_gut_run.stderr)}"
        )


class TestGateIsARealNonTautologicalGate:
    """test_criteria #6: 'The harness itself fails ... if run against a
    repository state where any of FIX-001..FIX-004's fixes have been
    reverted, proving it is a real gate and not a tautology.'

    Demonstrated two ways: (a) the regressed FIXTURE (mirroring exactly
    what a reverted fix's real GUT output would look like) mismatches the
    REAL, committed, empty manifest below; and (b)
    TestRealGutInvocation.test_gut_failing_test_ids_exactly_match_the_accepted_manifest
    above runs that SAME identity check against the real subprocess's real
    output every time this suite runs -- so reverting any of iteration-U's
    or FIX-001..FIX-004's fixes (which always produces an identifier never
    seen in the manifest) trips that assertion immediately, the next time
    this suite is actually run against the reverted repository."""

    def test_regressed_fixture_mismatches_the_real_committed_manifest(self, regressed_output):
        accepted = load_accepted_known_failures()
        ids = extract_failing_test_ids(regressed_output)
        result = compare_to_manifest(ids, accepted)
        assert result["is_match"] is False
        assert result["unexpected_failures"] != []


class TestCapturedEvidenceArtifact:
    """test_criteria #4: 'Raw captured stdout from both real invocations
    is written to a committed artifact path and is non-empty and
    greppable.'"""

    def test_artifact_file_exists_and_is_nonempty(self, captured_evidence_log):
        assert captured_evidence_log.exists()
        content = captured_evidence_log.read_text()
        assert len(content) > 0

    def test_artifact_is_greppable_for_the_gut_summary_lines(self, captured_evidence_log):
        content = captured_evidence_log.read_text()
        # "Passing Tests" is always present. "Failing Tests" is only printed
        # by GUT when the count is non-zero (see parse_gut_summary's doc).
        assert "Passing Tests" in content

    def test_artifact_is_greppable_for_the_pytest_result_line(self, captured_evidence_log):
        content = captured_evidence_log.read_text()
        assert re.search(r"\d+ passed", content) is not None

    def test_artifact_records_both_real_exit_codes(self, captured_evidence_log, real_pytest_run, real_gut_run):
        content = captured_evidence_log.read_text()
        assert f"exit code: {real_pytest_run.returncode}" in content
        assert f"exit code: {real_gut_run.returncode}" in content
