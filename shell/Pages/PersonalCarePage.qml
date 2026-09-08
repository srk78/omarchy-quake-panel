import QtQuick
import "../Ui"

// Page 2 — pomodoro + water + stand, one combined block (a single card, the way Omarchy's
// multi-section popups stack several labeled sections inside one PopupCard). On this 4:1
// panel the three sections sit side by side, split by vertical separators, instead of
// stacked — same block, full width.
//
// Touch buttons are provided alongside the knob gestures (press = start/pause pomodoro on
// this page, hold = open the water-amount picker from any page). Ui/PanelButton registers
// itself with TouchRouter — see TouchRouter.qml for why plain TapHandler alone doesn't
// receive real touch input here.
// Work/break use theme.red/theme.green as a semantic (not decorative) signal.
Item {
    id: root
    required property var personalCareState
    required property var touchRouter
    required property var theme

    property real _now: Date.now()
    Timer { interval: 500; running: true; repeat: true; onTriggered: root._now = Date.now() }

    readonly property bool working: root.personalCareState.pomodoroPhase === "work"
    readonly property real pomodoroRemainingMs: Math.max(0, root.personalCareState.pomodoroPhaseEndsAt - root._now)

    // Surfaces in the page header's status caption (Ui/PageHost.qml).
    readonly property string heroMeta: root.personalCareState.pomodoroRunning
        ? (root.working ? "Work" : "Break") + " · " + root.fmtTime(root.pomodoroRemainingMs) + " left"
        : "Pomodoro paused"

    function fmtTime(ms) {
        var s = Math.floor(ms / 1000)
        var m = Math.floor(s / 60)
        var ss = s % 60
        return m + ":" + (ss < 10 ? "0" : "") + ss
    }
    // "3h 15m" — the elapsed time alone; callers add "ago"/"since ..." context.
    function fmtElapsed(ts) {
        if (!ts) return "never"
        var mins = Math.floor((root._now - ts) / 60000)
        if (mins < 1) return "just now"
        if (mins < 60) return mins + "m"
        return Math.floor(mins / 60) + "h " + (mins % 60) + "m"
    }
    function fmtAgo(ts) {
        var e = root.fmtElapsed(ts)
        return (e === "never" || e === "just now") ? e : e + " ago"
    }

    component HeroText: Text {
        textFormat: Text.PlainText
        color: root.theme.foreground
        font.family: root.theme.font.family
        font.pixelSize: root.theme.font.hero
        font.bold: true
    }
    component DetailText: Text {
        textFormat: Text.PlainText
        color: root.theme.secondaryForeground
        font.family: root.theme.font.family
        font.pixelSize: root.theme.font.subtitle
        width: parent.width
        elide: Text.ElideRight
    }

    // One section = a column of the card. Label + separator + hero content at the top,
    // the action button pinned to the bottom so all three columns share a baseline.
    component Section: Item {
        id: section
        property string icon: ""
        property string label: ""
        default property alias content: sectionBody.data
        property alias button: buttonLoader.sourceComponent
        height: parent.height

        Column {
            id: sectionBody
            width: parent.width
            spacing: root.theme.spacing.rowGap
            SectionLabel { theme: root.theme; icon: section.icon; text: section.label }
            SectionSeparator { theme: root.theme }
        }
        Loader {
            id: buttonLoader
            anchors.left: parent.left
            anchors.bottom: parent.bottom
        }
    }

    Card {
        theme: root.theme
        anchors.fill: parent

        Row {
            id: columns
            anchors.fill: parent
            anchors.margins: root.theme.space(16)
            spacing: root.theme.space(24)
            readonly property real columnWidth: (width - spacing * 4 - 2) / 3

            // ---- Pomodoro ----
            Section {
                icon: "󱎫"; label: "POMODORO"
                width: columns.columnWidth

                // Phase pill — PanelHero.qml's `detail` pill shape, colored semantically.
                Rectangle {
                    implicitWidth: phaseText.implicitWidth + root.theme.space(10)
                    implicitHeight: phaseText.implicitHeight + root.theme.space(4)
                    color: "transparent"
                    border.color: root.theme.withAlpha(root.working ? root.theme.red : root.theme.green, 0.4)
                    border.width: root.theme.borderWidth
                    radius: root.theme.cornerRadius
                    Text {
                        id: phaseText
                        anchors.centerIn: parent
                        text: root.working ? "WORK" : "BREAK"
                        textFormat: Text.PlainText
                        color: root.working ? root.theme.red : root.theme.green
                        font.family: root.theme.font.family
                        font.pixelSize: root.theme.font.caption
                        font.bold: true
                        font.letterSpacing: root.theme.font.heroCaptionSpacing
                    }
                }
                HeroText { text: root.personalCareState.pomodoroRunning ? root.fmtTime(root.pomodoroRemainingMs) : "Paused" }
                DetailText { text: "Completed today: " + root.personalCareState.todayPomodoroCount }

                button: PanelButton {
                    theme: root.theme
                    touchRouter: root.touchRouter
                    icon: root.personalCareState.pomodoroRunning ? "󰏤" : "󰐊"
                    text: root.personalCareState.pomodoroRunning ? "Pause" : "Start"
                    onActivated: root.personalCareState.togglePomodoro()
                }
            }

            SectionSeparator { theme: root.theme; vertical: true }

            // ---- Water ----
            Section {
                icon: "󰖌"; label: "WATER"
                width: columns.columnWidth

                HeroText { text: (root.personalCareState.todayWaterMl / 1000).toFixed(2) + " L" }
                DetailText { text: "today · " + root.personalCareState.todayWaterCount + " logged · last " + root.fmtAgo(root.personalCareState.lastDrinkAt) }

                button: PanelButton {
                    theme: root.theme
                    touchRouter: root.touchRouter
                    icon: "󰅶"
                    text: "Log water"
                    onActivated: root.personalCareState.requestWaterAmount()
                }
            }

            SectionSeparator { theme: root.theme; vertical: true }

            // ---- Stand ----
            Section {
                icon: "󰖃"; label: "STAND"
                width: columns.columnWidth

                HeroText { text: root.fmtElapsed(root.personalCareState.lastStandAt) }
                DetailText { text: "since last stand · reminds every " + Math.round(root.personalCareState.standIntervalMs / 60000) + " min" }
            }
        }
    }
}
