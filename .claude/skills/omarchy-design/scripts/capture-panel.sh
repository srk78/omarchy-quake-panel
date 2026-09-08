#!/usr/bin/env bash
# capture-panel.sh — restart the kiosk shell and capture a screenshot of the real
# DK-QUAKE panel output. This is the verification "driver" for styling work: there is
# no headless/simulated rendering path for this app — it only makes sense running
# against the real Quickshell instance on the real panel output, so every visual review
# in this skill goes through this script.
#
# Usage (run from the omarchy-quake-panel repo root):
#   .claude/skills/omarchy-design/scripts/capture-panel.sh [output.png]
#
# Requires: the DK-QUAKE panel physically connected and configured in
# ~/.config/hypr/monitors.lua (see project README). Override PANEL_DESC_MATCH if
# your panel's Hyprland `description` doesn't contain "DK-QUAKE".
#
# To capture a specific page without touching the knob, set OQP_START_PAGE=<index>
# (0 = Dashboard, 1 = Self Care) — shell.qml reads it once at startup, dev-only:
#   OQP_START_PAGE=1 .claude/skills/omarchy-design/scripts/capture-panel.sh out.png
#
# The launched quickshell is fully detached (setsid, stdin/stdout/stderr off the caller's
# pipes) so a harness waiting on this script's output can't block until the shell exits.
set -euo pipefail

ROOT="$(pwd)"
if [ ! -f "$ROOT/shell/shell.qml" ]; then
  echo "Run this from the omarchy-quake-panel repo root (shell/shell.qml not found under $ROOT)" >&2
  exit 1
fi

OUT="${1:-/tmp/omarchy-quake-panel-capture-$(date +%s).png}"
PANEL_DESC_MATCH="${PANEL_DESC_MATCH:-DK-QUAKE}"

# 1. Resolve the panel's exact geometry from Hyprland. grim wants POST-transform
# (logical/on-screen) width x height; hyprctl's JSON reports the PRE-transform mode, so
# swap width/height when the output is rotated 90 or 270 degrees (odd transform value)
# — confirmed necessary live for this panel (native mode is portrait, shown landscape).
GEOM="$(hyprctl monitors -j | python3 -c "
import json, sys, os
data = json.load(sys.stdin)
match = os.environ.get('PANEL_DESC_MATCH', 'DK-QUAKE')
for m in data:
    if match in m.get('description', ''):
        w, h = m['width'], m['height']
        if m.get('transform', 0) % 2 == 1:
            w, h = h, w
        print(f\"{m['x']},{m['y']} {w}x{h}\")
        break
")"

if [ -z "$GEOM" ]; then
  echo "No connected monitor matched description containing '$PANEL_DESC_MATCH'." >&2
  echo "Run 'hyprctl monitors' to see connected outputs, or set PANEL_DESC_MATCH." >&2
  exit 1
fi
echo "Panel geometry: $GEOM"

# 2. Stop any existing instance of OUR shell/daemon — never touch Omarchy's own
# `omarchy-shell` (pgrep pattern is scoped to this project's exact paths so it can't
# match that). Kill by PID from a completed pgrep, never a live `pkill -f <pattern>`:
# the harness that runs shell scripts does so as one literal string, and a pkill whose
# pattern also appears in that same string can match and kill its own invoking shell —
# confirmed live during this project's development (see project memory/README).
mapfile -t PIDS < <(pgrep -f "quickshell -p .*shell/shell\.qml" || true)
mapfile -t DAEMON_PIDS < <(pgrep -f "node .*daemon/src/bridge\.js" || true)
ALL_PIDS=("${PIDS[@]:-}" "${DAEMON_PIDS[@]:-}")
if [ "${#PIDS[@]}" -gt 0 ] || [ "${#DAEMON_PIDS[@]}" -gt 0 ]; then
  echo "Stopping existing instance(s): ${PIDS[*]:-} ${DAEMON_PIDS[*]:-}"
  kill -TERM "${PIDS[@]}" "${DAEMON_PIDS[@]}" 2>/dev/null || true
  sleep 2
fi

# 3. Lint before launching — catches QML errors before they crash the shell on start.
( cd "$ROOT/shell" && qmllint shell.qml Services/*.qml Ui/*.qml Pages/*.qml )

# 4. Launch fresh, detached from this script's own process group.
( cd "$ROOT" && setsid nohup quickshell -p shell/shell.qml >/tmp/omarchy-quake-panel-shell.log 2>&1 </dev/null & disown )
sleep 5

if ! pgrep -f "quickshell -p .*shell/shell\.qml" >/dev/null; then
  echo "quickshell did not stay running — check /tmp/omarchy-quake-panel-shell.log" >&2
  tail -n 20 /tmp/omarchy-quake-panel-shell.log >&2 || true
  exit 1
fi

# 5. Capture.
grim -g "$GEOM" "$OUT"
echo "Captured: $OUT"
