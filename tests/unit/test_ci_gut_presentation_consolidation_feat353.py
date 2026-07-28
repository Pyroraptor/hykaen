"""
tests/unit/test_ci_gut_presentation_consolidation_feat353.py

Pytest suite for FEAT-353 (US-012 / FR-012, mitigates RISK-007/RISK-008):
"Consolidate presentation-layer camera/panel test suite and fix
regressions".

Mirrors the established pattern this codebase already uses for a
"consolidated suite really passes together" gate --
tests/unit/test_ci_gut_domain_consolidation_feat004.py (FEAT-004 / US-014,
the domain-suite consolidation) -- but scoped to the presentation-layer
camera/panel suite instead of the core/ domain suite:

  * tests/hex_grid/test_hex_grid_view_pan.gd          (FEAT-005/FEAT-006,
    US-006/US-007: drag-to-pan + keyboard pan)
  * tests/unit/presentation/test_hex_grid_view.gd      (FEAT-002/FEAT-003,
    US-003/US-004: world-coordinate draw refactor + set_origin_offset()
    camera re-implementation)
  * tests/unit/presentation/test_hex_grid_view_hit_test.gd (FEAT-004,
    US-005: camera-aware hit-testing)
  * tests/unit/presentation/test_collapsible_panel.gd  (FEAT-008/FEAT-009,
    US-008: shared collapsible-panel toggle contract, parametrized over
    InitiativeView/StatusPanelView/EventLogView)

These four files map to the feature plan's files_to_create entries
"tests/hex_grid/test_hex_grid_view.gd", "tests/hex_grid/
test_hex_grid_view_hit_test.gd", "tests/hex_grid/test_hex_grid_view_pan.gd",
and "tests/panels/test_collapsible_panel.gd" verbatim -- this project's
actual, established file layout (every prior FEAT-001..010 commit) keeps
three of the four under tests/unit/presentation/ and the production
scripts under presentation/*.gd rather than a scripts/hex_grid/ or
tests/panels/ tree that does not otherwise exist in this codebase (see
each of those test files' own file-level docs for the identical note).

Each suite already passes in isolation (proven by every prior FEAT-002..
010 commit). This suite proves, via a real subprocess `godot` invocation,
that they ALSO pass together in one combined GUT run -- closing the gap
FEAT-353/US-012 calls out (RISK-007/RISK-008: coverage authored only
per-feature in isolation, never confirmed as a whole) -- and that the
combined run is genuinely SCOPED to these four scripts (not a silent
fallback to the full ~360-script project suite, which would defeat the
point of a dedicated, fast, targeted gate).
"""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

import pytest


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def repo_root() -> Path:
    """Absolute path to the repository root (where project.godot lives)."""
    return Path(__file__).parent.parent.parent


GODOT_AVAILABLE = shutil.which("godot") is not None

# The four presentation-layer camera/panel test scripts this feature
# consolidates, expressed as res:// paths (the actual, established file
# layout -- see this file's own module doc above for why these differ
# from the feature plan's literal files_to_create entries).
PRESENTATION_SUITE_RES_PATHS = [
    "res://tests/unit/presentation/test_hex_grid_view.gd",
    "res://tests/unit/presentation/test_hex_grid_view_hit_test.gd",
    "res://tests/hex_grid/test_hex_grid_view_pan.gd",
    "res://tests/unit/presentation/test_collapsible_panel.gd",
]

PRESENTATION_SUITE_SCRIPT_NAMES = [
    "test_hex_grid_view.gd",
    "test_hex_grid_view_hit_test.gd",
    "test_hex_grid_view_pan.gd",
    "test_collapsible_panel.gd",
]


# ── Filesystem sanity: the four files this feature consolidates exist ───────

class TestConsolidatedPresentationSuiteFilesExist:
    @pytest.mark.parametrize("res_path", PRESENTATION_SUITE_RES_PATHS)
    def test_file_exists(self, repo_root, res_path):
        rel = res_path.replace("res://", "")
        assert (repo_root / rel).is_file(), (
            f"{res_path} must exist -- one of the four presentation-layer "
            "camera/panel test suites FEAT-353 consolidates"
        )


# ── Actually run the four suites together (real Godot binary) ───────────────
#
# Uses GUT's own `-gtest` CLI option (a list of full res:// paths to run,
# independent of any -gdir/-gconfig directory scan) with `-gconfig=` and
# `-gdir=` both explicitly blanked out -- otherwise the default
# res://.gutconfig.json (dirs: ["res://tests", ...], include_subdirs: true)
# is loaded first and silently widens the run back to the whole ~360-script
# project suite, defeating the point of a scoped, dedicated gate (the exact
# regression class tests/unit/test_ci_gut_domain_consolidation_feat004.py's
# own test_consolidated_suite_is_scoped_not_full_project already guards
# against for the domain suite).

