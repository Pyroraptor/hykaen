"""
tests/unit/test_ci_spec_approval_hardening_feat084.py

Pytest suite for FEAT-084: CI Spec-Approval Linter Hardening and Author
Signature Correction.

Validates all test criteria from the feature spec:
  1. lint-spec-approval-marker step requires 'Guy Verisage' specifically
     (not just any non-empty signer — tightens the previous broad grep).
  2. New lint-spec-status-approved step: greps '#+STATUS: APPROVED' and
     exits 1 if status is DRAFT or missing.
  3. lint-spec-no-placeholder step is confirmed present (regression check).
  4. Bash smoke: grep against file with '#+APPROVAL: Sharding' exits 1.
  5. Bash smoke: grep against file with 'Guy Verisage' + 'APPROVED' exits 0.
  6. docs/hollow-world-v0-spec.org #+APPROVAL line reads 'Guy Verisage —
     reviewed 2026-06-29'.
  7. docs/hollow-world-v0-spec.org #+STATUS line reads 'APPROVED'.
  8. No unchecked Org-mode checkboxes ([ ]) remain in the spec.
"""

import re
import subprocess
from pathlib import Path

import pytest
import yaml


# ── Fixtures ───────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def repo_root() -> Path:
    """Absolute path to the repository root (where project.godot lives)."""
    return Path(__file__).parent.parent.parent


@pytest.fixture(scope="module")
def workflow_path(repo_root) -> Path:
    return repo_root / ".github" / "workflows" / "test.yml"


@pytest.fixture(scope="module")
def workflow(workflow_path) -> dict:
    with workflow_path.open() as f:
        raw = yaml.safe_load(f)
    # PyYAML parses bare `on:` as boolean True; normalise to string key.
    if True in raw and "on" not in raw:
        raw["on"] = raw.pop(True)
    return raw


@pytest.fixture(scope="module")
def spec_file(repo_root) -> Path:
    return repo_root / "docs" / "hollow-world-v0-spec.org"


@pytest.fixture(scope="module")
def spec_content(spec_file) -> str:
    return spec_file.read_text()


def _all_steps(workflow: dict) -> list:
    return workflow.get("jobs", {}).get("test", {}).get("steps", [])


def _all_run_blocks(workflow: dict) -> str:
    """Concatenate every 'run' block from all test job steps."""
    steps = _all_steps(workflow)
    return "\n".join(step.get("run", "") for step in steps if isinstance(step, dict))


# ── 1. lint-spec-approval-marker step requires 'Guy Verisage' ─────────────────

class TestApprovalMarkerHardened:
    """The lint-spec-approval-marker step must grep for 'Guy Verisage'
    specifically, not just any non-empty #+APPROVAL: content."""

    def test_approval_marker_step_exists(self, workflow):
        """A step named lint-spec-approval-marker must exist."""
        steps = _all_steps(workflow)
        names = [s.get("name", "") for s in steps if isinstance(s, dict)]
        assert "lint-spec-approval-marker" in names, (
            "test.yml must contain a step named 'lint-spec-approval-marker'"
        )

    def test_approval_marker_step_greps_for_guy_verisage(self, workflow):
        """lint-spec-approval-marker run block must grep for 'Guy Verisage',
        not merely for a non-empty #+APPROVAL: line."""
        steps = _all_steps(workflow)
        approval_step = next(
            (s for s in steps if isinstance(s, dict)
             and s.get("name") == "lint-spec-approval-marker"),
            None,
        )
        assert approval_step is not None, (
            "lint-spec-approval-marker step not found"
        )
        run_block = approval_step.get("run", "")
        assert "Guy Verisage" in run_block, (
            "lint-spec-approval-marker step must grep for 'Guy Verisage' "
            "to reject AI-signed stubs (FEAT-084 / DEF-001)"
        )

    def test_approval_marker_step_uses_extended_regex(self, workflow):
        """The grep must use -E or -P to match #\\+APPROVAL:.*Guy Verisage.

        Note: in extended regex (grep -E), '+' is a quantifier, so the literal
        '+' in '#+APPROVAL:' must be escaped as '\\+' giving '#\\+APPROVAL:'.
        """
        steps = _all_steps(workflow)
        approval_step = next(
            (s for s in steps if isinstance(s, dict)
             and s.get("name") == "lint-spec-approval-marker"),
            None,
        )
        assert approval_step is not None
        run_block = approval_step.get("run", "")
        # Must use extended regex (-E or -P) with the pattern containing .*
        has_extended = re.search(r'grep\s+-[^\'"\n]*E', run_block) is not None
        has_pattern_with_dot = ".*Guy Verisage" in run_block or "Guy Verisage" in run_block
        assert has_extended and has_pattern_with_dot, (
            "lint-spec-approval-marker must use 'grep -E' with pattern "
            "'#\\+APPROVAL:.*Guy Verisage' to require the author's full name"
        )


