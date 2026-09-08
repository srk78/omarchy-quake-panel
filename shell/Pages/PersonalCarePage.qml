import QtQuick

// Page 3 — pomodoro + water + stand, combined into a single 1/3-width block (all three
// functions stacked top-to-bottom inside one card, rather than three separate cards).
// Touch buttons are provided alongside the knob gestures (press = start/pause pomodoro on
// this page, hold = open the water-amount picker from any page). Buttons register with
// TouchRouter, not just TapHandler — see TouchRouter.qml for why plain TapHandler alone
// doesn't receive real touch input here.
//
// Styled to match Omarchy's own shell chrome (see Services/Theme.qml's header comment):
// sharp corners, a card surface that's the page background plus a border rather than a
// lightened fill, controls built from subtle low-alpha fills rather than solid color
// blocks, and bold darkened-foreground section labels (no letter-spacing — not present in
// the verified Ui/PanelSectionHeader.qml source) with a thin separator beneath — the same
// hero-label-then-separator texture as Omarchy's own plugin panels (e.g. the bluetooth
// panel's "CONNECTED" header + PanelSeparator, which also stacks multiple labeled sections
// inside one card).
// Work/break use theme.red/theme.green as a semantic (not decorative) signal.
Rectangle {
    id: root
    required property var personalCareState
    required property var touchRouter
    required property var theme
    color: root.theme.background

    property real _now: Date.now()
    Timer { interval: 500; running: true; repeat: true; onTriggered: root._now = Date.now() }

    readonly property real pomodoroRemainingMs: Math.max(0, root.personalCareState.pomodoroPhaseEndsAt - root._now)

    function fmtTime(ms) {
        var s = Math.floor(ms / 1000)
        var m = Math.floor(s / 60)
        var ss = s % 60
        return m + ":" + (ss < 10 ? "0" : "") + ss
    }
    function fmtAgo(ts) {
        if (!ts) return "never"
        var mins = Math.floor((root._now - ts) / 60000)
        if (mins < 1) return "just now"
        if (mins < 60) return mins + "m ago"
        return Math.floor(mins / 60) + "h " + (mins % 60) + "m ago"
    }

    component Card: Rectangle {
        color: root.theme.background
        border.color: root.theme.controlBorderColor
        border.width: root.theme.borderWidth
        radius: root.theme.cornerRadius
    }

    // Matches Ui/PanelSectionHeader.qml exactly: darkened foreground, bold, caption
    // size — no letter-spacing.
    component SectionLabel: Text {
        color: root.theme.secondaryForeground
        font.pixelSize: 12
        font.bold: true
    }

    component SectionSeparator: Rectangle {
        width: parent.width
        height: 1
        color: root.theme.separatorColor
    }

    component PluginButton: Rectangle {
        id: btn
        property alias label: btnText.text
        signal activated()
        color: tapHandler.pressed ? root.theme.controlFillHover : root.theme.controlFill
        border.color: root.theme.controlBorderColor
        border.width: root.theme.borderWidth
        radius: root.theme.cornerRadius
        width: 160; height: 44
        Text { id: btnText; anchors.centerIn: parent; color: root.theme.foreground; font.pixelSize: 14 }
        TapHandler { id: tapHandler; onTapped: btn.activated() } // mouse; see TouchRouter.qml for touch
    }

    // Single block, 1/3 of the page width (same width one of the original three cards
    // had) — full page height, all three functions stacked inside.
    Card {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 18
        width: (parent.width - 36) / 3

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            // Card-level title (distinct from the section labels below) — mirrors
            // Omarchy's own hero-title-then-sections popups (e.g. bluetooth's "Bluetooth"
            // heading above its "CONNECTED" section label).
            Text { text: "Self Care"; color: root.theme.foreground; font.pixelSize: 17; font.bold: true }
            SectionSeparator {}

            // ---- Pomodoro ----
            SectionLabel { text: "POMODORO" }
            SectionSeparator {}
            Text {
                text: (root.personalCareState.pomodoroPhase === "work" ? "Work" : "Break").toUpperCase()
                color: root.personalCareState.pomodoroPhase === "work" ? root.theme.red : root.theme.green
                font.pixelSize: 12; font.bold: true
            }
            Text {
                text: root.personalCareState.pomodoroRunning ? root.fmtTime(root.pomodoroRemainingMs) : "Paused"
                color: root.theme.foreground; font.pixelSize: 26; font.bold: true
            }
            Text { text: "Completed today: " + root.personalCareState.todayPomodoroCount; color: root.theme.secondaryForeground; font.pixelSize: 13 }
            PluginButton {
                id: pomodoroButton
                label: root.personalCareState.pomodoroRunning ? "Pause" : "Start"
                onActivated: root.personalCareState.togglePomodoro()
                Component.onCompleted: root.touchRouter.registerTap(pomodoroButton, function () { root.personalCareState.togglePomodoro() })
                Component.onDestruction: root.touchRouter.unregisterTap(pomodoroButton)
            }

            // ---- Water ----
            SectionLabel { text: "WATER" }
            SectionSeparator {}
            Text {
                text: (root.personalCareState.todayWaterMl / 1000).toFixed(2) + " L today"
                color: root.theme.foreground; font.pixelSize: 20; font.bold: true
            }
            Text { text: root.personalCareState.todayWaterCount + " logged · last: " + root.fmtAgo(root.personalCareState.lastDrinkAt); color: root.theme.secondaryForeground; font.pixelSize: 13 }
            PluginButton {
                id: waterButton
                label: "Log water"
                onActivated: root.personalCareState.requestWaterAmount()
                Component.onCompleted: root.touchRouter.registerTap(waterButton, function () { root.personalCareState.requestWaterAmount() })
                Component.onDestruction: root.touchRouter.unregisterTap(waterButton)
            }

            // ---- Stand ----
            SectionLabel { text: "STAND" }
            SectionSeparator {}
            Text { text: root.fmtAgo(root.personalCareState.lastStandAt); color: root.theme.foreground; font.pixelSize: 18; font.bold: true }
            Text {
                text: "Reminds every " + Math.round(root.personalCareState.standIntervalMs / 60000) + " min"
                color: root.theme.secondaryForeground; font.pixelSize: 13
            }
        }
    }
}
