"""
tests/unit/test_ci_hardening_feat039.py

Pytest suite for FEAT-039: CI Pipeline Hardening.

Covers three coordinated improvements to test.yml + .gutconfig.json:

  1. DEF-002: GUT output capture — .gutconfig.json gains output_dir, test.yml
     redirects GUT output to gut_output.log so the artifact-upload step always
     captures a real, non-empty file.

  2. Godot version pin — the Godot download URL in test.yml uses a fully-
     hardcoded literal (no shell variable indirection) so the exact binary is
     immutable.

  3. DEF-001 (CI aspect) — two sequential grep linter steps assert that
     docs/hollow-world-v0-spec.org both (a) contains a #+APPROVAL: line and
     (b) does NOT contain the word PLACEHOLDER on that line.

All assertions are pure-Python filesystem / YAML / subprocess checks; no
running Godot binary is required.
"""

import json
import re
import subprocess
from pathlib import Path

import pytest
import yaml


# ── Fixtures ──────────────────────────────────────────────────────────────────

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
def gutconfig(repo_root) -> dict:
    return json.loads((repo_root / ".gutconfig.json").read_text())


@pytest.fixture(scope="module")
def spec_file(repo_root) -> Path:
    return repo_root / "docs" / "hollow-world-v0-spec.org"


def _all_run_blocks(workflow: dict) -> str:
    """Concatenate every 'run' block from all test job steps."""
    steps = workflow.get("jobs", {}).get("test", {}).get("steps", [])
    return "\n".join(step.get("run", "") for step in steps if isinstance(step, dict))


def _all_steps(workflow: dict) -> list:
    return workflow.get("jobs", {}).get("test", {}).get("steps", [])


# ── DEF-002: GUT output capture ───────────────────────────────────────────────

class TestGutOutputCapture:
    """DEF-002: .gutconfig.json must specify an output path; test.yml must
    produce gut_output.log so the artifact-upload step captures a real file."""

    def test_gutconfig_has_output_dir_key(self, gutconfig):
        """output_dir (or log_path) must exist in .gutconfig.json."""
        assert "output_dir" in gutconfig or "log_path" in gutconfig, (
            ".gutconfig.json must contain 'output_dir' or 'log_path' key "
            "so CI knows where GUT writes its output (DEF-002)"
        )

    def test_gutconfig_output_dir_is_non_empty_string(self, gutconfig):
        """The output path value must be a non-empty string."""
        path = gutconfig.get("output_dir") or gutconfig.get("log_path", "")
        assert isinstance(path, str) and len(path.strip()) > 0, (
            "output_dir / log_path in .gutconfig.json must be a non-empty string"
        )

    def test_workflow_gut_step_captures_to_log_file(self, workflow):
        """The GUT run step must pipe/redirect output to gut_output.log."""
        run_text = _all_run_blocks(workflow)
        assert "gut_output.log" in run_text, (
            "test.yml must redirect GUT output to 'gut_output.log' "
            "so the artifact-upload step always captures a non-empty file (DEF-002)"
        )

    def test_artifact_upload_covers_gut_output_log(self, workflow):
        """The upload-artifact step path must capture gut_output.log."""
        upload_steps = [
            s for s in _all_steps(workflow)
            if isinstance(s, dict) and "upload-artifact" in s.get("uses", "")
        ]
        assert upload_steps, "No upload-artifact step found"
        for step in upload_steps:
            path_val = str(step.get("with", {}).get("path", ""))
            if "gut_output.log" in path_val or "*.log" in path_val:
                return
        pytest.fail(
            "Artifact upload step must capture gut_output.log or *.log (DEF-002)"
        )

    def test_gut_step_preserves_exit_code_from_godot(self, workflow):
        """If GUT output is captured via tee/pipe, exit code must come from godot,
        not tee. The step must use pipefail or ${PIPESTATUS[0]} so CI correctly
        fails when tests fail."""
        run_text = _all_run_blocks(workflow)
        # Acceptable signals: pipefail, PIPESTATUS, or direct redirect (no pipe needed)
        has_pipefail = "pipefail" in run_text
        has_pipestatus = "PIPESTATUS" in run_text
        # Direct redirect to file (no pipe) also preserves exit code
        has_direct_redirect = (
            re.search(r'godot.*--gut-run-all.*>\s*gut_output\.log', run_text) is not None
        )
        assert has_pipefail or has_pipestatus or has_direct_redirect, (
            "When tee-ing GUT output, test.yml must preserve godot's exit code "
            "via pipefail, PIPESTATUS, or direct file redirect (not just tee)"
        )


