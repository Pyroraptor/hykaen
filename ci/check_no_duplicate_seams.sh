#!/usr/bin/env bash
# ci/check_no_duplicate_seams.sh — FEAT-009 (US-009; NFR-001, NFR-002,
# NFR-006, NFR-007; ADR-002, ADR-006)
#
# Standalone, independently-invokable CI gate proving ADR-002/ADR-006's "no
# new/duplicate seam" guarantee holds structurally, not just by trust:
#
#   1. Exactly ONE _movement_used gate implementation exists — the per-turn
#      Movement-trait lockout flag core/rules/action_economy.gd owns
#      (mark_movement_used() / can_take_movement_action()), the SAME gate
#      core/rules/movement.gd's step()/stride() and core/combat/ai.gd's
#      AI-issued Stride path all trip through. A second, independently
#      declared `_movement_used` flag anywhere else would mean two gates
#      could silently disagree — this check fails the build the moment
#      that happens.
#
#   2. Exactly ONE concrete AI decision call path exists —
#      core/combat/ai.gd's decide_action() is the single production
#      implementation RoundSession drives via AIDecisionPort
#      (core/application/ai_decision_port.gd). That port file's own
#      decide_action() is a deliberately abstract stub (documented
#      contract only — it push_error()s and returns a no-op decision; see
#      its file header) and is excluded here by name, exactly as this
#      project's existing ADR-002 RNG lint already excludes
#      core/rules/rng.gd by name (.github/workflows/test.yml, "Lint —
#      injected RNG"). A second CONCRETE decide_action() anywhere else
#      would be a duplicate AI decision path and fails this check.
#
#   3. Exactly ONE token-reposition function exists —
#      presentation/hex_grid_view.gd's move_token() is the single
#      implementation both the player-driven Stride path
#      (presentation/movement_input_controller.gd) and the AI-driven
#      Stride path (core/application/round_session.gd's
#      _reposition_token_after_ai_stride(), via the injected
#      _token_reposition_fn Callable) call — never a second, independently
#      implemented repositioning function.
#
# Usage:
#   ci/check_no_duplicate_seams.sh [repo_root]
#
#   repo_root defaults to this script's own repository (resolved from its
#   own path) so it can be run from anywhere. Tests pass an explicit
#   fixture repo root to prove the check can detect an injected duplicate
#   without ever mutating the real tree.
#
# Exit code: 0 when all three seams are singular; non-zero (with a
# diagnostic naming which seam duplicated, and every offending file) when
# any of them is not.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [ ! -d "$REPO_ROOT" ]; then
    echo "ERROR: check_no_duplicate_seams.sh: repo root '$REPO_ROOT' does not exist" >&2
    exit 1
fi

cd "$REPO_ROOT"

# Source-of-truth directories only — never tests/ or addons/ (test doubles
# and fixtures legitimately declare their own decide_action()/move_token()
# stand-ins and must not be counted as production duplicates).
SCAN_DIRS=(core presentation infrastructure)

EXISTING_SCAN_DIRS=()
for d in "${SCAN_DIRS[@]}"; do
    if [ -d "$d" ]; then
        EXISTING_SCAN_DIRS+=("$d")
    fi
done

if [ "${#EXISTING_SCAN_DIRS[@]}" -eq 0 ]; then
    echo "ERROR: check_no_duplicate_seams.sh: none of ${SCAN_DIRS[*]} exist under $REPO_ROOT" >&2
    exit 1
fi

FAILURES=0

# ── 1. Exactly one _movement_used gate implementation ──────────────────────
MOVEMENT_HITS="$(grep -rn "var _movement_used" --include="*.gd" "${EXISTING_SCAN_DIRS[@]}" 2>/dev/null || true)"
MOVEMENT_COUNT=0
if [ -n "$MOVEMENT_HITS" ]; then
    MOVEMENT_COUNT=$(printf '%s\n' "$MOVEMENT_HITS" | grep -c .)
fi

if [ "$MOVEMENT_COUNT" -eq 1 ]; then
    echo "OK: exactly one _movement_used gate implementation found (ADR-002/ADR-006)"
else
    echo "ERROR: expected exactly one '_movement_used' gate declaration, found $MOVEMENT_COUNT:" >&2
    echo "$MOVEMENT_HITS" >&2
    FAILURES=$((FAILURES + 1))
fi

# ── 2. Exactly one concrete AI decision (decide_action) call path ──────────
# The abstract Protocol stub (ai_decision_port.gd) documents the contract
# but never decides anything itself — excluded by name, mirroring this
# project's existing --exclude="rng.gd" ADR-002 lint convention.
DECIDE_ACTION_HITS="$(grep -rln "func decide_action(" --include="*.gd" "${EXISTING_SCAN_DIRS[@]}" 2>/dev/null \
    | grep -v -- '/ai_decision_port\.gd$' || true)"
DECIDE_ACTION_COUNT=0
if [ -n "$DECIDE_ACTION_HITS" ]; then
    DECIDE_ACTION_COUNT=$(printf '%s\n' "$DECIDE_ACTION_HITS" | grep -c .)
fi

if [ "$DECIDE_ACTION_COUNT" -eq 1 ]; then
    echo "OK: exactly one concrete AI decision (decide_action) call path found (ADR-002/ADR-006)"
else
    echo "ERROR: expected exactly one concrete 'decide_action' implementation (excluding the abstract ai_decision_port.gd stub), found $DECIDE_ACTION_COUNT:" >&2
    echo "$DECIDE_ACTION_HITS" >&2
    FAILURES=$((FAILURES + 1))
fi

# ── 3. Exactly one token-reposition call path (move_token) ─────────────────
MOVE_TOKEN_HITS="$(grep -rln "func move_token(" --include="*.gd" "${EXISTING_SCAN_DIRS[@]}" 2>/dev/null || true)"
MOVE_TOKEN_COUNT=0
if [ -n "$MOVE_TOKEN_HITS" ]; then
    MOVE_TOKEN_COUNT=$(printf '%s\n' "$MOVE_TOKEN_HITS" | grep -c .)
fi

if [ "$MOVE_TOKEN_COUNT" -eq 1 ]; then
    echo "OK: exactly one token-reposition (move_token) call path found (ADR-002/ADR-006)"
else
    echo "ERROR: expected exactly one 'move_token' implementation, found $MOVE_TOKEN_COUNT:" >&2
    echo "$MOVE_TOKEN_HITS" >&2
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "check_no_duplicate_seams.sh: $FAILURES seam(s) failed the no-duplicate check" >&2
    exit 1
fi

echo "check_no_duplicate_seams.sh: all seams singular — no duplicate ports/use-cases/gates detected"
exit 0
