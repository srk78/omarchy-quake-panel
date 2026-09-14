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
    and `PersonalCarePage.qml` (see §5).
12. **Initial git commit** (2026-09-08) — everything above finally committed on `master`.
13. **Layout + styling pass, second round** (2026-09-08) — the full-width redesign
    described in §5a: Omarchy's font alias and font/spacing scale, shared `Ui/`
    components, a hero page header, both pages laid out for the 1920x480 aspect, and the
    two overlays brought onto the same tokens.

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

### 5a. Second styling round — full-width layout (2026-09-08)

Triggered by "improve the layout and styling by using /omarchy-design". Verified against
the same installed source; two corrections to the conventions doc came out of it (the
hero meta caption IS letter-spaced at 1.2 while section headers are not; the selected
fill blends foreground, not accent — `Theme.selectedFill` had accent, now fixed).

- **`Theme.qml` became the `Style.qml` equivalent too**: `fontFamily: "monospace"` (the
  fontconfig alias Omarchy's own `Style.font.family` binds to — follows `omarchy font set`
  with no hardcoded family, and brings Nerd Font glyphs along), a single kiosk `scale`
  (1.5) over Omarchy's 12px base, `font.*` tokens with Omarchy's names/multipliers plus a
  kiosk-only `hero` size, `spacing.*` named tokens plus `touchControlHeight`, and
  `pressedFill` (0.22). `surfaceBorder` is gone.
- **Shared `shell/Ui/` components** replaced the per-page inline ones: `Card`,
  `SectionLabel` (optional leading glyph), `SectionSeparator` (`vertical: true` for
  side-by-side sections), `PanelButton` (Omarchy Button states: transparent at rest,
  pressed fill, optional icon — and it **registers itself with `TouchRouter`**, so a page
  can no longer forget to), and `PageHeader` (PanelHero: glyph, title, letter-spaced
  status caption; trailing read-only page tabs + clock).
- **`PageHost` owns the header** and the page `Loader`; pages expose an optional
  `heroMeta` string for the caption (Self Care shows "WORK · 12:34 LEFT" / "POMODORO
  PAUSED"; Dashboard shows the hostname, read from `/etc/hostname` in PageHost so
  `SystemStats` stayed untouched).
- **Self Care** is still one combined card (the earlier user decision), but its three
  sections now sit side by side across the full width, split by vertical separators, each
  with a hero value and its action button pinned to the bottom so the buttons share a
  baseline. The stand line no longer clips. Glyphs: 󱎫 󰖌 󰖃, buttons 󰐊/󰏤 and 󰅶.
- **Dashboard**: same three cards, now with glyph labels (󰻠 󰍛 󰛳), hero % with the
  detail on its baseline (core count, used/total in GB), sparklines that take the
  remaining height, per-core bars over a faint track, and 󰇚/󰕒 rate glyphs with MB/s
  formatting.
- **Overlays**: `ToastOverlay` (bell glyph, popup padding) and `WaterAmountPicker`
  (finger-sized options, selected = foreground @ 0.18 + bold, no accent border) on the
  same tokens.
- **Dev-only `OQP_START_PAGE` env var** in `shell.qml`'s `Component.onCompleted` picks the
  initial page so `capture-panel.sh` can screenshot any page without turning the knob.
  The script now launches quickshell fully detached (`setsid`, `</dev/null`) — the
  earlier version blocked a harness that piped its output, because the launched shell
  inherited that pipe.
- **Not verified this round**: the water picker and toast were restyled from source only
  (no way to trigger them from a script without the knob/touch), and real-touch on the
  two buttons still needs a physical tap — `PanelButton` registers with `TouchRouter` the
  same way the old inline buttons did, but only a finger proves it.

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
- Both pages restyled to verified Omarchy conventions (see §5/§5a), laid out for the
  full 1920x480 panel, and screenshotted for review.

**Not yet done** — see `NEXT_STEPS.md` for the actionable list.

## 7. Becoming a real Omarchy shell plugin (2026-09-08)

Triggered by "Make a plan for making this an /omarchy plugin with a toggle to use the
screen as a second screen or as the full app." Investigation (not guessing) found Omarchy
has a real, documented third-party plugin system — `omarchy plugin add/enable/disable/
list`, git-checkout-based, loaded **inside** the single long-running `omarchy-shell`
process — not just a styling convention to imitate, which is all this project had done
until now. A plan was written (`~/.claude/plans/proud-soaring-crown.md`), approved, and
implemented and live-tested in the same session.

Key findings that shaped the design, each verified live before being relied on:
- `background`'s own manifest uses `kind: "service"` even though the shell README
  describes `service` as "headless, no UI" — its `Background.qml` is a plain `Item` that
  owns a `PanelWindow` per screen with full `WlrLayershell` control. That's the precedent
  this project's own service plugin follows.
- **Stopping this project's own standalone kiosk process, with nothing else changed,
  revealed Omarchy's own bar and wallpaper already rendering on the DK-QUAKE output** —
  proving "second screen" mode needs zero new code, only *not covering* the output.
- The `nightlight` service's `IpcHandler` (`status()/enable()/disable()/toggle()`) plus a
  thin `bin/omarchy-toggle-nightlight` wrapper is the established toggle pattern this
  project's own mode flag copies.
- Entry points are plain relative paths (`shell/Service.qml` is fine, no first-party-only
  restriction), and every QML document resolves `Qt.resolvedUrl(".")` against its own
  location regardless of which process loaded it — confirmed live, this is what lets the
  daemon path resolve correctly whether running standalone or cloned into
  `~/.config/omarchy/plugins/<id>/`.

What shipped:
- **`manifest.json`** (repo root) declares `srk78.quake-panel`, `kinds: ["service"]`,
  `entryPoints.service: "shell/Service.qml"`.
- **`shell/Service.qml`** (new) — the real entry point. Owns `HidBridge`,
  `PersonalCareState`, `SystemStats`, `Theme` unconditionally (so the daemon connection
  and pomodoro/water/stand timers never stop, regardless of mode); a persisted `mode`
  flag (`"kiosk"`/`"desktop"`, `~/.local/state/omarchy-quake-panel/mode.json`); an
  `IpcHandler` (`target: "quake-panel"`) with `status()/setMode()/toggleMode()`; a
  Service-root `Connections` block watching for a **3-second knob hold** (independent of
  `KnobRouter`, which only exists in kiosk mode) that calls `toggleMode()` — the one
  toggle surface that works with no window on screen to read input through; and a
  `Loader { active: mode === "kiosk" }` wrapping the same `PanelWindow`/`PageHost`/
  `TouchRouter`/`KnobRouter`/overlays setup `shell.qml` already had, recreated fresh each
  time kiosk mode is re-entered.
- **`shell/shell.qml` kept**, unchanged, purely as the fast standalone dev/screenshot
  entry point `capture-panel.sh` already depended on — reloading the whole
  `omarchy-shell` process on every styling tweak would be far slower.
- **`ops/omarchy-menu.example.jsonc`**, **`ops/hyprland/keybind.example.lua`**,
  **`ops/bin/omarchy-quake-panel-toggle`** — three more callers of the same IPC target,
  none duplicating toggle logic.

**Live-verified this session** (hand-installed via a real copy — not a symlink,
`omarchy plugin validate` rejects those — at
`~/.config/omarchy/plugins/srk78.quake-panel/`, `rescanPlugins`, `enable`): the plugin
loads and renders identically to the standalone process inside real `omarchy-shell`;
`omarchy-shell quake-panel toggleMode`/`status` and the `ops/bin` CLI wrapper both flip
the mode and persist it; toggling to desktop mode instantly reveals the bar/wallpaper
with the output's normal workspace and reserved bar zone intact; the daemon process
never restarts across a toggle (same PID throughout, since `HidBridge` lives outside the
`Loader`); the rest of the desktop (other outputs, client count) stayed healthy across
repeated toggles. **Not yet verified**: the knob's physical 3-second hold (requires
hands on the real hardware, not something this session could simulate), and touch on
real hardware while loaded as the plugin specifically (touch itself was already
reconfirmed working standalone earlier this project, and the Hyprland `wl_touch` bug
`TouchRouter` works around is compositor-level, not process-level, so no behavior change
is expected — but only a live tap proves it, same caveat as every prior restyle).

**Deliberately deferred, not forgotten**: the plan's styling-migration piece (replacing
`Services/Theme.qml`/`Ui/Card.qml` etc. with real `import qs.Commons`/`qs.Ui`, now that
`Service.qml` actually makes them reachable) was left for its own pass — a visual change
needs its own screenshot-verified review, and this session's scope was already large
enough to isolate the plugin-mechanics risk from the styling risk. See `NEXT_STEPS.md`.

The manual `~/.config/omarchy/plugins/srk78.quake-panel/` install used for this session's
live test is a plain copy (including a synced-in `daemon/node_modules`, since Omarchy's
installer never runs `npm install`), not git-managed — it works today, but the durable
install path is `omarchy plugin add <this-repo's-github-url> --enable` once
`manifest.json`/`shell/Service.qml`/`ops/` are pushed there.

Later small fixes on the live plugin this same day: removed the red WORK/BREAK pill and
added Reset buttons to Pomodoro and Stand (`resetPomodoro()`/`resetStand()` in
`PersonalCareState.qml`); found and documented that `omarchy plugin disable`/`enable`
does **not** reload changed QML from disk (only a genuine file write under the plugin's
own directory, or a full `omarchy-restart-shell`, does) — see `NEXT_STEPS.md`; fixed
Reset to leave the pomodoro genuinely idle (full duration, not running) instead of
auto-starting it, which needed exposing `PersonalCareState.pausedRemainingMs` publicly so
the page can tell "genuinely paused mid-session" apart from "fresh/just reset" (both are
`pomodoroRunning === false`); renamed the Dashboard page to "System" (one line,
`Ui/PageHost.qml`'s `pages` array — both the header title and the page-switch tab read
from the same source).

## 9. A Settings page, and the knob's RGB ring (2026-09-10)

Added a third page (`shell/Pages/SettingsPage.qml`) exposing the knob's RGB ring color as
tappable presets, using daemon commands that already existed but had no UI
(`setLedEffect`/`setLedColor`/`saveLighting`/`getLighting` in `Aris68Connector.js`) — no
daemon changes needed, only new QML.

- **`shell/Services/KnobLighting.qml`** (new) — queries the ring's actual current color
  once at daemon connect (`getLighting`) rather than keeping its own persisted
  preference; the device is the source of truth. `setColor(hue, sat)` forces effect index
  `1` ("Solid Color" — the conventional first non-off entry in QMK's stock
  `rgb_matrix_effects` enum, **inferred from convention, not verified against this exact
  firmware's effect list** — flagged in the file's own header comment and in
  `NEXT_STEPS.md`) then pushes the color and calls `saveLighting()` to flash it.
- **A real hard-won gotcha, caught immediately by actually loading the plugin**:
  `qmllint` passed clean on `KnobLighting.qml`, but it failed to load with "Cannot assign
  to non-existent default property" — a bare `Connections { ... }` as a direct child of a
  `QtObject` (unlike `Item`) has no default property to bind to. Fixed by giving it an
  explicit `property Connections _stateConn: Connections { ... }`, matching the pattern
  `PersonalCareState.qml`'s own `Timer`/`FileView`/`Process` children already use.
  **`qmllint` does not catch this class of error — only a real plugin load does.**
