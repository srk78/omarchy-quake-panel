import QtQuick

// Owns the panel's built-in microphone on/off state (daemon commands setMic/queryMic —
// Aris68Connector.js's cmd3, "1=mic on, 0=off"). The mic is now gated entirely by
// Foxy's own on/off state (Service.qml/shell.qml call setOn() directly on every
// connect and continuousMode change — see HISTORY.md's FOXY redesign), not by a
// separate manual Settings-page toggle, so nothing here needs to read the mic's
// leftover state back at boot.
//
// Deliberately does NOT auto-query the device on connect anymore (it used to,
// mirroring KnobLighting.qml's getLighting) — confirmed live that this raced Foxy's
// own authoritative setOn() call at boot: both fire off hidBridge's connected signal,
// but the query's reply is async and could arrive after setOn() already ran, silently
// overwriting the correctly-commanded value with whatever stale state the hardware had
// from a previous session. Since nothing reads `on`/`loaded` for display anymore, the
// query served no purpose but to create that race — removed at the root rather than
// papered over with a timing guess. `refresh()`/`on`/`loaded` stay defined for any
// future caller that genuinely needs a real read-back (e.g. a future debug hook), just
// not wired to fire automatically.
QtObject {
    id: root
    required property var hidBridge

    // True once a real queryMic() reply (or an unprompted state push) has set `on`
    // below, or once setOn() has been called at least once.
    property bool loaded: false
    property bool on: false

    function setOn(value) {
        root.on = value
        root.loaded = true
        root.hidBridge.sendCommand({ cmd: "setMic", on: value })
    }
    function toggle() { root.setOn(!root.on) }
    function refresh() { root.hidBridge.sendCommand({ cmd: "queryMic" }) }

    // Bare Connections {} would fail here — see KnobLighting.qml's own comment on why
    // QtObject children need an explicit property name.
    property Connections _stateConn: Connections {
        target: root.hidBridge
        function onStateEvent(state) {
            if (!state || state.mic === undefined) return
            root.on = state.mic
            root.loaded = true
        }
    }
}
