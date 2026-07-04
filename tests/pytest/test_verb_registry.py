"""
tests/pytest/test_verb_registry.py

Pytest suite for FEAT-003: Data-driven verb registry core (US-003/FR-008,
ADR-004).

Exercises core/application/verb_registry.py's VerbDescriptor contract and
VerbRegistry dispatch table against small, stateful fake port
implementations (GameStatePort/ActionResolverPort/MovementPort/TurnPort) —
not mocks-of-everything — so the assertions actually verify business
behavior (availability computed from real state, execute() mutating real
state through the port), not merely "was a method called".

Covers all three test_criteria from the feature spec:
  1. registry.list_verbs() returns exactly Strike/Step/Stride/End Turn.
  2. registry.execute() / enter_selection() dispatch through the
     descriptor, not through name-conditional branching (behavioral proof
     + a structural source-inspection guard).
  3. A hypothetical fifth verb can be registered and dispatched without
     any change to VerbRegistry's dispatch methods (extensibility demo).

The module under test lives at core/application/verb_registry.py.
core/ is not a Python package (no __init__.py, consistent with the rest
of this project's engine-side tree, e.g. scripts/check_ci_pipeline_sync.py
loaded the same way by tests/ci/test_pipeline_sync.py), so it is loaded
here via importlib rather than a package-style `import core...` statement.
"""

from __future__ import annotations

import importlib.util
import inspect
import re
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
MODULE_PATH = REPO_ROOT / "core" / "application" / "verb_registry.py"


def _load_verb_registry_module():
    assert MODULE_PATH.is_file(), "core/application/verb_registry.py must exist"
    spec = importlib.util.spec_from_file_location("verb_registry", MODULE_PATH)
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
SelectionDescriptor = _verb_registry.SelectionDescriptor
VerbDescriptor = _verb_registry.VerbDescriptor
VerbRegistry = _verb_registry.VerbRegistry
build_default_registry = _verb_registry.build_default_registry


# ── Fake ports (stateful, not Mock-everything) ────────────────────────────


class FakeGameState:
    """A tiny, real in-memory GameStatePort implementation."""

    def __init__(self):
        self.active_combatant_id = "titus"
        self.actions_remaining = {"titus": 1}
        self.reachable_targets = {"titus": ["skeleton"]}
        self.adjacent_hexes = {"titus": [(1, 0)]}
        self.stride_hexes = {"titus": [(2, 0), (1, 1)]}

    def get_active_combatant(self):
        return self.active_combatant_id

    def get_remaining_actions(self, combatant_id):
        return self.actions_remaining.get(combatant_id, 0)

    def get_reachable_targets(self, combatant_id):
        return list(self.reachable_targets.get(combatant_id, []))

    def get_legal_adjacent_hexes(self, combatant_id):
        return list(self.adjacent_hexes.get(combatant_id, []))

    def get_legal_stride_hexes(self, combatant_id):
        return list(self.stride_hexes.get(combatant_id, []))


class FakeActionResolver:
    """A tiny, real ActionResolverPort implementation (Strike)."""

    def __init__(self, game_state: FakeGameState):
        self._game_state = game_state
        self.calls = []

    def select_target(self, combatant_id, target_id):
        self.calls.append((combatant_id, target_id))
        if target_id not in self._game_state.get_reachable_targets(combatant_id):
            return ResolutionResult(verb_id=STRIKE, success=False, error="OUT_OF_REACH")
        if self._game_state.get_remaining_actions(combatant_id) <= 0:
            return ResolutionResult(verb_id=STRIKE, success=False, error="NO_ACTIONS_REMAINING")
        self._game_state.actions_remaining[combatant_id] -= 1
        return ResolutionResult(
            verb_id=STRIKE, success=True, action_spent=True, resolved_target_id=target_id
        )


