# Omarchy Quake Panel

A Quickshell (QML) kiosk UI + Node.js HID daemon for driving a **DK-QUAKE / ARIS-68**
panel — a 1920×480 touchscreen-plus-knob device — on Omarchy Linux (Hyprland/Wayland).

Sibling project to [Bedrock Panel](https://github.com/TeeJS/bedrock-panel), which drives
the same hardware on Windows via Electron. This repo is a from-scratch Linux-native build,
not a port of that app — it reuses only the reverse-engineered HID protocol driver.

**Status: real kiosk shell running on hardware, 2 of 3 pages.** See `HISTORY.md` for the
architecture, build order, and hard-won fixes, and `NEXT_STEPS.md` for pending work. Confirmed
working end-to-end: the HID bridge daemon (`daemon/`), a virtual `/dev/uinput` touchscreen,
and the Quickshell kiosk shell (`shell/shell.qml`) with a knob-driven `KnobRouter`, a
system dashboard page, and a personal-care page — pomodoro (with correct pause/resume),
water tracked in **ml** via a knob-and-touch-drivable amount picker, and a stand reminder
— all with persisted state. Touch on our own on-screen buttons works via a custom
`TouchRouter`, **not** the virtual touchscreen (see below for why). **The Home Assistant
page is on hold** — embedding a `WebEngineView` inside Quickshell crashes hard (see
`shell/Pages/HomeAssistantPage.qml`'s header comment); it needs a different approach (an
external kiosk browser window our shell yields to) before it can come back. Not yet built:
`config.json` wiring (thresholds are hardcoded in `PersonalCareState.qml`), systemd
autostart units.

## How it works

- **`daemon/`** — a small Node.js process (`daemon/src/bridge.js`) that opens the panel's
  two USB HID interfaces (via a ported `Aris68Connector.js`) and prints one JSON event per
  line to stdout (`touch`, `knob`, `state`, `connect`/`disconnect`, `error`); accepts JSON
  commands on stdin (screen on/off, RGB ring control, etc). It also owns a virtual
  `/dev/uinput` touchscreen device (`uinputTouch.js`) — a real kernel input device other
  Wayland clients see (confirmed: it can switch focus between two real windows via touch),
  though our own Quickshell UI doesn't rely on it — see "Two touch paths" below.
- **`shell/`** — the Quickshell/QML kiosk UI: a layer-shell window pinned to the panel's
  output, `HidBridge` (parses the daemon's JSON), `KnobRouter` (per-page knob gestures),
  `TouchRouter` (drives our own buttons directly from raw touch JSON), `SystemStats` and
  `PersonalCareState` (the two pages' data/logic), and `ToastOverlay`/`WaterAmountPicker`
  as global overlays.
- **`ops/`** — udev rules (HID + uinput permissions, `GROUP`-based — see below),
  `modules-load.d` config (autoload `uinput` at boot), and real, validated Hyprland config
  examples (`monitors.example.lua`, `input.example.lua`) mirroring what's actually applied
  on the machine this was built on.

## Two touch paths — and why our own UI uses the unusual one

The panel's touchscreen reports over a **vendor-defined HID usage page** (`0xFF73`), not
the standard Digitizer/Touchscreen usage — so it never shows up as a real input device to
the OS on its own. `uinputTouch.js` fixes that in general by re-emitting the daemon's
parsed reports as a genuine kernel touch device via `/dev/uinput`.

That would normally be the end of it — except **Hyprland has a confirmed, unresolved
upstream bug**: a Wayland layer-shell surface (what every Quickshell `PanelWindow` is)
never receives `wl_touch` events unless the mouse cursor happens to already be on the same
output ([hyprwm/Hyprland#12221](https://github.com/hyprwm/Hyprland/discussions/12221)).
Reproduced live here: a plain `TapHandler` on our own window never fired for real touch,
while a mouse click on the exact same spot fired instantly — yet the *same* virtual touch
device correctly drove touch-to-focus-switch on two ordinary (non-layer-shell) terminal
windows. So kernel-level touch is fine; it's specifically our own layer-shell surface that
Hyprland won't route it to.

Since this build no longer needs `WebEngineView` (the one thing that would have required
real kernel input — see below), the fix was to stop depending on the broken path for our
own UI: `TouchRouter.qml` feeds the daemon's raw touch JSON directly into a small QML
hit-tester that drives our registered buttons, bypassing Wayland/Hyprland entirely. The
knob was never in that pipeline either — it's a deliberate JSON event stream `KnobRouter`
interprets itself, since page-dependent semantics (rotate=page-switch, hold=water,
press=varies) aren't something a generic input device concept fits anyway.

## Hard-won `uinput` lessons (read before touching `uinputTouch.js`)

- **This panel's touch interface never sends an explicit "up"/release report** — only
  repeated "down" frames while held, then silence. The only real release mechanism is a
  timeout (no refresh for `STALE_MS`) plus an immediate release when a new, distant touch
  appears. `TouchRouter.qml`'s own debouncing mirrors this same timeout.
- **A release and the press that follows it must be flushed as separate `SYN_REPORT` sync
  frames.** Bundling them into one frame is what caused "switching between two spots works
  exactly once, then never again" — libinput didn't track it as two distinct contacts.
- **Declare the virtual device as pure MT-B protocol only** (`ABS_MT_*` +
  `INPUT_PROP_DIRECT`) — never add `EV_KEY`/`BTN_TOUCH` or legacy single-touch `ABS_X`/
  `ABS_Y`. Doing so once made libinput treat it as a generic pointer, and a missed release
  looked exactly like **a mouse button stuck down system-wide** — text selection broke on
  the *entire* desktop, not just the panel, and needed a full logout/login to clear.
- Bind the virtual device to the panel's Hyprland output **by device name**
  (`hl.device({name=...})`), not the global `input.touchdevice.output` — otherwise touches
  land on whatever your primary/laptop screen is. Use **`transform = 0`** on that binding
  even if the monitor itself uses a non-zero transform: the virtual device already emits
  coordinates pre-rotated to match the final view, so re-applying the monitor's transform
  double-rotates it.

## Try the daemon today

```sh
cd daemon
npm install
node src/bridge.js
```

With the panel plugged in, udev rules from `ops/udev/` installed (and your user in the
`input` group — see below), you'll see decoded JSON lines as you touch/turn/press the
panel, and a real touchscreen input device will appear (`hyprctl devices`, or
`/proc/bus/input/devices`) that Hyprland/libinput treat as genuine touch input. Send
commands via stdin, e.g.:

```sh
echo '{"cmd":"queryFirmware"}' | node src/bridge.js
```

To try the bare Quickshell debug window (pins to the panel's output and dumps live daemon
events on-screen):

```sh
quickshell -p shell/shell.qml
```

## Licensing

Split-licensed — see [`NOTICE`](NOTICE):
- **MIT** ([LICENSE](LICENSE)) — everything except the two files below.
- **PolyForm Noncommercial 1.0.0** ([daemon/LICENSE](daemon/LICENSE)) — `daemon/src/Aris68Connector.js`
  and `daemon/src/uinputTouch.js`, which embed the reverse-engineered DK-QUAKE / ARIS-68
  protocol (ported from [Bedrock Panel](https://github.com/TeeJS/bedrock-panel)). The
  vendor described that protocol as restricted for commercial use — these two files are
  **non-commercial use only**.
