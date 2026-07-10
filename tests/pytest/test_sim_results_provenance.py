"""FEAT-211 (DEF-003): pin the full shape of the checked-in balance-simulation
artifact so a future edit cannot silently drop provenance metadata again.

FEAT-007's commit regenerated sim_results.json with only the four *result* keys
(total_battles / win_rate / avg_rounds / confidence_interval), dropping the three
*provenance* keys (commit_hash / seed / timestamp) that document WHICH commit,
WHICH seed, and WHEN the deterministic 1000-battle balance gate was produced.
V&V flagged this as a regression (DEF-003 / NFR-002). The emitter
(tests/sim/test_balance_sim.gd::test_write_sim_results_json_artifact) now writes
all seven keys; this test guards the artifact so the drop can't recur unnoticed.

FEAT-009 (US-009, iteration K): a one-time re-baseline. skeleton.tres' Arming
Sword weapon table moved proficiency_bonus 1 -> 2 (FEAT-001, reconciled to the
Weapons.pdf ground truth), which is the SOLE change that shifted the pinned
N=1000 / seed=12345 deterministic balance outcome. This adds two things beyond
the FEAT-211 shape guard above:

  1. An explicit pin on `confidence_interval` (test_only_arming_sword_attributable_metrics_moved
     below) -- win_rate/avg_rounds were already re-pinned by
     test_result_values_are_unchanged_from_pinned_gate, but confidence_interval
     is a DERIVED metric (1.96*sqrt(p*(1-p)/n) off win_rate) that could, in
     principle, drift independently if a future change altered the CI formula
     or `n` itself without touching win_rate -- pinning it closes that gap so
     "no OTHER sim metric moved" is actually verified, not just asserted in
     prose (test_criteria #2).

  2. TestBalanceSimRegenerationIsDeterministic: a real, two-subprocess
     regression test (mirroring tests/integration/test_headless_boot_smoke.py's
     established `_find_godot_binary()` / subprocess.run() convention) that
     actually re-runs tests/sim/test_balance_sim.gd's real
     test_write_sim_results_json_artifact TWICE, each in an independent `godot
     --headless` process, and diffs the resulting sim_results.json result keys.
     core/sim/simulator.gd's Encounter never wires a reaction_chooser_port
     (no Dodge/Parry/Block/Opportunistic-Strike AI is invoked at all in the
     balance sim -- see core/combat/encounter.gd, which has zero `reaction`
     references), so every reaction window this simulator's Encounter
     instances would otherwise open is implicitly "pass" -- there is no
     reaction-choice RNG consumption path for a future AI-policy change to
     leak variance through. This test proves that empirically: two
     independent regen runs of the SAME seed (12345) must produce
     byte-identical win_rate/avg_rounds/confidence_interval/total_battles,
     confirming no reaction-path (or any other) nondeterminism entered the
     pass-only sim (test_criteria #3).
"""

import json
import re
import shutil
import subprocess
from pathlib import Path
from typing import Optional

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
SIM_RESULTS = REPO_ROOT / "sim_results.json"

# The four *result* keys a sim run actually produces (as opposed to the three
# *provenance* keys -- commit_hash/seed/timestamp -- which are metadata ABOUT
# a run, not sim-behavior output, and are expected to change every regen).
RESULT_KEYS = ("win_rate", "avg_rounds", "total_battles", "confidence_interval")

_BALANCE_SIM_TEST_FILE = "test_balance_sim.gd"
_BALANCE_SIM_TEST_DIR = "res://tests/sim"
_SUBPROCESS_TIMEOUT_SECONDS = 90


def _find_godot_binary() -> Optional[str]:
    """Mirrors tests/integration/test_headless_boot_smoke.py's identically-named
    helper exactly, so every subprocess-invoking pytest suite in this project
    agrees on how the `godot` binary is discovered."""
    for candidate in ("godot", "godot4", "godot4.3", "godot-headless"):
        found = shutil.which(candidate)
        if found:
            return found
    return None

