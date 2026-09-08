# Development history

This is a working log of how `omarchy-quake-panel` was built, written so a new session
(in a fresh context window, possibly a different assistant) can pick up work without
re-deriving decisions that were already made and re-litigating problems that are already
solved. It complements `README.md` (current architecture/status) rather than duplicating
it — read that first, this second, for the *why* and the *what was tried and rejected*.

**Nothing in this repo is committed to git yet.** `git status` shows every top-level
entry as untracked on an empty `master` branch. Whoever picks this up next should make an
initial commit before doing anything else that could be lost to an accidental `git clean`
or similar.

## 1. Origin and goal

This is the Linux-native sibling of [Bedrock Panel](https://github.com/TeeJS/bedrock-panel)
(an Electron app, `~/Projects/bedrock-panel`), which drives a DK-QUAKE/ARIS-68
touchscreen-plus-knob panel on Windows. The goal here is the same hardware, driven from
Omarchy Linux (Hyprland/Wayland), via Quickshell/QML instead of Electron — a from-scratch
build that only reuses the reverse-engineered USB HID protocol, not the UI code.

Planned pages, in order: (1) a system dashboard, (2) a Home Assistant dashboard, (3) a
personal-care page (pomodoro + water + stand reminders). The knob was always meant to have
different functions per page (confirmed Bedrock Panel already does this via
`effectiveKnob`, which is why `KnobRouter.qml` here follows the same per-page-mode-table
shape).

## 2. Architecture, and why each odd piece exists

- **`daemon/` (Node.js)** owns all hardware I/O. `Aris68Connector.js` is ported
  near-verbatim from Bedrock Panel's HID driver (pure `node-hid`, EventEmitter-based).
  `bridge.js` is the CLI entry: JSON-lines on stdout (`touch`/`knob`/`key`/`state`/
  `connect`/`disconnect`/`error`), JSON commands on stdin (screen on/off, RGB ring, etc).
- **The panel's touchscreen uses a vendor-defined HID usage page (`0xFF73`)**, so it never
  shows up as a normal OS input device on its own. `uinputTouch.js` fixes that by
  re-emitting parsed touch reports as a real `/dev/uinput` MT-B touch device via `koffi`
  FFI calls to libc `ioctl` (`koffi` was chosen specifically because it ships prebuilt
  binaries — no native compilation step needed).
- **Hyprland has a confirmed, unresolved upstream bug**
  ([hyprwm/Hyprland#12221](https://github.com/hyprwm/Hyprland/discussions/12221)): a
  Wayland layer-shell surface (what every Quickshell `PanelWindow` is) never receives
  `wl_touch` unless the mouse cursor already happens to be on the same output. This was
  reproduced live and root-caused via careful frame analysis: a plain `TapHandler` in our
  own window never fired for real touch but did fire for mouse clicks, while the *same*
  virtual uinput device correctly drove touch-to-focus on ordinary (non-layer-shell)
  windows. Fix: **`TouchRouter.qml`** bypasses Wayland's touch path entirely for this
  app's own UI — it consumes the daemon's raw touch JSON directly and hit-tests against
  registered items itself. **Any new tappable element in this app must call
  `touchRouter.registerTap(item, callback)`/`unregisterTap` — a `TapHandler` alone will
  render correctly but never receive real touch on the physical panel.**
- **`shell/`** is the Quickshell/QML kiosk UI: a layer-shell window pinned to the panel's
  output (`WlrLayershell.layer: WlrLayer.Overlay` + `exclusionMode: ExclusionMode.Ignore`
  — see §4 for why both are needed), `HidBridge` (parses the daemon's JSON over a
  `Process`+`SplitParser`), `KnobRouter` (per-page knob gesture table), `TouchRouter`,
  `SystemStats` and `PersonalCareState` (page data/logic, `FileView`-persisted), and
  `ToastOverlay`/`WaterAmountPicker` as global overlays.
- **`ops/`** holds udev rules, `modules-load.d` config, and validated Hyprland config
  examples mirroring what's actually applied on the build machine.

## 3. Build timeline

1. **Investigation phase** — read through `bedrock-panel`'s HID driver, USB protocol
   decode, and knob-handling code to understand what needed porting vs. rebuilding.
2. **Repo scaffolding** — sibling folder, MIT + PolyForm split license (matching the two
   protocol-derived files' noncommercial restriction inherited from the vendor's stated
   terms).
3. **Daemon bring-up** — got raw HID events flowing, fixed permissions (see §4), built
   the virtual touch device, hit and fixed the touch-reliability and stuck-button bugs
   (see §4) — this was the longest and highest-risk phase since bugs here manifested as
   system-wide desktop breakage, not just app bugs.
4. **Quickshell shell bring-up** — pinned the window to the panel's output, wired
   `HidBridge`, discovered and worked around the Hyprland layer-shell touch bug via
   `TouchRouter`.
5. **Dashboard page** — system stats (CPU/RAM/network), later revisited to add btop-style
   history sparklines and a per-core bar grid (`SystemStats.qml` rewritten to keep rolling
   history buffers; `Ui/Sparkline.qml` added, a `Canvas`-based line+fill graph).
6. **Home Assistant page — descoped.** Embedding a `WebEngineView` inside Quickshell
   crashes hard (`QtWebEngineQuick::initialize()` is never called before
   `QGuiApplication` construction, and there's no QML-level fix for Quickshell's binary).
   User chose to skip it for now rather than chase an external-kiosk-window workaround.
   `shell/Pages/HomeAssistantPage.qml` exists but is on hold — see its header comment.
7. **Personal Care page** — pomodoro + water (in **ml**, not "glasses" — an early water
   design that logged discrete "glasses" was explicitly rejected) + stand reminders, all
   `FileView`-persisted. Iterated through: a knob-hold-driven ml amount picker
   (`WaterAmountPicker.qml`, remembers the last-picked amount), a pomodoro pause/resume
   bug fix (see §4), then a full layout redesign from three side-by-side cards into one
   combined 1/3-width card (see the plan file this session left at
   `~/.claude/plans/merry-watching-ripple.md` for the exact before/after reasoning), then
   a title correction ("Pomodoro" → "Self Care", since the card now covers three
   functions).
8. **Bar-overlap fix** — Omarchy's own bar was rendering on top of the kiosk app. Fixed
   in `shell.qml` (see §4).
9. **Theme following** — `Theme.qml` built to read the live Omarchy theme
   (`~/.local/state/omarchy/current/theme/colors.toml`) with a poll-based live-update
   fallback (see §4).
10. **The `omarchy-design` skill** — after user feedback that the styling didn't actually
    match Omarchy's real design system ("Are you following the /omarchy way of building a
    plugin?"), built a dedicated skill (via `/run-skill-generator`) that verifies Omarchy's
    real conventions from installed source (`/usr/share/omarchy/shell/`, primarily the
    Wi-Fi and bluetooth panels) rather than guessing. See §5.
11. **Styling pass using that skill** — applied the verified tokens to `DashboardPage.qml`
    and `PersonalCarePage.qml` (this was the most recent work in this session before this
    file was written — see §5 for exactly what changed and §6 for what's left).

## 4. Hard-won bugs and fixes (read before touching the related code)

- **udev permissions**: `GROUP="input", MODE="0660"` works reliably; `TAG+="uaccess"` did
  **not** reliably grant ACLs on this machine. Use the `GROUP` form (see
  `ops/udev/99-omarchy-quake-panel.rules`).
- **`uinput` module must autoload** at boot — `/etc/modules-load.d/` entry (see
  `ops/modules-load/`).
- **Touch worked once, then never again**: root-caused to bundling a synthetic release +
  the next press into a single `SYN_REPORT` sync frame. Fixed by flushing releases as
  their own separate `SYN_REPORT` in `uinputTouch.js`, both in `_reapStale()` and in the
  "release all others on new distant touch" path. This panel's touch interface **never
  sends an explicit HID "up" frame** — releases are inferred from a `STALE_MS` (400ms)
  timeout or an immediately-distant new touch.
- **Text selection broke system-wide (desktop-wide stuck mouse button)** after a missed
  touch release: root-caused to declaring `EV_KEY`/`BTN_TOUCH`/legacy `ABS_X`/`ABS_Y` on
  the virtual uinput device, which made libinput treat it as a generic pointer instead of
  a pure multitouch device. Fixed by declaring **pure MT-B protocol only**
  (`ABS_MT_SLOT`/`ABS_MT_TRACKING_ID`/`ABS_MT_POSITION_X`/`ABS_MT_POSITION_Y` +
  `INPUT_PROP_DIRECT`, nothing else). This bug required a full logout/login to clear once
  triggered — killing the daemon or unplugging the panel did not clear the stuck state.
- **Root-level `TapHandler` never fired for real touch** — the Hyprland layer-shell touch
  bug described in §2. Do not attempt to route real touch through Qt's normal input
  path in this app; use `TouchRouter`.
- **Omarchy's own bar rendered on top of the kiosk app**: `WlrLayershell.layer:
  WlrLayer.Overlay` alone was insufficient, because the bar *also* reserves an exclusive
  zone (`hyprctl monitors` showed `"reserved": [0, 26, 0, 0]`) that Hyprland shrinks other
  layer surfaces around regardless of layer ordering. Full fix required **also** setting
  `exclusionMode: ExclusionMode.Ignore` in `shell.qml`.
- **`omarchy theme set` doesn't trigger `FileView.watchChanges`** on the rewritten
  `colors.toml` — confirmed live, not fixed by any watcher flag. `Theme.qml` uses a 3s
  poll `Timer` calling `reload()` instead; harmless to also leave `watchChanges: true` on,
  it just never fires for this particular file.
- **QtWebEngine crashes inside Quickshell** — see §3 point 6. Not fixable at the QML
  level; would need an external browser-process kiosk approach instead.
- **Pomodoro pause/resume restarted the full duration** instead of continuing from where
  it left off: fixed by adding `_pausedRemainingMs` tracking in `PersonalCareState.qml`.
- **Border color initially looked "brownish"**: an early fix flattened
  `theme.surfaceBorder` to an opaque `muted` color to get rid of it. This was later found
  to be the *wrong* fix once the real Omarchy source was checked — see §5, the actual
  convention is still alpha-blended `foreground`, just at a much lower alpha for plain
  separators than for interactive control borders.
- **Harness/self-kill hazard** (a debugging-session gotcha, not an app bug): `pkill -f
  "<pattern>"` can match and kill the very shell script invoking it, since scripts are
  sometimes run as literal strings via `bash -c 'eval "..."'`. Always kill by explicit PID
  captured from a prior, separate `ps`/`pgrep` call — this is what
  `.claude/skills/omarchy-design/scripts/capture-panel.sh` does.
- **Screenshot mixups**: the interactive `omarchy capture screenshot` picker grabs
  whatever monitor currently has focus, almost never the panel (a separate, non-focused
  output). Use `grim -g "<x,y> <w>x<h>"` with the panel's real geometry (from `hyprctl
  monitors -j`) instead — this is exactly what `capture-panel.sh` automates.

## 5. Design system work — the `omarchy-design` skill

After a user challenge ("Are you following the /omarchy way of building a plugin, when
you look at styling??"), the styling approach shifted from ad-hoc guesses to **verifying
Omarchy's actual conventions from the installed source** before touching any QML. This
produced a reusable, project-scoped skill:

- **Location**: `.claude/skills/omarchy-design/` (project-scoped — see §7 for why it
  didn't show up in an unrelated session's skill list, and the discoverability tradeoff).
- **`SKILL.md`**: workflow + a visual review checklist + points at the driver script.
- **`reference/omarchy-conventions.md`**: verified-from-source tokens, with exact
  `file:line` citations into `/usr/share/omarchy/shell/` (primarily
  `plugins/panels/network/Panel.qml`, the Wi-Fi panel, and the bluetooth panel as
  corroboration). Key findings:
  - Structural surfaces are **alpha-blended `foreground`**, not a separate flat "muted"
    swatch — but at **two different strengths for two different purposes**: plain
    separators use `foreground @ 0.12` (`Ui/PanelSeparator.qml`), interactive control
    borders use `foreground @ 0.4` (`Style.normalBorderAlpha`). Conflating these (using
    the stronger alpha for a plain separator) is what caused the earlier "brownish line"
    complaint — the fix wasn't to abandon alpha-blending, it was to use the *right*
    alpha for each purpose.
  - Secondary/status text is `Qt.darker(foreground, 1.4)`, not `Color.muted`.
  - Corners are sharp (radius 0) on this machine, but that's because
    `Style.cornerRadius` mirrors the live `hyprctl getoption decoration:rounding`, not a
    fixed Omarchy constant — re-check per machine.
  - Icons are literal Nerd Font PUA glyphs in the currently-active font
    (`omarchy font current`), not images.
- **`reference/project-styling-notes.md`**: maps those conventions onto this specific
  project — explains `import qs.Commons`/`qs.Ui` are **not** importable here (this app is
  a standalone `quickshell -p` process, not a plugin inside Omarchy's own shell process;
  confirmed, don't re-attempt), and lists the exact "preserve behavior" boundaries (the
  daemon, `KnobRouter`'s gesture meanings, `TouchRouter`'s registration requirement,
  `PersonalCareState`/`SystemStats` logic, `shell.qml`'s window setup).
- **`scripts/capture-panel.sh`**: a tested driver that resolves the panel's exact
  geometry from `hyprctl monitors -j`, stops any existing instance of *this project's*
  shell/daemon by PID (never touches Omarchy's own shell), runs `qmllint`, relaunches, and
  captures via `grim`.

**What the skill's corrections actually changed in `Theme.qml`** (this project's
`Color.qml`/`Style.qml`-equivalent): added `separatorColor` (foreground @ 0.12),
`controlBorderColor` (foreground @ 0.4), and `secondaryForeground`
(`Qt.darker(foreground, 1.4)`) as new tokens, alongside the pre-existing `surfaceBorder`
(kept only because `ToastOverlay.qml`/`WaterAmountPicker.qml` still reference it — those
two files were explicitly out of scope for the pages-only restyle request and have not
been updated to the new tokens).

**Pages restyled with these tokens** (this session, most recently):
`shell/Pages/DashboardPage.qml` and `shell/Pages/PersonalCarePage.qml` — `Card` borders,
`SectionLabel` (now bold + darkened-foreground, **no** `letterSpacing` — the earlier
`1.2` letter-spacing was decorative, not present in the verified
`Ui/PanelSectionHeader.qml` source), `SectionSeparator`, `PluginButton` borders, and every
plain `theme.muted` body/status text usage were all switched to the new tokens. Verified
via `qmllint` (clean) and a real capture on the physical panel (both pages screenshotted
and sent to the user for review).

## 6. Current status (as of this file's writing)

**Working end-to-end on real hardware:**
- HID bridge daemon, virtual uinput touchscreen, Quickshell kiosk shell pinned to the
  panel's output, fully covering Omarchy's own bar on that output.
- `KnobRouter`: rotate = switch between Dashboard/Personal Care, hold = open water-amount
  picker from any page, press = per-page action (pomodoro toggle on Personal Care).
- `TouchRouter`-registered on-screen buttons (Start/Pause, Log water) work via real touch.
- Dashboard page: clock, CPU/RAM/network with btop-style history sparklines + per-core
  bar grid.
- Personal Care page: pomodoro (correct pause/resume), water in ml with a
  last-amount-remembered picker, stand reminder — all persisted to
  `~/.local/state/omarchy-quake-panel/personal-care.json`.
- Live theme following (polls `colors.toml` every 3s).
- Both pages restyled to verified Omarchy conventions (see §5) and screenshotted for
  review.

**Not yet done** — see `NEXT_STEPS.md` for the actionable list.

## 7. Where things live (quick map)

| Thing | Path |
|---|---|
| HID/USB driver | `daemon/src/Aris68Connector.js` |
| Daemon CLI entry | `daemon/src/bridge.js` |
| Virtual touchscreen | `daemon/src/uinputTouch.js` |
| Kiosk window entry point | `shell/shell.qml` |
| Daemon↔QML bridge | `shell/Services/HidBridge.qml` |
| Knob gesture table | `shell/Services/KnobRouter.qml` |
| Touch hit-testing workaround | `shell/Services/TouchRouter.qml` |
| Theme (Color.qml-equivalent) | `shell/Services/Theme.qml` |
| Dashboard logic | `shell/Services/SystemStats.qml` |
| Personal Care logic | `shell/Services/PersonalCareState.qml` |
| Pages | `shell/Pages/*.qml` |
| Overlays | `shell/Ui/ToastOverlay.qml`, `shell/Ui/WaterAmountPicker.qml` |
| Styling skill | `.claude/skills/omarchy-design/` |
| udev/Hyprland/modules-load examples | `ops/` |

Durable cross-session notes (permissions gotchas, hardware bring-up) also live in this
machine's assistant memory at
`~/.claude/projects/-home-srk-Projects-bedrock-panel/memory/project_omarchy_quake_panel.md`
— that file predates this one and has more granular debugging detail; this file is the
project-local, portable equivalent (readable from *any* session rooted in this repo,
where the memory file above is only loaded automatically in sessions rooted in
`bedrock-panel`).
