"""
tests/integration/test_out_of_scope_regression_guard.py

Pytest suite for FEAT-349 (US-007; resolves DEF-004/DEF-006).

── Background ──

DEF-004/DEF-006 named a triage gap: the "single" LateSpawnHighRoll domain-logic
gap iteration-U originally described as living in ONE test actually spans 4
test functions inside tests/unit/test_opportunistic_strike_initiative_ordering.gd
(test_candidate_reactors_ordered_by_rolled_initiative_not_spawn_order,
test_ordering_is_stable_for_equal_initiative_rolls,
test_consistent_ordering_does_not_trigger_the_assertion,
test_two_eligible_reactors_resolve_in_initiative_order -- see
tests/integration/test_def001_gate_evidence.py's module doc, point 3), plus two
additional out-of-scope files (tests/integration/
test_opportunistic_strike_ranged_reactor_excluded.gd and tests/integration/
test_steel_thread_scenario_boot_e2e.gd -- see that same module doc, point 4)
that prior evidence acknowledged in prose but never formally ticketed into
ci/accepted_known_failures.json (created by FIX-003/FEAT-348) or protected by
any automated diff-based guard.

── What this suite actually found, and why the manifest stays empty ──

Triaging this properly means re-measuring reality, not copying stale prose
forward -- exactly the discipline test_def001_gate_evidence.py's own module
doc established ("real evidence over narration"). A real, non-mocked
`godot --headless --path <repo_root> -- --gut-run-all` run against this
feature's HEAD (captured 2026-07-27; see ci/accepted_known_failures.json's
own FEAT-349 triage note) found ZERO failing tests across all three named
files: the LateSpawnHighRoll gap and the two sibling defects were already
fixed by prior iterations (commit e42ff80 "fix(tests): migrate 4 pre-existing
post-Iter-T/Q test failures to 0 failing" and FEAT-346's
ExplorationModeController migration sweep), both of which landed before this
triage ever ran.

ci/gate_exit_policy.gd's `evaluate()` treats a manifest entry for an ACTUALLY
PASSING test as an "unexpectedly_passing" mismatch -- i.e. it turns the gate
RED, the exact opposite of "accepted". So adding entries for these now-passing
functions would not "match the real GUT output exactly" (this feature's own
test_criteria #1) -- it would contradict it, and would break test_criteria #3
("exit code 0 via gate_exit_policy"). The correct, real-output-matching
manifest state is therefore the EMPTY list ci/accepted_known_failures.json
already carries -- this suite's TestAcceptedKnownFailuresManifestTriage class
below verifies that state holds, structurally, on every run.

What DOES need a durable guard is the other half of DEF-004/DEF-006's ask:
making sure this triage's scope-containment finding cannot silently rot --
if one of these three files' content drifts (whether re-widening the
LateSpawnHighRoll gap, or masking it, or any unrelated edit), that must be
caught explicitly rather than passing by accident because the manifest
happened to still read empty. TestByteIdenticalRegressionGuard below is that
guard: it recomputes each file's live SHA-256 and fails loud against the
pinned tests/integration/fixtures/baseline_out_of_scope_hashes.json baseline
on any drift -- extending ADR-010's diff-based scope-containment pattern
(originally scoped to US-007/FEAT-232's single ranged-reactor file only) to
cover all three files this iteration formally ticketed.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
FIXTURES_DIR = Path(__file__).parent / "fixtures"
BASELINE_HASHES_PATH = FIXTURES_DIR / "baseline_out_of_scope_hashes.json"
ACCEPTED_KNOWN_FAILURES_PATH = REPO_ROOT / "ci" / "accepted_known_failures.json"

# The exact three files DEF-004/DEF-006 named as needing formal triage into
# the accepted-known-failures manifest, relative to the repo root -- mirrors
# the paths recorded as keys in baseline_out_of_scope_hashes.json.
OUT_OF_SCOPE_FILES = [
    "tests/unit/test_opportunistic_strike_initiative_ordering.gd",
    "tests/integration/test_opportunistic_strike_ranged_reactor_excluded.gd",
    "tests/integration/test_steel_thread_scenario_boot_e2e.gd",
]

# The 4 test functions DEF-004/DEF-006 identified as making up the
# "LateSpawnHighRoll" gap inside test_opportunistic_strike_initiative_ordering.gd
# (see this file's module doc + test_def001_gate_evidence.py's module doc,
# point 3). Referenced here purely for documentation/traceability -- this
# suite does not re-derive test names from file content; the byte-identical
# hash guard below is what actually protects the file.
LATE_SPAWN_HIGH_ROLL_GAP_FUNCTIONS = [
    "test_candidate_reactors_ordered_by_rolled_initiative_not_spawn_order",
    "test_ordering_is_stable_for_equal_initiative_rolls",
    "test_consistent_ordering_does_not_trigger_the_assertion",
    "test_two_eligible_reactors_resolve_in_initiative_order",
]


def sha256_of(path: Path) -> str:
    """Returns the lowercase hex SHA-256 digest of `path`'s raw bytes -- the
    same digest form used throughout baseline_out_of_scope_hashes.json."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


