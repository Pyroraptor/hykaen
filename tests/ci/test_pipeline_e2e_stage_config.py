"""
tests/ci/test_pipeline_e2e_stage_config.py

Pytest suite for FEAT-172 (resolves DEF-002, US-010/US-011): config-assertion
regression guard for the `steel_thread_prologue_encounter_e2e` CI stage's
-gselect/-gdir pairing in ci/pipeline.yml.

Prior to this feature, that stage's command was:

    godot --headless -s addons/gut/gut_cmdln.gd
    -gselect=test_steel_thread_prologue_encounter.gd
    -gdir=res://tests/integration -ginclude_subdirs -gexit

which resolves to tests/integration/test_steel_thread_prologue_encounter.gd
— NOT tests/e2e/test_full_steel_thread_e2e.gd, the FEAT-167 capstone E2E
test this dedicated, named stage is supposed to directly and exclusively
gate. As a result, the "steel thread E2E" stage never actually ran that
test on its own; it only happened to be exercised indirectly whenever the
catch-all `gut_full_suite` stage (`godot --headless -- --gut-run-all`) swept
the whole project.

This suite parses the REAL, currently-committed ci/pipeline.yml and:

  1. Asserts the `steel_thread_prologue_encounter_e2e` stage's -gselect/
     -gdir pairing resolves to an existing
     tests/e2e/test_full_steel_thread_e2e.gd path (test_criteria #1).

  2. Proves the resolution logic actually discriminates -- i.e. that it
     is capable of failing -- by re-running it against a deliberately
     mismatched FIXTURE pipeline.yml (selector/dir edited to no longer
     point at the real file) and asserting resolution then fails/produces
     a non-existent or wrong path (test_criteria #3, regression guard).

Resolution semantics mirror GUT's own gut_cmdln.gd / gut_config.gd CLI
contract: `-gdir=res://tests/e2e` is a project-relative ("res://") directory
GUT searches for test scripts, and `-gselect=<filename>` is a substring/exact
filename filter (gut.gd's `select_script`) restricting the run to scripts
whose file name matches -- so the pairing "resolves to" a real file if, and
only if, joining the res://-relative directory with the selector's filename
lands on a file that actually exists on disk.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

STAGE_ID = "steel_thread_prologue_encounter_e2e"
EXPECTED_TEST_FILE = "test_full_steel_thread_e2e.gd"
EXPECTED_RELATIVE_PATH = Path("tests") / "e2e" / EXPECTED_TEST_FILE


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def repo_root() -> Path:
    """Absolute path to the repository root (where project.godot lives)."""
    return Path(__file__).parent.parent.parent


@pytest.fixture(scope="module")
def pipeline_yml_path(repo_root) -> Path:
    return repo_root / "ci" / "pipeline.yml"


# ── Parsing helpers (module-level so both the real-repo checks and the ──────
# ── fixture-mismatch regression-guard checks below reuse identical logic) ───

def load_stage(pipeline_yml_path: Path, stage_id: str) -> dict:
    """Parse ci/pipeline.yml (or a fixture with the same shape) and return
    the stage dict whose `id` matches `stage_id`. Raises if the pipeline
    file is malformed or the stage is missing, mirroring
    scripts/check_ci_pipeline_sync.py's fail-loud-on-malformed-input
    convention rather than silently returning None."""
    loaded = yaml.safe_load(pipeline_yml_path.read_text())
    if not isinstance(loaded, dict):
        raise ValueError(f"{pipeline_yml_path}: expected a YAML mapping at the top level")

    stages = loaded.get("stages")
    if not isinstance(stages, list) or not stages:
        raise ValueError(f"{pipeline_yml_path}: must declare a non-empty 'stages' list")

    for stage in stages:
        if isinstance(stage, dict) and stage.get("id") == stage_id:
            return stage

    raise ValueError(f"{pipeline_yml_path}: no stage with id={stage_id!r} found")


def extract_gselect_gdir(command: str) -> tuple[str, str]:
    """Extract the -gselect=<value> and -gdir=<value> tokens from a GUT
    stage command string (a YAML folded '>-' block scalar, so embedded
    newlines are normalized to spaces first). Raises ValueError if either
    flag is absent, since a stage claiming to select a specific test file
    MUST declare both."""
    normalized = re.sub(r"\s+", " ", command).strip()

    select_match = re.search(r"-gselect=(\S+)", normalized)
    dir_match = re.search(r"-gdir=(\S+)", normalized)

    if not select_match:
        raise ValueError(f"command has no -gselect= flag: {normalized!r}")
    if not dir_match:
        raise ValueError(f"command has no -gdir= flag: {normalized!r}")

    return select_match.group(1), dir_match.group(1)


def resolve_selected_test_path(repo_root: Path, gselect: str, gdir: str) -> Path:
    """Resolve a (-gselect, -gdir) pairing to the on-disk file path it
    targets, mirroring GUT's own res://-relative directory convention:
    -gdir=res://tests/e2e maps to <repo_root>/tests/e2e, and -gselect
    names the file within it directly (this project's -gselect values are
    always a bare, exact test script filename, never a glob/substring, so
    direct join is the correct resolution -- consistent with every other
    stage already declared in ci/pipeline.yml)."""
    if not gdir.startswith("res://"):
        raise ValueError(f"-gdir value must be res://-relative, got {gdir!r}")

    relative_dir = gdir[len("res://"):]
    return repo_root / relative_dir / gselect


# ── Criterion #1: the real, committed ci/pipeline.yml resolves correctly ───

class TestStageSelectorResolvesToFullSteelThreadE2ETest:
    def test_stage_is_declared(self, pipeline_yml_path):
        stage = load_stage(pipeline_yml_path, STAGE_ID)
        assert stage["id"] == STAGE_ID

    def test_gselect_names_the_full_steel_thread_e2e_script(
        self, pipeline_yml_path
    ):
        stage = load_stage(pipeline_yml_path, STAGE_ID)
        gselect, _gdir = extract_gselect_gdir(stage["command"])
        assert gselect == EXPECTED_TEST_FILE, (
            f"stage {STAGE_ID!r}'s -gselect must directly name "
            f"{EXPECTED_TEST_FILE}, got {gselect!r} -- this stage must "
            "invoke the FEAT-167 capstone E2E test directly, not some "
            "other script"
        )

    def test_gdir_points_at_tests_e2e(self, pipeline_yml_path):
        stage = load_stage(pipeline_yml_path, STAGE_ID)
        _gselect, gdir = extract_gselect_gdir(stage["command"])
        assert gdir == "res://tests/e2e", (
            f"stage {STAGE_ID!r}'s -gdir must be res://tests/e2e "
            f"(where {EXPECTED_TEST_FILE} actually lives), got {gdir!r}"
        )

    def test_selector_dir_pairing_resolves_to_an_existing_file(
        self, repo_root, pipeline_yml_path
    ):
        """The core config-assertion: join -gdir + -gselect and confirm the
        resulting path is the real, existing test_full_steel_thread_e2e.gd
        file on disk (DEF-002 fix, test_criteria #1)."""
        stage = load_stage(pipeline_yml_path, STAGE_ID)
        gselect, gdir = extract_gselect_gdir(stage["command"])
        resolved = resolve_selected_test_path(repo_root, gselect, gdir)

        assert resolved.is_file(), (
            f"stage {STAGE_ID!r}'s -gselect/-gdir pairing "
            f"(-gselect={gselect!r} -gdir={gdir!r}) resolved to {resolved}, "
            "which does not exist on disk. This stage must directly target "
            f"{EXPECTED_RELATIVE_PATH}."
        )
        assert resolved == repo_root / EXPECTED_RELATIVE_PATH


# ── Criterion #3: the guard actually detects a re-introduced mismatch ──────

MISMATCHED_PIPELINE_YML_TEMPLATE = """\
name: fixture-quality-gate
stages:
  - id: steel_thread_prologue_encounter_e2e
    name: Steel thread prologue-encounter E2E test
    command: >-
      godot --headless -s addons/gut/gut_cmdln.gd
      -gselect={gselect}
      -gdir={gdir} -gexit
    required: true
"""


class TestRegressionGuardDetectsReintroducedMismatch:
    """Proves this suite would actually FAIL the build if a future edit
    re-introduces the DEF-002 bug (selector/dir pointing somewhere other
    than tests/e2e/test_full_steel_thread_e2e.gd), rather than trivially
    passing regardless of the pipeline.yml content."""

    def test_original_buggy_pairing_does_not_resolve_to_the_e2e_file(
        self, repo_root, tmp_path
    ):
        """The exact pre-fix (-gselect, -gdir) pairing this feature
        replaces must NOT resolve to tests/e2e/test_full_steel_thread_e2e.gd
        -- confirming the old configuration really was broken, and that
        this resolution logic would have caught it."""
        fixture = tmp_path / "pipeline.yml"
        fixture.write_text(
            MISMATCHED_PIPELINE_YML_TEMPLATE.format(
                gselect="test_steel_thread_prologue_encounter.gd",
                gdir="res://tests/integration",
            )
        )
        stage = load_stage(fixture, STAGE_ID)
        gselect, gdir = extract_gselect_gdir(stage["command"])
        resolved = resolve_selected_test_path(repo_root, gselect, gdir)

        assert resolved != repo_root / EXPECTED_RELATIVE_PATH, (
            "the pre-FEAT-172 selector/dir pairing must not resolve to "
            f"{EXPECTED_RELATIVE_PATH} -- it targets a different script "
            "(tests/integration/test_steel_thread_prologue_encounter.gd), "
            "proving the old pairing truly never invoked the intended "
            "capstone E2E test"
        )
        assert resolved.name != EXPECTED_TEST_FILE

    def test_selector_pointing_at_nonexistent_file_is_detected(
        self, repo_root, tmp_path
    ):
        """A hypothetical future typo (right directory, wrong/renamed
        file) must also be caught."""
        fixture = tmp_path / "pipeline.yml"
        fixture.write_text(
            MISMATCHED_PIPELINE_YML_TEMPLATE.format(
                gselect="test_full_steel_thread_e2e_TYPO.gd",
                gdir="res://tests/e2e",
            )
        )
        stage = load_stage(fixture, STAGE_ID)
        gselect, gdir = extract_gselect_gdir(stage["command"])
        resolved = resolve_selected_test_path(repo_root, gselect, gdir)

        assert not resolved.is_file()

    def test_missing_gselect_flag_raises(self, tmp_path):
        fixture = tmp_path / "pipeline.yml"
        fixture.write_text(
            "name: fixture\n"
            "stages:\n"
            "  - id: steel_thread_prologue_encounter_e2e\n"
            "    command: godot --headless -gdir=res://tests/e2e -gexit\n"
        )
        stage = load_stage(fixture, STAGE_ID)
        with pytest.raises(ValueError):
            extract_gselect_gdir(stage["command"])

    def test_missing_stage_raises(self, tmp_path):
        fixture = tmp_path / "pipeline.yml"
        fixture.write_text(
            "name: fixture\n"
            "stages:\n"
            "  - id: some_other_stage\n"
            "    command: echo hi\n"
        )
        with pytest.raises(ValueError):
            load_stage(fixture, STAGE_ID)


# ── test_criteria #2: running the corrected stage locally really works ────

class TestCorrectedStageActuallyRunsTheE2ETest:
    """End-to-end proof (test_criteria #2): invoking godot with EXACTLY the
    -gselect/-gdir pairing now declared in ci/pipeline.yml for this stage
    executes tests/e2e/test_full_steel_thread_e2e.gd specifically, and it
    passes. Skipped when the `godot` binary isn't available on PATH (e.g.
    a pure-Python CI runner stage) so this suite still collects/runs
    everywhere else."""

    def test_running_stage_command_executes_and_passes_the_e2e_test(
        self, repo_root, pipeline_yml_path
    ):
        godot_bin = _find_godot_binary()
        if godot_bin is None:
            pytest.skip("godot binary not found on PATH")

        stage = load_stage(pipeline_yml_path, STAGE_ID)
        gselect, gdir = extract_gselect_gdir(stage["command"])

        result = subprocess.run(
            [
                godot_bin,
                "--headless",
                "-s",
                "addons/gut/gut_cmdln.gd",
                f"-gselect={gselect}",
                f"-gdir={gdir}",
                "-gexit",
            ],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=180,
        )
        combined_output = result.stdout + result.stderr

        assert EXPECTED_TEST_FILE in combined_output, (
            "expected the corrected stage command to actually run "
            f"{EXPECTED_TEST_FILE}; it did not appear in the run output.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert result.returncode == 0, (
            f"corrected stage command exited {result.returncode}.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )


def _find_godot_binary() -> str | None:
    import shutil

    for candidate in ("godot", "godot4", "godot4.3", "godot-headless"):
        found = shutil.which(candidate)
        if found:
            return found
    return None
