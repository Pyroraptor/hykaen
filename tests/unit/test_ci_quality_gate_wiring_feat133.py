"""
tests/unit/test_ci_quality_gate_wiring_feat133.py

Pytest suite for FEAT-133: CI quality-gate wiring and headless regression
config (US-011 / NFR-004 / NFR-006 / NFR-008 / NFR-009).

Realizes the code/configuration portion of US-011: wires the headless
smoke test (FEAT-001, tests/gut/test_smoke_boot.gd) into the CI
test_command (pytest + `godot --gut-run-all`) and ensures the
core/sim/simulator.gd N=1000 regression run (tests/sim/test_balance_sim.gd)
is invoked as part of the SAME automated pipeline, so the full steel
thread and the existing suite are gated together in one invocation.

This feature introduces two new files (per the feature spec's
files_to_modify, neither of which previously existed in the repo):

  - scripts/test_command.sh — a single, canonical CI entry-point script
    that runs, in order: the FEAT-001 headless smoke test, the full
    pytest suite, the full GUT project suite (--gut-run-all, which
    itself includes test_smoke_boot.gd), and an explicit, separately
    labeled core/sim/simulator.gd N=1000 balance regression gate
    (tests/sim/test_balance_sim.gd). `set -euo pipefail` makes the
    script abort with a non-zero exit code the instant any stage fails.

  - ci/pipeline.yml — a pipeline manifest that documents/declares this
    project's CI gate stages, confirming the headless smoke test stage
    is REQUIRED (non-optional, no allow-failure escape hatch) and that
    scripts/test_command.sh is the pipeline's test_command entry point.

All assertions that don't require a running Godot binary are pure-Python
filesystem/YAML checks so they run in any environment with pytest
installed. Assertions that do shell out to a real `godot` binary are
skipped when no `godot` executable is on PATH.
"""

import os
import shutil
import stat
import subprocess
from pathlib import Path

import pytest
import yaml  # PyYAML — already a project dependency (see test_ci_infrastructure.py)


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def repo_root() -> Path:
    """Absolute path to the repository root (where project.godot lives)."""
    return Path(__file__).parent.parent.parent


@pytest.fixture(scope="module")
def test_command_sh_path(repo_root) -> Path:
    return repo_root / "scripts" / "test_command.sh"


@pytest.fixture(scope="module")
def test_command_sh_text(test_command_sh_path) -> str:
    assert test_command_sh_path.is_file(), (
        "scripts/test_command.sh must exist at the repo root"
    )
    return test_command_sh_path.read_text()


@pytest.fixture(scope="module")
def pipeline_yml_path(repo_root) -> Path:
    return repo_root / "ci" / "pipeline.yml"


@pytest.fixture(scope="module")
def pipeline_yml_text(pipeline_yml_path) -> str:
    assert pipeline_yml_path.is_file(), "ci/pipeline.yml must exist"
    return pipeline_yml_path.read_text()


@pytest.fixture(scope="module")
def pipeline(pipeline_yml_text) -> dict:
    return yaml.safe_load(pipeline_yml_text)


GODOT_AVAILABLE = shutil.which("godot") is not None


# ── scripts/test_command.sh: exists, executable, well-formed ────────────────

class TestTestCommandShFileExists:
    def test_exists(self, test_command_sh_path):
        assert test_command_sh_path.is_file()

    def test_is_executable(self, test_command_sh_path):
        mode = test_command_sh_path.stat().st_mode
        assert mode & stat.S_IXUSR, "scripts/test_command.sh must be executable (chmod +x)"

    def test_has_shebang(self, test_command_sh_text):
        assert test_command_sh_text.startswith("#!"), (
            "scripts/test_command.sh must start with a shebang line"
        )

    def test_fails_fast_on_any_stage_failure(self, test_command_sh_text):
        assert "set -e" in test_command_sh_text, (
            "scripts/test_command.sh must abort (non-zero exit) if any stage fails"
        )


# ── scripts/test_command.sh: wires pytest + headless smoke + GUT + N=1000 sim ─

class TestTestCommandShWiring:
    def test_runs_pytest(self, test_command_sh_text):
        assert "pytest" in test_command_sh_text, (
            "scripts/test_command.sh must invoke pytest"
        )

    def test_runs_gut_run_all_headless(self, test_command_sh_text):
        assert "--gut-run-all" in test_command_sh_text, (
            "scripts/test_command.sh must invoke godot with --gut-run-all"
        )
        assert "--headless" in test_command_sh_text, (
            "scripts/test_command.sh must invoke godot headlessly"
        )

    def test_wires_headless_smoke_test(self, test_command_sh_text):
        assert "test_smoke_boot" in test_command_sh_text, (
            "scripts/test_command.sh must explicitly wire in the FEAT-001 "
            "headless smoke test (tests/gut/test_smoke_boot.gd)"
        )

    def test_wires_n1000_balance_regression(self, test_command_sh_text):
        assert "test_balance_sim" in test_command_sh_text, (
            "scripts/test_command.sh must explicitly wire in the "
            "core/sim/simulator.gd N=1000 regression (tests/sim/test_balance_sim.gd)"
        )

    def test_smoke_test_stage_runs_before_full_gut_suite(self, test_command_sh_text):
        smoke_idx = test_command_sh_text.index("test_smoke_boot")
        gut_all_idx = test_command_sh_text.index("--gut-run-all")
        assert smoke_idx < gut_all_idx, (
            "The headless smoke test must run as an early, fast gate BEFORE "
            "the full GUT suite in scripts/test_command.sh"
        )