@pytest.fixture(scope="module")
def baseline_hashes() -> dict:
    with BASELINE_HASHES_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


@pytest.fixture(scope="module")
def accepted_known_failures_manifest() -> dict:
    with ACCEPTED_KNOWN_FAILURES_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


# ══════════════════════════════════════════════════════════════════════════
# The baseline fixture itself: well-formed, and covers exactly the three
# named files -- no fewer, no silently-added extras.
# ══════════════════════════════════════════════════════════════════════════


class TestBaselineFixtureShape:
    def test_baseline_fixture_file_exists(self):
        assert BASELINE_HASHES_PATH.exists(), (
            f"expected baseline fixture at {BASELINE_HASHES_PATH}"
        )

    def test_baseline_fixture_declares_sha256_algorithm(self, baseline_hashes):
        assert baseline_hashes.get("hash_algorithm") == "sha256"

    def test_baseline_fixture_covers_exactly_the_three_out_of_scope_files(
        self, baseline_hashes
    ):
        assert set(baseline_hashes["baseline_hashes"].keys()) == set(OUT_OF_SCOPE_FILES)

    @pytest.mark.parametrize("relative_path", OUT_OF_SCOPE_FILES)
    def test_baseline_entry_has_a_well_formed_64_char_hex_digest(
        self, baseline_hashes, relative_path
    ):
        entry = baseline_hashes["baseline_hashes"][relative_path]
        digest = entry["sha256"]
        assert len(digest) == 64, f"{relative_path}: expected a 64-char hex sha256 digest, got {digest!r}"
        int(digest, 16)  # raises ValueError if not valid hex

    @pytest.mark.parametrize("relative_path", OUT_OF_SCOPE_FILES)
    def test_baseline_entry_byte_length_matches_a_positive_integer(
        self, baseline_hashes, relative_path
    ):
        entry = baseline_hashes["baseline_hashes"][relative_path]
        assert isinstance(entry["byte_length"], int)
        assert entry["byte_length"] > 0


# ══════════════════════════════════════════════════════════════════════════
# The regression guard itself (test_criteria #2): every one of the three
# files' LIVE content must hash byte-identically to the pinned baseline.
# ══════════════════════════════════════════════════════════════════════════