# ── 2. New lint-spec-status-approved step ─────────────────────────────────────

class TestStatusApprovedStepAdded:
    """A new lint-spec-status-approved step must exist and grep for
    '#+STATUS: APPROVED', exiting 1 if status is DRAFT or missing."""

    def test_status_approved_step_exists(self, workflow):
        """A step named 'lint-spec-status-approved' must be present."""
        steps = _all_steps(workflow)
        names = [s.get("name", "") for s in steps if isinstance(s, dict)]
        assert "lint-spec-status-approved" in names, (
            "test.yml must contain a step named 'lint-spec-status-approved' "
            "(FEAT-084 adds this new gate)"
        )

    def test_status_approved_step_greps_for_status_approved(self, workflow):
        """The step's run block must grep for '#+STATUS: APPROVED'."""
        steps = _all_steps(workflow)
        status_step = next(
            (s for s in steps if isinstance(s, dict)
             and s.get("name") == "lint-spec-status-approved"),
            None,
        )
        assert status_step is not None, "lint-spec-status-approved step not found"
        run_block = status_step.get("run", "")
        assert "#+STATUS: APPROVED" in run_block, (
            "lint-spec-status-approved step must grep for '#+STATUS: APPROVED' "
            "so a DRAFT status is rejected"
        )

    def test_status_approved_step_exits_nonzero_on_draft(self, tmp_path):
        """Dry-run: file with #+STATUS: DRAFT exits 1 from the new gate."""
        draft_spec = tmp_path / "spec_draft.org"
        draft_spec.write_text(
            "#+TITLE: Test\n"
            "#+APPROVAL: Guy Verisage — reviewed 2026-06-29\n"
            "#+STATUS: DRAFT\n"
        )
        result = subprocess.run(
            ["bash", "-c",
             f"grep '#+STATUS: APPROVED' '{draft_spec}' && exit 0 || exit 1"],
            capture_output=True,
        )
        assert result.returncode == 1, (
            "lint-spec-status-approved must exit 1 when #+STATUS: is DRAFT"
        )

    def test_status_approved_step_exits_zero_on_approved(self, tmp_path):
        """Dry-run: file with #+STATUS: APPROVED exits 0."""
        approved_spec = tmp_path / "spec_approved.org"
        approved_spec.write_text(
            "#+TITLE: Test\n"
            "#+APPROVAL: Guy Verisage — reviewed 2026-06-29\n"
            "#+STATUS: APPROVED\n"
        )
        result = subprocess.run(
            ["bash", "-c",
             f"grep '#+STATUS: APPROVED' '{approved_spec}' && exit 0 || exit 1"],
            capture_output=True,
        )
        assert result.returncode == 0, (
            "lint-spec-status-approved must exit 0 when #+STATUS: APPROVED"
        )

    def test_status_approved_step_exits_nonzero_on_missing_status(self, tmp_path):
        """Dry-run: file with no #+STATUS: line exits 1."""
        no_status_spec = tmp_path / "spec_no_status.org"
        no_status_spec.write_text(
            "#+TITLE: Test\n"
            "#+APPROVAL: Guy Verisage — reviewed 2026-06-29\n"
        )
        result = subprocess.run(
            ["bash", "-c",
             f"grep '#+STATUS: APPROVED' '{no_status_spec}' && exit 0 || exit 1"],
            capture_output=True,
        )
        assert result.returncode == 1, (
            "lint-spec-status-approved must exit 1 when #+STATUS: is missing"
        )


