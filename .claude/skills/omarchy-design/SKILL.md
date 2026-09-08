---
name: omarchy-design
description: Restyle or theme QML/Quickshell pages in this project (omarchy-quake-panel) to visually match the installed Omarchy desktop's real design system, verified against Omarchy's own Wi-Fi and bluetooth panel source. Use when asked to style, restyle, reskin, theme, polish the look of, or make a page "look like Omarchy" / "look like a plugin" / "match the Wi-Fi panel". Includes a working screenshot-capture driver for reviewing changes on the real DK-QUAKE panel — there is no headless render path for this app.
---

# Styling this app to match Omarchy

This app is a standalone Quickshell kiosk UI for a DK-QUAKE touchscreen-plus-knob panel
— **not** a plugin inside Omarchy's own shell process, so its components/imports aren't
available here (see `reference/project-styling-notes.md`). This skill is about matching
Omarchy's *visual conventions* (colors, typography, spacing, borders, selection states,
icons) using this project's own small styling layer (`shell/Services/Theme.qml`) — not
importing Omarchy's code.

**This is a visual-refinement task only.** All functionality, hardware interaction, knob
mappings, and touch handling already work and must not change — see "Preserve behavior"
in `reference/project-styling-notes.md` before editing anything.

## Read these two reference files first

1. **`reference/omarchy-conventions.md`** — verified-from-source Omarchy design tokens:
   color roles, spacing/typography scale, the alpha-blended-foreground fill/border system
   (and the two *different* alpha strengths for separators vs control borders — the
   detail most likely to get lost), the darkened-foreground secondary-text idiom, the
   hover/selected state machine, icon-glyph convention, and a file index into
   `/usr/share/omarchy/shell/` for going deeper. Every claim there cites its source file.
2. **`reference/project-styling-notes.md`** — how those conventions map onto *this*
   project specifically: why Omarchy's QML modules can't be imported directly, the
   current known gaps in `Theme.qml` versus the verified conventions, and the exact list
   of files/behaviors a styling task must not touch (the daemon, `KnobRouter`,
   `TouchRouter`'s touch-registration requirement, etc.).

Don't invent QML imports, component names, or theme APIs beyond what those two files (or
your own fresh reading of `/usr/share/omarchy/shell/`) verify. If you need a convention
those files don't cover, go read the real source yourself — don't guess.

## Workflow

1. **Read both reference files above.**
2. **Read the page(s) you're restyling** (`shell/Pages/*.qml`) and `shell/Services/Theme.qml`
   to see what styling primitives already exist — reuse/extend them rather than
   duplicating constants in each page file. If a convention from
   `omarchy-conventions.md` is missing from `Theme.qml` (e.g. the two-strength separator
   vs control-border alpha), add it there, once, and consume it from the pages.
3. **Make the change**, preserving all page structure, panel grouping, navigation, data
   bindings, and knob/touch wiring exactly as documented in `project-styling-notes.md`.
4. **Lint**: `cd shell && qmllint shell.qml Services/*.qml Ui/*.qml Pages/*.qml` — fix
   anything it reports before launching.
5. **Capture and look at the real result** — see below. There is no other way to know if
   a QML layout change actually renders correctly; `qmllint` only catches syntax errors.
6. **If a comparison against Omarchy's real Wi-Fi/bluetooth panel would help**, open it
   yourself (e.g. click the network icon in the bar) and capture the *primary* screen the
   normal way — but note it closes when focus moves elsewhere (confirmed: it did not stay
   open while typing in another window), so time the capture right after opening it, in
   one shot. Source-code fidelity to `omarchy-conventions.md` is the primary method;
   screenshot comparison is best-effort supplementary.
7. **Send the captured screenshot to the user** (they're following this from another
   device, and viewing a file yourself does not show it to them) so they can confirm
   before you consider the task done.

## Run this to see the real result — `scripts/capture-panel.sh`

There is no simulated/headless rendering path for this app. Verifying a change means
running the actual Quickshell instance against the actual panel output and looking at a
real screenshot. This script does that — tested and confirmed working this session:

```bash
cd /home/srk/Projects/omarchy-quake-panel   # repo root — the script checks for this
.claude/skills/omarchy-design/scripts/capture-panel.sh /path/to/output.png
```

What it does, in order: resolves the panel's exact on-screen geometry from `hyprctl
monitors -j` (matching by description substring `DK-QUAKE`, overridable via
`PANEL_DESC_MATCH=...` if a different panel enumerates differently), stops any existing
instance of *this project's* shell/daemon by PID (never touches Omarchy's own
`omarchy-shell`), runs `qmllint`, launches a fresh `quickshell -p shell/shell.qml`, waits
for it to come up, and captures with `grim -g <geometry>` — bypassing the interactive
screenshot picker entirely, which grabs whatever monitor currently has focus (almost
never the panel, since it's a separate output you're not actively clicking into).

Set `OQP_START_PAGE=<index>` (0 = Dashboard, 1 = Self Care) in the script's environment
to open on a given page — the only way to screenshot a non-default page without someone
physically turning the knob. Run the script with `< /dev/null` and its output to a file
when a harness is waiting on it.

The script prints the resolved geometry and the output path, and exits non-zero with the
shell's log tail if quickshell didn't stay running (usually a QML error `qmllint` missed,
or a genuine runtime exception — check `/tmp/omarchy-quake-panel-shell.log`).

**Requires**: the DK-QUAKE panel physically connected and already configured in
`~/.config/hypr/monitors.lua` (see repo `README.md`/`PLAN.md` if it isn't). If hardware
access isn't available in your session, say so explicitly and proceed from verified
source alone (`omarchy-conventions.md` + reading the page files) — don't claim a visual
result you didn't actually capture.

## Visual review checklist

Work through this against a real capture before calling a restyle done:

- [ ] Corners match `Style.cornerRadius` convention (sharp/0 on this machine — re-check
      `hyprctl getoption decoration:rounding` if unsure, don't assume)
- [ ] Plain separators/dividers are subtle (foreground @ ~0.12 alpha) — not a flat opaque
      color, not muddy/tinted from blending an unrelated hue
- [ ] Interactive control borders (buttons, cards) are more present than separators
      (~0.4 alpha foreground) but still not a hard flat color
- [ ] Secondary/status text reads as a *darkened version of that surface's own
      foreground*, not an unrelated gray
- [ ] No gradients, shadows, rounded cards, or other decorative effects absent from the
      verified reference
- [ ] Any icon glyphs render as real icons, not tofu/missing-glyph boxes (confirm the
      font is actually installed — `fc-list | grep -i nerd`)
- [ ] Colors still live-update when the Omarchy theme changes (`Theme.qml`'s poll —
      switch theme with `omarchy theme set <name>` and re-capture)
- [ ] Every existing touch target still registers with `TouchRouter`, not just
      `TapHandler` — a button that only responds to mouse clicks in a screenshot test but
      not real touch is a regression, and a screenshot alone won't reveal this. Use
      `Ui/PanelButton` for buttons: it registers itself
- [ ] Hero meta captions are letter-spaced (1.2); section labels are not — see the
      conventions doc
- [ ] Knob rotate/press/hold still do exactly what they did before (page switch, water
      picker, per-page action) — a styling change should never need to touch
      `KnobRouter.qml`'s logic
- [ ] A real screenshot was captured via `scripts/capture-panel.sh` and sent to the user
      for review — not just eyeballed via the `Read` tool (which only you can see)
