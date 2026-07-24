#!/usr/bin/env bash
# ci/check_mainscene_gate.sh — FEAT-010 (US-009; FR-009, FR-010, FR-011;
# ADR-001 fitness functions)
#
# Standalone, independently-invokable CI gate enforcing the composition
# root's two structural fitness functions established by ADR-001 and this
# steel thread's design notes:
#
#   1. Line-count budget — `wc -l MainScene.gd` must be <= 1000. MainScene.gd
#      is the project's ONE composition root (project.godot's run/main_scene
#      points at MainScene.tscn, which attaches this script); everything
#      else (adapters, ports, use cases, presentation controllers) lives in
#      its own file under core/ or presentation/. A composition root that
#      keeps growing past this budget is a signal that feature branching or
#      domain calculation is creeping back into _ready()/signal-wiring code
#      instead of staying inside an extracted controller/session/adapter.
#
#   2. No circular preload — MainScene.gd must never `preload`/`load` itself
#      (res://MainScene.gd). Every other file this project's controllers/
#      adapters/use cases live in is preloaded BY MainScene (the composition
#      root depends outward on them); the reverse dependency (MainScene
#      preloading its own script) is nonsensical and would be a sign that
#      some other file's careless self-reference or a copy/paste of this
#      file's own preload table introduced a cycle.
#
# Usage:
#   ci/check_mainscene_gate.sh [mainscene_path]
#
#   mainscene_path defaults to "MainScene.gd" (repo-root-relative or
#   absolute). Tests pass an explicit fixture file so the "current
#   MainScene.gd passes" and "an oversized/circular fixture fails" criteria
#   can both be exercised without ever mutating the real MainScene.gd.
#
# Exit code: 0 when mainscene_path is <= 1000 lines AND contains no
# preload/load statement referencing "MainScene.gd" itself; non-zero (with a
# clear diagnostic on stderr) otherwise.

set -euo pipefail

MAINSCENE_PATH="${1:-MainScene.gd}"
LINE_LIMIT=1000

if [ ! -f "$MAINSCENE_PATH" ]; then
    echo "ERROR: check_mainscene_gate.sh: file '$MAINSCENE_PATH' does not exist" >&2
    exit 1
fi

FAILURES=0

# ── 1. Line-count budget ────────────────────────────────────────────────
LINE_COUNT="$(wc -l < "$MAINSCENE_PATH" | tr -d '[:space:]')"

if [ "$LINE_COUNT" -le "$LINE_LIMIT" ]; then
    echo "OK: $MAINSCENE_PATH is $LINE_COUNT lines (<= $LINE_LIMIT budget, US-009/FR-009/ADR-001)"
else
    echo "ERROR: $MAINSCENE_PATH is $LINE_COUNT lines, exceeding the $LINE_LIMIT-line composition-root budget (US-009/FR-009/ADR-001). Extract more logic into presentation/application/adapter files." >&2
    FAILURES=$((FAILURES + 1))
fi

# ── 2. No circular preload (MainScene.gd referencing itself) ───────────
# Only a genuine preload()/load() call naming "MainScene.gd" is a circular
# reference -- a `##` doc-comment mentioning "MainScene.gd" in prose (this
# project's established documentation convention, e.g. "see MainScene.gd's
# own FEAT-316 doc") must never be flagged. Filter comment-only lines
# before searching for the preload/load call.
CIRCULAR_HITS="$(grep -nE '(preload|load)\([^)]*MainScene\.gd' "$MAINSCENE_PATH" 2>/dev/null \
    | grep -vE ':[[:space:]]*##' || true)"

if [ -z "$CIRCULAR_HITS" ]; then
    echo "OK: $MAINSCENE_PATH contains no circular preload/load referencing itself (US-009/FR-010/FR-011/ADR-001)"
else
    echo "ERROR: $MAINSCENE_PATH preloads/loads itself (circular composition-root reference, US-009/FR-010/FR-011/ADR-001):" >&2
    echo "$CIRCULAR_HITS" >&2
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "check_mainscene_gate.sh: $FAILURES fitness-function check(s) failed" >&2
    exit 1
fi

echo "check_mainscene_gate.sh: MainScene.gd passes both composition-root fitness functions"
exit 0
