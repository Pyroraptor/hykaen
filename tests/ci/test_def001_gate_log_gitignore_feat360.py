"""
tests/ci/test_def001_gate_log_gitignore_feat360.py

Pytest suite for FEAT-360 (resolves DEF-VER-001): eliminate working-tree
drift from the regenerated DEF-001 gate captured-evidence log.

Root cause: tests/integration/test_def001_gate_evidence.py's
`captured_evidence_log` fixture rewrites tests/integration/fixtures/
def001_gate_captured_output.log on EVERY real run of that suite (raw
subprocess stdout/stderr from both the nested pytest run and the real
`godot ... --gut-run-all` run) -- and, because that path lived under the
git-TRACKED tests/integration/fixtures/ directory, every run of the DEF-001
gate suite left the working tree dirty (`git status` showing the log
modified), exactly the class of regression FEAT-292 already fixed once for
res://sim_results.json. Peer review finding DEF-VER-001 caught this file
sitting modified/untracked at HEAD, tripping
scripts/verify_clean_tree.sh's clean_tree_gate.

The fix (see .gitignore and tests/integration/test_def001_gate_evidence.py):
  1. `CAPTURED_EVIDENCE_LOG_PATH` now resolves to a directory OUTSIDE
     tests/integration/fixtures/ -- a dedicated, root-anchored,
     git-ignored `.test-output/` directory -- so re-running the suite
     regenerates an ordinary ignored file rather than dirtying a tracked
     path.
  2. The old tracked copy at tests/integration/fixtures/
     def001_gate_captured_output.log has been removed from the git index
     (`git rm`) -- a .gitignore rule alone does not silence `git status`
     for an already-tracked file.
  3. .gitignore gained a new, root-anchored, narrowly-scoped rule
     (`/.test-output/`) that must NOT shadow any other, legitimately
     committed fixture under tests/integration/fixtures/ (e.g.
     gut_output_known_good.txt, gut_output_regressed.txt,
     baseline_out_of_scope_hashes.json) -- those stay tracked and
     committed per CLAUDE.md.

This suite verifies:
  - The old tracked log path is gone from disk and from the git index.
  - `CAPTURED_EVIDENCE_LOG_PATH` (imported straight from the real gate
    module) resolves outside tests/integration/fixtures/.
  - `.gitignore` declares a rule covering that new path, and
    `git check-ignore` actually matches it (test_criteria #2).
  - The rule does not shadow any currently-tracked fixture under
    tests/integration/fixtures/ (test_criteria #4).
  - Writing the log (as the real fixture does) twice in a row to its new
    location leaves `git status --porcelain` clean both times, with no
    untracked path anywhere in the repo matching `*_gate_captured_output.log`
    (test_criteria #1).
  - scripts/verify_clean_tree.sh exits 0 immediately afterward
    (test_criteria #3).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
OLD_TRACKED_LOG_PATH = REPO_ROOT / "tests" / "integration" / "fixtures" / "def001_gate_captured_output.log"
VERIFY_CLEAN_TREE_SH = REPO_ROOT / "scripts" / "verify_clean_tree.sh"


def _run_git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
    )


def _import_gate_module():
    """Imports the real gate module (never re-implements its path logic)
    so this suite fails immediately if a future edit reintroduces the old
    tests/integration/fixtures/ location."""
    sys.path.insert(0, str(REPO_ROOT / "tests" / "integration"))
    try:
        import test_def001_gate_evidence as gate_module  # noqa: PLC0415

        return gate_module
    finally:
        sys.path.remove(str(REPO_ROOT / "tests" / "integration"))


# ══════════════════════════════════════════════════════════════════════════
# The old tracked copy is gone -- from disk and from the git index.
# ══════════════════════════════════════════════════════════════════════════

def test_old_tracked_log_no_longer_exists_on_disk() -> None:
    assert not OLD_TRACKED_LOG_PATH.exists(), (
        f"{OLD_TRACKED_LOG_PATH} must no longer exist -- the DEF-001 gate "
        "evidence log must be written to a git-ignored location instead "
        "(FEAT-360 / DEF-VER-001)"
    )


def test_old_tracked_log_is_no_longer_tracked_by_git() -> None:
    result = _run_git("ls-files", str(OLD_TRACKED_LOG_PATH.relative_to(REPO_ROOT)))
    assert result.stdout.strip() == "", (
        "tests/integration/fixtures/def001_gate_captured_output.log must "
        "no longer be tracked by git (FEAT-360 / DEF-VER-001)"
    )


# ══════════════════════════════════════════════════════════════════════════
# The gate module's own path constant resolves outside fixtures/.
# ══════════════════════════════════════════════════════════════════════════

def test_captured_evidence_log_path_resolves_outside_tracked_fixtures_dir() -> None:
    gate_module = _import_gate_module()
    fixtures_dir = (REPO_ROOT / "tests" / "integration" / "fixtures").resolve()
    resolved_log_path = gate_module.CAPTURED_EVIDENCE_LOG_PATH.resolve()
    assert fixtures_dir not in resolved_log_path.parents, (
        f"CAPTURED_EVIDENCE_LOG_PATH ({resolved_log_path}) must not live "
        f"inside the git-tracked fixtures directory ({fixtures_dir}) -- "
        "FEAT-360 / DEF-VER-001"
    )


# ══════════════════════════════════════════════════════════════════════════
# .gitignore coverage -- test_criteria #2
# ══════════════════════════════════════════════════════════════════════════

def test_gitignore_covers_the_new_captured_evidence_log_path() -> None:
    gate_module = _import_gate_module()
    rel_path = gate_module.CAPTURED_EVIDENCE_LOG_PATH.resolve().relative_to(REPO_ROOT)
    result = _run_git("check-ignore", "-q", str(rel_path))
    assert result.returncode == 0, (
        f"{rel_path} must be matched by a .gitignore rule "
        f"(git check-ignore exited {result.returncode}) -- FEAT-360"
    )


# ══════════════════════════════════════════════════════════════════════════
# Regression: the new rule must never shadow an existing, legitimately
# tracked fixture -- test_criteria #4 / CLAUDE.md commit-hygiene section.
# ══════════════════════════════════════════════════════════════════════════

def _tracked_fixture_files() -> list[str]:
    result = _run_git("ls-files", "tests/integration/fixtures/")
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def test_fixtures_directory_still_has_other_tracked_files() -> None:
    """Sanity check the regression test below has real files to exercise."""
    files = _tracked_fixture_files()
    assert files, "expected at least one tracked file under tests/integration/fixtures/"


def test_gitignore_rule_does_not_shadow_any_other_tracked_fixture() -> None:
    files = _tracked_fixture_files()
    matched = []
    for path in files:
        result = _run_git("check-ignore", "-q", path)
        if result.returncode == 0:
            matched.append(path)
    assert not matched, (
        "the new .gitignore rule must not match any currently-tracked "
        f"fixture, but it matched: {matched} -- those files must remain "
        "trackable/committed per CLAUDE.md (FEAT-360 regression guard)"
    )


# ══════════════════════════════════════════════════════════════════════════
# End-to-end: writing the log (as the real fixture does) leaves the
# working tree clean, twice in a row -- test_criteria #1.
# ══════════════════════════════════════════════════════════════════════════

def _git_status_porcelain() -> str:
    return _run_git("status", "--porcelain").stdout


def _assert_no_stray_gate_log_untracked(status: str) -> None:
    offending = [
        line
        for line in status.splitlines()
        if "_gate_captured_output.log" in line and line.strip().startswith("??")
    ]
    assert not offending, (
        "no untracked file matching *_gate_captured_output.log may remain "
        f"in the working tree; found: {offending}"
    )


class TestWritingTheLogTwiceLeavesTheWorkingTreeClean:
    def test_first_write_leaves_git_status_clean(self) -> None:
        gate_module = _import_gate_module()
        log_path = gate_module.CAPTURED_EVIDENCE_LOG_PATH
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text("FEAT-360 regression-guard write #1\n")

        status = _git_status_porcelain()
        _assert_no_stray_gate_log_untracked(status)

    def test_second_write_also_leaves_git_status_clean(self) -> None:
        gate_module = _import_gate_module()
        log_path = gate_module.CAPTURED_EVIDENCE_LOG_PATH
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text("FEAT-360 regression-guard write #2 (rewritten)\n")

        status = _git_status_porcelain()
        _assert_no_stray_gate_log_untracked(status)


# ══════════════════════════════════════════════════════════════════════════
# scripts/verify_clean_tree.sh must pass immediately afterward --
# test_criteria #3.
#
# Exercised against an ISOLATED fixture git repository built fresh under
# tmp_path (mirroring tests/ci/test_verify_clean_tree.py's own
# `_init_fixture_git_repo` convention) rather than the real repository --
# the real repo's own working tree legitimately fluctuates while other
# work is in flight (see test_verify_clean_tree.py's
# TestDefaultsToRepoRootWhenNoArgumentGiven note making the same choice),
# so asserting a hard exit-0 against it here would be flaky by
# construction, not a genuine regression guard.
# ══════════════════════════════════════════════════════════════════════════

def _init_fixture_git_repo(path: Path, gitignore_text: str) -> None:
    path.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q"], cwd=str(path), check=True)
    subprocess.run(["git", "config", "user.email", "fixture@hykaen.test"], cwd=str(path), check=True)
    subprocess.run(["git", "config", "user.name", "Fixture"], cwd=str(path), check=True)
    (path / ".gitignore").write_text(gitignore_text)
    (path / "tracked.txt").write_text("committed content\n")
    subprocess.run(["git", "add", ".gitignore", "tracked.txt"], cwd=str(path), check=True)
    subprocess.run(["git", "commit", "-q", "-m", "fixture: initial commit"], cwd=str(path), check=True)


class TestVerifyCleanTreePassesAfterTheGateLogIsWritten:
    def test_verify_clean_tree_exits_zero_on_isolated_fixture_repo(self, tmp_path) -> None:
        gate_module = _import_gate_module()
        rel_log_path = gate_module.CAPTURED_EVIDENCE_LOG_PATH.resolve().relative_to(REPO_ROOT)

        fixture_repo = tmp_path / "def001_gate_fixture_repo"
        real_gitignore_text = (REPO_ROOT / ".gitignore").read_text()
        _init_fixture_git_repo(fixture_repo, real_gitignore_text)

        # Simulate the DEF-001 gate's own write, at the SAME relative path
        # the real fixture uses, inside the isolated repo.
        fixture_log_path = fixture_repo / rel_log_path
        fixture_log_path.parent.mkdir(parents=True, exist_ok=True)
        fixture_log_path.write_text("FEAT-360 regression-guard write #1\n")

        first_result = subprocess.run(
            ["bash", str(VERIFY_CLEAN_TREE_SH), str(fixture_repo)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert first_result.returncode == 0, (
            "scripts/verify_clean_tree.sh must exit 0 against an isolated "
            "fixture repo immediately after the DEF-001 gate evidence log "
            f"is written to its new, git-ignored location.\n"
            f"STDOUT:\n{first_result.stdout}\nSTDERR:\n{first_result.stderr}"
        )

        # Running the gate twice in a row (test_criteria #1/#3): rewrite
        # the log again and confirm the gate still passes.
        fixture_log_path.write_text("FEAT-360 regression-guard write #2 (rewritten)\n")

        second_result = subprocess.run(
            ["bash", str(VERIFY_CLEAN_TREE_SH), str(fixture_repo)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert second_result.returncode == 0, (
            "scripts/verify_clean_tree.sh must still exit 0 after a SECOND "
            "consecutive rewrite of the DEF-001 gate evidence log.\n"
            f"STDOUT:\n{second_result.stdout}\nSTDERR:\n{second_result.stderr}"
        )
