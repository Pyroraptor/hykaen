"""
tests/ci/test_pipeline_sync.py

Pytest suite for FEAT-158 (resolves FIND-151, US-011): CI pipeline
stage-list consistency check.

ci/pipeline.yml's per-stage `command:` entries are documentation-only —
they describe the same stage list scripts/test_command.sh actually
executes, but nothing previously enforced that the two stayed in sync.
This suite exercises scripts/check_ci_pipeline_sync.py, the drift-detection
mechanism introduced to close that gap:

  1. Against the REAL, currently-committed ci/pipeline.yml and
     scripts/test_command.sh, the check must report the two stage lists
     as in sync (proves the check doesn't cry wolf against the actual
     repository state).

  2. Against a pair of FIXTURE files where one stage's command has been
     deliberately changed (a divergent stage list), the check must detect
     and report the mismatch (proves the check actually catches drift,
     not just that it always passes).

  3. Running scripts/check_ci_pipeline_sync.py directly as a subprocess
     against the real repository must exit 0 (test_criteria #3).

The module under test lives at scripts/check_ci_pipeline_sync.py.
scripts/ is not a Python package (no __init__.py, consistent with the
rest of this project's scripts/ directory), so it's loaded here via
importlib, the same way one would load any standalone script module.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def repo_root() -> Path:
    """Absolute path to the repository root (where project.godot lives)."""
    return Path(__file__).parent.parent.parent


@pytest.fixture(scope="module")
def script_path(repo_root) -> Path:
    return repo_root / "scripts" / "check_ci_pipeline_sync.py"


@pytest.fixture(scope="module")
def pipeline_yml_path(repo_root) -> Path:
    return repo_root / "ci" / "pipeline.yml"


@pytest.fixture(scope="module")
def test_command_sh_path(repo_root) -> Path:
    return repo_root / "scripts" / "test_command.sh"


@pytest.fixture(scope="module")
def sync_module(script_path):
    """Import scripts/check_ci_pipeline_sync.py as a module without
    requiring scripts/ to be a package."""
    assert script_path.is_file(), (
        "scripts/check_ci_pipeline_sync.py must exist"
    )
    spec = importlib.util.spec_from_file_location(
        "check_ci_pipeline_sync", script_path
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ── File existence ────────────────────────────────────────────────────────────

class TestRequiredFilesExist:
    def test_script_exists(self, script_path):
        assert script_path.is_file()

    def test_script_has_shebang(self, script_path):
        assert script_path.read_text().startswith("#!"), (
            "scripts/check_ci_pipeline_sync.py must start with a shebang line"
        )


# ── Criterion #1: passes against the current committed repository state ────

class TestChecksRealRepositoryState:
    def test_check_sync_reports_in_sync(
        self, sync_module, pipeline_yml_path, test_command_sh_path
    ):
        result = sync_module.check_sync(pipeline_yml_path, test_command_sh_path)
        assert result.in_sync, (
            "ci/pipeline.yml and scripts/test_command.sh stage lists must "
            f"match in the current committed repository state:\n{result.describe()}"
        )
        assert not result.pipeline_only
        assert not result.script_only

    def test_extracts_multiple_stage_commands(
        self, sync_module, pipeline_yml_path, test_command_sh_path
    ):
        """Sanity check: the extractors must find the real stage commands,
        not silently return empty lists (which would make in_sync
        trivially/vacuously true)."""
        pipeline_commands = sync_module.extract_pipeline_commands(pipeline_yml_path)
        script_commands = sync_module.extract_test_command_sh_commands(
            test_command_sh_path
        )
        assert len(pipeline_commands) >= 3
        assert len(script_commands) >= 3
        # A known real stage command must appear in both lists.
        assert any("pytest" in cmd for cmd in pipeline_commands)
        assert any("pytest" in cmd for cmd in script_commands)


# ── Criterion #3: running the script directly exits 0 ───────────────────────

class TestScriptExitsZeroAgainstRealRepo:
    def test_check_script_exits_zero(self, repo_root, script_path):
        result = subprocess.run(
            [sys.executable, str(script_path)],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            "scripts/check_ci_pipeline_sync.py must exit 0 against the "
            f"current repository state.\nSTDOUT:\n{result.stdout}\n"
            f"STDERR:\n{result.stderr}"
        )
        assert "in sync" in result.stdout.lower()

    def test_check_script_accepts_explicit_paths(
        self, repo_root, script_path, pipeline_yml_path, test_command_sh_path
    ):
        result = subprocess.run(
            [
                sys.executable,
                str(script_path),
                "--pipeline",
                str(pipeline_yml_path),
                "--test-command",
                str(test_command_sh_path),
            ],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0


# ── Criterion #2: fixture-injected divergent stage list is DETECTED ────────

DIVERGENT_PIPELINE_YML = textwrap.dedent(
    """\
    name: fixture-quality-gate
    test_command: scripts/test_command.sh
    stages:
      - id: headless_smoke_test
        name: Headless smoke test
        command: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gselect=test_smoke_boot.gd -gexit
        required: true
      - id: pytest_suite
        name: Python pytest suite
        command: python -m pytest -q --tb=short
        required: true
      - id: mystery_stage_only_in_pipeline_yml
        name: A stage declared only in the fixture pipeline manifest
        command: echo "this command does not exist in test_command.sh"
        required: true
    """
)

DIVERGENT_TEST_COMMAND_SH = textwrap.dedent(
    """\
    #!/usr/bin/env bash
    set -euo pipefail

    cd "$(dirname "${BASH_SOURCE[0]}")/.."

    echo "=== [1/2] headless smoke test ==="
    godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gselect=test_smoke_boot.gd -gexit

    echo "=== [2/2] pytest suite ==="
    python -m pytest -q --tb=short
    """
)

MATCHING_PIPELINE_YML = textwrap.dedent(
    """\
    name: fixture-quality-gate
    test_command: scripts/test_command.sh
    stages:
      - id: headless_smoke_test
        name: Headless smoke test
        command: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gselect=test_smoke_boot.gd -gexit
        required: true
      - id: pytest_suite
        name: Python pytest suite
        command: python -m pytest -q --tb=short
        required: true
    """
)


class TestDetectsDivergentFixtureStageList:
    """Proves the check actually detects drift (test_criteria #2), rather
    than trivially reporting everything as in sync."""

    def _write_fixture(self, tmp_path: Path, name: str, content: str) -> Path:
        path = tmp_path / name
        path.write_text(content)
        return path

    def test_matching_fixtures_are_in_sync(self, sync_module, tmp_path):
        """Control case: two fixture files whose stage lists genuinely
        match must be reported in sync — proves the detection in the next
        test isn't a false positive baked into the fixtures themselves."""
        pipeline_fixture = self._write_fixture(
            tmp_path, "pipeline.yml", MATCHING_PIPELINE_YML
        )
        script_fixture = self._write_fixture(
            tmp_path, "test_command.sh", DIVERGENT_TEST_COMMAND_SH
        )
        result = sync_module.check_sync(pipeline_fixture, script_fixture)
        assert result.in_sync, result.describe()

    def test_divergent_fixtures_are_detected(self, sync_module, tmp_path):
        """Injected divergence: ci/pipeline.yml fixture declares a stage
        ('mystery_stage_only_in_pipeline_yml') that scripts/test_command.sh
        fixture never runs. The check must flag this as NOT in sync."""
        pipeline_fixture = self._write_fixture(
            tmp_path, "pipeline.yml", DIVERGENT_PIPELINE_YML
        )
        script_fixture = self._write_fixture(
            tmp_path, "test_command.sh", DIVERGENT_TEST_COMMAND_SH
        )
        result = sync_module.check_sync(pipeline_fixture, script_fixture)
        assert not result.in_sync, (
            "Expected the consistency check to detect the injected "
            "divergence between the fixture pipeline.yml and "
            "test_command.sh stage lists, but it reported them as in sync."
        )
        assert any(
            "this command does not exist in test_command.sh" in cmd
            for cmd in result.pipeline_only
        )
        assert not result.script_only

    def test_divergent_fixtures_cause_nonzero_exit(
        self, repo_root, script_path, tmp_path
    ):
        """End-to-end: running the script's CLI against divergent fixture
        paths must exit non-zero (mirrors how CI would actually catch this)."""
        pipeline_fixture = self._write_fixture(
            tmp_path, "pipeline.yml", DIVERGENT_PIPELINE_YML
        )
        script_fixture = self._write_fixture(
            tmp_path, "test_command.sh", DIVERGENT_TEST_COMMAND_SH
        )
        result = subprocess.run(
            [
                sys.executable,
                str(script_path),
                "--pipeline",
                str(pipeline_fixture),
                "--test-command",
                str(script_fixture),
            ],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode != 0, (
            "check_ci_pipeline_sync.py must exit non-zero when the two "
            f"fixture stage lists diverge.\nSTDOUT:\n{result.stdout}\n"
            f"STDERR:\n{result.stderr}"
        )
        assert "diverged" in result.stdout.lower()

    def test_missing_stages_key_raises(self, sync_module, tmp_path):
        """A malformed pipeline fixture (no 'stages' list at all) must
        raise rather than silently comparing against an empty list."""
        bad_pipeline = self._write_fixture(
            tmp_path,
            "bad_pipeline.yml",
            "name: no-stages-here\ntest_command: scripts/test_command.sh\n",
        )
        script_fixture = self._write_fixture(
            tmp_path, "test_command.sh", DIVERGENT_TEST_COMMAND_SH
        )
        with pytest.raises(ValueError):
            sync_module.check_sync(bad_pipeline, script_fixture)


# ── Order-insensitivity (documented, intentional behavior) ─────────────────

class TestOrderInsensitiveComparison:
    """scripts/test_command.sh legitimately runs its stages in a different
    order than ci/pipeline.yml declares them (see module docstring in
    check_ci_pipeline_sync.py) — the check must compare stage SETS, not
    sequences, so reordering alone is never reported as drift."""

    def test_reordered_but_identical_stage_sets_are_in_sync(
        self, sync_module, tmp_path
    ):
        pipeline_fixture = tmp_path / "pipeline.yml"
        pipeline_fixture.write_text(
            textwrap.dedent(
                """\
                name: fixture
                test_command: scripts/test_command.sh
                stages:
                  - id: a
                    command: python -m pytest -q --tb=short
                  - id: b
                    command: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gselect=test_smoke_boot.gd -gexit
                """
            )
        )
        script_fixture = tmp_path / "test_command.sh"
        script_fixture.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env bash
                set -euo pipefail
                cd "$(dirname "${BASH_SOURCE[0]}")/.."
                echo "=== stage 1 ==="
                godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gselect=test_smoke_boot.gd -gexit
                echo "=== stage 2 ==="
                python -m pytest -q --tb=short
                """
            )
        )
        result = sync_module.check_sync(pipeline_fixture, script_fixture)
        assert result.in_sync, result.describe()
