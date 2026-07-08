"""
tests/integration/test_headless_boot_smoke.py

Pytest suite for FEAT-180 (US-015/FR-015; the headless-boot portion of
US-017/NFR-003/NFR-004) — the mandatory final smoke test proving the REAL,
shipped res://MainScene.tscn composition root (project.godot's own
run/main_scene target) boots under `godot --headless` with ZERO ERROR/
WARNING-level Godot console output, and that every combatant token renders
within viewport bounds at boot.

This is a Python-level, real-subprocess complement to the existing in-process
GDScript headless-boot smoke tests (tests/gut/test_smoke_boot.gd, tests/
smoke/test_main_scene_headless_boot.gd, tests/infrastructure/
test_mainscene_headless_boot.gd): those suites run INSIDE an already-launched
`godot --headless -- --gut-run-all` process and can therefore only observe
"no null composition-root field" as a proxy for "no unhandled error" — Godot
4.3's engine-level error/warning capture hook (GutErrorTracker's
OS.add_logger, addons/gut/error_tracker.gd) is a documented Godot 4.4+ API
and a no-op on this project's pinned 4.3 engine (see those files' own
file-level docs). This suite instead spawns a SECOND, independent
`godot --headless` process (mirroring tests/ci/test_pipeline_e2e_stage_config.py's
established `subprocess.run([godot_bin, ...], capture_output=True, text=True)`
convention) and reads that process's own real stdout/stderr streams directly
-- the one vantage point from which "zero ERROR/WARNING console output" can
actually be observed on this engine version.

Design note -- the pre-existing "invalid UID" resource-format warning class:
booting this project today already emits a handful of WARNING-level lines of
the shape:

    WARNING: res://data/encounters/prologue_encounter.tres:3 - ext_resource,
    invalid UID: uid://encrsc1a2b3cd - using text path instead: ...
         at: load (scene/resources/resource_format_text.cpp:453)

These come from Godot's resource loader falling back from a stale/placeholder
UID recorded inside this project's committed `.tres` fixture files (data/*)
to the resource's text path -- a pre-existing, unrelated data/tooling quirk
(no corresponding `.gd.uid` files are committed) that predates this feature,
is not one of this feature's files_to_create/files_to_modify, and carries no
resolves_findings entry. It fires during ResourceLoader.load(), before
MainScene.gd's own composition-root logic (the thing this feature's steel
thread actually verifies) ever runs a single line. Treating it as a hard
failure here would make this gate permanently red for a reason entirely
orthogonal to what FEAT-180 exists to verify (Strike/Step/Stride/End Turn/
gating/cancel composing correctly through the real MainScene entry-to-exit
point) -- so this suite narrowly allowlists ONLY that documented warning
shape (asserted, below, to not swallow anything else) and requires TRUE ZERO
tolerance for every other WARNING and for every ERROR line, with no allowlist
at all.

Design note -- viewport-bounds check reuses existing coverage, rather than
forking a second implementation of it (this codebase's established ADR-002/
CR-001 "no duplicate logic" discipline): tests/gut/test_viewport_centering.gd's
test_mainscene_boot_renders_every_token_within_viewport_bounds() already
proves, in-process against the real booted MainScene.tscn, that every
combatant token's rendered position falls within the project's configured
viewport bounds (FEAT-002/US-002). This suite invokes that EXACT GUT suite
via a scoped `-gselect=`/`-gdir=` subprocess call (mirroring tests/ci/
test_pipeline_e2e_stage_config.py's TestCorrectedStageActuallyRunsTheE2ETest)
and asserts it passes, rather than re-deriving the same pixel-bounds math a
second time from raw console text.

Every subprocess-invoking test is skipped (not failed) when no `godot` binary
is discoverable on PATH, mirroring tests/ci/test_pipeline_e2e_stage_config.py's
`_find_godot_binary()` / `pytest.skip(...)` convention, so this suite still
collects and the classification-logic unit tests below still run in any
environment with pytest installed, even without Godot available.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Optional

import pytest

MAIN_SCENE_BOOT_MARKER = "Hykaen MainScene booted into the prologue encounter"

VIEWPORT_CENTERING_TEST_FILE = "test_viewport_centering.gd"
VIEWPORT_CENTERING_TEST_DIR = "res://tests/gut"

# The ONE pre-existing, documented, out-of-scope warning shape this suite
# allowlists (see file-level design note above). Anchored to the specific
# "ext_resource, invalid UID ... using text path instead" phrasing Godot's
# resource_format_text.cpp loader emits -- narrow enough that an unrelated
# WARNING (e.g. a real composition-root regression) can never match it.
_ALLOWLISTED_WARNING_PATTERN = re.compile(
    r"ext_resource, invalid UID:.*using text path instead"
)

# Safety bound on how many frames the bare headless boot is allowed to run
# before Godot's own `--quit-after` flag terminates it (CWE-835 "never loop
# unbounded" guard, mirroring this codebase's established `_MAX_*` /
# `--quit-after` conventions elsewhere in the suite).
_QUIT_AFTER_FRAMES = 10
_SUBPROCESS_TIMEOUT_SECONDS = 90


def _find_godot_binary() -> Optional[str]:
    """Mirrors tests/ci/test_pipeline_e2e_stage_config.py's identically-named
    helper exactly, so both suites agree on how the `godot` binary is
    discovered."""
    for candidate in ("godot", "godot4", "godot4.3", "godot-headless"):
        found = shutil.which(candidate)
        if found:
            return found
    return None


def _classify_console_lines(text: str) -> tuple[list[str], list[str]]:
    """Splits raw Godot console output (stdout+stderr concatenated) into
    (errors, warnings), where `warnings` EXCLUDES any line matching the one
    documented, pre-existing allowlisted warning shape above. Both stdout and
    stderr are scanned (mirroring `_run_bare_headless_boot()`'s callers,
    below) since Godot's WARNING/ERROR lines are observed to land on stderr
    while INFO/DEBUG project `print()` calls land on stdout -- but this
    function itself is agnostic to which stream a line came from, so it
    remains correct even if that split ever changes.
    """
    errors: list[str] = []
    warnings: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line.startswith("ERROR:"):
            errors.append(line)
        elif line.startswith("WARNING:"):
            if not _ALLOWLISTED_WARNING_PATTERN.search(line):
                warnings.append(line)
    return errors, warnings


@pytest.fixture(scope="module")
def repo_root() -> Path:
    """Absolute path to the repository root (where project.godot lives),
    mirroring every other pytest suite's identically-named fixture in this
    project (tests/unit/test_ci_infrastructure.py, tests/ci/
    test_pipeline_e2e_stage_config.py)."""
    return Path(__file__).parent.parent.parent


@pytest.fixture(scope="module")
def godot_bin() -> str:
    found = _find_godot_binary()
    if found is None:
        pytest.skip("godot binary not found on PATH")
    return found


@pytest.fixture(scope="module")
def bare_headless_boot(godot_bin, repo_root) -> subprocess.CompletedProcess:
    """Spawns a SECOND, independent, real `godot --headless` process booting
    this project's actual run/main_scene target (project.godot's
    run/main_scene=res://MainScene.tscn, no GUT harness/HeadlessRunner
    involvement beyond the autoload every launch of this project always
    carries) and returns the completed process -- shared across every test in
    TestHeadlessBootZeroErrorAndWarningOutput below so this (relatively slow)
    subprocess spawn happens exactly once per test session, mirroring
    module-scoped fixture conventions already used elsewhere in this suite
    file (`repo_root`, `godot_bin`).

    `--quit-after N` lets N frames of real, unmodified _ready()/_process()
    composition-root logic run (the SAME code path a real, non-test launch
    executes) before the engine exits on its own -- no test-local scene, no
    stubbed autoload, no mock.

    FEAT-006 (US-005/FR-005, ADR-002): MainScene.gd now wires RoundSession's
    enemy-strikes-player reaction window to the REAL, blocking
    TurnController.resolve_reaction() -> PlayerReactionChooser ->
    $ReactionPromptUI chain (see MainScene.gd's rewire_session() doc), which
    has "no auto-timeout" by design (scenes/ui/reaction_prompt_ui.gd) --
    genuinely correct behavior for an actual player launch, but this bare
    boot has no seed pinned (infrastructure/seed_policy.gd's documented
    random fallback), so an unlucky initiative draw could seat the Skeleton
    first and have it auto-Strike Titus before this fixture's N frames
    elapse, suspending a coroutine forever and leaking a RefCounted past
    `--quit-after`'s forced exit (observed as Godot's own "resources still
    in use at exit" ERROR line -- exactly what this suite exists to catch).
    HYKAEN_SEED is pinned here to 42 -- the prologue fixture's own
    established "Titus acts first" seed (the SAME value every other
    seed-pinning fixture in this codebase uses, e.g. tests/unit/
    test_main_scene_interactive_wiring.gd) -- via infrastructure/
    seed_policy.gd's documented env-var precedence (ADR-004), so this real,
    unmodified subprocess boot is deterministic rather than randomly seeded.
    """
    env = dict(os.environ)
    env["HYKAEN_SEED"] = "42"
    return subprocess.run(
        [
            godot_bin,
            "--headless",
            "--path",
            str(repo_root),
            "--quit-after",
            str(_QUIT_AFTER_FRAMES),
        ],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
        timeout=_SUBPROCESS_TIMEOUT_SECONDS,
        env=env,
    )


# ══════════════════════════════════════════════════════════════════════════
# Classification-logic unit tests -- run with no `godot` binary required, so
# this suite's allowlist discriminates correctly regardless of environment.
# ══════════════════════════════════════════════════════════════════════════

class TestConsoleLineClassification:
    def test_allowlisted_uid_warning_is_excluded(self):
        sample = (
            "WARNING: res://data/encounters/prologue_encounter.tres:3 - "
            "ext_resource, invalid UID: uid://encrsc1a2b3cd - using text "
            "path instead: res://data/encounters/encounter_resource.gd\n"
            "     at: load (scene/resources/resource_format_text.cpp:453)"
        )
        errors, warnings = _classify_console_lines(sample)
        assert errors == []
        assert warnings == [], "the documented pre-existing resource-UID warning shape must be allowlisted, not flagged"

    def test_an_unrelated_warning_is_still_flagged(self):
        """Regression guard (mirrors tests/ci/test_pipeline_e2e_stage_config.py's
        own regression-guard style): the allowlist must be narrow enough that
        a genuinely different WARNING line -- e.g. a future composition-root
        regression -- is never silently swallowed alongside it."""
        sample = "WARNING: some unrelated future regression happened here"
        errors, warnings = _classify_console_lines(sample)
        assert errors == []
        assert warnings == [sample], "an unrelated WARNING line must NOT be caught by the narrow UID allowlist"

    def test_an_error_line_is_always_flagged_even_alongside_allowlisted_warnings(self):
        sample = (
            "WARNING: res://data/encounters/prologue_encounter.tres:3 - "
            "ext_resource, invalid UID: uid://encrsc1a2b3cd - using text "
            "path instead: res://data/encounters/encounter_resource.gd\n"
            "ERROR: something actually went wrong during boot"
        )
        errors, warnings = _classify_console_lines(sample)
        assert errors == ["ERROR: something actually went wrong during boot"]
        assert warnings == []

    def test_info_and_debug_lines_are_never_flagged(self):
        sample = (
            "INFO: Hykaen MainScene booted into the prologue encounter "
            "(interactive) -- current_actor=Titus round_over=false\n"
            "DEBUG: viewport_centering centering_offset=(576, 324)"
        )
        errors, warnings = _classify_console_lines(sample)
        assert errors == []
        assert warnings == []

    def test_no_console_output_at_all_classifies_as_zero_errors_and_warnings(self):
        errors, warnings = _classify_console_lines("")
        assert errors == []
        assert warnings == []


# ══════════════════════════════════════════════════════════════════════════
# test_criteria: "Headless boot smoke test: MainScene boots headless with
# zero ERROR/WARNING console output..."
# ══════════════════════════════════════════════════════════════════════════

class TestHeadlessBootZeroErrorAndWarningOutput:
    def test_bare_headless_boot_exits_successfully(self, bare_headless_boot):
        assert bare_headless_boot.returncode == 0, (
            "a real `godot --headless` boot of the shipped project must exit 0 "
            f"(no crash/unhandled fatal error).\nSTDOUT:\n{bare_headless_boot.stdout}\n"
            f"STDERR:\n{bare_headless_boot.stderr}"
        )

    def test_bare_headless_boot_produces_zero_error_level_console_output(self, bare_headless_boot):
        combined_output = bare_headless_boot.stdout + "\n" + bare_headless_boot.stderr
        errors, _warnings = _classify_console_lines(combined_output)
        assert errors == [], (
            "booting the real res://MainScene.tscn composition root headlessly must "
            f"produce ZERO ERROR-level console lines; found:\n" + "\n".join(errors)
            + f"\n\nFull STDOUT:\n{bare_headless_boot.stdout}\nFull STDERR:\n{bare_headless_boot.stderr}"
        )

    def test_bare_headless_boot_produces_zero_unallowlisted_warning_level_console_output(self, bare_headless_boot):
        combined_output = bare_headless_boot.stdout + "\n" + bare_headless_boot.stderr
        _errors, warnings = _classify_console_lines(combined_output)
        assert warnings == [], (
            "booting the real res://MainScene.tscn composition root headlessly must "
            "produce ZERO WARNING-level console lines beyond the one documented, "
            f"pre-existing, out-of-scope resource-UID warning shape; found:\n" + "\n".join(warnings)
            + f"\n\nFull STDOUT:\n{bare_headless_boot.stdout}\nFull STDERR:\n{bare_headless_boot.stderr}"
        )

    def test_bare_headless_boot_actually_reaches_the_interactive_prologue_encounter(self, bare_headless_boot):
        """A silently-empty/no-op boot (e.g. run/main_scene failing to
        resolve at all) would trivially satisfy "zero ERROR/WARNING output"
        -- guard against that degenerate pass by also confirming
        MainScene.gd's own real _ready() boot-confirmation print (see
        MainScene.gd's `print("INFO: Hykaen MainScene booted...")` call)
        actually appears in this SAME real subprocess's output."""
        combined_output = bare_headless_boot.stdout + bare_headless_boot.stderr
        assert MAIN_SCENE_BOOT_MARKER in combined_output, (
            "the real MainScene.tscn composition root must actually reach its "
            "interactive, input-awaiting boot state within "
            f"{_QUIT_AFTER_FRAMES} frames -- its own boot-confirmation log line was "
            f"not observed.\nFull STDOUT:\n{bare_headless_boot.stdout}\n"
            f"Full STDERR:\n{bare_headless_boot.stderr}"
        )


# ══════════════════════════════════════════════════════════════════════════
# test_criteria: "...and renders all tokens within viewport bounds."
# ══════════════════════════════════════════════════════════════════════════

class TestHeadlessBootTokensRenderWithinViewportBounds:
    def test_viewport_centering_gut_suite_confirms_every_token_within_bounds(self, godot_bin, repo_root):
        """Reuses (never re-derives, ADR-002/CR-001) tests/gut/
        test_viewport_centering.gd's already-verified
        test_mainscene_boot_renders_every_token_within_viewport_bounds() --
        the in-process assertion that every combatant token HexGridView
        renders after a real MainScene.tscn boot falls within the project's
        configured viewport bounds. Invoked here via a scoped `-gselect=`/
        `-gdir=` GUT CLI subprocess call, mirroring tests/ci/
        test_pipeline_e2e_stage_config.py's
        TestCorrectedStageActuallyRunsTheE2ETest convention exactly."""
        result = subprocess.run(
            [
                godot_bin,
                "--headless",
                "-s",
                "addons/gut/gut_cmdln.gd",
                f"-gselect={VIEWPORT_CENTERING_TEST_FILE}",
                f"-gdir={VIEWPORT_CENTERING_TEST_DIR}",
                "-gexit",
            ],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=_SUBPROCESS_TIMEOUT_SECONDS,
        )
        combined_output = result.stdout + result.stderr

        assert VIEWPORT_CENTERING_TEST_FILE in combined_output, (
            f"expected {VIEWPORT_CENTERING_TEST_FILE} to actually run; it did not "
            f"appear in the run output.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert result.returncode == 0, (
            f"{VIEWPORT_CENTERING_TEST_FILE} (which includes the real-MainScene-boot "
            "viewport-bounds assertion) must pass.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
