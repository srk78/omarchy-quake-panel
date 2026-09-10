import QtQuick

// Owns the panel's built-in microphone on/off state (daemon commands setMic/queryMic —
// Aris68Connector.js's cmd3, "1=mic on, 0=off"). The device is the source of truth,
// queried once at daemon connect, same pattern as KnobLighting.qml's getLighting.
QtObject {
    id: root
    required property var hidBridge

    // True once a real queryMic() reply (or an unprompted state push) has set `on`
    // below — until then, the Settings page can't know the mic's actual state.
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
    property Connections _connectedConn: Connections {
        target: root.hidBridge
        function onConnected(iface) { if (iface === "control") root.refresh() }
    }
}
