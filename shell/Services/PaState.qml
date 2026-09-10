import QtQuick

// Conversation state for the PA ("Foxy") page — the QML-side domain object over
// PaBridge.qml's raw daemon connection, same relationship KnobLighting.qml/MicState.qml
// have to HidBridge.qml. Phase A: manual push-to-talk only (no continuous/wake-word mode
// yet — see HISTORY.md's brainstorm for the full plan), text reply only (no TTS yet).
QtObject {
    id: root
    required property var paBridge

    // "idle" | "listening" | "transcribing" | "thinking"
    property string status: "idle"
    readonly property bool busy: root.status !== "idle"

    // Last exchange only, not a scrolling history — the panel's own screen is a short,
    // wide strip (see PaPage.qml), and each turn already carries its own memory via the
    // daemon's --resume session, so the UI doesn't need to replay past turns either.
    property string lastHeard: ""
    property string lastReply: ""
    property string lastError: ""

    function beginTurn() {
        if (root.busy) return
        root.lastError = ""
        root.paBridge.sendCommand({ cmd: "startTurn" })
    }
    function endTurn() {
        root.paBridge.sendCommand({ cmd: "endTurn" })
    }
    // The one gesture both the knob press (KnobRouter, on the PA page) and the on-screen
    // button use: press to start listening, press again to stop and send. Mirrors
    // Voxtype's own "toggle" push-to-talk mode rather than "hold" — a knob press is a
    // discrete action, not a continuous hold, and this app has no per-page hold gesture
    // to reuse (KnobRouter's only hold gesture is the global water-picker one).
    function togglePushToTalk() {
        if (root.status === "idle") root.beginTurn()
        else if (root.status === "listening") root.endTurn()
        // transcribing/thinking: ignore — already committed to this turn
    }
    function cancelTurn() {
        root.paBridge.sendCommand({ cmd: "cancelTurn" })
    }
    function resetSession() {
        root.paBridge.sendCommand({ cmd: "resetSession" })
    }

    // Bare Connections {} would fail here — see KnobLighting.qml's own comment on why
    // QtObject children need an explicit property name.
    property Connections _bridgeConn: Connections {
        target: root.paBridge
        function onStateEvent(state) { if (state && state.status) root.status = state.status }
        function onTranscript(text) { root.lastHeard = text }
        function onReply(text) { root.lastReply = text }
        function onDaemonError(message) { root.lastError = message }
    }
}