# ── 3. lint-spec-no-placeholder step is present (regression) ──────────────────

class TestNoPlaceholderStepPresent:
    """lint-spec-no-placeholder must still be present after FEAT-084 changes."""

    def test_no_placeholder_step_exists(self, workflow):
        """A step named 'lint-spec-no-placeholder' must exist."""
        steps = _all_steps(workflow)
        names = [s.get("name", "") for s in steps if isinstance(s, dict)]
        assert "lint-spec-no-placeholder" in names, (
            "test.yml must still contain lint-spec-no-placeholder (regression guard)"
        )

    def test_no_placeholder_step_greps_for_placeholder(self, workflow):
        """The step must grep for PLACEHOLDER text."""
        steps = _all_steps(workflow)
        placeholder_step = next(
            (s for s in steps if isinstance(s, dict)
             and s.get("name") == "lint-spec-no-placeholder"),
            None,
        )
        assert placeholder_step is not None
        run_block = placeholder_step.get("run", "")
        assert "PLACEHOLDER" in run_block, (
            "lint-spec-no-placeholder step must grep for 'PLACEHOLDER'"
        )

    def test_no_placeholder_step_exits_1_on_placeholder(self, tmp_path):
        """Dry-run: file containing PLACEHOLDER exits 1."""
        stub_spec = tmp_path / "spec_with_placeholder.org"
        stub_spec.write_text(
            "#+TITLE: Test\n"
            "#+APPROVAL: PLACEHOLDER — replace with a genuine sign-off\n"
        )
        result = subprocess.run(
            ["bash", "-c",
             f"grep -q PLACEHOLDER '{stub_spec}' "
             f"&& {{ echo 'GATE FAIL' >&2; exit 1; }} || true"],
            capture_output=True,
        )
        assert result.returncode == 1, (
            "lint-spec-no-placeholder must exit 1 when PLACEHOLDER is found"
        )


# ── 4. Bash smoke: Sharding signature → exit 1 ────────────────────────────────

class TestBashSmokeShardingRejectsToExit1:
    """Bash smoke: grep for 'Guy Verisage' against a file containing only
    '#+APPROVAL: Sharding' produces exit code 1."""

    def test_sharding_approval_exits_1_from_hardened_grep(self, tmp_path):
        """A file signed by 'Sharding' must fail the hardened linter.

        Uses grep -E '#\\+APPROVAL:.*Guy Verisage' — the \\+ escapes the
        literal '+' character so extended regex treats it as a literal, not
        a quantifier.
        """
        sharding_spec = tmp_path / "spec_sharding.org"
        sharding_spec.write_text(
            "#+TITLE: Test\n"
            "#+APPROVAL: Sharding — reviewed 2026-06-29 — approved\n"
            "#+STATUS: APPROVED\n"
        )
        result = subprocess.run(
            ["bash", "-c",
             f"grep -E '#\\+APPROVAL:.*Guy Verisage' '{sharding_spec}' "
             f"&& exit 0 || exit 1"],
            capture_output=True,
        )
        assert result.returncode == 1, (
            "Hardened linter (grep -E '#\\+APPROVAL:.*Guy Verisage') must reject "
            "a file signed by 'Sharding' — exit code must be 1"
        )


# ── 5. Bash smoke: Guy Verisage + APPROVED → exit 0 ──────────────────────────

