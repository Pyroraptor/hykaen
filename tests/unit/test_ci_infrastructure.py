"""
tests/unit/test_ci_infrastructure.py

Pytest suite for FEAT-001: CI/GUT Headless Test Infrastructure Bootstrap.

Validates every test criterion from the feature spec without requiring a
running Godot binary.  All assertions are pure-Python filesystem and
content checks so they run in any environment with pytest installed.
"""

import json
import re
import subprocess
from pathlib import Path

import pytest
import yaml  # PyYAML — available in the project's Python environment

# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def repo_root() -> Path:
    """Absolute path to the repository root (where project.godot lives)."""
    return Path(__file__).parent.parent.parent


@pytest.fixture(scope="module")
def workflow_path(repo_root) -> Path:
    return repo_root / ".github" / "workflows" / "test.yml"


@pytest.fixture(scope="module")
def workflow(workflow_path) -> dict:
    with workflow_path.open() as f:
        raw = yaml.safe_load(f)
    # PyYAML parses bare `on:` as boolean True; normalise to string key.
    if True in raw and "on" not in raw:
        raw["on"] = raw.pop(True)
    return raw


@pytest.fixture(scope="module")
def placeholder_gd(repo_root) -> str:
    return (repo_root / "tests" / "unit" / "test_placeholder.gd").read_text()


@pytest.fixture(scope="module")
def project_godot(repo_root) -> str:
    return (repo_root / "project.godot").read_text()


@pytest.fixture(scope="module")
def gutconfig(repo_root) -> dict:
    return json.loads((repo_root / ".gutconfig.json").read_text())


# ── File existence ────────────────────────────────────────────────────────────

class TestRequiredFilesExist:
    def test_github_workflow_exists(self, repo_root):
        assert (repo_root / ".github" / "workflows" / "test.yml").is_file()

    def test_gut_plugin_cfg_exists(self, repo_root):
        assert (repo_root / "addons" / "gut" / "plugin.cfg").is_file(), (
            "GUT plugin not installed under addons/gut/plugin.cfg"
        )

    def test_gut_plugin_main_script_exists(self, repo_root):
        assert (repo_root / "addons" / "gut" / "gut_plugin.gd").is_file()

    def test_tests_unit_directory_exists(self, repo_root):
        assert (repo_root / "tests" / "unit").is_dir()

    def test_tests_integration_directory_exists(self, repo_root):
        assert (repo_root / "tests" / "integration").is_dir()

    def test_tests_sim_directory_exists(self, repo_root):
        assert (repo_root / "tests" / "sim").is_dir()

    def test_placeholder_test_exists(self, repo_root):
        assert (repo_root / "tests" / "unit" / "test_placeholder.gd").is_file()

    def test_project_godot_exists(self, repo_root):
        assert (repo_root / "project.godot").is_file()

    def test_gutconfig_json_exists(self, repo_root):
        assert (repo_root / ".gutconfig.json").is_file()

    def test_headless_runner_exists(self, repo_root):
        assert (repo_root / "tests" / "runner" / "headless_runner.gd").is_file()


# ── Placeholder test content ──────────────────────────────────────────────────

class TestPlaceholderTestContent:
    def test_extends_gut_test(self, placeholder_gd):
        assert "extends GutTest" in placeholder_gd, (
            "test_placeholder.gd must extend GutTest"
        )

    def test_contains_assert_eq_1_1(self, placeholder_gd):
        assert "assert_eq(1, 1" in placeholder_gd, (
            "test_placeholder.gd must call assert_eq(1, 1, 'placeholder')"
        )

    def test_contains_placeholder_message(self, placeholder_gd):
        assert "placeholder" in placeholder_gd, (
            "assert_eq must include the message string 'placeholder'"
        )

    def test_has_test_function(self, placeholder_gd):
        assert "func test_" in placeholder_gd, (
            "test_placeholder.gd must define at least one func test_*"
        )


# ── CI workflow triggers ──────────────────────────────────────────────────────

