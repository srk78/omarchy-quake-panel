import QtQuick

// Conversation state for the PA ("Foxy") page — the QML-side domain object over
// PaBridge.qml's raw daemon connection, same relationship KnobLighting.qml/MicState.qml
// have to HidBridge.qml. Phases A-C done (push-to-talk, spoken replies, continuous
// "wake word" mode) — see HISTORY.md. `continuousMode` is now the ONE "is Foxy on"
// control (the on-screen Talk button and manual push-to-talk are gone — see HISTORY.md's
// FOXY redesign section): off shows nothing but a power button, on arms the wake-word
// listener and shows the conversation.
QtObject {
    id: root
    required property var paBridge

    // "idle" | "listening" | "transcribing" | "thinking" | "speaking"
    property string status: "idle"
    readonly property bool busy: root.status !== "idle"
    // Whether the daemon's wake-word listener is armed — read by Ui/PageHeader.qml's
    // pulsing dot (shown on every page, not just this one) via PageHost.qml, and by
    // Pages/PaPage.qml to pick the off/on layout.
    property bool continuousMode: false
    // 0..1, normalized — Foxy's own reply volume, streamed from paBridge.js while
    // status === "speaking". Read by Pages/PaPage.qml's Ui/FoxyVisualizer.qml.
    property real audioLevel: 0

    // The full conversation for this "Foxy on" session — a ListModel (not a plain JS
    // array) so Pages/PaPage.qml's ListView gets real incremental updates via append()
    // rather than reassigning the whole list on every line. Each entry is
    // {role: "user"|"foxy"|"error", body: "..."} — "body", not "text": a ListView
    // delegate that's itself a Text-derived item can't declare a `required property
    // string text` (Text already has its own built-in `text` property; the names
    // collide). Cleared on setContinuousMode(false) — going back to the off screen has
    // nothing to show anyway, so turning Foxy back on starts clean. This is a purely
    // visual reset; the daemon's own --resume session memory is untouched.
    property ListModel transcript: ListModel {}
    function _appendLine(role, body) {
        root.transcript.append({ role: role, body: body })
        if (root.transcript.count > 200) root.transcript.remove(0) // simple cap, not expected to matter in practice
    }

    property string lastError: ""

    function beginTurn() {
        if (root.busy) return
        root.lastError = ""
        root.paBridge.sendCommand({ cmd: "startTurn" })
    }
    function endTurn() {
        root.paBridge.sendCommand({ cmd: "endTurn" })
    }
    function cancelTurn() {
        root.paBridge.sendCommand({ cmd: "cancelTurn" })
    }
    function resetSession() {
        root.paBridge.sendCommand({ cmd: "resetSession" })
    }
    function setContinuousMode(on) {
        if (!on) {
            root.transcript.clear()
            root.lastError = "" // otherwise the header's "Error" meta outlives the transcript that explained it
        }
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
            // it started (knob, a wake word, or Foxy's own auto-follow-up after asking
            // a question) — clearing any stale error here, not just in beginTurn(),
            // means those turns also start with a clean slate instead of leaving a
            // transient error from moments ago (e.g. a one-off mic handoff race the
            // listener already recovered from on its own) sitting on screen looking
            // like a still-current problem.
            if (state.status === "listening") root.lastError = ""
            if (state.status) root.status = state.status
            if (state.continuous !== undefined) root.continuousMode = state.continuous
        }
        function onTranscript(text) { root._appendLine("user", text) }
        function onReply(text) { root._appendLine("foxy", text) }
        function onDaemonError(message) {
            root.lastError = message
            root._appendLine("error", message)
        }
        function onAudioLevel(value) { root.audioLevel = value }
    }
}
