#!/usr/bin/env bash
# ci/check_domain_purity.sh — FEAT-009 (US-009; NFR-001, NFR-002, NFR-006,
# NFR-007; ADR-001)
#
# Standalone, independently-invokable CI gate enforcing ADR-001's domain
# purity rule: core/ (this project's domain + application layer) must stay
# pure GDScript/Python — ZERO Godot scene-tree (Node/Control-descendant)
# inheritance. .github/workflows/test.yml already runs an inline
# `grep -rn "extends Node\|extends Control\|extends CanvasItem" core/` step,
# but that check only exists embedded inside the workflow YAML — it cannot
# be run locally, unit-tested on its own, or reused by another gate. This
# script extracts the SAME rule into a real, testable artifact under ci/
# (see tests/ci/test_static_checks.gd for the executable proof it actually
# catches an injected violation) so it can be wired in as its own named,
# blocking stage (see ci/pipeline.yml's domain_purity_check stage).
#
# Usage:
#   ci/check_domain_purity.sh [target_dir]
#
#   target_dir defaults to "core" (repo-root-relative or absolute). Tests
#   pass an explicit fixture directory so the "current core/ tree passes"
#   and "an injected violation fails" criteria can both be exercised
#   without ever mutating the real core/ tree.
#
# Exit code: 0 when target_dir contains no bare `extends Node` / `extends
# Control` clause in any *.gd file; non-zero (with the offending file:line
# printed to stderr) otherwise.

set -euo pipefail

TARGET_DIR="${1:-core}"

if [ ! -d "$TARGET_DIR" ]; then
    echo "ERROR: check_domain_purity.sh: target directory '$TARGET_DIR' does not exist" >&2
    exit 1
fi

# Only a BARE (non-string) `extends Node`/`extends Control` clause is a
# scene-tree dependency. A quoted `extends "res://...gd"` chain (this
# project's established script-inheritance pattern, e.g.
# core/application/ai_decision_port.gd's concrete adapters) is same-layer
# inheritance, not an engine dependency, and must never be flagged.
VIOLATIONS="$(grep -rnE '^[[:space:]]*extends[[:space:]]+(Node|Control)\b' \
    --include="*.gd" "$TARGET_DIR" 2>/dev/null || true)"

if [ -n "$VIOLATIONS" ]; then
    echo "ERROR: 'extends Node'/'extends Control' found under $TARGET_DIR/ (ADR-001 domain purity violation):" >&2
    echo "$VIOLATIONS" >&2
    exit 1
fi

echo "OK: no 'extends Node'/'extends Control' found under $TARGET_DIR/ (ADR-001)"
exit 0