class FakeMovement:
    """A tiny, real MovementPort implementation (Step/Stride)."""

    def __init__(self, game_state: FakeGameState):
        self._game_state = game_state
        self.calls = []

    def move_token(self, combatant_id, destination, spend_action):
        self.calls.append((combatant_id, destination, spend_action))
        if spend_action:
            self._game_state.actions_remaining[combatant_id] -= 1
        verb_id = STRIDE if spend_action else STEP
        return ResolutionResult(
            verb_id=verb_id, success=True, action_spent=spend_action, new_position=destination
        )


class FakeTurn:
    """A tiny, real TurnPort implementation (End Turn)."""

    def __init__(self):
        self.ended = False
        self.calls = 0

    def end_turn(self):
        self.calls += 1
        self.ended = True
        return ResolutionResult(verb_id=END_TURN, success=True)


@pytest.fixture()
def game_state() -> FakeGameState:
    return FakeGameState()


@pytest.fixture()
def action_resolver(game_state) -> FakeActionResolver:
    return FakeActionResolver(game_state)


@pytest.fixture()
def movement(game_state) -> FakeMovement:
    return FakeMovement(game_state)


@pytest.fixture()
def turn() -> FakeTurn:
    return FakeTurn()


@pytest.fixture()
def registry(game_state, action_resolver, movement, turn) -> VerbRegistry:
    return build_default_registry(game_state, action_resolver, movement, turn)


# ── Criterion 1: list_verbs() returns exactly Strike/Step/Stride/End Turn ──


class TestListVerbs:
    def test_returns_exactly_four_descriptors(self, registry):
        descriptors = registry.list_verbs()
        assert len(descriptors) == 4

    def test_returns_exactly_the_expected_verb_ids_no_extras(self, registry):
        verb_ids = {d.verb_id for d in registry.list_verbs()}
        assert verb_ids == {STRIKE, STEP, STRIDE, END_TURN}

    def test_list_verbs_yields_verb_descriptor_instances(self, registry):
        for descriptor in registry.list_verbs():
            assert isinstance(descriptor, VerbDescriptor)


# ── Availability (business_logic verb-availability computation) ──────────


class TestAvailability:
    def test_strike_available_when_action_and_target_present(self, registry):
        assert registry.is_available(STRIKE) is True

    def test_strike_unavailable_when_no_actions_remaining(self, registry, game_state):
        game_state.actions_remaining["titus"] = 0
        assert registry.is_available(STRIKE) is False

    def test_strike_unavailable_when_no_reachable_targets(self, registry, game_state):
        game_state.reachable_targets["titus"] = []
        assert registry.is_available(STRIKE) is False

    def test_step_available_when_legal_adjacent_hex_exists(self, registry):
        assert registry.is_available(STEP) is True

    def test_step_unavailable_when_no_legal_adjacent_hex(self, registry, game_state):
        game_state.adjacent_hexes["titus"] = []
        assert registry.is_available(STEP) is False

    def test_stride_available_when_action_and_destination_present(self, registry):
        assert registry.is_available(STRIDE) is True

    def test_stride_unavailable_when_no_actions_remaining(self, registry, game_state):
        game_state.actions_remaining["titus"] = 0
        assert registry.is_available(STRIDE) is False

    def test_end_turn_always_available(self, registry, game_state):
        game_state.actions_remaining["titus"] = 0
        game_state.reachable_targets["titus"] = []
        game_state.adjacent_hexes["titus"] = []
        game_state.stride_hexes["titus"] = []
        assert registry.is_available(END_TURN) is True


# ── Criterion 2: generic dispatch through the descriptor ─────────────────


