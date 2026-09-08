# Verified Omarchy design conventions

Everything in this file was read directly from this machine's installed Omarchy shell
source (`/usr/share/omarchy/shell/`) during a live session — not inferred, not from
upstream docs, not from memory of a different Omarchy version. File paths and line
numbers are cited so you can re-verify or go deeper. **Treat the installed version as
authoritative** — re-check these paths before relying on them if the Omarchy package has
been updated since.

Primary reference used: `plugins/panels/network/Panel.qml` (the Wi-Fi panel — 1970
lines, most detailed real usage of every convention below) and
`plugins/panels/bluetooth/Panel.qml` (corroborates the same patterns independently).

## Color roles (`Commons/Color.qml`)

Foundational palette, loaded from the active theme's `colors.toml`
(`~/.local/state/omarchy/current/theme/colors.toml`):

- `Color.background`, `Color.foreground`, `Color.accent`, `Color.urgent`, `Color.muted`

Per-surface roles (`Color.bar.*`, `Color.popups.*`, `Color.menu.*`, etc.) come from a
second file, `shell.toml`, generated per-theme — most panel code doesn't reach for these
directly, it builds from the foundational five roles using the helpers below.

## Structural tokens (`Commons/Style.qml`)

- `Style.cornerRadius` — **mirrors the live Hyprland `decoration:rounding` value**, not a
  fixed Omarchy default. Confirmed on this machine: `hyprctl getoption decoration:rounding`
  → `0` (sharp corners). Re-check per machine; don't hardcode "Omarchy uses radius 0" as a
  universal law — it's whatever this user's Hyprland config says.
- Spacing scale (`Style.spacing.*`, `Style.qml:235-260`): `xxs:2, xs:3, sm:4, md:6, lg:8,
  xl:10, xxl:12, xxxl:14, huge:18`, plus named tokens `rowGap:8, rowPaddingX:12,
  panelPadding:18, popupPadding:14, controlHeight:28, controlPaddingX:10,
  controlPaddingY:6`. All scale together via `Style.spacing.scale` (font-size-linked).
- Font scale (`Style.font.*`, `Style.qml:327-338`), base 12px: `caption:10, bodySmall:11,
  body:12, subtitle:13, title:14, heading:16, display:24, displayLarge:28`. Icon sizes
  reuse these: `iconSmall:bodySmall, icon:title, iconLarge:18`.
- Font family: `Style.font.family` *defaults* to `"monospace"` in code, but the real
  active font on this machine is **JetBrainsMono Nerd Font** (`omarchy font current`) —
  the Nerd Font part matters, see Icons below.

## State fills and borders — alpha-blended `foreground`, not flat swatches

This is the single most important convention, and the one most likely to be gotten
wrong: interactive/structural surfaces are **not** filled with a separate "muted" or
"surface" color. They're the **foreground color at low alpha**, layered over whatever's
underneath (`Style.qml:80-91`, functions at `Style.qml:154-156`):

```
normalFillAlpha    = 0.04   →  Style.normalFillFor(fg, accent)   = alpha(foreground, 0.04)
hoverFillAlpha     = 0.08   →  Style.hoverFillFor(fg, accent)    = alpha(foreground, 0.08)
selectedFillAlpha  = 0.18   →  Style.selectedFillFor(fg, accent) = alpha(foreground, 0.18)
pressedFillAlpha   = 0.22
normalBorderAlpha  = 0.4    (control border — buttons, input fields)
hoverBorderAlpha   = 0.25
selectedBorderAlpha= 1.0    BUT selectedBorderWidth defaults to 0 — selected rows are
                            usually shown via FILL ONLY, no border, unless overridden.
normalBorderWidth  = 1
hoverBorderWidth   = defaults to normalBorderWidth (1)
```

**Plain structural separators use a much lower alpha than control borders** —
`Ui/PanelSeparator.qml:17`: `color: Qt.rgba(foreground.r, foreground.g, foreground.b,
0.12)`. A 1px divider between sections is foreground-at-0.12, **not** the 0.4 used for an
interactive control's border. Conflating these two (using the stronger control-border
alpha for a plain separator line) reads as a muddy/tinted line, especially on a theme
whose foreground and background are on opposite ends of the warm/cool spectrum (verified
live on the Everforest theme: foreground `#d3c6aa` — warm cream — over background
`#2d353b` — cool dark — blended at 0.4 alpha reads distinctly brownish; the same blend at
0.12 is subtle enough not to fight the background hue).

**Selected fill blends `foreground`, not `accent`**: `Style.selectedStateColor` falls back
to `foreground` (`Style.qml:135-137`), so `selectedFillFor(...)` = foreground @ 0.18 by
default, and `Ui/Button.qml`'s selected text is that same resolved color, bold — accent
only enters if a theme's `shell.toml` overrides the selected-color token.

## Hero captions ARE letter-spaced; section headers are NOT

Two different small-caps captions, easy to conflate:

- `Ui/PanelHero.qml:100` and the bluetooth hero (`Panel.qml:758`): the hero's uppercase
  `meta` caption is `caption` size, bold, `Qt.darker(foreground, 1.4)`, **`letterSpacing:
  1.2`**. The clock panel uses `1` in the same role.
- `Ui/PanelSectionHeader.qml`: a section label ("CONNECTED", "PAIRED DEVICES") is the same
  color/weight/size with **no** letter-spacing, plus `topPadding: ceil(fontSize * 0.15)`
  to reserve the Nerd Font ascent overshoot.

