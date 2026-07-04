"""
tests/static/test_no_godot_types_in_core.py

Pytest suite for FEAT-179: Architectural boundary compliance static checks
(US-016 / NFR-001 / NFR-002 / NFR-005, ADR-001).

ADR-001 requires core/ (domain + application layer, in this repo's GDScript/
Python hybrid tree) to stay engine-agnostic: pure logic + data, ZERO Godot
scene-tree (Node/Control-descendant) imports or inheritance. The existing
per-file header comments across core/ ("Domain layer (ADR-001): pure
GDScript -- no Node/Control/CanvasItem inheritance") document this intent,
but nothing previously enforced it mechanically -- a future core/ file could
silently start `extends Control` and nothing would catch it until a much
later, harder-to-diagnose runtime/architecture failure.

This is an EXECUTABLE test artifact (not a document): it statically scans
every source file under core/ and fails the build the moment a Node/Control
-descendant base class, a scene-tree type reference, or a Godot .tscn scene
dependency is introduced.

Two complementary checks:
  1. Positive/negative self-test of the scanning logic itself, against
     inline synthetic source snippets (not new fixture files -- this
     feature creates only the three tests/static/*.py files) -- proves the
     scanner actually catches a violation and does not false-positive on
     the legitimate RefCounted/Resource/string-`extends` patterns already
     used throughout core/.
  2. The REAL scan: every *.gd and *.py file under the repository's core/
     tree must be clean.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Iterable, List

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
CORE_DIR = REPO_ROOT / "core"

# ── The banned set: Node itself, plus every Node/Control-descendant the
# Godot 4 built-in class hierarchy ships, curated to the ones a game-combat
# codebase could plausibly reach for. Resource and RefCounted (the two base
# classes core/ legitimately extends -- see core/domain/combatant.gd,
# core/geometry/hex_coord.gd, core/model/*_resource.gd) are deliberately
# NOT in this set: they carry no scene-tree/engine-IO behavior and are the
# documented, sanctioned domain-purity pattern for this project. ──────────

BANNED_GODOT_SCENE_TREE_TYPES = frozenset(
    {
        # Root scene-tree types
        "Node",
        "Node2D",
        "Node3D",
        "CanvasItem",
        "CanvasLayer",
        "SceneTree",
        "Viewport",
        "Window",
        "Control",
        # Common Control-descendant UI widgets
        "Button",
        "Label",
        "Panel",
        "PanelContainer",
        "VBoxContainer",
        "HBoxContainer",
        "GridContainer",
        "CenterContainer",
        "MarginContainer",
        "LineEdit",
        "TextEdit",
        "RichTextLabel",
        "ColorRect",
        "TextureRect",
        "TextureButton",
        "CheckBox",
        "CheckButton",
        "OptionButton",
        "ItemList",
        "Tree",
        "TabContainer",
        "ScrollContainer",
        "ProgressBar",
        "Slider",
        "HSlider",
        "VSlider",
        "SpinBox",
        "PopupMenu",
        "Popup",
        "AcceptDialog",
        "ConfirmationDialog",
        "FileDialog",
        "ColorPicker",
        "ColorPickerButton",
        # Common Node2D-descendant render/gameplay nodes
        "Sprite2D",
        "AnimatedSprite2D",
        "Camera2D",
        "CollisionShape2D",
        "Area2D",
        "RigidBody2D",
        "CharacterBody2D",
        "StaticBody2D",
        "TileMap",
        "Polygon2D",
        "Line2D",
        "Path2D",
        "PathFollow2D",
        # Other common Node-descendants
        "Timer",
        "AnimationPlayer",
        "AudioStreamPlayer",
        "HTTPRequest",
    }
)

# Base classes explicitly sanctioned for core/'s domain-purity pattern.
ALLOWED_BASE_TYPES = frozenset({"RefCounted", "Resource"})

_EXTENDS_RE = re.compile(r"^\s*extends\s+(\S+)", re.MULTILINE)
_STRING_EXTENDS_RE = re.compile(r'^\s*extends\s+"([^"]+)"', re.MULTILINE)


def find_extends_violations(source: str) -> List[str]:
    """Returns every banned scene-tree base class this GDScript source
    declares via a bare (non-string) `extends <Base>` clause."""
    violations = []
    for match in _EXTENDS_RE.finditer(source):
        target = match.group(1).strip()
        # A quoted string extends clause (`extends "res://..."`) is a
        # same-tree-layer inheritance chain, not a bare identifier --
        # handled separately by find_scene_preload_violations below.
        if target.startswith('"'):
            continue
        if target in BANNED_GODOT_SCENE_TREE_TYPES:
            violations.append(target)
    return violations


def find_type_hint_violations(source: str) -> List[str]:
    """Catches banned scene-tree types used as a type hint/instantiation
    (`: Node`, `as Control`, `Node.new()`) even when the file's own
    `extends` clause is clean -- e.g. a domain class holding a `Node`
    reference as a collaborator would still leak an engine dependency."""
    violations = []
    for banned in BANNED_GODOT_SCENE_TREE_TYPES:
        pattern = re.compile(
            r"(?::\s*"
            + re.escape(banned)
            + r"\b|\bas\s+"
            + re.escape(banned)
            + r"\b|\b"
            + re.escape(banned)
            + r"\.new\s*\()"
        )
        if pattern.search(source):
            violations.append(banned)
    return violations


def find_scene_preload_violations(source: str) -> List[str]:
    """A `preload("res://....tscn")` (or `.tres` importing a scene) pulls
    in a Godot scene-tree resource -- a UI/engine dependency that has no
    place in core/, regardless of the base class the file itself extends."""
    return re.findall(r'(?:preload|load)\(\s*["\']([^"\']+\.tscn)["\']\s*\)', source)


def find_python_engine_import_violations(source: str) -> List[str]:
    """Guards the Python side of core/ (core/application/verb_registry.py)
    against ever importing a Godot Python-binding shim."""
    violations = []
    for match in re.finditer(r"^\s*(?:import|from)\s+(\S+)", source, re.MULTILINE):
        module = match.group(1)
        if module.split(".")[0].lower() == "godot":
            violations.append(module)
    return violations


def _iter_core_files(suffix: str) -> Iterable[Path]:
    if not CORE_DIR.is_dir():
        return []
    return sorted(CORE_DIR.rglob(f"*{suffix}"))


# ── Self-test: prove the scanner itself works (true positive + true
# negative) before trusting it against the real tree. ──────────────────────


class TestScannerSelfCheck:
    def test_flags_bare_extends_node(self):
        bad = 'class_name RogueWidget\nextends Node\n\nfunc _ready() -> void:\n\tpass\n'
        assert find_extends_violations(bad) == ["Node"]

    def test_flags_bare_extends_control(self):
        bad = 'class_name RogueLabel\nextends Control\n'
        assert find_extends_violations(bad) == ["Control"]

    def test_flags_control_descendant_widget(self):
        bad = 'class_name RogueButton\nextends Button\n'
        assert find_extends_violations(bad) == ["Button"]

    def test_does_not_flag_refcounted(self):
        good = 'class_name Pure\nextends RefCounted\n'
        assert find_extends_violations(good) == []

    def test_does_not_flag_resource(self):
        good = 'class_name PureData\nextends Resource\n'
        assert find_extends_violations(good) == []

    def test_does_not_flag_string_extends_chain(self):
        good = 'class_name Adapter\nextends "res://core/rules/random_port.gd"\n'
        assert find_extends_violations(good) == []

    def test_flags_node_type_hint_even_with_clean_extends(self):
        bad = (
            "class_name SneakyDomain\n"
            "extends RefCounted\n"
            "var collaborator: Node\n"
        )
        assert "Node" in find_type_hint_violations(bad)

    def test_flags_control_instantiation(self):
        bad = "class_name SneakyDomain\nextends RefCounted\nfunc make():\n\treturn Control.new()\n"
        assert "Control" in find_type_hint_violations(bad)

    def test_does_not_flag_clean_domain_source(self):
        good = (
            "class_name HexCoord\n"
            "extends RefCounted\n"
            "var q: int\n"
            "var r: int\n"
            "func distance(other: HexCoord) -> int:\n"
            "\treturn 0\n"
        )
        assert find_type_hint_violations(good) == []
        assert find_extends_violations(good) == []

    def test_flags_tscn_preload(self):
        bad = 'const SCENE = preload("res://scenes/battlefield/HexBattlefield.tscn")\n'
        assert find_scene_preload_violations(bad) == ["res://scenes/battlefield/HexBattlefield.tscn"]

    def test_does_not_flag_gd_preload(self):
        good = 'const SCRIPT = preload("res://core/rules/random_port.gd")\n'
        assert find_scene_preload_violations(good) == []

    def test_flags_python_godot_import(self):
        bad = "import godot\nfrom godot import Node\n"
        assert find_python_engine_import_violations(bad) == ["godot", "godot"]

    def test_does_not_flag_python_stdlib_imports(self):
        good = "from __future__ import annotations\nimport re\nfrom typing import Any, Protocol\n"
        assert find_python_engine_import_violations(good) == []


# ── The real scan over core/ ────────────────────────────────────────────────


class TestCoreTreeHasNoGodotSceneTreeTypes:
    def test_core_directory_exists(self):
        assert CORE_DIR.is_dir(), "core/ must exist for this static check to be meaningful"

    def test_core_gd_files_found(self):
        gd_files = list(_iter_core_files(".gd"))
        assert len(gd_files) > 0, "expected at least one .gd file under core/ to scan"

    def test_no_gd_file_extends_a_banned_scene_tree_type(self):
        offenders = {}
        for path in _iter_core_files(".gd"):
            violations = find_extends_violations(path.read_text())
            if violations:
                offenders[str(path.relative_to(REPO_ROOT))] = violations
        assert offenders == {}, (
            "core/ files must not extend a Node/Control-descendant Godot scene-tree "
            f"type (ADR-001 domain purity); offenders: {offenders}"
        )

    def test_no_gd_file_references_a_banned_type_as_hint_or_instantiation(self):
        offenders = {}
        for path in _iter_core_files(".gd"):
            violations = find_type_hint_violations(path.read_text())
            if violations:
                offenders[str(path.relative_to(REPO_ROOT))] = violations
        assert offenders == {}, (
            "core/ files must not reference a Node/Control-descendant type as a "
            f"type hint, cast target, or via .new() instantiation; offenders: {offenders}"
        )

    def test_no_gd_file_preloads_a_godot_scene(self):
        offenders = {}
        for path in _iter_core_files(".gd"):
            violations = find_scene_preload_violations(path.read_text())
            if violations:
                offenders[str(path.relative_to(REPO_ROOT))] = violations
        assert offenders == {}, (
            "core/ files must not preload/load a .tscn Godot scene resource "
            f"(a scene-tree/UI dependency); offenders: {offenders}"
        )

    def test_no_tscn_scene_files_exist_under_core(self):
        tscn_files = list(_iter_core_files(".tscn"))
        assert tscn_files == [], (
            "core/ must not contain any .tscn Godot scene files at all "
            f"(ADR-001 domain purity); found: {tscn_files}"
        )

    def test_no_python_file_under_core_imports_a_godot_engine_shim(self):
        offenders = {}
        for path in _iter_core_files(".py"):
            violations = find_python_engine_import_violations(path.read_text())
            if violations:
                offenders[str(path.relative_to(REPO_ROOT))] = violations
        assert offenders == {}, (
            f"core/*.py files must not import a Godot engine binding; offenders: {offenders}"
        )