class TestGenericDispatch:
    def test_enter_selection_strike_returns_reachable_targets(self, registry, game_state):
        selection = registry.enter_selection(STRIKE)
        assert isinstance(selection, SelectionDescriptor)
        assert selection.verb_id == STRIKE
        assert selection.candidate_targets == game_state.get_reachable_targets("titus")

    def test_enter_selection_step_returns_adjacent_hexes(self, registry, game_state):
        selection = registry.enter_selection(STEP)
        assert selection.candidate_hexes == game_state.get_legal_adjacent_hexes("titus")

    def test_enter_selection_stride_returns_stride_hexes(self, registry, game_state):
        selection = registry.enter_selection(STRIDE)
        assert selection.candidate_hexes == game_state.get_legal_stride_hexes("titus")

    def test_execute_strike_dispatches_to_action_resolver_port(
        self, registry, action_resolver, game_state
    ):
        result = registry.execute(STRIKE, "skeleton")
        assert result.success is True
        assert result.resolved_target_id == "skeleton"
        assert action_resolver.calls == [("titus", "skeleton")]
        # Real state mutation proves this went through the port, not a stub.
        assert game_state.actions_remaining["titus"] == 0

    def test_execute_step_dispatches_to_movement_port_without_spending_action(
        self, registry, movement, game_state
    ):
        result = registry.execute(STEP, (1, 0))
        assert result.success is True
        assert result.action_spent is False
        assert movement.calls == [("titus", (1, 0), False)]
        assert game_state.actions_remaining["titus"] == 1

    def test_execute_stride_dispatches_to_movement_port_spending_action(
        self, registry, movement, game_state
    ):
        result = registry.execute(STRIDE, (2, 0))
        assert result.success is True
        assert result.action_spent is True
        assert movement.calls == [("titus", (2, 0), True)]
        assert game_state.actions_remaining["titus"] == 0

    def test_execute_end_turn_dispatches_to_turn_port(self, registry, turn):
        result = registry.execute(END_TURN)
        assert result.success is True
        assert turn.calls == 1
        assert turn.ended is True

    def test_unknown_verb_id_raises_on_is_available(self, registry):
        with pytest.raises(KeyError):
            registry.is_available("NOT_A_REAL_VERB")

    def test_unknown_verb_id_raises_on_enter_selection(self, registry):
        with pytest.raises(KeyError):
            registry.enter_selection("NOT_A_REAL_VERB")

    def test_unknown_verb_id_raises_on_execute(self, registry):
        with pytest.raises(KeyError):
            registry.execute("NOT_A_REAL_VERB")

    def test_cancel_is_a_pure_noop(self, registry, action_resolver, movement, turn):
        result = registry.cancel()
        assert result is None
        assert action_resolver.calls == []
        assert movement.calls == []
        assert turn.calls == 0

    def test_dispatch_methods_contain_no_verb_conditional_branching(self):
        """Structural guard for 'dispatch through the descriptor, not through
        name-conditional branching': VerbRegistry.execute/enter_selection/
        is_available must not contain an `if`/`elif` comparing verb_id (or
        verb names) — dispatch must be a dict lookup, generic over any
        registered verb.
        """
        for method_name in ("execute", "enter_selection", "is_available"):
            source = inspect.getsource(getattr(VerbRegistry, method_name))
            assert not re.search(r"\bif\b", source), (
                f"VerbRegistry.{method_name} appears to branch on verb identity "
                f"instead of dispatching generically through the descriptor table"
            )
            for literal in (STRIKE, STEP, STRIDE, END_TURN):
                assert literal not in source, (
                    f"VerbRegistry.{method_name} references the verb literal "
                    f"{literal!r} directly — dispatch must be verb-agnostic"
                )


# ── FEAT-008 (US-008/FR-003): Strike Layer 2 target-highlight contract ────


class TestStrikeEnterSelectionEnemyOnlyTargeting:
    """Pins the exact FEAT-008 test_criteria wording: 'Strike
    enter_selection() returns a SelectionDescriptor containing only
    in-reach enemy target ids.' VerbRegistry itself has no notion of
    ally/enemy — that filtering is GameStatePort.get_reachable_targets()'s
    contract (see build_default_registry()'s strike_enter_selection()
    docstring) — so this suite proves the descriptor is EXACTLY whatever
    that port reports, with no VerbRegistry-side re-filtering/re-ordering/
    duplication, using a fixture where an ally id is deliberately present
    in the wider combatant roster but absent from get_reachable_targets()'s
    return value (mirroring how the real Godot adapter, MainScene.gd's
    _strike_reachable_target_ids(), only ever iterates `_enemies`)."""

    def test_candidate_targets_contains_only_the_reachable_enemy_ids(self, game_state, action_resolver, movement, turn):
        # A living ally ("marigold") exists in this encounter but must never
        # be a reachable Strike target — game_state.reachable_targets only
        # ever names enemies (the real adapter's contract), so it is simply
        # never added here.
        game_state.reachable_targets["titus"] = ["skeleton_1", "skeleton_2"]
        registry = build_default_registry(game_state, action_resolver, movement, turn)

        selection = registry.enter_selection(STRIKE)

        assert selection.candidate_targets == ["skeleton_1", "skeleton_2"]
        assert "marigold" not in selection.candidate_targets

    def test_candidate_targets_is_empty_when_no_enemy_is_in_reach(self, game_state, action_resolver, movement, turn):
        game_state.reachable_targets["titus"] = []
        registry = build_default_registry(game_state, action_resolver, movement, turn)

        selection = registry.enter_selection(STRIKE)

        assert selection.candidate_targets == []