class TestBashSmokeGuyVerisagePassesToExit0:
    """Bash smoke: grep against a file containing '#+APPROVAL: Guy Verisage...'
    and '#+STATUS: APPROVED' produces exit code 0."""

    def test_guy_verisage_and_approved_status_exits_0(self, tmp_path):
        """A file with the correct author and APPROVED status passes all linters.

        Uses grep -E '#\\+APPROVAL:.*Guy Verisage' — the \\+ escapes the
        literal '+' so extended regex treats it as literal, not a quantifier.
        """
        approved_spec = tmp_path / "spec_approved.org"
        approved_spec.write_text(
            "#+TITLE: Test\n"
            "#+APPROVAL: Guy Verisage — reviewed 2026-06-29\n"
            "#+STATUS: APPROVED\n"
        )
        approval_result = subprocess.run(
            ["bash", "-c",
             f"grep -E '#\\+APPROVAL:.*Guy Verisage' '{approved_spec}' "
             f"&& exit 0 || exit 1"],
            capture_output=True,
        )
        assert approval_result.returncode == 0, (
            "Hardened linter must exit 0 when '#+APPROVAL: Guy Verisage' is present"
        )
        status_result = subprocess.run(
            ["bash", "-c",
             f"grep '#+STATUS: APPROVED' '{approved_spec}' && exit 0 || exit 1"],
            capture_output=True,
        )
        assert status_result.returncode == 0, (
            "Status linter must exit 0 when '#+STATUS: APPROVED' is present"
        )


# ── 6. docs/hollow-world-v0-spec.org #+APPROVAL reads 'Guy Verisage' ──────────

class TestSpecApprovalLine:
    """The real spec file must have #+APPROVAL: containing 'Guy Verisage'."""

    def test_spec_approval_contains_guy_verisage(self, spec_content):
        """#+APPROVAL: line must contain 'Guy Verisage'."""
        approval_lines = [
            line for line in spec_content.splitlines()
            if line.startswith("#+APPROVAL:")
        ]
        assert approval_lines, (
            "docs/hollow-world-v0-spec.org must contain a #+APPROVAL: header line"
        )
        approval_line = approval_lines[0]
        assert "Guy Verisage" in approval_line, (
            f"#+APPROVAL: line must contain 'Guy Verisage', got: {approval_line!r}"
        )

    def test_spec_approval_does_not_contain_sharding(self, spec_content):
        """#+APPROVAL: line must NOT contain 'Sharding' (the AI handle)."""
        approval_lines = [
            line for line in spec_content.splitlines()
            if line.startswith("#+APPROVAL:")
        ]
        assert approval_lines, "#+APPROVAL: line must be present"
        approval_line = approval_lines[0]
        assert "Sharding" not in approval_line, (
            f"#+APPROVAL: must not be signed by AI handle 'Sharding': {approval_line!r}"
        )

    def test_spec_approval_contains_review_date(self, spec_content):
        """#+APPROVAL: line should contain a review date (2026-06-29 or later)."""
        approval_lines = [
            line for line in spec_content.splitlines()
            if line.startswith("#+APPROVAL:")
        ]
        assert approval_lines, "#+APPROVAL: line must be present"
        approval_line = approval_lines[0]
        # Pattern: 4-digit year, dash, 2-digit month, dash, 2-digit day
        assert re.search(r'\d{4}-\d{2}-\d{2}', approval_line), (
            f"#+APPROVAL: line should include a review date (YYYY-MM-DD): {approval_line!r}"
        )

    def test_real_spec_passes_hardened_approval_linter(self, spec_file):
        """Dry-run: running the hardened grep against the real spec exits 0."""
        result = subprocess.run(
            ["bash", "-c",
             f"grep -E '#\\+APPROVAL:.*Guy Verisage' '{spec_file}' "
             f"&& exit 0 || exit 1"],
            capture_output=True,
        )
        assert result.returncode == 0, (
            "Real spec must pass the hardened linter: "
            "grep -E '#\\+APPROVAL:.*Guy Verisage' docs/hollow-world-v0-spec.org"
        )


