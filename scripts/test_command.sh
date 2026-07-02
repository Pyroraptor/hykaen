#!/usr/bin/env bash
# scripts/test_command.sh — FEAT-133 / FEAT-136 / US-011 (NFR-004, NFR-006,
# NFR-008, NFR-009; DEF-002, DEF-003) CI quality-gate wiring and headless
# regression config.
#
# THE single canonical automated test gate for the hykaen project — the
# entry point declared by ci/pipeline.yml's `test_command:` key and invoked
# directly by .github/workflows/test.yml's CI job (FEAT-136). The
# root-level `test_command` script is a thin delegating wrapper around this
# file (see test_command at the repo root); it has no stage list of its
# own, so there is exactly ONE place project test stages are defined —
# resolving the previously divergent/duplicated stage lists across
# `test_command` (FEAT-004) and `scripts/test_command.sh` (FEAT-133)
# (DEF-002/DEF-003).
#
# Runs, in order, aborting immediately (non-zero exit) if any stage fails:
#
#   1. FEAT-001 headless launchability smoke test
#      (tests/gut/test_smoke_boot.gd) — boots the project's composition-
#      root entry point (MainScene.tscn) headlessly and asserts autoload
#      resolution, run/main_scene wiring, and first-frame processing with
#      no unhandled errors. Run via GUT's real CLI entry point
#      (addons/gut/gut_cmdln.gd, -gdir=/-gselect=) scoped to just
#      tests/gut/test_smoke_boot.gd — a cheap, EARLY regression signal for
#      the entry point, ahead of every other stage below.
#
#   2. pytest — the full Python test suite (CI/infra + config assertions
#      under tests/unit/*.py, including this file's own suite).
#
#   3. The CONSOLIDATED domain suite via tests/.gutconfig.json — hex
#      distance/adjacency, Combatant hex-coordinate init, melee reach
#      gating, RoundSession stepwise API, enemy-turn automation, Step/
#      Stride movement, and Flanking/Off-Guard domain logic under
#      tests/unit/core. This is the single green gate for that
#      domain/application layer that must pass before any UI work
#      begins. Run via GUT's real CLI entry point (-gconfig=) rather than
#      the -- --gut-run-all/HeadlessRunner path: the project's
#      HeadlessRunner autoload (tests/runner/headless_runner.gd) hardcodes
#      loading res://.gutconfig.json for a bare --gut-run-all flag and
#      ignores any -gconfig= passed alongside it, which would silently
#      widen this stage to the full project suite instead of the intended
#      consolidated domain suite. Invoking gut_cmdln.gd directly (as stage
#      1 already does) honors -gconfig= and keeps this stage a genuinely
#      scoped, fast gate.
#
#   4. The FULL project-wide GUT suite (root .gutconfig.json) via
#      `godot --headless -- --gut-run-all`. This is the whole-project
#      regression gate and already includes both
#      tests/gut/test_smoke_boot.gd (stage 1) and tests/sim/test_balance_sim.gd
#      (stage 5 below).
#
#   5. core/sim/simulator.gd N=1000 balance regression
#      (tests/sim/test_balance_sim.gd, NFR-006/NFR-008/NFR-009) — already
#      covered by stage 4's full-project run, but called out here as its
#      own explicit, clearly-labeled gate confirming the aggregate
#      win-rate/outcome distribution stays within existing tolerance
#      ([0.40, 0.80]) and that no balance-affecting constants were
#      modified. Run via GUT's real CLI entry point scoped to just
#      tests/sim/test_balance_sim.gd, mirroring stage 1's convention.
#
#   6. Steel thread prologue-encounter E2E test
#      (tests/integration/test_steel_thread_prologue_encounter.gd) —
#      already covered by stage 4's full-project run, but called out here
#      as its own explicit, clearly-labeled gate: it headlessly boots
#      MainScene.tscn into prologue_encounter.tres, verifies the hex
#      battlefield/status/initiative render, drives a player melee Strike
#      and a full AI-controlled enemy turn through the real Presentation/
#      event pipeline, confirms the Win/Loss ResultScreenView with input
#      disabled afterward, and re-confirms determinism (NFR-002/006) by
#      booting the same seeded encounter twice. Run via GUT's real CLI
#      entry point with -gselect= scoped to this one script (mirroring
#      stage 1/3/5's convention of invoking gut_cmdln.gd directly rather
#      than the -- --gut-run-all/HeadlessRunner path).
#
# Exit code: 0 only if every stage above exits 0. `set -euo pipefail`
# ensures a single failing assertion anywhere aborts the script
# immediately with a non-zero exit code.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "=== [1/6] FEAT-001 / NFR-004 headless launchability smoke test (tests/gut/test_smoke_boot.gd) ==="
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gselect=test_smoke_boot.gd -gexit

echo "=== [2/6] pytest suite ==="
python -m pytest -q --tb=short

echo "=== [3/6] GUT consolidated domain suite (tests/.gutconfig.json) ==="
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=res://tests/.gutconfig.json -gexit

echo "=== [4/6] GUT full project suite (root .gutconfig.json, --gut-run-all regression gate) ==="
godot --headless -- --gut-run-all

echo "=== [5/6] core/sim/simulator.gd N=1000 balance regression (NFR-006 / NFR-008 / NFR-009, tests/sim/test_balance_sim.gd) ==="
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/sim -gselect=test_balance_sim.gd -gexit

echo "=== [6/6] Steel thread prologue-encounter E2E test ==="
godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_steel_thread_prologue_encounter.gd -gdir=res://tests/integration -ginclude_subdirs -gexit

echo "=== scripts/test_command.sh: all stages passed ==="
