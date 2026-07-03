#!/usr/bin/env python3
"""
scripts/check_ci_pipeline_sync.py — FEAT-158 (resolves FIND-151, US-011)

ci/pipeline.yml's per-stage `command:` entries are documentation-only — they
describe, in prose/YAML, the same stage list that scripts/test_command.sh
actually executes. Nothing previously enforced that the two stayed in sync,
so a future edit to one (e.g. adding/removing/renaming a stage in
scripts/test_command.sh) could silently drift out of step with
ci/pipeline.yml's declared stage list, making the pipeline manifest a lie
about what CI really runs.

This script is the drift-prevention mechanism: it parses BOTH stage lists
(the `command:` field of every entry in ci/pipeline.yml's `stages:` list,
and the actual shell commands invoked by scripts/test_command.sh) and fails
(non-zero exit) if the two sets of commands diverge.

Comparison is order-INSENSITIVE by design: scripts/test_command.sh legitimately
orders its stages differently from ci/pipeline.yml's declared `stages:` list
(the script front-loads the consolidated domain suite ahead of the full
`--gut-run-all` run for a faster-fail ordering, while the manifest lists the
full-suite stage first) — same stage SET, different execution order. What
must never diverge is which commands exist in each list, not the order they
appear in.

Usage:
    python scripts/check_ci_pipeline_sync.py
    python scripts/check_ci_pipeline_sync.py --pipeline path/to/pipeline.yml \\
        --test-command path/to/test_command.sh

Exit code 0 when the two stage lists match; non-zero (with a diagnostic
message on stderr) when they diverge.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PIPELINE_PATH = REPO_ROOT / "ci" / "pipeline.yml"
DEFAULT_TEST_COMMAND_SH_PATH = REPO_ROOT / "scripts" / "test_command.sh"

# Leading tokens that mark a shell line as scaffolding rather than an
# actual test-stage command (shebang/comments handled separately).
_NON_STAGE_LINE_PREFIXES = ("set ", "set\t", "cd ", "cd\t", "echo ")

# This script's own invocation line (however it appears in
# scripts/test_command.sh) is the consistency-CHECK mechanism itself, not
# one of the test stages being cross-checked — exclude it so the checker
# never flags its own wiring as "drift" against ci/pipeline.yml, which
# documents test stages rather than tooling/gate scripts.
_SELF_SCRIPT_NAME = Path(__file__).name


def _normalize_whitespace(command: str) -> str:
    """Collapse any run of whitespace (including embedded newlines from a
    YAML folded '>-' block scalar) into single spaces, and strip ends."""
    return re.sub(r"\s+", " ", command).strip()


def extract_pipeline_commands(pipeline_yml_path: Path) -> list[str]:
    """Parse ci/pipeline.yml and return the normalized `command:` string of
    every entry under `stages:`, in the order they're declared."""
    text = pipeline_yml_path.read_text()
    loaded = yaml.safe_load(text)
    if not isinstance(loaded, dict):
        raise ValueError(f"{pipeline_yml_path}: expected a YAML mapping at the top level")

    stages = loaded.get("stages")
    if not isinstance(stages, list) or not stages:
        raise ValueError(f"{pipeline_yml_path}: must declare a non-empty 'stages' list")

    commands: list[str] = []
    for stage in stages:
        if not isinstance(stage, dict) or "command" not in stage:
            raise ValueError(
                f"{pipeline_yml_path}: stage {stage!r} is missing a 'command' field"
            )
        commands.append(_normalize_whitespace(str(stage["command"])))
    return commands


def _join_line_continuations(text: str) -> list[str]:
    """Join backslash-newline continued shell lines into single logical
    lines, so a multi-line command is still compared as one command."""
    raw_lines = text.splitlines()
    logical_lines: list[str] = []
    buffer = ""
    for line in raw_lines:
        stripped = line.rstrip("\n")
        if buffer:
            stripped = buffer + " " + stripped.strip()
            buffer = ""
        if stripped.rstrip().endswith("\\"):
            buffer = stripped.rstrip()[:-1].rstrip()
            continue
        logical_lines.append(stripped)
    if buffer:
        logical_lines.append(buffer)
    return logical_lines


def extract_test_command_sh_commands(test_command_sh_path: Path) -> list[str]:
    """Parse scripts/test_command.sh and return the normalized list of
    actual commands it invokes, in execution order — skipping the
    shebang, comments, blank lines, and shell scaffolding (set/cd/echo)."""
    text = test_command_sh_path.read_text()
    logical_lines = _join_line_continuations(text)

    commands: list[str] = []
    for line in logical_lines:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#!"):
            continue
        if stripped.startswith("#"):
            continue
        if stripped.startswith(_NON_STAGE_LINE_PREFIXES):
            continue
        if _SELF_SCRIPT_NAME in stripped:
            continue
        commands.append(_normalize_whitespace(stripped))
    return commands


class PipelineSyncResult:
    """Outcome of comparing ci/pipeline.yml's declared stage commands
    against scripts/test_command.sh's actually-executed commands."""

    def __init__(self, pipeline_commands: list[str], script_commands: list[str]):
        self.pipeline_commands = pipeline_commands
        self.script_commands = script_commands
        self.pipeline_only = sorted(set(pipeline_commands) - set(script_commands))
        self.script_only = sorted(set(script_commands) - set(pipeline_commands))

    @property
    def in_sync(self) -> bool:
        return not self.pipeline_only and not self.script_only

    def describe(self) -> str:
        if self.in_sync:
            return (
                "ci/pipeline.yml and scripts/test_command.sh stage lists are in sync "
                f"({len(self.pipeline_commands)} stage command(s))."
            )
        lines = ["ci/pipeline.yml and scripts/test_command.sh stage lists have DIVERGED:"]
        if self.pipeline_only:
            lines.append("  Declared in ci/pipeline.yml but NOT run by scripts/test_command.sh:")
            lines.extend(f"    - {cmd}" for cmd in self.pipeline_only)
        if self.script_only:
            lines.append("  Run by scripts/test_command.sh but NOT declared in ci/pipeline.yml:")
            lines.extend(f"    - {cmd}" for cmd in self.script_only)
        return "\n".join(lines)


def check_sync(pipeline_yml_path: Path, test_command_sh_path: Path) -> PipelineSyncResult:
    pipeline_commands = extract_pipeline_commands(pipeline_yml_path)
    script_commands = extract_test_command_sh_commands(test_command_sh_path)
    return PipelineSyncResult(pipeline_commands, script_commands)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Fail if ci/pipeline.yml's declared stage commands diverge from "
            "the commands scripts/test_command.sh actually runs (FEAT-158 / "
            "FIND-151)."
        )
    )
    parser.add_argument(
        "--pipeline",
        type=Path,
        default=DEFAULT_PIPELINE_PATH,
        help="Path to ci/pipeline.yml (default: %(default)s)",
    )
    parser.add_argument(
        "--test-command",
        type=Path,
        default=DEFAULT_TEST_COMMAND_SH_PATH,
        help="Path to scripts/test_command.sh (default: %(default)s)",
    )
    args = parser.parse_args(argv)

    result = check_sync(args.pipeline, args.test_command)
    print(result.describe())
    return 0 if result.in_sync else 1


if __name__ == "__main__":
    sys.exit(main())