# ── 7. docs/hollow-world-v0-spec.org #+STATUS reads 'APPROVED' ────────────────

class TestSpecStatusLine:
    """The real spec file must have #+STATUS: APPROVED in its header."""

    def test_spec_has_status_approved_header(self, spec_content):
        """#+STATUS: APPROVED must appear in the spec header."""
        assert "#+STATUS: APPROVED" in spec_content, (
            "docs/hollow-world-v0-spec.org must contain '#+STATUS: APPROVED' "
            "in its Org header section (FEAT-084)"
        )

    def test_spec_status_not_draft(self, spec_content):
        """The #+STATUS: header line must NOT read DRAFT."""
        status_headers = [
            line for line in spec_content.splitlines()
            if line.startswith("#+STATUS:")
        ]
        for line in status_headers:
            assert "DRAFT" not in line, (
                f"#+STATUS: header must not read DRAFT: {line!r}"
            )

    def test_real_spec_passes_status_approved_linter(self, spec_file):
        """Dry-run: running the status grep against the real spec exits 0."""
        result = subprocess.run(
            ["bash", "-c",
             f"grep '#+STATUS: APPROVED' '{spec_file}' && exit 0 || exit 1"],
            capture_output=True,
        )
        assert result.returncode == 0, (
            "Real spec must pass the status linter: "
            "grep '#+STATUS: APPROVED' docs/hollow-world-v0-spec.org"
        )


# ── 8. No unchecked Org-mode checkboxes ───────────────────────────────────────

class TestNoUncheckedCheckboxes:
    """No unchecked Org-mode checkboxes (- [ ] or * [ ]) may remain in
    the spec that gate author approval."""

    def test_no_unchecked_todo_checkboxes(self, spec_content):
        """The spec must not contain any unchecked '[ ]' checkboxes."""
        unchecked_pattern = re.compile(r'- \[ \]|\* \[ \]')
        unchecked = [
            (i + 1, line)
            for i, line in enumerate(spec_content.splitlines())
            if unchecked_pattern.search(line)
        ]
        assert not unchecked, (
            "docs/hollow-world-v0-spec.org contains unchecked checkboxes "
            "([ ]) that must be resolved before approval:\n"
            + "\n".join(f"  line {lineno}: {line}" for lineno, line in unchecked)
        )


# ── Regression: all existing CI gates still present ───────────────────────────

class TestExistingGatesRegression:
    """Prior linter steps must not be removed or broken by FEAT-084 changes."""

    def test_domain_purity_linter_still_present(self, workflow):
        run_text = _all_run_blocks(workflow)
        assert "extends Node" in run_text and "core/" in run_text

    def test_binary_resource_linter_still_present(self, workflow):
        run_text = _all_run_blocks(workflow)
        assert ".scn" in run_text or ".res" in run_text

    def test_injected_rng_linter_still_present(self, workflow):
        run_text = _all_run_blocks(workflow)
        assert ("randf" in run_text or "randi" in run_text) and "rng.gd" in run_text

    def test_content_keywords_linter_still_present(self, workflow):
        run_text = _all_run_blocks(workflow)
        assert "lint-spec-content-keywords" in "\n".join(
            s.get("name", "") for s in _all_steps(workflow) if isinstance(s, dict)
        )

    def test_gut_run_all_still_present(self, workflow):
        run_text = _all_run_blocks(workflow)
        assert "--gut-run-all" in run_text

    def test_artifact_upload_still_present(self, workflow):
        steps = _all_steps(workflow)
        upload_steps = [
            s for s in steps
            if isinstance(s, dict) and "upload-artifact" in s.get("uses", "")
        ]
        assert upload_steps, "upload-artifact step must still exist"