`Ui/PanelHero.qml` is the canonical hero: a `display`-size glyph on the left, a
`title`-size bold title, the letter-spaced meta caption under it, an optional bordered
`detail` pill on the title row, and an optional trailing control on the right edge.

## Secondary/status text — darkened foreground, not a separate muted swatch

Both `Ui/PanelSectionHeader.qml:18` (the "CONNECTED"-style section caption) and inline
row status text in the Wi-Fi/bluetooth panels use **`Qt.darker(foreground, 1.4)`** (or
`1.5` in one bluetooth spot) for de-emphasized text — not `Color.muted`. `Color.muted` is
the foundational theme role and does get used for some structural chrome, but the
panel-content idiom for "this text matters less than the row above it" is a *darkened
foreground*, derived per-surface from whatever foreground that surface is already using
(so it stays correctly related to that surface's own color, not a global muted constant
that might not relate visually to a locally-overridden foreground).

## Selection / hover state machine (`Ui/CursorSurface.qml`)

The canonical "this row can be selected and/or hovered" component. Two independent
booleans, two different visual treatments:

- `hasCursor` (mouse hover **or** keyboard/panel cursor over this row) → paints
  `hoverFillFor(...)` + a hover-cursor border.
- `current` (persistently active/selected — e.g. the currently-connected Wi-Fi network)
  → paints `selectedFillFor(...)`, no border by default (see `selectedBorderWidth` above).
- Both can never show a border AND no-border-fill confusion because the component
  computes `color` and `borderSpec` from a single `hasCursor ? ... : (current ? ... :
  ...)` chain — never overlapping states.
- Explicit contract in the file's own header comment: **items must not read
  `containsMouse` directly for color/border** — hover state flows through the shared
  `hasCursor` property so exactly one highlight exists on screen at a time across mouse
  and keyboard input.

## Borders as a structured spec, not raw `border.color`/`border.width`

`Ui/BorderSurface.qml` + `Commons/Border.qml`: real panel code builds borders via
`Border.controlSpec(state, foreground, accent)` (state = `"normal"`, `"hover-cursor"`, or
`"selected"`), which resolves to a `{color, widths, gradient}` spec consumed by
`BorderSurface`. This lets a theme override any control's border color/width/alpha via
`shell.toml` without touching component code. A full port of this override system is
almost certainly overkill for a standalone app with no such theme-override file — the
useful thing to port is the **default values themselves** (documented above), not the
indirection.

## Icons: literal glyphs from the installed Nerd Font, not images

Icons throughout the Wi-Fi/bluetooth panels are plain `Text` elements whose `text` is a
single Private-Use-Area Unicode codepoint from a Nerd Font, rendered in the same font
family as surrounding UI text:

```qml
Text { text: "󰌾"; color: ...; font.family: root.bar.fontFamily; font.pixelSize: Style.font.subtitle }
```

Verified glyphs in use: `󰌾` (lock — network requires credentials), `󰅙` (cancel/forget),
`󰄬` (checkmark — connect action), `󰂱`/`󰂯` (bluetooth connected/idle), `󰍹`/`󰍺`
(monitor panel). To check a codepoint exists before using it, query the resolved font
file's charset — `fc-query --format='%{charset}' "$(fc-match -f '%{file}' monospace)"` —
rather than trusting memory of the Nerd Font cheat sheet. This machine's
active font is **JetBrainsMono Nerd Font** (`omarchy font current`) — confirmed installed
via `fc-list`. If you add icon glyphs to a standalone app, set `font.family` to a Nerd
Font that's actually installed (check `fc-list | grep -i nerd`) — don't assume the exact
same family Omarchy is currently themed with, since that's a user preference, not a fixed
Omarchy constant. Falling back to plain text/no icon is safer than a guaranteed-wrong
hardcoded font name.

## Reusable component file index

| Component | Path | What it's for |
|---|---|---|
| `Color` | `Commons/Color.qml` | Foundational + per-surface theme colors, loaded from `colors.toml`/`shell.toml`, live-updated via shell IPC on theme change |
| `Style` | `Commons/Style.qml` | Spacing/typography/corner-radius/state-fill-and-border tokens |
| `Border` | `Commons/Border.qml` | Structured border-spec builder (`controlSpec`, `none`, width/color accessors) |
| `BorderSurface` | `Ui/BorderSurface.qml` | `Rectangle`-compatible surface consuming a `Border` spec + padding |
| `CursorSurface` | `Ui/CursorSurface.qml` | The hover/selected row idiom described above |
| `PanelSectionHeader` | `Ui/PanelSectionHeader.qml` | Small-caps-style section label (darkened foreground, bold, caption size) |
| `PanelSeparator` | `Ui/PanelSeparator.qml` | 1px divider, foreground @ 0.12 alpha |
| `PanelActionButton` | `Ui/PanelActionButton.qml` | Small icon-glyph action button (used for the Wi-Fi row's connect/forget actions) |
| `PanelToolTip` | `Ui/PanelToolTip.qml` | Hover tooltip |
| `Button` | `Ui/Button.qml` | Base pill/button component (`BandPill`, `DnsProviderPill` in the Wi-Fi panel extend this) |
| Wi-Fi panel | `plugins/panels/network/Panel.qml` | The richest real example — `NetworkRow` (line ~1596) is the canonical row-with-selection-and-actions pattern |
| Bluetooth panel | `plugins/panels/bluetooth/Panel.qml` | Corroborates the same hero/section/row conventions independently |

All paths are relative to `/usr/share/omarchy/shell/`. **Never edit anything under
`/usr/share/omarchy/`** (owned by the package, overwritten on update) — read-only
reference.