# ── Godot version pin ─────────────────────────────────────────────────────────

class TestGodotVersionPin:
    """The Godot binary download URL must be a fully-hardcoded literal — no
    shell variable indirection and no mutable alias like 'latest'."""

    def test_godot_url_has_no_latest_keyword(self, workflow):
        """'latest' must not appear anywhere near the godot download."""
        run_text = _all_run_blocks(workflow)
        lines = run_text.splitlines()
        download_lines = [
            l for l in lines
            if ("curl" in l or "wget" in l) and "godot" in l.lower()
        ]
        assert download_lines, "Must have a curl/wget line downloading Godot"
        for line in download_lines:
            assert "latest" not in line.lower(), (
                f"Godot download line must not reference 'latest': {line.strip()}"
            )

    def test_godot_url_contains_literal_version_string(self, workflow):
        """The literal string '4.3-stable' must appear in the curl URL — not
        via a variable like ${GODOT_VERSION}."""
        run_text = _all_run_blocks(workflow)
        # The literal URL segment must be present
        assert "releases/download/4.3-stable/" in run_text, (
            "Godot download URL must contain the literal path segment "
            "'releases/download/4.3-stable/' (no shell variable indirection)"
        )

    def test_godot_download_references_pinned_binary_filename(self, workflow):
        """The exact binary filename Godot_v4.3-stable_linux.x86_64 must appear."""
        run_text = _all_run_blocks(workflow)
        assert "Godot_v4.3-stable_linux.x86_64" in run_text, (
            "Godot download must reference the pinned binary name "
            "'Godot_v4.3-stable_linux.x86_64'"
        )

    def test_godot_url_does_not_use_shell_variable_for_version(self, workflow):
        """${GODOT_VERSION} must NOT be used in the download URL — version must
        be hardcoded so it can't drift silently."""
        run_text = _all_run_blocks(workflow)
        assert "${GODOT_VERSION}" not in run_text, (
            "Godot download URL must not use shell variable ${GODOT_VERSION}; "
            "hardcode the version string directly in the URL"
        )


# ── DEF-001: Approval-marker linter steps ─────────────────────────────────────

