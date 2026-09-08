# Omarchy Quake Panel

A Quickshell (QML) kiosk UI + Node.js HID daemon for driving a **DK-QUAKE / ARIS-68**
panel — a 1920×480 touchscreen-plus-knob device — on Omarchy Linux (Hyprland/Wayland).

Sibling project to [Bedrock Panel](https://github.com/TeeJS/bedrock-panel), which drives
the same hardware on Windows via Electron. This repo is a from-scratch Linux-native build,
not a port of that app — it reuses only the reverse-engineered HID protocol driver.

**Status: real kiosk shell running on hardware, 2 of 3 pages.** See `HISTORY.md` for the
full build history and hard-won fixes, and `NEXT_STEPS.md` for pending work. Confirmed
working end-to-end: the HID bridge daemon, a virtual `/dev/uinput` touchscreen, and the
Quickshell kiosk shell with a knob-driven page switcher, a system dashboard, and a
personal-care page (pomodoro, water in ml, stand reminders) — all styled to match
Omarchy's own design system and persisted to disk. **The Home Assistant page is on
hold** — embedding a `WebEngineView` inside Quickshell crashes hard (see
`shell/Pages/HomeAssistantPage.qml`'s header comment); it needs a different approach (an
external kiosk browser window this shell yields to) before it can come back. Not yet
built: reading `config/config.example.json` into the running app (thresholds are
currently hardcoded in `PersonalCareState.qml`) and systemd autostart units.

## Repo layout

| Path | What it is |
|---|---|
| `daemon/` | Node.js process that talks to the panel over USB HID and exposes it as JSON-lines-over-stdio |
| `shell/` | Quickshell/QML kiosk UI — the layer-shell window, pages, services, and shared UI components |
| `ops/` | udev rules, `modules-load.d` config, and validated Hyprland config examples from the real build machine |
| `config/` | `config.example.json` — the shape a future config-file loader will read (not wired up yet, see above) |
| `.claude/skills/omarchy-design/` | a project-scoped Claude Code skill that verifies Omarchy's real design tokens from installed source before any styling change |
| `HISTORY.md` | development log — why each odd architectural choice exists, in the order it was made |
| `NEXT_STEPS.md` | the actionable pending-work list |
| `LICENSE`, `daemon/LICENSE`, `NOTICE` | split MIT / PolyForm Noncommercial licensing — see below |

## How it works

### `daemon/` — the HID bridge

A small Node.js process (`daemon/src/bridge.js`) that opens the panel's USB HID
interfaces via a ported `Aris68Connector.js` and prints one JSON event per line to
stdout, accepting JSON commands on stdin. It also owns a virtual `/dev/uinput`
touchscreen device (`uinputTouch.js`) — a real kernel input device other Wayland clients
can see (confirmed: it can switch focus between two real windows via touch) — though our
own Quickshell UI doesn't rely on it for its own buttons; see "Two touch paths" below.

**stdout** — one JSON object per line:

```jsonc
{"t":"touch","points":[{"action":1,"x":812,"y":301}]}
{"t":"knob","event":{"type":"rotate","dir":1}}
{"t":"knob","event":{"type":"press","index":1}}
{"t":"knob","event":{"type":"hold","phase":"start"}}
{"t":"state","state":{"firmware":"1.0.19"}}
{"t":"connect","iface":"control"} | {"t":"disconnect","iface":"touch"}
{"t":"error","message":"..."}
```

**stdin** — one JSON command per line:

```jsonc
{"cmd":"screenOn"} | {"cmd":"screenOff"} | {"cmd":"ping"}
{"cmd":"queryFirmware"} | {"cmd":"queryMic"} | {"cmd":"queryLuminance"}
{"cmd":"setMic","on":true} | {"cmd":"buzzer","tone":100} | {"cmd":"setKnobLed","on":true}
{"cmd":"setLedBrightness","value":200} | {"cmd":"setLedEffect","index":3}
{"cmd":"setLedSpeed","value":128} | {"cmd":"setLedColor","hue":128,"sat":255}
{"cmd":"saveLighting"} | {"cmd":"getLighting"}
```

`enterDfu` is intentionally **not** wired to a command — sending it puts the device into
firmware-flash mode and can brick it (see `Aris68Connector.js`'s own warning).

The full reverse-engineered HID protocol (interfaces, frame format, opcodes, checksums,
touch/knob/RGB-ring semantics, validated hex frames) is documented upstream in
[Bedrock Panel's `docs/DEVICE_PROTOCOL.md`](https://github.com/TeeJS/bedrock-panel/blob/main/docs/DEVICE_PROTOCOL.md)
— `daemon/docs/DEVICE_PROTOCOL.md` here just points to it rather than forking a copy that
could drift. `Aris68Connector.js` is a straight port of that project's driver, adapted
for Linux/`uinput` instead of Windows/Electron.

### `shell/` — the Quickshell kiosk UI

A single fullscreen Wayland layer-shell window (`shell/shell.qml`) pinned to the panel's
output, built from:

- **`Services/HidBridge.qml`** — spawns the daemon as a `Process` and parses its
  JSON-lines stdout into Qt signals.
- **`Services/KnobRouter.qml`** — the per-page knob gesture table (the QML analog of
  Bedrock Panel's `effectiveKnob`): rotate switches pages, hold opens the water-amount
  picker from any page, press does whatever the active page defines (e.g. pomodoro
  toggle). The water picker temporarily takes over rotate/press while it's open.
- **`Services/TouchRouter.qml`** — drives this app's own on-screen buttons directly from
  the daemon's raw touch JSON, bypassing Wayland's touch path entirely (see below for
  why). Any tappable element registers itself here; a plain `TapHandler` alone renders
  fine but never receives real touch on the physical panel.
- **`Services/SystemStats.qml`** — polls `/proc` for CPU/RAM/network and keeps rolling
  history buffers for the Dashboard's sparklines.
- **`Services/PersonalCareState.qml`** — pomodoro/water/stand state and timers,
  persisted as JSON to `~/.local/state/omarchy-quake-panel/personal-care.json`.
- **`Services/Theme.qml`** — this project's `Color.qml` + `Style.qml` equivalent: reads
  the live Omarchy theme (`~/.local/state/omarchy/current/theme/colors.toml`, polled
  every 3s since file-watching doesn't fire for it), follows the same `"monospace"`
  fontconfig alias Omarchy's own shell binds to, and exposes verified Omarchy tokens
  (alpha-blended borders/separators at two different strengths, darkened-foreground
  secondary text, state fills) scaled up 1.5× for arm's-length kiosk viewing.
- **`Pages/DashboardPage.qml`** — CPU/RAM/network, each with a hero percentage, a
  btop-style history sparkline, and (CPU) a per-core load bar grid.
- **`Pages/PersonalCarePage.qml`** — pomodoro, water (tracked in **ml**, not "glasses"),
  and stand reminders, laid out as one combined card with three sections across the
  panel's full width.
- **`Pages/HomeAssistantPage.qml`** — not wired into the page rotation; see Status above.
- **`Ui/`** — shared components consumed by both pages: `Card`, `SectionLabel`,
  `SectionSeparator`, `PanelButton` (a touch button that registers itself with
  `TouchRouter`), `PageHeader` (the hero title/status/clock/page-indicator bar),
  `PageHost` (owns the header and swaps pages via `KnobRouter.currentPageIndex`),
  `Sparkline` (a `Canvas`-based history graph), `ToastOverlay` (reminder banners, with no
  knob wiring at all so it can never steal a gesture), and `WaterAmountPicker` (the
  knob/touch-drivable "how much water?" popup).

Run it directly for development:

```sh
quickshell -p shell/shell.qml
```

### Two touch paths — and why our own UI uses the unusual one

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
real kernel input), the fix was to stop depending on the broken path for our own UI:
`TouchRouter.qml` feeds the daemon's raw touch JSON directly into a small QML hit-tester
that drives our registered buttons, bypassing Wayland/Hyprland entirely. The knob was
never in that pipeline either — it's a deliberate JSON event stream `KnobRouter`
interprets itself, since page-dependent semantics (rotate=page-switch, hold=water,
press=varies) aren't something a generic input device concept fits anyway.

### `ops/` — system integration

- **`ops/udev/99-omarchy-quake-panel.rules`** — grants the `input` group read/write
  access to the panel's HID interfaces and to `/dev/uinput`, using `GROUP`/`MODE` rather
  than `TAG+="uaccess"` (the uaccess/logind seat-ACL mechanism did not actually grant
  access on the build machine — confirmed via `getfacl`). Requires the user to be in the
  `input` group and to fully log out/in afterward (group membership is read at login).
- **`ops/modules-load/omarchy-quake-panel.conf`** — autoloads the `uinput` kernel module
  at boot (drop into `/etc/modules-load.d/`).
- **`ops/hyprland/monitors.example.lua`** / **`input.example.lua`** — real, validated
  copies of the Hyprland config applied on the build machine: the monitor block that
  places and rotates the panel's output (matched by `desc:`, not port name, since port
  names can change on replug), and the touch-device-to-output binding (matched by device
  *name*, with `transform = 0` even though the monitor itself is rotated — the virtual
  device already emits pre-rotated coordinates, so reapplying the monitor's transform
  would double-rotate it). Both files document the exact confirmed-correct values and the
  reasoning, not just a template — your own transform/position may differ depending on
  how the panel is physically mounted.

### `config/config.example.json`

The shape a future config loader will read into `PersonalCareState.qml` and the Home
Assistant page: pomodoro/water/stand thresholds, the Home Assistant URL/token, and the
panel's Hyprland output description. Not wired up yet — see `NEXT_STEPS.md`.

### `.claude/skills/omarchy-design/`

A project-scoped Claude Code skill for keeping this app's styling honest to Omarchy's
actual design system rather than guessing. It verifies color roles, spacing/typography
scale, the two-strength alpha-blended border/separator convention, and icon conventions
directly from the installed `/usr/share/omarchy/shell/` source (primarily the Wi-Fi and
bluetooth panels), and includes a driver script (`scripts/capture-panel.sh`) that
restarts the kiosk shell and captures a real screenshot from the physical panel output —
there is no headless render path for this app.

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

See `HISTORY.md` for the full list of hard-won bugs and fixes across the whole project,
including the Hyprland-bar-overlap fix, the pomodoro pause/resume bug, and the styling
corrections made while building the `omarchy-design` skill.

## Try the daemon today

```sh
cd daemon
npm install
node src/bridge.js
```

With the panel plugged in, udev rules from `ops/udev/` installed (and your user in the
`input` group — see above), you'll see decoded JSON lines as you touch/turn/press the
panel, and a real touchscreen input device will appear (`hyprctl devices`, or
`/proc/bus/input/devices`) that Hyprland/libinput treat as genuine touch input. Send
commands via stdin, e.g.:

```sh
echo '{"cmd":"queryFirmware"}' | node src/bridge.js
```

To run the full kiosk shell (pins to the panel's output, spawns the daemon itself):

```sh
quickshell -p shell/shell.qml
```

## Licensing

Split-licensed — see [`NOTICE`](NOTICE) for the full reasoning:

- **MIT** ([LICENSE](LICENSE)) — everything except the two files below: `shell/` in
  full, `daemon/src/bridge.js` (the daemon's own CLI/IPC orchestration — it encodes no
  device protocol itself), `ops/`, `config/`, and all other original work in this repo.
- **PolyForm Noncommercial 1.0.0** ([daemon/LICENSE](daemon/LICENSE)) —
  `daemon/src/Aris68Connector.js` and `daemon/src/uinputTouch.js`, which embed the
  reverse-engineered DK-QUAKE / ARIS-68 protocol (ported from
  [Bedrock Panel](https://github.com/TeeJS/bedrock-panel)). The vendor described that
  protocol as restricted for commercial use — these two files are **non-commercial use
  only**. No vendor source code, binaries, or API keys are included in this repository.