# ── ci/pipeline.yml: exists, valid YAML, required gate stages ───────────────

class TestPipelineYmlFileExists:
    def test_exists(self, pipeline_yml_path):
        assert pipeline_yml_path.is_file()

    def test_is_valid_yaml(self, pipeline_yml_text):
        loaded = yaml.safe_load(pipeline_yml_text)
        assert isinstance(loaded, dict)


class TestPipelineTestCommandEntryPoint:
    def test_declares_test_command(self, pipeline):
        assert pipeline.get("test_command") == "scripts/test_command.sh", (
            "ci/pipeline.yml must declare scripts/test_command.sh as the "
            "pipeline's test_command entry point"
        )


class TestPipelineStages:
    def _stages(self, pipeline) -> list:
        stages = pipeline.get("stages")
        assert isinstance(stages, list) and stages, (
            "ci/pipeline.yml must declare a non-empty 'stages' list"
        )
        return stages

    def _find_stage(self, stages, needle: str) -> dict:
        for stage in stages:
            haystack = " ".join(
                str(stage.get(k, "")) for k in ("id", "name", "command")
            )
            if needle in haystack:
                return stage
        pytest.fail(f"No pipeline stage found referencing {needle!r}")

    def test_headless_smoke_test_stage_present(self, pipeline):
        stages = self._stages(pipeline)
        stage = self._find_stage(stages, "test_smoke_boot")
        assert stage is not None

    def test_headless_smoke_test_stage_is_required_non_optional(self, pipeline):
        """Confirms the headless smoke test is a required (non-optional) gate
        step — test_criteria #2 for FEAT-133."""
        stages = self._stages(pipeline)
        stage = self._find_stage(stages, "test_smoke_boot")
        assert stage.get("required") is True, (
            "The headless smoke test pipeline stage must set required: true"
        )
        assert stage.get("optional") is False, (
            "The headless smoke test pipeline stage must set optional: false"
        )
        assert stage.get("allow_failure") is False, (
            "The headless smoke test pipeline stage must not allow failure "
            "(allow_failure: false) — it is a required gate, not advisory"
        )

    def test_pytest_stage_present_and_required(self, pipeline):
        stages = self._stages(pipeline)
        stage = self._find_stage(stages, "pytest")
        assert stage.get("required") is True

    def test_gut_full_suite_stage_present_and_required(self, pipeline):
        stages = self._stages(pipeline)
        stage = self._find_stage(stages, "--gut-run-all")
        assert stage.get("required") is True

    def test_balance_simulation_n1000_stage_present_and_required(self, pipeline):
        stages = self._stages(pipeline)
        stage = self._find_stage(stages, "test_balance_sim")
        assert stage.get("required") is True
        assert stage.get("allow_failure") is False

    def test_no_stage_allows_failure(self, pipeline):
        """Every declared gate stage in the steel-thread pipeline must be a
        real, non-optional gate — none may silently allow_failure: true."""
        stages = self._stages(pipeline)
        for stage in stages:
            assert stage.get("allow_failure", False) is False, (
                f"Pipeline stage {stage.get('id')!r} must not set "
                "allow_failure: true"
            )


class TestPipelineGateSemantics:
    def test_fail_fast_declared(self, pipeline):
        gate = pipeline.get("gate", {})
        assert gate.get("exit_non_zero_on_any_stage_failure") is True, (
            "ci/pipeline.yml must declare that the pipeline exits non-zero "
            "on any stage failure"
        )


# ── Actually run scripts/test_command.sh end-to-end (real Godot + pytest) ───
#
# scripts/test_command.sh's own pytest stage re-discovers this very file, so
# invoking it from inside a test in this file would recurse forever without a
# guard, mirroring the recursion guard used for the root `test_command`
# script in tests/unit/test_ci_gut_domain_consolidation_feat004.py.

_E2E_GUARD_ENV_VAR = "HYKAEN_TEST_COMMAND_SH_E2E_GUARD"


@pytest.mark.skipif(not GODOT_AVAILABLE, reason="godot binary not on PATH")
class TestFullTestCommandShEndToEnd:
    def test_test_command_sh_exits_zero(self, repo_root, test_command_sh_path):
        if os.environ.get(_E2E_GUARD_ENV_VAR) == "1":
            pytest.skip(
                "already running inside a scripts/test_command.sh "
                "end-to-end invocation (recursion guard)"
            )

        env = dict(os.environ)
        env[_E2E_GUARD_ENV_VAR] = "1"
        result = subprocess.run(
            ["bash", str(test_command_sh_path)],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=600,
            env=env,
        )
        assert result.returncode == 0, (
            "scripts/test_command.sh must exit 0 when all stages pass.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )

    def test_output_mentions_smoke_and_balance_stages(
        self, repo_root, test_command_sh_path
    ):
        if os.environ.get(_E2E_GUARD_ENV_VAR) == "1":
            pytest.skip(
                "already running inside a scripts/test_command.sh "
                "end-to-end invocation (recursion guard)"
            )

        env = dict(os.environ)
        env[_E2E_GUARD_ENV_VAR] = "1"
        result = subprocess.run(
            ["bash", str(test_command_sh_path)],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=600,
            env=env,
        )
        output = result.stdout + result.stderr
        assert "test_smoke_boot" in output
        assert "test_balance_sim" in output
