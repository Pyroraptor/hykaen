#!/usr/bin/env bash
# ci/check_no_duplicate_seams.sh — FEAT-009 (US-009; NFR-001, NFR-002,
# NFR-006, NFR-007; ADR-002, ADR-006)
#
# Standalone, independently-invokable CI gate proving ADR-002/ADR-006's "no
# new/duplicate seam" guarantee holds structurally, not just by trust:
#
#   1. Exactly ONE _movement_used gate implementation exists — the per-turn
#      Movement-trait lockout flag core/rules/action_economy.gd owns
#      (mark_movement_used() / can_take_movement_action()), the SAME gate
#      core/rules/movement.gd's step()/stride() and core/combat/ai.gd's
#      AI-issued Stride path all trip through. A second, independently
#      declared `_movement_used` flag anywhere else would mean two gates
#      could silently disagree — this check fails the build the moment
#      that happens.
#
#   2. Exactly ONE concrete AI decision call path exists —
#      core/combat/ai.gd's decide_action() is the single production
#      implementation RoundSession drives via AIDecisionPort
#      (core/application/ai_decision_port.gd). That port file's own
#      decide_action() is a deliberately abstract stub (documented
#      contract only — it push_error()s and returns a no-op decision; see
#      its file header) and is excluded here by name, exactly as this
#      project's existing ADR-002 RNG lint already excludes
#      core/rules/rng.gd by name (.github/workflows/test.yml, "Lint —
#      injected RNG"). A second CONCRETE decide_action() anywhere else
#      would be a duplicate AI decision path and fails this check.
#
#   3. Exactly ONE token-reposition function exists —
#      presentation/hex_grid_view.gd's move_token() is the single
#      implementation both the player-driven Stride path
#      (presentation/movement_input_controller.gd) and the AI-driven
#      Stride path (core/application/round_session.gd's
#      _reposition_token_after_ai_stride(), via the injected
#      _token_reposition_fn Callable) call — never a second, independently
#      implemented repositioning function.
#
#   4. core/domain/effects_applier.gd's EffectsApplier is the sole
#      (non-legacy) call site of each Combatant combat-state mutator —
#      take_damage()/heal()/add_condition()/move_to()
#      (core/domain/combatant.gd) — FEAT-002 (US-002, ADR-002/ADR-006).
#      This is "the single reusable seam the steel thread routes all
#      mutation through": any NEW file calling one of these four methods
#      outside EffectsApplier fails this check. A small, EXPLICIT set of
#      pre-existing call sites is excluded per method (never a blanket
#      exemption) because migrating them is out of this feature's scope:
#        - take_damage(): core/application/resolve_action_use_case.gd and
#          core/application/apply_on_hit_defense_uc.gd still inline-mutate
#          HP directly, pending a later retrofit (design notes' US-004/
#          US-005) that reroutes their damage through a constructed
#          DamageEffect + EffectsApplier.apply() instead.
#        - move_to(): core/rules/movement.gd is a DIFFERENT, permanent
#          seam (the Movement rule layer driving Step/Stride, FEAT-013) —
#          not an Effect-dispatch path, so it is not itself a duplicate of
#          EffectsApplier's seam.
#      heal()/add_condition() have no legacy exclusions (no pre-existing
#      caller exists). A file mentioning e.g. "Combatant.heal()" only in a
#      `##` doc-comment line is not a call site and must never be flagged
#      — the scan below filters out comment-only lines before counting.
#
#   5. core/application/use_cases/effects_applier_use_case.gd's
#      EffectsApplierUseCase (FEAT-002/US-002 application-layer wrapper
#      around EffectsApplier, ADR-002/ADR-005) never itself calls a
#      Combatant mutator directly — it validates each effect, then
#      delegates the actual mutation to the SAME EffectsApplier instance
#      checked by #4 above. This keeps check #4's "exactly one call site"
#      guarantee true even though the application layer now has its own
#      DTO-returning entry point: a regression that made
#      EffectsApplierUseCase re-implement dispatch itself (instead of
#      delegating) would silently create a second seam, since #4 only
#      scans for the sole call site being EffectsApplier itself — this
#      check fails the build the moment that happens.
#
# Usage:
#   ci/check_no_duplicate_seams.sh [repo_root]
#
#   repo_root defaults to this script's own repository (resolved from its
#   own path) so it can be run from anywhere. Tests pass an explicit
#   fixture repo root to prove the check can detect an injected duplicate
#   without ever mutating the real tree.
#
# Exit code: 0 when all three seams are singular; non-zero (with a
# diagnostic naming which seam duplicated, and every offending file) when
# any of them is not.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [ ! -d "$REPO_ROOT" ]; then
    echo "ERROR: check_no_duplicate_seams.sh: repo root '$REPO_ROOT' does not exist" >&2
    exit 1
