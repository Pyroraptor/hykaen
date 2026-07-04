"""
tests/static/test_no_new_ports_introduced.py

Pytest suite for FEAT-179: Architectural boundary compliance static checks
(US-016 / NFR-001 / NFR-002 / NFR-005, ADR-002).

ADR-002/ADR-004 ("VerbRegistry composes EXISTING ports, introduces NO new
port/use-case of its own") is only as good as something that keeps proving
it after this iteration. This is an EXECUTABLE test artifact (not a
document): it snapshots the exact pre-iteration-E baseline of

    ActionResolverPort, MovementPort, TurnPort, GameStatePort

(the four Protocol classes defined in core/application/verb_registry.py)
and fails the moment any of the following drifts:
  - a method is ADDED to or REMOVED from any of the four ports,
  - an existing method's signature (parameter names/annotations/return
    type) changes,
  - a FIFTH port (a new Protocol class) is introduced in the same module.

The baseline below was captured by reading the current, committed
core/application/verb_registry.py (see the design notes' api_contracts
section, reproduced 1:1 here) -- it is intentionally a literal, hand-frozen
snapshot rather than something computed at import time, precisely so a
future change to the live file is what this test is designed to catch.
"""

from __future__ import annotations

import importlib.util
import inspect
import sys
from pathlib import Path
from typing import Any, Dict, List

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
MODULE_PATH = REPO_ROOT / "core" / "application" / "verb_registry.py"

# ── The frozen, pre-iteration baseline ─────────────────────────────────────
# Exactly the four ports ADR-002/ADR-004 say are reused verbatim -- no more,
# no fewer -- each with its exact method-name -> signature-string mapping.

BASELINE_PORT_NAMES = frozenset(
    {"GameStatePort", "ActionResolverPort", "MovementPort", "TurnPort"}
)

BASELINE_PORT_SIGNATURES: Dict[str, Dict[str, str]] = {
    "GameStatePort": {
        "get_active_combatant": "(self) -> Any",
        "get_remaining_actions": "(self, combatant_id: Any) -> int",
        "get_reachable_targets": "(self, combatant_id: Any) -> List[Any]",
        "get_legal_adjacent_hexes": "(self, combatant_id: Any) -> List[Any]",
        "get_legal_stride_hexes": "(self, combatant_id: Any) -> List[Any]",
    },
    "ActionResolverPort": {
        "select_target": "(self, combatant_id: Any, target_id: Any) -> ResolutionResult",
    },
    "MovementPort": {
        "move_token": "(self, combatant_id: Any, destination: Any, spend_action: bool) -> ResolutionResult",
    },
    "TurnPort": {
        "end_turn": "(self) -> ResolutionResult",
    },
}


def _load_verb_registry_module():
    assert MODULE_PATH.is_file(), "core/application/verb_registry.py must exist"
    spec = importlib.util.spec_from_file_location("verb_registry_static_check", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def verb_registry_module():
    return _load_verb_registry_module()


def _public_methods(cls) -> List[str]:
    return sorted(
        name
        for name, member in vars(cls).items()
        if inspect.isfunction(member) and not name.startswith("_")
    )


_QUOTED_ANNOTATION_RE = __import__("re").compile(r"'([^']*)'")


def _signature_str(cls, method_name: str) -> str:
    func = vars(cls)[method_name]
    # verb_registry.py has `from __future__ import annotations`, so raw
    # inspect.signature() renders every annotation as its quoted source
    # string (e.g. "(self) -> 'Any'") rather than a resolved object. Strip
    # the quotes textually (rather than eval_str=True resolving them to
    # live class objects) so the comparison stays purely structural: a
    # renamed/re-typed parameter still changes this string, but the result
    # isn't coupled to *how* this test happens to load the module (e.g.
    # eval_str=True's rendering of a resolved class annotation is prefixed
    # with the importing module's own __name__, an artifact of the
    # importlib.util.spec_from_file_location loader below, not of
    # verb_registry.py's real contract).
    return _QUOTED_ANNOTATION_RE.sub(r"\1", str(inspect.signature(func)))


def _is_protocol_subclass(obj) -> bool:
    return (
        inspect.isclass(obj)
        and obj.__name__ != "Protocol"
        and any(base.__name__ == "Protocol" for base in obj.__mro__[1:])
    )


class TestExactlyTheBaselinePortsExist:
    """No fifth port may be introduced in this module -- ADR-002/ADR-004's
    'no new ports' guarantee, checked structurally rather than by trust."""

    def test_module_defines_exactly_the_four_baseline_ports(self, verb_registry_module):
        discovered_protocols = {
            name
            for name in vars(verb_registry_module)
            if _is_protocol_subclass(getattr(verb_registry_module, name))
        }
        assert discovered_protocols == set(BASELINE_PORT_NAMES), (
            "core/application/verb_registry.py must define exactly the pre-iteration "
            f"port set {sorted(BASELINE_PORT_NAMES)} (ADR-002: no new ports); "
            f"found: {sorted(discovered_protocols)}"
        )


@pytest.mark.parametrize("port_name", sorted(BASELINE_PORT_NAMES))
class TestPortMethodSetMatchesBaselineExactly:
    def test_method_names_match_baseline(self, verb_registry_module, port_name):
        cls = getattr(verb_registry_module, port_name)
        live_methods = set(_public_methods(cls))
        baseline_methods = set(BASELINE_PORT_SIGNATURES[port_name].keys())
        assert live_methods == baseline_methods, (
            f"{port_name}'s method set must match the pre-iteration baseline exactly "
            f"(no additions/removals); baseline={sorted(baseline_methods)}, "
            f"live={sorted(live_methods)}"
        )

    def test_every_method_signature_matches_baseline_verbatim(self, verb_registry_module, port_name):
        cls = getattr(verb_registry_module, port_name)
        for method_name, baseline_sig in BASELINE_PORT_SIGNATURES[port_name].items():
            live_sig = _signature_str(cls, method_name)
            assert live_sig == baseline_sig, (
                f"{port_name}.{method_name}'s signature must match the pre-iteration "
                f"baseline exactly; baseline={baseline_sig!r}, live={live_sig!r}"
            )


class TestBaselineSelfConsistency:
    """Sanity checks on the baseline table itself and the helpers above --
    proves this suite would actually fail on a real drift rather than being
    vacuously true, without touching the real module."""

    def test_baseline_covers_all_four_documented_ports(self):
        assert set(BASELINE_PORT_SIGNATURES.keys()) == BASELINE_PORT_NAMES

    def test_signature_helper_detects_added_method(self):
        class FakePortWithExtraMethod:
            def existing(self) -> None: ...
            def brand_new_method(self) -> None: ...

        live_methods = set(_public_methods(FakePortWithExtraMethod))
        baseline_methods = {"existing"}
        assert live_methods != baseline_methods
        assert "brand_new_method" in (live_methods - baseline_methods)

    def test_signature_helper_detects_removed_method(self):
        class FakePortMissingMethod:
            def existing(self) -> None: ...

        live_methods = set(_public_methods(FakePortMissingMethod))
        baseline_methods = {"existing", "was_removed"}
        assert "was_removed" in (baseline_methods - live_methods)

    def test_signature_helper_detects_signature_drift(self):
        class FakePortWithChangedSignature:
            def move_token(self, combatant_id: Any, destination: Any) -> None: ...  # noqa: F821

        # Missing spend_action param relative to the real MovementPort baseline.
        live_sig = _signature_str(FakePortWithChangedSignature, "move_token")
        assert live_sig != BASELINE_PORT_SIGNATURES["MovementPort"]["move_token"]
