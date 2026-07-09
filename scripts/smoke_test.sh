#!/usr/bin/env bash
# scripts/smoke_test.sh — FEAT-220 (US-002..US-009; resolves PR-003/PR-004)
#
# THE concrete, automated "installable artifact" / exported-build smoke
# test the deployment gate flagged as missing: a standalone, CI-runnable
# release gate that boots the REAL Godot application headless — the exact
# res://MainScene.tscn composition root project.godot's own run/main_scene
# points at, never a hand-wired double (G2) — and drives the actual, full
# Dodge-Step steel thread end to end:
#
#   a real attack -> a forced-successful Dodge -> a scripted legal-hex pick
#   -> the defender's token relocation -> a single rich log row with the
#   correct "Defense: dodge" segment
#
# via tests/gut/test_smoke_full_steel_thread.gd, run through GUT's real CLI
# entry point (addons/gut/gut_cmdln.gd), scoped to just that one test file
# (mirroring this project's established scripts/test_command.sh convention
# of invoking gut_cmdln.gd directly with -gdir=/-gselect= rather than the
# `-- --gut-run-all` HeadlessRunner path, so this stays a genuinely scoped,
# fast, independently-invokable gate).
#
# Exit code: 0 only if the smoke test's every assertion passes. `set -euo
# pipefail` + GUT's own `-gexit` flag ensure a single failing assertion
# anywhere in tests/gut/test_smoke_full_steel_thread.gd aborts this script
# with a non-zero exit code — giving CI a real user-journey check rather
# than a manual sign-off document.
#
# This is a standalone release gate, distinct from (and not a replacement
# for) scripts/test_command.sh's own full stage list — it can be run on its
# own, locally or as its own CI job, alongside the full existing GUT+pytest
# suite (scripts/test_command.sh), which must also remain green.
#
# Usage:
#   scripts/smoke_test.sh

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "=== FEAT-220 smoke test: full steel thread (Dodge-Step relocation + rich log) ==="
echo "=== booting the real MainScene.tscn composition root headlessly via GUT ==="
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gselect=test_smoke_full_steel_thread.gd -gexit

echo "=== scripts/smoke_test.sh: smoke test passed (exit 0) ==="
