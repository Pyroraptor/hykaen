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
#   3. FEAT-158 (FIND-151) CI pipeline stage-list consistency check
#      (scripts/check_ci_pipeline_sync.py) — ci/pipeline.yml's per-stage
#      `command:` entries are documentation describing the SAME stage list
#      this script executes; nothing previously stopped the two from
#      drifting apart. This stage parses both stage lists and fails the
#      whole pipeline immediately if they diverge, so drift is caught in
#      CI rather than discovered later by a human reading stale docs.
#      Already indirectly exercised by stage 2 via pytest test discovery
#      (tests/ci/test_pipeline_sync.py), but also invoked directly here so
#      a stage-list divergence produces its own clearly-labeled failure.
#
#   4. FEAT-239 (US-009, resolves PR-004; ADR-006) sim_results.json
#      provenance guard (scripts/ci/check_sim_results_provenance.py) — a
#      standalone gate diffing the current commit against its parent and
#      failing the build if sim_results.json's tracked metric keys
#      (win_rate/avg_rounds/total_battles/confidence_interval) moved
#      without a sanctioned weapon/enemy data file (a *.tres resource
#      under data/weapons/ or data/enemies/) changing in the same commit.
#      Prevents exactly the kind of silent reaction-variance leakage
#      ADR-006 is meant to catch (see
#      tests/ci/test_check_sim_results_provenance.py).
#
#   5. FEAT-009 (US-009) domain purity static check
#      (ci/check_domain_purity.sh) — a standalone, independently-invokable
#      gate asserting core/ contains zero bare 'extends Node'/'extends
#      Control' Godot scene-tree inheritance (ADR-001). Extracted from the
#      inline grep step already embedded in .github/workflows/test.yml so
#      it can be run/tested on its own (see tests/ci/test_static_checks.gd).
#
#   6. FEAT-009 (US-009) no-duplicate-ports/use-cases/seams check
#      (ci/check_no_duplicate_seams.sh) — a standalone gate confirming
#      exactly one _movement_used gate implementation and exactly one
#      concrete AI decision (decide_action)/token-reposition (move_token)
#      call path exist across core/, presentation/, and infrastructure/
#      (ADR-002/ADR-006 — no new/duplicate seam introduced).
#
#   7. The CONSOLIDATED domain suite via tests/.gutconfig.json — hex
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
#   8. The FULL project-wide GUT suite (root .gutconfig.json) via
#      `godot --headless -- --gut-run-all`. This is the whole-project
#      regression gate and already includes both
#      tests/gut/test_smoke_boot.gd (stage 1) and tests/sim/test_balance_sim.gd
#      (stage 9 below).
#
#   9. core/sim/simulator.gd N=1000 balance regression
#      (tests/sim/test_balance_sim.gd, NFR-006/NFR-008/NFR-009) — already
#      covered by stage 8's full-project run, but called out here as its
#      own explicit, clearly-labeled gate confirming the aggregate
#      win-rate/outcome distribution stays within existing tolerance
#      ([0.40, 0.80]) and that no balance-affecting constants were
#      modified. Run via GUT's real CLI entry point scoped to just
#      tests/sim/test_balance_sim.gd, mirroring stage 1's convention.
#
#   10. Steel thread prologue-encounter E2E test
#      (tests/e2e/test_full_steel_thread_e2e.gd, FEAT-167) — already
#      covered by stage 8's full-project run, but called out here as its
#      own explicit, clearly-labeled gate: it headlessly boots the real
#      MainScene.tscn composition root into prologue_encounter.tres and
#      drives the COMPLETE steel thread end-to-end (turn-start highlight,
#      a movement Step/Stride, a player melee Strike, a full
#      AI-controlled enemy turn, and the post-resolution ResultScreenView
#      lock with Strike/EndTurn/Move all disabled and the hex highlight
#      cleared). DEF-002 fix (FEAT-172): this stage previously selected
#      tests/integration/test_steel_thread_prologue_encounter.gd instead
#      of the intended E2E capstone test; -gselect/-gdir now resolve
#      directly to tests/e2e/test_full_steel_thread_e2e.gd (see
#      tests/ci/test_pipeline_e2e_stage_config.py). Run via GUT's real
#      CLI entry point with -gselect= scoped to this one script
#      (mirroring stage 1/7/9's convention of invoking gut_cmdln.gd
#      directly rather than the -- --gut-run-all/HeadlessRunner path).
#
#   11. FEAT-255 (US-004/US-005/US-006/US-012/US-013, resolves PR-004,
#      RISK-006) pinned-seed baseline-diff regression gate
#      (tests/regression/test_baseline_diff_regression.gd) — already
#      covered by stage 8's full-project run, but called out here as its
#      own explicit, clearly-labeled gate: re-drives the Effects Applier
#      retrofit's player-Strike, enemy-on-hit-reaction, and END_TURN
#      boot-real scenarios at the pinned seed=42 fixture and asserts
#      hp outcome / AttackEvent fields / rendered combat-log line / the
#      full round-event sequence all diff to ZERO against the checked-in
#      tests/regression/fixtures/baseline_*_seed42.json snapshots —
#      turning RISK-006's previously-manual "no behavior change" diff
#      step into a durable, automated, gating artifact. Run via GUT's
#      real CLI entry point scoped to just this one script (mirrors
#      stage 1/7/9/10's convention).
#
# FEAT-246 (US-015): tests/e2e/test_steel_thread_strike_full_flow.gd — the
# steel thread's final end-to-end smoke test, consolidating this
# iteration's additive selection/execute generalization work
# (FEAT-004..FEAT-014, FEAT-242..FEAT-245) into one continuous proof: a
# boot-real player-Strike and a boot-real enemy-reaction scenario both
# mutate hp through the single EffectsApplier seam with an AttackEvent/log
# outcome byte-identical to the established pre-retrofit baseline, the
# SAME selection/execute pipeline additively resolves an option-list pick
# and a fully-resolved AREA target set into execute() without regressing
# Strike or END_TURN, and a pinned-seed rerun reproduces an identical
# hp/AttackEvent/log outcome (determinism). This file lives under
# res://tests/e2e, so it is already picked up automatically by stage 8's
# full-project run (the root .gutconfig.json's ("res://tests",
# include_subdirs=true) scope), exactly like
# tests/e2e/test_steel_thread_post_remediation_smoke.gd before it; it
# gains no dedicated numbered stage of its own (unlike FEAT-255's stage 11
# above, which pins the SAME retrofit's outcome against checked-in fixture
# snapshots rather than merely reproducing it once, so it stays a distinct,
# explicit, gating stage).
#
# Exit code: 0 only if every stage above exits 0. `set -euo pipefail`
# ensures a single failing assertion anywhere aborts the script
# immediately with a non-zero exit code.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "=== [1/11] FEAT-001 / NFR-004 headless launchability smoke test (tests/gut/test_smoke_boot.gd) ==="
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gselect=test_smoke_boot.gd -gexit

