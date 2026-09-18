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
                id: conversationSection
                theme: root.theme
                icon: "󰍩"; label: "CONVERSATION"
                width: pageRow.conversationWidth

                ListView {
                    id: transcriptView
                    width: parent.width
                    height: parent.height
                    clip: true
                    // Real touch never reaches native flick gestures on this layer-shell
                    // surface anyway (Services/TouchRouter.qml's own header comment on
                    // Hyprland's touch-delivery bug), so native Flickable dragging was
                    // never going to work regardless of this flag — scrolling is driven
                    // by hand below, the same way Ui/Slider.qml drives its own value by
                    // hand rather than through a native drag handle.
                    interactive: false
                    model: root.paState.transcript

                    // Whether the view is currently at (or very near) its true bottom —
                    // everything that auto-scrolls below checks this first, so a manual
                    // scroll-back to reread something is never fought. Only the user's
                    // own drag (or the transcript emptying out on Foxy off) changes it
                    // back; new content while scrolled away just accumulates, visible
                    // once they scroll back down themselves.
                    property bool pinnedToBottom: true
                    readonly property real _maxContentY: Math.max(0, contentHeight - height)
                    function _updatePinned() {
                        pinnedToBottom = contentY >= _maxContentY - root.theme.space(4)
                    }
                    function _scrollToBottomInstant() {
                        if (!pinnedToBottom) return
                        Qt.callLater(positionViewAtEnd)
                    }
                    function _lastRole() {
                        var c = root.paState.transcript.count
                        return c === 0 ? "" : root.paState.transcript.get(c - 1).role
                    }

                    // Touch-drag scroll-back — the same TouchRouter.registerDrag(item,
                    // onStart, onMove) pattern Ui/Slider.qml already uses for continuous
                    // dragging (see its own header comment for why this exists at all:
                    // a confirmed Hyprland bug means real touch never reaches a native
                    // gesture recognizer on this window). Global (x, y) in; only the
                    // vertical delta since the last point matters here. A drag starting
                    // mid-animation takes over immediately rather than fighting it.
                    property real _dragLastY: 0
                    Component.onCompleted: root.touchRouter.registerDrag(transcriptView,
                        function (x, y) {
                            pacedScroll.stop()
                            transcriptView._dragLastY = y
                        },
                        function (x, y) {
                            var dy = y - transcriptView._dragLastY
                            transcriptView._dragLastY = y
                            transcriptView.contentY = Math.max(0, Math.min(transcriptView._maxContentY, transcriptView.contentY - dy))
                            transcriptView._updatePinned()
                        })
                    Component.onDestruction: root.touchRouter.unregisterDrag(transcriptView)

                    delegate: Column {
                        required property string role
                        required property string body
                        required property real durationMs
                        width: ListView.view.width
                        Line {
                            text: (role === "user" ? "You: " : role === "foxy" ? "Foxy: " : "") + body
                            font.bold: role === "foxy"
                            color: role === "user" || role === "error" ? root.theme.secondaryForeground : root.theme.foreground
                            maximumLineCount: 9999 // no truncation — real scrolling handles overflow now
                        }
                        // How long Foxy's brain took to answer — thinking time only
                        // (daemon/src/paBridge.js's thinkingStartedAt), not how long the
                        // user spoke or how long Piper takes to speak the reply.
                        Text {
                            visible: role === "foxy" && durationMs > 0
                            textFormat: Text.PlainText
                            text: (durationMs / 1000).toFixed(1) + "s"
                            color: root.theme.secondaryForeground
                            font.family: root.theme.font.family
                            font.pixelSize: root.theme.font.caption
                        }
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

                    // A Foxy reply no longer jumps to the bottom the instant its (whole,
                    // un-streamed) text is appended — see speakingStartedConn below,
                    // which paces the reveal to actual speaking time instead. Every
                    // other line (the user's own, an error) keeps the plain instant
                    // scroll, still gated on pinnedToBottom via _scrollToBottomInstant.
                    // Two triggers on the plain path, not one: onCountChanged fires the
                    // moment a line is appended, but a wrapped multi-line reply's own
                    // height resolves asynchronously (Text.wrapMode's implicit-height
                    // pass) — contentHeightChanged catches that settling a frame later.
                    onCountChanged: {
                        if (root.paState.transcript.count === 0) { pinnedToBottom = true; return }
                        if (_lastRole() === "foxy") { foxyScrollFallback.restart(); return }
                        _scrollToBottomInstant()
                    }
                    onContentHeightChanged: {
                        // A foxy reply's growing height deliberately does NOT recompute
                        // pinnedToBottom here — it's still waiting on speakingStartedConn
                        // to run the paced scroll below, and content having grown ahead
                        // of that (contentY hasn't moved yet, on purpose) would otherwise
                        // look exactly like "the user scrolled away," incorrectly
                        // cancelling the very animation this height change is set up for.
                        if (_lastRole() === "foxy") return
                        _scrollToBottomInstant()
                        // Deferred so it judges the position AFTER the scroll just
                        // triggered above has actually run (Qt.callLater callbacks run
                        // in the order queued), not a stale pre-scroll snapshot.
                        Qt.callLater(_updatePinned)
                    }

                    // Safety net: if Foxy's own reply text was appended but real
                    // playback never actually starts (a Piper/paplay failure), the
                    // reply would otherwise stay stuck out of view forever with nothing
                    // left to trigger a scroll. Armed above the moment a foxy line
                    // lands; disarmed by speakingStartedConn the moment real playback
                    // (and the paced scroll) actually begins. 30s, not a few — confirmed
                    // live that Piper synthesizing a long reply (a minute-plus of actual
                    // speech) can itself take longer than a short timeout here, which
                    // fired this "failure" fallback during perfectly normal synthesis
                    // and jumped to the bottom before speakingStartedConn ever got a
                    // chance to pace anything.
                    Timer { id: foxyScrollFallback; interval: 30000; onTriggered: transcriptView._scrollToBottomInstant() }

                    NumberAnimation {
                        id: pacedScroll
                        target: transcriptView
                        property: "contentY"
                        easing.type: Easing.Linear
                        // Final safety snap once paced playback ends — cheap and
                        // idempotent, guards against contentHeight drifting a little
                        // after the animation's target was first computed.
                        onStopped: transcriptView._scrollToBottomInstant()
                    }
                    Connections {
                        id: speakingStartedConn
                        target: root.paState
                        function onSpeakingStarted(durationMs) {
                            foxyScrollFallback.stop()
                            if (!transcriptView.pinnedToBottom) return
                            pacedScroll.stop()
                            pacedScroll.to = transcriptView._maxContentY
                            pacedScroll.duration = Math.max(1, durationMs)
                            pacedScroll.start()
                        }
                    }
                }
            }

            // Wrapped together (rather than anchored as a loose sibling in pageRow) so
            // the off icon can sit at THIS block's own top-right corner, not the
            // conversation block's — FoxyVisualizer itself stays untouched, a focused
            // rendering component with no chrome of its own.
            Item {
                width: pageRow.visualizerWidth
                height: pageRow.height

                FoxyVisualizer {
                    anchors.fill: parent
                    theme: root.theme
                    audioLevel: root.paState.audioLevel
                    status: root.paState.status
                }

                PanelButton {
                    theme: root.theme
                    touchRouter: root.touchRouter
                    icon: "󰍭"
                    anchors.top: parent.top
                    anchors.right: parent.right
                    onActivated: root.paState.toggleContinuousMode()
                }
            }
        }
    }
}
