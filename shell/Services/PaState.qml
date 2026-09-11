import QtQuick

// Conversation state for the PA ("Foxy") page — the QML-side domain object over
// PaBridge.qml's raw daemon connection, same relationship KnobLighting.qml/MicState.qml
// have to HidBridge.qml. Phases A-C done (push-to-talk, spoken replies, continuous
// "wake word" mode) — see HISTORY.md.
QtObject {
    id: root
    required property var paBridge

    // "idle" | "listening" | "transcribing" | "thinking" | "speaking"
    property string status: "idle"
    readonly property bool busy: root.status !== "idle"
    // Whether the daemon's wake-word listener is armed — read by Ui/PageHeader.qml's
    // pulsing dot (shown on every page, not just this one) via PageHost.qml.
    property bool continuousMode: false
    // 0..1, normalized — Foxy's own reply volume, streamed from paBridge.js while
    // status === "speaking". Read by Pages/PaPage.qml's Ui/FoxyVisualizer.qml.
    property real audioLevel: 0

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
    function setContinuousMode(on) {
        root.paBridge.sendCommand({ cmd: on ? "startContinuous" : "stopContinuous" })
    }
    function toggleContinuousMode() { root.setContinuousMode(!root.continuousMode) }

    // Bare Connections {} would fail here — see KnobLighting.qml's own comment on why
    // QtObject children need an explicit property name.
    property Connections _bridgeConn: Connections {
        target: root.paBridge
        function onStateEvent(state) {
            if (!state) return
            // A fresh "listening" is the one status every turn passes through, however
            // it started (button, knob, or a wake word) — clearing any stale error here,
            // not just in beginTurn(), means a wake-triggered turn also starts with a
            // clean slate instead of leaving a transient error from moments ago (e.g. a
            // one-off mic handoff race the listener already recovered from on its own)
            // sitting on screen looking like a still-current problem.
            if (state.status === "listening") root.lastError = ""
            if (state.status) root.status = state.status
            if (state.continuous !== undefined) root.continuousMode = state.continuous
        }
        function onTranscript(text) { root.lastHeard = text }
        function onReply(text) { root.lastReply = text }
        function onDaemonError(message) { root.lastError = message }
        function onAudioLevel(value) { root.audioLevel = value }
    }
}
