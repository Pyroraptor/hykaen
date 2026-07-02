"""
tests/unit/test_ci_gut_domain_consolidation_feat004.py

Pytest suite for FEAT-004: GUT domain-suite consolidation and CI wiring
(US-014).

Verifies:
  1. A `test_command` script exists at the repo root, is executable, and
     wires together `pytest` and `godot --gut-run-all` (headless) as the
     project's single automated test gate.
  2. `test_command` explicitly runs the consolidated domain suite via
     `tests/.gutconfig.json` — the single green gate for the new hex
     distance/adjacency + melee reach gating domain logic (US-001/US-002/
     US-003) — as well as the full project-wide GUT suite for regression
     safety.
  3. `tests/.gutconfig.json` is valid JSON and is configured to collect
     exactly the domain/application suites under tests/unit/core
     (test_hex_coord.gd, test_hex_math.gd, test_combatant_hex_init.gd,
     test_resolve_action_reach.gd, test_round_session.gd [FEAT-110]), with
     should_exit true so the exit code is forwarded correctly in CI/headless
     runs.
  4. Actually running `godot --headless -- -gconfig=res://tests/.gutconfig.json
     --gut-run-all` (skipped if no `godot` binary is on PATH) passes and
     reports all five consolidated domain test files.
  5. Running the full `test_command` script end-to-end (skipped if no
     `godot` binary is on PATH) exits 0.

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
    def test_runs_pytest(self, test_command_text):
        assert "pytest" in test_command_text, (
            "test_command must invoke pytest"
        )

    def test_runs_gut_run_all_headless(self, test_command_text):
        assert "--gut-run-all" in test_command_text, (
            "test_command must invoke godot with --gut-run-all"
        )
        assert "--headless" in test_command_text, (
            "test_command must invoke godot headlessly"
        )

    def test_wires_consolidated_domain_gutconfig(self, test_command_text):
        assert "tests/.gutconfig.json" in test_command_text, (
            "test_command must wire in the consolidated domain GUT suite "
            "via tests/.gutconfig.json (US-014 single green gate)"
        )

    def test_fails_fast_on_any_stage_failure(self, test_command_text):
        # `set -e` (or `-euo pipefail` / explicit `|| exit 1` handling) so a
        # failure in any stage stops the script with a non-zero exit code.
        assert "set -e" in test_command_text, (
            "test_command must abort (non-zero exit) if any stage fails"
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

def _extract_domain_suite_command(test_command_text: str) -> str:
    for line in test_command_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("godot") and "tests/.gutconfig.json" in stripped:
            return stripped
    raise AssertionError(
        "Could not find a godot invocation referencing tests/.gutconfig.json "
        "inside test_command"
    )


@pytest.mark.skipif(not GODOT_AVAILABLE, reason="godot binary not on PATH")
class TestConsolidatedDomainSuiteReallyPasses:
    def _run(self, repo_root, test_command_text) -> subprocess.CompletedProcess:
        cmd = _extract_domain_suite_command(test_command_text)
        return subprocess.run(
            cmd,
            shell=True,
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=180,
        )

    def test_consolidated_domain_suite_passes(self, repo_root, test_command_text):
        result = self._run(repo_root, test_command_text)
        output = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Consolidated GUT domain suite must exit 0. Output:\n{output}"
        )

    def test_all_domain_suites_reported(self, repo_root, test_command_text):
        result = self._run(repo_root, test_command_text)
        output = result.stdout + result.stderr
        for expected in (
            "test_hex_coord",
            "test_hex_math",
            "test_combatant_hex_init",
            "test_resolve_action_reach",
            "test_round_session",
        ):
            assert expected in output, (
                f"Consolidated GUT run output must mention {expected}.gd"
            )

    def test_consolidated_suite_is_scoped_not_full_project(
        self, repo_root, test_command_text
    ):
        """US-014's consolidated domain suite must actually be SCOPED to the
        domain/application test scripts under tests/unit/core (5, as of
        FEAT-110 -- see the module-level note above), not silently fall back
        to running the whole project's ~46 GUT scripts. This guards against
        the -gconfig-ignored regression described above."""
        result = self._run(repo_root, test_command_text)
        output = result.stdout + result.stderr
        match = re.search(r"Scripts\s+(\d+)", output)
        assert match, f"Could not find a 'Scripts  N' summary line. Output:\n{output}"
        scripts_run = int(match.group(1))
        assert scripts_run == 5, (
            "The consolidated domain GUT suite stage must run exactly the 5 "
            f"domain/application test scripts under tests/unit/core, but ran "
            f"{scripts_run}. This means test_command's stage 3 is not "
            f"actually scoped via tests/.gutconfig.json.\nOutput:\n{output}"
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