# The full, documented output shape (FEAT-090 result keys + FEAT-211 provenance).
REQUIRED_KEYS = {
    "commit_hash",
    "seed",
    "timestamp",
    "win_rate",
    "avg_rounds",
    "total_battles",
    "confidence_interval",
}


def _load() -> dict:
    assert SIM_RESULTS.exists(), f"{SIM_RESULTS} must exist (balance-sim artifact)"
    return json.loads(SIM_RESULTS.read_text())


def test_sim_results_contains_all_seven_documented_keys() -> None:
    data = _load()
    missing = REQUIRED_KEYS - data.keys()
    assert not missing, (
        "sim_results.json is missing documented key(s) %s — provenance must not be "
        "dropped (DEF-003). Present keys: %s" % (sorted(missing), sorted(data.keys()))
    )


def test_provenance_keys_are_non_empty() -> None:
    data = _load()
    assert isinstance(data.get("seed"), int), "seed must be an int (the pinned balance seed)"
    assert str(data.get("commit_hash", "")).strip() != "", "commit_hash must be recorded"
    assert str(data.get("timestamp", "")).strip() != "", "timestamp must be recorded"


def test_result_values_are_unchanged_from_pinned_gate() -> None:
    # FEAT-001 (iteration K, US-009 re-baseline): skeleton.tres' Arming Sword
    # weapon table moved proficiency_bonus from 1 to 2 (ground truth per the
    # Weapons.pdf table, reconciled 2026-07-10), which genuinely shifts the
    # Skeleton's attack bonus and therefore the deterministic N=1000 balance
    # outcome at the pinned seed (12345). This re-pins the gate to the new,
    # freshly regenerated deterministic values (win_rate 0.747 -> 0.688,
    # avg_rounds 1.081 -> 1.068) — still comfortably inside test_balance_sim.gd's
    # [0.40, 0.80] balance invariant — rather than masking the intentional data
    # change. Any FUTURE drift away from these values (a different sim-behavior
    # regression) still fails this gate, exactly as before.
    data = _load()
    assert data["win_rate"] == 0.688, "win_rate must stay the pinned 0.688 (no sim-behavior drift beyond FEAT-001's Arming Sword re-baseline)"
    assert data["avg_rounds"] == 1.068, "avg_rounds must stay the pinned 1.068 (no sim-behavior drift beyond FEAT-001's Arming Sword re-baseline)"
    assert data["total_battles"] == 1000, "total_battles must remain 1000"


def test_only_arming_sword_attributable_metrics_moved() -> None:
    # FEAT-009 (US-009, test_criteria #2): confidence_interval is DERIVED from
    # win_rate and n (core/sim/simulator.gd: 1.96*sqrt(p*(1-p)/n)) -- pin its
    # exact value too, so a future change that touched the CI formula or `n`
    # WITHOUT touching win_rate (which test_result_values_are_unchanged_from_pinned_gate
    # already guards) still fails this gate rather than passing unnoticed.
    # This closes the "no OTHER sim metric moved" half of the FEAT-001
    # Arming Sword re-baseline, not just the win_rate/avg_rounds half.
    data = _load()
    win_rate = data["win_rate"]
    n = data["total_battles"]
    expected_ci = 1.96 * ((win_rate * (1.0 - win_rate) / n) ** 0.5)
    assert data["confidence_interval"] == pytest.approx(expected_ci, abs=1e-12), (
        "confidence_interval must stay derived purely from the pinned win_rate/total_battles "
        "(1.96*sqrt(p*(1-p)/n)) -- any other drift indicates a sim-behavior regression beyond "
        "FEAT-001's Arming Sword proficiency change"
    )
    assert data["confidence_interval"] == 0.0287162408681916, (
        "confidence_interval must stay the pinned 0.0287162408681916 (no sim-behavior drift "
        "beyond FEAT-001's Arming Sword re-baseline)"
    )
    assert data["seed"] == 12345, "the pinned balance seed must not move -- a seed change would itself be an unattributed metric shift"
    assert data["total_battles"] == 1000, "total_battles must remain 1000 -- an n change would itself be an unattributed metric shift"


