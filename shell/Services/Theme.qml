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

    // ---- "plugin" surface language, mirroring Omarchy's own shell (Commons/Style.qml,
    // Ui/PopupCard.qml) so our pages read as part of the same design system rather than a
    // bespoke app: sharp corners (this system's real Hyprland decoration:rounding is 0,
    // which Style.cornerRadius mirrors), a card surface that's the SAME background as the
    // page with a border for definition (not a lightened fill), and controls built from
    // subtle low-alpha foreground fills rather than solid color blocks — see Style.qml's
    // normal/selected fill-alpha tokens.
    readonly property int cornerRadius: 0
    readonly property int borderWidth: 1
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    // Kept for ToastOverlay/WaterAmountPicker, which still use it — not touched by the
    // omarchy-design pass below (out of scope for the Personal Care / Dashboard restyle).
    readonly property color surfaceBorder: muted

    // ---- omarchy-design pass: verified against /usr/share/omarchy/shell source
    // (see .claude/skills/omarchy-design/reference/omarchy-conventions.md). Real Omarchy
    // panels use alpha-blended `foreground` for BOTH separators and control borders, but
    // at two different strengths — not one flat opaque color for everything. (An earlier
    // attempt used a single flat `muted` border after alpha=0.4 read as "brownish" on
    // Everforest — the actual fix, per verified source, is a much lower alpha for plain
    // separators, not abandoning alpha-blending altogether.)
    readonly property color separatorColor: withAlpha(foreground, 0.12)     // Ui/PanelSeparator.qml
    readonly property color controlBorderColor: withAlpha(foreground, 0.4) // Style.normalBorderAlpha
    // Secondary/status text idiom from Ui/PanelSectionHeader.qml + the Wi-Fi/bluetooth
    // panels' row status text: a DARKENED foreground, not the separate `muted` role.
    readonly property color secondaryForeground: Qt.darker(foreground, 1.4)

    readonly property color controlFill: withAlpha(foreground, 0.04)    // Style.normalFillAlpha
    readonly property color controlFillHover: withAlpha(foreground, 0.08) // Style.hoverFillAlpha
    readonly property color selectedFill: withAlpha(accent, 0.18)       // Style.selectedFillAlpha

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
