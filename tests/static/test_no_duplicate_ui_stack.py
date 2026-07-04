"""
tests/static/test_no_duplicate_ui_stack.py

Pytest suite for FEAT-179: Architectural boundary compliance static checks
(US-016 / NFR-001 / NFR-002 / NFR-005).

Iteration D's P0-2 ("Consolidate to ONE UI stack") removed the duplicate
scenes/battlefield/* widget set's WIRING from MainScene.tscn/.gd (see
tests/infrastructure/test_mainscene_no_battlefield_refs.gd), and this
iteration's FEAT-006/FEAT-007 removed the last of its legacy immediate-
action controller logic -- but the scenes/battlefield/ directory's actual
*.gd/*.tscn FILES were never deleted from disk, leaving a fully dead,
unreferenced duplicate UI stack sitting in the tree (confirmed by
inspection: nothing outside scenes/battlefield/ itself ever preloads,
ext_resource-references, or imports any file under that path -- every
remaining mention elsewhere in the repo is prose/comment/const-string
documentation of the removal, e.g.
tests/fixtures/naming_hygiene/test_fixture_with_stale_reference.gd's
deliberate bait constant for the naming-hygiene checker).

This is an EXECUTABLE test artifact (not a document) closing that gap two
ways:
  1. No files may exist under scenes/battlefield/* at all (the duplicate
     stack must be actually gone, not merely unwired).
  2. No file anywhere in the repository may contain a live CODE reference
     to that path -- a `preload(...)`/`load(...)` call or a `.tscn`
     `ext_resource`/node `path=` attribute pointing at
     res://scenes/battlefield/... This deliberately does NOT flag bare
     prose/comment mentions of the historical path (those are pre-existing
     documentation in files outside this feature's scope, not a live
     dependency), which is why check 2 requires the match to sit inside an
     actual load/preload/ext_resource token, not a bare substring anywhere
     in the file.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Dict, List

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
BATTLEFIELD_DIR = REPO_ROOT / "scenes" / "battlefield"

# Directories that are irrelevant to a "live code reference" scan (VCS
# internals, editor caches, imported/compiled binary artifacts).
_EXCLUDED_DIR_PARTS = {".git", ".godot", ".pytest_cache", "__pycache__", ".benchmarks"}

# This static-check suite itself (tests/static/) deliberately embeds
# synthetic "bad" preload/ext_resource strings as self-test fixtures (see
# TestCodeReferenceScannerSelfCheck above, and the sibling
# test_no_godot_types_in_core.py's own preload self-test) -- those are not
# live dependencies on the removed scenes/battlefield/* stack, so the
# whole-repo scan below excludes this suite's own directory to avoid
# flagging its own test fixtures.
_SELF_EXCLUDED_DIR = REPO_ROOT / "tests" / "static"

_CODE_REFERENCE_RE = re.compile(
    r'(?:preload|load)\(\s*["\']([^"\']*res://scenes/battlefield[^"\']*)["\']'
    r'|path\s*=\s*"([^"]*res://scenes/battlefield[^"]*)"'
    r'|(?:^|[\s(])import\s+["\']?(scenes\.battlefield[^\s"\']*)'
)


def find_code_references(content: str) -> List[str]:
    """Returns every LIVE (preload/load/ext_resource-path/import) reference
    to scenes/battlefield found in `content` -- excludes bare prose/comment
    mentions of the path, which are not code dependencies."""
    hits = []
    for match in _CODE_REFERENCE_RE.finditer(content):
        hits.append(next(group for group in match.groups() if group))
    return hits


def _iter_scannable_files():
    for path in REPO_ROOT.rglob("*"):
        if not path.is_file():
            continue
        if any(part in _EXCLUDED_DIR_PARTS for part in path.parts):
            continue
        if _SELF_EXCLUDED_DIR in path.parents:
            continue
        yield path


# ── Self-test: prove the reference-scanner distinguishes a live dependency
# from historical prose before trusting it against the real repo. ─────────


class TestCodeReferenceScannerSelfCheck:
    def test_flags_gdscript_preload(self):
        bad = 'const X = preload("res://scenes/battlefield/HexBattlefield.gd")\n'
        assert find_code_references(bad) == ["res://scenes/battlefield/HexBattlefield.gd"]

    def test_flags_gdscript_load(self):
        bad = 'var x = load("res://scenes/battlefield/ResultScreen.tscn")\n'
        assert find_code_references(bad) == ["res://scenes/battlefield/ResultScreen.tscn"]

    def test_flags_tscn_ext_resource_path(self):
        bad = '[ext_resource type="Script" path="res://scenes/battlefield/HexBattlefield.gd" id="1"]\n'
        assert find_code_references(bad) == ["res://scenes/battlefield/HexBattlefield.gd"]

    def test_does_not_flag_a_bare_comment_mention(self):
        good = (
            "## mirrors scenes/battlefield/StrikeInputController.gd's lock()/"
            "is_locked() contract\n"
        )
        assert find_code_references(good) == []

    def test_does_not_flag_a_string_constant_used_only_as_bait_data(self):
        # Mirrors tests/fixtures/naming_hygiene/test_fixture_with_stale_reference.gd's
        # deliberate const -- a plain string assignment is not a load/preload/
        # ext_resource call, so it must not be flagged as a live reference.
        good = 'const _STALE_PATH: String = "res://scenes/battlefield/HexBattlefield.tscn"\n'
        assert find_code_references(good) == []

    def test_does_not_flag_unrelated_preloads(self):
        good = 'const SCRIPT = preload("res://core/rules/random_port.gd")\n'
        assert find_code_references(good) == []


# ── The real checks ─────────────────────────────────────────────────────────


class TestNoScenesBattlefieldFilesExist:
    def test_scenes_battlefield_directory_is_absent_or_empty(self):
        if not BATTLEFIELD_DIR.exists():
            return
        remaining = sorted(
            str(p.relative_to(REPO_ROOT)) for p in BATTLEFIELD_DIR.rglob("*") if p.is_file()
        )
        assert remaining == [], (
            "no files may exist under scenes/battlefield/* -- the duplicate UI stack "
            f"must be fully removed (ADR-002 / iteration D P0-2 / US-016); found: {remaining}"
        )


class TestNoLiveCodeReferencesToScenesBattlefieldRemain:
    def test_no_file_in_the_repository_loads_or_preloads_scenes_battlefield(self):
        offenders: Dict[str, List[str]] = {}
        for path in _iter_scannable_files():
            try:
                content = path.read_text(errors="ignore")
            except (UnicodeDecodeError, OSError):
                continue
            hits = find_code_references(content)
            if hits:
                offenders[str(path.relative_to(REPO_ROOT))] = hits
        assert offenders == {}, (
            "no file may contain a live preload/load/ext_resource-path reference to "
            f"res://scenes/battlefield/*; offenders: {offenders}"
        )
