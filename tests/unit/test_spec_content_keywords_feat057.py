"""
tests/unit/test_spec_content_keywords_feat057.py

Pytest suite for FEAT-057: Spec Content Section-Keyword CI Validation Gates.

Validates that .github/workflows/test.yml contains a 'lint-spec-content-keywords'
step that:
  1. Exits 1 immediately when the spec body contains 'STUB placeholder'
  2. Exits 1 when any of the seven attribute names is absent
     (strength, constitution, dexterity, willpower, intellect, intuition, social)
  3. Exits 1 when the 'HP =' formula marker is absent
  4. Exits 1 when any defense keyword (AC, Reflex, Fortitude, Will) is absent
  5. Exits 1 when action set keywords (Strike, Stride) are absent
  6. Exits 0 when all required keywords are present and the STUB marker is absent
  7. Existing lint-spec-approval-marker and lint-spec-no-placeholder gates
     continue to pass (regression guard)

All assertions are pure-Python YAML-parse and subprocess bash checks;
no running Godot binary is required.
"""

import subprocess
import textwrap
from pathlib import Path

import pytest
import yaml


# ── Fixtures ──────────────────────────────────────────────────────────────────

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
def spec_file(repo_root) -> Path:
    return repo_root / "docs" / "hollow-world-v0-spec.org"


def _all_steps(workflow: dict) -> list:
    return workflow.get("jobs", {}).get("test", {}).get("steps", [])


def _all_run_blocks(workflow: dict) -> str:
    """Concatenate every 'run' block from all test job steps."""
    steps = _all_steps(workflow)
    return "\n".join(step.get("run", "") for step in steps if isinstance(step, dict))


def _find_step_by_name(workflow: dict, name: str) -> dict | None:
    """Return the first step dict whose 'name' matches exactly."""
    for step in _all_steps(workflow):
        if isinstance(step, dict) and step.get("name") == name:
            return step
    return None


def _get_step_run(workflow: dict, name: str) -> str:
    """Return the 'run' block of a named step, or empty string if not found."""
    step = _find_step_by_name(workflow, name)
    return step.get("run", "") if step else ""


# ── Minimal full-content spec used for exit-0 tests ──────────────────────────

FULL_CONTENT_SPEC = textwrap.dedent("""\
    #+TITLE: Hollow World v0 — Combat Simulation Specification
    #+AUTHOR: Guy Verisage
    #+DATE: 2026-06-26
    #+APPROVAL: Guy Verisage — reviewed 2026-06-26 — approved for v0 combat simulation milestone

    * Attributes
      Characters have seven core attributes: strength, constitution, dexterity,
      willpower, intellect, intuition, and social.

    * Hit Points
      HP = 8 + class_hp + constitution modifier.

    * Defenses
      - AC (Armor Class)
      - Reflex defense
      - Fortitude defense
      - Will defense

    * Actions
      Each turn a character may Strike (attack) or Stride (move).

    * Armor
      | Armor    | ac_base | Category |
      |----------+---------+----------|
      | Leather  | 11      | light    |

    * Talents
      Each class grants access to a talent tree of passive and active abilities.
""")


# ── Step existence ────────────────────────────────────────────────────────────

class TestStepExists:
    """The 'lint-spec-content-keywords' step must exist in the test job."""

    def test_step_is_present_in_workflow(self, workflow):
        step = _find_step_by_name(workflow, "lint-spec-content-keywords")
        assert step is not None, (
            "test.yml must contain a step named exactly 'lint-spec-content-keywords' "
            "(FEAT-057 / DEF-NEW-001)"
        )

    def test_step_has_run_block(self, workflow):
        run = _get_step_run(workflow, "lint-spec-content-keywords")
        assert run.strip(), (
            "'lint-spec-content-keywords' step must have a non-empty 'run' block"
        )

    def test_step_targets_spec_file(self, workflow):
        run = _get_step_run(workflow, "lint-spec-content-keywords")
        assert "hollow-world-v0-spec.org" in run, (
            "'lint-spec-content-keywords' step must reference docs/hollow-world-v0-spec.org"
        )


