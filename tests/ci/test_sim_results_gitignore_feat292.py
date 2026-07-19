"""
tests/ci/test_sim_results_gitignore_feat292.py

Pytest suite for FEAT-292 (resolves PR-001/PR-002): eliminate working-tree
drift from the generated sim_results.json artifact.

Root cause: tests/sim/test_balance_sim.gd (core/sim/simulator.gd's N=1000
balance regression) rewrites res://sim_results.json on EVERY test run,
including its commit_hash/timestamp provenance fields, which change on
every regen even when no balance metric moved. sim_results.json used to be
a git-TRACKED file, so every run of scripts/test_command.sh (or its N=1000
simulation stage alone) left the working tree dirty (`git status` showing
sim_results.json modified) — a CLAUDE.md commit-hygiene violation and a
deployment-gate blocker.

The fix (see .gitignore and scripts/test_command.sh):
  1. sim_results.json is untracked from git (`git rm --cached`) and covered
     by a new, root-anchored .gitignore rule (`/sim_results.json`), so it
     is regenerated as an ordinary ignored file from now on — the file
     stays at its existing res://sim_results.json path (tooling that reads
     it — scripts/ci/check_sim_results_provenance.py,
     tests/pytest/test_sim_results_provenance.py, and
     .github/workflows/test.yml's artifact-upload step — is unaffected).
  2. scripts/test_command.sh now runs the N=1000 balance regression stage
     BEFORE the pytest stage, so a freshly regenerated sim_results.json is
     always on disk before tests/pytest/test_sim_results_provenance.py (and
     this suite) reads it, even on a completely fresh checkout that never
     shipped a committed copy of the file.

This suite verifies:
  - sim_results.json is no longer tracked by git.
  - sim_results.json is matched by a .gitignore rule (`git check-ignore`
    succeeds for it) — test_criteria #2.
  - The .gitignore rule does NOT match any currently-tracked data/*.tres
    resource file — data/ resources must remain trackable/committed per
    CLAUDE.md (regression test — test_criteria #3).
  - Running the N=1000 balance-sim stage twice in a row (a real, two-
    subprocess Godot regen, mirroring tests/pytest/
    test_sim_results_provenance.py's established subprocess convention)
    leaves `git status --porcelain` clean with respect to sim_results.json
    after EACH run — test_criteria #1 and #4.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from typing import Optional

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
SIM_RESULTS_PATH = REPO_ROOT / "sim_results.json"

_BALANCE_SIM_TEST_FILE = "test_balance_sim.gd"
_BALANCE_SIM_TEST_DIR = "res://tests/sim"
_SUBPROCESS_TIMEOUT_SECONDS = 90


def _run_git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
    )


def _find_godot_binary() -> Optional[str]:
    """Mirrors tests/pytest/test_sim_results_provenance.py's identically-named
    helper exactly, so every subprocess-invoking pytest suite in this project
    agrees on how the `godot` binary is discovered."""
    for candidate in ("godot", "godot4", "godot4.3", "godot-headless"):
        found = shutil.which(candidate)
        if found:
            return found
    return None


# ══════════════════════════════════════════════════════════════════════════
# .gitignore coverage — test_criteria #2
# ══════════════════════════════════════════════════════════════════════════

def test_gitignore_declares_a_sim_results_json_rule() -> None:
    gitignore_text = (REPO_ROOT / ".gitignore").read_text()
    assert "sim_results.json" in gitignore_text, (
        ".gitignore must declare a rule covering sim_results.json (FEAT-292)"
    )


def test_sim_results_json_is_git_ignored() -> None:
    """`git check-ignore` must succeed (exit 0) for sim_results.json,
    proving it is covered by a .gitignore rule rather than merely absent
    from the working tree."""
    result = _run_git("check-ignore", "-q", "sim_results.json")
    assert result.returncode == 0, (
        "sim_results.json must be matched by a .gitignore rule "
        f"(git check-ignore exited {result.returncode}) — FEAT-292"
    )


def test_sim_results_json_is_no_longer_tracked_by_git() -> None:
    """A .gitignore rule alone does not stop git from reporting diffs on an
    already-tracked file — the file must also have been removed from the
    git index (`git rm --cached`) for `git status` to actually go quiet."""
    result = _run_git("ls-files", "sim_results.json")
    assert result.stdout.strip() == "", (
        "sim_results.json must be untracked (git rm --cached) — a "
        ".gitignore rule alone does not silence git status for an "
        "already-tracked file — FEAT-292"
    )


# ══════════════════════════════════════════════════════════════════════════
# Regression: the new .gitignore rule must never shadow data/ resources —
# test_criteria #3 / CLAUDE.md ("data files MUST be committed")
# ══════════════════════════════════════════════════════════════════════════

def _tracked_data_tres_files() -> list[str]:
    result = _run_git("ls-files", "data/")
    files = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    return [f for f in files if f.endswith(".tres")]


def test_data_directory_has_tracked_tres_fixtures() -> None:
    """Sanity check the regression test below actually has real files to
    exercise (would silently pass-vacuously if data/ were ever emptied)."""
    files = _tracked_data_tres_files()
    assert files, "expected at least one tracked data/*.tres resource file to exist"


def test_gitignore_rule_does_not_match_any_tracked_data_file() -> None:
    files = _tracked_data_tres_files()
    matched = []
    for path in files:
        result = _run_git("check-ignore", "-q", path)
        if result.returncode == 0:
            matched.append(path)
    assert not matched, (
        "the sim_results.json .gitignore rule must NOT match any data/*.tres "
        f"resource file, but it matched: {matched} — data/ resources must "
        "remain trackable/committed per CLAUDE.md (FEAT-292 regression guard)"
    )


def test_gitignore_rule_is_root_anchored() -> None:
    """The rule must be anchored to the repo root (leading '/') and target
    the exact filename — a bare `sim_results.json` (no leading slash) would
    also match any nested path of the same name anywhere in the tree,
    which is broader than intended."""
    gitignore_text = (REPO_ROOT / ".gitignore").read_text()
    matching_lines = [
        line.strip()
        for line in gitignore_text.splitlines()
        if "sim_results.json" in line and not line.strip().startswith("#")
    ]
    assert matching_lines, "expected an active (non-comment) sim_results.json rule in .gitignore"
    assert any(line.startswith("/") for line in matching_lines), (
        f"sim_results.json .gitignore rule(s) {matching_lines!r} should be "
        "root-anchored (leading '/') for a precise, narrowly-scoped match"
    )


# ══════════════════════════════════════════════════════════════════════════
# End-to-end: running the simulation stage (real Godot subprocess) leaves
# the working tree clean w.r.t. sim_results.json — test_criteria #1 and #4
# ══════════════════════════════════════════════════════════════════════════

@pytest.fixture(scope="module")
def godot_bin() -> str:
    found = _find_godot_binary()
    if found is None:
        pytest.skip("godot binary not found on PATH")
    return found


def _run_balance_sim_stage(godot_bin: str) -> None:
    """Runs the real N=1000 balance-sim GUT stage exactly as
    scripts/test_command.sh's stage 2 does, regenerating
    res://sim_results.json in the process."""
    result = subprocess.run(
        [
            godot_bin,
            "--headless",
            "-s",
            "addons/gut/gut_cmdln.gd",
            f"-gselect={_BALANCE_SIM_TEST_FILE}",
            f"-gdir={_BALANCE_SIM_TEST_DIR}",
            "-gexit",
        ],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        timeout=_SUBPROCESS_TIMEOUT_SECONDS,
    )
    assert result.returncode == 0, (
        f"{_BALANCE_SIM_TEST_FILE} regen run must exit 0.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def _git_status_porcelain_for_sim_results() -> str:
    result = _run_git("status", "--porcelain", "--", "sim_results.json")
    return result.stdout.strip()


# ══════════════════════════════════════════════════════════════════════════
# Structural guard on scripts/test_command.sh's stage ORDER — a fresh
# checkout no longer ships a committed sim_results.json (it's gitignored),
# so the N=1000 balance-sim stage that regenerates it must run BEFORE the
# pytest stage whose tests/pytest/test_sim_results_provenance.py reads the
# file straight off disk.
# ══════════════════════════════════════════════════════════════════════════

def test_balance_sim_stage_runs_before_pytest_stage_in_test_command_sh() -> None:
    text = (REPO_ROOT / "scripts" / "test_command.sh").read_text()
    balance_sim_idx = text.index(
        "-gdir=res://tests/sim -gselect=test_balance_sim.gd -gexit"
    )
    pytest_idx = text.index("python -m pytest -q --tb=short")
    assert balance_sim_idx < pytest_idx, (
        "scripts/test_command.sh must run the N=1000 balance-sim stage "
        "BEFORE the pytest stage (FEAT-292) — otherwise "
        "tests/pytest/test_sim_results_provenance.py can read a stale or "
        "nonexistent sim_results.json on a fresh checkout, since the file "
        "is no longer committed to git"
    )


class TestRunningTheSimulationStageLeavesTheWorkingTreeClean:
    def test_single_run_leaves_git_status_clean(self, godot_bin) -> None:
        assert SIM_RESULTS_PATH.exists() or True  # existence is not required beforehand
        _run_balance_sim_stage(godot_bin)
        assert SIM_RESULTS_PATH.exists(), "sim_results.json must exist after the sim stage runs"
        status = _git_status_porcelain_for_sim_results()
        assert status == "", (
            "git status --porcelain must report NO changes for sim_results.json "
            f"after running the N=1000 simulation stage once; got: {status!r} — FEAT-292"
        )

    def test_running_twice_in_a_row_produces_no_diff_either_time(self, godot_bin) -> None:
        _run_balance_sim_stage(godot_bin)
        status_after_first = _git_status_porcelain_for_sim_results()
        assert status_after_first == "", (
            "git status --porcelain must be clean for sim_results.json after the "
            f"FIRST of two consecutive sim-stage runs; got: {status_after_first!r} — FEAT-292"
        )

        _run_balance_sim_stage(godot_bin)
        status_after_second = _git_status_porcelain_for_sim_results()
        assert status_after_second == "", (
            "git status --porcelain must be clean for sim_results.json after the "
            f"SECOND of two consecutive sim-stage runs too; got: {status_after_second!r} — FEAT-292"
        )