class TestWorkflowTriggers:
    def test_workflow_triggers_on_pull_request(self, workflow):
        triggers = workflow.get("on", {})
        assert "pull_request" in triggers, (
            "CI workflow must trigger on pull_request events"
        )

    def test_pull_request_targets_main(self, workflow):
        pr_config = workflow["on"].get("pull_request", {}) or {}
        branches = pr_config.get("branches", []) if pr_config else []
        assert "main" in branches, (
            "pull_request trigger must target the main branch"
        )

    def test_workflow_triggers_on_push_to_main(self, workflow):
        push_config = workflow["on"].get("push", {}) or {}
        branches = push_config.get("branches", []) if push_config else []
        assert "main" in branches, (
            "CI workflow must also trigger on push to main"
        )


# ── Workflow linter steps ─────────────────────────────────────────────────────

class TestWorkflowLinterSteps:
    def _get_all_step_run_blocks(self, workflow) -> str:
        """Concatenate all 'run' blocks from all steps for content search."""
        steps = workflow.get("jobs", {}).get("test", {}).get("steps", [])
        return "\n".join(
            step.get("run", "") for step in steps if isinstance(step, dict)
        )

    def test_linter_1_domain_purity_adr001(self, workflow):
        run_text = self._get_all_step_run_blocks(workflow)
        assert "extends Node" in run_text, (
            "CI must have a linter checking for 'extends Node' violations in core/"
        )
        assert "core/" in run_text, (
            "ADR-001 linter must target the core/ directory"
        )

    def test_linter_2_binary_resources_adr009(self, workflow):
        run_text = self._get_all_step_run_blocks(workflow)
        assert ".scn" in run_text or ".res" in run_text, (
            "CI must check for binary .scn/.res files (ADR-009)"
        )

    def test_linter_3_injected_rng_adr002(self, workflow):
        run_text = self._get_all_step_run_blocks(workflow)
        assert "randf" in run_text or "randi" in run_text, (
            "CI must have a linter for direct RNG usage (ADR-002)"
        )
        assert "rng.gd" in run_text, (
            "ADR-002 linter must exclude rng.gd"
        )

    def test_gut_run_step_present(self, workflow):
        run_text = self._get_all_step_run_blocks(workflow)
        assert "--gut-run-all" in run_text, (
            "CI must run 'godot --headless -- --gut-run-all'"
        )

    def test_gut_run_is_headless(self, workflow):
        run_text = self._get_all_step_run_blocks(workflow)
        assert "--headless" in run_text, (
            "Godot must be invoked with --headless in CI"
        )


# ── Artifact upload ───────────────────────────────────────────────────────────

class TestArtifactUpload:
    def _get_steps(self, workflow) -> list:
        return workflow.get("jobs", {}).get("test", {}).get("steps", [])

    def test_upload_artifact_step_exists(self, workflow):
        steps = self._get_steps(workflow)
        uses_values = [
            s.get("uses", "") for s in steps if isinstance(s, dict)
        ]
        assert any("upload-artifact" in u for u in uses_values), (
            "CI must have an upload-artifact step for GUT output"
        )

    def test_artifact_upload_runs_always(self, workflow):
        steps = self._get_steps(workflow)
        upload_steps = [
            s for s in steps
            if isinstance(s, dict) and "upload-artifact" in s.get("uses", "")
        ]
        assert upload_steps, "No upload-artifact step found"
        assert any(
            s.get("if", "").strip() == "always()" for s in upload_steps
        ), "Artifact upload step must have 'if: always()' to run on pass AND fail"

    def test_artifact_includes_log_files(self, workflow):
        steps = self._get_steps(workflow)
        upload_steps = [
            s for s in steps
            if isinstance(s, dict) and "upload-artifact" in s.get("uses", "")
        ]
        assert upload_steps
        # Check that .log is referenced in the with.path of the upload step
        for step in upload_steps:
            path_val = step.get("with", {}).get("path", "")
            if ".log" in str(path_val):
                return
        pytest.fail("Artifact upload must include *.log files in its path")


