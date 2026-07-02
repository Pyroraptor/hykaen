#!/usr/bin/env bash
# scripts/test_command.sh — FEAT-133 / US-011 (NFR-004, NFR-006, NFR-008,
# NFR-009) CI quality-gate wiring and headless regression config.
#
# Canonical single-invocation CI entry point declared by ci/pipeline.yml's
# `test_command: scripts/test_command.sh`. Wires the FEAT-001 headless
# smoke test (tests/gut/test_smoke_boot.gd) into the SAME gate as the full
# pytest suite and the full GUT project suite (`--gut-run-all`), and
# additionally invokes the core/sim/simulator.gd N=1000 balance regression
# (tests/sim/test_balance_sim.gd) explicitly, so the full steel thread and
# the existing suite are gated together in one command.
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
#   3. The FULL project-wide GUT suite (root .gutconfig.json) via
#      `godot --headless -- --gut-run-all`. This is the whole-project
#      regression gate and already includes both
#      tests/gut/test_smoke_boot.gd (stage 1, re-run here as part of the
#      full suite) and tests/sim/test_balance_sim.gd (stage 4 below).
#
#   4. core/sim/simulator.gd N=1000 balance regression
#      (tests/sim/test_balance_sim.gd, NFR-006/NFR-008/NFR-009) — already
#      covered by stage 3's full-project run, but called out here as its
#      own explicit, clearly-labeled gate confirming the aggregate
#      win-rate/outcome distribution stays within existing tolerance
#      ([0.40, 0.80]) and that no balance-affecting constants were
#      modified. Run via GUT's real CLI entry point scoped to just
#      tests/sim/test_balance_sim.gd, mirroring stage 1's convention.
#
# Exit code: 0 only if every stage above exits 0. `set -euo pipefail`
# ensures a single failing assertion anywhere aborts the script
# immediately with a non-zero exit code.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "=== [1/4] FEAT-001 / NFR-004 headless launchability smoke test (tests/gut/test_smoke_boot.gd) ==="
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gselect=test_smoke_boot.gd -gexit

echo "=== [2/4] pytest suite ==="
python -m pytest -q --tb=short

echo "=== [3/4] GUT full project suite (root .gutconfig.json, --gut-run-all regression gate) ==="
godot --headless -- --gut-run-all

echo "=== [4/4] core/sim/simulator.gd N=1000 balance regression (NFR-006 / NFR-008 / NFR-009, tests/sim/test_balance_sim.gd) ==="
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/sim -gselect=test_balance_sim.gd -gexit

echo "=== scripts/test_command.sh: all stages passed ==="
