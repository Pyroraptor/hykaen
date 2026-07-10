"""FEAT-211 (DEF-003): pin the full shape of the checked-in balance-simulation
artifact so a future edit cannot silently drop provenance metadata again.

FEAT-007's commit regenerated sim_results.json with only the four *result* keys
(total_battles / win_rate / avg_rounds / confidence_interval), dropping the three
*provenance* keys (commit_hash / seed / timestamp) that document WHICH commit,
WHICH seed, and WHEN the deterministic 1000-battle balance gate was produced.
V&V flagged this as a regression (DEF-003 / NFR-002). The emitter
(tests/sim/test_balance_sim.gd::test_write_sim_results_json_artifact) now writes
all seven keys; this test guards the artifact so the drop can't recur unnoticed.
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent
SIM_RESULTS = REPO_ROOT / "sim_results.json"

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
