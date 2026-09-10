import QtQuick
import Quickshell.Io
import "../Pages"

// Page chrome shared by every page — the hero header (glyph, title, status caption, clock,
// page indicator) — plus the Loader that swaps the active page below it, driven by
// KnobRouter.currentPageIndex. HomeAssistantPage is not wired in yet — see
// KnobRouter.qml's header comment.
Item {
    id: root
    required property var knobRouter
    required property var systemStats
    required property var personalCareState
    required property var knobLighting
    required property var micState
    required property var screenBrightness
    required property var hidBridge
    required property var paState
    required property var touchRouter
    required property var theme

    // Glyphs are Nerd Font (Material Design set) codepoints, rendered through the same
    // fontconfig alias Omarchy uses — see Services/Theme.qml. FOXY is the one
    // exception: no Nerd Font set (checked directly in the font's own glyph names) has
    // a generic fox icon, only the trademarked Firefox browser logo — so this is a
    // genuine Unicode emoji (🦊, U+1F98A) instead, which Qt's own font-fallback renders
    // in full color via Noto Color Emoji (already installed) despite the surrounding
    // theme font being a plain monospace with no color-emoji glyphs of its own —
    // confirmed live, no special handling needed beyond just using the character.
    readonly property var pages: [
        { icon: "󰓅", title: "System" },
        { icon: "󰗶", title: "Self Care" },
        { icon: "󰒓", title: "Settings" },
        { icon: "🦊", title: "FOXY" },
    ]
    readonly property var pageNames: root.pages.map(function (p) { return p.title })
    readonly property int pageIndex: Math.max(0, Math.min(root.pages.length - 1, root.knobRouter.currentPageIndex))

    // The System page's caption is the machine name — cheap to read here, and it keeps
    // SystemStats untouched.
    property string hostname: ""
    FileView {
        path: "/etc/hostname"
        printErrors: false
        onLoaded: root.hostname = String(text() || "").trim()
    }

    PageHeader {
        id: header
        theme: root.theme
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.theme.spacing.panelPadding
        anchors.bottomMargin: 0
        icon: root.pages[root.pageIndex].icon
        title: root.pages[root.pageIndex].title
        meta: root.pageIndex === 0 ? root.hostname
            : (pageLoader.item && pageLoader.item.heroMeta !== undefined ? pageLoader.item.heroMeta : "")
        clock: root.systemStats.clockText
        pageNames: root.pageNames
        pageIndex: root.pageIndex
        continuousListening: root.paState.continuousMode
    }

    Loader {
        id: pageLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.margins: root.theme.spacing.panelPadding
        anchors.topMargin: root.theme.space(12)
        sourceComponent: {
            switch (root.knobRouter.currentPageIndex) {
                case 0: return dashboardComp
                case 1: return careComp
                case 2: return settingsComp
                case 3: return paComp
                default: return dashboardComp
            }
        }
    }

    Component { id: dashboardComp; DashboardPage { systemStats: root.systemStats; theme: root.theme } }
    Component { id: careComp; PersonalCarePage { personalCareState: root.personalCareState; touchRouter: root.touchRouter; theme: root.theme } }
    Component { id: settingsComp; SettingsPage { knobLighting: root.knobLighting; micState: root.micState; screenBrightness: root.screenBrightness; touchRouter: root.touchRouter; theme: root.theme } }
    Component { id: paComp; PaPage { paState: root.paState; touchRouter: root.touchRouter; theme: root.theme } }
}
