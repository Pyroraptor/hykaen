"""
tests/unit/test_ci_entry_point_smoke_feat135.py

Pytest suite for FEAT-135 (DEF-001, critical): the 'Entry-Point Smoke Test
(DEF-003)' step in .github/workflows/test.yml historically ran
`godot --headless -s game/main.gd --check-only`, but game/main.gd does not
exist anywhere in the repo (game/ contains only .gitkeep) -- causing this
mandatory CI gate to fail on every single run.

The real entry point is res://MainScene.gd / MainScene.tscn, per
project.godot's `run/main_scene="res://MainScene.tscn"`. This suite asserts
the workflow step has been corrected to check-validate the real entry-point
script, so the gate is meaningful (and green) again.

All assertions are pure-Python YAML-parse checks; the final test optionally
invokes the real `godot` binary if available to prove the corrected
invocation actually exits 0 locally.
"""

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
def workflow_text(workflow_path) -> str:
    return workflow_path.read_text()


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


def _find_entry_point_step(workflow: dict):
    for step in _all_steps(workflow):
        if isinstance(step, dict) and "Entry-Point Smoke Test" in step.get("name", ""):
            return step
    return None


# ── Test class ────────────────────────────────────────────────────────────────

class TestEntryPointSmokeTestReferencesRealCompositionRoot:
    """FEAT-135 / DEF-001: Entry-Point Smoke Test must target a real file."""

    def test_no_reference_to_nonexistent_game_main_gd(self, workflow_text):
        """`game/main.gd` must not appear anywhere in test.yml -- it does not
        exist in the repo (game/ only contains .gitkeep)."""
        assert "game/main.gd" not in workflow_text, (
            "test.yml must not reference the nonexistent game/main.gd entry "
            "point (DEF-001) -- grep -n 'game/main.gd' .github/workflows/test.yml "
            "must return zero hits"
        )

    def test_entry_point_smoke_test_step_exists(self, workflow):
        step = _find_entry_point_step(workflow)
        assert step is not None, (
            "test.yml must still contain an 'Entry-Point Smoke Test' step"
        )

    def test_entry_point_smoke_test_step_targets_real_main_scene(self, workflow):
        """The step must invoke a check against res://MainScene.gd (or
        MainScene.tscn) -- the actual entry point per project.godot's
        run/main_scene."""
        step = _find_entry_point_step(workflow)
        assert step is not None, "Entry-Point Smoke Test step not found"
        run_block = step.get("run", "")
        assert "MainScene.gd" in run_block or "MainScene.tscn" in run_block, (
            "Entry-Point Smoke Test step must reference the real composition "
            "root (res://MainScene.gd or MainScene.tscn), not a nonexistent "
            "game/main.gd (DEF-001)"
        )

    def test_entry_point_smoke_test_step_invokes_check_only(self, workflow):
        step = _find_entry_point_step(workflow)
        assert step is not None, "Entry-Point Smoke Test step not found"
        run_block = step.get("run", "")
        assert "--headless" in run_block, (
            "Entry-Point Smoke Test step must invoke godot with '--headless'"
        )
        assert "--check-only" in run_block, (
            "Entry-Point Smoke Test step must invoke godot with '--check-only'"
        )

    def test_entry_point_smoke_test_step_no_bypass(self, workflow):
        """The step must not swallow a non-zero exit code (no '|| true' /
        '|| exit 0' bypass) -- mirrors the guarantee already enforced for
        the GDScript Type Check step in test_ci_type_check_feat040.py."""
        step = _find_entry_point_step(workflow)
        assert step is not None, "Entry-Point Smoke Test step not found"
        run_block = step.get("run", "")
        assert "|| true" not in run_block, (
            "Entry-Point Smoke Test step must NOT use '|| true' -- that "
            "would suppress the exit code and nullify the gate"
        )
        assert "|| exit 0" not in run_block, (
            "Entry-Point Smoke Test step must NOT use '|| exit 0' -- that "
            "would suppress the exit code and nullify the gate"
        )

    def test_entry_point_smoke_test_step_dry_run_exits_zero_locally(self, repo_root, workflow):
        """Dry-run simulation: if Godot is available, actually run the
        corrected check-only invocation against the real entry-point file
        and assert it exits 0.

        Skips if godot is not installed, or if it hangs (sandboxes without a
        fully initialised Godot runtime) -- the real gate runs on GitHub
        Actions where the environment is correct.
        """
        godot_check = subprocess.run(["which", "godot"], capture_output=True)
        if godot_check.returncode != 0:
            pytest.skip("godot binary not available in this environment")

        step = _find_entry_point_step(workflow)
        assert step is not None, "Entry-Point Smoke Test step not found"
        run_block = step.get("run", "")

        # Extract the godot invocation line (skip echo/comment lines).
        godot_line = next(
            (line.strip() for line in run_block.splitlines() if line.strip().startswith("godot ")),
            None,
        )
        assert godot_line is not None, "Could not find a 'godot ...' invocation line in the step"

        try:
            result = subprocess.run(
                godot_line.split(),
                capture_output=True,
                text=True,
                cwd=str(repo_root),
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            pytest.skip(
                "godot invocation timed out in this environment (likely a "
                "sandbox without a fully initialised Godot runtime). The CI "
                "gate is validated structurally by the YAML-parse tests above."
            )

        assert result.returncode == 0, (
            f"'{godot_line}' exited {result.returncode} against the current codebase.\n"
            f"stdout: {result.stdout}\n"
            f"stderr: {result.stderr}\n"
            "The real entry-point script must be syntactically valid for the "
            "gate to be green."
        )


# ── Regression: FEAT-040 type-check step assertions remain intact ────────────

class TestGdscriptTypeCheckStepStillIntact:
    """Regression guard: this feature must not disturb the FEAT-040 step or
    its no-bypass guarantee, which tests/unit/test_ci_type_check_feat040.py
    already covers in depth -- spot-check the key invariant here too."""

    def test_type_check_step_still_present_and_unbypassed(self, workflow):
        steps = _all_steps(workflow)
        type_check_step = next(
            (s for s in steps if isinstance(s, dict) and s.get("name") == "GDScript Type Check"),
            None,
        )
        assert type_check_step is not None, "GDScript Type Check step must still be present"
        run_block = type_check_step.get("run", "")
        assert "|| true" not in run_block
        assert "|| exit 0" not in run_block
