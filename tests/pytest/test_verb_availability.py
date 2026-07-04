"""
tests/pytest/test_verb_availability.py

Pytest suite for FEAT-005: Per-verb availability gating from live game
state (US-005/FR-002).

This is a focused, dedicated exercise of the "business_logic (verb
availability computation from live game state)" contract that gates the
Layer 1 verb bar (VerbBarView, FEAT-004) at the steel thread's entry
point:

  - Strike.availability()   -> true iff actions_remaining > 0 AND
                                get_reachable_targets() is non-empty.
  - Step.availability()     -> true iff get_legal_adjacent_hexes() is
                                non-empty (no action-economy requirement
                                — Step never spends an action).
  - Stride.availability()   -> true iff actions_remaining > 0 AND
                                get_legal_stride_hexes() is non-empty.
  - End Turn.availability() -> always true, regardless of game state.

The availability functions under test live in
core/application/verb_registry.py (build_default_registry's
*_availability closures, reached here through
VerbRegistry.is_available()). They were introduced under FEAT-003 and
composed into the Layer 1 verb bar under FEAT-004; this suite exists to
pin down the availability *contract* in isolation, independent of
list_verbs()/dispatch/extensibility concerns already covered by
tests/pytest/test_verb_registry.py.

Unlike that suite's single shared "everything is available" fixture,
every test here toggles exactly ONE live-state input at a time (via a
small stateful fake GameStatePort, not a mock-everything double) so
each assertion pins down which specific input each verb's availability
truly depends on — including the negative cross-checks (e.g. Step
availability must NOT depend on actions_remaining; Strike/Stride must
each depend on BOTH of their two inputs, not just one).

core/ is not a Python package (no __init__.py) — loaded via importlib,
matching the convention already established by test_verb_registry.py.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
MODULE_PATH = REPO_ROOT / "core" / "application" / "verb_registry.py"


def _load_verb_registry_module():
    assert MODULE_PATH.is_file(), "core/application/verb_registry.py must exist"
    spec = importlib.util.spec_from_file_location("verb_registry_availability", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


_verb_registry = _load_verb_registry_module()

END_TURN = _verb_registry.END_TURN
STEP = _verb_registry.STEP
STRIDE = _verb_registry.STRIDE
STRIKE = _verb_registry.STRIKE
ResolutionResult = _verb_registry.ResolutionResult
build_default_registry = _verb_registry.build_default_registry


# ── Fake ports (stateful, not mock-everything) ─────────────────────────────
# Only GameStatePort's outputs matter for availability() — the mutating
# ports (ActionResolverPort/MovementPort/TurnPort) are wired with trivial
# stubs since build_default_registry() requires all four, but availability
# computation never calls them.


ACTIVE_ID = "titus"


class FakeGameState:
    """A tiny, real in-memory GameStatePort implementation whose live
    state can be toggled per-test to isolate exactly one availability
    input at a time."""

    def __init__(
        self,
        *,
        actions_remaining: int = 1,
        reachable_targets=None,
        adjacent_hexes=None,
        stride_hexes=None,
    ):
        self.active_combatant_id = ACTIVE_ID
        self._actions_remaining = actions_remaining
        self._reachable_targets = list(reachable_targets or [])
        self._adjacent_hexes = list(adjacent_hexes or [])
        self._stride_hexes = list(stride_hexes or [])

    def get_active_combatant(self):
        return self.active_combatant_id

    def get_remaining_actions(self, combatant_id):
        assert combatant_id == self.active_combatant_id
        return self._actions_remaining

    def get_reachable_targets(self, combatant_id):
        assert combatant_id == self.active_combatant_id
        return list(self._reachable_targets)

    def get_legal_adjacent_hexes(self, combatant_id):
        assert combatant_id == self.active_combatant_id
        return list(self._adjacent_hexes)

    def get_legal_stride_hexes(self, combatant_id):
        assert combatant_id == self.active_combatant_id
        return list(self._stride_hexes)


class StubActionResolver:
    def select_target(self, combatant_id, target_id):  # pragma: no cover - unused
        return ResolutionResult(verb_id=STRIKE, success=False, error="UNUSED_IN_AVAILABILITY_TESTS")


class StubMovement:
    def move_token(self, combatant_id, destination, spend_action):  # pragma: no cover - unused
        return ResolutionResult(verb_id=STRIDE, success=False, error="UNUSED_IN_AVAILABILITY_TESTS")


class StubTurn:
    def end_turn(self):  # pragma: no cover - unused
        return ResolutionResult(verb_id=END_TURN, success=False, error="UNUSED_IN_AVAILABILITY_TESTS")


def _registry_for(game_state: FakeGameState):
    """Composes a VerbRegistry over the given live game state, per
    build_default_registry's factory (US-003/ADR-004) — this is the exact
    seam the Layer 1 verb bar (FEAT-004) queries via is_available()."""
    return build_default_registry(game_state, StubActionResolver(), StubMovement(), StubTurn())


# ── Strike: actions_remaining > 0 AND reachable targets non-empty ─────────


class TestStrikeAvailability:
    def test_available_when_action_remaining_and_target_in_reach(self):
        game_state = FakeGameState(actions_remaining=1, reachable_targets=["skeleton"])
        assert _registry_for(game_state).is_available(STRIKE) is True

    def test_unavailable_when_no_actions_remaining_even_with_target(self):
        game_state = FakeGameState(actions_remaining=0, reachable_targets=["skeleton"])
        assert _registry_for(game_state).is_available(STRIKE) is False

    def test_unavailable_when_no_reachable_targets_even_with_action(self):
        game_state = FakeGameState(actions_remaining=1, reachable_targets=[])
        assert _registry_for(game_state).is_available(STRIKE) is False

    def test_unavailable_when_neither_action_nor_target(self):
        game_state = FakeGameState(actions_remaining=0, reachable_targets=[])
        assert _registry_for(game_state).is_available(STRIKE) is False

    def test_available_with_multiple_reachable_targets(self):
        game_state = FakeGameState(actions_remaining=2, reachable_targets=["skeleton", "goblin"])
        assert _registry_for(game_state).is_available(STRIKE) is True


# ── Step: legal adjacent unoccupied hex non-empty ──────────────────────────


class TestStepAvailability:
    def test_available_when_legal_adjacent_hex_exists(self):
        game_state = FakeGameState(adjacent_hexes=[(1, 0)])
        assert _registry_for(game_state).is_available(STEP) is True

    def test_unavailable_when_no_legal_adjacent_hex(self):
        game_state = FakeGameState(adjacent_hexes=[])
        assert _registry_for(game_state).is_available(STEP) is False

    def test_available_regardless_of_actions_remaining(self):
        """Step never spends an action, so its availability must not be
        gated by action economy — only by whether a legal destination
        hex exists."""
        game_state = FakeGameState(actions_remaining=0, adjacent_hexes=[(1, 0)])
        assert _registry_for(game_state).is_available(STEP) is True

    def test_unavailable_when_no_adjacent_hex_even_with_actions_remaining(self):
        game_state = FakeGameState(actions_remaining=3, adjacent_hexes=[])
        assert _registry_for(game_state).is_available(STEP) is False


# ── Stride: actions_remaining > 0 AND legal <=Speed destination non-empty ──


class TestStrideAvailability:
    def test_available_when_action_remaining_and_destination_exists(self):
        game_state = FakeGameState(actions_remaining=1, stride_hexes=[(2, 0), (1, 1)])
        assert _registry_for(game_state).is_available(STRIDE) is True

    def test_unavailable_when_no_actions_remaining_even_with_destination(self):
        game_state = FakeGameState(actions_remaining=0, stride_hexes=[(2, 0)])
        assert _registry_for(game_state).is_available(STRIDE) is False

    def test_unavailable_when_no_legal_stride_hexes_even_with_action(self):
        game_state = FakeGameState(actions_remaining=1, stride_hexes=[])
        assert _registry_for(game_state).is_available(STRIDE) is False

    def test_unavailable_when_neither_action_nor_destination(self):
        game_state = FakeGameState(actions_remaining=0, stride_hexes=[])
        assert _registry_for(game_state).is_available(STRIDE) is False


# ── End Turn: hardcoded always-available, independent of game state ───────


class TestEndTurnAvailability:
    @pytest.mark.parametrize(
        "game_state",
        [
            FakeGameState(),
            FakeGameState(actions_remaining=0, reachable_targets=[], adjacent_hexes=[], stride_hexes=[]),
            FakeGameState(actions_remaining=5, reachable_targets=["skeleton"], adjacent_hexes=[(1, 0)], stride_hexes=[(2, 0)]),
        ],
        ids=["default", "everything-exhausted", "everything-available"],
    )
    def test_always_available_regardless_of_game_state_fixture(self, game_state):
        assert _registry_for(game_state).is_available(END_TURN) is True

    def test_always_available_even_when_active_combatant_has_no_recorded_state(self):
        """An edge fixture with an active combatant unseen by any of the
        other collections still yields End Turn == available; End Turn's
        availability_fn takes no game-state input at all (see
        core/application/verb_registry.py's end_turn_availability)."""
        game_state = FakeGameState(actions_remaining=0)
        game_state.active_combatant_id = "unknown-combatant"
        assert _registry_for(game_state).is_available(END_TURN) is True