# ── Criterion 3: extensibility — a hypothetical fifth verb ────────────────


class TestExtensibility:
    def test_a_fifth_verb_can_be_registered_and_dispatched_generically(self, registry):
        """CAST_SPELL does not exist anywhere in verb_registry.py — it is
        invented entirely here, in the test, to prove VerbRegistry never
        needed to know the name/shape of a future verb in advance."""
        CAST_SPELL = "CAST_SPELL"
        cast_state = {"available": True, "cast": False}

        def cast_spell_availability() -> bool:
            return cast_state["available"]

        def cast_spell_enter_selection() -> SelectionDescriptor:
            return SelectionDescriptor(verb_id=CAST_SPELL, candidate_targets=["skeleton"])

        def cast_spell_execute(selection) -> ResolutionResult:
            cast_state["cast"] = True
            return ResolutionResult(
                verb_id=CAST_SPELL, success=True, resolved_target_id=selection
            )

        registry.register(
            VerbDescriptor(
                CAST_SPELL,
                cast_spell_availability,
                cast_spell_enter_selection,
                cast_spell_execute,
            )
        )

        verb_ids = {d.verb_id for d in registry.list_verbs()}
        assert verb_ids == {STRIKE, STEP, STRIDE, END_TURN, CAST_SPELL}

        assert registry.is_available(CAST_SPELL) is True

        selection = registry.enter_selection(CAST_SPELL)
        assert selection.candidate_targets == ["skeleton"]

        result = registry.execute(CAST_SPELL, "skeleton")
        assert result.success is True
        assert result.resolved_target_id == "skeleton"
        assert cast_state["cast"] is True

    def test_registering_a_fifth_verb_does_not_disturb_the_original_four(self, registry):
        registry.register(
            VerbDescriptor(
                "CHANNEL",
                lambda: True,
                lambda: SelectionDescriptor(verb_id="CHANNEL"),
                lambda selection: ResolutionResult(verb_id="CHANNEL", success=True),
            )
        )
        verb_ids = [d.verb_id for d in registry.list_verbs()]
        assert verb_ids[:4] == [STRIKE, STEP, STRIDE, END_TURN]
        assert verb_ids[4] == "CHANNEL"


# ── Domain purity (ADR-001-style discipline, mirrored for this Python module) ─


class TestModulePurity:
    def test_verb_registry_module_has_zero_framework_imports(self):
        """ADR-001-style discipline: no framework import lines (Godot,
        FastAPI, SQLAlchemy, Flask, ...). Only actual `import`/`from ...
        import` statements are checked — prose in comments/docstrings
        explaining *why* the module is pure is expected and fine."""
        source = MODULE_PATH.read_text()
        import_lines = [
            line
            for line in source.splitlines()
            if re.match(r"^\s*(import|from)\s+\S", line)
        ]
        forbidden_modules = ("godot", "fastapi", "sqlalchemy", "flask")
        for line in import_lines:
            lowered = line.lower()
            for token in forbidden_modules:
                assert token not in lowered, (
                    f"core/application/verb_registry.py must not import framework "
                    f"module {token!r} (Clean Architecture application layer): {line!r}"
                )