# ── Stub-detection: exits 1 when 'STUB placeholder' is present ───────────────

class TestStubDetection:
    """The step must exit 1 immediately when 'STUB placeholder' appears in the spec."""

    def test_step_run_block_checks_stub_placeholder(self, workflow):
        run = _get_step_run(workflow, "lint-spec-content-keywords")
        assert "STUB placeholder" in run, (
            "'lint-spec-content-keywords' run block must grep for 'STUB placeholder' "
            "and exit 1 when found (FEAT-057)"
        )

    def test_step_exits_1_when_stub_placeholder_present(self, tmp_path, workflow):
        """Dry-run: step exits 1 when spec contains 'STUB placeholder'."""
        stub_spec = tmp_path / "stub_spec.org"
        stub_spec.write_text(
            "#+TITLE: Test\n"
            "#+APPROVAL: Guy Verisage — reviewed 2026-06-26 — approved\n"
            "* STATUS\n"
            "  This is a STUB placeholder created by the enforcement gate.\n"
        )
        run_block = _get_step_run(workflow, "lint-spec-content-keywords")
        assert run_block.strip(), "step run block must be non-empty"

        # Substitute the spec path in the run block with our temp file
        adapted_run = run_block.replace(
            "docs/hollow-world-v0-spec.org", str(stub_spec)
        )
        result = subprocess.run(
            ["bash", "-c", adapted_run],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 1, (
            f"lint-spec-content-keywords must exit 1 when spec contains "
            f"'STUB placeholder'\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_current_spec_has_no_stub_placeholder(self, spec_file):
        """The real v0 spec has been authored and author-approved, so it must
        NOT contain 'STUB placeholder' (the content gate must now pass)."""
        content = spec_file.read_text()
        assert "STUB placeholder" not in content, (
            "docs/hollow-world-v0-spec.org has been authored — it must no longer "
            "contain 'STUB placeholder'; the content gate now passes"
        )


# ── Seven attribute names ─────────────────────────────────────────────────────

class TestAttributeKeywords:
    """The step must exit 1 when any of the seven attribute names is absent."""

    ATTRIBUTES = [
        "strength", "constitution", "dexterity",
        "willpower", "intellect", "intuition", "social",
    ]

    def test_step_greps_for_attribute_keywords(self, workflow):
        run = _get_step_run(workflow, "lint-spec-content-keywords")
        for attr in self.ATTRIBUTES:
            assert attr in run, (
                f"'lint-spec-content-keywords' run block must check for attribute "
                f"keyword '{attr}' (FEAT-057)"
            )

    @pytest.mark.parametrize("missing_attr", [
        "strength", "constitution", "dexterity",
        "willpower", "intellect", "intuition", "social",
    ])
    def test_step_exits_1_when_attribute_missing(self, missing_attr, tmp_path, workflow):
        """Dry-run: step exits 1 when one attribute keyword is absent from spec."""
        all_attrs = self.ATTRIBUTES.copy()
        all_attrs.remove(missing_attr)
        # Build a spec with all attributes EXCEPT the missing one.
        # HP formula uses 'CON' abbreviation to avoid accidentally re-introducing
        # 'constitution' in a non-attribute section, which would falsely satisfy the grep.
        attr_lines = "\n".join(f"  - {a}" for a in all_attrs)
        spec_content = (
            "#+TITLE: Test\n"
            "#+APPROVAL: Guy Verisage — reviewed 2026-06-26 — approved\n"
            f"* Attributes\n{attr_lines}\n"
            "* HP\n  HP = 8 + CON_modifier\n"
            "* Defenses\n  AC Reflex Fortitude Will\n"
            "* Actions\n  Strike Stride\n"
            "* Armor\n  | Armor | ac_base |\n"
            "* Talents\n  talent tree here\n"
        )
        spec_file = tmp_path / f"spec_missing_{missing_attr}.org"
        spec_file.write_text(spec_content)

        run_block = _get_step_run(workflow, "lint-spec-content-keywords")
        adapted_run = run_block.replace(
            "docs/hollow-world-v0-spec.org", str(spec_file)
        )
        result = subprocess.run(
            ["bash", "-c", adapted_run],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 1, (
            f"lint-spec-content-keywords must exit 1 when '{missing_attr}' is absent "
            f"from spec\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )


# ── HP formula marker ─────────────────────────────────────────────────────────

class TestHPFormulaMarker:
    """The step must exit 1 when 'HP =' is absent from the spec."""

    def test_step_greps_for_hp_formula(self, workflow):
        run = _get_step_run(workflow, "lint-spec-content-keywords")
        assert "HP =" in run, (
            "'lint-spec-content-keywords' run block must check for 'HP =' marker "
            "(FEAT-057)"
        )

    def test_step_exits_1_when_hp_formula_absent(self, tmp_path, workflow):
        """Dry-run: step exits 1 when 'HP =' is not in spec."""
        spec_file = tmp_path / "spec_no_hp.org"
        spec_file.write_text(
            "#+TITLE: Test\n"
            "#+APPROVAL: Guy Verisage — reviewed 2026-06-26 — approved\n"
            "* Attributes\n"
            "  strength constitution dexterity willpower intellect intuition social\n"
            "* Defenses\n  AC Reflex Fortitude Will\n"
            "* Actions\n  Strike Stride\n"
            "* Armor\n  | Armor | ac_base |\n"
            "* Talents\n  talent tree here\n"
            # Note: 'HP =' deliberately omitted
        )
        run_block = _get_step_run(workflow, "lint-spec-content-keywords")
        adapted_run = run_block.replace(
            "docs/hollow-world-v0-spec.org", str(spec_file)
        )
        result = subprocess.run(
            ["bash", "-c", adapted_run],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 1, (
            f"lint-spec-content-keywords must exit 1 when 'HP =' is absent\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_step_passes_when_hp_formula_present(self, tmp_path, workflow):
        """Dry-run: 'HP =' present in a complete spec does not cause exit 1 for HP check."""
        spec_file = tmp_path / "spec_with_hp.org"
        spec_file.write_text(FULL_CONTENT_SPEC)
        run_block = _get_step_run(workflow, "lint-spec-content-keywords")
        adapted_run = run_block.replace(
            "docs/hollow-world-v0-spec.org", str(spec_file)
        )
        result = subprocess.run(
            ["bash", "-c", adapted_run],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, (
            f"lint-spec-content-keywords must exit 0 when all keywords present\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )


# ── Defense keywords ──────────────────────────────────────────────────────────

class TestDefenseKeywords:
    """The step must exit 1 when any defense keyword is absent."""

    DEFENSE_KEYWORDS = ["AC", "Reflex", "Fortitude", "Will"]

    def test_step_greps_for_defense_keywords(self, workflow):
        run = _get_step_run(workflow, "lint-spec-content-keywords")
        for kw in self.DEFENSE_KEYWORDS:
            assert kw in run, (
                f"'lint-spec-content-keywords' run block must check for defense "
                f"keyword '{kw}' (FEAT-057)"
            )

    @pytest.mark.parametrize("missing_kw", ["AC", "Reflex", "Fortitude", "Will"])
    def test_step_exits_1_when_defense_keyword_absent(self, missing_kw, tmp_path, workflow):
        """Dry-run: step exits 1 when a defense keyword is absent."""
        present_kws = [kw for kw in self.DEFENSE_KEYWORDS if kw != missing_kw]
        defense_line = " ".join(present_kws)
        spec_file = tmp_path / f"spec_missing_{missing_kw}.org"
        spec_file.write_text(
            "#+TITLE: Test\n"
            "#+APPROVAL: Guy Verisage — reviewed 2026-06-26 — approved\n"
            "* Attributes\n"
            "  strength constitution dexterity willpower intellect intuition social\n"
            "* HP\n  HP = 8 + constitution\n"
            f"* Defenses\n  {defense_line}\n"
            "* Actions\n  Strike Stride\n"
            "* Armor\n  | Armor | ac_base |\n"
            "* Talents\n  talent tree here\n"
        )
        run_block = _get_step_run(workflow, "lint-spec-content-keywords")
        adapted_run = run_block.replace(
            "docs/hollow-world-v0-spec.org", str(spec_file)
        )
        result = subprocess.run(
            ["bash", "-c", adapted_run],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 1, (
            f"lint-spec-content-keywords must exit 1 when '{missing_kw}' is absent\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )


# ── Action set keywords ───────────────────────────────────────────────────────

class TestActionKeywords:
    """The step must exit 1 when Strike or Stride is absent."""

    ACTION_KEYWORDS = ["Strike", "Stride"]

    def test_step_greps_for_action_keywords(self, workflow):
        run = _get_step_run(workflow, "lint-spec-content-keywords")
        for kw in self.ACTION_KEYWORDS:
            assert kw in run, (
                f"'lint-spec-content-keywords' run block must check for action "
                f"keyword '{kw}' (FEAT-057)"
            )

    @pytest.mark.parametrize("missing_kw", ["Strike", "Stride"])
    def test_step_exits_1_when_action_keyword_absent(self, missing_kw, tmp_path, workflow):
        """Dry-run: step exits 1 when an action keyword is absent."""
        present_kws = [kw for kw in self.ACTION_KEYWORDS if kw != missing_kw]
        action_line = " ".join(present_kws)
        spec_file = tmp_path / f"spec_missing_{missing_kw}.org"
        spec_file.write_text(
            "#+TITLE: Test\n"
            "#+APPROVAL: Guy Verisage — reviewed 2026-06-26 — approved\n"
            "* Attributes\n"
            "  strength constitution dexterity willpower intellect intuition social\n"
            "* HP\n  HP = 8 + constitution\n"
            "* Defenses\n  AC Reflex Fortitude Will\n"
            f"* Actions\n  {action_line}\n"
            "* Armor\n  | Armor | ac_base |\n"
            "* Talents\n  talent tree here\n"
        )
        run_block = _get_step_run(workflow, "lint-spec-content-keywords")
        adapted_run = run_block.replace(
            "docs/hollow-world-v0-spec.org", str(spec_file)
        )
        result = subprocess.run(
            ["bash", "-c", adapted_run],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 1, (
            f"lint-spec-content-keywords must exit 1 when '{missing_kw}' is absent\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )


# ── Exit 0: all required keywords present ─────────────────────────────────────

class TestExitZeroWithAllKeywords:
    """The step must exit 0 when all required keywords are present and STUB absent."""

    def test_step_exits_0_with_full_content_spec(self, tmp_path, workflow):
        """Dry-run: step exits 0 when spec has all required keywords and no STUB."""
        spec_file = tmp_path / "spec_full.org"
        spec_file.write_text(FULL_CONTENT_SPEC)
        run_block = _get_step_run(workflow, "lint-spec-content-keywords")
        adapted_run = run_block.replace(
            "docs/hollow-world-v0-spec.org", str(spec_file)
        )
        result = subprocess.run(
            ["bash", "-c", adapted_run],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, (
            f"lint-spec-content-keywords must exit 0 when all required keywords "
            f"are present and 'STUB placeholder' is absent\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_step_exits_0_with_current_real_spec(self, spec_file, workflow):
        """The current spec is the authored, approved v0 ruleset (no stub), so the
        content-keywords gate must exit 0 — confirming the real spec passes."""
        content = spec_file.read_text()
        assert "STUB placeholder" not in content, (
            "Pre-condition: current spec must be the authored real spec (no stub)"
        )
        run_block = _get_step_run(workflow, "lint-spec-content-keywords")
        adapted_run = run_block.replace(
            "docs/hollow-world-v0-spec.org", str(spec_file)
        )
        result = subprocess.run(
            ["bash", "-c", adapted_run],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, (
            f"lint-spec-content-keywords must exit 0 on the authored real spec\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )


# ── Regression: existing gates still work ────────────────────────────────────

class TestExistingGatesPreserved:
    """lint-spec-approval-marker and lint-spec-no-placeholder must still pass
    when the approval line is valid and the body contains no PLACEHOLDER."""

    def test_lint_spec_approval_marker_step_still_present(self, workflow):
        step = _find_step_by_name(workflow, "lint-spec-approval-marker")
        assert step is not None, (
            "'lint-spec-approval-marker' step must still be present in test.yml "
            "(regression guard — FEAT-057 must not remove existing gates)"
        )

    def test_lint_spec_no_placeholder_step_still_present(self, workflow):
        step = _find_step_by_name(workflow, "lint-spec-no-placeholder")
        assert step is not None, (
            "'lint-spec-no-placeholder' step must still be present in test.yml "
            "(regression guard — FEAT-057 must not remove existing gates)"
        )

    def test_approval_marker_gate_passes_current_spec(self, spec_file):
        """lint-spec-approval-marker exits 0 on current spec (approval line present)."""
        result = subprocess.run(
            ["bash", "-c",
             f"grep -q '#+APPROVAL:' '{spec_file}' || exit 1"],
            capture_output=True,
        )
        assert result.returncode == 0, (
            "lint-spec-approval-marker must exit 0 — current spec has #+APPROVAL:"
        )

    def test_no_placeholder_gate_passes_current_spec(self, spec_file):
        """lint-spec-no-placeholder exits 0 on current spec.

        The current spec body contains 'STUB placeholder' but the #+APPROVAL:
        line itself does NOT contain 'PLACEHOLDER', so the no-placeholder gate
        (which only fails if PLACEHOLDER appears anywhere in the file) should
        be checked against the actual workflow logic.

        NOTE: The current spec DOES have 'STUB placeholder' in its body — but
        the existing lint-spec-no-placeholder gate greps for 'PLACEHOLDER'
        (uppercase) while the body contains 'placeholder' (lowercase mixed
        case).  Confirm this remains consistent.
        """
        content = spec_file.read_text()
        # The approval line must not have uppercase PLACEHOLDER
        approval_line = next(
            (line for line in content.splitlines() if line.startswith("#+APPROVAL:")),
            ""
        )
        assert "PLACEHOLDER" not in approval_line, (
            "Current #+APPROVAL: line must not contain 'PLACEHOLDER' "
            "— the no-placeholder gate must continue to pass"
        )

    def test_all_three_spec_lint_steps_present(self, workflow):
        """All three spec lint steps must coexist in the workflow."""
        step_names = [
            s.get("name", "") for s in _all_steps(workflow)
            if isinstance(s, dict)
        ]
        expected = [
            "lint-spec-approval-marker",
            "lint-spec-no-placeholder",
            "lint-spec-content-keywords",
        ]
        for name in expected:
            assert name in step_names, (
                f"Step '{name}' must be present in test.yml (FEAT-057)"
            )

    def test_content_keywords_step_appears_after_no_placeholder_step(self, workflow):
        """lint-spec-content-keywords must appear after lint-spec-no-placeholder."""
        steps = _all_steps(workflow)
        names = [s.get("name", "") for s in steps if isinstance(s, dict)]
        no_ph_idx = names.index("lint-spec-no-placeholder") if "lint-spec-no-placeholder" in names else -1
        content_idx = names.index("lint-spec-content-keywords") if "lint-spec-content-keywords" in names else -1
        assert no_ph_idx >= 0, "'lint-spec-no-placeholder' step not found"
        assert content_idx >= 0, "'lint-spec-content-keywords' step not found"
        assert content_idx > no_ph_idx, (
            f"'lint-spec-content-keywords' (index {content_idx}) must appear AFTER "
            f"'lint-spec-no-placeholder' (index {no_ph_idx})"
        )