# ── project.godot GUT plugin configuration ───────────────────────────────────

class TestProjectGodot:
    def test_gut_plugin_enabled(self, project_godot):
        assert "gut/plugin.cfg" in project_godot, (
            "project.godot must enable the GUT plugin under [editor_plugins]"
        )

    def test_headless_runner_autoload_registered(self, project_godot):
        assert "headless_runner" in project_godot.lower(), (
            "project.godot must register headless_runner.gd as an autoload"
        )

    def test_config_version_5(self, project_godot):
        assert "config_version=5" in project_godot, (
            "project.godot must be Godot 4 format (config_version=5)"
        )

    def test_main_scene_configured(self, project_godot):
        assert "run/main_scene" in project_godot, (
            "project.godot must set a main scene so --headless starts cleanly"
        )


# ── .gutconfig.json ───────────────────────────────────────────────────────────

class TestGutConfig:
    def test_dirs_includes_tests(self, gutconfig):
        assert "dirs" in gutconfig
        assert any("tests" in d for d in gutconfig["dirs"]), (
            ".gutconfig.json dirs must point at res://tests"
        )

    def test_include_subdirs_true(self, gutconfig):
        assert gutconfig.get("include_subdirs") is True, (
            ".gutconfig.json must set include_subdirs: true"
        )

    def test_should_exit_true(self, gutconfig):
        assert gutconfig.get("should_exit") is True, (
            ".gutconfig.json must set should_exit: true for CI exit-code forwarding"
        )

    def test_prefix_is_test_underscore(self, gutconfig):
        assert gutconfig.get("prefix") == "test_", (
            ".gutconfig.json prefix must be 'test_'"
        )


# ── Linter dry-runs (no violations in the current repo) ──────────────────────

class TestLinterDryRuns:
    def test_linter1_no_node_inheritance_in_core(self, repo_root):
        """ADR-001: core/ must contain no 'extends Node/Control/CanvasItem'."""
        core_dir = repo_root / "core"
        if not core_dir.exists():
            pytest.skip("core/ directory does not exist yet")
        pattern = re.compile(
            r"\bextends\s+(Node|Control|CanvasItem)\b"
        )
        violations = []
        for gd_file in core_dir.rglob("*.gd"):
            text = gd_file.read_text()
            for lineno, line in enumerate(text.splitlines(), 1):
                if pattern.search(line):
                    violations.append(f"{gd_file.relative_to(repo_root)}:{lineno}: {line.strip()}")
        assert not violations, (
            "ADR-001 violation — Godot Node inheritance found in core/:\n"
            + "\n".join(violations)
        )

    def test_linter2_no_binary_resources_outside_addons(self, repo_root):
        """ADR-009: no .scn/.res files outside addons/."""
        violations = []
        for ext in ("*.scn", "*.res"):
            for p in repo_root.rglob(ext):
                if "addons" not in p.parts and ".git" not in p.parts:
                    violations.append(str(p.relative_to(repo_root)))
        assert not violations, (
            "ADR-009 violation — binary resource files found outside addons/:\n"
            + "\n".join(violations)
        )

    def test_linter3_no_direct_rng_in_core(self, repo_root):
        """ADR-002: no randf/randi/RandomNumberGenerator.new() in core/ (excluding rng.gd)."""
        core_dir = repo_root / "core"
        if not core_dir.exists():
            pytest.skip("core/ directory does not exist yet")
        pattern = re.compile(
            r"\b(randf|randi)\b|RandomNumberGenerator\.new\(\)"
        )
        violations = []
        for gd_file in core_dir.rglob("*.gd"):
            if gd_file.name == "rng.gd":
                continue
            text = gd_file.read_text()
            for lineno, line in enumerate(text.splitlines(), 1):
                if pattern.search(line):
                    violations.append(f"{gd_file.relative_to(repo_root)}:{lineno}: {line.strip()}")
        assert not violations, (
            "ADR-002 violation — direct RNG usage in core/ (excluding rng.gd):\n"
            + "\n".join(violations)
        )
