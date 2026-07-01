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
     exactly the domain suites under tests/unit/core (test_hex_coord.gd,
     test_hex_math.gd, test_combatant_hex_init.gd,
     test_resolve_action_reach.gd), with should_exit true so the exit
     code is forwarded correctly in CI/headless runs.
  4. Actually running `godot --headless -- -gconfig=res://tests/.gutconfig.json
     --gut-run-all` (skipped if no `godot` binary is on PATH) passes and
     reports all four consolidated domain test files.
  5. Running the full `test_command` script end-to-end (skipped if no
     `godot` binary is on PATH) exits 0.

All assertions that don't require a running Godot binary are pure-Python
filesystem/JSON checks so they run in any environment with pytest installed.
"""

import json
import os
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

@pytest.mark.skipif(not GODOT_AVAILABLE, reason="godot binary not on PATH")
class TestConsolidatedDomainSuiteReallyPasses:
    def _run(self, repo_root) -> subprocess.CompletedProcess:
        return subprocess.run(
            [
                "godot", "--headless", "--path", str(repo_root),
                "--", "-gconfig=res://tests/.gutconfig.json", "--gut-run-all",
            ],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=180,
        )

    def test_consolidated_domain_suite_passes(self, repo_root):
        result = self._run(repo_root)
        output = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Consolidated GUT domain suite must exit 0. Output:\n{output}"
        )

    def test_all_four_domain_suites_reported(self, repo_root):
        result = self._run(repo_root)
        output = result.stdout + result.stderr
        for expected in (
            "test_hex_coord",
            "test_hex_math",
            "test_combatant_hex_init",
            "test_resolve_action_reach",
        ):
            assert expected in output, (
                f"Consolidated GUT run output must mention {expected}.gd"
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
