-- Omarchy Quake Panel — reference copy of the monitor block already applied to this
-- machine's ~/.config/hypr/monitors.lua. Kept here so the repo documents the real,
-- validated config rather than a guess. See also ops/hyprland/input.example.lua for the
-- touch-device-to-output binding (a separate concern, applied in ~/.config/hypr/input.lua
-- on the real system).
--
-- Confirmed on real hardware (2026-09-08):
--   description: "BOE DK-QUAKE" (enumerates as DP-1 here, but port names can change on
--   replug — always match by `desc:`, never by port name)
--   availableModes: 480x1920@60.00Hz, 400x1280@60.82Hz  <- PORTRAIT ONLY, no landscape mode
--   transform=1 (90 CW) rendered UPSIDE DOWN on this unit's physical mounting;
--   transform=3 (270 CW / 90 CCW) is the confirmed-correct orientation.
-- Your own transform may differ depending on how the panel is physically mounted —
-- verify by looking at the panel after `hyprctl reload`, same as we did here.

hl.monitor({
  output = "desc:BOE DK-QUAKE",
  mode = "480x1920@60",     -- native mode; transform below rotates it to landscape
  position = "3000x0",      -- adjust to your own monitor layout
  scale = 1,
  transform = 3,            -- confirmed correct orientation on this hardware
})

-- NOTE: the Quickshell kiosk window itself needs NO window-rule pin here. shell/shell.qml's
-- PanelWindow is a Wayland layer-shell surface, which attaches directly to its assigned
-- output via the Wayland protocol and bypasses Hyprland's window-rule/workspace placement
-- entirely. Window rules would only become relevant again if a future Quickshell version
-- renders the kiosk as a regular toplevel window instead.
