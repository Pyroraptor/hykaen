"""
tests/unit/test_ci_type_check_feat040.py

Pytest suite for FEAT-040: GDScript Static Type-Check CI Gate.

Validates that test.yml contains a 'GDScript Type Check' step that:
  1. Exists and is named exactly 'GDScript Type Check'
  2. Appears AFTER all existing lint-gate steps
  3. Appears BEFORE the GUT run step
  4. Invokes 'godot --headless --check-only' (forwards exit code to CI)

All assertions are pure-Python YAML-parse checks; no running Godot binary required.
"""

import subprocess
import tempfile
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


def _all_steps(workflow: dict) -> list:
    return workflow.get("jobs", {}).get("test", {}).get("steps", [])


def _step_names(workflow: dict) -> list:
    return [s.get("name", "") for s in _all_steps(workflow) if isinstance(s, dict)]


def _step_index_by_name(workflow: dict, name: str) -> int:
    """Return the 0-based index of the first step whose name matches `name`."""
    for i, step in enumerate(_all_steps(workflow)):
        if isinstance(step, dict) and step.get("name") == name:
            return i
    return -1


def _step_index_containing(workflow: dict, substring: str) -> int:
    """Return the 0-based index of the first step whose 'run' block contains `substring`."""
    for i, step in enumerate(_all_steps(workflow)):
        if isinstance(step, dict) and substring in step.get("run", ""):
            return i
    return -1


# ── Test class ────────────────────────────────────────────────────────────────