- **Verified end-to-end on real hardware, not just via screenshot**: set the ring to blue
  through a temporary debug IPC hook, then did a full `omarchy-restart-shell` (a
  completely fresh daemon connection, fresh `KnobLighting` instance with no local state)
  and confirmed `getLighting()` genuinely read back hue=170/sat=255 from the device
  itself — proof the color really flashed to the hardware and survived a real
  reconnect, not just an optimistic local UI guess. The one thing this session could not
  verify is what the physical LED ring actually looks like — no camera on this hardware,
  only firmware-level confirmation that the device accepted and stored the value.
- `KnobRouter.pageCount` is now 3 (System/Self Care/Settings); Settings' knob `press` is
  a no-op for now, same as System's.

**Same day, follow-up request**: added a "None" ring preset (turns the ring fully off —
`setLedEffect(0)`, the documented "All Off" index, not a color at all) and a microphone
on/off toggle (`shell/Services/MicState.qml`, wrapping the daemon's pre-existing
`setMic`/`queryMic` commands the same `getLighting`-style query-on-connect pattern).

- **`KnobLighting.isCurrent()` now also checks `effect === solidColorEffect`**, not just
  hue/sat — otherwise a ring that's off but still remembers an old color internally would
  wrongly highlight that color's swatch. This was **not a hypothetical edge case**: the
  ring's actual state when this was tested was genuinely off with a leftover hue that
  exactly matched the Green preset, and the fix correctly showed "None" as current with
  no color swatch highlighted, no coincidence "test" needed to construct it.
- Both new pieces got the same real-hardware verification as the color picker: toggled
  the mic and confirmed the query round-trip reflects it; set a color, restarted the
  shell fully fresh, and confirmed `getLighting()` still reported it — genuine flash
  persistence, not a UI guess. The mic was found on at the very start of this check and
  restored to on before finishing, since muting it wasn't something asked for.
- `MicState.qml` and `KnobLighting.qml` both wrote their non-visual `Connections`
  children as named properties (`property Connections _stateConn: Connections {...}`)
  from the start this time, having just learned the hard way (above) that a bare one
  under `QtObject` fails at load with no `qmllint` warning.

## 11. Dimmable ring brightness, and fixing the Settings layout (2026-09-10)

Two requests in one turn: "make the knob ring light dimmable" and "fix the settings page
layout." Both landed in the same file set.

