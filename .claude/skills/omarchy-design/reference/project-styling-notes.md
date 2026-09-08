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
(or promote to a shared `Ui/` component if more than one page needs the same shape — this
project already does this for `Card`/`SectionLabel`/`SectionSeparator`/`PluginButton`,
currently defined inline per-page via QML's `component Name: ... { }` syntax).

## Current state of this project's styling layer

`shell/Services/Theme.qml` is this project's own `Color.qml` equivalent — it reads the
same `colors.toml` Omarchy reads (`~/.local/state/omarchy/current/theme/colors.toml`) and
exposes `background`, `foreground`, `accent`, `muted`, `red`, `green`. It also has a
`cornerRadius`, `borderWidth`, and a few fill/border helpers — this is this project's
*first pass* at the Style.qml-equivalent conventions, and it does not yet fully match
what `reference/omarchy-conventions.md` documents. Known, verified gaps as of this
writing:

- `Theme.surfaceBorder` is currently just `muted` (a flat, opaque color) for **all**
  borders — both plain separators and interactive control borders. The verified Omarchy
  convention uses **alpha-blended `foreground`** for both, but at *different* strengths:
  ~0.12 for a plain separator line, ~0.4 for an interactive control's border (see the
  conventions doc's "State fills and borders" section for exactly why flattening this to
  one opaque color is a regression, not a simplification — it was a fix for making a
  *separator* look better, at the cost of drifting from the real convention for
  *control* borders. A styling pass should reintroduce the two-strength alpha-blended
  approach: something like `Theme.separatorColor` (foreground @ 0.12) and
  `Theme.controlBorderColor` (foreground @ 0.4), rather than one `surfaceBorder` for both.
- No `Qt.darker(foreground, 1.4)`-style "secondary text" helper exists yet — pages
  currently reach for `theme.muted` for this purpose. Per the verified convention, prefer
  a darkened-foreground helper for text that's secondary *within a surface already using
  a specific foreground*, and reserve `theme.muted` for cases where the foundational
  theme role is genuinely what's wanted.
- No hover/selected/pressed state distinction exists anywhere in this project yet (no
  `CursorSurface` equivalent). This matters less here than in Omarchy's own mouse-driven
  bar: **this is a touch panel** (see Preserve Behavior below) — there is no hover concept
  at all on real hardware. Where a "state" distinction is worth adding, it should
  distinguish **pressed** (finger currently down on a button — already tracked in
  `PluginButton`'s `tapHandler.pressed`, which only fires for mouse in dev/testing since
  real touch bypasses `TapHandler` entirely, see Preserve Behavior) from **idle**, not
  hover-vs-selected in the mouse-UI sense.
- No icon glyphs are used anywhere in this project yet. If a styling pass wants to add
  them (e.g. a lock glyph, a signal-strength glyph), confirm a Nerd Font is actually
  installed and reachable (`fc-list | grep -i nerd`) before hardcoding a `font.family` —
  don't copy `JetBrainsMono Nerd Font` verbatim as if it were a fixed Omarchy constant;
  it's this particular machine's currently-selected font (`omarchy font current`), a user
  preference that can change.

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
  `Component.onCompleted` wiring) — this is what pins the app to the panel's output,
  fully covers Omarchy's own bar on that output, and connects the daemon/knob/touch
  signal chain. A styling task should not need to touch this file at all beyond passing a
  new `theme` property down to a new component, if one is added.

## Verifying a restyle

There is no headless/simulated rendering path for this app — see
`scripts/capture-panel.sh` and the main `SKILL.md` for the real verification workflow
against the physical panel. `qmllint` catches syntax errors but proves nothing about
whether real touch still reaches a moved/restyled button — only a live capture (or the
user's own eyes on the physical panel) does that.
