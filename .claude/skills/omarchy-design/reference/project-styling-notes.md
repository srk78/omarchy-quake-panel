# Applying Omarchy conventions to this standalone app

This app (`omarchy-quake-panel`) is **not** a plugin running inside Omarchy's own
`omarchy-shell` process — it's launched separately as `quickshell -p shell/shell.qml`
(see repo `README.md`). That has one concrete, verified consequence:

**`import qs.Commons` / `import qs.Ui` are not available here.** Those module names are
synthesized by Omarchy's own shell process at startup from its own directory tree
(`Quickshell.shellDir`-relative), specific to *that* running instance. This project has
never successfully imported them (confirmed across this project's entire build so far —
every styling primitive was hand-rolled in `shell/Services/Theme.qml` for exactly this
reason). Don't attempt `import qs.Commons` and don't assume a future Quickshell version
changes this — verify fresh if revisiting.

**What this means practically:** port the *default values and idioms* documented in
`reference/omarchy-conventions.md`, not the component names or import paths. Where this
project needs the equivalent of `Color`, build it into `Theme.qml`; where it needs
`BorderSurface`/`CursorSurface`, build a small local component in the page that needs it
(or promote to a shared `Ui/` component if more than one page needs the same shape — see
the `shell/Ui/` table below for what already exists; page-local shapes still use QML's
`component Name: ... { }` syntax).

## Current state of this project's styling layer

`shell/Services/Theme.qml` is this project's `Color.qml` **and** `Style.qml` equivalent.
It reads the same `colors.toml` Omarchy reads and exposes:

- Colors: `background`, `foreground`, `accent`, `muted`, `red`, `green`, plus the verified
  derived roles `separatorColor` (fg @ 0.12), `controlBorderColor` (fg @ 0.4),
  `secondaryForeground` (`Qt.darker(fg, 1.4)`), and the state fills `controlFill` (0.04),
  `controlFillHover` (0.08), `selectedFill` (0.18), `pressedFill` (0.22) — all blended
  from **foreground**, matching `Style.qml`'s defaults (selected is not accent-tinted).
- `fontFamily: "monospace"` — the fontconfig alias, exactly what Omarchy's `Style.font.family`
  binds to, so `omarchy font set` is followed without a hardcoded family and Nerd Font
  glyphs come along for free.
- `scale` (1.5) — one kiosk factor applied to Omarchy's 12px base and to spacing, since
  the panel is read from arm's length. `font.*` carries the same token names/multipliers
  as `Style.font.*` (`caption` … `displayLarge`) plus a kiosk-only `hero` for the one
  glanceable number per section; `spacing.*` mirrors the named `Style.spacing` tokens,
  plus `touchControlHeight` for finger-sized buttons. `space(px)` = `Style.space(px)`.

Shared components in `shell/Ui/` (each takes `required property var theme`):

| Component | Omarchy equivalent | Notes |
|---|---|---|
| `Card` | `Ui/PopupCard.qml` surface | background fill + control-alpha border, sharp corners |
| `SectionLabel` | `Ui/PanelSectionHeader.qml` | optional leading glyph; no letter-spacing |
| `SectionSeparator` | `Ui/PanelSeparator.qml` | `vertical: true` splits side-by-side sections |
| `PanelButton` | `Ui/Button.qml` (bordered) | transparent at rest, `pressedFill` when down, optional `icon`; **registers itself with `TouchRouter`** via its `touchRouter` property |
| `PageHeader` | `Ui/PanelHero.qml` | glyph + title + letter-spaced meta caption; trailing read-only page tabs (`selectedFill` + bold) and clock |

`Ui/PageHost.qml` owns the header and the page `Loader`; pages fill the area below and
may expose a `heroMeta` string for the header's caption. Both pages, `ToastOverlay` and
`WaterAmountPicker` are on these tokens; nothing references a flat `surfaceBorder` or
`theme.muted` for text any more.

Still true: there is no hover concept on the real hardware (touch panel), so the only
state distinction worth drawing is pressed vs idle, and the page tabs are display-only —
the knob switches pages.

## Preserve behavior — do not touch these while restyling

This is a styling task. The following are load-bearing and must not change (verified
working end-to-end on real hardware across many rounds of this project's development —
see project memory `project_omarchy_quake_panel.md` for the debugging history):

- **`daemon/`** (the whole directory) — the Node.js HID/USB driver. No styling task
  touches this.
- **`shell/Services/HidBridge.qml`** — parses the daemon's JSON event stream. Don't
  change its signals or the JSON schema it expects.
- **`shell/Services/KnobRouter.qml`** — knob rotate=page-switch, hold=water picker,
  press=per-page action. **Do not repurpose the knob, add keyboard-style interactions to
  it, or change what any gesture means** as part of a styling task. If a restyle adds a
  new interactive element, it must be reachable via the *existing* touch/knob model
  (register with `TouchRouter`, or make it respond to the current page's existing knob
  press action), not a new gesture.
- **`shell/Services/TouchRouter.qml`** — real touch does **not** flow through Qt's normal
  input path here (a confirmed, unresolved Hyprland bug — full explanation in this file's
  own header comment and the repo README). Any new tappable element must call
  `touchRouter.registerTap(item, callback)` in `Component.onCompleted` and
  `unregisterTap` in `Component.onDestruction` — a `TapHandler` alone will render
  correctly but **will not respond to real touch on the physical panel**, only to a mouse
  in dev/testing. This is the single most common way a styling change silently breaks
  real-hardware interaction: adding a new button with only a `TapHandler` and no
  `TouchRouter` registration.
- **`shell/Services/PersonalCareState.qml`, `shell/Services/SystemStats.qml`** — logic
  and persisted state. Touch only their visual consumers (the pages), not their
  properties/functions/signals.
- **`shell/shell.qml`**'s window setup (`WlrLayershell.layer`, `exclusionMode`, the
  `Component.onCompleted` wiring — the one dev-only line there, `OQP_START_PAGE`, just
  picks the initial page for screenshot runs and is inert when the variable is unset) —
  this is what pins the app to the panel's output, fully covers Omarchy's own bar on
  that output, and connects the daemon/knob/touch signal chain. A styling task should not need to touch this file at all beyond passing a
  new `theme` property down to a new component, if one is added.

## Verifying a restyle

There is no headless/simulated rendering path for this app — see
`scripts/capture-panel.sh` and the main `SKILL.md` for the real verification workflow
against the physical panel. `qmllint` catches syntax errors but proves nothing about
whether real touch still reaches a moved/restyled button — only a live capture (or the
user's own eyes on the physical panel) does that.
