"""
tests/ci/test_verify_clean_tree.py

Pytest suite for FEAT-293 (US-011, US-012; resolves PR-003, PR-004,
PR-008, PR-009): scripts/verify_clean_tree.sh, the automated clean-tree
CI gate.

Deployment review could not independently confirm the pipeline itself
caught a working tree left dirty by a prior stage -- that check only ever
existed as manual `git status` inspection (see CLAUDE.md's commit-hygiene
section). scripts/verify_clean_tree.sh turns that manual check into a
real, scripted gate: it wraps `git status --porcelain` against a target
directory and fails (non-zero exit) the instant ANY pending change
(staged, unstaged, or untracked) exists.

This suite proves, via real `bash`/`git` subprocess invocations against
ISOLATED fixture git repositories built fresh under tmp_path for each
test (never against the real repository's own working-tree state, which
may legitimately be mid-edit while this very feature is implemented):

  1. scripts/verify_clean_tree.sh exits 0 against a clean fixture working
     tree (test_criteria #2).
  2. scripts/verify_clean_tree.sh exits non-zero against a deliberately
     dirtied fixture working tree -- both an untracked file and a
     modified tracked file (test_criteria #1, regression guard).
  3. scripts/test_command.sh wires the new gate in immediately after the
     N=1000 simulation stage.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def repo_root() -> Path:
    """Absolute path to the repository root (where project.godot lives)."""
    return Path(__file__).parent.parent.parent


@pytest.fixture(scope="module")
def script_path(repo_root) -> Path:
    return repo_root / "scripts" / "verify_clean_tree.sh"


@pytest.fixture(scope="module")
def test_command_sh_path(repo_root) -> Path:
    return repo_root / "scripts" / "test_command.sh"


def _run_script(script_path: Path, target_dir: Path | None = None, timeout: int = 30):
    args = ["bash", str(script_path)]
    if target_dir is not None:
        args.append(str(target_dir))
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def _init_fixture_git_repo(path: Path) -> None:
    """Build a fresh, minimal, committed git repository at `path` -- this
    suite's own isolated "clean working tree" fixture, never the real
    repository."""
    path.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q"], cwd=str(path), check=True)
    subprocess.run(["git", "config", "user.email", "fixture@hykaen.test"], cwd=str(path), check=True)
    subprocess.run(["git", "config", "user.name", "Fixture"], cwd=str(path), check=True)
    (path / "tracked.txt").write_text("committed content\n")
    subprocess.run(["git", "add", "tracked.txt"], cwd=str(path), check=True)
    subprocess.run(["git", "commit", "-q", "-m", "fixture: initial commit"], cwd=str(path), check=True)


# ── File existence / shape ───────────────────────────────────────────────────

class TestRequiredFileExists:
    def test_script_exists(self, script_path):
        assert script_path.is_file(), "scripts/verify_clean_tree.sh must exist"

    def test_script_has_shebang(self, script_path):
        assert script_path.read_text().startswith("#!"), (
            "scripts/verify_clean_tree.sh must start with a shebang line"
        )

    def test_script_is_executable(self, script_path):
        import stat

        mode = script_path.stat().st_mode
        assert mode & stat.S_IXUSR, "scripts/verify_clean_tree.sh must be executable"


# ── Criterion: exits zero against a clean fixture working tree ─────────────

class TestExitsZeroOnCleanFixtureTree:
    def test_exits_zero_on_freshly_committed_fixture_repo(self, script_path, tmp_path):
        fixture_repo = tmp_path / "clean_repo"
        _init_fixture_git_repo(fixture_repo)

        result = _run_script(script_path, fixture_repo)

        assert result.returncode == 0, (
            "verify_clean_tree.sh must exit 0 against a clean fixture "
            f"working tree.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert "clean" in result.stdout.lower()


# ── Criterion: exits non-zero against a deliberately dirtied fixture ───────
# ── working tree (regression test) ──────────────────────────────────────────

class TestExitsNonZeroOnDirtiedFixtureTree:
    def test_exits_nonzero_when_untracked_file_present(self, script_path, tmp_path):
        fixture_repo = tmp_path / "dirty_repo_untracked"
        _init_fixture_git_repo(fixture_repo)

        # Control case first: confirm the fixture is clean before dirtying it,
        # so the failure below isn't vacuously caused by a bad fixture setup.
        clean_result = _run_script(script_path, fixture_repo)
        assert clean_result.returncode == 0, (
            f"control case failed unexpectedly: {clean_result.stdout} {clean_result.stderr}"
        )

        (fixture_repo / "untracked_new_file.txt").write_text("surprise!\n")

        dirty_result = _run_script(script_path, fixture_repo)
        assert dirty_result.returncode != 0, (
            "verify_clean_tree.sh must exit non-zero once an untracked file "
            "is left behind in the working tree"
        )
        assert "untracked_new_file.txt" in dirty_result.stderr, (
            f"failure output must name the offending path; got: {dirty_result.stderr}"
        )

    def test_exits_nonzero_when_tracked_file_modified(self, script_path, tmp_path):
        fixture_repo = tmp_path / "dirty_repo_modified"
        _init_fixture_git_repo(fixture_repo)

        (fixture_repo / "tracked.txt").write_text("mutated content\n")

        dirty_result = _run_script(script_path, fixture_repo)
        assert dirty_result.returncode != 0, (
            "verify_clean_tree.sh must exit non-zero once a tracked file "
            "has an uncommitted modification"
        )
        assert "tracked.txt" in dirty_result.stderr

    def test_exits_nonzero_when_change_is_staged_but_uncommitted(self, script_path, tmp_path):
        fixture_repo = tmp_path / "dirty_repo_staged"
        _init_fixture_git_repo(fixture_repo)

        (fixture_repo / "staged_only.txt").write_text("staged but not committed\n")
        subprocess.run(["git", "add", "staged_only.txt"], cwd=str(fixture_repo), check=True)

        dirty_result = _run_script(script_path, fixture_repo)
        assert dirty_result.returncode != 0, (
            "verify_clean_tree.sh must exit non-zero for a staged-but-uncommitted change"
        )


# ── Edge cases ────────────────────────────────────────────────────────────

class TestEdgeCases:
    def test_exits_nonzero_on_nonexistent_target_dir(self, script_path, tmp_path):
        missing = tmp_path / "does_not_exist"
        result = _run_script(script_path, missing)
        assert result.returncode != 0

    def test_exits_nonzero_on_dir_outside_any_git_repo(self, script_path, tmp_path):
        non_git_dir = tmp_path / "not_a_git_repo"
        non_git_dir.mkdir()
        result = _run_script(script_path, non_git_dir)
        assert result.returncode != 0


# ── Real repository sanity check ─────────────────────────────────────────
# NOTE: intentionally NOT a "must exit 0 against the real repo" assertion
# (unlike this project's other ci/*.sh test suites) -- the real repo's
# working tree legitimately fluctuates while a feature implementing this
# very script is in flight. Instead, just confirm invoking with no
# argument at all (defaulting to the repo root) runs without erroring out
# on argument handling, regardless of the tree's current clean/dirty state.
class TestDefaultsToRepoRootWhenNoArgumentGiven:
    def test_runs_without_argument_error_against_default_target(self, script_path, repo_root):
        result = _run_script(script_path, target_dir=None)
        assert result.returncode in (0, 1), (
            "verify_clean_tree.sh with no explicit target_dir must either "
            "report clean (0) or dirty (1) -- not error out on argument "
            f"handling.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert repo_root.name in (result.stdout + result.stderr) or str(repo_root) in (
            result.stdout + result.stderr
        )


# ── Wiring: scripts/test_command.sh invokes the gate immediately after ─────
# ── the N=1000 simulation stage ─────────────────────────────────────────────

class TestWiredIntoTestCommandShAfterSimulationStage:
    def test_test_command_sh_invokes_verify_clean_tree(self, test_command_sh_path):
        text = test_command_sh_path.read_text()
        assert "verify_clean_tree.sh" in text, (
            "scripts/test_command.sh must invoke scripts/verify_clean_tree.sh"
        )

    def test_clean_tree_stage_runs_immediately_after_simulation_stage(self, test_command_sh_path):
        text = test_command_sh_path.read_text()

        # Only look at the EXECUTABLE section (after the header doc-comment
        # block, which mentions "pytest"/"test_balance_sim.gd" repeatedly in
        # prose and would otherwise produce false matches) -- anchor on
        # `set -euo pipefail`, this file's own established boundary between
        # the header comment and the actual stage commands.
        exec_start = text.find("set -euo pipefail")
        assert exec_start != -1, "scripts/test_command.sh must contain 'set -euo pipefail'"
        executable_text = text[exec_start:]

        sim_idx = executable_text.find("-gselect=test_balance_sim.gd")
        clean_tree_idx = executable_text.find("scripts/verify_clean_tree.sh")

        assert sim_idx != -1, "the N=1000 simulation stage's actual command must still be present"
        assert clean_tree_idx != -1, "the clean-tree gate's actual command must be present"
        assert clean_tree_idx > sim_idx, (
            "the clean-tree gate must be wired in AFTER the simulation stage"
        )

        # "Immediately after" -- no OTHER stage's actual command (a
        # DIFFERENT `godot --headless ...` invocation or the pytest command)
        # may sit between the simulation stage's own command line and the
        # clean-tree gate's command line.
        between = executable_text[sim_idx + len("-gselect=test_balance_sim.gd"):clean_tree_idx]
        assert "godot --headless" not in between, (
            "no other godot stage's command may run between the simulation "
            f"stage and the clean-tree gate; found stray content:\n{between}"
        )
        assert "python -m pytest" not in between, (
            "the pytest stage's command must not run between the simulation "
            f"stage and the clean-tree gate; found stray content:\n{between}"
        )
