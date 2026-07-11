#!/usr/bin/env python3
"""
scripts/ci/check_sim_results_provenance.py — FEAT-239 (resolves PR-004,
US-009; ADR-006)

sim_results.json is the checked-in artifact of record for the deterministic
N=1000 balance simulation (core/sim/simulator.gd). Its `win_rate` and
`avg_rounds` (and the metrics derived from them, `confidence_interval`) are
only legitimately allowed to move when SOMETHING in the sanctioned
weapon/enemy data (e.g. data/enemies/skeleton.tres, a data/weapons/*.tres
resource table) actually changed in the same commit and caused that shift
(see FEAT-001/FEAT-237's Arming Sword proficiency re-baseline for the
canonical example). Prior to this feature, nothing enforced that
relationship in CI: a commit could silently rewrite sim_results.json's
metrics with no corresponding causal data-file change, and nothing would
catch it — exactly the kind of silent reaction-variance leakage ADR-006 is
meant to prevent (this remediates PR-004).

This script diffs a commit against its parent (default: HEAD vs HEAD^) and:

  1. If sim_results.json's tracked *metric* keys (win_rate, avg_rounds,
     total_battles, confidence_interval — see TRACKED_METRIC_KEYS below;
     NOT the provenance metadata keys commit_hash/seed/timestamp, which are
     expected to move on every regen even when no metric shifted, per
     tests/pytest/test_sim_results_provenance.py's own RESULT_KEYS/
     provenance-key split) did NOT change between the two commits, this
     check passes trivially — there is nothing to attribute.

  2. If a tracked metric key DID change, at least one sanctioned
     weapon/enemy data file (a `*.tres` resource under data/weapons/ or
     data/enemies/) must also have changed in the same commit. If one did,
     the check passes. If none did, the check fails loudly, naming exactly
     which metric(s) moved with no attributable cause.

Usage:
    python scripts/ci/check_sim_results_provenance.py
    python scripts/ci/check_sim_results_provenance.py --repo /path/to/repo \\
        --parent HEAD~1 --commit HEAD

Exit code: 0 when the change is either absent or properly attributed
(or when the parent commit cannot be resolved at all, e.g. the very first
commit in a shallow clone — there is no "prior state" to have drifted from);
non-zero (with a diagnostic violation message on stdout) when
sim_results.json's metrics moved without a sanctioned causal data-file
change in the same commit.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_REPO_DIR = REPO_ROOT

SIM_RESULTS_RELATIVE_PATH = "sim_results.json"

# The *result* keys a sim run actually produces — mirrors
# tests/pytest/test_sim_results_provenance.py's RESULT_KEYS exactly. These
# are the metrics this guard cares about; the three *provenance* keys
# (commit_hash/seed/timestamp) are metadata ABOUT a run and are expected to
# change on every regen regardless of whether a metric moved, so they are
# deliberately excluded from this set.
TRACKED_METRIC_KEYS = ("win_rate", "avg_rounds", "total_battles", "confidence_interval")

# Sanctioned weapon/enemy data files: Godot .tres resource tables under
# data/weapons/ or data/enemies/ (e.g. data/enemies/skeleton.tres,
# data/weapons/longsword.tres). A change to one of these is treated as a
# legitimate causal reason for sim_results.json's metrics to move.
_SANCTIONED_DATA_DIR_PREFIXES = ("data/weapons/", "data/enemies/")
_SANCTIONED_DATA_SUFFIX = ".tres"


def is_sanctioned_data_file(path: str) -> bool:
    """True if `path` (a repo-relative git diff path, forward or backward
    slashes) is a sanctioned weapon/enemy resource data file."""
    normalized = path.replace("\\", "/")
    return normalized.endswith(_SANCTIONED_DATA_SUFFIX) and normalized.startswith(
        _SANCTIONED_DATA_DIR_PREFIXES
    )


class UnresolvableRevisionError(RuntimeError):
    """Raised internally when a git revision (typically the parent) cannot
    be resolved at all — e.g. the very first commit in the repository, or a
    shallow clone that never fetched history beyond HEAD."""


def _run_git(repo_dir: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args],
        cwd=str(repo_dir),
        capture_output=True,
        text=True,
    )


def _revision_exists(repo_dir: Path, revision: str) -> bool:
    result = _run_git(repo_dir, "rev-parse", "--verify", "--quiet", f"{revision}^{{commit}}")
    return result.returncode == 0


def get_diff_files(repo_dir: Path, parent: str, commit: str) -> list[str]:
    """Return the list of repo-relative paths that differ between `parent`
    and `commit` (git diff --name-only order, i.e. as changed)."""
    if not _revision_exists(repo_dir, parent):
        raise UnresolvableRevisionError(
            f"parent revision {parent!r} could not be resolved in {repo_dir} "
            "(first commit / shallow clone with no prior history?)"
        )
    if not _revision_exists(repo_dir, commit):
        raise UnresolvableRevisionError(
            f"commit revision {commit!r} could not be resolved in {repo_dir}"
        )

    result = _run_git(repo_dir, "diff", "--name-only", parent, commit)
    if result.returncode != 0:
        raise RuntimeError(
            f"git diff --name-only {parent} {commit} failed in {repo_dir}: {result.stderr.strip()}"
        )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def get_file_at_revision(repo_dir: Path, revision: str, path: str) -> str | None:
    """Return the text content of `path` at `revision`, or None if the file
    did not exist at that revision."""
    result = _run_git(repo_dir, "show", f"{revision}:{path}")
    if result.returncode != 0:
        return None
    return result.stdout


@dataclass
class ProvenanceCheckResult:
    ok: bool
    message: str
    changed_metric_keys: list[str] = field(default_factory=list)
    sanctioned_files_changed: list[str] = field(default_factory=list)


def check_provenance(
    repo_dir: Path,
    parent: str = "HEAD^",
    commit: str = "HEAD",
) -> ProvenanceCheckResult:
    """The core check: diff `commit` against `parent` and verify
    sim_results.json's tracked metric keys never moved without a
    sanctioned weapon/enemy data-file change in the same diff."""
    try:
        changed_files = get_diff_files(repo_dir, parent, commit)
    except UnresolvableRevisionError as exc:
        return ProvenanceCheckResult(
            ok=True,
            message=(
                f"OK: {SIM_RESULTS_RELATIVE_PATH} provenance check skipped — {exc}"
            ),
        )

    if SIM_RESULTS_RELATIVE_PATH not in changed_files:
        return ProvenanceCheckResult(
            ok=True,
            message=(
                f"OK: {SIM_RESULTS_RELATIVE_PATH} did not change between "
                f"{parent} and {commit}; nothing to attribute."
            ),
        )

    old_text = get_file_at_revision(repo_dir, parent, SIM_RESULTS_RELATIVE_PATH)
    new_text = get_file_at_revision(repo_dir, commit, SIM_RESULTS_RELATIVE_PATH)
    old_data = json.loads(old_text) if old_text else {}
    new_data = json.loads(new_text) if new_text else {}

    changed_metric_keys = sorted(
        key for key in TRACKED_METRIC_KEYS if old_data.get(key) != new_data.get(key)
    )

    if not changed_metric_keys:
        return ProvenanceCheckResult(
            ok=True,
            message=(
                f"OK: {SIM_RESULTS_RELATIVE_PATH} changed between {parent} and {commit}, "
                f"but no tracked metric key ({', '.join(TRACKED_METRIC_KEYS)}) moved "
                "(provenance-only change, e.g. commit_hash/timestamp regen)."
            ),
        )

    sanctioned_files_changed = sorted(f for f in changed_files if is_sanctioned_data_file(f))

    if sanctioned_files_changed:
        return ProvenanceCheckResult(
            ok=True,
            message=(
                f"OK: {SIM_RESULTS_RELATIVE_PATH} metric key(s) {changed_metric_keys} changed "
                f"between {parent} and {commit}, alongside sanctioned weapon/enemy data "
                f"file(s) {sanctioned_files_changed} — causally attributed."
            ),
            changed_metric_keys=changed_metric_keys,
            sanctioned_files_changed=sanctioned_files_changed,
        )

    return ProvenanceCheckResult(
        ok=False,
        message=(
            f"VIOLATION: {SIM_RESULTS_RELATIVE_PATH} metric key(s) {changed_metric_keys} "
            f"changed between {parent} and {commit}, but no sanctioned weapon/enemy data "
            "file (a *.tres resource under data/weapons/ or data/enemies/) changed in the "
            "same commit. sim_results.json's win_rate/avg_rounds (and derived metrics) may "
            "only drift alongside their causal data-file commit (ADR-006) — this looks like "
            "silent reaction-variance leakage. Files changed in this commit: "
            f"{sorted(changed_files)}"
        ),
        changed_metric_keys=changed_metric_keys,
        sanctioned_files_changed=[],
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Fail if sim_results.json's tracked metric keys (win_rate/avg_rounds/"
            "total_battles/confidence_interval) changed in a commit that did not "
            "also change a sanctioned weapon/enemy data file (FEAT-239 / PR-004 / "
            "ADR-006)."
        )
    )
    parser.add_argument(
        "--repo",
        type=Path,
        default=DEFAULT_REPO_DIR,
        help="Path to the git repository root (default: %(default)s)",
    )
    parser.add_argument(
        "--parent",
        default="HEAD^",
        help="The parent revision to diff from (default: %(default)s)",
    )
    parser.add_argument(
        "--commit",
        default="HEAD",
        help="The commit revision to diff to (default: %(default)s)",
    )
    args = parser.parse_args(argv)

    result = check_provenance(args.repo, parent=args.parent, commit=args.commit)
    print(result.message)
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