- **Brightness**: `KnobLighting.qml` gained `brightness`/`brightnessPresets`
  (25/50/75/100%, mapped to `setLedBrightness`'s documented ~247 ceiling: 62/124/185/247)
  and `setBrightness()`/`isCurrentBrightness()`, mirroring the color picker's shape
  exactly (query-on-connect, `saveLighting()` to flash, tolerance-based "current" check
  since `setLedBrightness`'s own comment says "device quantizes"). **The quantization
  wasn't hypothetical either**: requesting 124 and restarting fresh, the device reported
  back 119 — a 5-unit gap the `<6` tolerance was specifically chosen to absorb, confirmed
  correct by this exact real reading, not assumed.
- **A second, different `qmllint`-blind bug, caught the same way as the first**: tried to
  extract one shared `PresetColumn`/`PresetSwatch` pair (a `default property alias
  content: contentItem.data`) to de-duplicate the color-swatch and brightness-swatch
  Repeater delegates. `qmllint` passed clean; loading the plugin threw `TypeError: Cannot
  read property 'off'/'value' of undefined` at runtime. Root cause: the default-property
  alias silently redirects a delegate's declared children into the wrapper `Item`
  (`contentItem`), so `parent` inside the swatch was that wrapper, not the delegate
  holding `modelData` — `parent.modelData` was reading a property that simply isn't
  there. Fixed by reverting to two small, duplicated, directly-scoped inline delegates
  (each `modelData` reference resolves in the same scope it's declared in, no indirection)
  rather than chasing the abstraction further — correct and boring beat clever and broken.
  **Second confirmation this session that `qmllint` doesn't catch every real class of
  QML load/runtime error** — a real device load remains the only reliable check.
- **The layout fix itself**: the color row (needs the full page width for ten swatches)
  stayed a full-width block up top; Brightness and Microphone — each far narrower — were
  moved into a shared second row, split by a vertical separator, reusing `Ui/Section.qml`
  (promoted out of `PersonalCarePage.qml`'s previously page-local `Section` component,
  now `required property var theme` instead of implicitly closing over an inline `root`).
  This fills the page's height instead of one top-aligned block leaving a large empty
  area below it — but the FIRST version of this still overflowed the panel's real
  480px height (hint text under both KNOB COLOR and BRIGHTNESS, plus `xxl` gaps around
  the middle separator, added up to more vertical space than a 1920×480 panel actually
  has after the header). Caught immediately from the same live screenshot: brightness
  swatches cut off at the very bottom edge, and the Microphone section's label/button
  visibly overlapping in too little height. Fixed by dropping both hint texts, shrinking
  `xxl` gaps to `lg`, and shrinking every swatch from `space(64)` to `space(48)` — this is
  the second time in this project a layout looked fine in isolation but didn't fit this
  panel's unusually short, wide aspect ratio; there is no substitute for a real capture
  at 1920×480 specifically, a normal-aspect mockup would not have shown either overflow.

## 13. A real slider, and screen brightness (2026-09-10)

Same-day follow-up: rename "BRIGHTNESS" to disambiguate from screen brightness, replace
the discrete presets with an actual slider, and — asked as a question first, "is it also
possible?" — screen brightness turned out to be a genuinely separate, already-half-wired
daemon command (`setBrightness`/`queryLuminance`, Aris68Connector.js's "legacy 0xA3
path", distinct from the ring's VIA channel), so it shipped in the same pass rather than
just being answered.

- **`TouchRouter.qml` gained real drag support** (`registerDrag(item, onStart, onMove)`
  alongside the existing `registerTap`) — this app's first continuous, not tap-once,
  touch control. A drag session is distinguished from a tap session only at its first
  point: if that point hits a drag target, every subsequent point in the same session
  (session = "still recent", same staleness model as taps) goes to `onMove` instead of
  being debounced away; a tap session's later points were always ignored the same way
  before this, so existing tap behavior is provably unchanged. No proactive "drag ended"
  signal exists — the next touch anywhere resets `_activeDrag` via the same staleness
  check that already ran for taps, so a slider's own settle-timeout is what a consumer
  uses to mean "released," not a TouchRouter callback.
- **`Ui/Slider.qml`** (new) — the shape both new brightness controls needed: a
  fill-track + thumb, driven by `registerDrag`, throttling its own `settled(value)`
  signal (trailing-edge, ~90ms) so a fast drag can't flood a real USB HID device with
  writes. `KnobLighting.previewBrightness()` additionally debounces the *flash write*
  (`saveLighting()`) separately and much less often (700ms after the last change) —
  flash has real write-cycle endurance limits, unlike the live brightness write itself.
- **`Services/ScreenBrightness.qml`** (new) — same query-on-connect/device-is-truth
  shape as `KnobLighting`/`MicState`, wrapping `setBrightness`/`queryLuminance`. No
  save/persist command exists for it in the driver, so (like the mic) it likely doesn't
  survive a power cycle — see NEXT_STEPS.md.
- **Verified the new TouchRouter drag path with the real dispatch code, not a shortcut**:
  a temporary debug hook read each registered drag target's actual on-screen bounds
  (`item.mapToItem(null,0,0)`), then fed a synthetic multi-point sequence through the
  exact same `TouchRouter.feed()` real touch goes through — confirmed the value moves
  correctly across a full simulated drag (0%→70%→exact expected byte value both times).
  Hit one, and only one, transient hiccup along the way, tracked down and worth
  recording since it reveals something real about the debounce model: a fresh test
  begun **inside the still-active previous session** (same simulated-drag helper called
  again well within the actual staleness window) had its first point silently continue
  the *old* target's drag instead of starting a new one, and a separate test used an
  exact-boundary fraction (1.0, the target's literal right edge) that a `Math.round()`
  pushed a fraction of a pixel past the real float boundary, missing the hit-test
  entirely — both were artifacts of the synthetic test harness's own timing/rounding,
  not bugs in `TouchRouter`, `Slider`, or either service; the real, continuous drag path
  worked correctly every time it was actually exercised end to end.
- Still true from the ring-color/mic work: **no camera on this hardware** — the software
  round-trip (set brightness, full restart, read the same value back) is confirmed for
  both the ring and the screen, but nobody has looked at either to confirm the ring
  visibly dims or the screen backlight actually changes. A `grim` screenshot specifically
  **cannot** show this either way — it captures the rendered framebuffer, not the
  physical backlight, so a dimmed screenshot was never going to be possible even if the
  command works perfectly.

## 15. A real, pre-existing bug the slider finally made visible: a phantom "Mouse" device

Reported live, immediately after the slider work above: "Changing the slider seems to
affect the main screen too. I can scroll the main screen by touching the device's
screen." This turned out to be a genuine, previously-undiscovered gap in this project's
whole HID setup — not a new bug introduced by the slider, but one the slider was simply
the first thing to make *visible*.

**Root cause, found by reading Hyprland's own libinput debug log
(`/run/user/1000/hypr/<instance>/hyprland.log`) while the panel was touched**: the
panel's raw touch hardware (vendor 0712:0010, "hotlotus" in
`ops/udev/99-omarchy-quake-panel.rules`) auto-registers with the kernel as **more than
one** input device. Alongside the vendor-specific touch usage page this project's own
daemon reads directly via hidraw — the whole reason `Aris68Connector.js`/`uinputTouch.js`
exist, per this project's own README: "the panel's touchscreen uses a vendor-defined HID
usage page (0xFF73), so it never shows up as a normal OS input device on its own" — its
HID report descriptor *also* exposes a standard-usage-page "Mouse" collection that
Linux's generic HID driver **can** parse as real relative pointer motion. The log showed
it plainly: `libinput: New device hotlotus wcidtest Mouse` / `device is a pointer`,
entirely separate from `omarchy-quake-panel-touch` (this project's own virtual
re-emission, which *is* correctly bound to the panel's output in
`~/.config/hypr/input.lua`). Nothing in this project ever bound or disabled this second,
phantom device, so its motion went wherever Hyprland's default pointer-output happens to
be — the primary/laptop screen.

**Why this was invisible until today**: every touch interaction before the brightness
sliders was a quick, discrete tap (buttons, color swatches) — a stray click landing
somewhere on the main screen rarely does anything noticeable. The sliders introduced the
first *sustained, continuous* touch-drag in this app's history, and a continuous phantom
pointer drag reads immediately and unmistakably as scrolling. The underlying bug has
almost certainly existed since this project's very first hardware bring-up; dragging
just finally made it visible.

**Fix**: `hl.device({ name = "hotlotus-wcidtest-mouse", enabled = false })`, added to
`~/.config/hypr/input.lua` (the user's live config, outside this repo) and mirrored into
`ops/hyprland/input.example.lua`. Disabled outright rather than confined to the panel's
own output like the touch device is: this "Mouse" collection has no legitimate use for
this project even there — it would still jump/click a real cursor around in "desktop
mode" (`shell/Service.qml`'s mode toggle) if only confined rather than disabled. This is
Omarchy's own first-party pattern for disabling a named input device, not something
invented for this project — see `/usr/share/omarchy/default/hypr/disabled-input-device.lua`.

**A second, smaller gotcha caught while writing the fix**: `hl.device({name=...})`
matches Hyprland's own *normalized* device name (lowercase, hyphens for spaces — the
form `hyprctl devices` itself prints), not the raw, human-readable name libinput's debug
log shows. The first attempt used the log's literal spelling, `"hotlotus wcidtest
Mouse"`, which `hyprctl reload` accepted without error but silently matched nothing (the
device still appeared in `hyprctl devices -j` afterward). Confirmed correct once
rewritten as `"hotlotus-wcidtest-mouse"`, matching `hyprctl devices`' own listing exactly
— worth remembering for the existing touch-device binding too, which only ever "worked"
without hitting this because this project happened to choose an already-hyphenated name
(`omarchy-quake-panel-touch`) for its own virtual device in the first place.

**Not independently verified**: whether the fix actually stops the scrolling. Hyprland
does not expose a device's enabled/disabled state via `hyprctl devices -j` (no field for
it), and unlike this project's own virtual touch device, there is no software hook to
feed synthetic input through this specific kernel-level phantom device to test it
directly — confirming this needs the same physical retest that reported the bug in the
first place. If scrolling persists, the plain `hotlotus-wcidtest` touch-tagged device
(not the "-mouse" one) is the next suspect — left alone this round since the
vendor-specific-usage-page reasoning above suggests it's likely inert, but that's
reasoning, not a live confirmation.

**Superseded by §16 below**: the user retested and the scrolling persisted. A proper
from-scratch kernel-level investigation (reading every input device directly, not
guessing from names) showed this whole theory, plausible as it looked, was wrong.

## 16. The real investigation: still unresolved, and an important correction

The user retested §15's fix and the scrolling persisted. What followed was a genuine,
from-scratch diagnostic session — worth recording in full both because the bug is still
open and because it surfaced an important gap in how this whole session verified touch.

**First, a correction that matters more than the bug itself**: every "touch confirmed
working" claim made anywhere in §7 through §15 of this file — the color picker, the
brightness presets, the mic toggle, the slider's own drag mechanism — was verified via a
temporary debug `IpcHandler` method calling `TouchRouter.feed()` or the underlying
service function **directly, in software**. That path exercises this app's own internal
dispatch (`HidBridge → TouchRouter → QML callback`) and nothing else — it never touches
`uinputTouch.js`, `/dev/uinput`, the kernel, libinput, or Hyprland's output routing,
which is exactly where this bug turned out to live. None of that testing could have
caught this regardless of when the underlying problem started. The lesson: a debug hook
that calls the same function real input calls is a genuinely useful test of *this
app's own logic*, but it is not evidence about the OS-level delivery path, and should
never have been described in a way that implied it was.

**The actual investigation, in order**:
1. Checked Hyprland's own `libinput` debug log (`disable_logs` is `true` by default —
   had to be flipped live via `hyprctl eval "hl.config({debug={disable_logs=false}})"`,
   since `hyprctl keyword` doesn't work with this Lua-based config's non-legacy parser)
   while the user dragged a slider. **First attempt caught nothing at all** — the log
   file's own last-write timestamp hadn't moved in over an hour despite two confirmed
   drags in between, meaning Hyprland's debug logging path itself wasn't a reliable
   real-time signal here (verified live via `/proc/<pid>/fd` that Hyprland did still
   hold the log file open — the log just wasn't a useful window into this).
2. Switched to reading raw kernel `struct input_event` records directly from
   `/dev/input/eventN` (this account is in the `input` group, so this needs no root) —
   entirely bypassing Hyprland/libinput. First guessed at the two "hotlotus" devices
   from §15 specifically; **zero events from either during a confirmed drag** — ruling
   out that whole theory outright, not just leaving it unconfirmed.
3. Escalated to watching **every single readable `/dev/input/event*` node at once**
   (25 devices) rather than guessing further — removes all ambiguity about which device
   is responsible. This is the method that should have been used from the start of the
   diagnosis, not the second resort. **This time, exactly one device fired**:
   `/dev/input/event9`, `omarchy-quake-panel-touch` — this project's own virtual touch
   device — emitting textbook-correct `ABS_MT_POSITION_X`/`ABS_MT_POSITION_Y` data
   tracking the entire drag. (One other device, the laptop's own physical keyboard,
   fired unrelated key events during the same window — plain noise, not a candidate.)
4. This means the device itself is not malfunctioning — `uinputTouch.js` is doing
   exactly what it should. The bug is specifically that
   `ops/hyprland/input.example.lua`'s own long-standing binding
   (`hl.device({name="omarchy-quake-panel-touch", output="desc:BOE DK-QUAKE"})`) is not
   confining this device's real touch to the panel's output, despite every check on the
   binding itself coming back clean: the device name matches `hyprctl devices` exactly,
   the monitor description matches `hyprctl monitors` exactly (`'BOE DK-QUAKE'`), and
   `hyprctl reload`/`hyprctl eval` both report success with no config errors.
5. Confirmed via the installed `/usr/include/hyprland/src/devices/ITouch.hpp` header
   that Hyprland genuinely has a dedicated `std::string m_boundOutput` field on its
   touch-device object — so per-device touch output binding is a real, intended
   mechanism in this Hyprland version, not something touch devices are silently
   excluded from. The actual assignment logic lives in `.cpp` files this machine's
   headers-only package doesn't ship, so it couldn't be inspected further this way.
6. Tried, in order, none of which changed anything (each followed by the user actually
   re-dragging the slider, not assumed): forcing a fresh device reconnect via `omarchy
   plugin disable`/`enable` (destroys and recreates the virtual device, on the theory
   that output binding only applies at connect-time and this device had been running
   since before some of today's config edits); then applying the identical binding as a
   direct `hyprctl eval` one-liner — bypassing the config file and any possible Lua
   `require`-caching issue with plain `hyprctl reload` — followed by *another* fresh
   reconnect.
7. **Current leading hypothesis, not yet tested**: this project already has one
   documented precedent for exactly this class of symptom. §4's stuck-mouse-button bug
   states plainly: "This bug required a full logout/login to clear once triggered —
   killing the daemon or unplugging the panel did not clear the stuck state." Today
   involved an unusually large number of repeated daemon/virtual-device reconnects
   (dozens, across a full session of feature work) — if Hyprland's own internal
   input-routing state can get stuck in a similar way, only a full compositor restart
   (not a config reload) would clear it. A full session restart is disruptive enough
   that trying it is the user's call, not something to do unprompted.

**Status: unresolved as of §16.** See §18 below for what actually fixed it.

## 17. A full logout/login, a fresh diagnostic clue, and one more dead end

The user tried a full session restart (logging out and back in — a genuine fresh
Hyprland process, not just a config reload). **The bug survived it**, ruling out §16's
"stuck compositor state" hypothesis outright — nothing about Hyprland's *own* internal
state was the cause.

A new detail came with that retest: **dragging exactly horizontal did not scroll the
main screen; only vertical motion did.** This looked at first like it might point to an
entirely different mechanism (a gesture recognizer, a touchpad-style axis distinction),
but on reflection it's fully consistent with the existing diagnosis, not a new one: if
genuine absolute touch position is landing on a real window on the main screen (exactly
what §16 already confirmed at the kernel level), *of course* only the vertical component
reads as a scroll — that's how virtually every scrollable UI (browsers, GTK, etc.)
already interprets touch-drag, whether or not the touch was supposed to be there.
Horizontal-only motion on most content simply has nothing to do.

Verified Hyprland's exact native config keys for this via the installed
`/usr/include/hyprland/src/config/values/ConfigValues.hpp` (rather than guessing at Lua
syntax): `input:touchdevice:output`, `:transform`, `:enabled` — the *global* form,
distinct from the per-device `hl.device({output=...})` already tried. Applied it live
(`hyprctl eval "hl.config({input={touchdevice={output='desc:BOE DK-QUAKE'}}})"`) and, for
the first time in this whole investigation, **confirmed it was actually active**
(`hyprctl getoption` returned `set: true` — a check the per-device binding never offered,
since Hyprland doesn't expose per-device bound-output state through any `hyprctl` query).
Also independently re-verified our own device's declared coordinate range via a direct
`EVIOCGABS` ioctl read (`ABS_MT_POSITION_X`/`Y`: 0–1919 / 0–479, exactly matching the
panel) — ruling out a coordinate-space mismatch as the cause. **The user retested; the
global binding, confirmed active, still did not fix it.**

At this point every reasonable Hyprland-level configuration lever had been tried,
confirmed applied, and confirmed insufficient: per-device binding (file and live-eval,
both confirmed matching by name and by monitor description), a global fallback
(confirmed active via `getoption`, the one check the per-device form never allowed), two
fresh device reconnects, and a full session restart. The remaining gap is inside
Hyprland's own `.cpp` implementation, which this machine's headers-only dev package
doesn't ship — not something further configuration or diagnosis from this project's side
was going to resolve.

## 18. The actual fix: stop needing an answer to the question at all

Reframed the problem. This app's own kiosk UI (`TouchRouter.qml`) has **never** used the
virtual `/dev/uinput` touch device for anything — it reads touch directly from the same
daemon JSON stream the virtual device is built from, specifically *because* real
Wayland/Hyprland touch delivery to a layer-shell surface doesn't work at all (the
original, unrelated bug `TouchRouter` exists to route around — see §2). The virtual
device has exactly one real purpose in this whole project: letting an *ordinary* window
receive real touch in "desktop" mode. In "kiosk" mode — the default, and everything this
whole debugging session was testing — it does nothing useful and was the entire and only
mechanism by which touch could reach the wrong screen. So: stop creating it in kiosk
mode. Not "fix the routing" — remove the one component capable of ever misrouting in the
first place.

- **`daemon/src/bridge.js`** gained a `setVirtualTouch` command
  (`{cmd:"setVirtualTouch", on:bool}`) calling `uinputTouch.start()`/`.stop()` — both
  already existed, already idempotent, and `feed()` already no-ops safely when the
  device isn't running (`if (this.fd === null) return`), so this needed zero changes to
  `uinputTouch.js` itself, the single most historically fragile file in this project
  (§4's "longest and highest-risk phase," the stuck-mouse-button bug). The daemon's own
  default startup behavior (auto-start) is unchanged, so `shell/shell.qml`'s standalone
  dev path — which has no mode concept at all — keeps working exactly as before.
- **`shell/Service.qml`** sends this command on every mode change (`onModeChanged`,
  which fires regardless of *how* `mode` changes) and once more as soon as the daemon
  connects (covering the compiled-in default value before the persisted mode has even
  loaded): `on: mode === "desktop"`.
- **Verified, not assumed**: after this shipped, `/proc/bus/input/devices` showed **zero**
  `omarchy-quake-panel-touch` entries while in kiosk mode — the device architecturally
  does not exist, not "exists but is hopefully confined." Toggling to desktop mode and
  back showed it appear and disappear exactly on cue. A synthetic drag fed through
  `TouchRouter.feed()` directly (bypassing the now-absent virtual device entirely, since
  this app's own dispatch never used it) confirmed the Settings sliders still track
  correctly — this app's own UI is completely unaffected by the device's absence, exactly
  as predicted by `TouchRouter`'s own design.
- **What this does and doesn't prove**: this is architecturally certain to eliminate the
  reported symptom in kiosk mode — there is no code path left that could deliver this
  app's touch to the OS while a real device to do it with doesn't exist. It says nothing
  about *why* Hyprland's own output binding wasn't confining it, which remains
  genuinely unresolved and is no longer this project's problem to solve, since it no
  longer depends on that mechanism working at all. If the exact same symptom is ever
  seen again specifically in "desktop" mode (where the virtual device is still needed
  and still created), that would be new information — the Hyprland-side mystery
  documented in §16/§17 remains the reference for investigating it, but note desktop
  mode differs in one relevant way already confirmed elsewhere in this project's
  history: a *real* window is present there, and ordinary (non-layer-shell) windows were
  already confirmed to receive Wayland touch correctly, unlike this app's own kiosk
  surface.

**Confirmed by the user's own hand, same day**: dragged a Settings slider in kiosk mode
— no more scrolling on the main screen. This closes the loop this whole multi-section
investigation (§15–§18) was working toward. Status: **resolved for kiosk mode.** Desktop
mode's open question (above) stands as the only remaining unknown.

## 19. A design pass on the Settings page (2026-09-10)

Ran the `omarchy-design` skill against `Pages/SettingsPage.qml` specifically. Most of
the page already matched the verified conventions correctly (separator vs control-border
alpha, darkened-foreground secondary text, glyph usage, spacing) — one real
inconsistency stood out: the KNOB LIGHT BRIGHTNESS and SCREEN BRIGHTNESS columns both
lead with a bold hero-style value (their percentage) before their control, matching this
app's own established pattern everywhere else (System's CPU/Memory/Network, Self Care's
Pomodoro/Water/Stand). The MICROPHONE column instead led with a full dimmed sentence
("Panel microphone is on/off") — the one place on the page breaking that rhythm.

Fixed by replacing the sentence with a bold "On"/"Off" hero value in `theme.foreground`
at `font.title`, matching the other two columns' exact size/weight/baseline. **First
attempt added this as a second line below a kept detail sentence — wrong**: this row's
vertical budget was already tight (the same budget documented in §11's layout fix
earlier this project), and the extra line collided visibly with the bottom-anchored
button, caught immediately from the live capture. Corrected to a single line, replacing
the sentence rather than adding to it, restoring the exact line count that was already
proven to fit.

**Then removed entirely, per direct user feedback**: "Just above the Microphone toggle,
the word on/oof is shown, but the state is already shown correctly inside the toggle.
Please remove the one just above the toggle." The hero value fixed the overlap, but it
was still redundant — `Ui/PanelButton`'s own label already reads "On"/"Off", so the
Microphone column ended up saying the same word twice. The other two lower-row columns
(Knob Light Brightness, Screen Brightness) keep their hero value because their `Slider`
has no label of its own to duplicate; Microphone's control does, so it doesn't need one.
Verified live: deployed, `omarchy-restart-shell`, navigated to Settings via a temporary
debug hook, screenshot confirmed the redundant text is gone and the button reads cleanly
with no overlap, then the debug hook was removed and the shell restarted clean once more.

**Considered and deliberately left alone**: the color swatches' "current" indicator uses
an opaque, doubled-width `theme.foreground` border, which is a stronger treatment than
`omarchy-conventions.md`'s documented row-selection idiom (fill only, no border, by
default). Not changed — that convention was verified from Omarchy's *list row* selection
pattern (Wi-Fi/bluetooth device rows), which isn't a clean analogue for "which color
swatch is currently active." Flagging the reasoning here rather than silently applying a
convention outside where it was actually verified.

Verified via two live captures against the real, running plugin (not a throwaway
process) — the first catching the overlap bug, the second confirming the fix — and sent
to the user for final visual confirmation.

## 20. A top-bar dropdown for the mode toggle (2026-09-10)

User request: "Toggle between modes from a dropdown in the top bar" — a sixth surface
alongside the knob long-hold, raw IPC, CLI wrapper, menu entry, and keybind (§7), all of
which already existed but all of which require either physical hardware access or
knowing a command to run. A bar dropdown is the one surface discoverable by just looking
at the screen.

**Architecture**: `manifest.json` gained a second `kinds` entry, `"bar-widget"`, and a
second entry point, `shell/BarWidget.qml` — the exact split `omarchy.media` uses for its
own two-kind manifest (confirmed by reading it): `Service.qml` is always loaded and owns
the real state (`mode`, `setMode()`, the `IpcHandler`), `BarWidget.qml` only mounts while
a bar is on screen and is a thin read/write client of that state, never a second source
of truth. The link between them is `bar.shell.serviceFor("srk78.quake-panel")` —
`shell.qml`'s own generic lookup for *any* enabled service-kind plugin by id (confirmed
in source: `firstPartyServiceFor()` is a one-line alias over the same `serviceFor()`,
despite the name — nothing about it is actually first-party-only). This returns
`Service.qml`'s root `Item` directly, so `service.mode`/`service.setMode()` are the exact
same properties/functions the knob and IPC already used. No new IPC target, no duplicated
mode state.

The widget itself (`BarWidget.qml`) is built entirely from real `qs.Ui`/`qs.Commons`
components — genuinely available here, unlike the shared `Pages/`/`Ui/` files that also
have to run under the standalone `shell/shell.qml` dev entry point (see
`project-styling-notes.md`) — since a bar-widget only ever runs inside `omarchy-shell`
itself: `BarIconButton` for the bar icon, `PopupCard` for the dropdown (a lighter,
click-dismissed popup than the keyboard-navigable `KeyboardPanel` the network/power
panels use — this widget has two rows and no keyboard nav requirement, so the simpler
base fit), and the exact selected-row `BorderSurface` idiom `omarchy.media`'s own
`BarWidget.qml` uses for its source-player list, reused verbatim for the Kiosk/Second
screen rows.

**Two real gotchas hit getting this actually enabled and rendering, both confirmed live,
neither obvious from the README**:

1. **A stale `plugins[]` entry silently blocks bar placement.** Before this session, the
   manifest only declared `kinds: ["service"]`, and `shell.json` had a top-level
   `plugins: [{"id": "srk78.quake-panel"}]` entry — the mechanism the README documents
   for enabling a service/panel/overlay plugin. Adding `"bar-widget"` to `kinds` and
   running `omarchy plugin enable srk78.quake-panel --section right` reported success
   ("Enabled and moved...") but placed nothing — `omarchy plugin list` kept showing it
   disabled, and no widget appeared anywhere. Read `PluginRegistry.qml`'s `setEnabled()`
   source to find why: it only inserts a `bar.layout` entry when
   `!findEntryLocation(config, key).found` — and `findEntryLocation` matches the stale
   top-level `plugins[]` entry just as readily as a real bar-layout entry, so it thought
   the widget was "already placed" and did nothing. Fixed by deleting the stale
   `plugins[]` entry first, then re-running the enable command, which then correctly
   created a `bar.layout.right` entry — after which `srk78.quake-panel`'s own `mode`
   property (read via `serviceFor()`, independent of `plugins[]`) kept working the whole
   time, since `_syncServices()`'s own `isEnabled()` check matches a `bar.layout` entry
   just as well as a `plugins[]` one. Worth remembering for anyone converting an
   existing service-only plugin to also be a bar-widget: drop the old `plugins[]` entry
   first, or the CLI's success message is misleading.
2. **A Nerd Font codepoint's conventional name does not reliably predict what it renders
   as.** The first icon chosen for kiosk mode, 0xF0F26 (nominally "tablet" in the
   Material Design Icons set this project has referenced before, e.g. §11's brightness
   icons), rendered on the real bar as an unrelated media skip-forward glyph — confirmed
   by screenshotting the real bar, not by `fc-query`/cmap presence (the codepoint IS
   present in the font; presence was never the issue, only which glyph lives there in
   this exact Nerd Font patch revision). Also caught along the way: this project's bar
   font is **JetBrainsMono Nerd Font** (`fc-match monospace`), not the CaskaydiaMono this
   session had been checking glyph coverage against for the panel's own pages — the two
   happened to agree on the codepoints checked so far, which is what let the mismatch go
   unnoticed until now. Fixed properly this time by rendering each candidate codepoint
   with the *actual* font file via a quick PIL script and reading the result, rather than
   trusting a name-to-codepoint table from memory — landed on 0xF011C ("cellphone" in
   the same MDI set), which does render as a plausible small-touchscreen-device
   silhouette in this font. `Service.qml`'s icon choices from earlier sessions were not
   re-audited this way and could have the same latent issue; worth a real screenshot
   check if any of them ever look wrong on hardware.

**Verified live**: the widget loads with no QML errors (`journalctl --user -t
omarchy-shell`, clean); its bar icon genuinely tracks `mode` — toggling via
`omarchy-shell quake-panel setMode kiosk|desktop` and diffing before/after screenshots of
the primary screen's bar isolated the exact icon and confirmed it swaps between the
device glyph and the monitor glyph on every toggle, on the real running plugin (not a
synthetic `TouchRouter.feed()`-style test). **Not yet verified**: actually clicking the
icon and a dropdown row with a real mouse — this machine has no pointer-click simulation
tool available (`ydotool`/`wlrctl`/`dotool` all absent, only `wtype` for keyboard), so
the popup open/close and row-click-to-`setMode()` wiring rests on `PopupCard`/
`BarIconButton`'s own extensively-used first-party behavior plus a source-level read of
the click handler, not a live click. Should be checked with an actual mouse at some
point, though risk is low since nothing here is bespoke touch code.

## 22. A voice agent, "Foxy" — Phase A: manual push-to-talk + one real tool (2026-09-10)

A fourth page, PA, where a real AI agent lives: local speech-to-text (Voxtype, already
running as `voxtype.service`), an actual tool-using agent (`claude -p`, not a plain-text
chatbot), and one real action wired all the way through to the panel's own state. This
is Phase A of a larger brainstormed plan (continuous "Hey Foxy" wake-word mode, spoken
replies via Piper, Home Assistant control — all later phases, deliberately deferred so
this first, riskiest slice — does the whole pipeline even work? — could be proven on
real hardware before building anything on top of it.

**Architecture**: a second, independent daemon, `daemon/src/paBridge.js`, kept separate
from `bridge.js`/`HidBridge.qml` on purpose — an LLM CLI call can take several seconds,
and this heavier, more experimental piece must never be able to block or destabilize the
HID/touch daemon everything else depends on. `Services/PaBridge.qml` wraps it exactly
like `HidBridge.qml` wraps the other one (same JSON-lines stdout / JSON-command stdin
shape); `Services/PaState.qml` is the domain object over it (status, last-heard,
last-reply), same relationship `KnobLighting.qml`/`MicState.qml` have to `HidBridge`.

**Voxtype integration** uses its scriptable, file-based path rather than its normal
type-into-focused-window dictation behavior — no keyboard-injection interception needed:
`voxtype record start --file=<path>` writes the transcript to a plain text file instead
of typing it, and `voxtype record stop --wait --json --timeout 20` blocks until
transcription is final. A dedicated Voxtype config, `~/.config/voxtype/pa.toml` (see
`ops/voxtype/pa.example.toml`), pins the input device explicitly rather than trusting
"default" — see the mic-hardware finding below for what it's pinned to.

**The mic hardware theory from the brainstorm was confirmed live**, and better than
"confirmed" — actually used successfully for a real transcription. `voxtype info
devices` (ALSA-level, not PipeWire's naming) resolved the panel's own mic to
`sysdefault:CARD=Device` — card 0 in `/proc/asound/cards`, the same
"C-Media Electronics Inc. USB PnP Audio Device" `lsusb -t` had already shown sitting
behind the same internal hub as the panel's own vendor touch/HID device. Pinned that in
`pa.toml` and ran a real `startTurn`/`endTurn` cycle through the actual daemon: it
genuinely captured live audio through it (a few seconds of room tone transcribed as
"you" — an expected whisper hallucination on near-silence, not a bug) and produced a
real, in-character reply. The panel's mic is a real, working input device for this
feature, not merely a plausible theory.

**Two things had to be discovered the hard way to make `claude -p` actually call the
tool, both confirmed by testing against the real MCP server and reading source, not
guessed from docs**:

1. **`--append-system-prompt` isn't enough for a real persona.** It only ADDS to Claude
   Code's own default system prompt ("you are Claude Code, a software engineering
   assistant"), it doesn't replace it. A model told to be "Foxy" via append still
   introduced itself as a coding assistant when asked to start a pomodoro, and reached
   for its own `Bash` tool to fake one with `sleep 1500 && notify-send` instead of
   calling the real `start_pomodoro` tool that was sitting right there — confirmed live,
   the exact failure the confirm-before-acting design in the brainstorm was worried
   about, just from the *wrong* tool this time, not a missing confirmation. Fixed by
   `--system-prompt` (a full replacement) instead — worked immediately.
2. **A non-interactive `-p` call still runs Claude Code's normal permission system, and
   there's no human to click "allow."** Even with the persona fixed and only the MCP
   tool exposed, the very first real call came back as `permission_denials:
   [{"tool_name":"mcp__quake-panel__start_pomodoro", ...}]` — the model tried to call
   the right tool and was blocked by the same approval gate an interactive session would
   show a dialog for. Fixed with `--allowedTools mcp__quake-panel__start_pomodoro`
   (confirmed live: MCP tool names are qualified as `mcp__<serverName>__<toolName>`,
   matching the server name in `--mcp-config`, not documented anywhere obvious — found
   by reading the `permission_denials` field's own `tool_name`). `paBridge.js` keeps
   this as a small `ALLOWED_TOOLS` array specifically so later phases add to it rather
   than re-discovering this.

Also worth remembering: **running `claude -p` FROM WITHIN an active Claude Code session
inherits that session's own `CLAUDE_CODE_*` environment and reflects back its outer
tool list** — several early manual tests done this way looked broken or contradictory
(a fresh `-p` call claiming access to `ListAgents`/`CronCreate`/etc., or claiming zero
tools) purely because of this nesting artifact, not real Claude Code behavior. The real
daemon is launched by `omarchy-shell` (itself started by Hyprland/systemd at login), a
completely unrelated process tree with none of that — the one test that mattered was
running the ACTUAL `paBridge.js` daemon standalone via `node`, not another hand-rolled
`claude -p` invocation from inside this coding session. **One more real trap this
caught**: an early hand-written MCP config file used a *relative* path to
`paTools/server.js` and failed silently ("the quake-panel server isn't connected right
now") — `paBridge.js`'s own `writeMcpConfig()` was already correct (built from
`path.join(__dirname, ...)` inside a real file, not a `node -e` snippet where
`__dirname` doesn't mean what it looks like it means), but it's exactly the kind of thing
worth double-checking again if the "not connected" message ever reappears.

**Also added**: `PersonalCareState.startPomodoro()` — idempotent (only starts if not
already running), distinct from `togglePomodoro()` which would wrongly *pause* an
already-running session if the agent (or anything else external) called it while a
pomodoro was in progress. `Service.qml`'s `IpcHandler` gained `startPomodoro()` so the
MCP tool (`daemon/src/paTools/server.js`) reaches it the exact same way every other
external toggle surface reaches this plugin — `omarchy-shell quake-panel startPomodoro`
— not a separate code path invented for the agent. `KnobRouter.qml`'s per-page `press`
table gained a fourth entry, `pushToTalk`, reusing the existing per-page-press mechanism
rather than inventing a new hold-length gesture (the plan's original idea) — a knob
press is already a discrete, page-scoped action here, and Voxtype has its own "toggle"
push-to-talk mode for exactly this shape (press to start, press again to send), so this
needed no new gesture vocabulary at all, on the knob or the on-screen `Talk` button.

**Verified live**: MCP server responds correctly to a raw stdio handshake
(`initialize`/`tools/list`); the real `paBridge.js` daemon runs a full
`startTurn`→`endTurn`→transcript→`claude -p`→reply cycle against the real Voxtype
service and the real `claude` CLI; `startPomodoro()` flips the real
`personal-care.json` state (verified via a temporary debug IPC hook, removed before
finishing, per this project's usual pattern); the PA page renders correctly on the real
panel (screenshot, `capture-panel.sh`-style geometry) — ghost/ready header, "Press Talk
and ask for something" placeholder, working `Talk` button matching every other page's
`PanelButton` styling. **Not yet verified**: actually pressing the on-screen button or
the knob with a real finger/hand and speaking a real request — the daemon-level
plumbing is proven, but nobody has done the physical gesture yet. Text-only reply only
(Phase B adds spoken output); no continuous/wake-word mode yet (Phase C).

## 24. "Foxy" gets a voice — Phase B: spoken replies via Piper (2026-09-10)

Phase B of the PA design (§22): the agent's reply is now spoken aloud, not just shown on
the page. `daemon/src/paBridge.js` gained one function, `speak(text)`, called right
after emitting the `reply` event — no QML changes needed beyond `PaPage.qml`'s `heroMeta`
learning about a new `"speaking"` status string, since `PaState.qml`'s status handling
was already a generic pass-through.

**Piper (piper1-gpl, the actively-maintained OHF-Voice fork — the original
rhasspy/piper is superseded) has no official Arch package; the AUR one, `piper-tts`,
needed sudo the user ran themselves** (this session can't authenticate interactively).
While waiting, verified the whole pipeline with a `pip install --user` copy plus a
`~/.local/bin/piper-tts` symlink — a deliberately temporary stand-in for exactly the
same binary name the real package installs, removed once the AUR install lands (`/usr/
bin` precedes `~/.local/bin` on `$PATH` here, so the real package transparently takes
over the same command name without any code change once it exists). **The AUR
package's own PKGBUILD renames its binary from `piper` to `piper-tts` at package time**
specifically to avoid colliding with an unrelated GTK gaming-mouse configuration tool
already named `piper` in the official `extra` repo — confirmed by reading the PKGBUILD
itself, not guessed; `paBridge.js` calls `piper-tts`, never bare `piper`, because of
this.

**Voice model**: `en_US-lessac-medium`, fetched once via `python -m
piper.download_voices en_US-lessac-medium --download-dir ~/.local/share/piper/voices`
— Piper's own bundled downloader, not a manual URL, and not fetched automatically by
the daemon itself (same reasoning as Voxtype's whisper models: a multi-hundred-MB
download has no business happening silently inside a daemon's normal startup path).

**Output device pinned explicitly**, same reasoning as `pa.toml` pinning the input
device: `paplay --device <sink>` with the laptop's own speaker's exact PipeWire sink
name (`pactl list short sinks`), not whatever the system default happens to be — a
plugged-in HDMI display can silently change that default, which would make Foxy
inaudibly "speak" into a monitor nobody has speakers connected to. Both new external
tool paths (`PIPER_BIN`, `PIPER_MODEL`, `SPEAKER_SINK`) are overridable via
`OQP_PA_*` environment variables for a different machine.

**Verified**: a full real `startTurn`→`endTurn`→transcript→`claude -p`→reply→`speak()`
cycle through the actual `paBridge.js` daemon produced a valid WAV (correct sample
rate/duration for the reply text) and `paplay` exited cleanly against the real speaker
sink; the same cycle triggered through the real installed plugin via IPC produced no
QML errors. **Not yet verified**: actually hearing it — this session can run processes
and inspect their output/exit codes, but has no ears. Ask on next contact whether "Hey
there! What can I help with?" was audible from the laptop speaker.

## 26. "Hey Jarvis" — Phase C: continuous wake-word mode (2026-09-10)

Phase C of the PA design (§22): a "Listen for wake word" button (`Pages/PaPage.qml`)
arms continuous listening, shown as a small pulsing dot in `Ui/PageHeader.qml` — the one
piece of chrome shared by every page, since continuous mode keeps listening no matter
which page is on screen. Verified with **real acoustic loopback**, not a synthetic
event injection: a "Hey Jarvis" clip played through the laptop's own speaker, picked up
by the panel's mic, correctly triggered a real turn through the actual running plugin —
repeated several times across this section's debugging, including one full cycle that
correctly called `start_pomodoro` for real.

**The wake word is "Hey Jarvis," not "Hey Foxy."** openWakeWord's pretrained models are
for specific stock phrases (alexa, hey mycroft, hey jarvis, hey rhasspy); "Hey Foxy"
needs custom training, and the supported path for that is Google's Colab (a whole
separate manual undertaking — a Google account, a browser session, real wall-clock
time). Deliberately deferred rather than blocking Phase C's actual architecture on it —
"Foxy" stays the spoken persona regardless of which phrase wakes it, and swapping in a
real custom model later is a one-line change to `wakeword.py`'s `MODEL_PATH`/`MODEL_KEY`,
not a redesign.

### Architecture: wake-word listener as a one-shot handoff, not a continuous VAD

`daemon/src/paTools/wakeword.py` (Python — openWakeWord is Python/ONNX) does exactly one
job and exits: spot the phrase on the panel's mic, print `{"event":"wake"}`, done.
`paBridge.js` relaunches it after every turn finishes, if continuous mode is still on.
This shape — rather than a long-running listener that also handles the ongoing
turn — exists specifically so the listener and Voxtype's own recording are **never open
on the same device at the same time**, sidestepping any question of whether this
machine's ALSA setup actually shares capture across processes (`dsnoop`) or not.

**A wake-triggered turn records for a fixed window (`CONTINUOUS_TURN_MS`, 6s default),
not until silence is detected.** There's no manual "release" the way the button/knob
gesture has one. Checked Voxtype's own `config schema` for a silence/VAD auto-stop
option before building this — it only has a hard `max_duration_secs` safety cap
(default 60s) and a post-hoc silence-only-recording filter, nothing that shortens a
recording early. Real VAD-based endpointing (reusing the same mic stream the listener
already has open to also judge when the user stopped talking) was considered and
rejected for v1: it re-introduces exactly the concurrent-mic-access question the
one-shot handoff design exists to avoid. The trade-off is honest, not hidden: a short
request leaves a little dead air before Voxtype stops recording; a long one could
theoretically get cut off. Worth revisiting if 6s proves wrong in practice.

### Two real bugs found via extensive live testing, not from reading the code

1. **A leftover `wakeword.py` process survives `omarchy-restart-shell` as an orphan.**
   Confirmed by directly inspecting process parentage (`ps -o pid,ppid,lstart`): after a
   restart, a still-running listener's PPID pointed at a node process that no longer
   existed under that PID — a straggler from a previous daemon generation, still
   holding the mic, fighting the new daemon's own fresh listener for the same device.
   This is what caused every intermittent `Invalid sample rate [PaErrorCode -9997]`
   error seen while building this feature — not really a "handoff timing" race at all
   (though `MIC_HANDOFF_DELAY_MS`/the retry logic are still worth keeping as real
   defense-in-depth for genuine timing races). **Root cause**: `omarchy-restart-shell`
   killing the old quickshell/daemon tree does not reliably cascade to this daemon's own
   *grandchild* processes. **Fixed** with a startup-time cleanup in `paBridge.js`:
   `pkill -9 -f <the exact wakeword.py path>` before doing anything else, every time the
   daemon boots, so a leftover from any previous generation can never linger into a new
   one. Confirmed via direct process inspection (no orphan survives a restart anymore).
2. **`SIGTERM` alone isn't reliable against this specific process.** Both the startup
   cleanup and `stopListener()` use `SIGKILL`, not `SIGTERM` — confirmed live that a
   `pkill`/`.kill()` without `-9` didn't reliably stop an instance blocked in a
   PortAudio/ALSA wait, which likely simply doesn't notice `SIGTERM` until it exits that
   call on its own. Nothing in this script has state worth flushing on the way out, so
   an abrupt kill costs nothing.

### One layout bug, also found live

The conversation `Column` (`PaPage.qml`) has no natural height limit, and Claude's
replies have no natural length limit — a longer reply visually overlapped the
bottom-anchored button row (`Section.qml`'s content area has no idea where the button
row sits; it just sizes to fit its children). Same fixed-vertical-budget lesson this
project has hit before on other pages (§11, §19), just the first page where the content
itself is unbounded rather than a couple of known-short lines. Fixed with
`maximumLineCount: 4` + `elide: Text.ElideRight` on the shared `Line` component, caught
and confirmed fixed via a live screenshot with a genuinely long reply.

### A UX polish found live: stale errors

A transient error (e.g., one of the mic-handoff races above, before the orphan-process
root cause was found and fixed) stayed on screen indefinitely — nothing ever cleared
`PaState.lastError` once the system had actually recovered on its own, so a
long-resolved problem could still look like a current one. Fixed by clearing it on
every fresh `"listening"` status transition, not just `beginTurn()`'s manual-path
clearing — a wake-triggered turn goes through the same status transition, so it gets
the same clean slate.

### On the testing methodology itself

Every acoustic test in this section used **Piper-synthesized speech**, not a real human
voice — a deliberate choice (no human available to speak during automated testing), and
it worked well for the wake word itself (openWakeWord's own models are trained on
100% synthetic TTS data, so this is a legitimate signal, not a toy test) but produced
some genuinely funny whisper mis-transcriptions of the follow-up command ("start the
pomodoro" → "start the motor wheel" → "start to promote the room") — TTS diction
artifacts, not representative of real speech, but still a good incidental test of the
system prompt's "ask a brief clarifying question instead of guessing" instruction:
Claude asked sensible clarifying questions every time rather than mis-firing the
`start_pomodoro` tool on a garbled transcript, exactly the behavior wanted. **Real human
speech was already confirmed working** for the manual push-to-talk path back in Phase
A/B (the user's own "I tried it, it is working" after this session's Phase A+B work) —
continuous mode's wake-word *detection* and *turn mechanics* are now proven for real,
but nobody has yet said "Hey Jarvis" out loud and spoken a real follow-up command in one
breath.

## 27. FOXY: the page rename, and a real fox icon (2026-09-10)

Three small polish requests after Phase C: rename the page from "PA" to "FOXY", replace
its ghost icon with "a cool fox icon," and reword the continuous-mode button away from
naming "Hey Jarvis" directly (`Ui/PageHost.qml`'s `pages[]` title, and
`Pages/PaPage.qml`'s section icon + `button2` text).

**No Nerd Font icon set has a generic fox** — checked directly against the font's own
glyph names (`fontTools`' `getGlyphOrder()`), not guessed from a codepoint name the way
earlier icon mistakes happened (§20). The only "fox"-named glyphs anywhere are
`seti-firefox`/`dev-firefox`/`fa-firefox`/`md-firefox` — the trademarked Firefox browser
logo, which would misleadingly brand this page as browser-related. Asked the user how
to handle this rather than guessing; while waiting, found a better answer than any of
the offered options: **🦊 (U+1F98A) is a real Unicode emoji**, already covered by Noto
Color Emoji (already installed on this machine — `fc-list | grep -i emoji`). Verified
live that Qt's own font-fallback renders it in full color inside this app's existing
`Text`-based icon slots, despite the surrounding theme font being a plain monospace
with zero color-emoji glyphs of its own — no architecture change needed, just using the
character. This is the first non-Nerd-Font icon anywhere in this project; if a future
icon need hits the same "doesn't exist in Nerd Fonts" wall, checking for a plain
Unicode emoji first is worth trying before reaching for an external image asset.

## 28. FOXY polish round two: page order, grayscale icon, no duplicate, a spacer (2026-09-10)

Four follow-up requests after §27's rename:

1. **Page order**: FOXY moved between Self Care and Settings (was last). `Ui/PageHost.qml`'s
   `pages[]` array order and its `sourceComponent` switch, and `Services/KnobRouter.qml`'s
   `modeTable[]` (per-page knob-press actions are index-keyed, so reordering pages means
   reordering this table too, or the wrong page would get the wrong knob behavior) all
   had to move together.
2. **Grayscale fox icon**: the 🦊 emoji ignores `Text.color` entirely — confirmed live
   (set to `theme.foreground`, rendered its natural orange regardless) — because a
   color-emoji glyph carries baked-in color data (COLR/CBDT tables) that a plain text
   color property has no power over. Fixed with `QtQuick.Effects`' `MultiEffect`
   (`saturation: -1.0`) wrapping the icon `Text` (`layer.enabled: true` on the source,
   `visible: false` so only the effect's output paints) — this operates on the actually
   *rendered pixels*, so it works regardless of how the glyph itself draws itself, and
   costs nothing on the three other pages' plain monochrome Nerd Font icons (desaturating
   an already-gray image is a no-op). Confirmed `QtQuick.Effects` is genuinely present in
   this Quickshell/Qt6 install (`/usr/lib/qt6/qml/QtQuick/Effects`) before relying on it —
   this is the first use of a graphical-effects module anywhere in this project.
3. **No more duplicate FOXY + fox icon on the page itself**: `Pages/PaPage.qml`'s own
   `Section` had reused "🦊"/"FOXY" as its own header, on top of the identical pair
   already in the shared page header (`Ui/PageHeader.qml`) — genuinely redundant, and
   also an inconsistency with every other page's own convention (Personal Care's
   sections say POMODORO/WATER/STAND, not "Self Care" three times; Settings says KNOB
   COLOR/etc., not "Settings"). Replaced with a content-descriptive icon+label instead —
   a message-bubble glyph + "CONVERSATION" — matching that established pattern.
4. **A spacer between the page-name tabs and the clock**: `Ui/PageHeader.qml`'s
   `trailing` Row applies its own `spacing` uniformly between every child already; added
   a plain fixed-width `Item` between the page-indicator Row and the
   continuous-dot/clock group so that gap reads as deliberately larger than the gap
   between the dot and the clock itself, rather than one continuous evenly-spaced run.

Verified live via screenshot: page order (SYSTEM · SELF CARE · FOXY · SETTINGS), the
header's fox rendering in clean grayscale, the page body now reading "CONVERSATION"
with no repeated fox/FOXY, and a visibly wider gap before the clock.

## 29. Phase D: real Home Assistant control (2026-09-11)

The last phase of the PA design (§22): FOXY can now actually control real Home
Assistant devices — lights, switches, climate, and locks (the four domains the user
chose) — gated behind a propose-then-confirm flow, exactly as the original brainstorm
specified. Five new MCP tools in `daemon/src/paTools/server.js`:
`list_ha_entities` (read-only lookup by domain), `propose_ha_action` (records what's
being asked for, performs nothing), `confirm_pending_action` (the only tool that
actually calls Home Assistant), and `cancel_pending_action`. Credentials
(`homeAssistant.url`/`token` in `~/.config/omarchy-quake-panel/config.json`, outside
the repo) come from a real Home Assistant long-lived access token the user generated by
hand — confirmed live against the user's own real instance, not a mock.

**A real gap in the confirm-gate design, found before it shipped, not after**: nothing
about MCP's own mechanics stops a single `claude -p` call from making several tool
calls back-to-back, all before the process ever returns text to the human. The
brainstormed design's whole safety premise — "only confirm after the user's *next*
turn contains a yes" — assumed a real round trip back to a human between propose and
confirm, but nothing enforced that; a model could propose and confirm inside one
response and the human would never see the question. Fixed with a code-level check, not
a stronger prompt: `daemon/src/paBridge.js` gives every separate `claude -p` invocation
(one per user utterance) a distinct `OQP_PA_TURN_ID` environment variable (a simple
incrementing counter); `propose_ha_action` stamps the pending action with it, and
`confirm_pending_action` refuses if the confirming call's own turn ID matches the one
that proposed it. Verified directly at the protocol level (raw MCP `tools/call`
requests with a hand-set `OQP_PA_TURN_ID`) before ever letting a real model near it:
same turn ID → refused with no Home Assistant call made; different turn ID → allowed
through.

**Verified against the user's real Home Assistant instance, with the user's explicit
go-ahead before any real device state changed** (a live smart-home action is a
real-world side effect, not a harmless local test) — the user picked which device to
use rather than leaving that to guesswork:

- `list_ha_entities` returned real entities from the user's own instance.
- The turn-ID gate was verified in isolation first (same-turn confirm rejected, no HA
  call attempted).
- A full real two-turn `claude -p` conversation (not a hand-driven protocol call) —
  "turn on \<device\>" then, in a resumed session, "yes" — correctly looked up the
  entity, proposed, waited, and only called Home Assistant after the second message
  arrived. Confirmed via Home Assistant's own state endpoint before and after each
  step: unchanged after turn one, actually flipped after turn two. Restored to its
  original state immediately after.
- Domain/service allow-list rejections confirmed too (an unlisted domain like
  `automation`, and a disallowed service like `delete` on an allowed domain, are both
  refused before a pending action is ever written).
- One real device happened to have an integration that returned a genuine HTTP 500 from
  Home Assistant itself on a normal `turn_on` call — not a bug in this project's code
  (the gate, the request construction, and the error handling all behaved correctly;
  Home Assistant's own backend for that specific entity is what failed), confirmed by
  checking the entity's state was unchanged after the 500 and successfully controlling
  a different entity of the same domain right after.

**Deliberately not a generic "call any Home Assistant service" tool** — `propose_ha_action`
validates `entity_id`'s domain and the requested service against a small hardcoded
allow-list (`HA_ALLOWED_SERVICES`) before ever writing a pending action, rejecting
anything outside lights/switches/climate/locks and their basic on/off/toggle/
set_temperature-style actions. The whole point of the confirm gate is undercut if the
thing being confirmed could be arbitrary.

No QML changes needed for this phase — it's purely new tool-calling capability, surfaced
through the same conversation transcript UI Phase A already built.

## 30. A 3D audio-reactive particle cloud on the FOXY page (2026-09-11)

The user asked for a visual companion to FOXY's conversation area, inspired by a
Three.js/WebGL audio-reactive particle demo: a 3D particle cloud, occupying the right
1/5 of the page, reacting to both the user's own speech and FOXY's replies. This app is
Qt Quick/QML inside Quickshell, not a browser, and this project already has a
documented, hard-won reason not to try embedding a real web engine (§3/§4's
`WebEngineView` crash) — so rather than chase that dead end again, this is a
from-scratch equivalent built on Qt's own native 3D module, `QtQuick3D`/`Particles3D`.

**The single biggest unproven risk going in**: nothing in this project had ever put a
`View3D` inside Quickshell's own scene before. It's a different rendering technology
than `WebEngineView` (a native Qt Quick item, not an embedded browser engine) so there
was no specific reason to expect the same crash — but "no specific reason to expect it"
isn't the same as "confirmed safe," so the plan's first step, before building anything
else, was proving a minimal `View3D` scene renders inside the real installed plugin at
all. **It did, on the first real attempt** — no crash, confirmed via
`omarchy-restart-shell` + `journalctl --user -t omarchy-shell` + a real screenshot of
the FOXY page with the particle cloud rendering and idling correctly.

**New system dependency**: `qt6-quick3d` (official Arch `extra` repo, ~21MB) — not a
default Quickshell/Omarchy dependency, sudo-gated the same way `piper-tts` was, so the
user installed it by hand (`sudo pacman -S qt6-quick3d`) before any of this QML could
even load. Confirmed genuinely absent beforehand and genuinely present after, with
`ParticleEffects`/`Particles3D`/`Helpers`/`AssetUtils` all present under
`/usr/lib/qt6/qml/QtQuick3D/`.

**Reactivity is asymmetric on purpose, a deliberate scope decision the user agreed to
up front, not an oversight**:

- FOXY's own reply gets *real* reactivity — `daemon/src/paBridge.js`'s `speak()` reads
  Piper's finished WAV file (a hand-rolled RIFF/WAVE parser, no new dependency — the
  same mono 16-bit PCM format already confirmed in §24), computes an RMS volume
  envelope over ~30 windows/sec normalized against the clip's own peak, and streams it
  to QML as `{"t":"audioLevel","value":0..1}` events timed to match `paplay`'s actual
  playback, stopping when playback's own exit callback fires. Real reactivity is
  possible here specifically *because* this app generates that audio itself and can
  measure it exactly before a single sample plays.
- The user's own voice while `status === "listening"` gets a generic ambient "breathing"
  pulse instead — deliberately **not** a real mic tap. §26's whole wake-word-listener
  saga already established the panel's mic as a carefully single-consumer-at-a-time
  resource between Voxtype and the wake-word listener; a third live consumer during a
  recording risked reintroducing that exact flakiness for what would only ever be a
  decorative effect. The user chose this trade-off explicitly when asked.

**Built entirely from Qt's own primitives, no new asset files**: the particle cloud uses
`ModelParticle3D` with Qt's built-in `"#Sphere"` mesh (via a plain `Model`), not
`SpriteParticle3D` — a sprite particle needs a texture image, and this project has never
had an image asset anywhere (every existing visual is a Nerd Font glyph, a flat color,
or plain shapes); reusing a built-in primitive mesh keeps that true here too. Flat-shaded
(`PrincipledMaterial.NoLighting`) to match the app's flat/no-gradient design language
rather than introducing a new lit-rendering look nothing else on the panel uses. Exact
QML type/property names (`ParticleSystem3D`, `ParticleEmitter3D`, `ParticleShape3D`,
`VectorDirection3D`, `Wander3D`, `ModelParticle3D`'s actual property list, etc.) were
verified against the installed module's own `plugins.qmltypes` metadata before writing
any QML, not guessed from memory or general Qt familiarity — the same "verify, don't
guess" discipline this project has followed since earlier icon-glyph mistakes.

**Files**: `shell/Ui/FoxyVisualizer.qml` (new — the `View3D`/`ParticleSystem3D` scene);
`daemon/src/paBridge.js` (WAV envelope extraction + timed `audioLevel` events in
`speak()`); `shell/Services/PaBridge.qml` (new `audioLevel` signal, parsed from the
existing stdout line handler); `shell/Services/PaState.qml` (new `audioLevel` property,
updated via the existing `_bridgeConn` pattern); `shell/Pages/PaPage.qml` (the previous
single full-width conversation `Section` is now one child of a `Row`, alongside a new
`FoxyVisualizer` taking the remaining 1/5 width).

**Verified live, in layers, matching the plan's own build order**:

1. The WAV-envelope math confirmed correct in isolation against a real Piper-generated
   file (a realistic speech-shaped envelope, not silence or clipping).
2. The full daemon confirmed to actually stream `audioLevel` events in real time during
   real `paplay` playback, roughly in sync with the audio's real duration.
3. A real conversation turn on the real panel, screenshotted during FOXY's actual
   spoken reply and compared directly against an idle-state screenshot (tight-cropped,
   excluding the card border to avoid polluting the comparison) — the particle cloud is
   visibly denser, larger, and brighter during real speech than at idle. Idle motion
   (a constant `Wander3D` drift, amplified but never absent, so a frozen field never
   reads as broken) and the listening-state ambient pulse were also confirmed rendering
   correctly.

Not yet tried: a full real spoken conversation through the wake-word path specifically
exercising this visual (all of this session's live verification used push-to-talk turns
and Piper's own synthesized speech for FOXY's side, which is exactly what drives the
real reactivity anyway). Push-to-talk itself is removed in §31, below.

## 31. FOXY redesign: one power control, auto-follow-up listening, a real scrolling transcript (2026-09-11)

The FOXY page had grown two separate on/off controls (manual push-to-talk "Talk", and a
"Continuous Mode" toggle) and showed only the single last exchange. This reworks the
interaction model into one clear control, a more natural back-and-forth, and a real
conversation history — see the approved plan for the full design; this section covers
what shipped and what was verified.

**One power control.** The Talk button and `PaState.togglePushToTalk()` are gone —
`continuousMode` (still the same backend `startContinuous`/`stopContinuous` commands) is
now the only "is Foxy on" concept anywhere in the UI. `Pages/PaPage.qml` is two sibling
branches inside the `Card`, visibility driven by `continuousMode`: **off** shows nothing
but a single centered "Turn Foxy on" button — no header, no conversation, no
visualizer, confirmed live via screenshot (the request was explicit that the off page
should show *only* the button); **on** shows the existing CONVERSATION `Section` + 3D
visualizer `Row`, with the old button pair replaced by one "Turn Foxy off" button.
`Services/TouchRouter.qml`'s own `_hitTestIn` already skips `!item.visible` targets, so
toggling `visible` between the two branches needed no special (un)registration handling.
The knob's per-page press action (`Services/KnobRouter.qml`) changed from
`pushToTalk` to `foxyToggle` — a physical press now toggles Foxy on/off, mirroring how
a knob press already toggles the Pomodoro on the Personal Care page. **Confirmed working
by the user's own physical knob press**, not just IPC/code-reading. Confirmed with the
user before building: pressing "Turn Foxy on" arms the wake-word listener but does
**not** skip straight to listening — "Hey Jarvis" (soon "Hey Foxy," see below) is still
needed for the first request, same as any later unprompted turn.

**Auto-listen after Foxy asks a question.** `daemon/src/paBridge.js`'s `finishTurn()`
used to unconditionally re-arm the wake-word listener once a turn ended. Now, right
before `speak()` is called in `askClaude()`'s success path, a single-shot
`autoListenAfterReply` flag is set from a simple heuristic — does the trimmed reply end
in `?` (allowing trailing quote/parenthesis characters) — deliberately not a second
model call or structured-output field, matching this project's existing preference for
honest, simple heuristics over more machinery (the fixed-duration recording window
instead of real VAD, §26, is the precedent). `finishTurn()` consumes that flag exactly
once: if set, it calls `startTurn()` directly (skipping the wake word) with the same
fixed-window `continuousTurnTimer` the wake handler itself already uses; otherwise it
re-arms `startListener()` as before. The flag is also cleared defensively at the top of
`startTurn()` and in `cancelTurn()`. **Verified live, real end-to-end, twice**: a real
"Hey Jarvis" + a prompt engineered to make Foxy ask something back ("What would you like
help with?" / "What's your favorite color?") both put the daemon straight into
`"listening"` status immediately after Foxy finished speaking — confirmed via a live
screenshot showing the header meta at "Listening…" with no wake phrase in between, and
via the transcript itself showing the sequence. One of the two follow-up windows timed
out with "Nothing transcribed" (a genuine test-methodology timing miss on my end, not a
code defect) and the daemon correctly fell back to re-arming the wake-word listener —
which then hit the already-documented, already-mitigated transient `Invalid sample rate
[PaErrorCode -9997]` ALSA race (§26) and recovered on its own via its existing retry,
confirmed by checking a fresh `wakeword.py` process was running moments later.

**A real scrolling transcript.** `PaState.qml`'s `lastHeard`/`lastReply` (each
overwritten every turn) are replaced by a `ListModel` `transcript` of
`{role, body}` entries (`body`, not `text` — a `ListView` delegate that's itself a
`Text`-derived item can't declare a `required property string text`; it collides with
`Text`'s own built-in property, caught before ever deploying), appended via a new
`_appendLine()` helper wired into the existing `onTranscript`/`onReply`/`onDaemonError`
handlers. Cleared whenever Foxy is turned off (a purely visual reset — the daemon's own
`--resume` session memory is untouched). `PaPage.qml` renders it with a `ListView`
(`interactive: false` — real touch never reaches native flick gestures on this
layer-shell surface anyway, per `TouchRouter.qml`'s own documented Hyprland bug, so
scrolling here is deliberately automatic-only via `onCountChanged: positionViewAtEnd()`,
never a manual drag). **This needed a real fix to `Ui/Section.qml`**, not a page-local
workaround: its `content` area used to be part of one intrinsic-sized `Column` with the
header, so a `ListView` inside it had no real viewport height to scroll within — the
exact class of bug already hit once before (§26's overlapping-button-row wart, from
unbounded content with no idea where the button row sat). Fixed at the root: `content`
now lives in its own `Column`, anchored `top: header.bottom` / `bottom: buttonRow.top`,
so it always gets exactly the space between the separator and the buttons, filled or
not. Existing `Section` consumers (`PersonalCarePage.qml`, `SettingsPage.qml`) pass
plain `Text`/`HeroText`/`DetailText` content with no anchors of their own, so this is a
no-op for them — confirmed via side-by-side screenshots of both pages showing no visual
change. **Verified live**: the real acoustic test above produced four transcript lines
across two turns (not just the last one), and the view visibly auto-scrolled to keep the
newest line in frame as it grew past the visible area.

**"Hey Jarvis" → "Hey Foxy," code side done, training still pending.** A trained
"Hey Foxy" model needs openWakeWord's own Colab training notebook — a manual, external
step (a Google account, a browser session; the notebook synthesizes its own training
audio, no microphone recording required) that only the user can do. Made the swap a
config change rather than a future code edit: `daemon/src/paTools/wakeword.py`'s
`MODEL_PATH`/`MODEL_KEY`/`THRESHOLD` are now `OQP_PA_WAKEWORD_MODEL`/
`OQP_PA_WAKEWORD_MODEL_KEY`/`OQP_PA_WAKEWORD_THRESHOLD` env vars (same pattern as
`PIPER_MODEL`/`OQP_PA_SPEAKER_SINK`), defaulting to today's stock "Hey Jarvis" model
until all three are set. Still says "Hey Jarvis" everywhere in code/docs on purpose —
that gets updated once a real trained model is actually in place and verified working
via the same real acoustic-loopback method already used for "Hey Jarvis," not before.

## 32. The microphone is now gated by Foxy's own on/off state (2026-09-11)

The Settings page had a separate, manual mic on/off toggle (`Services/MicState.qml` +
a `Section` on `Pages/SettingsPage.qml`) — independent of whether Foxy was even armed
to listen. Removed: the mic is now off by default and live only while Foxy is on,
with no separate switch that could disagree with that. `Service.qml`/`shell.qml` call
`micState.setOn(paState.continuousMode)` directly — once when the daemon connects
(forcing a clean default regardless of whatever the hardware was left at from a
previous session) and again on every `continuousMode` change, mirroring the exact
dual-trigger shape `Service.qml`'s own `_syncVirtualTouch` already used for a similar
cross-service sync (§18). `Pages/SettingsPage.qml`'s lower row is now a two-column
split (Knob Light Brightness / Screen Brightness) instead of three.

**A real race found and fixed before it shipped**, not after: `MicState.qml` used to
also auto-query the hardware's mic state on every connect (`refresh()`, mirroring
`KnobLighting.qml`'s own `getLighting`), for the Settings page's now-removed on/off
display. That query and the new authoritative `setOn()` call both fire off the same
`hidBridge.connected` signal — confirmed live that the query's reply, being async, could
arrive *after* `setOn()` already ran, silently overwriting the correctly-commanded
value with whatever stale state the hardware had from before (`debugMicState()`, a
temporary debug hook, showed `on: true` at boot despite `setOn(false)` having just been
called). Since nothing reads `MicState.on`/`.loaded` for display anymore, the query
served no purpose but to create that race — removed at the root (no more auto-query on
connect) rather than papered over with a timing guess, and reconfirmed clean afterward:
`off` at boot, `on` immediately after activating Foxy, `off` again immediately after
deactivating.

## 33. "Hey Jarvis" is finally "Hey Foxy" (2026-09-14)

The interim stock wake phrase from §26 is real now — a custom-trained model, and a
different training tool than originally planned.

**openWakeWord's own training notebook turned out to be badly bit-rotted.** Working
through it cell-by-cell (per the user's own request, to see and paste each error rather
than run it blind) surfaced a long chain of real, unrelated version-drift breaks against
Colab's current environment: no `cp313` wheels for `piper-phonemize`/`speexdsp-ns`
(fixed with a Python 3.11 `uv`-managed venv, since those wheels only go up to
cp311/cp312), `tensorflow-cpu`/`onnx_tf`/`tensorflow-addons` all unavailable (confirmed
via the actual `train.py` source that these are only used by an optional, never-invoked
`--convert_to_tflite` path — skipped entirely, no functional loss), `datasets==2.14.6`
broken against current `pyarrow` (`pa.PyExtensionType` removed) and then, after
upgrading, broken a *different* way against `torchcodec`-based audio decoding a newer
`datasets` release now requires by default (fixed by pinning `datasets==3.6.0`, the last
release before that switch, verified against the actual GitHub history rather than
guessed), `scipy` removing `sph_harm` (used by the long-abandoned `acoustics` package;
pinned `scipy<1.17`), a Colab `MPLBACKEND` environment variable leaking into the
training subprocess and breaking `matplotlib` import (overridden per-invocation), the
`agkphysics/AudioSet` dataset repo's raw `.tar` shards replaced by Parquet entirely (404,
rewritten to stream a fixed sample count instead), `rudraml/fma`'s own loading script
incompatible with current streaming internals (`Cannot seek streaming HTTP file` — FMA
dropped for this training pass rather than fought further), and finally
`piper-sample-generator`'s own repo restructuring `generate_samples.py` into a package
(fixed by pinning to the commit right before that change). Every one of these was
diagnosed from the real upstream source before proposing a fix — not guessed — but the
sheer number of independent breaks in one inherited notebook made it clear this
particular tool had drifted too far from anything still routinely exercised by its own
maintainers.

**Training moved to a different, actively-maintained tool**: nanowakeword
(`github.com/arcosoph/nanowakeword`), via its own Colab notebook — the user's own find,
after this session flagged the version-drift wall as a real cost/benefit question worth
stopping on rather than continuing to fight cell-by-cell.

**This changed the integration, not just the source of the model file.** nanowakeword
has its own inference API (`nanowakeword.NanoInterpreter`), not openWakeWord's
(`openwakeword.model.Model`) — confirmed by reading its actual source
(`nanointerpreter.py`), not just its README example. `daemon/src/paTools/wakeword.py`
was rewritten accordingly: `from nanowakeword import NanoInterpreter`,
`NanoInterpreter.load_model(MODEL_PATH)` in fully-local single-model mode (no
cascade/gate, no remote verifier — those exist for genuinely low-power edge devices,
not this machine's ordinary laptop CPU), and `interpreter.predict(frame).score` in place
of `model.predict(frame).get(MODEL_KEY, 0.0)` — simpler than before, since
`DetectionResult.score` already resolves to the one loaded model with no key lookup
needed. `MODEL_KEY`/`OQP_PA_WAKEWORD_MODEL_KEY` are gone (nothing to key). A plain `pip
install nanowakeword` pulls in only `numpy`+`onnxruntime` as hard dependencies (verified
via its PyPI metadata) — training-only dependencies (`torch`, `scipy`, `acoustics`,
etc.) sit behind a `[train]` extra never installed here, keeping the daemon's own
inference-time footprint as light as `openwakeword` was.

**The model file itself is committed to the repo**, not kept as an external download —
`daemon/src/paTools/models/hey_foxy.onnx` (266KB), alongside a distilled `hey_foxy_lite.onnx`
(a "gate" model for nanowakeword's optional low-power cascade mode — not used by this
deployment, kept in case a future low-power satellite mic ever wants it) and
`hey_foxy.pt` (the raw PyTorch checkpoint, kept only in case retraining/re-exporting is
ever needed — not used by the runtime). All three are small enough that this cost
nothing. Unlike Piper's voice model (a generic, anonymously re-downloadable asset,
deliberately kept outside the repo), this is a one-of-a-kind artifact from the user's
own training run that nobody could regenerate without redoing all of the above — the
user's own call, and the right one. `wakeword.py`'s `MODEL_PATH` now resolves relative
to the script itself by default (`OQP_PA_WAKEWORD_MODEL` still overrides it for anyone
who trains a different phrase later), so a fresh clone just works with no separate
download step.

**One real first-run behavior worth knowing about**: `NanoInterpreter.load_model()`
lazily downloads two small shared preprocessing models (`melspectrogram.onnx`,
`embedding_model.onnx`, ~2.4MB total) into the `nanowakeword` package's own install
directory the first time it ever runs on a machine — confirmed live. Needs internet
access once; cached under site-packages after that, surviving every later run.

**Verified live, real acoustic loopback, twice**: a real "Hey Foxy" utterance (Piper TTS
— the same legitimate-signal reasoning as §26's "Hey Jarvis" test, and this model was
itself trained on Piper-synthesized data, so if anything this is a more representative
test than before) correctly fired a real wake event through the actual running plugin,
first alone (correctly producing "Nothing transcribed" with no follow-up spoken) and
then with a real follow-up question — "What is 2 plus 2?" — correctly transcribed and
answered "2 plus 2 is 4." by the real running daemon end to end. The wake-word listener
hit and recovered from the same pre-existing, already-documented transient ALSA race
from §26 in between — unrelated to this change, confirmed self-recovering as before.

## 34. Where things live (quick map)

| Thing | Path |
|---|---|
| Plugin manifest | `manifest.json` |
| HID/USB driver | `daemon/src/Aris68Connector.js` |
| Daemon CLI entry | `daemon/src/bridge.js` |
| Virtual touchscreen | `daemon/src/uinputTouch.js` |
| Real plugin entry point (mode toggle, IPC) | `shell/Service.qml` |
| Top-bar mode-toggle dropdown (§20) | `shell/BarWidget.qml` |
| PA voice agent page + orchestration daemon (§22) | `shell/Pages/PaPage.qml`, `shell/Services/PaState.qml`, `shell/Services/PaBridge.qml`, `daemon/src/paBridge.js` |
| PA's MCP tools (agent-callable panel actions) | `daemon/src/paTools/server.js` |
| PA-scoped Voxtype config (pins the panel's own mic) | `ops/voxtype/pa.example.toml`, live copy at `~/.config/voxtype/pa.toml` |
| PA spoken replies (§24) | `daemon/src/paBridge.js`'s `speak()`; voice model at `~/.local/share/piper/voices/` (not in the repo) |
| PA "Hey Foxy" wake-word mode (§26, §31, §33) | `daemon/src/paTools/wakeword.py` (`nanowakeword.NanoInterpreter`, model at `daemon/src/paTools/models/hey_foxy.onnx`, overridable via `OQP_PA_WAKEWORD_MODEL`/`_THRESHOLD`), `daemon/src/paBridge.js`'s `startListener`/`stopListener`, `Ui/PageHeader.qml`'s pulsing dot |
| PA Home Assistant control (§29) | `daemon/src/paTools/server.js`'s HA tools, `daemon/src/paBridge.js`'s `OQP_PA_TURN_ID`; credentials at `~/.config/omarchy-quake-panel/config.json` (not in the repo) |
| FOXY's 3D particle visualizer (§30) | `shell/Ui/FoxyVisualizer.qml`, `daemon/src/paBridge.js`'s `computeAudioEnvelope`/`speak()`; needs the `qt6-quick3d` system package |
| FOXY on/off, auto-follow-up listening, scrolling transcript (§31) | `shell/Pages/PaPage.qml`, `shell/Services/PaState.qml`'s `transcript` `ListModel`, `daemon/src/paBridge.js`'s `autoListenAfterReply`, `shell/Ui/Section.qml`'s content-area anchoring |
| Standalone dev entry point | `shell/shell.qml` |
| Daemon↔QML bridge | `shell/Services/HidBridge.qml` |
| Knob gesture table | `shell/Services/KnobRouter.qml` |
| Touch hit-testing workaround | `shell/Services/TouchRouter.qml` |
| Theme (Color.qml-equivalent) | `shell/Services/Theme.qml` |
| Dashboard logic | `shell/Services/SystemStats.qml` |
| Personal Care logic | `shell/Services/PersonalCareState.qml` |
| Pages | `shell/Pages/*.qml` |
| Overlays | `shell/Ui/ToastOverlay.qml`, `shell/Ui/WaterAmountPicker.qml` |
| Shared styled components | `shell/Ui/Card.qml`, `SectionLabel.qml`, `SectionSeparator.qml`, `PanelButton.qml`, `PageHeader.qml` |
| Page chrome + page switching | `shell/Ui/PageHost.qml` |
| Knob RGB ring color + brightness | `shell/Services/KnobLighting.qml`, `shell/Pages/SettingsPage.qml` |
| Screen brightness | `shell/Services/ScreenBrightness.qml` |
| Panel microphone on/off, gated by Foxy (§32) | `shell/Services/MicState.qml`, `shell/Service.qml`/`shell.qml`'s `setOn(paState.continuousMode)` wiring |
| Shared section-column shape (Self Care + Settings) | `shell/Ui/Section.qml` |
| Touch-drag slider (Ui/Slider.qml's own TouchRouter support) | `shell/Ui/Slider.qml`, `shell/Services/TouchRouter.qml` |
| Virtual touch device on/off by mode (§18's fix) | `daemon/src/bridge.js`'s `setVirtualTouch`, `shell/Service.qml`'s `_syncVirtualTouch` |
| Styling skill | `.claude/skills/omarchy-design/` |
| Mode-toggle samples (menu/keybind/CLI) | `ops/omarchy-menu.example.jsonc`, `ops/hyprland/keybind.example.lua`, `ops/bin/omarchy-quake-panel-toggle` |
| udev/Hyprland/modules-load examples | `ops/` |
| Phantom "Mouse" device disable (real hardware gotcha) | `ops/hyprland/input.example.lua` |

Durable cross-session notes (permissions gotchas, hardware bring-up) also live in this
machine's assistant memory at
`~/.claude/projects/-home-srk-Projects-bedrock-panel/memory/project_omarchy_quake_panel.md`
— that file predates this one and has more granular debugging detail; this file is the
project-local, portable equivalent (readable from *any* session rooted in this repo,
where the memory file above is only loaded automatically in sessions rooted in
`bedrock-panel`).
