#!/usr/bin/env bash
# tests/unit/test_ci_infrastructure.sh
#
# Validates the CI/GUT infrastructure bootstrap (FEAT-001) without
# requiring a running Godot binary.  Every assertion prints PASS or FAIL
# and the script exits non-zero if any assertion failed.
#
# Run from the repository root:
#   bash tests/unit/test_ci_infrastructure.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }

# ── File existence checks ────────────────────────────────────────────────────

[ -f "$REPO_ROOT/.github/workflows/test.yml" ] \
    && pass ".github/workflows/test.yml exists" \
    || fail ".github/workflows/test.yml is missing"

[ -f "$REPO_ROOT/addons/gut/plugin.cfg" ] \
    && pass "addons/gut/plugin.cfg exists (GUT plugin installed)" \
    || fail "addons/gut/plugin.cfg is missing"

[ -f "$REPO_ROOT/tests/unit/test_placeholder.gd" ] \
    && pass "tests/unit/test_placeholder.gd exists" \
    || fail "tests/unit/test_placeholder.gd is missing"

[ -d "$REPO_ROOT/tests/unit" ] \
    && pass "tests/unit/ directory exists" \
    || fail "tests/unit/ directory is missing"

[ -d "$REPO_ROOT/tests/integration" ] \
    && pass "tests/integration/ directory exists" \
    || fail "tests/integration/ directory is missing"

[ -d "$REPO_ROOT/tests/sim" ] \
    && pass "tests/sim/ directory exists" \
    || fail "tests/sim/ directory is missing"

[ -f "$REPO_ROOT/project.godot" ] \
    && pass "project.godot exists" \
    || fail "project.godot is missing"

[ -f "$REPO_ROOT/.gutconfig.json" ] \
    && pass ".gutconfig.json exists" \
    || fail ".gutconfig.json is missing"

# ── Content checks ───────────────────────────────────────────────────────────

# Placeholder test must contain the canonical assert_eq call
grep -q "assert_eq(1, 1" "$REPO_ROOT/tests/unit/test_placeholder.gd" \
    && pass "test_placeholder.gd contains assert_eq(1, 1, ...)" \
    || fail "test_placeholder.gd is missing the assert_eq(1, 1, ...) call"

grep -q "extends GutTest" "$REPO_ROOT/tests/unit/test_placeholder.gd" \
    && pass "test_placeholder.gd extends GutTest" \
    || fail "test_placeholder.gd does not extend GutTest"

# CI workflow triggers
grep -q "pull_request" "$REPO_ROOT/.github/workflows/test.yml" \
    && pass "CI workflow includes pull_request trigger" \
    || fail "CI workflow missing pull_request trigger"

grep -q "branches:" "$REPO_ROOT/.github/workflows/test.yml" \
    && pass "CI workflow specifies branch filter" \
    || fail "CI workflow missing branch filter"

grep -q "main" "$REPO_ROOT/.github/workflows/test.yml" \
    && pass "CI workflow targets main branch" \
    || fail "CI workflow does not reference main branch"

# Linter steps present
grep -q "extends Node" "$REPO_ROOT/.github/workflows/test.yml" \
    && pass "CI workflow includes ADR-001 linter (Node check)" \
    || fail "CI workflow missing ADR-001 linter"

grep -q '\.scn\|\.res' "$REPO_ROOT/.github/workflows/test.yml" \
    && pass "CI workflow includes ADR-009 linter (binary resource check)" \
    || fail "CI workflow missing ADR-009 linter"

grep -q "randf\|randi" "$REPO_ROOT/.github/workflows/test.yml" \
    && pass "CI workflow includes ADR-002 linter (RNG check)" \
    || fail "CI workflow missing ADR-002 linter"

# GUT output artifact upload
grep -q "upload-artifact" "$REPO_ROOT/.github/workflows/test.yml" \
    && pass "CI workflow uploads GUT output artifact" \
    || fail "CI workflow missing artifact upload step"

grep -q "if: always()" "$REPO_ROOT/.github/workflows/test.yml" \
    && pass "Artifact upload runs on always() (pass AND fail)" \
    || fail "Artifact upload missing always() condition"

# project.godot plugin
grep -q "gut/plugin.cfg" "$REPO_ROOT/project.godot" \
    && pass "project.godot references GUT plugin" \
    || fail "project.godot does not reference GUT plugin"

grep -q "HeadlessRunner\|headless_runner" "$REPO_ROOT/project.godot" \
    && pass "project.godot registers HeadlessRunner autoload" \
    || fail "project.godot missing HeadlessRunner autoload"

# .gutconfig.json valid JSON and contains dirs
python3 -c "import json,sys; d=json.load(open('$REPO_ROOT/.gutconfig.json')); assert 'dirs' in d, 'missing dirs'; assert d.get('should_exit') == True, 'should_exit must be true'" \
    && pass ".gutconfig.json is valid JSON with required fields" \
    || fail ".gutconfig.json is malformed or missing required fields"

# ── Linter dry-runs (validate the linter logic itself) ───────────────────────

# Linter 1: core/ is empty → should pass (no violations to find)
if grep -rn "extends Node\|extends Control\|extends CanvasItem" "$REPO_ROOT/core/" 2>/dev/null; then
    fail "Linter 1 would reject current core/ — contains Node/Control/CanvasItem"
else
    pass "Linter 1 passes: core/ has no Node/Control/CanvasItem violations"
fi

# Linter 2: no binary .scn/.res outside addons/
VIOLATIONS=$(find "$REPO_ROOT" \( -name "*.scn" -o -name "*.res" \) ! -path "*/addons/*" ! -path "*/.git/*" 2>/dev/null)
if [ -n "$VIOLATIONS" ]; then
    fail "Linter 2 would reject — binary resources found: $VIOLATIONS"
else
    pass "Linter 2 passes: no binary .scn/.res outside addons/"
fi

# Linter 3: core/ has no rng violations (core/rules/rng.gd excluded)
if grep -rn "randf\|randi\b\|RandomNumberGenerator\.new()" "$REPO_ROOT/core/" \
       --exclude="rng.gd" 2>/dev/null; then
    fail "Linter 3 would reject current core/ — contains direct RNG usage"
else
    pass "Linter 3 passes: core/ has no direct RNG usage (excluding rng.gd)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
