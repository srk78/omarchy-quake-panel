import QtQuick
import "../Ui"

// Page 4 — FOXY, the voice agent. Phases A-C of the design in HISTORY.md: local
// speech-to-text (Voxtype), one real tool (starting the Pomodoro,
// Services/PersonalCareState.qml's startPomodoro()), a spoken reply (Piper, driven
// entirely from daemon/src/paBridge.js — this page just shows the "speaking" status, it
// doesn't touch audio itself), and continuous "wake word" mode.
//
// Redesigned (see HISTORY.md's FOXY redesign section): there is now exactly ONE
// on/off control — Services/PaState.qml's continuousMode — not a separate manual
// push-to-talk button plus a continuous-mode toggle. Off shows nothing but a single
// power button (no header, no conversation, no visualizer — matching the request that
// the off page get out of the way entirely); on shows the full conversation + 3D cloud,
// with a single deactivate button in place of the old button pair. The continuous-mode
// indicator dot itself still lives in Ui/PageHeader.qml, not here — it needs to show on
// every page, not just this one, since continuous mode keeps listening no matter which
// page is on screen.
//
// A Row split, 4/5 conversation + 1/5 a 3D particle-cloud visualizer
// (Ui/FoxyVisualizer.qml) — same computed-width-column pattern Pages/SettingsPage.qml
// already uses for its own three-way split. The visualizer needs `qt6-quick3d`
// installed (see FoxyVisualizer.qml's own header comment and HISTORY.md for why a real
// 3D module, not a browser or a flat 2D approximation).
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

    // maximumLineCount + elide caps the idle placeholder line only — the real
    // transcript (below) scrolls instead of truncating, since a ListView with a real
    // viewport can just show more of a long conversation rather than cutting it off.
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

        // Off: nothing but a single power button, centered — no header, no
        // conversation, no visualizer. TouchRouter's own hit-testing already skips
        // !visible targets (Services/TouchRouter.qml's _hitTestIn), so toggling
        // `visible` between this and the "on" branch below is enough on its own.
        Item {
            anchors.fill: parent
            visible: !root.paState.continuousMode

            PanelButton {
                anchors.centerIn: parent
                theme: root.theme
                touchRouter: root.touchRouter
                icon: "󰋋"
                text: "Turn Foxy on"
                onActivated: root.paState.toggleContinuousMode()
            }
        }

        Row {
            id: pageRow
            anchors.fill: parent
            anchors.margins: root.theme.space(16)
            spacing: root.theme.space(16)
            visible: root.paState.continuousMode
            readonly property real visualizerWidth: (width - spacing) * 0.2
            readonly property real conversationWidth: width - spacing - visualizerWidth

            // Content-descriptive label, not a repeat of the page title/icon —
            // matching every other page's own section convention (Personal Care's
            // POMODORO/WATER/STAND, Settings' KNOB COLOR/etc. never just repeat "Self
            // Care"/"Settings" either). FOXY + the fox icon already live in the shared
            // page header (Ui/PageHeader.qml) — showing them a second time here was
            // redundant.
            Section {
                theme: root.theme
                icon: "󰍩"; label: "CONVERSATION"
                width: pageRow.conversationWidth

                ListView {
                    width: parent.width
                    height: parent.height
                    clip: true
                    // Real touch never reaches native flick gestures on this
                    // layer-shell surface anyway (Services/TouchRouter.qml's own
                    // header comment on Hyprland's touch-delivery bug) — scrolling
                    // here is automatic-only (onCountChanged below), never a manual
                    // drag, so disabling interactive flicking isn't a lost feature.
                    interactive: false
                    model: root.paState.transcript
                    delegate: Line {
                        required property string role
                        required property string body
                        text: (role === "user" ? "You: " : role === "foxy" ? "Foxy: " : "") + body
                        font.bold: role === "foxy"
                        color: role === "user" || role === "error" ? root.theme.secondaryForeground : root.theme.foreground
                        maximumLineCount: 9999 // no truncation — real scrolling handles overflow now
                    }
                    Line {
                        // Not anchors.fill — Line already binds width: parent.width
                        // itself (see its own definition above); fighting that with a
                        // second, anchors-driven width binding is the kind of subtle
                        // conflict worth just not creating. Parented directly to the
                        // ListView (its default property), so it sits at (0,0) as a
                        // plain sibling of the delegate-managed content — the standard
                        // "empty state placeholder inside a ListView" idiom.
                        visible: root.paState.transcript.count === 0
                        text: "Say “Hey Foxy” and ask for something — try “start the pomodoro”."
                        color: root.theme.secondaryForeground
                    }
                    onCountChanged: Qt.callLater(positionViewAtEnd)
                }

                button: PanelButton {
                    theme: root.theme
                    touchRouter: root.touchRouter
                    icon: "󰍭"
                    text: "Turn Foxy off"
                    onActivated: root.paState.toggleContinuousMode()
                }
            }

            FoxyVisualizer {
                theme: root.theme
                width: pageRow.visualizerWidth
                height: pageRow.height
                audioLevel: root.paState.audioLevel
                status: root.paState.status
            }
        }
    }
}
