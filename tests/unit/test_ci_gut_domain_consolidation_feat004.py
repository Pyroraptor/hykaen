"""
tests/unit/test_ci_gut_domain_consolidation_feat004.py

Pytest suite for FEAT-004: GUT domain-suite consolidation and CI wiring
(US-014).

Verifies:
  1. A `test_command` script exists at the repo root, is executable, and
     (as of FEAT-136 / DEF-002 / DEF-003) delegates to scripts/test_command.sh
     — the single canonical script — which wires together `pytest` and
     `godot --gut-run-all` (headless) as the project's single automated
     test gate.
  2. The canonical script (scripts/test_command.sh) explicitly runs the
     consolidated domain suite via `tests/.gutconfig.json` — the single
     green gate for the new hex distance/adjacency + melee reach gating
     domain logic (US-001/US-002/US-003) — as well as the full
     project-wide GUT suite for regression safety.
  3. `tests/.gutconfig.json` is valid JSON and is configured to collect
     exactly the domain/application suites under tests/unit/core
     (test_hex_coord.gd, test_hex_math.gd, test_combatant_hex_init.gd,
     test_resolve_action_reach.gd, test_round_session.gd [FEAT-110],
     test_round_session_ai_turn.gd [FEAT-111],
     test_movement_step.gd [FEAT-013], test_movement_stride.gd [FEAT-014],
     test_flanking.gd [FEAT-015],
     test_resolve_action_ranged_reach.gd [FEAT-140]),
     with should_exit true so the exit code is forwarded correctly in
     CI/headless runs.
  4. Actually running `godot --headless -- -gconfig=res://tests/.gutconfig.json
     --gut-run-all` (skipped if no `godot` binary is on PATH) passes and
     reports all ten consolidated domain test files.
  5. Running the full `test_command` script end-to-end (skipped if no
     `godot` binary is on PATH) exits 0.

FEAT-136 / DEF-002 / DEF-003 UPDATE: `test_command` (this feature's script)
and `scripts/test_command.sh` (FEAT-133's script) previously hand-duplicated
divergent stage lists — the exact defect this reconciliation feature fixes.
scripts/test_command.sh is now THE single canonical script (matching
ci/pipeline.yml's declared test_command); `test_command` at the repo root
is a thin delegating wrapper around it with no stage list of its own. The
stage-content assertions below therefore check scripts/test_command.sh
(via the `canonical_script_text` fixture) rather than `test_command`
directly — `test_command`'s own assertions (TestTestCommandFileExists,
TestTestCommandWiring) now confirm existence/executability/delegation
instead. See tests/unit/test_ci_quality_gate_wiring_feat133.py for the
FEAT-133/FEAT-136 canonical-script test suite.

All assertions that don't require a running Godot binary are pure-Python
filesystem/JSON checks so they run in any environment with pytest installed.
"""

import json
import os
import re
import shutil
import stat
import subprocess
from pathlib import Path

import pytest


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def repo_root() -> Path:
    """Absolute path to the repository root (where project.godot lives)."""
    return Path(__file__).parent.parent.parent


@pytest.fixture(scope="module")
def test_command_path(repo_root) -> Path:
    return repo_root / "test_command"


@pytest.fixture(scope="module")
def test_command_text(test_command_path) -> str:
    assert test_command_path.is_file(), "test_command must exist at the repo root"
    return test_command_path.read_text()


@pytest.fixture(scope="module")
def canonical_script_path(repo_root) -> Path:
    """FEAT-136 / DEF-002 / DEF-003: scripts/test_command.sh is now THE
    single canonical script; the root `test_command` delegates to it."""
    return repo_root / "scripts" / "test_command.sh"


@pytest.fixture(scope="module")
def canonical_script_text(canonical_script_path) -> str:
    assert canonical_script_path.is_file(), (
        "scripts/test_command.sh (the canonical script) must exist"
    )
    return canonical_script_path.read_text()


@pytest.fixture(scope="module")
def tests_gutconfig_path(repo_root) -> Path:
    return repo_root / "tests" / ".gutconfig.json"


@pytest.fixture(scope="module")
def tests_gutconfig(tests_gutconfig_path) -> dict:
    assert tests_gutconfig_path.is_file(), "tests/.gutconfig.json must exist"
    return json.loads(tests_gutconfig_path.read_text())


GODOT_AVAILABLE = shutil.which("godot") is not None


# ── test_command exists, is executable, and wires pytest + GUT ──────────────

