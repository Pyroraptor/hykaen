#!/usr/bin/env bash
# scripts/verify_clean_tree.sh — FEAT-293 (US-011, US-012; resolves
# PR-003, PR-004, PR-008, PR-009); FEAT-360 (resolves DEF-VER-001)
#
# FEAT-360 note: this gate's own logic is unchanged — it has always
# failed loud on ANY pending change, tracked or untracked (see the
# `git status --porcelain` call below). Peer review finding DEF-VER-001
# caught this gate correctly hard-failing because a DIFFERENT script —
# tests/integration/test_def001_gate_evidence.py's `captured_evidence_log`
# fixture — was rewriting a log file at a git-TRACKED path
# (tests/integration/fixtures/def001_gate_captured_output.log) on every
# real run. The fix moved that log to a dedicated, git-ignored
# `.test-output/` directory (see .gitignore and that fixture's own doc
# comment) so THIS gate now has nothing left to catch there — proof this
# script was never the source of the drift, only the (correctly firing)
# detector of it. See tests/ci/test_def001_gate_log_gitignore_feat360.py.
#
# Deployment review could not independently confirm the automated
# pipeline actually left the working tree clean after a full run — that
# confirmation existed only as manual `git status` inspection by whoever
# happened to run the gate by hand (see CLAUDE.md's commit-hygiene
# section: "the reviewer checks `git log` / `git status` ... Do NOT
# assume data files were committed by a previous step"). This script
# turns that manual check into a real, scripted, independently-invokable
# CI gate: it fails the build the instant a pipeline run leaves ANY
# pending change (staged, unstaged, or untracked) behind, exactly the
# class of regression that let FEAT-292's since-fixed sim_results.json
# churn (PR-001/PR-002) and other silent working-tree drift slip past
# review undetected.
#
# Wired into scripts/test_command.sh immediately after the N=1000
# simulation stage (the stage historically most likely to leave
# generated artifacts behind — see .gitignore's FEAT-292 entry for
# res://sim_results.json) so a regenerated-but-uncommitted/untracked
# artifact is caught as early as possible, well before the slower
# pytest/GUT stages run. See tests/ci/test_verify_clean_tree.py for the
# executable proof this script both passes against a clean fixture
# working tree and fails against a deliberately dirtied one.
#
# Usage:
#   scripts/verify_clean_tree.sh [target_dir]
#
#   target_dir defaults to this repository's root (two directories up
#   from this script) and must be a directory located inside a git
#   working tree. Tests pass an explicit, isolated fixture git repo so
#   the "clean tree passes" / "dirty tree fails" criteria can both be
#   exercised without ever depending on (or mutating) the real repo's
#   own working-tree state.
#
# Exit code: 0 when `git status --porcelain` against target_dir reports
# ZERO pending changes (staged, unstaged, or untracked files all count);
# non-zero (with the offending paths printed to stderr) otherwise.

set -euo pipefail

DEFAULT_TARGET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${1:-$DEFAULT_TARGET_DIR}"

if [ ! -d "$TARGET_DIR" ]; then
    echo "ERROR: verify_clean_tree.sh: target directory '$TARGET_DIR' does not exist" >&2
    exit 1
fi

if ! git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: verify_clean_tree.sh: '$TARGET_DIR' is not inside a git working tree" >&2
    exit 1
fi

# `git status --porcelain` reports staged, unstaged, AND untracked paths
# (one line each) with nothing printed at all for a fully clean tree --
# exactly the "any pending change of any kind" definition this gate
# needs (no --untracked-files=no narrowing, so a stray generated file
# left behind by an earlier pipeline stage is still caught).
DIRTY="$(git -C "$TARGET_DIR" status --porcelain)"

if [ -n "$DIRTY" ]; then
    echo "ERROR: working tree at '$TARGET_DIR' is NOT clean -- the automated pipeline (or a prior manual step) left pending changes behind:" >&2
    echo "$DIRTY" >&2
    echo "Per CLAUDE.md's commit-hygiene policy, any modified/untracked file (data/ resources in particular) must be staged and committed before the gate can pass." >&2
    exit 1
fi

echo "OK: working tree at '$TARGET_DIR' is clean (git status --porcelain reported no pending changes)"
exit 0
