import QtQuick
import "../Ui"

// Page 4 — PA ("Foxy"), the voice agent. Phases A-C of the design in HISTORY.md: manual
// push-to-talk (knob press or the on-screen Talk button toggles listening on/off — see
// Services/PaState.qml's togglePushToTalk()), one real tool (starting the Pomodoro,
// Services/PersonalCareState.qml's startPomodoro()), a spoken reply (Piper, driven
// entirely from daemon/src/paBridge.js — this page just shows the "speaking" status, it
// doesn't touch audio itself), and continuous "wake word" mode (Listen button below —
// says "Hey Jarvis", the interim stock phrase for "Hey Foxy", see HISTORY.md for why).
// The continuous-mode indicator itself lives in Ui/PageHeader.qml, not here — it needs
// to show on every page, not just this one, since continuous mode keeps listening no
// matter which page is on screen.
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
        if (root.paState.status === "speaking") return "Speaking…"
        if (root.paState.lastError !== "") return "Error"
        return "Ready"
    }

    readonly property string buttonIcon: root.paState.status === "listening" ? "󰓛" : "󰍬"
    readonly property string buttonText: {
        if (root.paState.status === "listening") return "Stop"
        if (root.paState.busy) return "…"
        return "Talk"
    }

    // maximumLineCount + elide caps how tall a reply can grow — Claude's replies have no
    // natural length limit, and without this a long one visually overlapped the
    // bottom-anchored button row (Section.qml's content Column sizes to fit its
    // children and has no idea where the button row sits — see HISTORY.md's Phase C
    // notes). Same fixed-vertical-budget lesson as every other page on this panel, just
    // the first one where the content itself is unbounded rather than a couple of known
    // short lines.
    component Line: Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: 4
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
            button2: PanelButton {
                theme: root.theme
                touchRouter: root.touchRouter
                icon: root.paState.continuousMode ? "󰋋" : "󰍭"
                text: root.paState.continuousMode ? "Listening for “Hey Jarvis”" : "Listen for wake word"
                onActivated: root.paState.toggleContinuousMode()
            }
        }
    }
}