class TestTestCommandFileExists:
    def test_test_command_exists(self, test_command_path):
        assert test_command_path.is_file()

    def test_test_command_is_executable(self, test_command_path):
        mode = test_command_path.stat().st_mode
        assert mode & stat.S_IXUSR, "test_command must be executable (chmod +x)"

    def test_test_command_has_shebang(self, test_command_text):
        assert test_command_text.startswith("#!"), (
            "test_command must start with a shebang line"
        )


class TestTestCommandWiring:
    """FEAT-136 / DEF-002 / DEF-003: `test_command` no longer hand-duplicates
    stage invocations — it delegates to scripts/test_command.sh (the
    canonical script), which does the actual wiring. These tests confirm
    the delegation itself; TestCanonicalScriptWiring below confirms the
    canonical script performs the wiring test_command used to do directly."""

    def test_delegates_to_canonical_script(self, test_command_text):
        assert "scripts/test_command.sh" in test_command_text, (
            "test_command must delegate to scripts/test_command.sh — the "
            "single canonical script (FEAT-136 / DEF-002 / DEF-003) — "
            "rather than hand-duplicating its own stage list"
        )

    def test_has_no_divergent_stage_list_of_its_own(self, test_command_text):
        assert "python -m pytest" not in test_command_text, (
            "test_command must not directly invoke pytest itself — that "
            "would reintroduce the divergent stage list DEF-002/DEF-003 "
            "fixed; it must delegate to scripts/test_command.sh instead"
        )
        assert "gut_cmdln.gd" not in test_command_text, (
            "test_command must not directly invoke GUT's CLI entry point "
            "itself — it must delegate to scripts/test_command.sh instead"
        )

    def test_fails_fast_on_any_stage_failure(self, test_command_text):
        # `set -e` (or `-euo pipefail` / explicit `|| exit 1` handling) so a
        # failure in any stage stops the script with a non-zero exit code.
        assert "set -e" in test_command_text, (
            "test_command must abort (non-zero exit) if any stage fails"
        )


class TestCanonicalScriptWiring:
    """FEAT-136 / DEF-002 / DEF-003: scripts/test_command.sh (the canonical
    script that test_command now delegates to) must perform the wiring
    test_command used to do directly — pytest, `godot --gut-run-all`
    headless, and the consolidated domain suite via tests/.gutconfig.json."""

    def test_runs_pytest(self, canonical_script_text):
        assert "pytest" in canonical_script_text, (
            "scripts/test_command.sh must invoke pytest"
        )

    def test_runs_gut_run_all_headless(self, canonical_script_text):
        assert "--gut-run-all" in canonical_script_text, (
            "scripts/test_command.sh must invoke godot with --gut-run-all"
        )
        assert "--headless" in canonical_script_text, (
            "scripts/test_command.sh must invoke godot headlessly"
        )

    def test_wires_consolidated_domain_gutconfig(self, canonical_script_text):
        assert "tests/.gutconfig.json" in canonical_script_text, (
            "scripts/test_command.sh must wire in the consolidated domain "
            "GUT suite via tests/.gutconfig.json (US-014 single green gate)"
        )

    def test_fails_fast_on_any_stage_failure(self, canonical_script_text):
        assert "set -e" in canonical_script_text, (
            "scripts/test_command.sh must abort (non-zero exit) if any "
            "stage fails"
        )


# ── tests/.gutconfig.json content ────────────────────────────────────────────

class TestConsolidatedGutConfig:
    def test_is_valid_json(self, tests_gutconfig_path):
        json.loads(tests_gutconfig_path.read_text())

    def test_dirs_covers_core_domain_suites(self, tests_gutconfig):
        assert "dirs" in tests_gutconfig
        dirs = tests_gutconfig["dirs"]
        assert any("tests/unit/core" in d for d in dirs), (
            "tests/.gutconfig.json dirs must cover tests/unit/core "
            "(geometry, domain, application hex/reach suites)"
        )

    def test_include_subdirs_true(self, tests_gutconfig):
        assert tests_gutconfig.get("include_subdirs") is True, (
            "tests/.gutconfig.json must set include_subdirs: true so "
            "geometry/domain/application subdirectories are all collected"
        )

    def test_should_exit_true(self, tests_gutconfig):
        assert tests_gutconfig.get("should_exit") is True, (
            "tests/.gutconfig.json must set should_exit: true so the exit "
            "code is forwarded correctly for CI/test_command"
        )

    def test_prefix_and_suffix_match_project_convention(self, tests_gutconfig):
        assert tests_gutconfig.get("prefix") == "test_"
        assert tests_gutconfig.get("suffix") == ".gd"


