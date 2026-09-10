import QtQuick
import "../Ui"

// Page 4 — PA ("Foxy"), the voice agent. Phase A of the design in HISTORY.md: manual
// push-to-talk only (knob press or the on-screen button toggles listening on/off — see
// Services/PaState.qml's togglePushToTalk()), one real tool (starting the Pomodoro,
// Services/PersonalCareState.qml's startPomodoro()), and a text-only reply — no
// continuous "Hey Foxy" mode and no spoken reply yet, both later phases.
//
// Single full-width Section (not the personal-care/settings pattern of several side by
// side) — there's one thing on this page, a conversation, not several independent
// controls that each need their own column.
Item {
    id: root
    required property var paState
    required property var touchRouter
    required property var theme

    readonly property string heroMeta: {
        if (root.paState.status === "listening") return "Listening…"
        if (root.paState.status === "transcribing") return "Transcribing…"
        if (root.paState.status === "thinking") return "Thinking…"
        if (root.paState.lastError !== "") return "Error"
        return "Ready"
    }

    readonly property string buttonIcon: root.paState.status === "listening" ? "󰓛" : "󰍬"
    readonly property string buttonText: {
        if (root.paState.status === "listening") return "Stop"
        if (root.paState.busy) return "…"
        return "Talk"
    }

    component Line: Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        color: root.theme.foreground
        font.family: root.theme.font.family
        font.pixelSize: root.theme.font.subtitle
    }

    Card {
        theme: root.theme
        anchors.fill: parent

        Section {
            theme: root.theme
            icon: "󰊠"; label: "FOXY"
            anchors.fill: parent
            anchors.margins: root.theme.space(16)

            Column {
                width: parent.width
                spacing: root.theme.spacing.rowGap

                Line {
                    visible: root.paState.lastHeard !== ""
                    text: "You: " + root.paState.lastHeard
                    color: root.theme.secondaryForeground
                }
                Line {
                    visible: root.paState.lastReply !== ""
                    text: "Foxy: " + root.paState.lastReply
                    font.bold: true
                }
                Line {
                    visible: root.paState.lastError !== ""
                    text: root.paState.lastError
                    color: root.theme.secondaryForeground
                }
                Line {
                    visible: root.paState.lastHeard === "" && root.paState.lastReply === "" && root.paState.lastError === ""
                    text: "Press Talk and ask for something — try “start the pomodoro”."
                    color: root.theme.secondaryForeground
                }
            }

            button: PanelButton {
                theme: root.theme
                touchRouter: root.touchRouter
                icon: root.buttonIcon
                text: root.buttonText
                onActivated: root.paState.togglePushToTalk()
            }
        }
    }
}
