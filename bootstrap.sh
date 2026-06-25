#!/usr/bin/env bash
# bootstrap.sh — disentangle the Hykaen game from the aef checkout.
#
# WHY
#   This 'hykaen' folder currently lives *inside* an aef checkout. The
#   AEF launch harness (run-claude.sh) expects each project to be its
#   OWN directory: the project dir is mounted to /workspace, and a
#   SIBLING 'aef' directory is mounted read-only to /aef. This script
#   promotes 'hykaen' to a top-level sibling of the aef checkout and
#   copies in the launch harness so you can run the agent against the
#   game in isolation.
#
#   Resulting host layout:
#       <parent>/
#         aef/          -> mounted read-only to /aef   (framework)
#         hykaen/       -> mounted to /workspace        (this game)
#
# RUN THIS ON THE HOST — not inside the container.
#       cd <aef-checkout>/hykaen
#       ./bootstrap.sh           # prints a plan, asks before doing anything
#       ./bootstrap.sh --yes     # skip the confirmation prompt
#
# Safe to re-run: if already disentangled, it does nothing.

set -euo pipefail

ASSUME_YES=0
[ "${1:-}" = "--yes" ] && ASSUME_YES=1

# Resolve absolute paths up front, so moving ourselves mid-run is safe.
HYKAEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${HYKAEN_DIR}")"   # the aef checkout we live inside
PARENT_DIR="$(dirname "${PROJECT_DIR}")"   # where siblings live
TARGET_DIR="${PARENT_DIR}/hykaen"          # where hykaen should end up
AEF_SIBLING="${PARENT_DIR}/aef"            # what run-claude.sh's ../aef needs
HARNESS_FILES=(run-claude.sh Dockerfile .mise.toml)

say()  { printf '%s\n' "$*"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[33m⚠ %s\033[0m\n' "$*"; }

# --- Guard: are we inside the container? The move can't work there. -------
if [ -f /.dockerenv ] || [ "${PROJECT_DIR}" = "/workspace" ]; then
  die "This looks like INSIDE the container (project is /workspace, whose
   parent is read-only). Run bootstrap.sh on the HOST instead, from the
   aef checkout's hykaen/ folder."
fi

# --- Already done? --------------------------------------------------------
if [ "${HYKAEN_DIR}" = "${TARGET_DIR}" ]; then
  ok "Already a top-level sibling: ${HYKAEN_DIR}"
  ok "Nothing to move."
  exit 0
fi

# --- Refuse to clobber an existing target --------------------------------
[ -e "${TARGET_DIR}" ] && die "${TARGET_DIR} already exists — resolve manually before re-running."

# --- Show the plan --------------------------------------------------------
say ""
say "Plan:"
say "  1. Move   ${HYKAEN_DIR}"
say "       ->   ${TARGET_DIR}"
say "  2. Copy launch harness from ${PROJECT_DIR}:"
for f in "${HARNESS_FILES[@]}"; do say "       - ${f}"; done
say "  3. Ensure an 'aef' sibling exists at ${AEF_SIBLING} (for the /aef mount)"
say ""

if [ "${ASSUME_YES}" -ne 1 ]; then
  read -r -p "Proceed? [y/N] " reply
  case "${reply}" in
    [yY]|[yY][eE][sS]) ;;
    *) die "Aborted — nothing changed." ;;
  esac
fi

# --- 1. Move hykaen up to be a sibling -----------------------------------
mv "${HYKAEN_DIR}" "${TARGET_DIR}"
ok "Moved hykaen to ${TARGET_DIR}"

# --- 2. Copy the launch harness ------------------------------------------
for f in "${HARNESS_FILES[@]}"; do
  if [ -e "${PROJECT_DIR}/${f}" ]; then
    cp -n "${PROJECT_DIR}/${f}" "${TARGET_DIR}/${f}" && ok "copied ${f}"
  else
    warn "harness file not found in source, skipped: ${f}"
  fi
done

# --- 3. Ensure the read-only 'aef' sibling exists ------------------------
if [ -e "${AEF_SIBLING}" ]; then
  ok "Framework sibling present: ${AEF_SIBLING}"
else
  warn "No 'aef' directory at ${AEF_SIBLING}."
  say  "  run-claude.sh mounts ../aef read-only to /aef, so one is required."
  say  "  Linking it to your existing aef checkout:"
  ln -s "${PROJECT_DIR}" "${AEF_SIBLING}"
  ok   "Linked ${AEF_SIBLING} -> ${PROJECT_DIR}"
  say  "  (Prefer a clean copy? Remove the link and clone instead:"
  say  "     rm ${AEF_SIBLING} && git clone git@github.com:veriai-com/aef.git ${AEF_SIBLING})"
fi

# --- Reminder: the harness Dockerfile is inherited from the web project ---
say ""
warn "The copied Dockerfile carries the web project's Chromium/Playwright
   deps. For this Godot project, swap those for Godot headless deps
   (e.g. install the Godot binary + libgl/libx11) before relying on CI."

say ""
ok "Done. Next:"
say "    cd ${TARGET_DIR}"
say "    ./run-claude.sh          # /workspace = the game, /aef = framework (ro)"