# ── Actually run the consolidated domain GUT suite (real Godot binary) ──────
#
# The command exercised here is extracted directly out of test_command's own
# text (rather than hand-duplicated) so this test can never silently drift
# out of sync with what test_command actually runs. This matters because the
# project's HeadlessRunner autoload (tests/runner/headless_runner.gd), which
# intercepts a bare `--gut-run-all` flag, hardcodes loading
# res://.gutconfig.json (the FULL project suite) and ignores any -gconfig=
# argument passed alongside it -- so a stage-3 invocation of the form
# `godot -- -gconfig=res://tests/.gutconfig.json --gut-run-all` would
# silently run the full ~46-script project suite instead of the intended
# 4-script consolidated domain suite. test_command must therefore invoke the
# consolidated suite via GUT's own CLI entry point (-s addons/gut/gut_cmdln.gd
# -gconfig=...), which DOES honor -gconfig, so this stage is a genuinely
# scoped/fast gate rather than a duplicate of stage 4.
#
# FEAT-110 note: tests/unit/core/application/test_round_session.gd (US-010's
# RoundSession stepwise-API unit suite) was deliberately added alongside the
# pre-existing test_resolve_action_reach.gd in this same directory -- both
# unit-test Application-layer collaborators (ResolveActionUseCase /
# RunRoundUseCase) that happen to live under tests/unit/core/ by established
# project convention. The consolidated domain suite therefore now legitimately
# collects 5 scripts, not 4; the assertions below were updated accordingly so
# this guard still catches the ORIGINAL regression it targets (a silent
# fallback to running the whole ~46-script project suite) without falsely
# flagging the expected, intentional growth from 4 to 5 scripts.
#
# FEAT-111 note: tests/unit/core/application/test_round_session_ai_turn.gd
# (US-011's enemy-turn-automation suite -- RoundSession.advance_ai_turn()
# driven by the REAL core/combat/ai.gd, plus the presentation/
# turn_controller.gd input-disabling behavior) was added alongside
# test_round_session.gd in this same directory, by the identical established
# convention. The consolidated domain suite therefore now legitimately
# collects 6 scripts, not 5; the assertions below were updated accordingly so
# this guard still catches the ORIGINAL regression it targets without falsely
# flagging this expected, intentional growth from 5 to 6 scripts.
#
# FEAT-013 note: tests/unit/core/rules/test_movement_step.gd (US-013's Step
# movement domain-rule suite -- core/rules/movement.gd, covering the free
# 1-hex Step move, its adjacency/occupancy preconditions, and the Strike
# reach re-gate after a Step) was added under tests/unit/core/rules/ by the
# identical established convention (a core/rules|domain|application/
# collaborator's unit suite living under tests/unit/core/). The consolidated
# domain suite therefore now legitimately collects 7 scripts, not 6; the
# assertions below were updated accordingly so this guard still catches the
# ORIGINAL regression it targets without falsely flagging this expected,
# intentional growth from 6 to 7 scripts.
#
# FEAT-014 note: tests/unit/core/rules/test_movement_stride.gd (US-014's
# Stride movement domain-rule suite -- core/rules/movement.gd, covering the
# up-to-Speed multi-hex Stride move that spends one action via
# core/rules/action_economy.gd, its distance/occupancy/action-availability
# preconditions, and the Strike reach re-gate after a Stride) was added under
# tests/unit/core/rules/ by the identical established convention. The
# consolidated domain suite therefore now legitimately collects 8 scripts,
# not 7; the assertions below were updated accordingly so this guard still
# catches the ORIGINAL regression it targets without falsely flagging this
# expected, intentional growth from 7 to 8 scripts.
#
# FEAT-015 note: tests/unit/core/rules/test_flanking.gd (US-015's Flanking ->
# Off-Guard positional-condition domain-rule suite -- core/rules/flanking.gd,
# covering the opposite-adjacency detector over hex geometry that flags a
# target Off-Guard, and its negative/edge cases) was added under
# tests/unit/core/rules/ by the identical established convention. The
# consolidated domain suite therefore now legitimately collects 9 scripts,
# not 8; the assertions below were updated accordingly so this guard still
# catches the ORIGINAL regression it targets without falsely flagging this
# expected, intentional growth from 8 to 9 scripts.
#
# FEAT-140 note: tests/unit/core/application/test_resolve_action_ranged_reach.gd
# (US-007's ranged-weapon reach gating suite -- DEF-007/FR-014, covering the
# new HexMath.hex_distance()-based range_hexes reach precondition in
# core/application/resolve_action_use_case.gd, layered alongside the
# pre-existing melee adjacency precondition) was added under
# tests/unit/core/application/ by the identical established convention. The
# consolidated domain suite therefore now legitimately collects 10 scripts,
# not 9; the assertions below were updated accordingly so this guard still
# catches the ORIGINAL regression it targets without falsely flagging this
# expected, intentional growth from 9 to 10 scripts.