@pytest.mark.skipif(not GODOT_AVAILABLE, reason="godot binary not on PATH")
class TestConsolidatedPresentationSuiteReallyPassesTogether:
    def _run(self, repo_root) -> subprocess.CompletedProcess:
        cmd = [
            "godot",
            "--headless",
            "-s",
            "addons/gut/gut_cmdln.gd",
            "-gconfig=",
            "-gdir=",
            "-gtest=" + ",".join(PRESENTATION_SUITE_RES_PATHS),
            "-gexit",
        ]
        return subprocess.run(
            cmd,
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=180,
        )

    def test_combined_run_exits_zero(self, repo_root):
        result = self._run(repo_root)
        output = result.stdout + result.stderr
        assert result.returncode == 0, (
            "The combined presentation-layer camera/panel GUT run "
            f"(test_hex_grid_view.gd + test_hex_grid_view_hit_test.gd + "
            f"test_hex_grid_view_pan.gd + test_collapsible_panel.gd) must "
            f"exit 0 with zero failures. Output:\n{output}"
        )

    def test_combined_run_reports_all_four_scripts(self, repo_root):
        result = self._run(repo_root)
        output = result.stdout + result.stderr
        for expected in PRESENTATION_SUITE_SCRIPT_NAMES:
            assert expected in output, (
                f"Combined presentation-layer GUT run output must mention "
                f"{expected}.\nOutput:\n{output}"
            )

    def test_combined_run_is_scoped_to_exactly_four_scripts(self, repo_root):
        """Guards against the -gconfig-ignored regression class described
        above: the combined run must collect EXACTLY the four consolidated
        presentation-layer scripts, never silently falling back to the full
        project suite (~360 scripts) nor to the whole tests/unit/presentation
        directory (dozens of unrelated presentation suites)."""
        result = self._run(repo_root)
        output = result.stdout + result.stderr
        match = re.search(r"Scripts\s+(\d+)", output)
        assert match, f"Could not find a 'Scripts  N' summary line. Output:\n{output}"
        scripts_run = int(match.group(1))
        assert scripts_run == 4, (
            "The combined presentation-layer run must collect exactly the "
            f"4 consolidated camera/panel scripts, but ran {scripts_run}. "
            f"This means -gtest fell back to (or was widened by) the "
            f"default project-wide gutconfig scan.\nOutput:\n{output}"
        )
        # An unrelated presentation suite (present under tests/unit/
        # presentation/ but NOT one of the four this feature consolidates)
        # must NOT be swept in by an accidental directory-wide scan.
        assert "test_hex_grid_view_hover.gd" not in output, (
            "Combined run must not pull in unrelated presentation-layer "
            f"tests via a directory-wide fallback.\nOutput:\n{output}"
        )

    def test_all_six_pan_related_drag_assertions_present_in_output(self, repo_root):
        """test_criteria: 'All six pan-related assertions in
        test_hex_grid_view_pan.gd (drag delta, click suppression, hover
        suppression, click-when-not-dragging, offset non-mutation,
        input-handled call) pass together'."""
        result = self._run(repo_root)
        output = result.stdout + result.stderr
        for expected in (
            "test_middle_mouse_press_then_drag_motion_decrements_camera_position_by_relative",
            "test_hex_clicked_is_not_emitted_for_left_click_while_drag_panning",
            "test_hex_hovered_is_not_emitted_for_mouse_motion_while_drag_panning",
            "test_left_click_still_emits_hex_clicked_when_not_drag_panning",
            "test_drag_panning_never_mutates_origin_offset",
            "test_middle_mouse_press_calls_set_input_as_handled",
        ):
            assert expected in output, (
                f"Combined run output must include the pan-drag assertion "
                f"{expected}.\nOutput:\n{output}"
            )

    def test_all_four_keyboard_pan_assertions_present_in_output(self, repo_root):
        """test_criteria: 'All four keyboard-pan assertions (no-input
        unchanged, diagonal normalization, PAN_SPEED*delta scaling, focus
        passthrough) pass together'."""
        result = self._run(repo_root)
        output = result.stdout + result.stderr
        for expected in (
            "test_no_input_frame_leaves_camera_position_unchanged",
            "test_diagonal_input_is_normalized_before_scaling",
            "test_single_direction_wasd_input_moves_camera_by_pan_speed_times_delta",
            "test_arrow_key_input_does_not_move_camera_when_control_has_focus",
        ):
            assert expected in output, (
                f"Combined run output must include the keyboard-pan "
                f"assertion {expected}.\nOutput:\n{output}"
            )

    def test_collapse_assertions_present_for_all_three_panel_classes(self, repo_root):
        """test_criteria: 'All five collapse assertions in
        test_collapsible_panel.gd pass for all three panel classes in a
        single suite run'. test_collapsible_panel.gd parametrizes every
        assertion over PANEL_SCENES (InitiativeView/StatusPanelView/
        EventLogView) via GUT's use_parameters(), so a single occurrence of
        each test name with 3 parameter rows in the log output is the
        expected, correct shape -- this asserts the parametrized test names
        themselves are present (the per-parameter row count is proven by
        test_combined_run_exits_zero already covering all 50 collected
        tests passing with zero failures)."""
        result = self._run(repo_root)
        output = result.stdout + result.stderr
        for expected in (
            "test_boots_with_collapsed_false",
            "test_toggle_collapsed_sets_collapsed_true_and_hides_content",
            "test_toggle_collapsed_twice_restores_expanded_state",
            "test_collapse_button_text_is_down_arrow_when_collapsed",
            "test_collapse_button_text_is_up_arrow_when_expanded",
            "test_toggle_collapsed_with_no_parent_does_not_raise",
        ):
            assert expected in output, (
                f"Combined run output must include the collapsible-panel "
                f"assertion {expected}.\nOutput:\n{output}"
            )
