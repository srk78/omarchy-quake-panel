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
// receive real touch input here. All three sections also get a Reset button
// (PersonalCareState.resetPomodoro()/resetWater()/resetStand()) — a second PanelButton in
// the same row as the primary action, via Section's `button`/`button2` slots.
Item {
    id: root
    required property var personalCareState
    required property var touchRouter
    required property var theme

    property real _now: Date.now()
    Timer { interval: 500; running: true; repeat: true; onTriggered: root._now = Date.now() }

    readonly property bool working: root.personalCareState.pomodoroPhase === "work"
    readonly property real pomodoroRemainingMs: Math.max(0, root.personalCareState.pomodoroPhaseEndsAt - root._now)
    // pomodoroRunning === false covers two different situations: paused mid-session
    // (resume continues from pausedRemainingMs) and fresh/just-reset (nothing to resume,
    // pausedRemainingMs === 0). Only the former should read as "Paused" — the latter
    // shows the phase's full duration instead, so Reset doesn't masquerade as a pause.
    readonly property bool pausedMidSession: !root.personalCareState.pomodoroRunning && root.personalCareState.pausedRemainingMs > 0
    readonly property real pomodoroPhaseDefaultMs: root.working ? root.personalCareState.pomodoroWorkMs : root.personalCareState.pomodoroBreakMs

    // Surfaces in the page header's status caption (Ui/PageHost.qml).
    readonly property string heroMeta: root.personalCareState.pomodoroRunning
        ? (root.working ? "Work" : "Break") + " · " + root.fmtTime(root.pomodoroRemainingMs) + " left"
        : (root.pausedMidSession ? "Pomodoro paused" : "Pomodoro ready")

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
                theme: root.theme
                icon: "󱎫"; label: "POMODORO"
                width: columns.columnWidth

                HeroText {
                    text: root.personalCareState.pomodoroRunning ? root.fmtTime(root.pomodoroRemainingMs)
                        : root.pausedMidSession ? "Paused"
                        : root.fmtTime(root.pomodoroPhaseDefaultMs)
                }
                DetailText { text: "Completed today: " + root.personalCareState.todayPomodoroCount }

                button: PanelButton {
                    theme: root.theme
                    touchRouter: root.touchRouter
                    icon: root.personalCareState.pomodoroRunning ? "󰏤" : "󰐊"
                    text: root.personalCareState.pomodoroRunning ? "Pause" : "Start"
                    onActivated: root.personalCareState.togglePomodoro()
                }
                button2: PanelButton {
                    theme: root.theme
                    touchRouter: root.touchRouter
                    icon: "󰜉"
                    text: "Reset"
                    onActivated: root.personalCareState.resetPomodoro()
                }
            }

            SectionSeparator { theme: root.theme; vertical: true }

            // ---- Water ----
            Section {
                theme: root.theme
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
                button2: PanelButton {
                    theme: root.theme
                    touchRouter: root.touchRouter
                    icon: "󰜉"
                    text: "Reset"
                    onActivated: root.personalCareState.resetWater()
                }
            }

            SectionSeparator { theme: root.theme; vertical: true }

            // ---- Stand ----
            Section {
                theme: root.theme
                icon: "󰖃"; label: "STAND"
                width: columns.columnWidth

                HeroText { text: root.fmtElapsed(root.personalCareState.lastStandAt) }
                DetailText { text: "since last stand · reminds every " + Math.round(root.personalCareState.standIntervalMs / 60000) + " min" }

                button: PanelButton {
                    theme: root.theme
                    touchRouter: root.touchRouter
                    icon: "󰜉"
                    text: "Reset"
                    onActivated: root.personalCareState.resetStand()
                }
            }
        }
    }
}