fi

cd "$REPO_ROOT"

# Source-of-truth directories only — never tests/ or addons/ (test doubles
# and fixtures legitimately declare their own decide_action()/move_token()
# stand-ins and must not be counted as production duplicates).
SCAN_DIRS=(core presentation infrastructure)

EXISTING_SCAN_DIRS=()
for d in "${SCAN_DIRS[@]}"; do
    if [ -d "$d" ]; then
        EXISTING_SCAN_DIRS+=("$d")
    fi
done

if [ "${#EXISTING_SCAN_DIRS[@]}" -eq 0 ]; then
    echo "ERROR: check_no_duplicate_seams.sh: none of ${SCAN_DIRS[*]} exist under $REPO_ROOT" >&2
    exit 1
fi

FAILURES=0

# check_seam_sole_caller(method_name, legacy_caller...) — prints OK/ERROR
# and returns 0/1. Finds every *.gd file under EXISTING_SCAN_DIRS with a
# genuine `.method_name(` CALL (comment-only lines, e.g. a `##` doc-comment
# mentioning "Combatant.heal()", are filtered out first — see the ":##"
# pattern below, which matches a line-number/content separator directly
# followed by "##"), excludes core/domain/effects_applier.gd's own file
# together with any explicitly named `legacy_caller` paths (see check #4's
# header comment for why each named exclusion exists), and fails unless
# what's left is empty (no other caller exists yet) — a genuinely new/
# rogue call site outside EffectsApplier and the documented legacy list is
# what this guards against.
check_seam_sole_caller() {
    local method_name="$1"
    shift
    local legacy_callers=("$@")

    local hits
    hits="$(grep -rn "\.${method_name}(" --include="*.gd" "${EXISTING_SCAN_DIRS[@]}" 2>/dev/null \
        | grep -vE ':[[:space:]]*##' || true)"

    local caller_files=""
    if [ -n "$hits" ]; then
        caller_files="$(printf '%s\n' "$hits" | sed -E 's/^([^:]+):.*/\1/' | sort -u)"
    fi

    local remaining=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if [ "$f" = "core/domain/effects_applier.gd" ]; then
            continue
        fi
        local is_legacy=0
        for legacy in "${legacy_callers[@]}"; do
            if [ "$f" = "$legacy" ]; then
                is_legacy=1
                break
            fi
        done
        if [ "$is_legacy" -eq 0 ]; then
            remaining+=("$f")
        fi
    done <<< "$caller_files"

    if [ "${#remaining[@]}" -eq 0 ]; then
        echo "OK: no rogue call site of '${method_name}' found outside EffectsApplier/documented legacy callers (ADR-002/ADR-006, FEAT-002/US-002)"
        return 0
    fi

    echo "ERROR: found a call site of '${method_name}' outside core/domain/effects_applier.gd and the documented legacy callers:" >&2
    printf '%s\n' "${remaining[@]}" >&2
    return 1
}

# ── 1. Exactly one _movement_used gate implementation ──────────────────────
MOVEMENT_HITS="$(grep -rn "var _movement_used" --include="*.gd" "${EXISTING_SCAN_DIRS[@]}" 2>/dev/null || true)"
MOVEMENT_COUNT=0
if [ -n "$MOVEMENT_HITS" ]; then
    MOVEMENT_COUNT=$(printf '%s\n' "$MOVEMENT_HITS" | grep -c .)
fi

if [ "$MOVEMENT_COUNT" -eq 1 ]; then
    echo "OK: exactly one _movement_used gate implementation found (ADR-002/ADR-006)"
else
    echo "ERROR: expected exactly one '_movement_used' gate declaration, found $MOVEMENT_COUNT:" >&2
    echo "$MOVEMENT_HITS" >&2
    FAILURES=$((FAILURES + 1))
fi

# ── 2. Exactly one concrete AI decision (decide_action) call path ──────────
# The abstract Protocol stub (ai_decision_port.gd) documents the contract
# but never decides anything itself — excluded by name, mirroring this
# project's existing --exclude="rng.gd" ADR-002 lint convention.
DECIDE_ACTION_HITS="$(grep -rln "func decide_action(" --include="*.gd" "${EXISTING_SCAN_DIRS[@]}" 2>/dev/null \
    | grep -v -- '/ai_decision_port\.gd$' || true)"
DECIDE_ACTION_COUNT=0
if [ -n "$DECIDE_ACTION_HITS" ]; then
    DECIDE_ACTION_COUNT=$(printf '%s\n' "$DECIDE_ACTION_HITS" | grep -c .)
fi

if [ "$DECIDE_ACTION_COUNT" -eq 1 ]; then
    echo "OK: exactly one concrete AI decision (decide_action) call path found (ADR-002/ADR-006)"
else
    echo "ERROR: expected exactly one concrete 'decide_action' implementation (excluding the abstract ai_decision_port.gd stub), found $DECIDE_ACTION_COUNT:" >&2
    echo "$DECIDE_ACTION_HITS" >&2
    FAILURES=$((FAILURES + 1))
fi

# ── 3. Exactly one token-reposition call path (move_token) ─────────────────
MOVE_TOKEN_HITS="$(grep -rln "func move_token(" --include="*.gd" "${EXISTING_SCAN_DIRS[@]}" 2>/dev/null || true)"
MOVE_TOKEN_COUNT=0
if [ -n "$MOVE_TOKEN_HITS" ]; then
    MOVE_TOKEN_COUNT=$(printf '%s\n' "$MOVE_TOKEN_HITS" | grep -c .)
fi

if [ "$MOVE_TOKEN_COUNT" -eq 1 ]; then
    echo "OK: exactly one token-reposition (move_token) call path found (ADR-002/ADR-006)"
else
    echo "ERROR: expected exactly one 'move_token' implementation, found $MOVE_TOKEN_COUNT:" >&2
    echo "$MOVE_TOKEN_HITS" >&2
    FAILURES=$((FAILURES + 1))
fi

# ── 4. EffectsApplier is the sole (non-legacy) call site of each Combatant
#      mutator: take_damage/heal/add_condition/move_to ─────────────────────
if ! check_seam_sole_caller "take_damage" \
    "core/application/resolve_action_use_case.gd" \
    "core/application/apply_on_hit_defense_uc.gd"; then
    FAILURES=$((FAILURES + 1))
fi

if ! check_seam_sole_caller "heal"; then
    FAILURES=$((FAILURES + 1))
fi

if ! check_seam_sole_caller "add_condition"; then
    FAILURES=$((FAILURES + 1))
fi

if ! check_seam_sole_caller "move_to" \
    "core/rules/movement.gd"; then
    FAILURES=$((FAILURES + 1))
fi

# ── 5. EffectsApplierUseCase (application layer) must delegate, never
#      re-dispatch a Combatant mutator itself ────────────────────────────────
EFFECTS_APPLIER_USE_CASE_FILE="core/application/use_cases/effects_applier_use_case.gd"
if [ -f "$EFFECTS_APPLIER_USE_CASE_FILE" ]; then
    UC_DIRECT_CALLS="$(grep -nE '\.(take_damage|heal|add_condition|remove_condition|move_to)\(' "$EFFECTS_APPLIER_USE_CASE_FILE" 2>/dev/null \
        | grep -vE ':[[:space:]]*##' || true)"

    if [ -n "$UC_DIRECT_CALLS" ]; then
        echo "ERROR: $EFFECTS_APPLIER_USE_CASE_FILE must delegate to EffectsApplier (core/domain/effects_applier.gd) rather than calling a Combatant mutator directly:" >&2
        echo "$UC_DIRECT_CALLS" >&2
        FAILURES=$((FAILURES + 1))
    else
        echo "OK: EffectsApplierUseCase contains no direct Combatant-mutator call sites -- delegates to the sole EffectsApplier seam (ADR-002/ADR-005, FEAT-002/US-002)"
    fi
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "check_no_duplicate_seams.sh: $FAILURES seam(s) failed the no-duplicate check" >&2
    exit 1
fi

echo "check_no_duplicate_seams.sh: all seams singular — no duplicate ports/use-cases/gates detected"
exit 0
