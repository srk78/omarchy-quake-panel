import QtQuick
import Quickshell
import Quickshell.Io

// Follows the user's selected Omarchy theme, the same way Omarchy's own shell does
// (mirrors /usr/share/omarchy/shell/Commons/Color.qml's colors.toml parsing, trimmed to
// the handful of roles this kiosk app actually uses). Reads
// ~/.local/state/omarchy/current/theme/colors.toml, the file `omarchy theme set` writes.
//
// Live updates are polled, not FileView's watchChanges — confirmed live that watchChanges
// does not fire when `omarchy theme set` rewrites this file (Omarchy's own Color.qml
// comment explains why: "Runtime theme switches push the payload explicitly through shell
// IPC" — its bar doesn't trust file-watching for this either, it relies on an IPC push
// from the theme-set hook targeting that specific shell instance. We're a separate
// Quickshell instance with no such IPC wiring, so a cheap periodic reload is the robust
// option instead of taking on a theme-set hook + IPC handshake for this).
//
// This file is also this project's Commons/Style.qml equivalent: the font scale, spacing
// scale and state fill/border tokens below are Omarchy's verified defaults (see
// .claude/skills/omarchy-design/reference/omarchy-conventions.md), multiplied by one
// kiosk `scale` factor because this panel is read from arm's length, not from a bar.
QtObject {
    id: root

    readonly property string currentThemePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme"

    // Sensible dark-theme defaults, used only until the real file loads (or if it's ever
    // missing) — never hardcode these elsewhere in the UI.
    property color background: "#101315"
    property color foreground: "#cacccc"
    property color accent: "#7fbbb3"
    property color muted: "#707880"
    property color red: "#e67e80"
    property color green: "#a7c080"

    // ---- Typography. Omarchy binds font.family to the fontconfig alias "monospace"
    // (Commons/Style.qml: `property string fontFamily: "monospace"`), which `omarchy font
    // set` re-points — so we follow the user's font choice for free, no hardcoded family.
    // Nerd Font icon glyphs render through the same alias (the shipped fonts are all Nerd
    // Font patched; verified via fc-query on the resolved file).
    readonly property string fontFamily: "monospace"

    // One knob for how much bigger than Omarchy's bar/popup metrics this kiosk renders.
    // Omarchy's base is 12px (Style.fontBaseSize) and spacing scales with font
    // (Style.effectiveSpacingScale), so the same factor applies to both.
    readonly property real scale: 1.5
    function fontPx(mult) { return Math.max(1, Math.round(12 * mult * root.scale)) }
    function space(px) { return px <= 0 ? 0 : Math.max(1, Math.round(px * root.scale)) }

    // Same multipliers as Style.qml:327-334; `hero` is a kiosk-only extension for the one
    // glanceable number each section leads with (Omarchy's largest token is displayLarge).
    readonly property QtObject font: QtObject {
        readonly property string family: root.fontFamily
        readonly property int caption: root.fontPx(0.833)
        readonly property int bodySmall: root.fontPx(0.917)
        readonly property int body: root.fontPx(1.0)
        readonly property int subtitle: root.fontPx(1.083)
        readonly property int title: root.fontPx(1.167)
        readonly property int heading: root.fontPx(1.333)
        readonly property int display: root.fontPx(2.0)
        readonly property int displayLarge: root.fontPx(2.333)
        readonly property int hero: root.fontPx(3.333)
        // Ui/PanelHero.qml:100 / bluetooth Panel.qml:758 — the hero's uppercase meta
        // caption is letter-spaced; plain section headers (PanelSectionHeader) are not.
        readonly property real heroCaptionSpacing: 1.2
    }

    // Style.qml:235-260 named spacing tokens, through the same scale.
    readonly property QtObject spacing: QtObject {
        readonly property int xs: root.space(3)
        readonly property int sm: root.space(4)
        readonly property int md: root.space(6)
        readonly property int lg: root.space(8)
        readonly property int xl: root.space(10)
        readonly property int xxl: root.space(12)
        readonly property int huge: root.space(18)
        readonly property int rowGap: root.space(8)
        readonly property int panelPadding: root.space(18)
        readonly property int popupPadding: root.space(14)
        readonly property int controlPaddingX: root.space(10)
        readonly property int controlPaddingY: root.space(6)
        // Touch target height for on-screen buttons — deliberately larger than Omarchy's
        // mouse-sized controlHeight (28): fingers, not pointers, hit these.
        readonly property int touchControlHeight: root.space(40)
    }

    // ---- "plugin" surface language, mirroring Omarchy's own shell (Commons/Style.qml,
    // Ui/PopupCard.qml): sharp corners (this system's real Hyprland decoration:rounding is
    // 0, which Style.cornerRadius mirrors), a card surface that's the SAME background as
    // the page with a border for definition (not a lightened fill), and controls built
    // from subtle low-alpha foreground fills rather than solid color blocks.
    readonly property int cornerRadius: 0
    readonly property int borderWidth: 1
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // Real Omarchy panels use alpha-blended `foreground` for BOTH separators and control
    // borders, but at two different strengths — not one flat opaque color for everything.
    readonly property color separatorColor: withAlpha(foreground, 0.12)     // Ui/PanelSeparator.qml
    readonly property color controlBorderColor: withAlpha(foreground, 0.4) // Style.normalBorderAlpha
    // Secondary/status text idiom from Ui/PanelSectionHeader.qml + the Wi-Fi/bluetooth
    // panels' row status text: a DARKENED foreground, not the separate `muted` role.
    readonly property color secondaryForeground: Qt.darker(foreground, 1.4)

    // State fills (Style.qml:80-91). Every one of these blends FOREGROUND by default —
    // including selected (Style.selectedStateColor falls back to foreground, not accent).
    // Omarchy's Button is transparent at rest; normalFill is what bordered surfaces use.
    readonly property color controlFill: withAlpha(foreground, 0.04)      // normalFillAlpha
    readonly property color controlFillHover: withAlpha(foreground, 0.08) // hoverFillAlpha
    readonly property color selectedFill: withAlpha(foreground, 0.18)     // selectedFillAlpha
    readonly property color pressedFill: withAlpha(foreground, 0.22)      // pressedFillAlpha

    function _load(raw) {
        var lines = String(raw || "").split("\n")
        var color0 = "", color1 = "", color2 = "", color4 = "", color7 = "", color8 = ""
        var gotBg = false, gotFg = false, gotAccent = false, gotMuted = false, gotRed = false, gotGreen = false
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
            if (!m) continue
            var k = m[1], v = m[2]
            if (k === "background") { root.background = v; gotBg = true }
            else if (k === "foreground") { root.foreground = v; gotFg = true }
            else if (k === "accent") { root.accent = v; gotAccent = true }
            else if (k === "muted") { root.muted = v; gotMuted = true }
            else if (k === "red") { root.red = v; gotRed = true }
            else if (k === "green") { root.green = v; gotGreen = true }
            else if (k === "color0") color0 = v
            else if (k === "color1") color1 = v
            else if (k === "color2") color2 = v
            else if (k === "color4") color4 = v
            else if (k === "color7") color7 = v
            else if (k === "color8") color8 = v
        }
        // Fall back to the ANSI-style color0-15 palette for themes that only supply that
        // (same fallback Omarchy's own Color.qml uses).
        if (!gotBg && color0) root.background = color0
        if (!gotFg && color7) root.foreground = color7
        if (!gotAccent && color4) root.accent = color4
        if (!gotMuted) root.muted = color8 || root.foreground
        if (!gotRed && color1) root.red = color1
        if (!gotGreen && color2) root.green = color2
    }

    property FileView _colorsFile: FileView {
        path: root.currentThemePath + "/colors.toml"
        watchChanges: true // harmless to leave on — it just never seems to fire for this file
        printErrors: false
        onLoaded: root._load(text())
        onFileChanged: reload()
    }

    // Polling fallback for theme switches (see header comment) — 3s is imperceptible for
    // a rare, deliberate user action like changing themes.
    property Timer _pollTimer: Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: root._colorsFile.reload()
    }
}