# ══════════════════════════════════════════════════════════════════════════
# FEAT-009 test_criteria #3: "Regression test confirms the pass-only sim run
# remains deterministic (no reaction-path variance) across two regen runs."
# ══════════════════════════════════════════════════════════════════════════

@pytest.fixture(scope="module")
def godot_bin() -> str:
    found = _find_godot_binary()
    if found is None:
        pytest.skip("godot binary not found on PATH")
    return found


def _regenerate_sim_results(godot_bin: str) -> dict:
    """Runs the REAL tests/sim/test_balance_sim.gd suite in its own
    independent `godot --headless` subprocess (mirroring tests/integration/
    test_headless_boot_smoke.py's established subprocess convention). That
    suite's test_write_sim_results_json_artifact() re-writes res://sim_results.json
    from a freshly-run Simulator.run(1000, 12345) each time it executes, so this
    performs a genuine end-to-end regen -- not a mock -- and returns the
    resulting parsed JSON.
    """
    result = subprocess.run(
        [
            godot_bin,
            "--headless",
            "-s",
            "addons/gut/gut_cmdln.gd",
            f"-gselect={_BALANCE_SIM_TEST_FILE}",
            f"-gdir={_BALANCE_SIM_TEST_DIR}",
            "-gexit",
        ],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        timeout=_SUBPROCESS_TIMEOUT_SECONDS,
    )
    assert result.returncode == 0, (
        f"{_BALANCE_SIM_TEST_FILE} regen run must exit 0.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    return _load()


class TestBalanceSimRegenerationIsDeterministic:
    def test_two_independent_regen_runs_produce_identical_result_metrics(self, godot_bin) -> None:
        run1 = _regenerate_sim_results(godot_bin)
        run2 = _regenerate_sim_results(godot_bin)

        for key in RESULT_KEYS:
            assert run1[key] == run2[key], (
                f"two independent regen runs of tests/sim/test_balance_sim.gd (same seed=12345, "
                f"N=1000) produced DIFFERENT '{key}' values ({run1[key]!r} vs {run2[key]!r}) -- "
                "this would indicate reaction-path (or other) nondeterminism leaked into the "
                "pass-only balance sim. run1=%r run2=%r" % (run1, run2)
            )

        # Provenance (commit_hash/seed/timestamp) is metadata ABOUT a run, not
        # sim-behavior output -- seed must stay pinned (it's a fixed constant,
        # BALANCE_SEED, not a rolled value), but timestamp is EXPECTED to
        # differ between the two runs; asserting that distinguishes "the
        # regen genuinely re-ran twice" from "the file was never rewritten".
        assert run1["seed"] == run2["seed"] == 12345
        assert run1["timestamp"] != run2["timestamp"], (
            "two independent regen subprocess runs should have produced two distinct "
            "timestamps -- identical timestamps would suggest the second run never actually "
            "re-wrote sim_results.json (a vacuous determinism 'pass')"
        )

    def test_regenerated_values_match_the_pinned_gate(self, godot_bin) -> None:
        # After regenerating, the freshly-produced values must still match the
        # values pinned by test_result_values_are_unchanged_from_pinned_gate /
        # test_only_arming_sword_attributable_metrics_moved above -- i.e. the
        # committed sim_results.json in this repo IS what a fresh regen
        # produces, not a stale/hand-edited artifact.
        regenerated = _regenerate_sim_results(godot_bin)
        assert regenerated["win_rate"] == 0.688
        assert regenerated["avg_rounds"] == 1.068
        assert regenerated["total_battles"] == 1000
        assert regenerated["confidence_interval"] == 0.0287162408681916