echo "=== [2/11] pytest suite ==="
# HYKAEN_TEST_COMMAND_E2E_GUARD=1: the recursive end-to-end meta-tests
# (tests/unit/test_ci_quality_gate_wiring_feat133.py,
# tests/unit/test_ci_gut_domain_consolidation_feat004.py) shell out THIS very
# script and assert it exits 0. Inside the gate's own pytest stage that is pure
# recursion — each spawns a nested full pipeline (smoke+pytest+GUT+sim+e2e), so
# ~4 nested gates hammer the machine at once and intermittently flake on GUT
# 4.3 teardown noise ("Nonexistent function 'clear' in base 'Nil'"), and with
# `set -euo pipefail` a single flake aborts the whole gate before the real
# GUT/sim/e2e stages. The tests already honor this guard var (they skip when
# it's "1", and set it in the child env when spawning). Activating it here makes
# the gate deterministic + fast WITHOUT losing coverage: the meta-tests still
# run when pytest is invoked standalone (no guard set), where they legitimately
# exercise the script end-to-end exactly once.
HYKAEN_TEST_COMMAND_E2E_GUARD=1 python -m pytest -q --tb=short

echo "=== [3/11] FEAT-158 CI pipeline stage-list consistency check (FIND-151) ==="
python scripts/check_ci_pipeline_sync.py

echo "=== [4/11] FEAT-239 sim_results.json provenance guard (PR-004 / ADR-006) ==="
python scripts/ci/check_sim_results_provenance.py

echo "=== [5/11] FEAT-009 domain purity static check (ADR-001) ==="
ci/check_domain_purity.sh core

echo "=== [6/11] FEAT-009 no-duplicate-ports/use-cases/seams check (ADR-002/ADR-006) ==="
ci/check_no_duplicate_seams.sh

echo "=== [7/11] GUT consolidated domain suite (tests/.gutconfig.json) ==="
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=res://tests/.gutconfig.json -gexit

echo "=== [8/11] GUT full project suite (root .gutconfig.json, --gut-run-all regression gate) ==="
godot --headless -- --gut-run-all

echo "=== [9/11] core/sim/simulator.gd N=1000 balance regression (NFR-006 / NFR-008 / NFR-009, tests/sim/test_balance_sim.gd) ==="
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/sim -gselect=test_balance_sim.gd -gexit

echo "=== [10/11] Steel thread prologue-encounter E2E test (tests/e2e/test_full_steel_thread_e2e.gd) ==="
godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_full_steel_thread_e2e.gd -gdir=res://tests/e2e -gexit

echo "=== [11/11] FEAT-255 pinned-seed baseline-diff regression gate (resolves PR-004 / RISK-006, tests/regression/test_baseline_diff_regression.gd) ==="
godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_baseline_diff_regression.gd -gdir=res://tests/regression -gexit

echo "=== scripts/test_command.sh: all stages passed ==="