class TestApprovalMarkerLinterSteps:
    """Two sequential grep steps in test.yml:
      (a) assert #+APPROVAL: is present — exit 1 if absent
      (b) assert PLACEHOLDER is absent from that line — exit 1 if present
    """

    def test_workflow_has_approval_presence_check(self, workflow):
        """test.yml must grep for #+APPROVAL: in the spec and exit 1 if absent."""
        run_text = _all_run_blocks(workflow)
        assert "#+APPROVAL:" in run_text, (
            "test.yml must contain a linter step that greps for '#+APPROVAL:' "
            "in docs/hollow-world-v0-spec.org (DEF-001)"
        )

    def test_workflow_has_placeholder_absence_check(self, workflow):
        """test.yml must grep for PLACEHOLDER and exit 1 if found."""
        run_text = _all_run_blocks(workflow)
        assert "PLACEHOLDER" in run_text, (
            "test.yml must contain a linter step checking that PLACEHOLDER "
            "does NOT appear in the approval line (DEF-001)"
        )

    def test_approval_presence_step_blocks_on_missing_approval(self, spec_file, tmp_path):
        """Dry-run: linter exits 1 when #+APPROVAL: is absent."""
        no_approval = tmp_path / "spec_no_approval.org"
        no_approval.write_text("#+TITLE: Test\n\n* No approval here.\n")
        result = subprocess.run(
            ["bash", "-c",
             f"grep -q '#+APPROVAL:' '{no_approval}' || exit 1"],
            capture_output=True,
        )
        assert result.returncode == 1, (
            "Approval-presence linter must exit 1 when #+APPROVAL: is absent"
        )

    def test_approval_presence_step_passes_when_approval_present(self, spec_file):
        """Dry-run: current spec has #+APPROVAL: so presence linter exits 0."""
        result = subprocess.run(
            ["bash", "-c",
             f"grep -q '#+APPROVAL:' '{spec_file}' || exit 1"],
            capture_output=True,
        )
        assert result.returncode == 0, (
            "Approval-presence linter must exit 0 when #+APPROVAL: is present"
        )

    def test_placeholder_linter_exits_1_when_placeholder_found(self, spec_file):
        """Dry-run: current spec DOES contain PLACEHOLDER — linter must exit 1."""
        result = subprocess.run(
            ["bash", "-c",
             f"grep -q PLACEHOLDER '{spec_file}' && exit 1 || exit 0"],
            capture_output=True,
        )
        assert result.returncode == 1, (
            "Anti-PLACEHOLDER linter must exit 1 when 'PLACEHOLDER' appears in spec"
        )

    def test_placeholder_linter_exits_0_when_placeholder_absent(self, tmp_path):
        """Dry-run: linter exits 0 when a genuine approval has no PLACEHOLDER."""
        good_spec = tmp_path / "spec_good.org"
        good_spec.write_text(
            "#+TITLE: Test\n"
            "#+APPROVAL: Guy Verisage — reviewed 2026-07-01 — approved for v0\n"
        )
        result = subprocess.run(
            ["bash", "-c",
             f"grep -q PLACEHOLDER '{good_spec}' && exit 1 || exit 0"],
            capture_output=True,
        )
        assert result.returncode == 0, (
            "Anti-PLACEHOLDER linter must exit 0 when 'PLACEHOLDER' is absent"
        )

    def test_approval_linter_step_count(self, workflow):
        """There must be at least two linter steps related to the spec approval:
        one for presence of #+APPROVAL: and one for absence of PLACEHOLDER."""
        steps = _all_steps(workflow)
        run_blocks = [s.get("run", "") for s in steps if isinstance(s, dict)]
        steps_with_approval = [b for b in run_blocks if "#+APPROVAL:" in b]
        steps_with_placeholder = [b for b in run_blocks if "PLACEHOLDER" in b]
        assert steps_with_approval, (
            "At least one step must grep for '#+APPROVAL:'"
        )
        assert steps_with_placeholder, (
            "At least one step must grep for 'PLACEHOLDER' absence"
        )


# ── Regression: existing lint gates still present ─────────────────────────────

class TestExistingLintersPreserved:
    """All lint gates from prior features must still be present after FEAT-039
    modifies test.yml."""

    def test_domain_purity_linter_adr001_still_present(self, workflow):
        run_text = _all_run_blocks(workflow)
        assert "extends Node" in run_text and "core/" in run_text, (
            "ADR-001 domain-purity linter must still be present (regression)"
        )

    def test_binary_resource_linter_adr009_still_present(self, workflow):
        run_text = _all_run_blocks(workflow)
        assert ".scn" in run_text or ".res" in run_text, (
            "ADR-009 binary-resource linter must still be present (regression)"
        )

    def test_injected_rng_linter_adr002_still_present(self, workflow):
        run_text = _all_run_blocks(workflow)
        assert ("randf" in run_text or "randi" in run_text) and "rng.gd" in run_text, (
            "ADR-002 injected-RNG linter must still be present (regression)"
        )

    def test_gut_run_all_still_present(self, workflow):
        run_text = _all_run_blocks(workflow)
        assert "--gut-run-all" in run_text, (
            "GUT --gut-run-all step must still be present (regression)"
        )

    def test_gut_headless_still_present(self, workflow):
        run_text = _all_run_blocks(workflow)
        assert "--headless" in run_text, (
            "Godot must still be invoked with --headless (regression)"
        )

    def test_artifact_upload_still_runs_always(self, workflow):
        upload_steps = [
            s for s in _all_steps(workflow)
            if isinstance(s, dict) and "upload-artifact" in s.get("uses", "")
        ]
        assert upload_steps, "upload-artifact step must still exist"
        assert any(
            s.get("if", "").strip() == "always()" for s in upload_steps
        ), "Artifact upload must still have 'if: always()'"