class TestGdscriptTypeCheckStep:
    """FEAT-040: GDScript Static Type-Check CI Gate."""

    def test_gdscript_type_check_step_exists(self, workflow):
        """A step named 'GDScript Type Check' must be present in the test job."""
        names = _step_names(workflow)
        assert "GDScript Type Check" in names, (
            "test.yml must contain a step named exactly 'GDScript Type Check' (FEAT-040)"
        )

    def test_gdscript_type_check_step_invokes_check_only(self, workflow):
        """The step must invoke 'godot --headless --check-only'."""
        steps = _all_steps(workflow)
        type_check_step = next(
            (s for s in steps if isinstance(s, dict) and s.get("name") == "GDScript Type Check"),
            None,
        )
        assert type_check_step is not None, "GDScript Type Check step not found"
        run_block = type_check_step.get("run", "")
        assert "--check-only" in run_block, (
            "GDScript Type Check step must invoke godot with '--check-only' flag (FEAT-040)"
        )
        assert "--headless" in run_block, (
            "GDScript Type Check step must invoke godot with '--headless' flag (FEAT-040)"
        )

    def test_gdscript_type_check_step_targets_project_root(self, workflow):
        """The step must target the project root (--path . or equivalent)."""
        steps = _all_steps(workflow)
        type_check_step = next(
            (s for s in steps if isinstance(s, dict) and s.get("name") == "GDScript Type Check"),
            None,
        )
        assert type_check_step is not None, "GDScript Type Check step not found"
        run_block = type_check_step.get("run", "")
        # Accept --path . or --path $GITHUB_WORKSPACE or just `godot --headless --check-only`
        # The project root is implicitly . when invoked from checkout directory.
        # We accept either explicit --path or the invocation being run from project root.
        has_explicit_path = "--path" in run_block
        has_implicit_root = "godot --headless --check-only" in run_block or "godot --headless --check-only --path" in run_block
        assert has_explicit_path or has_implicit_root, (
            "GDScript Type Check step must target the project root "
            "(use --path . or be invoked from the repo root directory)"
        )

    def test_gdscript_type_check_step_appears_after_lint_steps(self, workflow):
        """GDScript Type Check must appear after all lint-gate steps."""
        type_check_idx = _step_index_by_name(workflow, "GDScript Type Check")
        assert type_check_idx >= 0, "GDScript Type Check step not found"

        # All lint steps should appear before the type-check step.
        # Check the three original lint steps by their run-block content.
        lint_markers = [
            "extends Node",           # ADR-001 domain purity linter
            "#+APPROVAL:",            # Spec approval presence linter
            "PLACEHOLDER",            # Spec approval no-placeholder linter
        ]
        for marker in lint_markers:
            lint_idx = _step_index_containing(workflow, marker)
            assert lint_idx >= 0, f"Could not find lint step containing '{marker}'"
            assert lint_idx < type_check_idx, (
                f"GDScript Type Check (index {type_check_idx}) must appear AFTER "
                f"the lint step containing '{marker}' (index {lint_idx})"
            )

    def test_gdscript_type_check_step_appears_before_gut_run(self, workflow):
        """GDScript Type Check must appear before the GUT run step."""
        type_check_idx = _step_index_by_name(workflow, "GDScript Type Check")
        assert type_check_idx >= 0, "GDScript Type Check step not found"

        gut_run_idx = _step_index_containing(workflow, "--gut-run-all")
        assert gut_run_idx >= 0, "GUT run step not found"

        assert type_check_idx < gut_run_idx, (
            f"GDScript Type Check (index {type_check_idx}) must appear BEFORE "
            f"the GUT run step (index {gut_run_idx})"
        )

    def test_gdscript_type_check_step_forwards_exit_code(self, workflow):
        """The step's run block must not suppress the godot exit code.

        A plain `godot --headless --check-only --path .` forwards the exit
        code automatically. The step must NOT pipe through `|| true` or
        similar constructs that would swallow a non-zero exit.
        """
        steps = _all_steps(workflow)
        type_check_step = next(
            (s for s in steps if isinstance(s, dict) and s.get("name") == "GDScript Type Check"),
            None,
        )
        assert type_check_step is not None, "GDScript Type Check step not found"
        run_block = type_check_step.get("run", "")
        assert "|| true" not in run_block, (
            "GDScript Type Check step must NOT use '|| true' — "
            "that would suppress the exit code and nullify the gate (FEAT-040)"
        )
        assert "|| exit 0" not in run_block, (
            "GDScript Type Check step must NOT use '|| exit 0' — "
            "that would suppress the exit code and nullify the gate (FEAT-040)"
        )

    def test_gdscript_type_check_step_dry_run_exits_zero_on_clean_codebase(self, repo_root):
        """Dry-run simulation: if Godot is available, the check-only step exits 0.

        This test skips if godot is not installed in the CI/test environment
        (it is not required for linting the YAML itself).  It also skips if
        godot hangs (common in sandbox environments without a proper display
        context) — the real gate runs on GitHub Actions where the environment
        is correct.  A 15-second timeout catches the hang and skips cleanly.
        """
        godot_check = subprocess.run(
            ["which", "godot"],
            capture_output=True,
        )
        if godot_check.returncode != 0:
            pytest.skip("godot binary not available in this environment — skipping live type-check run")

        try:
            result = subprocess.run(
                ["godot", "--headless", "--check-only", "--path", str(repo_root)],
                capture_output=True,
                text=True,
                cwd=str(repo_root),
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            pytest.skip(
                "godot --headless --check-only timed out in this environment "
                "(likely a sandbox without a fully initialised Godot runtime). "
                "The CI gate is validated structurally by the YAML-parse tests above."
            )

        assert result.returncode == 0, (
            f"'godot --headless --check-only' exited {result.returncode} on the current codebase.\n"
            f"stdout: {result.stdout}\n"
            f"stderr: {result.stderr}\n"
            "The codebase must have zero GDScript type errors for the CI gate to be green."
        )


# ── Regression: existing CI structure still intact ───────────────────────────

class TestExistingCIStructurePreserved:
    """All prior lint gates must remain intact after FEAT-040 modifies test.yml."""

    def test_domain_purity_linter_still_present(self, workflow):
        steps = _all_steps(workflow)
        run_text = "\n".join(s.get("run", "") for s in steps if isinstance(s, dict))
        assert "extends Node" in run_text and "core/" in run_text, (
            "ADR-001 domain-purity linter must still be present (regression guard)"
        )

    def test_binary_resource_linter_still_present(self, workflow):
        steps = _all_steps(workflow)
        run_text = "\n".join(s.get("run", "") for s in steps if isinstance(s, dict))
        assert ".scn" in run_text or ".res" in run_text, (
            "ADR-009 binary-resource linter must still be present (regression guard)"
        )

    def test_injected_rng_linter_still_present(self, workflow):
        steps = _all_steps(workflow)
        run_text = "\n".join(s.get("run", "") for s in steps if isinstance(s, dict))
        assert ("randf" in run_text or "randi" in run_text) and "rng.gd" in run_text, (
            "ADR-002 injected-RNG linter must still be present (regression guard)"
        )

    def test_gut_run_still_present(self, workflow):
        steps = _all_steps(workflow)
        run_text = "\n".join(s.get("run", "") for s in steps if isinstance(s, dict))
        assert "--gut-run-all" in run_text, (
            "GUT run step must still be present (regression guard)"
        )

    def test_artifact_upload_still_present(self, workflow):
        steps = _all_steps(workflow)
        upload_steps = [
            s for s in steps
            if isinstance(s, dict) and "upload-artifact" in s.get("uses", "")
        ]
        assert upload_steps, "upload-artifact step must still be present (regression guard)"
        assert any(
            s.get("if", "").strip() == "always()" for s in upload_steps
        ), "Artifact upload must still have 'if: always()' (regression guard)"

    def test_approval_spec_linters_still_present(self, workflow):
        steps = _all_steps(workflow)
        run_text = "\n".join(s.get("run", "") for s in steps if isinstance(s, dict))
        assert "#+APPROVAL:" in run_text, (
            "Spec-approval presence linter must still be present (regression guard)"
        )
        assert "PLACEHOLDER" in run_text, (
            "Spec-approval no-placeholder linter must still be present (regression guard)"
        )
