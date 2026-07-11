"""
tests/ci/test_check_sim_results_provenance.py

Pytest suite for FEAT-239 (resolves PR-004, US-009; ADR-006):
scripts/ci/check_sim_results_provenance.py — the CI provenance guard that
fails a build if sim_results.json's tracked metric keys (win_rate,
avg_rounds, total_battles, confidence_interval) changed in a commit that
did not also change a sanctioned weapon/enemy data file (a *.tres resource
under data/weapons/ or data/enemies/).

This suite builds small, disposable, real git repositories under pytest's
tmp_path (mirroring tests/ci/test_pipeline_sync.py's fixture-driven,
importlib-loaded-module convention rather than mocking git out) so the
check's actual `git diff`/`git show` plumbing is exercised end-to-end, not
just its pure-Python helper functions.

Covers (see module docstring in the script under test for full rationale):
  1. sim_results.json changed, no weapon/enemy resource file changed -> fail
     (non-zero exit / ok=False).
  2. sim_results.json changed AND a sanctioned data file changed in the same
     commit -> pass (ok=True).
  3. sim_results.json did not change at all -> pass, regardless of any other
     file changes in the commit.
  4. scripts/test_command.sh actually invokes the check as a real pipeline
     stage (not merely present on disk somewhere), and ci/pipeline.yml
     stays in sync with it (reusing scripts/check_ci_pipeline_sync.py's own
     sync-detection machinery as the wiring proof).
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT_RELATIVE_PATH = Path("scripts") / "ci" / "check_sim_results_provenance.py"
SIM_RESULTS_FILENAME = "sim_results.json"

BASELINE_SIM_RESULTS = {
    "avg_rounds": 1.081,
    "commit_hash": "0000000000000000000000000000000000000",
    "confidence_interval": 0.0269,
    "seed": 12345,
    "timestamp": "2026-01-01 00:00:00",
    "total_battles": 1000,
    "win_rate": 0.747,
}

BASELINE_WEAPON_TRES = (
    'resource_name = "arming_sword"\n'
    "damage_die = 6\n"
    "proficiency_bonus = 1\n"
)

BASELINE_SKELETON_TRES = 'resource_name = "skeleton"\nhp_max = 12\n'


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def repo_root() -> Path:
    """Absolute path to the repository root (where project.godot lives)."""
    return Path(__file__).parent.parent.parent


@pytest.fixture(scope="module")
def script_path(repo_root) -> Path:
    return repo_root / SCRIPT_RELATIVE_PATH


@pytest.fixture(scope="module")
def check_module(script_path):
    """Import scripts/ci/check_sim_results_provenance.py as a module
    without requiring scripts/ci to be a package (mirrors
    tests/ci/test_pipeline_sync.py's importlib convention for scripts/)."""
    assert script_path.is_file(), f"{SCRIPT_RELATIVE_PATH} must exist"
    spec = importlib.util.spec_from_file_location(
        "check_sim_results_provenance", script_path
    )
    module = importlib.util.module_from_spec(spec)
    # Register in sys.modules before exec: the module under test is a
    # dataclass with `from __future__ import annotations`, whose field-type
    # resolution needs to find itself via sys.modules[cls.__module__].
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _git(repo_dir: Path, *args: str) -> subprocess.CompletedProcess:
    result = subprocess.run(
        ["git", *args],
        cwd=str(repo_dir),
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"git {' '.join(args)} failed in {repo_dir}\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    return result


def _init_repo(repo_dir: Path) -> None:
    repo_dir.mkdir(parents=True, exist_ok=True)
    _git(repo_dir, "init", "-q")
    _git(repo_dir, "config", "user.email", "test@example.com")
    _git(repo_dir, "config", "user.name", "Test Runner")
    _git(repo_dir, "config", "commit.gpgsign", "false")


def _write(repo_dir: Path, relative_path: str, content: str) -> None:
    path = repo_dir / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def _commit_all(repo_dir: Path, message: str) -> str:
    _git(repo_dir, "add", "-A")
    _git(repo_dir, "commit", "-q", "-m", message)
    return _git(repo_dir, "rev-parse", "HEAD").stdout.strip()


@pytest.fixture()
def base_repo(tmp_path) -> tuple[Path, str]:
    """A fresh repo with one baseline commit: sim_results.json plus the
    two sanctioned data files this suite exercises, all at their starting
    values. Returns (repo_dir, baseline_commit_sha)."""
    repo_dir = tmp_path / "repo"
    _init_repo(repo_dir)
    _write(repo_dir, SIM_RESULTS_FILENAME, json.dumps(BASELINE_SIM_RESULTS, indent="\t"))
    _write(repo_dir, "data/weapons/arming_sword.tres", BASELINE_WEAPON_TRES)
    _write(repo_dir, "data/enemies/skeleton.tres", BASELINE_SKELETON_TRES)
    _write(repo_dir, "README.md", "baseline\n")
    baseline_sha = _commit_all(repo_dir, "baseline")
    return repo_dir, baseline_sha


# ── File existence ────────────────────────────────────────────────────────────

class TestRequiredFilesExist:
    def test_script_exists(self, script_path):
        assert script_path.is_file()

    def test_script_has_shebang(self, script_path):
        assert script_path.read_text().startswith("#!")


# ── is_sanctioned_data_file unit coverage ──────────────────────────────────

class TestIsSanctionedDataFile:
    @pytest.mark.parametrize(
        "path",
        [
            "data/enemies/skeleton.tres",
            "data/weapons/arming_sword.tres",
            "data/weapons/longsword.tres",
        ],
    )
    def test_sanctioned_paths_match(self, check_module, path):
        assert check_module.is_sanctioned_data_file(path) is True

    @pytest.mark.parametrize(
        "path",
        [
            SIM_RESULTS_FILENAME,
            "data/armor/scale_mail.tres",
            "data/enemies/enemy_resource.gd",
            "core/sim/simulator.gd",
            "data/weapons/notes.txt",
        ],
    )
    def test_non_sanctioned_paths_do_not_match(self, check_module, path):
        assert check_module.is_sanctioned_data_file(path) is False


# ── Criterion #1: metrics changed, no sanctioned data file changed -> fail ──

class TestMetricChangeWithoutCausalDataFileFails:
    def test_check_provenance_reports_violation(self, check_module, base_repo):
        repo_dir, baseline_sha = base_repo
        updated = dict(BASELINE_SIM_RESULTS)
        updated["win_rate"] = 0.900
        updated["avg_rounds"] = 1.500
        _write(repo_dir, SIM_RESULTS_FILENAME, json.dumps(updated, indent="\t"))
        bad_sha = _commit_all(repo_dir, "drift sim_results.json with no causal data change")

        result = check_module.check_provenance(repo_dir, parent=baseline_sha, commit=bad_sha)

        assert result.ok is False
        assert "VIOLATION" in result.message
        assert "win_rate" in result.message
        assert sorted(result.changed_metric_keys) == ["avg_rounds", "win_rate"]
        assert result.sanctioned_files_changed == []

    def test_cli_exits_non_zero(self, script_path, base_repo):
        repo_dir, baseline_sha = base_repo
        updated = dict(BASELINE_SIM_RESULTS)
        updated["win_rate"] = 0.900
        _write(repo_dir, SIM_RESULTS_FILENAME, json.dumps(updated, indent="\t"))
        bad_sha = _commit_all(repo_dir, "drift sim_results.json with no causal data change")

        result = subprocess.run(
            [
                sys.executable,
                str(script_path),
                "--repo",
                str(repo_dir),
                "--parent",
                baseline_sha,
                "--commit",
                bad_sha,
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode != 0
        assert "VIOLATION" in result.stdout


# ── Criterion #2: metrics changed AND sanctioned data file changed -> pass ──

class TestMetricChangeWithCausalDataFilePasses:
    def test_check_provenance_reports_ok_when_skeleton_tres_changes(
        self, check_module, base_repo
    ):
        repo_dir, baseline_sha = base_repo
        updated = dict(BASELINE_SIM_RESULTS)
        updated["win_rate"] = 0.688
        updated["avg_rounds"] = 1.068
        _write(repo_dir, SIM_RESULTS_FILENAME, json.dumps(updated, indent="\t"))
        _write(
            repo_dir,
            "data/weapons/arming_sword.tres",
            BASELINE_WEAPON_TRES.replace("proficiency_bonus = 1", "proficiency_bonus = 2"),
        )
        good_sha = _commit_all(
            repo_dir, "re-baseline sim_results.json alongside Arming Sword proficiency change"
        )

        result = check_module.check_provenance(repo_dir, parent=baseline_sha, commit=good_sha)

        assert result.ok is True
        assert "OK" in result.message
        assert result.changed_metric_keys == ["avg_rounds", "win_rate"]
        assert result.sanctioned_files_changed == ["data/weapons/arming_sword.tres"]

    def test_check_provenance_reports_ok_when_skeleton_resource_file_changes(
        self, check_module, base_repo
    ):
        repo_dir, baseline_sha = base_repo
        updated = dict(BASELINE_SIM_RESULTS)
        updated["win_rate"] = 0.5
        _write(repo_dir, SIM_RESULTS_FILENAME, json.dumps(updated, indent="\t"))
        _write(
            repo_dir,
            "data/enemies/skeleton.tres",
            BASELINE_SKELETON_TRES.replace("hp_max = 12", "hp_max = 20"),
        )
        good_sha = _commit_all(repo_dir, "skeleton.tres hp change moved win_rate")

        result = check_module.check_provenance(repo_dir, parent=baseline_sha, commit=good_sha)

        assert result.ok is True
        assert result.sanctioned_files_changed == ["data/enemies/skeleton.tres"]

    def test_cli_exits_zero(self, script_path, base_repo):
        repo_dir, baseline_sha = base_repo
        updated = dict(BASELINE_SIM_RESULTS)
        updated["win_rate"] = 0.688
        _write(repo_dir, SIM_RESULTS_FILENAME, json.dumps(updated, indent="\t"))
        _write(
            repo_dir,
            "data/weapons/arming_sword.tres",
            BASELINE_WEAPON_TRES.replace("proficiency_bonus = 1", "proficiency_bonus = 2"),
        )
        good_sha = _commit_all(repo_dir, "re-baseline with causal weapon change")

        result = subprocess.run(
            [
                sys.executable,
                str(script_path),
                "--repo",
                str(repo_dir),
                "--parent",
                baseline_sha,
                "--commit",
                good_sha,
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0
        assert "OK" in result.stdout


# ── Criterion #3: sim_results.json unchanged -> pass regardless ────────────

class TestNoSimResultsChangePassesRegardless:
    def test_other_file_changes_alone_do_not_trip_the_guard(self, check_module, base_repo):
        repo_dir, baseline_sha = base_repo
        # Change weapon/enemy data AND an unrelated file, but leave
        # sim_results.json completely untouched.
        _write(
            repo_dir,
            "data/weapons/arming_sword.tres",
            BASELINE_WEAPON_TRES.replace("proficiency_bonus = 1", "proficiency_bonus = 3"),
        )
        _write(repo_dir, "README.md", "unrelated edit\n")
        other_sha = _commit_all(repo_dir, "touch weapon data and readme only")

        result = check_module.check_provenance(repo_dir, parent=baseline_sha, commit=other_sha)

        assert result.ok is True
        assert "did not change" in result.message
        assert result.changed_metric_keys == []

    def test_provenance_only_sim_results_change_passes(self, check_module, base_repo):
        """sim_results.json IS in the diff, but only its provenance
        metadata (commit_hash/timestamp) moved -- no tracked metric key
        changed -- so this must still pass."""
        repo_dir, baseline_sha = base_repo
        updated = dict(BASELINE_SIM_RESULTS)
        updated["commit_hash"] = "1111111111111111111111111111111111111"
        updated["timestamp"] = "2026-01-02 00:00:00"
        _write(repo_dir, SIM_RESULTS_FILENAME, json.dumps(updated, indent="\t"))
        provenance_sha = _commit_all(repo_dir, "regen provenance metadata only")

        result = check_module.check_provenance(
            repo_dir, parent=baseline_sha, commit=provenance_sha
        )

        assert result.ok is True
        assert result.changed_metric_keys == []

    def test_cli_exits_zero(self, script_path, base_repo):
        repo_dir, baseline_sha = base_repo
        _write(repo_dir, "README.md", "unrelated edit\n")
        other_sha = _commit_all(repo_dir, "unrelated readme edit")

        result = subprocess.run(
            [
                sys.executable,
                str(script_path),
                "--repo",
                str(repo_dir),
                "--parent",
                baseline_sha,
                "--commit",
                other_sha,
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0


# ── No-parent / unresolvable revision edge case ─────────────────────────────

class TestUnresolvableParentIsSkippedNotFatal:
    def test_first_commit_with_no_parent_passes(self, check_module, base_repo):
        repo_dir, baseline_sha = base_repo
        result = check_module.check_provenance(
            repo_dir, parent=f"{baseline_sha}^", commit=baseline_sha
        )
        assert result.ok is True
        assert "skipped" in result.message


# ── Criterion #4: scripts/test_command.sh actually invokes the check ───────

class TestWiredIntoTestCommandPipeline:
    """Proves the check is a REAL, executed pipeline stage -- not merely a
    file that exists on disk somewhere -- by reusing
    scripts/check_ci_pipeline_sync.py's own command-extraction and
    sync-detection machinery (the project's established mechanism for
    proving a script is wired into scripts/test_command.sh)."""

    @pytest.fixture(scope="class")
    def sync_module(self, repo_root):
        sync_script_path = repo_root / "scripts" / "check_ci_pipeline_sync.py"
        spec = importlib.util.spec_from_file_location(
            "check_ci_pipeline_sync", sync_script_path
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_test_command_sh_executes_the_provenance_check(self, repo_root, sync_module):
        test_command_sh_path = repo_root / "scripts" / "test_command.sh"
        commands = sync_module.extract_test_command_sh_commands(test_command_sh_path)
        assert any(
            "scripts/ci/check_sim_results_provenance.py" in cmd for cmd in commands
        ), (
            "scripts/test_command.sh must actually invoke "
            "scripts/ci/check_sim_results_provenance.py as an executed stage "
            "(found only as a comment/reference does not count); commands found: "
            f"{commands}"
        )

    def test_ci_pipeline_yml_stays_in_sync_with_the_new_stage(self, repo_root, sync_module):
        """If scripts/test_command.sh gained a new stage command,
        ci/pipeline.yml must declare the identical command too, or the
        project's own stage-list drift gate (FEAT-158) would fail the
        build. This is the strongest available proof the wiring is real
        and consistent, not just a lone edit in one file."""
        pipeline_yml_path = repo_root / "ci" / "pipeline.yml"
        test_command_sh_path = repo_root / "scripts" / "test_command.sh"
        result = sync_module.check_sync(pipeline_yml_path, test_command_sh_path)
        assert result.in_sync, result.describe()

    def test_check_sync_script_exits_zero_against_real_repo(self, repo_root):
        result = subprocess.run(
            [sys.executable, str(repo_root / "scripts" / "check_ci_pipeline_sync.py")],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )

    def test_running_stage_against_the_real_repo_history_exits_zero(
        self, repo_root, script_path
    ):
        """End-to-end: invoking the check with its default (HEAD vs HEAD^)
        arguments against the REAL repository must exit 0 -- the actual
        committed history must never trip this guard."""
        result = subprocess.run(
            [sys.executable, str(script_path)],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
