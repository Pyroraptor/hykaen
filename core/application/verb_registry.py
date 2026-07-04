"""
core/application/verb_registry.py — VerbRegistry (FEAT-003 / US-003/FR-008,
ADR-004)

Application layer (Clean Architecture): a small, DATA-DRIVEN dispatch table
of VerbDescriptor entries — {verb_id, availability_fn, enter_selection_fn,
execute_fn} — reused by every later Layer 1 (verb bar) / Layer 2
(target/destination selection) presentation surface (see the Iteration E
design notes: VerbBarView queries is_available()/list_verbs(), calls
enter_selection() on a Layer 1 click, and SelectionOverlay calls execute()
once the player picks a target/hex).

Depends ONLY on domain-shaped data and application-layer PORTS (Protocol
classes reused verbatim per ADR-002 — GameStatePort, ActionResolverPort,
MovementPort, TurnPort). It introduces NO new port/use-case of its own; it
is a composition/dispatch artifact sitting over the existing ports, exactly
as scoped by ADR-004. It never imports a concrete adapter/infrastructure
class, and it has ZERO Godot/engine imports (ADR-001's domain-purity
discipline extended to this Python composition surface for its own
pytest-only existence in this iteration).

THE CORE EXTENSIBILITY GUARANTEE (US-003 acceptance): VerbRegistry.execute(),
enter_selection(), and is_available() dispatch PURELY by looking up the
verb_id in a dict of registered VerbDescriptor entries and delegating to
whichever function that descriptor carries. There is no
if/elif verb_id == "..." branching anywhere in this dispatch path — so a
brand-new verb (e.g. a future "Cast a Spell") can be registered via
VerbRegistry.register() and immediately dispatches through the exact same
three methods, with ZERO changes to VerbRegistry itself or to any
presentation-layer controller that only ever calls the registry (never the
underlying use cases directly).

Only Strike/Step/Stride/End Turn are registered by build_default_registry()
this iteration (US-003's explicit scope) — Cast/Channel domain logic does
not exist yet and is deliberately NOT stubbed here.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Protocol


# ── Verb identifiers ───────────────────────────────────────────────────────
# The only four verbs registered this iteration (US-003 scope). Any future
# verb is just another string handed to VerbRegistry.register() — nothing
# in VerbRegistry's dispatch logic is keyed off these particular literals.

STRIKE: str = "STRIKE"
STEP: str = "STEP"
STRIDE: str = "STRIDE"
END_TURN: str = "END_TURN"


# ── Value objects (application-layer, transient — never persisted) ────────


@dataclass(frozen=True)
class SelectionDescriptor:
    """Layer 2 transient UI state returned by VerbDescriptor.enter_selection_fn.

    candidate_hexes is populated for hex-destination verbs (Step/Stride);
    candidate_targets is populated for combatant-target verbs (Strike).
    Verbs with no Layer 2 (End Turn) return a descriptor with both empty.
    """

    verb_id: str
    candidate_hexes: List[Any] = field(default_factory=list)
    candidate_targets: List[Any] = field(default_factory=list)
    cancellable: bool = True


@dataclass(frozen=True)
class ResolutionResult:
    """Result-typed outcome of VerbDescriptor.execute_fn — never an
    exception for expected domain-rule violations (see error_handling:
    Result-typed at the port boundary, not exception-typed)."""

    verb_id: str
    success: bool
    action_spent: bool = False
    new_position: Optional[Any] = None
    resolved_target_id: Optional[Any] = None
    error: Optional[str] = None


# ── Ports reused (Protocol classes) ────────────────────────────────────────
# Application depends only on these contracts (ADR-002: no new ports are
# introduced by this feature); a concrete adapter satisfying each Protocol
# is supplied by the composition root (build_default_registry's caller).


class GameStatePort(Protocol):
    def get_active_combatant(self) -> Any: ...

    def get_remaining_actions(self, combatant_id: Any) -> int: ...

    def get_reachable_targets(self, combatant_id: Any) -> List[Any]: ...

    def get_legal_adjacent_hexes(self, combatant_id: Any) -> List[Any]: ...

    def get_legal_stride_hexes(self, combatant_id: Any) -> List[Any]: ...


class ActionResolverPort(Protocol):
    def select_target(self, combatant_id: Any, target_id: Any) -> ResolutionResult: ...


class MovementPort(Protocol):
    def move_token(
        self, combatant_id: Any, destination: Any, spend_action: bool
    ) -> ResolutionResult: ...


class TurnPort(Protocol):
    def end_turn(self) -> ResolutionResult: ...


# ── VerbDescriptor — the registry entry (US-003 contract) ─────────────────


@dataclass(frozen=True)
class VerbDescriptor:
    """{verb_id, availability(), enter_selection(), execute()} — the exact
    shape US-003 calls for. Each *_fn is a zero/one-argument callable;
    VerbRegistry never inspects verb_id to decide HOW to call them, it only
    uses verb_id as the dict key that finds the right descriptor."""

    verb_id: str
    availability_fn: Callable[[], bool]
    enter_selection_fn: Callable[[], SelectionDescriptor]
    execute_fn: Callable[[Any], ResolutionResult]


# ── VerbRegistry — generic, data-driven dispatch table ─────────────────────


class VerbRegistry:
    """A fixed, statically-registered table of VerbDescriptor entries.

    Not a port in the hexagonal sense (no alternate implementation/adapter,
    not injected via DI for testing) — it is the composition surface a
    presentation controller consumes generically: list_verbs() to render a
    bar, is_available() to gate each button, enter_selection()/execute() to
    drive Layer 2, cancel() to back out with zero mutation.

    Every dispatch method below is a plain dict lookup by verb_id followed
    by a delegate call — there is deliberately no verb-name branching here,
    which is what lets a fifth, sixth, ... verb be registered and dispatched
    without touching this class or any controller built on top of it.
    """

    def __init__(self) -> None:
        self._descriptors: Dict[str, VerbDescriptor] = {}
        self._registration_order: List[str] = []

    def register(self, descriptor: VerbDescriptor) -> None:
        """Adds (or replaces) a VerbDescriptor. This is the ONLY way new
        verbs enter the table — no other method special-cases a verb_id."""
        if descriptor.verb_id not in self._descriptors:
            self._registration_order.append(descriptor.verb_id)
        self._descriptors[descriptor.verb_id] = descriptor

    def list_verbs(self) -> List[VerbDescriptor]:
        """Every registered VerbDescriptor, in registration order."""
        return [self._descriptors[verb_id] for verb_id in self._registration_order]

    def is_available(self, verb_id: str) -> bool:
        return bool(self._lookup(verb_id).availability_fn())

    def enter_selection(self, verb_id: str) -> SelectionDescriptor:
        return self._lookup(verb_id).enter_selection_fn()

    def execute(self, verb_id: str, selection: Any = None) -> ResolutionResult:
        return self._lookup(verb_id).execute_fn(selection)

    def cancel(self) -> None:
        """Returns to Layer 1 with GUARANTEED zero port calls — CancelController
        never touches ActionResolverPort/MovementPort/TurnPort (US-012)."""
        return None

    def _lookup(self, verb_id: str) -> VerbDescriptor:
        """The single dispatch primitive every public method above funnels
        through — a dict lookup, not a conditional chain. An unregistered
        verb_id is a programmer error (internal contract violation, not a
        player-triggerable state) and fails loudly per error_handling."""
        descriptor = self._descriptors.get(verb_id)
        if descriptor is None:
            raise KeyError(f"VerbRegistry: no verb registered for verb_id={verb_id!r}")
        return descriptor


# ── Default registry factory: Strike/Step/Stride/End Turn only (US-003) ───


def build_default_registry(
    game_state: GameStatePort,
    action_resolver: ActionResolverPort,
    movement: MovementPort,
    turn: TurnPort,
) -> VerbRegistry:
    """Composes the four in-scope VerbDescriptor entries over the existing
    ports and returns a ready-to-use VerbRegistry. This is the ONLY place
    verb-specific wiring exists in this module — VerbRegistry itself stays
    completely verb-agnostic (see its docstring)."""

    registry = VerbRegistry()

    def strike_availability() -> bool:
        combatant_id = game_state.get_active_combatant()
        return (
            game_state.get_remaining_actions(combatant_id) > 0
            and len(game_state.get_reachable_targets(combatant_id)) > 0
        )

    def strike_enter_selection() -> SelectionDescriptor:
        # FEAT-008 (US-008/FR-003): the returned candidate_targets is
        # exactly game_state.get_reachable_targets(combatant_id) — the
        # SAME in-reach ENEMY filter GameStatePort's own contract documents
        # (api_contracts: "get_reachable_targets(combatant_id) ->
        # List[Combatant] # used by Strike.availability()/enter_selection()").
        # VerbRegistry never re-derives or re-filters that list itself (no
        # ally ever appears here, no out-of-reach enemy ever appears here) —
        # a presentation-layer SelectionOverlay (this iteration's Godot
        # runtime realization, presentation/selection_overlay.gd) highlights
        # PURELY from this descriptor, so "only in-reach enemy targets are
        # highlighted" is guaranteed by construction, not by any UI-side
        # re-filtering.
        combatant_id = game_state.get_active_combatant()
        return SelectionDescriptor(
            verb_id=STRIKE,
            candidate_targets=game_state.get_reachable_targets(combatant_id),
            cancellable=True,
        )

    def strike_execute(target_id: Any) -> ResolutionResult:
        combatant_id = game_state.get_active_combatant()
        return action_resolver.select_target(combatant_id, target_id)

    registry.register(
        VerbDescriptor(STRIKE, strike_availability, strike_enter_selection, strike_execute)
    )

    def step_availability() -> bool:
        combatant_id = game_state.get_active_combatant()
        return len(game_state.get_legal_adjacent_hexes(combatant_id)) > 0

    def step_enter_selection() -> SelectionDescriptor:
        combatant_id = game_state.get_active_combatant()
        return SelectionDescriptor(
            verb_id=STEP,
            candidate_hexes=game_state.get_legal_adjacent_hexes(combatant_id),
            cancellable=True,
        )

    def step_execute(destination: Any) -> ResolutionResult:
        combatant_id = game_state.get_active_combatant()
        return movement.move_token(combatant_id, destination, spend_action=False)

    registry.register(
        VerbDescriptor(STEP, step_availability, step_enter_selection, step_execute)
    )

    def stride_availability() -> bool:
        combatant_id = game_state.get_active_combatant()
        return (
            game_state.get_remaining_actions(combatant_id) > 0
            and len(game_state.get_legal_stride_hexes(combatant_id)) > 0
        )

    def stride_enter_selection() -> SelectionDescriptor:
        combatant_id = game_state.get_active_combatant()
        return SelectionDescriptor(
            verb_id=STRIDE,
            candidate_hexes=game_state.get_legal_stride_hexes(combatant_id),
            cancellable=True,
        )

    def stride_execute(destination: Any) -> ResolutionResult:
        combatant_id = game_state.get_active_combatant()
        return movement.move_token(combatant_id, destination, spend_action=True)

    registry.register(
        VerbDescriptor(STRIDE, stride_availability, stride_enter_selection, stride_execute)
    )

    def end_turn_availability() -> bool:
        return True

    def end_turn_enter_selection() -> SelectionDescriptor:
        # End Turn has no Layer 2 (design notes: "no Layer 2, per spec") —
        # this descriptor exists only so the generic dispatch contract is
        # uniform across every verb; presentation calls execute() directly
        # for END_TURN and never enter_selection() in practice.
        return SelectionDescriptor(verb_id=END_TURN, cancellable=False)

    def end_turn_execute(_selection: Any = None) -> ResolutionResult:
        return turn.end_turn()

    registry.register(
        VerbDescriptor(END_TURN, end_turn_availability, end_turn_enter_selection, end_turn_execute)
    )

    return registry
