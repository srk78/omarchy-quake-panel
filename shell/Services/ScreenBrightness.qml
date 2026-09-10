import QtQuick

// Owns the panel's own screen backlight brightness — a DIFFERENT control than the
// knob's RGB ring (Services/KnobLighting.qml): Aris68Connector.js's "legacy 0xA3 path"
// (setBrightness/queryLuminance, cmd 0x05), not the VIA RGB-Matrix channel the ring uses.
// No save/persist command exists for this one in the driver (unlike the ring's
// saveLighting()), so it likely doesn't survive a power cycle — see NEXT_STEPS.md.
//
// Same query-on-connect pattern as KnobLighting/MicState: the device is the source of
// truth, queried once at daemon connect rather than guessed.
QtObject {
    id: root
    required property var hidBridge

    readonly property int valueMin: 0
    readonly property int valueMax: 255

    property bool loaded: false
    property int value: 128

    // Called on every Ui/Slider "settled" tick while dragging — no flash-persist step
    // exists for this control (see header comment), so unlike
    // KnobLighting.previewBrightness() there's nothing to debounce beyond what the
    // slider itself already throttles.
    function setValue(v) {
        root.value = v
        root.loaded = true
        root.hidBridge.sendCommand({ cmd: "setBrightness", value: v })
    }

    function refresh() {
        root.hidBridge.sendCommand({ cmd: "queryLuminance" })
    }

    // Bare Connections {} would fail here — see KnobLighting.qml's own comment on why
    // QtObject children need an explicit property name.
    property Connections _stateConn: Connections {
        target: root.hidBridge
        function onStateEvent(state) {
            if (!state || state.luminance === undefined) return
            root.value = state.luminance
            root.loaded = true
        }
    }
    property Connections _connectedConn: Connections {
        target: root.hidBridge
        function onConnected(iface) { if (iface === "control") root.refresh() }
    }
}