# FEAT-136 / DEF-002 / DEF-003: the domain-suite command is now extracted
# from scripts/test_command.sh (the canonical script), not from the
# delegating root `test_command` wrapper, since that's where the stage
# actually lives now.

def _extract_domain_suite_command(canonical_script_text: str) -> str:
    for line in canonical_script_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("godot") and "tests/.gutconfig.json" in stripped:
            return stripped
    raise AssertionError(
        "Could not find a godot invocation referencing tests/.gutconfig.json "
        "inside scripts/test_command.sh"
    )


@pytest.mark.skipif(not GODOT_AVAILABLE, reason="godot binary not on PATH")
class TestConsolidatedDomainSuiteReallyPasses:
    def _run(self, repo_root, canonical_script_text) -> subprocess.CompletedProcess:
        cmd = _extract_domain_suite_command(canonical_script_text)
        return subprocess.run(
            cmd,
            shell=True,
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=180,
        )

    def test_consolidated_domain_suite_passes(self, repo_root, canonical_script_text):
        result = self._run(repo_root, canonical_script_text)
        output = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Consolidated GUT domain suite must exit 0. Output:\n{output}"
        )

    def test_all_domain_suites_reported(self, repo_root, canonical_script_text):
        result = self._run(repo_root, canonical_script_text)
        output = result.stdout + result.stderr
        for expected in (
            "test_hex_coord",
            "test_hex_math",
            "test_combatant_hex_init",
            "test_resolve_action_reach",
            "test_round_session",
            "test_round_session_ai_turn",
            "test_movement_step",
            "test_movement_stride",
            "test_flanking",
            "test_resolve_action_ranged_reach",
        ):
            assert expected in output, (
                f"Consolidated GUT run output must mention {expected}.gd"
            )

    def test_consolidated_suite_is_scoped_not_full_project(
        self, repo_root, canonical_script_text
    ):
        """US-014's consolidated domain suite must actually be SCOPED to the
        domain/application test scripts under tests/unit/core (10, as of
        FEAT-140 -- see the module-level note above), not silently fall back
        to running the whole project's ~46 GUT scripts. This guards against
        the -gconfig-ignored regression described above."""
        result = self._run(repo_root, canonical_script_text)
        output = result.stdout + result.stderr
        match = re.search(r"Scripts\s+(\d+)", output)
        assert match, f"Could not find a 'Scripts  N' summary line. Output:\n{output}"
        scripts_run = int(match.group(1))
        assert scripts_run == 10, (
            "The consolidated domain GUT suite stage must run exactly the 10 "
            f"domain/application test scripts under tests/unit/core, but ran "
            f"{scripts_run}. This means scripts/test_command.sh's domain "
            f"suite stage is not actually scoped via tests/.gutconfig.json."
            f"\nOutput:\n{output}"
        )
        # An unrelated, non-domain test (present in the full project suite)
        # must NOT be collected by this stage.
        assert "test_longsword" not in output, (
            "Consolidated domain suite stage must not pull in unrelated "
            f"project-wide tests.\nOutput:\n{output}"
        )


# ── Full test_command end-to-end (real Godot + pytest) ──────────────────────
#
# test_command's own pytest stage re-discovers this very file, so invoking
# `bash test_command` from inside a test in this file would recurse forever
# without a guard. HYKAEN_TEST_COMMAND_E2E_GUARD marks "we are already inside
# an e2e invocation of test_command" so the nested pytest run skips this one
# test instead of shelling out to test_command again.

_E2E_GUARD_ENV_VAR = "HYKAEN_TEST_COMMAND_E2E_GUARD"


@pytest.mark.skipif(not GODOT_AVAILABLE, reason="godot binary not on PATH")
class TestFullTestCommandEndToEnd:
    def test_test_command_exits_zero(self, repo_root, test_command_path):
        if os.environ.get(_E2E_GUARD_ENV_VAR) == "1":
            pytest.skip(
                "already running inside a test_command end-to-end invocation "
                "(recursion guard) — avoids test_command's pytest stage "
                "re-invoking test_command forever"
            )

        env = dict(os.environ)
        env[_E2E_GUARD_ENV_VAR] = "1"
        result = subprocess.run(
            ["bash", str(test_command_path)],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=600,
            env=env,
        )
        assert result.returncode == 0, (
            "test_command must exit 0 when all consolidated domain tests "
            f"pass.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