class TestByteIdenticalRegressionGuard:
    @pytest.mark.parametrize("relative_path", OUT_OF_SCOPE_FILES)
    def test_out_of_scope_file_still_exists(self, relative_path):
        target = REPO_ROOT / relative_path
        assert target.exists(), (
            f"{relative_path} is one of the three files this feature formally "
            "scoped into the out-of-scope regression guard -- it must not be "
            "deleted or renamed without deliberately regenerating "
            f"{BASELINE_HASHES_PATH} to reflect that decision."
        )

    @pytest.mark.parametrize("relative_path", OUT_OF_SCOPE_FILES)
    def test_out_of_scope_file_is_byte_identical_to_its_pinned_baseline(
        self, baseline_hashes, relative_path
    ):
        target = REPO_ROOT / relative_path
        expected = baseline_hashes["baseline_hashes"][relative_path]
        actual_digest = sha256_of(target)
        actual_length = target.stat().st_size

        assert actual_digest == expected["sha256"], (
            f"{relative_path} has DRIFTED from its pinned pre-iteration "
            f"baseline (expected sha256={expected['sha256']}, got "
            f"{actual_digest}). This file is one of the three FEAT-349 "
            "scoped into the out-of-scope regression guard (DEF-004/DEF-006) "
            "-- any edit to it (fixing the LateSpawnHighRoll gap, masking "
            "it, or an unrelated change) must be a deliberate, reviewed "
            f"decision that also regenerates {BASELINE_HASHES_PATH}, not a "
            "silent drift."
        )
        assert actual_length == expected["byte_length"], (
            f"{relative_path}'s byte length changed from "
            f"{expected['byte_length']} to {actual_length} -- see the "
            "sha256 assertion above for the full byte-identical contract."
        )

    def test_all_three_files_pass_the_guard_together(self, baseline_hashes):
        """A single, summarizing assertion (test_criteria #2's own framing:
        'computes and compares checksums of all three files ... and passes
        only when byte-identical') -- redundant with the parametrized checks
        above by design, so a future refactor of this file that accidentally
        drops the parametrized cases still has one assertion enforcing the
        full-set contract."""
        mismatches = []
        for relative_path in OUT_OF_SCOPE_FILES:
            target = REPO_ROOT / relative_path
            expected_digest = baseline_hashes["baseline_hashes"][relative_path]["sha256"]
            if not target.exists() or sha256_of(target) != expected_digest:
                mismatches.append(relative_path)
        assert mismatches == [], f"drifted out-of-scope files: {mismatches}"


# ══════════════════════════════════════════════════════════════════════════
# Manifest triage (test_criteria #1): ci/accepted_known_failures.json must
# match the real, measured GUT output exactly -- which, per the module doc
# above, means carrying NO entries for these three (currently fully-passing)
# files.
# ══════════════════════════════════════════════════════════════════════════


class TestAcceptedKnownFailuresManifestTriage:
    def test_manifest_file_exists_and_is_well_formed_json(self):
        assert ACCEPTED_KNOWN_FAILURES_PATH.exists()
        with ACCEPTED_KNOWN_FAILURES_PATH.open("r", encoding="utf-8") as handle:
            json.load(handle)  # raises loudly if malformed

    def test_manifest_has_the_accepted_known_failures_key_as_a_list(
        self, accepted_known_failures_manifest
    ):
        assert isinstance(accepted_known_failures_manifest["accepted_known_failures"], list)

    def test_manifest_carries_no_entries_for_any_of_the_three_out_of_scope_files(
        self, accepted_known_failures_manifest
    ):
        """Per ci/gate_exit_policy.gd's own evaluate() contract, a manifest
        entry for a test that is ACTUALLY PASSING trips the
        'unexpectedly_passing' mismatch branch and turns the gate red. A
        real, verified `godot --headless --path <repo_root> --
        --gut-run-all` run (see this file's module doc) found zero failing
        tests across all three files -- so, to match real GUT output
        exactly, none of the three files' res:// paths may appear as a
        manifest entry's script-path prefix."""
        entries = accepted_known_failures_manifest["accepted_known_failures"]
        for relative_path in OUT_OF_SCOPE_FILES:
            res_path = f"res://{relative_path}"
            offending = [entry for entry in entries if str(entry).startswith(res_path + "::")]
            assert offending == [], (
                f"ci/accepted_known_failures.json lists {offending} for "
                f"{relative_path}, but a real, measured GUT run found this "
                "file fully passing -- such an entry would make "
                "ci/gate_exit_policy.gd report an 'unexpectedly_passing' "
                "mismatch and fail the gate, not pass it."
            )

    def test_documents_the_late_spawn_high_roll_gap_functions_for_traceability(self):
        """Not a manifest assertion -- a structural guard on this suite's own
        documentation constant, so LATE_SPAWN_HIGH_ROLL_GAP_FUNCTIONS (used
        only in this file's module doc / traceability comments) can never
        silently drift to a different count than DEF-004's own '4 test
        functions' finding without this test flagging it."""
        assert len(LATE_SPAWN_HIGH_ROLL_GAP_FUNCTIONS) == 4
        assert len(set(LATE_SPAWN_HIGH_ROLL_GAP_FUNCTIONS)) == 4
